import Foundation
import VelstriaCore

// スキル演出: H025 月弦のルミナ（Ranger / 三日月の長弓・月光の矢・翠と白の外套。MLBB の Miya の Velstria 版）。
// 主題: 月光の矢。白い芯 × 翠緑（主）× 月光の銀青（副）× 淡い月の黄（差し色）。円い光の床ではなく、
// 「分かれて飛ぶ矢」「天から落ちて地に刺さる矢」「二つの三日月が噛み合う月蝕の印」「月光の帳」で形を見せる。
// sim の実際の挙動（Systems/Kits/Kit_H025.swift の LuminaTuning）に合わせたタイミング:
//   パッシブ 月環の導き   — 通常攻撃の命中で段が積もるたび（0.4 秒に 1 回まで・5 段まで。隠れ月光が解けて最大の段になる瞬間も）:
//                           頭上に小さな三日月が灯り、弓の先がきらめき、足元を細い月の輪が一巡する（攻撃のたびなので小さく短く）
//   スキル1 月弦分矢      — 自己強化 4 秒（自身中心なので cast と impact を発動と同時に再生）。0.1 秒で弦を離すと、
//                           主矢（中央・2 枚重ねで明るい）と左右 16° の副矢が弓から前へ飛んで分かれ、通り道に翠の筋が残る。
//                           効果中は足元を三日月が巡り、弓の先に月のきらめきが流れ続ける（4 秒）
//   スキル2 月蝕の矢      — 0.1 秒で天へ矢を放つ（cast）。着弾点（ゾーンの telegraph = 発動と同時）に月の印が浮かび、
//                           0.03〜0.35 秒に月光の矢の雨と主矢が真上から落ち、0.35 秒（s2Delay）に着弾: 地に刺さった主矢・月光の柱・
//                           噛み合う二つの三日月（月蝕）・暗い影・砕ける結晶。移動不能 1.2 秒の敵は足元を月の輪と三日月の枷が締める（hit）。
//                           着弾と同時に 6 本の小さな矢（本物の投射物）が ±30° / ±90° / ±150° へ散る = travel が各矢に付く。
//                           impact は「ゾーンの発動」と「小さな矢 6 本それぞれの終わり（命中・射程の端）」の計 7 回再生されるので、
//                           着弾の本体は telegraph（at = 0.35）に置き、impact は小さな閃きだけにする
//   アルティメット 隠れ月光 — 腰を落とした瞬間、月光の帳（光の円柱）が降りて姿を包み、霞・翠の木の葉・小さな三日月が舞い散る。
//                           隠密 2 秒のあいだの位置を敵に見せないよう、演出は発動の位置に置き、追従するのは走り出す 0.3 秒の尾だけ
// SkillFXDirector は duration / count を読まない: 時刻は at（遅れ）で表す。

enum FX_H025: HeroFXSet {
    // 造形（銀白の髪・青紫の衣装・水色に光る弦）と MLBB の Miya の既定スキンの月光に合わせ、月光の青を主色にする。
    static let palette = FXPalette(core: RGB(0.96, 0.99, 1.0), primary: RGB(0.42, 0.76, 1.0),
                                   secondary: RGB(0.82, 0.92, 1.0), accent: RGB(0.62, 0.95, 1.0),
                                   dark: RGB(0.02, 0.05, 0.14))

    // MARK: - sim の時刻・寸法（Kit_H025.LuminaTuning と同じ値。sim を変えたらここも合わせる）

    /// スキル1 の効果時間（s1Duration）。
    private static let buffTime: Float = 4
    /// スキル2: 着弾までの遅れ（s2Delay）・半径（s2Radius 170）・移動不能（s2Root）。
    private static let eclipseDelay: Float = 0.35
    private static let eclipseRadius: Float = 1.7
    private static let rootTime: Float = 1.2
    /// 小さな矢が射程の端（420）へ着くまで（速度 1800）。
    private static let minorArrowTime: Float = 0.23

    /// 弓を構えた左手の先（局所座標）。
    private static let bow: SIMD3<Float> = [-0.1, 1.35, 0.6]
    /// 天へ向けて引いた弓の先（スキル2）。
    private static let bowHigh: SIMD3<Float> = [-0.1, 1.85, 0.45]
    /// 副矢が分かれる角度（度）。
    private static let split: Float = 16

