import XCTest
@testable import VelstriaCore

/// 稼働版 canyon（`MapDefinition.canyon`、nav 経路済み）を外部ツール用の JSON に書き出す。
/// 普段は skip。書き出し: VELSTRIA_EXPORT_MAP=<dir> swift test --filter CanyonExportTests → <dir>/canyon_resolved.json
final class CanyonExportTests: XCTestCase {
    typealias P = [Double]
    struct Tower: Encodable { let index: Int; let team: String; let lane: String?; let tier: String; let pos: P; let isCore: Bool; let radius: Double }
    struct Member: Encodable { let monster: String; let offset: P; let pos: P; let radius: Double; let isBoss: Bool }
    struct Camp: Encodable {
        let id: Int; let side: String; let kind: String; let pos: P; let firstSpawn: Double; let respawn: Double
        let isBoss: Bool; let isSentinel: Bool; let clearance: Double; let fromLayout: Bool; let members: [Member]
    }
    struct Shape: Encodable {
        let index: Int; let type: String; let source: String; let tower: Int?
        let points: [P]?; let rect: [Double]?; let center: P?; let radius: Double?; let bounds: [Double]
    }
    struct Brush: Encodable { let id: Int; let bush: Int; let rect: [Double]; let cells: Int }
    struct Mask: Encodable { let cell: Double; let cols: Int; let rows: Int; let bushCount: Int; let runLengthBase64: String }
    struct Objective: Encodable {
        let lordStart, evolvedStart, lordRespawn, lordRespawnLate, wyrmRespawn, wyrmLastRespawnBefore: Double
        let turtleToLordQuiet, turtleToLordDeadline: Double
    }
    struct Export: Encodable {
        let note: String; let sourceSHA256: String?; let stageID: String?; let size: Double
        let lanes: [String]; let expLane: String?; let goldLane: String?
        let fountains: [P]; let fountainRadius: Double; let cores: [P]
        let towers: [Tower]; let camps: [Camp]
        let lanePaths: [String: [P]]; let laneWaypoints: [String: [P]]; let laneRouteRadius: Double
        let obstacles: [Shape]; let river: Shape?; let riverWidth: Double
        let brushes: [Brush]; let bushMask: Mask?; let riverObjective: Objective
        let navGrid: [String: Double]; let radii: [String: Double]
    }
    struct Layout: Decodable {
        struct Camp: Decodable { let point: [Double] }
        let sourceSHA256: String?; let lanes: [[[Double]]]; let camps: [Camp]
    }

