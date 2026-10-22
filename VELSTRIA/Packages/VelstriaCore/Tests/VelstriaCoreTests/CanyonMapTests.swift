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

    func testCenteredTowersAndEverySolidProp() throws {
        struct Layout: Decodable {
            struct Tower: Decodable { let point: [Double]; let roadEdges: [[Double]] }
            struct Solid: Decodable { let name: String; let footprints: [[[Double]]] }
            let towers: [Tower]
            let solidObjects: [Solid]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "CanyonLayout", withExtension: "json"))
        let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: url))
        XCTAssertEqual(layout.towers.count, 18)
        for tower in layout.towers {
            for axis in 0..<2 {
                XCTAssertEqual(tower.point[axis], (tower.roadEdges[0][axis] + tower.roadEdges[1][axis]) / 2, accuracy: 0.01)
            }
        }
        let nav = NavGrid.shared(for: .canyon)
        XCTAssertGreaterThan(layout.solidObjects.count, 150)
        for solid in layout.solidObjects {
            for shape in solid.footprints {
                for vertex in shape {
                    XCTAssertFalse(nav.isWalkable(Vec2(vertex[0], vertex[1]), radius: Balance.heroRadius), solid.name)
                }
            }
        }
    }

    func testIdleHeroRecoversFromEmbeddedPosition() throws {
        let config = MatchFactory.botMatch(seed: 7)
        let ctx = SimContext(master: .shared, map: .canyon, config: config)
        var state = SimState(config: config)
        SpawnSystem.setupMatch(&state, ctx)
        let i = try XCTUnwrap(state.units.firstIndex { $0.kind == .hero })
        state.units[i].pos = ctx.map.towers[0].pos
        state.units[i].moveIntent = .none
        state.units[i].windupRemaining = 1
        MovementSystem.update(&state, ctx)
        XCTAssertTrue(ctx.nav.isWalkable(state.units[i].pos, radius: state.units[i].radius))
        XCTAssertEqual(state.units[i].pos, state.units[i].prevPos)
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
            // Approach along the lane: a fixed horizontal offset can land beyond
            // the newly collidable perimeter fence on a vertical outer lane.
            let direction = tower.isCore || tower.lane == .mid ? Vec2(1, 1).normalized
                : ((tower.team == .blue) == (tower.lane == .top) ? Vec2(0, 1) : Vec2(1, 0))
            let start = nav.nearestWalkable(tower.pos - direction * 500, radius: Balance.heroRadius)
            let end = nav.resolveMove(from: start, to: tower.pos, radius: Balance.heroRadius)
            XCTAssertGreaterThan(end.distance(to: tower.pos), Balance.heroRadius)
            XCTAssertTrue(nav.isWalkable(end, radius: Balance.heroRadius))
            let goal = nav.nearestWalkable(tower.pos + direction * 500, radius: Balance.heroRadius)
            XCTAssertFalse(nav.findPath(from: start, to: goal, radius: Balance.heroRadius).isEmpty, "\(tower.team) \(String(describing: tower.lane)) \(tower.tier) core=\(tower.isCore) \(start) -> \(goal)")
        }
        for lane in map.lanes {
            let points = map.lanePath(lane, for: .blue)
            XCTAssertGreaterThanOrEqual(points.count, 2, "empty lane \(lane): \(points)")
            XCTAssertLessThan(points.first?.distance(to: map.core(.blue)) ?? .infinity, 500)
            XCTAssertLessThan(points.last?.distance(to: map.core(.red)) ?? .infinity, 500)
            for (a, b) in zip(points, points.dropFirst()) {
                XCTAssertTrue(nav.hasLineOfSight(from: a, to: b, radius: 75), "lane \(lane): \(a) → \(b)")
            }
        }
    }

    func testFirstWaveSpawnsOnEveryLane() {
        let config = MatchFactory.botMatch(seed: 7)
        let ctx = SimContext(master: .shared, map: .canyon, config: config)
        var state = SimState(config: config)
        SpawnSystem.setupMatch(&state, ctx)
        SpawnSystem.spawnWave(&state, ctx)
        for team in Team.players {
            for lane in ctx.map.lanes {
                let minions = state.units.filter { $0.team == team && $0.minion?.lane == lane }
                XCTAssertEqual(minions.count, SpawnSystem.waveComposition(waveIndex: 0, lane: lane).count)
                for minion in minions { XCTAssertTrue(ctx.nav.isWalkable(minion.pos, radius: minion.radius)) }
                for type in [MinionType.melee, .ranged, .siege] {
                    let elite = UnitFactory.makeMinion(type: type, team: team, lane: lane, pos: .zero, time: 0, isSuper: true)
                    XCTAssertLessThan(elite.radius, 75)
                }
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
