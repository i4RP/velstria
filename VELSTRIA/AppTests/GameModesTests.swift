import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 追加ゲームモード（乱闘・ライジング・カスタム・マジックチェス）のサービス層テスト。
final class GameModesTests: XCTestCase {
    // MARK: 乱闘の報酬

    func testBrawlIsRewardEligible() {
        XCTAssertTrue(RewardService.isRewardEligible(ServicesFixtures.outcome(mode: .brawl)))
    }

    func testCustomIsNotRewardEligible() {
        XCTAssertFalse(RewardService.isRewardEligible(ServicesFixtures.outcome(mode: .custom)))
    }

    func testBrawlRewardsWithoutRank() {
        var p = Profile()
        let before = p.rank
        let outcome = ServicesFixtures.outcome(mode: .brawl, won: true, countsForRank: false)
        let persistence = ServicesFixtures.tempPersistence()
        _ = RewardService.apply(outcome: outcome, to: &p, master: ServicesFixtures.master,
                                persistence: persistence, now: ServicesFixtures.weekday)
        XCTAssertEqual(p.rank, before, "乱闘はランクに影響しない")
        XCTAssertGreaterThan(p.starlightCoin, 0, "乱闘は報酬あり")
    }

    // MARK: ライジング

    func testRisingConfigUsesStageDifficulty() {
        let stage = RisingService.ladder[4]
        let cfg = RisingService.config(for: stage, heroID: "H001", profile: Profile(), seed: 3)
        XCTAssertEqual(cfg.mode, .standard)
        let enemy = cfg.players.first { $0.team == .red && $0.controller == .bot }
        XCTAssertEqual(enemy?.botDifficulty, stage.enemyDifficulty)
    }

    func testRisingAdvanceAndRewardIdempotent() {
        var p = Profile()
        XCTAssertEqual(p.rising.stageIndex, 0)
        XCTAssertNotNil(RisingService.resolve(won: true, stageIndex: 0, profile: &p))
        XCTAssertEqual(p.rising.stageIndex, 1)
        XCTAssertTrue(p.rising.claimedStages.contains(0))
        let coins = p.starlightCoin
        // 同じ（古い）ステージで再解決しても前進・再付与しない。
        XCTAssertNil(RisingService.resolve(won: true, stageIndex: 0, profile: &p))
        XCTAssertEqual(p.starlightCoin, coins)
    }

    func testRisingLossDoesNotAdvance() {
        var p = Profile()
        XCTAssertNil(RisingService.resolve(won: false, stageIndex: 0, profile: &p))
        XCTAssertEqual(p.rising.stageIndex, 0)
    }

    // MARK: カスタム

    func testCustomBrawlMapIsBrawlMode() {
        let cfg = CustomSetup.config(heroID: "H001", side: .blue, mapKind: .brawl,
                                     allyDifficulty: .normal, enemyDifficulty: .hard, profile: Profile(), seed: 7)
        XCTAssertEqual(cfg.mode, .brawl)
    }

    func testCustomStandardMapIsCustomMode() {
        let cfg = CustomSetup.config(heroID: "H001", side: .blue, mapKind: .standard,
                                     allyDifficulty: .normal, enemyDifficulty: .hard, profile: Profile(), seed: 7)
        XCTAssertEqual(cfg.mode, .custom)
        XCTAssertEqual(cfg.players.first { $0.team == .red }?.botDifficulty, .hard)
    }

    // MARK: マジックチェス報酬

    func testMagicChessRewardWinnerBeatsLast() {
        var winner = Profile(); MagicChessRewardService.apply(placement: 1, participants: 8, to: &winner)
        var last = Profile(); MagicChessRewardService.apply(placement: 8, participants: 8, to: &last)
        XCTAssertGreaterThan(winner.starlightCoin, last.starlightCoin)
        XCTAssertEqual(winner.magicChessBestPlacement, 1)
        XCTAssertEqual(winner.magicChessMatches, 1)
    }

    // MARK: Profile 永続化（新フィールド）

    func testProfileRoundTripNewFields() throws {
        var p = Profile()
        p.rising.stageIndex = 3
        p.rising.claimedStages = [0, 1, 2]
        p.magicChessBestPlacement = 2
        p.magicChessMatches = 5
        let data = try PersistenceService.makeEncoder().encode(p)
        let back = try PersistenceService.makeDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(back.rising.stageIndex, 3)
        XCTAssertEqual(back.rising.claimedStages, [0, 1, 2])
        XCTAssertEqual(back.magicChessBestPlacement, 2)
        XCTAssertEqual(back.magicChessMatches, 5)
    }

    // MARK: 対戦フロー入口

    @MainActor
    func testMatchFlowBuildsBrawlConfig() {
        let model = MatchFlowModel(seed: 10)
        model.heroID = "H001"
        model.startBrawl()
        XCTAssertEqual(model.kind, .brawl)
        let cfg = model.buildConfig(profile: Profile(), master: ServicesFixtures.master)
        XCTAssertEqual(cfg?.mode, .brawl)
    }
}
