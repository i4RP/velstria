import Foundation
import VelstriaCore

// スキル演出: H029 聖槌のボルグ（Support / 巨大な聖槌・円盾・青と金の重装。MLBB の Tigreal の Velstria 版）。
// 主題: 金の聖槌が大地を打つ。白金の芯 × 金（主）× 鋼の青（副）× 温かい白（差し色）× 土煙。
// 上から見下ろすカメラで「扇へ 3 回はじける」「突進して押し運ぶ」「振り上げて打ち上げる」「吸い寄せて叩き潰す」が読めるよう、
// 円い輪を主役にせず、前方の弧・扇に並ぶ爆発・地割れ・内へ縮む輪で形を見せる。
// sim の実際の挙動（Systems/Kits/Kit_H029.swift の Tune）に合わせたタイミング:
//   パッシブ 聖鎚の誓い       — 誓いが積まれる / 防御が発動する（バッジのタイマー）たびに、左腕の盾に小さな金のきらめき。
//                              スキルの発動の直後（0.6 秒以内）の防御は passiveRelease: 青い六角の盾の殻と金の盾面が弾ける
//   スキル1 聖槌波           — 0.12 秒で槌が地を打ち、前方の扇（±45°）に衝撃波が 3 回はじける
//                              （0.12 / 0.32 / 0.52 秒 = waveFirstDelay + waveInterval × n、半径は射程 3m の 0.7 / 0.85 / 1.0 倍）。
//                              回ごとに金の弧が前の半径から次の半径へ走り、弧の上の 3 点で金の爆発・土の破片・地割れが起きる
//   スキル2 聖槌突撃         — 1 回目: 盾を前に突進（4.2m を約 0.25 秒）。通り道に金の筋と土煙、終点（照準点）で押し運んだ衝撃。
//                              突進は impact を再生しない（ゾーンを作らない）ので、終点の演出は cast の .target に 0.25 秒遅れで置く。
//                              再使用（stage 1、4 秒以内）: 0.2 秒（smashDelay）で槌を振り上げ、前方の扇（3.2m）に金の光の柱・
//                              昇る輪・上へ噴く火花 = 打ち上げ（0.6 秒）。段の演出は recipe(_:stage:_:)
//   アルティメット 崩落聖域    — 詠唱 0.8 秒。0〜0.3 秒: 槌を掲げて金の光が集まり、半径 5.2m の金の陣が範囲を示す。
//                              0.3 秒: 引き寄せ（0.38 秒かけて集める）= 外から内へ縮む衝撃の輪・逆巻く渦・吸い込まれる光の筋と土煙。
//                              0.8 秒: 槌が落ちて崩落 = 金の柱・広がる三重の衝撃波・地割れ・円陣に噴く光の柱 + 気絶（1.8 秒）の星
// SkillFXDirector は duration / count を読まない: 波の回数・段は at（遅れ）と recipe(_:stage:_:) で表す。
// 扇・自身中心のアーキタイプ（S1・S2 の再使用・奥義）は発動と同時に cast と impact を再生する（impact の at が sim の時刻）。

