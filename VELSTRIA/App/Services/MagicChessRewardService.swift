import Foundation
import VelstriaCore

// 担当: app-services。マジックチェスの報酬（最終順位で算出）。
// RewardService.apply は MOBA 用なので通さず、ここでコイン/アカウントXP/パスXP を直接付与する。

enum MagicChessRewardService {
    static func coins(placement: Int) -> Int { max(40, 220 - (placement - 1) * 24) }
    static func accountXP(placement: Int) -> Int { max(15, 70 - (placement - 1) * 7) }
    static func passXP(placement: Int) -> Int { max(5, 40 - (placement - 1) * 4) }

    /// 最終順位（1 が優勝）で報酬を付与し、記録を更新する。
    static func apply(placement: Int, participants: Int, to profile: inout Profile) {
        profile.starlightCoin += coins(placement: placement)
        RewardService.addAccountXP(accountXP(placement: placement), to: &profile)
        LiveOpsService.addPassXP(passXP(placement: placement), to: &profile)
        profile.magicChessMatches += 1
        if let best = profile.magicChessBestPlacement {
            profile.magicChessBestPlacement = min(best, placement)
        } else {
            profile.magicChessBestPlacement = placement
        }
    }
}
