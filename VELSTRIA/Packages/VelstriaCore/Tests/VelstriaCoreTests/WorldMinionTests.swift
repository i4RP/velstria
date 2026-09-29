import XCTest
@testable import VelstriaCore

/// ミニオン（DESIGN §3・§4）: 索敵優先度・救援要請・追跡制限・レーン進行・巨像の加護。
final class WorldMinionTests: XCTestCase {
    typealias Kit = WorldTestKit

    /// mid 中央（両軍の塔から遠い）で戦う状態。
    func makeField() -> (SimState, SimContext) {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.setTime(&s, 120)
        Kit.suppressWaves(&s)
        return (s, ctx)
    }

    func refresh(_ s: inout SimState, _ ctx: SimContext) {
        VisionSystem.update(&s, ctx)
        MinionSystem.update(&s, ctx)
    }

    func testPrefersMinionsOverCloserHero() {
        var (s, ctx) = makeField()
        let me = Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(5800, 5800))
        let hero = Kit.addHero(&s, ctx, team: .red, pos: Vec2(6000, 6000))
        let enemy = Kit.addMinion(&s, ctx, team: .red, pos: Vec2(6250, 6250))
        refresh(&s, ctx)
        XCTAssertEqual(s.units[me].attackTargetID, s.units[enemy].id)
        XCTAssertEqual(s.units[me].moveIntent, .follow(targetID: s.units[enemy].id, range: s.units[me].stats.attackRange))
        _ = hero
    }

    func testTargetsHeroWhenAlone() {
        var (s, ctx) = makeField()
        let me = Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(5800, 5800))
        let hero = Kit.addHero(&s, ctx, team: .red, pos: Vec2(6100, 6100))
        refresh(&s, ctx)
        XCTAssertEqual(s.units[me].attackTargetID, s.units[hero].id)
    }

    func testIgnoresTargetsBeyondAcquireRadiusAndNeutrals() {
        var (s, ctx) = makeField()
        let me = Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(5800, 5800))
        Kit.addMinion(&s, ctx, team: .red, pos: Vec2(6400, 6400)) // 849 > 700
        s.addUnit(UnitFactory.makeMonster(kind: .campSmall, campID: 0, pos: Vec2(6000, 5800)))
        refresh(&s, ctx)
        XCTAssertNil(s.units[me].attackTargetID)
        // レーンを進む（次の経由点 = Red Core 手前）
        if case .point(let p) = s.units[me].moveIntent {
            XCTAssertLessThan(p.distance(to: Vec2(9700, 9700)), 60)
        } else {
            XCTFail("minion should walk the lane")
        }
    }

    func testStructureBeforeHeroAndSkipsInvulnerableStructures() {
        var (s, ctx) = makeField()
        let outer = Kit.structureIndex(s, team: .red, lane: .mid, tier: .outer) // (7700,7700)
        let me = Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(7200, 7200))
        s.units[me].minion?.waypointIndex = 2
        Kit.addHero(&s, ctx, team: .red, pos: Vec2(7300, 7300))
        refresh(&s, ctx)
        XCTAssertEqual(s.units[me].attackTargetID, s.units[outer].id)

        // 内塔は外塔が健在の間は無敵なので狙わない
        var (s2, ctx2) = makeField()
        let inner = Kit.structureIndex(s2, team: .red, lane: .mid, tier: .inner) // (8600,8600)
        let m2 = Kit.addMinion(&s2, ctx2, team: .blue, pos: Vec2(8150, 8150))
        s2.units[m2].minion?.waypointIndex = 2
        refresh(&s2, ctx2)
        XCTAssertNotEqual(s2.units[m2].attackTargetID, s2.units[inner].id)
        Kit.kill(&s2, Kit.structureIndex(s2, team: .red, lane: .mid, tier: .outer))
        s2.units[m2].attackTargetID = nil
        refresh(&s2, ctx2)
        XCTAssertEqual(s2.units[m2].attackTargetID, s2.units[inner].id)
    }

    func testCallForHelpSwitchesToHeroAggressor() {
        var (s, ctx) = makeField()
        let me = Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(5800, 5800))
        let enemyMinion = Kit.addMinion(&s, ctx, team: .red, pos: Vec2(6100, 6100))
        let enemyHero = Kit.addHero(&s, ctx, team: .red, pos: Vec2(6200, 5900))
        let ally = Kit.addHero(&s, ctx, team: .blue, pos: Vec2(5900, 5600))
        refresh(&s, ctx)
        XCTAssertEqual(s.units[me].attackTargetID, s.units[enemyMinion].id)

        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[enemyHero].id, targetIndex: ally, amount: 40,
                                 type: .physical, source: .basicAttack)
        refresh(&s, ctx)
        XCTAssertEqual(s.units[me].attackTargetID, s.units[enemyHero].id)

        // 2 秒経過後も（範囲内なら）ヒーローを追い続ける
        Kit.setTime(&s, s.time + 3)
        refresh(&s, ctx)
        XCTAssertEqual(s.units[me].attackTargetID, s.units[enemyHero].id)
    }

    func testCallForHelpIgnoresFarAwayFights() {
        var (s, ctx) = makeField()
        let me = Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(5800, 5800))
        let enemyMinion = Kit.addMinion(&s, ctx, team: .red, pos: Vec2(6100, 6100))
        // 攻撃された味方はミニオンから遠い（救援要請の範囲外）
        let enemyHero = Kit.addHero(&s, ctx, team: .red, pos: Vec2(6300, 5700))
        let ally = Kit.addHero(&s, ctx, team: .blue, pos: Vec2(7200, 5000))
        refresh(&s, ctx)
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[enemyHero].id, targetIndex: ally, amount: 40,
                                 type: .physical, source: .basicAttack)
        refresh(&s, ctx)
        XCTAssertEqual(s.units[me].attackTargetID, s.units[enemyMinion].id)
    }

    func testKeepsTargetUntilOutOfKeepRadius() {
        var (s, ctx) = makeField()
        let me = Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(5800, 5800))
        let hero = Kit.addHero(&s, ctx, team: .red, pos: Vec2(6100, 6100))
        refresh(&s, ctx)
        XCTAssertEqual(s.units[me].attackTargetID, s.units[hero].id)
        // 別の敵ミニオンが来ても維持
        Kit.addMinion(&s, ctx, team: .red, pos: Vec2(6000, 6000))
        refresh(&s, ctx)
        XCTAssertEqual(s.units[me].attackTargetID, s.units[hero].id)
        // 900 を超えたら解除（近くの敵ミニオンへ）
        s.units[hero].pos = Vec2(6600, 6600)
        refresh(&s, ctx)
        XCTAssertNotEqual(s.units[me].attackTargetID, s.units[hero].id)
    }

    func testDoesNotChaseFarFromLane() {
        var (s, ctx) = makeField()
        // mid レーン中心線 (x = y) から 900 超の相手は追わない
        let me = Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(5800, 5800))
        let hero = Kit.addHero(&s, ctx, team: .red, pos: Vec2(6000, 5600))
        refresh(&s, ctx)
        XCTAssertEqual(s.units[me].attackTargetID, s.units[hero].id)
        s.units[hero].pos = Vec2(6300, 5000) // レーンから 919
        refresh(&s, ctx)
        XCTAssertNil(s.units[me].attackTargetID)
        guard case .point = s.units[me].moveIntent else { return XCTFail("should walk back to lane") }

        // ミニオン自身がレーンから 900 超に押し出されたら対象を捨ててレーンへ戻る
        var (s2, ctx2) = makeField()
        let m2 = Kit.addMinion(&s2, ctx2, team: .blue, pos: Vec2(6700, 5300)) // レーンから 990
        XCTAssertTrue(ctx2.nav.isWalkable(s2.units[m2].pos, radius: s2.units[m2].radius))
        let h2 = Kit.addHero(&s2, ctx2, team: .red, pos: Vec2(6700, 5500))
        s2.units[m2].attackTargetID = s2.units[h2].id
        refresh(&s2, ctx2)
        XCTAssertNil(s2.units[m2].attackTargetID)
        guard case .point(let goal) = s2.units[m2].moveIntent else { return XCTFail("should return") }
        XCTAssertLessThan(ctx2.map.distanceToLane(goal, lane: .mid), 1)
        XCTAssertGreaterThan(goal.x + goal.y, 6700 + 5300) // 後戻りせず前方へ合流
    }

    func testReturnToLaneSteersAroundWalls() {
        var (s, ctx) = makeField()
        // bot レーン (y = 1400) との間に壁 (5300..6900, 1950..2450) がある位置へ押し出された
        let m = Kit.addMinion(&s, ctx, team: .blue, lane: .bot, pos: Vec2(6100, 2650))
        s.units[m].minion?.waypointIndex = 2
        refresh(&s, ctx)
        guard case .point(let goal) = s.units[m].moveIntent else { return XCTFail("should return") }
        XCTAssertTrue(ctx.nav.hasLineOfSight(from: s.units[m].pos, to: goal, radius: s.units[m].radius))
        XCTAssertTrue(goal.x < 5300 || goal.x > 6900, "should go around the wall: \(goal)")

        // 実際に歩かせるとレーンへ戻る
        let id = s.units[m].id
        let sim = Simulation(snapshot: s)
        sim.runHeadless(maxTime: s.time + 12)
        let u = sim.state.unit(id)!
        XCTAssertLessThan(sim.ctx.map.distanceToLane(u.pos, lane: .bot), Balance.minionReturnThreshold)
    }

    func testWaypointProgression() {
        var (s, ctx) = makeField()
        // Blue top: (1500,1500) → (1400,2400) → (1400,10600) → (9600,10600) → (10500,10500)
        let m = Kit.addMinion(&s, ctx, team: .blue, lane: .top, pos: Vec2(1420, 2320))
        refresh(&s, ctx)
        XCTAssertEqual(s.units[m].minion?.waypointIndex, 2)
        // 押し出されて先の区間に居ても射影で進む
        s.units[m].pos = Vec2(1600, 10580)
        refresh(&s, ctx)
        XCTAssertEqual(s.units[m].minion?.waypointIndex, 3)
        guard case .point(let p) = s.units[m].moveIntent else { return XCTFail() }
        XCTAssertLessThan(p.distance(to: Vec2(9600, 10600)), 60)
        // 最後の経由点（敵 Core）で止まる
        s.units[m].pos = Vec2(10300, 10520)
        refresh(&s, ctx)
        XCTAssertEqual(s.units[m].minion?.waypointIndex, 4)

        // Red は逆順の経路（Red top = 右上から左へ）
        var (s2, ctx2) = makeField()
        let r = Kit.addMinion(&s2, ctx2, team: .red, lane: .top, pos: Vec2(9650, 10580))
        refresh(&s2, ctx2)
        XCTAssertEqual(s2.units[r].minion?.waypointIndex, 2)
        guard case .point(let q) = s2.units[r].moveIntent else { return XCTFail() }
        XCTAssertLessThan(q.distance(to: Vec2(1400, 10600)), 60)
    }

    func testColossusBlessingEmpowersNearbyMinions() {
        var (s, ctx) = makeField()
        let m = Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(5000, 5000))
        let far = Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(3000, 3000))
        let enemy = Kit.addMinion(&s, ctx, team: .red, pos: Vec2(5300, 5300))
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: Vec2(5600, 5600))
        s.units[hero].statuses.append(StatusEffect(kind: .colossusBlessing, duration: 180))
        s.units[enemy].statuses.append(StatusEffect(kind: .colossusBlessing, duration: 180)) // ミニオンの加護は無関係
        let baseHP = s.units[m].stats.maxHP, baseAtk = s.units[m].stats.attack
        s.units[m].hp = baseHP * 0.5
        refresh(&s, ctx)
        XCTAssertEqual(s.units[m].minion?.empowered, true)
        XCTAssertEqual(s.units[m].stats.maxHP, baseHP * 1.5, accuracy: 1e-9)
        XCTAssertEqual(s.units[m].stats.attack, baseAtk * 1.5, accuracy: 1e-9)
        XCTAssertEqual(s.units[m].hpRatio, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.units[far].minion?.empowered, false)
        XCTAssertEqual(s.units[enemy].minion?.empowered, false)
        // 毎 tick 重ね掛けされない
        refresh(&s, ctx)
        StatCalculator.recompute(&s, m, ctx)
        XCTAssertEqual(s.units[m].stats.maxHP, baseHP * 1.5, accuracy: 1e-9)
        // 加護が切れたら元に戻る
        s.units[hero].statuses.removeAll()
        refresh(&s, ctx)
        XCTAssertEqual(s.units[m].minion?.empowered, false)
        XCTAssertEqual(s.units[m].stats.maxHP, baseHP, accuracy: 1e-9)
        XCTAssertEqual(s.units[m].stats.attack, baseAtk, accuracy: 1e-9)
        XCTAssertEqual(s.units[m].hpRatio, 0.5, accuracy: 1e-9)
    }

    func testWavesMeetAndFightInSimulation() {
        var (s, _) = makeField()
        WorldTestKit.setTime(&s, 19.9)
        s.world.nextWaveTime = 20
        let sim = Simulation(snapshot: s)
        var minionDamage = 0
        sim.runHeadless(maxTime: 60) { ev in
            for e in ev {
                if case .damage(let d) = e, d.source == .minion { minionDamage += 1 }
            }
        }
        XCTAssertGreaterThan(minionDamage, 20)
        // 経路上から大きく外れない・障害物に埋まらない
        for u in sim.state.units where u.kind == .minion {
            XCTAssertTrue(sim.ctx.nav.isWalkable(u.pos, radius: 0), "\(u.pos)")
            XCTAssertLessThan(sim.ctx.map.distanceToLane(u.pos, lane: u.minion!.lane), Balance.minionLaneChaseLimit + 200)
        }
    }
}
