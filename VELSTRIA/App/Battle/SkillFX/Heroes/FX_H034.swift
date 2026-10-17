import Foundation
import VelstriaCore

// スキル演出: H034 鎖鉤のゴルム（Support / 先に鉤のついた太い鎖・鉄の肩当てと胸当て・大柄。MLBB の Franco の Velstria 版）。
// 主題: 光らない鉄の鎖と鉤、当たった瞬間だけ白 → 淡い黄の閃き。S2 は地を這う橙の炎の輪、奥義は金の振りの軌跡と金の円。
// 白い芯 × 金（主 = 闘気・奥義の振り）× 炎の橙（副 = S2）× 鋼の灰（差し色 = 鎖）× 煤（暗 = 焦げ跡）。
// MLBB の画面収録（docs/vfx/H034.md）: 鎖と鉤は暗い鉄のまま光の尾を引かない。命中は白い閃光 → 淡い黄の放射の閃き（約 0.1 秒）。
// S2 は淡い黄白の円が一瞬満ち、橙の炎の舌が内向きに並ぶ輪（外に細い赤い線）が広がって消え、中心に焦げた地割れ。
// 奥義は鎖で縛る演出が無く、殴るたびに金の三日月の振りと命中の閃き、6 撃目の直前に足元へ金の円と昇る金の光条・焦げたひび。
// 闘気（パッシブ）は両手の武器の縁が金に光る。
// sim の実際の挙動（Systems/Kits/Kit_H034.swift の Tune）に合わせたタイミング:
//   パッシブ 鉄鎖の執念    — 5 秒無被弾のあと闘気が 1 秒に 1 つたまる（バッジのスタックが増えるたび = 毎秒）: 鉤の手と盾の手に金の光
//                            （1.05 秒。毎秒重なって光り続ける）。闘気はスキルのダメージが当たった時に消費する
//                            （sim: 鉤の命中・S2 の叩きつけ・奥義の 6 撃目。外れたら残る）。消費（バッジが 0 に戻る）が発動から 0.6 秒以内
//                            （S2・近い鉤）なら passiveRelease: 両手の金の光が膨らんで散る（大きさは消費した闘気の数に比例）。
//                            遠い鉤・奥義の消費は Director の窓（kitReleaseWindow）の外なので出ない
//   スキル1 鎖鉤           — 0.33 秒の振りかぶり（体をひねって鎖を回す。MLBB は光らない）の後に、射程 8.23m・15.15m/s（最大 0.54 秒）の
//                            非貫通の鉤。暗い赤茶の鉄の鉤と、手元 → 鉤まで伸びる鋼の鎖（travel。発射から。0.14 秒ずつの 4 本が鉤に追従しながら
//                            伸びる。命中・消滅で追従が切れると、残りの本は出ない）。命中点（impact）: 白い閃光 → 淡い黄の放射の閃き・火花。
//                            被弾者（hit）: その場の 0.45 秒は術者と被弾者の間に張られた鎖（線上の 4 か所に置く）、引き寄せ（0.25 秒）の間は
//                            被弾者に付いて縮む鎖。スタンの表示は共通の状態の表示に任せる
//   スキル2 鉄鎖旋         — 自身中心（半径 2.57m）。0.27 秒の振りかぶりで斧鉤を地に叩きつける（sim のダメージも 0.27 秒。hit はダメージの時刻）:
//                            淡い黄白の円の閃光 → 橙に変わる内側・内向きの炎の舌の輪（加算・筋の模様が内へ流れて欠ける）・外の細い赤い線・
//                            輪の上の小さな炎・中心の焦げた地割れ。被弾者は白 → 淡い黄の閃き（70% 鈍足 1.5 秒は共通の状態の表示）
//   アルティメット 狩猟鎖獄 — 対象指定（縁まで 1.88m。その場で拘束）→ 0.25 秒で掴みかかり、1.8 秒の拘束の間に 6 回殴る（0.25 + 0.32n 秒）。
//                            impact（対象の位置。発動の時に再生）: 2〜5 撃の 0.07 秒前に左右交互の金の三日月（加算）、6 撃目（1.85 秒）の
//                            0.25 秒前に縦の振り上げ、0.17 秒前から足元（術者と対象の間）の金の円・昇る金の光条・焦げたひび、6 撃目の白い閃光。
//                            hit（1 撃ごと・sim の時刻どおり）は白 → 淡い黄の閃きと火花
// 時刻と寸法は MLBB の画面収録で測った値（docs/kits/Franco.md「動画で測った値（2026-10-16）」、見た目の対応は docs/vfx/H034.md）。
// 光る部品（閃光・命中の閃き・炎の輪・金の三日月・金の円・闘気の光）は加算（glowing / 粒子の加算）。鎖・鉤・焦げ跡はアルファ合成。
// SkillFXDirector は duration / count を読まない。

