import CoreGraphics
import Foundation
import VelstriaCore
import Metal
import RealityKit
import UIKit

// 担当: battle-renderer（ステージ）。StagePlan から地面・崖・小物・草花・草むら・祭壇の円盤のエンティティを作る（main actor）。
// 材質はすべて CustomMaterial（tools/stage/shaders/StageShaders.metal を事前コンパイルした metallib）。
// 作れない環境では nil を返し、MapScene が従来の手続き生成の地形に戻す。

@MainActor
final class StageScene {
    let root = Entity()
    /// index = MapDefinition.brushes の添字。
    private(set) var brushEntities: [ModelEntity] = []
    private(set) var triangleCount = 0
    /// 素材のセット（StageArtSet）。
    let artSet: StageArtSet
    /// 泉の台座の柱の頂部（world、Team.players の順）。台座の無いセットでは空（MapScene が旧来の泉を作る）。
    let fountainSockets: [[SIMD3<Float>]]
    private var brushLODs: [(near: MeshResource, far: MeshResource)] = []
    private var brushIsFar: [Bool] = []
    private var lodElapsed: Float = 0

    struct Materials {
        var ground: CustomMaterial
        var rock: CustomMaterial
        var prop: CustomMaterial
        var flora: CustomMaterial
        var brush: CustomMaterial
        var rune: PhysicallyBasedMaterial
        var sanctuary: CustomMaterial?
        var field: CustomMaterial?
    }

    init?(plan: StagePlan) {
        root.name = "stage"
        let procedural: ProceduralStagePlan
        switch plan {
        case .canyon(let imported):
            artSet = .ruins
            fountainSockets = []
            guard buildCanyon(imported) else { return nil }
            return
        case .procedural(let value): procedural = value
        }
        let plan = procedural
        artSet = plan.assets.set
        fountainSockets = plan.layout.fountainSockets
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let materials = StageScene.makeMaterials(plan: plan) else {
            StagePrep.log.error("stage materials unavailable; falling back to procedural terrain")
            return nil
        }
        let t1 = CFAbsoluteTimeGetCurrent()
        defer {
            StagePrep.log.notice("""
                stage scene: materials \(Int((t1 - t0) * 1000))ms meshes \(Int((CFAbsoluteTimeGetCurrent() - t1) * 1000))ms \
                entities \(self.root.children.count) tris \(self.triangleCount)
                """)
        }
        buildGround(material: materials.ground)
        add(plan.layout.edgeSkirt, name: "stageEdgeSkirt", material: materials.flora, castsShadow: false)
        let chunks = plan.layout.chunks
        for key in Set(chunks.props.keys).union(chunks.rocks.keys).union(chunks.flora.keys).sorted() {
            add(chunks.rocks[key], name: "stageRock_\(key)", material: materials.rock)
            add(chunks.props[key], name: "stageProp_\(key)", material: materials.prop)
            add(chunks.flora[key], name: "stageFlora_\(key)", material: materials.flora, castsShadow: false)
        }
        if let material = materials.sanctuary {
            for key in chunks.sanctuaries.keys.sorted() {
                AssetLedger.record(.mesh, "sanctuary chunk")
                AssetLedger.record(.entity, "sanctuary chunk")
                add(chunks.sanctuaries[key], name: "stageSanctuary_\(key)", material: material)
            }
        }
        if let material = materials.field {
            for key in chunks.fieldProps.keys.sorted() {
                AssetLedger.record(.mesh, "field prop chunk")
                AssetLedger.record(.entity, "field prop chunk")
                add(chunks.fieldProps[key], name: "stageField_\(key)", material: material)
            }
        }
        for (i, buf) in plan.layout.brushes.enumerated() {
            // 両LODをロード中に準備。失敗時はステージ全体を既存の手続き地形へ戻す。
            guard let near = buf.makeMesh(), let far = plan.layout.brushCards[i].makeMesh() else { return nil }
            AssetLedger.record(.mesh, "brush near")
            AssetLedger.record(.mesh, "brush far")
            AssetLedger.record(.entity, "brush")
            var brushMaterial = materials.brush
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-brushLegacy") { brushMaterial = materials.flora }
            #endif
            let e = ModelEntity(mesh: near, materials: [brushMaterial])
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            brushLODs.append((near, far))
            brushIsFar.append(false)
            e.name = "brush_\(i)"
            e.position = plan.layout.brushCenters[i]
            triangleCount += buf.triangleCount
            root.addChild(e)
            brushEntities.append(e)
        }
        if let disc = add(plan.layout.runeDiscs, name: "stageRunes", material: materials.rune, castsShadow: false) {
            disc.name = "stageRunes"
        }
    }

