import XCTest
@testable import VELSTRIA
import VelstriaCore

/// サービス層テスト共通の組み立て部品。
enum ServicesFixtures {
    static let master = MasterData.shared

    /// 一時ディレクトリの永続化（バックアップは毎回繰り下げ、デバウンスは短め）。
    static func tempPersistence(debounce: TimeInterval = 0.5, rotation: TimeInterval = 0) -> PersistenceService {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VelstriaServicesTests-\(UUID().uuidString)", isDirectory: true)
        return PersistenceService(directory: dir, saveDebounce: debounce, backupRotationInterval: rotation)
    }

    /// 端末ローカル暦の日時。
    static func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, minute: Int = 0) -> Date {
        LiveOpsService.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    /// 2026-10-07（水）正午。週末ブーストの影響を受けない平日。
    static var weekday: Date { date(2026, 10, 7) }

    static func config(mode: MatchMode, heroID: String = "H001", seed: UInt64 = 42) -> MatchConfig {
        switch mode {
        case .standard, .ranked:
            return MatchFactory.standardMatch(mode: mode, humanHeroID: heroID, humanName: "Tester", seed: seed)
        case .practice, .tutorial:
            return MatchFactory.practiceMatch(humanHeroID: heroID, humanName: "Tester", options: PracticeOptions(),
                                              tutorial: mode == .tutorial, seed: seed)
        case .spectate:
            return MatchFactory.botMatch(seed: seed)
        case .brawl:
            return MatchFactory.brawlMatch(humanHeroID: heroID, humanName: "Tester", seed: seed)
        case .custom:
            return MatchFactory.customMatch(humanSide: .blue, humanHeroID: heroID, humanName: "Tester", seed: seed)
        case .magicChess:
            // マジックチェスは MatchConfig を通常の MOBA 用途では使わない（戦闘のみ一時 SimState で流用）。
            return MatchConfig(mode: .magicChess, seed: seed, players: [])
        case .online:
            return MatchFactory.onlineMatch(humans: [OnlineHumanSlot(team: .blue, position: .mid, heroID: heroID, displayName: "Tester")],
                                            seed: seed)
        }
    }

    static func summary(mode: MatchMode, won: Bool?, minutes: Double, heroID: String = "H001",
                        kills: Int = 4, deaths: Int = 2, assists: Int = 6, minionKills: Int = 90,
                        damage: Double = 12_000, gold: Double = 8_000, multiKill: Int = 1,
                        isMVP: Bool = false, towers: Int = 3, humanPresent: Bool = true) -> MatchSummary {
        var score = HeroScore()
        score.kills = kills
        score.deaths = deaths
        score.assists = assists
        score.minionKills = minionKills
        score.damageToHeroes = damage
        score.goldEarned = gold
        score.largestMultiKill = multiKill
        let human = PlayerSummary(entityID: 1, team: .blue, heroID: heroID, displayName: "Tester", isHuman: humanPresent,
                                  position: .top, level: 12, items: ["EQ001", "EQ002"], score: score, mvpScore: 20,
                                  grade: "A", isMVP: isMVP)
        let enemy = PlayerSummary(entityID: 2, team: .red, heroID: "H010", displayName: "Bot", isHuman: false,
                                  position: .top, level: 11, items: [], score: HeroScore(), mvpScore: 5,
                                  grade: "C", isMVP: false)
        let winner: Team? = won.map { $0 ? .blue : .red }
        return MatchSummary(mode: mode, seed: 42, winner: winner, endReason: won == nil ? .timeLimit : .coreDestroyed,
                            duration: minutes * 60, humanTeam: humanPresent ? .blue : nil, players: [human, enemy],
                            teamKills: [kills + 10, 8], towersDestroyed: [towers, 2])
    }

    static func replay(config: MatchConfig, summary: MatchSummary, ticks: Int = 900) -> ReplayData {
        let recorder = ReplayRecorder(config: config)
        recorder.record(tick: 1, commands: [])
        recorder.record(tick: ticks, commands: [])
        return recorder.finish(summary: summary)
    }

    static func outcome(mode: MatchMode = .standard, won: Bool? = true, minutes: Double = 15, heroID: String = "H001",
                        abandoned: Bool = false, withReplay: Bool = false, isReplayPlayback: Bool = false,
                        countsForRank: Bool = false, kills: Int = 4, assists: Int = 6, multiKill: Int = 1,
                        isMVP: Bool = false, towers: Int = 3, damage: Double = 12_000) -> BattleOutcome {
        let cfg = config(mode: mode, heroID: heroID)
        let sum = summary(mode: mode, won: won, minutes: minutes, heroID: heroID, kills: kills, assists: assists,
                          damage: damage, multiKill: multiKill, isMVP: isMVP, towers: towers)
        let rep = replay(config: cfg, summary: sum)
        let launch = BattleLaunch(config: cfg, replay: isReplayPlayback ? rep : nil, countsForRank: countsForRank)
        return BattleOutcome(launch: launch, summary: sum, replay: withReplay ? rep : nil, abandoned: abandoned)
    }
}

final class ServicesSupportTests: XCTestCase {
    func testFixturesProduceHumanPlayer() {
        let o = ServicesFixtures.outcome()
        XCTAssertEqual(o.summary.humanPlayer?.heroID, "H001")
        XCTAssertEqual(o.summary.humanWon, true)
        XCTAssertTrue(RewardService.isRewardEligible(o))
    }

    func testDayAndWeekKeys() {
        let d = ServicesFixtures.date(2026, 9, 28)
        XCTAssertEqual(LiveOpsService.dayKey(d), "2026-09-28")
        XCTAssertEqual(LiveOpsService.weekKey(d), "2026-W40")
        XCTAssertEqual(LiveOpsService.monthKey(d), "2026-09")
        // ISO 週は年をまたぐ（2027-01-01 は 2026 年第 53 週）
        XCTAssertEqual(LiveOpsService.weekKey(ServicesFixtures.date(2027, 1, 1)), "2026-W53")
        XCTAssertEqual(LiveOpsService.weekKey(ServicesFixtures.date(2027, 1, 4)), "2027-W01")
    }
}
