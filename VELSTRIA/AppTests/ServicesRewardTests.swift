import XCTest
@testable import VELSTRIA
import VelstriaCore

final class ServicesRewardTests: XCTestCase {
    private let master = ServicesFixtures.master

    private func apply(_ outcome: BattleOutcome, _ profile: inout Profile, now: Date = ServicesFixtures.weekday,
                       persistence: PersistenceService? = nil) -> RewardReport {
        RewardService.apply(outcome: outcome, to: &profile, master: master,
                            persistence: persistence ?? ServicesFixtures.tempPersistence(), now: now)
    }

    func testWinFullDurationRewards() {
        var p = Profile()
        let r = apply(ServicesFixtures.outcome(won: true, minutes: 15), &p)
        XCTAssertFalse(r.noRewards)
        XCTAssertTrue(r.won)
        XCTAssertEqual(r.coins, 220)
        XCTAssertEqual(r.firstWinBonus, 300)
        XCTAssertEqual(r.eventBonusCoins, 0)
        XCTAssertEqual(p.starlightCoin, 520)
        XCTAssertEqual(r.accountXP, 120)
        XCTAssertEqual(p.accountXP, 120)
        XCTAssertEqual(r.passXP, 150)
        XCTAssertEqual(p.pass.xp, 150)
        XCTAssertNil(r.rankBefore)
        XCTAssertNil(r.rankAfter)
        XCTAssertEqual(p.career.matches, 1)
        XCTAssertEqual(p.career.wins, 1)
        XCTAssertEqual(p.career.kills, 4)
        XCTAssertEqual(p.career.perHero["H001"]?.wins, 1)
        XCTAssertEqual(p.matchHistory.count, 1)
        XCTAssertEqual(p.matchHistory.first?.id, r.matchRecordID)
        XCTAssertEqual(p.matchHistory.first?.won, true)
        XCTAssertEqual(p.matchHistory.first?.creepScore, 90)
        XCTAssertNotNil(p.matchHistory.first?.summary)
        XCTAssertEqual(p.lastFirstWinDayKey, "2026-10-07")
        XCTAssertFalse(r.missionsProgressed.isEmpty)
        XCTAssertTrue(r.achievementsUnlocked.contains("ACH_FIRST_WIN"))
    }

    func testLossCoinsScaleWithDurationAndFloor() {
        var p = Profile()
        let half = apply(ServicesFixtures.outcome(won: false, minutes: 6), &p)
        XCTAssertEqual(half.coins, 55) // 110 × 0.5
        XCTAssertEqual(half.firstWinBonus, 0)
        XCTAssertEqual(half.accountXP, 80)
        XCTAssertEqual(half.passXP, 100)
        let short = apply(ServicesFixtures.outcome(won: false, minutes: 1), &p)
        XCTAssertEqual(short.coins, 33) // 下限 30%
        let shortWin = apply(ServicesFixtures.outcome(won: true, minutes: 3), &p)
        XCTAssertEqual(shortWin.coins, 66) // 220 × 0.3
        XCTAssertEqual(RewardService.durationFactor(seconds: 12 * 60), 1)
        XCTAssertEqual(RewardService.durationFactor(seconds: 30 * 60), 1)
        XCTAssertEqual(RewardService.durationFactor(seconds: .nan), 0.3)
    }

    func testDrawCountsAsLoss() {
        var p = Profile()
        let r = apply(ServicesFixtures.outcome(won: nil, minutes: 20), &p)
        XCTAssertFalse(r.won)
        XCTAssertEqual(r.coins, 110)
        XCTAssertNil(p.matchHistory.first?.won)
        XCTAssertEqual(p.career.wins, 0)
    }

    func testFirstWinOfDayOnlyOnce() {
        var p = Profile()
        let day1 = ServicesFixtures.date(2026, 10, 7, hour: 9)
        XCTAssertEqual(apply(ServicesFixtures.outcome(won: true), &p, now: day1).firstWinBonus, 300)
        XCTAssertEqual(apply(ServicesFixtures.outcome(won: true), &p, now: day1.addingTimeInterval(3600)).firstWinBonus, 0)
        // 敗北は初勝利ボーナスを消費しない
        var q = Profile()
        XCTAssertEqual(apply(ServicesFixtures.outcome(won: false), &q, now: day1).firstWinBonus, 0)
        XCTAssertEqual(apply(ServicesFixtures.outcome(won: true), &q, now: day1).firstWinBonus, 300)
        // 翌日は再び
        let day2 = ServicesFixtures.date(2026, 10, 8, hour: 9)
        XCTAssertEqual(apply(ServicesFixtures.outcome(won: true), &p, now: day2).firstWinBonus, 300)
        XCTAssertEqual(p.lastFirstWinDayKey, "2026-10-08")
    }

