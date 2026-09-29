import Foundation

// 担当: core-economy
// 装備の購入（合成）・売却・推奨ビルド、装備パッシブ・ルーンの能力値反映（DESIGN §8）。

/// 購入できない理由（.purchaseFailed の reason 文字列 = rawValue）。
public enum PurchaseFailure: String, Codable, Hashable, Sendable {
    case slotsFull = "slots_full"
    case notEnoughGold = "not_enough_gold"
    case uniqueCategory = "unique_category"
    case requiresSmite = "requires_smite"
    case unknownItem = "unknown_item"
}

/// 購入見積もり（HUD のショップ表示・AI の判断・実購入で共通）。
public struct PurchaseQuote: Hashable, Sendable {
    public var itemID: String
    /// 実際に支払う Gold（合成割引込み）。不明な装備は .infinity。
    public var cost: Double
    /// 合成で消費される所持品の添字（昇順）。
    public var consumedSlots: [Int]
    /// nil なら購入可能。
    public var failure: PurchaseFailure?

    public init(itemID: String, cost: Double, consumedSlots: [Int], failure: PurchaseFailure?) {
        self.itemID = itemID
        self.cost = cost
        self.consumedSlots = consumedSlots
        self.failure = failure
    }

    public var canBuy: Bool { failure == nil }
}

public enum ItemSystem {
    /// 購入（DESIGN §8）。失敗時は .purchaseFailed を発行。
    public static func buy(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, itemID: String) {
        guard var h = s.units[i].hero else { return }
        normalizeInvested(&h, master: ctx.master)
        let infinite = EconomyRewards.hasInfiniteGold(ctx)
        if infinite { h.gold = Balance.Economy.practiceGold }
        let q = quote(h, itemID: itemID, ctx: ctx)
        if let f = q.failure {
            s.units[i].hero = h
            s.emit(.purchaseFailed(heroID: s.units[i].id, itemID: itemID, reason: f.rawValue))
            return
        }
        // 素材を消費（添字が大きい方から除去）し、投資額を引き継ぐ
        var invested = q.cost
        for k in q.consumedSlots.reversed() {
            invested += h.itemInvested[k]
            h.items.remove(at: k)
            h.itemInvested.remove(at: k)
        }
        h.gold -= q.cost
        if infinite { h.gold = Balance.Economy.practiceGold }
        h.items.append(itemID)
        h.itemInvested.append(invested)
        s.units[i].hero = h
        StatCalculator.recompute(&s, i, ctx)
        s.emit(.itemPurchased(heroID: s.units[i].id, itemID: itemID))
    }

    /// 売却: 投資額の 60%（Balance.sellRatio）を返金。
    public static func sell(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, slotIndex: Int) {
        guard var h = s.units[i].hero, slotIndex >= 0, slotIndex < h.items.count else { return }
        normalizeInvested(&h, master: ctx.master)
        let itemID = h.items.remove(at: slotIndex)
        let invested = h.itemInvested.remove(at: slotIndex)
        let refund = sellValue(invested: invested)
        h.gold += refund
        if EconomyRewards.hasInfiniteGold(ctx) { h.gold = Balance.Economy.practiceGold }
        s.units[i].hero = h
        StatCalculator.recompute(&s, i, ctx)
        s.emit(.itemSold(heroID: s.units[i].id, itemID: itemID, refund: refund))
    }

    /// 投資額に対する売却額。
    public static func sellValue(invested: Double) -> Double {
        (invested * Balance.sellRatio).rounded()
    }

    /// slotIndex の装備を今売った場合の返金額（HUD 表示用）。
    public static func sellValue(_ hero: HeroData, slotIndex: Int, master: MasterData) -> Double {
        guard slotIndex >= 0, slotIndex < hero.items.count else { return 0 }
        if slotIndex < hero.itemInvested.count { return sellValue(invested: hero.itemInvested[slotIndex]) }
        return sellValue(invested: master.item(hero.items[slotIndex])?.priceGold ?? 0)
    }

    /// 現在の所持で itemID を買う場合の実コスト（合成割引込み）。
    public static func effectiveCost(_ hero: HeroData, itemID: String, ctx: SimContext) -> Double {
        guard let item = ctx.master.item(itemID) else { return .infinity }
        return combine(hero, item: item, master: ctx.master).cost
    }

    /// 購入の可否と実コストを見積もる。判定順: 不明 → 狩猟印 → 固有カテゴリ → 枠 → Gold。
    public static func quote(_ hero: HeroData, itemID: String, ctx: SimContext) -> PurchaseQuote {
        guard let item = ctx.master.item(itemID) else {
            return PurchaseQuote(itemID: itemID, cost: .infinity, consumedSlots: [], failure: .unknownItem)
        }
        let (cost, consumed) = combine(hero, item: item, master: ctx.master)
        var q = PurchaseQuote(itemID: itemID, cost: cost, consumedSlots: consumed, failure: nil)
        let gold = EconomyRewards.hasInfiniteGold(ctx) ? Balance.Economy.practiceGold : hero.gold

        if item.category == .jungle && !hero.spells.contains(Balance.Economy.smiteSpellID) {
            q.failure = .requiresSmite
        } else if isUniqueCategory(item.category) {
            // 合成で消費される素材を除いた所持品に同カテゴリがあれば不可
            let conflict = hero.items.indices.contains { k in
                !consumed.contains(k) && ctx.master.item(hero.items[k])?.category == item.category
            }
            if conflict { q.failure = .uniqueCategory }
        }
        if q.failure == nil, hero.items.count - consumed.count + 1 > Balance.itemSlots {
            q.failure = .slotsFull
        }
        if q.failure == nil, gold < cost {
            q.failure = .notEnoughGold
        }
        return q
    }