    func testExportResolvedCanyon() throws {
        guard let dir = ProcessInfo.processInfo.environment["VELSTRIA_EXPORT_MAP"], !dir.isEmpty else {
            throw XCTSkip("VELSTRIA_EXPORT_MAP=<dir> で書き出す")
        }
        let map = MapDefinition.canyon
        let url = try XCTUnwrap(Bundle.module.url(forResource: "CanyonLayout", withExtension: "json"))
        let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: url))
        func p(_ v: Vec2) -> P { [v.x, v.y] }
        func r(_ r: Rect2) -> [Double] { [r.minX, r.minY, r.maxX, r.maxY] }
        func name<T>(_ v: T) -> String { String(describing: v) }
        let laneNames = Lane.allCases.map(name)

        let towers = map.towers.enumerated().map { i, t in
            Tower(index: i, team: name(t.team), lane: t.lane.map(name), tier: name(t.tier), pos: p(t.pos), isCore: t.isCore,
                  radius: t.isCore ? Balance.coreRadius : Balance.towerRadius)
        }
        let layoutCamps = layout.camps.map { Vec2($0.point[0], $0.point[1]) }
        let camps = map.camps.map { c in
            Camp(id: c.id, side: name(c.side), kind: name(c.kind), pos: p(c.pos), firstSpawn: c.firstSpawn, respawn: c.respawn,
                 isBoss: c.kind.isBoss, isSentinel: c.kind.isSentinel, clearance: MapDefinition.campClearance(c.kind),
                 fromLayout: layoutCamps.contains(c.pos),
                 members: SpawnSystem.campMembers(c.kind).map { m in
                     let prof = UnitFactory.monsterProfile(m.kind)
                     return Member(monster: name(m.kind), offset: p(m.offset), pos: p(c.pos + m.offset), radius: prof.radius, isBoss: prof.isBoss)
                 })
        }
        // 壁（CanyonLayout.walls）の後ろに塔・Core の足場（CanyonStructures）が続く。足場は中に立つ塔で見分ける
        func shape(_ o: Obstacle, _ i: Int, _ source: String) -> Shape {
            let tower = source == "river" ? nil : map.towers.firstIndex { o.contains($0.pos) }
            let src = source == "river" ? source : (tower == nil ? "wall" : "structure")
            switch o {
            case .polygon(let v):
                return Shape(index: i, type: "polygon", source: src, tower: tower, points: v.map(p), rect: nil, center: nil, radius: nil, bounds: r(o.bounds))
            case .rect(let rc):
                return Shape(index: i, type: "rect", source: src, tower: tower, points: nil, rect: r(rc), center: nil, radius: nil, bounds: r(o.bounds))
            case .circle(let c, let rad):
                return Shape(index: i, type: "circle", source: src, tower: tower, points: nil, rect: nil, center: p(c), radius: rad, bounds: r(o.bounds))
            }
        }
        let obstacles = map.obstacles.enumerated().map { shape($1, $0, "obstacle") }
        var cellCounts = [Int](repeating: 0, count: map.brushes.count)
        if let m = map.bushMask { for v in m.cells where v != 0 && Int(v) - 1 < cellCounts.count { cellCounts[Int(v) - 1] += 1 } }
        let nav = NavGrid(map: map)

        let export = Export(
            note: "sim units (100 = 1 m), +y = north. Render metres: (x, height, z) = (sim.x / 100, h, -sim.y / 100). " +
                "lanePaths are Blue core -> Red core, nav-routed (radius laneRouteRadius); laneWaypoints are the authored CanyonLayout lanes. " +
                "Boss camps (astralWyrm/ancientColossus) are driven by riverObjective, not their firstSpawn/respawn.",
            sourceSHA256: layout.sourceSHA256, stageID: map.stageID, size: map.size,
            lanes: map.lanes.map(name), expLane: map.expLane.map(name), goldLane: map.goldLane.map(name),
            fountains: map.fountains.map(p), fountainRadius: Balance.fountainRadius, cores: map.cores.map(p),
            towers: towers, camps: camps,
            lanePaths: Dictionary(uniqueKeysWithValues: zip(laneNames, map.lanePaths.map { $0.map(p) })),
            laneWaypoints: Dictionary(uniqueKeysWithValues: zip(laneNames, layout.lanes)), laneRouteRadius: 75,
            obstacles: obstacles, river: map.river.map { shape($0, -1, "river") }, riverWidth: map.riverWidth,
            brushes: map.brushes.map { Brush(id: $0.id, bush: $0.bush, rect: r($0.rect), cells: cellCounts[$0.id]) },
            bushMask: map.bushMask.map { Mask(cell: $0.cell, cols: $0.cols, rows: $0.rows, bushCount: $0.bushCount, runLengthBase64: $0.runLengthBase64) },
            riverObjective: Objective(lordStart: RiverObjectiveSystem.lordStart, evolvedStart: RiverObjectiveSystem.evolvedStart,
                                      lordRespawn: RiverObjectiveSystem.lordRespawn, lordRespawnLate: RiverObjectiveSystem.lordRespawnLate,
                                      wyrmRespawn: RiverObjectiveSystem.wyrmRespawn, wyrmLastRespawnBefore: RiverObjectiveSystem.wyrmLastRespawnBefore,
                                      turtleToLordQuiet: RiverObjectiveSystem.turtleToLordQuiet, turtleToLordDeadline: RiverObjectiveSystem.turtleToLordDeadline),
            navGrid: ["cellSize": nav.cellSize, "cols": Double(nav.cols), "rows": Double(nav.rows)],
            radii: ["hero": Balance.heroRadius, "tower": Balance.towerRadius, "core": Balance.coreRadius,
                    "laneObstacleClearance": MapDefinition.laneObstacleClearance, "baseClear": MapDefinition.baseClearRadius]
        )
        XCTAssertEqual(obstacles.filter { $0.source == "structure" }.count, map.towers.count)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let out = URL(fileURLWithPath: dir).appendingPathComponent("canyon_resolved.json")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(export).write(to: out)
        print("canyon export: \(out.path) towers \(towers.count) camps \(camps.count) obstacles \(obstacles.count) lanes \(map.lanePaths.map(\.count))")
    }
}
