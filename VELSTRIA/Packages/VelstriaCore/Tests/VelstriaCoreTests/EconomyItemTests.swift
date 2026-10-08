import XCTest
@testable import VelstriaCore

/// 装備: 合成・制限・売却・パッシブ・ルーン・推奨ビルド（DESIGN §8）。
final class EconomyItemTests: XCTestCase {
    private func setup(spells: [String]? = nil, gold: Double = 5000) -> EconomyFixture {
        var f = EconomyFixture.standard()
        let i = f.human
        f.s.units[i].hero!.gold = gold
        if let spells { f.s.units[i].hero!.spells = spells }
        f.s.events.removeAll()
        return f
    }

    private func buy(_ f: inout EconomyFixture, _ i: Int, _ id: String) -> [SimEvent] {
        f.s.events.removeAll()
        ItemSystem.buy(&f.s, f.ctx, heroIndex: i, itemID: id)
        return f.s.events
    }

    func testCombineCostConsumesComponents() {
        var f = setup(gold: 2000)
        let i = f.human
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ019", ctx: f.ctx), 960)
        _ = buy(&f, i, "EQ007")
        _ = buy(&f, i, "EQ007")
        XCTAssertEqual(f.hero(i).items, ["EQ007", "EQ007"])
        XCTAssertEqual(f.hero(i).gold, 2000 - 330 - 330)
        // 960 − (330 + 330) = 300（下限 960 × 0.3 = 288 より上）
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ019", ctx: f.ctx), 300)
        let ev = buy(&f, i, "EQ019")
        XCTAssertTrue(ev.contains(.itemPurchased(heroID: f.id(i), itemID: "EQ019")))
        XCTAssertEqual(f.hero(i).items, ["EQ019"])
        XCTAssertEqual(f.hero(i).itemInvested, [Double(330 + 330 + 300)])
        XCTAssertEqual(f.hero(i).gold, 2000 - 330 - 330 - 300)
        // 能力値は即時反映（攻撃速度 +45%・移動速度 +15・クリティカル率 +8%）
        let def = f.master.hero(f.hero(i).heroID)!
        let base = HeroGrowth.baseStats(def: def, level: 1)
        XCTAssertEqual(f.s.units[i].stats.attackSpeed, base.attackSpeed * 1.45, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[i].stats.moveSpeed, base.moveSpeed + 15, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[i].stats.critChance, base.critChance + 0.08, accuracy: 1e-6)
    }

    func testPartialComponentDiscount() {
        var f = setup(gold: 5000)
        let i = f.human
        _ = buy(&f, i, "EQ025")    // EQ043 = EQ025 + EQ031
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ043", ctx: f.ctx), 2800 - 1070)
        let q = ItemSystem.quote(f.hero(i), itemID: "EQ043", ctx: f.ctx)
        XCTAssertEqual(q.consumedSlots, [0])
        XCTAssertTrue(q.canBuy)
    }

    func testDuplicateComponentsMatchedOncePerOwnedCopy() {
        var f = setup(gold: 5000)
        let i = f.human
        _ = buy(&f, i, "EQ009")
        // EQ021 = EQ009 + EQ009（1 個所持）→ 1040 − 380 = 660
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ021", ctx: f.ctx), 660)
        _ = buy(&f, i, "EQ009")
        // 2 個所持 → 1040 − 760 = 280 < 下限 → round(1040 × 0.3) = 312
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ021", ctx: f.ctx), 312)
        _ = buy(&f, i, "EQ001")
        _ = buy(&f, i, "EQ021")
        XCTAssertEqual(f.hero(i).items, ["EQ001", "EQ021"])
        XCTAssertEqual(f.hero(i).itemInvested, [350, Double(380 * 2 + 312)])
    }

