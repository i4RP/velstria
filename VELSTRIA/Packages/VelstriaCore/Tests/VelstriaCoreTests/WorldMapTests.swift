import XCTest
@testable import VelstriaCore

/// 標準マップの設計制約（DESIGN §2）。
final class WorldMapTests: XCTestCase {
    let map = MapDefinition.standard

    func testDesignCoordinatesKept() {
        XCTAssertEqual(map.fountains, [Vec2(700, 700), Vec2(11300, 11300)])
        XCTAssertEqual(map.cores, [Vec2(1500, 1500), Vec2(10500, 10500)])
        XCTAssertEqual(map.lanePaths[Lane.mid.rawValue], [Vec2(1500, 1500), Vec2(2300, 2300), Vec2(9700, 9700), Vec2(10500, 10500)])
        XCTAssertEqual(map.riverWidth, 900)
        XCTAssertTrue(map.towers.contains { $0.team == .blue && $0.lane == .top && $0.tier == .outer && $0.pos == Vec2(1400, 7000) })
        XCTAssertEqual(map.camps.first { $0.kind == .astralWyrm }?.pos, Vec2(8300, 3700))
        XCTAssertEqual(map.camps.first { $0.kind == .ancientColossus }?.pos, Vec2(3700, 8300))
        XCTAssertEqual(map.camps.first { $0.kind == .astralWyrm }?.firstSpawn, 120)
        XCTAssertEqual(map.camps.first { $0.kind == .ancientColossus }?.respawn, 300)
    }

    func testBrushAndObstacleCounts() {
        XCTAssertEqual(map.brushes.count, 24)
        XCTAssertTrue((30...50).contains(map.obstacles.count), "obstacles = \(map.obstacles.count)")
        XCTAssertEqual(map.brushes.map(\.id), Array(0..<map.brushes.count))
    }

    func testPointSymmetry() {
        for o in map.obstacles {
            XCTAssertTrue(map.obstacles.contains(o.mirrored), "no mirror for \(o)")
        }
        for b in map.brushes {
            XCTAssertTrue(map.brushes.contains { $0.rect == b.rect.mirrored }, "no mirror for brush \(b.id)")
        }
        for c in map.camps where c.side != .neutral {
            XCTAssertTrue(map.camps.contains { $0.side == c.side.opponent && $0.kind == c.kind && $0.pos == c.pos.mirrored })
        }
    }

    func testDesignConstraints() {
        // レーン 350 以内に障害物なし・本拠点周辺が空いている・構造物/キャンプが埋まっていない・草むらと障害物が重ならない
        XCTAssertEqual(map.validationIssues(), [])
    }

    func testLaneCentersWalkable() {
        let nav = NavGrid(map: map)
        for lane in Lane.allCases {
            let path = map.lanePaths[lane.rawValue]
            for k in 1..<path.count {
                XCTAssertTrue(nav.hasLineOfSight(from: path[k - 1], to: path[k], radius: 220),
                              "lane \(lane) segment \(k) blocked")
            }
        }
    }

    func testCampsAndBossPitsReachableFromBothFountains() {
        let nav = NavGrid(map: map)
        for team in Team.players {
            let start = map.fountain(team)
            for camp in map.camps {
                let path = nav.findPath(from: start, to: camp.pos, radius: Balance.heroRadius)
                XCTAssertFalse(path.isEmpty, "camp \(camp.id) unreachable from \(team)")
                XCTAssertLessThan(path.last!.distance(to: camp.pos), 1, "camp \(camp.id) path ends off target")
                assertPathClear(nav, from: start, path: path, radius: Balance.heroRadius)
            }
            let enemyCore = map.core(team.opponent)
            XCTAssertFalse(nav.findPath(from: start, to: enemyCore, radius: Balance.heroRadius).isEmpty)
        }
    }

    func testMonstersFitInTheirCamps() {
        let nav = NavGrid(map: map)
        for camp in map.camps {
            for member in SpawnSystem.campMembers(camp.kind) {
                let r = UnitFactory.monsterProfile(member.kind).radius
                XCTAssertTrue(nav.isWalkable(camp.pos + member.offset * (camp.side == .red ? -1 : 1), radius: r),
                              "camp \(camp.id) member \(member.kind) does not fit")
            }
            // 巣の周囲を歩ける（リーシュ帰還の経路が存在する）
            let r = UnitFactory.monsterProfile(SpawnSystem.campMembers(camp.kind)[0].kind).radius
            XCTAssertFalse(nav.findPath(from: camp.pos + Vec2(300, 0), to: camp.pos, radius: r).isEmpty)
        }
    }

    func testDebugASCIIRendersFeatures() {
        let ascii = map.debugASCII()
        let lines = ascii.split(separator: "\n")
        XCTAssertEqual(lines.count, 60)
        XCTAssertTrue(lines.allSatisfy { $0.count == 60 })
        for ch in ["#", "\"", "=", "~", "T", "C", "F", "c", "B"] {
            XCTAssertTrue(ascii.contains(ch), "missing \(ch)")
        }
        // 上端 = +y。左上は Red の top 外塔側（x 小・y 大）で河川が通る
        XCTAssertEqual(lines[0].first, "~")
        // 点対称: 180° 回転した描画と記号の配置が一致する（ラベルの陣営差は無視）
        let grid = lines.map { Array($0) }
        var mismatches = 0
        for r in 0..<60 {
            for c in 0..<60 where (grid[r][c] == "#") != (grid[59 - r][59 - c] == "#") { mismatches += 1 }
        }
        XCTAssertEqual(mismatches, 0)
        print(ascii)
    }

    func testLaneGeometryHelpers() {
        XCTAssertEqual(map.distanceToLane(Vec2(1400, 5000), lane: .top), 0, accuracy: 1e-9)
        XCTAssertEqual(map.distanceToLane(Vec2(1800, 5000), lane: .top), 400, accuracy: 1e-9)
        XCTAssertEqual(map.nearestLane(to: Vec2(5000, 5100)).lane, .mid)
        let proj = MapDefinition.project(Vec2(5000, 1000), onto: map.lanePath(.bot, for: .blue))
        XCTAssertEqual(proj.point, Vec2(5000, 1400))
        XCTAssertEqual(proj.segmentEnd, 2)
    }

    private func assertPathClear(_ nav: NavGrid, from: Vec2, path: [Vec2], radius: Double,
                                 file: StaticString = #filePath, line: UInt = #line) {
        var a = from
        for p in path {
            XCTAssertTrue(nav.isWalkable(p, radius: radius), "waypoint \(p) not walkable", file: file, line: line)
            // 平滑化は格子の隣接点までは許容するため、線分は半径をわずかに縮めて確認
            XCTAssertTrue(nav.hasLineOfSight(from: a, to: p, radius: radius - 10), "segment \(a)->\(p) blocked",
                          file: file, line: line)
            a = p
        }
    }
}
