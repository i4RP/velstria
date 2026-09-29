import Foundation
import VelstriaCore

// 担当: app-services
// 試合報酬（DESIGN §12）:
// - 対象: 通常戦・ランク戦のみ。リプレイ再生・観戦・練習場・チュートリアル・途中離脱は報酬なし・記録なし。
// - Coin: 勝利 220 / 敗北 110 × 時間係数 min(1, 分/12)（下限 0.3）。週末スターブースト中は +50%（coins に含める）。
// - 初勝利ボーナス: その日（端末ローカル日付）の最初の勝利に +300（日付キーが前回より進んだ時のみ）。
// - アカウント XP: 勝利 120 / 敗北 80。次のレベルまで 400 + 100×Lv、最大 Lv 60（最大到達後の XP は 0 に固定）。
// - ランク戦は RankService.apply。パス XP: 勝利 150 / 敗北 100。
// - ミッション進捗・通算成績（ヒーロー別・MVP・連勝・ペンタキル）・戦績（最新 50 件）・リプレイ保存（最新 20 件）・実績評価。
// - 反映後は即時保存する（デバウンス待ちの間にアプリが終了しても報酬・リプレイの紐付けを失わないように）。

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

    /// 勝利したか（引き分け・時間切れは false）。
    var won = false
    /// coins のうち週末スターブーストによる増加分（内訳表示用。coins に含まれる）。
    var eventBonusCoins = 0
    /// Coin の時間係数（0.3〜1.0）。
    var durationFactor = 1.0
    var accountXPBefore = 0
    var accountXPAfter = 0
    var passLevelBefore = 0
    var passLevelAfter = 0
    /// 追加した戦績（MatchRecord.id）。
    var matchRecordID: UUID?
    /// 保存したリプレイ（ReplayMeta.id）。
    var replayID: UUID?

    /// 獲得 Coin の合計。
    var totalCoins: Int { coins + firstWinBonus }
    var leveledUp: Bool { accountLevelAfter > accountLevelBefore }
}

enum RewardService {
    static let winCoins = 220
    static let lossCoins = 110
    static let firstWinBonusCoins = 300
    static let winAccountXP = 120
    static let lossAccountXP = 80
    static let winPassXP = 150
    static let lossPassXP = 100
    /// 時間係数が 1.0 になる試合時間（分）。
    static let fullRewardMinutes = 12.0
    static let minDurationFactor = 0.3
    static let maxAccountLevel = 60
    static let maxMatchHistory = 50

    /// レベル level → level+1 に必要な XP。
    static func xpToNext(level: Int) -> Int { 400 + 100 * level }

    /// Coin の時間係数 min(1, 分/12)（下限 0.3）。
    static func durationFactor(seconds: Double) -> Double {
        guard seconds.isFinite, seconds > 0 else { return minDurationFactor }
        return max(minDurationFactor, min(1, seconds / 60 / fullRewardMinutes))
    }

    /// 報酬対象の試合か。
    static func isRewardEligible(_ outcome: BattleOutcome) -> Bool {
        let mode = outcome.launch.config.mode
        guard outcome.launch.replay == nil, !outcome.launch.isSpectating, !outcome.abandoned else { return false }
        guard mode == .standard || mode == .ranked else { return false }
        return outcome.summary.humanPlayer != nil
    }

    /// アカウント XP を加算してレベルアップを処理する。
    static func addAccountXP(_ amount: Int, to profile: inout Profile) {
        guard amount > 0 else { return }
        guard profile.accountLevel < maxAccountLevel else {
            profile.accountXP = 0
            return
        }
        profile.accountXP += amount
        while profile.accountLevel < maxAccountLevel && profile.accountXP >= xpToNext(level: profile.accountLevel) {
            profile.accountXP -= xpToNext(level: profile.accountLevel)
            profile.accountLevel += 1
        }
        if profile.accountLevel >= maxAccountLevel { profile.accountXP = 0 }
    }

