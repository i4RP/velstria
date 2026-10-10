import XCTest
@testable import VelstriaCore

/// World 系テストの共通ヘルパー。
enum WorldTestKit {
    /// ヒーローなし（ミニオン・構造物・中立のみ）の構成。
    static func emptyConfig(mode: MatchMode = .standard, seed: UInt64 = 1,
                            practice: PracticeOptions? = nil) -> MatchConfig {
        MatchConfig(mode: mode, seed: seed, players: [], practice: practice)
    }

    /// Simulation.init と同じ手順で初期状態を作る（テストで状態を直接いじるため）。
    static func makeState(_ config: MatchConfig) -> (SimState, SimContext) {
        let ctx = SimContext(master: .shared, map: .standard, config: config)
        var s = SimState(config: config)
        SpawnSystem.setupMatch(&s, ctx)
        for i in s.units.indices { StatCalculator.recompute(&s, i, ctx) }
        VisionSystem.update(&s, ctx)
        s.phase = .playing
        return (s, ctx)
    }

    /// 時刻を進める（システムは呼ばない）。
    static func setTime(_ s: inout SimState, _ t: Double) {
        s.tick = Int((t * Balance.tickRate).rounded())
        s.time = Double(s.tick) * Balance.dt
    }

    /// 時刻を飛ばした状態でウェーブがまとめて出ないようにする（シナリオ用）。
    static func suppressWaves(_ s: inout SimState) {
        s.world.nextWaveTime = 1e9
    }

    @discardableResult
    static func addHero(_ s: inout SimState, _ ctx: SimContext, team: Team, pos: Vec2, heroID: String = "H001") -> Int {
        let def = ctx.master.hero(heroID)!
        let slot = PlayerSlot(team: team, heroID: heroID, controller: .human, position: .mid, displayName: "T")
        let id = s.addUnit(UnitFactory.makeHero(def: def, slot: slot, pos: pos))
        let i = s.index(of: id)!
        StatCalculator.recompute(&s, i, ctx)
        s.units[i].hp = s.units[i].stats.maxHP
        return i
    }

    @discardableResult
    static func addMinion(_ s: inout SimState, _ ctx: SimContext, type: MinionType = .melee, team: Team,
                          lane: Lane = .mid, pos: Vec2) -> Int {
        let id = s.addUnit(UnitFactory.makeMinion(type: type, team: team, lane: lane, pos: pos, time: s.time))
        let i = s.index(of: id)!
        StatCalculator.recompute(&s, i, ctx)
        return i
    }

    static func structureIndex(_ s: SimState, team: Team, lane: Lane?, tier: TowerTier, core: Bool = false) -> Int {
        s.units.indices.first {
            let u = s.units[$0]
            return u.isStructure && u.team == team && (core ? u.kind == .core : (u.kind == .tower && u.tower?.lane == lane && u.tower?.tier == tier))
        }!
    }

    static func kill(_ s: inout SimState, _ i: Int) {
        s.units[i].hp = 0
        s.units[i].isAlive = false
        s.units[i].deathTime = s.time
    }
}

/// ミニオンのウェーブ・中立キャンプ・練習用人形の出現（DESIGN §3・§4）。
final class WorldSpawnTests: XCTestCase {
    func testSideLaneMinionsAreTenPercentSlower() {
        for type in [MinionType.melee, .ranged, .siege] {
            let mid = UnitFactory.makeMinion(type: type, team: .blue, lane: .mid, pos: .zero, time: 0).stats.moveSpeed
            for lane in [Lane.top, .bot] {
                let side = UnitFactory.makeMinion(type: type, team: .blue, lane: lane, pos: .zero, time: 0).stats.moveSpeed
                XCTAssertEqual(side, mid * 0.9, accuracy: 1e-9, "\(type) \(lane)")
            }
        }
    }

    func testWaveComposition() {
        XCTAssertEqual(SpawnSystem.waveComposition(waveIndex: 0, time: 20), [.melee, .melee, .melee, .ranged, .ranged, .ranged])
        XCTAssertEqual(SpawnSystem.waveComposition(waveIndex: 1, time: 50).filter { $0 == .siege }.count, 0)
        XCTAssertEqual(SpawnSystem.waveComposition(waveIndex: 2, time: 80), [.melee, .melee, .melee, .siege, .ranged, .ranged, .ranged])
        XCTAssertEqual(SpawnSystem.waveComposition(waveIndex: 5, time: 170).filter { $0 == .siege }.count, 1)
        // 10:00 以降は近接 +1
        XCTAssertEqual(SpawnSystem.waveComposition(waveIndex: 19, time: 590).filter { $0 == .melee }.count, 3)
        XCTAssertEqual(SpawnSystem.waveComposition(waveIndex: 20, time: 620).filter { $0 == .melee }.count, 4)
        XCTAssertEqual(SpawnSystem.waveComposition(waveIndex: 20, time: 620).filter { $0 == .siege }.count, 1)
    }

