import XCTest
@testable import VelstriaCore

/// スキル・スペルのテスト用ワールド（本番のマップ・マスター・ヒーロー定義、ユニットは手動配置）。
/// tick() は Simulation と同じ順で戦闘系・スキル・経済（回復）を回す（入力・出現・死亡処理・勝敗は除く）。
/// autoReveal = true の間は毎 tick 全ユニットを両チームから可視にする（視界テストでは false にして VisionSystem を回す）。
struct SkillWorld {
    var s: SimState
    let ctx: SimContext
    var autoReveal = true
    /// tick() で発生したイベント（古い順）。
    var log: [SimEvent] = []

    static let standardContext: SimContext = {
        let cfg = MatchConfig(mode: .standard, seed: 1, players: [])
        return SimContext(master: .shared, config: cfg)
    }()

    static let practiceContext: SimContext = {
        let cfg = MatchConfig(mode: .practice, seed: 1, players: [],
                              practice: PracticeOptions(noCooldowns: true, spawnMinions: false, spawnDummies: false))
        return SimContext(master: .shared, config: cfg)
    }()

    private static let seededLock = NSLock()
    nonisolated(unsafe) private static var seededContexts: [UInt64: SimContext] = [:]

    /// 乱数の種だけを変えた standard の文脈（種ごとにキャッシュ。NavGrid の構築が重いので使い回す）。
    static func standardContext(seed: UInt64) -> SimContext {
        if seed == 1 { return standardContext }
        seededLock.lock()
        defer { seededLock.unlock() }
        if let c = seededContexts[seed] { return c }
        let c = SimContext(master: .shared, config: MatchConfig(mode: .standard, seed: seed, players: []))
        seededContexts[seed] = c
        return c
    }

    /// seed は SimState.rng（会心などの抽選）の種。既定 1 は従来と同じ。noCooldowns と同時には指定できない（種は 1 固定）。
    init(noCooldowns: Bool = false, seed: UInt64 = 1) {
        ctx = noCooldowns ? SkillWorld.practiceContext : SkillWorld.standardContext(seed: seed)
        s = SimState(config: ctx.config)
        s.phase = .playing
        // EconomySystem の初回処理（tick == 1 の開始レベル反映）を避ける
        s.tick = 30
        s.time = 1
    }

    /// ヒーローを配置する。ranks = [Skill1, Skill2, Ult]（nil なら自動習得）。
    @discardableResult
    mutating func addHero(_ heroID: String, team: Team, at pos: Vec2, level: Int = 1, ranks: [Int]? = [1, 1, 1],
                          spells: [String] = ["BS01", "BS03"], facing: Double? = nil) -> Int {
        let def = ctx.master.hero(heroID)!
        let slot = PlayerSlot(team: team, heroID: heroID, controller: .bot,
                              position: MatchFactory.defaultPosition(for: def.role), spells: spells,
                              displayName: heroID)
        var u = UnitFactory.makeHero(def: def, slot: slot, pos: pos)
        u.hero!.level = level
        u.visibleMask = Team.blue.visionBit | Team.red.visionBit
        if let facing { u.facing = facing }
        let id = s.addUnit(u)
        let i = s.index(of: id)!
        StatCalculator.recompute(&s, i, ctx)
        s.units[i].hp = s.units[i].stats.maxHP
        s.units[i].resource = s.units[i].stats.maxResource
        if let ranks {
            s.units[i].hero!.skillRanks = [1] + ranks
            s.units[i].hero!.skillPoints = 0
        } else {
            s.units[i].hero!.skillPoints = level
            SkillLeveling.autoLevel(&s, ctx, heroIndex: i)
        }
        return i
    }

    @discardableResult
    mutating func addMinion(_ type: MinionType = .melee, team: Team, at pos: Vec2) -> Int {
        var u = UnitFactory.makeMinion(type: type, team: team, lane: .mid, pos: pos, time: 0)
        u.visibleMask = Team.blue.visionBit | Team.red.visionBit
        let id = s.addUnit(u)
        return s.index(of: id)!
    }

    @discardableResult
    mutating func addMonster(_ kind: MonsterKind, at pos: Vec2) -> Int {
        var u = UnitFactory.makeMonster(kind: kind, campID: 0, pos: pos)
        u.visibleMask = Team.blue.visionBit | Team.red.visionBit
        let id = s.addUnit(u)
        return s.index(of: id)!
    }

    @discardableResult
    mutating func addTower(team: Team, at pos: Vec2) -> Int {
        let u = UnitFactory.makeStructure(TowerSpot(team: team, lane: .mid, tier: .outer, pos: pos, isCore: false))
        let id = s.addUnit(u)
        return s.index(of: id)!
    }

    func id(_ i: Int) -> EntityID { s.units[i].id }

    @discardableResult
    mutating func cast(_ i: Int, _ slot: SkillSlot, _ target: SkillTarget = .none) -> Bool {
        let ok = SkillSystem.cast(&s, ctx, heroIndex: i, slot: slot, target: target)
        flushEvents()
        return ok
    }

    @discardableResult
    mutating func castSpell(_ i: Int, _ index: Int, _ target: SkillTarget = .none) -> Bool {
        let ok = SpellSystem.cast(&s, ctx, heroIndex: i, spellIndex: index, target: target)
        flushEvents()
        return ok
    }