    /// 1 個までに制限されるカテゴリ（Movement / Jungle）。
    public static func isUniqueCategory(_ c: ItemCategory) -> Bool {
        c == .movement || c == .jungle
    }

    /// 合成コストと消費する素材の添字。
    /// cost = max(price × minCombineCostRatio, price − Σ 所持素材の price)。build_from の重複は所持数分だけ照合する。
    static func combine(_ hero: HeroData, item: ItemDef, master: MasterData) -> (cost: Double, consumed: [Int]) {
        var consumed: [Int] = []
        var componentValue: Double = 0
        for comp in item.buildFrom {
            if let k = hero.items.indices.first(where: { hero.items[$0] == comp && !consumed.contains($0) }) {
                consumed.append(k)
                componentValue += master.item(comp)?.priceGold ?? 0
            }
        }
        consumed.sort()
        let floor = (item.priceGold * Balance.minCombineCostRatio).rounded()
        return (max(floor, item.priceGold - componentValue), consumed)
    }

    /// itemInvested を items と同じ長さに揃える（外部で items だけ変更された場合は定価を投資額とみなす）。
    static func normalizeInvested(_ h: inout HeroData, master: MasterData) {
        if h.itemInvested.count > h.items.count {
            h.itemInvested.removeLast(h.itemInvested.count - h.items.count)
        }
        while h.itemInvested.count < h.items.count {
            h.itemInvested.append(master.item(h.items[h.itemInvested.count])?.priceGold ?? 0)
        }
    }

    // MARK: - 推奨ビルド

    /// ロール別の購入順カテゴリ（6 枠）。
    public static func buildPlan(role: Role) -> [ItemCategory] {
        switch role {
        case .ranger: return [.attack, .movement, .attack, .attack, .attack, .attack]
        case .arcanist: return [.magic, .movement, .magic, .utility, .magic, .magic]
        case .vanguard: return [.defense, .utility, .defense, .defense, .utility, .defense]
        case .duelist: return [.attack, .defense, .attack, .defense, .attack, .defense]
        case .assassin: return [.jungle, .attack, .attack, .attack, .attack, .attack]
        case .support: return [.utility, .defense, .utility, .defense, .utility, .defense]
        }
    }

    /// ロール別の推奨ビルド（購入順の item ID）。AI と HUD の「おすすめ購入」が使う。
    public static func recommendedBuild(role: Role, master: MasterData) -> [String] {
        build(plan: buildPlan(role: role), master: master)
    }

    /// ヒーローの装備スペルに合わせた推奨ビルド。
    /// 狩猟印なし → Jungle 枠を Movement（既にあれば主力カテゴリ）へ。狩猟印ありのジャングラー → 先頭に Jungle。
    public static func recommendedBuild(for hero: HeroData, master: MasterData) -> [String] {
        var plan = buildPlan(role: hero.role)
        let hasSmite = hero.spells.contains(Balance.Economy.smiteSpellID)
        if !hasSmite, let k = plan.firstIndex(of: .jungle) {
            let primary = plan.first { $0 != .jungle && $0 != .movement } ?? .attack
            plan[k] = plan.contains(.movement) ? primary : .movement
        } else if hasSmite, hero.position == .jungle, !plan.contains(.jungle) {
            plan.insert(.jungle, at: 0)
            // 6 枠に収めるため末尾から 1 つ削る
            plan.removeLast()
        }
        return build(plan: plan, master: master)
    }

    /// カテゴリ列から、各カテゴリの評価順に重複なく装備を割り当てる。
    static func build(plan: [ItemCategory], master: MasterData) -> [String] {
        let table = EconomyItemTable.table(for: master)
        var out: [String] = []
        for cat in plan {
            if let pick = table.rankedItems(cat).first(where: { !out.contains($0.itemID) }) {
                out.append(pick.itemID)
            }
        }
        return out
    }

    /// カテゴリ内の完成品候補を評価順に並べる（上位 Tier → 評価値 → ID 昇順）。
    public static func rankedItems(category: ItemCategory, master: MasterData) -> [ItemDef] {
        EconomyItemTable.table(for: master).rankedItems(category)
    }

    /// 推奨ビルド用の評価値（カテゴリの主要能力 + パッシブ% × 2）。
    static func itemValue(_ it: ItemDef) -> Double {
        EconomyItemTable.value(it, percent: it.passivePercent)
    }

