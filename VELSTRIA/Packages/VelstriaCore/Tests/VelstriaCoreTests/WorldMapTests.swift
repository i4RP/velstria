import XCTest
@testable import VelstriaCore

/// 標準マップの設計制約（DESIGN §2）。
final class WorldMapTests: XCTestCase {
    let map = MapDefinition.standard

    func testDesignCoordinatesKept() {
        XCTAssertEqual(map.fountains, [Vec2(600, 600), Vec2(11400, 11400)])
        XCTAssertEqual(map.cores, [Vec2(1250, 1250), Vec2(10750, 10750)])
        XCTAssertEqual(map.lanePaths[Lane.mid.rawValue], [Vec2(1250, 1250), Vec2(2300, 2300), Vec2(9700, 9700), Vec2(10750, 10750)])
        XCTAssertEqual(map.riverWidth, 900)
        XCTAssertTrue(map.towers.contains { $0.team == .blue && $0.lane == .top && $0.tier == .outer && $0.pos == Vec2(484, 8793) })
        XCTAssertEqual(map.camps.first { $0.kind == .astralWyrm }?.pos, Vec2(8260, 3590))
        XCTAssertEqual(map.camps.first { $0.kind == .ancientColossus }?.pos, Vec2(3740, 8410))
        XCTAssertEqual(map.camps.first { $0.kind == .astralWyrm }?.firstSpawn, 120)
        XCTAssertEqual(map.camps.first { $0.kind == .ancientColossus }?.respawn, 180)
        XCTAssertEqual(map.camps.first { $0.kind == .astralWyrm }?.respawn, 120)
    }

    /// 側レーンは地図の縁に沿い（縁から 700 以内。以前は 1400）、左上と右下の角は 45° に切る。
    func testSideLanesHugTheMapEdgesAndCutTheCornersDiagonally() {
        let top = map.lanePaths[Lane.top.rawValue], bot = map.lanePaths[Lane.bot.rawValue]
        XCTAssertEqual(top[1].x, 700)
        XCTAssertEqual(top[2].x, 700)
        XCTAssertEqual(top[3].y, 11300)
        XCTAssertEqual(top[4].y, 11300)
        for p in top.dropFirst().dropLast() {
            XCTAssertLessThanOrEqual(min(p.x, map.size - p.y), 700, "\(p)")
        }
        for p in bot.dropFirst().dropLast() {
            XCTAssertLessThanOrEqual(min(p.y, map.size - p.x), 700, "\(p)")
        }
        // 角（左上）は 45°
        let corner = top[3] - top[2]
        XCTAssertEqual(abs(corner.x), abs(corner.y), accuracy: 1e-9)
        // bot は top の点対称（逆順）
        XCTAssertEqual(Array(bot.map(\.mirrored).reversed()), top)
        // 角の外側（レーンを切る壁）は歩けない
        let nav = NavGrid(map: map)
        XCTAssertFalse(nav.isWalkable(Vec2(200, 11800), radius: Balance.heroRadius))
        XCTAssertFalse(nav.isWalkable(Vec2(11800, 200), radius: Balance.heroRadius))
        XCTAssertTrue(nav.isWalkable(Vec2(700, 9000), radius: Balance.heroRadius))
    }

    /// タワーの配置（ミニマップのアイコンから測った外塔・内塔・基部塔）。レーンの帯の中（中心線から 300 以内）にあり、間隔は 1500 以上。
    func testTowerLayoutAndSpacing() {
        let expected: [Lane: [Vec2]] = [
            .top: [Vec2(484, 8793), Vec2(556, 6342), Vec2(639, 3166)],
            .mid: [Vec2(4656, 4991), Vec2(3391, 3705), Vec2(2399, 2399)],
            .bot: [Vec2(8848, 567), Vec2(5423, 470), Vec2(3179, 630)],
        ]
        for lane in Lane.allCases {
            let blue = TowerTier.allCases.map { tier in
                map.towers.first { $0.team == .blue && $0.lane == lane && $0.tier == tier }!.pos
            }
            XCTAssertEqual(blue, expected[lane]!, "\(lane)")
            for p in blue { XCTAssertLessThan(map.distanceToLane(p, lane: lane), 300, "\(lane) \(p)") }
            for k in 1..<blue.count { XCTAssertGreaterThanOrEqual(blue[k - 1].distance(to: blue[k]), 1500, "\(lane) \(k)") }
            // 基部塔は Core から 1400〜2200
            XCTAssertTrue((1400...2200).contains(blue[2].distance(to: map.core(.blue))), "\(lane)")
        }
    }

    func testBrushAndObstacleCounts() {
        // MLBB の草むら 16 か所 × 2（斜め・細長いものは複数の矩形で 22 個 × 2）
        XCTAssertEqual(map.brushes.count, 44)
        XCTAssertEqual(Set(map.brushes.map(\.bush)).count, 32)
        XCTAssertTrue((90...130).contains(map.obstacles.count), "obstacles = \(map.obstacles.count)")
        XCTAssertEqual(map.brushes.map(\.id), Array(0..<map.brushes.count))
    }

    func testPointSymmetry() {
        for o in map.obstacles {
            XCTAssertTrue(map.obstacles.contains(o.mirrored), "no mirror for \(o)")
        }
        for b in map.brushes {
            XCTAssertTrue(map.brushes.contains { $0.rect == b.rect.mirrored }, "no mirror for brush \(b.id)")
        }
        // キャンプはミニマップから測った位置（ゲーム側の配置が厳密な点対称ではない）。相手側の対応するキャンプは写像から 200 以内。
        for c in map.camps where c.side != .neutral {
            XCTAssertTrue(map.camps.contains { $0.side == c.side.opponent && $0.kind == c.kind && $0.pos.distance(to: c.pos.mirrored) < 200 },
                          "no counterpart for camp \(c.id)")
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
        // 上端 = +y。左上の角はレーンを斜めに切る壁（右下も点対称）
        XCTAssertEqual(lines[0].first, "#")
        XCTAssertEqual(lines[59].last, "#")
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
        XCTAssertEqual(map.distanceToLane(Vec2(700, 5000), lane: .top), 0, accuracy: 1e-9)
        XCTAssertEqual(map.distanceToLane(Vec2(1100, 5000), lane: .top), 400, accuracy: 1e-9)
        XCTAssertEqual(map.nearestLane(to: Vec2(5000, 5100)).lane, .mid)
        let proj = MapDefinition.project(Vec2(5000, 1000), onto: map.lanePath(.bot, for: .blue))
        XCTAssertEqual(proj.point, Vec2(5000, 700))
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
