import XCTest
@testable import VelstriaCore

/// 移動の基本動作。NavGrid の障害物に依存しないよう、中央レーンの中心線（x = y、350 以内に障害物なし）
/// 付近の座標だけを使う。
final class CombatMovementTests: XCTestCase {
    /// 中央レーン上の基準点と、レーンに沿った単位ベクトル。
    private let origin = Vec2(5000, 5000)
    private let lane = Vec2(1, 1).normalized

    func testDirectionMovementUsesMoveSpeedAndOutOfCombatBonus() {
        var w = CombatWorld()
        var st = CombatWorld.stats(moveSpeed: 300)
        st.outOfCombatMoveSpeedBonus = 0.2
        let h = w.addHero(team: .blue, at: origin, stats: st)
        w.s.units[h].moveIntent = .direction(lane * 3) // 正規化される
        w.tick(30)
        XCTAssertEqual(w.s.units[h].pos.distance(to: origin), 360, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[h].facing, .pi / 4, accuracy: 1e-9)

        // 戦闘中（5 秒以内に交戦）は非戦闘ボーナスなし
        w.s.units[h].lastCombatTime = w.s.time
        w.tick(30)
        XCTAssertEqual(w.s.units[h].pos.distance(to: origin), 660, accuracy: 1e-6)
        XCTAssertEqual(MovementSystem.currentMoveSpeed(w.s, h), 300)
    }

    func testNoMovementDuringWindupCrowdControlOrChannel() {
        var w = CombatWorld()
        let h = w.addHero(team: .blue, at: origin)
        w.s.units[h].moveIntent = .direction(lane)

        w.s.units[h].windupRemaining = 10
        MovementSystem.update(&w.s, w.ctx)
        XCTAssertEqual(w.s.units[h].pos, Vec2(5000, 5000))
        w.s.units[h].windupRemaining = nil

        CombatSystem.addStatus(&w.s, targetIndex: h, StatusEffect(kind: .root, duration: 1))
        MovementSystem.update(&w.s, w.ctx)
        XCTAssertEqual(w.s.units[h].pos, Vec2(5000, 5000))
        w.s.units[h].statuses.removeAll()

        w.s.units[h].hero?.channel = Channel(kind: .recall, duration: 6)
        MovementSystem.update(&w.s, w.ctx)
        XCTAssertEqual(w.s.units[h].pos, Vec2(5000, 5000))
        w.s.units[h].hero?.channel = nil

        MovementSystem.update(&w.s, w.ctx)
        XCTAssertEqual(w.s.units[h].pos.distance(to: origin), 10, accuracy: 1e-9)
    }

    func testPointMovementArrivesAndClearsIntent() {
        var w = CombatWorld()
        let h = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let goal = Vec2(5400, 5300) // 500 ユニット先
        w.s.units[h].moveIntent = .point(goal)
        w.tick()
        XCTAssertFalse(w.s.units[h].path.isEmpty, "経路をキャッシュする")
        XCTAssertEqual(w.s.units[h].pos.distance(to: Vec2(5000, 5000)), 10, accuracy: 1e-6)
        w.tick(48)
        XCTAssertNotEqual(w.s.units[h].moveIntent, .none)
        w.tick(2)
        XCTAssertEqual(w.s.units[h].pos.distance(to: goal), 0, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[h].moveIntent, .none)
        XCTAssertTrue(w.s.units[h].path.isEmpty)
    }

    func testPointGoalChangeRecomputesPath() {
        var w = CombatWorld()
        let h = w.addHero(team: .blue, at: Vec2(5000, 5000))
        w.s.units[h].moveIntent = .point(Vec2(5500, 5500))
        w.tick()
        let goal = Vec2(4700, 4800)
        let before = w.s.units[h].pos.distance(to: goal)
        w.s.units[h].moveIntent = .point(goal)
        w.tick()
        XCTAssertEqual(w.s.units[h].path.last, goal)
        XCTAssertEqual(w.s.units[h].pos.distance(to: goal), before - 10, accuracy: 1e-6)
    }

    func testCachedPathValidityToleratesUnwalkableGoalOffset() {
        let w = CombatWorld()
        let edgePath = [Vec2(1, 5000)]
        let r = Balance.heroRadius
        // 目標が歩み寄れる地点なら 50 以内のずれだけ許す
        XCTAssertTrue(MovementSystem.pathStillValid(w.ctx, edgePath, goal: Vec2(40, 5000), radius: r,
                                                    unwalkableTolerance: 400))
        XCTAssertFalse(MovementSystem.pathStillValid(w.ctx, [Vec2(5000, 5000)], goal: Vec2(5100, 5000), radius: r,
                                                     unwalkableTolerance: 400))
        // マップ外（歩行不能）の目標: 終点は最寄りの歩行可能点でずれるが、許容内なら作り直さない
        XCTAssertTrue(MovementSystem.pathStillValid(w.ctx, edgePath, goal: Vec2(-300, 5000), radius: r,
                                                    unwalkableTolerance: 400))
        XCTAssertFalse(MovementSystem.pathStillValid(w.ctx, edgePath, goal: Vec2(-600, 5000), radius: r,
                                                     unwalkableTolerance: 400))
        XCTAssertFalse(MovementSystem.pathStillValid(w.ctx, [], goal: Vec2(40, 5000), radius: r,
                                                     unwalkableTolerance: 400))
    }

