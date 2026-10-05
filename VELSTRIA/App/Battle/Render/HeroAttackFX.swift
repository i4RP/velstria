import Foundation
import RealityKit
import UIKit

// 担当: battle-renderer。ヒーロー別の通常攻撃の着弾・発射の演出（HeroFXProfile → VFXSystem の粒子・輪・閃光）。
// 1 回の命中・発射で出す粒子の放出体は原則 1 つ（重い打撃・大筒だけ 2 つ）と、安価なメッシュの閃光・地面の輪。
// 低画質は粒子 1 つだけ（発射炎の粒子・破片・添えの閃光は出さない）。重要度（important）は呼び出し側が決める:
// 注目中のヒーローが関わる戦闘だけ true（予算を超えた時に他の演出と入れ替えてでも出す）。
// 輪・閃光の色は単色マテリアルのキーなので、事前生成（BattleWorld.plannedUnlitMaterials）と同じ値だけを使う（meshColors）。

@MainActor
enum HeroAttackFX {
    /// 近接の通常攻撃の命中。p = 対象の当たり位置、dir = 攻撃者 → 対象の水平の単位ベクトル。
    static func meleeImpact(_ profile: HeroFXProfile, at p: SIMD3<Float>, direction dir: SIMD3<Float>, vfx: VFXSystem,
                            quality: RenderQuality, important: Bool) {
        impact(profile, at: p, direction: dir, vfx: vfx, quality: quality, important: important)
    }

    /// 遠隔の通常攻撃の着弾（投射物の位置・進行方向）。
    static func rangedImpact(_ profile: HeroFXProfile, at p: SIMD3<Float>, direction dir: SIMD3<Float>, vfx: VFXSystem,
                             quality: RenderQuality, important: Bool) {
        impact(profile, at: p, direction: dir, vfx: vfx, quality: quality, important: important)
    }

    private static func impact(_ profile: HeroFXProfile, at p: SIMD3<Float>, direction dir: SIMD3<Float>, vfx: VFXSystem,
                               quality: RenderQuality, important: Bool) {
        let c = profile.primary.uiColor
        let low = quality.level == .low
        // 振り・弾の向きへ少し上向きに飛ばす
        let spray = simd_normalize(dir + SIMD3(0, 0.35, 0))
        switch profile.impact {
        case .slash:
            vfx.spawn(.slashHit, at: p, color: c, scale: 1, important: important, direction: spray)
            if !low { vfx.flash(at: p, color: profile.primary, radius: 0.3, duration: 0.1, alpha: 0.45) }
        case .pierce:
            vfx.spawn(.slashHit, at: p, color: c, scale: 0.85, count: 9, important: important,
                      direction: simd_normalize(dir + SIMD3(0, 0.12, 0)))
            if !low { vfx.flash(at: p, color: profile.primary, radius: 0.22, duration: 0.08, alpha: 0.5) }
        case .sparkle:
            vfx.spawn(.magicHit, at: p, color: c, scale: 0.7, count: 10, important: important)
        case .blunt:
            vfx.spawn(.bluntHit, at: p, color: c, scale: 1, important: important)
            vfx.ring(at: p, color: ringColor(profile), from: 0.25, to: 1.0, duration: 0.3, alpha: 0.7)
        case .heavyBlunt:
            vfx.spawn(.bluntHit, at: p, color: c, scale: 1.35, important: important)
            vfx.ring(at: p, color: ringColor(profile), from: 0.4, to: 1.8, duration: 0.4, alpha: 0.8)
            if !low { vfx.spawn(.debris, at: SIMD3(p.x, 0.2, p.z), color: .gray, scale: 0.45, count: 10, important: false) }
        case .gust:
            vfx.ring(at: p, color: profile.primary, from: 0.3, to: 1.3, duration: 0.3, alpha: 0.75)
            vfx.spawn(.slashHit, at: p, color: c, scale: 0.7, count: 8, important: important, direction: spray)
        case .splash:
            vfx.spawn(.splash, at: p, color: c, scale: 1, important: important)
            if !low { vfx.ring(at: p, color: profile.primary, from: 0.2, to: 0.8, duration: 0.3, alpha: 0.6) }
        case .embers:
            vfx.spawn(.bluntHit, at: p, color: c, scale: 0.8, count: 12, important: important)
            if !low { vfx.flash(at: p, color: profile.primary, radius: 0.28, duration: 0.1, alpha: 0.5) }
        case .fireBurst:
            vfx.spawn(.bluntHit, at: p, color: c, scale: 1.05, important: important)
            if !low { vfx.flash(at: p, color: profile.primary, radius: 0.45, duration: 0.14, alpha: 0.55) }
        case .electric:
            vfx.spawn(.hitSpark, at: p, color: profile.core.uiColor, scale: 1.15, count: 12, important: important)
            if !low { vfx.flash(at: p, color: profile.primary, radius: 0.35, duration: 0.08, alpha: 0.6) }
        case .sparks:
            vfx.spawn(.hitSpark, at: p, color: c, scale: 1, important: important)
        case .ringFlash:
            vfx.flash(at: p, color: profile.primary, radius: 0.5, duration: 0.16, alpha: 0.5)
            vfx.ring(at: p, color: profile.primary, from: 0.2, to: 1.0, duration: 0.3, alpha: 0.7)
            if important && !low { vfx.spawn(.magicHit, at: p, color: c, scale: 0.6, count: 8, important: true) }
        case .softBurst:
            vfx.spawn(.magicHit, at: p, color: c, scale: 0.9, important: important)
            if !low { vfx.flash(at: p, color: profile.primary, radius: 0.4, duration: 0.14, alpha: 0.35) }
        case .abyssBurst:
            vfx.spawn(.magicHit, at: p, color: c, scale: 1.1, important: important)
            if !low { vfx.flash(at: p, color: profile.primary, radius: 0.38, duration: 0.12, alpha: 0.5) }
        }
    }

