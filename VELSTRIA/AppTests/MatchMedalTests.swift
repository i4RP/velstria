import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 試合のメダル（MLBB の条件。docs/OUTGAME_GAP.md 6-2）とリザルトのクイックチャットの定型文。
final class MatchMedalTests: XCTestCase {
    private func player(_ id: EntityID, _ team: Team, mvp: Double, human: Bool = false) -> PlayerSummary {
        PlayerSummary(entityID: id, team: team, heroID: "H027", displayName: "P\(id)", isHuman: human, position: .mid,
                      level: 10, items: [], score: HeroScore(), mvpScore: mvp, grade: "B", isMVP: false)
    }

    /// ブルーは ID 1〜、レッドは ID 11〜。ブルーの先頭が人間。
    private func summary(winner: Team?, mode: MatchMode = .standard, blue: [Double], red: [Double]) -> MatchSummary {
        var players: [PlayerSummary] = []
        for (i, s) in blue.enumerated() { players.append(player(EntityID(i + 1), .blue, mvp: s, human: i == 0)) }
        for (i, s) in red.enumerated() { players.append(player(EntityID(i + 11), .red, mvp: s)) }
        return MatchSummary(mode: mode, seed: 7, winner: winner, endReason: winner == nil ? .timeLimit : .coreDestroyed,
                            duration: 720, humanTeam: .blue, players: players, teamKills: [12, 8, 0], towersDestroyed: [5, 2, 0])
    }

    func testRatingBandsFollowMLBB() {
        // 銅 3.0〜3.4 / 銀 3.5〜7.0 / 金 7.1〜10.0 / ウルトラ 10.1〜（3.0 未満は勲章なし）
        let cases: [(Double, MatchMedal?)] = [
            (0, nil), (2.9, nil), (3.0, .bronze), (3.4, .bronze), (3.5, .silver), (7.0, .silver),
            (7.1, .gold), (10.0, .gold), (10.1, .supreme), (16, .supreme),
        ]
        for (rating, medal) in cases {
            XCTAssertEqual(MatchMedal.award(rating: rating, won: true, isTeamBest: false), medal, "評価 \(rating)（勝ち）")
            XCTAssertEqual(MatchMedal.award(rating: rating, won: false, isTeamBest: false), medal, "評価 \(rating)（負け）")
        }
    }

    func testWinningTeamBestIsMVPAtAnyRating() {
        XCTAssertEqual(MatchMedal.award(rating: 2.0, won: true, isTeamBest: true), .mvp)
        XCTAssertEqual(MatchMedal.award(rating: 10.0, won: true, isTeamBest: true), .mvp)
        XCTAssertEqual(MatchMedal.award(rating: 10.1, won: true, isTeamBest: true), .supremeMVP)
        XCTAssertEqual(MatchMedal.award(rating: 15.5, won: true, isTeamBest: true), .supremeMVP)
    }

    func testLosingTeamBestIsMVPLossAtAnyRating() {
        // 2.2.16: 負けたチームの最高点が敗北MVP（下限は無い）
        XCTAssertEqual(MatchMedal.award(rating: 2.5, won: false, isTeamBest: true), .mvpLoss)
        XCTAssertEqual(MatchMedal.award(rating: 6.5, won: false, isTeamBest: true), .mvpLoss)
        XCTAssertEqual(MatchMedal.award(rating: 12, won: false, isTeamBest: true), .mvpLoss)
    }

    func testRatingIsComparedAtTheShownPrecision() {
        // 評価点は 0.1 刻みで出すので、表示と同じ桁で比べる（7.04 は「7.0」で銀、7.06 は「7.1」で金）
        XCTAssertEqual(MatchMedal.award(rating: 7.04, won: true, isTeamBest: false), .silver)
        XCTAssertEqual(MatchMedal.award(rating: 7.06, won: true, isTeamBest: false), .gold)
        XCTAssertNil(MatchMedal.award(rating: .nan, won: true, isTeamBest: true))
        XCTAssertNil(MatchMedal.award(rating: .infinity, won: true, isTeamBest: false))
    }

    func testSummaryGivesOneMVPPerTeam() throws {
        let s = summary(winner: .blue, blue: [30, 12, 8, 4, 1], red: [25, 10, 6, 2, 0])
        let results = MatchMedal.results(in: s)
        XCTAssertEqual(results.count, 10)
        let blue = s.players(of: .blue), red = s.players(of: .red)
        // 勝ったチームは最高の 1 人だけが MVP（10.1 以上ならウルトラ MVP）
        XCTAssertEqual(blue.filter { results[$0.entityID]?.medal?.isWinnerMVP == true }.map(\.entityID), [blue[0].entityID])
        XCTAssertFalse(red.contains { results[$0.entityID]?.medal?.isWinnerMVP == true })
        // 負けたチームは最高の 1 人が敗北MVP
        let redTop = try XCTUnwrap(results[red[0].entityID])
        XCTAssertEqual(redTop.medal, .mvpLoss)
        XCTAssertFalse(red.dropFirst().contains { results[$0.entityID]?.medal == .mvpLoss })
        XCTAssertFalse(blue.contains { results[$0.entityID]?.medal == .mvpLoss })
        // ほかの人は評価点だけで決まる（評価点は RankService.matchRating）
        for p in Array(blue.dropFirst()) + Array(red.dropFirst()) {
            let r = try XCTUnwrap(results[p.entityID])
            let rating = RankService.matchRating(p, in: s)
            XCTAssertEqual(r.rating, rating)
            XCTAssertEqual(r.medal, MatchMedal.award(rating: rating, won: p.team == .blue, isTeamBest: false))
        }
        XCTAssertEqual(MatchMedal.result(for: blue[1], in: s), results[blue[1].entityID])
    }

