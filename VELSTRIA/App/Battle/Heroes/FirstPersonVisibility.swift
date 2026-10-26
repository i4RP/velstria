import Foundation
import Metal
import RealityKit

/// 自分のモデルだけの画面占有を制限する。ロード中に材質を用意し、プレイ中は uniform のみを変更する。
/// クリップはスキニング後のフラグメント位置で行うので、攻撃・移動中も画面下 9% を越えない。
@MainActor
final class FirstPersonVisibility {
    static let coverageLimit: Float = 0.09
    static let revealStart: Float = -20 * .pi / 180
    static let revealEnd: Float = -60 * .pi / 180

    /// 下を向き始めるまでは 9%。-20°〜-60°で滑らかに胴体全体を解放する。
    nonisolated static func visibleFraction(pitch: Float) -> Float {
        guard pitch.isFinite else { return 0.09 }
        let t = min(1, max(0, (-pitch * 180 / .pi - 20) / 40))
        return 0.09 + 0.91 * t * t * (3 - 2 * t)
    }

    /// NDC の上端（下端 = -1、上端 = 1）。フェザーはこの境界の内側だけに掛ける。
    nonisolated static func cutoff(pitch: Float) -> Float { -1 + 2 * visibleFraction(pitch: pitch) }

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
    private var previousCutoff: Float = .nan
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

    /// mask は占有率撮影用。同じクリップ・元のアルファのまま白く描く。不透明度 50% は親が適用する。
    func update(enabled: Bool, pitch: Float, mask: Bool = false) {
        let boundary = Self.cutoff(pitch: pitch)
        let changed = enabled != previousEnabled || boundary != previousCutoff || mask != previousMask
        for entry in entries {
            // 材質変換に失敗しても制限外を描かない。十分下を向いた時だけ元のモデルを見せる。
            if !entry.supported {
                let hide = enabled && (boundary < 1 || mask)
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
                    material.custom.value.x = boundary
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
        previousCutoff = boundary
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
        // Alpha is composited against the world; a discarded fragment must not hide the background.
        material.writesDepth = false
        let intensity = (original as? PhysicallyBasedMaterial)?.emissiveIntensity ?? 1
        material.custom.value = SIMD4(-1 + 2 * coverageLimit, Float(flags), intensity, 0)
        return material
    }
}