    /// 遠隔の発射の瞬間（p = 発射位置、dir = 発射位置 → 対象の単位ベクトル）。
    static func muzzle(_ profile: HeroFXProfile, at p: SIMD3<Float>, direction dir: SIMD3<Float>, vfx: VFXSystem,
                       quality: RenderQuality, important: Bool) {
        let particles = quality.level != .low
        let c = profile.primary.uiColor
        switch profile.muzzle {
        case .none:
            break
        case .bow:
            vfx.flash(at: p, color: profile.primary, radius: 0.18, duration: 0.08, alpha: 0.6)
        case .cast, .claw:
            vfx.flash(at: p, color: profile.primary, radius: 0.22, duration: 0.1, alpha: 0.6)
        case .flame:
            vfx.flash(at: p, color: profile.primary, radius: 0.3, duration: 0.12, alpha: 0.65)
            if particles { vfx.spawn(.muzzle, at: p, color: c, scale: 0.8, important: important, direction: dir) }
        case .mech:
            vfx.flash(at: p, color: profile.primary, radius: 0.22, duration: 0.07, alpha: 0.7)
            if particles { vfx.spawn(.muzzle, at: p, color: c, scale: 0.7, count: 8, important: important, direction: dir) }
        case .blast:
            vfx.flash(at: p, color: profile.primary, radius: 0.55, duration: 0.12, alpha: 0.75)
            if particles { vfx.spawn(.muzzle, at: p, color: c, scale: 1.4, count: 16, important: important, direction: dir) }
        case .rifle:
            vfx.flash(at: p, color: profile.primary, radius: 0.2, duration: 0.07, alpha: 0.65)
            if particles { vfx.spawn(.muzzle, at: p, color: c, scale: 0.6, count: 6, important: important, direction: dir) }
        case .spark:
            vfx.flash(at: p, color: profile.primary, radius: 0.26, duration: 0.08, alpha: 0.65)
            if particles { vfx.spawn(.muzzle, at: p, color: profile.core.uiColor, scale: 0.6, count: 6, important: important,
                                     direction: dir) }
        }
    }

    /// 地面の輪の色（土埃の輪のダガンは副色 = 骨の白、他は主色）。
    static func ringColor(_ profile: HeroFXProfile) -> RGB {
        profile.heroID == "H013" ? profile.secondary : profile.primary
    }

    /// この演出が使う輪・閃光の色（単色マテリアルの事前生成に足す）。
    static func meshColors(_ profile: HeroFXProfile) -> (rings: [RGB], flashes: [RGB]) {
        var rings = [profile.primary]
        if ringColor(profile) != profile.primary { rings.append(ringColor(profile)) }
        return (rings, [profile.primary])
    }
}
