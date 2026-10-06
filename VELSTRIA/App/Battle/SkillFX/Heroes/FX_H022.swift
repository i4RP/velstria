import Foundation
import VelstriaCore

// スキル演出: H022 蒼爪のレア（Arcanist / 蒼い爪 2 本・獣耳・浮かぶ爪の結晶）。
// 主題: 蒼い狐火と氷の爪。白い芯 × 蒼（主）× 氷の水色（副）× 月白（差し色）。爪痕・氷晶・狐火。
//   パッシブ 蒼爪連舞      — スキルが英雄に当たると、爪の結晶が回って青い爪痕が閃く
//   S1 レア式・一閃         — 振り抜いた爪から蒼い爪撃が飛ぶ。命中で爪痕と氷の輪が足を縛る（根止め）
//   S2 星環シフト           — 狐火となって跳び、転移先に蒼い火の粉と爪の輪が舞う
//   S3 境界制圧             — 地点に霜の陣、氷の爪が地から突き出す（鈍足）
//   奥義 蒼爪月輪            — 1 秒の溜めで月と爪の大紋章が地に浮かび、巨大な十字の爪撃と氷柱の環が裂く（気絶）

enum FX_H022: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.9, 0.98, 1.0), primary: RGB(0.24, 0.6, 1.0),
                                   secondary: RGB(0.6, 0.9, 1.0), accent: RGB(0.88, 0.94, 1.0),
                                   dark: RGB(0.03, 0.06, 0.15))

    /// 氷の爪（地から突き出す半透明の尖塔）。
    private static func iceFang(_ h: Float, life: Float = 1.0) -> FXMesh {
        FXMesh(shape: .spire, tex: .shard, tint: .secondary, alpha: 0.8, size: [0.28, 0.1, 0.28], sizeEnd: [0.36, h, 0.36],
               ease: .outBack, life: life, fadeIn: 0.02, fadeOut: 0.7, pitch: 12)
    }

    /// 狐火（青い炎の粒が揺れながら昇る）。
    private static func foxfire(_ n: Int, radius: Float, life: Float = 0.9) -> FXEmit {
        FXEmit.rising(n, radius: radius, .primary, speed: 1.8, life: life, size: 0.26, tex: .flame).with {
            $0.tintEnd = .secondary; $0.noise = 0.8; $0.orient = .upright
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.sprite(.claw, 1.2, .primary, life: 0.3, grow: 1.2), .follow, offset: [0, 1.2, 0]),
                .emit(.flutter(.shard, 10, radius: 0.6, .secondary, speed: 2, life: 0.7, size: 0.16), .follow, offset: [0, 1.2, 0]),
                .mesh(.halo(0.8, .primary, life: 0.6, spin: 400, tex: .ringDouble), .follow, offset: [0, 1.2, 0]),
            ]
            r.hit = []
        case .skill1:
            r.cast = [
                .mesh(.slash(1.2, .primary, from: 70, to: -70, height: 1.1, tilt: -30, life: 0.18, tex: .slashThin), at: 0.08,
                      offset: [0, 1.1, 0]),
                .emit(.flare(1.0, .core, life: 0.14), at: 0.09, offset: [0, 1.2, 0.7]),
            ]
            r.travel = [
                .mesh(.sprite(.claw, 1.3, .primary, life: 1.0, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.8 }, .follow,
                      offset: [0, 1.1, 0]),
                .emit(.trail(.glow, .secondary, rate: 60, life: 0.25, size: 0.6), .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.shard, .accent, rate: 30, life: 0.4, size: 0.18).with { $0.angleVar = 180; $0.spin = 300 },
                      .follow, offset: [0, 1.1, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.4, .core, life: 0.16), offset: [0, 1.1, 0]),
                .mesh(FXMesh(shape: .disc, tex: .claw, tint: .primary, alpha: 0.95, size: [R * 1.2, 1, R * 1.8],
                              sizeEnd: [R * 1.4, 1, R * 2.0], ease: .out, life: 0.9, fadeIn: 0.03, fadeOut: 0.55, yaw: 20)),
                .mesh(.halo(R * 0.8, .secondary, life: 0.9, spin: 200, tex: .ringDouble), at: 0.04, offset: [0, 0.3, 0]),
                .emit(.flutter(.shard, 16, radius: 0.4, .secondary, speed: 5, life: 0.7, size: 0.18).with { $0.gravity = 6 },
                      offset: [0, 1.0, 0]),
                .mesh(.shockRing(R * 1.2, .accent, life: 0.35)),
            ]
            r.hit = [
                .mesh(.sprite(.claw, 0.9, .primary, life: 0.22, grow: 1.2), offset: [0, 1.1, 0]),
                .emit(.sparks(8, speed: 5, .accent, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            r.cast = [
                .emit(foxfire(18, radius: 0.5, life: 0.7)),
                .emit(.bloom(1.4, .primary, life: 0.3), offset: [0, 1.0, 0]),
                .mesh(.sprite(.moon, 1.0, .accent, life: 0.35, grow: 0.6, alpha: 0.85), offset: [0, 1.5, 0]),
            ]
            r.impact = [
                .emit(.flare(1.5, .core, life: 0.18), at: 0.04, offset: [0, 1.0, 0]),
                .emit(foxfire(22, radius: 0.9), at: 0.04),
                .mesh(FXMesh(shape: .disc, tex: .claw, tint: .primary, alpha: 0.9, size: [1.2, 1, 1.8], sizeEnd: [1.5, 1, 2.2],
                              ease: .out, life: 0.8, fadeIn: 0.03, fadeOut: 0.55), at: 0.04)
                    .ringed(3, radius: 0.6),
                .mesh(.shockRing(2.0, .secondary, life: 0.4), at: 0.04),
            ]
        case .skill3:
            r.cast = [
                .mesh(.slash(1.0, .secondary, from: -60, to: 60, height: 1.6, tilt: 60, life: 0.2, tex: .slashThin), at: 0.1,
                      offset: [0, 1.4, 0]),
                .emit(.flare(1.0, .core, life: 0.14), at: 0.12, offset: [0, 1.7, 0.4]),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.1, .primary, life: 0.6, spin: 90, alpha: 0.7)),
                .mesh(.decal(.hexShield, R * 1.8, .secondary, life: 0.6, spin: -60, alpha: 0.5)),
                .emit(.motes(14, radius: R * 0.8, .accent, life: 0.6, rise: 0.4), offset: [0, 0.2, 0]),
            ]
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.2, tex: .flare6), offset: [0, 0.6, 0]),
                .mesh(iceFang(1.8, life: 1.1)),
                .mesh(iceFang(1.2, life: 1.0)).ringed(6, radius: R * 0.65, every: 0.025),
                .mesh(.decal(.crack, R * 2.2, .secondary, life: 1.2, spin: 0, alpha: 0.75)),
                .mesh(.shockRing(R * 1.2, .accent, life: 0.4)),
                .emit(.flutter(.shard, 20, radius: R * 0.4, .secondary, speed: 5, life: 0.8, size: 0.18).with { $0.gravity = 8 }),
                .emit(.motes(16, radius: R * 0.8, .accent, life: 1.2, rise: 0.3), at: 0.1, offset: [0, 0.4, 0], quality: 1),
                .shake(0.15),
            ]
        case .ultimate:
            r.cast = [
                .emit(foxfire(24, radius: 0.8, life: 1.0)),
                .mesh(.sprite(.moon, 1.8, .accent, life: 1.0, grow: 1.2, alpha: 0.85), offset: [0, 2.6, 0]),
                .mesh(.halo(1.0, .primary, life: 1.0, spin: 300, tex: .ringDouble), offset: [0, 1.4, 0]),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.2, .primary, life: 1.05, spin: 100, alpha: 0.75)),
                .mesh(.decal(.moon, R * 1.6, .accent, life: 1.05, spin: -80, alpha: 0.65)),
                .mesh(FXMesh(shape: .disc, tex: .claw, tint: .secondary, alpha: 0.5, size: [R * 1.4, 1, R * 2.0],
                              sizeEnd: [R * 1.4, 1, R * 2.0], ease: .linear, life: 1.05, fadeIn: 0.3, fadeOut: 0.8)),
                .emit(.gather(24, radius: R, .secondary, life: 0.6), at: 0.4, offset: [0, 0.4, 0]),
            ]
            r.impact = [
                .emit(.flare(3.0, .core, life: 0.3, tex: .flare6), offset: [0, 1.0, 0]),
                // 十字の大爪撃
                .mesh(FXMesh(shape: .disc, tex: .claw, tint: .primary, alpha: 1, size: [R * 1.4, 1, R * 2.2],
                              sizeEnd: [R * 1.55, 1, R * 2.45], ease: .out, life: 1.2, fadeIn: 0.02, fadeOut: 0.55, yaw: 45)),
                .mesh(FXMesh(shape: .disc, tex: .claw, tint: .secondary, alpha: 1, size: [R * 1.4, 1, R * 2.2],
                              sizeEnd: [R * 1.55, 1, R * 2.45], ease: .out, life: 1.2, fadeIn: 0.02, fadeOut: 0.55, yaw: -45),
                      at: 0.08),
                .mesh(.sprite(.claw, 3.0, .primary, life: 0.3, grow: 1.2), at: 0.02, offset: [0, 1.4, 0]),
                .mesh(iceFang(2.2, life: 1.4)).ringed(8, radius: R * 0.85, every: 0.025),
                .mesh(.decal(.moon, R * 2.8, .accent, life: 1.4, spin: 40, alpha: 0.8)),
                .mesh(.shockRing(R * 1.6, .core, life: 0.4)),
                .mesh(.shockRing(R * 1.9, .primary, life: 0.7), at: 0.07),
                .emit(.flutter(.shard, 36, radius: R * 0.5, .secondary, speed: 8, life: 0.9, size: 0.2).with { $0.gravity = 8 }),
                .emit(foxfire(28, radius: R * 0.9, life: 1.2), at: 0.1, quality: 1),
                // 気絶の月の輪
                .mesh(.halo(R * 0.55, .accent, life: 1.1, spin: 260, tex: .ringDouble), at: 0.15, offset: [0, 0.5, 0]),
                .shake(0.65),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 右の爪を振り抜いて爪撃を飛ばす
            m.windup(0.05, side: 1, power: 0.9)
            m.slash(0.06, side: 1, power: 1.1)
            m.hold(0.14)
        case .skill2:
            // 狐のように身を丸めて跳ぶ
            m.brace(0.04, depth: 0.16)
            m.leap(0.12, height: 0.5, forward: 0.3)
            m.land(0.08, depth: 0.14)
            m.settle(0.1)
        case .skill3:
            // 両爪を下から天へ切り上げる
            m.uppercut(0.12)
            m.hold(0.16) { $0.glow = 1.8 }
        case .ultimate:
            // 両爪を胸に溜めて祈り → 十字に振り下ろす
            m.gather(0.16)
            m.raise(0.2, glow: 2.0)
            m.hold(0.22) { $0.ring = 1.4; $0.glow = 2.3 }
            m.crossSlash(0.14)
            m.hold(0.16)
        }
    }
}
