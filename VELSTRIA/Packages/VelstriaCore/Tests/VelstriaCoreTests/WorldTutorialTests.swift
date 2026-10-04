import XCTest
@testable import VelstriaCore

final class WorldTutorialTests: XCTestCase {
    private func config(tutorial: Bool = true) -> MatchConfig {
        MatchFactory.practiceMatch(humanHeroID: "H001", humanName: "Tutorial",
                                   options: PracticeOptions(spawnMinions: false, spawnDummies: true),
                                   tutorial: tutorial, seed: 7)
    }

    func testRemovingDummiesLetsMinionResumeMarchingTowardTower() throws {
        var (s, ctx) = WorldTestKit.makeState(config())
        let forward = (ctx.map.core(.red) - ctx.map.core(.blue)).normalized
        let start = s.world.dummySpots[1] - forward * 220
        let minion = WorldTestKit.addMinion(&s, ctx, team: .blue, pos: start)
        let minionID = s.units[minion].id
        MinionSystem.update(&s, ctx)
        let target = try XCTUnwrap(s.units[minion].attackTargetID)
        XCTAssertTrue(s.world.dummyIDs.contains(target))

        let sim = Simulation(snapshot: s)
        sim.step(commands: [HeroCommand(heroID: try XCTUnwrap(s.humanHeroID), command: .removeTutorialDummies)])

        XCTAssertFalse(sim.state.units.contains { $0.kind == .dummy })
        let marching = try XCTUnwrap(sim.state.unit(minionID))
        XCTAssertNil(marching.attackTargetID)
        XCTAssertNil(marching.windupRemaining)
        guard case .point(let goal) = marching.moveIntent else {
            return XCTFail("The minion should resume its lane after the training dummies disappear")
        }
        XCTAssertGreaterThan((goal - start).dot(forward), 0)
        sim.runHeadless(maxTime: 1)
        let advanced = try XCTUnwrap(sim.state.unit(minionID))
        XCTAssertGreaterThan((advanced.pos - start).dot(forward), 100)
    }

    func testRemovingDummiesCancelsPendingRespawnEvenWhileHeroIsDead() throws {
        var (s, ctx) = WorldTestKit.makeState(config())
        let dummyID = try XCTUnwrap(s.world.dummyIDs[0])
        WorldTestKit.kill(&s, try XCTUnwrap(s.index(of: dummyID)))
        s.removeFinishedEntities()
        SpawnSystem.update(&s, ctx)
        XCTAssertNotNil(s.world.dummyRespawnAt[0])

        let hero = try XCTUnwrap(s.humanHeroIndex)
        let humanID = s.units[hero].id
        WorldTestKit.kill(&s, hero)
        s.units[hero].hero?.respawnTimer = 30
        let sim = Simulation(snapshot: s)
        sim.step(commands: [HeroCommand(heroID: humanID, command: .removeTutorialDummies)])
        sim.runHeadless(maxTime: Balance.dummyRespawnDelay + 1)

        XCTAssertFalse(sim.state.units.contains { $0.kind == .dummy })
        XCTAssertTrue(sim.state.world.dummySpots.isEmpty)
        XCTAssertTrue(sim.state.world.dummyIDs.isEmpty)
        XCTAssertTrue(sim.state.world.dummyRespawnAt.isEmpty)
        XCTAssertTrue(try XCTUnwrap(sim.state.unit(humanID)?.hero).isDead)
    }

    func testRemovalDoesNotAffectPracticeDummies() throws {
        let sim = Simulation(config: config(tutorial: false))
        let originalIDs = sim.state.world.dummyIDs
        sim.step(commands: [HeroCommand(heroID: try XCTUnwrap(sim.state.humanHeroID), command: .removeTutorialDummies)])
        XCTAssertEqual(sim.state.units.filter { $0.kind == .dummy && $0.isAlive }.count, 3)
        XCTAssertEqual(sim.state.world.dummyIDs, originalIDs)
    }

    func testOnlyTutorialHumanCanRemoveDummies() {
        var (s, ctx) = WorldTestKit.makeState(config())
        let other = WorldTestKit.addHero(&s, ctx, team: .red, pos: ctx.map.fountain(.red))
        let otherID = s.units[other].id
        let originalIDs = s.world.dummyIDs
        let sim = Simulation(snapshot: s)
        sim.step(commands: [HeroCommand(heroID: otherID, command: .removeTutorialDummies)])
        XCTAssertEqual(sim.state.units.filter { $0.kind == .dummy && $0.isAlive }.count, 3)
        XCTAssertEqual(sim.state.world.dummyIDs, originalIDs)
    }

    func testRemovalIsIdempotentAndSurvivesReplay() throws {
        let cfg = config()
        let sim = Simulation(config: cfg)
        let recorder = ReplayRecorder(config: cfg)
        sim.recorder = recorder
        let command = HeroCommand(heroID: try XCTUnwrap(sim.state.humanHeroID), command: .removeTutorialDummies)
        sim.step(commands: [command])
        sim.step(commands: [command])
        XCTAssertFalse(sim.state.units.contains { $0.kind == .dummy })

        let data = recorder.finish(summary: nil)
        let decoded = try JSONDecoder().decode(ReplayData.self, from: JSONEncoder().encode(data))
        let player = ReplayPlayer(data: decoded)
        while !player.isFinished { player.stepOnce() }
        XCTAssertFalse(player.state.units.contains { $0.kind == .dummy })
        XCTAssertEqual(player.state.stateHash(), sim.state.stateHash())
    }
}
