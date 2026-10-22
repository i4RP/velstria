import XCTest
@testable import VelstriaCore

final class CanyonMapTests: XCTestCase {
    func testDefaultAndExistingMaps() {
        XCTAssertEqual(MapDefinition.map(for: .practice).stageID, "canyon")
        XCTAssertEqual(MapDefinition.map(for: .brawl), .brawl)
        XCTAssertNil(MapDefinition.relayout.stageID)
        let map = MapDefinition.canyon
        XCTAssertEqual(map.towers.count, 20)
        XCTAssertEqual(map.camps.count, 15)
        XCTAssertEqual(map.brushes.count, map.bushMask?.bushCount)
        XCTAssertFalse(map.brushes.isEmpty)
        XCTAssertEqual(map.towers.filter(\.isCore).map(\.pos), map.cores)
    }

    func testAuthoredMasonryWallsBlockWalking() {
        let nav = NavGrid(map: .canyon)
        for p in [Vec2(6630, 682), Vec2(9053, 3744), Vec2(3265, 9051), Vec2(669, 5978)] {
            XCTAssertFalse(nav.isWalkable(p), "Missing masonry wall at \(p)")
        }
    }

    func testSpawnAndLaneReachability() {
        let map = MapDefinition.canyon
        let nav = NavGrid(map: map)
        for team in Team.players {
            let spawn = map.fountain(team)
            XCTAssertTrue(nav.isWalkable(spawn, radius: Balance.heroRadius), "fountain \(team)")
            for n in 0..<5 {
                let angle = Double(n) * .pi / 8
                let pos = spawn + Vec2(cos(angle), sin(angle)) * (team == .blue ? 300 : -300)
                XCTAssertTrue(nav.isWalkable(pos, radius: Balance.heroRadius), "hero spawn \(team) \(n)")
            }
            for camp in map.camps {
                for member in SpawnSystem.campMembers(camp.kind) {
                    let p = camp.pos + member.offset * (camp.side == .red ? -1 : 1)
                    XCTAssertTrue(nav.isWalkable(p, radius: UnitFactory.monsterProfile(member.kind).radius),
                                  "camp \(camp.kind) \(camp.side) \(member.kind) at \(p), clearance \(nav.clearance(at: p))")
                }
                let route = nav.findPath(from: spawn, to: camp.pos, radius: Balance.heroRadius)
                XCTAssertLessThan(route.last?.distance(to: camp.pos) ?? .infinity, 1, "unreachable \(camp.kind) \(camp.side)")
            }
        }
        for tower in map.towers {
            XCTAssertFalse(nav.isWalkable(tower.pos, radius: tower.isCore ? 150 : 90), "tower \(tower.team) \(String(describing: tower.lane)) \(tower.tier)")
        }
        for tower in map.towers {
            let start = nav.nearestWalkable(tower.pos + Vec2(-500, 0), radius: Balance.heroRadius)
            let end = nav.resolveMove(from: start, to: tower.pos, radius: Balance.heroRadius)
            XCTAssertGreaterThan(end.distance(to: tower.pos), Balance.heroRadius)
            XCTAssertTrue(nav.isWalkable(end, radius: Balance.heroRadius))
            let goal = nav.nearestWalkable(tower.pos + Vec2(500, 0), radius: Balance.heroRadius)
            XCTAssertFalse(nav.findPath(from: start, to: goal, radius: Balance.heroRadius).isEmpty)
        }
        for lane in map.lanes {
            let points = map.lanePath(lane, for: .blue)
            for (a, b) in zip(points, points.dropFirst()) {
                XCTAssertTrue(nav.hasLineOfSight(from: a, to: b, radius: 100), "lane \(lane): \(a) → \(b)")
            }
        }
    }

    func testBossArenasUseAlternatingObjectiveRules() {
        let map = MapDefinition.canyon
        let bosses = map.camps.filter { $0.kind.isBoss }
        XCTAssertEqual(bosses.count, 2)
        XCTAssertTrue(bosses.contains { $0.pos.x < map.size / 2 && $0.pos.y > map.size / 2 })
        XCTAssertTrue(bosses.contains { $0.pos.x > map.size / 2 && $0.pos.y < map.size / 2 })
        let config = MatchConfig(mode: .practice, seed: 1, players: [])
        let ctx = SimContext(master: .shared, map: map, config: config)
        var state = SimState(config: config)
        SpawnSystem.setupMatch(&state, ctx)
        XCTAssertNotNil(state.world.riverObjective)
    }
}
