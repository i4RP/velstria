import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。環境パーティクル（RenderQuality.ambientParticles）: 両陣営の泉のきらめきと河川の水面のきらめき。
// 放出体は読み込み時に全て作り、画質の変更（適応での切り替えを含む）では有効/無効と粒子数の書き換えだけを行う
// （試合中に ParticleEmitterComponent を構築しない）。粒子は少なく・小さく・ゆっくり（戦闘の視認性を邪魔しない）。
// 河川のきらめきは GroundLayer.ambient（霧の板より上）から出す。泉は台座の上から昇る。

@MainActor
final class AmbientParticles {
    let root = Entity()

    private struct Emitter {
        let entity: Entity
        /// particleScale = 1 での毎秒の粒子数。
        let baseRate: Float
    }

    private var emitters: [Emitter] = []
    private var appliedScale: Float = -1

    /// 河川のきらめきの放出体の数（対角線の川を等分する。粒子系 1 つにつき約 1 MB を持つので少なく長く）。
    static let riverSegments = 4
    /// 泉の台座の上面（MapScene の泉の内側の段の高さ）。
    static let fountainTop: Float = 0.42
    /// 泉の浮遊結晶の中心の高さ（MapScene.fountainSpires）。
    static let spireHeight: Float = 1.6

    init(map: MapDefinition, teams: TeamColors, texture: TextureResource?, quality: RenderQuality) {
        root.name = "ambient"
        for team in Team.players {
            let base = worldPosition(map.fountain(team))
            let tint = teams.light(team).uiColor
            // 台座から昇る光の粒（円盤状の範囲から上へ）
            var rise = AmbientParticles.base(texture: texture)
            rise.emitterShape = .cylinder
            rise.birthLocation = .volume
            rise.emitterShapeSize = [2.4, 0.05, 2.4]
            rise.birthDirection = .world
            rise.emissionDirection = [0, 1, 0]
            rise.speed = 0.35
            rise.speedVariation = 0.2
            rise.mainEmitter.lifeSpan = 2.6
            rise.mainEmitter.lifeSpanVariation = 0.6
            rise.mainEmitter.size = 0.06
            rise.mainEmitter.sizeVariation = 0.025
            rise.mainEmitter.acceleration = [0, 0.12, 0]
            rise.mainEmitter.dampingFactor = 0.3
            rise.mainEmitter.color = .evolving(start: .single(tint), end: .single(.white))
            add(rise, rate: 16, at: base + SIMD3(0, AmbientParticles.fountainTop, 0))
            // 浮遊結晶の周りの瞬き
            var glint = AmbientParticles.base(texture: texture)
            glint.emitterShape = .sphere
            glint.birthLocation = .surface
            glint.emitterShapeSize = SIMD3(repeating: 0.9)
            glint.speed = 0.12
            glint.speedVariation = 0.08
            glint.mainEmitter.lifeSpan = 1.3
            glint.mainEmitter.lifeSpanVariation = 0.3
            glint.mainEmitter.size = 0.05
            glint.mainEmitter.sizeVariation = 0.02
            glint.mainEmitter.opacityCurve = .quickFadeInOut
            glint.mainEmitter.color = .constant(.single(tint))
            add(glint, rate: 9, at: base + SIMD3(0, AmbientParticles.spireHeight, 0))
        }
        // 河川（sim (0, 12000) → (12000, 0) = world (0, -120) → (120, 0)）の水面のきらめき
        let M = MapScene.mapMeters
        let length = M * Float(2).squareRoot()
        let width = Float(map.riverWidth / Balance.unitsPerMeter) * 0.92
        let n = AmbientParticles.riverSegments
        for k in 0..<n {
            let t = (Float(k) + 0.5) / Float(n) * 0.88 + 0.06
            var shimmer = AmbientParticles.base(texture: texture)
            shimmer.emitterShape = .box
            shimmer.birthLocation = .volume
            shimmer.emitterShapeSize = [length / Float(n) * 0.85, 0.02, width * 0.7]
            shimmer.birthDirection = .world
            shimmer.emissionDirection = [0, 1, 0]
            shimmer.speed = 0.04
            shimmer.speedVariation = 0.03
            shimmer.mainEmitter.lifeSpan = 1.0
            shimmer.mainEmitter.lifeSpanVariation = 0.3
            shimmer.mainEmitter.size = 0.045
            shimmer.mainEmitter.sizeVariation = 0.02
            shimmer.mainEmitter.opacityCurve = .quickFadeInOut
            shimmer.mainEmitter.color = .constant(.single(UIColor(red: 0.75, green: 0.95, blue: 1.0, alpha: 1)))
            let e = add(shimmer, rate: 14, at: [M * t, GroundLayer.ambient, -M + M * t])
            // 水面と同じ向き（局所 x = 川の流れの方向）
            e.orientation = simd_quatf(angle: -.pi / 4, axis: [0, 1, 0])
        }
        apply(quality: quality)
    }

    /// 共通の設定（星形の加算合成・照明なし・連続放出）。
    private static func base(texture: TextureResource?) -> ParticleEmitterComponent {
        AssetLedger.record(.emitter, "ambient")
        var p = ParticleEmitterComponent()
        p.fieldSimulationSpace = .global
        p.mainEmitter.image = texture
        p.mainEmitter.blendMode = .additive
        p.mainEmitter.opacityCurve = .gradualFadeInOut
        p.mainEmitter.billboardMode = .billboard
        p.mainEmitter.isLightingEnabled = false
        p.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.4
        // 有効にした瞬間から粒子が漂っているように、事前に少し進めておく
        p.timing = .repeating(warmUp: 2, emit: .init(duration: 10), idle: nil)
        p.isEmitting = true
        return p
    }

    @discardableResult
    private func add(_ c: ParticleEmitterComponent, rate: Float, at p: SIMD3<Float>) -> Entity {
        AssetLedger.record(.entity, "ambient emitter")
        let e = Entity()
        e.name = "ambientEmitter"
        e.position = p
        e.components.set(c)
        root.addChild(e)
        emitters.append(Emitter(entity: e, baseRate: rate))
        return e
    }

    /// 画質の反映（有効/無効と粒子数の書き換えだけ。作り直さない）。
    func apply(quality: RenderQuality) {
        root.isEnabled = quality.ambientParticles
        guard quality.particleScale != appliedScale else { return }
        appliedScale = quality.particleScale
        for em in emitters {
            guard var c = em.entity.components[ParticleEmitterComponent.self] else { continue }
            c.mainEmitter.birthRate = max(1, em.baseRate * quality.particleScale)
            em.entity.components.set(c)
        }
    }

    var isEnabled: Bool { root.isEnabled }
    var emitterCount: Int { emitters.count }
}
