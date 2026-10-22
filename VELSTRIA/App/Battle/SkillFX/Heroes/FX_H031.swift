import Foundation
import VelstriaCore

// スキル演出: H031 氷嵐のオーリア（Arcanist / 杖は持たず氷華に覆われた右手から放つ・氷の光輪の冠・周囲に浮く氷の結晶。
// MLBB の Aurora の Velstria 版）。
// 主題: 氷の結晶と凍てつく嵐。白い芯 × 氷の水色（主）× 白青（副）× 光る縁の水色（差し色）× 深い群青（暗）。
// 氷の塊・凍った地面・冷気はアルファ合成（青い結晶 ice・霜の床 frost・水色の冷気 wind・白い冷気 mist）。加算（glowing）は
// 光る縁・光の帯・閃光・星だけ。氷の割れはコマ送り（FXSheet.iceShatter）。見た目の対応（画面収録 vid4 のコマ・色）は docs/vfx/H031.md。
// sim の実際の挙動（Systems/Kits/Kit_H031.swift の OriaTuning）に合わせたタイミング:
//   パッシブ 氷の誇り   — cast: 致命傷で凍りつく瞬間（パッシブのバッジのタイマーが始まる）に冷気が集まり、外へ傾いた氷柱 3 本・霜の床・
//                         回復のきらめき（1.5 秒）→ 1.5 秒で氷が割れて散る（コマ送り・光る縁）。再発動の準備ができた瞬間（バッジが 0 → 1）にも
//                         同じ合図が出る（演出の側では区別できない）。氷の殻そのものは状態表示（UnitVisuals の iceShell）が描く。
//                         telegraph / impact は S1 の雹のゾーンが借りる（雹のゾーンはパッシブの演出 ID。隕石と同じ円の持続ゾーン 1 つが
//                         5 回当たる）: 予告（撃った瞬間に置かれる）= 隕石の後の霜の床の上に舞う白いきらめき、着弾（撃ってから 1.03 秒）=
//                         円の中のばらばらの位置に白い氷粒が 0.15 秒おきに 5 つ落ちて砕ける（ゾーンの発動は 1 回なので、5 発の見た目は
//                         着弾の合図の中で時間をずらす）
//   スキル1 雪華の烈風 — cast: 右手を掲げて着弾点を指す（手元は小さなきらめきだけ）。telegraph（着弾点、0〜0.57 秒）: 0.06〜0.28 秒に
//                         円の縁から光る氷の刃 3 本が中心へ寄って小さな結晶になり、0.33 秒から細い氷塊が空から落ちて 0.57 秒で刺さる。
//                         impact（0.57 秒）: 白い閃光 → 氷の星が割れて散る（地面の青い結晶 + 光る白い芯）・外へ傾いた氷柱 3 本・
//                         青い霜の床（細胞のひび）と光る縁が雹の終わり（撃ってから約 1.9 秒）まで残る。被弾は鈍足 40%（1 秒）の霜の枷
//   スキル2 氷花のそよ風 — cast（扇 ±25°、射程 6.0m）: 0.2 秒に右手の横で水色の光、0.22〜0.77 秒に水色の冷気の塊（アルファ・揺らぎで
//                         縁が欠ける）と光る結晶の網目が扇の先へ流れ、0.42 秒に扇の先で白い風の筋。0.77〜1.37 秒: 扇の先の半分
//                         （術者から 2.9〜6.0m）に放射状の筋の凍った地面・扇の両辺の光る縁・外縁の氷柱 3 本。当たりは 0.26 秒で終わるが、
//                         氷の地面は 0.6 秒残る（動画）。impact は発動時・霜風のゾーン・凍結エリアのゾーン（どちらも術者の位置、向き不定）の
//                         発動で再生されるので、向きを持たない小さなきらめきだけ。telegraph（術者の足元、2 つのゾーンで 2 回）も小さなきらめき
//   アルティメット 凍てつく氷結 — cast: 右手を地へ振り下ろし、0.27 秒で照準線の上に光る霜の道（術者の 0.7m 後ろ〜6.8m 先）が一度に現れ、
//                         白い氷片が跳ねる（霜の道は弾ではなく、0.27 秒の帯の当たり。travel は実演用の小さな軌跡だけ）。
//                         telegraph（氷河のゾーンの中心 = 帯の前の端 6.2m、発動時。位置は .along で帯の中ほど）: 0.27〜1.5 秒に青い氷の板
//                         （アルファ・単色の長方形）が道の幅 1.3m から帯の幅 4.9m へ育ち、0.45 秒から道の上に光る 4 方向の星 2 つ、
//                         1.1 秒から帯の長い辺の光る縁。impact（氷河の発動 = 撃ってから 1.49 秒）: 帯が白く光り、大きな氷の板 4 枚と
//                         氷柱 3 本が突き出して割れ（コマ送り）、青い氷の床と星の跡が 0.8 秒で消える
// 氷柱（.spire）のプールは高画質で 5 本（低画質 2 本）なので、1 つの段の氷柱は 5 本まで。
// fanned で扇に並べると板の向きは扇の中心から half 度ずれるので、向きのあるメッシュは fannedRadial で放射に合わせる。

