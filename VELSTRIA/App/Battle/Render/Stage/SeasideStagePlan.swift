import CoreGraphics
import Foundation
import simd
import VelstriaCore

/// One selected tropical stage, prepared off the main actor and merged by material/12 m cell.
/// Collision walls and concealment remain independent of the decorative triangle allowance.
struct SeasideStagePlan: @unchecked Sendable {
    let ground: [Int: StageMeshBuffer]
    let stone: [Int: StageMeshBuffer]
    let greenery: [Int: StageMeshBuffer]
    let props: [Int: StageMeshBuffer]
    let water: StageMeshBuffer
    let foliage: StageLayoutResult
    let foliageAtlas: CGImage
    let propAtlas: CGImage?
    let shaderURL: URL
    let quality: GraphicsQuality
    let mapMeters: Float
    let decorationTriangles: Int

    var triangleCount: Int {
        [ground, stone, greenery, props].reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.triangleCount } }
            + water.triangleCount + foliage.brushes.reduce(0) { $0 + $1.triangleCount }
    }

    static func load(map: MapDefinition, quality: RenderQuality, bundle: Bundle = .main) -> SeasideStagePlan? {
        guard let shader = bundle.url(forResource: StageAssets.shaderResourceName, withExtension: "metallib"),
              let brush = StageAssets.image(bundle, "StageBrushAtlas", "png"),
              brush.width <= 1024, brush.height <= 512 else { return nil }
        var imported: [StagePropKind: StagePropMesh] = [:]
        var atlas: CGImage?
        if let url = bundle.url(forResource: "StageSeaside", withExtension: "bin"),
           let data = try? Data(contentsOf: url),
           let meshes = StageAssets.parseProps(data, kinds: [.treeTall, .ruinArch]),
           meshes.values.allSatisfy({ $0.indices.count / 3 <= 2500 && $0.size.y > 0.1 }),
           let image = StageAssets.image(bundle, "StageSeasideAtlas", "jpg"),
           image.width <= 2048, image.height <= 1024 {
            imported = meshes
            atlas = image
        }
        var builder = SeasideLayout(map: map, quality: quality, imported: imported)
        builder.build()
        let result = SeasideStagePlan(ground: builder.ground, stone: builder.stone, greenery: builder.greenery,
                                     props: builder.props, water: builder.water, foliage: builder.brushes.out,
                                     foliageAtlas: brush, propAtlas: atlas, shaderURL: shader, quality: quality.level,
                                     mapMeters: builder.extent, decorationTriangles: builder.decorationTriangles)
        guard result.triangleCount <= BattleWorkBudget.stagePropTriangles(quality.level),
              result.foliage.brushes.reduce(0, { $0 + $1.triangleCount }) <= 90_000 else { return nil }
        return result
    }
}

private struct SeasideLayout {
    let map: MapDefinition
    let quality: RenderQuality
    let imported: [StagePropKind: StagePropMesh]
    let extent: Float
    var brushes: StageLayout
    var ground: [Int: StageMeshBuffer] = [:]
    var stone: [Int: StageMeshBuffer] = [:]
    var greenery: [Int: StageMeshBuffer] = [:]
    var props: [Int: StageMeshBuffer] = [:]
    var water = StageMeshBuffer()
    var decorationTriangles = 0
    var decorationAllowance = 0
    var rng = RenderRNG(seed: 0x5EA51DE)

    init(map: MapDefinition, quality: RenderQuality, imported: [StagePropKind: StagePropMesh]) {
        self.map = map
        self.quality = quality
        self.imported = imported
        extent = Float(map.size / Balance.unitsPerMeter)
        brushes = StageLayout(map: map, props: [:], density: 1, level: quality.level)
    }

    mutating func build() {
        sandAndSea()
        wallCores()
        plazas()
        brushes.brushFields()
        // Reserve exact gameplay silhouettes first, then admit whole decorative placements.
        let required = ground.values.reduce(0) { $0 + $1.triangleCount }
            + stone.values.reduce(0) { $0 + $1.triangleCount } + water.triangleCount
            + brushes.out.brushes.reduce(0) { $0 + $1.triangleCount }
        decorationAllowance = max(0, BattleWorkBudget.stagePropTriangles(quality.level) - required)
        tropicalWalls()
        coastline()
    }

    func world(_ p: SIMD2<Float>, _ y: Float = 0) -> SIMD3<Float> { [p.x, y, -p.y] }
    func meters(_ p: Vec2) -> SIMD2<Float> { [Float(p.x / Balance.unitsPerMeter), Float(p.y / Balance.unitsPerMeter)] }