    private func buildCanyon(_ plan: CanyonStagePlan) -> Bool {
        guard let lib = Self.shaderLibrary(plan.shaderURL) else { return false }
        do {
            var materials: [CustomMaterial] = []
            for image in plan.atlases {
                AssetLedger.record(.texture, "canyon atlas 2048x1024")
                let texture = try TextureResource(image: image, options: .init(semantic: .color))
                AssetLedger.record(.material, "canyon cutout")
                var material = try CustomMaterial(surfaceShader: .init(named: "stageCanyonSurface", in: lib), lightingModel: .unlit)
                material.baseColor = .init(texture: .init(texture))
                material.faceCulling = .none
                materials.append(material)
            }
            for (i, chunk) in plan.chunks.enumerated() {
                AssetLedger.record(.mesh, "canyon chunk")
                AssetLedger.record(.entity, "canyon chunk")
                guard add(chunk.mesh, name: "canyon_\(i)", material: materials[chunk.atlas], castsShadow: false) != nil else { return false }
            }
            AssetLedger.record(.texture, "canyon brush atlas")
            let texture = try TextureResource(image: plan.brushAtlas, options: .init(semantic: .color))
            AssetLedger.record(.material, "canyon brush")
            var material = try CustomMaterial(surfaceShader: .init(named: "stageBrushSurface", in: lib), lightingModel: .lit)
            material.baseColor = .init(texture: .init(texture))
            material.faceCulling = .none
            for i in plan.brushes.brushes.indices {
                AssetLedger.record(.mesh, "canyon brush near")
                AssetLedger.record(.mesh, "canyon brush far")
                guard let near = plan.brushes.brushes[i].makeMesh(), let far = plan.brushes.brushCards[i].makeMesh() else { return false }
                AssetLedger.record(.entity, "canyon brush")
                let e = ModelEntity(mesh: near, materials: [material])
                e.name = "brush_\(i)"
                e.position = plan.brushes.brushCenters[i]
                e.components.set(DynamicLightShadowComponent(castsShadow: false))
                root.addChild(e)
                brushEntities.append(e)
                brushLODs.append((near, far))
                brushIsFar.append(false)
                triangleCount += plan.brushes.brushes[i].triangleCount
            }
            return true
        } catch { return false }
    }

    /// Distance from camera to nearest brush edge, with hysteresis. Only swaps cached meshes.
    func updateBrushLOD(camera: SIMD3<Float>, dt: Float) {
        lodElapsed += dt
        guard lodElapsed >= 0.2 else { return }
        lodElapsed = 0
        for i in brushEntities.indices {
            let e = brushEntities[i]
            let bounds = brushLODs[i].near.bounds
            let lo = e.position + bounds.min, hi = e.position + bounds.max
            let nearest = simd_min(simd_max(camera, lo), hi)
            let distance = simd_distance(camera, nearest)
            let far = distance > (brushIsFar[i] ? 29 : 34)
            guard far != brushIsFar[i] else { continue }
            e.model?.mesh = far ? brushLODs[i].far : brushLODs[i].near
            brushIsFar[i] = far
        }
    }

    @discardableResult
    private func add(_ buf: StageMeshBuffer?, name: String, material: any RealityKit.Material,
                     castsShadow: Bool = true) -> ModelEntity? {
        guard let buf, let mesh = buf.makeMesh() else { return nil }
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.name = name
        if !castsShadow { e.components.set(DynamicLightShadowComponent(castsShadow: false)) }
        triangleCount += buf.triangleCount
        root.addChild(e)
        return e
    }

    /// 地面: 地図の外 70 m まで覆う 1 枚の板（配合マップの外は端の値＝森の下草が続く）。
    private func buildGround(material: CustomMaterial) {
        var b = StageMeshBuffer(reserveVertices: 4)
        let lo: Float = -70, hi: Float = Float(MapDefinition.relayout.size / Balance.unitsPerMeter) + 70
        let up = SIMD3<Float>(0, 1, 0)
        let c = stageColor(0.5, 0.5, 0.5, 0)
        let i0 = b.addVertex([lo, GroundLayer.ground, -lo], up, [0, 0], c)
        let i1 = b.addVertex([hi, GroundLayer.ground, -lo], up, [1, 0], c)
        let i2 = b.addVertex([hi, GroundLayer.ground, -hi], up, [1, 1], c)
        let i3 = b.addVertex([lo, GroundLayer.ground, -hi], up, [0, 1], c)
        b.addTriangle(i0, i1, i2)
        b.addTriangle(i0, i2, i3)
        if let e = add(b, name: "ground", material: material, castsShadow: false) {
            e.name = "ground"
        }
    }

    // MARK: 材質

