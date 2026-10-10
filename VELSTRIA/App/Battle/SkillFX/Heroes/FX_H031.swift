import Foundation
import VelstriaCore

// スキル演出: H031 氷嵐のオーリア（Arcanist / 氷の杖・氷の冠・周囲に浮く氷の結晶。MLBB の Aurora の Velstria 版）。
// 主題: 氷の結晶と凍てつく嵐。白い芯 × 氷青（主）× 白青（副）× 淡い紫（差し色）× 深い群青（暗）+ 白い冷気（アルファ合成の霧）。
// 上から見下ろすカメラで「空から氷塊が落ちて結晶が咲く」「扇へ吹く霜風と、扇の先の凍った地面」「前へ走る氷の道が氷河に育って砕ける」
// 「致命傷で自分を氷に閉じ込める」が読めるよう、全周の輪を主役にせず、落ちる氷塊・外へ傾いて咲く氷柱・扇の前線・道に並ぶ結晶で形を見せる。
// sim の実際の挙動（Systems/Kits/Kit_H031.swift の OriaTuning）に合わせたタイミング:
//   パッシブ 氷の誇り   — cast: 致命傷で凍りつく瞬間（パッシブのバッジのタイマーが始まる）に、外へ傾いた氷柱 3 本・凍った地面・冷気の渦・
//                         回復の光（1.5 秒）→ 1.5 秒で氷が砕ける。再発動の準備ができた瞬間（バッジが 0 → 1）にも同じ合図が出る（結晶が咲く）。
//                         氷の殻そのものは状態表示（UnitVisuals の iceShell）が描く。
//                         telegraph / impact は S1 の雹 5 つのゾーンが借りる（雹のゾーンはパッシブの演出 ID）: 予告 = 落ちる場所の小さな霜の輪、
//                         着弾（0.7〜1.1 秒）= 小さな氷粒が上から落ちて砕ける
//   スキル1 氷塊と雹   — cast: 杖を天へ掲げて冷気を空へ放つ。telegraph（着弾点、0〜0.5 秒）: 縮む霜の輪と広がる影、空から下を向いた巨大な
//                         氷塊が落ちてくる（0.5 秒でちょうど地面に刺さる）。impact（0.5 秒）: 氷の結晶 4 本が外へ傾いて咲き、氷のひび・冷気・
//                         氷片が散る。被弾は鈍足 40%（1 秒）の霜の枷
//   スキル2 霜風       — cast（扇 ±37°、射程 6.5m）: 杖を横へ払い、0〜0.3 秒で霜風の前線（扇の弧）が扇の端まで走る。氷片・風の筋・白い冷気が
//                         扇に吹き、0.22 秒で扇の中に結晶がきらめく。0.3〜2.1 秒: 扇の先（術者から 5.4m = 照準線の 0.83）に凍った地面
//                         （氷の格子・ひび・外へ傾いた氷柱 4 本）。impact は発動時・霜風のゾーン（術者の位置、向き不定）・凍った地面の発動で
//                         再生されるので、向きを持たない小さな霜のきらめきにした。telegraph（術者の足元と凍った地面の中心）も小さな冷気の波紋だけ
//   アルティメット 氷河 — cast: 杖を地に突き立て、0〜0.35 秒で照準線の上に霜の帯が伸びる（氷の道 22m/s × 7.7m に合わせて前へ伸びる）。
//                         travel: 道の先頭の氷の結晶と、通り道に残る結晶（約 1 秒残る）。telegraph（氷河の中心 = 術者から 4.5m、発動時）:
//                         0.05〜1.2 秒に氷の格子が半径 3.6m へ広がり、道に沿って氷柱 5 本が順に育ち、周りに結晶がきらめき、0.85 秒から冷気が
//                         中心へ集まる → 1.2 秒（ゾーンの遅れ）で砕ける（閃光・細い衝撃の輪・ひび・飛び散る氷片と氷塊・跳ね上がる結晶・冷気）。
//                         impact は道の最初の命中と氷河の発動で再生されるので小さな閃きだけ（砕けは telegraph の at: 1.2）
// 氷柱（.spire）のプールは高画質で 5 本（低画質 2 本）なので、1 つの段の氷柱は 5 本まで。