    func testExcludedModesGiveNothingAndRecordNothing() {
        let cases: [BattleOutcome] = [
            ServicesFixtures.outcome(mode: .practice, withReplay: true),
            ServicesFixtures.outcome(mode: .tutorial),
            ServicesFixtures.outcome(mode: .spectate, withReplay: true),
            ServicesFixtures.outcome(mode: .standard, isReplayPlayback: true),
            ServicesFixtures.outcome(mode: .ranked, abandoned: true, countsForRank: true),
        ]
        for o in cases {
            let original = Profile()
            var p = original
            let r = apply(o, &p)
            XCTAssertTrue(r.noRewards, "\(o.launch.config.mode)")
            XCTAssertEqual(p, original, "\(o.launch.config.mode) で記録が残った")
            XCTAssertEqual(r.coins, 0)
            XCTAssertFalse(r.replaySaved)
        }
    }

    func testAccountLevelCurveAndCap() {
        XCTAssertEqual(RewardService.xpToNext(level: 1), 500)
        XCTAssertEqual(RewardService.xpToNext(level: 10), 1400)
        var p = Profile()
        RewardService.addAccountXP(499, to: &p)
        XCTAssertEqual(p.accountLevel, 1)
        RewardService.addAccountXP(1, to: &p)
        XCTAssertEqual(p.accountLevel, 2)
        XCTAssertEqual(p.accountXP, 0)
        // 複数レベルを一度に上がる: Lv2→3 は 600、Lv3→4 は 700
        RewardService.addAccountXP(1350, to: &p)
        XCTAssertEqual(p.accountLevel, 4)
        XCTAssertEqual(p.accountXP, 50)
        RewardService.addAccountXP(10_000_000, to: &p)
        XCTAssertEqual(p.accountLevel, 60)
        XCTAssertEqual(p.accountXP, 0)
        RewardService.addAccountXP(500, to: &p)
        XCTAssertEqual(p.accountLevel, 60)
        XCTAssertEqual(p.accountXP, 0)
    }

    func testLevelUpReportedAfterMatches() {
        var p = Profile()
        p.accountXP = 450
        let r = apply(ServicesFixtures.outcome(won: true), &p)
        XCTAssertEqual(r.accountLevelBefore, 1)
        XCTAssertEqual(r.accountLevelAfter, 2)
        XCTAssertTrue(r.leveledUp)
        XCTAssertEqual(p.accountXP, 70)
    }

    func testRankedMatchUpdatesRank() {
        var p = Profile()
        let r = apply(ServicesFixtures.outcome(mode: .ranked, won: true, countsForRank: true), &p)
        XCTAssertEqual(r.rankBefore?.stars, 0)
        XCTAssertEqual(r.rankAfter?.stars, 1)
        XCTAssertEqual(p.rank.seasonWins, 1)
        let loss = apply(ServicesFixtures.outcome(mode: .ranked, won: false, countsForRank: true), &p)
        XCTAssertEqual(loss.rankAfter?.stars, 0)
        XCTAssertEqual(p.rank.seasonLosses, 1)
        // 通常戦はランクに影響しない
        _ = apply(ServicesFixtures.outcome(mode: .standard, won: true), &p)
        XCTAssertEqual(p.rank.seasonWins, 1)
    }

    func testCareerStreaksMVPAndPenta() {
        var p = Profile()
        for _ in 0..<3 { _ = apply(ServicesFixtures.outcome(won: true, isMVP: true), &p) }
        XCTAssertEqual(p.career.currentWinStreak, 3)
        XCTAssertEqual(p.career.longestWinStreak, 3)
        XCTAssertEqual(p.career.mvps, 3)
        _ = apply(ServicesFixtures.outcome(won: false, heroID: "H003", multiKill: 5), &p)
        XCTAssertEqual(p.career.currentWinStreak, 0)
        XCTAssertEqual(p.career.longestWinStreak, 3)
        XCTAssertEqual(p.career.pentaKills, 1)
        XCTAssertEqual(p.career.perHero["H001"]?.matches, 3)
        XCTAssertEqual(p.career.perHero["H001"]?.mvps, 3)
        XCTAssertEqual(p.career.perHero["H003"]?.matches, 1)
        XCTAssertEqual(p.career.perHero["H003"]?.wins, 0)
        XCTAssertEqual(p.career.totalDamage, 48_000, accuracy: 0.001)
        XCTAssertTrue(p.achievements["ACH_PENTA"]?.unlockedAt != nil)
    }