    mutating func flushEvents() {
        log.append(contentsOf: s.events)
        s.events.removeAll(keepingCapacity: true)
    }

    mutating func tick(_ n: Int = 1) {
        for _ in 0..<n {
            s.tick += 1
            s.time = Double(s.tick) * Balance.dt
            for i in s.units.indices { s.units[i].prevPos = s.units[i].pos }
            for i in s.projectiles.indices { s.projectiles[i].prevPos = s.projectiles[i].pos }
            StatusSystem.update(&s, ctx)
            for i in s.units.indices { StatCalculator.recompute(&s, i, ctx) }
            RecallSystem.update(&s, ctx)
            MovementSystem.update(&s, ctx)
            CombatSystem.updateAttacks(&s, ctx)
            ProjectileSystem.update(&s, ctx)
            ZoneSystem.update(&s, ctx)
            SkillSystem.update(&s, ctx)
            SpellSystem.update(&s, ctx)
            EconomySystem.update(&s, ctx)
            if autoReveal {
                for i in s.units.indices { s.units[i].visibleMask = Team.blue.visionBit | Team.red.visionBit }
            } else if s.tick % Balance.visionUpdateEveryTicks == 0 {
                VisionSystem.update(&s, ctx)
            }
            flushEvents()
        }
    }

    /// 秒数ぶん進める。
    mutating func run(seconds: Double) { tick(Int((seconds * Balance.tickRate).rounded(.up))) }

    var damageEvents: [DamageEvent] {
        log.compactMap { if case .damage(let d) = $0 { return d } else { return nil } }
    }

    func damage(to i: Int, from source: DamageSource? = nil) -> Double {
        let target = s.units[i].id
        return damageEvents.filter { $0.targetID == target && (source == nil || $0.source == source) }
            .reduce(0) { $0 + $1.amount }
    }

    var castEvents: [SkillCastEvent] {
        log.compactMap { if case .skillCast(let e) = $0 { return e } else { return nil } }
    }

    func numbers(_ i: Int, _ slot: SkillSlot) -> SkillNumbers {
        let h = s.units[i].hero!
        let def = ctx.master.hero(h.heroID)!
        let skill = ctx.master.skill(hero: h.heroID, slot: slot)!
        return SkillCatalog.numbers(for: skill, hero: def, rank: max(1, h.rank(slot)), stats: s.units[i].stats)
    }

    func targeting(_ i: Int, _ slot: SkillSlot) -> SkillTargeting {
        let h = s.units[i].hero!
        let def = ctx.master.hero(h.heroID)!
        return SkillCatalog.targeting(for: ctx.master.skill(hero: h.heroID, slot: slot)!, hero: def)
    }

    /// 生ダメージ → 実ダメージ（防御・魔防のみ。与ダメ補正・被ダメ軽減なし）。
    func mitigated(_ raw: Double, _ type: DamageType, on i: Int) -> Double {
        raw * CombatSystem.mitigationMultiplier(type, armor: s.units[i].stats.armor,
                                                magicResist: s.units[i].stats.magicResist)
    }
}

/// 開けた場所（mid レーン中央付近、障害物・草むらなし）。
let skillArena = Vec2(5200, 5200)

final class SkillArchetypeTests: XCTestCase {

    func testArenaIsOpen() {
        let ctx = SkillWorld.standardContext
        for dx in stride(from: -1000.0, through: 1000, by: 100) {
            let p = skillArena + Vec2(dx, dx)
            XCTAssertTrue(ctx.nav.isWalkable(p, radius: 60), "\(p)")
            XCTAssertNil(ctx.map.brushIndex(at: p), "\(p)")
        }
    }

    // MARK: - カタログ

    func testEverySkillHasTargetingPerDesign() {
        let m = MasterData.shared
        XCTAssertEqual(m.skills.filter { $0.slot != .passive }.count, 102)
        for hero in m.heroes {
            for skill in m.skills(forHero: hero.heroID) {
                // 汎用の設計（キットの上書きを含まない）を検証する
                let t = SkillCatalog.genericTargeting(for: skill, hero: hero)
                switch skill.slot {
                case .passive:
                    XCTAssertEqual(t.archetype, .passive)
                case .skill1:
                    XCTAssertEqual(t.archetype, hero.isRanged ? .lineSkillshot : .cone, skill.skillID)
                    XCTAssertEqual(t.aim, .direction)
                    XCTAssertEqual(t.range, skill.range)
                    if hero.isRanged { XCTAssertEqual(t.radius, skill.radius * 0.5, accuracy: 1e-9) }
                case .skill2:
                    XCTAssertEqual(t.archetype, hero.isRanged ? .blinkEmpower : .dashStrike, skill.skillID)
                    XCTAssertEqual(t.range, hero.isRanged ? 350 : skill.range + 100)
                case .ultimate:
                    let expected: SkillArchetype
                    switch hero.role {
                    case .vanguard: expected = .leapSlam
                    case .duelist: expected = .multiStrike
                    case .ranger: expected = .piercingLine
                    case .arcanist: expected = .groundAoE
                    case .support: expected = .teamHeal
                    case .assassin: expected = .targetedBlink
                    }
                    XCTAssertEqual(t.archetype, expected, skill.skillID)
                }
                if skill.slot != .passive {
                    XCTAssertGreaterThan(t.range + t.radius, 0, skill.skillID)
                }
            }
        }
    }