enum FX_H034: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.98, 0.86), primary: RGB(0.95, 0.8, 0.18),
                                   secondary: RGB(0.97, 0.44, 0.2), accent: RGB(0.7, 0.67, 0.58),
                                   dark: RGB(0.13, 0.11, 0.07))

    /// 鉤の頭（暗い赤茶の鉄。動画 f110 の鉤）。
    private static let hookIron = FXTint.rgb(0.36, 0.22, 0.18)
    /// 命中の白い閃光（f119 #F9F8E9）と、その次のコマの淡い黄の放射の閃き（f120〜121 #FBF6B8 / #FCEE98）。
    private static let flashWhite = FXTint.rgb(0.98, 0.97, 0.91)
    private static let starburst = FXTint.rgb(0.99, 0.94, 0.62)
    /// S2 の叩きつけの淡い黄白の円（f194 #FCFABE）、炎の舌の明るい先（f198 #FFD378）、外の細い赤い線（f196）。
    private static let slamFlash = FXTint.rgb(0.99, 0.98, 0.75)
    private static let flameTip = FXTint.rgb(1.0, 0.83, 0.47)
    private static let flameRed = FXTint.rgb(0.88, 0.25, 0.16)
    /// 奥義の 6 撃目の金の円（f350〜352 #EFED81 / #F1F184）。
    private static let paleGold = FXTint.rgb(0.94, 0.92, 0.5)

    /// 鉤の手（右）と盾・鎚の手（左）の位置（術者の足元から。闘気の光）。
    private static let hookHand: SIMD3<Float> = [0.5, 1.0, 0.25]
    private static let shieldHand: SIMD3<Float> = [-0.5, 1.1, 0.25]

    // MARK: - sim の時刻・寸法（Kit_H034.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 振りかぶりの長さ（hookDelay。発動 → 鉤が飛び出す）、鉤の速さ（m/s）。
    private static let launch: Float = 0.33
    private static let hookSpeed: Float = 15.15
    /// 命中から引き寄せが始まるまで（hookHold）、引き寄せの所要（hookPull）、命中から動けない時間の合計（hookStun + hookLandStun）。
    private static let holdTime: Float = 0.45
    private static let pullTime: Float = 0.25
    private static let stunTotal: Float = 1.3
    /// 鎖の 1 本の長さ（秒）と本数（4 本 = 0.56 秒 ≧ 最大の飛行 8.23m / 15.15m/s ≈ 0.54 秒）。
    private static let chainPiece: Float = 0.14
    /// スキル2: 叩きつけの時刻（shockDelay。モーションの振り下ろし = sim のダメージ）。
    private static let slam: Float = 0.27
    /// アルティメット: 掴みかかり（ultDelay）、拘束（ultSuppress）、連撃の間隔（ultInterval）。
    private static let grab: Float = 0.25
    private static let suppress: Float = 1.8
    private static let strikeGap: Float = 0.32

    // MARK: - 見た目の寸法（動画で測った値・推定。sim には無い）

    /// 鎖の板の幅（m）。鎖の画像の輪は板の幅の 2 割 = 約 0.1m（動画の鎖は画面で 6 px ≈ 0.1m）。
    private static let chainWidth: Float = 0.5
    /// その場の 0.45 秒に張る鎖の 1 本の長さ（線上の 4 か所に置く。4 本 × 2.1m で射程 8.23m の命中まで届く）。
    private static let holdPiece: Float = 2.1
    /// 引き寄せの間に被弾者に付いて縮む鎖の初めの長さ（推定。命中の距離は演出から分からないので中くらいの値）。
    private static let pullLength: Float = 3.5
    /// 奥義の 6 撃目の金の円の半径（動画 f350〜355 の幅 約 250 px ≈ 4.0m）。
    private static let finaleRadius: Float = 2.0

    // MARK: - 部品

    /// 手元から鉤まで伸びる鎖の k 本目（travel。鉤に追従）。鉤は hookSpeed（m/s）なので、本の始まりの時刻 t0 の長さ 0.3 + v·t0 から
    /// chainPiece 秒で v·chainPiece だけ伸び、中心は毎秒 v/2 後ろへ退く = 前端は鉤（+0.15）、後端は手元に留まる。
    private static func chain(_ k: Int, width: Float, _ tint: FXTint, tex: FXTex = .chain, alpha: Float = 1,
                              y: Float) -> FXCue {
        let t0 = chainPiece * Float(k)
        let l0 = 0.3 + hookSpeed * t0
        let l1 = 0.3 + hookSpeed * (t0 + chainPiece)
        let m = FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [l0, 1, width], sizeEnd: [l1, 1, width],
                       ease: .linear, life: chainPiece, fadeIn: 0.01, fadeOut: 0.99, yaw: 90, advance: -hookSpeed / 2)
        return .mesh(m, at: t0, .follow, offset: [0, y, 0.15 - l0 / 2])
    }

    /// 命中からその場の 0.45 秒、術者と被弾者の間に張られた鎖（hit。線上の t の位置に holdPiece の長さで置く。追従しない）。
    /// 引き寄せの始まりから 0.1 秒で消える（縮む鎖 pullChain と入れ替わる）。
    private static func heldChain(at t: Float) -> FXCue {
        let life = holdTime + 0.1
        let m = FXMesh(shape: .disc, tex: .chain, tint: .accent, alpha: 1, size: [holdPiece, 1, chainWidth],
                       sizeEnd: [holdPiece, 1, chainWidth], ease: .linear, life: life, fadeIn: 0.02,
                       fadeOut: holdTime / life, yaw: 90)
        return .mesh(m, .along(t), offset: [0, 1.0, 0])
    }

    /// 引き寄せ（pullTime）の間に被弾者に付いて縮む鎖（hit。被弾者に追従）。被弾者側の端を保ったまま pullLength → 0.6m。
    private static func pullChain() -> FXCue {
        let life = pullTime + 0.02
        let m = FXMesh(shape: .disc, tex: .chain, tint: .accent, alpha: 1, size: [pullLength, 1, chainWidth],
                       sizeEnd: [0.6, 1, chainWidth], ease: .linear, life: life, fadeIn: 0.08, fadeOut: 0.75, yaw: 90,
                       advance: (pullLength - 0.6) / 2 / life)
        return .mesh(m, at: holdTime, .follow, offset: [0, 1.0, -pullLength / 2])
    }

    /// 命中の閃き: 白い閃光（1 コマ）→ 淡い黄の放射の閃き（約 0.2 秒で欠けて消える）。
    private static func hitBurst(_ size: Float, y: Float) -> [FXCue] {
        [
            .emit(.flare(size * 0.7, flashWhite, life: 0.08, tex: .glowHard), offset: [0, y, 0]),
            .emit(.sheet(.hitFlash, size, starburst, end: .primary, life: 0.2), at: 0.02, offset: [0, y, 0]),
        ]
    }

    /// 闘気の金の光（武器の縁の光の代わり。手の位置の柔らかい光）。
    private static func handGlow(_ size: Float, life: Float, grow: Float, alpha: Float, fadeIn: Float,
                                 fadeOut: Float) -> FXMesh {
        FXMesh.sprite(.glow, size, .primary, life: life, grow: grow, alpha: alpha).with {
            $0.fadeIn = fadeIn
            $0.fadeOut = fadeOut
        }.glowing()
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        switch slot {
        case .passive:
            // 闘気がたまるたび（毎秒）: 鉤の手と盾の手に金の光（1.05 秒。毎秒重なって光り続ける）と小さなきらめき
            let glow = handGlow(0.75, life: 1.05, grow: 1.0, alpha: 0.7, fadeIn: 0.15, fadeOut: 0.7)
            r.cast = [
                .mesh(glow, .follow, offset: hookHand),
                .mesh(glow, .follow, offset: shieldHand),
                .emit(.motes(5, radius: 0.25, .primary, life: 0.8, size: 0.07, rise: 0.6), .follow, offset: hookHand),
            ]
            r.hit = []
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
        // 振りかぶり（0.33 秒）: MLBB は体をひねって鉤を後ろへ回すだけで光らない。投げ放つ瞬間の鎖の振りの細い鋼の弧（アルファ）だけ
        r.cast = [
            .mesh(.slash(0.9, .accent, from: 110, to: -30, life: 0.16, tex: .slashThin).with { $0.alpha = 0.55 },
                  at: launch - 0.07, offset: [0, 1.2, 0.2]),
        ]
        // 飛ぶ鉤（前方 = 進行方向）: 暗い赤茶の鉄の鉤（凸が前、爪が後ろ。光らない）・手元から伸びる鋼の鎖 4 本。光の尾は無い
        r.travel = [
            .mesh(FXMesh(shape: .disc, tex: .moon, tint: hookIron, alpha: 1, size: [0.6, 1, 0.6], sizeEnd: [0.6, 1, 0.6],
                         ease: .linear, life: 0.6, fadeIn: 0.02, fadeOut: 0.85, yaw: -90), .follow, offset: [0, 1.05, 0.12]),
            chain(0, width: chainWidth, .accent, y: 1.0),
            chain(1, width: chainWidth, .accent, y: 1.0),
            chain(2, width: chainWidth, .accent, y: 1.0),
            chain(3, width: chainWidth, .accent, y: 1.0),
        ]
        // 鉤が食い込む点（f119〜122）: 白い閃光 → 淡い黄の放射の閃き（約 2m）・橙〜赤の短い火花・小さな揺れ
        r.impact = hitBurst(2.1, y: 1.0) + [
            .emit(.sparks(10, speed: 6, flameTip, end: flameRed), at: 0.03, offset: [0, 1.0, 0]),
            .shake(0.15),
        ]
        // 被弾者（その場 0.45 秒 → 引き寄せ 0.25 秒）: 術者との間に張られた鋼の鎖（線上の 4 か所）→ 被弾者に付いて縮む鎖。
        // スタン（命中から 1.3 秒）は共通の状態の表示（MLBB も頭上の共通の印だけ）
        r.hit = [heldChain(at: 0.125), heldChain(at: 0.375), heldChain(at: 0.625), heldChain(at: 0.875), pullChain(),
                 .emit(.sparks(6, speed: 4, flameTip, end: flameRed), offset: [0, 1.0, 0])]
        return r
    }

    // MARK: - スキル2 鉄鎖旋

    /// 斧鉤を地に叩きつける（0.27 秒）。R = 範囲の半径（2.57m）。MLBB の炎の輪は照準より内側（2.1〜2.4m）。
    private static func shockRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 3.0)
        let S = slam
        // 振りかぶり（0.27 秒）は MLBB では光らない（斧鉤を振り上げるだけ）。空の cast を既定演出（魔法陣と光）で補わせない
        r.cast = []
        r.fillsEmptyPhases = false
        // 自己中心なので発動と同時に再生される（叩きつけは S 秒後）
        r.impact = [
            // 叩きつけの瞬間（f194）: 範囲の内側が淡い黄白に満ちる閃光（加算）。次のコマから内側が橙に（groundGlow の色の変化）
            .mesh(FXMesh(shape: .disc, tex: .glow, tint: slamFlash, alpha: 1, size: [R * 1.5, 1, R * 1.5],
                         sizeEnd: [R * 1.9, 1, R * 1.9], ease: .out, life: 0.16, fadeIn: 0.02, fadeOut: 0.35).glowing(), at: S),
            .emit(.groundGlow(R * 0.85, slamFlash, life: 0.42).with { $0.tintEnd = .secondary }, at: S + 0.02,
                  offset: [0, 0.03, 0]),
            // 内向きの炎の舌の輪（f196〜207）: 帯の外縁が明るく、筋の模様が内へ流れて欠ける（加算）。0.75R → 0.92R に広がって 0.5 秒で消える
            .mesh(FXMesh(shape: .band, tex: .beam, tint: .secondary, alpha: 1, size: [R * 0.75, 1, R * 0.75],
                         sizeEnd: [R * 0.92, 1, R * 0.92], ease: .out, life: 0.5, fadeIn: 0.06, fadeOut: 0.5).glowing()
                .flowing(.streaks, scroll: [0.1, -1.4], tiling: 1, strength: 0.8, erosion: 0.55, edge: flameTip), at: S + 0.03),
            // 外の細い赤い線（f195〜198。輪の画像の半径は板の 0.44 倍 → 0.77R → 0.95R）
            .mesh(FXMesh(shape: .disc, tex: .ring, tint: flameRed, alpha: 0.9, size: [R * 1.75, 1, R * 1.75],
                         sizeEnd: [R * 2.15, 1, R * 2.15], ease: .out, life: 0.32, fadeIn: 0.03, fadeOut: 0.4).glowing(),
                  at: S + 0.03),
            // 輪の上でちらつく小さな炎（コマ送り）
            .emit(.sheet(.flameLoop, 0.6, flameTip, end: flameRed, count: 16, life: 0.42, orient: .upright).with {
                $0.shape = .ring(R * 0.84)
                $0.surface = true
            }, at: S + 0.04, offset: [0, 0.2, 0]),
            // 中心の焦げた地割れ（f199〜207。アルファ）
            .mesh(.decal(.crack, R * 0.9, .dark, life: 0.95, spin: 0, grow: 1.0, alpha: 0.85), at: S + 0.05),
            .shake(0.3, at: S),
        ]
        // 被弾者（sim のダメージ = 叩きつけの時刻に再生）: 白 → 淡い黄の閃き。70% 鈍足 1.5 秒は共通の状態の表示
        r.hit = hitBurst(1.7, y: 1.0)
        return r
    }

    // MARK: - アルティメット 狩猟鎖獄

    /// 対象へ 0.25 秒で掴みかかり、1.8 秒の間に 6 回殴る（掴んだ瞬間から 0.32 秒おき = 0.25 / 0.57 / 0.89 / 1.21 / 1.53 / 1.85 秒）。
    /// impact は対象の位置（発動時）で再生される = 時刻は発動から。.along は術者 → 対象の線上。
    private static func huntRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let G = grab
        let gap = strikeGap
        let last = G + gap * 5
        let D = finaleRadius
        // 掴みかかり（0.25 秒）は MLBB では光らない（1 撃目の閃きは hit）。空の cast を既定演出（光と粒）で補わせない
        r.cast = []
        r.fillsEmptyPhases = false
        var impact: [FXCue] = []
        // 2〜5 撃の前（f316・f325・f333・f343）: 左右交互に振る金の三日月（加算。撃の 0.07 秒前から 0.2 秒）
        let swings: [(from: Float, to: Float, tilt: Float)] = [(80, -80, 55), (-80, 80, -55), (70, -90, 75), (-70, 90, -35)]
        for (n, w) in swings.enumerated() {
            impact.append(.mesh(.slash(1.0, .primary, from: w.from, to: w.to, tilt: w.tilt, life: 0.2).glowing()
                .flowing(.streaks, scroll: [-2.5, 0], tiling: 1.5, strength: 0.4, erosion: 0.3, edge: .core),
                                at: G + gap * Float(n + 1) - 0.07, .along(0.7), offset: [0, 1.1, 0]))
        }
        // 6 撃目の前の振り上げ（f349 = 1.60 秒）: 縦の大きな金の三日月
        impact.append(.mesh(.slash(1.3, .primary, from: 90, to: -60, tilt: 90, life: 0.22).glowing(), at: last - 0.25,
                            .along(0.6), offset: [0, 1.2, 0]))
        // 6 撃目の叩きつけ（f350〜363 = 1.68〜2.1 秒）: 術者と対象の間に金の円（縁が明るい・加算）と内側の淡い光・昇る金の光条・
        // 焦げたひび（アルファ。広がるコマ送り + 残る地割れ）・6 撃目の白い閃光
        impact += [
            .mesh(FXMesh(shape: .disc, tex: .shockwave, tint: paleGold, alpha: 1, size: [D * 1.7, 1, D * 1.7],
                         sizeEnd: [D * 2, 1, D * 2], ease: .out, life: 0.4, fadeIn: 0.05, fadeOut: 0.6).glowing()
                .flowing(.noise, scroll: [0.2, 0.3], tiling: 2, strength: 0.35, edge: .core), at: last - 0.17, .along(0.6)),
            .emit(.groundGlow(D * 0.85, paleGold, life: 0.42), at: last - 0.17, .along(0.6), offset: [0, 0.03, 0]),
            .emit(FXEmit(tex: .streak, tint: .primary, tintEnd: .core, count: 14, emit: 0.12, life: 0.3, lifeVar: 0.2,
                         size: 0.3, sizeVar: 0.4, grow: 0.6, shape: .disc(1.3), dir: .up, speed: 11, speedVar: 0.3,
                         drag: 1.5, stretch: 4, fade: .linearFadeOut), at: last - 0.15, .along(0.65), offset: [0, 0.3, 0]),
            .emit(.groundSheet(.groundCrack, 2.6, .dark, life: 0.6, additive: false), at: last - 0.15,
                  offset: [0, 0.04, -0.3]),
            .mesh(.decal(.crack, 2.4, .dark, life: 0.8, spin: 0, grow: 1.0, alpha: 0.8), at: last - 0.12,
                  offset: [0, 0, -0.3]),
            .emit(.flare(2.4, flashWhite, life: 0.1, tex: .glowHard), at: last, offset: [0, 1.0, 0]),
            .shake(0.4, at: last),
        ]
        r.impact = impact
        // 6 回の 1 撃ごと（sim の時刻どおり。f307・317・327・337・345・355）: 白 → 淡い黄の放射の閃き・火花・小さな揺れ
        r.hit = hitBurst(1.9, y: 1.1) + [
            .emit(.sparks(8, speed: 6, flameTip, end: flameRed, gravity: 7), at: 0.02, offset: [0, 1.0, 0]),
            .shake(0.1),
        ]
        r.hitPerHit = true
        return r
    }

    // MARK: - パッシブの解放

    /// 闘気を使い切った（スキルのダメージが当たって消費したのが、発動から 0.6 秒以内）ときの合図。released は消費した闘気の数（1...10）で、
    /// 大きさに比例する。MLBB は武器の縁の金の光が消えるだけなので、両手の金の光が膨らんで散る短い合図にした。
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? {
        let k = Float(min(max(released, 1), 10)) / 10
        let burst = handGlow(0.8 + 0.8 * k, life: 0.28, grow: 1.6, alpha: 0.9, fadeIn: 0.02, fadeOut: 0.3)
        return [
            .mesh(burst, .follow, offset: hookHand),
            .mesh(burst, .follow, offset: shieldHand),
            .emit(.flare(0.9 + 1.3 * k, .core, life: 0.16, tex: .flare4), .follow, offset: hookHand),
            .emit(.sparks(6 + Int(12 * k), speed: 4 + 3 * k, .core, end: .primary), .follow, offset: [0, 1.0, 0.3]),
        ]
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
