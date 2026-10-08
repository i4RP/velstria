import XCTest
@testable import VelstriaCore

/// ジャングル靴・ローム靴: 購入条件・靴枠・時間で変わる収入・祝福（DESIGN §8.1）。
final class GearTests: XCTestCase {
    private let spot = Vec2(6000, 6000)
    private let noSmite = ["BS01", "BS03"]
    private let smite = ["BS05", "BS01"]

    private func setup(spells: [String]? = nil, gold: Double = 5000) -> EconomyFixture {
        var f = EconomyFixture.standard()
        let i = f.human
        f.s.units[i].hero!.gold = gold
        if let spells { f.s.units[i].hero!.spells = spells }
        f.s.events.removeAll()
        return f
    }

    /// 全ヒーローを泉へ退避し、blue の先頭 1 体だけ靴を持たせて返す。
    private func geared(_ itemID: String, spells: [String], time: Double) -> (EconomyFixture, Int) {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0]
        f.place(a, at: spot)
        f.s.units[a].hero!.items = [itemID]
        f.s.units[a].hero!.itemInvested = [600]
        f.s.units[a].hero!.spells = spells
        f.s.units[a].hero!.autoLevelSkills = false
        f.s.tick = Int(time / Balance.dt)
        f.s.time = time
        StatCalculator.recompute(&f.s, a, f.ctx)
        return (f, a)
    }

    // MARK: - カタログ・購入

    func testBootsAreInMasterAndUseTheBootsSlot() throws {
        let m = MasterData.shared
        let jungle = try XCTUnwrap(m.item(GearCatalog.jungleBootsID))
        let roam = try XCTUnwrap(m.item(GearCatalog.roamBootsID))
        XCTAssertEqual(jungle.category, .jungle)
        XCTAssertEqual(roam.category, .roam)
        XCTAssertGreaterThan(jungle.moveSpeed, 0)
        XCTAssertGreaterThan(roam.moveSpeed, 0)
        XCTAssertTrue(ItemSystem.isBoots(jungle))
        XCTAssertTrue(ItemSystem.isBoots(roam))
        XCTAssertTrue(ItemSystem.isBoots(try XCTUnwrap(m.item("EQ004"))))     // Movement
        XCTAssertFalse(ItemSystem.isBoots(try XCTUnwrap(m.item("EQ006"))))    // 移動速度の無いジャングル装備
        XCTAssertEqual(jungle.passivePercent, 8)
    }

    func testRoamBootsCannotBeBoughtWithSmite() {
        var f = setup(spells: smite)
        let i = f.human
        let q = ItemSystem.quote(f.hero(i), itemID: GearCatalog.roamBootsID, ctx: f.ctx)
        XCTAssertEqual(q.failure, .blockedBySmite)
        ItemSystem.buy(&f.s, f.ctx, heroIndex: i, itemID: GearCatalog.roamBootsID)
        XCTAssertTrue(f.hero(i).items.isEmpty)
        XCTAssertEqual(f.s.events.purchaseFailures, ["blocked_by_smite"])
    }

    func testJungleBootsRequireSmiteAndBlockOtherBoots() {
        var f = setup(spells: noSmite)
        let i = f.human
        XCTAssertEqual(ItemSystem.quote(f.hero(i), itemID: GearCatalog.jungleBootsID, ctx: f.ctx).failure, .requiresSmite)

        f = setup(spells: smite)
        ItemSystem.buy(&f.s, f.ctx, heroIndex: i, itemID: GearCatalog.jungleBootsID)
        XCTAssertEqual(f.hero(i).items, [GearCatalog.jungleBootsID])
        // 靴枠は 1 つ（移動系の靴は買えない）
        XCTAssertEqual(ItemSystem.quote(f.hero(i), itemID: "EQ004", ctx: f.ctx).failure, .uniqueCategory)
        // 移動速度の無い通常のジャングル装備は別枠として扱われ、カテゴリの上限（1 つ）で止まる
        XCTAssertEqual(ItemSystem.quote(f.hero(i), itemID: "EQ006", ctx: f.ctx).failure, .uniqueCategory)
        // 靴の移動速度は能力値に反映される
        let def = f.master.hero(f.hero(i).heroID)!
        XCTAssertEqual(f.s.units[i].stats.moveSpeed,
                       HeroGrowth.baseStats(def: def, level: 1).moveSpeed + 40, accuracy: 1e-6)
    }

    func testRoamBootsBlockMovementBootsAndPickDefaultOption() {
        var f = setup(spells: noSmite)
        let i = f.human
        ItemSystem.buy(&f.s, f.ctx, heroIndex: i, itemID: GearCatalog.roamBootsID)
        XCTAssertEqual(f.hero(i).items, [GearCatalog.roamBootsID])
        XCTAssertEqual(ItemSystem.quote(f.hero(i), itemID: "EQ004", ctx: f.ctx).failure, .uniqueCategory)
        XCTAssertEqual(f.hero(i).gear?.option, GearOption.defaultOption(for: .roam, role: f.hero(i).role))
    }

    func testSetGearOptionOnlyAcceptsMatchingCategory() {
        var f = setup(spells: noSmite)
        let i = f.human
        ItemSystem.buy(&f.s, f.ctx, heroIndex: i, itemID: GearCatalog.roamBootsID)
        let id = f.id(i)
        CommandSystem.apply([HeroCommand(heroID: id, command: .setGearOption(.favor))], &f.s, f.ctx)
        XCTAssertEqual(f.hero(i).gear?.option, .favor)
        // ジャングルの祝福はローム靴には付けられない
        CommandSystem.apply([HeroCommand(heroID: id, command: .setGearOption(.flame))], &f.s, f.ctx)
        XCTAssertEqual(f.hero(i).gear?.option, .favor)
    }

    func testRecommendedBuildUsesBootsForJunglerAndSupport() {
        let f = EconomyFixture.standard()
        var support = f.hero(f.human)
        support.position = .support
        support.spells = noSmite
        let supportBuild = ItemSystem.recommendedBuild(for: support, master: f.master)
        XCTAssertEqual(supportBuild.first, GearCatalog.roamBootsID)
        XCTAssertLessThanOrEqual(supportBuild.count, Balance.itemSlots)

        var jungler = f.hero(f.human)
        jungler.position = .jungle
        jungler.spells = smite
        let junglerBuild = ItemSystem.recommendedBuild(for: jungler, master: f.master)
        XCTAssertEqual(junglerBuild.first, GearCatalog.jungleBootsID)
        XCTAssertFalse(ItemSystem.recommendedBuild(for: support, master: f.master).contains(GearCatalog.jungleBootsID))
    }

    // MARK: - ジャングル靴: 時間で変わる収入

    func testJungleBootsHalveMinionRewardsOnlyBeforeFiveMinutes() {
        for (time, factor) in [(200.0, 0.5), (400.0, 1.0)] {
            var (f, a) = geared(GearCatalog.jungleBootsID, spells: smite, time: time)
            let m = f.addMinion(.melee, team: .red, at: spot)
            let gold = f.hero(a).gold
            f.kill(m, by: f.id(a))
            XCTAssertEqual(f.hero(a).gold - gold, Balance.Economy.minionGold(.melee, at: time) * factor, accuracy: 1e-9, "t=\(time)")
            XCTAssertEqual(f.hero(a).xp, Balance.Economy.minionXP(.melee) * factor, accuracy: 1e-9, "t=\(time)")
        }
    }

    func testJungleBootsDoNotReduceMonsterRewards() {
        var (f, a) = geared(GearCatalog.jungleBootsID, spells: smite, time: 100)
        let gold = f.hero(a).gold
        f.kill(f.addMonster(.campLarge, at: spot), by: f.id(a))
        // 大型 40 × (1 + 20%) = 48（制限なし）
        XCTAssertEqual(f.hero(a).gold - gold, 48)
        XCTAssertEqual(f.hero(a).xp, Balance.Economy.monsterXP(.campLarge), accuracy: 1e-9)
    }

    func testJungleBlessingUnlocksAfterFiveHuntsOrKills() {
        var (f, a) = geared(GearCatalog.jungleBootsID, spells: smite, time: 100)
        // 補助効果 8% → モンスターへのダメージ +3 × 8% = 24%
        XCTAssertEqual(f.s.units[a].stats.monsterDamageBonus, 0.24, accuracy: 1e-9)
        XCTAssertFalse(GearEffects.jungleBlessingActive(f.hero(a), master: f.master))
        f.s.units[a].hero!.score.monsterKills = 3
        f.s.units[a].hero!.score.kills = 1
        XCTAssertFalse(GearEffects.jungleBlessingActive(f.hero(a), master: f.master))
        f.s.units[a].hero!.score.assists = 1
        XCTAssertTrue(GearEffects.jungleBlessingActive(f.hero(a), master: f.master))
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.monsterDamageBonus, 0.24 + Balance.Gear.jungleBlessingMonsterDamage,
                       accuracy: 1e-9)
    }

    func testSmiteOnHeroAppliesTheChosenBlessing() {
        for (option, status) in [(GearOption.flame, StatusKind.damageDealtReduction), (.ice, .slow)] {
            var (f, a) = geared(GearCatalog.jungleBootsID, spells: smite, time: 100)
            f.s.units[a].hero!.gear = GearState(option: option)
            let v = f.heroes(.red)[0]
            f.place(v, at: spot + Vec2(100, 0))
            let hp = f.s.units[v].hp
            GearSystem.applySmiteOnHero(&f.s, f.ctx, caster: a, target: v)
            XCTAssertLessThan(f.s.units[v].hp, hp, "\(option)")
            XCTAssertNotNil(f.s.units[v].status(status), "\(option)")
        }
    }

    // MARK: - ローム靴: 共有収入

    func testThrivingIncomeRisesAtEightMinutes() {
        let interval = Int(Balance.Gear.thrivingInterval * Balance.tickRate)
        for (tick, gold, xp) in [(interval * 10, 6.0, 12.0), (interval * 100, 9.0, 18.0)] {
            var (f, a) = geared(GearCatalog.roamBootsID, spells: noSmite, time: 10)
            f.s.tick = tick
            f.s.time = Double(tick) * Balance.dt
            let g0 = f.hero(a).gold
            GearSystem.update(&f.s, f.ctx)
            XCTAssertEqual(f.hero(a).gold - g0, gold, accuracy: 1e-9, "t=\(f.s.time)")
            XCTAssertEqual(f.hero(a).xp, xp, accuracy: 1e-9, "t=\(f.s.time)")
            XCTAssertEqual(f.hero(a).gear?.roamGold ?? 0, gold, accuracy: 1e-9)
        }
    }

    func testThrivingOnlyFiresOnIncomeTicksAndRespectsCap() {
        let interval = Int(Balance.Gear.thrivingInterval * Balance.tickRate)
        var (f, a) = geared(GearCatalog.roamBootsID, spells: noSmite, time: 10)
        f.s.tick = interval * 10 + 1
        f.s.time = Double(f.s.tick) * Balance.dt
        let g0 = f.hero(a).gold
        GearSystem.update(&f.s, f.ctx)
        XCTAssertEqual(f.hero(a).gold, g0)

        f.s.tick = interval * 100
        f.s.time = Double(f.s.tick) * Balance.dt
        var g = GearState(option: .encourage)
        g.roamGold = Balance.Gear.roamGoldCap - 2
        f.s.units[a].hero!.gear = g
        GearSystem.update(&f.s, f.ctx)
        XCTAssertEqual(f.hero(a).gold - g0, 2, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).gear?.roamGold ?? 0, Balance.Gear.roamGoldCap, accuracy: 1e-9)
        // 上限に達したら入らない
        let g1 = f.hero(a).gold
        GearSystem.update(&f.s, f.ctx)
        XCTAssertEqual(f.hero(a).gold, g1)
    }

    func testRoamBootsHalveOwnFarmUntilEightMinutes() {
        for (time, factor) in [(100.0, 0.5), (500.0, 1.0)] {
            var (f, a) = geared(GearCatalog.roamBootsID, spells: noSmite, time: time)
            let m = f.addMinion(.melee, team: .red, at: spot)
            var gold = f.hero(a).gold
            f.kill(m, by: f.id(a))
            XCTAssertEqual(f.hero(a).gold - gold, Balance.Economy.minionGold(.melee, at: time) * factor, accuracy: 1e-9, "t=\(time)")
            XCTAssertEqual(f.hero(a).xp, Balance.Economy.minionXP(.melee) * factor, accuracy: 1e-9, "t=\(time)")

            f.s.units[a].hero!.xp = 0
            gold = f.hero(a).gold
            f.kill(f.addMonster(.campLarge, at: spot), by: f.id(a))
            XCTAssertEqual(f.hero(a).gold - gold, (Balance.Economy.monsterGold(.campLarge) * factor).rounded(), "t=\(time)")
            XCTAssertEqual(f.hero(a).xp, Balance.Economy.monsterXP(.campLarge) * factor, accuracy: 1e-9, "t=\(time)")
        }
    }

    func testRoamBootsGiveAssistBonus() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        f.s.firstBloodTaken = true
        let blue = f.heroes(.blue), red = f.heroes(.red)
        for i in blue + red { f.s.units[i].hero!.autoLevelSkills = false }
        let a = blue[0], b = blue[1], v = red[0]
        f.s.units[b].hero!.items = [GearCatalog.roamBootsID]
        f.s.units[b].hero!.itemInvested = [600]
        f.place(v, at: spot)
        f.place(a, at: spot)
        f.place(b, at: spot + Vec2(500, 0))
        f.addDamager(victim: v, source: b, secondsAgo: 4)
        f.addDamager(victim: v, source: a, secondsAgo: 0.1)
        let gold = f.hero(b).gold
        f.kill(v, by: f.id(a))
        // 単独アシスト = バウンティ 300 の半分 + ローム靴の追加
        XCTAssertEqual(f.hero(b).gold - gold, 150 + Balance.Gear.assistBonusGold, accuracy: 1e-9)
        // XP: キラー 130 の 60% = 78 + 追加
        XCTAssertEqual(f.hero(b).xp, 78 + Balance.Gear.assistBonusXP, accuracy: 1e-9)
    }

    // MARK: - ローム靴: 祝福

    func testRoamBlessingStagesFollowSharedGold() {
        XCTAssertEqual(GearEffects.roamStage(roamGold: 0), 0)
        XCTAssertEqual(GearEffects.roamStage(roamGold: 249), 0)
        XCTAssertEqual(GearEffects.roamStage(roamGold: 250), 1)
        XCTAssertEqual(GearEffects.roamStage(roamGold: 999), 2)
        XCTAssertEqual(GearEffects.roamStage(roamGold: 1000), 3)
        XCTAssertEqual(GearEffects.roamStage(roamGold: 2000), 3)
    }

    func testFavorHealsLowAllyOnlyAfterUnlockAndThenCoolsDown() {
        var (f, a) = geared(GearCatalog.roamBootsID, spells: noSmite, time: 100)
        let b = f.heroes(.blue)[1]
        f.place(b, at: spot + Vec2(200, 0))
        let maxHP = f.s.units[b].stats.maxHP
        f.s.units[b].hp = maxHP * 0.3
        f.s.tick = 3001            // 1 秒ごとの判定 tick ではない
        f.s.units[a].hero!.gear = GearState(option: .favor)
        var g = f.hero(a).gear!
        g.roamGold = 1000          // 段階 3
        f.s.units[a].hero!.gear = g

        GearSystem.update(&f.s, f.ctx)
        XCTAssertEqual(f.s.units[b].hp, maxHP * 0.3, accuracy: 1e-9)

        f.s.tick = 3030
        f.s.time = 101
        // 段階 0 では何もしない
        g.roamGold = 0
        f.s.units[a].hero!.gear = g
        GearSystem.update(&f.s, f.ctx)
        XCTAssertEqual(f.s.units[b].hp, maxHP * 0.3, accuracy: 1e-9)

        g.roamGold = 1000
        f.s.units[a].hero!.gear = g
        GearSystem.update(&f.s, f.ctx)
        XCTAssertGreaterThan(f.s.units[b].hp, maxHP * 0.3)
        XCTAssertGreaterThan(f.hero(a).gear!.abilityReadyAt, f.s.time)

        // クールダウン中は 2 回目が出ない
        let healed = f.s.units[b].hp
        f.s.units[b].hp = maxHP * 0.3
        f.s.tick = 3060
        f.s.time = 102
        GearSystem.update(&f.s, f.ctx)
        XCTAssertEqual(f.s.units[b].hp, maxHP * 0.3, accuracy: 1e-9)
        XCTAssertGreaterThan(healed, maxHP * 0.3)
    }

    func testEncourageBuffsNearbyAllies() {
        var (f, a) = geared(GearCatalog.roamBootsID, spells: noSmite, time: 100)
        let b = f.heroes(.blue)[1]
        f.place(b, at: spot + Vec2(300, 0))
        var g = GearState(option: .encourage)
        g.roamGold = 1000
        f.s.units[a].hero!.gear = g
        f.s.tick = 3030
        GearSystem.update(&f.s, f.ctx)
        for i in [a, b] {
            XCTAssertEqual(f.s.units[i].status(.attackSpeedBoost)?.magnitude ?? 0, Balance.Gear.encourageAttackSpeed,
                           accuracy: 1e-9)
            XCTAssertEqual(f.s.units[i].status(.damageBoost)?.magnitude ?? 0, Balance.Gear.encourageDamage,
                           accuracy: 1e-9)
        }
    }
}
