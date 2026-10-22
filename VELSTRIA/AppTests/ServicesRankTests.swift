import XCTest
@testable import VELSTRIA
import VelstriaCore

/// ランクの規則（Mobile Legends と同じ。relay/src/rank.ts と揃える）。シーズンは ServicesSeasonTests。
final class ServicesRankTests: XCTestCase {
    private func state(_ tier: RankTier, _ division: Int, _ stars: Int, starPoints: Int = 0, protection: Int = 0) -> RankState {
        var r = RankState(tier: tier, division: division, stars: stars)
        r.starPoints = starPoints
        r.protectionPoints = protection
        return r
    }

    func testShapeMatchesMLBB() {
        XCTAssertEqual(RankTier.allCases.map(RankService.divisions), [3, 3, 4, 5, 5, 5, 1])
        XCTAssertEqual(RankTier.allCases.map(RankService.maxStars), [3, 4, 4, 5, 5, 5, 0])
    }

    /// 満タンはティアごと（Fandom「Ranked」）。ミシックにはスターポイントが無く、保護ポイントは 1100（2.2.16 の映像）。
    func testPointCapsPerTier() {
        XCTAssertEqual(RankTier.allCases.map(RankService.starPointCap), [100, 200, 300, 500, 700, 1000, 0])
        XCTAssertEqual(RankTier.allCases.map(RankService.protectionCap), [100, 200, 300, 500, 700, 1000, 1100])
        XCTAssertEqual(RankService.progress(350, cap: 700), 0.5)
        XCTAssertEqual(RankService.progress(5, cap: 0), 0, "ミシックのスターポイントは 0 で割らない")
        XCTAssertEqual(RankService.progress(2000, cap: 1500), 1)
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
        XCTAssertEqual(r.seasonHighestTier, .master)
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
        XCTAssertEqual(RankService.mythicName(stars: 24), L("ミシック", "Mythic"))
        XCTAssertEqual(RankService.mythicName(stars: 25), L("Hミシック", "Mythical Honor"))
        XCTAssertEqual(RankService.mythicName(stars: 50), L("Gミシック", "Mythical Glory"))
        XCTAssertEqual(RankService.mythicName(stars: 100), L("Iミシック", "Mythical Immortal"))
    }

    func testProtectionPointsSaveAStar() {
        var r = state(.epic, 3, 3, protection: RankService.protectionCap(.epic))
        XCTAssertTrue(RankService.hasFloorProtection(r))
        let d = RankService.apply(won: false, rating: 8, to: &r)
        XCTAssertTrue(d.protected)
        XCTAssertEqual(r.stars, 3)
        XCTAssertEqual(r.protectionPoints, 0)
        let d2 = RankService.apply(won: false, rating: 8, to: &r)
        XCTAssertEqual(r.stars, 2)
        XCTAssertEqual(r.protectionPoints, d2.scoreBonus + d2.activeBonus)
    }

    func testStarPointsGrantBonusStar() {
        var r = state(.epic, 3, 1, starPoints: RankService.starPointCap(.epic) - 1)
        RankService.apply(won: true, rating: 10, to: &r)
        XCTAssertEqual(r.stars, 3)
        XCTAssertLessThan(r.starPoints, RankService.starPointCap(.epic))
    }

    /// 各ティアの満タン: 満タン − 1 から評価 0 の勝ち（+20）で星 +2・残り 19。満タン − 21 からなら星 +1 だけ。
    func testStarPointCapAtEachTier() {
        for tier in RankTier.allCases where tier != .mythic {
            let cap = RankService.starPointCap(tier)
            var full = state(tier, RankService.divisions(tier), 0, starPoints: cap - 1)
            let d = RankService.apply(won: true, rating: 0, to: &full)
            XCTAssertEqual(d.starPointsGain, 20, "\(tier)")
            XCTAssertEqual([full.stars, full.starPoints], [2, 19], "\(tier)")
            var short = state(tier, RankService.divisions(tier), 0, starPoints: cap - 21)
            RankService.apply(won: true, rating: 0, to: &short)
            XCTAssertEqual([short.stars, short.starPoints], [1, cap - 1], "\(tier)")
        }
    }

