import Foundation
import VelstriaCore

// スキル演出: H033 紅牙のヴァルド（Assassin / 巨大な紅の大剣・蝙蝠の翼風のマント・深紅と黒の鎧。MLBB の Alucard の Velstria 版）。
// 主題: 紅の大剣が大地を割り、血を吸う。白い芯 × 深紅（主）× 鮮血の朱（副）× 青白（差し色。Alucard の光の名残）× 黒に近い暗赤（暗）。
// 上から見下ろすカメラで「跳び込んで地を割る」「大剣が一回転する」「範囲から紅の力を吸い上げる → 前方へ巨大な三日月の衝撃波」
// 「傷から紅の光が術者へ吸われる（吸血）」が読めるよう、円い輪を主役にせず、前へ走る地割れ・回る三日月・内へ縮む輪・流れ込む光で見せる。
// sim の実際の挙動（Systems/Kits/Kit_H033.swift の Tune）に合わせたタイミング:
//   パッシブ 追撃          — スキルを発動するたび（バッジのタイマーが始まるたび）: 大剣に紅の光が走り、足元の輪・立ちのぼる紅の光条
//                            （次の通常攻撃が踏み込みの追撃になる合図。追撃そのものは通常攻撃の演出）
//   スキル1 裂地撃         — 指定地点へ 3.5m を約 0.19 秒（18m/s）で転がり、着いた tick に半径 1.9m を叩く（鈍足 40%・2 秒）。
//                            転がりは impact を再生しない（ゾーンを作らない）ので、着地の叩きつけは cast の .target に 0.19 秒遅れで置く:
//                            縦に振り下ろす弧 → 閃光・二重の地割れ（暗い裂け目 + 紅く光る裂け目）・前方へ走る紅の裂け目・岩片・土煙
//   スキル2 旋回斬         — その場で大剣を回す（即時・半径 2.5m）。白い細い弧と紅の太い三日月が左回りに 1 回転余り掃き、
//                            地面に渦が残る（術者の spin と同じ向き・同じ 0.05〜0.35 秒）
//   奥義 核分裂波          — 1 回目（吸収・即時）: 照準点の半径 3m に紅い月の陣、外から内へ縮む輪、吸い上げた紅の光が照準点から術者へ流れ込み、
//                            術者は紅をまとう（クールダウン半減の 5 秒のうち 3 秒ほど）。1 回目は地点 AoE（impact は再生されない）なので cast に置く。
//                            2 回目（stage 1、6 秒以内）: 前方へ大剣を振り抜く（段の演出 recipe(_:stage:_:)）→ 貫通する衝撃波（9m を約 0.41 秒）。
//                            衝撃波の travel / impact / hit は共通の演出（投射物の visual はスキルの演出 ID = 段 0）: 前へ凸の巨大な紅の三日月と、
//                            後ろに残る地割れの跡
//   吸血（奥義を習得している間 常時）— 傷を負わせた相手から紅の光条が術者の方へ飛ぶ（各スキルの hit）
// SkillFXDirector は duration / count を読まない。