    mutating func append(_ mesh: StageMeshBuffer, at p: SIMD2<Float>, material: Int, decoration: Bool = false) {
        if decoration {
            guard mesh.triangleCount <= decorationAllowance - decorationTriangles else { return }
            decorationTriangles += mesh.triangleCount
        }
        let key = StageChunks.key(world(p))
        switch material {
        case 0: var chunk = ground.removeValue(forKey: key) ?? StageMeshBuffer(); chunk.append(mesh); ground[key] = chunk
        case 1: var chunk = stone.removeValue(forKey: key) ?? StageMeshBuffer(); chunk.append(mesh); stone[key] = chunk
        case 2: var chunk = greenery.removeValue(forKey: key) ?? StageMeshBuffer(); chunk.append(mesh); greenery[key] = chunk
        default: var chunk = props.removeValue(forKey: key) ?? StageMeshBuffer(); chunk.append(mesh); props[key] = chunk
        }
    }

    mutating func sandAndSea() {
        // The playable square remains continuous; the wavering shoreline is beyond its boundary.
        let n = 48
        func point(_ ix: Int, _ iy: Int) -> SIMD2<Float> {
            let u = Float(ix) / Float(n), v = Float(iy) / Float(n)
            let x = -8 + (extent + 16) * u
            let y = -8 + (extent + 16) * v
            let waveX = sin(y * 0.12) * 1.8 + sin(y * 0.33) * 0.7
            let waveY = sin(x * 0.1 + 2) * 2.0 + sin(x * 0.28) * 0.7
            return [x + waveX * pow(abs(u * 2 - 1), 12), y + waveY * pow(abs(v * 2 - 1), 12)]
        }
        for y in 0..<n { for x in 0..<n {
            let a = point(x, y), b = point(x + 1, y), c = point(x + 1, y + 1), d = point(x, y + 1)
            var mesh = StageMeshBuffer()
            quad(&mesh, world(a, -0.04), world(b, -0.04), world(c, -0.04), world(d, -0.04), color: stageColor(0.95, 0.86, 0.61))
            append(mesh, at: (a + c) / 2, material: 0)
        } }
        quad(&water, world([-130, -130], -0.12), world([extent + 130, -130], -0.12),
             world([extent + 130, extent + 130], -0.12), world([-130, extent + 130], -0.12), color: stageColor(0.04, 0.68, 0.82))
        // The shallow lagoon marks the unchanged river footprint without sinking characters.
        if case .polygon(let points)? = map.river {
            var outline = points.map(meters)
            if StageLayout.signedArea(outline) < 0 { outline.reverse() }
            let vertices = outline.map { water.addVertex(world($0, -0.025), [0, 1, 0], .zero, stageColor(0.22, 0.8, 0.79)) }
            for (a, b, c) in StageLayout.triangulate(outline) { water.addTriangle(vertices[a], vertices[b], vertices[c]) }
        }
    }

    func outline(_ obstacle: Obstacle) -> [SIMD2<Float>] {
        switch obstacle {
        case .polygon(let p): return p.map(meters)
        case .rect(let r): return [meters(Vec2(r.minX, r.minY)), meters(Vec2(r.maxX, r.minY)), meters(Vec2(r.maxX, r.maxY)), meters(Vec2(r.minX, r.maxY))]
        case .circle(let c, let radius):
            return (0..<20).map { i in let a = Float(i) * .pi / 10; return meters(c) + SIMD2(cos(a), sin(a)) * Float(radius / Balance.unitsPerMeter) }
        }
    }

    mutating func wallCores() {
        // Last authored footprints belong to the existing towers; a low plinth retains those boundaries.
        let naturalCount = max(0, map.obstacles.count - map.towers.count)
        for (index, obstacle) in map.obstacles.enumerated() {
            let loop = outline(obstacle)
            guard loop.count >= 3 else { continue }
            let center = loop.reduce(SIMD2<Float>.zero, +) / Float(loop.count)
            let height: Float = index >= naturalCount ? 0.19 : 0.72 + Float(index % 4) * 0.15
            var mesh = StageMeshBuffer()
            limestone(&mesh, outline: loop, height: height, seed: index)
            append(mesh, at: center, material: 1)
        }
    }

