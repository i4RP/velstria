import Foundation
import VelstriaCore

// スキル演出: H012 玻璃歌のエリネ（Assassin / 硝子の短剣 2 本・浮かぶ硝子片）。
// 主題: 硝子の歌。白い芯 × 氷青（主）× 虹の藤（副）× 桃のプリズム（差し色）。砕ける硝子片と響く音の輪。
//   パッシブ 共鳴硝子      — 奇襲の一撃で、相手の周りに硝子片が砕け散り音符が鳴る
//   S1 エリネ式・一閃       — 両刃の交差斬りから硝子片の扇が飛ぶ。足元に響く音の輪（根止め）
//   S2 星環シフト           — 硝子の残像を残して駆け、着地で周囲の硝子が砕け散る
//   S3 境界制圧             — 歌声が地点で結晶の柱となって立ち、音の波が広がる（鈍足）
//   奥義 玻璃大合唱          — 背後へ転移し、結晶の檻が対象を閉じ込め、大合唱の音の輪が三重に響いて砕ける（気絶）

enum FX_H012: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.95, 1.0, 1.0), primary: RGB(0.45, 0.88, 1.0),
                                   secondary: RGB(0.82, 0.72, 1.0), accent: RGB(1.0, 0.72, 0.92),
                                   dark: RGB(0.04, 0.06, 0.1))

    /// 結晶の柱（半透明の氷青の尖塔）。
    private static func crystal(_ h: Float, _ tint: FXTint = .primary, life: Float = 0.9) -> FXMesh {
        FXMesh(shape: .spire, tex: .shard, tint: tint, alpha: 0.75, size: [0.25, 0.1, 0.25], sizeEnd: [0.32, h, 0.32],
               ease: .outBack, life: life, fadeIn: 0.02, fadeOut: 0.7)
    }

    /// 砕ける硝子片（加算の結晶片が飛び散る）。
    private static func shatter(_ n: Int, speed: Float = 6) -> FXEmit {
        FXEmit.flutter(.shard, n, radius: 0.3, .primary, speed: speed, life: 0.7, size: 0.2).with {
            $0.tintEnd = .accent; $0.gravity = 7; $0.drag = 1.2
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(shatter(14, speed: 5), .follow, offset: [0, 1.1, 0]),
                .emit(.flutter(.note, 5, radius: 0.5, .accent, speed: 1.2, life: 0.9, size: 0.22).with { $0.gravity = -1 },
                      .follow, offset: [0, 1.6, 0]),
                .emit(.flare(1.1, .core, life: 0.16, tex: .flare6), .follow, offset: [0, 1.1, 0]),
                .mesh(.decal(.soundWave, 1.6, .secondary, life: 0.5, spin: 0, grow: 1.4, alpha: 0.7), .follow),
            ]
            r.hit = []
        case .skill1:
            r.impact = [
                .mesh(.slash(R * 0.9, .primary, from: 75, to: -75, height: 1.0, tilt: -25, life: 0.22, tex: .slashThin), at: 0.07,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.9, .secondary, from: -75, to: 75, height: 1.05, tilt: 25, life: 0.22, tex: .slashThin),
                      at: 0.08, offset: [0, 1.05, 0]),
                .emit(.fan(18, .primary, speed: R * 4, spread: 35, life: 0.4, tex: .shard, size: 0.2), at: 0.08,
                      offset: [0, 1.0, 0.3]),
                .emit(.flare(1.1, .core, life: 0.15, tex: .flare6), at: 0.08, offset: [0, 1.0, R * 0.4]),
                .mesh(.decal(.soundWave, R * 1.6, .secondary, life: 0.6, spin: 0, grow: 1.3, alpha: 0.8).with { $0.yaw = 90 },
                      at: 0.09, offset: [0, 0, R * 0.4]),
                .mesh(.shockRing(R * 0.9, .accent, life: 0.4, tex: .ripple), at: 0.1, offset: [0, 0, R * 0.5]),
            ]
            r.hit = [
                .emit(shatter(8, speed: 4), offset: [0, 1.0, 0]),
                .mesh(.halo(0.6, .primary, life: 0.8, spin: 180, tex: .ringDouble), offset: [0, 0.25, 0]),
            ]
        case .skill2:
            r.cast = [
                .emit(shatter(10, speed: 3)),
                .emit(.trail(.shard, .primary, rate: 50, life: 0.5, size: 0.25).with {
                    $0.duration = 0.32; $0.angleVar = 180; $0.shape = .sphere(0.4)
                }, .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.glow, .secondary, rate: 50, life: 0.25, size: 0.5).with { $0.duration = 0.32 }, .follow,
                      offset: [0, 1.0, 0]),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.18, tex: .flare6), offset: [0, 1.0, 0]),
                .emit(shatter(26, speed: 8), offset: [0, 0.9, 0]),
                .mesh(.shockRing(R * 1.2, .primary, life: 0.4, tex: .ringDouble)),
                .mesh(crystal(0.9, .secondary, life: 0.6)).ringed(5, radius: R * 0.7, every: 0.02),
                .emit(.wave(R * 1.3, .accent, life: 0.4), offset: [0, 0.1, 0]),
                .shake(0.15),
            ]
        case .ultimate:
            r.cast = [
                .emit(shatter(16, speed: 4), offset: [0, 1.0, 0]),
                .emit(.flare(1.4, .secondary, life: 0.2), offset: [0, 1.0, 0]),
                .mesh(.decal(.soundWave, 2.0, .accent, life: 0.4, spin: 0, grow: 1.4, alpha: 0.7)),
            ]
            r.impact = [
                .emit(.flare(2.4, .core, life: 0.26, tex: .flare6), offset: [0, 1.2, 0]),
                // 結晶の檻
                .mesh(crystal(2.8, .primary, life: 1.3)).ringed(8, radius: 1.3, every: 0.025),
                .mesh(.dome(1.5, .secondary, life: 1.2, tex: .hexShield, alpha: 0.45), at: 0.1),
                .mesh(.decal(.runeCircle, 4.4, .primary, life: 1.5, spin: 70, alpha: 0.85)),
                // 三重に響く大合唱
                .mesh(.shockRing(3.2, .accent, life: 0.55, tex: .ripple), at: 0.15).repeated(3, every: 0.2),
                .emit(.flutter(.note, 14, radius: 1.5, .accent, speed: 2, life: 1.3, size: 0.26).with { $0.gravity = -1.2 },
                      at: 0.2, offset: [0, 1.5, 0]),
                // 最後に砕ける
                .emit(shatter(40, speed: 9), at: 0.75, offset: [0, 1.2, 0]),
                .emit(.flare(2.6, .accent, life: 0.24, tex: .flare6), at: 0.75, offset: [0, 1.2, 0]),
                .mesh(.shockRing(3.6, .primary, life: 0.45), at: 0.75),
                // 気絶の光輪
                .mesh(.halo(0.5, .core, life: 1.0, spin: 400, tex: .ringDouble), at: 0.2, offset: [0, 2.1, 0]),
                .shake(0.3, at: 0.1),
                .shake(0.5, at: 0.75),
            ]
            r.hit = [
                .emit(shatter(8, speed: 5), offset: [0, 1.1, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 両刃を開いて交差させる（歌うように身を反らせて締める）
            m.crossSlash(0.12)
            m.hold(0.1) { $0.headPitch = -0.2 }
        case .skill2:
            // 低く滑るように駆け、着地で両刃を外へ払う
            m.dash(0.06, lean: 0.55)
            m.hold(0.1)
            m.key(0.07, .snap) { p in
                p.armR = ArmPose(pitch: 1.2, out: 1.2, yaw: -0.2, elbow: 0.1)
                p.armL = ArmPose(pitch: 1.2, out: 1.2, yaw: -0.2, elbow: 0.1)
                p.weaponR = -1.6; p.weaponL = -1.6; p.glow = 1.5
            }
            m.settle(0.1)
        case .ultimate:
            // 背後で一回転 → 交差斬り → 両腕を広げて大合唱
            m.spin(0.22, turns: 1.25)
            m.crossSlash(0.12)
            m.raise(0.12, glow: 2.0)
            m.hold(0.24) { $0.ring = 1.4 }
        }
    }
}