    func testSlotLimitAppliesAfterConsumption() {
        var f = setup(gold: 20000)
        let i = f.human
        for id in ["EQ003", "EQ009", "EQ001", "EQ002", "EQ005", "EQ007"] { _ = buy(&f, i, id) }
        XCTAssertEqual(f.hero(i).items.count, 6)
        let full = buy(&f, i, "EQ008")
        XCTAssertEqual(full.purchaseFailures, ["slots_full"])
        XCTAssertEqual(f.hero(i).items.count, 6)
        // 素材 2 個を消費する合成は 6 枠でも買える（EQ033 = EQ003 + EQ009）
        let ok = buy(&f, i, "EQ033")
        XCTAssertTrue(ok.purchaseFailures.isEmpty)
        XCTAssertEqual(f.hero(i).items.count, 5)
        XCTAssertFalse(f.hero(i).items.contains("EQ003"))
        XCTAssertFalse(f.hero(i).items.contains("EQ009"))
    }

    func testNotEnoughGoldAndUnknownItem() {
        var f = setup(gold: 100)
        let i = f.human
        XCTAssertEqual(buy(&f, i, "EQ001").purchaseFailures, ["not_enough_gold"])
        XCTAssertEqual(buy(&f, i, "NOPE").purchaseFailures, ["unknown_item"])
        XCTAssertEqual(f.hero(i).gold, 100)
        XCTAssertTrue(f.hero(i).items.isEmpty)
    }

    func testMovementIsUnique() {
        var f = setup(gold: 5000)
        let i = f.human
        _ = buy(&f, i, "EQ004")
        XCTAssertEqual(buy(&f, i, "EQ010").purchaseFailures, ["unique_category"])
        XCTAssertEqual(buy(&f, i, "EQ052").purchaseFailures, ["unique_category"])
        XCTAssertEqual(f.hero(i).items, ["EQ004"])
    }

    func testJungleRequiresSmiteAndIsUnique() {
        var f = setup(spells: ["BS01", "BS03"], gold: 5000)
        let i = f.human
        XCTAssertEqual(buy(&f, i, "EQ006").purchaseFailures, ["requires_smite"])
        f.s.units[i].hero!.spells = ["BS05", "BS01"]
        XCTAssertTrue(buy(&f, i, "EQ006").purchaseFailures.isEmpty)
        XCTAssertEqual(buy(&f, i, "EQ012").purchaseFailures, ["unique_category"])
        // 所持中の Jungle 素材を消費する Jungle 合成は可（EQ024 = EQ006 + EQ001）
        XCTAssertTrue(buy(&f, i, "EQ024").purchaseFailures.isEmpty)
        XCTAssertEqual(f.hero(i).items, ["EQ024"])
    }

    func testMovementItemDoesNotNeedSmiteAndCoexistsWithJungle() {
        var f = setup(spells: ["BS05", "BS01"], gold: 5000)
        let i = f.human
        _ = buy(&f, i, "EQ018")                  // Jungle 素材
        XCTAssertTrue(buy(&f, i, "EQ022").purchaseFailures.isEmpty)   // Movement = EQ004 + EQ010（定価）
        XCTAssertEqual(f.hero(i).items, ["EQ018", "EQ022"])
        // 狩猟印が無くても Movement 装備自体は買える（定価）
        var g = setup(spells: ["BS01", "BS03"], gold: 5000)
        let j = g.human
        XCTAssertTrue(buy(&g, j, "EQ022").purchaseFailures.isEmpty)
        XCTAssertEqual(g.hero(j).gold, 5000 - 930)
    }

    func testSellRefundsSixtyPercentOfInvested() {
        var f = setup(gold: 2000)
        let i = f.human
        _ = buy(&f, i, "EQ007")
        _ = buy(&f, i, "EQ007")
        _ = buy(&f, i, "EQ019")
        let gold = f.hero(i).gold
        XCTAssertEqual(ItemSystem.sellValue(f.hero(i), slotIndex: 0, master: f.master), (960 * 0.6).rounded())
        f.s.events.removeAll()
        ItemSystem.sell(&f.s, f.ctx, heroIndex: i, slotIndex: 0)
        XCTAssertEqual(f.hero(i).gold - gold, 576)
        XCTAssertTrue(f.hero(i).items.isEmpty)
        XCTAssertTrue(f.hero(i).itemInvested.isEmpty)
        XCTAssertTrue(f.s.events.contains(.itemSold(heroID: f.id(i), itemID: "EQ019", refund: 576)))
        // 範囲外は無視
        ItemSystem.sell(&f.s, f.ctx, heroIndex: i, slotIndex: 3)
        XCTAssertEqual(f.hero(i).gold - gold, 576)
    }