    /// 各ティアの満タン: 満タンで負けると星が減らずに 0 へ。満タン − 1 なら守らず（ウォリアーはもともと減らない）、満タンで止まる。
    func testProtectionCapAtEachTier() {
        for tier in RankTier.allCases {
            let cap = RankService.protectionCap(tier)
            let stars = tier == .mythic ? 10 : 2
            var full = state(tier, 1, stars, protection: cap)
            let d = RankService.apply(won: false, rating: 0, to: &full)
            XCTAssertTrue(d.protected, "\(tier)")
            XCTAssertEqual([full.stars, full.protectionPoints], [stars, 0], "\(tier)")
            var short = state(tier, 1, stars, protection: cap - 1)
            let d2 = RankService.apply(won: false, rating: 0, to: &short)
            XCTAssertFalse(d2.protected, "\(tier)")
            XCTAssertEqual([short.stars, short.protectionPoints], [tier == .warrior ? stars : stars - 1, cap], "\(tier)")
        }
    }

    /// ミシック: スターポイントは無く（上がると 0）、保護ポイントは負けるとたまる。レジェンドへ落ちたらレジェンドの満タンに収める。
    func testMythicHasProtectionButNoStarPoints() {
        var r = state(.legend, 1, 5, starPoints: 400)
        RankService.apply(won: true, rating: 16, mvp: true, to: &r)
        XCTAssertEqual(r.tier, .mythic)
        XCTAssertEqual(r.starPoints, 0)
        let win = RankService.apply(won: true, rating: 16, mvp: true, to: &r)
        XCTAssertEqual(win.starPointsGain, 0)
        XCTAssertEqual(r.starPoints, 0)
        let loss = RankService.apply(won: false, rating: 10, to: &r)
        XCTAssertEqual([loss.scoreBonus, loss.activeBonus], [30, 5])
        XCTAssertEqual(r.protectionPoints, 35)
        var fall = state(.mythic, 1, 0, protection: 1000)
        RankService.apply(won: false, rating: 16, to: &fall)
        XCTAssertEqual(fall.tier, .legend)
        XCTAssertEqual(fall.protectionPoints, RankService.protectionCap(.legend))
    }

