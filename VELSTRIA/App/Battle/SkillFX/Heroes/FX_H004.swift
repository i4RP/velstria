import Foundation
import VelstriaCore

// スキル演出: H004 潮祈のミレア（Arcanist / 潮の杖・浮かぶ水球）。
// 主題: 潮と祈り。白い飛沫の芯 × 澄んだ水色（主）× 碧（副）× 珊瑚の差し色。波紋・泡・渦で「水が光る」。
//   パッシブ 潮騒の加護    — スキルが敵の英雄に当たると、足元に波紋が広がり泡が立ちのぼる
//   S1 ミレア式・一閃       — 渦を巻く水球を放つ。泡の尾を引き、命中で水が弾けて波紋が残る（鈍足）
//   S2 星環シフト           — 水柱に飛び込んで消え、転移先の水の渦から現れる（気絶 = 泡の輪）
//   S3 境界制圧             — 地点に渦が巻き、間欠泉が噴き上がって敵を押し流す（吹き飛ばし）
//   奥義 大潮祈祷            — 1 秒の祈りで大渦が地に描かれ、巨大な潮の竜巻と六本の水柱が立つ（根止め）

enum FX_H004: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.9, 1.0, 1.0), primary: RGB(0.18, 0.72, 1.0),
                                   secondary: RGB(0.45, 0.95, 0.9), accent: RGB(1.0, 0.56, 0.5),
                                   dark: RGB(0.02, 0.09, 0.14))

    /// 杖先（局所座標）。
    private static let staff: SIMD3<Float> = [0.3, 1.75, 0.45]

    /// 水滴（重力で落ちる光の粒）。
    private static func droplets(_ n: Int, speed: Float) -> FXEmit {
        FXEmit.sparks(n, speed: speed, .core, end: .primary, size: 0.12, life: 0.6, gravity: 14).with {
            $0.dir = .up; $0.spread = 50; $0.stretch = 1.2; $0.tex = .glowHard
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.decal(.ripple, 2.4, .primary, life: 0.9, spin: 30, grow: 1.3, alpha: 0.8), .follow),
                .emit(.flutter(.bubble, 12, radius: 0.5, .secondary, speed: 1.2, life: 1.0, size: 0.18).with {
                    $0.gravity = -2; $0.dir = .up
                }, .follow, offset: [0, 0.3, 0]),
                .mesh(.halo(0.8, .secondary, life: 0.7, spin: 160, tex: .ripple, alpha: 0.7), .follow, offset: [0, 0.8, 0]),
            ]
            r.hit = []
        case .skill1:
            r.cast = [
                .emit(.vortex(14, radius: 0.35, .secondary, life: 0.25, tex: .glowHard, speed: 1), offset: staff),
                .emit(.flare(1.0, .core, life: 0.14), at: 0.1, offset: [0.15, 1.35, 0.7]),
                .emit(droplets(10, speed: 4), at: 0.1, offset: [0.15, 1.35, 0.6]),
            ]
            r.travel = [
                .emit(.trail(.bubble, .secondary, rate: 40, life: 0.5, size: 0.22).with { $0.spin = 90; $0.shape = .sphere(0.25) },
                      .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.glow, .primary, rate: 60, life: 0.25, size: 0.7), .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.swirl, .core, rate: 18, life: 0.2, size: 0.6).with { $0.spin = 720; $0.grow = 1.2 },
                      .follow, offset: [0, 1.1, 0]),
            ]
            r.impact = [
                .emit(.flare(1.3, .core, life: 0.16), offset: [0, 1.0, 0]),
                .emit(droplets(22, speed: 6), offset: [0, 0.9, 0]),
                .mesh(.decal(.ripple, R * 2.6, .primary, life: 1.1, spin: 20, grow: 1.25, alpha: 0.85)),
                .mesh(.shockRing(R * 1.3, .secondary, life: 0.45, tex: .ring)),
                .emit(.flutter(.bubble, 10, radius: 0.6, .secondary, speed: 1.5, life: 1.0, size: 0.16), offset: [0, 0.6, 0],
                      quality: 1),
            ]
            r.hit = [
                .emit(droplets(10, speed: 4), offset: [0, 1.0, 0]),
                .mesh(.decal(.ripple, 1.4, .secondary, life: 0.6, spin: 0, grow: 1.4, alpha: 0.7)),
            ]
        case .skill2:
            r.cast = [
                .mesh(.pillar(0.5, height: 3, .secondary, life: 0.4, alpha: 0.7)),
                .mesh(.tornado(0.8, height: 2.4, .primary, life: 0.4, spin: 720)),
                .emit(droplets(18, speed: 5.5)),
                .mesh(.decal(.ripple, 2.2, .primary, life: 0.7, spin: 0, grow: 1.3, alpha: 0.75)),
            ]
            r.impact = [
                .mesh(.tornado(0.9, height: 2.6, .secondary, life: 0.45, spin: -720), at: 0.03),
                .emit(.flare(1.4, .core, life: 0.18), at: 0.05, offset: [0, 1.0, 0]),
                .emit(droplets(22, speed: 6.5), at: 0.05),
                .mesh(.shockRing(2.0, .primary, life: 0.45, tex: .ripple), at: 0.05),
                // 気絶の泡の輪
                .mesh(.halo(0.6, .secondary, life: 0.8, spin: 200, tex: .bubble), at: 0.1, offset: [0, 2.0, 0]),
                .emit(.flutter(.bubble, 12, radius: 0.8, .secondary, speed: 1.5, life: 1.0, size: 0.18), at: 0.08,
                      offset: [0, 0.6, 0], quality: 1),
            ]
        case .ultimate:
            r.cast = [
                .mesh(.decal(.ripple, 3.0, .primary, life: 1.1, spin: 40, grow: 1.4, alpha: 0.8)),
                .emit(.vortex(24, radius: 1.0, .secondary, life: 0.9, tex: .glowHard, speed: 2.5)),
                .mesh(.halo(1.2, .secondary, life: 1.1, spin: 220, tex: .ripple), offset: [0, 2.2, 0]),
                .emit(.flare(1.6, .core, life: 0.3), at: 0.5, offset: staff),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.2, .primary, life: 1.05, spin: 120, alpha: 0.7)),
                .mesh(.decal(.swirl, R * 1.8, .secondary, life: 1.05, spin: -300, alpha: 0.75)),
                .emit(.vortex(30, radius: R * 0.9, .primary, life: 0.9, tex: .streak, speed: 2)),
                .emit(.gather(24, radius: R, .secondary, life: 0.6), at: 0.4, offset: [0, 0.4, 0]),
            ]
            r.impact = [
                .emit(.flare(3.0, .core, life: 0.3, tex: .flare6), offset: [0, 1.0, 0]),
                .mesh(.tornado(R * 1.0, height: 6, .primary, life: 1.0, spin: 540)),
                .mesh(.tornado(R * 0.7, height: 4.5, .core, life: 0.8, spin: -720).with { $0.alpha = 0.55 }),
                .mesh(.pillar(0.35, height: 5, .secondary, life: 0.7)).ringed(6, radius: R * 0.9, every: 0.04),
                .mesh(.decal(.ripple, R * 3.2, .primary, life: 1.6, spin: 30, grow: 1.2, alpha: 0.85)),
                .mesh(.shockRing(R * 1.6, .core, life: 0.4, tex: .ring)),
                .mesh(.shockRing(R * 2.2, .secondary, life: 0.7, tex: .ripple), at: 0.08),
                .emit(droplets(50, speed: 11)),
                .emit(.flutter(.bubble, 24, radius: R * 0.8, .secondary, speed: 2.5, life: 1.3, size: 0.22), at: 0.1,
                      offset: [0, 0.6, 0], quality: 1),
                // 根止めの水の環
                .mesh(.halo(R * 0.8, .accent, life: 1.2, spin: -160, tex: .ringDouble), at: 0.15, offset: [0, 0.3, 0]),
                .shake(0.6),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 杖を後ろへ引き、水球を前へ押し出す
            m.chamber(0.06)
            m.push(0.06)
            m.hold(0.14) { $0.weaponR = -1.2 }
        case .skill2:
            // 杖を回して水柱へ身を沈める
            m.twirl(0.12, turns: 0.75)
            m.kneel(0.06)
            m.hold(0.1)
            m.settle(0.12)
        case .ultimate:
            // 両手を天へ掲げて長く祈り、杖を地へ突いて潮を呼ぶ
            m.raise(0.18, glow: 1.8)
            m.hold(0.3) { $0.glow = 2.2; $0.ring = 1.3; $0.headPitch = -0.5 }
            m.gather(0.12)
            m.plant(0.08)
            m.hold(0.22) { $0.glow = 2.4 }
        }
    }
}
