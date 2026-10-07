import Foundation
import VelstriaCore

// スキル演出: H010 焔冠のテッサ（Arcanist / 掌の焔 + 魔導書）。
// 主題: 焔の冠。橙赤（主）× 金（副）× 紅（差し色）。炎の舌・残り火・焦げ跡で「熱」を見せる。
//   パッシブ 燃焼冠       — スキルが敵の英雄に当たると、頭上の焔の冠が燃え上がる
//   S1 テッサ式・一閃     — 掌から放つ火球。命中で弾け、頭上に小さな焔の冠（気絶）
//   S2 星環シフト         — 炎に溶けて転移し、転移先で火柱が噴き上がる。炎の舌が外へ走り吹き飛ばす
//   S3 境界制圧           — 地点に焔の魔法陣を描き、噴き出す炎の鎖で縛る（根止め）
//   奥義 焔冠戴天          — 天に焔の冠を戴き、1 秒の予告ののち隕石が落ちて大地を焼く

enum FX_H010: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.95, 0.75), primary: RGB(1.0, 0.42, 0.1),
                                   secondary: RGB(1.0, 0.76, 0.24), accent: RGB(1.0, 0.22, 0.12),
                                   dark: RGB(0.18, 0.06, 0.03))

    /// 炎の舌を立ちのぼらせる（輪・円盤・球から）。
    private static func flames(_ count: Int, _ shape: FXEmitShape, _ tint: FXTint = .secondary, speed: Float = 2,
                               life: Float = 0.5, size: Float = 0.4, emit: Float = 0.12) -> FXEmit {
        FXEmit(tex: .flame, tint: tint, tintEnd: .accent, count: count, emit: emit, life: life, size: size, sizeVar: 0.4,
               grow: 0.5, shape: shape, surface: true, dir: .up, speed: speed, speedVar: 0.4, gravity: -1, drag: 1.2,
               orient: .upright, fade: .gradualFadeInOut)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(.flare(1.0, .core, life: 0.18), .follow, offset: [0, 2.0, 0]),
                .mesh(.halo(0.5, .secondary, life: 0.7, spin: 300), .follow, offset: [0, 2.0, 0]),
                .emit(flames(10, .ring(0.35), speed: 1.2, life: 0.5, size: 0.32), .follow, offset: [0, 1.9, 0]),
                .mesh(.decal(.runeCircle, 1.6, .primary, life: 0.6, spin: 200, alpha: 0.6), .follow),
                .emit(.embers(12, radius: 0.5, .secondary), .follow, offset: [0, 0.8, 0], quality: 1),
            ]
            r.hit = []
        case .skill1:
            // 掌で火を練り → 0.14 秒で投げる
            r.cast = [
                .emit(.gather(8, radius: 0.5, .secondary, life: 0.12), offset: [0.35, 1.4, 0.3]),
                .emit(.flare(1.2, .core, life: 0.15), at: 0.13, offset: [0.3, 1.3, 0.7]),
                .emit(.fan(10, .primary, speed: 6, spread: 25, life: 0.3), at: 0.13, offset: [0.3, 1.3, 0.7]),
            ]
            r.travel = [
                .mesh(.orb(0.32, .secondary, life: 0.9, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.0, 0]),
                .emit(.trail(.flame, .primary, rate: 90, life: 0.28, size: 0.45).with { $0.tintEnd = .accent; $0.orient = .upright },
                      .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.glowHard, .secondary, rate: 50, life: 0.18, size: 0.5), .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.glowHard, .secondary, rate: 30, life: 0.6, size: 0.06).with {
                    $0.gravity = -1; $0.speed = 1; $0.noise = 1
                }, .follow, offset: [0, 1.0, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.2), offset: [0, 1.0, 0]),
                .emit(.bloom(1.2, .primary, life: 0.35), offset: [0, 0.9, 0]),
                .mesh(.shockRing(1.6, .primary, life: 0.35)),
                .mesh(.decal(.crack, 2.0, .dark, life: 1.2, spin: 0, alpha: 0.7)),
                .emit(flames(14, .sphere(0.4), speed: 3, life: 0.45, size: 0.5)),
            ]
            r.hit = [
                // 気絶: 頭上に小さな焔の冠
                .mesh(.halo(0.4, .secondary, life: 0.9, spin: 420), .follow, offset: [0, 2.0, 0]),
                .emit(flames(6, .ring(0.35), speed: 0.6, life: 0.6, size: 0.25, emit: 0.4), .follow, offset: [0, 1.95, 0]),
            ]
        case .skill2:
            // 腕を広げて炎に溶ける → 転移先で火柱
            r.cast = [
                .emit(.flare(1.5, .primary, life: 0.2), offset: [0, 1.0, 0]),
                .emit(flames(16, .ring(0.5), speed: 3, life: 0.45)),
                .mesh(.decal(.runeCircle, 1.8, .primary, life: 0.5, spin: 300, alpha: 0.7)),
                .emit(.embers(14, radius: 0.6), quality: 1),
                .emit(.smoke(6, radius: 0.4, .dark, life: 0.8, size: 0.6), quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.2), at: 0.12, offset: [0, 1.0, 0]),
                .mesh(.pillar(0.7, height: 3.2, .primary, life: 0.5), at: 0.1),
                .mesh(.pillar(0.35, height: 3.8, .secondary, life: 0.4), at: 0.1),
                .mesh(.shockRing(R * 1.4, .accent, life: 0.35), at: 0.12),
                .mesh(.burstWall(R, height: 1.6, .primary, life: 0.4), at: 0.12),
                // 吹き飛ばし: 外へ走る炎の舌
                .mesh(.ray(.flame, length: 1.4, width: 0.8, .primary, life: 0.35).with { $0.advance = 5 }, at: 0.12)
                    .ringed(6, radius: R * 0.5),
                .emit(flames(20, .ring(R * 0.6), speed: 3.5, life: 0.5, size: 0.5), at: 0.12),
                .emit(.sparks(16, speed: 7, .secondary, end: .primary), at: 0.12, offset: [0, 0.8, 0]),
                .shake(0.15, at: 0.12),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.15), offset: [0, 1.0, 0]),
                .mesh(.ray(.flame, length: 1.0, width: 0.6, .accent, life: 0.3).with { $0.advance = 4 }),
            ]
        case .ultimate:
            // 焔冠戴天: 天に冠を掲げる（0.13 秒）→ 1 秒の予告で冠が降り、隕石が落ちる → 大爆炎
            r.cast = [
                .emit(.flare(1.8, .core, life: 0.3, tex: .flare6), at: 0.12, offset: [0, 2.2, 0]),
                .mesh(.halo(0.9, .secondary, life: 1.0, spin: 300), at: 0.1, .follow, offset: [0, 2.3, 0]),
                .emit(flames(16, .ring(0.6), speed: 1.5, life: 0.6, size: 0.4, emit: 0.5), at: 0.1, .follow,
                      offset: [0, 2.2, 0]),
                .emit(.embers(16, radius: 0.6), .follow, offset: [0, 1.0, 0], quality: 1),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.2, .primary, life: 1.05, spin: 60, grow: 1.0, alpha: 0.7)),
                .mesh(.decal(.ringDouble, R * 2.0, .secondary, life: 1.05, spin: -40, alpha: 0.55)),
                // 降りてくる焔の冠
                .mesh(.halo(R * 0.6, .secondary, life: 1.0, spin: 200).with { $0.rise = -4.5; $0.fadeOut = 0.85 },
                      offset: [0, 5.0, 0]),
                // 隕石（芯 + 上へ伸びる炎の尾）
                .mesh(.sprite(.glowHard, 1.4, .secondary, life: 1.0, grow: 1.3).with { $0.rise = -9; $0.fadeOut = 0.92 },
                      offset: [0, 9.2, 0]),
                .mesh(.sprite(.flame, 1.8, .primary, life: 1.0, grow: 1.1).with { $0.rise = -9; $0.fadeOut = 0.92 },
                      offset: [0, 10.2, 0]),
                .emit(flames(24, .ring(R), speed: 1.5, life: 0.6, size: 0.45, emit: 0.8)),
                .emit(.gather(24, radius: R, .secondary, life: 0.9), offset: [0, 0.4, 0]),
            ]
            r.impact = [
                .emit(.flare(3.0, .core, life: 0.28, tex: .flare6), offset: [0, 1.2, 0]),
                .emit(.bloom(R * 0.5, .primary, life: 0.5, grow: 1.6), offset: [0, 0.8, 0]),
                .mesh(.orb(R * 0.25, .secondary, life: 0.3, grow: 2.6, alpha: 0.7), offset: [0, 0.5, 0]),
                .mesh(.decal(.crack, R * 2.2, .dark, life: 2.0, spin: 0, grow: 1.0, alpha: 0.85)),
                .mesh(.decal(.runeCircle, R * 2.4, .accent, life: 1.6, spin: 30, grow: 1.05, alpha: 0.9)),
                .mesh(.shockRing(R * 1.1, .core, life: 0.4)),
                .mesh(.shockRing(R * 1.5, .primary, life: 0.65), at: 0.06),
                .mesh(.burstWall(R * 1.0, height: 3.0, .primary, life: 0.55)),
                .mesh(.pillar(0.45, height: 5.5, .secondary, life: 0.8)).ringed(6, radius: R * 0.6, every: 0.04),
                .mesh(.wall(.flame, width: 1.4, height: 2.6, .primary, life: 0.8)).ringed(6, radius: R * 0.9, every: 0.02),
                .emit(flames(40, .disc(R * 0.8), .secondary, speed: 4, life: 0.6, size: 0.6)),
                .emit(.sparks(36, speed: 11, .secondary, end: .primary, life: 0.5), offset: [0, 0.6, 0]),
                .emit(.debris(18, speed: 7.5)),
                .emit(.smoke(12, radius: R * 0.6, .dark, life: 1.6, size: 1.3), quality: 1),
                .shake(0.75),
            ]
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.15), offset: [0, 1.0, 0]),
                .mesh(.sprite(.flame, 1.2, .primary, life: 0.4, grow: 1.2), .follow, offset: [0, 0.8, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 掌に火を練り、横手で投げる
            m.gather(0.04)
            m.throwCast(0.1)
            m.hold(0.14) { $0.glow = 1.3 }
        case .skill2:
            // 胸元に炎を抱え → 腕を広げて炎に溶ける
            m.gather(0.05)
            m.roar(0.08)
            m.hold(0.16) { $0.glow = 1.6; $0.ring = 1 }
        case .ultimate:
            // 両手で天に冠を掲げ、長く溜めてから大地へ振り下ろす
            m.gather(0.05)
            m.raise(0.08, glow: 2.2)
            m.hold(0.25) { $0.ring = 1.5; $0.glow = 2.4; $0.headPitch = -0.5 }
            m.push(0.08, high: -0.3)
            m.hold(0.25) { $0.glow = 2 }
        }
    }
}