    func testWaveTimingAndCounts() {
        var waves: [(index: Int, time: Double)] = []
        var minionsPerWave: [Int] = []
        var announced = 0
        func run(_ sim: Simulation, until t: Double) {
            while sim.state.time < t {
                let ev = sim.step()
                var spawned = 0
                for e in ev {
                    switch e {
                    case .waveSpawned(let index): waves.append((index, sim.state.time))
                    case .unitSpawned(_, let kind, _, _) where kind == .minion: spawned += 1
                    case .announcement(.minionsSpawned): announced += 1
                    default: break
                    }
                }
                if spawned > 0 { minionsPerWave.append(spawned) }
            }
        }
        // 初回は 0:00 から実時間で進め、以降はウェーブ直前まで時刻を飛ばす（ウェーブ予定は保持される）
        var sim = Simulation(config: WorldTestKit.emptyConfig())
        run(sim, until: 21)
        for next in [50.0, 80.0] {
            var st = sim.state
            WorldTestKit.setTime(&st, next - 1)
            sim = Simulation(snapshot: st)
            run(sim, until: next + 1)
        }
        XCTAssertEqual(waves.map(\.index), [0, 1, 2])
        XCTAssertEqual(waves[0].time, 20, accuracy: 1e-6)
        XCTAssertEqual(waves[1].time, 50, accuracy: 1e-6)
        XCTAssertEqual(waves[2].time, 80, accuracy: 1e-6)
        // 2 チーム × 3 レーン × (6, 6, 7)
        XCTAssertEqual(minionsPerWave, [36, 36, 42])
        XCTAssertEqual(announced, 1)
    }

    func testMinionsSpawnOnTheirLaneAtTheirBase() {
        var (s, ctx) = WorldTestKit.makeState(WorldTestKit.emptyConfig())
        WorldTestKit.setTime(&s, 20)
        SpawnSystem.update(&s, ctx)
        let minions = s.units.filter { $0.kind == .minion }
        XCTAssertEqual(minions.count, 36)
        for m in minions {
            let lane = m.minion!.lane
            XCTAssertLessThan(ctx.map.distanceToLane(m.pos, lane: lane), 60)
            XCTAssertLessThan(m.pos.distance(to: ctx.map.core(m.team)), 800)
            XCTAssertGreaterThan(m.pos.distance(to: ctx.map.core(m.team)), 250)
            XCTAssertEqual(m.minion!.waypointIndex, 1)
        }
        // 基礎値（DESIGN §4、t = 20 秒の成長込み）
        let melee = minions.first { $0.minion!.type == .melee }!
        XCTAssertEqual(melee.stats.maxHP, 520 * (1 + 0.03 * 20 / 60), accuracy: 1e-6)
        XCTAssertEqual(melee.radius, 36)
    }

    func testPracticeRespectsSpawnMinions() {
        let off = WorldTestKit.emptyConfig(mode: .practice, practice: PracticeOptions(spawnMinions: false, spawnDummies: false))
        let sim = Simulation(config: off)
        sim.runHeadless(maxTime: 21)
        XCTAssertEqual(sim.state.units.filter { $0.kind == .minion }.count, 0)
        XCTAssertEqual(sim.state.units.filter { $0.kind == .dummy }.count, 0)

        let tutorialOn = WorldTestKit.emptyConfig(mode: .tutorial, practice: PracticeOptions(spawnMinions: true))
        let sim2 = Simulation(config: tutorialOn)
        sim2.runHeadless(maxTime: 21)
        XCTAssertEqual(sim2.state.units.filter { $0.kind == .minion }.count, 36)
    }

