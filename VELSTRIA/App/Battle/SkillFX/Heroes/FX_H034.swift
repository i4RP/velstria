import Foundation
import VelstriaCore

// スキル演出: H034 鎖鉤のゴルム（Support / 先に鉤のついた太い鎖・鉄の肩当てと胸当て・大柄。MLBB の Franco の Velstria 版）。
// MLBB の画面収録 franco_sfx（2026-10-18。1108×512・30fps・62.3 px/m。docs/vfx/H034.md）に合わせた。判定・数値は Kit の値を読む
// （FXSkillInfo.kit。Tune を写さない。docs/vfx/RANGES.md）。範囲を示す部品（S2 の炎の舌の輪・外の細い赤い線）は判定の時刻に縁が判定の半径。
// 見せ場の閃き・光芒・閃光・焦げ跡・光の棘は Effekseer の効果を段に重ねる（FXCue.efk。Effects/Effekseer/Kit/H034_*.efk、
// tools/effekseer/heroes/h034_kit.py）。鎖・鉤・縮む鎖・炎の輪の縁・奥義の振りの帯は SkillFX（sim の時刻・距離と連動する部品）。
//   パッシブ 鉄鎖の執念    — 闘気がたまるたび: 両手の武器の金の光（#B48D40 / 縁 #F1DB64）。消費（命中）では何も出さない（録画どおり）
//   スキル1 鎖鉤           — 振りかぶり（hookDelay）は光らない。飛ぶ鉤は暗い鉄（#25211F・明るい所 #9DA1A0。横幅 = 判定の幅）と
//                            鋼の灰の鎖（#B6B6AF）。光の尾は無い。命中: 白い芯 → 淡い黄の棘の光芒（H034_hit_spark・約 2.2 m・0.13 秒）・
//                            小さな揺れ。その場（hookHold）は張られた鎖、引き寄せ（hookPull）の始め 0.13 秒で鎖が縮んで消える
//   スキル2 鉄鎖旋         — 振りかぶり（shockDelay）は光らない。叩きつけ: 黄の円の閃光（H034_s2_slam）→ 外向きの炎の舌の輪（SkillFX・
//                            縁 = 判定の半径・0.47 秒）と外の細い赤い線・舌の根元の黄のハイライト・内の橙の円・中心の焦げ跡と放射状のひび。
//                            被弾者は光芒（小）
//   アルティメット 狩猟鎖獄 — 掴みかかり（ultDelay）は光らない。1 撃ごと（ultInterval おき・ultHits 回）に白 → 黄の光芒（H034_hit_spark）、
//                            2〜6 撃は撃の直前に金の三日月の振り（SkillFX の帯。左の縦の振りと前の低い振りを交互）。6 撃目の 0.17 秒前から
//                            対象の足元の淡い黄緑の円・立ちのぼる黄の光の棘・暗いひび・最後の撃の閃光（H034_ult_final）
// 時刻は sim の判定の時刻（録画の撃の時刻は 0.08 秒ほど早いが、判定に合わせる）。
// SkillFXDirector は duration / count を読まない。

