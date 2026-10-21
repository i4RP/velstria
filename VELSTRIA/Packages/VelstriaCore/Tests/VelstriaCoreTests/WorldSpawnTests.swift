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
    static func makeState(_ config: MatchConfig, map: MapDefinition = .standard) -> (SimState, SimContext) {
        let ctx = SimContext(master: .shared, map: map, config: config)
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
    /// 種類によらず同じ速さ（ウェーブがまとまって進む）。側レーンは中央の 0.957 倍（MLBB: 側 −10%、中央 −6%）。
    func testMinionSpeedBySideLaneAndTime() {
        for type in [MinionType.melee, .ranged, .siege] {
            let mid = UnitFactory.makeMinion(type: type, team: .blue, lane: .mid, pos: .zero, time: 0).stats.moveSpeed
            XCTAssertEqual(mid, Balance.minionMoveSpeed, accuracy: 1e-9, "\(type)")
            for lane in [Lane.top, .bot] {
                let side = UnitFactory.makeMinion(type: type, team: .blue, lane: lane, pos: .zero, time: 0).stats.moveSpeed
                XCTAssertEqual(side, mid * 0.957, accuracy: 1e-9, "\(type) \(lane)")
            }
        }
        // 12:00 までは伸びない。12:00 から毎分 +30（× mapScale）、4 分で上限 +120（同）
        let base = Balance.minionMoveSpeed
        XCTAssertEqual(UnitFactory.minionMoveSpeed(lane: .mid, time: 11 * 60 + 59), base, accuracy: 1e-9)
        XCTAssertEqual(UnitFactory.minionMoveSpeed(lane: .mid, time: 13 * 60), base + 30 * Balance.mapScale, accuracy: 1e-9)
        XCTAssertEqual(UnitFactory.minionMoveSpeed(lane: .mid, time: 16 * 60), base + 120 * Balance.mapScale, accuracy: 1e-9)
        XCTAssertEqual(UnitFactory.minionMoveSpeed(lane: .top, time: 25 * 60),
                       base * 0.957 + 120 * Balance.mapScale, accuracy: 1e-9)
    }

    /// MLBB: 側レーンは毎ウェーブ 近接・遠隔・攻城を 1 体ずつ（前列から）。中央は最初の 10 ウェーブが 近接 1 + 遠隔 3、以後は側と同じ。
    func testWaveCompositionByLane() {
        for lane in [Lane.top, .bot] {
            for wave in [0, 1, 9, 10, 40] {
                XCTAssertEqual(SpawnSystem.waveComposition(waveIndex: wave, lane: lane), [.melee, .ranged, .siege], "\(lane) \(wave)")
            }
        }
        XCTAssertEqual(SpawnSystem.waveComposition(waveIndex: 0, lane: .mid), [.melee, .ranged, .ranged, .ranged])
        XCTAssertEqual(SpawnSystem.waveComposition(waveIndex: 9, lane: .mid), [.melee, .ranged, .ranged, .ranged])
        XCTAssertEqual(SpawnSystem.waveComposition(waveIndex: 10, lane: .mid), [.melee, .ranged, .siege])
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
        run(sim, until: 12)
        for next in [41.0, 281.0, 311.0] {
            var st = sim.state
            // 4:41 へは途中のウェーブを飛ばす（予定を次の 1 回だけ進める）
            if next == 281 { st.world.waveIndex = 9; st.world.nextWaveTime = 281 }
            WorldTestKit.setTime(&st, next - 1)
            sim = Simulation(snapshot: st)
            run(sim, until: next + 1)
        }
        // 0:11 に初回、以後 30 秒毎（4:41 のウェーブ 9 が最後の序盤ウェーブ、5:11 のウェーブ 10 から中央も攻城入り）
        XCTAssertEqual(waves.map(\.index), [0, 1, 9, 10])
        for (w, t) in zip(waves, [11.0, 41, 281, 311]) { XCTAssertEqual(w.time, t, accuracy: 1e-6) }
        // 2 チーム × (中央 4 + 側 3 × 2) = 20、中央も 3 体になると 18
        XCTAssertEqual(minionsPerWave, [20, 20, 20, 18])
        XCTAssertEqual(announced, 1)
    }

    func testMinionsSpawnOnTheirLaneAtTheirBase() {
        var (s, ctx) = WorldTestKit.makeState(WorldTestKit.emptyConfig())
        WorldTestKit.setTime(&s, 11)
        SpawnSystem.update(&s, ctx)
        let minions = s.units.filter { $0.kind == .minion }
        XCTAssertEqual(minions.count, 20)
        for m in minions {
            let lane = m.minion!.lane
            XCTAssertLessThan(ctx.map.distanceToLane(m.pos, lane: lane), 60)
            XCTAssertLessThan(m.pos.distance(to: ctx.map.core(m.team)), 1000)
            XCTAssertGreaterThan(m.pos.distance(to: ctx.map.core(m.team)), 250)
            XCTAssertEqual(m.minion!.waypointIndex, 1)
        }
        // 基礎値（DESIGN §4、t = 11 秒の成長込み）
        let melee = minions.first { $0.minion!.type == .melee }!
        XCTAssertEqual(melee.stats.maxHP, 520 * (1 + 0.03 * 11 / 60), accuracy: 1e-6)
        XCTAssertEqual(melee.radius, 36)
    }

    func testPracticeRespectsSpawnMinions() {
        let off = WorldTestKit.emptyConfig(mode: .practice, practice: PracticeOptions(spawnMinions: false, spawnDummies: false))
        let sim = Simulation(config: off)
        sim.runHeadless(maxTime: 12)
        XCTAssertEqual(sim.state.units.filter { $0.kind == .minion }.count, 0)
        XCTAssertEqual(sim.state.units.filter { $0.kind == .dummy }.count, 0)

        let tutorialOn = WorldTestKit.emptyConfig(mode: .tutorial, practice: PracticeOptions(spawnMinions: true))
        let sim2 = Simulation(config: tutorialOn)
        sim2.runHeadless(maxTime: 12)
        XCTAssertEqual(sim2.state.units.filter { $0.kind == .minion }.count, 20)
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
        // Fandom の紅焔の番人 × Patch 1.9.90（HP +30%）。0 分の値
        XCTAssertEqual(sentinel.stats.maxHP, UnitFactory.monsterProfile(.redSentinel).maxHP(at: 0), accuracy: 1e-9)
        XCTAssertEqual(sentinel.stats.maxHP, 4941 * 1.3, accuracy: 1e-9)
        XCTAssertEqual(sentinel.radius, 110)
        XCTAssertEqual(sentinel.stats.armor, 37)
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
        // 2:00 に出て、生きている間も毎分伸びる（8:00 の値）
        XCTAssertEqual(wyrm.stats.maxHP, UnitFactory.monsterProfile(.astralWyrm).maxHP(at: 480), accuracy: 1e-9)
        XCTAssertEqual(wyrm.radius, 180)
        XCTAssertEqual(later.state.units.filter { $0.monster?.kind == .astralWyrm }.count, 1)
        let colossus = later.state.units.first { $0.monster?.kind == .ancientColossus }!
        XCTAssertEqual(colossus.stats.maxHP, UnitFactory.monsterProfile(.ancientColossus).maxHP(at: 480), accuracy: 1e-9)
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
        // MLBB 2.2.16 の通常の試合の値（Balance.Tower。docs/TOWER_BASE_MLBB.md）: 射程 5.3・視界 8（× 100）
        let outer = s.units[WorldTestKit.structureIndex(s, team: .red, lane: .bot, tier: .outer)]
        XCTAssertEqual(outer.stats.maxHP, 4500)
        XCTAssertEqual(outer.stats.attack, 320)
        XCTAssertEqual(outer.stats.armor, 20)
        XCTAssertEqual(outer.stats.magicResist, 20)
        XCTAssertEqual(outer.stats.attackRange, 530)
        XCTAssertEqual(outer.stats.sightRange, 800)
        XCTAssertEqual(outer.stats.attackSpeed, 1)
        let inner = s.units[WorldTestKit.structureIndex(s, team: .blue, lane: .mid, tier: .inner)]
        XCTAssertEqual(inner.stats.maxHP, 5700)
        XCTAssertEqual(inner.stats.attack, 360)
        XCTAssertEqual(inner.stats.armor, 20)
        let base = s.units[WorldTestKit.structureIndex(s, team: .blue, lane: .top, tier: .base)]
        XCTAssertEqual(base.stats.maxHP, 7300)
        XCTAssertEqual(base.stats.attack, 520)
        XCTAssertEqual(base.stats.armor, 40)
        let core = s.units[WorldTestKit.structureIndex(s, team: .blue, lane: nil, tier: .base, core: true)]
        XCTAssertEqual(core.stats.maxHP, 7900)
        XCTAssertEqual(core.stats.attack, 539)
        XCTAssertEqual(core.stats.armor, 40)
        XCTAssertEqual(core.stats.attackRange, 530)
        XCTAssertEqual(core.radius, 250)
    }
}

