import XCTest
@testable import VelstriaCore

/// リプレイ（記録 → 再生で同一状態）と状態ハッシュ。
final class EconomyReplayTests: XCTestCase {
    /// 人間入力の台本（tick → コマンド）。移動・攻撃・購入・スキル・帰還を含む。
    private func scriptedCommands(tick: Int, hero: EntityID) -> [HeroCommand] {
        var out: [HeroCommand] = []
        func add(_ c: PlayerCommand) { out.append(HeroCommand(heroID: hero, command: c, sequence: UInt32(tick))) }
        switch tick {
        case 1: add(.buyItem(itemID: "EQ001"))                 // Gold 不足で失敗（失敗も再現されること）
        case 5: add(.move(direction: Vec2(1, 0.5)))
        case 120: add(.moveTo(point: Vec2(3200, 3200)))
        case 710: add(.levelSkill(slot: .skill2))
        case 1300: add(.buyItem(itemID: "EQ005"))            // 序盤の収入で買える価格（340）になってから
        case 1500: add(.move(direction: Vec2(0.3, 1)))
        case 1560: add(.stop)
        case 1900: add(.recall)
        case 2000: add(.sellItem(slotIndex: 0))
        default: break
        }
        if tick >= 600 && tick % 45 == 0 && tick < 1500 { add(.attackNearest(priority: .minionsFirst)) }
        if tick == 900 { add(.moveTo(point: Vec2(5200, 5200))) }
        return out
    }

    private func record(ticks: Int, hashAt checkpoints: [Int]) -> (ReplayData, UInt64, [Int: UInt64]) {
        let cfg = MatchFactory.standardMatch(humanHeroID: "H002", humanName: "Rec", seed: 2024)
        let sim = Simulation(config: cfg)
        let recorder = ReplayRecorder(config: cfg)
        sim.recorder = recorder
        let human = sim.state.humanHeroID!
        var hashes: [Int: UInt64] = [:]
        while sim.state.tick < ticks && !sim.isEnded {
            sim.step(commands: scriptedCommands(tick: sim.state.tick + 1, hero: human))
            if checkpoints.contains(sim.state.tick) { hashes[sim.state.tick] = sim.state.stateHash() }
        }
        return (recorder.finish(summary: ScoreSystem.summary(sim.state)), sim.state.stateHash(), hashes)
    }

    func testReplayReproducesRecordedMatch() throws {
        let (data, finalHash, _) = record(ticks: 2400, hashAt: [])
        XCTAssertEqual(data.finalTick, 2400)
        XCTAssertFalse(data.frames.isEmpty)
        XCTAssertTrue(data.isPlayable)

        // 保存形式（JSON）を経由しても再現できる
        let decoded = try JSONDecoder().decode(ReplayData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded, data)

        let player = ReplayPlayer(data: decoded)
        var purchases = 0
        while !player.isFinished {
            for e in player.stepOnce() {
                if case .itemPurchased = e { purchases += 1 }
            }
        }
        XCTAssertEqual(player.currentTick, 2400)
        XCTAssertEqual(player.state.stateHash(), finalHash)
        XCTAssertEqual(ScoreSystem.summary(player.state), data.summary)
        XCTAssertGreaterThanOrEqual(purchases, 1)
        XCTAssertTrue(player.stepOnce().isEmpty)
        XCTAssertEqual(player.progress, 1)
    }

    func testReplayWithoutInputsDiverges() {
        let (data, finalHash, _) = record(ticks: 900, hashAt: [])
        var empty = data
        empty.frames = []
        let player = ReplayPlayer(data: empty)
        while !player.isFinished { player.stepOnce() }
        XCTAssertNotEqual(player.state.stateHash(), finalHash)
    }

    func testSeekForwardAndBackward() {
        let (data, _, hashes) = record(ticks: 1500, hashAt: [600, 1200])
        let player = ReplayPlayer(data: data)
        player.seek(toTick: 1200)
        XCTAssertEqual(player.currentTick, 1200)
        XCTAssertEqual(player.state.stateHash(), hashes[1200])
        player.seek(toTick: 600)
        XCTAssertEqual(player.currentTick, 600)
        XCTAssertEqual(player.state.stateHash(), hashes[600])
        player.seek(toTick: 99_999)
        XCTAssertEqual(player.currentTick, 1500)
        XCTAssertTrue(player.isFinished)
    }

    func testStateHashIsSensitiveAndStable() {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 8))
        sim.step()
        var s = sim.state
        let h = s.stateHash()
        XCTAssertEqual(h, sim.state.stateHash())
        s.units[0].hp -= 1
        XCTAssertNotEqual(s.stateHash(), h)
        s = sim.state
        s.units[3].pos.x += 0.5
        XCTAssertNotEqual(s.stateHash(), h)
        s = sim.state
        s.units[s.heroIndices[0]].hero!.gold += 1
        XCTAssertNotEqual(s.stateHash(), h)
    }
}
