import XCTest
@testable import VelstriaCore

/// ジャングルとローム装備を MLBB 2.2.16 に合わせた規則（docs/JUNGLE_ROAM_MLBB.md）:
/// 狩猟印の式と被ダメ軽減、序盤の規則、モンスターの毎分の伸び、ロード（18 分の進化・150 秒・報酬・塔への突進）、
/// ロード後の蟹、川の流れ、バトルプランの靴の祝福。
final class JungleRoamMLBBTests: XCTestCase {
    private let spot = Vec2(6000, 6000)
    private let smite = [Balance.Economy.smiteSpellID, "BS01"]
    private let noSmite = ["BS01", "BS03"]
    /// ボスの巣が上下交互になる地図（今遊ぶ canyon と、その前の relayout。RiverObjectiveSystem）。
    static let objectiveMaps: [MapDefinition] = [.relayout, .canyon]

    /// 標準の 5v5（全員を泉へ退避、人間（blue）を spot に置く）。キット・エンブレムの補正は外す。
    private func fixture(time: Double) -> EconomyFixture {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        for i in f.s.heroIndices {
            f.s.units[i].hero!.autoLevelSkills = false
            f.s.units[i].hero!.emblem = nil
            f.s.units[i].hero!.kit = nil
            f.s.units[i].hero!.spells = noSmite
            StatCalculator.recompute(&f.s, i, f.ctx)
            f.s.units[i].hp = f.s.units[i].stats.maxHP
        }
        f.place(f.human, at: spot)
        f.s.tick = Int((time * Balance.tickRate).rounded())
        f.s.time = Double(f.s.tick) * Balance.dt
        f.s.events.removeAll()
        return f
    }