    func testUltimateGeometryModifiers() {
        let m = MasterData.shared
        let vUlt = m.skill(hero: "H001", slot: .ultimate)!
        let v = SkillCatalog.targeting(for: vUlt, hero: m.hero("H001")!)
        XCTAssertEqual(v.range, vUlt.range + 200)
        XCTAssertEqual(v.radius, vUlt.radius * 1.4, accuracy: 1e-9)
        let rUlt = m.skill(hero: "H003", slot: .ultimate)!
        let r = SkillCatalog.targeting(for: rUlt, hero: m.hero("H003")!)
        XCTAssertEqual(r.range, 2000)
        XCTAssertEqual(r.radius, rUlt.radius)
        let aUlt = m.skill(hero: "H004", slot: .ultimate)!
        let a = SkillCatalog.targeting(for: aUlt, hero: m.hero("H004")!)
        XCTAssertEqual(a.radius, aUlt.radius * 1.8, accuracy: 1e-9)
        let sUlt = m.skill(hero: "H005", slot: .ultimate)!
        XCTAssertEqual(SkillCatalog.targeting(for: sUlt, hero: m.hero("H005")!).range, 1500)
        let asUlt = m.skill(hero: "H006", slot: .ultimate)!
        let asT = SkillCatalog.targeting(for: asUlt, hero: m.hero("H006")!)
        XCTAssertEqual(asT.aim, .unit)
        XCTAssertEqual(asT.range, asUlt.range)
    }

    func testNumbersFollowDesignFormulaAndRankScaling() {
        let m = MasterData.shared
        let hero = m.hero("H001")!
        let skill = m.skill(hero: "H001", slot: .skill1)!
        var st = Stats()
        st.attack = 200
        st.abilityPower = 50
        st.cooldownReduction = 0.1
        for rank in 1...4 {
            let n = SkillCatalog.numbers(for: skill, hero: hero, rank: rank, stats: st)
            let raw = skill.baseDamage * (1 + 0.30 * Double(rank - 1)) + skill.scalingAttack * 200 * 0.6
                + skill.scalingPower * 50
            XCTAssertEqual(n.damage, raw * Balance.Skills.damageScale(.skill1), accuracy: 1e-9)
            let cd = skill.cooldownSec * (1 - 0.06 * Double(rank - 1)) * 0.9 * Balance.Skills.cooldownScale
            XCTAssertEqual(n.cooldown, cd, accuracy: 1e-9)
            XCTAssertEqual(n.cost, skill.cost)
            XCTAssertEqual(n.cc, skill.cc)
            XCTAssertEqual(n.ccDuration, Balance.knockbackTime + Balance.knockbackStun)
        }
        // ランクが上がるほど強く・短く
        let r1 = SkillCatalog.numbers(for: skill, hero: hero, rank: 1, stats: st)
        let r4 = SkillCatalog.numbers(for: skill, hero: hero, rank: 4, stats: st)
        XCTAssertGreaterThan(r4.damage, r1.damage)
        XCTAssertLessThan(r4.cooldown, r1.cooldown)
        // 範囲外のランクは丸める
        XCTAssertEqual(SkillCatalog.numbers(for: skill, hero: hero, rank: 9, stats: st).rank, 4)
        XCTAssertEqual(SkillCatalog.numbers(for: skill, hero: hero, rank: 0, stats: st).rank, 1)
        // CD 短縮は 40% で頭打ち
        st.cooldownReduction = 0.9
        let capped = SkillCatalog.numbers(for: skill, hero: hero, rank: 1, stats: st)
        XCTAssertEqual(capped.cooldown, skill.cooldownSec * 0.6 * Balance.Skills.cooldownScale, accuracy: 1e-9)
    }

