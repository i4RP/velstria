import XCTest
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud。戦闘中ショップの計算（おすすめ購入・購入順・見積もり・売却額・祝福のカード）と、
// アクティブ装備・隠蔽・ポーションの表示値、そのボタンの配置。

final class HUDShopTests: XCTestCase {
    private func makeHero(gold: Double, items: [String] = [], heroID: String = "H003") -> (HeroData, SimContext) {
        let config = MatchFactory.standardMatch(humanHeroID: heroID, humanName: "T", seed: 11)
        let sim = Simulation(config: config)
        let i = sim.state.humanHeroIndex!
        var h = sim.state.units[i].hero!
        h.gold = gold
        h.items = items
        h.itemInvested = items.map { sim.ctx.master.item($0)?.priceGold ?? 0 }
        return (h, sim.ctx)
    }

    func testQuickBuyFollowsItemSystemAndSetting() {
        let (h, ctx) = makeHero(gold: 5000)
        let expected = ItemSystem.nextRecommendedPurchase(h, ctx: ctx, customBuild: nil)
        XCTAssertNotNil(expected)
        XCTAssertEqual(HUDShopLogic.quickBuy(hero: h, ctx: ctx, customBuild: nil, enabled: true), expected)
        XCTAssertNil(HUDShopLogic.quickBuy(hero: h, ctx: ctx, customBuild: nil, enabled: false), "設定オフなら出さない")
    }

    func testQuickBuyHiddenWhenNothingAffordable() {
        let (h, ctx) = makeHero(gold: 0)
        XCTAssertNil(HUDShopLogic.quickBuy(hero: h, ctx: ctx, customBuild: nil, enabled: true))
    }

    func testQuickBuyUsesCustomBuild() {
        let (h, ctx) = makeHero(gold: 5000)
        let cheapest = ctx.master.items.filter { $0.tier == 1 && $0.category == .defense && !$0.isConsumable }
            .min { $0.priceGold < $1.priceGold }!
        let custom = [cheapest.itemID]
        XCTAssertEqual(HUDShopLogic.quickBuy(hero: h, ctx: ctx, customBuild: custom, enabled: true), cheapest.itemID)
        // 持っていれば次は無い
        let (owned, ctx2) = makeHero(gold: 5000, items: custom)
        XCTAssertNil(HUDShopLogic.quickBuy(hero: owned, ctx: ctx2, customBuild: custom, enabled: true))
    }

    func testRecommendedPathMarksOwnedAndNext() {
        let (base, ctx) = makeHero(gold: 5000)
        let build = HUDShopLogic.build(hero: base, ctx: ctx, customBuild: nil)
        XCTAssertEqual(build.count, 6)
        let (h, _) = makeHero(gold: 5000, items: [build[0]])
        let path = HUDShopLogic.recommendedPath(hero: h, ctx: ctx, customBuild: nil)
        XCTAssertEqual(path.map(\.itemID), build)
        XCTAssertTrue(path[0].owned)
        XCTAssertFalse(path[0].isNext)
        XCTAssertEqual(path.filter(\.isNext).count, 1, "次の購入は 1 つだけ")
        XCTAssertEqual(path.filter(\.isGoal).count, 0)
        let next = ItemSystem.nextRecommendedPurchase(h, ctx: ctx, customBuild: nil)!
        let nextStep = path.first(where: \.isNext)!
        XCTAssertTrue(nextStep.itemID == next || ctx.master.item(nextStep.itemID)!.buildFrom.contains(next))
    }

    func testPathShowsGoalWhenBroke() {
        let (h, ctx) = makeHero(gold: 0)
        let path = HUDShopLogic.recommendedPath(hero: h, ctx: ctx, customBuild: nil)
        XCTAssertEqual(path.filter(\.isNext).count, 0)
        XCTAssertEqual(path.first(where: \.isGoal)?.id, 0)
    }

    func testShopStateUsesQuotes() {
        let (h, ctx) = makeHero(gold: 400)
        let st = HUDShopLogic.state(hero: h, ctx: ctx, customBuild: nil)
        XCTAssertEqual(st.entries.count, ctx.master.items.count)
        XCTAssertEqual(st.gold, 400)
        for item in ctx.master.items {
            let q = ItemSystem.quote(h, itemID: item.itemID, ctx: ctx)
            let e = st.entry(item.itemID)
            XCTAssertEqual(e?.cost, Int(q.cost), item.itemID)
            XCTAssertEqual(e?.failure, q.failure, item.itemID)
        }
        let expensive = ctx.master.items.max { $0.priceGold < $1.priceGold }!
        XCTAssertEqual(st.entry(expensive.itemID)?.failure, .notEnoughGold)
    }

