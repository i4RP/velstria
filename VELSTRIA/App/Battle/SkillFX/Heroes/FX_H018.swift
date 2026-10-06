import Foundation
import VelstriaCore

// スキル演出: H018 花星のセリア（Assassin / 花弁の双刃、花冠）。
// 主題: 花と星。桃（主）× 金の星（副）× 淡い桜色（差し色）。華やかに舞い、一瞬で咲いて散る。
//   パッシブ 花星循環       — 奇襲の一撃で、斬った相手の上に金の星が咲き、花弁が弾ける
//   S1 Celia式・一閃        — 双刃の交差斬りから、花吹雪が前方へ長く吹き抜ける（扇）
//   S2 星環シフト           — 流れ星となって駆け、着地で地に金の五芒星が刻まれる。散った花弁が足を絡める（鈍足）
//   S3 境界制圧             — 花の蕾を放ると地に五弁の花が開き、咲き誇って弾ける。頭上を星が回る（気絶）
//   奥義 花星満開            — 花弁となって消え、標的の背後に咲く。八弁の大輪と星が満開に咲き、花嵐が吹き飛ばす

enum FX_H018: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.95, 0.97), primary: RGB(1.0, 0.42, 0.7),
                                   secondary: RGB(1.0, 0.8, 0.3), accent: RGB(1.0, 0.68, 0.86),
                                   dark: RGB(0.22, 0.05, 0.12))

    /// 花弁の吹雪（前方へ流れる）。
    private static func petalGust(_ count: Int, speed: Float, spread: Float, life: Float = 0.9) -> FXEmit {
        FXEmit.flutter(.petal, count, radius: 0.3, .primary, speed: speed, life: life, size: 0.2).with {
            $0.dir = .forward
            $0.spread = spread
            $0.gravity = 0.4
            $0.drag = 1.2
            $0.tintEnd = .accent
        }
    }

    /// 頭上を回る星（気絶）。
    private static let starCrown = FXEmit(tex: .star, tint: .secondary, tintEnd: .core, count: 5, life: 1.0, lifeVar: 0,
                                          size: 0.2, sizeVar: 0.1, shape: .ring(0.35), surface: true, dir: .up,
                                          speed: 0.05, spin: 240, fade: .gradualFadeInOut, vortex: 7)

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            // 原点は奇襲を受けた相手
            r.cast = [
                .emit(.flare(1.3, .core, life: 0.18, tex: .flare4), .follow, offset: [0, 1.2, 0]),
                .mesh(.sprite(.star, 1.1, .secondary, life: 0.4, grow: 1.6), .follow, offset: [0, 1.4, 0]),
                .mesh(.decal(.star, 1.8, .primary, life: 0.7, spin: 120, alpha: 0.8), .follow),
                .emit(.flutter(.petal, 16, radius: 0.4, .primary, speed: 4, life: 0.9), .follow, offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 5, .core, end: .secondary), .follow, offset: [0, 1.1, 0]),
            ]
            r.hit = []
        case .skill1:
            // 交差斬り（0.15 秒）→ 花吹雪が前方へ長く吹き抜ける（射程 R）
            let near = min(R, 1.8)
            r.cast = [
                .emit(.flutter(.petal, 6, radius: 0.4, .accent, speed: 1, life: 0.5), offset: [0, 1.0, 0], quality: 1),
            ]
            r.impact = [
                .mesh(.slash(near, .core, from: 70, to: -50, height: 1.0, tilt: 35, life: 0.18, tex: .slashThin), at: 0.14,
                      offset: [0, 1.05, 0]),
                .mesh(.slash(near, .core, from: -70, to: 50, height: 1.0, tilt: -35, life: 0.18, tex: .slashThin),
                      at: 0.15, offset: [0, 1.05, 0]),
                .mesh(.slash(near * 1.1, .primary, from: 70, to: -50, height: 1.0, tilt: 35, life: 0.3), at: 0.14,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(near * 1.1, .primary, from: -70, to: 50, height: 1.0, tilt: -35, life: 0.3), at: 0.15,
                      offset: [0, 1.0, 0]),
                // 吹き抜ける花の道
                .mesh(.ray(.streak, length: R, width: 1.6, .primary, life: 0.45, alpha: 0.7), at: 0.15,
                      offset: [0, 0.05, R * 0.5]),
                .mesh(.ray(.streak, length: R * 0.9, width: 0.5, .secondary, life: 0.3), at: 0.16,
                      offset: [0, 0.06, R * 0.45]),
                .emit(.flare(1.1, .core, life: 0.14), at: 0.15, offset: [0, 1.0, 0.6]),
                .emit(petalGust(36, speed: R * 2.2, spread: 20), at: 0.15, offset: [0, 0.9, 0.4]),
                .emit(.fan(18, .secondary, speed: R * 2.5, spread: 18, life: 0.4, tex: .twinkle, size: 0.16), at: 0.16,
                      offset: [0, 0.9, 0.4]),
                .emit(.lineBurst(R, count: 10, .secondary, life: 0.6, size: 0.25, tex: .star), at: 0.2,
                      offset: [0, 0.2, 0.3], quality: 1),
                .shake(0.1, at: 0.15),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.0, 0]),
                .mesh(.slash(0.7, .primary, from: 50, to: -50, height: 1.0, tilt: 30, life: 0.2), offset: [0, 1.0, 0]),
                .emit(.flutter(.petal, 8, radius: 0.3, .primary, speed: 3, life: 0.7), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            // 流れ星の突進 → 着地で五芒星
            r.cast = [
                .emit(.flare(1.0, .secondary, life: 0.16, tex: .flare4), offset: [0, 1.0, 0.2]),
                .emit(.trail(.twinkle, .secondary, rate: 70, life: 0.35, size: 0.22).with {
                    $0.duration = 0.3; $0.stretch = 2; $0.dir = .backward; $0.speed = 2.5; $0.tintEnd = .primary
                }, .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.petal, .primary, rate: 40, life: 0.6, size: 0.2).with {
                    $0.duration = 0.3; $0.spin = 300; $0.spinVar = 200; $0.angleVar = 180; $0.gravity = 1; $0.speed = 0.8
                }, .follow, offset: [0, 0.8, 0]),
            ]
            r.telegraph = [
                .mesh(.decal(.star, R * 1.6, .secondary, life: 0.3, spin: 200, alpha: 0.5)),
            ]
            r.impact = [
                .emit(.flare(1.5, .core, life: 0.18, tex: .flare4), offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.9, .core, from: 80, to: -100, height: 1.0, tilt: -12, life: 0.2, tex: .slashThin),
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 1.0, .primary, from: 80, to: -100, height: 1.0, tilt: -12, life: 0.32), offset: [0, 0.95, 0]),
                .mesh(.decal(.star, R * 2.3, .secondary, life: 1.0, spin: 40, grow: 1.05, alpha: 0.95), at: 0.03),
                .mesh(.decal(.ringDouble, R * 2.0, .primary, life: 0.8, spin: -60, alpha: 0.7), at: 0.05),
                .mesh(.shockRing(R * 1.3, .accent, life: 0.4), at: 0.04),
                .emit(.sparks(16, speed: 6, .core, end: .secondary), at: 0.03, offset: [0, 0.9, 0]),
                // 散って地に残る花弁（鈍足）
                .emit(.flutter(.petal, 24, radius: R * 0.6, .primary, speed: 2.5, life: 1.4, size: 0.18), at: 0.04,
                      offset: [0, 0.8, 0]),
                .shake(0.18, at: 0.03),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.0, 0]),
                .mesh(.decal(.petal, 1.0, .primary, life: 1.0, spin: 90, alpha: 0.7), .follow),
            ]
        case .skill3:
            // 花の蕾を放る（0.14 秒）→ 五弁の花が開き、咲き誇って弾ける
            r.cast = [
                .emit(.flare(0.9, .accent, life: 0.16), at: 0.13, offset: [0.3, 1.4, 0.5]),
                .emit(.flutter(.petal, 8, radius: 0.2, .primary, speed: 3, life: 0.6).with { $0.dir = .forward; $0.spread = 25 },
                      at: 0.13, offset: [0.3, 1.3, 0.5]),
            ]
            r.telegraph = [
                // 地に開く五弁の花
                .mesh(.decal(.petal, R * 1.0, .primary, life: 0.65, spin: 0, grow: 1.0, alpha: 0.75))
                    .ringed(5, radius: R * 0.42, every: 0.04),
                .mesh(.decal(.star, R * 0.9, .secondary, life: 0.65, spin: 120, alpha: 0.8)),
                .mesh(.decal(.ring, R * 2.1, .accent, life: 0.65, spin: 0, grow: 1.0, alpha: 0.6)),
            ]
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.2, tex: .flare4), offset: [0, 1.0, 0]),
                .mesh(.decal(.petal, R * 1.3, .primary, life: 0.8, spin: 30, grow: 1.1, alpha: 0.9))
                    .ringed(5, radius: R * 0.55),
                .mesh(.decal(.star, R * 1.6, .secondary, life: 1.0, spin: -80, grow: 1.1, alpha: 0.95)),
                .mesh(.shockRing(R * 1.4, .primary, life: 0.4)),
                .emit(.vortex(26, radius: R * 0.8, .primary, life: 1.0, tex: .petal, speed: 3.5).with { $0.size = 0.2 }),
                .emit(.flutter(.star, 10, radius: R * 0.6, .secondary, speed: 3.5, life: 0.9, size: 0.2), offset: [0, 0.8, 0]),
                .emit(.sparks(16, speed: 7, .core, end: .primary), offset: [0, 0.6, 0]),
                .shake(0.18),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.0, 0]),
                .emit(starCrown, .follow, offset: [0, 2.05, 0]),
            ]
        case .ultimate:
            // 花星満開: 花弁となって消え（転移元）→ 標的の背後で交差斬り（0.15 秒）と大輪の満開（0.45 秒）
            r.cast = [
                .emit(.flutter(.petal, 30, radius: 0.5, .primary, speed: 3.5, life: 1.0), offset: [0, 1.0, 0]),
                .emit(.flare(1.2, .accent, life: 0.2), offset: [0, 1.0, 0]),
                .mesh(.decal(.star, 1.8, .secondary, life: 0.6, spin: 200, alpha: 0.75)),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.18, tex: .flare4), at: 0.14, offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.8, .core, from: 70, to: -50, height: 1.0, tilt: 38, life: 0.2, tex: .slashThin), at: 0.14,
                      offset: [0, 1.05, 0]),
                .mesh(.slash(R * 0.8, .core, from: -70, to: 50, height: 1.0, tilt: -38, life: 0.2, tex: .slashThin),
                      at: 0.16, offset: [0, 1.05, 0]),
                .mesh(.slash(R * 0.9, .primary, from: 70, to: -50, height: 1.0, tilt: 38, life: 0.32), at: 0.14,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.9, .primary, from: -70, to: 50, height: 1.0, tilt: -38, life: 0.32), at: 0.16,
                      offset: [0, 1.0, 0]),
                // 八弁の大輪が咲く
                .mesh(.decal(.petal, R * 1.4, .primary, life: 1.4, spin: 20, grow: 1.15, alpha: 0.9), at: 0.2)
                    .ringed(8, radius: R * 0.6, every: 0.02),
                .mesh(.decal(.star, R * 1.7, .secondary, life: 1.5, spin: -50, grow: 1.1, alpha: 0.95), at: 0.4),
                .mesh(.decal(.ringDouble, R * 2.8, .accent, life: 1.3, spin: 40, alpha: 0.7), at: 0.42),
                .mesh(.shockRing(R * 1.6, .core, life: 0.4), at: 0.45),
                .mesh(.shockRing(R * 2.2, .primary, life: 0.6), at: 0.5),
                .mesh(.sprite(.star, 1.6, .secondary, life: 0.35, grow: 1.6), at: 0.45, offset: [0, 1.3, 0]),
                .emit(.flare(2.2, .core, life: 0.24, tex: .flare6), at: 0.45, offset: [0, 1.0, 0]),
                // 花嵐（吹き飛ばし）
                .emit(.flutter(.petal, 50, radius: R * 0.4, .primary, speed: R * 3.5, life: 1.3, size: 0.22).with {
                    $0.dir = .outward; $0.gravity = 0.6
                }, at: 0.45, offset: [0, 0.8, 0]),
                .emit(.vortex(24, radius: R * 0.7, .secondary, life: 1.1, tex: .star, speed: 4).with { $0.size = 0.18 },
                      at: 0.45),
                .emit(.sparks(24, speed: 9, .core, end: .primary), at: 0.45, offset: [0, 0.8, 0]),
                .emit(.rising(20, radius: R, .accent, speed: 3, life: 1.1), at: 0.5, quality: 1),
                .shake(0.25, at: 0.15),
                .shake(0.6, at: 0.45),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
                .emit(.flutter(.petal, 10, radius: 0.3, .primary, speed: 4, life: 0.8), offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 小さく踏み込み、双刃を開いて交差させる
            m.lunge(0.05, distance: 0.25, lean: 0.2)
            m.crossSlash(0.1)
            m.hold(0.14) { $0.glow = 1.4; $0.cape = 0.6 }
        case .skill2:
            // 低く駆け、着地で交差斬り → くるりと一回りして構え直す
            m.dash(0.05, lean: 0.55)
            m.hold(0.06)
            m.crossSlash(0.12)
            m.spin(0.14, turns: 1, arms: false)
            m.key(0.01, .linear) { $0.yaw -= 2 * .pi }
            m.settle(0.08)
        case .skill3:
            // 跳び退きながら花の蕾を放る
            m.backstep(0.06, distance: 0.25)
            m.throwCast(0.08)
            m.hold(0.12) { $0.glow = 1.3 }
            m.settle(0.08)
        case .ultimate:
            // 花弁に溶け（半透明）、背後に現れて交差斬り → 舞うように一回転して大輪を咲かせる斬り下ろし
            m.key(0.03, .snap) { $0.opacity = 0.3 }
            m.key(0.04, .out) { $0.opacity = 1 }
            m.crossSlash(0.08)
            m.spin(0.2, turns: 1)
            m.key(0.01, .linear) { $0.yaw -= 2 * .pi }
            m.uppercut(0.08)
            m.smash(0.06)
            m.hold(0.16) { $0.glow = 2.2; $0.hipsDrop = 0.14 }
        }
    }
}
