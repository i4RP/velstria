import XCTest
@testable import VelstriaCore

/// ヒーローキル: バウンティ・連続キル/死亡・シャットダウン・アシスト・告知（DESIGN §5, §8, §11）。
final class EconomyKillTests: XCTestCase {
    private let spot = Vec2(6000, 6000)

    private func setup() -> (EconomyFixture, blue: [Int], red: [Int]) {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let blue = f.heroes(.blue), red = f.heroes(.red)
        for i in blue + red { f.s.units[i].hero!.autoLevelSkills = false }
        return (f, blue, red)
    }

    func testBountyFormula() {
        XCTAssertEqual(DeathSystem.bounty(victimKillStreak: 0, victimDeathStreak: 0), 300)
        XCTAssertEqual(DeathSystem.bounty(victimKillStreak: 1, victimDeathStreak: 0), 300)
        XCTAssertEqual(DeathSystem.bounty(victimKillStreak: 2, victimDeathStreak: 0), 360)
        XCTAssertEqual(DeathSystem.bounty(victimKillStreak: 5, victimDeathStreak: 0), 540)
        XCTAssertEqual(DeathSystem.bounty(victimKillStreak: 9, victimDeathStreak: 0), 780)
        XCTAssertEqual(DeathSystem.bounty(victimKillStreak: 30, victimDeathStreak: 0), 780)
        XCTAssertEqual(DeathSystem.bounty(victimKillStreak: 0, victimDeathStreak: 1), 300)
        XCTAssertEqual(DeathSystem.bounty(victimKillStreak: 0, victimDeathStreak: 2), 255)
        XCTAssertEqual(DeathSystem.bounty(victimKillStreak: 0, victimDeathStreak: 3), 210)
        XCTAssertEqual(DeathSystem.bounty(victimKillStreak: 0, victimDeathStreak: 6), 100)
        XCTAssertEqual(DeathSystem.bounty(victimKillStreak: 0, victimDeathStreak: 20), 100)
        XCTAssertEqual(DeathSystem.assistGold(bounty: 300, assisters: 1), 150)
        XCTAssertEqual(DeathSystem.assistGold(bounty: 300, assisters: 2), 75)
        XCTAssertEqual(DeathSystem.assistGold(bounty: 300, assisters: 4), 40)
        XCTAssertEqual(DeathSystem.heroKillXP(victimLevel: 5), 250)
    }

    func testFirstBloodKill() {
        var (f, blue, red) = setup()
        let a = blue[0], v = red[0]
        f.place(a, at: spot)
        f.place(v, at: spot + Vec2(100, 0))
        f.s.units[v].hero!.level = 3
        let gold0 = f.hero(a).gold
        let ev = f.kill(v, by: f.id(a))

        XCTAssertEqual(f.hero(a).gold - gold0, 400)
        XCTAssertEqual(f.hero(a).score.goldEarned, 400)
        XCTAssertEqual(f.hero(a).xp, 190, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).score.kills, 1)
        XCTAssertEqual(f.hero(a).killStreak, 1)
        XCTAssertEqual(f.hero(v).score.deaths, 1)
        XCTAssertEqual(f.hero(v).deathStreak, 1)
        XCTAssertEqual(f.hero(v).respawnTimer, 10, accuracy: 1e-9)
        XCTAssertFalse(f.s.units[v].isAlive)
        XCTAssertEqual(f.s.teams[Team.blue.rawValue].kills, 1)
        XCTAssertTrue(f.s.firstBloodTaken)
        XCTAssertEqual(ev.announcements, [.firstBlood(killerID: f.id(a), victimID: f.id(v))])
        let k = ev.heroKills.first!
        XCTAssertEqual(k.killerID, f.id(a))
        XCTAssertEqual(k.bounty, 300)
        XCTAssertTrue(k.isFirstBlood)
        XCTAssertEqual(k.multiKill, 1)

