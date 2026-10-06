import Foundation
import VelstriaCore

// スキル演出: H006 月灯のセレン（Assassin / 三日月の短刀・月の灯籠・フードと覆面）。
// 主題: 月灯籠の光と影。灯の白金の芯 × 淡い金（主）× 紫の影（副）。灯りが閃き、影が切り裂く。
//   パッシブ 月影の灯      — 隠れた所からの一撃で、相手の上に灯籠の光が灯り、三日月の傷が走る
//   S1 セレン式・一閃       — 金と紫の二筋の三日月を交差させて斬り払う（吹き飛ばし）
//   S2 星環シフト           — 影となって駆け抜け、着地点に灯籠の光が弾けて影の輪が足を縛る（根止め）
//   S3 境界制圧             — 灯籠を掲げると、地点に五つの灯火が降りて光の円を描く
//   奥義 満月灯界            — 影に消えて対象の背後へ。頭上に満月が昇り、四方からの三日月の連斬で切り刻む（鈍足）

enum FX_H006: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.97, 0.86), primary: RGB(1.0, 0.8, 0.4),
                                   secondary: RGB(0.62, 0.45, 1.0), accent: RGB(1.0, 0.93, 0.66),
                                   dark: RGB(0.08, 0.04, 0.14))

    /// 影の煙（紫がかった暗い煙）。
    private static func shadow(_ n: Int, radius: Float, life: Float = 0.8) -> FXEmit {
        FXEmit.smoke(n, radius: radius, .rgb(0.16, 0.08, 0.26), life: life, size: 0.7)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(.flare(1.3, .accent, life: 0.2, tex: .flare6), .follow, offset: [0, 2.1, 0]),
                .mesh(.sprite(.moon, 0.8, .primary, life: 0.45, grow: 1.4), .follow, offset: [0, 2.1, 0]),
                .mesh(.slash(0.9, .secondary, from: 60, to: -60, height: 1.0, tilt: 35, life: 0.22, tex: .slashThin), .follow,
                      offset: [0, 1.0, 0]),
                .emit(shadow(5, radius: 0.4, life: 0.6), .follow, quality: 1),
            ]
            r.hit = []
        case .skill1:
            r.impact = [
                // 金の三日月（右上 → 左下）と紫の三日月（左上 → 右下）が交差
                .mesh(.slash(R * 0.95, .primary, from: 80, to: -70, height: 1.0, tilt: -30, life: 0.24), at: 0.07,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.9, .secondary, from: -80, to: 70, height: 1.05, tilt: 30, life: 0.26), at: 0.11,
                      offset: [0, 1.05, 0]),
                .mesh(.slash(R * 0.8, .core, from: 80, to: -70, height: 1.0, tilt: -30, life: 0.12, tex: .slashThin), at: 0.07,
                      offset: [0, 1.0, 0]),
                .emit(.flare(1.2, .accent, life: 0.16, tex: .flare6), at: 0.1, offset: [0, 1.0, R * 0.5]),
                .emit(.fan(22, .primary, speed: R * 4.5, spread: 35, life: 0.32), at: 0.1, offset: [0, 1.0, 0.3]),
                .mesh(.decal(.moon, R * 1.6, .secondary, life: 0.5, spin: 0, alpha: 0.75), at: 0.1, offset: [0, 0, R * 0.4]),
                .emit(shadow(6, radius: 0.6, life: 0.7), at: 0.1, offset: [0, 0, R * 0.5], quality: 1),
                .shake(0.1, at: 0.1),
            ]
            r.hit = [
                .mesh(.slash(0.7, .secondary, from: 50, to: -50, height: 1.0, tilt: 40, life: 0.16, tex: .slashThin),
                      offset: [0, 1.0, 0]),
                .emit(.sparks(8, speed: 5, .accent, end: .secondary), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            r.cast = [
                .emit(shadow(8, radius: 0.5, life: 0.7)),
                .emit(.trail(.glow, .secondary, rate: 70, life: 0.3, size: 0.55).with { $0.duration = 0.3 }, .follow,
                      offset: [0, 0.9, 0]),
                .emit(.trail(.smoke, .rgb(0.16, 0.08, 0.26), rate: 30, life: 0.5, size: 0.6).with {
                    $0.duration = 0.3; $0.additive = false; $0.grow = 1.8
                }, .follow, offset: [0, 0.7, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.8, .accent, life: 0.2, tex: .flare6), offset: [0, 1.0, 0]),
                .emit(.bloom(1.6, .primary, life: 0.35), offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.9, .primary, from: 100, to: -100, height: 0.9, life: 0.25), offset: [0, 0.9, 0]),
                .mesh(.decal(.ringDouble, R * 2.2, .secondary, life: 1.0, spin: -150, alpha: 0.8)),
                .mesh(.halo(R * 0.7, .secondary, life: 0.9, spin: 220, tex: .chain), at: 0.05, offset: [0, 0.3, 0]),
                .emit(.sparks(16, speed: 6, .accent, end: .primary)),
                .emit(shadow(6, radius: R * 0.5), quality: 1),
                .shake(0.15),
            ]
        case .skill3:
            r.cast = [
                .emit(.flare(1.2, .accent, life: 0.2), at: 0.12, offset: [-0.3, 2.0, 0.2]),
                .emit(.motes(10, radius: 0.4, .primary, life: 0.6), at: 0.12, offset: [-0.3, 2.0, 0.2]),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.1, .primary, life: 0.6, spin: 80, alpha: 0.6)),
                .mesh(.sprite(.glowHard, 0.7, .accent, life: 0.55, grow: 1.0).with { $0.rise = -5 }, offset: [0, 3.0, R * 0.7])
                    .ringed(5, radius: 0, every: 0.04),
            ]
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.2, tex: .flare6), offset: [0, 0.6, 0]),
                .mesh(.pillar(0.25, height: 3.2, .accent, life: 0.55)).ringed(5, radius: R * 0.7),
                .mesh(.decal(.moon, R * 2.3, .primary, life: 1.0, spin: 45, alpha: 0.85)),
                .mesh(.shockRing(R * 1.2, .secondary)),
                .emit(.wave(R * 1.3, .primary, life: 0.5), offset: [0, 0.1, 0]),
                .emit(.motes(16, radius: R * 0.8, .accent, life: 1.0), at: 0.1, offset: [0, 0.6, 0], quality: 1),
                .shake(0.12),
            ]
        case .ultimate:
            r.cast = [
                .emit(shadow(10, radius: 0.6, life: 0.9)),
                .emit(.flare(1.4, .secondary, life: 0.2)),
                .mesh(.decal(.moon, 2.0, .secondary, life: 0.6, spin: 200, alpha: 0.75)),
            ]
            r.impact = [
                .mesh(.sprite(.moon, 2.4, .accent, life: 1.0, grow: 1.15, alpha: 0.95).with { $0.rise = 0.6 }, offset: [0, 2.6, 0]),
                .emit(.flare(2.6, .core, life: 0.3, tex: .flare6), offset: [0, 2.6, 0]),
                .mesh(.decal(.runeCircle, 5.0, .primary, life: 1.4, spin: 60, alpha: 0.9)),
                .mesh(.decal(.moon, 3.4, .secondary, life: 1.2, spin: -100, alpha: 0.8)),
                // 四方からの三日月の連斬
                .mesh(.slash(1.6, .primary, from: 60, to: -60, height: 1.0, tilt: 25, life: 0.2)).repeated(6, every: 0.08, yaw: 110),
                .mesh(.slash(1.4, .secondary, from: 60, to: -60, height: 1.1, tilt: -25, life: 0.22, tex: .slashThin), at: 0.04)
                    .repeated(6, every: 0.08, yaw: 110),
                .emit(.sparks(12, speed: 6, .accent, end: .primary), offset: [0, 1.0, 0]).repeated(4, every: 0.12),
                .mesh(.shockRing(3.0, .accent, life: 0.5), at: 0.5),
                .emit(.flare(2.0, .accent, life: 0.24, tex: .flare6), at: 0.5, offset: [0, 1.0, 0]),
                .emit(shadow(10, radius: 1.2, life: 1.1), at: 0.45, quality: 1),
                .emit(.motes(20, radius: 2.0, .secondary, life: 1.2), at: 0.5, offset: [0, 0.5, 0], quality: 1),
                .shake(0.3, at: 0.1),
                .shake(0.5, at: 0.5),
            ]
            r.hit = [
                .emit(.flare(1.1, .accent, life: 0.14), offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 6, .core, end: .secondary), offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 両刃を開いて交差させ、半歩踏み込む
            m.crossSlash(0.12)
            m.lunge(0.05, distance: 0.25, lean: 0.2)
            m.hold(0.12)
        case .skill2:
            // 前傾で駆け抜け、着地で逆手に斬り下ろす
            m.dash(0.06, lean: 0.6)
            m.hold(0.1)
            m.crossSlash(0.1)
            m.settle(0.1)
        case .skill3:
            // 灯籠（左手）を高く掲げる
            m.key(0.12, .out) { p in
                p.armL = ArmPose(pitch: 2.8, out: 0.35, yaw: 0, elbow: 0.2)
                p.armR = ArmPose(pitch: 0.4, out: 0.5, yaw: 0, elbow: 0.9)
                p.headPitch = -0.35
                p.torsoPitch = -0.15
                p.glow = 1.6
                p.ring = 0.8
            }
            m.hold(0.24) { $0.glow = 2.0 }
        case .ultimate:
            // 影に沈み → 背後で回転斬り → 締めの交差斬り
            m.brace(0.05, depth: 0.2)
            m.spin(0.24, turns: 1.5)
            m.crossSlash(0.12)
            m.spin(0.18, turns: -1)
            m.lunge(0.06, distance: 0.3)
            m.settle(0.1)
        }
    }
}
