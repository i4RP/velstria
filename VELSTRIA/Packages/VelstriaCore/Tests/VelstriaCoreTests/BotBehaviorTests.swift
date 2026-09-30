import XCTest
@testable import VelstriaCore

/// ボットの個別の振る舞い（状態を組み立てて 1 回の意思決定を検査する）。
struct BotFixture {
    var s: SimState
    let ctx: SimContext

    init(config: MatchConfig, time: Double = 300) {
        ctx = SimContext(master: .shared, config: config)
        s = SimState(config: config)
        SpawnSystem.setupMatch(&s, ctx)
        for i in s.units.indices { StatCalculator.recompute(&s, i, ctx) }
        s.phase = .playing
        s.tick = Int((time * Balance.tickRate).rounded())
        s.time = time
        HeroGrowth.applyMatchStart(&s, ctx)
        BotAI.initialize(&s, ctx)
    }

    static func bots(_ difficulty: Difficulty = .normal, seed: UInt64 = 5, time: Double = 300) -> BotFixture {
        BotFixture(config: MatchFactory.botMatch(difficulty: difficulty, seed: seed), time: time)
    }

    func hero(_ team: Team, _ position: LanePosition) -> Int {
        s.heroIndices(team: team).first { s.units[$0].hero?.position == position }!
    }

    func slot(of i: Int) -> Int { s.bots.heroes.firstIndex { $0.heroID == s.units[i].id }! }
    func memory(_ i: Int) -> BotHeroMemory { s.bots.heroes[slot(of: i)] }

    mutating func place(_ i: Int, at p: Vec2) {
        s.units[i].pos = p
        s.units[i].prevPos = p
    }

    mutating func advance(_ seconds: Double) {
        s.tick += Int((seconds * Balance.tickRate).rounded())
        s.time = Double(s.tick) * Balance.dt
    }

    /// 視界とチームの情報を今の配置で更新する。
    mutating func refreshVision() {
        VisionSystem.update(&s, ctx)
        BotAI.updateIntel(&s, ctx)
    }

    /// ヒーロー i の意思決定を 1 回行い、発行したコマンドを返す。
    mutating func decide(_ i: Int) -> [PlayerCommand] {
        var out: [HeroCommand] = []
        let w = BotWorld(s, ctx)
        BotAI.decide(&s, ctx, w, unit: i, slot: slot(of: i), out: &out)
        return out.map(\.command)
    }

    /// 全ヒーローを各自の泉へ（邪魔な視界・脅威を消す）。
    mutating func parkAllHeroes() {
        for i in s.heroIndices { place(i, at: ctx.map.fountain(s.units[i].team)) }
    }

    @discardableResult
    mutating func addMinion(_ type: MinionType, team: Team, lane: Lane, at p: Vec2, hp: Double? = nil) -> Int {
        let id = s.addUnit(UnitFactory.makeMinion(type: type, team: team, lane: lane, pos: p, time: s.time))
        let i = s.index(of: id)!
        if let hp { s.units[i].hp = hp }
        return i
    }
}

extension Array where Element == PlayerCommand {
    func attackTarget() -> EntityID? {
        for c in self { if case .attack(let id) = c { return id } }
        return nil
    }

    func moveGoal() -> Vec2? {
        for c in self { if case .moveTo(let p) = c { return p } }
        return nil
    }

    var recalls: Bool { contains { if case .recall = $0 { return true } else { return false } } }

    var purchases: [String] {
        compactMap { if case .buyItem(let id) = $0 { return id } else { return nil } }
    }
}

final class BotBehaviorTests: XCTestCase {

    // MARK: - 状態・スケジュール