    /// Reuse the bounded collision-outline bevel builder, then flatten normals for broad limestone facets.
    func limestone(_ mesh: inout StageMeshBuffer, outline raw: [SIMD2<Float>], height: Float, seed: Int) {
        guard raw.count >= 3 else { return }
        let bevel = StageLayout.slopedSlab(outline: raw, seed: UInt64(seed + 1),
                                          tint: stageColor(0.5, 0.5, 0.5), fine: false, refine: false).mesh
        let scale = height / max(0.1, bevel.boundsMax.y)
        for i in stride(from: 0, to: bevel.indices.count, by: 3) {
            func p(_ j: Int) -> SIMD3<Float> {
                let v = bevel.positions[Int(bevel.indices[i + j])]
                return [v.x, v.y < 0 ? -0.16 : v.y * scale, v.z]
            }
            let a = p(0), b = p(1), c = p(2)
            let cross = simd_cross(b - a, c - a)
            guard simd_length_squared(cross) > 0.000001 else { continue }
            let normal = simd_normalize(cross)
            let grass = height > 0.5 && normal.y > 0.54 && min(a.y, b.y, c.y) > height * 0.55
            let tint = grass ? stageColor(0.15, 0.40, 0.035) : stageColor(0.46, 0.53, 0.51)
            triangle(&mesh, a, b, c, color: tint)
        }
    }

    mutating func plazas() {
        // Low shell-colored sanctuary floors retain objective readability without adding blockers.
        for tower in map.towers {
            let p = meters(tower.pos)
            var mesh = StageMeshBuffer()
            disc(&mesh, at: p, radius: tower.isCore ? 3.5 : 1.9, y: -0.008, color: stageColor(0.79, 0.79, 0.68))
            append(mesh, at: p, material: 1)
        }
        for camp in map.camps where camp.kind == .astralWyrm || camp.kind == .ancientColossus {
            let p = meters(camp.pos)
            var mesh = StageMeshBuffer()
            disc(&mesh, at: p, radius: 3.7, y: -0.006, color: stageColor(0.77, 0.81, 0.69))
            append(mesh, at: p, material: 1)
        }
    }

    mutating func tropicalWalls() {
        let naturalCount = max(0, map.obstacles.count - map.towers.count)
        for (i, obstacle) in map.obstacles.prefix(naturalCount).enumerated() {
            let bounds = obstacle.bounds
            let center = meters(bounds.center)
            // Keep trunks in collision footprints. The canopies are high enough to preserve targets.
            let sim = Vec2(Double(center.x) * Balance.unitsPerMeter, Double(center.y) * Balance.unitsPerMeter)
            guard obstacle.signedDistance(to: sim) < -65 else { continue }
            let h: Float = 0.72 + Float(i % 4) * 0.15
            if i % (quality.level == .low ? 4 : 3) == 0 {
                palm(at: center, floor: h, height: 4.5 + Float(i % 4) * 0.45, yaw: Float(i) * 1.7)
            }
            if i % 2 == 0 { plants(at: center + SIMD2(0.25, -0.2), floor: h, scale: 0.8) }
        }
    }

    mutating func coastline() {
        // A recognisable limestone arch and tall palms frame both spawn approaches.
        for (p, yaw) in [(SIMD2<Float>(-14, 28), Float.pi / 3), (SIMD2<Float>(22, extent + 16), Float.pi / 8), (SIMD2<Float>(extent - 24, extent + 15), Float.pi / 8)] {
            arch(at: p, yaw: yaw)
        }
        for i in 0..<26 {
            let t = Float(i) / 25
            let p: SIMD2<Float> = i < 13 ? [-9 - sin(t * 9) * 2, t * 2 * extent] : [(t - 0.5) * 2 * extent, extent + 9 + cos(t * 12) * 2]
            palm(at: p, floor: 0, height: 5.5 + Float(i % 4) * 0.65, yaw: Float(i) * 2.4)
            plants(at: p + SIMD2(1.3, -0.7), floor: 0, scale: 1.0)
            var rock = StageMeshBuffer()
            boulder(&rock, at: p + SIMD2(-0.9, 0.5), floor: 0, radius: 1.8, height: 1.3, seed: i)
            append(rock, at: p, material: 1, decoration: true)
        }
        // Distant islands are simple silhouettes, never loaded as individual objects.
        for i in 0..<4 {
            let p = SIMD2<Float>(extent + 43 + Float(i) * 13, 12 + Float(i) * 30)
            var island = StageMeshBuffer()
            boulder(&island, at: p, floor: -0.7, radius: 8 + Float(i % 2) * 3, height: 4 + Float(i % 3) * 2, seed: i + 70)
            append(island, at: p, material: 1, decoration: true)
        }
    }

