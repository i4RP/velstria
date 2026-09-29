import XCTest
@testable import VelstriaCore

/// 降参投票・時間切れ・MVP/評価（DESIGN §3, §11）。
final class EconomyMatchFlowTests: XCTestCase {
    private func votingFixture(time: Double = 9 * 60) -> EconomyFixture {
        var f = EconomyFixture.standard()
        f.s.time = time
        f.s.tick = Int((time / Balance.dt).rounded())
        f.s.events.removeAll()
        return f
    }

    /// MatchFlowSystem を seconds 秒分回し、発行イベントを返す。
    private func run(_ f: inout EconomyFixture, seconds: Double) -> [SimEvent] {
        var out: [SimEvent] = []
        for _ in 0..<Int((seconds / Balance.dt).rounded()) {
            guard f.s.phase == .playing else { break }
            f.s.tick += 1
            f.s.time = Double(f.s.tick) * Balance.dt
            f.s.events.removeAll()
            MatchFlowSystem.update(&f.s, f.ctx)
            out += f.s.events
        }
        return out
    }

    private func votes(_ ev: [SimEvent]) -> [(yes: Int, no: Int, needed: Int)] {
        ev.compactMap { if case .surrenderVote(_, let y, let n, let need) = $0 { return (y, n, need) } else { return nil } }
    }