    func testBotStateHasOneMemoryPerHeroInEntityOrder() {
        var f = BotFixture(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "Human", seed: 9))
        f.refreshVision()
        let ids = f.s.heroIndices.map { f.s.units[$0].id }
        XCTAssertEqual(f.s.bots.heroes.map(\.heroID), ids.sorted())
        XCTAssertEqual(f.s.bots.teams.count, 2)
        XCTAssertEqual(f.s.bots.teams[0].enemyIDs.count, 5)
        let human = f.s.humanHeroID!
        for m in f.s.bots.heroes {
            XCTAssertEqual(m.isBot, m.heroID != human)
            XCTAssertEqual(m.lane, BotAI.lane(for: m.position))
        }
    }

    func testDecisionsRunAtFiveHertzStaggeredPerBot() {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 3))
        sim.step()
        var perTick: [Int] = []
        var before = sim.state.bots.heroes.map(\.lastDecisionTick)
        var counts = [Int](repeating: 0, count: before.count)
        for _ in 0..<60 {
            sim.step()
            let now = sim.state.bots.heroes.map(\.lastDecisionTick)
            var n = 0
            for k in now.indices where now[k] != before[k] {
                counts[k] += 1
                n += 1
            }
            perTick.append(n)
            before = now
        }
        // 2 秒 = 60 tick で各ボット 10 回（5Hz）、1 tick に集中しない
        XCTAssertEqual(counts, [Int](repeating: 10, count: counts.count))
        XCTAssertLessThanOrEqual(perTick.max() ?? 0, 2)
    }

    func testPracticeModeProducesNoBotCommands() {
        let cfg = MatchFactory.practiceMatch(humanHeroID: "H001", humanName: "P", options: PracticeOptions(), seed: 1)
        let sim = Simulation(config: cfg)
        for _ in 0..<90 { sim.step() }
        var s = sim.state
        XCTAssertTrue(BotAI.generateCommands(&s, sim.ctx).isEmpty)
    }

    // MARK: - 知覚（反応遅延・視界）

    func testReactionDelayIgnoresNewlyVisibleThreatUntilItPasses() {
        for (difficulty, delay) in [(Difficulty.easy, 0.6), (.hard, 0.15)] {
            var f = BotFixture.bots(difficulty)
            f.parkAllHeroes()
            let me = f.hero(.blue, .mid)
            let foe = f.hero(.red, .mid)
            f.place(me, at: Vec2(5200, 5200))
            f.place(foe, at: Vec2(5450, 5450))
            f.s.units[me].hp = f.s.units[me].stats.maxHP * 0.2
            f.refreshVision()
            XCTAssertTrue(f.s.isVisible(foe, to: .blue))
            // 見えた直後は脅威に反応しない（体力が少ないので帰還しようとする）
            f.advance(delay * 0.5)
            BotAI.updateIntel(&f.s, f.ctx)
            let early = f.decide(me)
            XCTAssertNotEqual(f.memory(me).goal, .retreat, "\(difficulty)")
            XCTAssertTrue(early.recalls || f.memory(me).goal == .recall, "\(difficulty) \(early)")
            // 反応時間を過ぎたら撤退する
            f.advance(delay + 0.1)
            BotAI.updateIntel(&f.s, f.ctx)
            _ = f.decide(me)
            XCTAssertEqual(f.memory(me).goal, .retreat, "\(difficulty)")
        }
    }

    func testInvisibleEnemiesAreNeverTargeted() {
        var f = BotFixture.bots(.hard)
        f.parkAllHeroes()
        let me = f.hero(.blue, .top)
        let foe = f.hero(.red, .top)
        f.place(me, at: Vec2(1400, 7600))
        f.place(foe, at: Vec2(1400, 7900))
        f.s.units[foe].hp = 50
        f.refreshVision()
        // 霧の中（視界ビットなし）にする
        f.s.units[foe].visibleMask = Team.red.visionBit
        f.s.bots.teams[0].visibleSince = f.s.bots.teams[0].visibleSince.map { _ in -1 }
        f.s.bots.teams[0].lastSeenTime = f.s.bots.teams[0].lastSeenTime.map { _ in -999 }
        f.advance(1)
        let cmds = f.decide(me)
        XCTAssertNotEqual(cmds.attackTarget(), f.s.units[foe].id)
        XCTAssertFalse(cmds.contains { if case .castSkill = $0 { return true } else { return false } })
    }

    // MARK: - 撤退・帰還・買い物

    func testLowHealthBotRetreatsTowardItsOwnSide() {
        var f = BotFixture.bots(.normal)
        f.parkAllHeroes()
        let me = f.hero(.blue, .mid)
        let foes = [f.hero(.red, .mid), f.hero(.red, .jungle)]
        f.place(me, at: Vec2(5600, 5600))
        f.place(foes[0], at: Vec2(5900, 5900))
        f.place(foes[1], at: Vec2(5900, 5700))
        f.s.units[me].hp = f.s.units[me].stats.maxHP * 0.25
        f.refreshVision()
        f.advance(1)
        BotAI.updateIntel(&f.s, f.ctx)
        let cmds = f.decide(me)
        XCTAssertEqual(f.memory(me).goal, .retreat)
        let goal = try? XCTUnwrap(cmds.moveGoal())
        let fountain = f.ctx.map.fountain(.blue)
        XCTAssertLessThan(goal?.distance(to: fountain) ?? .infinity, Vec2(5600, 5600).distance(to: fountain))
    }

    func testSafeBotRecallsWhenHurtAndHealsInFountain() {
        var f = BotFixture.bots(.normal)
        f.parkAllHeroes()
        let me = f.hero(.blue, .top)
        f.place(me, at: Vec2(1400, 6200))
        f.s.units[me].hp = f.s.units[me].stats.maxHP * 0.2
        f.refreshVision()
        let cmds = f.decide(me)
        XCTAssertTrue(cmds.recalls, "\(cmds)")
        XCTAssertEqual(f.memory(me).recall, .channeling)

        // 泉に着いたら回復するまで待つ
        f.place(me, at: f.ctx.map.fountain(.blue))
        f.s.units[me].hero?.channel = nil
        f.advance(0.2)
        f.refreshVision()
        _ = f.decide(me)
        XCTAssertEqual(f.memory(me).goal, .shopping)
        XCTAssertEqual(f.memory(me).recall, .none)
    }

    func testDeadBotBuysRecommendedItemsUntilNothingAffordable() {
        var f = BotFixture.bots(.normal)
        let me = f.hero(.red, .carry)
        f.s.units[me].hero?.respawnTimer = 10
        f.s.units[me].isAlive = false
        f.s.units[me].hero?.gold = 3200
        let cmds = f.decide(me)
        let bought = cmds.purchases
        XCTAssertFalse(bought.isEmpty)
        XCTAssertEqual(f.memory(me).goal, .shopping)
        // 実際に CommandSystem で処理すると失敗せずに所持金内で買える
        f.s.events.removeAll()
        CommandSystem.apply(bought.map { HeroCommand(heroID: f.s.units[me].id, command: .buyItem(itemID: $0)) }, &f.s, f.ctx)
        XCTAssertFalse(f.s.events.contains { if case .purchaseFailed = $0 { return true } else { return false } })
        let h = f.s.units[me].hero!
        XCTAssertGreaterThanOrEqual(h.gold, 0)
        XCTAssertNil(ItemSystem.nextRecommendedPurchase(h, ctx: f.ctx), "should shop until nothing is affordable")
    }

    func testShoppingPlanMatchesRepeatedPurchases() {
        let f = BotFixture.bots(.normal)
        for i in f.s.heroIndices {
            var h = f.s.units[i].hero!
            h.gold = 5000
            let plan = BotShop.plannedPurchases(h, ctx: f.ctx)
            XCTAssertFalse(plan.isEmpty)
            // 手元で仮適用した結果と、実際に ItemSystem.buy した結果が一致する
            var simulated = h
            for id in plan { BotShop.apply(ItemSystem.quote(simulated, itemID: id, ctx: f.ctx), to: &simulated, ctx: f.ctx) }
            var s = f.s
            s.units[i].hero = h
            s.events.removeAll()
            for id in plan { ItemSystem.buy(&s, f.ctx, heroIndex: i, itemID: id) }
            XCTAssertFalse(s.events.contains { if case .purchaseFailed = $0 { return true } else { return false } })
            XCTAssertEqual(s.units[i].hero!.items, simulated.items)
            XCTAssertEqual(s.units[i].hero!.gold, simulated.gold, accuracy: 1e-6)
            XCTAssertNil(ItemSystem.nextRecommendedPurchase(s.units[i].hero!, ctx: f.ctx))
        }
    }

    // MARK: - レーン戦

    func testLastHitsKillableMinionAndIgnoresOneAboutToDie() {
        var f = BotFixture.bots(.hard)
        f.parkAllHeroes()
        let me = f.hero(.blue, .carry)
        f.place(me, at: Vec2(8000, 1400))
        // A: 1 発で倒せる HP、B: 味方の弾がすでに向かっていて先に倒れる
        let a = f.addMinion(.melee, team: .red, lane: .bot, at: Vec2(8300, 1450))
        let b = f.addMinion(.ranged, team: .red, lane: .bot, at: Vec2(8250, 1350))
        let hit = CombatSystem.estimateBasicAttackDamage(f.s, f.ctx, attacker: me, target: a)
        f.s.units[a].hp = hit * 0.8
        f.s.units[b].hp = hit * 0.5
        let shooter = f.addMinion(.ranged, team: .blue, lane: .bot, at: Vec2(8000, 1300))
        let payload = HitPayload(damage: 500, damageType: .physical, source: .minion)
        f.s.projectiles.append(Projectile(id: f.s.allocateID(), ownerID: f.s.units[shooter].id, team: .blue,
                                          pos: Vec2(8200, 1350), motion: .homing(targetID: f.s.units[b].id),
                                          speed: Balance.combatMinionProjectileSpeed, payload: payload,
                                          visual: "basic_attack"))
        f.refreshVision()
        let cmds = f.decide(me)
        XCTAssertEqual(cmds.attackTarget(), f.s.units[a].id)
    }

    func testLanerHoldsOutsideEnemyTowerRangeWithoutMinionCover() {
        var f = BotFixture.bots(.normal, time: 400)
        f.parkAllHeroes()
        let me = f.hero(.blue, .mid)
        f.place(me, at: Vec2(6200, 6200))
        f.refreshVision()
        let cmds = f.decide(me)
        let goal = try? XCTUnwrap(cmds.moveGoal())
        let redMidOuter = f.s.units.first { $0.kind == .tower && $0.team == .red && $0.tower?.lane == .mid && $0.tower?.tier == .outer }!
        let reach = redMidOuter.stats.attackRange + redMidOuter.radius + Balance.heroRadius
        XCTAssertGreaterThan(goal?.distance(to: redMidOuter.pos) ?? 0, reach)
    }

    // MARK: - ジャングル

    func testJunglerSmitesLowBuffInItsOwnCamp() {
        var f = BotFixture.bots(.normal, time: 200)
        f.parkAllHeroes()
        let me = f.hero(.blue, .jungle)
        XCTAssertEqual(f.s.units[me].hero?.spells.first, "BS05")
        let camp = f.ctx.map.camps.first { $0.side == .blue && $0.kind == .blueSentinel }!
        f.s.world.campRespawnAt[camp.id] = nil
        let id = f.s.addUnit(UnitFactory.makeMonster(kind: .blueSentinel, campID: camp.id, pos: camp.pos))
        let monster = f.s.index(of: id)!
        f.s.units[monster].hp = 400
        f.place(me, at: camp.pos + Vec2(-250, -200))
        f.refreshVision()
        let cmds = f.decide(me)
        XCTAssertTrue(cmds.contains(.castSpell(index: 0, target: .unit(id))), "\(cmds)")
        XCTAssertEqual(cmds.attackTarget(), id)
        XCTAssertEqual(f.memory(me).goal, .jungling)
    }

    func testJunglerHeadsToOwnSideCampAtStart() {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 12))
        sim.runHeadless(maxTime: 25)
        for team in Team.players {
            let j = sim.state.heroIndices(team: team).first { sim.state.units[$0].hero?.position == .jungle }!
            let own = sim.ctx.map.camps.filter { $0.side == team }
            let d = own.map { $0.pos.distance(to: sim.state.units[j].pos) }.min()!
            XCTAssertLessThan(d, 1500, "\(team) jungler should be at its own camps")
        }
    }

    // MARK: - スキル照準

    func testAimLeadsMovingTargetWithHighAccuracy() {
        var f = BotFixture.bots(.hard)
        let me = f.hero(.blue, .mid)
        let a = BotAgent(i: me, slot: f.slot(of: me), id: f.s.units[me].id, team: .blue, profile: .of(.hard),
                         difficulty: .hard, pos: Vec2(5000, 5000), level: 5, role: .arcanist, position: .mid,
                         isRanged: true, skillsWork: true)
        let target = BotSighting(index: f.hero(.red, .mid), id: 0, pos: Vec2(5600, 5000), velocity: Vec2(0, 300),
                                 distance: 600, visible: true)
        var mem = f.memory(me)
        var hits = 0
        for _ in 0..<40 {
            let p = BotCombat.predicted(&f.s, a, &mem, target, travel: 0.5, radius: 100)
            if p.y > 5100 && abs(p.x - 5600) < 60 { hits += 1 }
        }
        // 92% の精度: ほとんどが進行方向へ先読みした地点
        XCTAssertGreaterThanOrEqual(hits, 30)
    }

    func testBotCastsSkillsOnKillableEnemyWhenFighting() {
        var f = BotFixture.bots(.hard, time: 600)
        f.parkAllHeroes()
        let me = f.hero(.blue, .mid)
        let foe = f.hero(.red, .carry)
        f.place(me, at: Vec2(6000, 6000))
        f.place(foe, at: Vec2(6300, 6100))
        f.s.units[foe].hp = f.s.units[foe].stats.maxHP * 0.15
        f.refreshVision()
        f.advance(0.5)
        BotAI.updateIntel(&f.s, f.ctx)
        let cmds = f.decide(me)
        XCTAssertEqual(f.memory(me).goal, .teamfight)
        XCTAssertEqual(cmds.attackTarget(), f.s.units[foe].id)
        XCTAssertTrue(cmds.contains { if case .castSkill = $0 { return true } else { return false } }, "\(cmds)")
    }

    // MARK: - 観戦・スナップショット

    func testSnapshotRoundTripKeepsBotStateAndContinuesIdentically() throws {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 21))
        sim.runHeadless(maxTime: 45)
        let data = try JSONEncoder().encode(sim.state)
        let decoded = try JSONDecoder().decode(SimState.self, from: data)
        XCTAssertEqual(decoded.bots, sim.state.bots)
        let resumed = Simulation(snapshot: decoded)
        sim.runHeadless(maxTime: 55)
        resumed.runHeadless(maxTime: 55)
        XCTAssertEqual(resumed.state.stateHash(), sim.state.stateHash())
        XCTAssertEqual(resumed.state.bots, sim.state.bots)
    }

    func testSlotHandedToBotControlIsDrivenMidMatch() {
        var f = BotFixture(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "Leaver", seed: 4),
                           time: 120)
        let human = f.s.humanHeroIndex!
        let id = f.s.units[human].id
        var commanded = false
        for _ in 0..<12 {
            f.advance(Balance.dt)
            commanded = commanded || BotAI.generateCommands(&f.s, f.ctx).contains { $0.heroID == id }
        }
        XCTAssertFalse(commanded, "a human slot is never driven by the AI")
        f.s.units[human].hero?.controller = .bot
        for _ in 0..<12 {
            f.advance(Balance.dt)
            commanded = commanded || BotAI.generateCommands(&f.s, f.ctx).contains { $0.heroID == id }
        }
        XCTAssertTrue(commanded, "after the hand-over the AI drives the hero")
        XCTAssertTrue(f.memory(human).isBot)
    }

    func testIdleHumanHeroIsNeverCommandedByBots() {
        let cfg = MatchFactory.standardMatch(humanHeroID: "H003", humanName: "Idle", seed: 17)
        let sim = Simulation(config: cfg)
        let human = sim.state.humanHeroID!
        let start = sim.state.unit(human)!.pos
        sim.runHeadless(maxTime: 80)
        let u = sim.state.unit(human)!
        XCTAssertEqual(u.pos, start, "bots must not move the human's hero")
        XCTAssertTrue(u.hero!.items.isEmpty, "bots must not shop for the human")
        XCTAssertEqual(sim.state.bots.memory(for: human)?.lastDecisionTick, -1)
    }
}
