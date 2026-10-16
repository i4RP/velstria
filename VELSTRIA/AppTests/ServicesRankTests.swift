import XCTest
@testable import VELSTRIA
import VelstriaCore

/// ランクの規則（Mobile Legends と同じ。relay/src/rank.ts と揃える）。
final class ServicesRankTests: XCTestCase {
    private func state(_ tier: RankTier, _ division: Int, _ stars: Int) -> RankState {
        RankState(tier: tier, division: division, stars: stars)
    }

    func testShapeMatchesMLBB() {
        XCTAssertEqual(RankTier.allCases.map(RankService.divisions), [3, 3, 4, 5, 5, 5, 1])
        XCTAssertEqual(RankTier.allCases.map(RankService.maxStars), [3, 4, 4, 5, 5, 5, 0])
    }

    func testWinsFillStarsThenPromoteDivision() {
        var r = RankState()
        for expected in 1...3 {
            RankService.apply(won: true, rating: 0, to: &r)
            XCTAssertEqual(r.stars, expected)
        }
        XCTAssertTrue(RankService.isPromotionMatch(r))
        RankService.apply(won: true, rating: 0, to: &r)
        XCTAssertEqual(r.division, 2)
        XCTAssertEqual(r.stars, 1)
    }

    func testTierPromotionStartsAtBottomDivision() {
        var r = state(.elite, 1, 4)
        RankService.apply(won: true, rating: 0, to: &r)
        XCTAssertEqual(r.tier, .master)
        XCTAssertEqual(r.division, 4)
        XCTAssertEqual(r.stars, 1)
        XCTAssertEqual(r.highestTier, .master)
    }

    func testWarriorNeverLosesStars() {
        var r = state(.warrior, 2, 2)
        RankService.apply(won: false, to: &r)
        XCTAssertEqual(r.stars, 2)
    }

    func testLossDemotesDivisionButNotTier() {
        var r = state(.epic, 4, 0)
        RankService.apply(won: false, to: &r)
        XCTAssertEqual(r.division, 5)
        XCTAssertEqual(r.stars, 4)
        var bottom = state(.epic, 5, 0)
        RankService.apply(won: false, to: &bottom)
        XCTAssertEqual(bottom.tier, .epic)
        XCTAssertEqual(bottom.division, 5)
        XCTAssertEqual(bottom.stars, 0)
    }

    func testMythicCountsStarsAndDropsToLegend() {
        var r = state(.legend, 1, 5)
        RankService.apply(won: true, rating: 0, to: &r)
        XCTAssertEqual(r.tier, .mythic)
        XCTAssertEqual(r.stars, 0)
        RankService.apply(won: false, to: &r)
        XCTAssertEqual(r.tier, .legend)
        XCTAssertEqual(r.stars, 4)
        XCTAssertEqual(RankService.mythicName(stars: 25), L("ミシックオナー", "Mythical Honor"))
        XCTAssertEqual(RankService.mythicName(stars: 100), L("ミシックイモータル", "Mythical Immortal"))
    }

    func testProtectionPointsSaveAStar() {
        var r = state(.epic, 3, 3)
        r.protectionPoints = RankService.bar
        let d = RankService.apply(won: false, rating: 8, to: &r)
        XCTAssertTrue(d.protected)
        XCTAssertEqual(r.stars, 3)
        XCTAssertEqual(r.protectionPoints, 0)
        let d2 = RankService.apply(won: false, rating: 8, to: &r)
        XCTAssertEqual(r.stars, 2)
        XCTAssertEqual(r.protectionPoints, d2.scoreBonus + d2.activeBonus)
    }

    func testStarPointsGrantBonusStar() {
        var r = state(.epic, 3, 1)
        r.starPoints = RankService.bar - 1
        RankService.apply(won: true, rating: 10, to: &r)
        XCTAssertEqual(r.stars, 3)
        XCTAssertLessThan(r.starPoints, RankService.bar)
    }

    func testRatingOrdersTiers() {
        XCTAssertLessThan(RankService.rating(state(.master, 1, 4)), RankService.rating(state(.grandmaster, 5, 0)))
        XCTAssertLessThan(RankService.rating(state(.legend, 1, 5)), RankService.rating(state(.mythic, 1, 0)))
    }

    func testLadderContainsPlayer() {
        let p = Profile()
        let ladder = RankService.ladder(for: p)
        XCTAssertEqual(ladder.count, RankService.rivalCount + 1)
        XCTAssertEqual(ladder.filter(\.isPlayer).count, 1)
    }
}
