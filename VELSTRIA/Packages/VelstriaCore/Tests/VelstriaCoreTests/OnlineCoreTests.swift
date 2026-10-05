import XCTest
@testable import VelstriaCore

/// オンライン対戦の土台: 操作者の切り替えコマンド・スナップショットからの復元・複数人間の構成。
final class OnlineCoreTests: XCTestCase {
    func testOnlineMatchSeatsMapToPlayerIndices() {
        let humans = [
            OnlineHumanSlot(team: .blue, position: .mid, heroID: "H001", displayName: "A"),
            OnlineHumanSlot(team: .red, position: .carry, heroID: "H002", displayName: "B"),
        ]
        let config = MatchFactory.onlineMatch(humans: humans, seed: 7)
        XCTAssertEqual(config.mode, .online)
        XCTAssertEqual(config.players.count, 10)
        let a = MatchFactory.onlineSeatIndex(team: .blue, position: .mid)
        let b = MatchFactory.onlineSeatIndex(team: .red, position: .carry)
        XCTAssertEqual(config.players[a].heroID, "H001")
        XCTAssertEqual(config.players[a].controller, .human)
        XCTAssertEqual(config.players[b].heroID, "H002")
        XCTAssertEqual(config.players[b].controller, .human)
        XCTAssertEqual(config.players.filter { $0.controller == .human }.count, 2)
        // AI は人間のピックを避け、ヒーローは重複しない
        XCTAssertEqual(Set(config.players.map(\.heroID)).count, 10)
        for (i, p) in config.players.enumerated() {
            XCTAssertEqual(MatchFactory.onlineSeatIndex(team: p.team, position: p.position), i)
            XCTAssertEqual(MatchFactory.onlineSeat(i)?.team, p.team)
            XCTAssertEqual(MatchFactory.onlineSeat(i)?.position, p.position)
        }
        // 同じ構成は同じシードで再現する
        XCTAssertEqual(MatchFactory.onlineMatch(humans: humans, seed: 7), config)
        XCTAssertNil(MatchFactory.onlineSeat(10))
        XCTAssertNil(MatchFactory.onlineSeat(-1))
    }

    func testHeroesSpawnInSeatOrderAndBotsSkipHumans() {
        let humans = [
            OnlineHumanSlot(team: .blue, position: .mid, heroID: "H001", displayName: "A"),
            OnlineHumanSlot(team: .red, position: .carry, heroID: "H002", displayName: "B"),
        ]
        let config = MatchFactory.onlineMatch(humans: humans, seed: 11)
        let sim = Simulation(config: config)
        let heroes = sim.state.heroIndices
        XCTAssertEqual(heroes.count, 10)
        for (seat, i) in heroes.enumerated() {
            XCTAssertEqual(sim.state.units[i].hero?.heroID, config.players[seat].heroID)
            XCTAssertEqual(sim.state.units[i].hero?.controller, config.players[seat].controller)
        }
        // 人間 2 人は AI の入力なしでは動かない（開始位置のまま）
        let redHuman = heroes[MatchFactory.onlineSeatIndex(team: .red, position: .carry)]
        let start = sim.state.units[redHuman].pos
        for _ in 0..<90 { sim.step() }
        XCTAssertEqual(sim.state.units[redHuman].pos, start)
    }

    func testSetControllerHandsHeroToBotsAndBack() {
        let humans = [OnlineHumanSlot(team: .red, position: .mid, heroID: "H001", displayName: "A")]
        let config = MatchFactory.onlineMatch(humans: humans, seed: 3)
        let sim = Simulation(config: config)
        let seat = MatchFactory.onlineSeatIndex(team: .red, position: .mid)
        let heroIndex = sim.state.heroIndices[seat]
        let heroID = sim.state.units[heroIndex].id
        let start = sim.state.units[heroIndex].pos

        for _ in 0..<60 { sim.step() }
        XCTAssertEqual(sim.state.units[heroIndex].pos, start, "人間の枠は入力がなければ動かない")

        sim.step(commands: [HeroCommand(heroID: heroID, command: .setController(.bot))])
        XCTAssertEqual(sim.state.units[heroIndex].hero?.controller, .bot)
        for _ in 0..<300 { sim.step() }
        XCTAssertNotEqual(sim.state.units[heroIndex].pos, start, "AI に引き継がれると動き出す")

        sim.step(commands: [HeroCommand(heroID: heroID, command: .setController(.human))])
        XCTAssertEqual(sim.state.units[heroIndex].hero?.controller, .human)
        // 人間に戻すと AI は操作しない（移動意図を出さない）: 停止後の位置が変わらない
        sim.step(commands: [HeroCommand(heroID: heroID, command: .stop)])
        let stopped = sim.state.units[heroIndex].pos
        for _ in 0..<60 { sim.step() }
        XCTAssertEqual(sim.state.units[heroIndex].pos, stopped)
    }

    func testRestoreFromSnapshotContinuesIdentically() {
        let humans = [OnlineHumanSlot(team: .blue, position: .mid, heroID: "H001", displayName: "A")]
        let config = MatchFactory.onlineMatch(humans: humans, seed: 5)
        let host = Simulation(config: config)
        let client = Simulation(config: config)
        let heroID = host.state.units[host.state.heroIndices[MatchFactory.onlineSeatIndex(team: .blue, position: .mid)]].id
        let inputs: (Int) -> [HeroCommand] = { tick in
            tick % 20 == 0 ? [HeroCommand(heroID: heroID, command: .move(direction: Vec2(1, 0.3)))] : []
        }
        for t in 1...200 {
            host.step(commands: inputs(t))
            client.step(commands: inputs(t))
        }
        XCTAssertEqual(host.state.stateHash(), client.state.stateHash())

        // クライアントがずれた（適用し損ねた入力）→ ホストのスナップショットで置き換え → 以後は一致し続ける
        client.step(commands: [HeroCommand(heroID: heroID, command: .move(direction: Vec2(-1, 0)))])
        host.step()
        XCTAssertNotEqual(host.state.stateHash(), client.state.stateHash())
        let snapshot = try! JSONDecoder().decode(SimState.self, from: JSONEncoder().encode(host.state))
        client.restore(from: snapshot)
        XCTAssertEqual(host.state.stateHash(), client.state.stateHash())
        XCTAssertEqual(client.state.index(of: heroID), host.state.index(of: heroID), "索引が復元される")
        for t in 1...300 {
            host.step(commands: inputs(t))
            client.step(commands: inputs(t))
            XCTAssertEqual(host.state.stateHash(), client.state.stateHash(), "tick \(host.state.tick)")
        }
    }

    func testSurrenderEnabledOnline() {
        let config = MatchFactory.onlineMatch(humans: [OnlineHumanSlot(team: .blue, position: .mid, heroID: "H001", displayName: "A")], seed: 1)
        let sim = Simulation(config: config)
        XCTAssertTrue(MatchFlowSystem.surrenderEnabled(sim.ctx))
    }
}
