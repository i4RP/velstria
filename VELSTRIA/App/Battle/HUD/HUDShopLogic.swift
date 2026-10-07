import Foundation
import VelstriaCore

// 担当: battle-hud。戦闘中ショップ（UI028）の計算（純粋関数。単体テスト対象）。
// 価格・可否は ItemSystem（quote / effectiveCost / sellValue / nextRecommendedPurchase）をそのまま使う。

struct HUDShopEntry: Equatable, Identifiable {
    var id: String { itemID }
    var itemID: String
    /// 合成割引込みの実コスト。
    var cost: Int
    var failure: PurchaseFailure?
    var ownedCount: Int

    var canBuy: Bool { failure == nil }
}

struct HUDShopPathStep: Equatable, Identifiable {
    var id: Int
    var itemID: String
    var owned: Bool
    /// 次に買うべき（またはその素材を買う）装備。
    var isNext: Bool
    /// 買える物が無い時に貯金の目標とする装備。
    var isGoal: Bool
}

struct HUDShopState: Equatable {
    var gold = 0
    var items: [String] = []
    var sellValues: [Int] = []
    /// MasterData.items と同じ順序。
    var entries: [HUDShopEntry] = []
    var path: [HUDShopPathStep] = []
    var next: String?
    /// 選んでいる靴のオプション（靴を持っていなければ nil）。
    var gearOption: GearOption?
    /// ローム靴の共有収入の累計とその祝福の段階（0〜3）。
    var roamGold = 0
    var roamStage = 0
    /// ジャングル靴の祝福の進み具合（狩り・キル・アシストの合計）と解放済みか。
    var jungleProgress = 0
    var jungleBlessed = false

    func entry(_ itemID: String) -> HUDShopEntry? {
        guard let k = HUDShopLogic.catalogIndex(itemID) else { return nil }
        return k < entries.count ? entries[k] : nil
    }
}

enum HUDShopLogic {
    /// 装備 ID → MasterData.items の添字（検索専用）。
    private static let indexByID: [String: Int] = {
        var d: [String: Int] = [:]
        for (k, it) in MasterData.shared.items.enumerated() { d[it.itemID] = k }
        return d
    }()

    static func catalogIndex(_ itemID: String) -> Int? { indexByID[itemID] }

    /// おすすめ購入（HUD のクイック購入）。表示しない設定なら nil。
    static func quickBuy(hero: HeroData, ctx: SimContext, customBuild: [String]?, enabled: Bool) -> String? {
        guard enabled else { return nil }
        return ItemSystem.nextRecommendedPurchase(hero, ctx: ctx, customBuild: customBuild)
    }

    /// 使うビルド（カスタムビルドが有効ならそれ、無ければロール別の推奨）。
    static func build(hero: HeroData, ctx: SimContext, customBuild: [String]?) -> [String] {
        if let custom = customBuild?.filter({ ctx.master.item($0) != nil }), !custom.isEmpty { return custom }
        return ItemSystem.recommendedBuild(for: hero, master: ctx.master)
    }

    /// おすすめの購入順（所持済み・次・目標の印付き）。
    static func recommendedPath(hero: HeroData, ctx: SimContext, customBuild: [String]?) -> [HUDShopPathStep] {
        let build = build(hero: hero, ctx: ctx, customBuild: customBuild)
        let next = ItemSystem.nextRecommendedPurchase(hero, ctx: ctx, customBuild: customBuild)
        var pool = hero.items
        var marked = false
        var steps: [HUDShopPathStep] = []
        for (k, id) in build.enumerated() {
            var owned = false
            if let j = pool.firstIndex(of: id) {
                pool.remove(at: j)
                owned = true
            }
            var isNext = false
            if !owned && !marked, let next,
               next == id || ctx.master.item(id)?.buildFrom.contains(next) == true {
                isNext = true
                marked = true
            }
            steps.append(HUDShopPathStep(id: k, itemID: id, owned: owned, isNext: isNext, isGoal: false))
        }
        if !marked, let k = steps.firstIndex(where: { !$0.owned }) { steps[k].isGoal = true }
        return steps
    }

    /// ショップ全体の状態（Gold・所持品が変わった時だけ作り直す）。
    static func state(hero: HeroData, ctx: SimContext, customBuild: [String]?) -> HUDShopState {
        var st = HUDShopState()
        st.gold = Int(EconomyRewards.hasInfiniteGold(ctx) ? Balance.Economy.practiceGold : hero.gold)
        st.items = hero.items
        st.sellValues = hero.items.indices.map { Int(ItemSystem.sellValue(hero, slotIndex: $0, master: ctx.master)) }
        st.entries = ctx.master.items.map { item in
            let q = ItemSystem.quote(hero, itemID: item.itemID, ctx: ctx)
            return HUDShopEntry(itemID: item.itemID, cost: q.cost.isFinite ? Int(q.cost) : 0, failure: q.failure,
                                ownedCount: hero.items.filter { $0 == item.itemID }.count)
        }
        st.path = recommendedPath(hero: hero, ctx: ctx, customBuild: customBuild)
        st.next = ItemSystem.nextRecommendedPurchase(hero, ctx: ctx, customBuild: customBuild)
        st.gearOption = GearEffects.option(of: hero, category: .roam, master: ctx.master)
            ?? GearEffects.option(of: hero, category: .jungle, master: ctx.master)
        st.roamGold = Int(hero.gear?.roamGold ?? 0)
        st.roamStage = GearEffects.roamStage(roamGold: hero.gear?.roamGold ?? 0)
        st.jungleProgress = hero.score.creepScore + hero.score.kills + hero.score.assists
        st.jungleBlessed = GearEffects.jungleBlessingActive(hero, master: ctx.master)
        return st
    }

    /// カテゴリの装備（Tier → 価格 → ID の順）。
    static func items(in category: ItemCategory, master: MasterData) -> [ItemDef] {
        master.items.filter { $0.category == category }.sorted {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.priceGold != $1.priceGold { return $0.priceGold < $1.priceGold }
            return $0.itemID < $1.itemID
        }
    }

    /// おすすめタブの一覧: 未所持のおすすめ装備と、その素材（素材が先・重複なし・購入順）。
    static func recommendedGridItems(_ path: [HUDShopPathStep], master: MasterData) -> [ItemDef] {
        var ids: [String] = []
        func add(_ id: String, depth: Int) {
            guard depth < 4, !ids.contains(id), let item = master.item(id) else { return }
            for part in item.buildFrom { add(part, depth: depth + 1) }
            ids.append(id)
        }
        for step in path where !step.owned { add(step.itemID, depth: 0) }
        return ids.compactMap { master.item($0) }
    }

    /// 表示用の購入不可理由。
    static func failureText(_ f: PurchaseFailure?) -> String? {
        guard let f else { return nil }
        return HUDText.purchaseFailure(f.rawValue)
    }
}