enum FX_H033: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.94, 0.94), primary: RGB(0.9, 0.06, 0.16),
                                   secondary: RGB(1.0, 0.36, 0.42), accent: RGB(0.78, 0.86, 1.0),
                                   dark: RGB(0.12, 0.0, 0.04))

    /// 土煙・岩片（暗い土色のアルファ合成）。
    private static let dust = FXTint.rgb(0.42, 0.34, 0.3)

    // MARK: - sim の時刻・寸法（Kit_H033.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 転がりの所要（s1Range 350 / s1Speed 1800 ≈ 0.19 秒）。
    private static let rollTime: Float = 0.19
    /// 奥義の衝撃波: 長さ 9m・半幅 1.3m・22m/s（≈ 0.41 秒）。
    private static let waveHalfWidth: Float = 1.3
    private static let waveLife: Float = 0.5

    // MARK: - 部品

    /// 舞い散る蝙蝠の羽（暗い紅の羽根）。
    private static func bats(_ n: Int, radius: Float, speed: Float = 3, life: Float = 0.9) -> FXEmit {
        FXEmit.flutter(.feather, n, radius: radius, .primary, speed: speed, life: life, size: 0.2).with {
            $0.tintEnd = .secondary; $0.gravity = 0.4
        }
    }

    /// 吸血: 傷から紅の光条が術者の方へ飛び（hit の前方 = 術者 → 被弾者なので後ろ向き）、届く頃に術者の体が紅く脈打つ
    /// （hit の .along(0) = 被弾した瞬間の術者の位置）。
    private static func drain(_ n: Int, at t: Float = 0.05) -> [FXCue] {
        [
            .emit(FXEmit(tex: .streak, tint: .secondary, tintEnd: .core, count: n, emit: 0.12, life: 0.35, lifeVar: 0.15,
                         size: 0.1, sizeVar: 0.3, grow: 0.6, shape: .sphere(0.3), dir: .backward, speed: 9, speedVar: 0.2,
                         spread: 14, stretch: 2.2, fade: .linearFadeOut), at: t, offset: [0, 1.0, 0]),
            .emit(.bloom(1.0, .primary, life: 0.3, grow: 1.4), at: t + 0.25, .along(0), offset: [0, 1.0, 0]),
        ]
    }

    /// 回る大剣の軌跡（三日月の板を from 度から turn 度ぶん回す。半径 r の弧）。
    private static func spinArc(_ r: Float, _ tint: FXTint, tex: FXTex, from: Float, turn: Float, life: Float) -> FXMesh {
        let d = r * 2.1
        return FXMesh(shape: .disc, tex: tex, tint: tint, alpha: 1, size: [d * 0.9, 1, d * 0.9], sizeEnd: [d, 1, d],
                      ease: .out, life: life, fadeIn: 0.03, fadeOut: 0.45, yaw: from, yawEnd: from + turn)
    }

    /// 外から内へ縮む輪（吸収）。直径 d0 → d1。
    private static func implode(_ d0: Float, to d1: Float, _ tint: FXTint, life: Float, tex: FXTex = .shockwave,
                                spin: Float = 0, alpha: Float = 0.9) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [d0, 1, d0], sizeEnd: [d1, 1, d1], ease: .in,
               life: life, fadeIn: 0.12, fadeOut: 0.8, spin: spin)
    }

    /// 前へ進む衝撃波の三日月（前方が凸。横 w × 奥行き d の板）。
    private static func waveCrescent(_ tex: FXTex, _ tint: FXTint, width w: Float, depth d: Float) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: 1, size: [w, 1, d], sizeEnd: [w * 1.08, 1, d * 1.1], ease: .out,
               life: waveLife, fadeIn: 0.04, fadeOut: 0.85)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        switch slot {
        case .passive:
            // 追撃の準備（スキルの発動のたび）: 大剣に紅の光が走る・足元の輪・立ちのぼる紅の光条
            r.cast = [
                .emit(.flare(1.0, .secondary, life: 0.16, tex: .flare4), .follow, offset: [0.35, 1.2, 0.3]),
                .mesh(.sprite(.slashLine, 1.4, .primary, life: 0.24, grow: 1.3), .follow, offset: [0.3, 1.25, 0.3]),
                .mesh(.halo(0.75, .primary, life: 0.6, spin: 200, tex: .ringDouble, alpha: 0.7), .follow, offset: [0, 0.2, 0]),
                .emit(.rising(10, radius: 0.5, .secondary, speed: 2.2, life: 0.7, size: 0.1, tex: .streak), .follow),
                .emit(bats(5, radius: 0.6, speed: 1.2, life: 0.9), .follow, offset: [0, 1.3, 0], quality: 1),
            ]
            r.hit = []
        case .skill1:
            r = groundsplitterRecipe(s)
        case .skill2:
            r = whirlRecipe(s)
        case .ultimate:
            r = fissionRecipe(s)
        }
        return r
    }

    // MARK: - スキル1 裂地撃

    /// 転がり込み（0〜0.19 秒）→ 着地点で大剣を叩きつけて地を割る。R = 着地の範囲の半径（1.9m）。
    private static func groundsplitterRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 2.4)
        let T = rollTime
        r.cast = [
            // 転がり出し: 蹴った土煙・紅の尾・舞う羽
            .emit(.smoke(6, radius: 0.5, dust, life: 0.7, size: 0.7).with { $0.dir = .backward; $0.speed = 2 },
                  offset: [0, 0.2, 0], quality: 1),
            .emit(.trail(.streak, .primary, rate: 90, life: 0.3, size: 0.5).with {
                $0.duration = T; $0.stretch = 3; $0.dir = .backward; $0.speed = 3; $0.tintEnd = .secondary
            }, .follow, offset: [0, 0.8, 0]),
            .emit(bats(5, radius: 0.5, speed: 2.5, life: 0.7), offset: [0, 0.9, 0], quality: 1),
            // 着地の直前: 頭上から縦に振り下ろす白い弧
            .mesh(.slash(1.4, .core, from: 80, to: -80, tilt: 90, life: 0.2, tex: .slashThin), at: T - 0.04, .target,
                  offset: [0, 1.2, -0.2]),
            // 着地（0.19 秒）: 閃光・暗い地割れ + 紅く光る地割れ・前方へ走る紅の裂け目（白い芯）・範囲の縁の青白い輪
            .emit(.flare(2.2, .core, life: 0.2, tex: .flare6), at: T, .target, offset: [0, 0.6, 0.3]),
            .mesh(.decal(.crack, R * 2.4, .dark, life: 1.6, spin: 0, grow: 1.0, alpha: 0.9), at: T, .target),
            .mesh(.decal(.crack, R * 1.9, .primary, life: 0.9, spin: 0, grow: 1.08, alpha: 0.9), at: T, .target,
                  offset: [0, 0, 0.1]),
            .mesh(.ray(.bolt, length: R * 2.0, width: 0.9, .secondary, life: 0.5), at: T, .target, offset: [0, 0.02, R * 0.55]),
            .mesh(.ray(.bolt, length: R * 1.6, width: 0.4, .core, life: 0.3), at: T + 0.02, .target, offset: [0, 0.03, R * 0.5]),
            .mesh(.shockRing(R * 1.05, .accent, life: 0.35, alpha: 0.8), at: T, .target),
            .emit(.groundGlow(R, .primary, life: 0.5), at: T, .target, offset: [0, 0.05, 0]),
            // 跳ね上がる岩片・上へ噴く火花・広がる土煙
            .emit(.debris(16, speed: 7, dust), at: T, .target, offset: [0, 0.1, 0.3]),
            .emit(.sparks(16, speed: 8, .core, end: .primary, gravity: 9).with { $0.dir = .up; $0.spread = 35 }, at: T,
                  .target, offset: [0, 0.3, 0.2]),
            .emit(.smoke(8, radius: R * 0.6, dust, life: 1.1, size: 0.9), at: T + 0.02, .target, quality: 1),
            .shake(0.3, at: T),
        ]
        // 転がり（leapSlam）は impact・telegraph を再生しない（着地の演出は cast の .target）。目視確認の実演（-skillDemo）だけが
        // 出すので、既定演出で補われないよう小さく置く
        r.telegraph = [.emit(.groundGlow(R * 0.8, .primary, life: 0.3), offset: [0, 0.05, 0])]
        r.impact = [.shake(0.1)]
        // 着地の範囲の敵: 閃光・火花・足元の紅の枷（鈍足 40%・2 秒）・吸血の光条
        r.hit = [
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 5, .secondary, end: .primary), offset: [0, 1.0, 0]),
            .mesh(.halo(0.6, .primary, life: 1.8, spin: 120, tex: .ringDouble, alpha: 0.75), .follow, offset: [0, 0.15, 0]),
        ] + drain(8)
        return r
    }

    // MARK: - スキル2 旋回斬

    /// その場で大剣を 1 回転余り振り回す（左回り。術者の spin と同じ）。R = 範囲の半径（2.5m）。
    private static func whirlRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 3.0)
        r.cast = [
            // 振りかぶった大剣の紅い光と、回転で舞い上がる土煙
            .emit(.flare(1.2, .secondary, life: 0.14, tex: .flare4), offset: [0.4, 1.1, 0.3]),
            .emit(.smoke(8, radius: 0.6, dust, life: 0.8, size: 0.7).with { $0.speed = 3 }, at: 0.1, quality: 1),
        ]
        // 自己中心なので発動と同時に再生される
        r.impact = [
            .emit(.flare(1.8, .core, life: 0.18, tex: .flare6), at: 0.04, offset: [0, 1.0, 0]),
            // 大剣の軌跡: 先に白い細い弧、続いて紅の太い三日月が左回りに掃き、内側の帯が追う
            .mesh(spinArc(R, .core, tex: .slashThin, from: -20, turn: 420, life: 0.3), at: 0.04, offset: [0, 0.95, 0]),
            .mesh(spinArc(R * 0.92, .primary, tex: .slash, from: -60, turn: 400, life: 0.36), at: 0.07, offset: [0, 0.9, 0]),
            .mesh(.sweep(R * 0.85, .secondary, from: -90, to: 300, life: 0.34), at: 0.1, offset: [0, 0.6, 0]),
            // 地面に残る渦（3 本の腕が回りながら広がる）と、えぐれた地面
            .mesh(FXMesh(shape: .disc, tex: .swirl, tint: .primary, alpha: 0.8, size: [R * 1.2, 1, R * 1.2],
                         sizeEnd: [R * 2.1, 1, R * 2.1], ease: .out, life: 0.55, fadeIn: 0.05, fadeOut: 0.4, spin: 600), at: 0.06),
            .mesh(.decal(.crack, R * 1.3, .dark, life: 1.0, spin: 0, grow: 1.0, alpha: 0.7), at: 0.08),
            // 届く範囲の縁（細い青白い輪。主役にしない）
            .mesh(.shockRing(R, .accent, life: 0.3, tex: .ring, alpha: 0.6), at: 0.12),
            // 回転で外へ飛び散る火花と羽
            .emit(.sparks(20, speed: 9, .core, end: .primary, gravity: 3).with { $0.shape = .ring(R * 0.5); $0.surface = true },
                  at: 0.08, offset: [0, 0.9, 0]),
            .emit(bats(8, radius: R * 0.4, speed: 4, life: 0.7), at: 0.1, offset: [0, 1.0, 0], quality: 1),
            .shake(0.25, at: 0.06),
        ]
        // 斬られた敵: 細い斬撃・血の火花・吸血の光条
        r.hit = [
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
            .mesh(.sprite(.slashThin, 1.2, .secondary, life: 0.16, grow: 1.2), offset: [0, 1.0, 0]),
            .emit(.sparks(10, speed: 6, .secondary, end: .primary), offset: [0, 1.0, 0]),
        ] + drain(8)
        return r
    }

    // MARK: - 奥義 核分裂波

    /// 1 回目（吸収）の cast と、衝撃波（2 回目の投射物）の travel / impact / hit。R = 吸収の半径（3m）。
    private static func fissionRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 3.5)
        r.cast = [
            // 大剣を掲げた先の紅い閃き
            .emit(.flare(1.6, .secondary, life: 0.2, tex: .flare6), offset: [0.3, 2.2, 0.2]),
            // 照準点: 紅い月の陣と三日月の紋（吸収の範囲）
            .mesh(.decal(.runeCircle, R * 2, .primary, life: 1.0, spin: -60, grow: 1.0, alpha: 0.6), .target),
            .mesh(.decal(.moon, R * 1.3, .secondary, life: 0.9, spin: 120, alpha: 0.6), at: 0.05, .target),
            // 外から内へ縮む輪 2 つ（逆巻く渦）と、中心へ吸い込まれる紅の光
            .mesh(implode(R * 2.1, to: 0.8, .primary, life: 0.45), at: 0.05, .target),
            .mesh(implode(R * 1.8, to: 0.6, .secondary, life: 0.42, tex: .swirl, spin: -520, alpha: 0.7), at: 0.12, .target),
            .emit(.gather(28, radius: R * 0.9, .secondary, life: 0.45), at: 0.05, .target, offset: [0, 0.8, 0]),
            // 吸い上げた紅の光が照準点から術者へ流れ込む
            .emit(FXEmit(tex: .streak, tint: .secondary, tintEnd: .core, count: 26, emit: 0.35, life: 0.45, lifeVar: 0.1,
                         size: 0.12, sizeVar: 0.4, grow: 0.6, shape: .sphere(0.6), dir: .backward, speed: 10, speedVar: 0.15,
                         spread: 10, stretch: 2.4, fade: .linearFadeOut), at: 0.15, .target, offset: [0, 1.0, 0]),
            // 術者: 紅をまとう（クールダウン半減の間）。頭上の血の月・膨らむ紅・足元の輪・立ちのぼる残り火
            .mesh(.sprite(.moon, 1.4, .primary, life: 1.2, grow: 1.2, alpha: 0.9), at: 0.3, .follow, offset: [0, 2.6, 0]),
            .emit(.bloom(1.8, .primary, life: 0.4), at: 0.35, .follow, offset: [0, 1.0, 0]),
            .mesh(.halo(0.9, .primary, life: 3.0, spin: 90, tex: .ringDouble, alpha: 0.6).with { $0.fadeOut = 0.75 }, at: 0.35,
                  .follow, offset: [0, 0.2, 0]),
            .emit(.trail(.glowHard, .secondary, rate: 14, life: 0.8, size: 0.08).with {
                $0.duration = 3.0; $0.shape = .disc(0.5); $0.dir = .up; $0.speed = 1.2; $0.tintEnd = .primary; $0.noise = 1
            }, at: 0.35, .follow),
            .shake(0.25, at: 0.05),
        ]
        // 目視確認の実演（-skillDemo）だけが出す予告（地点 AoE の既定演出で補わない）
        r.telegraph = [.mesh(.decal(.moon, R * 1.2, .primary, life: 0.5, spin: 60, alpha: 0.5))]
        // 衝撃波（投射物に追従。前方 = 進行方向）: 前へ凸の巨大な紅の三日月・白い芯・明るい前縁の帯・後ろに残る地割れの跡
        let w = waveHalfWidth * 2.3
        r.travel = [
            .mesh(FXMesh(shape: .arc, tex: .beam, tint: .secondary, alpha: 0.95, size: [waveHalfWidth * 1.3, 1, 1.1],
                         sizeEnd: [waveHalfWidth * 1.3, 1, 1.25], ease: .out, life: waveLife, fadeIn: 0.04, fadeOut: 0.85),
                  .follow, offset: [0, 0.5, 0]),
            .mesh(waveCrescent(.slash, .primary, width: w, depth: w * 0.66), .follow, offset: [0, 0.8, -0.3]),
            .mesh(waveCrescent(.slashThin, .core, width: w * 0.92, depth: w * 0.6), .follow, offset: [0, 0.85, -0.2]),
            .emit(.trail(.glow, .primary, rate: 90, life: 0.35, size: 0.9).with { $0.shape = .box([2.2, 0.2, 0.3]) }, .follow,
                  offset: [0, 0.8, 0]),
            .emit(.trail(.crack, .dark, rate: 24, life: 0.9, size: 1.3).with {
                $0.additive = false; $0.orient = .ground; $0.grow = 1.0; $0.angleVar = 180; $0.tintEnd = nil
                $0.fade = .gradualFadeInOut; $0.speed = 0
            }, .follow, offset: [0, 0.05, -0.4]),
            .emit(.trail(.streak, .core, rate: 60, life: 0.25, size: 0.3).with {
                $0.shape = .box([2.4, 0.3, 0.2]); $0.stretch = 3; $0.dir = .backward; $0.speed = 5; $0.tintEnd = .primary
            }, .follow, offset: [0, 0.8, 0], quality: 1),
        ]
        // 衝撃波が最初の敵に当たった点: 交差する紅の斬撃・地割れ・輪
        r.impact = [
            .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), offset: [0, 1.0, 0]),
            .mesh(.slash(1.6, .core, from: 80, to: -80, tilt: 35, life: 0.22, tex: .slashThin), offset: [0, 1.1, 0]),
            .mesh(.slash(1.7, .primary, from: -80, to: 80, tilt: -35, life: 0.3), at: 0.04, offset: [0, 1.1, 0]),
            .mesh(.decal(.crack, 2.4, .dark, life: 1.0, spin: 0, grow: 1.0, alpha: 0.75)),
            .mesh(.shockRing(1.6, .secondary, life: 0.35)),
            .emit(.sparks(16, speed: 8, .secondary, end: .primary), offset: [0, 1.0, 0]),
            .shake(0.35),
        ]
        // 衝撃波に貫かれた敵（吸収そのものはダメージ 0 なので hit を出さない）: 閃光・斬撃・血の火花・吸血の光条
        r.hit = [
            .emit(.flare(1.1, .core, life: 0.14), offset: [0, 1.0, 0]),
            .mesh(.sprite(.slash, 1.3, .primary, life: 0.18, grow: 1.2), offset: [0, 1.0, 0]),
            .emit(.sparks(10, speed: 6, .secondary, end: .primary), offset: [0, 1.0, 0]),
        ] + drain(10)
        return r
    }

    /// 奥義の 2 回目（stage 1）: 前方へ大剣を振り抜いて衝撃波を放つ（衝撃波そのものは共通の travel）。
    static func recipe(_ slot: SkillSlot, stage: Int, _ s: FXSkillInfo) -> SkillFXRecipe? {
        guard slot == .ultimate, stage == 1 else { return nil }
        var r = SkillFXRecipe()
        r.cast = [
            .emit(.flare(2.2, .core, life: 0.18, tex: .flare6), offset: [0, 1.1, 0.6]),
            // 振り抜きの前方の三日月（白い芯 + 紅）と、足元から前へ割れる地面
            .mesh(.slash(2.4, .core, from: 80, to: -80, life: 0.22, tex: .slashThin), offset: [0, 1.0, 0.3]),
            .mesh(.slash(2.6, .primary, from: 85, to: -85, life: 0.3), at: 0.02, offset: [0, 0.95, 0.2]),
            .mesh(.decal(.crack, 2.6, .dark, life: 1.2, spin: 0, grow: 1.0, alpha: 0.8), offset: [0, 0, 0.8]),
            .mesh(.ray(.bolt, length: 3.2, width: 1.0, .secondary, life: 0.45), at: 0.03, offset: [0, 0.02, 1.8]),
            // 前へ噴く紅の光条・土煙・羽
            .emit(.fan(20, .secondary, speed: 11, spread: 30, life: 0.35), offset: [0, 1.0, 0.4]),
            .emit(.smoke(8, radius: 0.6, dust, life: 0.9, size: 0.8).with { $0.dir = .forward; $0.speed = 4 },
                  offset: [0, 0.2, 0.5], quality: 1),
            .emit(bats(10, radius: 0.6, speed: 4, life: 0.8), offset: [0, 1.0, 0.6], quality: 1),
            .shake(0.35),
        ]
        return r
    }

    // MARK: - 詠唱モーション

    /// 奥義は 2 回とも同じモーション（モーションは段で分けられない）: すぐに前へ振り抜き（衝撃波は発動の瞬間に出る）、
    /// そのまま大剣を掲げて力を吸い上げる。
    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 低く転がり出して跳び、頭上から大剣を叩きつける（着地 0.19 秒）
            m.dash(0.05, lean: 0.6)
            m.leap(0.08, height: 0.45, forward: 0.2)
            m.overhead(0.04)
            m.smash(0.04)
            m.land(0.06, depth: 0.24)
            m.hold(0.1) { $0.glow = 1.8 }
        case .skill2:
            // 大剣を振りかぶり、その場で左回りに一回転
            m.windup(0.05, side: 1, power: 1.2)
            m.spin(0.3, turns: 1)
            m.hold(0.05)
            m.settle(0.1)
        case .ultimate:
            m.brace(0.04, depth: 0.12)
            m.slash(0.06, side: 1, power: 1.3)
            m.hold(0.1) { $0.glow = 1.8 }
            m.raise(0.14, glow: 2.0)
            m.hold(0.12) { $0.ring = 1.2 }
            m.settle(0.1)
        }
    }
}
