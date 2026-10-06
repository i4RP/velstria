import Foundation
import VelstriaCore

// スキル演出: H015 戦鐘のヴァルカ（Ranger / 鐘口の大筒、背に戦鐘）。
// 主題: 戦の鐘と大筒。青銅の橙（主）× 金（副）× 緑青（差し色）。撃つたびに鐘の音の輪が広がる、重い砲撃。
//   パッシブ 戦意共鳴       — 会心の一撃で背の戦鐘が鳴り、金の音の輪が身から広がる
//   S1 Valka式・一閃        — 鐘弾を撃つ（直線）。音の輪を連ねて飛び、命中で鐘が鳴り渡って頭上に金の環（気絶）
//   S2 星環シフト           — 足元へ大筒を撃って反動で跳び、着地の衝撃で音の壁が四方へ押し出す（吹き飛ばし）
//   S3 境界制圧             — 鐘弾を高く撃ち上げ、落ちた地点に青銅の鐘の檻が降りて輪が締まる（根止め）
//   奥義 終戦の鐘            — 全身で構えた大筒から巨大な鐘の音の砲撃。音の輪の列が戦場を貫き、全てを鳴らして穿つ

enum FX_H015: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.95, 0.8), primary: RGB(1.0, 0.58, 0.14),
                                   secondary: RGB(1.0, 0.84, 0.32), accent: RGB(0.35, 0.92, 0.78),
                                   dark: RGB(0.2, 0.12, 0.05))

    /// 大筒の銃口（構えた姿勢の右手の先。局所座標）。
    private static let muzzle: SIMD3<Float> = [0.25, 1.25, 0.95]

    /// 前方へ広がる音の輪（進行方向を向いて立つ輪が膨らむ）。
    private static func soundRing(_ size: Float, _ tint: FXTint, life: Float = 0.35, grow: Float = 2.6) -> FXEmit {
        FXEmit(tex: .ring, tint: tint, count: 1, life: life, lifeVar: 0, size: size, sizeVar: 0, grow: grow,
               orient: .facing, fade: .easeFadeOut)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            // 背の戦鐘が鳴る（会心）
            r.cast = [
                .emit(.flare(1.2, .core, life: 0.16), .follow, offset: [0, 1.5, -0.3]),
                .mesh(.halo(0.9, .secondary, life: 0.5, spin: 0, tex: .ringDouble).with {
                    $0.size = [0.4, 1, 0.4]; $0.sizeEnd = [1.4, 1, 1.4]; $0.ease = .out
                }, .follow, offset: [0, 1.3, 0]),
                .mesh(.shockRing(1.4, .primary, life: 0.4, tex: .ring), .follow),
                .emit(.wave(1.9, .secondary, life: 0.5, tex: .ripple), .follow, offset: [0, 0.05, 0]),
                .emit(.sparks(10, speed: 5, .core, end: .primary), .follow, offset: muzzle),
            ]
            r.hit = []
        case .skill1:
            // 構え → 発射（0.12 秒の反動に合わせる）
            r.cast = [
                .emit(.flare(1.3, .core, life: 0.14, tex: .flare6), at: 0.11, offset: muzzle),
                .emit(soundRing(0.6, .secondary, life: 0.3, grow: 3), at: 0.11, offset: muzzle + [0, 0, 0.3]),
                .emit(.fan(16, .primary, speed: 9, spread: 22, life: 0.25), at: 0.11, offset: muzzle),
                .emit(.smoke(6, radius: 0.2, life: 0.8, size: 0.5).with { $0.dir = .forward; $0.speed = 2.5; $0.spread = 30 },
                      at: 0.12, offset: muzzle, quality: 1),
            ]
            r.travel = [
                .emit(.trail(.glowHard, .core, rate: 110, life: 0.1, size: 0.5), .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.glow, .primary, rate: 70, life: 0.3, size: 0.5), .follow, offset: [0, 1.1, 0]),
                // 弾が引く音の輪
                .emit(.trail(.ring, .secondary, rate: 16, life: 0.35, size: 0.45).with {
                    $0.orient = .facing; $0.grow = 2.6; $0.fade = .easeFadeOut; $0.tintEnd = .primary
                }, .follow, offset: [0, 1.1, 0]),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.18, tex: .flare6), offset: [0, 1.0, 0]),
                .mesh(.shockRing(R * 2.4, .secondary, life: 0.45, tex: .ringDouble)),
                .mesh(.shockRing(R * 3.0, .primary, life: 0.6, tex: .ring), at: 0.08),
                .mesh(.decal(.ripple, R * 3.0, .primary, life: 0.7, spin: 0, grow: 1.15, alpha: 0.75)),
                .emit(.sparks(16, speed: 6, .core, end: .primary), offset: [0, 1.0, 0]),
                .shake(0.15),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
                // 気絶: 頭上で鳴り続ける金の環
                .mesh(.halo(0.45, .secondary, life: 0.9, spin: 380, tex: .ringDouble), .follow, offset: [0, 2.05, 0]),
                .mesh(.halo(0.32, .accent, life: 0.8, spin: -300, tex: .ring), .follow, offset: [0, 2.2, 0]),
            ]
        case .skill2:
            // 足元へ撃って反動で跳ぶ（転移元）→ 着地の衝撃で音の壁が四方へ
            r.cast = [
                .emit(.flare(1.6, .core, life: 0.16, tex: .flare6), offset: [0, 0.3, 0.3]),
                .mesh(.decal(.crack, 2.2, .dark, life: 1.0, spin: 0, grow: 1.0, alpha: 0.75)),
                .emit(.wave(1.8, .primary, life: 0.4)),
                .emit(.smoke(10, radius: 0.5, life: 1.1, size: 0.8)),
                .emit(.sparks(14, speed: 6, .core, end: .primary, gravity: 9), offset: [0, 0.2, 0]),
            ]
            r.impact = [
                .emit(.flare(1.7, .core, life: 0.18), at: 0.12, offset: [0, 0.6, 0]),
                .mesh(.shockRing(R * 1.3, .primary, life: 0.4), at: 0.12),
                .mesh(.decal(.ripple, R * 2.2, .secondary, life: 0.8, spin: 0, grow: 1.1, alpha: 0.8), at: 0.12),
                // 四方へ押し出す音の壁（吹き飛ばし）
                .mesh(FXMesh(shape: .disc, tex: .soundWave, tint: .secondary, alpha: 0.95, size: [1.3, 1, 1.3],
                             sizeEnd: [2.2, 1, 2.2], ease: .out, life: 0.45, fadeIn: 0.05, fadeOut: 0.4, yaw: 90,
                             advance: R * 2.4), at: 0.12).ringed(4, radius: R * 0.35),
                .emit(.wave(R * 1.6, .accent, life: 0.5, tex: .ring), at: 0.14, offset: [0, 0.05, 0]),
                .emit(.debris(8, speed: 5), at: 0.12, quality: 1),
                .emit(.smoke(8, radius: R * 0.5, life: 1.0, size: 0.8), at: 0.12, quality: 1),
                .shake(0.2, at: 0.12),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.0, 0]),
                .emit(.fan(12, .secondary, speed: 7, spread: 20, life: 0.3), offset: [0, 0.8, 0]),
            ]
        case .skill3:
            // 鐘弾を撃ち上げる（0.14 秒）→ 落下点に鐘の檻
            r.cast = [
                .emit(.flare(1.3, .core, life: 0.16, tex: .flare6), at: 0.13, offset: [0.2, 1.8, 0.6]),
                .emit(.fan(12, .primary, speed: 9, spread: 15, life: 0.3).with { $0.dir = .local([0, 1, 0.6]) }, at: 0.13,
                      offset: [0.2, 1.8, 0.6]),
                .emit(.smoke(6, radius: 0.3, life: 0.9, size: 0.6), at: 0.14, offset: [0.2, 1.4, 0.5], quality: 1),
            ]
            r.telegraph = [
                .mesh(.decal(.ringDouble, R * 2.2, .primary, life: 0.6, spin: 120, grow: 1.0, alpha: 0.7)),
                .mesh(.decal(.ripple, R * 1.8, .secondary, life: 0.6, spin: 0, grow: 0.8, alpha: 0.5)),
                // 落ちてくる鐘弾
                .emit(.flare(0.8, .secondary, life: 0.55).with {
                    $0.dir = .down; $0.speed = 7; $0.speedVar = 0; $0.grow = 1.2; $0.fade = .quickFadeInOut
                }, offset: [0, 4, 0]),
            ]
            r.impact = [
                .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), offset: [0, 1.0, 0]),
                // 青銅の鐘が降りる（縦長の半球）
                .mesh(.dome(R, .primary, life: 0.75, tex: .beam, alpha: 0.6).with {
                    $0.size = [R * 1.2, R * 2.2, R * 1.2]; $0.sizeEnd = [R * 0.95, R * 1.5, R * 0.95]; $0.spin = 0
                }),
                .mesh(.shockRing(R * 1.4, .secondary, life: 0.4, tex: .ringDouble)),
                .mesh(.decal(.ringDouble, R * 2.4, .primary, life: 1.2, spin: -40, alpha: 0.85)),
                // 根止め: 青銅の輪が締まる
                .mesh(.halo(R, .secondary, life: 1.0, spin: 160, tex: .ringDouble).with {
                    $0.size = [R * 1.1, 1, R * 1.1]; $0.sizeEnd = [R * 0.55, 1, R * 0.55]; $0.ease = .inOut
                }, at: 0.1, offset: [0, 0.3, 0]),
                .mesh(.halo(R * 0.8, .accent, life: 0.9, spin: -200, tex: .ring).with {
                    $0.size = [R * 0.9, 1, R * 0.9]; $0.sizeEnd = [R * 0.45, 1, R * 0.45]; $0.ease = .inOut
                }, at: 0.14, offset: [0, 0.8, 0]),
                .emit(.wave(R * 1.8, .primary, life: 0.55, tex: .ring), offset: [0, 0.05, 0]),
                .emit(.sparks(20, speed: 7, .core, end: .primary), offset: [0, 0.6, 0]),
                .emit(.debris(8, speed: 5), quality: 1),
                .shake(0.2),
            ]
            r.hit = [
                .mesh(.halo(0.6, .secondary, life: 1.0, spin: 300, tex: .ringDouble).with {
                    $0.size = [1.0, 1, 1.0]; $0.sizeEnd = [0.5, 1, 0.5]
                }, .follow, offset: [0, 0.25, 0]),
                .emit(.sparks(8, speed: 4, .core, end: .secondary), offset: [0, 0.8, 0]),
            ]
        case .ultimate:
            // 終戦の鐘: 0.14 秒の発射。巨大な音の輪の列が貫く
            r.cast = [
                .emit(.gather(18, radius: 1.2, .secondary, life: 0.12), offset: muzzle),
                .emit(.flare(2.4, .core, life: 0.22, tex: .flare6), at: 0.13, offset: muzzle),
                .mesh(.ray(.beam, length: 9, width: R * 1.6, .primary, life: 0.4, alpha: 0.65),
                      at: 0.13, offset: [0, 1.1, 5.0]),
                .mesh(.ray(.streak, length: 9, width: R * 0.7, .core, life: 0.25), at: 0.13, offset: [0, 1.15, 5.0]),
                // 銃口から立て続けに出る音の輪
                .mesh(.wall(.ring, width: 1.6, height: 1.6, .secondary, life: 0.4, alpha: 0.9).with {
                    $0.size = [0.8, 0.8, 1]; $0.sizeEnd = [2.6, 2.6, 1]; $0.ease = .out; $0.advance = 10
                }, at: 0.13, offset: [0, 0, 0.9]).repeated(4, every: 0.06),
                .mesh(.shockRing(2.2, .primary, life: 0.45), at: 0.13),
                .mesh(.decal(.crack, 2.6, .dark, life: 1.2, spin: 0, grow: 1.0, alpha: 0.7), at: 0.13),
                .emit(.smoke(12, radius: 0.6, life: 1.4, size: 1.0), at: 0.14, quality: 1),
                .emit(.fan(30, .secondary, speed: 14, spread: 18, life: 0.35), at: 0.13, offset: muzzle),
                .shake(0.55, at: 0.13),
            ]
            r.travel = [
                .emit(.trail(.glowHard, .core, rate: 120, life: 0.12, size: 1.0), .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.ring, .secondary, rate: 24, life: 0.45, size: 1.2).with {
                    $0.orient = .facing; $0.grow = 2.4; $0.fade = .easeFadeOut; $0.tintEnd = .primary
                }, .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.glow, .primary, rate: 80, life: 0.4, size: 1.0), .follow, offset: [0, 1.0, 0]),
            ]
            r.impact = [
                .emit(.flare(2.6, .core, life: 0.22, tex: .flare6), offset: [0, 1.0, 0]),
                .mesh(.shockRing(R * 2.6, .secondary, life: 0.5, tex: .ringDouble)),
                .mesh(.shockRing(R * 3.4, .primary, life: 0.7, tex: .ring), at: 0.08),
                .mesh(.decal(.ripple, R * 3.6, .primary, life: 0.9, spin: 0, grow: 1.2, alpha: 0.8)),
                .mesh(.pillar(R * 0.6, height: 4, .secondary, life: 0.5, alpha: 0.7)),
                .emit(.sparks(26, speed: 9, .core, end: .primary), offset: [0, 1.0, 0]),
                .shake(0.3),
            ]
            r.hit = [
                .emit(.flare(1.3, .core, life: 0.16), offset: [0, 1.0, 0]),
                .mesh(.sprite(.ringDouble, 1.4, .secondary, life: 0.3, grow: 1.8), offset: [0, 1.0, 0]),
                .emit(.fan(12, .primary, speed: 8, spread: 18, life: 0.3), offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 大筒を肩に構え、狙い澄まして一撃（反動で上体が跳ねる）
            m.aim(0.07)
            m.recoil(0.05, power: 1.1)
            m.hold(0.12) { $0.glow = 1.2 }
            m.settle(0.08)
        case .skill2:
            // 足元へ銃口を向け撃ち、反動で跳び上がって着地
            m.aim(0.06, up: -0.9)
            m.recoil(0.05, power: 1.6)
            m.leap(0.12, height: 0.55, forward: 0.2)
            m.land(0.08, depth: 0.2)
            m.settle(0.08)
        case .skill3:
            // 腰を落として大筒を高く向け、撃ち上げる
            m.brace(0.04, depth: 0.12)
            m.aim(0.05, up: 0.9)
            m.recoil(0.05, power: 1.4)
            m.hold(0.16) { $0.glow = 1.3 }
        case .ultimate:
            // 深く踏ん張って構え → 巨大な反動で後ろへ押し戻され、鐘の余韻を背負って立つ
            m.brace(0.04, depth: 0.18)
            m.aim(0.05)
            m.recoil(0.05, power: 2.2)
            m.backstep(0.14, distance: 0.5)
            m.hold(0.22) { $0.glow = 2.2; $0.hipsDrop = 0.12 }
            m.settle(0.12)
        }
    }
}