    func testTiedTopGoesToTheLowerID() {
        // 同点の最高は MVP スコアの並び（同点は ID の小さい方）の先頭だけが MVP
        let s = summary(winner: .red, blue: [5, 5, 1, 1, 1], red: [20, 20, 3, 3, 3])
        let results = MatchMedal.results(in: s)
        XCTAssertEqual(results[11]?.medal?.isWinnerMVP, true)
        XCTAssertEqual(results[12]?.medal?.isMVP, false)
        XCTAssertEqual(results[1]?.medal, .mvpLoss)
        XCTAssertNotEqual(results[2]?.medal, .mvpLoss)
    }

    func testNoWinnerMeansNoMVP() {
        let s = summary(winner: nil, blue: [20, 5, 1, 1, 1], red: [18, 4, 1, 1, 1])
        let results = MatchMedal.results(in: s)
        XCTAssertEqual(results.count, 10)
        XCTAssertFalse(results.values.contains { $0.medal?.isMVP == true })
    }

    func testPracticeAndTutorialHaveNoMedals() {
        for mode in [MatchMode.practice, .tutorial, .magicChess] {
            let s = summary(winner: nil, mode: mode, blue: [20], red: [])
            let results = MatchMedal.results(in: s)
            XCTAssertEqual(results.count, 1)
            XCTAssertNil(results[1]?.medal)
            XCTAssertNil(results[1]?.rating)
            XCTAssertEqual(results[1]?.ratingText, "—")
        }
        XCTAssertTrue(MatchMedal.isAwarded(in: .standard))
        XCTAssertTrue(MatchMedal.isAwarded(in: .ranked))
        XCTAssertTrue(MatchMedal.isAwarded(in: .spectate))
    }

    func testNamesAndConditions() {
        let names = MatchMedal.allCases.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(MatchMedal.allCases.allSatisfy { !$0.condition.isEmpty })
        XCTAssertEqual(MatchMedal.bronze.condition, L("評価 3.0〜3.4", "Rating 3.0–3.4"))
        XCTAssertEqual(MatchMedal.silver.condition, L("評価 3.5〜7.0", "Rating 3.5–7.0"))
        XCTAssertEqual(MatchMedal.supreme.name, L("ウルトラ勲章", "Supreme Medal"))
        XCTAssertEqual(MatchMedal.gold.condition, L("評価 7.1〜10.0", "Rating 7.1–10.0"))
        XCTAssertEqual(MatchMedal.supreme.condition, L("評価 10.1 以上", "Rating 10.1+"))
        XCTAssertEqual(MatchMedal.allCases.filter(\.isMVP), [.mvp, .supremeMVP, .mvpLoss])
        XCTAssertEqual(MatchMedalResult(rating: 8.25, medal: .gold).ratingText, String(format: "%.1f", 8.25))
    }

    /// チームの栄誉（2.2.16）: 1 人に 1 つ、まだ称号の無い人のうちその成績がいちばんの人へ。成績の無い人は「チームの力」。
    func testTeamHonorGivesEachPlayerOneTitle() {
        func p(_ id: EntityID, dmg: Double = 0, taken: Double = 0, kills: Int = 0, assists: Int = 0) -> PlayerSummary {
            var sc = HeroScore()
            sc.damageToHeroes = dmg
            sc.damageTaken = taken
            sc.kills = kills
            sc.assists = assists
            return PlayerSummary(entityID: id, team: .blue, heroID: "H027", displayName: "P\(id)", isHuman: id == 1, position: .mid,
                                 level: 10, items: [], score: sc, mvpScore: Double(10 - id), grade: "B", isMVP: false)
        }
        let players = [p(1, dmg: 9000, kills: 9), p(2, taken: 12000), p(3, kills: 5), p(4, assists: 12), p(5)]
        let s = MatchSummary(mode: .ranked, seed: 1, winner: .blue, endReason: .coreDestroyed, duration: 600, humanTeam: .blue,
                             players: players, teamKills: [14, 3, 0], towersDestroyed: [5, 1, 0])
        let t = TeamHonor.titles(team: .blue, in: s)
        XCTAssertEqual(t.count, 5)
        XCTAssertEqual(t[1]?.text, L("優れたダメージ", "Great Damage"))
        XCTAssertEqual(t[2]?.text, L("優秀タンク", "Great Tank"))
        XCTAssertEqual(t[3]?.text, L("即キル", "Swift Kills"), "1 人に 1 つ（キルが最多の P1 はもう称号がある）")
        XCTAssertEqual(t[4]?.text, L("優れた封鎖", "Great Lockdown"))
        XCTAssertEqual(t[5]?.text, L("チームの力", "Team Player"))
    }

    func testQuickChatIsFixedPhrasesOnly() {
        let texts = ResultQuickChat.allCases.map(\.text)
        XCTAssertEqual(texts.count, 4)
        XCTAssertEqual(Set(texts).count, texts.count)
        XCTAssertTrue(ResultQuickChat.allCases.allSatisfy { !$0.text.isEmpty && !$0.reply.isEmpty && !$0.symbol.isEmpty })
        XCTAssertEqual(Set(ResultQuickChat.allCases.map(\.id)).count, ResultQuickChat.allCases.count)
    }
}
