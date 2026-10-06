import XCTest
@testable import VelstriaCore

/// 観戦の試合構成（マップ・チーム別難易度・枠の固定・最大時間）。botMatch の出力は変えない。
final class MatchFactorySpectateTests: XCTestCase {
    private let master = MasterData.shared

    func testDefaultOptionsMatchBotMatchExactly() {
        // UI テストのシード 20261001 を含め、指定なし・同じ難易度なら botMatch と同じ構成
        for seed: UInt64 in [20261001, 1, 42, 0xFFFF_FFFF] {
            for d in Difficulty.allCases {
                let options = SpectateMatchOptions(blueDifficulty: d, redDifficulty: d)
                XCTAssertEqual(MatchFactory.spectateMatch(options: options, seed: seed),
                               MatchFactory.botMatch(difficulty: d, seed: seed), "seed \(seed) \(d)")
            }
        }
    }

    func testPerSideDifficultyKeepsRosters() {
        let a = MatchFactory.spectateMatch(options: SpectateMatchOptions(blueDifficulty: .easy, redDifficulty: .hard), seed: 9)
        let b = MatchFactory.botMatch(difficulty: .normal, seed: 9)
        XCTAssertEqual(a.players.map(\.heroID), b.players.map(\.heroID), "難易度だけ変えても編成は同じ")
        XCTAssertTrue(a.players.filter { $0.team == .blue }.allSatisfy { $0.botDifficulty == .easy })
        XCTAssertTrue(a.players.filter { $0.team == .red }.allSatisfy { $0.botDifficulty == .hard })
        XCTAssertTrue(a.players.allSatisfy { $0.controller == .bot })
        XCTAssertEqual(a.mode, .spectate)
    }

    func testBrawlMapIsAllBotBrawl() {
        let cfg = MatchFactory.spectateMatch(options: SpectateMatchOptions(map: .brawl), seed: 5)
        XCTAssertEqual(cfg.mode, .brawl, "マップは mode から導出するので乱闘は mode .brawl")
        XCTAssertEqual(MapDefinition.map(for: cfg.mode), MapDefinition.brawl)
        XCTAssertEqual(cfg.players.count, 10)
        XCTAssertNil(cfg.humanSlot)
        XCTAssertFalse(cfg.players.contains { $0.spells.contains("BS05") }, "乱闘は狩猟印を付けない")
        XCTAssertEqual(cfg.maxDuration, 15 * 60)
        XCTAssertEqual(SpectateMap.of(cfg), .brawl)
        XCTAssertEqual(Set(cfg.players.map(\.heroID)).count, 10)
    }

    func testPicksAreFixedAndInvalidPicksIgnored() {
        let heroes = master.heroes.map(\.heroID)
        let picks = [
            SpectatePick(team: .blue, position: .mid, heroID: heroes[0]),
            SpectatePick(team: .red, position: .top, heroID: heroes[1]),
            // 同じ枠の 2 つ目・同じヒーローの 2 つ目・存在しないヒーロー・中立は無視
            SpectatePick(team: .blue, position: .mid, heroID: heroes[2]),
            SpectatePick(team: .red, position: .support, heroID: heroes[0]),
            SpectatePick(team: .red, position: .carry, heroID: "NOPE"),
            SpectatePick(team: .neutral, position: .jungle, heroID: heroes[3]),
        ]
        let cfg = MatchFactory.spectateMatch(options: SpectateMatchOptions(picks: picks), seed: 77)
        func hero(_ team: Team, _ pos: LanePosition) -> String? {
            cfg.players.first { $0.team == team && $0.position == pos }?.heroID
        }
        XCTAssertEqual(hero(.blue, .mid), heroes[0])
        XCTAssertEqual(hero(.red, .top), heroes[1])
        XCTAssertNotEqual(hero(.red, .support), heroes[0])
        XCTAssertNotEqual(hero(.red, .carry), "NOPE")
        XCTAssertEqual(Set(cfg.players.map(\.heroID)).count, 10, "重複なし")
        XCTAssertEqual(cfg.players.filter { $0.team == .blue }.map(\.position), LanePosition.allCases)
        // 同じ指定・同じシードは同じ構成（決定論）
        XCTAssertEqual(cfg, MatchFactory.spectateMatch(options: SpectateMatchOptions(picks: picks), seed: 77))
    }

    func testMaxDurationIsClampedAndRoundTrips() {
        let custom = MatchFactory.spectateMatch(options: SpectateMatchOptions(maxDuration: 20 * 60), seed: 3)
        XCTAssertEqual(custom.maxDuration, 20 * 60)
        XCTAssertEqual(MatchFactory.spectateMatch(options: SpectateMatchOptions(maxDuration: 1), seed: 3).maxDuration, 5 * 60)
        XCTAssertEqual(MatchFactory.spectateMatch(options: SpectateMatchOptions(maxDuration: .infinity), seed: 3).maxDuration, 40 * 60)

        let options = SpectateMatchOptions(map: .brawl, blueDifficulty: .hard, redDifficulty: .easy, maxDuration: 25 * 60)
        let cfg = MatchFactory.spectateMatch(options: options, seed: 11)
        let back = MatchFactory.spectateOptions(from: cfg)
        XCTAssertEqual(back.map, .brawl)
        XCTAssertEqual(back.blueDifficulty, .hard)
        XCTAssertEqual(back.redDifficulty, .easy)
        XCTAssertEqual(back.maxDuration, 25 * 60)
        XCTAssertTrue(back.picks.isEmpty)
        XCTAssertNil(MatchFactory.spectateOptions(from: MatchFactory.botMatch(seed: 1)).maxDuration, "既定の時間は nil で戻る")
    }

    func testOptionsCodableRoundTrip() throws {
        let options = SpectateMatchOptions(map: .brawl, blueDifficulty: .easy, redDifficulty: .hard,
                                           picks: [SpectatePick(team: .red, position: .jungle, heroID: "H002")], maxDuration: 900)
        let data = try JSONEncoder().encode(options)
        XCTAssertEqual(try JSONDecoder().decode(SpectateMatchOptions.self, from: data), options)
    }

    /// 乱闘の全員 AI でもシミュレーションが進む（構成が sim の前提を満たす）。
    func testBrawlSpectateRunsDeterministically() {
        let cfg = MatchFactory.spectateMatch(options: SpectateMatchOptions(map: .brawl), seed: 21)
        let a = Simulation(config: cfg, map: MapDefinition.map(for: cfg.mode))
        let b = Simulation(config: cfg, map: MapDefinition.map(for: cfg.mode))
        for _ in 0..<120 {
            a.step()
            b.step()
        }
        XCTAssertEqual(a.state.stateHash(), b.state.stateHash())
        XCTAssertEqual(a.state.heroIndices.count, 10)
    }
}
