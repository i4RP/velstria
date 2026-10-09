import Foundation
import VelstriaCore

// 担当: battle-hud。戦闘中ショップ（UI028）の計算（純粋関数。単体テスト対象）。
// 価格・可否は ItemSystem（quote / effectiveCost / sellValue / nextRecommendedPurchase）をそのまま使う。
// ジャングル・ロームのタブは装備ではなく、靴に付ける祝福（GearOption。可否は GearEffects.quote）を並べる。

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

/// 祝福（ジャングル・ローム）のカード。
struct HUDBlessingCard: Equatable, Identifiable {
    var id: GearOption { option }
    var option: GearOption
    /// 一緒に買う靴の Gold（靴があれば 0、無ければスピードブーツの分）。
    var cost: Int
    var failure: PurchaseFailure?
    /// いま靴に付いている祝福。
    var isCurrent: Bool

    var canApply: Bool { failure == nil && !isCurrent }
}

struct HUDShopState: Equatable {
    var gold = 0
    var items: [String] = []
    var sellValues: [Int] = []
    /// MasterData.items と同じ順序。
    var entries: [HUDShopEntry] = []
    var path: [HUDShopPathStep] = []
    var next: String?
    /// 靴に付いている祝福（靴を持っていなければ nil）。
    var gearOption: GearOption?
    /// 祝福のカード（GearOption.allCases の順）。
    var blessings: [HUDBlessingCard] = []
    /// ローム: 共栄ゴールド（共栄・無私で得た Gold の累計）と、祝福の効果を解放済み（1000）か。
    var roamGold = 0
    var roamUnlocked = false
    /// ジャングル: モンスター・キル・アシストの合計と、狩猟印を強化済み（ヒーローに使える）か。
    var jungleProgress = 0
    var jungleBlessed = false

    func entry(_ itemID: String) -> HUDShopEntry? {
        guard let k = HUDShopLogic.catalogIndex(itemID) else { return nil }
        return k < entries.count ? entries[k] : nil
    }

    func blessing(_ option: GearOption) -> HUDBlessingCard? {
        blessings.first { $0.option == option }
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

    /// ショップ全体の状態（Gold・所持品・祝福の進みが変わった時だけ作り直す）。time = 試合時間（ロームの祝福の締め切り）。
    static func state(hero: HeroData, ctx: SimContext, customBuild: [String]?, time: Double = 0) -> HUDShopState {
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
        st.gearOption = GearEffects.option(of: hero, master: ctx.master)
        st.blessings = blessingCards(hero: hero, time: time, ctx: ctx)
        st.roamGold = Int(hero.gear?.roamGold ?? 0)
        st.roamUnlocked = GearEffects.roamBlessingUnlocked(hero)
        st.jungleProgress = GearEffects.jungleProgress(hero)
        st.jungleBlessed = GearEffects.jungleBlessingActive(hero, master: ctx.master)
        return st
    }

    /// 祝福のカード（付けられるか・一緒に買う靴の Gold・付いているか）。並びは GearOption.allCases。
    static func blessingCards(hero: HeroData, time: Double, ctx: SimContext) -> [HUDBlessingCard] {
        let current = GearEffects.option(of: hero, master: ctx.master)
        return GearOption.allCases.map { o in
            let q = GearEffects.quote(hero, option: o, time: time, ctx: ctx)
            return HUDBlessingCard(option: o, cost: q.cost.isFinite ? Int(q.cost) : 0, failure: q.failure, isCurrent: current == o)
        }
    }

    /// タブ（.jungle / .roam）の祝福のカード。
    static func blessings(in category: ItemCategory, shop: HUDShopState) -> [HUDBlessingCard] {
        shop.blessings.filter { $0.option.category == category }
    }

    /// 詳細に出す祝福: 選んだもの → 付いているもの → タブの先頭（そのタブのものだけ）。
    static func focusedBlessing(category: ItemCategory, selected: GearOption?, shop: HUDShopState) -> GearOption? {
        if let selected, selected.category == category { return selected }
        if let current = shop.gearOption, current.category == category { return current }
        return GearOption.options(for: category).first
    }

    /// 祝福の進み具合（ジャングル: 狩りとキル、ローム: 共栄ゴールド）。祝福のタブ以外は nil。
    static func blessingProgressText(_ category: ItemCategory, shop: HUDShopState) -> String? {
        switch category {
        case .jungle: return GearInfo.jungleProgressText(shop.jungleProgress)
        case .roam: return GearInfo.roamProgressText(shop.roamGold)
        default: return nil
        }
    }

    /// カードの費用（靴があれば 0、無ければ「スピードブーツ込み 250」）。
    static func blessingCostText(_ card: HUDBlessingCard, master: MasterData) -> String {
        guard card.cost > 0 else { return "0" }
        let boots = master.item(Balance.Gear.baseBootsID).map { MasterText.item($0) } ?? ""
        return L("\(boots)込み \(card.cost)", "With \(boots) \(card.cost)")
    }

    /// 詳細のボタンの文字（付いていなければ「付与」、別の祝福が付いていれば「付け替え」）。
    static func blessingActionTitle(_ card: HUDBlessingCard, current: GearOption?) -> String {
        if card.isCurrent { return L("付与済み", "Attached") }
        return current == nil ? L("付与", "Attach") : L("付け替え", "Swap")
    }

    /// カテゴリのタブの装備（別のタブにも並ぶ装備を含む。ID 順）。ジャングル・ロームは祝福のタブなので空。
    static func items(in category: ItemCategory, master: MasterData) -> [ItemDef] {
        master.items.filter { $0.isListed(in: category) }
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
