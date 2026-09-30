import XCTest
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud。戦闘中ショップの計算（おすすめ購入・購入順・見積もり・売却額）。

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
        let cheapest = ctx.master.items.filter { $0.tier == 1 && $0.category == .defense }
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
        let list = HUDShopLogic.items(in: .attack, master: .shared)
        XCTAssertFalse(list.isEmpty)
        XCTAssertTrue(list.allSatisfy { $0.category == .attack })
        for k in 1..<list.count {
            XCTAssertLessThanOrEqual(list[k - 1].tier, list[k].tier)
        }
    }

    func testFailureTexts() {
        let saved = Loc.current
        defer { Loc.current = saved }
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            let reasons: [PurchaseFailure] = [.slotsFull, .notEnoughGold, .uniqueCategory, .requiresSmite, .unknownItem]
            let texts = reasons.map { HUDShopLogic.failureText($0) ?? "" }
            XCTAssertTrue(texts.allSatisfy { !$0.isEmpty })
            XCTAssertEqual(Set(texts).count, texts.count)
        }
        XCTAssertNil(HUDShopLogic.failureText(nil))
        XCTAssertFalse(HUDText.purchaseFailure("garbage").isEmpty)
    }
}
