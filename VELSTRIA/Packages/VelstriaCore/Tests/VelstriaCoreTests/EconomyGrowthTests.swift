import XCTest
@testable import VelstriaCore

/// XP 分配・レベルアップ・スキルポイント（DESIGN §6, §8）。
final class EconomyGrowthTests: XCTestCase {
    private let spot = Vec2(6000, 6000)

    func testMinionXPAndGoldSingleHero() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0]
        f.place(a, at: spot)
        let gold0 = f.hero(a).gold
        let m = f.addMinion(.melee, team: .red, at: spot + Vec2(50, 0))
        let ev = f.kill(m, by: f.id(a))
        XCTAssertEqual(f.hero(a).xp, 60, accuracy: 1e-9)
        let melee = Balance.Economy.minionGold(.melee, at: f.s.time)
        XCTAssertEqual(f.hero(a).gold - gold0, melee, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).score.minionKills, 1)
        XCTAssertEqual(ev.goldGained(by: f.id(a)), melee, accuracy: 1e-9)
    }

    func testMinionXPSharedBetweenNearbyHeroes() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0], b = f.heroes(.blue)[1], far = f.heroes(.blue)[2]
        f.place(a, at: spot)
        f.place(b, at: spot + Vec2(0, 1000))
        f.place(far, at: spot + Vec2(0, 1500))
        let goldB = f.hero(b).gold
        let m = f.addMinion(.siege, team: .red, at: spot)
        f.kill(m, by: f.id(a))
        // 2 人 → 95 × 1.3 / 2
        XCTAssertEqual(f.hero(a).xp, 95 * 1.3 / 2, accuracy: 1e-9)
        XCTAssertEqual(f.hero(b).xp, 95 * 1.3 / 2, accuracy: 1e-9)
        XCTAssertEqual(f.hero(far).xp, 0)
        // Gold はラストヒットのみ
        XCTAssertEqual(f.hero(b).gold, goldB)
        XCTAssertEqual(f.hero(a).score.minionKills, 1)
        XCTAssertEqual(f.hero(b).score.minionKills, 0)
    }

    func testMinionKilledByMinionGivesXPButNoGold() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0]
        f.place(a, at: spot)
        let gold0 = f.hero(a).gold
        let killer = f.addMinion(.melee, team: .blue, at: spot)
        let m = f.addMinion(.ranged, team: .red, at: spot + Vec2(100, 0))
        f.kill(m, by: f.id(killer))
        XCTAssertEqual(f.hero(a).xp, 32, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).gold, gold0)
        XCTAssertEqual(f.hero(a).score.minionKills, 0)
    }

    func testDeadHeroesDoNotShareXP() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0], b = f.heroes(.blue)[1]
        f.place(a, at: spot)
        f.place(b, at: spot)
        f.s.units[b].isAlive = false
        f.s.units[b].hero!.respawnTimer = 10
        let m = f.addMinion(.melee, team: .red, at: spot)
        f.kill(m, by: f.id(a))
        XCTAssertEqual(f.hero(a).xp, 60, accuracy: 1e-9)
        XCTAssertEqual(f.hero(b).xp, 0)
    }

    func testLevelUpGrantsSkillPointsAndEvents() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        f.s.units[a].hero!.autoLevelSkills = false
        let hp1 = f.s.units[a].stats.maxHP
        f.s.events.removeAll()
        HeroGrowth.grantXP(&f.s, f.ctx, heroIndex: a, amount: 240 + 270 + 10)
        XCTAssertEqual(f.hero(a).level, 3)
        XCTAssertEqual(f.hero(a).xp, 10, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).skillPoints, 3)
        let levels = f.s.events.compactMap { e -> Int? in
            if case .levelUp(_, let lv) = e { return lv } else { return nil }
        }
        XCTAssertEqual(levels, [2, 3])
        XCTAssertGreaterThan(f.s.units[a].stats.maxHP, hp1)

        // 最大レベルで XP は 0 に固定
        HeroGrowth.grantXP(&f.s, f.ctx, heroIndex: a, amount: 100_000)
        XCTAssertEqual(f.hero(a).level, Balance.maxLevel)
        XCTAssertEqual(f.hero(a).xp, 0)
        XCTAssertEqual(f.hero(a).skillPoints, Balance.maxLevel)
        HeroGrowth.grantXP(&f.s, f.ctx, heroIndex: a, amount: 500)
        XCTAssertEqual(f.hero(a).xp, 0)
    }

    func testSkillLevelingRules() {
        let f = EconomyFixture.standard()
        var h = f.hero(f.heroes(.blue)[0])
        h.level = 3
        h.skillPoints = 5
        h.skillRanks = [1, 2, 0, 0]
        // 基本スキルは (Lv+1)/2 = 2 まで、Ult は Lv4 から
        XCTAssertFalse(SkillLeveling.canLevel(h, slot: .skill1))
        XCTAssertTrue(SkillLeveling.canLevel(h, slot: .skill2))
        XCTAssertFalse(SkillLeveling.canLevel(h, slot: .ultimate))
        XCTAssertFalse(SkillLeveling.canLevel(h, slot: .passive))
        h.level = 4
        XCTAssertTrue(SkillLeveling.canLevel(h, slot: .ultimate))
        h.skillRanks[3] = 1
        XCTAssertFalse(SkillLeveling.canLevel(h, slot: .ultimate))
        h.level = 8
        XCTAssertTrue(SkillLeveling.canLevel(h, slot: .ultimate))
        h.level = 15
        h.skillRanks = [1, 4, 4, 3]
        for slot in SkillSlot.actives { XCTAssertFalse(SkillLeveling.canLevel(h, slot: slot)) }
        h.skillPoints = 0
        h.skillRanks = [1, 0, 0, 0]
        XCTAssertFalse(SkillLeveling.canLevel(h, slot: .skill1))
    }

    func testAutoLevelOrder() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        f.s.units[a].hero!.autoLevelSkills = true
        HeroGrowth.applyMatchStart(&f.s, f.ctx)
        XCTAssertEqual(f.hero(a).skillRanks, [1, 1, 0, 0])
        XCTAssertEqual(f.hero(a).skillPoints, 0)
        HeroGrowth.grantXP(&f.s, f.ctx, heroIndex: a, amount: HeroGrowth.totalXP(toReach: 4))
        XCTAssertEqual(f.hero(a).level, 4)
        XCTAssertEqual(f.hero(a).skillRanks, [1, 2, 1, 1])
        HeroGrowth.grantXP(&f.s, f.ctx, heroIndex: a, amount: HeroGrowth.xpToNext(level: 4))
        XCTAssertEqual(f.hero(a).skillRanks, [1, 3, 1, 1])
        XCTAssertEqual(f.hero(a).skillPoints, 0)
        // applyMatchStart は冪等
        HeroGrowth.applyMatchStart(&f.s, f.ctx)
        XCTAssertEqual(f.hero(a).skillPoints, 0)
        XCTAssertEqual(HeroGrowth.spentSkillPoints(f.hero(a)), 5)
    }

    func testPracticeStartLevelAppliedOnFirstTick() {
        let opts = PracticeOptions(infiniteGold: true, spawnMinions: false, spawnDummies: false, startLevel: 6)
        let cfg = MatchFactory.practiceMatch(humanHeroID: "H001", humanName: "P", options: opts, seed: 5)
        let sim = Simulation(config: cfg)
        sim.step()
        let u = sim.state.units[sim.state.humanHeroIndex!]
        let h = u.hero!
        XCTAssertEqual(h.level, 6)
        XCTAssertEqual(HeroGrowth.spentSkillPoints(h) + h.skillPoints, 6)
        // 自動習得（既定 ON）で全ポイント消費、Ult 習得済み
        XCTAssertEqual(h.skillPoints, 0)
        XCTAssertEqual(h.rank(.ultimate), 1)
        XCTAssertEqual(u.hp, u.stats.maxHP, accuracy: 1e-6)
        XCTAssertEqual(h.gold, Balance.Economy.practiceGold)
        let def = MasterData.shared.hero("H001")!
        XCTAssertEqual(u.stats.maxHP, HeroGrowth.baseStats(def: def, level: 6).maxHP, accuracy: 1e-6)
    }

    func testStandardMatchLearnsFirstSkillOnFirstTick() {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 4))
        sim.step()
        for i in sim.state.heroIndices {
            let h = sim.state.units[i].hero!
            XCTAssertEqual(h.level, 1)
            XCTAssertEqual(h.skillPoints, 0)
            XCTAssertEqual(h.rank(.skill1), 1)
        }
    }
}