    /// 推奨ビルドに沿って「次に買うべき装備」（所持 Gold で買えるもの。無ければ nil）。HUD のおすすめ購入・AI が使う。
    /// customBuild が与えられればそれを優先する。
    /// 完成品が買えない時は、その素材のうち買えるものを返す（素材優先）。
    public static func nextRecommendedPurchase(_ hero: HeroData, ctx: SimContext, customBuild: [String]? = nil) -> String? {
        let build = customBuild.map { $0.filter { ctx.master.item($0) != nil } }
            ?? recommendedBuild(for: hero, master: ctx.master)
        // 完成品として確保済みの所持品を多重集合で取り除きながら進む
        var pool = hero.items
        for target in build {
            if let k = pool.firstIndex(of: target) {
                pool.remove(at: k)
                continue
            }
            let q = quote(hero, itemID: target, ctx: ctx)
            if q.canBuy { return target }
            switch q.failure {
            case .unknownItem?, .requiresSmite?, .uniqueCategory?:
                // 構造的に買えない（編成・ビルド指定の問題）ので次の候補へ
                continue
            default:
                break
            }
            guard let item = ctx.master.item(target) else { continue }
            // 未所持の素材のうち買えるもの（build_from の順）
            var owned = pool
            for comp in item.buildFrom {
                if let k = owned.firstIndex(of: comp) {
                    owned.remove(at: k)
                    continue
                }
                if quote(hero, itemID: comp, ctx: ctx).canBuy { return comp }
            }
            // 枠不足なら後続の完成品（素材を消費して枠が空くもの）を試す。Gold 不足なら貯める。
            if q.failure == .slotsFull { continue }
            return nil
        }
        return nil
    }
}

/// 装備・ルーンの能力値反映。
public enum ItemStats {
    /// 装備の固定値 → カテゴリ別パッシブ（同一装備は 1 回）→ ルーン（割合）の順で加算する。
    public static func apply(items: [String], runes: [String], to stats: inout Stats, ctx: SimContext) {
        apply(items: items, runes: runes, to: &stats, master: ctx.master)
    }

    public static func apply(items: [String], runes: [String], to stats: inout Stats, master: MasterData) {
        // 毎 tick 全ヒーローで呼ばれるため、% 値は事前計算表から引く
        let table = EconomyItemTable.table(for: master)
        var resourceRegenPct: Double = 0
        var hpRegenPct: Double = 0

        // 固定値（同じ装備を複数持てばその分加算）
        for id in items {
            guard let it = master.item(id) else { continue }
            stats.attack += it.attack
            stats.abilityPower += it.abilityPower
            stats.maxHP += it.hp
            stats.armor += it.armor
            stats.magicResist += it.magicResist
            stats.moveSpeed += it.moveSpeed
            stats.cooldownReduction += it.cooldownReductionPct / 100
        }

        // カテゴリ別パッシブ（X = passive_text の %、同じ装備のパッシブは重複しない）
        var seen: [String] = []
        var hasJungle = false
        for id in items where !seen.contains(id) {
            seen.append(id)
            guard let it = master.item(id) else { continue }
            let x = table.percent(item: it) / 100
            switch it.category {
            case .attack: stats.basicAttackDamageBonus += x
            case .magic: stats.skillDamageBonus += x
            case .defense: stats.damageReduction += x / 2
            case .movement: stats.outOfCombatMoveSpeedBonus += x
            case .utility:
                stats.healShieldPower += x
                resourceRegenPct += x
            case .jungle:
                stats.monsterDamageBonus += 3 * x
                hasJungle = true
            }
        }
        if hasJungle { stats.monsterGoldBonus += Balance.Economy.jungleMonsterGoldBonus }

        // ルーン（X = effect の %）
        var attackPct: Double = 0
        var powerPct: Double = 0
        var hpPct: Double = 0
        var defensePct: Double = 0
        var moveSpeedPct: Double = 0
        for rune in validRunes(runes, master: master) {
            let x = table.percent(rune: rune) / 100
            switch rune.path {
            case .valor:
                attackPct += x
            case .arcana:
                powerPct += x
                stats.skillDamageBonus += x / 2
            case .resolve:
                hpPct += x
                defensePct += x
            case .cunning:
                moveSpeedPct += x / 2
                stats.cooldownReduction += x / 2
            case .harmony:
                hpRegenPct += 3 * x
                resourceRegenPct += 3 * x
                stats.healShieldPower += x
            }
        }
        stats.attack *= 1 + attackPct
        stats.abilityPower *= 1 + powerPct
        stats.maxHP *= 1 + hpPct
        stats.armor *= 1 + defensePct
        stats.magicResist *= 1 + defensePct
        stats.moveSpeed *= 1 + moveSpeedPct
        stats.hpRegen *= 1 + hpRegenPct
        stats.resourceRegen *= 1 + resourceRegenPct
    }

    /// 有効なルーン（マスターに存在する ID のみ、各 Tier 先頭の 1 個、最大 3 個）。
    public static func validRunes(_ runes: [String], master: MasterData) -> [RuneDef] {
        var out: [RuneDef] = []
        for id in runes {
            guard let r = master.rune(id), !out.contains(where: { $0.tier == r.tier }) else { continue }
            out.append(r)
            if out.count == 3 { break }
        }
        return out
    }
}