    /// 旧規則（全ティア 700）の頃の保存データは、読み込む時にティアの満タンに収める。
    func testLegacyPointsAreFittedOnDecode() throws {
        func decode(_ json: String) throws -> RankState {
            try JSONDecoder().decode(RankState.self, from: Data(json.utf8))
        }
        let warrior = try decode(#"{"tier":0,"division":2,"stars":1,"starPoints":650,"protectionPoints":700}"#)
        XCTAssertEqual([warrior.starPoints, warrior.protectionPoints], [99, 100])
        let epic = try decode(#"{"tier":4,"division":2,"stars":1,"starPoints":650,"protectionPoints":700}"#)
        XCTAssertEqual([epic.starPoints, epic.protectionPoints], [650, 700])
        let mythic = try decode(#"{"tier":6,"division":1,"stars":3,"starPoints":650,"protectionPoints":700}"#)
        XCTAssertEqual([mythic.starPoints, mythic.protectionPoints], [0, 700])
    }

    /// relay/test/relay.test.mjs の RANK_RULES と同じ表（端末の計算と中継の計算が同じ値になるか）。
    func testSameRulesAsRelay() {
        func check(_ name: String, _ seed: RankState, won: Bool, rating: Double, mvp: Bool = false,
                   _ change: (inout RankState) -> Void, _ delta: RankMatchDelta,
                   file: StaticString = #filePath, line: UInt = #line) {
            var r = seed
            let d = RankService.apply(won: won, rating: rating, mvp: mvp, to: &r)
            var expected = seed
            change(&expected)
            if won { expected.seasonWins += 1 } else { expected.seasonLosses += 1 }
            XCTAssertEqual(r, expected, name, file: file, line: line)
            XCTAssertEqual(d, delta, name, file: file, line: line)
        }
        check("満星で勝つと次の段位の星 1（20 + 8.2 × 8 = 85.6 → 86）", state(.elite, 2, 4), won: true, rating: 8.2,
              { $0.division = 1; $0.stars = 1; $0.starPoints = 86 }, RankMatchDelta(starPointsGain: 86))
        check("ティアの最上段の満星で勝つと次のティアの最下段・星 1", state(.elite, 1, 4), won: true, rating: 5,
              { $0.tier = .master; $0.division = 4; $0.stars = 1; $0.starPoints = 60; $0.highestTier = .master; $0.seasonHighestTier = .master },
              RankMatchDelta(starPointsGain: 60))
        check("星 0 で負けると 1 段位下の満星 −1", state(.master, 3, 0), won: false, rating: 8.2,
              { $0.division = 4; $0.stars = 3; $0.protectionPoints = 30 }, RankMatchDelta(scoreBonus: 25, activeBonus: 5))
        check("ティアの最下段・星 0 で負けても下のティアへは落ちない", state(.grandmaster, 5, 0), won: false, rating: 0,
              { $0.protectionPoints = 5 }, RankMatchDelta(activeBonus: 5))
        check("ウォリアーは負けても星が減らない", state(.warrior, 2, 2), won: false, rating: 10,
              { $0.protectionPoints = 35 }, RankMatchDelta(scoreBonus: 30, activeBonus: 5))
        check("エピックのスターポイントは 700 で星がもう 1 つ", state(.epic, 5, 0, starPoints: 690), won: true, rating: 16, mvp: true,
              { $0.stars = 2; $0.starPoints = 168 }, RankMatchDelta(starPointsGain: 178))
        check("満タンを 1 試合で 2 回越えても星のおまけは 1 つ", state(.warrior, 3, 0, starPoints: 99), won: true, rating: 16, mvp: true,
              { $0.stars = 2; $0.starPoints = 99 }, RankMatchDelta(starPointsGain: 178))
        check("レジェンドの保護ポイント 1000 で負けると星が減らない", state(.legend, 2, 3, protection: 1000), won: false, rating: 10,
              { $0.protectionPoints = 0 }, RankMatchDelta(scoreBonus: 30, activeBonus: 5, protected: true))
        check("レジェンドは保護ポイント 700 では守らない", state(.legend, 2, 3, protection: 700), won: false, rating: 10,
              { $0.stars = 2; $0.protectionPoints = 735 }, RankMatchDelta(scoreBonus: 30, activeBonus: 5))
        check("エピックの保護ポイントは満タンの 700 で止まる", state(.epic, 3, 2, protection: 690), won: false, rating: 16,
              { $0.stars = 1; $0.protectionPoints = 700 }, RankMatchDelta(scoreBonus: 48, activeBonus: 5))
        check("レジェンド I の満星で勝つとミシック星 0（スターポイントは 0）", state(.legend, 1, 5, starPoints: 100), won: true, rating: 10, mvp: true,
              { $0.tier = .mythic; $0.division = 1; $0.stars = 0; $0.starPoints = 0; $0.highestTier = .mythic; $0.seasonHighestTier = .mythic },
              RankMatchDelta())
        var mythic24 = state(.mythic, 1, 24)
        mythic24.highestMythicStars = 24
        check("ミシックの勝ちは星の累計 +1", mythic24, won: true, rating: 16, mvp: true,
              { $0.stars = 25; $0.highestMythicStars = 25 }, RankMatchDelta())
        var mythic0 = state(.mythic, 1, 0)
        mythic0.highestMythicStars = 7
        check("ミシック星 0 で負けるとレジェンド I・星 4（保護ポイントはたまる）", mythic0, won: false, rating: 10,
              { $0.tier = .legend; $0.division = 1; $0.stars = 4; $0.protectionPoints = 35 }, RankMatchDelta(scoreBonus: 30, activeBonus: 5))
        check("ミシックからレジェンドへ落ちたら保護ポイントは 1000 に収める", state(.mythic, 1, 0, protection: 1000), won: false, rating: 16,
              { $0.tier = .legend; $0.division = 1; $0.stars = 4; $0.protectionPoints = 1000 }, RankMatchDelta(scoreBonus: 48, activeBonus: 5))
        check("評価は 16 までに収める", state(.elite, 3, 0), won: true, rating: 99,
              { $0.stars = 1; $0.starPoints = 148 }, RankMatchDelta(starPointsGain: 148))
        check("評価は 0 からに収める", state(.elite, 3, 2), won: false, rating: -5,
              { $0.stars = 1; $0.protectionPoints = 5 }, RankMatchDelta(activeBonus: 5))
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
