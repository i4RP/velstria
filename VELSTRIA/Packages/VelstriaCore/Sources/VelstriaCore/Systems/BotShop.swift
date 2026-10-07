import Foundation

// 担当: core-bots
// ボットの買い物（DESIGN §10: ロール別推奨ビルドを順に、帰還時・死亡時にまとめ買い）。
// ItemSystem.nextRecommendedPurchase を手元の HeroData に仮適用しながら繰り返し、
// 買えなくなるまでの .buyItem を 1 回の意思決定でまとめて発行する（CommandSystem が順に処理する）。

enum BotShop {
    /// 1 回にまとめて買う最大個数（素材 → 完成品の連鎖を含む）。
    static let maxPurchasesPerVisit = 8

    static func shop(_ s: SimState, _ ctx: SimContext, _ a: inout BotAgent, _ mem: inout BotHeroMemory) {
        guard let hero = s.units[a.i].hero else { return }
        // Gold が前回の試行から増えていなければ見積もりを省く
        if mem.lastShopGold >= 0, hero.gold < mem.lastShopGold + 25 { return }
        let items = plannedPurchases(hero, ctx: ctx)
        for id in items { a.emit(.buyItem(itemID: id)) }
        mem.lastShopGold = items.isEmpty ? hero.gold : -1
    }

    /// 今の所持 Gold で順に買える推奨装備の列（購入後の所持品で次を見積もる）。
    static func plannedPurchases(_ hero: HeroData, ctx: SimContext) -> [String] {
        var h = hero
        var out: [String] = []
        for _ in 0..<maxPurchasesPerVisit {
            guard let next = ItemSystem.nextRecommendedPurchase(h, ctx: ctx) else { break }
            let q = ItemSystem.quote(h, itemID: next, ctx: ctx)
            guard q.canBuy else { break }
            apply(q, to: &h, ctx: ctx)
            out.append(next)
        }
        return out
    }

    /// 購入見積もりを HeroData に仮適用する（ItemSystem.buy と同じ手順: 素材を消費して末尾に追加）。
    static func apply(_ q: PurchaseQuote, to h: inout HeroData, ctx: SimContext) {
        ItemSystem.normalizeInvested(&h, master: ctx.master)
        var invested = q.cost
        for k in q.consumedSlots.reversed() where k < h.items.count {
            invested += h.itemInvested[k]
            h.items.remove(at: k)
            h.itemInvested.remove(at: k)
        }
        h.gold -= q.cost
        h.items.append(q.itemID)
        h.itemInvested.append(invested)
    }

    /// 次の完成品までに必要な Gold（帰還判断用）。何も買えないビルド完了後は .infinity。
    static func goldForNextItem(_ hero: HeroData, ctx: SimContext) -> Double {
        let build = ItemSystem.recommendedBuild(for: hero, master: ctx.master)
        var pool = hero.items
        for target in build {
            if let k = pool.firstIndex(of: target) {
                pool.remove(at: k)
                continue
            }
            let q = ItemSystem.quote(hero, itemID: target, ctx: ctx)
            switch q.failure {
            case .unknownItem?, .requiresSmite?, .blockedBySmite?, .uniqueCategory?:
                continue
            default:
                return q.cost
            }
        }
        return .infinity
    }
}
