import Foundation
import VelstriaCore

// スキル演出: H020 光矢のユナ（Duelist / 光矢の刃 + 光の弓）。
// 主題: 光の矢と刃。金白（芯）× 黄金（主）× 琥珀（地の跡）。軽く・速く・鋭く、光の矢が降り注ぐ。
//   パッシブ 光標        — 足元に光輪と三本の光矢の標が回り、金の光条が立ちのぼる
//   S1 光刃一閃          — 黄金の三日月の横薙ぎ（扇）。刃から光矢の扇が飛び、地に一文字の光が走る（気絶 = 星の冠）
//   S2 星環シフト        — 光の筋となって突進、着地で光矢が地に刺さり、前方へ光矢の衝撃が押し出す（ノックバック）
//   S3 境界制圧          — 天へ一矢、光矢の雨が円陣に降り光の杭と縛りの光輪で地に留める（根止め）
//   奥義 光矢流星         — 左右の大斬り二閃と空からの射ち下ろし。三度の斬撃に合わせ光矢の流星群が降り注ぐ

enum FX_H020: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.98, 0.88), primary: RGB(1.0, 0.76, 0.16),
                                   secondary: RGB(1.0, 0.93, 0.58), accent: RGB(1.0, 0.56, 0.1),
                                   dark: RGB(0.2, 0.13, 0.03))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(.flare(1.3, .core, life: 0.2), .follow, offset: [0, 1.1, 0]),
                .mesh(.halo(0.85, .primary, life: 0.9, spin: 260), .follow, offset: [0, 0.1, 0]),
                .mesh(lance(.arrow, length: 0.8, width: 0.32, .accent, life: 0.85), .follow, offset: [0, 0.12, 0])
                    .ringed(3, radius: 0.72),
                .emit(.rising(18, radius: 0.55, .primary, speed: 3, life: 0.6, size: 0.14, tex: .streak), .follow),
                .emit(.motes(10, radius: 0.6, .secondary, life: 0.9), .follow, offset: [0, 1.0, 0], quality: 1),
            ]
        case .skill1:
            // 横薙ぎ: 振り抜きは 0.12 秒（windup → lunge → slash）
            r.cast = [
                .emit(.gather(10, radius: 0.6, .secondary, life: 0.12), offset: [0.4, 1.3, 0.2]),
            ]
            r.impact = [
                .mesh(.slash(R * 1.0, .primary, from: 80, to: -80, height: 1.0, tilt: -10, life: 0.3), at: 0.1,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.9, .core, from: 80, to: -80, height: 1.0, tilt: -10, life: 0.16), at: 0.1,
                      offset: [0, 1.05, 0]),
                .mesh(.slash(R * 1.15, .accent, from: 65, to: -95, height: 0.9, tilt: -4, life: 0.4, tex: .slashThin),
                      at: 0.12, offset: [0, 0.95, 0], quality: 1),
                .emit(.flare(1.0, .core, life: 0.16), at: 0.1, offset: [0, 1.0, R * 0.4]),
                .emit(.fan(7, .primary, speed: R * 7, spread: 30, life: 0.3, tex: .arrow, size: 0.55).with {
                    $0.stretch = 1.2; $0.sizeVar = 0.1
                }, at: 0.11, offset: [0, 1.0, 0.3]),
                .emit(.fan(22, .primary, speed: R * 5, spread: 40, life: 0.35), at: 0.1, offset: [0, 1.0, 0.4]),
                .mesh(.decal(.slash, R * 2.1, .accent, life: 0.6, spin: 0, grow: 1.05, alpha: 0.85), at: 0.1),
                // 地を走る一文字の光
                .mesh(FXMesh(shape: .disc, tex: .slashLine, tint: .primary, alpha: 0.95, size: [R * 1.2, 1, 0.5],
                             sizeEnd: [R * 2.2, 1, 0.8], ease: .out, life: 0.5, fadeIn: 0.04, fadeOut: 0.4),
                      at: 0.12, offset: [0, 0, R * 0.7]),
                .shake(0.12, at: 0.1),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.15), offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 6, .core, end: .accent), offset: [0, 1.0, 0]),
                // 気絶: 頭上に回る星の冠
                .mesh(.halo(0.4, .primary, life: 0.9, spin: 480), .follow, offset: [0, 2.0, 0]),
                .mesh(.sprite(.star, 0.26, .accent, life: 0.9, grow: 1.0), .follow, offset: [0, 2.08, 0])
                    .ringed(3, radius: 0.32),
            ]
        case .skill2:
            // 光の筋となって突進 → 着地で光矢が刺さり前方へ押し出す
            r.cast = [
                .emit(.flare(1.4, .core), offset: [0, 1.0, 0.4]),
                .emit(.trail(.glow, .primary, rate: 90, life: 0.35, size: 0.55).with { $0.duration = 0.35 }, .follow,
                      offset: [0, 1.0, 0]),
                .emit(.trail(.arrow, .secondary, rate: 26, life: 0.28, size: 0.7).with {
                    $0.duration = 0.35; $0.dir = .backward; $0.speed = 5; $0.stretch = 1.2; $0.tint = .core
                    $0.tintEnd = .primary
                }, .follow, offset: [0, 0.9, 0], quality: 1),
            ]
            r.telegraph = [
                .mesh(.decal(.ringDouble, R * 1.8, .primary, life: 0.3, spin: 220, alpha: 0.7)),
                .mesh(lance(.arrow, length: 1.6, width: 0.6, .accent, life: 0.3, alpha: 0.75), offset: [0, 0, 0.3]),
                .emit(.gather(12, radius: R * 0.8, .secondary, life: 0.25), offset: [0, 0.6, 0]),
            ]
            r.impact = [
                .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), offset: [0, 0.8, 0]),
                .mesh(.slash(R * 0.9, .core, from: -70, to: 70, height: 1.0, tilt: 8, life: 0.2), offset: [0, 1.0, 0]),
                .mesh(.decal(.flare6, R * 2.4, .primary, life: 0.9, spin: 20, grow: 1.05, alpha: 0.9)),
                .mesh(.shockRing(R * 1.2, .accent, life: 0.4)),
                // 押し出す向きの巨大な光矢（ノックバック）
                .mesh(lance(.arrow, length: R * 1.8, width: R * 0.8, .primary, life: 0.45), at: 0.03,
                      offset: [0, 0, R * 0.8]),
                .mesh(.pillar(0.16, height: 3.4, .core, life: 0.5)),
                .emit(.fan(26, .primary, speed: 10, spread: 45, life: 0.35), at: 0.02, offset: [0, 0.8, 0.3]),
                .emit(.debris(6, speed: 4, .accent, size: 0.1, tex: .glowHard), quality: 1),
                .shake(0.25),
            ]
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.15), offset: [0, 1.0, 0]),
                .emit(.fan(10, .accent, speed: 7, spread: 22, life: 0.3), offset: [0, 1.0, 0]),
                .mesh(lance(.arrow, length: 1.3, width: 0.5, .primary, life: 0.35), offset: [0, 0, 0.5]),
            ]
        case .ultimate:
            // 光矢流星: 斬撃 0 / 0.3 / 0.6 秒（impact ×3、回ごとに左右反転）+ 全体に降る流星群（cast）
            r.cast = [
                .mesh(.decal(.ringDouble, R * 3.0, .primary, life: 1.4, spin: 60, alpha: 0.85)),
                .mesh(.decal(.flare6, R * 2.6, .accent, life: 1.3, spin: -25, alpha: 0.8), at: 0.05),
                .mesh(.pillar(0.5, height: 9, .core, life: 0.5, alpha: 0.7), at: 0.5),
                .mesh(.halo(R * 1.2, .secondary, life: 1.0, spin: 300), offset: [0, 0.2, 0]),
                .emit(arrowRain(40, radius: R * 1.7, over: 0.85), at: 0.05, offset: [0, 7, 0]),
                // 締め: 射ち下ろしの着地（0.62 秒）
                .emit(.flare(2.4, .core, life: 0.25, tex: .flare6), at: 0.62, offset: [0, 1.0, 0]),
                .mesh(.shockRing(R * 2.2, .core, life: 0.45), at: 0.62),
                .emit(.wave(R * 2.6, .primary, life: 0.6), at: 0.64, offset: [0, 0.1, 0]),
                .emit(.motes(20, radius: R * 1.2, .secondary, life: 1.2), at: 0.3, offset: [0, 1.0, 0], quality: 1),
                .shake(0.7, at: 0.62),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.18, tex: .flare6), at: 0.05, offset: [0, 1.0, 0.3]),
                .mesh(.slash(R * 1.15, .primary, from: 95, to: -95, height: 1.0, tilt: -12, life: 0.32), at: 0.05,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 1.0, .core, from: 95, to: -95, height: 1.0, tilt: -12, life: 0.18), at: 0.05,
                      offset: [0, 1.05, 0]),
                .mesh(.decal(.slash, R * 2.4, .accent, life: 0.6, spin: 0, grow: 1.05, alpha: 0.85), at: 0.06),
                .mesh(.shockRing(R * 1.3, .accent, life: 0.4), at: 0.07),
                .emit(.fan(9, .primary, speed: 12, spread: 70, life: 0.3, tex: .arrow, size: 0.6).with {
                    $0.stretch = 1.2; $0.sizeVar = 0.1
                }, at: 0.06, offset: [0, 1.0, 0.3]),
                .emit(.sparks(18, speed: 8, .core, end: .primary), at: 0.06, offset: [0, 1.0, 0.4]),
                .shake(0.35, at: 0.05),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.15), offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 6, .core, end: .accent), offset: [0, 1.0, 0]),
                .mesh(.slash(0.8, .primary, from: 40, to: -40, height: 1.0, life: 0.18), offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 刃を肩へ引き、半歩踏み込んで振り抜く（0.12 秒）、残心で刃を流す
            m.windup(0.05, side: 1, power: 1.1)
            m.lunge(0.03, distance: 0.25, lean: 0.2)
            m.slash(0.04, side: 1, power: 1.3)
            m.hold(0.14) { $0.torsoYaw -= 0.12; $0.glow = 1.5 }
            m.settle(0.08)
        case .skill2:
            // 前傾で光の筋になって駆け、着地で逆手に返して斬り払う
            m.dash(0.06, lean: 0.5)
            m.hold(0.12) { $0.cape = 1; $0.glow = 1.3 }
            m.windup(0.04, side: -1, power: 1.0)
            m.slash(0.05, side: -1, power: 1.3)
            m.settle(0.1)
        case .ultimate:
            // 右の大斬り（0.07）→ 左の大斬り（0.29）→ 跳んで射ち下ろし → 着地（0.61）
            m.windup(0.03, side: 1, power: 1.1)
            m.slash(0.04, side: 1, power: 1.2)
            m.windup(0.15, side: -1, power: 1.1)
            m.slash(0.07, side: -1, power: 1.3)
            m.leap(0.12, height: 0.8)
            m.draw(0.07, up: -0.7)
            m.release(0.05)
            m.land(0.08, depth: 0.25)
            m.hold(0.2) { $0.glow = 2.2; $0.ring = 1.2 }
        }
    }

    // MARK: 部品（ユナ用）

    /// 横長の画像（光矢・光条）を前方へ向けて寝かせた帯（中心に置く。長さ length・幅 width）。
    private static func lance(_ tex: FXTex, length: Float, width: Float, _ tint: FXTint, life: Float = 0.35,
                              alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [length * 0.7, 1, width * 0.6],
               sizeEnd: [length, 1, width], ease: .out, life: life, fadeIn: 0.04, fadeOut: 0.4, yaw: 90)
    }

    /// 空から降る光矢の雨（上空の円盤から下へ。矢じりが下を向く）。
    private static func arrowRain(_ count: Int, radius: Float, over: Float) -> FXEmit {
        FXEmit(tex: .arrow, tint: .core, tintEnd: .primary, count: count, emit: over, life: 0.32, lifeVar: 0.1,
               size: 0.9, sizeVar: 0.2, shape: .disc(radius), dir: .down, speed: 20, speedVar: 0.1,
               orient: .upright, angle: -90, fade: .linearFadeOut)
    }
}