enum FX_H031: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.95, 0.99, 1.0), primary: RGB(0.35, 0.75, 1.0),
                                   secondary: RGB(0.78, 0.93, 1.0), accent: RGB(0.7, 0.6, 1.0),
                                   dark: RGB(0.02, 0.08, 0.2))

    /// 白い冷気（アルファ合成。草地・水面の上でも白く見える）。
    private static let mist = FXTint.rgb(0.86, 0.94, 1.0)
    /// 落ちてくる氷塊の影（アルファ合成）。
    private static let shadow = FXTint.rgb(0.1, 0.18, 0.32)
    /// 飛び散る氷塊（アルファ合成の破片）。
    private static let chunk = FXTint.rgb(0.72, 0.88, 1.0)

    /// 天へ掲げた杖の先（局所座標）。
    private static let raisedTip: SIMD3<Float> = [0.15, 2.2, 0.3]

    // MARK: - sim の時刻・寸法（OriaTuning と同じ値。sim の値を変えたらここも合わせる）

    /// 氷の誇りで凍りつく秒数。
    private static let prideFreeze: Float = 1.5
    /// スキル1: 氷塊が落ちるまで。
    private static let meteorDelay: Float = 0.5
    /// スキル2: 霜風が届くまで・凍った地面の持続・中心（照準線の比 = (650 − 110) / 650）・半径。
    private static let breezeDelay: Float = 0.3
    private static let patchDuration: Float = 1.8
    private static let patchAlong: Float = 0.83
    private static let patchRadius: Float = 1.9
    /// 扇の半角（度。0.65 rad）。
    private static let breezeHalf: Float = 37
    /// アルティメット: 氷の道の長さ・所要（770 / 2200）、氷河の中心（術者から）・半径・砕けるまで。
    private static let pathLength: Float = 7.7
    private static let pathTime: Float = 0.35
    private static let glacierCenter: Float = 4.5
    private static let glacierRadius: Float = 3.6
    private static let shatter: Float = 1.2

    // MARK: - 部品

    /// 地から突き上がる氷の結晶（尖塔）。lean = 前（輪に並べると外）への傾き（度）。
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

    /// 地面の模様（中心から広がる・縮む）。直径 d0 → d1。
    private static func groundSheet(_ tex: FXTex, _ tint: FXTint, from d0: SIMD2<Float>, to d1: SIMD2<Float>,
                                    life: Float, alpha: Float, ease: FXEase = .out, fadeIn: Float = 0.08,
                                    fadeOut: Float = 0.6, spin: Float = 0) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [d0.x, 1, d0.y], sizeEnd: [d1.x, 1, d1.y],
               ease: ease, life: life, fadeIn: fadeIn, fadeOut: fadeOut, spin: spin)
    }

    /// 霜風の前線（水平の半円の帯を扇の幅へ絞る。外縁が明るく両端へ薄れる）。半径 r0 → r1。
    private static func breezeFront(from r0: Float, to r1: Float, _ tint: FXTint, life: Float, alpha: Float = 0.9) -> FXMesh {
        let squash = sin(breezeHalf * .pi / 180) * 1.05
        return FXMesh(shape: .arc, tex: .beam, tint: tint, alpha: alpha, size: [r0 * squash, 1, r0],
                      sizeEnd: [r1 * squash, 1, r1], ease: .linear, life: life, fadeIn: 0.04, fadeOut: 0.8)
    }

    /// n 個を前方の扇の弧（半径 r、±half 度）に右から左へ並べる。
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
        // 凍りつく: 白い閃光 → 外へ傾いた氷柱 3 本が氷の牢を作り、足元が凍って冷気が渦巻く。回復の光が 1.5 秒立ちのぼる
        r.cast = [
            .emit(.flare(2.2, .core, life: 0.2, tex: .flare6), .follow, offset: [0, 1.1, 0]),
            .mesh(crystal(1.9, width: 0.5, .secondary, life: t, lean: 18, alpha: 0.85), .follow)
                .ringed(3, radius: 0.5, every: 0.03),
            .mesh(.decal(.crack, 2.6, .secondary, life: t + 0.2, spin: 0, grow: 1.0, alpha: 0.8), .follow),
            .mesh(groundSheet(.hexShield, .primary, from: [1.0, 1.0], to: [2.2, 2.2], life: t + 0.1, alpha: 0.45), .follow),
            .emit(.smoke(10, radius: 0.7, mist, life: 1.3, size: 0.9).with { $0.vortex = 2.5; $0.speed = 0.6 }, .follow,
                  quality: 1),
            .emit(.motes(16, radius: 0.55, .secondary, life: 1.0).with { $0.emit = t - 0.3 }, .follow, offset: [0, 0.5, 0]),
            // 1.5 秒: 氷が砕けて解ける
            .emit(.flare(1.8, .core, life: 0.18, tex: .flare4), at: t, .follow, offset: [0, 1.0, 0]),
            .emit(.flutter(.shard, 16, radius: 0.5, .secondary, speed: 5, life: 0.8, size: 0.2), at: t, .follow,
                  offset: [0, 1.0, 0]),
            .mesh(.shockRing(1.3, .secondary, life: 0.3, tex: .ring), at: t, .follow),
        ]
        // 雹の予告（落ちる場所に小さな霜の輪。氷塊の 0.2〜0.6 秒後に落ちる）
        r.telegraph = [
            .mesh(groundSheet(.ripple, .secondary, from: [0.5, 0.5], to: [1.7, 1.7], life: 1.0, alpha: 0.55,
                              fadeIn: 0.3, fadeOut: 0.8, spin: 30)),
        ]
        // 雹の着弾: 小さな氷粒が上から落ちて（0.1 秒）砕ける
        r.impact = [
            .mesh(fallingShard(0.55, from: 2.5, to: 0.25, time: 0.1), offset: [0, 2.5, 0]),
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: .secondary, count: 3, life: 0.12, size: 0.16, shape: .sphere(0.15),
                         dir: .down, speed: 20, stretch: 3, fade: .linearFadeOut), offset: [0, 2.6, 0]),
            .emit(.flutter(.shard, 8, radius: 0.2, .secondary, speed: 3.5, life: 0.5, size: 0.13), at: 0.08,
                  offset: [0, 0.25, 0]),
            .mesh(.shockRing(0.75, .secondary, life: 0.22, tex: .ring), at: 0.08),
            .mesh(.decal(.crack, 1.3, .secondary, life: 0.8, spin: 0, grow: 1.0, alpha: 0.7), at: 0.08),
        ]
        // パッシブのダメージは無い（雹の被弾はスキル1 の hit）。既定の被弾演出で補われないよう小さな合図だけ置く
        r.hit = [.mesh(.halo(0.4, .secondary, life: 0.3, spin: 120, tex: .ring), .follow, offset: [0, 0.2, 0])]
        return r
    }

    // MARK: - スキル1 氷塊と雹

    /// 0.5 秒で巨大な氷塊が落ちて刺さり、結晶が咲く（R = 氷塊の半径 1.7m）。
    private static func hailstoneRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 2.2)
        let t = meteorDelay
        // 杖を天へ掲げ、冷気の筋を空へ放つ
        r.cast = [
            .emit(.gather(12, radius: 0.6, .secondary, life: 0.14), offset: raisedTip),
            .emit(.flare(1.3, .core, life: 0.16, tex: .flare6), at: 0.1, offset: raisedTip),
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: .secondary, count: 8, emit: 0.1, life: 0.3, size: 0.12,
                         shape: .sphere(0.2), dir: .up, speed: 14, stretch: 3, fade: .linearFadeOut), at: 0.08, offset: raisedTip),
        ]
        // 着弾点: 縮む霜の輪と広がる影。空から下を向いた氷塊（+ 小さな氷粒 2 つ）が落ち、0.5 秒で地面に刺さる
        r.telegraph = [
            .mesh(groundSheet(.ripple, .secondary, from: [R * 2.7, R * 2.7], to: [R * 1.5, R * 1.5], life: t + 0.02,
                              alpha: 0.7, ease: .in, fadeIn: 0.2, fadeOut: 0.88, spin: 45)),
            .mesh(groundSheet(.glow, shadow, from: [0.4, 0.4], to: [R * 1.5, R * 1.5], life: t + 0.02, alpha: 0.55,
                              ease: .in, fadeIn: 0.3, fadeOut: 0.92)),
            .mesh(fallingIce(width: 0.75, length: 1.9, from: 9, time: t), offset: [0, 9, 0]),
            .mesh(fallingShard(0.7, from: 8.4, to: 0.5, time: t), offset: [0.5, 8.4, 0.25]),
            .mesh(fallingShard(0.55, from: 7.8, to: 0.4, time: t, .secondary), offset: [-0.45, 7.8, -0.2]),
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: .primary, count: 12, emit: 0.36, life: 0.3, size: 0.13,
                         shape: .disc(0.6), dir: .down, speed: 18, stretch: 3.5, fade: .linearFadeOut), offset: [0, 6.5, 0]),
            .emit(.gather(14, radius: R * 0.9, .secondary, life: 0.45), offset: [0, 0.2, 0]),
        ]
        // 0.5 秒: 結晶が外へ傾いて咲き、地面が凍りつく
        r.impact = [
            .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), offset: [0, 0.8, 0]),
            .mesh(crystal(2.2, width: 0.6, .core, life: 1.0, alpha: 0.9)),
            .mesh(crystal(1.4, width: 0.45, .primary, life: 0.95, lean: 30), at: 0.02).ringed(3, radius: 0.55, every: 0.02),
            .mesh(.decal(.crack, R * 2.4, .secondary, life: 1.2, spin: 0, grow: 1.0, alpha: 0.8)),
            .mesh(groundSheet(.glow, .secondary, from: [R * 1.6, R * 1.6], to: [R * 2.4, R * 2.4], life: 1.1, alpha: 0.45,
                              fadeIn: 0.05)),
            .mesh(.shockRing(R * 1.15, .core, life: 0.28, tex: .ring)),
            .emit(.flutter(.shard, 16, radius: 0.4, .secondary, speed: 6, life: 0.7, size: 0.18), offset: [0, 0.6, 0]),
            .emit(.debris(10, speed: 6, chunk, size: 0.16, tex: .shard), offset: [0, 0.2, 0]),
            .emit(.smoke(8, radius: R * 0.6, mist, life: 0.9, size: 0.9), quality: 1),
            .shake(0.15),
        ]
        // 鈍足 40%（1 秒）: 足元の霜の枷と、散る氷片
        r.hit = [
            .emit(.sparks(8, speed: 4, .core, end: .secondary), offset: [0, 1.0, 0]),
            .emit(.flutter(.shard, 6, radius: 0.3, .secondary, speed: 2, life: 0.6, size: 0.12), offset: [0, 0.9, 0]),
            .mesh(.halo(0.5, .secondary, life: 1.0, spin: 60, tex: .ring), .follow, offset: [0, 0.12, 0]),
        ]
        return r
    }

    // MARK: - スキル2 霜風

    /// 扇（±37°・6.5m）へ霜風が 0.3 秒で届き、扇の先に凍った地面が 1.8 秒残る。
    private static func breezeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = min(s.range, 7.0)
        let t = breezeDelay
        let patch = FXAnchor.along(patchAlong)
        let P = patchRadius
        r.cast = [
            // 杖を払う閃き
            .emit(.flare(1.1, .core, life: 0.14), offset: [0.4, 1.4, 0.5]),
            // 霜風の前線（0〜0.3 秒で扇の端へ）と、少し遅れて追う白い芯
            .mesh(breezeFront(from: 0.8, to: L * 1.05, .secondary, life: t + 0.04), at: 0.02),
            .mesh(breezeFront(from: 0.5, to: L * 0.85, .core, life: t, alpha: 0.75), at: 0.06),
            // 扇に吹く風の筋・氷片・白い冷気
            .emit(.fan(26, .secondary, speed: 24, spread: 34, life: 0.32, tex: .streak, size: 0.14), at: 0.04,
                  offset: [0, 1.1, 0.5]),
            .emit(FXEmit(tex: .shard, tint: .core, tintEnd: .primary, count: 22, emit: 0.12, life: 0.4, size: 0.2,
                         sizeVar: 0.4, grow: 0.7, shape: .sphere(0.3), dir: .forward, speed: 18, speedVar: 0.35, spread: 32,
                         drag: 1.2, angleVar: 180, spin: 500, spinVar: 300, fade: .linearFadeOut), at: 0.04,
                  offset: [0, 1.0, 0.5]),
            .emit(FXEmit(tex: .smoke, tint: mist, count: 14, emit: 0.12, life: 0.55, size: 0.7, sizeVar: 0.4, grow: 3.0,
                         shape: .sphere(0.3), dir: .forward, speed: 15, spread: 30, drag: 1.6, angleVar: 180, spin: 40,
                         fade: .gradualFadeInOut, additive: false), at: 0.03, offset: [0, 0.6, 0.6], quality: 1),
            // 前線が過ぎた扇の中で結晶がきらめく
            fanned(.mesh(.sprite(.shard, 0.8, .core, life: 0.4, grow: 1.3, alpha: 0.95), at: 0.2, offset: [0, 0.5, 0]),
                   3, radius: L * 0.62, half: 22, every: 0.02),
            // 0.3〜2.1 秒: 扇の先の凍った地面（氷の格子・ひび・外へ傾いた氷柱・立ちのぼる冷気）
            .mesh(groundSheet(.hexShield, .primary, from: [P * 1.3, P * 1.3], to: [P * 2.05, P * 2.05],
                              life: patchDuration + 0.05, alpha: 0.45, fadeIn: 0.06, fadeOut: 0.78), at: t, patch),
            .mesh(.decal(.crack, P * 2.0, .secondary, life: patchDuration + 0.05, spin: 0, grow: 1.0, alpha: 0.85), at: t, patch),
            .mesh(crystal(1.0, width: 0.34, .secondary, life: patchDuration - 0.2, lean: 22), at: t, patch)
                .ringed(4, radius: P * 0.55, every: 0.04),
            .emit(.rising(12, radius: P * 0.8, .secondary, speed: 1.2, life: 1.0, tex: .shard).with { $0.emit = 1.3 },
                  at: t + 0.02, patch, quality: 1),
        ]
        // 霜風のゾーン（術者の足元、向き不定）と凍った地面の中心で、作られた瞬間に小さな冷気の波紋
        r.telegraph = [
            .mesh(groundSheet(.ripple, .secondary, from: [0.6, 0.6], to: [2.2, 2.2], life: 0.4, alpha: 0.5, fadeIn: 0.1,
                              fadeOut: 0.5)),
        ]
        // 発動時・霜風の発動（術者の位置）・凍った地面の発動で再生される: 向きを持たない小さな霜のきらめき
        r.impact = [
            .emit(.flare(1.0, .secondary, life: 0.16, tex: .flare4), offset: [0, 1.0, 0]),
            .emit(.flutter(.shard, 8, radius: 0.35, .secondary, speed: 2.5, life: 0.6, size: 0.12), offset: [0, 0.9, 0]),
        ]
        // 霜風・凍った地面の被弾（凍結の氷の殻は状態表示が描く）
        r.hit = [
            .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.0, 0]),
            .emit(.flutter(.shard, 8, radius: 0.35, .secondary, speed: 3, life: 0.6, size: 0.14), offset: [0, 1.0, 0]),
            .mesh(.decal(.crack, 1.4, .secondary, life: 1.0, spin: 0, grow: 1.0, alpha: 0.7)),
            .emit(.smoke(5, radius: 0.35, mist, life: 0.8, size: 0.6), quality: 1),
        ]
        return r
    }

    // MARK: - アルティメット 氷河

    /// 氷の道（0〜0.35 秒）→ 氷河が育つ（〜1.2 秒）→ 砕ける（1.2 秒）。G = 氷河の半径 3.6m。
    private static func glacierRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let G = min(s.radius, 4.0)
        let len = pathLength
        let z0 = -glacierCenter
        let t = shatter
        // 杖を地に突き立てる → 照準線の上に霜の帯が前へ伸び（氷の道の先頭に合わせる）、氷河が砕けるまで残る
        r.cast = [
            .emit(.gather(18, radius: 1.0, .secondary, life: 0.16), offset: [0.15, 1.8, 0.3]),
            .emit(.flare(2.0, .core, life: 0.22, tex: .flare6), at: 0.06, offset: [0.2, 0.6, 0.7]),
            .mesh(.decal(.crack, 2.2, .secondary, life: 0.8, spin: 0, grow: 1.0, alpha: 0.75), at: 0.06, offset: [0.2, 0, 0.7]),
            .mesh(FXMesh(shape: .disc, tex: .streak, tint: .secondary, alpha: 0.8, size: [0.4, 1, 1.4], sizeEnd: [len, 1, 1.4],
                         ease: .linear, life: pathTime, fadeIn: 0.05, fadeOut: 0.95, yaw: 90,
                         advance: (len - 0.4) / 2 / pathTime), offset: [0, 0.02, 0.4]),
            .mesh(.ray(.streak, length: len, width: 1.6, .secondary, life: t - pathTime + 0.1, alpha: 0.75).with {
                $0.fadeIn = 0.02; $0.fadeOut = 0.8; $0.size = $0.sizeEnd
            }, at: pathTime - 0.02, offset: [0, 0.02, len / 2 + 0.2]),
        ]
        // 道の先頭の氷の結晶と、通り道に残る結晶（約 1 秒）
        r.travel = [
            .mesh(.sprite(.shard, 1.0, .core, life: pathTime + 0.05, grow: 1.0, alpha: 1).with { $0.fadeOut = 0.85 }, .follow,
                  offset: [0, 0.6, 0]),
            .emit(.trail(.glow, .primary, rate: 70, life: 0.35, size: 0.9), .follow, offset: [0, 0.4, 0]),
            .emit(FXEmit(tex: .shard, tint: .core, tintEnd: .secondary, rate: 70, life: 1.0, size: 0.38, sizeVar: 0.4,
                         shape: .disc(0.7), dir: .up, speed: 0.4, angleVar: 25, fade: .gradualFadeInOut), .follow,
                  offset: [0, 0.35, 0]),
        ]
        // 氷河（中心 = 術者から 4.5m）: 0.05〜1.2 秒に育ち、1.2 秒で砕ける
        r.telegraph = [
            .mesh(groundSheet(.hexShield, .secondary, from: [G * 0.8, G * 1.0], to: [G * 1.95, G * 2.05], life: t + 0.05,
                              alpha: 0.5, fadeIn: 0.25, fadeOut: 0.85), at: 0.05),
            .mesh(.decal(.crack, G * 1.9, .primary, life: t - 0.1, spin: 0, grow: 1.0, alpha: 0.55), at: 0.15),
            // 道に沿って氷柱が順に育つ（術者から 1.1 / 2.6 / 4.1 / 5.6 / 7.1m）
            .mesh(crystal(2.2, width: 0.62, .secondary, life: 0.85, alpha: 0.85), at: 0.3, offset: [0, 0, z0 + 1.1])
                .repeated(5, every: 0.06, step: [0, 0, 1.5]),
            // 氷河の縁にきらめく結晶
            .mesh(.sprite(.shard, 0.9, .core, life: 0.7, grow: 1.15, alpha: 0.9), at: 0.5, offset: [0, 0.5, 0])
                .ringed(6, radius: G * 0.62, every: 0.03),
            .emit(.rising(20, radius: G * 0.8, .secondary, speed: 1.4, life: 0.9, tex: .shard).with { $0.emit = 0.7 }, at: 0.3,
                  quality: 1),
            .emit(.gather(24, radius: G * 0.9, .core, life: 0.35), at: t - 0.35, offset: [0, 0.6, 0]),
            // 1.2 秒: 砕ける
            .emit(.flare(3.4, .core, life: 0.3, tex: .flare6), at: t, offset: [0, 1.2, 0]),
            .mesh(groundSheet(.glow, .core, from: [G * 1.4, G * 1.6], to: [G * 2.2, G * 2.4], life: 0.45, alpha: 0.6,
                              fadeIn: 0.02, fadeOut: 0.3), at: t),
            .mesh(.shockRing(G * 1.05, .core, life: 0.35, tex: .ring), at: t),
            .mesh(.decal(.crack, G * 2.1, .primary, life: 1.3, spin: 0, grow: 1.0, alpha: 0.85), at: t),
            .mesh(FXMesh(shape: .billboard, tex: .shard, tint: .core, alpha: 1, size: SIMD3(repeating: 1.2),
                         sizeEnd: SIMD3(repeating: 0.5), ease: .out, life: 0.45, fadeIn: 0.02, fadeOut: 0.5, rise: 5),
                  at: t, offset: [0, 0.6, 0]).ringed(4, radius: G * 0.35),
            .emit(.flutter(.shard, 34, radius: G * 0.6, .secondary, speed: 7, life: 1.0, size: 0.22), at: t, offset: [0, 0.8, 0]),
            .emit(.debris(22, speed: 9, chunk, size: 0.2, tex: .shard).with { $0.shape = .disc(G * 0.7) }, at: t),
            .emit(.sparks(28, speed: 11, .core, end: .secondary, life: 0.45), at: t, offset: [0, 0.8, 0]),
            .emit(.smoke(12, radius: G * 0.6, mist, life: 1.4, size: 1.3).with { $0.speed = 3 }, at: t + 0.02, quality: 1),
            .shake(0.5, at: t),
        ]
        // 道の最初の命中・氷河の発動: 小さな閃き（砕けは telegraph）
        r.impact = [
            .emit(.flare(1.4, .core, life: 0.18, tex: .flare4), offset: [0, 0.8, 0]),
            .emit(.flutter(.shard, 8, radius: 0.4, .secondary, speed: 3, life: 0.6, size: 0.14), offset: [0, 0.8, 0]),
        ]
        // 道の鈍足 80%・砕けの凍結（氷の殻は状態表示）
        r.hit = [
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
            .emit(.flutter(.shard, 10, radius: 0.35, .secondary, speed: 4, life: 0.7, size: 0.15), offset: [0, 1.0, 0]),
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
            // 杖を天へ掲げて冷気を空へ放ち、着弾点へ振り下ろして指す（氷塊は 0.5 秒で落ちる）
            m.command(0.1)
            m.push(0.07, high: 0.2)
            m.hold(0.15) { $0.glow = 1.8 }
        case .skill2:
            // 杖を右から横へ払い、霜風を扇へ吹かせる（0.3 秒で届くまで杖に冷気を纏う）
            m.windup(0.09, side: 1, power: 0.8)
            m.slash(0.08, side: 1, power: 1.0)
            m.hold(0.14) { $0.glow = 1.8 }
            m.settle(0.1)
        case .ultimate:
            // 杖を地に突き立てて氷の道を走らせ、氷河が育つ間は杖を天へ掲げて冷気を集め、1.2 秒の砕けへ向けて前へ突き出す
            m.plant(0.08)
            m.hold(0.25) { $0.glow = 2.0; $0.ring = 1.2 }
            m.raise(0.22, glow: 2.4)
            m.hold(0.5) { $0.ring = 1.6; $0.glow = 2.6 }
            m.push(0.08, high: 0.25)
            m.hold(0.08)
        }
    }
}