    func testCampsSpawnWithCompositionAndBossAnnouncements() {
        let sim = Simulation(config: WorldTestKit.emptyConfig())
        var wyrmAnnounce: Double?
        var colossusAnnounce: Double?
        sim.runHeadless(maxTime: 24.9)
        XCTAssertEqual(sim.state.units.filter { $0.kind == .monster }.count, 0)
        sim.runHeadless(maxTime: 25.1)
        let monsters = sim.state.units.filter { $0.kind == .monster }
        // 各陣地: 蒼晶の番人 + 仔、紅焔の番人、棘角トカゲ、熔岩の岩人、熾甲虫（宝殻蟹の子は 0:42、川の中立は 0:45 から）
        XCTAssertEqual(monsters.count, 12)
        for kind in [MonsterKind.blueSentinel, .azureWhelp, .redSentinel, .hornLizard, .magmaGolem, .emberBeetle] {
            XCTAssertEqual(monsters.filter { $0.monster!.kind == kind }.count, 2, "\(kind)")
        }
        XCTAssertTrue(monsters.allSatisfy { $0.team == .neutral })
        let sentinel = monsters.first { $0.monster!.kind == .redSentinel }!
        XCTAssertEqual(sentinel.stats.maxHP, 2200)
        XCTAssertEqual(sentinel.radius, 110)
        XCTAssertEqual(sentinel.stats.armor, 25)
        XCTAssertEqual(sentinel.stats.attackSpeed, 1 / 1.2, accuracy: 1e-9)
        // ボスの初回出現（時刻を直前まで飛ばして確認）
        var st = sim.state
        WorldTestKit.setTime(&st, 119)
        WorldTestKit.suppressWaves(&st)
        let late = Simulation(snapshot: st)
        func watch(_ ev: [SimEvent]) {
            for e in ev {
                if case .announcement(.wyrmSpawned) = e { wyrmAnnounce = late.state.time }
                if case .announcement(.colossusSpawned) = e { colossusAnnounce = late.state.time }
            }
        }
        late.runHeadless(maxTime: 121, onEvents: watch)
        XCTAssertEqual(wyrmAnnounce ?? 0, 120, accuracy: 0.05)
        XCTAssertNil(colossusAnnounce)
        var st2 = late.state
        WorldTestKit.setTime(&st2, 479)
        let later = Simulation(snapshot: st2)
        later.runHeadless(maxTime: 481) { ev in
            if ev.contains(.announcement(.colossusSpawned)) { colossusAnnounce = later.state.time }
        }
        XCTAssertEqual(colossusAnnounce ?? 0, 480, accuracy: 0.05)
        let wyrm = later.state.units.first { $0.monster?.kind == .astralWyrm }!
        XCTAssertEqual(wyrm.stats.maxHP, 5500)
        XCTAssertEqual(wyrm.radius, 180)
        XCTAssertEqual(later.state.units.filter { $0.monster?.kind == .astralWyrm }.count, 1)
        let colossus = later.state.units.first { $0.monster?.kind == .ancientColossus }!
        XCTAssertEqual(colossus.stats.maxHP, 9000)
        XCTAssertEqual(colossus.radius, 220)
        XCTAssertEqual(colossus.pos, Vec2(3740, 8410))
    }

    /// 川の中立（苔甲の徘徊者、片側のみ）は古環の巨像の巣の側に、約 0:45 に出現する（参照仕様 §5.1）。
    func testRiverCampSpawnsAtFortyFiveSecondsOnOneSideOnly() {
        let sim = Simulation(config: WorldTestKit.emptyConfig())
        let rivers = sim.ctx.map.camps.filter { $0.side == .neutral && $0.kind == .mossWanderer }
        XCTAssertEqual(rivers.count, 1)
        let camp = rivers[0]
        XCTAssertEqual(camp.pos, Vec2(4710, 7285))
        XCTAssertEqual(camp.firstSpawn, 45)
        XCTAssertEqual(camp.respawn, 120)
        XCTAssertTrue(sim.ctx.map.isInRiver(camp.pos))
        sim.runHeadless(maxTime: 44.9)
        XCTAssertEqual(sim.state.units.filter { $0.monster?.campID == camp.id }.count, 0)
        sim.runHeadless(maxTime: 45.1)
        XCTAssertEqual(sim.state.units.filter { $0.monster?.campID == camp.id }.count, 1)
        XCTAssertEqual(sim.state.units.first { $0.monster?.campID == camp.id }?.monster?.kind, .mossWanderer)
    }

