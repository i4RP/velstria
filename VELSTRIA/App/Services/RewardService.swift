import Foundation
import VelstriaCore

// 担当: app-services（最小実装。DESIGN §12 の報酬・ランク・ミッション・パス・実績・戦績・リプレイ保存を実装すること）

/// 試合報酬の内訳（リザルト画面に表示）。
struct RewardReport: Equatable {
    var coins = 0
    var firstWinBonus = 0
    var accountXP = 0
    var accountLevelBefore = 1
    var accountLevelAfter = 1
    var rankBefore: RankState?
    var rankAfter: RankState?
    var passXP = 0
    /// 進捗したミッション ID。
    var missionsProgressed: [String] = []
    /// 新たに解除した実績 ID。
    var achievementsUnlocked: [String] = []
    var replaySaved = false
    /// リプレイ・観戦・練習など報酬対象外。
    var noRewards = false
}

enum RewardService {
    static func apply(outcome: BattleOutcome, to profile: inout Profile, master: MasterData,
                      persistence: PersistenceService, now: Date) -> RewardReport {
        var report = RewardReport()
        report.accountLevelBefore = profile.accountLevel
        report.accountLevelAfter = profile.accountLevel
        let mode = outcome.launch.config.mode
        guard outcome.launch.replay == nil, mode == .standard || mode == .ranked else {
            report.noRewards = true
            return report
        }
        let won = outcome.summary.humanWon == true
        report.coins = won ? 220 : 110
        profile.starlightCoin += report.coins
        profile.career.matches += 1
        if won { profile.career.wins += 1 }
        return report
    }
}
