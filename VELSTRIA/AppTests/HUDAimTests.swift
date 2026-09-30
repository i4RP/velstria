import XCTest
import UIKit
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud。ドラッグ照準・スティック・ミニマップ投影・アイコンの単体テスト。

final class HUDAimTests: XCTestCase {
    private let point = SkillTargeting(archetype: .groundAoE, aim: .point, range: 600, radius: 150)
    private let line = SkillTargeting(archetype: .lineSkillshot, aim: .direction, range: 900, radius: 60)
    private let selfCast = SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: 300)
    private let unit = SkillTargeting(archetype: .targetedBlink, aim: .unit, range: 700, radius: 100)

    func testDragRatioClampsToOne() {
        XCTAssertEqual(HUDAim.dragRatio(.zero, maxDrag: 84), 0)
        XCTAssertEqual(HUDAim.dragRatio(CGVector(dx: 42, dy: 0), maxDrag: 84), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HUDAim.dragRatio(CGVector(dx: 0, dy: -300), maxDrag: 84), 1)
        XCTAssertEqual(HUDAim.dragRatio(CGVector(dx: 10, dy: 10), maxDrag: 0), 0)
    }

    func testScreenDragMapsToSimDirection() {
        // 画面の右 = sim +x、画面の上（dy < 0）= sim +y
        let right = HUDAim.direction(CGVector(dx: 50, dy: 0), facing: 0)
        XCTAssertEqual(right.x, 1, accuracy: 1e-9)
        XCTAssertEqual(right.y, 0, accuracy: 1e-9)
        let up = HUDAim.direction(CGVector(dx: 0, dy: -50), facing: 0)
        XCTAssertEqual(up.x, 0, accuracy: 1e-9)
        XCTAssertEqual(up.y, 1, accuracy: 1e-9)
        let diag = HUDAim.direction(CGVector(dx: -30, dy: 30), facing: 0)
        XCTAssertEqual(diag.x, -0.5.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(diag.y, -0.5.squareRoot(), accuracy: 1e-9)
    }

    func testTinyDragUsesFacing() {
        let d = HUDAim.direction(CGVector(dx: 1, dy: 1), facing: .pi / 2)
        XCTAssertEqual(d.x, 0, accuracy: 1e-9)
        XCTAssertEqual(d.y, 1, accuracy: 1e-9)
    }

    func testSimDirectionMatchesController() {
        let drag = CGVector(dx: 17, dy: -41)
        let a = HUDAim.simDirection(drag)
        let b = MainActor.assumeIsolated { BattleController.simDirection(fromDrag: drag) }
        XCTAssertEqual(a.x, b.x, accuracy: 1e-12)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-12)
    }

    func testDirectionAimAlwaysUsesFullRange() {
        let origin = Vec2(1000, 1000)
        let short = HUDAim.aimPoint(origin: origin, drag: CGVector(dx: 20, dy: 0), maxDrag: 84, targeting: line, facing: 0)
        XCTAssertEqual(short.x, 1900, accuracy: 1e-6)
        XCTAssertEqual(short.y, 1000, accuracy: 1e-6)
    }

    func testPointAimScalesWithDrag() {
        let origin = Vec2(1000, 1000)
        let half = HUDAim.aimPoint(origin: origin, drag: CGVector(dx: 0, dy: -42), maxDrag: 84, targeting: point, facing: 0)
        XCTAssertEqual(half.x, 1000, accuracy: 1e-6)
        XCTAssertEqual(half.y, 1300, accuracy: 1e-6)
        let beyond = HUDAim.aimPoint(origin: origin, drag: CGVector(dx: -400, dy: 0), maxDrag: 84, targeting: point, facing: 0)
        XCTAssertEqual(beyond.x, 400, accuracy: 1e-6, "最大射程で止まる")
        let none = HUDAim.aimPoint(origin: origin, drag: CGVector(dx: 60, dy: 0), maxDrag: 84, targeting: selfCast, facing: 0)
        XCTAssertEqual(none, origin)
    }

    func testCastTargetsPerAimType() {
        let sim = Simulation(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "T", seed: 7))
        let s = sim.state
        let origin = Vec2(1000, 1000)
        let drag = CGVector(dx: 0, dy: -84)
        if case .direction(let d) = HUDAim.castTarget(targeting: line, origin: origin, aimPoint: origin, drag: drag,
                                                     facing: 0, state: s, team: .blue, casterID: nil) {
            XCTAssertEqual(d.y, 1, accuracy: 1e-9)
        } else {
            XCTFail("方向型は .direction")
        }
        let p = Vec2(1000, 1600)
        XCTAssertEqual(HUDAim.castTarget(targeting: point, origin: origin, aimPoint: p, drag: drag, facing: 0, state: s,
                                         team: .blue, casterID: nil), .point(p))
        XCTAssertEqual(HUDAim.castTarget(targeting: selfCast, origin: origin, aimPoint: origin, drag: drag, facing: 0,
                                         state: s, team: .blue, casterID: nil), .none)
    }

    func testUnitAimPicksNearestVisibleEnemyHeroToAimPoint() {
        let sim = Simulation(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "T", seed: 7))
        var s = sim.state
        let reds = s.heroIndices(team: .red)
        XCTAssertGreaterThanOrEqual(reds.count, 2)
        // 2 体の敵ヒーローを並べて可視にする
        s.units[reds[0]].pos = Vec2(5000, 5000)
        s.units[reds[1]].pos = Vec2(5400, 5000)
        for i in reds { s.units[i].visibleMask = Team.blue.visionBit | Team.red.visionBit }
        let origin = Vec2(4800, 4800)
        let aimNearSecond = Vec2(5350, 5000)
        let t = HUDAim.castTarget(targeting: unit, origin: origin, aimPoint: aimNearSecond, drag: .zero, facing: 0,
                                  state: s, team: .blue, casterID: nil)
        XCTAssertEqual(t, .unit(s.units[reds[1]].id))
        // 見えていなければ選ばない（sim の自動選択に任せる）
        for i in reds { s.units[i].visibleMask = Team.red.visionBit }
        XCTAssertEqual(HUDAim.castTarget(targeting: unit, origin: origin, aimPoint: aimNearSecond, drag: .zero, facing: 0,
                                         state: s, team: .blue, casterID: nil), .none)
        // 射程外は選ばない
        for i in reds { s.units[i].visibleMask = Team.blue.visionBit | Team.red.visionBit }
        XCTAssertEqual(HUDAim.castTarget(targeting: unit, origin: Vec2(1000, 1000), aimPoint: Vec2(1500, 1000), drag: .zero,
                                         facing: 0, state: s, team: .blue, casterID: nil), .none)
    }

    func testCancelZone() {
        let c = CGPoint(x: 700, y: 60)
        XCTAssertTrue(HUDAim.isInCancelZone(CGPoint(x: 710, y: 70), center: c, radius: 38))
        XCTAssertFalse(HUDAim.isInCancelZone(CGPoint(x: 700, y: 100), center: c, radius: 38))
    }

    func testSpellTargeting() {
        XCTAssertEqual(HUDSpellAim.targeting(spellID: "BS01")?.aim, .direction)
        XCTAssertEqual(HUDSpellAim.targeting(spellID: "BS01")?.range, 400)
        XCTAssertEqual(HUDSpellAim.targeting(spellID: "BS07")?.aim, .unit)
        XCTAssertEqual(HUDSpellAim.targeting(spellID: "BS09")?.aim, .point)
        XCTAssertNil(HUDSpellAim.targeting(spellID: "BS03"), "治癒波は即時発動")
        XCTAssertNil(HUDSpellAim.targeting(spellID: "BS04"))
    }

    func testTeleportPicksForwardTowerOrDragDirection() {
        let sim = Simulation(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "T", seed: 7))
        let s = sim.state
        let fountain = MapDefinition.standard.fountain(.blue)
        let tap = HUDSpellAim.teleportDestination(state: s, team: .blue, origin: fountain, drag: .zero, fountain: fountain)
        // 最も前線 = 泉から最も遠い外塔
        let outer = MapDefinition.standard.towers.filter { $0.team == .blue && $0.tier == .outer }.map(\.pos)
        XCTAssertTrue(outer.contains(tap))
        // 右へドラッグ → 下レーン（右側）の塔
        let right = HUDSpellAim.teleportDestination(state: s, team: .blue, origin: Vec2(1500, 1500),
                                                    drag: CGVector(dx: 80, dy: 0), fountain: fountain)
        XCTAssertLessThan(right.y, 1500, "右方向のドラッグは下レーンの塔（y = 1400）")
        // 上へドラッグ → 上レーンの塔
        let up = HUDSpellAim.teleportDestination(state: s, team: .blue, origin: Vec2(1500, 1500),
                                                 drag: CGVector(dx: 0, dy: -80), fountain: fountain)
        XCTAssertLessThan(up.x, 1500)
    }

    // MARK: スティック

    func testJoystickSendsOnlyMeaningfulChanges() {
        let east = Vec2(1, 0)
        XCTAssertTrue(HUDJoystickMath.shouldSend(new: east, last: .zero), "停止 → 移動")
        XCTAssertTrue(HUDJoystickMath.shouldSend(new: .zero, last: east), "移動 → 停止")
        XCTAssertFalse(HUDJoystickMath.shouldSend(new: .zero, last: .zero))
        XCTAssertFalse(HUDJoystickMath.shouldSend(new: Vec2.fromAngle(2 * .pi / 180), last: east), "2° は送らない")
        XCTAssertTrue(HUDJoystickMath.shouldSend(new: Vec2.fromAngle(10 * .pi / 180), last: east), "10° は送る")
    }

    func testJoystickClamp() {
        let v = HUDJoystickMath.clamp(CGVector(dx: 300, dy: 400), radius: 50)
        XCTAssertEqual(v.dx, 30, accuracy: 1e-9)
        XCTAssertEqual(v.dy, 40, accuracy: 1e-9)
        let inside = HUDJoystickMath.clamp(CGVector(dx: 3, dy: 4), radius: 50)
        XCTAssertEqual(inside, CGVector(dx: 3, dy: 4))
    }

    // MARK: ミニマップ

    func testMinimapProjectionRoundTrip() {
        let proj = HUDMinimapProjection(size: 150)
        XCTAssertEqual(proj.point(Vec2(0, 0)), CGPoint(x: 0, y: 150), "Blue 本拠点は左下")
        XCTAssertEqual(proj.point(Vec2(12000, 12000)), CGPoint(x: 150, y: 0), "Red 本拠点は右上")
        let p = Vec2(3000, 9000)
        let back = proj.world(proj.point(p))
        XCTAssertEqual(back.x, p.x, accuracy: 1e-6)
        XCTAssertEqual(back.y, p.y, accuracy: 1e-6)
        XCTAssertEqual(proj.world(CGPoint(x: -20, y: 400)), Vec2(0, 0), "範囲外はマップ端に丸める")
    }

    // MARK: アイコン

    func testAllHUDSymbolsExist() {
        for name in HUDSymbols.all {
            XCTAssertNotNil(UIImage(systemName: name), "SF Symbol \(name) が存在しない")
        }
        for info in SpellInfo.all {
            XCTAssertNotNil(UIImage(systemName: info.symbol), info.symbol)
        }
    }
}
