import XCTest
@testable import VelstriaCore

/// ボットの意思決定コスト（Release で `swift test -c release --filter BotPerformanceTests`）。
final class BotPerformanceTests: XCTestCase {
    /// 1 回の意思決定あたり 0.3 ms 以下（償却）、試合全体で 1 tick 1 ms 未満。
    func testDecisionCostWithinBudget() throws {
        #if DEBUG
        throw XCTSkip("Release でのみ計測する（swift test -c release --filter BotPerformanceTests）")
        #else
        let sim = Simulation(config: MatchFactory.botMatch(difficulty: .hard, seed: 13))
        var botNs: UInt64 = 0
        var stepNs: UInt64 = 0
        var decisions = 0
        var ticks = 0
        while !sim.isEnded && sim.state.time < 15 * 60 {
            // 状態の写しに対して生成だけを計測する（BotAI は units を書き換えないため写しの複製は起きない）
            var copy = sim.state
            copy.tick += 1
            copy.time = Double(copy.tick) * Balance.dt
            let before = copy.bots.decisions
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = BotAI.generateCommands(&copy, sim.ctx)
            botNs += DispatchTime.now().uptimeNanoseconds - t0
            decisions += copy.bots.decisions - before
            let t1 = DispatchTime.now().uptimeNanoseconds
            sim.step()
            stepNs += DispatchTime.now().uptimeNanoseconds - t1
            ticks += 1
        }
        let perDecision = Double(botNs) / 1e6 / Double(max(1, decisions))
        let perTick = Double(stepNs) / 1e6 / Double(max(1, ticks))
        print(String(format: "BotPerformanceTests: %d decisions, %.4f ms/decision, bot %.4f ms/tick, full step %.3f ms/tick",
                     decisions, perDecision, Double(botNs) / 1e6 / Double(max(1, ticks)), perTick))
        XCTAssertGreaterThan(decisions, ticks)
        XCTAssertLessThan(perDecision, 0.3)
        XCTAssertLessThan(perTick, 1.0)
        #endif
    }
}