    func testNumbersArchetypeExtras() {
        let m = MasterData.shared
        let st = HeroGrowth.baseStats(def: m.hero("H002")!, level: 8)
        let duel = SkillCatalog.numbers(for: m.skill(hero: "H002", slot: .ultimate)!, hero: m.hero("H002")!, rank: 2,
                                        stats: st)
        XCTAssertEqual(duel.hits, 3)
        XCTAssertEqual(duel.damageReduction, 0.25)
        XCTAssertEqual(duel.ccDuration, Balance.ultStunDuration)
        XCTAssertEqual(duel.cost, m.skill(hero: "H002", slot: .ultimate)!.cost * 0.6, accuracy: 1e-9, "Energy は ×0.6")

        let ranger = m.hero("H003")!
        let blink = SkillCatalog.numbers(for: m.skill(hero: "H003", slot: .skill2)!, hero: ranger, rank: 1,
                                         stats: HeroGrowth.baseStats(def: ranger, level: 1))
        let skill = m.skill(hero: "H003", slot: .skill2)!
        let full = (skill.baseDamage + skill.scalingAttack * ranger.baseAttack * 0.6) * Balance.Skills.damageScale(.skill2)
        XCTAssertEqual(blink.damage, full * 0.5, accuracy: 1e-6)

        let support = m.hero("H005")!
        let sst = HeroGrowth.baseStats(def: support, level: 6)
        let team = SkillCatalog.numbers(for: m.skill(hero: "H005", slot: .ultimate)!, hero: support, rank: 1, stats: sst)
        XCTAssertEqual(team.damage, 0)
        XCTAssertEqual(team.shield, team.heal * 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan(team.heal, 0)

        let assassin = m.hero("H006")!
        let exec = SkillCatalog.numbers(for: m.skill(hero: "H006", slot: .ultimate)!, hero: assassin, rank: 1,
                                        stats: HeroGrowth.baseStats(def: assassin, level: 6))
        XCTAssertEqual(exec.missingHealthRatio, 0.12)
        let arc = SkillCatalog.numbers(for: m.skill(hero: "H004", slot: .ultimate)!, hero: m.hero("H004")!, rank: 1,
                                       stats: HeroGrowth.baseStats(def: m.hero("H004")!, level: 6))
        XCTAssertEqual(arc.delay, 1.0)
    }

    // MARK: - 検証（CD・コスト・CC・ランク）

    func testCastValidationRankCooldownCostAndCrowdControl() {
        var w = SkillWorld()
        let a = w.addHero("H001", team: .blue, at: skillArena, ranks: [0, 1, 1])
        w.addHero("H003", team: .red, at: skillArena + Vec2(200, 0))
        // ランク 0
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: a, slot: .skill1))
        XCTAssertFalse(w.cast(a, .skill1, .direction(Vec2(1, 0))))
        XCTAssertFalse(w.cast(a, .passive))
        // 発動 → CD とコスト
        let before = w.s.units[a].resource
        let n = w.numbers(a, .skill2)
        XCTAssertTrue(w.cast(a, .skill2))
        XCTAssertEqual(w.s.units[a].resource, before - n.cost, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[a].hero!.cooldown(.skill2), n.cooldown, accuracy: 1e-9)
        XCTAssertFalse(w.cast(a, .skill2), "CD 中")
        w.run(seconds: n.cooldown + 0.05)
        XCTAssertTrue(SkillSystem.canCast(w.s, w.ctx, heroIndex: a, slot: .skill2))
        // リソース不足
        w.s.units[a].resource = n.cost - 1
        XCTAssertFalse(w.cast(a, .skill2))
        w.s.units[a].resource = n.cost
        // 沈黙・スタンでは不可、スロー・ルートでは可
        CombatSystem.addStatus(&w.s, targetIndex: a, StatusEffect(kind: .silence, duration: 1))
        XCTAssertFalse(w.cast(a, .skill2))
        w.s.units[a].statuses.removeAll()
        CombatSystem.addStatus(&w.s, targetIndex: a, StatusEffect(kind: .stun, duration: 1))
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: a, slot: .skill2))
        w.s.units[a].statuses.removeAll()
        CombatSystem.addStatus(&w.s, targetIndex: a, StatusEffect(kind: .root, duration: 1))
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: a, slot: .skill2), "ルート中は突進できない")
        XCTAssertFalse(w.cast(a, .skill2, .direction(Vec2(1, 0))))
        var r = SkillWorld()
        let ranger = r.addHero("H003", team: .blue, at: skillArena)
        CombatSystem.addStatus(&r.s, targetIndex: ranger, StatusEffect(kind: .root, duration: 1))
        XCTAssertTrue(r.cast(ranger, .skill2, .direction(Vec2(1, 0))), "ブリンクはルート中も可")
        // 死亡中
        var d = SkillWorld()
        let dead = d.addHero("H001", team: .blue, at: skillArena)
        d.s.units[dead].isAlive = false
        XCTAssertFalse(d.cast(dead, .skill2))
    }

    func testEnergyHeroesPaySixtyPercent() {
        var w = SkillWorld()
        let a = w.addHero("H002", team: .blue, at: skillArena)
        XCTAssertEqual(w.s.units[a].hero!.resourceKind, .energy)
        let skill = w.ctx.master.skill(hero: "H002", slot: .skill1)!
        let before = w.s.units[a].resource
        XCTAssertTrue(w.cast(a, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(before - w.s.units[a].resource, skill.cost * 0.6, accuracy: 1e-9)
    }

    func testPracticeNoCooldownsKeepsCooldownsZeroAndCastsFree() {
        var w = SkillWorld(noCooldowns: true)
        let a = w.addHero("H004", team: .blue, at: skillArena)
        w.s.units[a].resource = 0
        for _ in 0..<3 {
            XCTAssertTrue(w.cast(a, .skill1, .direction(Vec2(1, 0))))
            XCTAssertEqual(w.s.units[a].hero!.cooldown(.skill1), 0)
        }
        XCTAssertEqual(w.s.units[a].resource, 0)
        XCTAssertTrue(w.cast(a, .ultimate, .point(skillArena + Vec2(300, 0))))
        w.tick()
        XCTAssertEqual(w.s.units[a].hero!.cooldown(.ultimate), 0)
    }

    func testCastCancelsWindupSetsFacingAndEmitsEvent() {
        var w = SkillWorld()
        let a = w.addHero("H003", team: .blue, at: skillArena)
        let t = w.addHero("H001", team: .red, at: skillArena + Vec2(0, 400))
        w.s.units[a].windupRemaining = 0.1
        XCTAssertTrue(w.cast(a, .skill1, .none))
        XCTAssertNil(w.s.units[a].windupRemaining)
        XCTAssertEqual(w.s.units[a].facing, Double.pi / 2, accuracy: 1e-9, "自動照準で敵ヒーローへ向く")
        let e = w.castEvents.last!
        XCTAssertEqual(e.casterID, w.id(a))
        XCTAssertEqual(e.slot, .skill1)
        XCTAssertEqual(e.archetype, .lineSkillshot)
        XCTAssertEqual(e.effectID, "FX_SK_003_2")
        XCTAssertEqual(e.skillID, "SK003_2")
        XCTAssertEqual(e.origin, skillArena)
        XCTAssertEqual(e.targetUnitID, w.id(t))
        XCTAssertEqual(e.range, w.targeting(a, .skill1).range)
        XCTAssertEqual(e.radius, w.targeting(a, .skill1).radius)
    }

    // MARK: - 自動照準

    func testAutoAimPrefersVisibleHeroThenNearestEnemyThenFacing() {
        var w = SkillWorld()
        let a = w.addHero("H003", team: .blue, at: skillArena, facing: 0)
        w.addMinion(team: .red, at: skillArena + Vec2(0, 300))
        let hero = w.addHero("H001", team: .red, at: skillArena + Vec2(0, -500))
        XCTAssertTrue(w.cast(a, .skill1))
        XCTAssertEqual(w.castEvents.last?.targetUnitID, w.id(hero), "ヒーロー優先")
        // 見えないヒーローは狙わない → 最寄りの敵（ミニオン）
        var w2 = SkillWorld()
        let a2 = w2.addHero("H003", team: .blue, at: skillArena, facing: 0)
        let m2 = w2.addMinion(team: .red, at: skillArena + Vec2(0, 300))
        let h2 = w2.addHero("H001", team: .red, at: skillArena + Vec2(0, -500))
        w2.s.units[h2].visibleMask = Team.red.visionBit
        XCTAssertTrue(w2.cast(a2, .skill1))
        XCTAssertEqual(w2.castEvents.last?.targetUnitID, w2.id(m2))
        // 誰も居なければ向いている方向
        var w3 = SkillWorld()
        let a3 = w3.addHero("H003", team: .blue, at: skillArena, facing: Double.pi)
        XCTAssertTrue(w3.cast(a3, .skill1))
        let e = w3.castEvents.last!
        XCTAssertNil(e.targetUnitID)
        XCTAssertEqual(e.target.x, skillArena.x - w3.targeting(a3, .skill1).range, accuracy: 1e-6)
    }

    func testPointTargetIsClampedToRange() {
        var w = SkillWorld()
        let a = w.addHero("H004", team: .blue, at: skillArena, level: 6)
        let range = w.targeting(a, .ultimate).range
        XCTAssertTrue(w.cast(a, .ultimate, .point(skillArena + Vec2(5000, 0))))
        XCTAssertEqual(w.castEvents.last!.target.x, skillArena.x + range, accuracy: 1e-6)
        XCTAssertEqual(w.s.zones.last!.center.x, skillArena.x + range, accuracy: 1e-6)
    }

    // MARK: - アーキタイプ

    func testConeHitsInsideNinetyDegreesOnlyAndAppliesKnockback() {
        var w = SkillWorld()
        let a = w.addHero("H001", team: .blue, at: skillArena)   // Skill1: 扇形 range 300, Knockback
        let front = w.addHero("H003", team: .red, at: skillArena + Vec2(200, 0))
        let edge = w.addMinion(team: .red, at: skillArena + Vec2(150, 140))   // 約 43°
        let side = w.addMinion(team: .red, at: skillArena + Vec2(0, 250))     // 90°
        let behind = w.addMinion(team: .red, at: skillArena + Vec2(-200, 0))
        let far = w.addMinion(team: .red, at: skillArena + Vec2(420, 0))
        let ally = w.addMinion(team: .blue, at: skillArena + Vec2(100, 0))
        let tower = w.addTower(team: .red, at: skillArena + Vec2(250, -120))
        let n = w.numbers(a, .skill1)
        XCTAssertTrue(w.cast(a, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.damage(to: front), w.mitigated(n.damage, .magic, on: front), accuracy: 1e-6)
        XCTAssertGreaterThan(w.damage(to: edge), 0)
        XCTAssertEqual(w.damage(to: side), 0)
        XCTAssertEqual(w.damage(to: behind), 0)
        XCTAssertEqual(w.damage(to: far), 0)
        XCTAssertEqual(w.damage(to: ally), 0)
        XCTAssertEqual(w.damage(to: tower), 0, "構造物にはスキルが当たらない")
        XCTAssertNotNil(w.s.units[front].displacement, "ノックバック")
        XCTAssertGreaterThan(w.s.units[front].displacement!.to.x, w.s.units[front].pos.x)
    }

    func testLineSkillshotHitsFirstEnemyOnlyAndCanMiss() {
        var w = SkillWorld()
        let a = w.addHero("H004", team: .blue, at: skillArena)   // Skill1 直線 range 650, Slow
        let first = w.addHero("H013", team: .red, at: skillArena + Vec2(300, 0))
        let second = w.addMinion(team: .red, at: skillArena + Vec2(500, 0))
        let offLine = w.addHero("H002", team: .red, at: skillArena + Vec2(300, 300))
        XCTAssertTrue(w.cast(a, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.s.projectiles.last?.width, w.targeting(a, .skill1).radius)
        XCTAssertEqual(w.s.projectiles.last?.speed, 1600)
        w.run(seconds: 0.6)
        XCTAssertGreaterThan(w.damage(to: first), 0)
        XCTAssertTrue(w.s.units[first].has(.slow))
        XCTAssertEqual(w.damage(to: second), 0, "最初の 1 体で止まる")
        XCTAssertEqual(w.damage(to: offLine), 0)
        // 射程外には届かない
        var w2 = SkillWorld()
        let a2 = w2.addHero("H004", team: .blue, at: skillArena)
        let beyond = w2.addHero("H001", team: .red, at: skillArena + Vec2(900, 0))
        XCTAssertTrue(w2.cast(a2, .skill1, .direction(Vec2(1, 0))))
        w2.run(seconds: 1)
        XCTAssertEqual(w2.damage(to: beyond), 0)
        XCTAssertTrue(w2.s.projectiles.allSatisfy(\.done))
    }

    func testPiercingLineHitsEveryEnemyAlongTwoThousandUnits() {
        var w = SkillWorld()
        let a = w.addHero("H003", team: .blue, at: skillArena, level: 6)   // Ult: Knockback
        let targets = [300.0, 900, 1600].map { w.addMinion(team: .red, at: skillArena + Vec2($0, $0)) }
        let hero = w.addHero("H001", team: .red, at: skillArena + Vec2(1300, 1300))
        let tooFar = w.addMinion(team: .red, at: skillArena + Vec2(1500, 1500) * 1.0 + Vec2(100, 100))
        XCTAssertTrue(w.cast(a, .ultimate, .point(skillArena + Vec2(10, 10))))
        w.run(seconds: 1.5)
        for t in targets.prefix(2) { XCTAssertGreaterThan(w.damage(to: t), 0) }
        XCTAssertGreaterThan(w.damage(to: hero), 0)
        // 2000 を超えた位置（中心距離 ~2263）には届かない
        XCTAssertEqual(w.damage(to: tooFar), 0)
        XCTAssertTrue(w.log.contains {
            if case .ccApplied(let id, .knockback, _) = $0 { return id == w.id(hero) } else { return false }
        })
    }

    func testDashStrikeMovesCasterAndHitsAtLanding() {
        var w = SkillWorld()
        let a = w.addHero("H001", team: .blue, at: skillArena)   // Skill2: range 300 → 400, radius 120, Root
        let target = w.addHero("H003", team: .red, at: skillArena + Vec2(450, 0))
        let start = w.addMinion(team: .red, at: skillArena + Vec2(-60, 0))
        XCTAssertTrue(w.cast(a, .skill2, .direction(Vec2(1, 0))))
        XCTAssertNotNil(w.s.units[a].displacement)
        let landing = w.s.units[a].displacement!.to
        XCTAssertEqual(landing.x, skillArena.x + 400, accuracy: 1)
        // 着地前はまだ当たらない
        w.tick()
        XCTAssertEqual(w.damage(to: target), 0)
        w.run(seconds: 0.4)
        XCTAssertNil(w.s.units[a].displacement)
        XCTAssertEqual(w.s.units[a].pos.x, landing.x, accuracy: 1)
        XCTAssertGreaterThan(w.damage(to: target), 0)
        XCTAssertTrue(w.s.units[target].has(.root))
        XCTAssertEqual(w.damage(to: start), 0, "出発点の敵には当たらない")
    }

    func testDashStrikeTowardUnitStopsAtItsEdge() {
        var w = SkillWorld()
        let a = w.addHero("H006", team: .blue, at: skillArena)   // Assassin Skill2: range 650 → 750
        let t = w.addHero("H003", team: .red, at: skillArena + Vec2(500, 0))
        XCTAssertTrue(w.cast(a, .skill2, .unit(w.id(t))))
        XCTAssertEqual(w.s.units[a].displacement!.to.x, skillArena.x + 500 - 55, accuracy: 1)
        w.run(seconds: 0.5)
        XCTAssertGreaterThan(w.damage(to: t), 0)
    }

    func testBlinkEmpowerMovesAndEmpowersNextAttack() {
        var w = SkillWorld()
        let a = w.addHero("H003", team: .blue, at: skillArena)   // Skill2: Slow
        let t = w.addHero("H001", team: .red, at: skillArena + Vec2(700, 0))
        let n = w.numbers(a, .skill2)
        w.s.units[a].attackCooldown = 0.8
        XCTAssertTrue(w.cast(a, .skill2, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.s.units[a].pos.x, skillArena.x + 350, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[a].hero!.empoweredAttack?.bonusDamage ?? 0, n.damage, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[a].hero!.empoweredAttack?.cc, .slow)
        XCTAssertEqual(w.s.units[a].attackCooldown, 0, "攻撃間隔をリセット")
        XCTAssertTrue(w.log.contains { if case .blinked = $0 { return true } else { return false } })
        w.s.units[a].attackTargetID = w.id(t)
        w.run(seconds: 1.0)
        XCTAssertNil(w.s.units[a].hero!.empoweredAttack)
        XCTAssertTrue(w.s.units[t].has(.slow))
        let bonus = w.damageEvents.filter { $0.targetID == w.id(t) && $0.damageType == .physical }.count
        XCTAssertGreaterThanOrEqual(bonus, 2, "通常攻撃 + 強化分")
    }

    func testGroundAoETelegraphThenHits() {
        var w = SkillWorld()
        let a = w.addHero("H004", team: .blue, at: skillArena, level: 6)   // Ult: radius 155 × 1.8、予告 1.0 秒
        let center = skillArena + Vec2(500, 0)
        let inside = w.addHero("H001", team: .red, at: center + Vec2(100, 0))
        let outside = w.addMinion(team: .red, at: center + Vec2(0, 420))
        XCTAssertTrue(w.cast(a, .ultimate, .point(center)))
        XCTAssertEqual(w.s.zones.last?.delay, 1.0)
        w.run(seconds: 0.9)
        XCTAssertEqual(w.damage(to: inside), 0, "予告中")
        w.run(seconds: 0.2)
        XCTAssertGreaterThan(w.damage(to: inside), 0)
        XCTAssertEqual(w.damage(to: outside), 0)
        // 予告中に避ければ当たらない
        var w2 = SkillWorld()
        let a2 = w2.addHero("H004", team: .blue, at: skillArena, level: 6)
        let dodger = w2.addHero("H001", team: .red, at: center)
        XCTAssertTrue(w2.cast(a2, .ultimate, .point(center)))
        w2.tick(5)
        w2.s.units[dodger].pos = center + Vec2(0, 700)
        w2.run(seconds: 1.2)
        XCTAssertEqual(w2.damage(to: dodger), 0)
    }

    func testArcanistUltimateHasLongerTelegraphAndLargerRadius() {
        var w = SkillWorld()
        let a = w.addHero("H004", team: .blue, at: skillArena, level: 6)   // Ult: radius 155 × 1.8 = 279, Root
        let center = skillArena + Vec2(600, 0)
        let t = w.addHero("H001", team: .red, at: center + Vec2(0, 250))
        XCTAssertTrue(w.cast(a, .ultimate, .point(center)))
        XCTAssertEqual(w.s.zones.last!.radius, 155 * 1.8, accuracy: 1e-9)
        w.run(seconds: 0.9)
        XCTAssertEqual(w.damage(to: t), 0)
        w.run(seconds: 0.2)
        XCTAssertGreaterThan(w.damage(to: t), 0)
        XCTAssertEqual(w.s.units[t].status(.root)?.duration ?? 0, Balance.ultRootDuration, accuracy: 1e-9)
    }

    func testLeapSlamLeapsAndSlamsWithUltimateCC() {
        var w = SkillWorld()
        let a = w.addHero("H001", team: .blue, at: skillArena, level: 6)   // Ult: range 420 → 620, radius 190 × 1.4, Slow
        let t = w.addHero("H003", team: .red, at: skillArena + Vec2(900, 0))
        let edge = w.addMinion(team: .red, at: skillArena + Vec2(620 + 250, 0))
        XCTAssertTrue(w.cast(a, .ultimate, .point(skillArena + Vec2(2000, 0))))
        XCTAssertEqual(w.s.units[a].displacement?.kind, .leap)
        XCTAssertEqual(w.s.units[a].displacement!.to.x, skillArena.x + 620, accuracy: 1)
        w.run(seconds: 0.6)
        XCTAssertGreaterThan(w.damage(to: t), 0)
        XCTAssertGreaterThan(w.damage(to: edge), 0)
        XCTAssertEqual(w.s.units[t].status(.slow)?.magnitude ?? 0, Balance.ultSlowPct, accuracy: 1e-9)
    }

    func testMultiStrikeHitsHeroesThreeTimesAndReducesDamage() {
        var w = SkillWorld()
        let a = w.addHero("H002", team: .blue, at: skillArena, level: 6)   // Ult: radius 225, Stun
        let t = w.addHero("H003", team: .red, at: skillArena + Vec2(200, 0))
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(0, 100))
        // 範囲内に敵ヒーローが居なければ発動しない
        var w0 = SkillWorld()
        let a0 = w0.addHero("H002", team: .blue, at: skillArena, level: 6)
        w0.addMinion(team: .red, at: skillArena + Vec2(100, 0))
        w0.addHero("H003", team: .red, at: skillArena + Vec2(600, 0))
        XCTAssertFalse(w0.cast(a0, .ultimate))
        XCTAssertEqual(w0.s.units[a0].hero!.cooldown(.ultimate), 0)

        let n = w.numbers(a, .ultimate)
        XCTAssertTrue(w.cast(a, .ultimate))
        XCTAssertTrue(w.s.units[a].has(.damageReduction))
        XCTAssertEqual(w.s.units[a].status(.damageReduction)?.magnitude ?? 0, 0.25)
        w.tick()
        XCTAssertEqual(w.damageEvents.filter { $0.targetID == w.id(t) }.count, 1)
        w.run(seconds: 0.7)
        let hits = w.damageEvents.filter { $0.targetID == w.id(t) && $0.source == .skill(.ultimate) }
        XCTAssertEqual(hits.count, 3)
        XCTAssertEqual(hits[0].amount, w.mitigated(n.damage, .physical, on: t), accuracy: 1e-6)
        XCTAssertEqual(w.damage(to: minion), 0, "ヒーローのみ")
        XCTAssertTrue(w.log.contains {
            if case .ccApplied(let id, .stun, let d) = $0 { return id == w.id(t) && d == Balance.ultStunDuration }
            return false
        })
        w.run(seconds: 1.5)
        XCTAssertFalse(w.s.units[a].has(.damageReduction), "2 秒で切れる")
    }

    func testTeamHealHealsAlliesWithinRangeAndCrowdControlsNearbyEnemies() {
        var w = SkillWorld()
        let a = w.addHero("H017", team: .blue, at: skillArena, level: 6)   // Support Ult: radius 190, Stun
        let near = w.addHero("H001", team: .blue, at: skillArena + Vec2(1200, 0))
        let far = w.addHero("H002", team: .blue, at: skillArena + Vec2(-1700, 0))
        let enemy = w.addHero("H003", team: .red, at: skillArena + Vec2(0, 200))
        let enemyFar = w.addHero("H004", team: .red, at: skillArena + Vec2(0, 600))
        w.s.units[near].hp = 500
        w.s.units[far].hp = 500
        w.s.units[a].hp = 800
        let n = w.numbers(a, .ultimate)
        XCTAssertTrue(w.cast(a, .ultimate))
        XCTAssertEqual(w.s.units[near].hp, 500 + n.heal, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[near].totalShield, n.shield, accuracy: 1e-6)
        XCTAssertGreaterThan(w.s.units[a].hp, 800 + n.heal - 1, "自身も回復")
        XCTAssertEqual(w.s.units[far].hp, 500)
        XCTAssertTrue(w.s.units[enemy].has(.stun))
        XCTAssertFalse(w.s.units[enemyFar].has(.stun))
        XCTAssertEqual(w.damage(to: enemy), 0)
    }

    func testTargetedBlinkNeedsHeroInRangeAndExecutes() {
        var w = SkillWorld()
        let a = w.addHero("H006", team: .blue, at: skillArena, level: 6)   // Ult: range 770, Slow
        let near = w.addHero("H001", team: .red, at: skillArena + Vec2(300, 0))
        let target = w.addHero("H003", team: .red, at: skillArena + Vec2(0, 700))
        w.addMinion(team: .red, at: skillArena + Vec2(100, 0))
        w.s.units[target].hp = 1000
        let n = w.numbers(a, .ultimate)
        XCTAssertTrue(w.cast(a, .ultimate, .unit(w.id(target))))
        // 対象の背後（術者から見て奥）
        XCTAssertEqual(w.s.units[a].pos.x, skillArena.x, accuracy: 1)
        XCTAssertGreaterThan(w.s.units[a].pos.y, w.s.units[target].pos.y)
        let missing = w.s.units[target].stats.maxHP - 1000
        XCTAssertEqual(w.damage(to: target), w.mitigated(n.damage + missing * 0.12, .physical, on: target),
                       accuracy: 1e-6)
        XCTAssertEqual(w.damage(to: near), 0)
        // .none は最寄りの敵ヒーロー、射程外なら失敗
        var w2 = SkillWorld()
        let a2 = w2.addHero("H006", team: .blue, at: skillArena, level: 6)
        let n2 = w2.addHero("H001", team: .red, at: skillArena + Vec2(400, 0))
        w2.addHero("H003", team: .red, at: skillArena + Vec2(0, 600))
        XCTAssertTrue(w2.cast(a2, .ultimate))
        XCTAssertEqual(w2.castEvents.last?.targetUnitID, w2.id(n2))
        var w3 = SkillWorld()
        let a3 = w3.addHero("H006", team: .blue, at: skillArena, level: 6)
        w3.addHero("H001", team: .red, at: skillArena + Vec2(1000, 0))
        w3.addMinion(team: .red, at: skillArena + Vec2(100, 0))
        XCTAssertFalse(w3.cast(a3, .ultimate))
        XCTAssertEqual(w3.s.units[a3].hero!.cooldown(.ultimate), 0)
        XCTAssertEqual(w3.s.units[a3].resource, w3.s.units[a3].stats.maxResource)
    }

    func testSkillsHitMonstersAndDummiesButNotStructures() {
        var w = SkillWorld()
        let a = w.addHero("H004", team: .blue, at: skillArena, level: 6)
        let center = skillArena + Vec2(400, 0)
        let monster = w.addMonster(.campSmall, at: center)
        let tower = w.addTower(team: .red, at: center + Vec2(0, 100))
        XCTAssertTrue(w.cast(a, .ultimate, .point(center)))
        w.run(seconds: 1.2)
        XCTAssertGreaterThan(w.damage(to: monster), 0)
        XCTAssertEqual(w.damage(to: tower), 0)
        XCTAssertEqual(w.s.units[tower].hp, w.s.units[tower].stats.maxHP)
    }

    func testEveryHeroCanCastEverySkill() {
        for hero in MasterData.shared.heroes {
            var w = SkillWorld()
            let a = w.addHero(hero.heroID, team: .blue, at: skillArena, level: 12, ranks: [4, 4, 3])
            let foe = w.addHero("H013", team: .red, at: skillArena + Vec2(250, 0), level: 12)
            for slot in SkillSlot.actives {
                XCTAssertTrue(w.cast(a, slot, .unit(w.id(foe))), "\(hero.heroID) \(slot)")
                w.run(seconds: 1.2)
                XCTAssertTrue(w.s.units[foe].isAlive)
                // 次のスキルのために全快・CC 解除・元の位置へ
                w.s.units[foe].hp = w.s.units[foe].stats.maxHP
                w.s.units[foe].statuses.removeAll()
                w.s.units[foe].displacement = nil
                w.s.units[foe].pos = w.s.units[a].pos + Vec2(250, 0)
            }
            XCTAssertEqual(w.castEvents.count, 3, hero.heroID)
            XCTAssertGreaterThan(w.damage(to: foe) + w.s.units[a].totalShield, 0, hero.heroID)
        }
    }
}