/// ミニオンのウェーブの進み方（MLBB の現行マップと同じ形になっているか）。
final class MinionWaveTests: XCTestCase {
    /// 経路の始点からの道のり（最寄り点まで）。
    static func arcLength(_ p: Vec2, along path: [Vec2]) -> Double {
        var best = (d: Double.infinity, s: 0.0)
        var acc = 0.0
        for k in 1..<path.count {
            let a = path[k - 1], b = path[k]
            let ab = b - a, len = ab.length
            let t = len > 0 ? min(1, max(0, (p - a).dot(ab) / (len * len))) : 0
            let d = p.distance(to: a + ab * t)
            if d < best.d { best = (d, acc + len * t) }
            acc += len
        }
        return best.s
    }

    static func length(_ path: [Vec2]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// MLBB Wiki: 出てから中央レーンは約 15 秒、側レーンは約 25 秒で着く（両軍のウェーブが出会うレーンの中点まで）。
    /// 実機のミニマップ（2026-10-10 のスクリーンショット）: 0:23 に側レーンの Blue のウェーブの中心は Core から道のり 約 5400、
    /// 0:32 に 約 8850〜8950 で、0:32〜0:33 に左上・右下の角（中点）で Red と出会った。中央は 0:25 ごろに中心で出会う。
    func testFirstWaveTravelMatchesTheMLBBMinimap() {
        let sim = Simulation(config: WorldTestKit.emptyConfig())
        let map = sim.ctx.map
        var firstClash: [Lane: (time: Double, pos: Vec2)] = [:]
        var centre: [Double: [Lane: Double]] = [:]
        sim.runHeadless(maxTime: 45) { ev in
            for e in ev {
                guard case .damage(let d) = e, d.source == .minion, let t = sim.state.unit(d.targetID),
                      t.kind == .minion, let lane = t.minion?.lane, firstClash[lane] == nil else { continue }
                firstClash[lane] = (sim.state.time, d.pos)
            }
            for at in [23.0, 32.0] where abs(sim.state.time - at) < Balance.dt / 2 {
                for lane in Lane.allCases {
                    let path = map.lanePath(lane, for: .blue)
                    let arcs = sim.state.units.filter { $0.kind == .minion && $0.team == .blue && $0.minion!.lane == lane }
                        .map { Self.arcLength($0.pos, along: path) }
                    centre[at, default: [:]][lane] = arcs.reduce(0, +) / Double(max(1, arcs.count))
                }
            }
        }
        for lane in [Lane.top, .bot] {
            XCTAssertEqual(centre[23]?[lane] ?? 0, 5400, accuracy: 400, "\(lane) 0:23")
            XCTAssertEqual(centre[32]?[lane] ?? 0, 8900, accuracy: 400, "\(lane) 0:32")
            XCTAssertEqual(firstClash[lane]?.time ?? 0, 33, accuracy: 1.5, "\(lane)")
        }
        XCTAssertEqual(firstClash[.mid]?.time ?? 0, 25, accuracy: 1.5)
        for lane in Lane.allCases {
            guard let clash = firstClash[lane] else { XCTFail("\(lane) waves never met"); continue }
            let path = map.lanePath(lane, for: .blue)
            XCTAssertEqual(Self.arcLength(clash.pos, along: path), Self.length(path) / 2, accuracy: 500, "\(lane) meets off-centre")
        }
    }

    /// 遊ぶ地図（canyon）でも、ウェーブは MLBB と同じ時刻にレーンの中点で出会う（中央 0:25・側 0:33）。
    /// canyon のレーンは standard の 0.72〜0.74 倍の長さなので、速さと出る位置をレーンの長さの比で縮める（SpawnSystem.minionLaneScale）。
    func testFirstWaveMeetsOnTimeOnTheCanyon() {
        let sim = Simulation(config: WorldTestKit.emptyConfig(), map: .canyon)
        let map = sim.ctx.map
        var firstClash: [Lane: (time: Double, pos: Vec2)] = [:]
        sim.runHeadless(maxTime: 45) { ev in
            for e in ev {
                guard case .damage(let d) = e, d.source == .minion, let t = sim.state.unit(d.targetID),
                      t.kind == .minion, let lane = t.minion?.lane, firstClash[lane] == nil else { continue }
                firstClash[lane] = (sim.state.time, d.pos)
            }
        }
        XCTAssertEqual(firstClash[.mid]?.time ?? 0, 25, accuracy: 1.5)
        for lane in [Lane.top, .bot] {
            XCTAssertEqual(firstClash[lane]?.time ?? 0, 33, accuracy: 1.5, "\(lane)")
        }
        for lane in Lane.allCases {
            guard let clash = firstClash[lane] else { XCTFail("\(lane) waves never met"); continue }
            let path = map.lanePath(lane, for: .blue)
            XCTAssertEqual(Self.arcLength(clash.pos, along: path), Self.length(path) / 2, accuracy: 400, "\(lane) meets off-centre")
        }
        XCTAssertEqual(SpawnSystem.minionLaneScale(.standard, .mid), 1, accuracy: 1e-9)
        XCTAssertLessThan(SpawnSystem.minionLaneScale(.canyon, .mid), 0.8)
    }

    /// 敵の基部塔が壊れたレーンだけ、それ以後のウェーブがスーパーミニオンになる（MLBB の Call of Raging）。
    func testSuperMinionsSpawnOnlyInTheLaneWhoseEnemyBaseTurretFell() {
        var (s, ctx) = WorldTestKit.makeState(WorldTestKit.emptyConfig())
        let redTopBase = s.units.indices.first {
            s.units[$0].kind == .tower && s.units[$0].team == .red && s.units[$0].tower?.lane == .top && s.units[$0].tower?.tier == .base
        }!
        WorldTestKit.kill(&s, redTopBase)
        WorldTestKit.setTime(&s, 11)
        SpawnSystem.update(&s, ctx)
        let minions = s.units.filter { $0.kind == .minion }
        XCTAssertFalse(minions.isEmpty)
        for m in minions {
            let expected = m.team == .blue && m.minion!.lane == .top
            XCTAssertEqual(m.minion!.isSuper, expected, "\(m.team) \(m.minion!.lane)")
        }
        let normal = UnitFactory.makeMinion(type: .siege, team: .blue, lane: .top, pos: .zero, time: 11)
        let boosted = minions.first { $0.minion!.isSuper && $0.minion!.type == .siege }!
        XCTAssertEqual(boosted.stats.maxHP, normal.stats.maxHP * Balance.superMinionHPMultiplier, accuracy: 1e-6)
        XCTAssertEqual(boosted.stats.attack, normal.stats.attack * Balance.superMinionAttackMultiplier, accuracy: 1e-6)
        XCTAssertEqual(boosted.stats.armor, normal.stats.armor + Balance.superMinionDefenseBonus, accuracy: 1e-6)
        XCTAssertEqual(boosted.radius, normal.radius * Balance.superMinionRadiusMultiplier, accuracy: 1e-6)
    }
}
