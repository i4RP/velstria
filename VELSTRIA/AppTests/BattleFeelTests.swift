import simd
import UIKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 戦闘の手応え（BattleFeel・画面の脈・カメラの押し込み）。描画だけで sim を変えないこと、格・間隔・上限、自分が関わる時だけ。
@MainActor
final class BattleFeelTests: XCTestCase {
    /// 格: 倒した一撃・自分の奥義 90 ms、受けた奥義 70、自分の S1/S2 55、受けた S1/S2・自分の会心 40。英雄・人形以外、自分が関わらない命中は止めない。
    func testHoldTiers() {
        func h(_ s: DamageSource, crit: Bool = false, byMe: Bool = true, onMe: Bool = false, hero: Bool = true,
               killed: Bool = false) -> Double? {
            BattleFeel.holdSeconds(source: s, isCrit: crit, byMe: byMe, onMe: onMe, targetIsHero: hero, killed: killed)
        }
        XCTAssertEqual(h(.skill(.ultimate)), 0.09)
        XCTAssertEqual(h(.skill(.ultimate), byMe: false, onMe: true), 0.07)
        XCTAssertEqual(h(.skill(.skill1)), 0.055)
        XCTAssertEqual(h(.skill(.skill2), byMe: false, onMe: true), 0.04)
        XCTAssertEqual(h(.basicAttack, crit: true), 0.04)
        XCTAssertNil(h(.basicAttack))
        XCTAssertEqual(h(.basicAttack, killed: true), 0.09, "倒した一撃")
        XCTAssertNil(h(.skill(.skill1), hero: false), "ミニオン・モンスターの狩りでは止めない")
        XCTAssertNil(h(.skill(.ultimate), byMe: false, onMe: false), "自分が関わらない命中")
        XCTAssertNil(h(.tower, byMe: false, onMe: true))
        for t in [0.09, 0.07, 0.055, 0.04] { XCTAssertLessThanOrEqual(t, BattleFeel.maxHold) }
    }

    private func practice() -> BattleController {
        let config = MatchFactory.practiceMatch(humanHeroID: "H029", humanName: "P", options: PracticeOptions(spawnMinions: false),
                                                tutorial: false, seed: 3)
        return BattleController(launch: BattleLaunch(config: config))
    }

    private func hit(_ c: BattleController, _ source: DamageSource) -> SimEvent? {
        guard let me = c.humanHeroID, let dummy = c.state.units.first(where: { $0.kind == .dummy })?.id else { return nil }
        return .damage(DamageEvent(sourceID: me, targetID: dummy, amount: 10, absorbed: 0, damageType: .physical,
                                   source: source, isCrit: false, pos: .zero))
    }

    /// 止めるのはその長さだけ。止めた後 holdGap は次を止めない（多段でかくつき続けない）。出さない場面（enabled = false）は止めない。
    /// sim の時刻・状態は変えない。
    func testHoldLastsItsTierThenWaitsForTheGap() throws {
        let c = practice()
        let e = try XCTUnwrap(hit(c, .skill(.skill1)))
        let tick = c.state.tick
        let feel = BattleFeel()
        XCTAssertTrue(feel.frame(events: [e], controller: c, now: 10, enabled: true).hold)
        XCTAssertTrue(feel.frame(events: [], controller: c, now: 10.05, enabled: true).hold)
        XCTAssertFalse(feel.frame(events: [], controller: c, now: 10.06, enabled: true).hold)
        XCTAssertFalse(feel.frame(events: [e], controller: c, now: 10.1, enabled: true).hold, "間（holdGap）の内は止めない")
        XCTAssertTrue(feel.frame(events: [e], controller: c, now: 10.2, enabled: true).hold)
        XCTAssertFalse(BattleFeel().frame(events: [e], controller: c, now: 10, enabled: false).hold)
        XCTAssertEqual(c.state.tick, tick, "sim は進めない・変えない")
    }

    /// 自分の奥義: 閃光・ぼかし・押し込み。後処理の脈は 0.03 秒で立ち上がり、長さで 0 に戻る。
    func testOwnUltimatePulsesAndPushes() throws {
        let c = practice()
        let me = try XCTUnwrap(c.humanHeroID)
        let cast = SimEvent.skillCast(SkillCastEvent(casterID: me, heroID: "H029", slot: .ultimate, skillID: "", effectID: "",
                                                     archetype: .selfAoE, origin: .zero, target: .zero, range: 0, radius: 300))
        let f = BattleFeel().frame(events: [cast], controller: c, now: 5, enabled: true)
        let p = try XCTUnwrap(f.pulse)
        XCTAssertGreaterThan(p.flash, 0)
        if !UIAccessibility.isReduceMotionEnabled {
            XCTAssertGreaterThan(p.blur, 0)
            XCTAssertEqual(f.pushIn ?? 0, 1.1, accuracy: 1e-5)
        }
        XCTAssertEqual(p.amounts(at: 5).flash, 0, accuracy: 1e-5)
        XCTAssertEqual(p.amounts(at: 5.03).flash, p.flash, accuracy: 1e-3)
        XCTAssertEqual(p.amounts(at: 5 + PostProcessor.ScreenPulse.flashSeconds).flash, 0, accuracy: 1e-4)
        XCTAssertEqual(p.amounts(at: 5 + PostProcessor.ScreenPulse.blurSeconds).blur, 0, accuracy: 1e-4)
        XCTAssertNil(BattleFeel().frame(events: [cast], controller: c, now: 5, enabled: false).pulse)
    }

    /// カメラの押し込み: 視線の方向へ寄って戻る。注視点・距離（頭上バーの大きさ・影の範囲）は変えない。
    func testPushInMovesAlongTheViewAndReturns() {
        let rig = CameraRig()
        let drive = CameraDrive(target: [20, -20], zoom: 1, transition: .cut)
        rig.update(drive, dt: 1 / 60, mapMeters: 97.2)
        let p0 = rig.camera.position
        let d0 = rig.currentDistance
        rig.addPushIn(1)
        var nearest: Float = 0
        for _ in 0..<6 {
            rig.update(drive, dt: 1 / 60, mapMeters: 97.2)
            nearest = max(nearest, simd_distance(rig.camera.position, p0))
        }
        XCTAssertGreaterThan(nearest, 0.5, "寄った")
        let toFocus = simd_normalize(SIMD3<Float>(20, 0, -20) - p0)
        XCTAssertGreaterThan(simd_dot(simd_normalize(rig.camera.position - p0), toFocus), 0.99, "視線の方向へ")
        XCTAssertEqual(rig.currentDistance, d0, accuracy: 1e-4)
        for _ in 0..<60 { rig.update(drive, dt: 1 / 60, mapMeters: 97.2) }
        XCTAssertLessThan(simd_distance(rig.camera.position, p0), 1e-3, "戻った")
        XCTAssertEqual(CameraRig.pushEnvelope(0), 0)
        XCTAssertEqual(CameraRig.pushEnvelope(CameraRig.pushRise), 1, accuracy: 1e-4)
        XCTAssertEqual(CameraRig.pushEnvelope(CameraRig.pushRise + CameraRig.pushFall), 0)
    }
}