    mutating func palm(at p: SIMD2<Float>, floor: Float, height: Float, yaw: Float) {
        if let palm = imported[.treeTall] {
            let scale = height / palm.size.y
            var mesh = StageMeshBuffer()
            mesh.append(palm, transform: MX.t(world(p, floor)) * MX.ry(yaw) * MX.s(scale, scale, scale),
                        color: stageColor(0.5, 0.5, 0.5), windWeight: { smoothstep(palm.size.y * 0.65, palm.size.y, $0.y) * 0.5 })
            append(mesh, at: p, material: 3, decoration: true)
            return
        }
        var mesh = StageMeshBuffer()
        let lean = SIMD2<Float>(cos(yaw), sin(yaw)) * height * 0.17
        let rings = 8, sides = 7
        for r in 0..<rings {
            let a = Float(r) / Float(rings), b = Float(r + 1) / Float(rings)
            let ca = world(p + lean * a * a, floor + height * a), cb = world(p + lean * b * b, floor + height * b)
            for j in 0..<sides {
                let t = Float(j) * 2 * Float.pi / Float(sides), u = Float(j + 1) * 2 * Float.pi / Float(sides)
                let ra = height * 0.045 * (1 - 0.5 * a), rb = height * 0.045 * (1 - 0.5 * b)
                quad(&mesh, ca + [cos(t) * ra, 0, sin(t) * ra], ca + [cos(u) * ra, 0, sin(u) * ra],
                     cb + [cos(u) * rb, 0, sin(u) * rb], cb + [cos(t) * rb, 0, sin(t) * rb],
                     color: stageColor(0.45 + Float(r % 2) * 0.08, 0.29 + Float(r % 2) * 0.05, 0.11))
            }
        }
        let crown = world(p + lean, floor + height)
        for j in 0..<9 {
            let angle = yaw + Float(j) * 2 * .pi / 9
            frond(&mesh, base: crown, yaw: angle, length: height * 0.50, width: height * 0.105,
                  rise: height * (j % 3 == 0 ? 0.12 : 0.04), droop: height * 0.16, shade: Float(j % 3) * 0.035)
        }
        append(mesh, at: p, material: 2, decoration: true)
    }

    mutating func plants(at p: SIMD2<Float>, floor: Float, scale: Float) {
        var mesh = StageMeshBuffer()
        for i in 0..<9 {
            frond(&mesh, base: world(p, floor), yaw: Float(i) * 2.399, length: (1 + Float(i % 3) * 0.2) * scale,
                  width: 0.28 * scale, rise: 0.9 * scale, droop: 0.25 * scale, shade: Float(i % 3) * 0.03)
        }
        // Coral-red hibiscus gives the green clusters the reference board's small warm accents.
        for i in 0..<3 {
            let c = world(p + SIMD2(cos(Float(i) * 2.1), sin(Float(i) * 2.1)) * 0.5, floor + 0.5 * scale)
            for j in 0..<5 {
                let a = Float(j) * 2 * Float.pi / 5
                let b = a + 1.0
                triangle(&mesh, c, c + [cos(a) * 0.22, 0.10, sin(a) * 0.22], c + [cos(b) * 0.22, 0.10, sin(b) * 0.22], color: stageColor(0.96, 0.26, 0.12))
            }
        }
        append(mesh, at: p, material: 2, decoration: true)
    }

