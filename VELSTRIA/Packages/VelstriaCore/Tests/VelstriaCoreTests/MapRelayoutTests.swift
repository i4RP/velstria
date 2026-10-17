import XCTest
@testable import VelstriaCore

final class MapRelayoutTests: XCTestCase {
    func testTravelMeasurements() {
        measure(.standard, name: "before")
        measure(.relayout, name: "after")
    }

    func testPreservedObjectsAndClearRoutes() {
        let old = MapDefinition.standard, map = MapDefinition.relayout
        XCTAssertEqual(map.validationIssues(), [])
        XCTAssertEqual(old.towers.count, map.towers.count)
        XCTAssertEqual(old.camps.map(\.id), map.camps.map(\.id))
        // 壁は MLBB のミニマップ原本から起こした滑らかな多角形（2026-10-16。旧: standard の矩形と円の寸法のまま中心だけ移した）。
        // Blue 半面 + 点対称 + 中心の壁、どれも反時計回り
        XCTAssertEqual(map.obstacles.count,
                       MapDefinition.sanctumBlueWallSplines.count * 2 + MapDefinition.sanctumCenterWallSplines.count + 2)
        for o in map.obstacles where !map.camps.contains(where: { $0.kind.isBoss && $0.pos.distance(to: o.bounds.center) < 500 }) {
            guard case .polygon(let v) = o else { return XCTFail("壁が多角形でない: \(o)") }
            XCTAssertGreaterThan(Spline.signedArea(v), 0)
            // 1 mm の精度で細かく分けている（弦は 50 以下）
            for (a, b) in zip(v, v.dropFirst() + v.prefix(1)) { XCTAssertLessThanOrEqual(a.distance(to: b), 50.01) }
        }
        // 点対称（relayout の一辺で写す）
        for o in map.obstacles where !map.camps.contains(where: { $0.kind.isBoss && $0.pos.distance(to: o.bounds.center) < 500 }) {
            let c = o.bounds.center, m = Vec2(map.size - c.x, map.size - c.y)
            XCTAssertTrue(map.obstacles.contains { $0.bounds.center.distance(to: m) < 1 }, "no mirror for wall at \(c)")
        }
        XCTAssertEqual(map.brushes.map(\.id), Array(0..<map.brushes.count))
        let nav = NavGrid(map: map)
        for lane in map.lanes {
            let path = map.lanePath(lane, for: .blue)
            for (a, b) in zip(path, path.dropFirst()) {
                XCTAssertTrue(nav.hasLineOfSight(from: a, to: b, radius: 220))
            }
        }
        for team in Team.players {
            for camp in map.camps {
                for member in SpawnSystem.campMembers(camp.kind) {
                    XCTAssertTrue(nav.isWalkable(camp.pos + member.offset * (camp.side == .red ? -1 : 1),
                                                radius: UnitFactory.monsterProfile(member.kind).radius))
                }
                let path = nav.findPath(from: map.fountain(team), to: camp.pos, radius: Balance.heroRadius)
                XCTAssertLessThan(path.last?.distance(to: camp.pos) ?? .infinity, 1)
            }
        }
    }

    private func measure(_ map: MapDefinition, name: String) {
        let ctx = SimContext(master: .shared, map: map, config: MatchConfig(mode: .practice, seed: 1, players: []))
        // Freeze the original H025 baseline so later hero balancing cannot change the comparison.
        let speed: Double = 262
        let center = Vec2(map.size / 2, map.size / 2)
        let clearance = map.obstacles.flatMap { o in map.lanes.map { MapDefinition.distance(from: o, toPolyline: map.lanePath($0, for: .blue)) } }.min()!
        let midTowers = map.towers.filter { $0.team == .blue && $0.lane == .mid }
        print("MAP_DIM \(name) size=\(map.size) cores=\(map.core(.blue).distance(to: map.core(.red))) laneClearance=\(clearance) midTowerGaps=\(zip(midTowers, midTowers.dropFirst()).map { $0.pos.distance(to: $1.pos) })")
        let top = map.lanePaths[Lane.top.rawValue]
        let side = (top[2] + top[3]) * 0.5
        // Walk along the river to the first wall (hero radius included), not just the lane midpoint.
        let dir = Vec2(-1, 1).normalized
        func wallEndpoint(_ direction: Vec2) -> Vec2 {
            var lo = 0.0, hi = map.size
            for _ in 0..<40 {
                let d = (lo + hi) / 2
                if ctx.nav.hasLineOfSight(from: center, to: center + direction * d, radius: Balance.heroRadius) {
                    lo = d
                } else { hi = d }
            }
            return center + direction * max(0, lo - 2)
        }
        var routes: [(String, Vec2, Vec2)] = []
        for team in Team.players {
            routes.append(("\(team)-spawn-mid", map.fountain(team), center))
            routes.append(("\(team)-mid-side", center, team == .blue ? side : Vec2(map.size - side.x, map.size - side.y)))
            routes.append(("\(team)-mid-wall", center, wallEndpoint(team == .blue ? dir : dir * -1)))
            for camp in map.camps where camp.kind.isBoss {
                routes.append(("\(team)-spawn-\(camp.kind)", map.fountain(team), camp.pos))
            }
        }
        for (label, start, end) in routes {
            var path = ctx.nav.findPath(from: start, to: end, radius: Balance.heroRadius)
            XCTAssertFalse(path.isEmpty)
            let points = [start] + path
            let length = zip(points, points.dropFirst()).reduce(0.0) { $0 + $1.0.distance(to: $1.1) }
            var pos = start, ticks = 0
            while !path.isEmpty && ticks < 9000 {
                pos = MovementSystem.advance(ctx, from: pos, along: &path, step: speed * Balance.dt, radius: Balance.heroRadius)
                ticks += 1
            }
            XCTAssertLessThan(pos.distance(to: end), 1, label)
            print("MAP_TRAVEL \(name) \(label) distance=\(String(format: "%.1f", length)) seconds=\(String(format: "%.2f", Double(ticks) * Balance.dt)) speed=\(speed)")
        }
    }
}
