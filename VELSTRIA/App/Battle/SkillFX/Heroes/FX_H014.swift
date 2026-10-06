import Foundation
import VelstriaCore

// スキル演出: H014 霧歩のシオ（Duelist / 霧の太刀 + 小太刀の二刀、霧の外套）。
// 主題: 霧の剣士。青紫の霧（主）× 白刃（芯）× 淡い水色の霧（副）。静かに・鋭く・残像で。
//   パッシブ 薄霧          — 攻撃が速まるたび、足元に霧の渦が巻き、白い斬線の残像が身を掠める
//   S1 Sio式・一閃         — 低い居合から一文字の抜き打ち（扇）。白刃の一線が走り、霧が前方へ流れて足を絡める（鈍足）
//   S2 星環シフト          — 身を霧に溶かして駆け、着地で X の十字斬り。頭上に白刃の冠（気絶）
//   S3 境界制圧            — 唐竹割りで霧を放ち、霧の陣の中を五筋の斬線が同時に走って霧ごと弾き飛ばす（吹き飛ばし）
//   奥義 霧界歩法           — 霧に消えては現れる三連の居合。回るたび霧の斬線が円陣に立ち、斬られた者を霧の輪が縛る（根止め）

enum FX_H014: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.94, 0.96, 1.0), primary: RGB(0.52, 0.45, 1.0),
                                   secondary: RGB(0.55, 0.82, 1.0), accent: RGB(0.82, 0.72, 1.0),
                                   dark: RGB(0.14, 0.12, 0.26))

    /// 霧（淡い青紫のアルファ合成の煙。石畳の上でも青く見える色）。
    private static let mistTint = FXTint.rgb(0.62, 0.64, 0.92)

    /// 霧の塊（煙の部品を淡い霧色へ）。
    private static func mist(_ count: Int, radius: Float, life: Float = 1.0, size: Float = 0.8) -> FXEmit {
        FXEmit.smoke(count, radius: radius, mistTint, life: life, size: size)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.decal(.swirl, 2.0, .primary, life: 0.8, spin: 260, grow: 1.15, alpha: 0.75), .follow),
                .mesh(.halo(0.75, .secondary, life: 0.6, spin: -320, tex: .swirl, alpha: 0.7), .follow,
                      offset: [0, 0.9, 0]),
                .mesh(.wall(.slashLine, width: 1.5, height: 0.35, .core, life: 0.22, alpha: 0.9).with { $0.roll = 28 },
                      .follow, offset: [0, 1.1, 0.25]),
                .emit(.flare(0.8, .accent, life: 0.16), .follow, offset: [0.35, 1.0, 0.3]),
                .emit(mist(6, radius: 0.5, life: 0.8, size: 0.6), .follow, quality: 1),
                .emit(.vortex(14, radius: 0.7, .primary, life: 0.6, speed: 2), .follow),
            ]
            r.hit = []
        case .skill1:
            // 居合: 抜き打ちは 0.10 秒（モーションの slash に合わせる）。一文字の白刃 → 霧が前へ流れる
            r.cast = [
                .emit(.gather(10, radius: 0.6, .secondary, life: 0.1), offset: [-0.3, 0.9, 0.1]),
                .emit(mist(4, radius: 0.3, life: 0.6, size: 0.45), quality: 1),
            ]
            r.impact = [
                // 一文字の斬線（横一線、前方の扇を横切る）
                .mesh(.ray(.slashLine, length: R * 1.5, width: 0.42, .core, life: 0.2).with { $0.yaw = 0 }, at: 0.09,
                      offset: [0, 0.95, R * 0.45]),
                .mesh(.slash(R * 0.95, .core, from: 80, to: -85, height: 1.0, tilt: -5, life: 0.16, tex: .slashThin),
                      at: 0.09, offset: [0, 1.0, 0]),
                .mesh(.slash(R * 1.0, .primary, from: 80, to: -85, height: 1.0, tilt: -5, life: 0.32), at: 0.09,
                      offset: [0, 0.95, 0]),
                .mesh(.slash(R * 1.1, .secondary, from: 70, to: -95, height: 0.8, life: 0.42).with { $0.alpha = 0.5 },
                      at: 0.11, offset: [0, 0.85, 0], quality: 1),
                .mesh(.decal(.slash, R * 2.0, .primary, life: 0.7, spin: 0, grow: 1.05, alpha: 0.8), at: 0.1),
                .emit(.flare(1.0, .core, life: 0.14), at: 0.09, offset: [0, 1.0, R * 0.45]),
                .emit(.fan(26, .secondary, speed: R * 5, spread: 38, life: 0.4), at: 0.1, offset: [0, 0.9, 0.3]),
                // 霧が前へ流れて足を絡める（鈍足）
                .emit(mist(10, radius: 0.6, life: 1.2, size: 0.9).with {
                    $0.dir = .forward; $0.speed = R * 2.2; $0.spread = 40; $0.shape = .sphere(0.4)
                }, at: 0.1, offset: [0, 0.3, 0.4]),
                .emit(.motes(12, radius: R * 0.5, .accent, life: 1.0), at: 0.15, offset: [0, 0.3, R * 0.6], quality: 1),
                .shake(0.1, at: 0.09),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.0, 0]),
                .mesh(.sprite(.slashLine, 1.4, .core, life: 0.18, grow: 1.4), offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 5, .core, end: .secondary), offset: [0, 1.0, 0]),
                .emit(mist(4, radius: 0.3, life: 0.9, size: 0.5), offset: [0, 0.2, 0], quality: 1),
            ]
        case .skill2:
            // 霧渡り: 身が霧に溶けて駆け、着地で X の十字斬り
            r.cast = [
                .emit(mist(10, radius: 0.5, life: 0.9, size: 0.8)),
                .emit(.flare(1.0, .secondary, life: 0.16), offset: [0, 1.0, 0.2]),
                .emit(.trail(.smoke, mistTint, rate: 60, life: 0.5, size: 0.7).with {
                    $0.duration = 0.3; $0.additive = false; $0.grow = 1.8; $0.fade = .gradualFadeInOut
                }, .follow, offset: [0, 0.7, 0]),
                .emit(.trail(.slashLine, .primary, rate: 40, life: 0.22, size: 0.5).with {
                    $0.duration = 0.3; $0.stretch = 2.5; $0.dir = .backward; $0.speed = 2
                }, .follow, offset: [0, 1.0, 0], quality: 1),
            ]
            r.telegraph = [
                .mesh(.decal(.ringDouble, R * 1.8, .secondary, life: 0.3, spin: -200, alpha: 0.55)),
            ]
            r.impact = [
                .emit(.flare(1.5, .core, life: 0.18, tex: .flare4), at: 0.02, offset: [0, 1.0, 0]),
                .mesh(.slash(R * 1.0, .core, from: 60, to: -60, height: 1.0, tilt: 42, life: 0.2, tex: .slashThin),
                      at: 0.02, offset: [0, 1.0, 0]),
                .mesh(.slash(R * 1.0, .core, from: -60, to: 60, height: 1.0, tilt: -42, life: 0.2, tex: .slashThin),
                      at: 0.05, offset: [0, 1.0, 0]),
                .mesh(.slash(R * 1.15, .primary, from: 60, to: -60, height: 1.0, tilt: 42, life: 0.34), at: 0.02,
                      offset: [0, 0.95, 0]),
                .mesh(.slash(R * 1.15, .primary, from: -60, to: 60, height: 1.0, tilt: -42, life: 0.34), at: 0.05,
                      offset: [0, 0.95, 0]),
                .mesh(.decal(.ringDouble, R * 2.2, .primary, life: 0.8, spin: 90, alpha: 0.85), at: 0.04),
                .mesh(.shockRing(R * 1.3, .secondary, life: 0.4), at: 0.05),
                .emit(.sparks(18, speed: 7, .core, end: .accent), at: 0.05, offset: [0, 0.9, 0]),
                .emit(mist(10, radius: R * 0.6, life: 1.1, size: 0.8), at: 0.05, quality: 1),
                .shake(0.2, at: 0.05),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
                // 気絶: 頭上に回る白刃の冠
                .mesh(.halo(0.42, .accent, life: 0.9, spin: 420, tex: .ringDouble), .follow, offset: [0, 2.05, 0]),
                .emit(.flutter(.twinkle, 6, radius: 0.35, .core, speed: 0.5, life: 0.9, size: 0.14).with {
                    $0.gravity = 0; $0.vortex = 6
                }, .follow, offset: [0, 2.05, 0]),
            ]
        case .skill3:
            // 唐竹割り（0.12 秒）で霧を放つ → 霧の陣 → 五筋の斬線が同時に走り、霧ごと外へ弾く
            r.cast = [
                .emit(.flare(1.1, .core, life: 0.16), at: 0.11, offset: [0, 0.8, 0.6]),
                .emit(mist(6, radius: 0.4, life: 0.8, size: 0.6).with { $0.dir = .forward; $0.speed = 3 }, at: 0.11,
                      offset: [0, 0.6, 0.5]),
                .mesh(.slash(1.4, .primary, from: 10, to: -10, height: 1.2, tilt: 85, life: 0.22), at: 0.11,
                      offset: [0, 1.1, 0]),
            ]
            r.telegraph = [
                .mesh(.decal(.swirl, R * 2.3, .primary, life: 0.6, spin: 240, grow: 1.0, alpha: 0.6)),
                .mesh(.decal(.ring, R * 2.1, .secondary, life: 0.6, spin: 0, grow: 1.0, alpha: 0.7)),
                .emit(mist(10, radius: R * 0.8, life: 0.9, size: 0.8).with { $0.speed = 0.3 }),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.18), offset: [0, 0.9, 0]),
                // 五筋の斬線（陣を貫く白刃）
                .mesh(.ray(.slashLine, length: R * 2.4, width: 0.4, .core, life: 0.24)).repeated(5, every: 0.025, yaw: 36),
                .mesh(.ray(.slashLine, length: R * 2.6, width: 0.9, .primary, life: 0.36, alpha: 0.75))
                    .repeated(5, every: 0.025, yaw: 36),
                .mesh(.decal(.slash, R * 2.4, .accent, life: 0.7, spin: 60, alpha: 0.7), at: 0.06),
                .mesh(.shockRing(R * 1.35, .secondary, life: 0.4), at: 0.1),
                // 霧が外へ吹き飛ぶ（吹き飛ばし）
                .emit(mist(14, radius: R * 0.5, life: 1.0, size: 0.9).with { $0.speed = R * 3; $0.drag = 3 }, at: 0.1),
                .emit(.sparks(20, speed: 8, .core, end: .primary, gravity: 2), at: 0.1, offset: [0, 0.6, 0]),
                .shake(0.2, at: 0.1),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.12), offset: [0, 1.0, 0]),
                .mesh(.sprite(.slashLine, 1.3, .core, life: 0.16, grow: 1.3), offset: [0, 1.0, 0]),
                .emit(.fan(10, .secondary, speed: 6, spread: 20, life: 0.3), offset: [0, 0.8, 0]),
            ]
        case .ultimate:
            // 霧界歩法: 霧の結界が開き、0 / 0.3 / 0.6 秒の三連の居合（偶数回は左右反転）
            r.cast = [
                .emit(mist(16, radius: R * 0.5, life: 1.6, size: 1.1)),
                .mesh(.decal(.swirl, R * 2.6, .primary, life: 1.3, spin: 160, grow: 1.1, alpha: 0.7)),
                .mesh(.decal(.ringDouble, R * 2.3, .secondary, life: 1.2, spin: -90, alpha: 0.6)),
                .mesh(.halo(R * 0.85, .accent, life: 1.1, spin: 240, tex: .swirl, alpha: 0.6), offset: [0, 0.5, 0]),
                .emit(.vortex(24, radius: R * 0.8, .secondary, life: 1.0, speed: 2.5), quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.16, tex: .flare4), at: 0.06, offset: [0, 1.0, 0]),
                .mesh(.sweep(R * 0.95, .core, from: 100, to: -260, life: 0.22), at: 0.05, offset: [0, 0.95, 0]),
                .mesh(.sweep(R * 1.05, .primary, from: 100, to: -260, life: 0.38), at: 0.05, offset: [0, 0.85, 0]),
                .mesh(.slash(R * 0.9, .core, from: 80, to: -100, height: 1.0, tilt: -22, life: 0.2), at: 0.07,
                      offset: [0, 1.05, 0]),
                .mesh(.slash(R * 1.0, .primary, from: 80, to: -100, height: 1.0, tilt: -22, life: 0.34), at: 0.07,
                      offset: [0, 1.0, 0]),
                // 円陣に立つ霧の斬線（残像）
                .mesh(.wall(.slashLine, width: 1.8, height: 0.45, .core, life: 0.28, alpha: 0.95).with { $0.roll = 35 })
                    .ringed(4, radius: R * 0.7, every: 0.02),
                .mesh(.decal(.slash, R * 2.3, .primary, life: 0.6, spin: 0, grow: 1.05, alpha: 0.8), at: 0.07),
                .mesh(.shockRing(R * 1.2, .secondary, life: 0.4), at: 0.07),
                .emit(.sparks(24, speed: 8, .core, end: .accent, size: 0.1), at: 0.07, offset: [0, 0.9, 0]),
                .emit(mist(10, radius: R * 0.6, life: 1.0, size: 0.9), at: 0.07, quality: 1),
                .shake(0.45, at: 0.07),
            ]
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.14), offset: [0, 1.0, 0]),
                // 根止め: 霧の輪が足元で締まる
                .mesh(.halo(0.7, .primary, life: 1.2, spin: 300, tex: .ringDouble).with {
                    $0.size = [1.1, 1, 1.1]; $0.sizeEnd = [0.55, 1, 0.55]; $0.ease = .out
                }, .follow, offset: [0, 0.2, 0]),
                .mesh(.halo(0.5, .secondary, life: 1.0, spin: -360, tex: .swirl).with {
                    $0.size = [0.9, 1, 0.9]; $0.sizeEnd = [0.45, 1, 0.45]
                }, .follow, offset: [0, 0.75, 0]),
                .emit(.sparks(10, speed: 5, .core, end: .secondary), offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 低く沈んで鞘に手を掛け（太刀を左腰へ）、一瞬で横一文字に抜き打ち、振り抜いた残心
            m.brace(0.03, depth: 0.14)
            m.key(0.03, .out) { p in
                p.armR = ArmPose(pitch: 0.7, out: -0.15, yaw: 0.95, elbow: 1.3)
                p.weaponR = -0.7
                p.torsoYaw = 0.6
                p.torsoPitch = 0.15
                p.glow = 0.9
            }
            m.slash(0.04, side: 1, power: 1.4)
            m.hold(0.18) { $0.torsoYaw -= 0.12; $0.glow = 1.4 }
        case .skill2:
            // 霧になって駆ける（半透明）→ 実体へ戻りざまに X の十字斬り
            m.dash(0.05, lean: 0.6)
            m.hold(0.06) { $0.opacity = 0.35; $0.cape = 1.2 }
            m.key(0.03, .snap) { $0.opacity = 1 }
            m.crossSlash(0.12)
            m.settle(0.1)
        case .skill3:
            // 太刀を頭上へ、唐竹割りで霧を叩きつける
            m.backstep(0.04, distance: 0.15)
            m.overhead(0.04)
            m.smash(0.04)
            m.hold(0.18) { $0.glow = 1.6; $0.hipsDrop = 0.16 }
            m.settle(0.08)
        case .ultimate:
            // 霧に溶けては現れる三連の居合（0.09 / 0.36 / 0.69 秒）。半回転して反対の手で、最後は十字斬り
            m.windup(0.04, side: 1, power: 1.2)
            m.slash(0.05, side: 1, power: 1.4)
            m.hold(0.1) { $0.opacity = 0.35 }
            m.spin(0.1, turns: 0.5)
            m.key(0.03, .snap) { $0.opacity = 1 }
            m.slash(0.04, side: -1, power: 1.4)
            m.hold(0.1) { $0.opacity = 0.35 }
            m.spin(0.12, turns: -0.5)
            m.key(0.02, .snap) { $0.opacity = 1 }
            m.crossSlash(0.11)
            m.hold(0.18) { $0.glow = 2.2; $0.hipsDrop = 0.16 }
        }
    }
}