    func testCombineDiscountAndSellValue() {
        let master = MasterData.shared
        guard let combined = master.items.first(where: { !$0.buildFrom.isEmpty }) else { return XCTFail("合成装備が無い") }
        let part = combined.buildFrom[0]
        let (h, ctx) = makeHero(gold: 10000, items: [part])
        let st = HUDShopLogic.state(hero: h, ctx: ctx, customBuild: nil)
        XCTAssertEqual(st.entry(combined.itemID)?.cost, Int(ItemSystem.effectiveCost(h, itemID: combined.itemID, ctx: ctx)))
        XCTAssertLessThan(st.entry(combined.itemID)?.cost ?? .max, Int(combined.priceGold), "素材を持っていれば安くなる")
        XCTAssertEqual(st.sellValues, [Int(ItemSystem.sellValue(h, slotIndex: 0, master: master))])
        XCTAssertEqual(st.entry(part)?.ownedCount, 1)
    }

    func testRecommendedGridListsComponentsBeforeTargets() {
        let (h, ctx) = makeHero(gold: 0)
        let path = HUDShopLogic.recommendedPath(hero: h, ctx: ctx, customBuild: nil)
        let grid = HUDShopLogic.recommendedGridItems(path, master: ctx.master).map(\.itemID)
        XCTAssertEqual(Set(grid).count, grid.count, "重複なし")
        for step in path {
            guard let k = grid.firstIndex(of: step.itemID) else { return XCTFail("\(step.itemID) が一覧に無い") }
            for part in ctx.master.item(step.itemID)!.buildFrom {
                XCTAssertLessThan(grid.firstIndex(of: part) ?? .max, k, "素材が先")
            }
        }
    }

    func testCategoryListingOrder() {
        let master = MasterData.shared
        let list = HUDShopLogic.items(in: .attack, master: master)
        XCTAssertFalse(list.isEmpty)
        XCTAssertTrue(list.allSatisfy { $0.isListed(in: .attack) })
        XCTAssertEqual(list.map(\.itemID), list.map(\.itemID).sorted(), "ID 順")
        // 別のタブにも並ぶ装備（ウィンタークラウン = 攻撃 + 魔法、フリーティングタイム = 攻撃 + 魔法 + 防御）
        XCTAssertTrue(HUDShopLogic.items(in: .magic, master: master).contains { $0.itemID == "EQ113" })
        XCTAssertTrue(HUDShopLogic.items(in: .defense, master: master).contains { $0.itemID == "EQ114" })
        // ポーションは各タブで買える
        XCTAssertTrue(list.contains { $0.itemID == "EQ134" })
        // ジャングル・ロームは祝福のタブ
        XCTAssertTrue(HUDShopLogic.items(in: .jungle, master: master).isEmpty)
        XCTAssertTrue(HUDShopLogic.items(in: .roam, master: master).isEmpty)
        var listed = Set<String>()
        for c in ItemCategory.allCases { listed.formUnion(HUDShopLogic.items(in: c, master: master).map(\.itemID)) }
        XCTAssertEqual(listed.count, master.items.count, "どの装備もどこかのタブに並ぶ")
    }

