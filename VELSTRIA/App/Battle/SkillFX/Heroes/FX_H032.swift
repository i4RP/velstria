import Foundation
import VelstriaCore

// スキル演出: H032 赤拳のディアス（Duelist / 刃付きの籠手（拳剣）・赤い気・包帯の腕。MLBB の Dyrroth の Velstria 版）。
// 主題: 奈落の紫炎と紅のレイジ。桃白の芯 × 奈落の紫（主。MLBB のスキルの紫）× 紅（副。モデルの赤い気 = レイジ）×
// 燠の橙（差し色。籠手の輪の光）× 黒紫（暗。アルファ合成の煙・亡霊の影）。
// 上から見下ろすカメラで「腕に巻く紅の輪（レイジ）」「扇へ飛ぶ回転刃の衝撃 3 連」「亡霊の影を引く突進と、飛びかかる致命の一撃」
// 「溜めてから前へ 3 本の爪で裂く長い直線」が読めるよう、全周の輪を主役にせず、回転刃・爪痕・突進の影・直線の裂け目で形を見せる。
// sim の実際の挙動（Systems/Kits/Kit_H032.swift の Tune）に合わせたタイミング:
//   パッシブ 紅血の拳        — cast: レイジが 50・100 に届いた瞬間（バッジの段が増えたとき）: 両腕に回る紅の輪・足元の紫炎・燠。
//                              passiveRelease: アビス強化を放ってバッジの段が 1 → 0 に戻った瞬間（スキルの発動の直後）: 足元の紫の渦が
//                              拳へ吸い込まれ、紫炎が前へ噴く（スキル1 の 5 連・スキル2 の強化された致命の一撃に重なる）。
//                              円撃（通常攻撃 2 回に 1 回）は専用のイベントが無いので通常攻撃の演出（Effekseer）のまま
//   スキル1 赤拳連斬（扇）     — 扇のアーキタイプなので発動と同時に cast と impact。0.1 / 0.24 / 0.38 秒（burstFirstDelay + 0.14 × n）に、
//                              紫の回転刃が前へ飛び（advance）、右→左→右の斬線と紫の筋が扇へ吹く。足元に爪痕。被弾は 1 発ごと
//                              （hitPerHit）に小さな火花と鈍足の紅の輪。アビス強化（5 連・射程 400）はレシピが共通なので 3 連の演出のまま
//                              （passiveRelease の紫炎が重なる）
//   スキル2 紅蓮の踏込        — 1 回目（stage 0、dashStrike: impact は再生されない）: 紫の閃光から、紫の筋・紫炎・黒紫の亡霊の煙を引いて
//                              突進（≈ 0.17 秒）、通り道に爪痕 2 つ、終点（照準 = 着地点）に回転刃と斬線（cast の .target、0.12 秒）。
//                              被弾（最初に当たった敵、到着の瞬間）: 押し出す火花。
//                              2 回目（stage 1 = 致命の一撃、targetedBlink: impact は発動時に対象の位置）: 紅の閃光と尾を引いて飛びかかり、
//                              対象に紅の照準の輪が縮む。被弾（到着の瞬間）: 紫と紅の十字の斬撃・砕ける燠色の鎧（防御ダウン）・
//                              足元の紫のひび（防御ダウン 4 秒）。段の演出は recipe(_:stage:_:)
//   アルティメット 奈落の一撃  — 直線（piercingLine）だが投射物もゾーンも作らない（Kit.hitAreaEach）ので、全部を cast に置く。
//                              0〜0.5 秒の溜め: 足元の黒と紫の渦が縮み、紫炎が立ちのぼり、両腕の紅の輪が回り、前方の直線（6.5m）が
//                              薄く光る。0.5 秒: 前へ 3 本の爪の光条（射程いっぱい）・前へ走る紫の三日月（advance）・地面の爪痕・
//                              線に沿って舞う紫の光と破片と黒煙・終端の裂け目と火花。被弾（0.5 秒）: 対象を裂く斬線・紫炎・鈍足の紅の輪