    func testCampRespawnsOnlyAfterAllMembersDie() {
        var (s, ctx) = WorldTestKit.makeState(WorldTestKit.emptyConfig())
        WorldTestKit.setTime(&s, 30)
        SpawnSystem.update(&s, ctx)
        // 紫バフのキャンプは番人と仔の 2 体
        let camp = ctx.map.camps.first { $0.kind == .blueSentinel && $0.side == .blue }!
        let members = s.units.indices.filter { s.units[$0].monster?.campID == camp.id }
        XCTAssertEqual(members.count, 2)
        XCTAssertNil(s.world.campRespawnAt[camp.id])

        // 1 体倒しても再出現タイマーは動かない
        WorldTestKit.setTime(&s, 100)
        WorldTestKit.kill(&s, members[0])
        SpawnSystem.update(&s, ctx)
        XCTAssertNil(s.world.campRespawnAt[camp.id])

        // 全滅した時点から respawn 秒
        WorldTestKit.setTime(&s, 110)
        WorldTestKit.kill(&s, members[1])
        s.removeFinishedEntities()
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(s.world.campRespawnAt[camp.id] ?? 0, 110 + camp.respawn, accuracy: 1e-6)

        WorldTestKit.setTime(&s, 110 + camp.respawn - 1)
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(s.units.filter { $0.monster?.campID == camp.id && $0.isAlive }.count, 0)
        WorldTestKit.setTime(&s, 110 + camp.respawn)
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(s.units.filter { $0.monster?.campID == camp.id && $0.isAlive }.count, 2)
        XCTAssertNil(s.world.campRespawnAt[camp.id])
    }

    /// 序盤ボスは 6:00 以降に倒されると再出現しない（それ以前なら再出現する）。
    func testWyrmDoesNotRespawnWhenKilledAfterSixMinutes() {
        var (s, ctx) = WorldTestKit.makeState(WorldTestKit.emptyConfig())
        let wyrm = ctx.map.camps.first { $0.kind == .astralWyrm }!
        s.world.campRespawnAt = ctx.map.camps.map { _ in nil }
        WorldTestKit.setTime(&s, Balance.wyrmNoRespawnAfter - 1)
        SpawnSystem.update(&s, ctx)
        XCTAssertNotNil(s.world.campRespawnAt[wyrm.id], "6:00 前に倒れていれば再出現する")
        s.world.campRespawnAt = ctx.map.camps.map { _ in nil }
        WorldTestKit.setTime(&s, Balance.wyrmNoRespawnAfter)
        SpawnSystem.update(&s, ctx)
        XCTAssertNil(s.world.campRespawnAt[wyrm.id], "6:00 以降に倒れたら再出現しない")
        // 後半ボスは時刻に関わらず再出現する
        let colossus = ctx.map.camps.first { $0.kind == .ancientColossus }!
        XCTAssertNotNil(s.world.campRespawnAt[colossus.id])
    }

    func testBossRespawnTimingInFullSimulation() {
        var (s, _) = WorldTestKit.makeState(WorldTestKit.emptyConfig())
        WorldTestKit.setTime(&s, 119)
        WorldTestKit.suppressWaves(&s)
        let sim = Simulation(snapshot: s)
        sim.runHeadless(maxTime: 121)
        let wyrmCamp = sim.ctx.map.camps.first { $0.kind == .astralWyrm }!
        guard let w = sim.state.units.firstIndex(where: { $0.monster?.kind == .astralWyrm }) else {
            return XCTFail("wyrm not spawned")
        }
        var st = sim.state
        CombatSystem.applyDamage(&st, sim.ctx, sourceID: nil, targetIndex: w, amount: 1_000_000, type: .trueDamage, source: .spell)
        XCTAssertFalse(st.units[w].isAlive)
        // 撃破の次の tick で再出現時刻が決まる
        let sim2 = Simulation(snapshot: st)
        sim2.step()
        let deathSeen = sim2.state.time
        let at = sim2.state.world.campRespawnAt[wyrmCamp.id]
        XCTAssertEqual(at ?? 0, deathSeen + wyrmCamp.respawn, accuracy: 1e-6)
        // 直前まで時刻を飛ばして出現を確認
        var st3 = sim2.state
        WorldTestKit.setTime(&st3, (at ?? 0) - 1)
        let sim3 = Simulation(snapshot: st3)
        var respawned: Double?
        sim3.runHeadless(maxTime: (at ?? 0) + 1) { ev in
            if ev.contains(.announcement(.wyrmSpawned)) { respawned = sim3.state.time }
        }
        XCTAssertEqual(respawned ?? 0, at ?? -1, accuracy: Balance.dt)
    }