enum FX_H029: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.97, 0.82), primary: RGB(1.0, 0.76, 0.24),
                                   secondary: RGB(0.3, 0.56, 1.0), accent: RGB(1.0, 0.92, 0.72),
                                   dark: RGB(0.12, 0.09, 0.05))

    /// 土煙・土の破片（明るい土色のアルファ合成。草地・石畳・水の上でも見える）。
    private static let dust = FXTint.rgb(0.58, 0.48, 0.34)

    // MARK: - sim の時刻（Kit_H029.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 1 回目の衝撃波の遅れ・間隔・回ごとの扇の半径（射程に対する比）。
    private static let waveFirst: Float = 0.12
    private static let waveInterval: Float = 0.2
    private static let waveScale: [Float] = [0.7, 0.85, 1.0]
    /// スキル2: 突進の所要（4.2m / 17m/s ≈ 0.25 秒）、再使用の振り上げまでの遅れと扇の奥行き（m）。
    private static let dashTime: Float = 0.25
    private static let smashDelay: Float = 0.2
    private static let smashReach: Float = 3.2
    /// アルティメット: 引き寄せ（ultGather）と崩落（ultTotal）。
    private static let ultPull: Float = 0.3
    private static let ultSlam: Float = 0.8

    // MARK: - 部品

    /// n 個を前方の扇の弧（半径 r、±half 度）に右から左へ並べる（every 秒ずつ遅らせて、はじける順に波打たせる）。
    private static func fanned(_ c: FXCue, _ n: Int, radius r: Float, half: Float, every: Float = 0) -> FXCue {
        var c = c
        let a = half * .pi / 180
        c.offset += SIMD3<Float>(r * sin(a), 0, r * cos(a))
        c.count = n
        c.every = every
        c.stepYaw = n > 1 ? 2 * half / Float(n - 1) : 0
        c.orbit = 0.0001
        return c
    }

    /// 前方へ走る衝撃の弧（水平の半円の帯。外縁が明るく、両端へ薄れる）。半径 from → to へ広がる。
    /// 横を 0.85 倍に絞って、前方の扇に寄せる。
    private static func waveArc(from r0: Float, to r1: Float, _ tint: FXTint, life: Float) -> FXMesh {
        FXMesh(shape: .arc, tex: .beam, tint: tint, alpha: 1, size: [r0 * 0.85, 1, r0], sizeEnd: [r1 * 0.85, 1, r1],
               ease: .out, life: life, fadeIn: 0.02, fadeOut: 0.4)
    }

    /// 外から内へ縮む衝撃の輪（引き寄せ）。直径 from → to。
    private static func implodeRing(from d0: Float, to d1: Float, _ tint: FXTint, life: Float,
                                    tex: FXTex = .shockwave, spin: Float = 0, alpha: Float = 0.9) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [d0, 1, d0], sizeEnd: [d1, 1, d1], ease: .in,
               life: life, fadeIn: 0.12, fadeOut: 0.8, spin: spin)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        switch slot {
        case .passive:
            // 誓いが積まれる・防御が発動する: 左腕の盾にきらめき（スキルの発動のたびにも出るので小さく短く）
            r.cast = [
                .emit(.flare(0.9, .core, life: 0.14, tex: .flare4), .follow, offset: [-0.45, 1.1, 0.35]),
                .mesh(.decal(.hexShield, 1.5, .secondary, life: 0.4, spin: 0, grow: 1.15, alpha: 0.5), .follow),
                .emit(.motes(6, radius: 0.3, .primary, life: 0.6), .follow, offset: [-0.4, 1.0, 0.3]),
            ]
            r.hit = []
        case .skill1:
            r = waveRecipe(s)
        case .skill2:
            r = chargeRecipe(s)
        case .ultimate:
            r = implosionRecipe(s)
        }
        return r
    }

    // MARK: - スキル1 聖槌波

    /// 0.12 秒で槌が地を打つ → 扇に 3 回、前へ進みながらはじける（R = 扇の奥行き 3m）。
    private static func waveRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 4.0)
        // 槌の頭が地を打つ点（右手の槌 = やや右前）
        r.cast = [
            .emit(.flare(1.4, .core, life: 0.14, tex: .flare6), at: waveFirst - 0.02, offset: [0.25, 0.4, 0.9]),
            .mesh(.shockRing(0.9, .accent, life: 0.25), at: waveFirst - 0.02, offset: [0.2, 0, 0.9]),
            .emit(.smoke(8, radius: 0.5, dust, life: 1.0, size: 0.8).with {
                $0.dir = .forward; $0.speed = R * 1.3; $0.spread = 40; $0.shape = .sphere(0.4)
            }, at: waveFirst, offset: [0, 0.2, 0.8], quality: 1),
        ]
        var impact: [FXCue] = []
        var prev: Float = 0.6
        for (k, scale) in waveScale.enumerated() {
            let t = waveFirst + waveInterval * Float(k)
            let rad = R * scale
            let dist = rad * 0.8
            let strong = Float(k) * 0.2
            // 金の衝撃の弧: 前の波の半径から、この波の半径へ走る（3 回目は白金で最も明るい）
            impact.append(.mesh(waveArc(from: prev, to: rad, k == 2 ? .core : .primary, life: 0.32), at: t))
            // 弧の上の 3 点ではじける金の爆発（右 → 左へ少しずつ）
            impact.append(fanned(.mesh(.sprite(.flare6, 1.1 + strong, .primary, life: 0.26, grow: 1.5), at: t,
                                       offset: [0, 0.45, 0]), 3, radius: dist, half: 26, every: 0.015))
            // 地割れ（暗い土の裂け目）
            impact.append(.mesh(.decal(.crack, rad * 0.75, .dark, life: 1.1, spin: 0, grow: 1.0, alpha: 0.8), at: t,
                                offset: [0, 0, dist]))
            // 扇の幅に広がって飛ぶ土の破片と、上へ噴く金の火花
            impact.append(.emit(.debris(10, speed: 5 + strong * 4, dust, size: 0.16).with {
                $0.shape = .box([rad * 1.1, 0.1, 0.7])
            }, at: t, offset: [0, 0.1, dist]))
            impact.append(.emit(.sparks(10, speed: 6 + strong * 4, .core, end: .primary, gravity: 9).with {
                $0.dir = .up; $0.spread = 25; $0.shape = .box([rad * 1.0, 0.1, 0.6])
            }, at: t, offset: [0, 0.2, dist]))
            impact.append(.shake(0.16 + 0.06 * Float(k), at: t))
            prev = rad
        }
        r.impact = impact
        // 3 回の衝撃波が 1 発ごとに当たる: 小さな火花と、足元の青い鈍足の輪（命中ごとに深まる）
        r.hit = [
            .emit(.sparks(6, speed: 4, .core, end: .primary), offset: [0, 0.9, 0]),
            .mesh(.shockRing(0.55, .secondary, life: 0.3), .follow),
        ]
        r.hitPerHit = true
        return r
    }

    // MARK: - スキル2 聖槌突撃

    /// 1 回目: 盾を前に突進して、通り道の敵を終点まで押し運ぶ。
    private static func chargeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = min(s.range, 6.0)
        r.cast = [
            // 盾を構えて踏み出す閃きと、先頭の青い盾面
            .emit(.flare(1.2, .core, life: 0.14), .follow, offset: [-0.3, 1.0, 0.7]),
            .mesh(.wall(.hexShield, width: 1.3, height: 1.4, .secondary, life: 0.3, alpha: 0.75), .follow,
                  offset: [0, 0.25, 0.75]),
            // 金の尾・後ろへ流れる光条・土煙（突進の間だけ）
            .emit(.trail(.glow, .primary, rate: 70, life: 0.32, size: 0.55).with { $0.duration = dashTime }, .follow,
                  offset: [0, 0.9, 0]),
            .emit(.trail(.streak, .core, rate: 50, life: 0.25, size: 0.2).with {
                $0.duration = dashTime; $0.stretch = 2.4; $0.dir = .backward; $0.speed = 4; $0.tintEnd = .primary
            }, .follow, offset: [0, 1.0, 0]),
            .emit(.trail(.smoke, dust, rate: 45, life: 0.7, size: 0.7).with {
                $0.duration = dashTime + 0.03; $0.additive = false; $0.grow = 2; $0.fade = .gradualFadeInOut; $0.tintEnd = nil
            }, .follow, offset: [0, 0.2, 0], quality: 1),
            // 通り道に焼き付く金の筋と、舞い上がる光の粒（術者 → 終点の中間に置く）
            .mesh(.ray(.streak, length: L, width: 1.2, .primary, life: 0.45), at: 0.02, .along(0.5)),
            .emit(.lineBurst(L, count: 16, .primary, life: 0.5, size: 0.26), at: 0.05, .along(0.5), offset: [0, 0.1, 0]),
            // 終点: 押し運んだ敵ごと止まる衝撃（前方の三日月・輪・破片・土煙）
            .emit(.flare(1.8, .core, life: 0.18, tex: .flare6), at: dashTime, .target, offset: [0, 0.9, 0.3]),
            .mesh(.slash(1.6, .primary, from: 60, to: -60, life: 0.25), at: dashTime, .target, offset: [0, 0.5, 0.1]),
            .mesh(.shockRing(1.6, .accent, life: 0.35), at: dashTime, .target, offset: [0, 0, 0.4]),
            .emit(.debris(10, speed: 5, dust), at: dashTime, .target, offset: [0, 0, 0.5]),
            .emit(.smoke(8, radius: 0.6, dust, life: 0.9, size: 0.8), at: dashTime, .target, offset: [0, 0, 0.4], quality: 1),
            .shake(0.2, at: dashTime),
        ]
        // 突進（dashStrike）は impact を再生しない（終点の演出は cast の .target）。目視確認の実演（-skillDemo）だけが
        // impact を出すので、既定演出で補われないよう小さな揺れだけ置く
        r.impact = [.shake(0.1)]
        // 突進に巻き込まれた敵: 押される向きへ散る火花と、押し運ばれる間の土煙
        r.hit = [
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
            .emit(.sparks(10, speed: 6, .core, end: .primary).with { $0.dir = .forward; $0.spread = 35 },
                  offset: [0, 1.0, -0.2]),
            .emit(.trail(.smoke, dust, rate: 40, life: 0.5, size: 0.5).with {
                $0.duration = dashTime; $0.additive = false; $0.grow = 1.8; $0.fade = .gradualFadeInOut; $0.tintEnd = nil
            }, .follow, offset: [0, 0.2, 0], quality: 1),
        ]
        return r
    }

    /// 再使用（stage 1）: 0.2 秒で聖槌を下から振り上げ、前方の扇（3.2m）の敵を打ち上げる（0.6 秒）。
    /// 突進の尾（共通の cast）は出さない。被弾演出は昇る輪つき（共通の hit は突進の火花）。
    static func recipe(_ slot: SkillSlot, stage: Int, _ s: FXSkillInfo) -> SkillFXRecipe? {
        guard slot == .skill2, stage == 1 else { return nil }
        var r = SkillFXRecipe()
        let t = smashDelay
        let mid: SIMD3<Float> = [0, 0, smashReach * 0.5]
        // 槌を低く構えて金の光を溜め、地を擦る
        r.cast = [
            .emit(.gather(16, radius: 0.9, .primary, life: t), .follow, offset: [0.35, 0.5, 0.6]),
            .emit(.sparks(8, speed: 3, .primary, end: .accent, gravity: 4), at: 0.08, offset: [0.4, 0.15, 0.7]),
        ]
        // 扇のアーキタイプなので発動と同時に再生される。振り上げは smashDelay の後
        r.impact = [
            .emit(.flare(2.2, .core, life: 0.2, tex: .flare6), at: t, offset: [0, 1.2, smashReach * 0.45]),
            // 天へ立つ金の光の柱（外側の金 + 芯の白金）
            .mesh(.pillar(0.9, height: 5, .primary, life: 0.55), at: t, offset: mid),
            .mesh(.pillar(0.45, height: 6, .core, life: 0.35), at: t, offset: mid),
            // 振り上げの前方の三日月（扇の奥行き）と地割れ・足元の輪
            .mesh(.slash(smashReach * 0.95, .primary, from: 50, to: -50, life: 0.3), at: t, offset: [0, 0.3, 0]),
            .mesh(.decal(.crack, 3.0, .dark, life: 1.1, spin: 0, grow: 1.0, alpha: 0.8), at: t, offset: mid),
            .mesh(.shockRing(1.8, .accent, life: 0.35), at: t, offset: mid),
            // 打ち上げ: 地面から昇る輪が 3 つ続く
            .mesh(.halo(0.9, .accent, life: 0.6, spin: 200, tex: .ringDouble).with { $0.rise = 3.5 }, at: t,
                  offset: [0, 0.2, smashReach * 0.5]).repeated(3, every: 0.08),
            // 扇の幅から上へ噴く火花・昇る光の筋・跳ね上がる土の破片
            .emit(.sparks(22, speed: 10, .core, end: .primary, size: 0.12, life: 0.55, gravity: 7).with {
                $0.dir = .up; $0.spread = 20; $0.shape = .box([2.4, 0.1, 1.8])
            }, at: t, offset: [0, 0.2, smashReach * 0.5]),
            .emit(.rising(18, radius: 1.3, .primary, speed: 6, life: 0.6, size: 0.14, tex: .streak), at: t, offset: mid),
            .emit(.debris(12, speed: 8, dust), at: t, offset: mid),
            .shake(0.3, at: t),
        ]
        // 打ち上げ（0.6 秒）: 被弾者の足元から昇る金の輪と光の粒
        r.hit = [
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 6, .core, end: .primary).with { $0.dir = .up; $0.spread = 30 }, offset: [0, 0.8, 0]),
            .mesh(.halo(0.55, .primary, life: 0.6, spin: 300, tex: .ringDouble).with { $0.rise = 2.0 }, .follow,
                  offset: [0, 0.3, 0]),
            .emit(.rising(8, radius: 0.4, .accent, speed: 4, life: 0.5), .follow),
        ]
        return r
    }

    // MARK: - アルティメット 崩落聖域

    /// 詠唱 0.8 秒: 掲げて集める（0〜0.3）→ 吸い寄せ（0.3〜0.68）→ 崩落（0.8）。R = 引き寄せ・爆発の半径（5.2m）。
    private static func implosionRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 6.0)
        let p = ultPull, t = ultSlam
        // 掲げた槌の頭（右手・頭上）に金の光が集まる
        r.cast = [
            .emit(.gather(20, radius: 1.2, .primary, life: p), .follow, offset: [0.3, 2.5, 0.1]),
            .emit(.flare(1.8, .core, life: 0.3, tex: .flare6), at: 0.14, .follow, offset: [0.3, 2.7, 0.1]),
            .mesh(.halo(1.2, .primary, life: t, spin: 200, tex: .ringDouble), .follow, offset: [0, 0.2, 0]),
        ]
        r.impact = [
            // 0〜: 範囲を示す金の陣と青い縁（崩落まで残る）
            .mesh(.decal(.runeCircle, R * 2, .primary, life: t + 0.05, spin: 40, grow: 1.0, alpha: 0.55)),
            .mesh(.halo(R, .secondary, life: t + 0.05, spin: -60, tex: .beam, alpha: 0.5)),
            // 0.3: 引き寄せ。外から内へ縮む衝撃の輪 2 つ・逆巻く渦 2 枚・吸い込まれる光の筋と土煙
            .emit(.flare(2.0, .primary, life: 0.2), at: p, offset: [0.3, 2.6, 0.1]),
            .mesh(implodeRing(from: R * 2, to: 1.2, .primary, life: 0.42), at: p),
            .mesh(implodeRing(from: R * 1.7, to: 1.0, .secondary, life: 0.38), at: p + 0.1),
            .mesh(implodeRing(from: R * 1.9, to: R * 0.5, .primary, life: 0.5, tex: .swirl, spin: -420, alpha: 0.75),
                  at: p),
            .mesh(implodeRing(from: R * 1.4, to: R * 0.3, .secondary, life: 0.45, tex: .swirl, spin: -600, alpha: 0.6),
                  at: p + 0.03),
            .emit(FXEmit(tex: .streak, tint: .primary, tintEnd: .core, count: 48, emit: 0.18, life: 0.42, lifeVar: 0.1,
                         size: 0.14, sizeVar: 0.4, grow: 0.5, shape: .ring(R * 0.9), surface: true, dir: .outward,
                         speed: 0, stretch: 2.4, fade: .easeFadeIn, vortex: 4, attract: 14),
                  at: p, offset: [0, 0.4, 0]),
            .emit(.smoke(10, radius: R * 0.85, dust, life: 0.6, size: 1.0).with {
                $0.shape = .ring(R * 0.85); $0.surface = true; $0.speed = 0; $0.attract = 6
            }, at: p, quality: 1),
            .shake(0.2, at: p),
            // 0.8: 聖槌が落ちて崩落（白金の閃光・金の柱・広がる三重の衝撃波・地割れ・円陣に噴く光の柱）
            .emit(.flare(3.2, .core, life: 0.3, tex: .flare6), at: t, offset: [0, 1.0, 0.4]),
            .mesh(.orb(1.0, .core, life: 0.25, grow: 2.4, alpha: 0.7), at: t, offset: [0, 0.3, 0.5]),
            .mesh(.pillar(1.2, height: 7, .primary, life: 0.5), at: t - 0.02),
            .mesh(.burstWall(R * 0.75, height: 2.2, .primary, life: 0.5), at: t),
            .mesh(.shockRing(R * 0.6, .core, life: 0.35), at: t),
            .mesh(.shockRing(R, .primary, life: 0.55), at: t + 0.04),
            .mesh(.shockRing(R * 1.2, .secondary, life: 0.75), at: t + 0.1),
            .mesh(.decal(.crack, R * 1.9, .dark, life: 2.0, spin: 0, grow: 1.0, alpha: 0.9), at: t),
            .mesh(.decal(.crack, R * 1.5, .primary, life: 1.2, spin: 0, grow: 1.05, alpha: 0.85), at: t),
            .mesh(.decal(.runeCircle, R * 1.7, .primary, life: 1.3, spin: -40, alpha: 0.6), at: t + 0.02),
            .mesh(.pillar(0.3, height: 2.6, .primary, life: 0.45, alpha: 0.8), at: t + 0.02, quality: 1)
                .ringed(6, radius: R * 0.6, every: 0.012),
            .emit(.wave(R, .primary, life: 0.6), at: t, offset: [0, 0.1, 0]),
            .emit(.sparks(36, speed: 11, .core, end: .primary, size: 0.12, life: 0.55), at: t, offset: [0, 0.6, 0]),
            .emit(.debris(24, speed: 8, dust), at: t),
            .emit(.smoke(14, radius: R * 0.6, dust, life: 1.5, size: 1.2).with { $0.speed = 3 }, at: t + 0.02, quality: 1),
            .emit(.embers(20, radius: R * 0.8, .primary, life: 1.3), at: t + 0.1, quality: 1),
            .shake(0.65, at: t),
        ]
        // 崩落の瞬間の被弾（気絶 1.8 秒）: 白金の閃光・頭上を回る金の輪（2 回）と星のきらめき
        r.hit = [
            .emit(.flare(1.2, .core, life: 0.15), offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 4, .primary, end: .accent), offset: [0, 1.0, 0]),
            .mesh(.halo(0.5, .primary, life: 0.9, spin: 300, tex: .ringDouble), .follow, offset: [0, 2.0, 0])
                .repeated(2, every: 0.9),
            .emit(.flutter(.star, 6, radius: 0.35, .primary, speed: 0.5, life: 1.2, size: 0.16).with {
                $0.gravity = 0; $0.vortex = 5
            }, .follow, offset: [0, 2.0, 0], quality: 1),
        ]
        return r
    }

    // MARK: - パッシブの解放

    /// 誓いを使い切った（防御の発動がスキルの直後）ときの盾の弾け。released は消費した誓いの数（4）。
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? {
        [
            .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), .follow, offset: [-0.4, 1.1, 0.45]),
            .mesh(.dome(1.1, .secondary, life: 0.45, tex: .hexShield, alpha: 0.6), .follow),
            .mesh(.wall(.hexShield, width: 1.3, height: 1.5, .primary, life: 0.35, alpha: 0.8), .follow,
                  offset: [0, 0.2, 0.7]),
            .mesh(.shockRing(1.3, .primary, life: 0.35), .follow),
            .emit(.sparks(14, speed: 5, .core, end: .primary), .follow, offset: [-0.3, 1.1, 0.5]),
        ]
    }

    // MARK: - 詠唱モーション

    /// 再使用の段もスキル2 と同じモーション（モーションは段で分けられない）: 盾で突っ込み、そのまま槌を下から振り上げる。
    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 槌を頭上へ振りかぶり、0.12 秒（1 回目の衝撃波）で地へ叩きつけ、3 回目（0.52 秒）まで押し込んで光らせる
            m.overhead(0.07)
            m.smash(0.05)
            m.hold(0.2) { $0.glow = 2.0; $0.torsoPitch = 0.55 }
            m.hold(0.2) { $0.glow = 2.4 }
        case .skill2:
            // 盾を前に前傾で突っ込み（突進 0.25 秒）、槌を下から振り上げる（再使用の打ち上げ 0.2 秒にほぼ合わせる）
            m.dash(0.04, lean: 0.5)
            m.shieldBash(0.06)
            m.uppercut(0.12)
            m.hold(0.1) { $0.glow = 1.8 }
            m.settle(0.1)
        case .ultimate:
            // 足を踏ん張って槌を天へ掲げ（0.3 秒で引き寄せ）、光を溜めて 0.8 秒で地へ叩き落とす
            m.brace(0.06, depth: 0.08)
            m.raise(0.12, glow: 1.8)
            m.hold(0.12) { $0.ring = 1.2 }
            m.hold(0.42) { $0.glow = 2.6; $0.ring = 1.6; $0.torsoPitch = -0.3 }
            m.smash(0.08)
            m.hold(0.2) { $0.glow = 2.0; $0.hipsDrop = 0.22 }
        }
    }
}