    static func shaderLibrary(_ url: URL) -> MTLLibrary? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return try? device.makeLibrary(URL: url)
    }

    static func makeMaterials(plan: ProceduralStagePlan) -> Materials? {
        guard let lib = shaderLibrary(plan.assets.shaderURL) else { return nil }
        let a = plan.assets
        func color(_ img: CGImage) -> TextureResource? {
            try? TextureResource(image: img, options: .init(semantic: .color))
        }
        func raw(_ img: CGImage) -> TextureResource? {
            try? TextureResource(image: img, options: .init(semantic: .raw, mipmapsMode: .none))
        }
        guard let grass = a.tiles[.grass].flatMap(color), let forest = a.tiles[.grassDark].flatMap(color),
              let dirt = a.tiles[.dirt].flatMap(color), let paving = a.tiles[.paving].flatMap(color),
              let rockTile = a.tiles[.rock].flatMap(color), let moss = a.tiles[.moss].flatMap(color),
              let bed = a.tiles[.riverbed].flatMap(color), let atlas = color(a.atlas), let rune = color(a.rune),
              let control = raw(plan.maps.control), let aux = raw(plan.maps.aux) else { return nil }
        let level = plan.quality.level
        let wind: Float = level == .low ? 0 : 1
        // 新セットの見た目の切り替え（シェーダーの custom_parameter。旧セットは 0 で 2026-10-05 の見た目のまま）
        let ruins: Float = a.set == .ruins ? 1 : 0
        do {
            var ground = try CustomMaterial(surfaceShader: .init(named: "stageGroundSurface", in: lib), lightingModel: .lit)
            ground.baseColor = .init(texture: .init(grass))
            ground.specular = .init(texture: .init(forest))
            ground.emissiveColor = .init(texture: .init(dirt))
            ground.roughness = .init(texture: .init(paving))
            ground.metallic = .init(texture: .init(bed))
            ground.ambientOcclusion = .init(texture: .init(aux))
            ground.custom.texture = .init(control)
            ground.custom.value = SIMD4(level == .low ? 0 : 1, 1, level == .high ? 4 : (level == .medium ? 2 : 1), ruins)

            var rock = try CustomMaterial(surfaceShader: .init(named: "stageRockSurface", in: lib), lightingModel: .lit)
            rock.baseColor = .init(texture: .init(rockTile))
            // 苔は roughness のスロットへ（clearcoat のスロットは .lit では束縛されない）
            rock.roughness = .init(texture: .init(moss))
            rock.custom.value = SIMD4(ruins, 0, 0, 0)

            let windModifier = CustomMaterial.GeometryModifier(named: "stageWindGeometry", in: lib)
            var prop = try CustomMaterial(surfaceShader: .init(named: "stagePropSurface", in: lib),
                                          geometryModifier: windModifier, lightingModel: .lit)
            prop.baseColor = .init(texture: .init(atlas))
            prop.custom.value = SIMD4(wind, ruins, 0, 0)

            var flora = try CustomMaterial(surfaceShader: .init(named: "stageVertexColorSurface", in: lib),
                                           geometryModifier: windModifier, lightingModel: .lit)
            flora.custom.value = SIMD4(wind, ruins, 0, 0)

            guard let brushImage = StageAssets.image(.main, "StageBrushAtlas", "png"),
                  let brushTexture = color(brushImage) else { return nil }
            AssetLedger.record(.texture, "brush atlas 1024x512")
            AssetLedger.record(.material, "brush foliage")
            var brush = try CustomMaterial(surfaceShader: .init(named: "stageBrushSurface", in: lib),
                                           geometryModifier: windModifier, lightingModel: .lit)
            brush.baseColor = .init(texture: .init(brushTexture))
            brush.faceCulling = .none
            brush.custom.value = SIMD4(level == .low ? 0.5 : 1, 0, 0, 0)

            var runeMat = PhysicallyBasedMaterial()
            runeMat.baseColor = .init(tint: a.set == .ruins ? UIColor(red: 0.40, green: 0.66, blue: 0.59, alpha: 1) : .white, texture: .init(rune))
            runeMat.roughness = .init(floatLiteral: 0.9)
            runeMat.metallic = .init(floatLiteral: 0)
            runeMat.specular = .init(floatLiteral: 0.2)
            var sanctuary: CustomMaterial?
            if let image = a.sanctuaryAtlas, let texture = color(image) {
                var material = try CustomMaterial(surfaceShader: .init(named: "stagePropSurface", in: lib), lightingModel: .lit)
                material.baseColor = .init(texture: .init(texture))
                material.custom.value = SIMD4(0, ruins, 0, 0)
                sanctuary = material
                AssetLedger.record(.texture, "sanctuary atlas 1024x1024")
                AssetLedger.record(.material, "sanctuary stone")
            }
            var field: CustomMaterial?
            if let image = a.fieldAtlas, let texture = color(image) {
                var material = try CustomMaterial(surfaceShader: .init(named: "stagePropSurface", in: lib), lightingModel: .lit)
                material.baseColor = .init(texture: .init(texture))
                material.custom.value = SIMD4(0, ruins, 0, 0)
                field = material
                AssetLedger.record(.texture, "field atlas 2048x1024")
                AssetLedger.record(.material, "field stone and roots")
            }
            return Materials(ground: ground, rock: rock, prop: prop, flora: flora, brush: brush, rune: runeMat,
                             sanctuary: sanctuary, field: field)
        } catch {
            return nil
        }
    }
}
