import Foundation

// 担当: core-economy
// 装備の購入（多段の合成）・売却・推奨ビルド、装備・ルーンの能力値反映（DESIGN §8）。
// 装備は Mobile Legends の図鑑をそのまま写したもの（tools/equipment_spec.mjs）。

/// 購入できない理由（.purchaseFailed の reason 文字列 = rawValue）。
public enum PurchaseFailure: String, Codable, Hashable, Sendable {
    case slotsFull = "slots_full"
    case notEnoughGold = "not_enough_gold"
    /// 靴は 1 足まで。
    case uniqueCategory = "unique_category"
    /// ジャングルの祝福は狩猟印が必要。
    case requiresSmite = "requires_smite"
    /// ロームの祝福は狩猟印を持つヒーローには付けられない。
    case blockedBySmite = "blocked_by_smite"
    /// ロームの祝福は 2:00 を過ぎると新たには付けられない。
    case roamClosed = "roam_closed"
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
    /// 購入（DESIGN §8）。失敗時は .purchaseFailed を発行。消耗品（ポーション）は所持枠を使わず、その場で効果が付く。
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
        h.gold -= q.cost
        if infinite { h.gold = Balance.Economy.practiceGold }
        if let item = ctx.master.item(itemID), item.isConsumable {
            // ポーションの効果は 1 つだけ（買い直すと置き換わる）
            h.itemRuntime.potionID = itemID
            h.itemRuntime.potionUntil = s.time + item.consumableSec
        } else {
            // 素材を消費（添字が大きい方から除去）し、投資額を引き継ぐ
            var invested = q.cost
            for k in q.consumedSlots.reversed() {
                invested += h.itemInvested[k]
                h.items.remove(at: k)
                h.itemInvested.remove(at: k)
            }
            h.items.append(itemID)
            h.itemInvested.append(invested)
            GearSystem.didChangeItems(&h, master: ctx.master, time: s.time)
        }
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
        GearSystem.didChangeItems(&h, master: ctx.master, time: s.time)
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

