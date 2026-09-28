import XCTest
@testable import VelstriaCore

/// タワー / Core（DESIGN §3・§4）: 索敵優先度・連続命中・対ミニオン割合ダメージ・保護・無敵の順序。
final class WorldTowerTests: XCTestCase {
    typealias Kit = WorldTestKit

    /// Blue mid 外塔 (4300,4300) の前（射程内）に敵を置いた状態。
    func makeLaneFight() -> (SimState, SimContext, tower: Int) {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.setTime(&s, 300)
        Kit.suppressWaves(&s)
        return (s, ctx, Kit.structureIndex(s, team: .blue, lane: .mid, tier: .outer))
    }

    func testPrefersNearestMinionOverCloserHero() {
        var (s, ctx, tower) = makeLaneFight()
        let hero = Kit.addHero(&s, ctx, team: .red, pos: Vec2(4550, 4550))
        let far = Kit.addMinion(&s, ctx, team: .red, pos: Vec2(4900, 4900))
        let near = Kit.addMinion(&s, ctx, team: .red, pos: Vec2(4800, 4750))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[near].id)
        _ = (hero, far)
    }

    func testTargetsHeroWhenNoMinionAndDummyCountsAsHero() {
        var (s, ctx, tower) = makeLaneFight()
        let hero = Kit.addHero(&s, ctx, team: .red, pos: Vec2(4800, 4800))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[hero].id)

        var (s2, ctx2, tower2) = makeLaneFight()
        let dummy = s2.addUnit(UnitFactory.makeDummy(team: .red, pos: Vec2(4700, 4700)))
        VisionSystem.update(&s2, ctx2)
        TowerSystem.update(&s2, ctx2)
        XCTAssertEqual(s2.units[tower2].attackTargetID, dummy)
    }

    func testOutOfRangeIsIgnoredAndTargetDropsWhenLeaving() {
        var (s, ctx, tower) = makeLaneFight()
        let m = Kit.addMinion(&s, ctx, team: .red, pos: Vec2(4900, 4900))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[m].id)
        s.units[m].pos = Vec2(5200, 5200) // 1273 > 750 + 110 + 36
        TowerSystem.update(&s, ctx)
        XCTAssertNil(s.units[tower].attackTargetID)
    }

    func testKeepsCurrentTargetUntilItLeaves() {
        var (s, ctx, tower) = makeLaneFight()
        let hero = Kit.addHero(&s, ctx, team: .red, pos: Vec2(4800, 4800))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[hero].id)
        // ミニオンが入ってきてもヒーローを撃ち続ける
        Kit.addMinion(&s, ctx, team: .red, pos: Vec2(4700, 4700))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[hero].id)
    }

    func testHeroAttackingAlliedHeroTakesPriority() {
        var (s, ctx, tower) = makeLaneFight()
        let minion = Kit.addMinion(&s, ctx, team: .red, pos: Vec2(4700, 4700))
        let enemy = Kit.addHero(&s, ctx, team: .red, pos: Vec2(4850, 4850))
        let ally = Kit.addHero(&s, ctx, team: .blue, pos: Vec2(4600, 4500))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[minion].id)

        // 敵ヒーローが味方ヒーローを攻撃 → 即座に切り替え
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[enemy].id, targetIndex: ally, amount: 50,
                                 type: .physical, source: .basicAttack)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[enemy].id)
        XCTAssertEqual(s.units[tower].tower?.rampHits, 0)

        // 2 秒経過後も射程内に居る限り維持
        Kit.setTime(&s, s.time + 2.5)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[enemy].id)

        // 味方がタワー射程外で攻撃された場合は対象外
        var (s2, ctx2, tower2) = makeLaneFight()
        let m2 = Kit.addMinion(&s2, ctx2, team: .red, pos: Vec2(4700, 4700))
        let e2 = Kit.addHero(&s2, ctx2, team: .red, pos: Vec2(4850, 4850))
        let far = Kit.addHero(&s2, ctx2, team: .blue, pos: Vec2(5600, 5600))
        VisionSystem.update(&s2, ctx2)
        CombatSystem.applyDamage(&s2, ctx2, sourceID: s2.units[e2].id, targetIndex: far, amount: 50,
                                 type: .physical, source: .basicAttack)
        TowerSystem.update(&s2, ctx2)
        XCTAssertEqual(s2.units[tower2].attackTargetID, s2.units[m2].id)
    }

    func testRampOnConsecutiveHeroHitsAndResetOnTargetChange() {
        var (s, ctx, tower) = makeLaneFight()
        let a = Kit.addHero(&s, ctx, team: .red, pos: Vec2(4800, 4800))
        let b = Kit.addHero(&s, ctx, team: .red, pos: Vec2(4850, 4750))
        let base = s.units[tower].stats.attack
        XCTAssertEqual(base, 260)
        let expected = [1.0, 1.3, 1.6, 1.9, 2.2, 2.2, 2.2].map { base * $0 }
        for e in expected {
            XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: a), e, accuracy: 1e-9)
        }
        // 別のヒーローに変えるとリセット、戻してもリセット
        XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: b), base, accuracy: 1e-9)
        XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: b), base * 1.3, accuracy: 1e-9)
        XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: a), base, accuracy: 1e-9)
        // ミニオンを撃つとヒーローの連続命中は途切れる
        let m = Kit.addMinion(&s, ctx, team: .red, pos: Vec2(4700, 4700))
        _ = TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: m)
        XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: a), base, accuracy: 1e-9)
    }

    func testMinionDamageIsPercentOfMaxHP() {
        var (s, ctx, tower) = makeLaneFight()
        for (type, pct) in [(MinionType.melee, 0.45), (.ranged, 0.70), (.siege, 0.14)] {
            let m = Kit.addMinion(&s, ctx, type: type, team: .red, pos: Vec2(4700, 4700))
            let maxHP = s.units[m].stats.maxHP
            let dmg = TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: m)
            CombatSystem.applyDamage(&s, ctx, sourceID: s.units[tower].id, targetIndex: m, amount: dmg,
                                     type: .physical, source: .tower)
            XCTAssertEqual(maxHP - s.units[m].hp, pct * maxHP, accuracy: 1e-6, "\(type)")
        }
        // 近接 3 発・遠隔 2 発・攻城 8 発で倒れる
        for (type, shots) in [(MinionType.melee, 3), (.ranged, 2), (.siege, 8)] {
            let m = Kit.addMinion(&s, ctx, type: type, team: .red, pos: Vec2(4700, 4700))
            var n = 0
            while s.units[m].isAlive {
                let dmg = TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: m)
                CombatSystem.applyDamage(&s, ctx, sourceID: s.units[tower].id, targetIndex: m, amount: dmg,
                                         type: .physical, source: .tower)
                n += 1
            }
            XCTAssertEqual(n, shots, "\(type)")
        }
    }

    func testOuterTowerEarlyProtection() {
        var (s, ctx, outer) = makeLaneFight()
        let inner = Kit.structureIndex(s, team: .blue, lane: .mid, tier: .inner)
        let siege = Kit.addMinion(&s, ctx, type: .siege, team: .red, pos: Vec2(4700, 4700))
        Kit.setTime(&s, 100)
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: nil), 0.6, accuracy: 1e-9)
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: siege), 0.9, accuracy: 1e-9)
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: inner, sourceIndex: siege), 1.5, accuracy: 1e-9)
        Kit.setTime(&s, 240)
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: siege), 1.5, accuracy: 1e-9)
    }

    func testBackdoorProtectionAgainstHeroes() {
        var (s, ctx, outer) = makeLaneFight()
        let hero = Kit.addHero(&s, ctx, team: .red, pos: Vec2(4800, 4800))
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: hero), 0.5, accuracy: 1e-9)
        // 塔から 800 以内に攻撃側のミニオンが居れば解除
        let m = Kit.addMinion(&s, ctx, team: .red, pos: Vec2(4800, 4850))
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: hero), 1.0, accuracy: 1e-9)
        // 遠くのミニオンや防衛側のミニオンでは解除されない
        s.units[m].pos = Vec2(5300, 5300)
        Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(4500, 4500))
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: hero), 0.5, accuracy: 1e-9)
        // 序盤保護と重なる
        Kit.setTime(&s, 60)
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: hero), 0.3, accuracy: 1e-9)
        // 実ダメージにも反映される（防御 80: 100 / 180）
        Kit.setTime(&s, 300)
        let before = s.units[outer].hp
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: outer, amount: 180,
                                 type: .physical, source: .basicAttack)
        XCTAssertEqual(before - s.units[outer].hp, 180 * 0.5 * 100 / 180, accuracy: 1e-6)
    }

    func testInvulnerabilityOrder() {
        var (s, ctx, _) = makeLaneFight()
        func idx(_ lane: Lane, _ tier: TowerTier) -> Int { Kit.structureIndex(s, team: .blue, lane: lane, tier: tier) }
        let core = Kit.structureIndex(s, team: .blue, lane: nil, tier: .base, core: true)
        XCTAssertFalse(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .outer)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .inner)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .base)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: core))
        XCTAssertEqual(CombatSystem.applyDamage(&s, ctx, sourceID: nil, targetIndex: idx(.top, .inner), amount: 500,
                                                type: .trueDamage, source: .spell), 0)

        Kit.kill(&s, idx(.top, .outer))
        XCTAssertFalse(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .inner)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .base)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: idx(.mid, .inner)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: core))

        Kit.kill(&s, idx(.top, .inner))
        XCTAssertFalse(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .base)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: core))
        TowerSystem.update(&s, ctx)
        XCTAssertFalse(s.events.contains(.announcement(.coreVulnerable(team: .blue))))

        Kit.kill(&s, idx(.top, .base))
        XCTAssertFalse(TowerSystem.isInvulnerable(s, ctx, index: core))
        XCTAssertGreaterThan(CombatSystem.applyDamage(&s, ctx, sourceID: nil, targetIndex: core, amount: 500,
                                                      type: .trueDamage, source: .spell), 0)
        // Core 露出の告知は 1 度だけ
        TowerSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.events.filter { $0 == .announcement(.coreVulnerable(team: .blue)) }.count, 1)
        // 前計算版（ミニオンの索敵用）と一致
        let table = WorldTargeting.structureInvulnerability(s)
        for i in s.units.indices where s.units[i].isStructure {
            XCTAssertEqual(table[i], TowerSystem.isInvulnerable(s, ctx, index: i))
        }
    }

    func testCoreAttacksLikeTower() {
        var (s, ctx, _) = makeLaneFight()
        let core = Kit.structureIndex(s, team: .red, lane: nil, tier: .base, core: true)
        // Core 射程 800 + 半径 250
        let m = Kit.addMinion(&s, ctx, team: .blue, pos: s.units[core].pos + Vec2(-700, -700))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[core].attackTargetID, s.units[m].id)
        XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: core, targetIndex: m),
                       0.45 * s.units[m].stats.maxHP, accuracy: 1e-6)
    }

    func testTowerKillsMinionsInSimulation() {
        var (s, ctx, tower) = makeLaneFight()
        let m = Kit.addMinion(&s, ctx, type: .ranged, team: .red, pos: Vec2(4800, 4800))
        s.units[m].minion?.waypointIndex = 2
        VisionSystem.update(&s, ctx)
        let sim = Simulation(snapshot: s)
        var hits = 0
        for _ in 0..<90 {
            for e in sim.step() {
                if case .damage(let d) = e, d.sourceID == s.units[tower].id { hits += 1 }
            }
        }
        XCTAssertNil(sim.state.unit(s.units[m].id), "ranged minion should die in 2 tower shots")
        XCTAssertEqual(hits, 2)
    }
}
