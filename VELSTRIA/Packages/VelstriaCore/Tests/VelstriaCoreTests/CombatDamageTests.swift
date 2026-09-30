import XCTest
@testable import VelstriaCore

/// 戦闘テスト用の小さなワールド（マップ・マスターは本番、ユニットは能力値を固定して手動配置）。
/// tick() は戦闘系システム（状態 → 移動 → 通常攻撃 → 投射物 → ゾーン）だけを Simulation と同じ順に回す。
struct CombatWorld {
    var s: SimState
    let ctx: SimContext

    init(seed: UInt64 = 1) {
        let cfg = MatchConfig(mode: .practice, seed: seed, players: [],
                              practice: PracticeOptions(spawnMinions: false, spawnDummies: false))
        ctx = SimContext(master: .shared, config: cfg)
        s = SimState(config: cfg)
        s.phase = .playing
    }

    static func stats(hp: Double = 1000, attack: Double = 100, armor: Double = 0, magicResist: Double = 0,
                      range: Double = 150, attackSpeed: Double = 1, moveSpeed: Double = 300) -> Stats {
        var st = Stats()
        st.maxHP = hp
        st.attack = attack
        st.armor = armor
        st.magicResist = magicResist
        st.attackRange = range
        st.attackSpeed = attackSpeed
        st.moveSpeed = moveSpeed
        st.sightRange = 1200
        return st
    }

    @discardableResult
    mutating func addHero(team: Team, at pos: Vec2, ranged: Bool = false, stats: Stats = CombatWorld.stats()) -> Int {
        let def = ctx.master.hero("H001")!
        let slot = PlayerSlot(team: team, heroID: def.heroID, controller: .bot, position: .mid, displayName: "T")
        var u = UnitFactory.makeHero(def: def, slot: slot, pos: pos)
        u.hero?.isRanged = ranged
        return add(u, stats: stats)
    }

    @discardableResult
    mutating func addUnit(_ kind: UnitKind, team: Team, at pos: Vec2, radius: Double = 40,
                          stats: Stats = CombatWorld.stats()) -> Int {
        var u = VelstriaCore.Unit(id: 0, kind: kind, team: team, pos: pos, radius: radius, stats: stats)
        if kind == .monster { u.monster = MonsterData(kind: .campSmall, campID: 0, home: pos) }
        if kind == .tower { u.tower = TowerData(lane: .mid, tier: .outer) }
        return add(u, stats: stats)
    }

    @discardableResult
    mutating func addMinion(_ type: MinionType, team: Team, at pos: Vec2) -> Int {
        var u = UnitFactory.makeMinion(type: type, team: team, lane: .mid, pos: pos, time: 0)
        u.visibleMask = 3
        let id = s.addUnit(u)
        return s.index(of: id)!
    }

    private mutating func add(_ unit: VelstriaCore.Unit, stats: Stats) -> Int {
        var u = unit
        u.baseStats = stats
        u.stats = stats
        u.hp = stats.maxHP
        u.visibleMask = Team.blue.visionBit | Team.red.visionBit
        let id = s.addUnit(u)
        return s.index(of: id)!
    }

    func id(_ i: Int) -> EntityID { s.units[i].id }

    mutating func tick(_ n: Int = 1) {
        for _ in 0..<n {
            s.tick += 1
            s.time = Double(s.tick) * Balance.dt
            for i in s.units.indices { s.units[i].prevPos = s.units[i].pos }
            for i in s.projectiles.indices { s.projectiles[i].prevPos = s.projectiles[i].pos }
            StatusSystem.update(&s, ctx)
            MovementSystem.update(&s, ctx)
            CombatSystem.updateAttacks(&s, ctx)
            ProjectileSystem.update(&s, ctx)
            ZoneSystem.update(&s, ctx)
        }
    }

    var damageEvents: [DamageEvent] {
        s.events.compactMap { if case .damage(let d) = $0 { return d } else { return nil } }
    }
}

final class CombatDamageTests: XCTestCase {

