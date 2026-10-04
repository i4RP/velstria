import CoreGraphics
import Foundation
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

    struct Materials {
        var ground: CustomMaterial
        var rock: CustomMaterial
        var prop: CustomMaterial
        var flora: CustomMaterial
        var rune: PhysicallyBasedMaterial
    }

    init?(plan: StagePlan) {
        root.name = "stage"
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
        let chunks = plan.layout.chunks
        for key in Set(chunks.props.keys).union(chunks.rocks.keys).union(chunks.flora.keys).sorted() {
            add(chunks.rocks[key], name: "stageRock_\(key)", material: materials.rock)
            add(chunks.props[key], name: "stageProp_\(key)", material: materials.prop)
            add(chunks.flora[key], name: "stageFlora_\(key)", material: materials.flora, castsShadow: false)
        }
        for (i, buf) in plan.layout.brushes.enumerated() {
            // 添字を MapDefinition.brushes と一致させるため、メッシュが作れなくても空のエンティティを置く
            let e = buf.makeMesh().map { ModelEntity(mesh: $0, materials: [materials.flora]) } ?? ModelEntity()
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

    /// 地面: 地図の外 40 m まで覆う 1 枚の板（配合マップの外は端の値＝森の下草が続く）。
    private func buildGround(material: CustomMaterial) {
        var b = StageMeshBuffer(reserveVertices: 4)
        let lo: Float = -40, hi: Float = 160
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

    static func makeMaterials(plan: StagePlan) -> Materials? {
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
        do {
            var ground = try CustomMaterial(surfaceShader: .init(named: "stageGroundSurface", in: lib), lightingModel: .lit)
            ground.baseColor = .init(texture: .init(grass))
            ground.specular = .init(texture: .init(forest))
            ground.emissiveColor = .init(texture: .init(dirt))
            ground.roughness = .init(texture: .init(paving))
            ground.metallic = .init(texture: .init(bed))
            ground.ambientOcclusion = .init(texture: .init(aux))
            ground.custom.texture = .init(control)
            ground.custom.value = SIMD4(level == .low ? 0 : 1, 1, level == .high ? 4 : (level == .medium ? 2 : 1), 0)

            var rock = try CustomMaterial(surfaceShader: .init(named: "stageRockSurface", in: lib), lightingModel: .lit)
            rock.baseColor = .init(texture: .init(rockTile))
            // 苔は roughness のスロットへ（clearcoat のスロットは .lit では束縛されない）
            rock.roughness = .init(texture: .init(moss))

            let windModifier = CustomMaterial.GeometryModifier(named: "stageWindGeometry", in: lib)
            var prop = try CustomMaterial(surfaceShader: .init(named: "stagePropSurface", in: lib),
                                          geometryModifier: windModifier, lightingModel: .lit)
            prop.baseColor = .init(texture: .init(atlas))
            prop.custom.value = SIMD4(wind, 0, 0, 0)

            var flora = try CustomMaterial(surfaceShader: .init(named: "stageVertexColorSurface", in: lib),
                                           geometryModifier: windModifier, lightingModel: .lit)
            flora.custom.value = SIMD4(wind, 0, 0, 0)

            var runeMat = PhysicallyBasedMaterial()
            runeMat.baseColor = .init(tint: .white, texture: .init(rune))
            runeMat.roughness = .init(floatLiteral: 0.9)
            runeMat.metallic = .init(floatLiteral: 0)
            runeMat.specular = .init(floatLiteral: 0.2)
            return Materials(ground: ground, rock: rock, prop: prop, flora: flora, rune: runeMat)
        } catch {
            return nil
        }
    }
}
