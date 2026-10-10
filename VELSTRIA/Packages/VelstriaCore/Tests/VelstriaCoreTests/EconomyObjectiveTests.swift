import XCTest
@testable import VelstriaCore

/// タワー・中立モンスター・ボスの報酬（DESIGN §4, §8）。
final class EconomyObjectiveTests: XCTestCase {
    private let spot = Vec2(6000, 6000)

    func testTowerGoldForLastHitterAndTeam() {
        var f = EconomyFixture.standard()
        let blue = f.heroes(.blue)
        let a = blue[0]
        let t = f.tower(team: .red, lane: .mid, tier: .outer)
        let golds = blue.map { f.hero($0).gold }
        let ev = f.kill(t, by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - golds[0], 270)
        for (n, i) in blue.enumerated().dropFirst() {
            XCTAssertEqual(f.hero(i).gold - golds[n], 120)
        }
        XCTAssertEqual(f.hero(a).score.towersDestroyed, 1)
        XCTAssertEqual(f.s.teams[Team.blue.rawValue].towersDestroyed, 1)
        XCTAssertEqual(f.s.teams[Team.red.rawValue].towersDestroyed, 0)
        XCTAssertEqual(ev.announcements, [.towerDestroyed(team: .red, lane: .mid, tier: .outer)])
        XCTAssertTrue(ev.contains { if case .structureDestroyed(_, .tower, .red, .mid, .outer, _) = $0 { return true }
            return false })
    }

    func testTowerKilledByMinionGivesTeamGoldOnly() {
        var f = EconomyFixture.standard()
        let blue = f.heroes(.blue)
        let m = f.addMinion(.siege, team: .blue, at: spot)
        let t = f.tower(team: .red, lane: .top, tier: .outer)
        let golds = blue.map { f.hero($0).gold }
        f.kill(t, by: f.id(m))
        for (n, i) in blue.enumerated() { XCTAssertEqual(f.hero(i).gold - golds[n], 120) }
        XCTAssertEqual(blue.reduce(0) { $0 + f.hero($1).score.towersDestroyed }, 0)
    }

