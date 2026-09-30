import CoreGraphics
import Foundation
import Metal
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。静的な戦場: 地面・外周の森・障害物（崖/岩/木）・草むら・泉・ボスの巣・河川の水面。
// 装飾は 30 m 格子のチャンク毎に 1 メッシュへ結合し（lit / glow の 2 マテリアル）、視錐台カリングを効かせる。

@MainActor
final class MapScene {
    let root = Entity()
    /// index = MapDefinition.brushes の添字。
    private(set) var brushEntities: [ModelEntity] = []
    private var translucentBrush: Int?
    private var waterModel: ModelEntity?
    private var waterMaterial: UnlitMaterial?
    private var waterTime: Float = 0
    private var waterAccumulator: Float = 0
    private(set) var fountainSpires: [Entity] = []

    /// 地図の境界（m）。
    static let mapMeters: Float = Float(Balance.mapSize / Balance.unitsPerMeter)

    init(map: MapDefinition, materials: RenderMaterials, quality: RenderQuality, groundImage: CGImage?) {
        root.name = "map"
        buildGround(image: groundImage, quality: quality)
        buildOuterGround()
        buildDecorations(map: map, materials: materials, quality: quality)
        buildBrushes(map: map, materials: materials, quality: quality)
        buildWater(map: map)
        buildGroundDecals(map: map, materials: materials)
        if quality.level != .low { buildDetailOverlay() }
    }

    // MARK: 地面

    private func buildGround(image: CGImage?, quality: RenderQuality) {
        let M = MapScene.mapMeters
        var d = MeshDescriptor(name: "ground")
        d.positions = MeshBuffers.Positions([[0, 0, 0], [M, 0, 0], [M, 0, -M], [0, 0, -M]])
        d.normals = MeshBuffers.Normals([[0, 1, 0], [0, 1, 0], [0, 1, 0], [0, 1, 0]])
        // sim (x, y) → 画像 (x, 上端から 1 - y)
        func uv(_ x: Float, _ y: Float) -> SIMD2<Float> {
            PaletteLayout.originBottomLeft ? SIMD2(x, y) : SIMD2(x, 1 - y)
        }
        d.textureCoordinates = MeshBuffers.TextureCoordinates([uv(0, 0), uv(1, 0), uv(1, 1), uv(0, 1)])
        d.primitives = .triangles([0, 1, 2, 0, 2, 3])
        guard let mesh = try? MeshResource.generate(from: [d]) else { return }
        var mat = PhysicallyBasedMaterial()
        if let image, let tex = try? TextureResource(image: image, options: .init(semantic: .color)) {
            var t = MaterialParameters.Texture(tex)
            let sd = MTLSamplerDescriptor()
            sd.minFilter = .linear
            sd.magFilter = .linear
            sd.mipFilter = .linear
            sd.sAddressMode = .clampToEdge
            sd.tAddressMode = .clampToEdge
            sd.maxAnisotropy = quality.level == .high ? 4 : (quality.level == .medium ? 2 : 1)
            t.sampler = .init(sd)
            mat.baseColor = .init(tint: .white, texture: t)
        } else {
            mat.baseColor = .init(tint: UIColor(red: 0.28, green: 0.48, blue: 0.25, alpha: 1))
        }
        mat.roughness = .init(floatLiteral: 0.95)
        mat.metallic = .init(floatLiteral: 0)
        mat.specular = .init(floatLiteral: 0.08)
        let ground = ModelEntity(mesh: mesh, materials: [mat])
        ground.name = "ground"
        root.addChild(ground)
    }

