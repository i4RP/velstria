import Foundation
import VelstriaCore

// スキル演出: H023 雷槍のトレン（Support / 雷の騎槍・翼兜・浮かぶ雷球）。
// 主題: 天を突く蒼い雷槍。白い雷光の芯 × 蒼（主）× 空色（副）× 金の火花（差し色）。
// ヴォス（黒雷・紫と煙）とは逆に、明るく澄んだ蒼雷と金の火花・光の槍で「騎士の雷」を見せる。
//   パッシブ 帯電槍        — 味方を癒やすと、その身に蒼い電弧が走り金の火花が散る
//   S1 トレン式・一閃       — 雷の槍を投げ放つ。光の槍が稲妻の尾を引き、命中で十字の雷が弾ける
//   S2 星環シフト           — 雷鳴とともに跳び、転移先に雷の輪が走る（鈍足）
//   S3 境界制圧             — 地点に雷球が浮かび、雷が降り注いで味方を癒やし敵を痺れさせる（気絶）
//   奥義 雷槍天穿            — 槍を天へ掲げ、六本の光の槍が周囲に降り注ぐ。味方を雷の盾が包み、敵を弾き飛ばす

enum FX_H023: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.92, 0.97, 1.0), primary: RGB(0.32, 0.62, 1.0),
                                   secondary: RGB(0.68, 0.88, 1.0), accent: RGB(1.0, 0.9, 0.45),
                                   dark: RGB(0.03, 0.05, 0.12))

    private static let tip: SIMD3<Float> = [0.25, 1.6, 0.9]

    /// 光の槍（天から落ちる細い光の尖塔）。
    private static func lance(_ h: Float, life: Float = 0.5) -> FXMesh {
        FXMesh(shape: .spire, tex: .beam, tint: .core, alpha: 1, size: [0.22, h, 0.22], sizeEnd: [0.12, h, 0.12],
               ease: .out, life: life, fadeIn: 0.02, fadeOut: 0.4)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(.sparks(16, speed: 3, .accent, end: .primary, life: 0.3, gravity: 2).with { $0.shape = .sphere(0.5) },
                      .follow, offset: [0, 1.0, 0]),
                .mesh(.sprite(.bolt, 1.2, .secondary, life: 0.18, grow: 1.1), .follow, offset: [0, 1.2, 0]),
                .mesh(.halo(0.7, .primary, life: 0.6, spin: 500, tex: .ring), .follow, offset: [0, 1.0, 0]),
                .emit(.flare(0.9, .core, life: 0.14), .follow, offset: [0, 1.6, 0]),
            ]
            r.hit = []
        case .skill1:
            r.cast = [
                .emit(.sparks(10, speed: 2.5, .accent, end: .primary, life: 0.2, gravity: 0).with { $0.shape = .sphere(0.3) },
                      offset: tip),
                .emit(.flare(1.3, .core, life: 0.14, tex: .flare6), at: 0.11, offset: tip),
            ]
            r.travel = [
                .mesh(.ray(.arrow, length: 2.2, width: 0.9, .core, life: 1.0, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.15, -0.5]),
                .emit(.trail(.bolt, .secondary, rate: 36, life: 0.14, size: 0.8).with { $0.angleVar = 180 }, .follow,
                      offset: [0, 1.15, 0]),
                .emit(.trail(.glow, .primary, rate: 60, life: 0.25, size: 0.55), .follow, offset: [0, 1.15, 0]),
                .emit(.trail(.glowHard, .accent, rate: 30, life: 0.3, size: 0.12).with { $0.speed = 1.5; $0.shape = .sphere(0.3) },
                      .follow, offset: [0, 1.15, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.18, tex: .flare6), offset: [0, 1.1, 0]),
                .mesh(.ray(.bolt, length: R * 2.4, width: 0.6, .secondary, life: 0.3)),
                .mesh(.ray(.bolt, length: R * 2.4, width: 0.6, .secondary, life: 0.3).with { $0.yaw = 0 }, at: 0.02),
                .emit(.sparks(20, speed: 7, .accent, end: .primary), offset: [0, 1.0, 0]),
                .mesh(.shockRing(R * 1.3, .primary, life: 0.35)),
            ]
            r.hit = [
                .mesh(.sprite(.bolt, 1.0, .secondary, life: 0.15, grow: 1.1), offset: [0, 1.2, 0]),
                .emit(.sparks(8, speed: 5, .accent, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            r.cast = [
                .mesh(.strike(5, .secondary, width: 0.35, life: 0.22)),
                .emit(.flare(1.4, .core, life: 0.16), offset: [0, 1.0, 0]),
                .emit(.sparks(14, speed: 5, .accent, end: .primary)),
            ]
            r.impact = [
                .mesh(.strike(6, .accent, width: 0.4, life: 0.22), at: 0.03),
                .emit(.flare(1.8, .core, life: 0.18, tex: .flare6), at: 0.03, offset: [0, 0.8, 0]),
                .mesh(.halo(1.6, .secondary, life: 0.9, spin: 600, tex: .ring), at: 0.04, offset: [0, 0.25, 0]),
                .mesh(.decal(.ringDouble, 3.0, .primary, life: 0.9, spin: -200, alpha: 0.8), at: 0.04),
                .emit(.sparks(18, speed: 6, .accent, end: .primary), at: 0.04, offset: [0, 0.6, 0]),
                .shake(0.15, at: 0.03),
            ]
        case .ultimate:
            r.cast = [
                .emit(.gather(24, radius: 1.4, .secondary, life: 0.3), offset: [0, 2.4, 0.2]),
                .mesh(.strike(9, .accent, width: 0.5, life: 0.3), at: 0.25),
                .emit(.flare(2.6, .core, life: 0.3, tex: .flare6), at: 0.25, offset: [0, 2.6, 0.2]),
                .mesh(.decal(.runeCircle, 4.6, .primary, life: 1.4, spin: 80, alpha: 0.85), at: 0.2),
            ]
            r.impact = [
                // 六本の光の槍が降り注ぐ
                .mesh(lance(7, life: 0.55), at: 0.3).ringed(6, radius: 2.6, every: 0.05),
                .mesh(.strike(7, .secondary, width: 0.35, life: 0.25), at: 0.3).ringed(6, radius: 2.6, every: 0.05),
                .emit(.flare(1.6, .accent, life: 0.2), at: 0.3, offset: [0, 0.5, 2.6]).ringed(6, radius: 0, every: 0.05),
                .mesh(.dome(3.0, .primary, life: 1.3, tex: .hexShield, alpha: 0.45), at: 0.3),
                .mesh(.shockRing(4.4, .secondary, life: 0.6), at: 0.35),
                .mesh(.shockRing(3.2, .accent, life: 0.45, tex: .ring), at: 0.6),
                .mesh(.halo(2.4, .primary, life: 1.2, spin: 240, tex: .ringDouble), at: 0.35, offset: [0, 0.4, 0]),
                .emit(.rising(30, radius: 2.8, .rgb(0.55, 1.0, 0.8), speed: 3, life: 1.0), at: 0.4),
                .emit(.sparks(34, speed: 9, .accent, end: .primary, life: 0.5), at: 0.32, offset: [0, 1.0, 0]),
                .shake(0.6, at: 0.3),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 騎槍を肩に担いで投げ放つ
            m.throwCast(0.15)
            m.hold(0.14) { $0.glow = 1.6 }
        case .skill2:
            // 槍を前に構えて突撃の跳躍
            m.brace(0.04, depth: 0.1)
            m.leap(0.1, height: 0.45, forward: 0.4)
            m.thrust(0.06)
            m.land(0.06, depth: 0.12)
            m.settle(0.1)
        case .ultimate:
            // 槍を天へ掲げ、翼兜の騎士が雷を呼ぶ → 槍を振り下ろす号令
            m.brace(0.06, depth: 0.1)
            m.command(0.16)
            m.hold(0.12) { $0.glow = 2.4; $0.wings = 1.4; $0.ring = 1.3 }
            m.smash(0.08)
            m.hold(0.2)
        }
    }
}
