import XCTest
@testable import VELSTRIA
import VelstriaCore

/// ランクのシーズン（MLBB と同じ番号・91 日。下げ方と報酬。relay/src/rank.ts と揃える）。
final class ServicesSeasonTests: XCTestCase {
    private func utc(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// シーズン 42 のレジェンド II（最高はミシック・44 勝 30 敗）。
    private func legendS42() -> RankState {
        var r = RankState(tier: .legend, division: 2, stars: 3)
        r.season = 42
        r.starPoints = 640
        r.protectionPoints = 120
        r.seasonWins = 44
        r.seasonLosses = 30
        r.highestTier = .mythic
        r.seasonHighestTier = .mythic
        r.highestMythicStars = 12
        return r
    }

    // MARK: - 境目

    func testSeasonBoundariesMatchRelay() {
        XCTAssertEqual(SeasonService.firstSeason, 42)
        XCTAssertEqual(SeasonService.firstSeasonStart, utc("2026-09-16T08:00:00Z"))
        XCTAssertEqual(SeasonService.seasonLength, 91 * 86_400)
        let cases: [(Date, Int)] = [
            (utc("2026-01-01T00:00:00Z"), 42), // シーズン制の前は S42
            (utc("2026-09-16T08:00:00Z").addingTimeInterval(-0.001), 42),
            (utc("2026-09-16T08:00:00Z"), 42),
            (utc("2026-10-21T00:00:00Z"), 42),
            (utc("2026-12-16T08:00:00Z").addingTimeInterval(-0.001), 42),
            (utc("2026-12-16T08:00:00Z"), 43),
            (utc("2027-03-17T08:00:00Z").addingTimeInterval(-0.001), 43),
            (utc("2027-03-17T08:00:00Z"), 44),
            (utc("2027-06-16T08:00:00Z"), 45),
        ]
        for (date, season) in cases {
            XCTAssertEqual(SeasonService.season(at: date), season, "\(date)")
        }
        XCTAssertEqual(SeasonService.start(of: 43), utc("2026-12-16T08:00:00Z"))
        XCTAssertEqual(SeasonService.start(of: 44), utc("2027-03-17T08:00:00Z"))
        XCTAssertEqual(SeasonService.start(of: 1), SeasonService.firstSeasonStart, "S42 より前の番号は S42")
    }

    func testDaysLeftRoundsUp() {
        XCTAssertEqual(SeasonService.daysLeft(at: utc("2026-09-16T08:00:00Z")), 91)
        XCTAssertEqual(SeasonService.daysLeft(at: utc("2026-10-21T00:00:00Z")), 57)
        XCTAssertEqual(SeasonService.daysLeft(at: utc("2026-12-15T07:59:59Z")), 2)
        XCTAssertEqual(SeasonService.daysLeft(at: utc("2026-12-15T08:00:00Z")), 1)
        XCTAssertEqual(SeasonService.daysLeft(at: utc("2026-12-16T07:00:00Z")), 1)
    }

    // MARK: - 下げ方

    /// relay の SEASON_RESET と同じ表（前のシーズンの最終ランク → 新しいシーズンのティアと段位）。
    func testResetTable() {
        let table: [((RankTier, Int, Int), (RankTier, Int))] = [
            ((.warrior, 3, 2), (.warrior, 3)), ((.warrior, 2, 1), (.warrior, 2)), ((.warrior, 1, 3), (.warrior, 1)),
            ((.elite, 3, 4), (.elite, 3)), ((.elite, 2, 0), (.elite, 2)), ((.elite, 1, 4), (.elite, 1)),
            ((.master, 4, 0), (.elite, 1)), ((.master, 3, 4), (.elite, 1)), ((.master, 2, 1), (.master, 4)), ((.master, 1, 4), (.master, 3)),
            ((.grandmaster, 5, 0), (.master, 2)), ((.grandmaster, 4, 5), (.master, 1)), ((.grandmaster, 3, 0), (.grandmaster, 5)),
            ((.grandmaster, 2, 3), (.grandmaster, 4)), ((.grandmaster, 1, 5), (.grandmaster, 3)),
            ((.epic, 5, 0), (.grandmaster, 2)), ((.epic, 4, 2), (.grandmaster, 1)), ((.epic, 3, 5), (.epic, 5)),
            ((.epic, 2, 0), (.epic, 5)), ((.epic, 1, 5), (.epic, 4)),
            ((.legend, 5, 0), (.epic, 4)), ((.legend, 4, 1), (.epic, 3)), ((.legend, 3, 2), (.epic, 3)),
            ((.legend, 2, 3), (.epic, 3)), ((.legend, 1, 5), (.epic, 3)),
            ((.mythic, 1, 0), (.epic, 2)), ((.mythic, 1, 24), (.epic, 2)),
            ((.mythic, 1, 25), (.epic, 1)), ((.mythic, 1, 49), (.epic, 1)),
            ((.mythic, 1, 50), (.legend, 5)), ((.mythic, 1, 99), (.legend, 5)),
            ((.mythic, 1, 100), (.legend, 5)), ((.mythic, 1, 800), (.legend, 5)),
        ]
        for ((tier, division, stars), (newTier, newDivision)) in table {
            let place = SeasonService.resetPlace(RankState(tier: tier, division: division, stars: stars))
            XCTAssertEqual(place.tier, newTier, "\(tier) \(division) ★\(stars)")
            XCTAssertEqual(place.division, newDivision, "\(tier) \(division) ★\(stars)")
        }
    }

    /// 1 回だけ下げ（星・両ポイント・勝敗は 0、最高到達はそのまま）、終わったシーズンを積む。同じ・前のシーズンへは何もしない。
    func testAdvanceLowersOnceAndKeepsHighest() {
        var r = legendS42()
        XCTAssertTrue(SeasonService.advance(&r, to: 43))
        XCTAssertEqual(r.tier, .epic)
        XCTAssertEqual(r.division, 3)
        XCTAssertEqual([r.stars, r.starPoints, r.protectionPoints, r.seasonWins, r.seasonLosses], [0, 0, 0, 0, 0])
        XCTAssertEqual(r.season, 43)
        XCTAssertEqual(r.highestTier, .mythic, "最高到達は下がらない")
        XCTAssertEqual(r.highestMythicStars, 12)
        XCTAssertEqual(r.seasonHighestTier, .epic, "今シーズンの最高は下げた後のティアから")
        XCTAssertEqual(r.endedSeasons, [SeasonRecord(season: 42, highestTier: .mythic, tier: .legend, division: 2, stars: 3, wins: 44, losses: 30)])

        let once = r
        XCTAssertFalse(SeasonService.advance(&r, to: 43), "同じシーズンへは二度下げない")
        XCTAssertFalse(SeasonService.advance(&r, to: 42), "前のシーズンへは戻さない")
        XCTAssertEqual(r, once)

        var skipped = legendS42()
        XCTAssertTrue(SeasonService.advance(&skipped, to: 47))
        XCTAssertEqual([skipped.tier.rawValue, skipped.division, skipped.season], [RankTier.epic.rawValue, 3, 47], "何シーズン空いても下げるのは 1 回")
        XCTAssertEqual(skipped.endedSeasons.map(\.season), [42])
    }

    /// シーズン制の前のデータ（season などの項目なし）は S42。今シーズンの最高はそれまでの最高到達。
    func testLegacyDataReadsAsFirstSeason() throws {
        let legacy = try JSONDecoder().decode(RankState.self, from: Data(
            #"{"tier":5,"division":2,"stars":3,"highestTier":6,"seasonWins":10,"seasonLosses":4}"#.utf8))
        XCTAssertEqual(legacy.season, 42)
        XCTAssertEqual(legacy.seasonHighestTier, .mythic)
        XCTAssertEqual(legacy.rewardedSeason, 0)
        XCTAssertTrue(legacy.endedSeasons.isEmpty)
        let old = try JSONDecoder().decode(RankState.self, from: Data(#"{"tier":0,"division":3,"stars":0,"season":1}"#.utf8))
        XCTAssertEqual(old.season, 42, "S42 より前の番号は S42")
        // 書いて読み直しても同じ（新しい項目も保存する）
        var r = legendS42()
        SeasonService.advance(&r, to: 43)
        r.rewardedSeason = 41
        let back = try JSONDecoder().decode(RankState.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
    }

    func testNewStateStartsInCurrentSeason() {
        let now = Date()
        XCTAssertEqual(RankState().season, SeasonService.season(at: now))
        var p = Profile()
        let before = p
        XCTAssertTrue(SeasonService.refresh(profile: &p, now: now).isEmpty)
        XCTAssertEqual(p, before, "今のシーズンの新しい記録は何も変えない")
    }

    // MARK: - 報酬

    func testSeasonRewardsAreMLBBBattlePointsAsCoins() {
        XCTAssertEqual(RankTier.allCases.map { SeasonService.rewards(for: $0) },
                       [500, 1000, 2000, 3500, 6000, 10_000, 10_000].map { [MailAttachment(kind: .coin, amount: $0)] })
    }

    /// 新しいシーズンの最初の起動: 下げて、前のシーズンの最高ティアの報酬をメールで 1 回だけ送る。
    func testRefreshMailsRewardOnce() {
        var p = Profile()
        p.rank = legendS42()
        let mails = p.mail.count
        let sent = SeasonService.refresh(profile: &p, now: utc("2026-12-16T09:00:00Z"))
        XCTAssertEqual(sent.map(\.season), [42])
        XCTAssertEqual(p.mail.count, mails + 1)
        XCTAssertEqual(p.mail.first?.attachments, SeasonService.rewards(for: .mythic), "下げる前の最終ランクでなく、シーズン中の最高（ミシック）")
        XCTAssertEqual(p.rank.rewardedSeason, 42)
        XCTAssertTrue(p.rank.endedSeasons.isEmpty)
        XCTAssertEqual(p.rank.season, 43)
        XCTAssertEqual(p.rank.tier, .epic)

        let once = p
        XCTAssertTrue(SeasonService.refresh(profile: &p, now: utc("2026-12-20T00:00:00Z")).isEmpty)
        XCTAssertEqual(p, once, "二度目の起動は何もしない")
    }

    /// そのシーズンに 1 試合もしていなければ、下げるだけで報酬は送らない。
    func testNoRewardWithoutRankedMatches() {
        var p = Profile()
        var r = RankState(tier: .epic, division: 1, stars: 2)
        r.season = 42
        p.rank = r
        let mails = p.mail.count
        XCTAssertTrue(SeasonService.refresh(profile: &p, now: utc("2027-01-01T00:00:00Z")).isEmpty)
        XCTAssertEqual(p.mail.count, mails)
        XCTAssertEqual([p.rank.tier.rawValue, p.rank.division, p.rank.season], [RankTier.epic.rawValue, 4, 43])
        XCTAssertEqual(p.rank.rewardedSeason, 0)
    }

    /// 同じシーズンを二度進めても（クラウドの古い番号で戻されるなど）、報酬は二度送らない。
    func testRewardIsNeverSentTwiceForTheSameSeason() {
        var p = Profile()
        p.rank = legendS42()
        SeasonService.refresh(profile: &p, now: utc("2026-12-16T09:00:00Z"))
        let mails = p.mail.count
        // S42 の記録へ戻された（勝敗もある）
        p.rank.season = 42
        p.rank.seasonWins = 3
        XCTAssertTrue(SeasonService.refresh(profile: &p, now: utc("2026-12-17T00:00:00Z")).isEmpty)
        XCTAssertEqual(p.mail.count, mails)
        XCTAssertEqual(p.rank.season, 43)
        XCTAssertTrue(p.rank.endedSeasons.isEmpty)
    }

    /// 起動したまま新しいシーズンになった時: ランク戦の結果の前に下げ（relay の match と同じ順）、報酬は次の起動・ランク画面で送る。
    func testApplyAdvancesSeasonBeforeTheMatch() {
        var r = RankState(tier: .mythic, division: 1, stars: 55)
        r.season = 43
        r.seasonWins = 70
        r.seasonLosses = 40
        r.highestMythicStars = 60
        let d = RankService.apply(won: true, rating: 8, to: &r, now: utc("2027-03-17T08:00:00Z"))
        XCTAssertTrue(d.seasonReset)
        XCTAssertEqual(d.starPointsGain, 84)
        XCTAssertEqual([r.tier.rawValue, r.division, r.stars, r.starPoints], [RankTier.legend.rawValue, 5, 1, 84])
        XCTAssertEqual([r.seasonWins, r.seasonLosses, r.season], [1, 0, 44])
        XCTAssertEqual(r.endedSeasons, [SeasonRecord(season: 43, highestTier: .mythic, tier: .mythic, division: 1, stars: 55, wins: 70, losses: 40)])
        let next = RankService.apply(won: false, rating: 8, to: &r, now: utc("2027-03-18T00:00:00Z"))
        XCTAssertFalse(next.seasonReset, "同じシーズンの 2 試合目は下げない")
        XCTAssertEqual(r.season, 44)

        var p = Profile()
        p.rank = r
        let sent = SeasonService.deliverRewards(profile: &p, now: utc("2027-03-18T00:00:00Z"))
        XCTAssertEqual(sent.map(\.season), [43])
        XCTAssertEqual(p.mail.first?.attachments, SeasonService.rewards(for: .mythic))
        XCTAssertTrue(SeasonService.deliverRewards(profile: &p, now: utc("2027-03-18T00:00:00Z")).isEmpty)
    }
}
