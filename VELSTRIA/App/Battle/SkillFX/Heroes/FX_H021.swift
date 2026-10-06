import Foundation
import VelstriaCore

// スキル演出: H021 時砂のキロス（Ranger / 砂の長銃・浮かぶ砂時計・つば広帽）。
// 主題: 時の砂。白金の芯 × 琥珀（主）× 砂色（副）× 時の青（差し色）。時計の盤面と砂の渦で「時を撃つ」。
//   パッシブ 時砂残響      — 会心の一撃で、時計の盤面が一瞬浮かび砂がこぼれる
//   S1 キロス式・一閃       — 砂を巻いた弾丸。命中で砂が弾け、時計の針が逆に跳ねる（吹き飛ばし）
//   S2 星環シフト           — 時を跳ぶ。転移元と転移先に盤面が刻まれ、砂の環が足を止める（根止め）
//   S3 境界制圧             — 地点に時計の陣が速回しで回り、砂柱が噴き上がる
//   奥義 時砂逆転            — 背後に巨大な盤面を背負って撃つ時の弾丸。軌跡に盤面が回り、命中で時が逆巻く（鈍足）

enum FX_H021: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.97, 0.88), primary: RGB(1.0, 0.7, 0.28),
                                   secondary: RGB(0.96, 0.84, 0.58), accent: RGB(0.5, 0.82, 1.0),
                                   dark: RGB(0.14, 0.1, 0.05))

    /// 銃口（局所座標）。
    private static let muzzle: SIMD3<Float> = [0.15, 1.35, 1.0]

    /// こぼれる砂（細かい粒が重力で落ちる）。
    private static func sand(_ n: Int, radius: Float, speed: Float = 2, life: Float = 0.9) -> FXEmit {
        FXEmit(tex: .sand, tint: .secondary, tintEnd: .primary, count: n, emit: 0.1, life: life, size: 0.35, sizeVar: 0.4,
               grow: 1.3, shape: .sphere(radius), speed: speed, speedVar: 0.5, gravity: 4, drag: 1.5, angleVar: 180,
               spin: 60, fade: .gradualFadeInOut)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.sprite(.clockFace, 1.0, .primary, life: 0.5, grow: 1.3, alpha: 0.9), .follow, offset: [0, 2.2, 0]),
                .emit(sand(14, radius: 0.4, speed: 1), .follow, offset: [0, 2.0, 0]),
                .emit(.flare(0.9, .core, life: 0.16), .follow, offset: [0, 2.2, 0]),
            ]
            r.hit = []
        case .skill1:
            r.cast = [
                .emit(.flare(1.3, .core, life: 0.12, tex: .flare6), at: 0.1, offset: muzzle),
                .emit(.fan(12, .primary, speed: 9, spread: 15, life: 0.22), at: 0.1, offset: muzzle),
                .emit(.smoke(4, radius: 0.15, .rgb(0.4, 0.33, 0.22), life: 0.6, size: 0.4), at: 0.1, offset: muzzle, quality: 1),
                .mesh(.sprite(.clockFace, 0.7, .accent, life: 0.25, grow: 1.6, alpha: 0.85), at: 0.1, offset: muzzle),
            ]
            r.travel = [
                .emit(.trail(.streak, .primary, rate: 70, life: 0.2, size: 0.45).with { $0.stretch = 3; $0.dir = .backward; $0.speed = 3 },
                      .follow, offset: [0, 1.15, 0]),
                .emit(.trail(.sand, .secondary, rate: 30, life: 0.6, size: 0.4).with { $0.gravity = 3; $0.spin = 90; $0.additive = true },
                      .follow, offset: [0, 1.15, 0]),
                .emit(.trail(.glowHard, .core, rate: 50, life: 0.12, size: 0.3), .follow, offset: [0, 1.15, 0]),
            ]
            r.impact = [
                .emit(.flare(1.5, .core, life: 0.18, tex: .flare6), offset: [0, 1.1, 0]),
                .mesh(.decal(.clockFace, R * 2.4, .primary, life: 0.8, spin: -360, alpha: 0.85)),
                .emit(sand(20, radius: 0.4, speed: 4), offset: [0, 1.0, 0]),
                .emit(.fan(14, .secondary, speed: 7, spread: 25, life: 0.3), offset: [0, 1.0, 0]),
                .mesh(.shockRing(R * 1.3, .accent, life: 0.4)),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.12), offset: [0, 1.1, 0]),
                .emit(sand(8, radius: 0.3, speed: 3), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            r.cast = [
                .mesh(.decal(.clockFace, 2.2, .primary, life: 0.7, spin: 540, alpha: 0.85)),
                .emit(.vortex(16, radius: 0.6, .secondary, life: 0.5, tex: .sand, speed: 2)),
                .emit(.flare(1.2, .accent, life: 0.18), offset: [0, 1.0, 0]),
            ]
            r.impact = [
                .emit(.flare(1.5, .core, life: 0.18), at: 0.04, offset: [0, 1.0, 0]),
                .mesh(.decal(.clockFace, 2.8, .accent, life: 1.0, spin: -540, alpha: 0.85), at: 0.04),
                .mesh(.halo(1.3, .secondary, life: 1.0, spin: 200, tex: .ringDouble), at: 0.06, offset: [0, 0.3, 0]),
                .emit(sand(18, radius: 1.0, speed: 1.5, life: 1.0), at: 0.05, offset: [0, 0.8, 0]),
                .mesh(.shockRing(2.0, .primary, life: 0.4), at: 0.04),
            ]
        case .skill3:
            r.cast = [
                .emit(.flare(1.2, .core, life: 0.14), at: 0.12, offset: [0.1, 1.8, 0.7]),
            ]
            r.telegraph = [
                .mesh(.decal(.clockFace, R * 2.2, .primary, life: 0.6, spin: 720, alpha: 0.75)),
                .mesh(.decal(.ringDouble, R * 2.4, .accent, life: 0.6, spin: -200, alpha: 0.5)),
                .emit(.vortex(16, radius: R * 0.8, .secondary, life: 0.5, tex: .sand, speed: 1.5)),
            ]
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.2, tex: .flare6), offset: [0, 0.6, 0]),
                .mesh(.tornado(R * 0.8, height: 4, .primary, life: 0.7, spin: 480)),
                .mesh(.pillar(R * 0.4, height: 4.5, .secondary, life: 0.5)),
                .mesh(.shockRing(R * 1.2, .accent)),
                .emit(sand(30, radius: R * 0.5, speed: 5, life: 1.1)),
                .emit(.wave(R * 1.3, .primary, life: 0.5), offset: [0, 0.1, 0]),
                .shake(0.15),
            ]
        case .ultimate:
            r.cast = [
                .mesh(.wall(.clockFace, width: 3.4, height: 3.4, .primary, life: 0.9, alpha: 0.8).with { $0.spin = 0 },
                      offset: [0, 0.2, -0.8]),
                .emit(.gather(26, radius: 1.4, .accent, life: 0.3), offset: muzzle),
                .emit(.flare(2.6, .core, life: 0.25, tex: .flare6), at: 0.3, offset: muzzle),
                .emit(.fan(22, .primary, speed: 12, spread: 14, life: 0.3), at: 0.3, offset: muzzle),
                .mesh(.ray(.streak, length: 8, width: 1.2, .primary, life: 0.3, alpha: 0.85), at: 0.3, offset: [0, 0.05, 4.5]),
                .shake(0.35, at: 0.3),
            ]
            r.travel = [
                .mesh(.sprite(.clockFace, 1.6, .accent, life: 1.1, grow: 1.0, alpha: 0.9).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.15, 0]),
                .emit(.trail(.glow, .primary, rate: 80, life: 0.35, size: 0.9), .follow, offset: [0, 1.15, 0]),
                .emit(.trail(.sand, .secondary, rate: 40, life: 0.8, size: 0.6).with { $0.gravity = 2; $0.spin = 120 },
                      .follow, offset: [0, 1.15, 0]),
                .emit(.trail(.streak, .core, rate: 60, life: 0.25, size: 0.45).with { $0.stretch = 3; $0.dir = .backward; $0.speed = 4 },
                      .follow, offset: [0, 1.15, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(3.0, .core, life: 0.28, tex: .flare6), offset: [0, 1.1, 0]),
                .mesh(.decal(.clockFace, R * 3.4, .primary, life: 1.6, spin: -720, alpha: 0.9)),
                .mesh(.decal(.ringDouble, R * 3.8, .accent, life: 1.4, spin: 300, alpha: 0.6)),
                .mesh(.tornado(R * 1.0, height: 5, .secondary, life: 1.0, spin: -540)),
                .mesh(.shockRing(R * 2.2, .core, life: 0.4)),
                .mesh(.shockRing(R * 2.8, .accent, life: 0.7), at: 0.06),
                .emit(sand(40, radius: R * 0.6, speed: 7, life: 1.3)),
                .emit(.vortex(24, radius: R * 1.2, .accent, life: 0.9, speed: 2.5), at: 0.1, quality: 1),
                .emit(.sparks(24, speed: 9, .core, end: .primary, life: 0.45), offset: [0, 1.0, 0]),
                .shake(0.55),
            ]
            r.hit = [
                .emit(.flare(1.2, .core, life: 0.14), offset: [0, 1.1, 0]),
                .mesh(.sprite(.clockFace, 0.9, .accent, life: 0.35, grow: 1.4), offset: [0, 1.3, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 構えて撃つ（小さな反動）
            m.aim(0.08)
            m.recoil(0.05, power: 0.6)
            m.hold(0.14)
        case .skill2:
            // 帽子を押さえて後ろへ跳び、銃を構え直す
            m.backstep(0.12, distance: 0.4)
            m.aim(0.08, up: 0.05)
            m.settle(0.1)
        case .skill3:
            // 斜め上へ向けて撃ち上げる
            m.aim(0.08, up: 0.5)
            m.recoil(0.06, power: 0.8)
            m.hold(0.16)
        case .ultimate:
            // 腰を落とし、長く狙いを定めて撃つ → 大きな反動
            m.brace(0.08, depth: 0.14)
            m.aim(0.14)
            m.hold(0.1) { $0.glow = 2.2; $0.ring = 1.2 }
            m.recoil(0.07, power: 1.4)
            m.settle(0.16)
        }
    }
}