    func testPracticeDummies() {
        let cfg = MatchFactory.practiceMatch(humanHeroID: "H001", humanName: "P",
                                             options: PracticeOptions(spawnMinions: false, spawnDummies: true), seed: 5)
        var (s, ctx) = WorldTestKit.makeState(cfg)
        let dummies = s.units.indices.filter { s.units[$0].kind == .dummy }
        XCTAssertEqual(dummies.count, 3)
        let tower = WorldTestKit.structureIndex(s, team: .blue, lane: .mid, tier: .outer)
        for d in dummies {
            let u = s.units[d]
            XCTAssertEqual(u.team, .red)
            XCTAssertEqual(u.stats.maxHP, 3000)
            XCTAssertEqual(u.stats.armor, 30)
            XCTAssertEqual(u.stats.magicResist, 30)
            // 外塔の前方（Red 側）で、外塔の攻撃範囲外
            XCTAssertGreaterThan(u.pos.x + u.pos.y, s.units[tower].pos.x + s.units[tower].pos.y)
            XCTAssertFalse(TowerSystem.inReach(s.units[tower], u))
            XCTAssertTrue(s.isVisible(d, to: .blue))
        }
        // 被ダメ後 4 秒で全回復
        let d = dummies[0]
        WorldTestKit.setTime(&s, 10)
        CombatSystem.applyDamage(&s, ctx, sourceID: nil, targetIndex: d, amount: 1000, type: .trueDamage, source: .spell)
        XCTAssertEqual(s.units[d].hp, 2000)
        WorldTestKit.setTime(&s, 13.9)
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(s.units[d].hp, 2000)
        WorldTestKit.setTime(&s, 14.0)
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(s.units[d].hp, 3000)

        // 撃破されたら 4 秒後に再出現
        let deadID = s.units[d].id
        CombatSystem.applyDamage(&s, ctx, sourceID: nil, targetIndex: d, amount: 5000, type: .trueDamage, source: .spell)
        s.removeFinishedEntities()
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(s.units.filter { $0.kind == .dummy }.count, 2)
        WorldTestKit.setTime(&s, 18.0)
        SpawnSystem.update(&s, ctx)
        let again = s.units.filter { $0.kind == .dummy }
        XCTAssertEqual(again.count, 3)
        XCTAssertFalse(again.contains { $0.id == deadID })

        // spawnDummies = false なら出ない
        let none = MatchFactory.practiceMatch(humanHeroID: "H001", humanName: "P",
                                              options: PracticeOptions(spawnDummies: false), seed: 5)
        XCTAssertEqual(WorldTestKit.makeState(none).0.units.filter { $0.kind == .dummy }.count, 0)
        // 通常戦では出ない
        XCTAssertEqual(WorldTestKit.makeState(WorldTestKit.emptyConfig()).0.units.filter { $0.kind == .dummy }.count, 0)
    }

    func testStructuresMatchDesignStats() {
        let (s, _) = WorldTestKit.makeState(WorldTestKit.emptyConfig())
        XCTAssertEqual(s.units.filter { $0.kind == .tower }.count, 18)
        XCTAssertEqual(s.units.filter { $0.kind == .core }.count, 2)
        let outer = s.units[WorldTestKit.structureIndex(s, team: .red, lane: .bot, tier: .outer)]
        XCTAssertEqual(outer.stats.maxHP, 4200 * Balance.structureHPScale, accuracy: 1e-9)
        XCTAssertEqual(outer.stats.attack, 260)
        XCTAssertEqual(outer.stats.attackRange, 750)
        let base = s.units[WorldTestKit.structureIndex(s, team: .blue, lane: .top, tier: .base)]
        XCTAssertEqual(base.stats.maxHP, 5000 * Balance.structureHPScale, accuracy: 1e-9)
        XCTAssertEqual(base.stats.armor, 100)
        let core = s.units[WorldTestKit.structureIndex(s, team: .blue, lane: nil, tier: .base, core: true)]
        XCTAssertEqual(core.stats.maxHP, 7000 * Balance.structureHPScale, accuracy: 1e-9)
        XCTAssertEqual(core.stats.attack, 360)
        XCTAssertEqual(core.stats.attackRange, 800)
        XCTAssertEqual(core.radius, 250)
    }
}