    func testArmorMagicResistAndDamageReductionMitigation() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(1000, 1000))
        let t = w.addHero(team: .red, at: Vec2(1100, 1000),
                          stats: CombatWorld.stats(hp: 5000, armor: 100, magicResist: 50))
        let src = w.id(a)

        XCTAssertEqual(CombatSystem.applyDamage(&w.s, w.ctx, sourceID: src, targetIndex: t, amount: 200,
                                                type: .physical, source: .spell), 100, accuracy: 1e-9)
        XCTAssertEqual(CombatSystem.applyDamage(&w.s, w.ctx, sourceID: src, targetIndex: t, amount: 150,
                                                type: .magic, source: .spell), 100, accuracy: 1e-9)
        w.s.units[t].stats.damageReduction = 0.3
        XCTAssertEqual(CombatSystem.applyDamage(&w.s, w.ctx, sourceID: src, targetIndex: t, amount: 200,
                                                type: .physical, source: .spell), 70, accuracy: 1e-9)
        // 被ダメ軽減は 60% で頭打ち
        w.s.units[t].stats.damageReduction = 0.9
        XCTAssertEqual(CombatSystem.applyDamage(&w.s, w.ctx, sourceID: src, targetIndex: t, amount: 200,
                                                type: .physical, source: .spell), 40, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[t].hp, 5000 - 310, accuracy: 1e-9)
    }

    func testOutgoingBonusesDependOnSourceAndTarget() {
        var w = CombatWorld()
        var st = CombatWorld.stats()
        st.damageBonus = 0.2
        st.basicAttackDamageBonus = 0.1
        st.skillDamageBonus = 0.3
        st.monsterDamageBonus = 0.5
        let a = w.addHero(team: .blue, at: Vec2(1000, 1000), stats: st)
        let hero = w.addHero(team: .red, at: Vec2(1100, 1000), stats: CombatWorld.stats(hp: 10000))
        let monster = w.addUnit(.monster, team: .neutral, at: Vec2(1000, 1100), stats: CombatWorld.stats(hp: 10000))
        let src = w.id(a)

        func hit(_ t: Int, _ source: DamageSource) -> Double {
            CombatSystem.applyDamage(&w.s, w.ctx, sourceID: src, targetIndex: t, amount: 100, type: .trueDamage,
                                     source: source)
        }
        XCTAssertEqual(hit(hero, .basicAttack), 130, accuracy: 1e-9)
        XCTAssertEqual(hit(hero, .skill(.skill1)), 150, accuracy: 1e-9)
        XCTAssertEqual(hit(hero, .spell), 120, accuracy: 1e-9)
        XCTAssertEqual(hit(monster, .basicAttack), 180, accuracy: 1e-9)
        // 与ダメ補正の合計が −100% を下回っても負のダメージにはならない
        w.s.units[a].stats.damageBonus = -3
        XCTAssertEqual(hit(hero, .spell), 0)
    }

    func testTrueDamageIgnoresArmorButNotDamageReduction() {
        var w = CombatWorld()
        let t = w.addHero(team: .red, at: Vec2(1000, 1000),
                          stats: CombatWorld.stats(hp: 1000, armor: 300, magicResist: 300))
        XCTAssertEqual(CombatSystem.applyDamage(&w.s, w.ctx, sourceID: nil, targetIndex: t, amount: 120,
                                                type: .trueDamage, source: .dot), 120, accuracy: 1e-9)
        w.s.units[t].stats.damageReduction = 0.25
        XCTAssertEqual(CombatSystem.applyDamage(&w.s, w.ctx, sourceID: nil, targetIndex: t, amount: 100,
                                                type: .trueDamage, source: .dot), 75, accuracy: 1e-9)
        // 泉は環境ダメージで被ダメ軽減も受けない
        XCTAssertEqual(CombatSystem.applyDamage(&w.s, w.ctx, sourceID: nil, targetIndex: t, amount: 100,
                                                type: .trueDamage, source: .fountain), 100, accuracy: 1e-9)
    }

    func testShieldsAbsorbOldestFirstThenHP() {
        var w = CombatWorld()
        let t = w.addHero(team: .red, at: Vec2(1000, 1000))
        CombatSystem.addShield(&w.s, w.ctx, sourceID: nil, targetIndex: t, amount: 50, duration: 5, tag: "old")
        CombatSystem.addShield(&w.s, w.ctx, sourceID: nil, targetIndex: t, amount: 100, duration: 5, tag: "new")

        let dealt = CombatSystem.applyDamage(&w.s, w.ctx, sourceID: nil, targetIndex: t, amount: 120,
                                             type: .trueDamage, source: .dot)
        XCTAssertEqual(dealt, 120, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[t].hp, 1000)
        XCTAssertEqual(w.s.units[t].shields.map(\.tag), ["new"])
        XCTAssertEqual(w.s.units[t].shields[0].amount, 30, accuracy: 1e-9)
        XCTAssertEqual(w.damageEvents.last?.absorbed ?? 0, 120, accuracy: 1e-9)

        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: nil, targetIndex: t, amount: 80, type: .trueDamage,
                                 source: .dot)
        XCTAssertTrue(w.s.units[t].shields.isEmpty)
        XCTAssertEqual(w.s.units[t].hp, 950, accuracy: 1e-9)
        XCTAssertEqual(w.damageEvents.last?.amount ?? 0, 80, accuracy: 1e-9)
        XCTAssertEqual(w.damageEvents.last?.absorbed ?? 0, 30, accuracy: 1e-9)
    }

    func testLifestealOnBasicAttacksAndSpellVampOnSkills() {
        var w = CombatWorld()
        var st = CombatWorld.stats(hp: 1000)
        st.lifesteal = 0.2
        st.spellVamp = 0.1
        st.healShieldPower = 1.0 // 吸収回復には回復強化が乗らない
        let a = w.addHero(team: .blue, at: Vec2(1000, 1000), stats: st)
        let t = w.addHero(team: .red, at: Vec2(1100, 1000), stats: CombatWorld.stats(hp: 5000))
        w.s.units[a].hp = 500

        let onHit = HitPayload(damage: 200, damageType: .physical, source: .basicAttack, appliesOnHit: true)
        CombatSystem.applyHit(&w.s, w.ctx, sourceID: w.id(a), team: .blue, targetIndex: t, payload: onHit,
                              from: w.s.units[a].pos)
        XCTAssertEqual(w.s.units[a].hp, 540, accuracy: 1e-9)

        // appliesOnHit = false の通常攻撃（強化攻撃の追加分など）には乗らない
        let noOnHit = HitPayload(damage: 200, damageType: .physical, source: .basicAttack, appliesOnHit: false)
        CombatSystem.applyHit(&w.s, w.ctx, sourceID: w.id(a), team: .blue, targetIndex: t, payload: noOnHit,
                              from: w.s.units[a].pos)
        XCTAssertEqual(w.s.units[a].hp, 540, accuracy: 1e-9)

        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a), targetIndex: t, amount: 300, type: .magic,
                                 source: .skill(.skill1))
        XCTAssertEqual(w.s.units[a].hp, 570, accuracy: 1e-9)
        // 吸収回復は回復量スコアに入らない
        XCTAssertEqual(w.s.units[a].hero?.score.healingDone, 0)
    }

    func testDeathIsQueuedExactlyOnceAndHPNeverNegative() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(1000, 1000))
        let t = w.addUnit(.minion, team: .red, at: Vec2(1100, 1000), stats: CombatWorld.stats(hp: 100))
        let first = CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a), targetIndex: t, amount: 250,
                                             type: .trueDamage, source: .spell)
        XCTAssertEqual(first, 100, accuracy: 1e-9, "HP を超えた分は与ダメに数えない")
        XCTAssertEqual(w.s.units[t].hp, 0)
        XCTAssertFalse(w.s.units[t].isAlive)
        let second = CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a), targetIndex: t, amount: 250,
                                              type: .trueDamage, source: .spell)
        XCTAssertEqual(second, 0)
        XCTAssertEqual(w.s.pendingDeaths.count, 1)
        XCTAssertEqual(w.s.pendingDeaths.first?.killerID, w.id(a))
        XCTAssertEqual(w.s.pendingDeaths.first?.victimID, w.id(t))
    }

    func testInvulnerableTargetsTakeNoDamage() {
        var w = CombatWorld()
        let t = w.addHero(team: .red, at: Vec2(1000, 1000))
        CombatSystem.addStatus(&w.s, targetIndex: t, StatusEffect(kind: .invulnerable, duration: 1))
        let dealt = CombatSystem.applyDamage(&w.s, w.ctx, sourceID: nil, targetIndex: t, amount: 500,
                                             type: .trueDamage, source: .spell)
        XCTAssertEqual(dealt, 0)
        XCTAssertEqual(w.s.units[t].hp, 1000)
        XCTAssertTrue(w.damageEvents.isEmpty)
    }

    func testScoresCombatTimesAndChannelCancel() {
        var w = CombatWorld()
        w.s.time = 42
        let a = w.addHero(team: .blue, at: Vec2(1000, 1000))
        let v = w.addHero(team: .red, at: Vec2(1100, 1000))
        let tower = w.addUnit(.tower, team: .red, at: Vec2(1500, 1000), radius: 110,
                              stats: CombatWorld.stats(hp: 4000))
        let minion = w.addUnit(.minion, team: .red, at: Vec2(1000, 1200))
        w.s.units[v].hero?.channel = Channel(kind: .recall, duration: 6)

        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a), targetIndex: v, amount: 100, type: .trueDamage,
                                 source: .basicAttack)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a), targetIndex: tower, amount: 60,
                                 type: .trueDamage, source: .basicAttack)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a), targetIndex: minion, amount: 30,
                                 type: .trueDamage, source: .basicAttack)

        XCTAssertEqual(w.s.units[a].hero?.score.damageToHeroes, 100)
        // 外塔は 4:00 まで ×0.6、護衛ミニオン無しの裏取り保護 ×0.5（DESIGN §4）→ 60 × 0.3 = 18
        XCTAssertEqual(w.s.units[a].hero?.score.towerDamage, 18)
        XCTAssertEqual(w.s.units[v].hero?.score.damageTaken, 100)
        XCTAssertEqual(w.s.units[a].lastCombatTime, 42)
        XCTAssertEqual(w.s.units[v].lastCombatTime, 42)
        XCTAssertEqual(w.s.units[v].lastDamagedTime, 42)
        XCTAssertEqual(w.s.units[v].lastAttackerID, w.id(a))
        XCTAssertNil(w.s.units[v].hero?.channel, "敵からの被ダメで詠唱は中断される")
        XCTAssertTrue(w.s.events.contains(.channelCanceled(heroID: w.id(v), kind: .recall)))

        // タワー → ヒーローも交戦扱い
        w.s.time = 50
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(tower), targetIndex: a, amount: 10, type: .physical,
                                 source: .tower)
        XCTAssertEqual(w.s.units[a].lastCombatTime, 50)
        XCTAssertEqual(w.s.units[tower].lastCombatTime, 50)
        // ミニオンからの被ダメは交戦扱いにしない
        w.s.time = 60
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(minion), targetIndex: a, amount: 10, type: .physical,
                                 source: .minion)
        XCTAssertEqual(w.s.units[a].lastCombatTime, 50)
    }

    func testAssistRecordsAreRefreshedPerSourceAndPruned() {
        var w = CombatWorld()
        let a1 = w.addHero(team: .blue, at: Vec2(1000, 1000))
        let a2 = w.addHero(team: .blue, at: Vec2(1000, 1100))
        let v = w.addHero(team: .red, at: Vec2(1100, 1000), stats: CombatWorld.stats(hp: 100_000))
        let ally = w.addHero(team: .red, at: Vec2(1200, 1000))

        w.s.time = 1
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a1), targetIndex: v, amount: 10, type: .trueDamage,
                                 source: .spell)
        w.s.time = 2
        // CC のみでもアシスト記録
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: w.id(a2), targetIndex: v, cc: .slow, isUltimate: false,
                             from: w.s.units[a2].pos)
        w.s.time = 3
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a1), targetIndex: v, amount: 10, type: .trueDamage,
                                 source: .spell)
        XCTAssertEqual(w.s.units[v].hero?.recentDamagers,
                       [DamageRecord(sourceID: w.id(a2), time: 2), DamageRecord(sourceID: w.id(a1), time: 3)])

        // 味方の回復・シールドは支援記録（自己回復は記録しない）
        CombatSystem.heal(&w.s, w.ctx, sourceID: w.id(ally), targetIndex: v, amount: 50)
        CombatSystem.heal(&w.s, w.ctx, sourceID: w.id(v), targetIndex: v, amount: 50)
        XCTAssertEqual(w.s.units[v].hero?.recentSupporters, [DamageRecord(sourceID: w.id(ally), time: 3)])

        // 10 秒を超えた記録は捨てられる
        w.s.time = 12.5
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a1), targetIndex: v, amount: 10, type: .trueDamage,
                                 source: .spell)
        XCTAssertEqual(w.s.units[v].hero?.recentDamagers, [DamageRecord(sourceID: w.id(a1), time: 12.5)])
        // 時間経過だけでも StatusSystem が掃除する
        w.s.time = 30
        StatusSystem.update(&w.s, w.ctx)
        XCTAssertEqual(w.s.units[v].hero?.recentDamagers, [])
        XCTAssertEqual(w.s.units[v].hero?.recentSupporters, [])
    }

    func testAssistRecordsAreKeptUntilDeathIsProcessedThenCleared() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(1000, 1000))
        let healer = w.addHero(team: .red, at: Vec2(1200, 1000))
        let v = w.addHero(team: .red, at: Vec2(1100, 1000), stats: CombatWorld.stats(hp: 100))
        w.s.time = 5
        CombatSystem.heal(&w.s, w.ctx, sourceID: w.id(healer), targetIndex: v, amount: 1)
        w.s.units[v].hp = 100
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a), targetIndex: v, amount: 500, type: .trueDamage,
                                 source: .spell)
        XCTAssertFalse(w.s.units[v].isAlive)
        // DeathSystem が処理するまで（respawnTimer 未設定）は記録を残す
        StatusSystem.update(&w.s, w.ctx)
        XCTAssertEqual(w.s.units[v].hero?.recentDamagers.map(\.sourceID), [w.id(a)])

        // 死亡処理後は前の命の記録を捨てる（復活直後の再死亡で古いアシストが付かない）
        w.s.units[v].hero?.empoweredAttack = EmpoweredAttack(bonusDamage: 10, damageType: .magic)
        w.s.units[v].hero?.respawnTimer = 6
        StatusSystem.update(&w.s, w.ctx)
        XCTAssertEqual(w.s.units[v].hero?.recentDamagers, [])
        XCTAssertEqual(w.s.units[v].hero?.recentSupporters, [])
        XCTAssertNil(w.s.units[v].hero?.empoweredAttack, "強化攻撃は死亡で失われる")
    }

    func testHealAndShieldPowerAndHealingReceived() {
        var w = CombatWorld()
        var st = CombatWorld.stats()
        st.healShieldPower = 0.5
        let healer = w.addHero(team: .blue, at: Vec2(1000, 1000), stats: st)
        let target = w.addHero(team: .blue, at: Vec2(1100, 1000))
        w.s.units[target].hp = 200
        w.s.units[target].stats.healingReceivedMultiplier = 0.5

        let healed = CombatSystem.heal(&w.s, w.ctx, sourceID: w.id(healer), targetIndex: target, amount: 100)
        XCTAssertEqual(healed, 75, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[target].hp, 275, accuracy: 1e-9)
        // 最大 HP を超えない
        let capped = CombatSystem.heal(&w.s, w.ctx, sourceID: w.id(healer), targetIndex: target, amount: 10_000)
        XCTAssertEqual(capped, 725, accuracy: 1e-9)

        // シールドには回復量倍率が掛からない
        CombatSystem.addShield(&w.s, w.ctx, sourceID: w.id(healer), targetIndex: target, amount: 100, duration: 2)
        XCTAssertEqual(w.s.units[target].totalShield, 150, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[healer].hero?.score.healingDone ?? 0, 800, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[healer].hero?.score.shieldingDone ?? 0, 150, accuracy: 1e-9)
        XCTAssertTrue(w.s.events.contains(.heal(targetID: w.id(target), sourceID: w.id(healer), amount: 75)))
        XCTAssertTrue(w.s.events.contains(.shieldGained(targetID: w.id(target), sourceID: w.id(healer), amount: 150)))

        // 同じ tag は置き換え、持続 0 は既定の持続になる
        CombatSystem.addShield(&w.s, w.ctx, sourceID: nil, targetIndex: target, amount: 40, duration: 0, tag: "x")
        CombatSystem.addShield(&w.s, w.ctx, sourceID: nil, targetIndex: target, amount: 60, duration: 0, tag: "x")
        XCTAssertEqual(w.s.units[target].shields.filter { $0.tag == "x" }.count, 1)
        XCTAssertEqual(w.s.units[target].shields.last?.remaining, Balance.combatDefaultShieldDuration)
    }
}
