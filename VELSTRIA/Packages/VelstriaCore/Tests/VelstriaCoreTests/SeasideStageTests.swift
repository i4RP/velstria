import XCTest
@testable import VelstriaCore

final class SeasideStageTests: XCTestCase {
    func testSeasideDefaultAndCanyonSelectionPreserveGameplayLayout() {
        let config = MatchFactory.botMatch(seed: 7)
        XCTAssertEqual(config.stage, .seaside)
        XCTAssertEqual(MapDefinition.map(for: config).stageID, "seaside")
        XCTAssertEqual(MapDefinition.map(for: .practice).stageID, "seaside")
        XCTAssertEqual(MapDefinition.map(for: .standard, stage: .canyon), .canyon)
        for stage in MatchStage.allCases {
            XCTAssertEqual(MapDefinition.map(for: .brawl, stage: stage), .brawl)
        }
        var seaside = MapDefinition.seaside
        seaside.stageID = "canyon"
        XCTAssertEqual(seaside, .canyon, "A stage change must not alter lanes, collisions, spawns or bushes")
    }

    func testRecordedStageSurvivesRoundTripAndLegacyConfigKeepsCanyon() throws {
        for stage in MatchStage.allCases {
            let config = MatchConfig(mode: .practice, seed: 1, players: [], stage: stage)
            let decoded = try JSONDecoder().decode(MatchConfig.self, from: JSONEncoder().encode(config))
            XCTAssertEqual(decoded.resolvedStage, stage)
            let replay = ReplayData(config: decoded, frames: [], finalTick: 1, summary: nil)
            XCTAssertEqual(ReplayPlayer(data: replay).simulation.ctx.map.stageID, stage.rawValue)
        }
        let config = MatchConfig(mode: .practice, seed: 1, players: [])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        object.removeValue(forKey: "stage")
        let legacy = try JSONDecoder().decode(MatchConfig.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.stage)
        XCTAssertEqual(legacy.resolvedStage, .canyon)
        XCTAssertEqual(MapDefinition.map(for: legacy), .canyon)
        let replay = ReplayData(config: legacy, frames: [], finalTick: 1, summary: nil)
        XCTAssertEqual(ReplayPlayer(data: replay).simulation.ctx.map, .canyon)
    }

    func testSeasideRetainsEmbeddedHeroRecoveryAndWaveSpawns() throws {
        let config = MatchFactory.botMatch(seed: 7)
        let sim = Simulation(config: config, map: .seaside)
        var state = sim.state
        let index = try XCTUnwrap(state.units.firstIndex { $0.kind == .hero })
        state.units[index].pos = sim.ctx.map.towers[0].pos
        state.units[index].moveIntent = .none
        state.units[index].windupRemaining = 1
        MovementSystem.update(&state, sim.ctx)
        XCTAssertTrue(sim.ctx.nav.isWalkable(state.units[index].pos, radius: state.units[index].radius))
        XCTAssertEqual(state.units[index].pos, state.units[index].prevPos)
        SpawnSystem.spawnWave(&state, sim.ctx)
        for team in Team.players {
            for lane in sim.ctx.map.lanes {
                let minions = state.units.filter { $0.team == team && $0.minion?.lane == lane }
                XCTAssertEqual(minions.count, SpawnSystem.waveComposition(waveIndex: 0, lane: lane).count)
                for minion in minions {
                    XCTAssertTrue(sim.ctx.nav.isWalkable(minion.pos, radius: minion.radius))
                }
            }
        }
    }
}
