import XCTest
@testable import VELSTRIA
import VelstriaCore

/// H029 ボルグの専用の収録（H029MotionClips.json、docs/H029_MOTION.md）が実際の再生経路で使われること:
/// 手続き（HeroIdle・HeroGait・Motion_H029 の全身の通常攻撃）に上書きされず、打撃は KitTimes / sim の windup に合う。
@MainActor
final class H029MotionClipTests: XCTestCase {
    private let hero = "H029"

    private func animator() throws -> HeroAnimator {
        HeroMotionClips.setResolverForTesting(nil)
        let lib = HeroMotionClips.library(heroID: hero)
        let set = try XCTUnwrap(HeroMotionSets.set(heroID: hero))
        let binding = try XCTUnwrap(HeroMotionBinding(set: set, library: lib))
        let bp = HeroBlueprints.blueprint(heroID: hero, role: nil)
        return HeroAnimator(profile: HeroMotionProfile(blueprint: bp, metrics: BodyMetrics.make(bp.build), heroID: hero),
                            defaultRunSpeed: 2.6, motion: binding)
    }

    func testDedicatedClipsAreBoundAndOverrideProceduralMotion() throws {
        HeroMotionClips.setResolverForTesting(nil)
        let lib = HeroMotionClips.library(heroID: hero)
        let set = try XCTUnwrap(HeroMotionSets.set(heroID: hero))
        XCTAssertEqual(set.idle, "idle_h029", "HeroIdle があっても専用の待機を外さない")
        let b = try XCTUnwrap(HeroMotionBinding(set: set, library: lib))
        XCTAssertTrue(b.dedicatedIdle)
        XCTAssertTrue(set.dedicatedAttack)
        XCTAssertNil(b.walk, "移動は 1 種類の走り（鈍足でも同じ走りを遅く回す）")
        XCTAssertNotNil(b.run)
        XCTAssertEqual(b.attacks.count, 3, "MLBB の通常攻撃 3 種")
        XCTAssertEqual(b.casts.compactMap { $0 }.count, 3)
        XCTAssertEqual(b.cast(1, stage: 1), lib.index(of: "maul_upswing_h029"), "S2 の再使用（打ち上げ）のクリップ")
        XCTAssertEqual(b.cast(1, stage: 0), lib.index(of: "shield_charge_h029"))
        XCTAssertTrue(b.locksLegs(1), "突進中も脚はクリップ")
        XCTAssertFalse(b.locksLegs(0))
        for name in ["idle_h029", "run_h029", "maul_sweep_h029", "maul_backhand_h029", "maul_smash_h029",
                     "maul_wave_h029", "shield_charge_h029",
                     "maul_upswing_h029", "maul_sanctuary_h029"] {
            let c = try XCTUnwrap(lib.index(of: name), name)
            XCTAssertNotEqual(lib.clips[c].detailMask, 0, "\(name): 肩・指・つま先の補助関節")
        }
        let a = try animator()
        XCTAssertTrue(a.profile.attackMotions.isEmpty, "Motion_H029 の全身の通常攻撃が専用の収録を上書きしない")
        XCTAssertEqual(a.clips.clipName, "idle_h029", "出現直後から専用の待機")
    }

    /// MLBB の 3 種（横振り → 返し → 叩きつけ）を順に繰り返し、どれも命中 = sim の windup、次の攻撃までに振り終える。
    func testAttackImpactLandsAtSimWindupAtBaseAndFastAttackSpeed() throws {
        let order = ["maul_sweep_h029", "maul_backhand_h029", "maul_smash_h029"]
        for interval: Float in [0.97, 0.45] {
            var a = try animator()
            let windup = interval * Float(Balance.attackWindupRatio)
            a.setState(.attack)
            for k in 0..<4 {
                a.playAttack(windup: windup, interval: interval)
                XCTAssertEqual(a.clips.clipName, order[k % 3], "\(k) 発目")
                var t: Float = 0, hit: Float?
                while t < interval - 1e-4 {
                    let before = a.clips.clipTime
                    _ = a.advance(dt: 1.0 / 120, moveSpeed: 0)
                    t += 1.0 / 120
                    if hit == nil, before < a.clips.impactTime, a.clips.clipTime >= a.clips.impactTime { hit = t }
                }
                XCTAssertEqual(try XCTUnwrap(hit, "\(interval) \(k)"), windup, accuracy: 1.0 / 60,
                               "命中 = sim の windup（攻撃間隔 \(interval)、\(order[k % 3])）")
                XCTAssertTrue(a.clips.clipTime <= a.clips.endTime + 1e-4)
            }
        }
    }

    /// 止まって（前の攻撃から 1.5 秒より空いて）から振ると ① に戻る。続けて振る間は順番を続ける。
    func testAttackRestartsFromSweepAfterPause() throws {
        var a = try animator()
        let interval: Float = 0.97, windup = interval * Float(Balance.attackWindupRatio)
        a.setState(.attack)
        for name in ["maul_sweep_h029", "maul_backhand_h029"] {
            a.playAttack(windup: windup, interval: interval)
            XCTAssertEqual(a.clips.clipName, name)
            for _ in 0..<Int(interval * 60) { _ = a.advance(dt: 1.0 / 60, moveSpeed: 0) }
        }
        a.setState(.idle)
        for _ in 0..<120 { _ = a.advance(dt: 1.0 / 60, moveSpeed: 0) }
        a.setState(.attack)
        a.playAttack(windup: windup, interval: interval)
        XCTAssertEqual(a.clips.clipName, "maul_sweep_h029", "止まった後は ① から")
    }