    private func buildOuterGround() {
        let M = MapScene.mapMeters
        let size: Float = M + 140
        let mesh = MeshResource.generatePlane(width: size, depth: size)
        var mat = PhysicallyBasedMaterial()
        if let img = GroundTextureGenerator.outerImage(),
           let tex = try? TextureResource(image: img, options: .init(semantic: .color)) {
            var t = MaterialParameters.Texture(tex)
            let sd = MTLSamplerDescriptor()
            sd.minFilter = .linear
            sd.magFilter = .linear
            sd.mipFilter = .linear
            sd.sAddressMode = .repeat
            sd.tAddressMode = .repeat
            t.sampler = .init(sd)
            mat.baseColor = .init(tint: .white, texture: t)
            mat.textureCoordinateTransform = .init(scale: SIMD2(12, 12))
        } else {
            mat.baseColor = .init(tint: UIColor(red: 0.10, green: 0.20, blue: 0.13, alpha: 1))
        }
        mat.roughness = .init(floatLiteral: 1)
        mat.metallic = .init(floatLiteral: 0)
        let outer = ModelEntity(mesh: mesh, materials: [mat])
        outer.name = "outerGround"
        outer.position = [M / 2, -0.04, -M / 2]
        root.addChild(outer)
    }

    // MARK: 装飾（チャンク結合）

    private struct ChunkBatch {
        var lit: [Int: MeshBuilder] = [:]
        var glow: [Int: MeshBuilder] = [:]
        static let chunk: Float = 30

        static func key(_ p: SIMD3<Float>) -> Int {
            let cx = Int(floor(p.x / chunk)) + 3
            let cz = Int(floor(-p.z / chunk)) + 3
            return max(0, min(15, cz)) * 16 + max(0, min(15, cx))
        }

        mutating func add(at p: SIMD3<Float>, _ body: (inout MeshBuilder, inout MeshBuilder) -> Void) {
            let k = ChunkBatch.key(p)
            var l = lit[k] ?? MeshBuilder(reserve: 4096)
            var g = glow[k] ?? MeshBuilder()
            body(&l, &g)
            lit[k] = l
            glow[k] = g
        }
    }

