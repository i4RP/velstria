import Foundation
import VelstriaCore

// スキル演出: H029 聖槌のボルグ（Support / 巨大な聖槌・円盾・青と金の重装。MLBB の Tigreal の Velstria 版）。
// 主題: 金の聖槌が大地を打つ。白金の芯 × 金（主）× 鋼の青（副）× 温かい白（差し色）× 土煙。
// 上から見下ろすカメラで「扇へ 3 回はじける」「突進して押し運ぶ」「振り上げて打ち上げる」「吸い寄せて叩き潰す」が読めるよう、
// 円い輪を主役にせず、前方の弧・扇に並ぶ爆発・地割れ・内へ縮む輪で形を見せる。
// sim の実際の挙動（Systems/Kits/Kit_H029.swift の Tune）に合わせたタイミング:
//   パッシブ 聖鎚の誓い       — 誓いが積まれる / 防御が発動する（バッジのタイマー）たびに、左腕の盾に小さな金のきらめき。
//                              スキルの発動の直後（0.6 秒以内）の防御は passiveRelease: 青い六角の盾の殻と金の盾面が弾ける
//   スキル1 聖槌波           — 0.25 秒で槌が地を打ち、前方の台形（奥行き 6.1m）に衝撃波が手前 → 中 → 奥へ 3 回はじける
//                              （0.25 / 0.58 / 0.92 秒 = waveFirstDelay + waveInterval × n、帯の中心は奥行きの 1/4・1/2・3/4）。
//                              回ごとに光る弧が前へ走り、白金の閃光 → 橙の炎の塊（コマ送り）・金に光るひびと焦げ跡・土煙
//   スキル2 聖槌突撃         — 1 回目: 盾を前に突進（5.25m を約 0.67 秒）。通り道に金の筋と土煙、終点（照準点）で押し運んだ衝撃。
//                              突進は impact を再生しない（ゾーンを作らない）ので、終点の演出は cast の .target に 0.67 秒遅れで置く。
//                              再使用（stage 1、4 秒以内）: 0.2 秒（smashDelay）で槌を振り上げ、前方の扇（2.15m）に金の光の柱・
//                              昇る輪・上へ噴く火花 = 打ち上げ（0.6 秒）。段の演出は recipe(_:stage:_:)
//   アルティメット 崩落聖域    — 詠唱 1.0 秒。0 秒: 半径 2.78m の金の陣が範囲を示し、引き寄せ（0.67 秒で集める）= 外から内へ縮む
//                              衝撃の輪・逆巻く渦・吸い込まれる光の筋と土煙。掲げた槌に金の光が集まり続ける。
//                              1.0 秒: 槌が落ちて崩落 = 白熱の閃光・橙の炎の爆発・三重の衝撃波・橙に光るひびの広がる焦げ跡・
//                              白い岩の破片 + 気絶（発動から 1.8 秒）の星
// 時刻と寸法は MLBB の画面収録で測った値（docs/kits/Tigreal.md「動画で測った値」）。見た目の対応は docs/vfx/H029.md。
// 光る部品（閃光・光の柱・衝撃波・光るひび）は加算（glowing）、煙・焦げ跡・盾面はアルファ合成。炎・煙・爆ぜはコマ送り（FXSheet）。
// SkillFXDirector は duration / count を読まない: 波の回数・段は at（遅れ）と recipe(_:stage:_:) で表す。
// 扇・自身中心のアーキタイプ（S1・S2 の再使用・奥義）は発動と同時に cast と impact を再生する（impact の at が sim の時刻）。

