import XCTest
@testable import VELSTRIA
import VelstriaCore

final class ServicesRankTests: XCTestCase {
    private func state(_ tier: RankTier, _ division: Int, _ stars: Int, points: Int = 0,
                       highest: RankTier? = nil) -> RankState {
        var r = RankState()
        r.tier = tier
        r.division = division
        r.stars = stars
        r.points = points
        r.highestTier = highest ?? tier
        return r
    }

    func testWinsFillStarsThenPromoteDivision() {
        var r = RankState()
        for expected in 1...3 {
            RankService.apply(won: true, to: &r)
            XCTAssertEqual(r.stars, expected)
            XCTAssertEqual(r.division, 3)
        }
        XCTAssertTrue(RankService.isPromotionMatch(r))
        RankService.apply(won: true, to: &r)
        XCTAssertEqual(r.tier, .meteorite)
        XCTAssertEqual(r.division, 2)
        XCTAssertEqual(r.stars, 1)
        XCTAssertEqual(r.seasonWins, 4)
    }

    func testTierPromotionGrantsFloorProtectionOnlyFirstTime() {
        var r = state(.meteorite, 1, 3)
        RankService.apply(won: true, to: &r)
        XCTAssertEqual(r.tier, .silverRing)
        XCTAssertEqual(r.division, 3)
        XCTAssertEqual(r.stars, 1)
        XCTAssertEqual(r.highestTier, .silverRing)
        XCTAssertTrue(RankService.hasFloorProtection(r))

        // 星 1 → 0 → 保護で留まる → 降格
        RankService.apply(won: false, to: &r)
        XCTAssertEqual(r.stars, 0)
        RankService.apply(won: false, to: &r)
        XCTAssertEqual(r.tier, .silverRing)
        XCTAssertEqual(r.division, 3)
        XCTAssertEqual(r.stars, 0)
        XCTAssertFalse(RankService.hasFloorProtection(r))
        RankService.apply(won: false, to: &r)
        XCTAssertEqual(r.tier, .meteorite)
        XCTAssertEqual(r.division, 1)
        XCTAssertEqual(r.stars, 2)
        XCTAssertEqual(r.highestTier, .silverRing)

        // 再昇格では保護は付かない（ティアごとに 1 回）
        RankService.apply(won: true, to: &r)
        RankService.apply(won: true, to: &r)
        XCTAssertEqual(r.tier, .silverRing)
        XCTAssertFalse(RankService.hasFloorProtection(r))
        RankService.apply(won: false, to: &r)
        RankService.apply(won: false, to: &r)
        XCTAssertEqual(r.tier, .meteorite)
    }

    func testLossAtZeroStarsDemotesDivisionWithTwoStars() {
        var r = state(.goldRing, 2, 0)
        RankService.apply(won: false, to: &r)
        XCTAssertEqual(r.tier, .goldRing)
        XCTAssertEqual(r.division, 3)
        XCTAssertEqual(r.stars, 2)
        XCTAssertEqual(r.seasonLosses, 1)
    }

    func testMeteoriteNeverDemotes() {
        var r = state(.meteorite, 2, 0)
        for _ in 0..<5 { RankService.apply(won: false, to: &r) }
        XCTAssertEqual(r.tier, .meteorite)
        XCTAssertEqual(r.division, 2)
        XCTAssertEqual(r.stars, 0)
        var bottom = RankState()
        RankService.apply(won: false, to: &bottom)
        XCTAssertEqual(bottom.division, 3)
        XCTAssertEqual(bottom.stars, 0)
    }

