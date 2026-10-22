import Foundation

extension MapDefinition {
    /// Uploaded 5v5 stage. Rendering and collision are exported with the same transform.
    /// Keep `relayout` as the previous stage and its regression/performance fixture.
    public static let canyon: MapDefinition = {
        guard let url = Bundle.module.url(forResource: "CanyonLayout", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let layout = try? JSONDecoder().decode(CanyonLayout.self, from: data),
              let mask = BushMask(cell: 16.2, cols: 600, rows: 600, runLengthBase64: layout.bushRLE) else {
            preconditionFailure("Missing or invalid bundled CanyonLayout.json")
        }
        func point(_ p: [Double]) -> Vec2 { Vec2(p[0], p[1]) }
        var map = relayout
        map.stageID = "canyon"
        map.size = layout.size
        map.cores = layout.cores.map(point)
        map.fountains = layout.fountains.map(point)
        map.lanePaths = layout.lanes.map { $0.map(point) }
        map.obstacles = layout.walls.map { .polygon($0.map(point)) }
        map.river = .polygon(layout.river.map(point))
        map.bushMask = mask
        map.brushes = brushAreas(of: mask)
        for i in map.towers.indices {
            let t = map.towers[i]
            if t.isCore { map.towers[i].pos = map.core(t.team); continue }
            guard let spot = layout.towers.first(where: {
                $0.team == (t.team == .blue ? "blue" : "red") && $0.lane == String(describing: t.lane!) && $0.tier == t.tier.rawValue
            }) else { preconditionFailure("Canyon is missing an authored tower placement") }
            map.towers[i].pos = point(spot.point)
        }
        var available = layout.camps
        for i in map.camps.indices {
            let camp = map.camps[i]
            let side = camp.side == .blue ? "blue" : (camp.side == .red ? "red" : "neutral")
            if let index = available.firstIndex(where: { $0.kind == String(describing: camp.kind) && $0.side == side }) {
                map.camps[i].pos = point(available.remove(at: index).point)
            }
        }
        guard let structuresURL = Bundle.module.url(forResource: "CanyonStructures", withExtension: "json"),
              let structuresData = try? Data(contentsOf: structuresURL),
              let structures = try? JSONDecoder().decode([CanyonStructure].self, from: structuresData),
              structures.count == map.towers.count else {
            preconditionFailure("Missing authored Canyon structure footprints")
        }
        map.obstacles += structures.map { .polygon($0.footprint.map(point)) }
        // Lane markers in the FBX sit inside towers. Route the wave around their bases
        // once during map preparation, instead of repeatedly aiming into a collider.
        let nav = NavGrid(map: map)
        // 75 cm fits heroes and the largest super minion, with clearance to spare.
        // A 125 cm radius incorrectly seals the authored base gates and tower gaps.
        let laneRadius = 75.0
        map.lanePaths = map.lanePaths.map { points in
            let goals = points.map { nav.nearestWalkable($0, radius: laneRadius) }
            var route = [goals[0]]
            for goal in goals.dropFirst() {
                let segment = nav.findPath(from: route.last!, to: goal, radius: laneRadius)
                precondition(!segment.isEmpty, "Canyon lane has an unreachable waypoint")
                route += segment
            }
            return route
        }
        return map
    }()
}

private struct CanyonLayout: Decodable {
    struct Tower: Decodable { let team: String; let lane: String; let tier: Int; let point: [Double] }
    struct Camp: Decodable { let kind: String; let side: String; let point: [Double] }
    let size: Double
    let cores: [[Double]]
    let fountains: [[Double]]
    let lanes: [[[Double]]]
    let walls: [[[Double]]]
    let river: [[Double]]
    let bushRLE: String
    let towers: [Tower]
    let camps: [Camp]
}

private struct CanyonStructure: Decodable { let footprint: [[Double]] }
