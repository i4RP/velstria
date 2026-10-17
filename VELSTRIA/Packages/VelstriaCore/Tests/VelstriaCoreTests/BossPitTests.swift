import XCTest
@testable import VelstriaCore

final class BossPitTests: XCTestCase {
    func testObjectiveAlternatesAndLordTimes() throws {
        let config = WorldTestKit.emptyConfig()
        let ctx = SimContext(master: .shared, map: .relayout, config: config)
        var s = SimState(config: config)
        SpawnSystem.setupMatch(&s, ctx)
        let lower = try XCTUnwrap(ctx.map.camps.filter { $0.kind.isBoss }.min { $0.pos.y < $1.pos.y })
        func liveBoss(_ s: SimState) -> Int? {
            s.units.indices.first { s.units[$0].isAlive && s.units[$0].team == .neutral && s.units[$0].monster?.kind.isBoss == true }
        }
        WorldTestKit.setTime(&s, 120)
        RiverObjectiveSystem.update(&s, ctx)
        let first = try XCTUnwrap(liveBoss(s))
        XCTAssertEqual(s.units[first].monster?.kind, .astralWyrm)
        XCTAssertEqual(s.units[first].monster?.campID, lower.id)
        s.units[first].isAlive = false
        WorldTestKit.setTime(&s, 150)
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertEqual(s.world.riverObjective?.nextSpawnAt, 270)
        XCTAssertNotEqual(s.world.riverObjective?.campID, lower.id)
        WorldTestKit.setTime(&s, 269)
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertNil(liveBoss(s))
        WorldTestKit.setTime(&s, 270)
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertNotNil(liveBoss(s))
        WorldTestKit.setTime(&s, 480)
        RiverObjectiveSystem.update(&s, ctx)
        let lord = try XCTUnwrap(liveBoss(s))
        XCTAssertEqual(s.units[lord].monster?.kind, .ancientColossus)
        XCTAssertEqual(s.units.filter { $0.isAlive && $0.monster?.kind.isBoss == true }.count, 1)
        WorldTestKit.setTime(&s, 720)
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertEqual(s.units[lord].monster?.lordTier, 1)
        WorldTestKit.setTime(&s, 1080)
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertEqual(s.units[lord].monster?.lordTier, 2)
        XCTAssertTrue(s.units[lord].statuses.contains { $0.tag == "lord.evolved" })
        s.units[lord].isAlive = false
        RiverObjectiveSystem.update(&s, ctx)
        XCTAssertEqual(s.world.riverObjective?.nextSpawnAt, 1260)
        XCTAssertEqual(s.world.riverObjective?.campID, lower.id)
        let restored = try JSONDecoder().decode(SimState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(restored.world.riverObjective, s.world.riverObjective)
    }

    func testCapturedLordUsesWeakestLaneAndGivesAuras() throws {
        let config = WorldTestKit.emptyConfig()
        let ctx = SimContext(master: .shared, map: .relayout, config: config)
        var s = SimState(config: config)
        SpawnSystem.setupMatch(&s, ctx)
        for i in s.units.indices where s.units[i].team == .blue && s.units[i].tower?.lane == .bot {
            s.units[i].isAlive = false
        }
        WorldTestKit.setTime(&s, 1080)
        RiverObjectiveSystem.capture(&s, ctx, team: .blue)
        let lord = try XCTUnwrap(s.units.indices.first { s.units[$0].monster?.kind == .ancientColossus })
        XCTAssertEqual(s.units[lord].minion?.lane, .bot)
        XCTAssertEqual(s.units[lord].team, .blue)
        let hero = WorldTestKit.addHero(&s, ctx, team: .blue, pos: s.units[lord].pos + Vec2(200, 0))
        RiverObjectiveSystem.abilities(&s, ctx, lord)
        XCTAssertTrue(s.units[hero].statuses.contains { $0.tag == "lord.magic" })
        MinionSystem.update(&s, ctx)
        let intent = s.units[lord].moveIntent
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[lord].moveIntent, intent)
        XCTAssertNotEqual(intent, .none)
    }

    func testMirroredFootprintsAndNavigableEntrance() {
        let map = MapDefinition.relayout
        let nav = NavGrid(map: map)
        for camp in map.camps where camp.kind.isBoss {
            let lower = camp.pos.y < map.size / 2
            let wall = BossPitGeometry.wall(center: camp.pos, lower: lower)
            XCTAssertGreaterThan(Spline.signedArea(wall), 0)
            XCTAssertTrue(nav.isWalkable(camp.pos, radius: 220))
            let entrance = BossPitGeometry.point(center: camp.pos, lower: lower, radius: 510, angle: -.pi / 7)
            XCTAssertTrue(nav.hasLineOfSight(from: camp.pos, to: entrance, radius: Balance.heroRadius))
            let back = BossPitGeometry.point(center: camp.pos, lower: lower, radius: 380, angle: .pi / 2)
            XCTAssertFalse(nav.isWalkable(back, radius: 1))
            XCTAssertFalse(map.brushes.contains { map.brush($0.id, contains: back) })
        }
        let upper = BossPitGeometry.wall(center: .zero, lower: false)
        let lower = BossPitGeometry.wall(center: .zero, lower: true).reversed()
        for (a, b) in zip(upper, lower) {
            XCTAssertEqual(a.x, b.x, accuracy: 0.001)
            XCTAssertEqual(a.y, -b.y, accuracy: 0.001)
        }
    }
}