    private func buildDecorations(map: MapDefinition, materials: RenderMaterials, quality: RenderQuality) {
        var batch = ChunkBatch()
        var rng = RenderRNG(seed: 0xDEC0)
        let density = quality.decorationDensity
        let treeKinds: [TreeKind] = [.round, .round, .pine, .teal, .round, .autumn, .pine]

        func w(_ p: Vec2, _ h: Float = 0) -> SIMD3<Float> { worldPosition(p, height: h) }

        // 障害物: 崖の塊 + 木
        for (oi, o) in map.obstacles.enumerated() {
            let seed = UInt64(oi) &* 7919
            switch o {
            case .rect(let r):
                let wM = Float(r.width / 100), hM = Float(r.height / 100)
                let step: Float = 1.35
                let nx = max(1, Int(wM / step)), ny = max(1, Int(hM / step))
                for ix in 0...nx {
                    for iy in 0...ny {
                        let fx = (Float(ix) + 0.5) / Float(nx + 1), fy = (Float(iy) + 0.5) / Float(ny + 1)
                        let jitter = Vec2(Double(rng.range(-0.35, 0.35)) * 100, Double(rng.range(-0.35, 0.35)) * 100)
                        let p = Vec2(r.minX + Double(fx) * r.width, r.minY + Double(fy) * r.height) + jitter
                        let edge = ix == 0 || iy == 0 || ix == nx || iy == ny
                        let h = edge ? rng.range(1.0, 1.7) : rng.range(1.5, 2.3)
                        let rad = rng.range(0.85, 1.25)
                        batch.add(at: w(p)) { l, _ in
                            MapProps.cliff(&l, at: w(p), radius: rad, height: h, seed: seed &+ UInt64(ix * 97 + iy))
                        }
                    }
                }
                // 木（内側）
                let treeCount = Int(Float(max(1, Int(wM * hM / 7))) * density)
                for k in 0..<treeCount {
                    let p = Vec2(r.minX + 60 + Double(rng.nextFloat()) * (r.width - 120),
                                 r.minY + 60 + Double(rng.nextFloat()) * (r.height - 120))
                    let kind = treeKinds[Int(rng.nextFloat() * Float(treeKinds.count)) % treeKinds.count]
                    let h = rng.range(2.8, 3.8)
                    batch.add(at: w(p)) { l, _ in
                        MapProps.tree(&l, at: w(p, 1.1), height: h, kind: kind, seed: seed &+ UInt64(1000 + k))
                    }
                }
                // 縁の岩と光る結晶
                let perimeterRocks = Int(Float(Int((wM + hM) * 2 / 2.2)) * density)
                for k in 0..<perimeterRocks {
                    let t = rng.nextFloat() * 4
                    let side = Int(t)
                    let f = Double(t - Float(side))
                    let p: Vec2
                    switch side {
                    case 0: p = Vec2(r.minX + f * r.width, r.minY - 40)
                    case 1: p = Vec2(r.maxX + 40, r.minY + f * r.height)
                    case 2: p = Vec2(r.minX + f * r.width, r.maxY + 40)
                    default: p = Vec2(r.minX - 40, r.minY + f * r.height)
                    }
                    let s = rng.range(0.3, 0.6)
                    let crystal = rng.chance(0.12)
                    batch.add(at: w(p)) { l, g in
                        MapProps.rock(&l, at: w(p), size: s, seed: seed &+ UInt64(5000 + k), mossy: rng.chance(0.4))
                        if crystal {
                            MapProps.smallFlora(&l, glow: &g, at: w(p + Vec2(60, 40)), seed: seed &+ UInt64(8000 + k) | 1)
                        }
                    }
                }
            case .circle(let c, let radius):
                let rM = Float(radius / 100)
                batch.add(at: w(c)) { l, g in
                    // 中央の高い柱 + 周囲の低い柱（崖の塊）
                    MapProps.cliff(&l, at: w(c), radius: min(1.3, rM * 0.55), height: rng.range(1.7, 2.2), seed: seed)
                    let n = max(3, Int(rM * 2.2))
                    for k in 0..<n {
                        let a = Float(k) / Float(n) * 6.28 + rng.range(0, 0.5)
                        let p = c + Vec2(Double(cos(a)), Double(sin(a))) * radius * 0.62
                        MapProps.cliff(&l, at: w(p), radius: rng.range(0.6, 0.9), height: rng.range(0.9, 1.5),
                                       seed: seed &+ UInt64(k + 1))
                    }
                    for k in 0..<(n + 2) {
                        let a = rng.range(0, 6.28)
                        let p = c + Vec2(Double(cos(a)), Double(sin(a))) * (radius + 30)
                        MapProps.rock(&l, at: w(p), size: rng.range(0.22, 0.42), seed: seed &+ UInt64(50 + k), mossy: rng.chance(0.5))
                    }
                    if rM > 2.2 && rng.chance(0.8 * density) {
                        MapProps.tree(&l, at: w(c + Vec2(Double(rng.range(-50, 50)), 60), 1.4), height: rng.range(2.8, 3.4),
                                      kind: treeKinds[Int(rng.nextFloat() * 7) % 7], seed: seed &+ 99)
                    }
                    if rng.chance(0.35) {
                        MapProps.smallFlora(&l, glow: &g, at: w(c + Vec2(radius + 40, 0)), seed: seed &+ 7)
                    }
                }
            }
        }

        // 外周の森（地図の外側 1.5〜14 m）
        let M = MapScene.mapMeters
        let ringStep: Float = 2.6 / max(0.6, density)
        for side in 0..<4 {
            var t: Float = -14
            while t < M + 14 {
                for row in 0..<4 {
                    let depth = 1.8 + Float(row) * 3.1 + rng.range(-0.8, 0.8)
                    let along = t + rng.range(-0.9, 0.9) + (row % 2 == 0 ? 0 : ringStep / 2)
                    let p: SIMD3<Float>
                    switch side {
                    case 0: p = [along, 0, depth]                 // 南（sim y < 0）
                    case 1: p = [along, 0, -M - depth]            // 北
                    case 2: p = [-depth, 0, -along]               // 西
                    default: p = [M + depth, 0, -along]           // 東
                    }
                    let seed = UInt64(side * 100_000 + row * 10_000) &+ UInt64(max(0, Int((t + 20) * 10)))
                    batch.add(at: p) { l, _ in
                        if row == 0 && rng.chance(0.45) {
                            MapProps.cliff(&l, at: p, radius: rng.range(1.0, 1.6), height: rng.range(0.8, 1.8), seed: seed)
                        } else {
                            let kind: TreeKind = row >= 2 ? (rng.chance(0.6) ? .pine : .teal) : treeKinds[Int(rng.nextFloat() * 7) % 7]
                            MapProps.tree(&l, at: p, height: rng.range(3.8, 5.6), kind: kind, seed: seed)
                        }
                    }
                }
                t += ringStep
            }
        }

        // ジャングルの小物（レーン・河川・構造物・キャンプから離れた場所のみ）
        let floraCount = Int(260 * density)
        var placed = 0, attempts = 0
        while placed < floraCount && attempts < floraCount * 8 {
            attempts += 1
            let p = Vec2(Double(rng.range(300, 11700)), Double(rng.range(300, 11700)))
            guard map.nearestLane(to: p).distance > 650, !map.isInRiver(p),
                  map.obstacleIndex(at: p, inflatedBy: 60) == nil, map.brushIndex(at: p) == nil else { continue }
            guard !map.camps.contains(where: { $0.pos.distance(to: p) < 650 }),
                  p.distance(to: map.fountain(.blue)) > 2600, p.distance(to: map.fountain(.red)) > 2600 else { continue }
            placed += 1
            let seed = UInt64(placed) &* 131
            batch.add(at: w(p)) { l, g in MapProps.smallFlora(&l, glow: &g, at: w(p), seed: seed) }
        }

        // 泉（台座 + 柱 + 浮遊結晶）とレーン入口の門柱
        for team in Team.players {
            let f = map.fountain(team)
            let crystalRamp: Ramp = team == .blue ? .crystalBlue : .crystalRed
            let rune: Swatch = team == .blue ? .glowBlue : .glowRed
            batch.add(at: w(f)) { l, g in
                l.frustum(bottomRadius: 3.4, topRadius: 3.1, height: 0.22, segments: 16, color: .solid(.stoneDark),
                          transform: MX.t(w(f)))
                l.frustum(bottomRadius: 2.2, topRadius: 1.9, height: 0.42, segments: 16, color: .solid(.stone),
                          transform: MX.t(w(f)))
                g.annulus(inner: 2.55, outer: 2.8, segments: 32, y: 0.235, color: .solid(rune), transform: MX.t(w(f)))
                for k in 0..<6 {
                    let a = Float(k) / 6 * 2 * .pi + 0.3
                    let pp = w(f) + SIMD3(cos(a) * 3.0, 0, -sin(a) * 3.0)
                    MapProps.pillar(&l, glow: &g, at: pp, height: 1.6, rune: rune, seed: UInt64(team.rawValue * 10 + k))
                }
                g.crystal(radius: 0.28, height: 0.9, color: .ramp(crystalRamp, from: 0.3, to: 1),
                          transform: MX.t(w(f, 0.42)) * MX.ry(0.4))
            }
            // 泉の浮遊結晶（回転させるので別エンティティ）
            var sb = MeshBuilder()
            sb.crystal(radius: 0.55, height: 2.2, sides: 6, color: .ramp(crystalRamp, from: 0.2, to: 1))
            if let mesh = sb.makeMesh(name: "fountainSpire") {
                let spire = ModelEntity(mesh: mesh, materials: [materials.glow])
                spire.position = w(f, 1.6)
                root.addChild(spire)
                fountainSpires.append(spire)
            }
            let core = map.core(team)
            for lane in Lane.allCases {
                let path = map.lanePath(lane, for: team)
                guard path.count >= 2 else { continue }
                let dir = (path[1] - core).normalized
                let gate = core + dir * 1560
                let nrm = dir.perpendicular
                for s in [-1.0, 1.0] {
                    let p = gate + nrm * (420 * s)
                    batch.add(at: w(p)) { l, g in
                        MapProps.pillar(&l, glow: &g, at: w(p), height: 2.0, rune: rune, seed: UInt64(lane.rawValue * 7 + (s > 0 ? 1 : 0)))
                    }
                }
            }
        }

        // ボスの巣の縁石
        for camp in map.camps where camp.kind == .astralWyrm || camp.kind == .ancientColossus {
            let rune: Swatch = camp.kind == .astralWyrm ? .glowPurple : .glowGold
            let n = 8
            for k in 0..<n {
                let a = Double(k) / Double(n) * 2 * .pi + .pi / 8
                let p = camp.pos + Vec2(cos(a), sin(a)) * 740
                batch.add(at: w(p)) { l, g in
                    MapProps.pillar(&l, glow: &g, at: w(p), height: 1.0, rune: rune, broken: k % 3 == 1,
                                    seed: UInt64(camp.id * 31 + k))
                }
            }
        }

        // チャンク → エンティティ
        for key in batch.lit.keys.sorted() {
            if let mesh = batch.lit[key]?.makeMesh(name: "deco_\(key)") {
                let e = ModelEntity(mesh: mesh, materials: [materials.lit])
                e.name = "deco_\(key)"
                root.addChild(e)
            }
            if let mesh = batch.glow[key]?.makeMesh(name: "glow_\(key)") {
                let e = ModelEntity(mesh: mesh, materials: [materials.glow])
                e.name = "glow_\(key)"
                root.addChild(e)
            }
        }
    }

