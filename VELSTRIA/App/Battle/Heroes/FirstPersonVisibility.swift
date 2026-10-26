import Foundation
import Metal
import RealityKit

/// 自分のモデルを半透明で描く材質。画面位置による切り取りはせず、体・武器の形を保つ。
/// 不透明度は親の OpacityComponent で適用し、材質はロード中に準備する。
@MainActor
final class FirstPersonVisibility {
    private final class Entry {
        let entity: Entity
        let originals: [any RealityKit.Material]
        var prepared: [any RealityKit.Material]
        let supported: Bool
        var hiddenByFallback = false
        var previousEnabled = true

        init(entity: Entity, originals: [any RealityKit.Material], prepared: [any RealityKit.Material], supported: Bool) {
            self.entity = entity
            self.originals = originals
            self.prepared = prepared
            self.supported = supported
        }
    }

    private var entries: [Entry] = []
    private var previousEnabled = false
    private var previousMask = false
    private(set) var unsupportedMaterialCount = 0
    private(set) var preparedModelCount = 0
    private(set) var failure: String?
    var isReady: Bool { failure == nil && unsupportedMaterialCount == 0 && preparedModelCount > 0 }

    init(root: Entity) {
        let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary()
        if library == nil { failure = "first-person default.metallib unavailable" }
        func visit(_ entity: Entity, usdUV: Bool) {
            let usdUV = usdUV || entity.name == "skinnedBody" || entity.name == "propFit"
            if let model = entity.components[ModelComponent.self], !model.materials.isEmpty {
                var prepared: [any RealityKit.Material] = []
                prepared.reserveCapacity(model.materials.count)
                var supported = true
                for material in model.materials {
                    do {
                        guard let library else { throw PreparationError.missingLibrary }
                        prepared.append(try Self.prepare(material, library: library, usdUV: usdUV))
                    } catch {
                        unsupportedMaterialCount += 1
                        supported = false
                        if failure == nil { failure = "\(entity.name): \(error)" }
                    }
                }
                if supported { preparedModelCount += 1 }
                entries.append(Entry(entity: entity, originals: model.materials, prepared: prepared, supported: supported))
            }
            for child in entity.children { visit(child, usdUV: usdUV) }
        }
        visit(root, usdUV: false)
        if let failure { print("VELSTRIA_FIRST_PERSON_VISIBILITY \(failure)") }
    }

    /// mask は撮影用。形・元のアルファを保って白く描く。不透明度 50% は親が適用する。
    func update(enabled: Bool, mask: Bool = false) {
        let changed = enabled != previousEnabled || mask != previousMask
        for entry in entries {
            // 通常表示は元の材質を保つ。白マスクを準備できない場合だけ撮影対象を隠す。
            if !entry.supported {
                let hide = enabled && mask
                if hide {
                    if !entry.hiddenByFallback { entry.previousEnabled = entry.entity.isEnabled }
                    entry.entity.isEnabled = false
                } else if entry.hiddenByFallback {
                    entry.entity.isEnabled = entry.previousEnabled
                }
                entry.hiddenByFallback = hide
                continue
            }
            guard changed, var model = entry.entity.components[ModelComponent.self] else { continue }
            if enabled {
                for index in entry.prepared.indices {
                    guard var material = entry.prepared[index] as? CustomMaterial else { continue }
                    material.custom.value.w = mask ? 1 : 0
                    entry.prepared[index] = material
                }
                model.materials = entry.prepared
            } else if previousEnabled {
                model.materials = entry.originals
            } else {
                continue
            }
            entry.entity.components.set(model)
        }
        previousEnabled = enabled
        previousMask = mask
    }

    private enum PreparationError: Error { case missingLibrary, unsupportedMaterial, missingShader }

    private static func prepare(_ original: any RealityKit.Material, library: any MTLLibrary, usdUV: Bool) throws -> CustomMaterial {
        let isUnlit = original is UnlitMaterial
        guard isUnlit || original is PhysicallyBasedMaterial else { throw PreparationError.unsupportedMaterial }
        let name = isUnlit ? "firstPersonUnlitSurface" : "firstPersonLitSurface"
        guard library.makeFunction(name: name) != nil else { throw PreparationError.missingShader }
        AssetLedger.record(.material, "first-person visibility")
        var material = try CustomMaterial(from: original, surfaceShader: .init(named: name, in: library))
        var flags: UInt32 = usdUV ? 1 : 0
        if material.baseColor.texture != nil { flags |= 2 }
        if material.normal.texture != nil { flags |= 4 }
        if material.emissiveColor.texture != nil { flags |= 8 }
        if material.roughness.texture != nil { flags |= 16 }
        if material.metallic.texture != nil { flags |= 32 }
        if material.specular.texture != nil { flags |= 64 }
        if material.ambientOcclusion.texture != nil { flags |= 128 }
        if material.clearcoat.texture != nil { flags |= 256 }
        if material.clearcoatRoughness.texture != nil { flags |= 512 }
        let opacity: CustomMaterial.Opacity
        switch material.blending {
        case .opaque: opacity = .init(floatLiteral: 1)
        case .transparent(let value): opacity = value
        @unknown default: throw PreparationError.unsupportedMaterial
        }
        if opacity.texture != nil { flags |= 1024 }
        material.blending = .transparent(opacity: opacity)
        // The translucent body must not occlude the world through depth writes.
        material.writesDepth = false
        let intensity = (original as? PhysicallyBasedMaterial)?.emissiveIntensity ?? 1
        material.custom.value = SIMD4(0, Float(flags), intensity, 0)
        return material
    }
}
