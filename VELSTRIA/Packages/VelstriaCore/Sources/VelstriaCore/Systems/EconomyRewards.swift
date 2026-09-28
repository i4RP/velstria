import Foundation

// 担当: core-economy
// Gold 付与の共通窓口。獲得 Gold（HeroScore.goldEarned）の集計と .goldGained 発行を一元化する。

public enum EconomyRewards {
    /// 練習場の無限 Gold が有効か。
    public static func hasInfiniteGold(_ ctx: SimContext) -> Bool {
        let practice = ctx.config.mode == .practice || ctx.config.mode == .tutorial
        return practice && ctx.config.practice?.infiniteGold == true
    }

    /// ヒーローに Gold を付与する。
    /// - Parameter visible: true なら .goldGained を発行（ラストヒット・キル等の「見える」獲得）。
    ///   パッシブ収入のような毎 tick の少額は false。
    public static func grantGold(_ s: inout SimState, heroIndex i: Int, amount: Double, at pos: Vec2? = nil,
                                 visible: Bool = true) {
        guard amount > 0, s.units[i].hero != nil else { return }
        s.units[i].hero!.gold += amount
        s.units[i].hero!.score.goldEarned += amount
        if visible {
            s.emit(.goldGained(heroID: s.units[i].id, amount: amount, pos: pos ?? s.units[i].pos))
        }
    }

    /// チームの全ヒーロー（死亡中を含む）に Gold を付与する。
    public static func grantTeamGold(_ s: inout SimState, team: Team, amount: Double) {
        for i in s.heroIndices(team: team) {
            grantGold(&s, heroIndex: i, amount: amount)
        }
    }

    /// チームの獲得 Gold 合計（開始 Gold を含む。降参判定・スコアボード用）。
    public static func teamGoldEarned(_ s: SimState, team: Team) -> Double {
        var total: Double = 0
        for i in s.heroIndices(team: team) {
            total += Balance.startingGold + (s.units[i].hero?.score.goldEarned ?? 0)
        }
        return total
    }
}