    /// 確定ダメージ 100 を source から target へ与え、減った HP を返す。
    private func hit(_ f: inout EconomyFixture, from source: Int, to target: Int, kind: DamageSource = .monster) -> Double {
        let hp = f.s.units[target].hp
        CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(source), targetIndex: target, amount: 100, type: .trueDamage,
                                source: kind, isCrit: false, appliesOnHit: false)
        return hp - f.s.units[target].hp
    }

    @discardableResult
    private func spawn(_ f: inout EconomyFixture, _ kind: MonsterKind, camp: CampSpot) -> Int {
        let id = f.s.addUnit(UnitFactory.makeMonster(kind: kind, campID: camp.id, pos: camp.pos, time: f.s.time))
        let m = f.s.index(of: id)!
        StatCalculator.recompute(&f.s, m, f.ctx)
        return m
    }

    // MARK: - 狩猟印

    func testSmiteDamageIsRetributionFromPatch2188() {
        XCTAssertEqual(Balance.Spells.smiteDamage(level: 1), 900, accuracy: 1e-9)
        XCTAssertEqual(Balance.Spells.smiteDamage(level: 15), 3000, accuracy: 1e-9)
    }

    func testSmiteHolderTakesLessFromMonstersButNotFromTurtleOrLord() {
        var f = fixture(time: 300)
        let a = f.human
        f.s.units[a].hero!.spells = smite
        let creep = f.addMonster(.redSentinel, at: spot + Vec2(200, 0))
        let turtle = f.addMonster(.astralWyrm, at: spot + Vec2(-200, 0))
        let lord = f.addMonster(.ancientColossus, at: spot + Vec2(0, 200))
        XCTAssertEqual(hit(&f, from: creep, to: a), 60, accuracy: 1e-6)
        XCTAssertEqual(hit(&f, from: turtle, to: a), 100, accuracy: 1e-6)
        XCTAssertEqual(hit(&f, from: lord, to: a), 100, accuracy: 1e-6)
        f.s.units[a].hero!.spells = noSmite
        XCTAssertEqual(hit(&f, from: creep, to: a), 100, accuracy: 1e-6)
    }

    func testOnlyJunglersCanTakeRetribution() {
        // 日本語版の選択画面ではジャングル以外の狩猟に鍵が掛かる（2026-10-21 のスクショ）
        XCTAssertEqual(MatchFactory.allowedSpells(["BS05", "BS03"], position: .jungle), ["BS05", "BS03"])
        XCTAssertEqual(MatchFactory.allowedSpells(["BS05", "BS03"], position: .support), ["BS04", "BS03"])
        XCTAssertEqual(MatchFactory.allowedSpells(["BS05", "BS03"], position: .mid), ["BS01", "BS03"])
        XCTAssertEqual(MatchFactory.allowedSpells(["BS14", "BS03"], position: .mid), ["BS14", "BS03"])
        for pos in LanePosition.allCases {
            XCTAssertEqual(MatchFactory.defaultSpells(for: pos).contains(Balance.Economy.smiteSpellID), pos == .jungle, "\(pos)")
        }
        let cfg = MatchFactory.standardMatch(humanHeroID: "H003", humanName: "T", humanSpells: ["BS05", "BS03"],
                                             humanPosition: .mid, seed: 3)
        XCTAssertFalse(cfg.players.first { $0.controller == .human }!.spells.contains(Balance.Economy.smiteSpellID))
    }

    // MARK: - 序盤の規則

    func testEveryCampLiesInItsOwnSidesJungle() {
        for map in [MapDefinition.standard, .relayout, .canyon] {
            for camp in map.camps where camp.side != .neutral {
                XCTAssertEqual(map.jungleSide(of: camp.pos), camp.side, "\(camp.kind) \(camp.id)")
            }
            XCTAssertNil(map.jungleSide(of: map.fountain(.blue)))
        }
    }

    func testInvadersTakeMoreDamageInTheFirstTwoMinutes() {
        var f = fixture(time: 60)
        let a = f.human
        let v = f.heroes(.red)[0]
        let enemyCamp = f.ctx.map.camps.first { $0.side == .red && $0.kind == .redSentinel }!
        let ownCamp = f.ctx.map.camps.first { $0.side == .blue && $0.kind == .redSentinel }!
        f.place(a, at: enemyCamp.pos)
        XCTAssertEqual(hit(&f, from: v, to: a, kind: .skill(.skill1)), 120, accuracy: 1e-6, "敵のジャングルでは +20%")
        f.place(a, at: ownCamp.pos)
        XCTAssertEqual(hit(&f, from: v, to: a, kind: .skill(.skill1)), 100, accuracy: 1e-6, "自陣のジャングル")
        f.place(a, at: enemyCamp.pos)
        f.s.time = Balance.Jungle.earlyJungleRuleEnd
        XCTAssertEqual(hit(&f, from: v, to: a, kind: .skill(.skill1)), 100, accuracy: 1e-6, "2:00 から")
    }

    func testEarlyHomeJungleRewardsGoToTheNearbySmiteHolder() {
        var f = fixture(time: 60)
        let a = f.human
        f.s.units[a].hero!.spells = smite
        let camp = f.ctx.map.camps.first { $0.side == .blue && $0.kind == .hornLizard }!
        let mate = f.heroes(.blue).first { $0 != a }!
        let foe = f.heroes(.red)[0]
        f.place(a, at: camp.pos + Vec2(300, 0))
        f.place(mate, at: camp.pos + Vec2(-300, 0))
        // 味方の止めでも、Gold と撃破は狩猟印を持つ a に入る
        var ga = f.hero(a).gold, gm = f.hero(mate).gold
        f.kill(spawn(&f, .hornLizard, camp: camp), by: f.id(mate))
        XCTAssertGreaterThan(f.hero(a).gold, ga)
        XCTAssertEqual(f.hero(mate).gold, gm, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).score.monsterKills, 1)
        // 敵の止めでも同じ
        f.place(foe, at: camp.pos + Vec2(0, 300))
        ga = f.hero(a).gold
        let gf = f.hero(foe).gold
        f.kill(spawn(&f, .hornLizard, camp: camp), by: f.id(foe))
        XCTAssertGreaterThan(f.hero(a).gold, ga)
        XCTAssertEqual(f.hero(foe).gold, gf, accuracy: 1e-9)
        // 遠くに居れば止めを刺した本人
        f.place(a, at: f.ctx.map.fountain(.blue))
        gm = f.hero(mate).gold
        f.kill(spawn(&f, .hornLizard, camp: camp), by: f.id(mate))
        XCTAssertGreaterThan(f.hero(mate).gold, gm)
        // 2:00 を過ぎれば止めを刺した本人
        f.place(a, at: camp.pos + Vec2(300, 0))
        f.s.time = Balance.Jungle.earlyJungleRuleEnd
        gm = f.hero(mate).gold
        ga = f.hero(a).gold
        f.kill(spawn(&f, .hornLizard, camp: camp), by: f.id(mate))
        XCTAssertGreaterThan(f.hero(mate).gold, gm)
        XCTAssertEqual(f.hero(a).gold, ga, accuracy: 1e-9)
    }

    // MARK: - モンスターの強さ

    func testMonstersStartAtMLBBValuesAndGrowEveryMinute() {
        // Fandom の表 × Patch 1.9.90（バフ・小キャンプの HP +30%・攻撃 −15%）
        let red = UnitFactory.monsterProfile(.redSentinel)
        XCTAssertEqual(red.maxHP(at: 0), 4941 * 1.3, accuracy: 1e-9)
        XCTAssertEqual(red.maxHP(at: 59.9), 4941 * 1.3, accuracy: 1e-9)
        XCTAssertEqual(red.maxHP(at: 60), (4941 + 158.22) * 1.3, accuracy: 1e-9)
        XCTAssertEqual(red.attack(at: 600), (214 + 3.84 * 10) * 0.85, accuracy: 1e-9)
        XCTAssertEqual(red.armor(at: 600), 37 + 2 * 10, accuracy: 1e-9)
        for (kind, base, perMinute, scale) in [(MonsterKind.blueSentinel, 4090.0, 230.22, 1.3), (.hornLizard, 3019, 156.69, 1.3),
                                               (.emberBeetle, 2501, 126.69, 1.3), (.magmaGolem, 3000, 81.50, 1.3),
                                               (.mossWanderer, 2251, 345.90, 1), (.treasureCrab, 3640, 384.30, 1),
                                               (.astralWyrm, 10367, 1067.15, 1)] {
            XCTAssertEqual(UnitFactory.monsterProfile(kind).maxHP(at: 120), (base + 2 * perMinute) * scale, accuracy: 1e-6,
                           "\(kind)")
        }
        XCTAssertEqual(UnitFactory.monsterProfile(.astralWyrm).armor(at: 120), 15 + 10 * 2, accuracy: 1e-9)
        XCTAssertEqual(UnitFactory.monsterProfile(.treasureCrab).armor(at: 600), 0, accuracy: 1e-9, "防御 0（1.9.90）")
        let lord = UnitFactory.monsterProfile(.ancientColossus)
        XCTAssertEqual(lord.maxHP(at: 8 * 60), 31743 + 2242 * 8, accuracy: 1e-9)
        XCTAssertEqual(lord.maxHP(at: 30 * 60), 31743 + 2242 * 18, accuracy: 1e-9, "18 分で止まる")
        XCTAssertEqual(lord.attack(at: 30 * 60), 428 + 20.15 * 18, accuracy: 1e-9)
        // 出現した時刻の値で出て、生きている間も分の変わり目に伸びる（HP の割合は保つ）
        var f = fixture(time: 125)
        let camp = f.ctx.map.camps.first { $0.side == .blue && $0.kind == .redSentinel }!
        let m = spawn(&f, .redSentinel, camp: camp)
        XCTAssertEqual(f.s.units[m].stats.maxHP, red.maxHP(at: 120), accuracy: 1e-9)
        f.s.units[m].hp = f.s.units[m].stats.maxHP / 2
        f.s.time = 180
        MonsterSystem.grow(&f.s, f.ctx, m)
        XCTAssertEqual(f.s.units[m].stats.maxHP, red.maxHP(at: 180), accuracy: 1e-9)
        XCTAssertEqual(f.s.units[m].hp, red.maxHP(at: 180) / 2, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[m].stats.armor, red.armor(at: 180), accuracy: 1e-9)
    }

    // MARK: - ロード

    func testLordGoldGrowsWithTheClock() {
        XCTAssertEqual(Balance.Economy.colossusTeamGold(at: 480), 130, accuracy: 1e-9)
        XCTAssertEqual(Balance.Economy.colossusTeamGold(at: 1199), 240, accuracy: 1e-9)
        XCTAssertEqual(RiverObjectiveSystem.lordRespawn(at: 1079), 180, accuracy: 1e-9)
        XCTAssertEqual(RiverObjectiveSystem.lordRespawn(at: 1080), 150, accuracy: 1e-9)
    }

    func testCapturedLordChargesEachTowerOnceBeforeEighteenMinutes() throws {
        for map in Self.objectiveMaps { try checkCapturedLordChargesEachTowerOnceBeforeEighteenMinutes(map) }
    }

    private func checkCapturedLordChargesEachTowerOnceBeforeEighteenMinutes(_ map: MapDefinition) throws {
        let config = WorldTestKit.emptyConfig()
        let ctx = SimContext(master: .shared, map: map, config: config)
        var s = SimState(config: config)
        SpawnSystem.setupMatch(&s, ctx)
        for i in s.units.indices { StatCalculator.recompute(&s, i, ctx) }
        WorldTestKit.setTime(&s, 600)
        RiverObjectiveSystem.capture(&s, ctx, team: .blue)
        let lord = try XCTUnwrap(s.units.indices.first { s.units[$0].monster?.kind == .ancientColossus })
        XCTAssertNil(s.units[lord].monster?.lordTier.flatMap { $0 > 0 ? $0 : nil }, "18 分までは進化しない")
        let tower = try XCTUnwrap(s.units.indices.first {
            s.units[$0].kind == .tower && s.units[$0].team == .red && s.units[$0].tower?.tier == .outer
        })
        s.units[tower].shields.removeAll()   // 外塔のシールド（時刻を飛ばしたので残っている）
        s.units[lord].attackTargetID = s.units[tower].id
        // 遠ければ突進（加速）するだけ
        s.units[lord].pos = s.units[tower].pos + Vec2(2000, 0)
        let full = s.units[tower].hp
        RiverObjectiveSystem.abilities(&s, ctx, lord)
        XCTAssertTrue(s.units[lord].statuses.contains { $0.tag == "lord.towerCharge" })
        XCTAssertEqual(s.units[tower].hp, full, accuracy: 1e-9)
        // 届いたら塔の最大 HP の 30% の確定ダメージ（塔ごとに 1 回）
        s.units[lord].pos = s.units[tower].pos + Vec2(s.units[tower].radius + s.units[lord].radius, 0)
        let mult = TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: tower, sourceIndex: lord)
        RiverObjectiveSystem.abilities(&s, ctx, lord)
        XCTAssertEqual(full - s.units[tower].hp, s.units[tower].stats.maxHP * 0.3 * mult, accuracy: 1e-6)
        let after = s.units[tower].hp
        RiverObjectiveSystem.abilities(&s, ctx, lord)
        XCTAssertEqual(s.units[tower].hp, after, accuracy: 1e-9, "同じ塔には 1 回だけ")
    }

    func testNeutralLordDamageReductionShrinksWithNearbyHeroes() {
        var f = fixture(time: 600)
        let a = f.human
        let lordID = f.s.addUnit(UnitFactory.makeMonster(kind: .ancientColossus, campID: -1, pos: spot + Vec2(300, 0), time: 600))
        let lord = f.s.index(of: lordID)!
        // 40% − 周り（縁から 500）のヒーロー 1 人につき 5%、下限 15%（MLBB Patch 1.6.42）
        XCTAssertEqual(RiverObjectiveSystem.neutralLordDamageTakenMultiplier(f.s, lord), 1 - 0.35, accuracy: 1e-9)
        for i in f.s.heroIndices where i != a { f.place(i, at: spot) }
        XCTAssertEqual(RiverObjectiveSystem.neutralLordDamageTakenMultiplier(f.s, lord), 1 - 0.15, accuracy: 1e-9)
        // 味方になったロードには効かない
        f.s.units[lord].team = .blue
        XCTAssertEqual(RiverObjectiveSystem.neutralLordDamageTakenMultiplier(f.s, lord), 1, accuracy: 1e-9)
    }

    func testNeutralLordStrikesByTargetHPAndBuildsPenetration() {
        var f = fixture(time: 600)
        let a = f.human
        let lordID = f.s.addUnit(UnitFactory.makeMonster(kind: .ancientColossus, campID: -1, pos: spot + Vec2(300, 0), time: 600))
        let lord = f.s.index(of: lordID)!
        f.s.units[lord].attackTargetID = f.id(a)
        // 最初の呼び出しで雷撃の時計を回し、4 秒後に雷撃（50 + 対象の最大 HP の 15% の確定ダメージ）
        RiverObjectiveSystem.neutralCombat(&f.s, f.ctx, lord)
        XCTAssertEqual(f.s.units[lord].monster?.lordPenStacks, 0)
        var hp = f.s.units[a].hp
        f.s.time += Balance.Jungle.lordStrikeInterval
        RiverObjectiveSystem.neutralCombat(&f.s, f.ctx, lord)
        XCTAssertEqual(hp - f.s.units[a].hp, 50 + 0.15 * f.s.units[a].stats.maxHP, accuracy: 1e-6)
        // 戦闘中は毎秒 物理貫通 +10%（最大 10 回）
        for _ in 0..<20 {
            f.s.time += 1
            RiverObjectiveSystem.neutralCombat(&f.s, f.ctx, lord)
        }
        XCTAssertEqual(f.s.units[lord].monster?.lordPenStacks, Balance.Jungle.lordPenMaxStacks)
        // 戦闘が終わると解ける
        f.s.units[lord].attackTargetID = nil
        RiverObjectiveSystem.neutralCombat(&f.s, f.ctx, lord)
        XCTAssertNil(f.s.units[lord].monster?.lordPenStacks)
        // 通常攻撃: 攻撃の 20% + 対象の最大 HP の 10%（物理）
        f.s.units[lord].attackTargetID = f.id(a)
        hp = f.s.units[a].hp
        let st = f.s.units[a].stats
        CombatSystem.releaseAttack(&f.s, f.ctx, attacker: lord, target: a)
        let raw = 0.2 * f.s.units[lord].stats.attack + 0.1 * st.maxHP
        XCTAssertEqual(hp - f.s.units[a].hp,
                       min(hp, raw * CombatSystem.mitigationMultiplier(.physical, armor: st.armor, magicResist: st.magicResist)
                            * CombatSystem.damageReductionMultiplier(st.damageReduction)), accuracy: 1e-6)
    }

    func testEarlyHomeBuffGoesToTheSmiteHolderWhoJustHitIt() {
        var f = fixture(time: 60)
        let a = f.human
        f.s.units[a].hero!.spells = smite
        let camp = f.ctx.map.camps.first { $0.side == .blue && $0.kind == .redSentinel }!
        let mate = f.heroes(.blue).first { $0 != a }!
        f.place(a, at: camp.pos + Vec2(300, 0))
        f.place(mate, at: camp.pos + Vec2(-300, 0))
        // 狩猟持ちが直前に攻撃していなければ、バフは止めを刺した味方に（Gold は狩猟持ちへ。1.9.06）
        f.kill(spawn(&f, .redSentinel, camp: camp), by: f.id(mate))
        XCTAssertTrue(f.s.units[mate].has(.redBuff))
        XCTAssertFalse(f.s.units[a].has(.redBuff))
        // 直前に攻撃していれば、最も近い狩猟持ちに（MLBB Patch 2.1.18）
        f.s.units[mate].statuses.removeAll()
        let m = spawn(&f, .redSentinel, camp: camp)
        CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(a), targetIndex: m, amount: 10, type: .trueDamage,
                                source: .basicAttack, isCrit: false, appliesOnHit: false)
        f.kill(m, by: f.id(mate))
        XCTAssertTrue(f.s.units[a].has(.redBuff))
        XCTAssertFalse(f.s.units[mate].has(.redBuff))
    }

    func testTurtleBecomesTheLordAfterEightOnceLeftAloneForFiveSeconds() throws {
        for map in Self.objectiveMaps { try checkTurtleBecomesTheLordAfterEightOnceLeftAloneForFiveSeconds(map) }
    }

    private func checkTurtleBecomesTheLordAfterEightOnceLeftAloneForFiveSeconds(_ map: MapDefinition) throws {
        var (s, ctx) = WorldTestKit.makeState(WorldTestKit.emptyConfig(), map: map)
        func boss(_ kind: MonsterKind) -> Int? {
            s.units.indices.first { s.units[$0].isAlive && s.units[$0].team == .neutral && s.units[$0].monster?.kind == kind }
        }
        WorldTestKit.setTime(&s, 120)
        RiverObjectiveSystem.update(&s, ctx)
        let turtle = try XCTUnwrap(boss(.astralWyrm))
        let pit = s.units[turtle].pos
        // 8:00 に戦っていれば、まだ変わらない
        WorldTestKit.setTime(&s, 480)
        s.units[turtle].lastDamagedTime = 478
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertNotNil(boss(.astralWyrm))
        XCTAssertEqual(s.world.riverObjective?.lordEra, false)
        // 5 秒ダメージを受けないと、その巣でロードになる（報酬なし）
        WorldTestKit.setTime(&s, 483)
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertNil(boss(.astralWyrm))
        let lord = try XCTUnwrap(boss(.ancientColossus))
        XCTAssertLessThan(s.units[lord].pos.distance(to: pit), 300)
        XCTAssertEqual(s.world.riverObjective?.lordEra, true)
        // 戦い続けても 9:00 には変わる
        var (s2, ctx2) = WorldTestKit.makeState(WorldTestKit.emptyConfig(), map: map)
        WorldTestKit.setTime(&s2, 120)
        RiverObjectiveSystem.update(&s2, ctx2)
        let t2 = try XCTUnwrap(s2.units.indices.first { s2.units[$0].isAlive && s2.units[$0].monster?.kind == .astralWyrm })
        for time in stride(from: 480.0, through: 540, by: 2) {
            WorldTestKit.setTime(&s2, time)
            s2.units[t2].lastDamagedTime = time
            RiverObjectiveSystem.update(&s2, ctx2)
        }
        XCTAssertEqual(s2.world.riverObjective?.lordEra, true)
        XCTAssertFalse(s2.units[t2].isAlive)
    }

    func testTurtleSlainAfterSixMinutesIsFollowedByTheLord() throws {
        for map in Self.objectiveMaps { try checkTurtleSlainAfterSixMinutesIsFollowedByTheLord(map) }
    }

    private func checkTurtleSlainAfterSixMinutesIsFollowedByTheLord(_ map: MapDefinition) throws {
        var (s, ctx) = WorldTestKit.makeState(WorldTestKit.emptyConfig(), map: map)
        func liveBoss() -> Int? {
            s.units.indices.first { s.units[$0].isAlive && s.units[$0].team == .neutral && s.units[$0].monster?.kind.isBoss == true }
        }
        WorldTestKit.setTime(&s, 120)
        RiverObjectiveSystem.update(&s, ctx)
        // 6:00 より前に倒すと 2 分後にタートル
        s.units[try XCTUnwrap(liveBoss())].isAlive = false
        WorldTestKit.setTime(&s, 300)
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertEqual(s.world.riverObjective?.nextIsLord, false)
        WorldTestKit.setTime(&s, 420)
        RiverObjectiveSystem.update(&s, ctx)
        let second = try XCTUnwrap(liveBoss())
        XCTAssertEqual(s.units[second].monster?.kind, .astralWyrm)
        // 6:00 以降に倒すと、次のタートルは出ずに 2 分後（8:00 より後）にロード
        s.units[second].isAlive = false
        WorldTestKit.setTime(&s, 430)
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertEqual(s.world.riverObjective?.nextIsLord, true)
        XCTAssertEqual(s.world.riverObjective?.nextSpawnAt ?? 0, 550, accuracy: 1e-9)
        WorldTestKit.setTime(&s, 549)
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertNil(liveBoss())
        WorldTestKit.setTime(&s, 550)
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertEqual(s.units[try XCTUnwrap(liveBoss())].monster?.kind, .ancientColossus)
        XCTAssertEqual(s.world.riverObjective?.lordEra, true)
    }

    func testEvolvedAlliedLordReducesDamageByNearbyAlliesAndEmpowersTheirAttacks() throws {
        for map in Self.objectiveMaps { try checkEvolvedAlliedLordReducesDamageByNearbyAlliesAndEmpowersTheirAttacks(map) }
    }

    private func checkEvolvedAlliedLordReducesDamageByNearbyAlliesAndEmpowersTheirAttacks(_ map: MapDefinition) throws {
        var (s, ctx) = WorldTestKit.makeState(WorldTestKit.emptyConfig(), map: map)
        WorldTestKit.setTime(&s, 1100)
        RiverObjectiveSystem.capture(&s, ctx, team: .blue)
        let lord = try XCTUnwrap(s.units.indices.first { s.units[$0].monster?.kind == .ancientColossus })
        XCTAssertEqual(s.units[lord].monster?.lordTier, 2)
        let allies = (0..<3).map { k in
            WorldTestKit.addHero(&s, ctx, team: .blue, pos: s.units[lord].pos + Vec2(200, Double(k) * 100))
        }
        RiverObjectiveSystem.abilities(&s, ctx, lord)
        // 周りの味方 3 人: 15% + 4% × 3（MLBB Patch 1.9.64）
        XCTAssertEqual(s.units[lord].statuses.first { $0.tag == "lord.evolved" }?.magnitude ?? 0, 0.15 + 0.04 * 3,
                       accuracy: 1e-9)
        // 加護: 敵ヒーローへの攻撃で 400 + 物攻 60% + 魔攻 60% + 最大 HP 3% の魔法ダメージ（CD 2 秒）
        let h = allies[0]
        XCTAssertTrue(s.units[h].statuses.contains { $0.tag == JungleBuffs.lordAuraTag })
        let e = WorldTestKit.addHero(&s, ctx, team: .red, pos: s.units[h].pos + Vec2(150, 0))
        let st = s.units[h].stats, es = s.units[e].stats
        var hp = s.units[e].hp
        JungleBuffs.lordAuraStrike(&s, ctx, attacker: h, target: e, source: .basicAttack)
        let raw = 400 + 0.6 * st.attack + 0.6 * st.abilityPower + 0.03 * st.maxHP
        XCTAssertEqual(hp - s.units[e].hp,
                       raw * CombatSystem.mitigationMultiplier(.magic, armor: es.armor, magicResist: es.magicResist)
                           * CombatSystem.damageReductionMultiplier(es.damageReduction), accuracy: 1e-6)
        hp = s.units[e].hp
        JungleBuffs.lordAuraStrike(&s, ctx, attacker: h, target: e, source: .basicAttack)
        XCTAssertEqual(s.units[e].hp, hp, accuracy: 1e-9, "2 秒に 1 回")
    }

    // MARK: - 宝殻蟹・川の流れ

    func testCrabsStopSpawningOnceTheLordAppears() throws {
        for map in Self.objectiveMaps { try checkCrabsStopSpawningOnceTheLordAppears(map) }
    }

    private func checkCrabsStopSpawningOnceTheLordAppears(_ map: MapDefinition) throws {
        var (s, ctx) = WorldTestKit.makeState(WorldTestKit.emptyConfig(), map: map)
        let k = try XCTUnwrap(ctx.map.camps.firstIndex { $0.kind == .treasureCrab })
        func crabs(_ s: SimState) -> Int {
            s.units.filter { $0.isAlive && $0.monster?.campID == k }.count
        }
        WorldTestKit.setTime(&s, 400)
        for i in s.units.indices where s.units[i].monster?.campID == k { s.units[i].isAlive = false }
        s.removeFinishedEntities()
        s.world.campRespawnAt[k] = 470
        SpawnSystem.updateCamps(&s, ctx)
        WorldTestKit.setTime(&s, 470)
        SpawnSystem.updateCamps(&s, ctx)
        XCTAssertEqual(crabs(s), 1, "8:00 までは出る")
        for i in s.units.indices where s.units[i].monster?.campID == k { s.units[i].isAlive = false }
        s.removeFinishedEntities()
        WorldTestKit.setTime(&s, 480)
        SpawnSystem.updateCamps(&s, ctx)
        XCTAssertEqual(s.world.campRespawnAt[k] ?? 0, Double.greatestFiniteMagnitude)
        WorldTestKit.setTime(&s, 480 + 600)
        SpawnSystem.updateCamps(&s, ctx)
        XCTAssertEqual(crabs(s), 0, "ロードが出た後は湧かない")
    }

    func testRiverCurrentSpeedsHeroesTowardThePitAroundTheTurtle() throws {
        for map in Self.objectiveMaps { try checkRiverCurrentSpeedsHeroesTowardThePitAroundTheTurtle(map) }
    }

    private func checkRiverCurrentSpeedsHeroesTowardThePitAroundTheTurtle(_ map: MapDefinition) throws {
        var (s, ctx) = WorldTestKit.makeState(WorldTestKit.emptyConfig(), map: map)
        let state = try XCTUnwrap(s.world.riverObjective)
        let pit = try XCTUnwrap(ctx.map.camps.first { $0.id == state.campID }).pos
        let spawnAt = try XCTUnwrap(state.nextSpawnAt)
        // 巣から中央へ向かう線の上で、川の中の点
        let toCenter = (Vec2(ctx.map.size / 2, ctx.map.size / 2) - pit).normalized
        let p = try XCTUnwrap(stride(from: 300.0, through: 2000, by: 50).map { pit + toCenter * $0 }
            .first { ctx.map.isInRiver($0) && ctx.nav.isWalkable($0, radius: 1) })
        let h = WorldTestKit.addHero(&s, ctx, team: .blue, pos: p)
        func speed(time: Double, towardPit: Bool) -> Double {
            WorldTestKit.setTime(&s, time)
            let d = (pit - p).normalized * (towardPit ? 1 : -1)
            s.units[h].pos = p
            s.units[h].prevPos = p - d * 5
            StatCalculator.recompute(&s, h, ctx)
            return s.units[h].stats.moveSpeed
        }
        let base = speed(time: spawnAt - 30, towardPit: true)
        XCTAssertEqual(speed(time: spawnAt - 10, towardPit: true) / base, 1.5, accuracy: 1e-6, "出現の 15 秒前から")
        XCTAssertEqual(speed(time: spawnAt - 10, towardPit: false), base, accuracy: 1e-6, "巣から離れる向きは速くならない")
        // タートルが倒されるまで続く（MLBB Patch 1.9.90）
        WorldTestKit.setTime(&s, spawnAt)
        RiverObjectiveSystem.update(&s, ctx)
        let turtle = try XCTUnwrap(s.units.indices.first { s.units[$0].isAlive && s.units[$0].monster?.kind == .astralWyrm })
        XCTAssertEqual(speed(time: spawnAt + 100, towardPit: true) / base, 1.5, accuracy: 1e-6, "生きている間")
        s.units[turtle].isAlive = false
        WorldTestKit.setTime(&s, spawnAt + 101)
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertEqual(speed(time: spawnAt + 101, towardPit: true), base, accuracy: 1e-6, "倒されたら終わる")
    }

    // MARK: - バトルプランの靴の祝福

    func testBuildPlansCarryTheirBootBlessing() {
        XCTAssertEqual(ItemSystem.plan(heroID: "H033", chosen: nil)?.blessing, .flame)
        XCTAssertEqual(ItemSystem.plan(heroID: "H033", chosen: 2)?.blessing, .ice)
        XCTAssertEqual(ItemSystem.plan(heroID: "H029", chosen: nil)?.blessing, .encourage)
        XCTAssertEqual(ItemSystem.plan(heroID: "H029", chosen: 1)?.blessing, .conceal)
        XCTAssertEqual(ItemSystem.plan(heroID: "H034", chosen: 2)?.blessing, .conceal)
        XCTAssertNil(ItemSystem.plan(heroID: "H025", chosen: nil)?.blessing)
        // ジャングル: 狩猟印を持って靴を買うと、選んだプランの祝福
        var f = fixture(time: 60)
        let a = f.human
        f.s.units[a].hero!.heroID = "H033"
        f.s.units[a].hero!.spells = smite
        f.s.units[a].hero!.buildPlan = 2
        f.s.units[a].hero!.gold = 1000
        ItemSystem.buy(&f.s, f.ctx, heroIndex: a, itemID: Balance.Gear.baseBootsID)
        XCTAssertEqual(f.hero(a).gear?.option, .ice)
        // ローム: ボットのロームはプランの祝福（H029 の 2 つ目 = 隠蔽）
        let sup = f.heroes(.blue).first { f.hero($0).controller == .bot }!
        f.s.units[sup].hero!.heroID = "H029"
        f.s.units[sup].hero!.position = .support
        f.s.units[sup].hero!.buildPlan = 1
        f.s.units[sup].hero!.gold = 1000
        ItemSystem.buy(&f.s, f.ctx, heroIndex: sup, itemID: Balance.Gear.baseBootsID)
        XCTAssertEqual(f.hero(sup).gear?.option, .conceal)
    }
}
