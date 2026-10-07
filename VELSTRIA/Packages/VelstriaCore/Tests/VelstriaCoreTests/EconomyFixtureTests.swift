import XCTest
@testable import VelstriaCore

/// 経済系テスト用の試合状態（Simulation を介さずシステムを直接呼ぶ）。
struct EconomyFixture {
    var s: SimState
    let ctx: SimContext

    init(config: MatchConfig) {
        ctx = SimContext(master: .shared, config: config)
        s = SimState(config: config)
        SpawnSystem.setupMatch(&s, ctx)
        for i in s.units.indices { StatCalculator.recompute(&s, i, ctx) }
        s.phase = .playing
        s.tick = 9000
        s.time = 300
    }

    /// 人間 1 人（Blue）+ AI 9 人の 5v5。
    static func standard(seed: UInt64 = 11) -> EconomyFixture {
        EconomyFixture(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "Tester", seed: seed))
    }

    var master: MasterData { ctx.master }

    func heroes(_ team: Team) -> [Int] { s.heroIndices(team: team) }
    func id(_ i: Int) -> EntityID { s.units[i].id }
    func hero(_ i: Int) -> HeroData { s.units[i].hero! }
    var human: Int { s.humanHeroIndex! }

    /// 全ヒーローを各自の泉へ退避させ、XP 共有範囲の影響を消す。
    mutating func parkHeroesAtFountains() {
        for i in s.heroIndices {
            s.units[i].pos = ctx.map.fountain(s.units[i].team)
        }
    }

    mutating func place(_ i: Int, at p: Vec2) { s.units[i].pos = p }

    mutating func addDamager(victim v: Int, source: Int, secondsAgo: Double) {
        s.units[v].hero!.recentDamagers.append(DamageRecord(sourceID: id(source), time: s.time - secondsAgo))
    }

    mutating func addSupporter(target t: Int, supporter: Int, secondsAgo: Double) {
        s.units[t].hero!.recentSupporters.append(DamageRecord(sourceID: id(supporter), time: s.time - secondsAgo))
    }

    /// 死亡を積む（CombatSystem と同じ状態遷移）。
    mutating func markDead(_ v: Int, by killerID: EntityID?) {
        s.units[v].hp = 0
        s.units[v].isAlive = false
        s.units[v].deathTime = s.time
        s.pendingDeaths.append(PendingDeath(victimID: s.units[v].id, killerID: killerID, time: s.time))
    }

    /// 死亡処理を実行し、その間に発行されたイベントを返す。
    @discardableResult
    mutating func processDeaths() -> [SimEvent] {
        s.events.removeAll()
        DeathSystem.process(&s, ctx)
        return s.events
    }

    @discardableResult
    mutating func kill(_ v: Int, by killerID: EntityID?) -> [SimEvent] {
        markDead(v, by: killerID)
        return processDeaths()
    }

    @discardableResult
    mutating func addMinion(_ type: MinionType, team: Team, at p: Vec2, lane: Lane = .mid) -> Int {
        var u = Unit(id: 0, kind: .minion, team: team, pos: p, radius: 36, stats: Stats())
        u.minion = MinionData(type: type, lane: lane, spawnTime: 0)
        let mid = s.addUnit(u)
        return s.index(of: mid)!
    }

    @discardableResult
    mutating func addMonster(_ kind: MonsterKind, at p: Vec2) -> Int {
        var u = Unit(id: 0, kind: .monster, team: .neutral, pos: p, radius: 80, stats: Stats())
        u.monster = MonsterData(kind: kind, campID: 0, home: p)
        let mid = s.addUnit(u)
        return s.index(of: mid)!
    }

    func tower(team: Team, lane: Lane, tier: TowerTier) -> Int {
        s.units.indices.first {
            s.units[$0].kind == .tower && s.units[$0].team == team
                && s.units[$0].tower?.lane == lane && s.units[$0].tower?.tier == tier
        }!
    }

    func core(_ team: Team) -> Int {
        s.units.indices.first { s.units[$0].kind == .core && s.units[$0].team == team }!
    }

    /// 1 tick 進めて EconomySystem を呼ぶ。
    mutating func economyTick() {
        s.tick += 1
        s.time = Double(s.tick) * Balance.dt
        EconomySystem.update(&s, ctx)
    }
}

extension Array where Element == SimEvent {
    var announcements: [Announcement] {
        compactMap { if case .announcement(let a) = $0 { return a } else { return nil } }
    }

    var heroKills: [HeroKillEvent] {
        compactMap { if case .heroKilled(let k) = $0 { return k } else { return nil } }
    }

    func goldGained(by id: EntityID) -> Double {
        reduce(0) { acc, e in
            if case .goldGained(let h, let amount, _) = e, h == id { return acc + amount }
            return acc
        }
    }

    var purchaseFailures: [String] {
        compactMap { if case .purchaseFailed(_, _, let r) = $0 { return r } else { return nil } }
    }
}

/// フィクスチャ自体の前提確認。
final class EconomyFixtureTests: XCTestCase {
    func testFixtureHasFiveHeroesPerTeam() {
        let f = EconomyFixture.standard()
        XCTAssertEqual(f.heroes(.blue).count, 5)
        XCTAssertEqual(f.heroes(.red).count, 5)
        XCTAssertNotNil(f.s.humanHeroIndex)
        XCTAssertEqual(f.s.units[f.human].team, .blue)
    }
}