    static func apply(outcome: BattleOutcome, to profile: inout Profile, master: MasterData,
                      persistence: PersistenceService, now: Date) -> RewardReport {
        var report = RewardReport()
        report.accountLevelBefore = profile.accountLevel
        report.accountLevelAfter = profile.accountLevel
        report.accountXPBefore = profile.accountXP
        report.accountXPAfter = profile.accountXP
        report.passLevelBefore = LiveOpsService.passLevel(xp: profile.pass.xp)
        report.passLevelAfter = report.passLevelBefore
        guard isRewardEligible(outcome), let human = outcome.summary.humanPlayer else {
            report.noRewards = true
            return report
        }
        let summary = outcome.summary
        let launch = outcome.launch
        let won = summary.humanWon == true
        report.won = won

        // Coin
        report.durationFactor = durationFactor(seconds: summary.duration)
        let baseCoins = Int((Double(won ? winCoins : lossCoins) * report.durationFactor).rounded())
        if LiveOpsService.isWeekendBoostActive(now: now) {
            report.eventBonusCoins = Int((Double(baseCoins) * LiveOpsService.weekendCoinBonusRate).rounded())
        }
        report.coins = baseCoins + report.eventBonusCoins
        let today = LiveOpsService.dayKey(now)
        // 日付キーが進んだ時だけ付与する（端末時刻を前後させての再取得を防ぐ。ログインボーナスと同じ基準）
        if won && today > profile.lastFirstWinDayKey {
            report.firstWinBonus = firstWinBonusCoins
            profile.lastFirstWinDayKey = today
        }
        profile.starlightCoin += report.totalCoins

        // アカウント XP
        report.accountXP = won ? winAccountXP : lossAccountXP
        addAccountXP(report.accountXP, to: &profile)
        report.accountLevelAfter = profile.accountLevel
        report.accountXPAfter = profile.accountXP

        // ランク（countsForRank が立っているか、モードがランク戦なら反映）
        if launch.countsForRank || launch.config.mode == .ranked {
            report.rankBefore = profile.rank
            RankService.apply(won: won, to: &profile.rank)
            report.rankAfter = profile.rank
        }

        // スターパス
        report.passXP = won ? winPassXP : lossPassXP
        LiveOpsService.addPassXP(report.passXP, to: &profile)
        report.passLevelAfter = LiveOpsService.passLevel(xp: profile.pass.xp)

        // 通算成績
        updateCareer(&profile.career, human: human, won: won)

        // リプレイ（戦績より先に保存して ID を結ぶ）
        if let replay = outcome.replay,
           let meta = persistence.storeReplay(replay, heroID: human.heroID, won: summary.humanWon, date: now, in: &profile) {
            report.replaySaved = true
            report.replayID = meta.id
        }

        // 戦績（新しい順・最新 50 件）
        let record = MatchRecord(
            date: now, mode: launch.config.mode, difficulty: enemyDifficulty(launch.config, humanTeam: human.team),
            won: summary.humanWon, duration: summary.duration, heroID: human.heroID,
            kills: human.score.kills, deaths: human.score.deaths, assists: human.score.assists,
            creepScore: human.score.creepScore, gold: human.score.goldEarned,
            damageToHeroes: human.score.damageToHeroes, grade: human.grade, isMVP: human.isMVP,
            items: human.items, replayID: report.replayID, summary: summary)
        profile.matchHistory.insert(record, at: 0)
        if profile.matchHistory.count > maxMatchHistory {
            profile.matchHistory.removeLast(profile.matchHistory.count - maxMatchHistory)
        }
        report.matchRecordID = record.id

        // ミッション
        let teamIndex = human.team.rawValue
        let towers = teamIndex < summary.towersDestroyed.count ? summary.towersDestroyed[teamIndex] : 0
        let input = MatchProgressInput(
            won: won, kills: human.score.kills, deaths: human.score.deaths, assists: human.score.assists,
            creepScore: human.score.creepScore, towersDestroyed: towers, damageToHeroes: human.score.damageToHeroes,
            role: master.hero(human.heroID)?.role, heroID: human.heroID)
        report.missionsProgressed = LiveOpsService.recordMatch(input, profile: &profile, now: now)

        // 実績（成績・ランク・所持の更新後に評価）
        report.achievementsUnlocked = LiveOpsService.evaluateAchievements(profile: &profile, master: master, now: now)

        persistence.saveNow(profile)
        return report
    }

    /// 通算成績とヒーロー別成績を更新する。
    static func updateCareer(_ c: inout CareerStats, human: PlayerSummary, won: Bool) {
        let s = human.score
        c.matches += 1
        if won {
            c.wins += 1
            c.currentWinStreak += 1
            c.longestWinStreak = max(c.longestWinStreak, c.currentWinStreak)
        } else {
            c.currentWinStreak = 0
        }
        c.kills += s.kills
        c.deaths += s.deaths
        c.assists += s.assists
        if human.isMVP { c.mvps += 1 }
        if s.damageToHeroes.isFinite { c.totalDamage += max(0, s.damageToHeroes) }
        if s.goldEarned.isFinite { c.totalGold += max(0, s.goldEarned) }
        if s.largestMultiKill >= 5 { c.pentaKills += 1 }

        var hero = c.perHero[human.heroID] ?? HeroCareer()
        hero.matches += 1
        if won { hero.wins += 1 }
        hero.kills += s.kills
        hero.deaths += s.deaths
        hero.assists += s.assists
        if human.isMVP { hero.mvps += 1 }
        c.perHero[human.heroID] = hero
    }

    /// 敵チーム AI の難易度（戦績表示用）。
    private static func enemyDifficulty(_ config: MatchConfig, humanTeam: Team) -> Difficulty {
        config.players.first { $0.team != humanTeam && $0.controller == .bot }?.botDifficulty
            ?? config.players.first { $0.controller == .bot }?.botDifficulty
            ?? .normal
    }
}
