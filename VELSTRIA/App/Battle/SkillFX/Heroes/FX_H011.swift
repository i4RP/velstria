import Foundation
import VelstriaCore

// スキル演出: H011 鉄翼のルーク（Support / 鉄の翼・灯火の杖・鉄の面頬）。
// 主題: 鋼の翼と守りの灯。白い芯 × 青緑の灯（主）× 鋼の銀（副）× 灯火の金（差し色）。羽根と六角の盾で「守る」を見せる。
//   パッシブ 翼装展開      — スキル後に味方を癒やすと、鋼の羽根が舞い六角の盾が一瞬その身を覆う
//   S1 ルーク式・一閃       — 杖から鋼の羽根の一斉射。命中で羽根が弾け、盾の衝撃が押し返す（吹き飛ばし）
//   S2 星環シフト           — 翼を広げて滑空し、転移先で羽根の輪が敵を縫い止める（根止め）
//   S3 境界制圧             — 地点に灯火の六角陣。光の盾が立ち上がり、味方を癒やす
//   奥義 鉄翼急襲            — 巨大な鉄翼を広げて味方全員を包む。羽根の嵐と盾の大円陣（鈍足）

enum FX_H011: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.92, 1.0, 1.0), primary: RGB(0.28, 0.86, 1.0),
                                   secondary: RGB(0.78, 0.86, 0.95), accent: RGB(1.0, 0.86, 0.5),
                                   dark: RGB(0.05, 0.08, 0.1))

    private static let staff: SIMD3<Float> = [0.3, 1.8, 0.4]

    /// 鋼の羽根（舞いながら落ちる）。
    private static func feathers(_ n: Int, radius: Float, speed: Float = 2.5, life: Float = 1.1) -> FXEmit {
        FXEmit.flutter(.feather, n, radius: radius, .secondary, speed: speed, life: life, size: 0.24).with {
            $0.tintEnd = .primary; $0.gravity = 1.6
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.dome(1.1, .primary, life: 0.7, tex: .hexShield, alpha: 0.55), .follow),
                .emit(feathers(10, radius: 0.6, speed: 1.6), .follow, offset: [0, 1.4, 0]),
                .emit(.flare(1.0, .core, life: 0.18), .follow, offset: [0, 1.1, 0]),
            ]
            r.hit = []
        case .skill1:
            r.cast = [
                .emit(.flare(1.1, .core, life: 0.15), at: 0.1, offset: [0.2, 1.5, 0.6]),
                .emit(.fan(16, .secondary, speed: 10, spread: 22, life: 0.3, tex: .feather, size: 0.25), at: 0.1,
                      offset: [0.2, 1.4, 0.5]),
            ]
            r.travel = [
                .emit(.trail(.feather, .secondary, rate: 40, life: 0.4, size: 0.3).with {
                    $0.shape = .sphere(0.3); $0.angleVar = 180; $0.spin = 200
                }, .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.glow, .primary, rate: 60, life: 0.25, size: 0.6), .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.streak, .core, rate: 50, life: 0.15, size: 0.3).with { $0.stretch = 2.5; $0.dir = .backward; $0.speed = 2 },
                      .follow, offset: [0, 1.1, 0]),
            ]
            r.impact = [
                .emit(.flare(1.4, .core, life: 0.18, tex: .flare6), offset: [0, 1.1, 0]),
                .mesh(.wall(.hexShield, width: 2.2, height: 2.0, .primary, life: 0.4, alpha: 0.75), offset: [0, 0, -0.3]),
                .emit(feathers(14, radius: 0.5, speed: 4, life: 0.9), offset: [0, 1.1, 0]),
                .mesh(.shockRing(R * 1.4, .secondary, life: 0.4)),
                .emit(.fan(14, .primary, speed: 8, spread: 25, life: 0.3), offset: [0, 1.0, 0]),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.1, 0]),
                .emit(feathers(5, radius: 0.3, speed: 3, life: 0.7), offset: [0, 1.1, 0]),
            ]
        case .skill2:
            r.cast = [
                .emit(feathers(16, radius: 0.7, speed: 3.5)),
                .mesh(.wall(.feather, width: 1.6, height: 2.2, .secondary, life: 0.4, alpha: 0.7).with { $0.yaw = 70 },
                      offset: [-0.5, 0.2, -0.2]),
                .mesh(.wall(.feather, width: 1.6, height: 2.2, .secondary, life: 0.4, alpha: 0.7).with { $0.yaw = -70 },
                      offset: [0.5, 0.2, -0.2]),
                .emit(.flare(1.2, .primary, life: 0.18), offset: [0, 1.2, 0]),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.18), at: 0.04, offset: [0, 1.0, 0]),
                .mesh(.decal(.hexShield, 2.8, .primary, life: 1.0, spin: 60, alpha: 0.8), at: 0.04),
                // 羽根が地へ刺さって縫い止める
                .mesh(.wall(.feather, width: 0.4, height: 0.9, .secondary, life: 1.0, alpha: 0.95), at: 0.06)
                    .ringed(6, radius: 1.2, every: 0.02),
                .mesh(.halo(1.1, .accent, life: 0.9, spin: 160, tex: .ringDouble), at: 0.08, offset: [0, 0.3, 0]),
                .emit(feathers(10, radius: 1.0, speed: 2), at: 0.05, offset: [0, 1.0, 0], quality: 1),
            ]
        case .ultimate:
            r.cast = [
                .emit(.flare(2.0, .accent, life: 0.3, tex: .flare6), at: 0.18, offset: [0, 2.2, 0]),
                .mesh(.wall(.feather, width: 3.2, height: 3.4, .secondary, life: 0.9, alpha: 0.8).with { $0.yaw = 60 },
                      at: 0.1, offset: [-0.9, 0.3, -0.4]),
                .mesh(.wall(.feather, width: 3.2, height: 3.4, .secondary, life: 0.9, alpha: 0.8).with { $0.yaw = -60 },
                      at: 0.1, offset: [0.9, 0.3, -0.4]),
            ]
            r.impact = [
                .mesh(.decal(.hexShield, 7.0, .primary, life: 1.6, spin: 30, alpha: 0.8), at: 0.2),
                .mesh(.decal(.runeCircle, 6.0, .accent, life: 1.4, spin: -40, alpha: 0.6), at: 0.2),
                .mesh(.dome(3.2, .primary, life: 1.4, tex: .hexShield, alpha: 0.45), at: 0.22),
                .mesh(.shockRing(5.0, .secondary, life: 0.7), at: 0.2),
                .mesh(.pillar(0.3, height: 4, .accent, life: 0.8)).ringed(6, radius: 3.0, every: 0.04),
                .emit(feathers(40, radius: 3.0, speed: 3, life: 1.6), at: 0.25, offset: [0, 2.0, 0]),
                .emit(.rising(30, radius: 3.0, .rgb(0.5, 1.0, 0.75), speed: 3, life: 1.1), at: 0.25),
                .mesh(.halo(2.6, .primary, life: 1.3, spin: 120, tex: .ringDouble), at: 0.25, offset: [0, 0.4, 0]),
                .shake(0.45, at: 0.2),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 杖を横に払って羽根を撃ち出す
            m.throwCast(0.14)
            m.hold(0.14) { $0.wings = 1.2 }
        case .skill2:
            // 翼を広げて低く滑空する
            m.key(0.08, .out) { p in p.wings = 1.6; p.armR.out = 0.9; p.armL.out = 0.9 }
            m.dash(0.08, lean: 0.4)
            m.hold(0.1) { $0.wings = 1.5 }
            m.settle(0.12)
        case .ultimate:
            // 翼を大きく開いて天を仰ぎ、味方を抱くように腕を広げる
            m.raise(0.16, glow: 2.0)
            m.hold(0.12) { $0.wings = 2.0; $0.ring = 1.4 }
            m.roar(0.12)
            m.hold(0.22) { $0.wings = 2.0; $0.glow = 2.2 }
        }
    }
}
