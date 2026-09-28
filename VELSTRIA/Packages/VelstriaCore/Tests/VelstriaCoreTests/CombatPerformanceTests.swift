import XCTest
@testable import VelstriaCore

/// 全体試合での決定論と tick 予算（Release で `swift test -c release --filter CombatPerformanceTests`）。
final class CombatPerformanceTests: XCTestCase {

    func testFullMatchEventsAreDeterministic() {
        let cfg = MatchFactory.botMatch(seed: 99)
        let a = Simulation(config: cfg)
        let b = Simulation(config: cfg)
        var eventsA: [SimEvent] = []
        var eventsB: [SimEvent] = []
        a.runHeadless(maxTime: 70) { eventsA += $0 }
        b.runHeadless(maxTime: 70) { eventsB += $0 }
        XCTAssertEqual(eventsA, eventsB)
        XCTAssertEqual(a.state.rng, b.state.rng)
        XCTAssertTrue(eventsA.contains { if case .damage = $0 { return true } else { return false } })
        // HP は常に 0...最大
        for u in a.state.units {
            XCTAssertGreaterThanOrEqual(u.hp, 0)
            XCTAssertLessThanOrEqual(u.hp, u.stats.maxHP + 1e-6)
        }
    }

    func testFullMatchTickBudget() throws {
        #if DEBUG
        throw XCTSkip("tick 予算は Release でのみ計測する（swift test -c release --filter CombatPerformanceTests）")
        #else
        let sim = Simulation(config: MatchFactory.botMatch(seed: 11))
        sim.runHeadless(maxTime: 60)
        let startTick = sim.state.tick
        let start = DispatchTime.now().uptimeNanoseconds
        sim.runHeadless(maxTime: 600)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let ticks = max(1, sim.state.tick - startTick)
        let perTick = elapsed / Double(ticks)
        print("CombatPerformanceTests: \(ticks) ticks, \(String(format: "%.3f", perTick)) ms/tick, units=\(sim.state.units.count)")
        XCTAssertLessThan(perTick, 1.0)
        #endif
    }
}