    func testSurrenderLockedBefore8Minutes() {
        var f = votingFixture(time: 7 * 60)
        XCTAssertFalse(MatchFlowSystem.canProposeSurrender(f.s, f.ctx, team: .blue))
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: f.human, yes: true)
        XCTAssertNil(f.s.surrender.voteDeadline[0])
        XCTAssertTrue(f.s.events.isEmpty)
    }

    func testBotsRejectWithoutDeficitAndCooldownApplies() {
        var f = votingFixture()
        XCTAssertTrue(MatchFlowSystem.canProposeSurrender(f.s, f.ctx, team: .blue))
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: f.human, yes: true)
        XCTAssertEqual(f.s.surrender.voteDeadline[0] ?? 0, f.s.time + 15, accuracy: 1e-9)
        let first = votes(f.s.events)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].yes, 1)
        XCTAssertEqual(first[0].needed, 3)
        // 人間の再投票は無視
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: f.human, yes: false)
        XCTAssertEqual(f.hero(f.human).surrenderVote, true)

        let ev = run(&f, seconds: 10)
        XCTAssertEqual(f.s.phase, .playing)
        XCTAssertNil(f.s.surrender.voteDeadline[0])
        // 反対 3 で成立不可が確定した時点で打ち切り
        let last = votes(ev).last!
        XCTAssertEqual(last.yes, 1)
        XCTAssertGreaterThanOrEqual(last.no, 3)
        // 3 人目の AI（開始 + 3.5 秒）の反対で確定 → 60 秒 CD
        XCTAssertEqual(f.s.surrender.nextAllowed[0], 9 * 60 + 3.5 + 60, accuracy: 0.05)
        XCTAssertTrue(f.heroes(.blue).allSatisfy { f.hero($0).surrenderVote == nil })
        // CD 中は提案できない
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: f.human, yes: true)
        XCTAssertNil(f.s.surrender.voteDeadline[0])
        // CD 明けに再提案可能
        _ = run(&f, seconds: 61)
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: f.human, yes: true)
        XCTAssertNotNil(f.s.surrender.voteDeadline[0])
    }

    func testSurrenderPassesWithTowerDeficit() {
        var f = votingFixture()
        f.s.teams[Team.red.rawValue].towersDestroyed = 3
        XCTAssertTrue(MatchFlowSystem.botWantsSurrender(f.s, team: .blue))
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: f.human, yes: true)
        let ev = run(&f, seconds: 15)
        XCTAssertEqual(f.s.phase, .ended)
        XCTAssertEqual(f.s.winner, .red)
        XCTAssertEqual(f.s.endReason, .surrender)
        XCTAssertTrue(ev.announcements.contains(.surrenderPassed(team: .blue)))
        XCTAssertTrue(ev.contains(.matchEnded(winner: .red, reason: .surrender)))
        // AI は開始から数秒かけて順に投票する
        XCTAssertGreaterThan(f.s.time, 9 * 60 + 1)
    }

    func testSurrenderPassesWithGoldDeficit() {
        var f = votingFixture()
        f.s.units[f.heroes(.red)[0]].hero!.score.goldEarned = 3000
        XCTAssertTrue(MatchFlowSystem.botWantsSurrender(f.s, team: .blue))
        XCTAssertFalse(MatchFlowSystem.botWantsSurrender(f.s, team: .red))
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: f.human, yes: true)
        _ = run(&f, seconds: 15)
        XCTAssertEqual(f.s.winner, .red)
    }

    func testBotCannotStartVoteAndCannotVoteYesWithoutDeficit() {
        var f = votingFixture()
        let bot = f.heroes(.blue).first { f.hero($0).controller == .bot }!
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: bot, yes: true)
        XCTAssertNil(f.s.surrender.voteDeadline[0])
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: f.human, yes: true)
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: bot, yes: true)
        XCTAssertEqual(f.hero(bot).surrenderVote, false)
    }

    func testVoteExpiresAtDeadline() {
        var f = votingFixture()
        f.s.teams[Team.red.rawValue].towersDestroyed = 3
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: f.human, yes: true)
        // AI を人間扱いにして自動投票を止め、締切まで未投票のままにする（未投票は反対扱い）
        for i in f.heroes(.blue) where i != f.human { f.s.units[i].hero!.controller = .human }
        let ev = run(&f, seconds: 16)
        XCTAssertEqual(f.s.phase, .playing)
        XCTAssertNil(f.s.surrender.voteDeadline[0])
        let last = votes(ev).last!
        XCTAssertEqual(last.yes, 1)
        XCTAssertEqual(last.no, 4)
    }

    func testSurrenderDisabledInPractice() {
        let opts = PracticeOptions()
        var f = EconomyFixture(config: MatchFactory.practiceMatch(humanHeroID: "H001", humanName: "P",
                                                                  options: opts, seed: 2))
        f.s.time = 20 * 60
        MatchFlowSystem.vote(&f.s, f.ctx, heroIndex: f.human, yes: true)
        XCTAssertNil(f.s.surrender.voteDeadline[0])
    }

    func testTimeLimitWinner() {
        var f = EconomyFixture.standard()
        f.s.teams[0].kills = 10
        f.s.teams[1].kills = 3
        f.s.teams[0].towersDestroyed = 2
        f.s.teams[1].towersDestroyed = 4
        XCTAssertEqual(MatchFlowSystem.timeLimitWinner(f.s), .red)
        f.s.teams[1].towersDestroyed = 2
        XCTAssertEqual(MatchFlowSystem.timeLimitWinner(f.s), .blue)
        f.s.teams[1].kills = 10
        XCTAssertNil(MatchFlowSystem.timeLimitWinner(f.s))

        f.s.teams[1].kills = 11
        f.s.time = f.ctx.config.maxDuration
        f.s.events.removeAll()
        MatchFlowSystem.update(&f.s, f.ctx)
        XCTAssertEqual(f.s.phase, .ended)
        XCTAssertEqual(f.s.winner, .red)
        XCTAssertEqual(f.s.endReason, .timeLimit)
        XCTAssertTrue(f.s.events.announcements.contains(.victory(team: .red)))
    }

    // MARK: - MVP・評価

    func testMVPScoreFormula() {
        var sc = HeroScore()
        sc.kills = 5; sc.assists = 4; sc.deaths = 2
        sc.damageToHeroes = 12000; sc.towerDamage = 3000; sc.healingDone = 2000; sc.shieldingDone = 5000
        sc.minionKills = 90; sc.monsterKills = 10
        // 15 + 8 − 3 + 12 + 2 + 1 + 5 = 40（シールド量は数えない）
        XCTAssertEqual(ScoreSystem.mvpScore(sc, won: false), 40, accuracy: 1e-9)
        XCTAssertEqual(ScoreSystem.mvpScore(sc, won: true), 43, accuracy: 1e-9)
    }

    func testGradeThresholds() {
        XCTAssertEqual(ScoreSystem.grade(teamRank: 1, kda: 2.5), "S")
        XCTAssertEqual(ScoreSystem.grade(teamRank: 1, kda: 2.4), "A")
        XCTAssertEqual(ScoreSystem.grade(teamRank: 1, kda: 1.4), "B")
        XCTAssertEqual(ScoreSystem.grade(teamRank: 2, kda: 1.5), "A")
        XCTAssertEqual(ScoreSystem.grade(teamRank: 3, kda: 3.9), "B")
        XCTAssertEqual(ScoreSystem.grade(teamRank: 5, kda: 4), "A")
        XCTAssertEqual(ScoreSystem.grade(teamRank: 3, kda: 0), "B")
        XCTAssertEqual(ScoreSystem.grade(teamRank: 5, kda: 1), "B")
        XCTAssertEqual(ScoreSystem.grade(teamRank: 4, kda: 0.5), "C")
    }

    func testSummaryAssignsMVPAndGrades() {
        var f = EconomyFixture.standard()
        let blue = f.heroes(.blue), red = f.heroes(.red)
        // Red の最高スコアと、勝利ボーナス +3 込みの Blue 1 位が同点になる構成
        f.s.units[red[0]].hero!.score.kills = 8          // 24
        f.s.units[blue[1]].hero!.score.kills = 7         // 21 + 3 = 24 → 同点は ID 昇順
        f.s.units[blue[1]].hero!.score.deaths = 0
        f.s.units[blue[2]].hero!.score.assists = 6       // 12 + 3
        f.s.units[blue[2]].hero!.score.deaths = 2        // −3 → 12, KDA 3
        f.s.units[blue[3]].hero!.score.deaths = 4        // −6 + 3 = −3
        f.s.winner = .blue
        f.s.endReason = .coreDestroyed
        let sum = ScoreSystem.summary(f.s)
        XCTAssertEqual(sum.players.count, 10)
        XCTAssertEqual(sum.players.filter(\.isMVP).count, 1)
        let mvp = sum.mvp!
        XCTAssertEqual(mvp.mvpScore, 24, accuracy: 1e-9)
        XCTAssertEqual(mvp.entityID, min(f.id(blue[1]), f.id(red[0])))
        let b1 = sum.players.first { $0.entityID == f.id(blue[1]) }!
        XCTAssertEqual(b1.grade, "S")              // チーム 1 位・KDA 7
        let b2 = sum.players.first { $0.entityID == f.id(blue[2]) }!
        XCTAssertEqual(b2.grade, "A")              // チーム 2 位・KDA 3（1 位ではないので S にならない）
        let b3 = sum.players.first { $0.entityID == f.id(blue[3]) }!
        XCTAssertEqual(b3.grade, "C")              // 最下位・KDA 0
        XCTAssertEqual(sum.players(of: .blue).first?.entityID, f.id(blue[1]))
        XCTAssertEqual(sum.humanWon, true)
        XCTAssertEqual(sum.endReason, .coreDestroyed)
    }

    func testSummaryIsStableInProgress() {
        let f = EconomyFixture.standard()
        let a = ScoreSystem.summary(f.s)
        let b = ScoreSystem.summary(f.s)
        XCTAssertEqual(a, b)
        XCTAssertNil(a.winner)
        XCTAssertNil(a.humanWon)
        XCTAssertEqual(a.players.filter(\.isMVP).count, 1)
        // 勝者未定なので勝利ボーナスなし
        XCTAssertTrue(a.players.allSatisfy { $0.mvpScore == 0 })
    }
}
