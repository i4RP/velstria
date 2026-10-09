import XCTest
@testable import VelstriaCore

/// ボット同士の試合を最後まで回す統合テスト（DESIGN §10）。
/// 長時間のため Release で実行する: swift test -c release --filter BotMatchTests
final class BotMatchTests: XCTestCase {
    /// 3 シード × Normal / Hard + Easy 1 試合。
    static let seeds: [UInt64] = [1, 6, 11]
    static let easySeed: UInt64 = 4

    func testFullBotMatchesEndByCoreDestruction() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter BotMatchTests")
        #else
        var reports: [BotMatchReport] = []
        for seed in Self.seeds {
            for difficulty in [Difficulty.normal, .hard] {
                reports.append(BotMatchReport.run("seed \(seed) \(difficulty)",
                                                  config: MatchFactory.botMatch(difficulty: difficulty, seed: seed)))
            }
        }
        reports.append(BotMatchReport.run("seed \(Self.easySeed) easy",
                                          config: MatchFactory.botMatch(difficulty: .easy, seed: Self.easySeed)))
        print(BotMatchReport.tableHeader())
        for r in reports { print(r.tableRow) }
        for r in reports {
            print(r.label)
            for line in r.heroLines { print(line) }
            check(r, requireKills: true)
        }
        #endif
    }

    /// 通常戦（人間 1 人 + AI 9 人）で人間が泉に立ったまま何もしない場合も、ボットは正常に試合を進める。
    func testStandardMatchWithIdleHumanInFountain() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter BotMatchTests")
        #else
        let cfg = MatchFactory.standardMatch(humanHeroID: "H003", humanName: "Idle", seed: 5)
        let r = BotMatchReport.run("standard idle human", config: cfg)
        print(BotMatchReport.tableHeader())
        print(r.tableRow)
        for line in r.heroLines { print(line) }
        check(r, requireKills: false)
        let human = r.heroes.first { !$0.isBot }
        XCTAssertNotNil(human)
        XCTAssertEqual(human?.moved ?? -1, 0, accuracy: 1e-9, "the idle human hero must stay where it spawned")
        XCTAssertEqual(human?.finalItems, 0, "bots must not shop for the human")
        #endif
    }

    /// 同じ設定・入力なら同じ試合になる（リプレイで完全に再現できる）。
    func testBotMatchReplayIsDeterministic() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter BotMatchTests")
        #else
        let cfg = MatchFactory.standardMatch(humanHeroID: "H002", humanName: "Rec", humanPosition: .top,
                                             allyDifficulty: .hard, enemyDifficulty: .normal, seed: 8)
        let sim = Simulation(config: cfg)
        let recorder = ReplayRecorder(config: cfg)
        sim.recorder = recorder
        let human = sim.state.humanHeroID!
        let limit = 7 * 60 * 30
        while sim.state.tick < limit && !sim.isEnded {
            var cmds: [HeroCommand] = []
            let tick = sim.state.tick + 1
            // 人間は開始直後に少し歩いて泉へ戻り、買い物だけする
            if tick == 30 { cmds.append(HeroCommand(heroID: human, command: .moveTo(point: Vec2(1500, 1100)))) }
            if tick == 400 { cmds.append(HeroCommand(heroID: human, command: .moveTo(point: Vec2(700, 700)))) }
            if tick == 2700 { cmds.append(HeroCommand(heroID: human, command: .buyItem(itemID: "EQ133"))) }
            sim.step(commands: cmds)
        }
        let player = ReplayPlayer(data: recorder.finish(summary: nil))
        player.seek(toTick: sim.state.tick)
        XCTAssertEqual(player.state.tick, sim.state.tick)
        XCTAssertEqual(player.state.stateHash(), sim.state.stateHash())
        XCTAssertEqual(player.state.bots, sim.state.bots)

        // ボットだけの試合も 2 回回して一致
        let a = Simulation(config: MatchFactory.botMatch(difficulty: .hard, seed: 31))
        let b = Simulation(config: MatchFactory.botMatch(difficulty: .hard, seed: 31))
        a.runHeadless(maxTime: 9 * 60)
        b.runHeadless(maxTime: 9 * 60)
        XCTAssertEqual(a.state.stateHash(), b.state.stateHash())
        XCTAssertEqual(a.state.bots, b.state.bots)
        XCTAssertEqual(a.state.rng, b.state.rng)
        #endif
    }

    /// 試合の要件（DESIGN §3 の目標時間 + ボットの健全性）。
    func check(_ r: BotMatchReport, requireKills: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.endReason, .coreDestroyed, "\(r.label) must end by core destruction", file: file, line: line)
        XCTAssertGreaterThanOrEqual(r.duration, 8 * 60, "\(r.label) too short", file: file, line: line)
        XCTAssertLessThanOrEqual(r.duration, 30 * 60, "\(r.label) too long", file: file, line: line)
        for h in r.heroes where h.isBot {
            XCTAssertGreaterThanOrEqual(h.movedPerMinute, 300, "\(r.label) \(h.heroID) stuck", file: file, line: line)
            XCTAssertGreaterThanOrEqual(h.itemsAt12, 1, "\(r.label) \(h.heroID) bought nothing by 12:00",
                                        file: file, line: line)
            XCTAssertGreaterThanOrEqual(h.levelAt12, 5, "\(r.label) \(h.heroID) under-levelled", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(r.avgLevelAt12, 9, "\(r.label) average level at 12:00", file: file, line: line)
        XCTAssertGreaterThanOrEqual(r.itemsAt12, 2, "\(r.label) average items at 12:00", file: file, line: line)
        if requireKills {
            XCTAssertGreaterThan(r.kills[0], 0, "\(r.label) blue never scored a kill", file: file, line: line)
            XCTAssertGreaterThan(r.kills[1], 0, "\(r.label) red never scored a kill", file: file, line: line)
        }
    }
}
