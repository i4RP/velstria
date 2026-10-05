import XCTest
@testable import VelstriaCore

/// マジックチェス（簡易オートバトラー）の検証。
final class MagicChessTests: XCTestCase {
    func testCombatDeterministicAndStrongerWins() {
        let master = MasterData.shared
        let hero = master.heroes[0].heroID
        let strong = [BoardUnit(instanceID: 1, heroID: hero, star: 3, cell: GridCell(col: 0, row: 0))]
        let weak = [BoardUnit(instanceID: 2, heroID: hero, star: 1, cell: GridCell(col: 0, row: 0))]
        let r1 = AutoCombatResolver.resolve(boardA: strong, boardB: weak, aID: 0, bID: 1, seed: 99, master: master)
        let r2 = AutoCombatResolver.resolve(boardA: strong, boardB: weak, aID: 0, bID: 1, seed: 99, master: master)
        XCTAssertEqual(r1, r2, "同じ入力・シードなら同じ結果")
        XCTAssertEqual(r1.winner, 0, "高い星の盤が勝つ")
    }

    func testEmptyBoardsDraw() {
        let r = AutoCombatResolver.resolve(boardA: [], boardB: [], aID: 0, bID: 1, seed: 1)
        XCTAssertNil(r.winner)
    }

    func testFightProducesFramesForHuman() {
        let master = MasterData.shared
        let hero = master.heroes[0].heroID
        let a = [BoardUnit(instanceID: 1, heroID: hero, star: 1, cell: GridCell(col: 0, row: 0))]
        let b = [BoardUnit(instanceID: 2, heroID: hero, star: 1, cell: GridCell(col: 1, row: 0))]
        let outcome = AutoCombatResolver.fight(boardA: a, boardB: b, aID: 0, bID: 1, seed: 5, master: master)
        XCTAssertFalse(outcome.frames.isEmpty)
    }

    func testFullGameTerminatesWithUniquePlacements() {
        let cfg = MagicChessConfig(seed: 1234, humanName: "T", aiDifficulty: .normal)
        let sim = MagicChessSim(config: cfg)
        sim.runHeadless()
        XCTAssertEqual(sim.state.phase, .gameOver)
        XCTAssertNotNil(sim.state.winner)
        if let w = sim.state.winner, let wp = sim.state.player(w)?.placement {
            XCTAssertEqual(wp, 1, "勝者は 1 位")
        }
        // 脱落者の順位は一意（2 位以降が重複しない）。
        let eliminated = sim.state.players.compactMap { $0.placement }
        XCTAssertEqual(Set(eliminated).count, eliminated.count, "順位は一意")
        XCTAssertEqual(sim.state.aliveCount, 1)
    }

    func testFullGameDeterministic() {
        let cfg = MagicChessConfig(seed: 555, humanName: "T", aiDifficulty: .hard)
        let a = MagicChessSim(config: cfg); a.runHeadless()
        let b = MagicChessSim(config: cfg); b.runHeadless()
        XCTAssertEqual(a.state.winner, b.state.winner)
        XCTAssertEqual(a.state.standings.map(\.id), b.state.standings.map(\.id))
        XCTAssertEqual(a.state.round, b.state.round)
    }

    func testSynergyCounting() {
        let master = MasterData.shared
        // 同一ロールのユニーク 2 体でシナジー第1段階になる。
        let rangers = master.heroes.filter { $0.role == .ranger }.prefix(2).map(\.heroID)
        guard rangers.count == 2 else { throw XCTSkip("レンジャーが 2 体未満") }
        let board = [
            BoardUnit(instanceID: 1, heroID: rangers[0], star: 1, cell: GridCell(col: 0, row: 0)),
            BoardUnit(instanceID: 2, heroID: rangers[1], star: 1, cell: GridCell(col: 1, row: 0)),
        ]
        let tiers = MagicChessSynergy.tiers(board: board, master: master)
        let ranger = tiers.first { $0.role == .ranger }
        XCTAssertEqual(ranger?.count, 2)
        XCTAssertEqual(ranger?.tier, 1)
    }

    func testBuyAndCombineUpgradesStar() {
        // 同名 3 体を buy で揃えると★2 に合成される。
        let cfg = MagicChessConfig(seed: 1, humanName: "T")
        var state = MagicChessState(config: cfg, players: [MChPlayer(id: 0, isHuman: true, displayName: "T",
                                                                     gold: 99, hp: 100)])
        let master = MasterData.shared
        let hero = master.heroes[0].heroID
        // ショップに同名を 3 枠用意して購入。
        state.players[0].shop = (0..<3).map { ShopUnit(slot: $0, heroID: hero, cost: 1) }
        for slot in 0..<3 { _ = MagicChessSim.buy(&state, playerIndex: 0, slot: slot, master: master) }
        let twoStars = state.players[0].allUnits.filter { $0.heroID == hero && $0.star == 2 }
        XCTAssertEqual(twoStars.count, 1, "3 体で★2 が 1 体できる")
        XCTAssertTrue(state.players[0].allUnits.filter { $0.heroID == hero && $0.star == 1 }.isEmpty)
    }
}
