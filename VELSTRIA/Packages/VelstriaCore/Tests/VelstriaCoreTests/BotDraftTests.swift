import XCTest
@testable import VelstriaCore

/// AI ドラフト（ピック / BAN）と、それを使う MatchFactory。
final class BotDraftTests: XCTestCase {
    let master = MasterData.shared
    var allIDs: [String] { master.heroes.map(\.heroID) }

    func testPickFitsPositionRoles() {
        for position in LanePosition.allCases {
            for seed in UInt64(0)..<20 {
                var rng = SplitMix64(seed: seed)
                let id = DraftAI.draftPick(available: allIDs, allyPicks: [], enemyPicks: [], position: position, rng: &rng)
                let role = master.hero(id)!.role
                XCTAssertTrue(MatchFactory.preferredRoles(for: position).contains(role), "\(position) got \(role)")
            }
        }
    }

    func testPickAvoidsDuplicatingAllyRolesWhenAlternativesExist() {
        // 味方にアサシンが 2 人居るなら、ジャングルでもデュエリストを選ぶ
        let assassins = master.heroes(role: .assassin).map(\.heroID)
        var rng = SplitMix64(seed: 3)
        let available = allIDs.filter { !assassins.prefix(2).contains($0) }
        let id = DraftAI.draftPick(available: available, allyPicks: Array(assassins.prefix(2)), enemyPicks: [],
                                   position: .jungle, rng: &rng)
        XCTAssertEqual(master.hero(id)?.role, .duelist)
    }

    func testPickIsDeterministicAndOnlyFromAvailable() {
        let available = Array(allIDs.shuffledDeterministically(seed: 11).prefix(9))
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
        let x = DraftAI.draftPick(available: available, allyPicks: [], enemyPicks: [], position: .mid, rng: &a)
        let y = DraftAI.draftPick(available: available, allyPicks: [], enemyPicks: [], position: .mid, rng: &b)
        XCTAssertEqual(x, y)
        XCTAssertEqual(a, b)
        XCTAssertTrue(available.contains(x))
    }

    func testBanChoosesAvailableHeroAndEmptyInputReturnsEmpty() {
        var rng = SplitMix64(seed: 7)
        let picks = ["H003", "H004"]
        let available = allIDs.filter { !picks.contains($0) }
        let ban = DraftAI.draftBan(available: available, allyPicks: picks, enemyPicks: [], rng: &rng)
        XCTAssertTrue(available.contains(ban))
        XCTAssertEqual(DraftAI.draftPick(available: [], allyPicks: [], enemyPicks: [], position: .top, rng: &rng), "")
        XCTAssertEqual(DraftAI.draftBan(available: [], allyPicks: [], enemyPicks: [], rng: &rng), "")
    }

    func testHeroPowerIsRelativeWithinRole() {
        for role in Role.allCases {
            let values = master.heroes(role: role).map { DraftAI.heroPower($0) }
            XCTAssertLessThanOrEqual(values.max() ?? 0, 1)
            XCTAssertGreaterThanOrEqual(values.min() ?? 0, -1)
            // 役割内の相対評価なので平均はほぼ 0
            XCTAssertEqual(values.reduce(0, +) / Double(max(1, values.count)), 0, accuracy: 0.35)
        }
    }

    func testBotMatchDraftsTenUniqueHeroesWithFittingRolesAndSpells() {
        for seed in UInt64(1)...12 {
            let cfg = MatchFactory.botMatch(difficulty: .hard, seed: seed)
            XCTAssertEqual(cfg.players.count, 10)
            XCTAssertEqual(Set(cfg.players.map(\.heroID)).count, 10)
            for p in cfg.players {
                XCTAssertEqual(p.controller, .bot)
                XCTAssertEqual(p.botDifficulty, .hard)
                XCTAssertTrue(MatchFactory.preferredRoles(for: p.position).contains(master.hero(p.heroID)!.role))
                XCTAssertEqual(p.spells, MatchFactory.defaultSpells(for: p.position))
            }
            XCTAssertTrue(cfg.players.filter { $0.position == .jungle }.allSatisfy { $0.spells.contains("BS05") })
        }
        XCTAssertEqual(MatchFactory.botMatch(seed: 5), MatchFactory.botMatch(seed: 5))
    }

    func testStandardMatchRespectsHumanAndBans() {
        let banned = ["H001", "H002", "H005", "H006"]
        let cfg = MatchFactory.standardMatch(mode: .ranked, humanHeroID: "H004", humanName: "Me", humanTeam: .red,
                                             allyDifficulty: .easy, enemyDifficulty: .hard, banned: banned, seed: 77)
        XCTAssertEqual(cfg.players.count, 10)
        XCTAssertEqual(Set(cfg.players.map(\.heroID)).count, 10)
        XCTAssertTrue(cfg.players.allSatisfy { !banned.contains($0.heroID) })
        let human = cfg.players.filter { $0.controller == .human }
        XCTAssertEqual(human.map(\.heroID), ["H004"])
        XCTAssertEqual(human.first?.team, .red)
        XCTAssertEqual(human.first?.position, .mid)
        for p in cfg.players where p.controller == .bot {
            XCTAssertEqual(p.botDifficulty, p.team == .red ? .easy : .hard)
        }
    }
}

private extension Array {
    /// テスト用の決定論的な並べ替え。
    func shuffledDeterministically(seed: UInt64) -> [Element] {
        var rng = SplitMix64(seed: seed)
        var a = self
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            a.swapAt(i, rng.nextInt(in: 0...i))
        }
        return a
    }
}
