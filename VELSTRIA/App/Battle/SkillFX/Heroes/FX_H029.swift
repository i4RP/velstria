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
    private static let flame = FXTint.rgb(1.0, 0.64, 0.22)
    private static let ember = FXTint.rgb(0.45, 0.2, 0.1)
    /// 崩落で飛ぶ白い岩の破片。
    private static let rock = FXTint.rgb(0.86, 0.82, 0.74)

    // MARK: - sim の時刻・寸法
    // Kit_H029.Tune の値は写さず、FXSkillInfo（HeroKits.fxValues）から読む（照準の表示・判定・演出が同じ値。docs/vfx/RANGES.md）:
    //   S1 waveFirstDelay・waveInterval・waveCount・waveReach・waveNear/FarHalfWidth・waveBandStart・waveBandLength（台形の帯）
    //   S2 dashRange・dashSpeed・dashWidth（突進の当たりの半幅）  再使用 smashDelay・smashReach・smashHalfAngle
    //   奥義 ultReach（捕まえる・崩落の半径）・ultTotal（崩落の時刻）

    /// スキル1 の k 回目の帯（手前・奥の奥行き m と、奥行き d の台形の半幅 m）。Kit_H029.waveBand と同じ寸法。
    private struct WaveBand {
        var lo: Float
        var hi: Float
        var near: Float
        var far: Float
        var reach: Float

        func half(_ d: Float) -> Float { near + (far - near) * min(max(d, 0), reach) / max(0.01, reach) }
        var center: Float { (lo + hi) / 2 }
    }

    private static func waveBands(_ s: FXSkillInfo) -> [WaveBand] {
        let reach = s.meters("waveReach")
        let starts = s.ratios("waveBandStart")
        let length = s.ratio("waveBandLength")
        let n = min(starts.count, s.count("waveCount"))
        return (0..<n).map { k in
            WaveBand(lo: k == 0 ? 0 : starts[k] * reach, hi: k == n - 1 ? reach : (starts[k] + length) * reach,
                     near: s.meters("waveNearHalfWidth"), far: s.meters("waveFarHalfWidth"), reach: reach)
        }
    }

    // MARK: - 部品

    /// 弧（arc）の見える開き（FXEdge.arcHalfSpan = ±81°）の端の sin・cos（帯に合わせる弧の大きさの計算）。
    private static let arcEdgeSin = sin(FXEdge.arcHalfSpan * .pi / 180)
    private static let arcEdgeCos = cos(FXEdge.arcHalfSpan * .pi / 180)

    /// 帯 b に合わせた衝撃の弧の大きさ（右・上・前）。弧の中心を帯の手前の辺に置くと、前の端 = 帯の奥の辺、見える開きの端
    /// （±81°）= その奥行きでの台形の横の辺（docs/vfx/RANGES.md）。
    private static func bandArcSize(_ b: WaveBand) -> SIMD3<Float> {
        let depth = b.hi - b.lo
        return [b.half(b.lo + depth * arcEdgeCos) / arcEdgeSin, 1, depth]
    }

    /// 円い模様の板の大きさ: 見える縁（板の FXEdge.radial 倍）が半径 r になる一辺。
    private static func plate(_ tex: FXTex, radius r: Float) -> SIMD3<Float> {
        let side = r / (FXEdge.radial(tex) ?? 0.49)
        return [side, 1, side]
    }

    /// 縁 → 縁 × spread へ ease .out で広がる部品が 1.03 倍を越える寿命の比より少し前（消え始めの比）。
    private static func edgeFade(_ spread: Float) -> Float {
        guard spread > 1.03 else { return 0.4 }
        let e: Float = 0.03 / (spread - 1)
        return max(0.02, (1 - pow(1 - e, 1.0 / 3.0)) * 0.9)
    }

    /// 判定の縁に出る輪（tex の円い模様）: 判定の瞬間に見える縁がちょうど r、消えながら r × spread へ広がる
    /// （外へは消えながらだけ。広がり始めの 1.03r を越える前に消え始める）。
    private static func edgeRing(_ r: Float, _ tint: FXTint, life: Float, spread: Float = 1.08, tex: FXTex = .shockwave,
                                 alpha: Float = 0.95) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: plate(tex, radius: r),
               sizeEnd: plate(tex, radius: r * spread), ease: .out, life: life, fadeIn: 0.02,
               fadeOut: edgeFade(spread))
    }

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

    /// waveFirstDelay で槌が地を打つ → 台形の帯に waveCount 回、前へ進みながらはじける（帯 = Kit の waveBand。奥行き waveReach）。
    /// MLBB の画面収録（docs/vfx/H029.md）: 回ごとに白金の芯の閃光 → 橙の炎と煙の塊、地を走る金のぎざぎざのひび、暗い焦げ跡。
    /// 範囲を示す部品は回ごとの衝撃の弧: 帯の手前から走って、判定の時刻にちょうど帯の奥の辺・横の辺に着き、消えながら少し広がる。
    private static func waveRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let first = s.seconds("waveFirstDelay")
        let interval = s.seconds("waveInterval")
        // 槌の頭が地を打つ点（右手の槌 = やや右前）: 白金の閃光と小さな衝撃の輪（光る。範囲より小さい飾り）
        r.cast = [
            .emit(.flare(1.4, .core, life: 0.14, tex: .flare6), at: max(0, first - 0.02), offset: [0.25, 0.4, 0.9]),
            .mesh(.shockRing(0.9, .accent, life: 0.25).glowing(), at: max(0, first - 0.02), offset: [0.2, 0, 0.9]),
        ]
        var impact: [FXCue] = []
        for (k, band) in waveBands(s).enumerated() {
            let t = first + interval * Float(k)
            let rad = band.center
            let dist = rad * 0.8
            let strong = Float(k) * 0.2
            let size = bandArcSize(band)
            let tint: FXTint = k == 2 ? .core : .primary
            // 前へ走る衝撃の弧（光る。筋の模様が前へ流れる）: 帯の手前の辺から走って判定の時刻にちょうど帯の縁に着き（run）、
            // そこから消えながら 1.05 倍へ
            let run = min(0.12, interval * 0.4)
            impact.append(.mesh(FXMesh(shape: .arc, tex: .beam, tint: tint, alpha: 1, size: size * SIMD3<Float>(0.35, 1, 0.35),
                                       sizeEnd: size, ease: .out, life: run, fadeIn: 0.15, fadeOut: 0.85).glowing()
                .flowing(.streaks, scroll: [0, -2.4], tiling: 2, strength: 0.6, erosion: 0.2, edge: .core),
                                at: max(0, t - run), offset: [0, 0, band.lo]))
            impact.append(.mesh(FXMesh(shape: .arc, tex: .beam, tint: tint, alpha: 1, size: size,
                                       sizeEnd: size * SIMD3<Float>(1.05, 1, 1.05), ease: .out, life: 0.22, fadeIn: 0.02,
                                       fadeOut: edgeFade(1.05)).glowing()
                .flowing(.streaks, scroll: [0, -2.4], tiling: 2, strength: 0.6, erosion: 0.35, edge: .core),
                                at: t, offset: [0, 0, band.lo]))
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
    /// 範囲を示す部品: 先頭の盾面の横幅 = 突進の当たりの幅（半幅 dashWidth）、終点の輪の半径 = 同じ半幅（押し運ぶ幅）。
    private static func chargeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = s.meters("dashRange")
        let speed = s.speed("dashSpeed")
        let dashTime = speed > 0 ? L / speed : 0.67
        let half = s.meters("dashWidth")
        // 盾面（六角の盾の画像の縁 = 板の幅の 0.48 倍）の幅: 見える横の端が ±half
        let shieldWidth = half / (FXEdge.radial(.hexShield) ?? 0.48)
        r.cast = [
            // 盾を構えて踏み出す閃きと、先頭の青い盾面（突進の間、横幅 = 当たりの幅のまま）
            .emit(.flare(1.2, .core, life: 0.14), .follow, offset: [-0.3, 1.0, 0.7]),
            .mesh(FXMesh(shape: .wall, tex: .hexShield, tint: .secondary, alpha: 0.75, size: [shieldWidth, 1.0, 1],
                         sizeEnd: [shieldWidth, 1.4, 1], ease: .outBack, life: dashTime + 0.05, fadeIn: 0.08,
                         fadeOut: 0.8), .follow, offset: [0, 0.25, 0.75]),
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
            // 終点の輪: 押し運んだ幅（半径 = 当たりの半幅）に出て、消えながら少し広がる
            .mesh(edgeRing(half, .accent, life: 0.35).glowing(), at: dashTime, .target),
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

    /// 再使用（stage 1）: smashDelay で聖槌を下から振り上げ、前方の扇（半径 smashReach・±smashHalfAngle）の敵を打ち上げる（0.6 秒）。
    /// MLBB: 縦に振り上げる白金の三日月と、打ち上げた敵の上の金の爆ぜ。突進の尾（共通の cast）は出さない。
    /// 扇の縁を示す部品は無い（MLBB も地面に扇を出さない）。以前の扇の中ほどの衝撃の輪（扇の外へ 0.7m はみ出す円）は外した。
    static func recipe(_ slot: SkillSlot, stage: Int, _ s: FXSkillInfo) -> SkillFXRecipe? {
        guard slot == .skill2, stage == 1 else { return nil }
        var r = SkillFXRecipe()
        let t = s.seconds("smashDelay")
        let smashReach = s.meters("smashReach")
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
            // 地割れ
            .mesh(.decal(.crack, 3.0, .dark, life: 1.1, spin: 0, grow: 1.0, alpha: 0.8), at: t, offset: mid),
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

    /// 詠唱 ultTotal（1.0 秒）: 発動の瞬間から吸い寄せ（0〜ultPullTime）しながら掲げて集める → 崩落（ultTotal）。
    /// R = 捕まえる・崩落の半径（ultReach）。判定は発動の瞬間（捕まえる円）と崩落（爆発の円）の 2 回で、どちらも半径 R。
    /// MLBB: 範囲の円が淡い金に満ち、縁を金の光の筋が渦を巻いて内へ吸い込む → 崩落の直前に槌の上へ縦の光の筋 →
    /// 白熱の閃光 → 橙の炎の爆発と、橙に光るひびが広がる焦げ跡、白い岩の破片。
    /// 範囲を示す部品: 詠唱の間ずっと縁 = R の渦の帯、発動の瞬間に縁 = R から内へ縮む衝撃の輪、崩落の瞬間に縁 = R に出て
    /// 消えながら広がる輪 2 つと光の壁（内側の小さな輪は飾り）。
    private static func implosionRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.meters("ultReach")
        let p: Float = 0, t = s.seconds("ultTotal")
        // 掲げた槌の頭（右手・頭上）に金の光が集まる（崩落の少し前まで）
        r.cast = [
            .emit(.gather(20, radius: 1.2, .primary, life: t - 0.2), .follow, offset: [0.3, 2.5, 0.1]),
            .emit(.flare(1.8, .core, life: 0.3, tex: .flare6), at: 0.14, .follow, offset: [0.3, 2.7, 0.1]),
            .mesh(.halo(1.2, .primary, life: t, spin: 200, tex: .ringDouble), .follow, offset: [0, 0.2, 0]),
        ]
        r.impact = [
            // 0〜: 範囲が淡い金に満ち（光る柔らかい円）、縁を金の光の筋が渦を巻いて回る（模様が弧に沿って流れる）
            .mesh(.decal(.glow, R * 2.1, .primary, life: t + 0.05, spin: 0, grow: 1.0, alpha: 0.32).glowing(), at: p),
            .mesh(.halo(R, .primary, life: t + 0.05, spin: -120, tex: .beam, alpha: 1).with {
                $0.size = [R, 1, R]
                $0.ease = .linear
            }.glowing()
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
            // 範囲の縁に立ちのぼる光の壁（崩落の瞬間に半径 R、消えながら少し広がって低くなる）
            .mesh(FXMesh(shape: .cylinder, tex: .beam, tint: .primary, alpha: 0.8, size: [R, 2.0, R],
                         sizeEnd: [R * 1.06, 0.6, R * 1.06], ease: .out, life: 0.45, fadeIn: 0.02,
                         fadeOut: edgeFade(1.06)).glowing()
                .flowing(.noise, scroll: [0.4, -1.5], tiling: 2, strength: 0.6, erosion: 0.5, edge: .core), at: t),
            // 内側の白い衝撃の輪（範囲より小さい飾り）と、崩落の瞬間に縁 = R に出る金・橙の輪
            .mesh(.shockRing(R * 0.45, .core, life: 0.32).glowing(), at: t),
            .mesh(edgeRing(R, .primary, life: 0.5).glowing(), at: t),
            .mesh(edgeRing(R, flame, life: 0.7, spread: 1.15).glowing(), at: t),
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