    func testMatchHistoryKeepsNewest50AndReplaysStayConsistent() {
        let persistence = ServicesFixtures.tempPersistence()
        var p = Profile()
        var lastReport = RewardReport()
        for i in 0..<55 {
            lastReport = apply(ServicesFixtures.outcome(won: i % 2 == 0, withReplay: true), &p,
                               now: ServicesFixtures.weekday.addingTimeInterval(Double(i) * 60), persistence: persistence)
        }
        XCTAssertEqual(p.matchHistory.count, 50)
        XCTAssertEqual(p.matchHistory.first?.id, lastReport.matchRecordID)
        XCTAssertTrue(zip(p.matchHistory, p.matchHistory.dropFirst()).allSatisfy { $0.date >= $1.date })
        XCTAssertTrue(lastReport.replaySaved)
        XCTAssertEqual(p.replays.count, PersistenceService.maxReplays)
        XCTAssertEqual(p.matchHistory.first?.replayID, lastReport.replayID)
        let replayIDs = Set(p.replays.map(\.id))
        for record in p.matchHistory {
            if let rid = record.replayID { XCTAssertTrue(replayIDs.contains(rid)) }
        }
        XCTAssertEqual(p.matchHistory.filter { $0.replayID != nil }.count, 20)
        let files = try? FileManager.default.contentsOfDirectory(atPath: persistence.replaysDirectory.path)
        XCTAssertEqual(files?.count, 20)
        XCTAssertNotNil(persistence.loadReplay(p.replays[0]))
    }

    /// 報酬・戦績・リプレイの紐付けはデバウンスを待たずに保存される。
    func testRewardsArePersistedImmediately() throws {
        let persistence = ServicesFixtures.tempPersistence(debounce: 30)
        defer { try? FileManager.default.removeItem(at: persistence.directory) }
        var p = Profile()
        let r = apply(ServicesFixtures.outcome(won: true, withReplay: true), &p, persistence: persistence)
        XCTAssertFalse(persistence.hasPendingSave)
        let loaded = try XCTUnwrap(PersistenceService(directory: persistence.directory).loadProfile())
        XCTAssertEqual(loaded.starlightCoin, p.starlightCoin)
        XCTAssertEqual(loaded.career.matches, 1)
        XCTAssertNotNil(r.replayID)
        XCTAssertEqual(loaded.matchHistory.first?.replayID, r.replayID)
        XCTAssertEqual(loaded.replays.first?.id, r.replayID)
    }

    func testWeekendBoostAddsCoins() {
        var p = Profile()
        let saturday = ServicesFixtures.date(2026, 10, 3, hour: 15)
        let r = apply(ServicesFixtures.outcome(won: true, minutes: 15), &p, now: saturday)
        // ブースト分は coins に含める（リザルト画面は coins + firstWinBonus を表示する）
        XCTAssertEqual(r.coins, 220 + 110)
        XCTAssertEqual(r.eventBonusCoins, 110)
        XCTAssertEqual(r.totalCoins, 220 + 110 + 300)
        XCTAssertEqual(p.starlightCoin, r.coins + r.firstWinBonus)
    }

    func testMissionProgressFromMatch() {
        var p = Profile()
        let now = ServicesFixtures.weekday
        LiveOpsService.refreshMissions(profile: &p, now: now)
        let r = apply(ServicesFixtures.outcome(won: true, kills: 7), &p, now: now)
        // ウィークリーの「対戦 15 回」は必ず進む
        XCTAssertTrue(r.missionsProgressed.contains("W01"))
        XCTAssertEqual(LiveOpsService.missionProgress(id: "W01", profile: p)?.progress, 1)
        XCTAssertEqual(LiveOpsService.missionProgress(id: "W03", profile: p)?.progress, 7)
        XCTAssertEqual(LiveOpsService.missionProgress(id: "W04", profile: p)?.progress, 3)
        // 開幕祭期間中はイベントミッションも進む
        XCTAssertTrue(r.missionsProgressed.contains("EV01"))
        XCTAssertEqual(LiveOpsService.missionProgress(id: "EV03", profile: p)?.progress, 7)
    }
}