    mutating func arch(at p: SIMD2<Float>, yaw: Float) {
        if let arch = imported[.ruinArch] {
            let scale = 30 / max(arch.size.x, arch.size.z)
            var mesh = StageMeshBuffer()
            mesh.append(arch, transform: MX.t(world(p, -0.2)) * MX.ry(yaw) * MX.s(scale, scale, scale), color: stageColor(0.5, 0.5, 0.5))
            append(mesh, at: p, material: 3, decoration: true)
            return
        }
        var mesh = StageMeshBuffer()
        let c = cos(yaw), s = sin(yaw)
        func w(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { world(p) + SIMD3(c * x + s * z, y, -s * x + c * z) * 1.5 }
        for i in 0..<12 {
            let a = Float(i) * .pi / 12, b = Float(i + 1) * .pi / 12
            let oa = SIMD2<Float>(cos(a) * 10, sin(a) * 8 + 0.5), ob = SIMD2<Float>(cos(b) * 10, sin(b) * 8 + 0.5)
            let ia = SIMD2<Float>(cos(a) * 6.5, sin(a) * 5.5), ib = SIMD2<Float>(cos(b) * 6.5, sin(b) * 5.5)
            for z: Float in [-2.5, 2.5] { quad(&mesh, w(oa.x, oa.y, z), w(ob.x, ob.y, z), w(ib.x, ib.y, z), w(ia.x, ia.y, z), color: stageColor(0.50, 0.59, 0.57)) }
            quad(&mesh, w(oa.x, oa.y, -2.5), w(ob.x, ob.y, -2.5), w(ob.x, ob.y, 2.5), w(oa.x, oa.y, 2.5), color: stageColor(0.17, 0.45, 0.035))
            quad(&mesh, w(ia.x, ia.y, 2.5), w(ib.x, ib.y, 2.5), w(ib.x, ib.y, -2.5), w(ia.x, ia.y, -2.5), color: stageColor(0.40, 0.48, 0.46))
        }
        append(mesh, at: p, material: 1, decoration: true)
    }

    func boulder(_ mesh: inout StageMeshBuffer, at p: SIMD2<Float>, floor: Float, radius: Float, height: Float, seed: Int) {
        let segments = 9
        for i in 0..<segments {
            let a = Float(i) * 2 * .pi / Float(segments), b = Float(i + 1) * 2 * .pi / Float(segments)
            let pa = p + SIMD2(cos(a), sin(a)) * radius, pb = p + SIMD2(cos(b), sin(b)) * radius
            let qa = p + SIMD2(cos(a), sin(a)) * radius * 0.55, qb = p + SIMD2(cos(b), sin(b)) * radius * 0.55
            quad(&mesh, world(pa, floor), world(pb, floor), world(qb, floor + height * 0.75), world(qa, floor + height * 0.75), color: stageColor(0.64 + Float((i + seed) % 3) * 0.04, 0.73, 0.70))
            triangle(&mesh, world(qa, floor + height * 0.75), world(qb, floor + height * 0.75), world(p, floor + height), color: stageColor(0.25, 0.56, 0.11))
        }
    }

    func frond(_ mesh: inout StageMeshBuffer, base: SIMD3<Float>, yaw: Float, length: Float, width: Float, rise: Float, droop: Float, shade: Float) {
        let dir = SIMD3<Float>(cos(yaw), 0, sin(yaw)), side = SIMD3<Float>(-sin(yaw), 0, cos(yaw))
        let segments = 6
        for i in 0..<segments {
            let a = Float(i) / Float(segments), b = Float(i + 1) / Float(segments)
            func p(_ t: Float) -> SIMD3<Float> { base + dir * length * t + SIMD3(0, rise * sin(t * .pi) - droop * t * t, 0) }
            let wa = width * sin(a * .pi) + 0.015, wb = width * sin(b * .pi) + 0.004
            let centerA = p(a), centerB = p(b)
            let tint = stageColor(0.18 + shade + a * 0.06, 0.47 + shade + a * 0.15, 0.035 + shade, a * 0.35)
            quad(&mesh, centerA - side * wa, centerB - side * wb, centerB + [0, 0.05, 0], centerA + [0, 0.05, 0], color: tint)
            quad(&mesh, centerA + [0, 0.05, 0], centerB + [0, 0.05, 0], centerB + side * wb, centerA + side * wa, color: tint)
        }
    }

    func disc(_ mesh: inout StageMeshBuffer, at p: SIMD2<Float>, radius: Float, y: Float, color: SIMD4<UInt8>) {
        for i in 0..<32 {
            let a = Float(i) * .pi / 16, b = Float(i + 1) * .pi / 16
            triangle(&mesh, world(p, y), world(p + SIMD2(cos(a), sin(a)) * radius, y), world(p + SIMD2(cos(b), sin(b)) * radius, y), color: color)
        }
    }

    func triangle(_ mesh: inout StageMeshBuffer, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, color: SIMD4<UInt8>) {
        let cross = simd_cross(b - a, c - a)
        guard simd_length_squared(cross) > 0.000001 else { return }
        let n = simd_normalize(cross)
        let ia = mesh.addVertex(a, n, .zero, color), ib = mesh.addVertex(b, n, .zero, color), ic = mesh.addVertex(c, n, .zero, color)
        mesh.addTriangle(ia, ib, ic)
    }

    func quad(_ mesh: inout StageMeshBuffer, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, color: SIMD4<UInt8>) {
        triangle(&mesh, a, b, c, color: color)
        triangle(&mesh, a, c, d, color: color)
    }
}
