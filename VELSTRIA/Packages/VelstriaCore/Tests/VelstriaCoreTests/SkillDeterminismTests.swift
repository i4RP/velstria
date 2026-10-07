import XCTest
@testable import VelstriaCore

/// スキル・スペルを多用する試合の決定論・スナップショット再開・tick 予算。
/// tick 予算は Release で `swift test -c release --filter SkillDeterminismTests`。
final class SkillDeterminismTests: XCTestCase {

    /// 全ヒーローが一定間隔で全スキル（自動照準）とスペルを撃つ入力。
    static func spamCommands(_ s: SimState, tick: Int) -> [HeroCommand] {
        var out: [HeroCommand] = []
        for i in s.heroIndices {
            let id = s.units[i].id
            let phase = (tick + Int(id)) % 20
            switch phase {
            case 0: out.append(HeroCommand(heroID: id, command: .castSkill(slot: .skill1, target: .none)))
            case 5: out.append(HeroCommand(heroID: id, command: .castSkill(slot: .skill2, target: .none)))
            case 15: out.append(HeroCommand(heroID: id, command: .castSkill(slot: .ultimate, target: .none)))
            default: break
            }
            if (tick + Int(id)) % 450 == 0 {
                out.append(HeroCommand(heroID: id, command: .castSpell(index: (tick / 450) % 2, target: .none)))
            }
        }
        return out
    }

    static func run(_ sim: Simulation, until time: Double, events: inout [SimEvent]) {
        while !sim.isEnded && sim.state.time < time {
            events += sim.step(commands: spamCommands(sim.state, tick: sim.state.tick))
        }
    }

    func testSkillHeavyMatchIsDeterministic() {
        let cfg = MatchFactory.botMatch(seed: 2024)
        let a = Simulation(config: cfg)
        let b = Simulation(config: cfg)
        var ea: [SimEvent] = []
        var eb: [SimEvent] = []
        Self.run(a, until: 100, events: &ea)
        Self.run(b, until: 100, events: &eb)
        XCTAssertEqual(ea, eb)
        XCTAssertEqual(a.state.units.map(\.pos), b.state.units.map(\.pos))
        XCTAssertEqual(a.state.units.map(\.hp), b.state.units.map(\.hp))
        XCTAssertEqual(a.state.rng, b.state.rng)
        let casts = ea.filter { if case .skillCast = $0 { return true } else { return false } }.count
        let spells = ea.filter { if case .spellCast = $0 { return true } else { return false } }.count
        XCTAssertGreaterThan(casts, 100)
        XCTAssertGreaterThan(spells, 5)
        XCTAssertTrue(ea.contains { if case .damage(let d) = $0 { return d.source.isSkill } else { return false } })
        for u in a.state.units {
            XCTAssertGreaterThanOrEqual(u.hp, 0)
            XCTAssertLessThanOrEqual(u.hp, u.stats.maxHP + 1e-6)
            XCTAssertGreaterThanOrEqual(u.resource, 0)
            if let h = u.hero {
                XCTAssertTrue(h.skillCooldowns.allSatisfy { $0 >= 0 && $0.isFinite })
                XCTAssertTrue(h.spellCooldowns.allSatisfy { $0 >= 0 && $0.isFinite })
            }
        }
    }

    func testSnapshotResumeMatchesContinuousRun() throws {
        let cfg = MatchFactory.botMatch(seed: 77)
        let continuous = Simulation(config: cfg)
        var e1: [SimEvent] = []
        Self.run(continuous, until: 45, events: &e1)
        let data = try JSONEncoder().encode(continuous.state)
        let resumed = Simulation(snapshot: try JSONDecoder().decode(SimState.self, from: data))
        var tail1: [SimEvent] = []
        var tail2: [SimEvent] = []
        Self.run(continuous, until: 65, events: &tail1)
        Self.run(resumed, until: 65, events: &tail2)
        XCTAssertEqual(tail1, tail2)
        XCTAssertEqual(continuous.state.units.map(\.hp), resumed.state.units.map(\.hp))
        XCTAssertEqual(continuous.state.units.map { $0.hero?.passive }, resumed.state.units.map { $0.hero?.passive })
    }

    func testSkillHeavyTickBudget() throws {
        #if DEBUG
        throw XCTSkip("tick 予算は Release でのみ計測する（swift test -c release --filter SkillDeterminismTests）")
        #else
        let sim = Simulation(config: MatchFactory.botMatch(seed: 5))
        var events: [SimEvent] = []
        Self.run(sim, until: 60, events: &events)
        events.removeAll()
        let startTick = sim.state.tick
        let start = DispatchTime.now().uptimeNanoseconds
        Self.run(sim, until: 360, events: &events)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let perTick = elapsed / Double(max(1, sim.state.tick - startTick))
        print("SkillDeterminismTests: \(String(format: "%.3f", perTick)) ms/tick, units=\(sim.state.units.count)")
        XCTAssertLessThan(perTick, 1.0)
        #endif
    }
}