    func testPracticeInfiniteGold() {
        let opts = PracticeOptions(infiniteGold: true, spawnMinions: false, spawnDummies: false)
        var f = EconomyFixture(config: MatchFactory.practiceMatch(humanHeroID: "H002", humanName: "P",
                                                                  options: opts, seed: 1))
        let i = f.human
        ItemSystem.buy(&f.s, f.ctx, heroIndex: i, itemID: "EQ049")
        XCTAssertEqual(f.hero(i).items, ["EQ049"])
        XCTAssertEqual(f.hero(i).gold, Balance.Economy.practiceGold)
        f.s.units[i].hero!.gold = 10
        f.economyTick()
        XCTAssertEqual(f.hero(i).gold, Balance.Economy.practiceGold)
        // 獲得 Gold には数えない
        XCTAssertEqual(f.hero(i).score.goldEarned, 0)
    }

    // MARK: - パッシブ・ルーン

    func testItemFlatStats() {
        let m = MasterData.shared
        var st = Stats()
        st.resourceRegen = 10
        ItemStats.apply(items: ["EQ001", "EQ001", "EQ002", "EQ003", "EQ004", "EQ005", "EQ006"], runes: [],
                        to: &st, master: m)
        XCTAssertEqual(st.attack, 25 * 2 + 18, accuracy: 1e-9)           // 固定値は個数分
        XCTAssertEqual(st.abilityPower, 30, accuracy: 1e-9)
        XCTAssertEqual(st.maxHP, 1 + 400 + 300, accuracy: 1e-9)
        XCTAssertEqual(st.hpRegen, 6, accuracy: 1e-9)
        XCTAssertEqual(st.moveSpeed, 40, accuracy: 1e-9)
        XCTAssertEqual(st.resourceRegen, 10, accuracy: 1e-9)
        XCTAssertEqual(st.monsterDamageBonus, 0.25, accuracy: 1e-9)      // Jungle 装備
        XCTAssertEqual(st.monsterGoldBonus, Balance.Economy.jungleMonsterGoldBonus, accuracy: 1e-9)
        XCTAssertEqual(st.cooldownReduction, 0, accuracy: 1e-9)
    }

    func testJungleMonsterDamageDoesNotStackAcrossCopies() {
        let m = MasterData.shared
        var st = Stats()
        ItemStats.apply(items: ["EQ006", "EQ006"], runes: [], to: &st, master: m)
        XCTAssertEqual(st.monsterDamageBonus, 0.25, accuracy: 1e-9)
        XCTAssertEqual(st.attack, 36, accuracy: 1e-9)
    }

    func testPhysicalPenetrationPercentTakesTheMaxAndFlatStacks() {
        let m = MasterData.shared
        var st = Stats()
        // EQ061 割合 40%、EQ054 割合 15%（重ならず最大）、EQ031・EQ064 固定 15 ずつ（合算）
        ItemStats.apply(items: ["EQ061", "EQ061", "EQ054", "EQ031", "EQ064"], runes: [], to: &st, master: m)
        XCTAssertEqual(st.armorPenPct, 0.40, accuracy: 1e-9)
        XCTAssertEqual(st.armorPenFlat, 30, accuracy: 1e-9)
        XCTAssertEqual(st.attack, 70 * 2 + 70 + 60 + 15, accuracy: 1e-9)
        XCTAssertEqual(st.cooldownReduction, 0.10, accuracy: 1e-9)
    }