enum FX_H029: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.97, 0.82), primary: RGB(1.0, 0.76, 0.24),
                                   secondary: RGB(0.3, 0.56, 1.0), accent: RGB(1.0, 0.92, 0.72),
                                   dark: RGB(0.12, 0.09, 0.05))

    /// 土煙・土の破片（明るい土色のアルファ合成。草地・石畳・水の上でも見える）。
    private static let dust = FXTint.rgb(0.58, 0.48, 0.34)
    /// MLBB の聖槌の爆発の炎（橙）と、その消え際（暗い朱）。
    private static let flame = FXTint.rgb(1.0, 0.52, 0.14)
    private static let ember = FXTint.rgb(0.55, 0.14, 0.04)
    /// 崩落で飛ぶ白い岩の破片。
    private static let rock = FXTint.rgb(0.86, 0.82, 0.74)

    // MARK: - sim の時刻（Kit_H029.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 1 回目の衝撃波の遅れ・間隔・回ごとの帯の中心（奥行きに対する比。帯 = waveBandStart + waveBandLength / 2）。
    private static let waveFirst: Float = 0.25
    private static let waveInterval: Float = 1.0 / 3.0
    private static let waveScale: [Float] = [0.25, 0.5, 0.75]
    /// スキル2: 突進の所要（5.25m / 7.8m/s ≈ 0.67 秒）、再使用の振り上げまでの遅れと扇の奥行き（m）。
    private static let dashTime: Float = 0.67
    private static let smashDelay: Float = 0.2
    private static let smashReach: Float = 2.15
    /// アルティメット: 引き寄せの始まり（発動の瞬間）と崩落（ultTotal）。
    private static let ultPull: Float = 0
    private static let ultSlam: Float = 1.0

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

    /// 0.25 秒で槌が地を打つ → 台形に 3 回、前へ進みながらはじける（R = 台形の奥行き 6.1m = 射程）。
    /// MLBB の画面収録（docs/vfx/H029.md）: 回ごとに白金の芯の閃光 → 橙の炎と煙の塊、地を走る金のぎざぎざのひび、暗い焦げ跡。
    private static func waveRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.range, 6.5)
        // 槌の頭が地を打つ点（右手の槌 = やや右前）: 白金の閃光と小さな衝撃の輪（光る）
        r.cast = [
            .emit(.flare(1.4, .core, life: 0.14, tex: .flare6), at: waveFirst - 0.02, offset: [0.25, 0.4, 0.9]),
            .mesh(.shockRing(0.9, .accent, life: 0.25).glowing(), at: waveFirst - 0.02, offset: [0.2, 0, 0.9]),
        ]
        var impact: [FXCue] = []
        for (k, scale) in waveScale.enumerated() {
            let t = waveFirst + waveInterval * Float(k)
            let rad = R * scale
            let dist = rad * 0.8
            let strong = Float(k) * 0.2
            // 前へ走る衝撃の弧（光る。筋の模様が前へ流れ、縁から欠けて消える）
            impact.append(.mesh(waveArc(from: max(0.6, rad - 1.4), to: rad, k == 2 ? .core : .primary, life: 0.3).glowing()
                .flowing(.streaks, scroll: [0, -2.4], tiling: 2, strength: 0.6, erosion: 0.35, edge: .core), at: t))
            // 爆発の芯の白金の閃光（一瞬）
            impact.append(.mesh(.sprite(.glowHard, 1.5 + strong, .core, life: 0.16, grow: 1.7).glowing(), at: t,
                                offset: [0, 0.6, dist]))
            // 地を走る金のぎざぎざのひび（光る）と、残る暗い焦げ跡
            impact.append(.mesh(.decal(.crack, rad * 0.8, flame, life: 0.55, spin: 0, grow: 1.06, alpha: 1).glowing()
                .flowing(.cells, scroll: [0.15, 0.5], tiling: 1.5, strength: 0.5, erosion: 0.25, edge: .core), at: t,
                                offset: [0, 0, dist]))
            impact.append(.mesh(.decal(.crack, rad * 0.75, .dark, life: 1.2, spin: 0, grow: 1.0, alpha: 0.7), at: t,
                                offset: [0, 0, dist]))
            // 橙の炎の塊（帯の幅に 2 つ）と土煙・火花
            impact.append(.emit(.sheet(.fireBurst, 2.3 + strong * 2, flame, end: ember, count: 2, life: 0.55,
                                       radius: rad * 0.3), at: t, offset: [0, 0.6, dist]))
            impact.append(.emit(.sheet(.smokePuff, 1.7, dust, count: 3, life: 0.9, additive: false, radius: rad * 0.35),
                                at: t + 0.04, offset: [0, 0.4, dist], quality: 1))
            impact.append(.emit(.sparks(10, speed: 6 + strong * 4, .core, end: .primary, gravity: 9).with {
                $0.dir = .up; $0.spread = 25; $0.shape = .box([rad * 1.0, 0.1, 0.6])
            }, at: t, offset: [0, 0.2, dist]))
            impact.append(.shake(0.16 + 0.06 * Float(k), at: t))
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

    /// 1 回目: 盾を前に突進して、通り道の敵を終点まで押し運ぶ。MLBB: 背に橙の炎の尾と金のきらめき、ぶつかった前で白金の閃光。
    private static func chargeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = min(s.range, 6.0)
        r.cast = [
            // 盾を構えて踏み出す閃きと、先頭の青い盾面
            .emit(.flare(1.2, .core, life: 0.14), .follow, offset: [-0.3, 1.0, 0.7]),
            .mesh(.wall(.hexShield, width: 1.3, height: 1.4, .secondary, life: 0.3, alpha: 0.75), .follow,
                  offset: [0, 0.25, 0.75]),
            // 背に流れる橙の炎の尾（コマ送り）と金の光条（突進の間だけ）
            .emit(.trail(.glow, flame, rate: 34, life: 0.38, size: 1.1).with {
                $0.duration = dashTime; $0.sheet = .flameLoop; $0.sheetRandomStart = true; $0.tintEnd = ember
                $0.dir = .backward; $0.speed = 2.5; $0.grow = 0.6
            }, .follow, offset: [0, 0.8, -0.3]),
            .emit(.trail(.streak, .core, rate: 50, life: 0.25, size: 0.2).with {
                $0.duration = dashTime; $0.stretch = 2.4; $0.dir = .backward; $0.speed = 4; $0.tintEnd = .primary
            }, .follow, offset: [0, 1.0, 0]),
            .emit(.trail(.smoke, dust, rate: 18, life: 0.7, size: 0.9).with {
                $0.duration = dashTime + 0.03; $0.additive = false; $0.grow = 1.6; $0.fade = .gradualFadeInOut; $0.tintEnd = nil
                $0.sheet = .smokePuff
            }, .follow, offset: [0, 0.3, 0], quality: 1),
            // 通り道に焼き付く金の筋（光る。前へ流れる）と、舞い上がる金のきらめき
            .mesh(.ray(.streak, length: L, width: 1.2, .primary, life: 0.45).glowing()
                .flowing(.streaks, scroll: [-2.0, 0], tiling: 2, strength: 0.5, erosion: 0.3, edge: .core),
                  at: 0.02, .along(0.5)),
            .emit(.lineBurst(L, count: 16, .primary, life: 0.5, size: 0.26), at: 0.05, .along(0.5), offset: [0, 0.1, 0]),
            // 終点: 押し運んだ敵ごと止まる衝撃（白金の爆ぜ・前方の三日月・輪・破片）
            .emit(.sheet(.energyBurst, 2.6, .core, end: .primary, life: 0.32), at: dashTime, .target, offset: [0, 0.9, 0.3]),
            .mesh(.slash(1.6, .primary, from: 60, to: -60, life: 0.25).glowing(), at: dashTime, .target, offset: [0, 0.5, 0.1]),
            .mesh(.shockRing(1.6, .accent, life: 0.35).glowing(), at: dashTime, .target, offset: [0, 0, 0.4]),
            .emit(.debris(10, speed: 5, dust), at: dashTime, .target, offset: [0, 0, 0.5]),
            .shake(0.2, at: dashTime),
        ]
        // 突進（dashStrike）は impact を再生しない（終点の演出は cast の .target）。目視確認の実演（-skillDemo）だけが
        // impact を出すので、既定演出で補われないよう小さな揺れだけ置く
        r.impact = [.shake(0.1)]
        // 突進に巻き込まれた敵: ぶつかった瞬間の白金の閃光と押される向きへ散る火花、押し運ばれる間の土煙
        r.hit = [
            .emit(.sheet(.hitFlash, 1.8, .core, end: .primary, life: 0.22), offset: [0, 1.0, 0]),
            .emit(.sparks(10, speed: 6, .core, end: .primary).with { $0.dir = .forward; $0.spread = 35 },
                  offset: [0, 1.0, -0.2]),
            .emit(.trail(.smoke, dust, rate: 30, life: 0.5, size: 0.5).with {
                $0.duration = dashTime; $0.additive = false; $0.grow = 1.8; $0.fade = .gradualFadeInOut; $0.tintEnd = nil
            }, .follow, offset: [0, 0.2, 0], quality: 1),
        ]
        return r
    }

    /// 再使用（stage 1）: 0.2 秒で聖槌を下から振り上げ、前方の扇（2.15m）の敵を打ち上げる（0.6 秒）。
    /// MLBB: 縦に振り上げる白金の三日月と、打ち上げた敵の上の金の爆ぜ。突進の尾（共通の cast）は出さない。
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
            // 縦に振り上げる白金の三日月（前を向いて立つ板・光る）とコマ送りの斬撃
            .mesh(.wall(.slash, width: 2.8, height: 2.8, .core, life: 0.28, alpha: 1).glowing()
                .flowing(.streaks, scroll: [0, -3], tiling: 1.5, strength: 0.5, erosion: 0.3, edge: .primary).with {
                    $0.roll = -90
                    $0.ease = .out
                }, at: t, offset: [0, 0.4, smashReach * 0.45]),
            .emit(.sheet(.slashFade, 2.6, .core, end: .primary, life: 0.3, orient: .facing).with {
                $0.angle = -90
                $0.angleVar = 8
            }, at: t, offset: [0, 1.3, smashReach * 0.45]),
            // 打ち上げの金の爆ぜと、天へ立つ金の光の柱（光る。筋が上へ流れる）
            .emit(.sheet(.energyBurst, 2.8, .core, end: .primary, life: 0.36), at: t + 0.03, offset: [0, 1.4, smashReach * 0.5]),
            .mesh(.pillar(0.7, height: 5, .primary, life: 0.5).glowing()
                .flowing(.streaks, scroll: [0, -2.5], tiling: 2, strength: 0.7, erosion: 0.2, edge: .core), at: t, offset: mid),
            // 地割れ・足元の輪
            .mesh(.decal(.crack, 3.0, .dark, life: 1.1, spin: 0, grow: 1.0, alpha: 0.8), at: t, offset: mid),
            .mesh(.shockRing(1.8, .accent, life: 0.35).glowing(), at: t, offset: mid),
            // 打ち上げ: 地面から昇る輪が 3 つ続く（光る）
            .mesh(FXMesh.halo(0.9, .accent, life: 0.6, spin: 200, tex: .ringDouble).with { $0.rise = 3.5 }.glowing(), at: t,
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
            .emit(.sheet(.hitFlash, 1.6, .core, end: .primary, life: 0.2), offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 6, .core, end: .primary).with { $0.dir = .up; $0.spread = 30 }, offset: [0, 0.8, 0]),
            .mesh(FXMesh.halo(0.55, .primary, life: 0.6, spin: 300, tex: .ringDouble).with { $0.rise = 2.0 }.glowing(), .follow,
                  offset: [0, 0.3, 0]),
            .emit(.rising(8, radius: 0.4, .accent, speed: 4, life: 0.5), .follow),
        ]
        return r
    }

    // MARK: - アルティメット 崩落聖域

    /// 詠唱 1.0 秒: 発動の瞬間から吸い寄せ（0〜0.67）しながら掲げて集める → 崩落（1.0）。R = 引き寄せ・爆発の半径（2.78m）。
    /// MLBB: 範囲の円が淡い金に満ち、縁を金の光の筋が渦を巻いて内へ吸い込む → 崩落の直前に槌の上へ縦の光の筋 →
    /// 白熱の閃光 → 橙の炎の爆発と、橙に光るひびが広がる焦げ跡、白い岩の破片。
    private static func implosionRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 6.0)
        let p = ultPull, t = ultSlam
        // 掲げた槌の頭（右手・頭上）に金の光が集まる（崩落の少し前まで）
        r.cast = [
            .emit(.gather(20, radius: 1.2, .primary, life: t - 0.2), .follow, offset: [0.3, 2.5, 0.1]),
            .emit(.flare(1.8, .core, life: 0.3, tex: .flare6), at: 0.14, .follow, offset: [0.3, 2.7, 0.1]),
            .mesh(.halo(1.2, .primary, life: t, spin: 200, tex: .ringDouble), .follow, offset: [0, 0.2, 0]),
        ]
        r.impact = [
            // 0〜: 範囲が淡い金に満ち（光る柔らかい円）、縁を金の光の筋が渦を巻いて回る（模様が弧に沿って流れる）
            .mesh(.decal(.glow, R * 2.1, .primary, life: t + 0.05, spin: 0, grow: 1.0, alpha: 0.32).glowing(), at: p),
            .mesh(.halo(R, .primary, life: t + 0.05, spin: -120, tex: .beam, alpha: 1).glowing()
                .flowing(.streaks, scroll: [1.6, 0], tiling: 3, strength: 0.85, erosion: 0.45, edge: .core), at: p),
            // 外から内へ縮む衝撃の輪と逆巻く渦（光る）、吸い込まれる光の筋と土煙
            .mesh(implodeRing(from: R * 2, to: 1.2, .primary, life: 0.42).glowing(), at: p),
            .mesh(implodeRing(from: R * 1.9, to: R * 0.5, .primary, life: 0.5, tex: .swirl, spin: -420, alpha: 0.8).glowing()
                .flowing(.noise, scroll: [0.6, 0.6], tiling: 2, strength: 0.6, erosion: 0.4, edge: .core), at: p),
            .emit(FXEmit(tex: .streak, tint: .primary, tintEnd: .core, count: 48, emit: 0.18, life: 0.42, lifeVar: 0.1,
                         size: 0.14, sizeVar: 0.4, grow: 0.5, shape: .ring(R * 0.9), surface: true, dir: .outward,
                         speed: 0, stretch: 2.4, fade: .easeFadeIn, vortex: 4, attract: 14),
                  at: p, offset: [0, 0.4, 0]),
            .emit(.smoke(10, radius: R * 0.85, dust, life: 0.6, size: 1.0).with {
                $0.shape = .ring(R * 0.85); $0.surface = true; $0.speed = 0; $0.attract = 6
            }, at: p, quality: 1),
            .shake(0.2, at: p),
            // 崩落の直前: 槌の上から天へ立つ細い光の筋（光る。筋が上へ流れる）
            .mesh(.pillar(0.16, height: 9, .core, life: 0.32, alpha: 1).glowing()
                .flowing(.streaks, scroll: [0, -3], tiling: 2, strength: 0.6, edge: .primary), at: t - 0.24,
                  offset: [0.3, 1.2, 0.1]),
            // 1.0: 聖槌が落ちて崩落（白熱の閃光 → 橙の炎の爆発 → 光るひびの広がる焦げ跡・白い岩の破片）
            .mesh(.sprite(.glowHard, 3.4, .core, life: 0.2, grow: 1.5).glowing(), at: t, offset: [0, 0.9, 0.3]),
            .emit(.sheet(.energyBurst, 5.2, .core, end: .primary, life: 0.42), at: t, offset: [0, 0.8, 0.3]),
            .emit(.sheet(.fireBurst, 3.2, flame, end: ember, count: 3, life: 0.75, radius: R * 0.45), at: t + 0.04,
                  offset: [0, 0.7, 0]),
            .mesh(.pillar(1.1, height: 6, .primary, life: 0.45).glowing()
                .flowing(.streaks, scroll: [0, -2.2], tiling: 2, strength: 0.7, erosion: 0.3, edge: .core), at: t - 0.02),
            .mesh(.burstWall(R * 0.75, height: 2.0, .primary, life: 0.45).glowing()
                .flowing(.noise, scroll: [0.4, -1.5], tiling: 2, strength: 0.6, erosion: 0.5, edge: .core), at: t),
            .mesh(.shockRing(R * 0.6, .core, life: 0.32).glowing(), at: t),
            .mesh(.shockRing(R, .primary, life: 0.5).glowing(), at: t + 0.04),
            .mesh(.shockRing(R * 1.2, flame, life: 0.7).glowing(), at: t + 0.1),
            // 焦げ跡（暗い）と、その上を広がる橙に光るひび（コマ送り）
            .mesh(.decal(.crack, R * 1.9, .dark, life: 2.0, spin: 0, grow: 1.0, alpha: 0.9), at: t),
            .mesh(.decal(.crack, R * 1.6, flame, life: 1.1, spin: 0, grow: 1.05, alpha: 1).glowing()
                .flowing(.cells, scroll: [0.1, 0.4], tiling: 1.5, strength: 0.5, erosion: 0.3, edge: .accent), at: t),
            .emit(.groundSheet(.groundCrack, R * 2.3, flame, life: 1.0), at: t + 0.02, offset: [0, 0.05, 0]),
            .emit(.sparks(30, speed: 11, .core, end: .primary, size: 0.12, life: 0.55), at: t, offset: [0, 0.6, 0]),
            .emit(.debris(22, speed: 8, rock), at: t),
            .emit(.sheet(.smokePuff, 2.4, dust, count: 4, life: 1.3, additive: false, radius: R * 0.6), at: t + 0.06,
                  offset: [0, 0.5, 0], quality: 1),
            .shake(0.65, at: t),
        ]
        // 崩落の瞬間の被弾（残りの気絶 0.8 秒。発動から合計 1.8 秒）: 白金の閃光・頭上を回る金の輪と星のきらめき
        r.hit = [
            .emit(.flare(1.2, .core, life: 0.15), offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 4, .primary, end: .accent), offset: [0, 1.0, 0]),
            .mesh(FXMesh.halo(0.5, .primary, life: 0.8, spin: 300, tex: .ringDouble).glowing(), .follow, offset: [0, 2.0, 0]),
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
            // 槌を頭上へ振りかぶり、0.25 秒（1 回目の衝撃波）で地へ叩きつけ、3 回目（0.92 秒）の手前まで押し込んで光らせる
            // （基本スキルのモーションの上限 1.1 秒に収める。戻りの分を含めて 1.09 秒）
            m.overhead(0.18)
            m.smash(0.07)
            m.hold(0.33) { $0.glow = 2.0; $0.torsoPitch = 0.55 }
            m.hold(0.26) { $0.glow = 2.4 }
        case .skill2:
            // 盾を前に前傾で突っ込み（突進 0.67 秒）、槌を下から振り上げる（再使用の打ち上げ 0.2 秒にほぼ合わせる）
            m.dash(0.04, lean: 0.5)
            m.shieldBash(0.06)
            m.uppercut(0.12)
            m.hold(0.1) { $0.glow = 1.8 }
            m.settle(0.1)
        case .ultimate:
            // 足を踏ん張って槌を天へ掲げ（発動の瞬間から引き寄せ）、光を溜めて 1.0 秒で地へ叩き落とす
            m.brace(0.06, depth: 0.08)
            m.raise(0.12, glow: 1.8)
            m.hold(0.12) { $0.ring = 1.2 }
            m.hold(0.62) { $0.glow = 2.6; $0.ring = 1.6; $0.torsoPitch = -0.3 }
            m.smash(0.08)
            m.hold(0.2) { $0.glow = 2.0; $0.hipsDrop = 0.22 }
        }
    }
}