    func testFollowStopsWithinRange() {
        var w = CombatWorld()
        let h = w.addHero(team: .blue, at: origin)
        let t = w.addHero(team: .blue, at: origin + lane * 600)
        w.s.units[h].moveIntent = .follow(targetID: w.id(t), range: 200)
        w.tick(60)
        let dist = w.s.units[h].pos.distance(to: w.s.units[t].pos)
        XCTAssertEqual(dist, 200 + 2 * Balance.heroRadius, accuracy: 1)
        XCTAssertEqual(w.s.units[h].moveIntent, .none)
    }

    func testFollowStopsWhenTargetDies() {
        var w = CombatWorld()
        let h = w.addHero(team: .blue, at: origin)
        let t = w.addHero(team: .red, at: origin + lane * 600)
        w.s.units[h].moveIntent = .follow(targetID: w.id(t), range: 100)
        w.tick(5)
        w.s.units[t].isAlive = false
        let pos = w.s.units[h].pos
        w.tick(5)
        XCTAssertEqual(w.s.units[h].pos, pos)
        XCTAssertEqual(w.s.units[h].moveIntent, .none)
    }

    func testMinionSeparationPushesSameTeamApartOnly() {
        var w = CombatWorld()
        let a = w.addMinion(.melee, team: .blue, at: Vec2(5000, 5000))
        let b = w.addMinion(.melee, team: .blue, at: Vec2(5000, 5000))
        let c = w.addMinion(.melee, team: .blue, at: Vec2(5010, 5000))
        let e1 = w.addMinion(.melee, team: .red, at: Vec2(6000, 6000))
        let e2 = w.addMinion(.melee, team: .blue, at: Vec2(6000, 6000))
        w.tick(60)
        let minDist = 0.9 * 2 * 36.0
        for (x, y) in [(a, b), (a, c), (b, c)] {
            XCTAssertGreaterThanOrEqual(w.s.units[x].pos.distance(to: w.s.units[y].pos), minDist - 1)
        }
        XCTAssertEqual(w.s.units[e1].pos, Vec2(6000, 6000), "敵ミニオンとは押し合わない")
        XCTAssertEqual(w.s.units[e2].pos, Vec2(6000, 6000))
    }

    func testMinionSeparationIsDeterministic() {
        func run() -> [Vec2] {
            var w = CombatWorld()
            for k in 0..<12 {
                w.addMinion(k % 3 == 0 ? .ranged : .melee, team: .blue, at: Vec2(5000 + Double(k % 3) * 5, 5000))
            }
            w.tick(45)
            return w.s.units.map(\.pos)
        }
        XCTAssertEqual(run(), run())
    }

    func testLeapDashAndBlink() {
        var w = CombatWorld()
        let h = w.addHero(team: .blue, at: origin)
        let landing = origin + lane * 400
        let to = MovementSystem.dash(&w.s, w.ctx, unitIndex: h, to: landing, speed: 800, kind: .leap)
        XCTAssertEqual(to, landing)
        XCTAssertEqual(w.s.units[h].displacement?.duration ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertFalse(w.s.units[h].canAct)
        w.tick(8)
        XCTAssertEqual(w.s.units[h].pos.distance(to: origin), 400 * (8 * Balance.dt / 0.5), accuracy: 1e-6)
        w.tick(8)
        XCTAssertNil(w.s.units[h].displacement)
        XCTAssertEqual(w.s.units[h].pos, landing)

        // 突進はマップ端で止まる
        let end = MovementSystem.dash(&w.s, w.ctx, unitIndex: h, to: Vec2(20_000, 5000), speed: 5000)
        XCTAssertLessThanOrEqual(end.x, Balance.mapSize)
        w.tick(90)
        XCTAssertLessThanOrEqual(w.s.units[h].pos.x, Balance.mapSize)

        let b = MovementSystem.blink(&w.s, w.ctx, unitIndex: h, to: origin)
        XCTAssertEqual(w.s.units[h].pos, b)
        XCTAssertEqual(w.s.units[h].prevPos, b)
        XCTAssertTrue(w.s.events.contains { if case .blinked = $0 { return true } else { return false } })
        XCTAssertEqual(w.s.events.filter { if case .displaced = $0 { return true } else { return false } }.count, 2)
    }
}