    func testMagicPenetrationAndPowerPercent() {
        let m = MasterData.shared
        var st = Stats()
        ItemStats.apply(items: ["EQ044", "EQ044", "EQ020", "EQ052"], runes: [], to: &st, master: m)
        XCTAssertEqual(st.magicPenPct, 0.40, accuracy: 1e-9)
        XCTAssertEqual(st.magicPenFlat, 12 + 15, accuracy: 1e-9)
        XCTAssertEqual(st.abilityPower, 85 * 2 + 62, accuracy: 1e-9)
        XCTAssertEqual(st.moveSpeed, 12 + 45, accuracy: 1e-9)
        // 魔力 +25%（Genius Wand 系）は重ならず、装備の魔力が確定した後に掛かる
        var p = Stats()
        ItemStats.apply(items: ["EQ050", "EQ050"], runes: [], to: &p, master: m)
        XCTAssertEqual(p.abilityPower, 210 * 1.25, accuracy: 1e-9)
    }

    func testCritChanceIsCappedAndCritDamageAdds() {
        let m = MasterData.shared
        var st = Stats()
        let baseCrit = st.critMultiplier
        ItemStats.apply(items: ["EQ055", "EQ055", "EQ055"], runes: [], to: &st, master: m)
        XCTAssertEqual(st.critChance, 1, accuracy: 1e-9)
        XCTAssertEqual(st.critMultiplier, baseCrit + 1.2, accuracy: 1e-9)
    }

    func testRunesValorArcanaResolve() {
        let m = MasterData.shared
        var st = Stats()
        st.attack = 100; st.abilityPower = 100; st.maxHP = 1000; st.armor = 50; st.magicResist = 40
        // RN01 Valor 3% (T1) / RN12 Arcana 7% (T2) / RN23 Resolve 4% (T3)。不正 ID・同 Tier の 2 個目は無視
        ItemStats.apply(items: [], runes: ["RN01", "BOGUS", "", "RN06", "RN12", "RN23"], to: &st, master: m)
        XCTAssertEqual(st.attack, 103, accuracy: 1e-9)
        XCTAssertEqual(st.abilityPower, 107, accuracy: 1e-9)
        XCTAssertEqual(st.skillDamageBonus, 0.035, accuracy: 1e-9)
        XCTAssertEqual(st.maxHP, 1040, accuracy: 1e-9)
        XCTAssertEqual(st.armor, 52, accuracy: 1e-9)
        XCTAssertEqual(st.magicResist, 41.6, accuracy: 1e-9)
        XCTAssertEqual(ItemStats.validRunes(["RN01", "BOGUS", "RN06", "RN12", "RN23"], master: m).map(\.runeID),
                       ["RN01", "RN12", "RN23"])
    }

    func testRunesCunningHarmonyApplyAfterItems() {
        let m = MasterData.shared
        var st = Stats()
        st.moveSpeed = 300; st.hpRegen = 10; st.resourceRegen = 5
        // RN04 Cunning 6% (T1) / RN20 Harmony 8% (T2) + Movement 装備 EQ004（+40 移動速度）
        ItemStats.apply(items: ["EQ004"], runes: ["RN04", "RN20"], to: &st, master: m)
        XCTAssertEqual(st.moveSpeed, 340 * 1.03, accuracy: 1e-9)
        XCTAssertEqual(st.cooldownReduction, 0.03, accuracy: 1e-9)
        XCTAssertEqual(st.hpRegen, 10 * 1.24, accuracy: 1e-9)
        XCTAssertEqual(st.resourceRegen, 5 * 1.24, accuracy: 1e-9)
        XCTAssertEqual(st.healShieldPower, 0.08, accuracy: 1e-9)
    }

    func testHeroStatsIncludeRunesViaStatCalculator() {
        var f = EconomyFixture.standard()
        let i = f.human
        let before = f.s.units[i].stats.attack
        f.s.units[i].hero!.runes = ["RN06"]    // Valor 8%
        StatCalculator.recompute(&f.s, i, f.ctx)
        XCTAssertEqual(f.s.units[i].stats.attack, before * 1.08, accuracy: 1e-6)
    }