    // MARK: 地面の輪郭（テクスチャでは滲む細部を平面メッシュで描く）

    private func buildGroundDecals(map: MapDefinition, materials: RenderMaterials) {
        var lit = MeshBuilder(reserve: 4096), glow = MeshBuilder(reserve: 2048)
        let y: Float = 0.012
        for team in Team.players {
            let soft: Swatch = team == .blue ? .glowBlueSoft : .glowRedSoft
            let strong: Swatch = team == .blue ? .glowBlue : .glowRed
            let core = worldPosition(map.core(team)), fountain = worldPosition(map.fountain(team))
            // 広場の石畳（24 分割 × 5 環、目地を残す）
            var r: Float = 4.6
            var ring = 0
            while r < 14.2 {
                let r1 = r + 1.85
                let segs = 24 + ring * 4
                for k in 0..<segs {
                    let a0 = Float(k) / Float(segs) * 2 * .pi + Float(ring) * 0.13
                    let sweep = 2 * .pi / Float(segs) - 0.06 / r1
                    let shades: [Swatch] = [.paving1, .paving2, .paving3, .paving4, .paving2]
                    let shade = shades[(k * 7 + ring * 3) % shades.count]
                    lit.annulus(inner: r + 0.05, outer: r1 - 0.05, segments: 3, y: y, startAngle: a0, sweep: sweep,
                                color: .solid(shade), transform: MX.t(core))
                }
                r = r1
                ring += 1
            }
            glow.annulus(inner: 13.05, outer: 13.45, segments: 72, y: y + 0.004, color: .solid(strong), transform: MX.t(core))
            glow.annulus(inner: 12.45, outer: 12.6, segments: 72, y: y + 0.004, color: .solid(soft), transform: MX.t(core))
            glow.annulus(inner: 4.35, outer: 4.55, segments: 40, y: y + 0.004, color: .solid(soft), transform: MX.t(core))
            // 泉の紋章
            glow.annulus(inner: 6.95, outer: 7.45, segments: 64, y: y, color: .solid(strong), transform: MX.t(fountain))
            glow.annulus(inner: 5.1, outer: 5.3, segments: 56, y: y, color: .solid(soft), transform: MX.t(fountain))
            for k in 0..<8 {
                let a0 = Float(k) / 8 * 2 * .pi, a1 = Float(k + 3) / 8 * 2 * .pi
                let p0 = SIMD3<Float>(cos(a0) * 7.0, 0, -sin(a0) * 7.0), p1 = SIMD3<Float>(cos(a1) * 7.0, 0, -sin(a1) * 7.0)
                let d = p1 - p0
                let len = simd_length(d)
                let yaw = atan2(-d.z, d.x)
                glow.flatRect(width: len, depth: 0.14, y: y, color: .solid(soft),
                              transform: MX.t(fountain + (p0 + p1) / 2) * MX.ry(yaw))
            }
        }
        // タワー台座の輪
        for t in map.towers where !t.isCore {
            let soft: Swatch = t.team == .blue ? .glowBlueSoft : .glowRedSoft
            glow.annulus(inner: 2.28, outer: 2.48, segments: 40, y: y, color: .solid(soft), transform: MX.t(worldPosition(t.pos)))
        }
        // ボスの巣の紋章
        for camp in map.camps where camp.kind == .astralWyrm || camp.kind == .ancientColossus {
            let rune: Swatch = camp.kind == .astralWyrm ? .glowPurple : .glowGold
            let c = worldPosition(camp.pos)
            glow.annulus(inner: 4.55, outer: 4.85, segments: 64, y: y, color: .solid(rune), transform: MX.t(c))
            glow.annulus(inner: 3.72, outer: 3.86, segments: 56, y: y, color: .solid(rune), transform: MX.t(c))
            for k in 0..<6 {
                let a = Float(k) / 6 * 2 * .pi + 0.26
                glow.star(outer: 0.34, inner: 0.15, thickness: 0.01, points: 4, color: .solid(rune),
                          transform: MX.t(c + SIMD3(cos(a) * 4.25, y, -sin(a) * 4.25)))
            }
        }
        if let mesh = lit.makeMesh(name: "decalsLit") {
            let e = ModelEntity(mesh: mesh, materials: [materials.lit])
            e.name = "decalsLit"
            root.addChild(e)
        }
        if let mesh = glow.makeMesh(name: "decalsGlow") {
            let e = ModelEntity(mesh: mesh, materials: [materials.glow])
            e.name = "decalsGlow"
            root.addChild(e)
        }
    }