    // MARK: - 部品

    /// 縦に立つ矢（円盤を横倒しにした板。up なら矢じりが上、そうでなければ下）。中心が原点。
    /// repeated(2, yaw: 90) で直交する 2 枚にすると、どの向きから見ても読める。
    private static func uprightArrow(length: Float, width: Float, _ tint: FXTint, life: Float, up: Bool,
                                     alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .disc, tex: .arrow, tint: tint, alpha: alpha, size: [length, 1, width],
               sizeEnd: [length, 1, width], ease: .linear, life: life, fadeIn: 0.05, fadeOut: 0.75, yaw: 45,
               roll: up ? 90 : -90)
    }

    /// 前へ飛ぶ水平の光の矢（前を向いたまま speed m/s で進む。repeated の yaw で向きを分ける）。
    private static func flyingArrow(length: Float, width: Float, _ tint: FXTint, speed: Float, life: Float) -> FXMesh {
        FXMesh(shape: .disc, tex: .arrow, tint: tint, alpha: 1, size: [length * 0.7, 1, width],
               sizeEnd: [length, 1, width * 0.8], ease: .out, life: life, fadeIn: 0.02, fadeOut: 0.6, yaw: 90,
               advance: speed)
    }

    /// 矢の通り道に残る光の筋（pivot から angle 度（+ = 左）の向きへ length m）。
    private static func afterimage(_ angle: Float, length: Float, width: Float, _ tint: FXTint, at t: Float,
                                   from pivot: SIMD3<Float>, life: Float = 0.32) -> FXCue {
        let a = angle * .pi / 180
        let d = length / 2
        let mid = pivot + SIMD3<Float>(-sin(a) * d, 0, cos(a) * d)
        let m = FXMesh.ray(.streak, length: length, width: width, tint, life: life).with { $0.yaw = 90 + angle }
        return .mesh(m, at: t, offset: mid)
    }

    /// 小さな光（スキルのダメージが出ない段を既定の演出で補わせないための詰め物）。
    private static func glint(_ tint: FXTint) -> [FXCue] {
        [.emit(.flare(0.6, tint, life: 0.12), offset: [0, 1.0, 0])]
    }

    // MARK: - レシピ

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        switch slot {
        case .passive:
            var r = SkillFXRecipe()
            // 段が積もるたび: 頭上の小さな三日月・弓の先のきらめき・足元を一巡する細い月の輪・昇る月の粒
            r.cast = [
                .mesh(.sprite(.moon, 0.42, .accent, life: 0.45, grow: 1.35, alpha: 0.95), .follow, offset: [0, 2.25, 0]),
                .emit(.flare(0.7, .core, life: 0.14, tex: .flare4), .follow, offset: bow),
                .mesh(.halo(0.75, .primary, life: 0.45, spin: 260, tex: .ring, alpha: 0.75), .follow, offset: [0, 0.12, 0]),
                .emit(.motes(6, radius: 0.35, .secondary, life: 0.6, size: 0.07, rise: 1.6), .follow, offset: [0, 1.2, 0]),
            ]
            // パッシブ由来のスキルのダメージは無い（月影は通常攻撃）
            r.hit = glint(.secondary)
            return r
        case .skill1:
            return moonArrow()
        case .skill2:
            return eclipse()
        case .ultimate:
            return hiddenMoonlight()
        }
    }

    // MARK: - スキル1 月弦分矢

    /// 自己強化（4 秒）。弦を離す 0.1 秒に、主矢と左右の副矢が弓から前へ飛んで分かれる。
    private static func moonArrow() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let t: Float = 0.1
        let pivot: SIMD3<Float> = [-0.05, 1.3, 0.85]
        r.cast = [
            // 弦を引くと弓に月光が集まり、離す瞬間に弓の先で三日月が閃く
            .emit(.gather(12, radius: 0.55, .secondary, life: t), offset: bow),
            .emit(.flare(1.3, .core, life: 0.16, tex: .flare4), at: t, offset: bow),
            .mesh(.sprite(.moon, 0.6, .accent, life: 0.32, grow: 1.6, alpha: 0.95), at: t, offset: bow),
            // 効果中（4 秒）: 足元を三日月が巡り、弓の先に月のきらめきが流れ続ける
            .mesh(FXMesh.decal(.moon, 1.7, .secondary, life: buffTime, spin: 170, grow: 1.0, alpha: 0.5).with {
                $0.fadeIn = 0.04
                $0.fadeOut = 0.88
            }, .follow),
            .emit(.trail(.twinkle, .secondary, rate: 14, life: 0.45, size: 0.13).with {
                $0.duration = buffTime
                $0.dir = .up
                $0.speed = 0.6
                $0.tintEnd = .primary
            }, .follow, offset: bow),
        ]
        // 主矢（中央は 2 枚が重なって明るい）と左右 16° の副矢が弓から前へ飛び、通り道に翠の筋が残る
        r.impact = [
            .mesh(flyingArrow(length: 1.7, width: 0.6, .core, speed: 15, life: 0.3), at: t, offset: pivot)
                .repeated(2, yaw: split),
            .mesh(flyingArrow(length: 1.5, width: 0.5, .secondary, speed: 14, life: 0.3), at: t + 0.02, offset: pivot)
                .repeated(2, yaw: -split),
            afterimage(0, length: 4.4, width: 0.55, .primary, at: t + 0.02, from: pivot),
            afterimage(split, length: 3.8, width: 0.42, .primary, at: t + 0.03, from: pivot),
            afterimage(-split, length: 3.8, width: 0.42, .primary, at: t + 0.04, from: pivot),
            .emit(.fan(12, .secondary, speed: 13, spread: split + 4, life: 0.28, size: 0.1), at: t, offset: pivot),
            .emit(.flutter(.shard, 8, radius: 0.25, .secondary, speed: 4, life: 0.5, size: 0.13), at: t, offset: pivot),
        ]
        // 連弾の矢は通常攻撃の弾（スキルのダメージではない）ので被弾演出は出ない
        r.hit = glint(.secondary)
        return r
    }

    // MARK: - スキル2 月蝕の矢

    /// 天へ放つ（0.1）→ 矢の雨と主矢が落ちる（0.03〜0.35）→ 着弾（0.35）→ 6 本の小さな矢が散る（travel）。
    private static func eclipse() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = eclipseRadius
        let land = eclipseDelay
        let shoot: Float = 0.1
        let skyward = bowHigh + SIMD3<Float>(0, 0.6, 0)
        r.cast = [
            .emit(.gather(10, radius: 0.5, .secondary, life: shoot), offset: bowHigh),
            .emit(.flare(1.2, .core, life: 0.15, tex: .flare4), at: shoot, offset: bowHigh),
            // 天へ放つ月蝕の矢（上向きの矢が一瞬で空へ抜ける）
            .mesh(uprightArrow(length: 1.6, width: 0.5, .core, life: 0.2, up: true).with { $0.rise = 18 }, at: shoot,
                  offset: skyward).repeated(2, yaw: 90),
            .emit(.sparks(8, speed: 7, .core, end: .secondary, size: 0.09, life: 0.3, gravity: 2).with {
                $0.dir = .up
                $0.spread = 18
            }, at: shoot, offset: bowHigh),
        ]
        // ゾーンの telegraph は発動と同時に着弾点で再生される（中心が原点）。着弾の本体もここに at = 0.35 で置く
        r.telegraph = [
            // 0〜: 着弾点に月の印（細い輪と、巡る三日月）が浮かぶ
            .mesh(FXMesh.decal(.ring, R * 2, .secondary, life: land + 0.1, spin: 0, grow: 1.0, alpha: 0.55)),
            .mesh(FXMesh.decal(.moon, R * 1.5, .accent, life: land + 0.1, spin: 260, grow: 1.0, alpha: 0.55)),
            // 0.03〜: 天から月光の矢の雨（縦の光の筋が着弾点の円へ降り注ぎ、0.3〜0.4 秒に地へ届く）
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: .secondary, count: 16, emit: 0.1, life: 0.28, lifeVar: 0.05,
                         size: 0.16, sizeVar: 0.3, grow: 1, shape: .box([R, 0.2, R]), dir: .down, speed: 24,
                         speedVar: 0.08, stretch: 3.2, fade: .linearFadeOut), at: 0.03, offset: [0, 6.6, 0]),
            // 0.1: 主矢が真上から落ちる（下向きの矢。0.35 秒に矢じりが地に届く）
            .mesh(uprightArrow(length: 2.6, width: 0.8, .core, life: land - 0.1, up: false).with {
                $0.rise = -20
                $0.fadeOut = 0.92
            }, at: 0.1, offset: [0, 6.3, 0]).repeated(2, yaw: 90),
            // 0.35: 着弾。白い閃光・地に刺さった主矢（移動不能のあいだ残る）・月光の柱・細い衝撃の輪
            .emit(.flare(2.3, .core, life: 0.2, tex: .flare6), at: land, offset: [0, 0.5, 0]),
            .mesh(uprightArrow(length: 1.7, width: 0.6, .secondary, life: rootTime, up: false, alpha: 0.95).with {
                $0.fadeIn = 0.02
                $0.fadeOut = 0.7
            }, at: land, offset: [0, 0.6, 0]).repeated(2, yaw: 90),
            .mesh(.pillar(0.45, height: 5, .secondary, life: 0.4), at: land),
            .mesh(.shockRing(R * 1.05, .core, life: 0.32, tex: .ring), at: land),
            // 月蝕の印: 噛み合う二つの三日月が巡り、中央の地面が影に沈む
            .mesh(FXMesh.decal(.moon, R * 2.1, .primary, life: rootTime, spin: 120, grow: 1.0, alpha: 0.75), at: land)
                .repeated(2, yaw: 180),
            .mesh(FXMesh(shape: .disc, tex: .glow, tint: .dark, alpha: 0.55, size: [R * 1.4, 1, R * 1.4],
                         sizeEnd: [R * 1.7, 1, R * 1.7], ease: .out, life: rootTime, fadeIn: 0.05, fadeOut: 0.6), at: land),
            // 砕けて舞う月の結晶と、立ちのぼる翠の光
            .emit(.flutter(.shard, 10, radius: 0.35, .secondary, speed: 5, life: 0.55, size: 0.15), at: land,
                  offset: [0, 0.5, 0]),
            .emit(.rising(12, radius: R * 0.8, .primary, speed: 2.4, life: 0.8), at: land + 0.04, quality: 1),
            .shake(0.15, at: land),
        ]
        // 着弾と同時に散る 6 本の小さな矢（本物の投射物。前方 = 飛ぶ向き）: 白い光の矢と銀青の筋
        r.travel = [
            .mesh(FXMesh(shape: .disc, tex: .arrow, tint: .core, alpha: 1, size: [1.1, 1, 0.45], sizeEnd: [1.1, 1, 0.45],
                         ease: .linear, life: minorArrowTime + 0.08, fadeIn: 0.02, fadeOut: 0.8, yaw: 90), .follow,
                  offset: [0, 0.9, 0]),
            .emit(.trail(.streak, .secondary, rate: 45, life: 0.16, size: 0.2).with {
                $0.dir = .backward
                $0.speed = 3
                $0.stretch = 2.5
                $0.tintEnd = .primary
            }, .follow, offset: [0, 0.9, 0], quality: 1),
        ]
        // ゾーンの発動（中心）と、小さな矢 6 本それぞれの終わり（命中・射程の端）: 小さな閃きだけ
        r.impact = [
            .emit(.flare(0.8, .core, life: 0.12, tex: .flare4), offset: [0, 0.8, 0]),
            .emit(.sparks(5, speed: 4, .core, end: .secondary, size: 0.08, life: 0.22), offset: [0, 0.8, 0]),
        ]
        // 移動不能 1.2 秒（着弾）/ 鈍足 2 秒（小さな矢）: 月光が射し、足元を細い月の輪と巡る三日月の枷が締める
        r.hit = [
            .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.0, 0]),
            .mesh(.pillar(0.3, height: 2.2, .secondary, life: 0.3), .follow),
            .mesh(.halo(0.55, .secondary, life: rootTime, spin: 220, tex: .ring), .follow, offset: [0, 0.12, 0]),
            .mesh(FXMesh.decal(.moon, 1.25, .primary, life: rootTime, spin: -260, grow: 1.0, alpha: 0.9), .follow),
            .emit(.sparks(6, speed: 4, .secondary, end: .primary, size: 0.08), offset: [0, 0.9, 0]),
        ]
        return r
    }

    // MARK: - アルティメット 隠れ月光

    /// 月光の帳に包まれて月影に紛れる（隠密 2 秒・弱体の解除・加速）。演出は発動の位置に置く（隠れた位置を敵に見せない）。
    private static func hiddenMoonlight() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let mist = FXTint.rgb(0.74, 0.9, 1.0)
        r.cast = [
            // 月光の帳（光の円柱が降りて縮む）と、背に昇る三日月・白い閃光
            .emit(.flare(1.8, .core, life: 0.22, tex: .flare6), offset: [0, 1.1, 0]),
            .mesh(FXMesh(shape: .cylinder, tex: .beam, tint: .secondary, alpha: 0.75, size: [0.55, 5.0, 0.55],
                         sizeEnd: [1.0, 3.2, 1.0], ease: .out, life: 0.65, fadeIn: 0.04, fadeOut: 0.45)),
            .mesh(.sprite(.moon, 1.1, .accent, life: 0.7, grow: 1.25, alpha: 0.85), offset: [0, 3.4, -0.2]),
            // 弱体の解除: 足元から細い輪が広がる
            .mesh(.shockRing(1.7, .secondary, life: 0.4, tex: .ring)),
            // 月光の霞・翠の木の葉・小さな三日月が舞い散る（外套が月影に溶ける）
            .emit(.smoke(10, radius: 0.5, mist, life: 1.1, size: 0.9).with { $0.speed = 1.8 }, quality: 1),
            .emit(.flutter(.petal, 12, radius: 0.6, .primary, speed: 3.2, life: 1.2, size: 0.14), offset: [0, 1.0, 0]),
            .emit(.flutter(.moon, 8, radius: 0.5, .accent, speed: 2.4, life: 1.0, size: 0.12), offset: [0, 1.3, 0]),
            // 走り出す一瞬だけ月光の尾（隠密中の位置を明かさないよう 0.3 秒で止める）
            .emit(.trail(.streak, .secondary, rate: 40, life: 0.25, size: 0.25).with {
                $0.duration = 0.3
                $0.dir = .backward
                $0.speed = 2.5
                $0.stretch = 2
            }, .follow, offset: [0, 0.9, 0]),
        ]
        // 自身中心なので発動と同時に再生: 地に広がる月の波紋・三日月の印・立ちのぼる月光の粒
        r.impact = [
            .emit(.wave(1.9, .secondary, life: 0.5, tex: .ripple), offset: [0, 0.05, 0]),
            .mesh(FXMesh.decal(.moon, 2.4, .primary, life: 0.9, spin: 160, grow: 1.1, alpha: 0.7)),
            .emit(.rising(16, radius: 0.7, .secondary, speed: 3.0, life: 0.9), quality: 1),
        ]
        // ダメージは無い
        r.hit = glint(.accent)
        return r
    }

    // MARK: - 詠唱モーション

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 弦を引き絞って月光を宿し、0.1 秒で離して三条の矢を放つ
            m.draw(0.08, up: 0.08)
            m.release(0.04)
            m.hold(0.14) { $0.glow = 1.8 }
        case .skill2:
            // 弓を天へ向けて引き（0.1 秒で放つ）、矢が落ちるまで空を見上げる
            m.draw(0.08, up: 0.75)
            m.release(0.04)
            m.hold(0.18) { $0.glow = 1.6; $0.headPitch = -0.35 }
            m.settle(0.1)
        case .ultimate:
            // 腰を落として外套で身を包み、月影に紛れる
            m.brace(0.08, depth: 0.22)
            m.guardCross(0.1)
            m.hold(0.12) { $0.glow = 2.0; $0.ring = 1.0 }
            m.settle(0.12)
        }
    }
}