    // MARK: - 推奨ビルド

    func testRecommendedBuildsPerRole() {
        let m = MasterData.shared
        let expected: [Role: [ItemCategory: Int]] = [
            .ranger: [.attack: 5, .movement: 1],
            .arcanist: [.magic: 4, .movement: 1, .utility: 1],
            .vanguard: [.defense: 4, .utility: 2],
            .duelist: [.attack: 3, .defense: 3],
            .assassin: [.jungle: 1, .attack: 5],
            .support: [.utility: 3, .defense: 3],
        ]
        for role in Role.allCases {
            let build = ItemSystem.recommendedBuild(role: role, master: m)
            XCTAssertEqual(build.count, 6, "\(role)")
            XCTAssertEqual(Set(build).count, 6, "\(role) は重複なし")
            XCTAssertEqual(build, ItemSystem.recommendedBuild(role: role, master: m), "決定論")
            var counts: [ItemCategory: Int] = [:]
            for id in build { counts[m.item(id)!.category, default: 0] += 1 }
            XCTAssertEqual(counts, expected[role], "\(role)")
            XCTAssertTrue(build.allSatisfy { m.item($0)!.tier == 3 }, "\(role) は完成品")
        }
    }

    func testRecommendedBuildAdaptsToSmite() {
        let m = MasterData.shared
        let f = EconomyFixture.standard()
        var h = f.hero(f.human)
        h.role = .assassin
        h.spells = ["BS01", "BS03"]
        let noSmite = ItemSystem.recommendedBuild(for: h, master: m)
        XCTAssertFalse(noSmite.contains { m.item($0)!.category == .jungle })
        XCTAssertEqual(noSmite.filter { m.item($0)!.category == .movement }.count, 1)
        h.role = .duelist
        h.position = .jungle
        h.spells = ["BS05", "BS01"]
        let jungler = ItemSystem.recommendedBuild(for: h, master: m)
        XCTAssertEqual(jungler.count, 6)
        XCTAssertEqual(m.item(jungler[0])!.category, .jungle)
    }

    func testNextRecommendedPurchaseBuysComponentsFirst() {
        var f = setup(spells: ["BS01", "BS03"], gold: 300)
        let i = f.human
        f.s.units[i].hero!.role = .ranger
        let build = ItemSystem.recommendedBuild(for: f.hero(i), master: f.master)
        let first = f.master.item(build[0])!
        XCTAssertFalse(first.buildFrom.isEmpty)
        let cheapest = first.buildFrom.map { f.master.item($0)!.priceGold }.min()!
        // 何も買えない
        f.s.units[i].hero!.gold = cheapest - 1
        XCTAssertNil(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx))
        // 素材なら買える
        f.s.units[i].hero!.gold = cheapest
        let step = ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx)
        XCTAssertNotNil(step)
        XCTAssertTrue(first.buildFrom.contains(step!))
        // 完成品が買えるなら完成品
        f.s.units[i].hero!.gold = first.priceGold
        XCTAssertEqual(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx), first.itemID)

        // 推奨に沿って買い進めると最終的に 6 完成品が揃う
        f.s.units[i].hero!.gold = 50_000
        var guardCount = 0
        while let next = ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx), guardCount < 40 {
            _ = buy(&f, i, next)
            guardCount += 1
        }
        XCTAssertEqual(f.hero(i).items.sorted(), build.sorted())
        XCTAssertNil(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx))
    }

    func testNextRecommendedPurchaseWithCustomBuild() {
        var f = setup(spells: ["BS01", "BS03"], gold: 400)
        let i = f.human
        // 狩猟印なしの Jungle 装備はスキップされ次の候補へ
        let custom = ["EQ006", "EQ001", "XXX"]
        XCTAssertEqual(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx, customBuild: custom), "EQ001")
        _ = buy(&f, i, "EQ001")
        XCTAssertNil(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx, customBuild: custom))
    }
}
