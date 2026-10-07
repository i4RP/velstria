import XCTest
@testable import VelstriaCore

/// 契約（スキャフォールド）の健全性確認。全担当がこのテストを壊さないこと。
final class ContractSmokeTests: XCTestCase {
    func testMasterDataLoads() {
        let m = MasterData.shared
        XCTAssertEqual(m.heroes.count, 24)
        XCTAssertEqual(m.skills.count, 96)
        XCTAssertEqual(m.items.count, 72)
        XCTAssertEqual(m.spells.count, 10)
        XCTAssertEqual(m.runes.count, 30)
        XCTAssertEqual(m.cosmetics.count, 72)
        XCTAssertEqual(m.store.count, 114)
        XCTAssertEqual(m.skills(forHero: "H001").map(\.slot), SkillSlot.allCases)
        XCTAssertEqual(m.items[0].passivePercent, 6)
    }

    func testMapSymmetry() {
        let map = MapDefinition.standard
        XCTAssertEqual(map.towers.count, 20)
        XCTAssertEqual(map.camps.count, 14)
        for t in map.towers where t.team == .blue && !t.isCore {
            let mirroredLane: Lane? = t.lane == .top ? .bot : (t.lane == .bot ? .top : .mid)
            XCTAssertTrue(map.towers.contains { $0.team == .red && $0.lane == mirroredLane && $0.tier == t.tier
                && $0.pos == t.pos.mirrored })
        }
    }

    func testStandardMatchConfig() {
        let cfg = MatchFactory.standardMatch(humanHeroID: "H003", humanName: "Tester", seed: 42)
        XCTAssertEqual(cfg.players.count, 10)
        XCTAssertEqual(Set(cfg.players.map(\.heroID)).count, 10)
        XCTAssertEqual(cfg.players.filter { $0.controller == .human }.count, 1)
    }

    func testHeadlessMatchRunsAndIsDeterministic() {
        let cfg = MatchFactory.botMatch(seed: 7)
        let a = Simulation(config: cfg)
        let b = Simulation(config: cfg)
        a.runHeadless(maxTime: 180)
        b.runHeadless(maxTime: 180)
        XCTAssertEqual(a.state.tick, b.state.tick)
        XCTAssertEqual(a.state.units.map(\.pos), b.state.units.map(\.pos))
        XCTAssertEqual(a.state.units.map(\.hp), b.state.units.map(\.hp))
        XCTAssertGreaterThan(a.state.units.filter { $0.kind == .minion }.count, 0)
    }

    func testSnapshotRoundTrip() throws {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 3))
        sim.runHeadless(maxTime: 40)
        let data = try JSONEncoder().encode(sim.state)
        let decoded = try JSONDecoder().decode(SimState.self, from: data)
        XCTAssertEqual(decoded.units.count, sim.state.units.count)
        XCTAssertEqual(decoded.unit(sim.state.units[5].id)?.pos, sim.state.units[5].pos)
    }
}