    func testFailureTexts() {
        let saved = Loc.current
        defer { Loc.current = saved }
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            let reasons: [PurchaseFailure] = [.slotsFull, .notEnoughGold, .uniqueCategory, .requiresSmite, .blockedBySmite,
                                              .roamClosed, .unknownItem]
            let texts = reasons.map { HUDShopLogic.failureText($0) ?? "" }
            XCTAssertTrue(texts.allSatisfy { !$0.isEmpty })
            XCTAssertEqual(Set(texts).count, texts.count)
        }
        XCTAssertNil(HUDShopLogic.failureText(nil))
        XCTAssertFalse(HUDText.purchaseFailure("garbage").isEmpty)
        Loc.current = .ja
        XCTAssertEqual(HUDShopLogic.failureText(.roamClosed), "ロームの祝福は 2:00 を過ぎると付けられません")
    }

    // MARK: 祝福（ジャングル・ローム）

    func testBlessingCardsFollowGearQuotes() {
        let made = makeHero(gold: 5000)
        var h = made.0
        let ctx = made.1
        h.spells = ["BS01", "BS03"]
        // 狩猟印なし・靴なし・2:00 前: ジャングルは付けられず、ロームはスピードブーツ込み
        var cards = HUDShopLogic.blessingCards(hero: h, time: 60, ctx: ctx)
        XCTAssertEqual(cards.map(\.option), GearOption.allCases)
        for card in cards {
            let q = GearEffects.quote(h, option: card.option, time: 60, ctx: ctx)
            XCTAssertEqual(card.failure, q.failure, card.option.rawValue)
            XCTAssertEqual(card.cost, Int(q.cost), card.option.rawValue)
            XCTAssertFalse(card.isCurrent)
        }
        let boots = ctx.master.item(Balance.Gear.baseBootsID)!
        XCTAssertTrue(cards.filter { $0.option.category == .jungle }.allSatisfy { $0.failure == .requiresSmite })
        XCTAssertTrue(cards.filter { $0.option.category == .roam }.allSatisfy { $0.canApply && $0.cost == Int(boots.priceGold) })
        // 2:00 を過ぎるとロームの祝福は新たには付けられない
        cards = HUDShopLogic.blessingCards(hero: h, time: Balance.Gear.roamPurchaseDeadline + 1, ctx: ctx)
        XCTAssertTrue(cards.filter { $0.option.category == .roam }.allSatisfy { $0.failure == .roamClosed })
        // 狩猟印あり: ジャングルは付けられ、ロームは付けられない
        h.spells = [Balance.Economy.smiteSpellID, "BS01"]
        cards = HUDShopLogic.blessingCards(hero: h, time: 60, ctx: ctx)
        XCTAssertTrue(cards.filter { $0.option.category == .jungle }.allSatisfy(\.canApply))
        XCTAssertTrue(cards.filter { $0.option.category == .roam }.allSatisfy { $0.failure == .blockedBySmite })
    }

    func testShopStateMarksCurrentBlessingAndProgress() throws {
        let saved = Loc.current
        defer { Loc.current = saved }
        Loc.current = .ja
        let made = makeHero(gold: 5000, items: ["EQ403"])
        var h = made.0
        let ctx = made.1
        h.spells = ["BS01", "BS03"]
        var g = GearState(option: .encourage)
        g.roamGold = 640
        h.gear = g
        h.score.kills = 2
        h.score.assists = 1
        let st = HUDShopLogic.state(hero: h, ctx: ctx, customBuild: nil, time: 60)
        XCTAssertEqual(st.gearOption, .encourage)
        XCTAssertEqual(st.roamGold, 640)
        XCTAssertFalse(st.roamUnlocked)
        XCTAssertEqual(st.jungleProgress, 3)
        let current = try XCTUnwrap(st.blessing(.encourage))
        XCTAssertTrue(current.isCurrent)
        XCTAssertFalse(current.canApply)
        XCTAssertEqual(current.cost, 0, "靴があれば 0 Gold")
        XCTAssertEqual(HUDShopLogic.blessingActionTitle(current, current: st.gearOption), "付与済み")
        let favor = try XCTUnwrap(st.blessing(.favor))
        XCTAssertTrue(favor.canApply)
        XCTAssertEqual(HUDShopLogic.blessingActionTitle(favor, current: st.gearOption), "付け替え")
        XCTAssertEqual(HUDShopLogic.blessingActionTitle(favor, current: nil), "付与")
        XCTAssertEqual(HUDShopLogic.blessingCostText(favor, master: ctx.master), "0")
        var withBoots = favor
        withBoots.cost = 250
        XCTAssertTrue(HUDShopLogic.blessingCostText(withBoots, master: ctx.master).hasSuffix("込み 250"))
        // 進み具合
        XCTAssertEqual(HUDShopLogic.blessingProgressText(.roam, shop: st), "共栄ゴールド 640 / 1000")
        XCTAssertEqual(HUDShopLogic.blessingProgressText(.jungle, shop: st), "狩りとキル 3 / 5")
        XCTAssertNil(HUDShopLogic.blessingProgressText(.attack, shop: st))
        XCTAssertEqual(HUDShopLogic.blessings(in: .roam, shop: st).map(\.option), GearOption.options(for: .roam))
        // 詳細に出す祝福: 選んだもの → 付いているもの → タブの先頭
        XCTAssertEqual(HUDShopLogic.focusedBlessing(category: .roam, selected: .favor, shop: st), .favor)
        XCTAssertEqual(HUDShopLogic.focusedBlessing(category: .roam, selected: .flame, shop: st), .encourage)
        XCTAssertEqual(HUDShopLogic.focusedBlessing(category: .jungle, selected: nil, shop: st),
                       GearOption.options(for: .jungle).first)
        // 靴を手放すと祝福は外れる
        h.items = []
        h.itemInvested = []
        XCTAssertNil(HUDShopLogic.state(hero: h, ctx: ctx, customBuild: nil, time: 60).gearOption)
    }
}