    /// 細かな砂粒・草の斑点のタイル（3 m 周期）を地面へ重ね、拡大時のぼけを抑える。
    private func buildDetailOverlay() {
        guard let img = MapScene.detailImage(),
              let tex = try? TextureResource(image: img, options: .init(semantic: .color)) else { return }
        let M = MapScene.mapMeters
        var d = MeshDescriptor(name: "detail")
        d.positions = MeshBuffers.Positions([[0, 0, 0], [M, 0, 0], [M, 0, -M], [0, 0, -M]])
        d.normals = MeshBuffers.Normals([[0, 1, 0], [0, 1, 0], [0, 1, 0], [0, 1, 0]])
        let tiles = M / 3
        d.textureCoordinates = MeshBuffers.TextureCoordinates([[0, 0], [tiles, 0], [tiles, tiles], [0, tiles]])
        d.primitives = .triangles([0, 1, 2, 0, 2, 3])
        guard let mesh = try? MeshResource.generate(from: [d]) else { return }
        var mat = UnlitMaterial(applyPostProcessToneMap: false)
        var t = MaterialParameters.Texture(tex)
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.mipFilter = .linear
        sd.sAddressMode = .repeat
        sd.tAddressMode = .repeat
        t.sampler = .init(sd)
        mat.color = .init(tint: .white, texture: t)
        mat.blending = .transparent(opacity: .init(floatLiteral: 1))
        mat.writesDepth = false
        let e = ModelEntity(mesh: mesh, materials: [mat])
        e.name = "groundDetail"
        e.position.y = 0.004
        OverlayOrder.apply(e, OverlayOrder.groundDetail)
        root.addChild(e)
    }