enum FX_H031: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.95, 0.99, 1.0), primary: RGB(0.36, 0.8, 0.98),
                                   secondary: RGB(0.8, 0.95, 1.0), accent: RGB(0.42, 0.88, 1.0),
                                   dark: RGB(0.02, 0.08, 0.2))

    /// 青い氷の結晶・氷の板（アルファ合成。MLBB の結晶の輪 #419BE6・氷河の板 #3383B0）。
    private static let ice = FXTint.rgb(0.27, 0.6, 0.88)
    /// 霜の床（アルファ合成。MLBB の凍った地面 #2E72AD〜#3D8DCB）。
    private static let frost = FXTint.rgb(0.2, 0.48, 0.74)
    /// 霜風の冷気の塊（アルファ合成。MLBB の霜風 #5AD2F7）。
    private static let wind = FXTint.rgb(0.45, 0.82, 0.98)
    /// 白い冷気（アルファ合成。草地・水面の上でも白く見える）。
    private static let mist = FXTint.rgb(0.86, 0.94, 1.0)
    /// 落ちてくる氷塊の影（アルファ合成）。
    private static let shadow = FXTint.rgb(0.1, 0.18, 0.32)
    /// 飛び散る氷塊（アルファ合成の破片）。
    private static let chunk = FXTint.rgb(0.72, 0.88, 1.0)

    /// 天へ掲げた右手の先（局所座標）。
    private static let raisedTip: SIMD3<Float> = [0.15, 2.2, 0.3]

    // MARK: - sim の時刻・寸法（OriaTuning と同じ値。sim の値を変えたらここも合わせる）

    /// 氷の誇りで凍りつく秒数。
    private static let prideFreeze: Float = 1.5
    /// スキル1: 氷塊が落ちるまで（17 tick）、雹の円の半径、隕石から最初の雹まで（14 tick）・雹の間隔。
    private static let meteorDelay: Float = 0.57
    private static let hailArea: Float = 1.91
    private static let hailFirst: Float = 0.47
    private static let hailEvery: Float = 0.15
    /// スキル2: 霜風が届くまで（17 tick）・払う手の振りかぶり・凍結エリアができるまで（23 tick）・凍った地面の見た目の長さ（当たりは 0.26 秒）・
    /// 中心（照準線の比 = 扇の 2.9〜6.0m の中ほど 4.46 / 6.02）・半径。
    private static let breezeDelay: Float = 0.57
    private static let breezeSwing: Float = 0.2
    private static let areaDelay: Float = 0.77
    private static let patchDuration: Float = 0.6
    private static let patchAlong: Float = 0.74
    private static let patchRadius: Float = 1.75
    /// 扇の半角（度。0.441 rad）。
    private static let breezeHalf: Float = 25.3
    /// アルティメット: 氷の道ができるまで（8 tick）・伸びきるまで・後ろの端（術者の後ろ）・長さ（−0.7〜6.8m）、
    /// 氷河の前の端（術者から = 氷河のゾーンの中心）・長さ（−0.7〜6.2m）・半幅、砕けるまで（45 tick）。
    private static let pathDelay: Float = 0.27
    private static let pathGrow: Float = 0.07
    private static let pathBack: Float = 0.7
    private static let pathLength: Float = 7.5
    private static let glacierFront: Float = 6.2
    private static let glacierLength: Float = 6.9
    private static let glacierHalf: Float = 2.45
    private static let shatter: Float = 1.5

    // MARK: - 見た目の時刻・寸法（MLBB の画面収録 vid4 で読んだ値。docs/vfx/H031.md）

    /// スキル1: 氷の刃が円の縁から中心へ寄る始まりと長さ（コマ 60〜65 = 指を離して 0.07〜0.23 秒）、
    /// 細い氷塊が空に見え始める時刻（コマ 69 = 0.37 秒）、隕石の後の霜の床の長さ（コマ 74〜約 115）。
    private static let bladeStart: Float = 0.06
    private static let bladeTime: Float = 0.22
    private static let iceFallStart: Float = 0.33
    private static let floorLife: Float = 1.35
    /// アルティメット: 霜の道の見た目の幅（照準の内側の線 ±0.48 と道の氷の縁 ±0.65 の間）、
    /// 砕けた後の氷の床が消えるまで（コマ 286〜約 310）。
    private static let pathWidth: Float = 1.3
    private static let afterLife: Float = 0.8

    // MARK: - 部品

    /// 地から突き上がる氷の結晶（尖塔、アルファ合成）。lean = 前（輪・扇に並べると外）への傾き（度）。
    private static func crystal(_ h: Float, width: Float = 0.42, _ tint: FXTint = .secondary, life: Float = 0.9,
                                lean: Float = 0, alpha: Float = 0.9) -> FXMesh {
        FXMesh(shape: .spire, tex: .shard, tint: tint, alpha: alpha, size: [width * 0.55, 0.1, width * 0.55],
               sizeEnd: [width, h, width], ease: .outBack, life: life, fadeIn: 0.03, fadeOut: 0.72, pitch: lean)
    }

    /// 空から落ちる氷塊（下を向いた結晶）。高さ y0 から落ち始め、time 秒で先端がちょうど地面に届く。
    private static func fallingIce(width: Float, length: Float, from y0: Float, time: Float) -> FXMesh {
        FXMesh(shape: .spire, tex: .shard, tint: .secondary, alpha: 0.95, size: [width, length, width],
               sizeEnd: [width, length, width], ease: .linear, life: time, fadeIn: 0.12, fadeOut: 0.94, pitch: 180,
               rise: -(y0 - length) / time)
    }

    /// 落ちてくる小さな氷粒（カメラを向く結晶の板）。
    private static func fallingShard(_ size: Float, from y0: Float, to y1: Float, time: Float,
                                     _ tint: FXTint = .core) -> FXMesh {
        FXMesh(shape: .billboard, tex: .shard, tint: tint, alpha: 1, size: SIMD3(repeating: size),
               sizeEnd: SIMD3(repeating: size), ease: .linear, life: time, fadeIn: 0.1, fadeOut: 0.9,
               rise: -(y0 - y1) / time)
    }

    /// 地面の板（中心から広がる・縮む）。大きさ（右 × 前）d0 → d1。tex = nil は単色の長方形。
    private static func groundDisc(_ tex: FXTex?, _ tint: FXTint, from d0: SIMD2<Float>, to d1: SIMD2<Float>,
                                   life: Float, alpha: Float, ease: FXEase = .out, fadeIn: Float = 0.08,
                                   fadeOut: Float = 0.6, spin: Float = 0) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [d0.x, 1, d0.y], sizeEnd: [d1.x, 1, d1.y],
               ease: ease, life: life, fadeIn: fadeIn, fadeOut: fadeOut, spin: spin)
    }

    /// 青い霜の床（アルファ合成の柔らかい円に、光る水色の細胞のひびが浮かぶ）。直径 d。
    private static func frostFloor(_ d: Float, life: Float, alpha: Float = 0.75) -> FXMesh {
        groundDisc(.glow, frost, from: [d * 0.8, d * 0.8], to: [d, d], life: life, alpha: alpha, fadeIn: 0.05, fadeOut: 0.7)
            .flowing(.cells, scroll: [0.02, -0.03], tiling: 1.4, strength: 0.75, edge: .accent)
    }

    /// n 個を前方の扇の弧（半径 r、±half 度）に右から左へ並べる（板の向きは前方 + 回した角度。粒子・カメラを向く板用）。
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

    /// メッシュ n 枚を前方の扇の弧（半径 r、±half 度、高さ y）に、扇の要から外を向けて（放射状に）並べる。
    private static func fannedRadial(_ m: FXMesh, _ n: Int, radius r: Float, half: Float, at: Float = 0, y: Float = 0,
                                     every: Float = 0) -> FXCue {
        var m = m
        m.yaw -= half
        return fanned(.mesh(m, at: at, offset: [0, y, 0]), n, radius: r, half: half, every: every)
    }

    /// n 個を中心の周りに散らす（黄金角 137.5° ずつ回しながら、半径を r0 から dr ずつ広げる。向きは外向き）。
    private static func scattered(_ c: FXCue, _ n: Int, from r0: Float, step dr: Float, every: Float = 0) -> FXCue {
        var c = c
        c.offset.z += r0
        c.stepOffset = [0, 0, dr]
        c.count = n
        c.every = every
        c.stepYaw = 137.5
        c.orbit = 0.0001
        return c
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        switch slot {
        case .passive: return prideRecipe(s)
        case .skill1: return hailstoneRecipe(s)
        case .skill2: return breezeRecipe(s)
        case .ultimate: return glacierRecipe(s)
        }
    }

    // MARK: - パッシブ 氷の誇り（+ スキル1 の雹）

    private static func prideRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let t = prideFreeze
        let R = hailArea
        // 凍りつく（動画に無い。推定）: 白い閃光と集まる冷気 → 外へ傾いた氷柱 3 本の牢・霜の床・回復のきらめき（1.5 秒）→ 割れて散る
        r.cast = [
            .emit(.flare(1.8, .core, life: 0.18, tex: .flare4), .follow, offset: [0, 1.1, 0]),
            .emit(.gather(16, radius: 1.1, .accent, life: 0.3), .follow, offset: [0, 1.0, 0]),
            .mesh(crystal(1.8, width: 0.5, ice, life: t, lean: 18, alpha: 0.8), .follow)
                .ringed(3, radius: 0.5, every: 0.03),
            .mesh(frostFloor(2.8, life: t + 0.25), .follow),
            .emit(.motes(14, radius: 0.5, .secondary, life: 0.9).with { $0.emit = t - 0.3 }, .follow, offset: [0, 0.5, 0]),
            // 1.5 秒: 氷が割れて散る（アルファの結晶片）と、光る縁
            .emit(.sheet(.iceShatter, 2.4, .secondary, end: ice, life: 0.5, additive: false), at: t, .follow,
                  offset: [0, 1.0, 0]),
            .emit(.flutter(.shard, 14, radius: 0.5, .core, speed: 5, life: 0.8, size: 0.2).with { $0.additive = false },
                  at: t, .follow, offset: [0, 1.0, 0]),
            .mesh(.shockRing(1.3, .accent, life: 0.3, tex: .shockwave, alpha: 0.7).glowing(), at: t, .follow),
        ]
        // 雹の予告（撃った瞬間に置かれる）: 隕石の後の霜の床の上に、雹の間ずっと白いきらめきが舞う（コマ 95・101 の白い粒）
        r.telegraph = [
            .emit(.motes(12, radius: R * 0.8, .core, life: 0.8, size: 0.08, rise: 0.6).with {
                $0.emit = 0.6
                $0.shape = .disc(R * 0.85)
            }, at: meteorDelay + 0.3, offset: [0, 0.3, 0], quality: 1),
        ]
        // 雹の着弾: 円の中のばらばらの位置（0.3〜1.5m）に白い氷粒が 0.12 秒で落ちて砕ける（0.15 秒おきに 5 つ。コマ 87・91・95…）。
        // 当たりは円全体（ゾーンの 5 回の適用）。ゾーンの発動の合図は 1 回だけなので、ここで時間をずらして 5 つ見せる
        r.impact = [
            scattered(.mesh(fallingShard(0.5, from: 2.6, to: 0.3, time: 0.12), offset: [0, 2.6, 0]), 5,
                      from: R * 0.16, step: R * 0.16, every: hailEvery),
            scattered(.emit(.sheet(.iceShatter, 1.1, .core, end: .secondary, life: 0.4, additive: false), at: 0.1,
                            offset: [0, 0.35, 0]), 5, from: R * 0.16, step: R * 0.16, every: hailEvery),
        ]
        // パッシブのダメージは無い（雹の被弾はスキル1 の hit）。既定の被弾演出で補われないよう小さな合図だけ置く
        r.hit = [.mesh(.halo(0.4, .secondary, life: 0.3, spin: 120, tex: .ring), .follow, offset: [0, 0.2, 0])]
        return r
    }

    // MARK: - スキル1 雪華の烈風

    /// 0.57 秒で細い氷塊が落ちて刺さり、氷の星が割れて散る（R = 隕石の半径 1.91m）。
    private static func hailstoneRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 2.2)
        let t = meteorDelay
        let fall = t - iceFallStart
        // 右手を掲げて着弾点を指す（MLBB は手元にほとんど光が無い。コマ 59〜64）
        r.cast = [
            .emit(.flare(0.8, .accent, life: 0.14, tex: .flare4), at: 0.05, offset: raisedTip),
            .emit(.motes(6, radius: 0.2, .secondary, life: 0.5), at: 0.03, offset: raisedTip),
        ]
        // 着弾点: 円の縁から光る氷の刃 3 本が中心へ寄り（水平に寝かせた菱形が縁 → 0.45m）、小さな結晶になって割れる。
        // 0.33 秒から細い氷塊が空から落ち（影が広がる）、0.57 秒で地面に刺さる
        r.telegraph = [
            .mesh(FXMesh(shape: .disc, tex: .shard, tint: .accent, alpha: 0.95, size: [0.32, 1, 1.7], sizeEnd: [0.42, 1, 1.0],
                         ease: .out, life: bladeTime, fadeIn: 0.12, fadeOut: 0.7, advance: -(R - 0.45) / bladeTime).glowing()
                .flowing(.streaks, scroll: [0, -2], tiling: 1, strength: 0.5, edge: .core),
                  at: bladeStart, offset: [0, 0.75, 0]).ringed(3, radius: R, every: 0.02),
            .emit(.sheet(.iceShatter, 1.3, .secondary, end: ice, life: 0.3, additive: false), at: bladeStart + bladeTime - 0.02,
                  offset: [0, 0.8, 0]),
            .mesh(groundDisc(.glow, shadow, from: [0.4, 0.4], to: [R * 1.3, R * 1.3], life: fall + 0.03, alpha: 0.5,
                             ease: .in, fadeIn: 0.3, fadeOut: 0.9), at: iceFallStart),
            .mesh(fallingIce(width: 0.35, length: 2.4, from: 7, time: fall), at: iceFallStart, offset: [0, 7, 0]),
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: .accent, count: 8, emit: fall * 0.7, life: 0.25, size: 0.13,
                         shape: .disc(0.35), dir: .down, speed: 20, stretch: 3.5, fade: .linearFadeOut),
                  at: iceFallStart, offset: [0, 6, 0]),
        ]
        // 0.57 秒: 白い閃光 → 氷の星が割れて散る（地面に寝かせた青い結晶 + 光る白い芯）・外へ傾いた氷柱 3 本、
        // 青い霜の床（細胞のひび）と光る縁が雹の終わりまで残る
        r.impact = [
            .mesh(.sprite(.glowHard, 2.4, .core, life: 0.12, grow: 1.4).glowing(), offset: [0, 0.8, 0]),
            .emit(.sheet(.iceShatter, R * 2.2, ice, end: .secondary, life: 0.55, additive: false, orient: .ground),
                  offset: [0, 0.25, 0]),
            .emit(.sheet(.iceShatter, R * 1.4, .core, end: .accent, life: 0.32), offset: [0, 0.9, 0]),
            .mesh(crystal(1.5, width: 0.55, ice, life: 0.75, lean: 38, alpha: 0.85), at: 0.02)
                .ringed(3, radius: R * 0.45, every: 0.02),
            .mesh(frostFloor(R * 2.4, life: floorLife), at: 0.03),
            .mesh(groundDisc(.shockwave, .accent, from: [R * 1.7, R * 1.7], to: [R * 2.04, R * 2.04], life: floorLife,
                             alpha: 0.55, fadeIn: 0.04, fadeOut: 0.7).glowing(), at: 0.03),
            .emit(.flutter(.shard, 14, radius: 0.4, .core, speed: 6, life: 0.7, size: 0.18).with { $0.additive = false },
                  offset: [0, 0.6, 0]),
            .emit(.sheet(.smokePuff, 1.6, mist, count: 3, life: 0.9, additive: false, radius: R * 0.5), at: 0.04,
                  offset: [0, 0.4, 0], quality: 1),
            .shake(0.15),
        ]
        // 鈍足 40%（1 秒）: 白い命中の閃き・散る氷片・足元の霜の枷
        r.hit = [
            .emit(.sheet(.hitFlash, 1.3, .core, end: .accent, life: 0.18), offset: [0, 1.0, 0]),
            .emit(.flutter(.shard, 6, radius: 0.3, .secondary, speed: 2.5, life: 0.6, size: 0.12).with { $0.additive = false },
                  offset: [0, 0.9, 0]),
            .mesh(.halo(0.5, .secondary, life: 1.0, spin: 60, tex: .ring), .follow, offset: [0, 0.12, 0]),
        ]
        return r
    }

    // MARK: - スキル2 氷花のそよ風

    /// 扇（±25°・6.0m）へ水色の冷気が 0.57 秒で届き（右手を払うのは 0.2 秒）、0.77 秒に扇の先の半分に凍った地面ができて 0.6 秒残る。
    private static func breezeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = min(s.range, 7.0)
        let w = breezeSwing
        let a = areaDelay
        // 凍った地面の中ほど（術者から 4.46m）と奥行き（2.9〜6.0m）
        let mid = L * patchAlong
        let depth = L * 2 * (1 - patchAlong)
        r.cast = [
            // 0.2 秒: 右手を横へ払う水色の光（コマ 167）
            .emit(.bloom(0.9, .accent, life: 0.2, grow: 1.4), at: w, offset: [0.45, 1.0, 0.25]),
            // 0.22〜0.77 秒: 水色の冷気の塊（アルファ。揺らぎの模様が前へ流れ、縁が欠ける）が扇の先へ流れる（コマ 169〜177）
            .mesh(FXMesh(shape: .disc, tex: .smoke, tint: wind, alpha: 0.9, size: [1.0, 1, 1.2], sizeEnd: [L * 0.72, 1, L * 0.58],
                         ease: .out, life: 0.55, fadeIn: 0.08, fadeOut: 0.5, advance: L * 1.3)
                .flowing(.noise, scroll: [0, -1.6], tiling: 1.5, strength: 0.6, erosion: 0.45, edge: .core),
                  at: w + 0.02, offset: [0, 0.35, 0.9]),
            // 冷気の中の光る結晶の網目（加算。細胞のひびだけが残り、縁から欠ける）
            .mesh(FXMesh(shape: .disc, tex: .glow, tint: .accent, alpha: 0.75, size: [0.8, 1, 1.0], sizeEnd: [L * 0.6, 1, L * 0.5],
                         ease: .out, life: 0.45, fadeIn: 0.06, fadeOut: 0.5, advance: L * 1.4).glowing()
                .flowing(.cells, scroll: [0, -1.2], tiling: 1.2, strength: 0.8, erosion: 0.35, edge: .core),
                  at: w + 0.04, offset: [0, 0.4, 0.9]),
            // 扇に吹く風の筋・氷のきらめき・白い冷気
            .emit(.fan(18, .accent, speed: 15, spread: 22, life: 0.4, tex: .streak, size: 0.13), at: w + 0.02,
                  offset: [0, 0.9, 0.5]),
            .emit(FXEmit(tex: .shard, tint: .core, tintEnd: .accent, count: 16, emit: 0.2, life: 0.45, size: 0.18,
                         sizeVar: 0.4, grow: 0.7, shape: .sphere(0.3), dir: .forward, speed: 13, speedVar: 0.35, spread: 22,
                         drag: 1.2, angleVar: 180, spin: 500, spinVar: 300, fade: .linearFadeOut), at: w + 0.02,
                  offset: [0, 0.8, 0.5]),
            .emit(.sheet(.smokePuff, 1.6, mist, count: 5, life: 0.6, additive: false).with {
                $0.shape = .sphere(0.3); $0.dir = .forward; $0.speed = 10; $0.speedVar = 0.3; $0.spread = 20; $0.drag = 1.6
                $0.emit = 0.15
            }, at: w + 0.01, offset: [0, 0.5, 0.6], quality: 1),
            // 0.42 秒: 扇の先の白い風の筋（光る。筋が前へ流れて欠ける。コマ 175〜181）
            fannedRadial(FXMesh.ray(.streak, length: 2.8, width: 2.4, .core, life: 0.33, alpha: 0.9).glowing()
                .flowing(.streaks, scroll: [-2.5, 0], tiling: 1.5, strength: 0.5, erosion: 0.3, edge: .accent),
                         3, radius: L * 0.76, half: 15, at: breezeDelay - 0.15, y: 0.3, every: 0.02),
            // 0.77〜1.37 秒: 扇の先の半分の凍った地面（放射状の筋）・扇の両辺の光る縁・外縁の氷柱・きらめきと冷気（コマ 183〜200）
            fannedRadial(groundDisc(.glow, frost, from: [2.0, 3.6], to: [2.5, depth * 1.4], life: patchDuration, alpha: 0.8,
                                    fadeIn: 0.06, fadeOut: 0.7)
                .flowing(.streaks, scroll: [0, -0.3], tiling: 1.4, strength: 0.75, edge: .accent),
                         3, radius: mid, half: 17, at: a),
            fannedRadial(FXMesh.ray(.streak, length: depth + 0.5, width: 1.4, .accent, life: patchDuration - 0.05, alpha: 0.85)
                .with { $0.size = $0.sizeEnd; $0.fadeIn = 0.08; $0.fadeOut = 0.6 }.glowing(),
                         2, radius: mid, half: breezeHalf, at: a, y: 0.03),
            fannedRadial(crystal(1.1, width: 0.4, ice, life: patchDuration - 0.1, lean: 25), 3, radius: L * 0.9, half: 16,
                         at: a + 0.02, every: 0.03),
            .emit(.sheet(.sparkTwinkle, 0.35, .core, count: 6, life: 0.6, radius: depth * 0.45), at: a + 0.03,
                  .along(patchAlong), offset: [0, 0.4, 0]),
            .emit(.sheet(.smokePuff, 1.4, mist, count: 3, life: 0.8, additive: false, radius: depth * 0.4), at: a + 0.02,
                  .along(patchAlong), offset: [0, 0.3, 0], quality: 1),
        ]
        // 霜風と凍結エリアのゾーン（どちらも術者の足元、向き不定）が作られた瞬間: 足元の小さなきらめき
        r.telegraph = [
            .emit(.motes(4, radius: 0.35, .secondary, life: 0.45), offset: [0, 0.3, 0]),
        ]
        // 発動時・霜風の発動・凍結エリアの発動（どちらも術者の位置）で再生される: 向きを持たない小さなきらめき
        r.impact = [
            .emit(.motes(5, radius: 0.35, .accent, life: 0.5), offset: [0, 0.9, 0]),
        ]
        // 霜風・凍った地面の被弾（凍結の氷の殻は状態表示が描く）: 白い命中の閃き・氷片・足元のひび
        r.hit = [
            .emit(.sheet(.hitFlash, 1.2, .core, end: .accent, life: 0.18), offset: [0, 1.0, 0]),
            .emit(.flutter(.shard, 8, radius: 0.35, .secondary, speed: 3, life: 0.6, size: 0.14).with { $0.additive = false },
                  offset: [0, 1.0, 0]),
            .mesh(.decal(.crack, 1.4, .secondary, life: 1.0, spin: 0, grow: 1.0, alpha: 0.7)),
        ]
        return r
    }

    // MARK: - アルティメット 凍てつく氷結

    /// 光る霜の道（0.27 秒に一度に現れる）→ 青い氷の板が帯の幅へ育つ（〜1.5 秒）→ 砕ける（1.49 秒のゾーンの発動）。
    /// G = 氷河の半幅 2.45m、帯は術者の 0.7m 後ろから 6.2m 先。
    private static func glacierRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let G = min(s.radius, glacierHalf)
        let len = pathLength
        let p = pathDelay
        let t = shatter
        // 氷河のゾーンの中心は帯の前の端（glacierFront）。帯の中ほど（術者から (6.2 − 0.7) / 2）を .along で指す
        let mid = FXAnchor.along((glacierFront - glacierLength / 2) / glacierFront)
        // 霜の道の光る帯（横長の筋の画像は高さの 16% だけが帯なので、幅を割り戻す）。両端は画像で薄れるので少し長く置く
        let rayLength = len + 1.1
        r.cast = [
            .emit(.gather(14, radius: 0.8, .accent, life: 0.16), offset: [0.15, 1.8, 0.3]),
            .emit(.bloom(1.0, .accent, life: 0.2, grow: 1.5), at: p - 0.08, offset: [0.2, 0.5, 0.6]),
            // 0.27 秒: 光る霜の道（筋の模様が前へ流れ、縁が欠ける。コマ 249〜252）
            .mesh(FXMesh.ray(.streak, length: rayLength, width: pathWidth / 0.16, .accent, life: 0.5, alpha: 0.95).with {
                $0.size = $0.sizeEnd; $0.fadeIn = 0.03; $0.fadeOut = 0.35
            }.glowing().flowing(.streaks, scroll: [-3, 0], tiling: 2, strength: 0.6, erosion: 0.3, edge: .core),
                  at: p, offset: [0, 0.03, (len - 2 * pathBack) / 2 + 0.05]),
            // 道から跳ねる白い氷片（アルファ）
            .emit(FXEmit(tex: .shard, tint: .core, tintEnd: .secondary, count: 16, life: 0.6, size: 0.14, sizeVar: 0.5,
                         grow: 0.8, shape: .line(len), dir: .up, speed: 3.5, speedVar: 0.5, spread: 50, gravity: 10, drag: 0.5,
                         angleVar: 180, spin: 300, spinVar: 300, fade: .linearFadeOut, additive: false),
                  at: p + 0.02, offset: [0, 0.15, len / 2 - pathBack]),
        ]
        // 霜の道は弾ではないので travel は再生されない（目視確認の実演の偽の弾だけ）。既定の軌跡で補われないよう 1 つだけ置く
        r.travel = [.emit(.trail(.twinkle, .secondary, rate: 30, life: 0.4, size: 0.15), .follow, offset: [0, 0.8, 0])]
        r.telegraph = [
            // 0.27〜1.5 秒: 青い氷の板（アルファ・単色の長方形）が道の幅から帯の幅 4.9m へ育つ（コマ 254〜285）
            .mesh(groundDisc(nil, ice, from: [pathWidth, glacierLength], to: [G * 2, glacierLength], life: t - p + 0.06,
                             alpha: 0.55, ease: .linear, fadeIn: 0.03, fadeOut: 0.95), at: p, mid),
            // 板の中の氷の面（淡い細胞のひび。アルファ）
            .mesh(groundDisc(.glow, .secondary, from: [pathWidth * 1.6, glacierLength * 1.2], to: [G * 2.6, glacierLength * 1.3],
                             life: t - p + 0.03, alpha: 0.35, ease: .linear, fadeIn: 0.1, fadeOut: 0.9)
                .flowing(.cells, scroll: [0.01, -0.04], tiling: 1.5, strength: 0.8, edge: .accent), at: p + 0.03, mid),
            // 0.45 秒〜: 道の上の光る 4 方向の星（術者から 4.3m・1.7m。コマ 256〜282）
            .mesh(groundDisc(.flare4, .accent, from: [0.6, 0.6], to: [3.4, 3.4], life: t - 0.45 + 0.08, alpha: 0.9,
                             ease: .outBack, fadeIn: 0.1, fadeOut: 0.85).glowing(), at: 0.45, offset: [0, 0.02, -1.9])
                .repeated(2, every: 0.12, step: [0, 0, -2.6]),
            // 1.1 秒〜: 帯の長い辺の光る縁（最大の幅 ±2.45m。コマ 274〜285）
            .mesh(FXMesh.ray(.streak, length: glacierLength + 0.6, width: 1.4, .accent, life: t - 1.1 + 0.08, alpha: 0.8).with {
                $0.size = $0.sizeEnd; $0.fadeIn = 0.55; $0.fadeOut = 0.85
            }.glowing(), at: 1.1, mid, offset: [G - 0.05, 0.03, 0]).repeated(2, step: [-(G - 0.05) * 2, 0, 0]),
            // 板の上に舞う白いきらめき
            .emit(.rising(16, radius: G * 0.8, .core, speed: 1.0, life: 0.8, tex: .twinkle).with {
                $0.emit = 0.9
                $0.shape = .box([G * 1.6, 0.1, glacierLength * 0.85])
            }, at: p + 0.2, mid, quality: 1),
        ]
        // 1.49 秒（氷河の発動）: 帯が白く光り、大きな氷の板と氷柱が突き出して割れる（コマ 286〜294）→ 青い氷の床と星の跡（〜コマ 310）
        r.impact = [
            .mesh(groundDisc(.glow, .core, from: [G * 2.2, glacierLength * 1.15], to: [G * 2.5, glacierLength * 1.3],
                             life: 0.3, alpha: 0.75, fadeIn: 0.02, fadeOut: 0.25).glowing(), mid, offset: [0, 0.02, 0]),
            // 白青の菱形の氷の板 4 枚（アルファ。帯の中ほどから外へ傾いて突き出す）と、帯の軸の氷柱 3 本
            scattered(.mesh(FXMesh(shape: .wall, tex: .shard, tint: .secondary, alpha: 0.8, size: [1.0, 0.5, 1],
                                   sizeEnd: [1.6, 2.7, 1], ease: .outBack, life: 0.6, fadeIn: 0.03, fadeOut: 0.55, pitch: 14),
                            mid), 4, from: 0.9, step: 0.55, every: 0.02),
            .mesh(crystal(2.4, width: 0.75, .secondary, life: 0.65, lean: 15, alpha: 0.85), at: 0.02,
                  offset: [0, 0, -0.9]).repeated(3, every: 0.04, yaw: 120, step: [0, 0, -2.2]),
            // 砕けた後の青い氷の床と星の跡（0.8 秒で消える）
            .mesh(groundDisc(nil, ice, from: [G * 2, glacierLength], to: [G * 2, glacierLength], life: afterLife, alpha: 0.5,
                             ease: .linear, fadeIn: 0.02, fadeOut: 0.4), mid),
            .mesh(groundDisc(.flare4, .secondary, from: [4.2, 4.2], to: [4.6, 4.6], life: afterLife, alpha: 0.6,
                             fadeIn: 0.05, fadeOut: 0.5), mid, offset: [0, 0.03, 0]),
            // 氷の割れのコマ送り（アルファの結晶 + 光る白い芯）・飛び散る氷片と氷塊・白い冷気
            .emit(.sheet(.iceShatter, 2.8, .secondary, end: ice, count: 4, life: 0.6, additive: false, radius: G), mid,
                  offset: [0, 0.8, 0]),
            .emit(.sheet(.iceShatter, 3.2, .core, end: .accent, count: 2, life: 0.35, radius: G * 0.6), mid,
                  offset: [0, 1.0, 0]),
            .emit(.flutter(.shard, 30, radius: G * 0.8, .core, speed: 7, life: 1.0, size: 0.22).with {
                $0.additive = false
                $0.shape = .box([G * 1.8, 0.4, glacierLength * 0.9])
            }, mid, offset: [0, 0.8, 0]),
            .emit(.debris(18, speed: 8, chunk, size: 0.2, tex: .shard).with {
                $0.shape = .box([G * 1.8, 0.1, glacierLength * 0.9])
            }, mid),
            .emit(.sheet(.smokePuff, 2.4, mist, count: 4, life: 1.2, additive: false, radius: G), at: 0.04, mid,
                  offset: [0, 0.5, 0], quality: 1),
            .shake(0.5),
        ]
        // 道の鈍足 80%・砕けの凍結（氷の殻は状態表示）: 白い命中の閃き（コマ 249・286 の白い姿）・氷片・足元のひび
        r.hit = [
            .emit(.sheet(.hitFlash, 1.6, .core, end: .accent, life: 0.2), offset: [0, 1.0, 0]),
            .emit(.flutter(.shard, 10, radius: 0.35, .secondary, speed: 4, life: 0.7, size: 0.15).with { $0.additive = false },
                  offset: [0, 1.0, 0]),
            .mesh(.decal(.crack, 1.5, .secondary, life: 1.2, spin: 0, grow: 1.0, alpha: 0.75)),
        ]
        return r
    }

    // MARK: - 詠唱モーション

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 右手を天へ掲げて冷気を空へ放ち、着弾点へ振り下ろして指す（氷塊は 0.57 秒で落ちる）。0.48 + 戻り 0.25 = 0.73 秒
            m.command(0.14)
            m.push(0.08, high: 0.2)
            m.hold(0.26) { $0.glow = 1.8 }
        case .skill2:
            // 右手を右へ振りかぶり、0.2 秒で横へ払って霜風を扇へ吹かせる（0.57 秒で届くまで右手に冷気を纏う）。0.66 + 0.25 = 0.91 秒
            m.windup(0.18, side: 1, power: 0.8)
            m.slash(0.08, side: 1, power: 1.0)
            m.hold(0.3) { $0.glow = 1.8 }
            m.settle(0.1)
        case .ultimate:
            // 右手を地へ振り下ろし（0.27 秒で氷の道）、氷河が育つ間は右手を天へ掲げて冷気を集め、1.5 秒の砕けへ向けて前へ突き出す。
            // 1.32 + 戻り 0.35 = 1.67 秒（上限 1.7 秒。突き出しは砕けの少し前）
            m.plant(0.08)
            m.hold(0.18) { $0.glow = 2.0; $0.ring = 1.2 }
            m.raise(0.24, glow: 2.4)
            m.hold(0.7) { $0.ring = 1.6; $0.glow = 2.6 }
            m.push(0.08, high: 0.25)
            m.hold(0.04)
        }
    }
}
