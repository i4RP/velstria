import Foundation
import VelstriaCore

// スキル演出: H003 月弓のフィリエル（Ranger / 三日月の弓・矢筒）。
// 主題: 月光の矢。銀白の芯 × 青緑の月光（主）× 淡い藤色の月（差し色）。静かで鋭く、夜空のきらめきを残す。
//   パッシブ 月影の刻印    — 会心の矢で、頭上に三日月が灯り足元に月の輪が刻まれる
//   S1 フィリエル式・一閃   — 引き絞った月光の矢。尾に光の羽を引き、命中で三日月の紋が咲く
//   S2 星環シフト           — 月の影に溶けて跳び、転移先に霜のような月の輪が広がる（鈍足）。次の矢が光る
//   S3 境界制圧             — 天へ放った矢が月となって落ち、月光の柱が地を穿つ（気絶 = 星の冠）
//   奥義 月光断界            — 全身で引く大弓。三日月の大矢が一直線に夜を断ち、命中で月の大紋章が爆ぜる（吹き飛ばし）

enum FX_H003: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.93, 0.98, 1.0), primary: RGB(0.4, 0.86, 1.0),
                                   secondary: RGB(0.72, 0.9, 1.0), accent: RGB(0.82, 0.74, 1.0),
                                   dark: RGB(0.04, 0.07, 0.14))

    /// 弓を構えた左手の先（局所座標）。
    private static let bow: SIMD3<Float> = [-0.1, 1.35, 0.6]

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.sprite(.moon, 0.7, .accent, life: 0.6, grow: 1.3, alpha: 0.95), .follow, offset: [0, 2.3, 0]),
                .emit(.flare(1.0, .core, life: 0.2, tex: .flare4), .follow, offset: [0, 2.3, 0]),
                .mesh(.decal(.ringDouble, 1.8, .primary, life: 0.7, spin: 120, alpha: 0.75), .follow),
                .emit(.motes(10, radius: 0.5, .secondary, life: 0.8), .follow, offset: [0, 1.2, 0]),
            ]
            r.hit = []
        case .skill1:
            // 引き絞り 0.10 秒 → 放つ 0.15 秒
            r.cast = [
                .emit(.gather(12, radius: 0.5, .primary, life: 0.14), offset: bow),
                .emit(.flare(1.1, .core, life: 0.15, tex: .flare4), at: 0.14, offset: bow),
                .mesh(.sprite(.moon, 0.6, .accent, life: 0.25, grow: 1.6, alpha: 0.9), at: 0.14, offset: bow),
                .emit(.fan(10, .secondary, speed: 8, spread: 12, life: 0.25), at: 0.14, offset: bow),
            ]
            r.travel = [
                .emit(.trail(.streak, .primary, rate: 70, life: 0.22, size: 0.5).with {
                    $0.stretch = 3; $0.dir = .backward; $0.speed = 2
                }, .follow, offset: [0, 1.15, 0]),
                .emit(.trail(.glowHard, .core, rate: 60, life: 0.12, size: 0.32), .follow, offset: [0, 1.15, 0]),
                .emit(.trail(.twinkle, .accent, rate: 30, life: 0.6, size: 0.12).with { $0.dir = .up; $0.speed = 0.5 },
                      .follow, offset: [0, 1.15, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.5, .core, life: 0.18, tex: .flare6), offset: [0, 1.1, 0]),
                .mesh(.sprite(.moon, 1.1, .accent, life: 0.35, grow: 1.5), offset: [0, 1.2, 0]),
                .mesh(.decal(.moon, R * 2.2, .primary, life: 0.6, spin: 60, alpha: 0.8)),
                .emit(.sparks(16, speed: 6, .core, end: .primary), offset: [0, 1.1, 0]),
                .emit(.wave(R * 1.2, .secondary, life: 0.4), offset: [0, 0.1, 0]),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.1, 0]),
                .emit(.sparks(8, speed: 5, .secondary, end: .primary), offset: [0, 1.1, 0]),
            ]
        case .skill2:
            r.cast = [
                .emit(.bloom(1.4, .accent, life: 0.35), offset: [0, 1.0, 0]),
                .mesh(.sprite(.moon, 1.0, .accent, life: 0.4, grow: 0.5, alpha: 0.9), offset: [0, 1.1, 0]),
                .emit(.rising(18, radius: 0.5, .primary, speed: 2.6, life: 0.6)),
                .emit(.flutter(.twinkle, 14, radius: 0.5, .secondary, speed: 2, life: 0.7, size: 0.12), offset: [0, 1.0, 0]),
            ]
            r.impact = [
                .emit(.flare(1.3, .core, life: 0.18), at: 0.04, offset: [0, 1.0, 0]),
                .mesh(.decal(.ringDouble, 3.2, .secondary, life: 0.9, spin: -70, grow: 1.1, alpha: 0.85), at: 0.04),
                .mesh(.decal(.moon, 2.0, .accent, life: 0.8, spin: 90, alpha: 0.8), at: 0.04),
                .mesh(.shockRing(2.0, .primary, life: 0.45), at: 0.04),
                .emit(.motes(16, radius: 1.2, .secondary, life: 1.0, rise: 0.4), at: 0.06, offset: [0, 0.3, 0], quality: 1),
                // 次の矢が光る（弓の月光）
                .emit(.trail(.glowHard, .primary, rate: 24, life: 0.3, size: 0.25).with { $0.duration = 1.2 }, .follow,
                      offset: [-0.1, 1.35, 0.4]),
            ]
        case .skill3:
            // 天へ放った矢が月になって落ちる
            r.cast = [
                .emit(.flare(1.0, .core, life: 0.16), at: 0.13, offset: [0, 2.0, 0.3]),
                .emit(.trail(.streak, .primary, rate: 60, life: 0.25, size: 0.4).with {
                    $0.duration = 0.3; $0.dir = .up; $0.speed = 14; $0.stretch = 3
                }, at: 0.13, offset: [0, 1.6, 0.3]),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.1, .primary, life: 0.6, spin: 90, alpha: 0.6)),
                .mesh(.decal(.moon, R * 1.4, .accent, life: 0.6, spin: -120, alpha: 0.7)),
                .mesh(.sprite(.moon, 1.4, .accent, life: 0.5, grow: 0.6, alpha: 0.9).with { $0.rise = -6 }, offset: [0, 4, 0]),
            ]
            r.impact = [
                .emit(.flare(2.0, .core, life: 0.22, tex: .flare6), offset: [0, 0.8, 0]),
                .mesh(.pillar(R * 0.45, height: 6, .core, life: 0.45)),
                .mesh(.pillar(R * 0.8, height: 4.5, .primary, life: 0.65, alpha: 0.55)),
                .mesh(.shockRing(R * 1.1, .secondary)),
                .mesh(.decal(.moon, R * 2.4, .primary, life: 0.9, spin: 40, alpha: 0.85)),
                .emit(.sparks(20, speed: 6, .core, end: .primary, gravity: 3), offset: [0, 0.5, 0]),
                // 気絶の星の冠
                .mesh(.halo(0.5, .accent, life: 0.9, spin: 300, tex: .ringDouble), at: 0.1, offset: [0, 2.0, 0]),
                .emit(.motes(14, radius: R * 0.7, .accent, life: 1.0), at: 0.1, offset: [0, 0.5, 0], quality: 1),
                .shake(0.15),
            ]
        case .ultimate:
            r.cast = [
                .emit(.gather(30, radius: 1.6, .primary, life: 0.3), offset: bow),
                // 背後の高い位置に満月を掲げる（上方カメラで体を覆わないよう、小さめ・後ろ・半透明）
                .mesh(.sprite(.moon, 1.5, .accent, life: 0.55, grow: 1.15, alpha: 0.7), offset: [0, 2.7, -1.5]),
                .mesh(.decal(.runeCircle, 3.2, .primary, life: 0.8, spin: 140, alpha: 0.75)),
                .emit(.flare(2.4, .core, life: 0.25, tex: .flare6), at: 0.3, offset: bow),
                .emit(.fan(24, .secondary, speed: 12, spread: 14, life: 0.35), at: 0.3, offset: bow),
                .mesh(.ray(.streak, length: 7, width: 1.4, .primary, life: 0.3, alpha: 0.85), at: 0.3, offset: [0, 0.05, 4]),
                .shake(0.3, at: 0.3),
            ]
            r.travel = [
                .mesh(.ray(.arrow, length: 3.2, width: 1.5, .core, life: 1.1, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.1, -0.8]),
                .emit(.trail(.glow, .primary, rate: 90, life: 0.35, size: 1.0), .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.moon, .accent, rate: 22, life: 0.6, size: 0.45).with { $0.spin = 200; $0.dir = .up; $0.speed = 0.6 },
                      .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.streak, .secondary, rate: 80, life: 0.3, size: 0.4).with {
                    $0.shape = .sphere(0.6); $0.stretch = 3; $0.dir = .backward; $0.speed = 4
                }, .follow, offset: [0, 1.1, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(3.0, .core, life: 0.28, tex: .flare6), offset: [0, 1.1, 0]),
                .mesh(.sprite(.moon, 2.6, .accent, life: 0.5, grow: 1.4), offset: [0, 1.4, 0]),
                .mesh(.decal(.runeCircle, R * 3.2, .primary, life: 1.3, spin: 60, alpha: 0.9)),
                .mesh(.decal(.moon, R * 2.6, .accent, life: 1.1, spin: -90, alpha: 0.85)),
                .mesh(.shockRing(R * 2.2, .core, life: 0.4)),
                .mesh(.shockRing(R * 3.0, .primary, life: 0.65), at: 0.06),
                .mesh(.slash(2.2, .secondary, from: 80, to: -80, height: 1.2, life: 0.35), offset: [0, 1.2, 0]),
                .emit(.sparks(36, speed: 10, .core, end: .primary, life: 0.45), offset: [0, 1.1, 0]),
                .emit(.fan(26, .secondary, speed: 10, spread: 30, life: 0.4), offset: [0, 1.0, 0]),
                .emit(.motes(20, radius: R, .accent, life: 1.2), at: 0.1, offset: [0, 0.6, 0], quality: 1),
                .shake(0.55),
            ]
            r.hit = [
                .emit(.flare(1.4, .core, life: 0.16), offset: [0, 1.1, 0]),
                .mesh(.sprite(.moon, 0.9, .accent, life: 0.3, grow: 1.5), offset: [0, 1.3, 0]),
                .emit(.fan(10, .primary, speed: 7, spread: 20), offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 素早く引いて放つ（残心で弓を下げない）
            m.draw(0.1)
            m.release(0.05)
            m.hold(0.12)
        case .skill2:
            // 後ろへ跳びながら次の矢をつがえる
            m.backstep(0.12, distance: 0.45)
            m.draw(0.1, up: 0.1)
            m.settle(0.1)
        case .skill3:
            // 天へ向けて引き絞り、真上へ放つ
            m.brace(0.04, depth: 0.06)
            m.draw(0.09, up: 0.9)
            m.release(0.05)
            m.hold(0.16) { $0.headPitch = -0.6 }
        case .ultimate:
            // 腰を落として全身で大弓を引き、溜めて放つ → 反動で半歩下がる
            m.brace(0.08, depth: 0.16)
            m.draw(0.16, up: 0.05)
            m.hold(0.08) { $0.glow = 2.2; $0.ring = 1.2 }
            m.release(0.05)
            m.recoil(0.08, power: 0.7)
            m.settle(0.14)
        }
    }
}