    /// 購入の可否と実コストを見積もる。判定順: 不明 → 靴は 1 足 → 枠 → Gold。
    public static func quote(_ hero: HeroData, itemID: String, ctx: SimContext) -> PurchaseQuote {
        guard let item = ctx.master.item(itemID) else {
            return PurchaseQuote(itemID: itemID, cost: .infinity, consumedSlots: [], failure: .unknownItem)
        }
        let gold = EconomyRewards.hasInfiniteGold(ctx) ? Balance.Economy.practiceGold : hero.gold
        if item.isConsumable {
            let cost = item.priceGold
            return PurchaseQuote(itemID: itemID, cost: cost, consumedSlots: [], failure: gold < cost ? .notEnoughGold : nil)
        }
        let (cost, consumed) = combine(hero, item: item, master: ctx.master)
        var q = PurchaseQuote(itemID: itemID, cost: cost, consumedSlots: consumed, failure: nil)
        if isBoots(item) {
            // 合成で消費される素材を除いた所持品に靴があれば不可
            let conflict = hero.items.indices.contains { k in
                guard !consumed.contains(k), let owned = ctx.master.item(hero.items[k]) else { return false }
                return isBoots(owned)
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

    /// 1 個までに制限されるカテゴリ（靴 = Movement）。
    public static func isUniqueCategory(_ c: ItemCategory) -> Bool {
        c == .movement
    }

    /// 靴（移動カテゴリ）。靴は 1 足まで。
    public static func isBoots(_ it: ItemDef) -> Bool {
        it.isBoots
    }

    /// 合成コストと消費する素材の添字。素材を持っていなければ、その素材の素材を持っているかを下へたどる（多段の合成）。
    /// cost = max(price × minCombineCostRatio, price − Σ 消費する所持品の price)。build_from の重複は所持数分だけ照合する。
    static func combine(_ hero: HeroData, item: ItemDef, master: MasterData) -> (cost: Double, consumed: [Int]) {
        var consumed: [Int] = []
        var componentValue: Double = 0
        func take(_ comp: String, depth: Int) {
            if let k = hero.items.indices.first(where: { hero.items[$0] == comp && !consumed.contains($0) }) {
                consumed.append(k)
                componentValue += master.item(comp)?.priceGold ?? 0
                return
            }
            guard depth < 4, let c = master.item(comp) else { return }
            for sub in c.buildFrom { take(sub, depth: depth + 1) }
        }
        for comp in item.buildFrom { take(comp, depth: 1) }
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

    /// ロール別の推奨ビルド（購入順、靴を含む 6 個。Mobile Legends の定番構成）。
    static let roleBuilds: [Role: [String]] = [
        // 射手: スイフトブーツ → マジックガン → ウィンドテラー → バーサーク → ディスペアブレイド → ナチュラルウィンド
        .ranger: ["EQ403", "EQ101", "EQ108", "EQ110", "EQ106", "EQ117"],
        // メイジ: アーケインブーツ → ボルトロッド → ジーニアスワンド → ヒートロッド → ガーディアンレリック → 魔法の聖剣
        .arcanist: ["EQ404", "EQ204", "EQ203", "EQ207", "EQ210", "EQ211"],
        // タンク: タフブーツ → ドミナントシールド → カースヘルム → ヴァルキュリアブレス → 上古の鎧 → イモータル
        .vanguard: ["EQ406", "EQ305", "EQ310", "EQ306", "EQ308", "EQ304"],
        // ファイター: ウォリアーブーツ → 常勝の神斧 → ハンターストライク → ブレストプレート → ヴァルキュリアブレス → イモータル
        .duelist: ["EQ407", "EQ116", "EQ105", "EQ303", "EQ306", "EQ304"],
        // アサシン: タフブーツ → ハンターストライク → オーシャンエッジ → スピリットシャウト → ディスペアブレイド → イモータル
        .assassin: ["EQ406", "EQ105", "EQ107", "EQ112", "EQ106", "EQ304"],
        // サポート: マジックブーツ → オアシスのフラスコ → ドミナントシールド → オラクル → ヴァルキュリアブレス → イモータル
        .support: ["EQ405", "EQ202", "EQ305", "EQ307", "EQ306", "EQ304"],
    ]

    /// ヒーロー固有の推奨ビルド（MLBB の元ヒーローの定番構成）。無いヒーローはロール別。
    static let heroBuilds: [String: [String]] = [
        // ルミナ（ミヤ）: スイフトブーツ → ラスティサイズ → デモンハント → 如意棒 → ナチュラルウィンド → スピリットシャウト
        "H025": ["EQ403", "EQ119", "EQ120", "EQ118", "EQ117", "EQ112"],
        // エウリア（エウドラ）: アーケインブーツ → ボルトロッド → ジーニアスワンド → ガーディアンレリック → 魔法の聖剣 → ウィンタークラウン
        "H026": ["EQ404", "EQ204", "EQ203", "EQ210", "EQ211", "EQ113"],
        // ジャルド（趙子龍）: スイフトブーツ → ラスティサイズ → ブラッドクロウ → バーサーク → ディスペアブレイド → ナチュラルウィンド
        "H027": ["EQ403", "EQ119", "EQ111", "EQ110", "EQ106", "EQ117"],
        // ザイル（セイバー）: 狩猟印のジャングラー。タフブーツ（ジャングルの祝福）→ ハンターストライク → オーシャンエッジ → スピリットシャウト → ディスペアブレイド → イモータル
        "H028": ["EQ406", "EQ105", "EQ107", "EQ112", "EQ106", "EQ304"],
        // ボルグ（ティグリアル）: タフブーツ（ロームの祝福）→ ドミナントシールド → ヴァルキュリアブレス → 上古の鎧 → イモータル → 聖光の鎧
        "H029": ["EQ406", "EQ305", "EQ306", "EQ308", "EQ304", "EQ301"],
        // ライナ（ライラ）: スイフトブーツ → マジックガン → ウィンドテラー → バーサーク → ディスペアブレイド → ナチュラルウィンド
        "H030": ["EQ403", "EQ101", "EQ108", "EQ110", "EQ106", "EQ117"],
        // オーリア（オーロラ）: アーケインブーツ → タリスマン → ボルトロッド → ガーディアンレリック → 魔法の聖剣 → ブラッドウィング
        "H031": ["EQ404", "EQ214", "EQ204", "EQ210", "EQ211", "EQ205"],
        // ディアス（ディロス）: ウォリアーブーツ → 常勝の神斧 → ハンターストライク → スピリットシャウト → ディスペアブレイド → イモータル
        "H032": ["EQ407", "EQ116", "EQ105", "EQ112", "EQ106", "EQ304"],
        // ヴァルド（アルカード）: 狩猟印のジャングラー。ウォリアーブーツ（ジャングルの祝福）→ 常勝の神斧 → ブラッドクロウ → ラスティサイズ → ディスペアブレイド → イモータル
        "H033": ["EQ407", "EQ116", "EQ111", "EQ119", "EQ106", "EQ304"],
        // ゴルム（フランコ）: タフブーツ（ロームの祝福）→ ドミナントシールド → ヴァルキュリアブレス → 上古の鎧 → イモータル → カースヘルム
        "H034": ["EQ406", "EQ305", "EQ306", "EQ308", "EQ304", "EQ310"],
    ]

    /// ロール別の推奨ビルド（購入順の item ID。マスターに無い ID は除く）。
    public static func recommendedBuild(role: Role, master: MasterData) -> [String] {
        (roleBuilds[role] ?? []).filter { master.item($0) != nil }
    }

    /// ヒーロー別（無ければロール別）の推奨ビルド。heroID のロールと role が食い違う時（テストの差し替えなど）はロール別。
    public static func recommendedBuild(heroID: String, role: Role, master: MasterData) -> [String] {
        if let build = heroBuilds[heroID], master.hero(heroID)?.role == role {
            return build.filter { master.item($0) != nil }
        }
        return recommendedBuild(role: role, master: master)
    }

    /// ヒーローの推奨ビルド（AI と HUD の「おすすめ購入」）。祝福は靴に付くので、ジャングル・ロームでも装備の並びは変わらない。
    public static func recommendedBuild(for hero: HeroData, master: MasterData) -> [String] {
        recommendedBuild(heroID: hero.heroID, role: hero.role, master: master)
    }

    /// カテゴリ内の完成品候補を評価順に並べる（上位 Tier → 評価値 → ID 昇順。消耗品は除く）。
    public static func rankedItems(category: ItemCategory, master: MasterData) -> [ItemDef] {
        EconomyItemTable.table(for: master).rankedItems(category)
    }

    /// 推奨ビルド用の評価値（能力値の重み付き合計 + 固有効果の分）。
    static func itemValue(_ it: ItemDef) -> Double {
        EconomyItemTable.value(it)
    }

    /// 推奨ビルドに沿って「次に買うべき装備」（所持 Gold で買えるもの。無ければ nil）。HUD のおすすめ購入・AI が使う。
    /// customBuild が与えられればそれを優先する。
    /// 完成品が買えない時は、その素材（さらにその素材）のうち買えるものを返す（素材優先、build_from の順）。
    public static func nextRecommendedPurchase(_ hero: HeroData, ctx: SimContext, customBuild: [String]? = nil) -> String? {
        let build = customBuild.map { $0.filter { ctx.master.item($0).map { !$0.isConsumable } == true } }
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
            case .unknownItem?, .requiresSmite?, .blockedBySmite?, .uniqueCategory?:
                // 構造的に買えない（ビルド指定の問題）ので次の候補へ
                continue
            default:
                break
            }
            // 未所持の素材のうち買えるもの（build_from の順に、持っていない素材の中へ下りる）
            var owned = pool
            func firstBuyable(_ id: String, depth: Int) -> String? {
                guard depth < 4, let item = ctx.master.item(id) else { return nil }
                for comp in item.buildFrom {
                    if let k = owned.firstIndex(of: comp) {
                        owned.remove(at: k)
                        continue
                    }
                    if quote(hero, itemID: comp, ctx: ctx).canBuy { return comp }
                    if let deeper = firstBuyable(comp, depth: depth + 1) { return deeper }
                }
                return nil
            }
            if let comp = firstBuyable(target, depth: 0) { return comp }
            // 枠不足なら後続の完成品（素材を消費して枠が空くもの）を試す。Gold 不足なら貯める。
            if q.failure == .slotsFull { continue }
            return nil
        }
        return nil
    }
}

/// 装備・ルーンの能力値反映。
public enum ItemStats {
    /// 装備の固定値 → 固有の能力値（重ならない）→ 適応攻撃 → ルーン（割合）の順で加算する。
    /// hero を渡すと、MP（Mana のヒーローだけ）・適応攻撃の振り分け・ポーション・レベルで変わる固有効果も反映する。
    public static func apply(items: [String], runes: [String], to stats: inout Stats, ctx: SimContext,
                             hero: HeroData? = nil, time: Double = 0) {
        apply(items: items, runes: runes, to: &stats, master: ctx.master, hero: hero, time: time)
    }

    public static func apply(items: [String], runes: [String], to stats: inout Stats, master: MasterData,
                             hero: HeroData? = nil, time: Double = 0) {
        // 毎 tick 全ヒーローで呼ばれるため、% 値は事前計算表から引く
        let table = EconomyItemTable.table(for: master)
        let base = stats
        var resourceRegenPct: Double = 0
        var hpRegenPct: Double = 0

        // 効果中のポーションは所持品と同じように能力値を足す
        var all = items
        if let rt = hero?.itemRuntime, let potion = rt.potionID, time < rt.potionUntil { all.append(potion) }

        // 能力値（装備ごとに定義。同じ装備を複数持てばその分加算）。
        // 割合の貫通・減速軽減は同名の固有効果なので重ならず、最大値だけを採る。
        var attackSpeedPct: Double = 0, armorPenPct: Double = 0, magicPenPct: Double = 0
        var abilityPowerPct: Double = 0, moveSpeedItemPct: Double = 0
        var itemAttack: Double = 0, itemPower: Double = 0, adaptive: Double = 0
        var mana: Double = 0, slowReduction: Double = 0, critChancePct: Double = 0
        var unique: [String: Double] = [:]
        var seen: [String] = []
        for id in all {
            guard let it = master.item(id) else { continue }
            itemAttack += it.attack
            itemPower += it.abilityPower
            adaptive += it.adaptiveAttack
            stats.maxHP += it.hp
            mana += it.mana
            stats.armor += it.armor
            stats.magicResist += it.magicResist
            stats.moveSpeed += it.moveSpeed
            stats.cooldownReduction += it.cooldownReductionPct / 100
            attackSpeedPct += it.attackSpeedPct / 100
            critChancePct += it.critChancePct
            stats.critMultiplier += it.critDamagePct / 100
            stats.lifesteal += it.lifestealPct / 100
            stats.spellVamp += it.spellVampPct / 100
            stats.armorPenFlat += it.armorPenFlat
            stats.magicPenFlat += it.magicPenFlat
            armorPenPct = max(armorPenPct, it.armorPenPct / 100)
            magicPenPct = max(magicPenPct, it.magicPenPct / 100)
            stats.hpRegen += it.hpRegen
            stats.resourceRegen += it.resourceRegen
            abilityPowerPct = max(abilityPowerPct, it.abilityPowerPct / 100)
            moveSpeedItemPct += it.moveSpeedPct / 100
            stats.outOfCombatMoveSpeedBonus += it.outOfCombatMovePct / 100
            stats.healShieldPower += it.healShieldPowerPct / 100
            stats.monsterDamageBonus += it.monsterDamagePct / 100
            stats.ccReduction += it.ccReductionPct / 100
            slowReduction = max(slowReduction, it.slowReductionPct / 100)
            stats.healingReceivedMultiplier += it.healReceivedPct / 100
            stats.critDamageReduction += it.critDamageReductionPct / 100
            stats.damageReduction += it.damageReductionPct / 100
            // 固有の能力値: 同じ装備は 1 回、同じ能力値は最大値
            if !it.uniqueStats.isEmpty, !seen.contains(id) {
                seen.append(id)
                for (k, v) in it.uniqueStats { unique[k] = max(unique[k] ?? 0, v) }
            }
        }
        for (k, v) in unique.sorted(by: { $0.key < $1.key }) {
            switch k {
            case "armor_pen_flat": stats.armorPenFlat += v
            case "magic_pen_flat": stats.magicPenFlat += v
            case "armor_pen_pct": armorPenPct = max(armorPenPct, v / 100)
            case "magic_pen_pct": magicPenPct = max(magicPenPct, v / 100)
            case "crit_damage_pct": stats.critMultiplier += v / 100
            case "lifesteal_pct": stats.lifesteal += v / 100
            case "spell_vamp_pct": stats.spellVamp += v / 100
            case "heal_shield_power_pct": stats.healShieldPower += v / 100
            case "crit_damage_reduction_pct": stats.critDamageReduction += v / 100
            case "move_speed": stats.moveSpeed += v
            case "attack_speed_pct": attackSpeedPct += v / 100
            case "crit_chance_pct": critChancePct += v
            case "hp": stats.maxHP += v
            case "cooldown_reduction_pct": stats.cooldownReduction += v / 100
            default: break
            }
        }
        // 適応攻撃: 装備で増えた攻撃力と魔力の多い方。同じなら（どちらも 0 を含む）ヒーローのスキルのダメージの種類
        if adaptive > 0 {
            let magic: Bool
            if itemPower != itemAttack {
                magic = itemPower > itemAttack
            } else {
                magic = hero.map { master.skills(forHero: $0.heroID).first?.damageType == .magic } ?? false
            }
            if magic { itemPower += adaptive } else { itemAttack += adaptive }
        }
        stats.attack += itemAttack
        stats.abilityPower += itemPower
        if hero?.resourceKind == .mana { stats.maxResource += mana }
        stats.armorPenPct = armorPenPct
        stats.magicPenPct = magicPenPct
        stats.slowReduction = slowReduction
        stats.critChance += critChancePct / 100
        stats.attackSpeed *= 1 + attackSpeedPct
        stats.abilityPower *= 1 + abilityPowerPct
        stats.critChance = min(1, stats.critChance)

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
        stats.moveSpeed *= 1 + moveSpeedPct + moveSpeedItemPct
        stats.hpRegen *= 1 + hpRegenPct
        stats.resourceRegen *= 1 + resourceRegenPct
        // 能力値で決まる固有効果（射程・魔力の割合・クリティカルの換算・混合防御など）。ルーンの後の値で計算する
        ItemEffects.applyStatEffects(items: all, hero: hero, to: &stats, base: base, master: master)
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