    func testSovereignPoints() {
        var r = state(.starCrown, 1, 3)
        RankService.apply(won: true, to: &r)
        XCTAssertEqual(r.tier, .starRingSovereign)
        XCTAssertEqual(r.points, 0)
        XCTAssertEqual(r.division, 1)
        RankService.apply(won: true, to: &r)
        XCTAssertEqual(r.points, 20)
        RankService.apply(won: false, to: &r)
        XCTAssertEqual(r.points, 5)
        RankService.apply(won: false, to: &r)
        XCTAssertEqual(r.points, 0)
        XCTAssertEqual(r.tier, .starRingSovereign)
        RankService.apply(won: false, to: &r)
        XCTAssertEqual(r.tier, .starCrown)
        XCTAssertEqual(r.division, 1)
        XCTAssertEqual(r.stars, 2)
        XCTAssertEqual(r.highestTier, .starRingSovereign)
        XCTAssertEqual(RankService.displayName(state(.starRingSovereign, 1, 0, points: 140)).hasSuffix("140pt"), true)
    }

    func testRatingOrdersTiersAndIgnoresProtectionFlag() {
        XCTAssertEqual(RankService.rating(state(.goldRing, 3, 0, points: 1)), RankService.rating(state(.goldRing, 3, 0)))
        XCTAssertLessThan(RankService.rating(state(.goldRing, 1, 3)), RankService.rating(state(.whiteStar, 3, 0)))
        XCTAssertLessThan(RankService.rating(state(.starCrown, 1, 3)), RankService.rating(state(.starRingSovereign, 1, 0)))
        XCTAssertLessThan(RankService.rating(state(.starRingSovereign, 1, 0, points: 20)),
                          RankService.rating(state(.starRingSovereign, 1, 0, points: 40)))
    }

    func testLadderIsDeterministicPerPlayer() {
        var p = Profile()
        p.playerID = "11111111-2222-3333-4444-555555555555"
        p.displayName = "Tester"
        let a = RankService.ladder(for: p)
        let b = RankService.ladder(for: p)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, RankService.rivalCount + 1)
        XCTAssertEqual(a.filter(\.isPlayer).count, 1)
        XCTAssertEqual(Set(a.map(\.name)).count, a.count, "名前（id）は一意")
        XCTAssertTrue(zip(a, a.dropFirst()).allSatisfy { $0.rating >= $1.rating })
        XCTAssertEqual(a.filter { $0.tier == .starRingSovereign && !$0.isPlayer }.count, 3)

        var q = p
        q.playerID = "99999999-8888-7777-6666-555555555555"
        XCTAssertNotEqual(RankService.ladder(for: q).map(\.name), a.map(\.name))

        // 新規プレイヤーは最下位付近
        XCTAssertGreaterThan(RankService.ladderPosition(for: p), 40)
        p.rank = state(.starRingSovereign, 1, 0, points: 5000)
        XCTAssertEqual(RankService.ladderPosition(for: p), 1)
    }

    func testTierRewardsClaimOnce() {
        var p = Profile()
        XCTAssertFalse(RankService.tierRewards(.meteorite).isEmpty)
        for tier in RankTier.allCases { XCTAssertFalse(RankService.tierRewards(tier).isEmpty) }
        XCTAssertTrue(RankService.claimTierReward(.meteorite, profile: &p))
        XCTAssertEqual(p.starlightCoin, 300)
        XCTAssertFalse(RankService.claimTierReward(.meteorite, profile: &p))
        XCTAssertEqual(p.starlightCoin, 300)
        XCTAssertFalse(RankService.claimTierReward(.goldRing, profile: &p), "未到達")
        p.rank.highestTier = .whiteStar
        XCTAssertTrue(RankService.claimTierReward(.whiteStar, profile: &p))
        XCTAssertTrue(p.ownedCosmeticIDs.contains("CO035"))
        XCTAssertEqual(p.freeGem, 60)
        XCTAssertEqual(p.rank.claimedTierRewards, [RankTier.meteorite.rawValue, RankTier.whiteStar.rawValue])
    }

    func testBotDifficultyMapping() {
        XCTAssertTrue(RankService.botDifficulty(for: state(.meteorite, 3, 0)) == (.normal, .easy))
        XCTAssertTrue(RankService.botDifficulty(for: state(.goldRing, 3, 0)) == (.normal, .normal))
        XCTAssertTrue(RankService.botDifficulty(for: state(.azureCrystal, 3, 0)) == (.hard, .hard))
    }
}