    static func detailImage(size: Int = 256) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var rng = RenderRNG(seed: 777)
        let s = CGFloat(size)
        for _ in 0..<900 {
            let x = CGFloat(rng.range(0, Float(size))), y = CGFloat(rng.range(0, Float(size)))
            let r = CGFloat(rng.range(0.8, 2.6))
            let dark = rng.chance(0.62)
            let a = CGFloat(rng.range(0.10, dark ? 0.26 : 0.16))
            let c: CGColor = dark ? CGColor(srgbRed: 0.02, green: 0.05, blue: 0.02, alpha: a)
                : CGColor(srgbRed: 1, green: 1, blue: 0.85, alpha: a)
            ctx.setFillColor(c)
            // タイル境界で継ぎ目が出ないよう周囲にも複製
            for dx in [-s, 0, s] {
                for dy in [-s, 0, s] {
                    ctx.fillEllipse(in: CGRect(x: x + dx - r, y: y + dy - r * 0.7, width: r * 2, height: r * 1.4))
                }
            }
        }
        // 短い草の筆致
        ctx.setLineCap(.round)
        for _ in 0..<260 {
            let x = CGFloat(rng.range(0, Float(size))), y = CGFloat(rng.range(0, Float(size)))
            let len = CGFloat(rng.range(2, 5))
            let ang = CGFloat(rng.range(1.2, 1.9))
            ctx.setStrokeColor(CGColor(srgbRed: 0.02, green: 0.08, blue: 0.02, alpha: CGFloat(rng.range(0.08, 0.2))))
            ctx.setLineWidth(1)
            for dx in [-s, 0, s] {
                for dy in [-s, 0, s] {
                    ctx.move(to: CGPoint(x: x + dx, y: y + dy))
                    ctx.addLine(to: CGPoint(x: x + dx + cos(ang) * len, y: y + dy + sin(ang) * len))
                    ctx.strokePath()
                }
            }
        }
        return ctx.makeImage()
    }

    // MARK: 草むら

    private func buildBrushes(map: MapDefinition, materials: RenderMaterials, quality: RenderQuality) {
        for b in map.brushes {
            var mb = MeshBuilder(reserve: 2048)
            let r = b.rect
            let step: Float = quality.level == .low ? 0.62 : 0.5
            let wM = Float(r.width / 100), hM = Float(r.height / 100)
            let nx = max(1, Int(wM / step)), ny = max(1, Int(hM / step))
            var rng = RenderRNG(seed: UInt64(b.id) &* 613)
            let center = worldPosition(r.center)
            for ix in 0..<nx {
                for iy in 0..<ny {
                    let lx = (Float(ix) + 0.5) / Float(nx) * wM - wM / 2 + rng.range(-0.18, 0.18)
                    let lz = -((Float(iy) + 0.5) / Float(ny) * hM - hM / 2) + rng.range(-0.18, 0.18)
                    mb.grassClump(at: [lx, 0, lz], height: rng.range(0.95, 1.35), seed: rng.next())
                }
            }
            guard let mesh = mb.makeMesh(name: "brush_\(b.id)") else { continue }
            let e = ModelEntity(mesh: mesh, materials: [materials.lit])
            e.name = "brush_\(b.id)"
            e.position = center
            root.addChild(e)
            brushEntities.append(e)
        }
    }

    /// 視点ヒーローが入っている草むらを半透明にする（nil で全て不透明）。
    func setTranslucentBrush(_ index: Int?) {
        guard index != translucentBrush else { return }
        if let old = translucentBrush, old < brushEntities.count {
            brushEntities[old].components.remove(OpacityComponent.self)
        }
        if let i = index, i < brushEntities.count {
            brushEntities[i].components.set(OpacityComponent(opacity: 0.38))
        }
        translucentBrush = index
    }

    // MARK: 水面

    private func buildWater(map: MapDefinition) {
        guard let img = MapScene.waterHighlightImage(),
              let tex = try? TextureResource(image: img, options: .init(semantic: .color)) else { return }
        let length: Float = MapScene.mapMeters * 1.42 + 10
        let width = Float(map.riverWidth / 100) * 0.92
        var d = MeshDescriptor(name: "water")
        let hw = width / 2, hl = length / 2
        d.positions = MeshBuffers.Positions([[-hl, 0, hw], [hl, 0, hw], [hl, 0, -hw], [-hl, 0, -hw]])
        d.normals = MeshBuffers.Normals([[0, 1, 0], [0, 1, 0], [0, 1, 0], [0, 1, 0]])
        let tilesU = length / 6, tilesV = width / 6
        d.textureCoordinates = MeshBuffers.TextureCoordinates([[0, 0], [tilesU, 0], [tilesU, tilesV], [0, tilesV]])
        d.primitives = .triangles([0, 1, 2, 0, 2, 3])
        guard let mesh = try? MeshResource.generate(from: [d]) else { return }
        var mat = UnlitMaterial(applyPostProcessToneMap: false)
        var t = MaterialParameters.Texture(tex)
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.mipFilter = .linear
        sd.sAddressMode = .repeat
        sd.tAddressMode = .repeat
        t.sampler = .init(sd)
        mat.color = .init(tint: UIColor(red: 0.75, green: 0.95, blue: 1.0, alpha: 1), texture: t)
        mat.blending = .transparent(opacity: .init(floatLiteral: 0.6))
        mat.writesDepth = false
        let e = ModelEntity(mesh: mesh, materials: [mat])
        e.name = "water"
        let M = MapScene.mapMeters
        e.position = [M / 2, 0.025, -M / 2]
        // 河川は sim (0,12000)→(12000,0) = world (0,-120)→(120,0)（+x かつ +z 方向）
        e.orientation = simd_quatf(angle: -.pi / 4, axis: [0, 1, 0])
        root.addChild(e)
        waterModel = e
        waterMaterial = mat
    }

    /// 水面のきらめきを流す（15Hz でマテリアル更新）。
    func update(dt: Float) {
        waterTime += dt
        waterAccumulator += dt
        for (k, s) in fountainSpires.enumerated() {
            s.orientation = simd_quatf(angle: waterTime * 0.6 + Float(k), axis: [0, 1, 0])
            s.position.y = 1.6 + sin(waterTime * 1.3 + Float(k)) * 0.12
        }
        guard waterAccumulator >= 1.0 / 15.0, var mat = waterMaterial, let model = waterModel else { return }
        waterAccumulator = 0
        mat.textureCoordinateTransform = .init(offset: SIMD2(waterTime * 0.035, waterTime * 0.011))
        waterMaterial = mat
        model.model?.materials = [mat]
    }

    static func waterHighlightImage(size: Int = 256) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var rng = RenderRNG(seed: 404)
        ctx.setLineCap(.round)
        for _ in 0..<70 {
            let x = CGFloat(rng.range(0, Float(size))), y = CGFloat(rng.range(0, Float(size)))
            let len = CGFloat(rng.range(12, 46))
            let a = CGFloat(rng.range(0.15, 0.55))
            ctx.setStrokeColor(CGColor(srgbRed: a, green: a, blue: a, alpha: a))
            ctx.setLineWidth(CGFloat(rng.range(1.5, 3.5)))
            // 端をまたぐ線はタイルの反対側にも描く（継ぎ目なし）
            for dx in [-CGFloat(size), 0, CGFloat(size)] {
                for dy in [-CGFloat(size), 0, CGFloat(size)] {
                    ctx.move(to: CGPoint(x: x + dx, y: y + dy))
                    ctx.addQuadCurve(to: CGPoint(x: x + len + dx, y: y + dy),
                                     control: CGPoint(x: x + len / 2 + dx, y: y + 3 + dy))
                    ctx.strokePath()
                }
            }
        }
        return ctx.makeImage()
    }
}

private extension MeshBuilder {
    mutating func grassClump(at p: SIMD3<Float>, height: Float, seed: UInt64) {
        MapProps.grassClump(&self, at: p, height: height, seed: seed)
    }
}