    func testCoreVulnerableOnlyOnFirstBaseTower() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        let top = f.tower(team: .red, lane: .top, tier: .base)
        let mid = f.tower(team: .red, lane: .mid, tier: .base)
        let ev1 = f.kill(top, by: f.id(a))
        XCTAssertTrue(ev1.announcements.contains(.coreVulnerable(team: .red)))
        let ev2 = f.kill(mid, by: f.id(a))
        XCTAssertFalse(ev2.announcements.contains(.coreVulnerable(team: .red)))
        // 同 tick に複数の基部塔が落ちても告知は 1 回
        var g = EconomyFixture.standard()
        g.markDead(g.tower(team: .blue, lane: .top, tier: .base), by: nil)
        g.markDead(g.tower(team: .blue, lane: .bot, tier: .base), by: nil)
        let ev3 = g.processDeaths()
        XCTAssertEqual(ev3.announcements.filter { $0 == .coreVulnerable(team: .blue) }.count, 1)
    }

    func testCoreDestructionDoesNotCountAsTower() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        let gold = f.hero(a).gold
        let ev = f.kill(f.core(.red), by: f.id(a))
        XCTAssertEqual(f.hero(a).gold, gold)
        XCTAssertEqual(f.s.teams[Team.blue.rawValue].towersDestroyed, 0)
        XCTAssertTrue(ev.contains { if case .structureDestroyed(_, .core, .red, _, _, _) = $0 { return true }
            return false })
        MatchFlowSystem.update(&f.s, f.ctx)
        XCTAssertEqual(f.s.phase, .ended)
        XCTAssertEqual(f.s.winner, .blue)
        XCTAssertEqual(f.s.endReason, .coreDestroyed)
    }

    func testSentinelGivesBuffGoldAndXP() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0]
        f.place(a, at: spot)
        let gold = f.hero(a).gold
        let m = f.addMonster(.blueSentinel, at: spot)
        let ev = f.kill(m, by: f.id(a))
        // 蒼晶の番人 90（仔 20 と合わせて 110）、XP は Patch 2.1.88 に合わせて小さい（小キャンプの主が多い）
        XCTAssertEqual(f.hero(a).gold - gold, 90)
        XCTAssertEqual(f.hero(a).xp, 35, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).score.monsterKills, 1)
        XCTAssertEqual(f.hero(a).score.objectivesTaken, 1)
        let buff = f.s.units[a].status(.blueBuff)
        XCTAssertNotNil(buff)
        XCTAssertEqual(buff?.remaining ?? 0, Balance.Economy.sentinelBuffDuration, accuracy: 1e-9)
        XCTAssertTrue(ev.contains(.objectiveTaken(kind: .blueSentinel, team: .blue, killerID: f.id(a))))

        let r = f.addMonster(.redSentinel, at: spot)
        f.kill(r, by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold, 90 + 110)
        // 赤バフの貫通はロールで決まる（後衛 10% / 前衛 5%）
        let pen = JungleBuffs.isFrontline(f.hero(a).role) ? Balance.Jungle.redFrontPenetration : Balance.Jungle.redBackPenetration
        XCTAssertEqual(f.s.units[a].status(.redBuff)?.magnitude ?? 0, pen, accuracy: 1e-9)
    }

    func testJungleBlessingIncreasesMonsterGold() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0]
        f.place(a, at: spot)
        // ジャングルの祝福（靴に付ける）: スピードブーツ + 炎撃の狩猟
        f.s.units[a].hero!.spells = [Balance.Economy.smiteSpellID, "BS01"]
        f.s.units[a].hero!.items = [Balance.Gear.baseBootsID]
        f.s.units[a].hero!.itemInvested = [250]
        f.s.units[a].hero!.gear = GearState(option: .flame)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.monsterGoldBonus, 0.2, accuracy: 1e-9)
        let gold = f.hero(a).gold
        f.kill(f.addMonster(.campLarge, at: spot), by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold, 48)
        f.kill(f.addMonster(.campSmall, at: spot), by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold, 48 + 18)
        XCTAssertEqual(f.hero(a).xp, 80, accuracy: 1e-9)
    }

    func testWyrmRewardsWholeTeam() {
        var f = EconomyFixture.standard()
        let blue = f.heroes(.blue)
        let a = blue[0], dead = blue[4]
        f.s.units[dead].isAlive = false
        f.s.units[dead].hero!.respawnTimer = 20
        for i in blue { f.s.units[i].hero!.autoLevelSkills = false }
        let golds = blue.map { f.hero($0).gold }
        let w = f.addMonster(.astralWyrm, at: Vec2(8300, 3700))
        let ev = f.kill(w, by: f.id(a))
        // 1 体目はチーム全員に 60 Gold と 200 XP（MLBB: 60 / 70 / 80）
        for (n, i) in blue.enumerated() {
            XCTAssertEqual(f.hero(i).gold - golds[n], 60)
            XCTAssertEqual(f.hero(i).xp, 200, accuracy: 1e-9)
        }
        // 撃破者: 加護 120 秒と 400 + 40×Lv のシールド。生存している味方: 200 + 20×Lv の一度きりのシールド
        let level = Double(f.hero(a).level)
        XCTAssertEqual(f.s.units[a].status(.wyrmBlessing)?.remaining ?? 0, 120, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[a].shields.first { $0.tag == JungleBuffs.wyrmShieldTag }?.amount ?? 0,
                       400 + 40 * level, accuracy: 1e-9)
        for i in blue.dropFirst().prefix(3) {
            XCTAssertNil(f.s.units[i].status(.wyrmBlessing))
            let lv = Double(f.hero(i).level)
            XCTAssertEqual(f.s.units[i].shields.first { $0.tag == JungleBuffs.wyrmAllyShieldTag }?.amount ?? 0,
                           200 + 20 * lv, accuracy: 1e-9)
        }
        XCTAssertNil(f.s.units[dead].status(.wyrmBlessing))
        XCTAssertTrue(f.s.units[dead].shields.isEmpty)
        XCTAssertEqual(f.s.teams[Team.blue.rawValue].wyrmKills, 1)
        XCTAssertEqual(f.hero(a).score.objectivesTaken, 1)
        XCTAssertTrue(ev.announcements.contains(.wyrmSlain(team: .blue)))
        XCTAssertTrue(ev.contains(.objectiveTaken(kind: .astralWyrm, team: .blue, killerID: f.id(a))))
        // 赤チームには何もない
        XCTAssertTrue(f.heroes(.red).allSatisfy { f.hero($0).xp == 0 })
        // 2 体目は 70、3 体目以降は 80
        let g2 = f.hero(a).gold
        f.kill(f.addMonster(.astralWyrm, at: Vec2(8300, 3700)), by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - g2, 70)
        let g3 = f.hero(a).gold
        f.kill(f.addMonster(.astralWyrm, at: Vec2(8300, 3700)), by: f.id(a))
        f.kill(f.addMonster(.astralWyrm, at: Vec2(8300, 3700)), by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - g3, 160)
    }

    func testColossusRewardsAndEmpoweredRecall() {
        var f = EconomyFixture.standard()
        let red = f.heroes(.red)
        for i in red { f.s.units[i].hero!.autoLevelSkills = false }
        let golds = red.map { f.hero($0).gold }
        let c = f.addMonster(.ancientColossus, at: Vec2(3700, 8300))
        let ev = f.kill(c, by: f.id(red[2]))
        for (n, i) in red.enumerated() {
            XCTAssertEqual(f.hero(i).gold - golds[n], 300)
            XCTAssertEqual(f.hero(i).level, 2)   // 300 XP → Lv2 + 40
            XCTAssertEqual(f.s.units[i].status(.colossusBlessing)?.remaining ?? 0, 180, accuracy: 1e-9)
        }
        XCTAssertEqual(f.s.teams[Team.red.rawValue].colossusKills, 1)
        XCTAssertTrue(ev.announcements.contains(.colossusSlain(team: .red)))
        XCTAssertEqual(RecallSystem.recallDuration(f.s.units[red[0]]), Balance.empoweredRecallChannel)
        XCTAssertEqual(RecallSystem.recallDuration(f.s.units[f.heroes(.blue)[0]]), Balance.recallChannel)
    }

    func testCampXPSharedWithGroupBonus() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.red)[0], b = f.heroes(.red)[1]
        f.place(a, at: spot)
        f.place(b, at: spot)
        f.kill(f.addMonster(.campLarge, at: spot), by: f.id(a))
        XCTAssertEqual(f.hero(a).xp, 50 * 1.3 / 2, accuracy: 1e-9)
        XCTAssertEqual(f.hero(b).xp, 50 * 1.3 / 2, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).score.monsterKills, 1)
    }
}