enum FX_H032: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.9, 0.96), primary: RGB(0.62, 0.2, 1.0),
                                   secondary: RGB(1.0, 0.18, 0.22), accent: RGB(1.0, 0.55, 0.22),
                                   dark: RGB(0.07, 0.0, 0.1))

    /// 右の拳（局所座標）。
    private static let fist: SIMD3<Float> = [0.35, 1.0, 0.5]

    // MARK: - sim の時刻・寸法（Kit_H032.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 1 発目の遅れと間隔（通常版）。
    private static let burstFirst: Float = 0.1
    private static let burstInterval: Float = 0.14
    /// スキル2: 突進の所要の目安（400 / 2400 ≈ 0.17 秒、致命の一撃は最長 500 / 2600 ≈ 0.19 秒）。
    private static let dashTime: Float = 0.17
    /// アルティメット: 溜め・射程（直線の長さ）・半幅。
    private static let ultCharge: Float = 0.5
    private static let ultReach: Float = 6.5
    private static let ultHalfWidth: Float = 1.4

    // MARK: - 部品

    /// 回転しながら前へ飛ぶ奈落の刃（渦巻きの板。speed m/s で前へ進む）。
    private static func chakram(_ size: Float, _ tint: FXTint, life: Float, speed: Float, spin: Float,
                                alpha: Float = 0.95) -> FXMesh {
        FXMesh(shape: .disc, tex: .swirl, tint: tint, alpha: alpha, size: [size * 0.6, 1, size * 0.6], sizeEnd: [size, 1, size],
               ease: .out, life: life, fadeIn: 0.05, fadeOut: 0.5, spin: spin, advance: speed)
    }

    /// 縮んで対象を捕らえる照準の輪（直径 d0 → d1）。
    private static func lockOn(from d0: Float, to d1: Float, _ tint: FXTint, life: Float) -> FXMesh {
        FXMesh(shape: .disc, tex: .ringDouble, tint: tint, alpha: 0.9, size: [d0, 1, d0], sizeEnd: [d1, 1, d1], ease: .in,
               life: life, fadeIn: 0.1, fadeOut: 0.7, spin: -360)
    }

    /// 中心へ縮む渦（溜め・吸い込み）。直径 d0 → d1。
    private static func drawIn(from d0: Float, to d1: Float, _ tint: FXTint, life: Float, spin: Float, alpha: Float) -> FXMesh {
        FXMesh(shape: .disc, tex: .swirl, tint: tint, alpha: alpha, size: [d0, 1, d0], sizeEnd: [d1, 1, d1], ease: .in,
               life: life, fadeIn: 0.2, fadeOut: 0.85, spin: spin)
    }

    /// 立ちのぼる紫炎（立てた炎の板）。
    private static func abyssFlame(_ count: Int, shape: FXEmitShape, speed: Float, life: Float, size: Float,
                                   emit: Float = 0.3, dir: FXEmitDirection = .up, spread: Float = 0) -> FXEmit {
        FXEmit(tex: .flame, tint: .primary, tintEnd: .secondary, count: count, emit: emit, life: life, size: size, sizeVar: 0.4,
               grow: 0.5, shape: shape, surface: true, dir: dir, speed: speed, speedVar: 0.4, spread: spread, drag: 1.0,
               orient: .upright, fade: .gradualFadeInOut)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        switch slot {
        case .passive: return wrathRecipe(s)
        case .skill1: return burstRecipe(s)
        case .skill2: return spectreRecipe(s)
        case .ultimate: return abysmRecipe(s)
        }
    }

    // MARK: - パッシブ 紅血の拳

    /// レイジが 50・100 に届いた瞬間: 両腕に回る紅の輪（MLBB のパッシブの絵）・足元の紫炎・燠。
    private static func wrathRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        r.cast = [
            .mesh(.halo(0.28, .secondary, life: 0.9, spin: 520, tex: .ringDouble), .follow, offset: [0.38, 1.0, 0.25]),
            .mesh(.halo(0.28, .secondary, life: 0.9, spin: -520, tex: .ringDouble), .follow, offset: [-0.38, 1.0, 0.25]),
            .mesh(.decal(.crack, 1.8, .primary, life: 0.8, spin: 0, grow: 1.0, alpha: 0.6), .follow),
            .emit(abyssFlame(14, shape: .ring(0.5), speed: 2.0, life: 0.6, size: 0.3, emit: 0.4), .follow, offset: [0, 0.2, 0]),
            .emit(.flare(1.2, .secondary, life: 0.18, tex: .flare6), .follow, offset: [0, 1.6, 0.1]),
            .emit(.embers(10, radius: 0.5, .accent, life: 0.9), .follow),
        ]
        // パッシブのダメージ（円撃）は通常攻撃（Effekseer）。既定の被弾演出で補われないよう小さな合図だけ置く
        r.hit = [.mesh(.halo(0.35, .secondary, life: 0.25, spin: 200, tex: .ring), .follow, offset: [0, 0.2, 0])]
        return r
    }

    /// アビス強化を放った（レイジの段が 1 → 0）瞬間: 足元の紫の渦が拳へ吸い込まれ、紫炎が前へ噴く。released は消費した段の数。
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? {
        [
            .mesh(drawIn(from: 2.4, to: 1.0, .primary, life: 0.4, spin: -720, alpha: 0.75), .follow),
            .emit(.flare(1.6, .core, life: 0.18, tex: .flare6), .follow, offset: fist),
            .emit(abyssFlame(16, shape: .sphere(0.3), speed: 4, life: 0.45, size: 0.32, emit: 0.08, dir: .forward, spread: 40),
                  .follow, offset: [0, 1.0, 0.5]),
            .mesh(.halo(0.6, .secondary, life: 0.4, spin: -500, tex: .ring), .follow, offset: [0, 1.0, 0]),
            .emit(.sparks(10, speed: 6, .core, end: .primary), .follow, offset: [0, 1.0, 0.4]),
        ]
    }

    // MARK: - スキル1 赤拳連斬

    /// 0.1 / 0.24 / 0.38 秒に扇（±37°・3m）へ回転刃と斬線（右→左→右）。
    private static func burstRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 4.0)
        let t0 = burstFirst, dt = burstInterval
        r.cast = [
            .emit(.flare(1.1, .core, life: 0.12, tex: .flare4), at: 0.06, offset: [0.35, 1.0, 0.6]),
        ]
        r.impact = [
            // 回転刃: 前へ飛びながら回る紫の渦の刃（3 発）
            .mesh(chakram(R * 0.8, .primary, life: 0.26, speed: R * 2.6, spin: 1100), at: t0, offset: [0, 0.6, 0.6])
                .repeated(3, every: dt),
            // 斬線: 右→左（1・3 発目）、左→右（2 発目）。外の紫 + 芯の白
            .mesh(.slash(R * 0.9, .primary, from: 75, to: -75, height: 1.0, tilt: -12, life: 0.22), at: t0,
                  offset: [0, 1.0, 0]).repeated(2, every: 2 * dt),
            .mesh(.slash(R * 0.85, .secondary, from: -75, to: 75, height: 1.05, tilt: 14, life: 0.22), at: t0 + dt,
                  offset: [0, 1.05, 0]),
            .mesh(.slash(R * 0.8, .core, from: 70, to: -70, height: 1.0, tilt: -8, life: 0.16, tex: .slashThin), at: t0,
                  offset: [0, 1.02, 0]).repeated(3, every: dt),
            // 扇へ吹く紫の筋（3 発）
            .emit(.fan(12, .primary, speed: R * 4, spread: 32, life: 0.3), at: t0, offset: [0, 0.9, 0.4]).repeated(3, every: dt),
            // 足元の爪痕と、最後の衝撃の火花
            .mesh(.decal(.claw, R * 1.3, .primary, life: 0.9, spin: 0, grow: 1.0, alpha: 0.7), at: t0 + 0.01,
                  offset: [0, 0, R * 0.5]),
            .emit(.sparks(12, speed: 7, .core, end: .secondary), at: t0 + 2 * dt + 0.02, offset: [0, 0.9, R * 0.7]),
            .shake(0.12, at: t0),
            .shake(0.16, at: t0 + 2 * dt),
        ]
        // 1 発ごと: 小さな火花と、鈍足（1.5 秒）の紅の輪
        r.hit = [
            .emit(.flare(0.8, .core, life: 0.12), offset: [0, 1.0, 0]),
            .emit(.sparks(6, speed: 5, .primary, end: .secondary), offset: [0, 1.0, 0]),
            .mesh(.halo(0.45, .secondary, life: 0.7, spin: 120, tex: .ring), .follow, offset: [0, 0.15, 0]),
        ]
        r.hitPerHit = true
        return r
    }

    // MARK: - スキル2 紅蓮の踏込

    /// 1 回目: 亡霊の影を引いて突進し、最初の敵の手前で殴って押し出す（照準 = 着地点）。
    private static func spectreRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let t = dashTime
        r.cast = [
            .emit(.flare(1.3, .primary, life: 0.14, tex: .flare6), offset: [0, 1.0, 0.3]),
            // 突進の間（≈ 0.17 秒）: 紫の筋・紫炎・黒紫の亡霊の煙
            .emit(.trail(.streak, .primary, rate: 100, life: 0.3, size: 0.5).with {
                $0.duration = t; $0.stretch = 3; $0.dir = .backward; $0.speed = 4; $0.tintEnd = .secondary
            }, .follow, offset: [0, 1.0, 0]),
            .emit(FXEmit(tex: .flame, tint: .primary, tintEnd: .secondary, rate: 60, duration: t, life: 0.45, size: 0.45,
                         sizeVar: 0.3, grow: 0.5, shape: .sphere(0.3), dir: .up, speed: 1.0, orient: .upright,
                         fade: .gradualFadeInOut), .follow, offset: [0, 0.4, 0]),
            .emit(.trail(.smoke, .dark, rate: 50, life: 0.6, size: 0.8).with {
                $0.duration = t + 0.02; $0.additive = false; $0.grow = 1.8; $0.fade = .gradualFadeInOut; $0.tintEnd = nil
            }, .follow, offset: [0, 0.6, 0], quality: 1),
            // 通り道の爪痕（照準線の 0.3 / 0.75。距離に合わせて並ぶ）
            .mesh(.decal(.claw, 1.1, .primary, life: 0.9, spin: 0, grow: 1.0, alpha: 0.6), at: 0.03, .along(0.3)),
            .mesh(.decal(.claw, 1.1, .secondary, life: 0.9, spin: 0, grow: 1.0, alpha: 0.6), at: 0.09, .along(0.75)),
            // 終点（着地点）: 回転刃と斬線、前へ散る火花
            .mesh(chakram(1.8, .primary, life: 0.3, speed: 0, spin: 900), at: t - 0.05, .target, offset: [0, 0.5, 0.3]),
            .mesh(.slash(1.3, .secondary, from: 70, to: -70, height: 1.0, life: 0.2), at: t - 0.04, .target,
                  offset: [0, 1.0, 0.1]),
            .emit(.flare(1.4, .core, life: 0.16, tex: .flare6), at: t - 0.03, .target, offset: [0, 1.0, 0.4]),
            .emit(.sparks(10, speed: 6, .core, end: .primary).with { $0.dir = .forward; $0.spread = 35 }, at: t - 0.03, .target,
                  offset: [0, 1.0, 0.4]),
        ]
        // 突進（dashStrike）は impact を再生しない（終点の演出は cast の .target）。目視確認の実演（-skillDemo）だけが
        // impact を出すので、既定演出で補われないよう小さな揺れだけ置く
        r.impact = [.shake(0.12)]
        // 最初に当たった敵（到着の瞬間）: 押し出す火花と小さな衝撃
        r.hit = [
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
            .emit(.sparks(10, speed: 6, .core, end: .secondary).with { $0.dir = .forward; $0.spread = 30 }, offset: [0, 1.0, 0]),
            .mesh(.shockRing(0.9, .primary, life: 0.25, tex: .ring)),
            .emit(.smoke(4, radius: 0.3, .dark, life: 0.6, size: 0.6), quality: 1),
        ]
        return r
    }

    /// 2 回目（stage 1 = 致命の一撃）: 敵ヒーローへ飛びかかり、十字に裂いて鎧を砕く（防御ダウン 4 秒）。
    static func recipe(_ slot: SkillSlot, stage: Int, _ s: FXSkillInfo) -> SkillFXRecipe? {
        guard slot == .skill2, stage == 1 else { return nil }
        var r = SkillFXRecipe()
        let t = dashTime + 0.02
        // 紅の閃光と尾を引いて飛びかかる
        r.cast = [
            .emit(.flare(1.4, .secondary, life: 0.14, tex: .flare6), offset: [0, 1.0, 0.3]),
            .emit(.trail(.streak, .secondary, rate: 100, life: 0.3, size: 0.55).with {
                $0.duration = t; $0.stretch = 3; $0.dir = .backward; $0.speed = 4; $0.tintEnd = .primary
            }, .follow, offset: [0, 1.1, 0]),
            .emit(FXEmit(tex: .flame, tint: .secondary, tintEnd: .primary, rate: 60, duration: t, life: 0.4, size: 0.4,
                         sizeVar: 0.3, grow: 0.5, shape: .sphere(0.3), dir: .up, speed: 1.0, orient: .upright,
                         fade: .gradualFadeInOut), .follow, offset: [0, 0.6, 0]),
        ]
        // 発動時に対象の位置: 紅の照準の輪が縮み、爪の印が浮かぶ
        r.impact = [
            .mesh(lockOn(from: 2.2, to: 0.9, .secondary, life: t)),
            .mesh(.decal(.claw, 1.6, .secondary, life: 0.5, spin: 0, grow: 1.0, alpha: 0.8), at: 0.05),
        ]
        // 到着の瞬間（被弾）: 紫と紅の十字の斬撃・砕ける燠色の鎧・足元の紫のひび（防御ダウン 4 秒）
        r.hit = [
            .mesh(.slash(1.2, .primary, from: 60, to: -60, height: 1.1, tilt: -40, life: 0.24), offset: [0, 1.1, -0.8]),
            .mesh(.slash(1.2, .secondary, from: -60, to: 60, height: 1.1, tilt: 40, life: 0.24), at: 0.06,
                  offset: [0, 1.1, -0.8]),
            .emit(.flare(1.6, .core, life: 0.16, tex: .flare6), offset: [0, 1.0, 0]),
            .mesh(.wall(.hexShield, width: 1.2, height: 1.4, .accent, life: 0.3, alpha: 0.7).with {
                $0.ease = .out; $0.sizeEnd = [1.7, 1.7, 1]
            }, offset: [0, 0.3, -0.4]),
            .emit(.flutter(.shard, 10, radius: 0.4, .accent, speed: 3.5, life: 0.7, size: 0.14), offset: [0, 1.0, -0.2]),
            .emit(.sparks(12, speed: 7, .core, end: .primary), offset: [0, 1.0, 0]),
            .mesh(.decal(.crack, 1.5, .primary, life: 3.6, spin: 0, grow: 1.0, alpha: 0.6), .follow),
            .shake(0.22),
        ]
        return r
    }

    // MARK: - アルティメット 奈落の一撃

    /// 0〜0.5 秒の溜め → 0.5 秒に前方の直線（6.5m・半幅 1.4m）を 3 本の爪で裂く。投射物もゾーンも無いので全部 cast。
    private static func abysmRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = min(s.range, ultReach)
        let W = min(s.radius, ultHalfWidth)
        let t = ultCharge
        r.cast = [
            // 溜め: 黒と紫の渦が足元へ縮み、紫炎が立ちのぼり、両腕の紅の輪が回る。前方の直線が薄く光る
            .emit(.gather(24, radius: 1.4, .primary, life: t - 0.08), offset: [0, 1.0, 0.4]),
            .mesh(drawIn(from: 3.2, to: 1.6, .dark, life: t + 0.02, spin: -540, alpha: 0.7), quality: 1),
            .mesh(drawIn(from: 2.8, to: 1.2, .primary, life: t, spin: -720, alpha: 0.6), at: 0.04),
            .emit(abyssFlame(22, shape: .ring(0.7), speed: 2.4, life: 0.5, size: 0.4, emit: t - 0.1), .follow,
                  offset: [0, 0.1, 0]),
            .mesh(.halo(0.32, .secondary, life: t, spin: 720, tex: .ringDouble), .follow, offset: [0.38, 1.0, 0.3]),
            .mesh(.halo(0.32, .secondary, life: t, spin: -720, tex: .ringDouble), .follow, offset: [-0.38, 1.0, 0.3]),
            .mesh(.ray(.streak, length: L, width: W * 1.9, .primary, life: t, alpha: 0.35).with {
                $0.fadeIn = 0.4; $0.fadeOut = 0.9
            }, offset: [0, 0.02, L / 2]),
            // 0.5 秒: 前へ 3 本の爪の光条（外の紫 + 芯の桃白）
            .mesh(.ray(.streak, length: L, width: 1.2, .primary, life: 0.4, alpha: 0.9), at: t, offset: [-0.5, 0.12, L / 2])
                .repeated(3, every: 0.02, step: [0.5, 0, 0]),
            .mesh(.ray(.streak, length: L, width: 0.5, .core, life: 0.26), at: t, offset: [-0.5, 0.15, L / 2], quality: 1)
                .repeated(3, every: 0.02, step: [0.5, 0, 0]),
            // 前へ走る紫の三日月（約 5.5m）
            .mesh(FXMesh(shape: .disc, tex: .slash, tint: .primary, alpha: 1, size: [W * 1.9, 1, W * 1.9],
                         sizeEnd: [W * 2.3, 1, W * 2.3], ease: .out, life: 0.42, fadeIn: 0.03, fadeOut: 0.6,
                         advance: (L - 1.0) / 0.42), at: t, offset: [0, 0.9, 0.2]),
            .mesh(FXMesh(shape: .disc, tex: .slashThin, tint: .core, alpha: 1, size: [W * 1.7, 1, W * 1.7],
                         sizeEnd: [W * 2.0, 1, W * 2.0], ease: .out, life: 0.3, fadeIn: 0.03, fadeOut: 0.5,
                         advance: (L - 1.0) / 0.42), at: t + 0.02, offset: [0, 0.95, 0.2], quality: 1),
            // 地面の爪痕（3 本の裂け目が直線いっぱいに）と、黒い焦げ
            .mesh(FXMesh(shape: .disc, tex: .claw, tint: .primary, alpha: 0.85, size: [W * 1.6, 1, L * 0.6],
                         sizeEnd: [W * 2.0, 1, L], ease: .out, life: 1.2, fadeIn: 0.03, fadeOut: 0.6), at: t,
                  offset: [0, 0, L / 2]),
            .mesh(FXMesh(shape: .disc, tex: .claw, tint: .dark, alpha: 0.6, size: [W * 1.8, 1, L],
                         sizeEnd: [W * 1.9, 1, L], ease: .out, life: 1.4, fadeIn: 0.05, fadeOut: 0.6), at: t + 0.02,
                  offset: [0, 0, L / 2], quality: 1),
            .emit(.flare(2.4, .core, life: 0.2, tex: .flare6), at: t, offset: [0, 1.0, 0.8]),
            .emit(.lineBurst(L, count: 26, .primary, life: 0.55, size: 0.3), at: t + 0.02, offset: [0, 0.2, L / 2]),
            .emit(.debris(16, speed: 6, .dark, size: 0.16).with { $0.shape = .box([W * 1.2, 0.1, L]) }, at: t + 0.02,
                  offset: [0, 0.1, L / 2]),
            .emit(.smoke(12, radius: 0.8, .dark, life: 1.0, size: 1.0).with { $0.shape = .box([W * 1.3, 0.2, L]) },
                  at: t + 0.05, offset: [0, 0.2, L / 2], quality: 1),
            // 終端の裂け目と火花
            .mesh(.decal(.crack, 2.6, .primary, life: 1.2, spin: 0, grow: 1.0, alpha: 0.8), at: t + 0.06,
                  offset: [0, 0, L - 0.4]),
            .emit(.sparks(18, speed: 9, .core, end: .secondary), at: t + 0.08, offset: [0, 0.9, L]),
            .shake(0.45, at: t),
        ]
        // 投射物もゾーンも無いので impact / travel は本番では再生されない（目視確認の実演だけ）。既定演出で補われないよう揺れだけ置く
        r.impact = [.shake(0.2)]
        r.travel = [.shake(0.05)]
        // 0.5 秒の被弾: 対象を裂く斬線・噴き上がる紫炎（失った HP の追撃）・鈍足（0.8 秒）の紅の輪
        r.hit = [
            .mesh(.slash(1.1, .primary, from: 70, to: -70, height: 1.0, tilt: -30, life: 0.24), offset: [0, 1.0, -0.6]),
            .emit(.flare(1.4, .core, life: 0.16, tex: .flare6), offset: [0, 1.0, 0]),
            .emit(abyssFlame(12, shape: .sphere(0.3), speed: 3.5, life: 0.45, size: 0.35, emit: 0.06, spread: 30),
                  offset: [0, 0.6, 0]),
            .mesh(.halo(0.5, .secondary, life: 0.8, spin: 140, tex: .ring), .follow, offset: [0, 0.15, 0]),
        ]
        return r
    }

    // MARK: - 詠唱モーション

    /// スキル2 は 1 回目と 2 回目で同じモーション（モーションは段で分けられない）。
    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 右から薙ぎ（0.1）、返して左から（0.24）、もう一度右から（0.38）。3 連の衝撃に打撃のキーを合わせる
            m.windup(0.06, side: 1, power: 1.0)
            m.slash(0.04, side: 1, power: 1.2)
            m.windup(0.07, side: -1, power: 0.9)
            m.slash(0.07, side: -1, power: 1.1)
            m.windup(0.07, side: 1, power: 0.9)
            m.slash(0.07, side: 1, power: 1.2)
            m.hold(0.1)
        case .skill2:
            // 前傾で駆け（≈ 0.17 秒）、踏み込みざまに拳を突き出す
            m.dash(0.05, lean: 0.6)
            m.lunge(0.08, distance: 0.6, lean: 0.35)
            m.thrust(0.05)
            m.hold(0.08)
            m.settle(0.1)
        case .ultimate:
            // 腰を落として拳に奈落の気を溜め（0.5 秒）、踏み込んで前へ突き出す
            m.brace(0.06, depth: 0.22)
            m.gather(0.12)
            m.hold(0.22) { $0.glow = 2.2; $0.ring = 1.2 }
            m.windup(0.06, side: 1, power: 1.3)
            m.lunge(0.04, distance: 0.5, lean: 0.4)
            m.thrust(0.04)
            m.hold(0.14) { $0.glow = 2.0 }
            m.settle(0.1)
        }
    }
}
