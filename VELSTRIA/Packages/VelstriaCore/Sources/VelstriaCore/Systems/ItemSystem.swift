import Foundation

// 担当: core-economy（最小実装。合成・制限・売却・装備パッシブ・ルーン・推奨ビルドを実装すること）

public enum ItemSystem {
    /// 購入（DESIGN §8）。失敗時は .purchaseFailed を発行。
    public static func buy(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, itemID: String) {
        guard var h = s.units[i].hero, let item = ctx.master.item(itemID) else { return }
        let cost = item.priceGold
        guard h.items.count < Balance.itemSlots else {
            s.emit(.purchaseFailed(heroID: s.units[i].id, itemID: itemID, reason: "slots_full"))
            return
        }
        guard h.gold >= cost else {
            s.emit(.purchaseFailed(heroID: s.units[i].id, itemID: itemID, reason: "not_enough_gold"))
            return
        }
        h.gold -= cost
        h.items.append(itemID)
        h.itemInvested.append(cost)
        s.units[i].hero = h
        s.emit(.itemPurchased(heroID: s.units[i].id, itemID: itemID))
    }

    public static func sell(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, slotIndex: Int) {
        guard var h = s.units[i].hero, slotIndex >= 0, slotIndex < h.items.count else { return }
        let itemID = h.items.remove(at: slotIndex)
        let invested = h.itemInvested.remove(at: slotIndex)
        let refund = (invested * Balance.sellRatio).rounded()
        h.gold += refund
        s.units[i].hero = h
        s.emit(.itemSold(heroID: s.units[i].id, itemID: itemID, refund: refund))
    }

    /// 現在の所持で itemID を買う場合の実コスト（合成割引込み）。
    public static func effectiveCost(_ hero: HeroData, itemID: String, ctx: SimContext) -> Double {
        ctx.master.item(itemID)?.priceGold ?? .infinity
    }

    /// ロール別の推奨ビルド（購入順の item ID）。AI と HUD の「おすすめ購入」が使う。
    public static func recommendedBuild(role: Role, master: MasterData) -> [String] {
        []
    }

    /// 推奨ビルドに沿って「次に買うべき装備」（所持 Gold で買えるもの。無ければ nil）。HUD のおすすめ購入・AI が使う。
    /// customBuild が与えられればそれを優先する。
    public static func nextRecommendedPurchase(_ hero: HeroData, ctx: SimContext, customBuild: [String]? = nil) -> String? {
        nil
    }
}

/// 装備・ルーンの能力値反映。
public enum ItemStats {
    public static func apply(items: [String], runes: [String], to stats: inout Stats, ctx: SimContext) {
        for id in items {
            guard let it = ctx.master.item(id) else { continue }
            stats.attack += it.attack
            stats.abilityPower += it.abilityPower
            stats.maxHP += it.hp
            stats.armor += it.armor
            stats.magicResist += it.magicResist
            stats.moveSpeed += it.moveSpeed
            stats.cooldownReduction += it.cooldownReductionPct / 100
        }
    }
}