        // 2 キル目は初キルボーナスなし
        let v2 = red[1]
        f.place(v2, at: spot)
        f.s.time += 30
        let gold1 = f.hero(a).gold
        let ev2 = f.kill(v2, by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold1, 300)
        XCTAssertFalse(ev2.heroKills.first!.isFirstBlood)
        XCTAssertTrue(ev2.announcements.isEmpty)
    }

    func testShutdownBountyAndStreakReset() {
        var (f, blue, red) = setup()
        f.s.firstBloodTaken = true
        let a = blue[0], v = red[0]
        f.s.units[v].hero!.killStreak = 4
        let gold0 = f.hero(a).gold
        let ev = f.kill(v, by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold0, 480)
        XCTAssertEqual(f.hero(v).killStreak, 0)
        XCTAssertTrue(ev.heroKills.first!.isShutdown)
        XCTAssertTrue(ev.announcements.contains(.shutdown(killerID: f.id(a), victimID: f.id(v))))
    }

    func testStreakOfTwoIsNotShutdown() {
        var (f, blue, red) = setup()
        f.s.firstBloodTaken = true
        f.s.units[red[0]].hero!.killStreak = 2
        let gold0 = f.hero(blue[0]).gold
        let ev = f.kill(red[0], by: f.id(blue[0]))
        XCTAssertEqual(f.hero(blue[0]).gold - gold0, 360)
        XCTAssertFalse(ev.heroKills.first!.isShutdown)
        XCTAssertTrue(ev.announcements.isEmpty)
    }

    func testDeathStreakReducesBountyAndKillResetsIt() {
        var (f, blue, red) = setup()
        f.s.firstBloodTaken = true
        let a = blue[0], v = red[0]
        f.s.units[v].hero!.deathStreak = 3
        let gold0 = f.hero(a).gold
        f.kill(v, by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold0, 210)
        XCTAssertEqual(f.hero(v).deathStreak, 4)
        // キラー側の連続死亡はキルでリセット
        f.s.units[a].hero!.deathStreak = 5
        f.s.time += 30
        f.kill(red[1], by: f.id(a))
        XCTAssertEqual(f.hero(a).deathStreak, 0)
    }

    func testAssistGoldSplitAndXPShare() {
        var (f, blue, red) = setup()
        f.s.firstBloodTaken = true
        let a = blue[0], b = blue[1], c = blue[2], stale = blue[3], v = red[0]
        f.place(v, at: spot)
        f.place(a, at: spot)
        f.place(b, at: spot + Vec2(500, 0))
        f.place(c, at: spot + Vec2(2000, 0))     // XP 範囲外
        f.place(stale, at: spot)
        f.addDamager(victim: v, source: stale, secondsAgo: 11)   // 窓の外
        f.addDamager(victim: v, source: b, secondsAgo: 4)
        f.addDamager(victim: v, source: c, secondsAgo: 2)
        f.addDamager(victim: v, source: a, secondsAgo: 0.1)
        let g = [a, b, c, stale].map { f.hero($0).gold }
        let ev = f.kill(v, by: f.id(a))

        let k = ev.heroKills.first!
        XCTAssertEqual(k.assistIDs, [f.id(b), f.id(c)].sorted())
        XCTAssertEqual(f.hero(a).gold - g[0], 300)
        XCTAssertEqual(f.hero(b).gold - g[1], 75)
        XCTAssertEqual(f.hero(c).gold - g[2], 75)
        XCTAssertEqual(f.hero(stale).gold - g[3], 0)
        XCTAssertEqual(f.hero(b).score.assists, 1)
        XCTAssertEqual(f.hero(c).score.assists, 1)
        XCTAssertEqual(f.hero(stale).score.assists, 0)
        // XP: キラー 130、範囲内のアシスト（b のみ）が 60% を独占
        XCTAssertEqual(f.hero(a).xp, 130, accuracy: 1e-9)
        XCTAssertEqual(f.hero(b).xp, 78, accuracy: 1e-9)
        XCTAssertEqual(f.hero(c).xp, 0)
        // 被害者のアシスト記録は消去される
        XCTAssertTrue(f.hero(v).recentDamagers.isEmpty)
    }

    func testMinimumAssistGold() {
        var (f, blue, red) = setup()
        f.s.firstBloodTaken = true
        let v = red[0]
        for i in blue[1...4] { f.addDamager(victim: v, source: i, secondsAgo: 1) }
        let g = f.hero(blue[4]).gold
        let ev = f.kill(v, by: f.id(blue[0]))
        XCTAssertEqual(ev.heroKills.first!.assistIDs.count, 4)
        XCTAssertEqual(f.hero(blue[4]).gold - g, 40)
    }

    func testSupporterAssists() {
        var (f, blue, red) = setup()
        f.s.firstBloodTaken = true
        let a = blue[0], healer = blue[1], shielder = blue[2], tank = blue[3], v = red[0]
        // キラーを回復したヒーロー
        f.addSupporter(target: a, supporter: healer, secondsAgo: 3)
        // 被害者に攻撃されていた味方をシールドしたヒーロー
        f.s.units[tank].hero!.recentDamagers.append(DamageRecord(sourceID: f.id(v), time: f.s.time - 2))
        f.addSupporter(target: tank, supporter: shielder, secondsAgo: 2)
        let ev = f.kill(v, by: f.id(a))
        XCTAssertEqual(ev.heroKills.first!.assistIDs, [f.id(healer), f.id(shielder)].sorted())
        XCTAssertEqual(f.hero(tank).score.assists, 0)
    }

    func testKillCreditedToLastHeroDamagerWhenTowerFinishes() {
        var (f, blue, red) = setup()
        f.s.firstBloodTaken = true
        let a = blue[0], b = blue[1], v = red[0]
        let tower = f.tower(team: .blue, lane: .mid, tier: .outer)
        f.addDamager(victim: v, source: a, secondsAgo: 6)
        f.addDamager(victim: v, source: b, secondsAgo: 2)
        let gb = f.hero(b).gold, ga = f.hero(a).gold
        let ev = f.kill(v, by: f.id(tower))
        let k = ev.heroKills.first!
        XCTAssertEqual(k.killerID, f.id(b))
        XCTAssertEqual(k.assistIDs, [f.id(a)])
        XCTAssertEqual(f.hero(b).gold - gb, 300)
        XCTAssertEqual(f.hero(a).gold - ga, 150)
        XCTAssertEqual(f.hero(b).score.kills, 1)
        // unitDied は実際の止め（タワー）を示す
        XCTAssertTrue(ev.contains(.unitDied(unitID: f.id(v), kind: .hero, team: .red, killerID: f.id(tower),
                                            pos: f.s.units[v].pos)))
    }

    func testExecutedDeathGivesNoRewards() {
        var (f, blue, red) = setup()
        let v = red[0]
        let tower = f.tower(team: .blue, lane: .mid, tier: .outer)
        f.addDamager(victim: v, source: blue[0], secondsAgo: 12)   // 窓の外
        let golds = blue.map { f.hero($0).gold }
        let ev = f.kill(v, by: f.id(tower))
        let k = ev.heroKills.first!
        XCTAssertNil(k.killerID)
        XCTAssertEqual(k.bounty, 0)
        XCTAssertEqual(blue.map { f.hero($0).gold }, golds)
        XCTAssertEqual(f.hero(v).score.deaths, 1)
        XCTAssertEqual(f.hero(v).deathStreak, 1)
        XCTAssertEqual(f.s.teams[Team.blue.rawValue].kills, 0)
        XCTAssertFalse(f.s.firstBloodTaken)
    }

    func testMultiKillAndKillingSpree() {
        var (f, blue, red) = setup()
        let a = blue[0]
        var anns: [Announcement] = []
        for (n, v) in red.prefix(3).enumerated() {
            f.s.time = 300 + Double(n) * 4
            anns += f.kill(v, by: f.id(a)).announcements
        }
        XCTAssertTrue(anns.contains(.multiKill(killerID: f.id(a), count: 2)))
        XCTAssertTrue(anns.contains(.multiKill(killerID: f.id(a), count: 3)))
        XCTAssertTrue(anns.contains(.killingSpree(killerID: f.id(a), streak: 3)))
        XCTAssertEqual(f.hero(a).score.largestMultiKill, 3)
        XCTAssertEqual(f.hero(a).score.largestKillStreak, 3)

        // 10 秒を超えるとマルチキルはリセット
        f.s.time += 11
        let ev = f.kill(red[3], by: f.id(a))
        XCTAssertEqual(ev.heroKills.first!.multiKill, 1)
        XCTAssertFalse(ev.announcements.contains { if case .multiKill = $0 { return true } else { return false } })
        XCTAssertEqual(f.hero(a).killStreak, 4)
    }

    func testAceAnnouncedOncePerWipe() {
        var (f, blue, red) = setup()
        f.s.firstBloodTaken = true
        for v in red.prefix(4) { f.kill(v, by: f.id(blue[0])) }
        f.s.time += 1
        // 最後の 1 人ともう 1 件を同 tick に処理しても 1 回だけ
        f.markDead(red[4], by: f.id(blue[1]))
        let ev = f.processDeaths()
        XCTAssertEqual(ev.announcements.filter { $0 == .ace(team: .blue) }.count, 1)
        XCTAssertEqual(f.s.teams[Team.blue.rawValue].lastAceTime, f.s.time)
        // 同じ全滅中に再度処理しても告知しない
        XCTAssertTrue(f.processDeaths().announcements.isEmpty)
    }

    func testDeadHeroNotProcessedTwice() {
        var (f, blue, red) = setup()
        let v = red[0]
        f.markDead(v, by: f.id(blue[0]))
        f.markDead(v, by: f.id(blue[1]))
        f.processDeaths()
        XCTAssertEqual(f.hero(v).score.deaths, 1)
        XCTAssertEqual(f.hero(blue[0]).score.kills + f.hero(blue[1]).score.kills, 1)
    }

    func testRespawnRestoresHeroAtFountain() {
        var (f, blue, red) = setup()
        let v = red[0]
        f.place(v, at: spot)
        f.s.units[v].statuses.append(StatusEffect(kind: .slow, duration: 30, magnitude: 0.3))
        f.kill(v, by: f.id(blue[0]))
        let t = f.hero(v).respawnTimer
        XCTAssertEqual(t, RespawnSystem.respawnTime(level: 1, time: f.s.time), accuracy: 1e-9)
        var respawned = false
        for _ in 0..<Int((t / Balance.dt).rounded() + 2) {
            f.s.events.removeAll()
            RespawnSystem.update(&f.s, f.ctx)
            if f.s.events.contains(where: { if case .respawned = $0 { return true } else { return false } }) {
                respawned = true
                break
            }
        }
        XCTAssertTrue(respawned)
        let u = f.s.units[v]
        XCTAssertTrue(u.isAlive)
        XCTAssertEqual(u.hp, u.stats.maxHP, accuracy: 1e-9)
        XCTAssertTrue(u.statuses.isEmpty)
        XCTAssertTrue(f.ctx.map.isInFountain(u.pos, team: .red))
    }

    func testRespawnFormula() {
        XCTAssertEqual(RespawnSystem.respawnTime(level: 1, time: 60), 6)
        XCTAssertEqual(RespawnSystem.respawnTime(level: 10, time: 60), 24)
        XCTAssertEqual(RespawnSystem.respawnTime(level: 10, time: 13 * 60), 30)
        XCTAssertEqual(RespawnSystem.respawnTime(level: 15, time: 20 * 60), 40)
    }
}