enum FX_H034: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 1.0, 0.89), primary: RGB(0.89, 0.75, 0.29),
                                   secondary: RGB(0.91, 0.35, 0.25), accent: RGB(0.71, 0.71, 0.69),
                                   dark: RGB(0.13, 0.12, 0.07))

    /// 鉤の頭の暗い鉄（#25211F）と、縁の明るい所（#9DA1A0）。
    private static let hookIron = FXTint.rgb(0.15, 0.13, 0.12)
    private static let hookShine = FXTint.rgb(0.62, 0.63, 0.61)
    /// 闘気の武器の金（#F1DB64）。
    private static let wildGold = FXTint.rgb(0.95, 0.86, 0.39)
    /// S2 の外の細い赤い線（#D85D4E）。
    private static let flameRed = FXTint.rgb(0.85, 0.36, 0.31)
    /// S2 の舌の根元の黄（#FDF191）。
    private static let flameTip = FXTint.rgb(0.99, 0.95, 0.57)
    /// 奥義の振りの金（#E3C04A）。明るい所（#FCF060）は加算の重なりで出る。
    private static let swingGold = FXTint.rgb(0.89, 0.75, 0.29)

    /// 鉤の手（右）と盾・鎚の手（左）の位置（術者の足元から。闘気の光）。
    private static let hookHand: SIMD3<Float> = [0.5, 1.0, 0.25]
    private static let shieldHand: SIMD3<Float> = [-0.5, 1.1, 0.25]

    /// Effekseer の効果（Effects/Effekseer/Kit/）。s2_slam は判定の半径 2.57 m で作った（倍率 = 半径 / 2.57）。
    private static let efkHitSpark = "H034_hit_spark"
    private static let efkSlam = "H034_s2_slam"
    private static let efkUltFinal = "H034_ult_final"
    private static let slamDesignRadius: Float = 2.57

    // MARK: - sim の時刻・寸法
    // Kit_H034.Tune の値は写さず、FXSkillInfo（HeroKits.fxValues）から読む（照準の表示・判定・演出が同じ値。docs/vfx/RANGES.md）:
    //   S1 hookDelay（振りかぶり → 鉤が飛び出す）・hookSpeed・hookRange・hookWidth（鉤の当たりの半幅）・hookHold（命中 → 引き寄せ）・hookPull
    //   S2 shockDelay（叩きつけ = ダメージ）・shockRadius   奥義 ultDelay（掴みかかり）・ultInterval（連撃の間隔）・ultHits

    // MARK: - 見た目の寸法（動画で測った値・推定。sim には無い）

    /// 鎖の 1 本の長さ（秒）。本数は飛行の最大（hookRange / hookSpeed）を覆う数。
    private static let chainPiece: Float = 0.14
    /// 鎖の板の幅（m）。鎖の画像の輪は板の幅の 2 割 = 約 0.1m（録画の鎖は 4〜5 px ≈ 0.07 m）。鎖は判定の幅を示さない
    /// （判定の幅 = 鉤の頭の横幅。hookHead）。
    private static let chainWidth: Float = 0.45
    /// 引き寄せの間に被弾者に付いて縮む鎖の初めの長さ（推定。命中の距離は演出から分からないので中くらいの値）。
    private static let pullLength: Float = 3.5
    /// 引き寄せの始めから鎖が消えるまで（録画: 引き寄せ 0.23 秒のうち 4 コマ = 0.13 秒で鎖が消え、対象は後から着く）。
    private static let pullChainTime: Float = 0.13
    /// S2 の炎の舌の輪の縁（FXEdge の見える縁）の、叩きつけの瞬間の大きさと消える時の大きさ（判定の半径に対する比）。
    /// 舌の先は見える縁の 1.045 倍（fx_flame_ring の画像）= 叩きつけの瞬間に 1.02R。消えながら縁 1.02R・舌の先 1.07R まで
    private static let flameEdge0: Float = 0.975
    private static let flameEdge1: Float = 1.02
    /// S2 の輪の寿命（録画: I+14 コマ = 0.47 秒で消える）と、消え始め（I+8 コマ = 0.27 秒）。
    private static let flameLife: Float = 0.47
    private static let flameFadeFrom: Float = 0.27

    // MARK: - 部品

    /// 手元から鉤まで伸びる鎖の k 本目（travel。鉤に追従）。鉤は v（m/s）なので、本の始まりの時刻 t0 の長さ 0.3 + v·t0 から
    /// chainPiece 秒で v·chainPiece だけ伸び、中心は毎秒 v/2 後ろへ退く = 前端は鉤（+0.15）、後端は手元に留まる。
    /// 鎖の輪は板に引き伸ばされる（録画の鎖も 16〜18 の輪が伸びるにつれて間隔 11 → 26 px に伸びる）。
    private static func chain(_ k: Int, speed v: Float, width: Float, _ tint: FXTint, tex: FXTex = .chain,
                              alpha: Float = 1, y: Float) -> FXCue {
        let t0 = chainPiece * Float(k)
        let l0 = 0.3 + v * t0
        let l1 = 0.3 + v * (t0 + chainPiece)
        let m = FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [l0, 1, width], sizeEnd: [l1, 1, width],
                       ease: .linear, life: chainPiece, fadeIn: 0.01, fadeOut: 0.99, yaw: 90, advance: -v / 2)
        return .mesh(m, at: t0, .follow, offset: [0, y, 0.15 - l0 / 2])
    }

    /// 鉤の頭（travel）: 暗い鉄の三日月（凸が前、2 本の返しが後ろ。録画 38 × 40 px ≈ 0.6 m）と、その下に少し大きく敷いた明るい鉄の縁。
    /// 見える横幅（縁の板）= 判定の幅（半幅 hookWidth の 2 倍。三日月の画像の上下の端は板の ±0.4 = FXEdge.linearHalfWidth(.moon)）。
    /// 板は横向き（yaw −90）なので、板の縦 = 横幅。暗い板は 0.86 倍で上に重ねる（縁が細く光って見える）。
    private static func hookHead(halfWidth: Float, life: Float) -> [FXCue] {
        let side = halfWidth / (FXEdge.linearHalfWidth(.moon) ?? 0.4)
        func plate(_ s: Float, _ tint: FXTint, y: Float) -> FXCue {
            .mesh(FXMesh(shape: .disc, tex: .moon, tint: tint, alpha: 1, size: [s, 1, s], sizeEnd: [s, 1, s], ease: .linear,
                         life: life, fadeIn: 0.02, fadeOut: 0.85, yaw: -90), .follow, offset: [0, y, 0.12])
        }
        return [plate(side, hookShine, y: 1.04), plate(side * 0.86, hookIron, y: 1.06)]
    }

    /// 命中からその場の hold 秒、術者と被弾者の間に張られた鎖（hit。線上の t の位置に piece の長さで置く。追従しない）。
    /// 引き寄せの始まりから 0.1 秒で消える（縮む鎖 pullChain と入れ替わる）。
    private static func heldChain(at t: Float, piece: Float, hold: Float) -> FXCue {
        let life = hold + 0.1
        let m = FXMesh(shape: .disc, tex: .chain, tint: .accent, alpha: 1, size: [piece, 1, chainWidth],
                       sizeEnd: [piece, 1, chainWidth], ease: .linear, life: life, fadeIn: 0.02,
                       fadeOut: hold / life, yaw: 90)
        return .mesh(m, .along(t), offset: [0, 1.0, 0])
    }

    /// 引き寄せ（命中から hold 秒後に始まる）の始めの pullChainTime 秒に、被弾者に付いて縮んで消える鎖（hit。被弾者に追従）。
    /// 被弾者側の端を保ったまま pullLength → 1.2 m（録画: 鎖は対象が着く前に消える）。
    private static func pullChain(hold: Float) -> FXCue {
        let life = pullChainTime
        let end: Float = 1.2
        let m = FXMesh(shape: .disc, tex: .chain, tint: .accent, alpha: 1, size: [pullLength, 1, chainWidth],
                       sizeEnd: [end, 1, chainWidth], ease: .linear, life: life, fadeIn: 0.15, fadeOut: 0.45, yaw: 90,
                       advance: (pullLength - end) / 2 / life)
        return .mesh(m, at: hold, .follow, offset: [0, 1.0, -pullLength / 2])
    }

    /// 円い模様の板の一辺: 見える縁（板の FXEdge.radial(tex) 倍）が半径 r になる大きさ。
    private static func edgeSize(_ r: Float, _ tex: FXTex) -> SIMD3<Float> {
        let side = r / (FXEdge.radial(tex) ?? 0.4575)
        return [side, 1, side]
    }

    /// 命中の光芒（Effekseer。白い芯 1 コマ → 淡い黄の棘の光芒 → 0.13 秒で消える。体に重ねるので 3D の上の層）。
    private static func hitSpark(_ scale: Float, _ anchor: FXAnchor = .origin, y: Float, at: Float = 0) -> FXCue {
        .efk(efkHitSpark, at: at, anchor, offset: [0, y, 0], scale: scale, onTop: true)
    }

    /// 闘気の金の光（武器の縁の光の代わり。手の位置の柔らかい光）。
    private static func handGlow(_ size: Float, life: Float, grow: Float, alpha: Float, fadeIn: Float,
                                 fadeOut: Float) -> FXMesh {
        FXMesh.sprite(.glow, size, wildGold, life: life, grow: grow, alpha: alpha).with {
            $0.fadeIn = fadeIn
            $0.fadeOut = fadeOut
        }.glowing()
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        switch slot {
        case .passive:
            // 闘気がたまるたび（毎秒）: 鉤の手と盾の手に金の光（1.05 秒。毎秒重なって光り続ける）。録画は武器の面が金になるだけで粒は無い
            let glow = handGlow(0.7, life: 1.05, grow: 1.0, alpha: 0.6, fadeIn: 0.12, fadeOut: 0.75)
            r.cast = [
                .mesh(glow, .follow, offset: hookHand),
                .mesh(glow, .follow, offset: shieldHand),
            ]
            r.hit = []
            r.fillsEmptyPhases = false
        case .skill1:
            r = hookRecipe(s)
        case .skill2:
            r = shockRecipe(s)
        case .ultimate:
            r = huntRecipe(s)
        }
        return r
    }

    // MARK: - スキル1 鎖鉤

    private static func hookRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let v = s.speed("hookSpeed")
        let range = s.meters("hookRange")
        let hold = s.seconds("hookHold")
        // 鎖の本数: 飛行の最大（射程 / 速さ）を覆う（8.23m / 15.15m/s ≈ 0.54 秒 → 0.14 秒 × 4 本）
        let flight = v > 0 ? range / v : 0.56
        let pieces = max(1, Int((flight / chainPiece).rounded(.up)))
        // 振りかぶり（hookDelay）: 録画は体を 1 回転させるだけで何も光らない（空の段を既定演出で補わせない）
        r.cast = []
        r.fillsEmptyPhases = false
        // 飛ぶ鉤（前方 = 進行方向）: 暗い鉄の鉤（光らない。横幅 = 判定の幅）・手元から伸びる鋼の鎖。光の尾は無い
        r.travel = hookHead(halfWidth: s.meters("hookWidth"), life: flight + 0.06)
            + (0..<pieces).map { chain($0, speed: v, width: chainWidth, .accent, y: 1.0) }
        // 鉤が食い込む点（録画 f207〜209）: 白い芯 → 淡い黄の棘の光芒（約 2.2 m）・カメラの小さな揺れ（約 9 px）
        r.impact = [hitSpark(1.0, y: 1.0), .shake(0.18)]
        // 被弾者（その場 hookHold → 引き寄せ）: 術者との間に張られた鋼の鎖（線上の 4 か所。4 本で射程の命中まで届く長さ）→
        // 被弾者に付いて縮んで消える鎖。スタン（命中から hookStun + hookLandStun）は共通の状態の表示（録画も文字の印だけ）
        let piece = range / 4 * 1.02
        r.hit = [0.125, 0.375, 0.625, 0.875].map { heldChain(at: $0, piece: piece, hold: hold) } + [pullChain(hold: hold)]
        return r
    }

    // MARK: - スキル2 鉄鎖旋

    /// 斧鉤を地に叩きつける（shockDelay = sim のダメージの時刻）。R = 判定の半径（shockRadius）。
    /// 範囲を示す部品（炎の舌の輪・外の細い赤い線）は叩きつけの瞬間に見える縁が R（舌の先 1.02R）、消えながら少し外へ広がる
    /// （docs/vfx/RANGES.md の縁の約束。録画の炎の輪は照準の円 2.6 m より少し内側 = 舌の先 2.5 m だが、判定に合わせた）。
    private static func shockRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.meters("shockRadius")
        let S = s.seconds("shockDelay")
        let fade = flameFadeFrom / flameLife
        // 振りかぶり（shockDelay）は録画では光らない（斧鉤を振り上げるだけ）。空の cast を既定演出（魔法陣と光）で補わせない
        r.cast = []
        r.fillsEmptyPhases = false
        // 自己中心なので発動と同時に再生される（叩きつけは S 秒後）
        r.impact = [
            // 外向きの炎の舌の輪（録画 I+1〜I+13。色は画像に焼き込み: 内縁の黄白 → 橙 → 赤の先）。縁 0.975R → 1.02R
            .mesh(FXMesh(shape: .disc, tex: .flameRing, tint: .white, alpha: 1, size: edgeSize(R * flameEdge0, .flameRing),
                         sizeEnd: edgeSize(R * flameEdge1, .flameRing), ease: .out, life: flameLife, fadeIn: 0.03,
                         fadeOut: fade), at: S),
            // 舌の根元の黄のハイライト（アルファ合成。加算は緑の地面で黄緑に寄る。内から縁へ一気に広がる = 録画の輪が 1.4 m から開く動き）
            .mesh(FXMesh(shape: .disc, tex: .flameRingCore, tint: flameTip, alpha: 0.8, size: edgeSize(R * 0.68, .flameRing),
                         sizeEnd: edgeSize(R * flameEdge1, .flameRing), ease: .out, life: 0.3, fadeIn: 0.05, fadeOut: 0.35), at: S),
            // 外の細い赤い線（録画 I+0〜I+2。判定の縁 R から 1.03R へ広がって消える）
            .mesh(FXMesh(shape: .disc, tex: .thinRing, tint: flameRed, alpha: 0.95, size: edgeSize(R, .thinRing),
                         sizeEnd: edgeSize(R * 1.03, .thinRing), ease: .out, life: 0.1, fadeIn: 0.0, fadeOut: 0.3), at: S),
            // 叩きつけの閃光・内の橙の円・焦げ跡と放射状のひび・土の筋（Effekseer。3D に隠れる）
            .efk(efkSlam, at: S, .origin, scale: R / slamDesignRadius),
            .shake(0.3, at: S),
        ]
        // 被弾者（sim のダメージ = 叩きつけの時刻に再生）: 光芒（小）。70% 鈍足 1.5 秒は共通の状態の表示
        r.hit = [hitSpark(0.8, .follow, y: 1.0)]
        return r
    }

    // MARK: - アルティメット 狩猟鎖獄

    /// 対象へ ultDelay（0.25 秒）で掴みかかり、ultSuppress の間に ultHits 回殴る（掴んだ瞬間から ultInterval おき =
    /// 0.25 / 0.57 / 0.89 / 1.21 / 1.53 / 1.85 秒）。impact は対象の位置（発動時）で再生される = 時刻は発動から。.along は術者 → 対象の線上。
    /// 判定は対象 1 体への命中だけ（範囲を持たない）。6 撃目の円は録画の飾りで、範囲を示さない。
    private static func huntRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let G = s.seconds("ultDelay") + s.seconds("ultFirst")
        let gap = s.seconds("ultInterval")
        let hits = max(2, s.count("ultHits"))
        let last = G + gap * Float(hits - 1)
        // 掴みかかり（ultDelay）は録画では光らない（1 撃目の閃きは hit）。空の cast を既定演出（光と粒）で補わせない
        r.cast = []
        r.fillsEmptyPhases = false
        var impact: [FXCue] = []
        // 2〜6 撃の直前（録画: 撃の 1〜4 コマ前）: 金の三日月の振り（加算の帯。長さ 2.4〜3.7 m・太さ 0.35〜0.4 m）。
        // 左の縦の振り（上から前の下へ）と前の低い振り（左から右）を交互。帯の頭が撃の時刻に届く
        let swings: [(radius: Float, from: Float, to: Float, height: Float, roll: Float, x: Float)] = [
            (1.5, 125, -35, 1.25, 72, -0.3), (1.6, 80, -85, 0.95, 12, 0), (1.55, 130, -30, 1.3, 80, -0.25),
            (1.65, -80, 85, 0.9, -10, 0), (1.7, 120, -45, 1.35, 85, -0.2),
        ]
        let sweep: Float = 0.09
        for (n, w) in swings.prefix(hits - 1).enumerated() {
            impact.append(.ribbon(.swing(radius: w.radius, from: w.from, to: w.to, height: w.height, roll: w.roll,
                                         duration: sweep, life: 0.13, width: 0.4, swingGold),
                                  at: G + gap * Float(n + 1) - sweep, .along(0), offset: [w.x, 0, 0.1]))
        }
        // 6 撃目（録画 C+48〜C+70）: 術者と対象の間（0.6）の淡い黄緑の円・対象から立ちのぼる黄の光の棘・暗いひび・最後の撃の閃光
        // （Effekseer。3D に隠れる。効果の前 = 術者 → 対象）
        impact += [
            .efk(efkUltFinal, at: last - 0.17, .along(0.6)),
            .shake(0.4, at: last),
        ]
        r.impact = impact
        // 1 撃ごと（sim の時刻どおり）: 白 → 淡い黄の棘の光芒（約 2.2 m）・小さな揺れ
        r.hit = [hitSpark(1.0, .follow, y: 1.1), .shake(0.1)]
        r.hitPerHit = true
        return r
    }

    // MARK: - 詠唱モーション

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 体をひねって鎖鉤を振りかぶり、0.33 秒で投げ放って構え直す（引き寄せは命中の 0.45 秒後で、モーションの後）
            m.chamber(0.14)
            m.hold(0.08) { $0.glow = 1.2; $0.torsoYaw = 0.5 }
            m.throwCast(0.14)    // 振り出し 0.22〜0.30 秒・投げ放ち 0.30〜0.36 秒（sim の鉤は 0.33 秒）
            m.hold(0.16) { $0.glow = 1.4 }
            m.chamber(0.12)
            m.hold(0.08)
        case .skill2:
            // 腰を落とし、斧鉤を頭上へ振り上げて地へ叩きつける（0.27 秒）
            m.brace(0.06, depth: 0.1)
            m.overhead(0.15)
            m.smash(0.06)
            m.hold(0.14) { $0.glow = 2.0; $0.hipsDrop = 0.2 }
            m.settle(0.14)
        case .ultimate:
            // 掴みかかって鎖で縛り、左右交互に叩き伏せる（撃は 0.25 秒から 0.32 秒おき。奥義のモーションの上限 1.7 秒に収めるため
            // 振りかぶりを短くし、5〜6 撃目は戻りの間に演出だけで見せる）
            m.brace(0.06, depth: 0.14)
            m.overhead(0.08)
            m.smash(0.06)
            m.overhead(0.14)
            m.smash(0.12)
            m.windup(0.14, side: 1, power: 1.1)
            m.slash(0.12, side: 1, power: 1.2)
            m.overhead(0.14)
            m.smash(0.12)
            m.windup(0.14, side: -1, power: 1.1)
            m.slash(0.12, side: -1, power: 1.2)
            m.settle(0.08)
        }
    }
}