    func testCastClipsStrikeAtKitTimes() throws {
        let cases: [(SkillSlot, Int, String, Float)] = [
            (.skill1, 0, "maul_wave_h029", KitTimes(hero, .skill1).seconds("waveFirstDelay")),
            (.skill2, 0, "shield_charge_h029",
             Float(KitTimes(hero, .skill2).distance("dashRange") / KitTimes(hero, .skill2).speed("dashSpeed"))),
            (.skill2, 1, "maul_upswing_h029", KitTimes(hero, .skill2, stage: 1).seconds("smashDelay")),
            (.ultimate, 0, "maul_sanctuary_h029", KitTimes(hero, .ultimate).seconds("ultTotal")),
        ]
        for (slot, stage, name, strike) in cases {
            XCTAssertGreaterThan(strike, 0, name)
            var a = try animator()
            if stage == 0 {
                a.setState(.cast(slot))
            } else {
                a.setState(.cast(slot))
                _ = a.advance(dt: 0.3, moveSpeed: 0)
                a.playCast(slot, stage: stage)
            }
            XCTAssertEqual(a.clips.clipName, name)
            var t: Float = 0, hit: Float?
            while t < strike + 0.3 {
                let before = a.clips.clipTime
                _ = a.advance(dt: 1.0 / 120, moveSpeed: 0)
                t += 1.0 / 120
                if hit == nil, before < a.clips.impactTime, a.clips.clipTime >= a.clips.impactTime { hit = t }
            }
            XCTAssertEqual(try XCTUnwrap(hit, name), strike, accuracy: 1.0 / 60, "\(name) の打撃 = KitTimes")
        }
    }

    /// 詠唱のクリップは詠唱の状態（手続きの Motion_H029 の長さ）が終わるまで続く。先に終わると手続きの姿勢へ一瞬戻る
    /// （槌を体の横に立て盾を胸の前に構えた旧い構え）。再生は打撃 = KitTimes になる位置から始まる。
    func testCastClipsCoverCastState() throws {
        let a = try animator()
        let lib = HeroMotionClips.library(heroID: hero)
        let cases: [(SkillSlot, Int, String)] = [(.skill1, 0, "maul_wave_h029"), (.skill2, 0, "shield_charge_h029"),
                                                 (.skill2, 1, "maul_upswing_h029"), (.ultimate, 0, "maul_sanctuary_h029")]
        for (slot, stage, name) in cases {
            let info = lib.clips[try XCTUnwrap(lib.index(of: name), name)]
            let strike = try XCTUnwrap(a.profile.clipStrike(slot, stage: stage), name)
            let visible = info.endTime - (info.impactTime - strike)
            XCTAssertGreaterThanOrEqual(visible, a.castDuration(slot, stage: stage), "\(name): クリップが詠唱より先に終わる")
        }
    }

    /// 同梱のモデルのマントに揺れ物の骨（capel1〜3・caper1〜3）があり、実行時の揺れ（HeroSecondaryMotion）が動かす。
    func testBundledCapeHasSecondaryChains() throws {
        guard let url = HeroAssetLibrary.bundledURL("Hero_H029") else { throw XCTSkip("Hero_H029 が同梱されていない") }
        let model = HeroModelLibrary.makeHero(heroID: hero, skinID: nil, team: .blue, master: MasterData.shared,
                                              options: HeroModelOptions.showcase.with(mesh: .skinned(url)))
        let m = try XCTUnwrap(model as? SkinnedHeroModel)
        XCTAssertTrue(m.hasSecondary, "マントの揺れ物の骨（capel1〜caper3）が見つからない")
    }

    func testLocomotionPicksWalkOrRunBySpeed() throws {
        var a = try animator()
        a.setState(.run)
        // 試合の移動速度（260 × mapScale 1.35 = 毎秒 3.51 m）は走り（MLBB の小走り 14 コマ / 周）を等速で回す
        let base = Float(260 * Balance.mapScale / Balance.unitsPerMeter)
        for _ in 0..<60 { _ = a.advance(dt: 1.0 / 60, moveSpeed: base) }
        XCTAssertEqual(a.clips.clipName, "run_h029")
        a.setState(.idle)
        for _ in 0..<60 { _ = a.advance(dt: 1.0 / 60, moveSpeed: 0) }
        a.setState(.run)
        let before = a.clips.clipTime
        for _ in 0..<60 { _ = a.advance(dt: 1.0 / 60, moveSpeed: 1.2) }
        XCTAssertEqual(a.clips.clipName, "run_h029", "鈍足でも同じ走り")
        // 実際の速さ / groundSpeed で回す（1 秒で 1.2 / 3.51 周の分だけ進む。足を滑らせない）
        let lib = HeroMotionClips.library(heroID: hero)
        let info = lib.clips[try XCTUnwrap(lib.index(of: "run_h029"))]
        let advanced = (a.clips.clipTime - before + info.duration).truncatingRemainder(dividingBy: info.duration)
        XCTAssertEqual(advanced, 1.2 / (info.groundSpeed ?? 3.51), accuracy: 0.08)
    }
}
