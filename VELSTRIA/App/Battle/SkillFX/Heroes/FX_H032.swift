import Foundation
import VelstriaCore

// スキル演出: H032 赤拳のディアス（Duelist / 刃付きの籠手（拳剣）・赤い気・包帯の腕。MLBB の Dyrroth の Velstria 版）。
// 主題: 奈落の紫と紅のレイジ。桃白の芯 × 紫（主。通常のスキルの色）× 紅（副。アビス強化 = レイジの色）×
// 金（差し色。籠手の刃の輪）× 黒紫（暗。アルファ合成の影・煙・棘）。
// 2026-10-17: MLBB の画面収録（vid6 / vid7 / vid12。docs/vfx/H032.md）に合わせて作り直した。見た目の要点:
//   - スキル1 の輪は「地面の暗い藍の円 + 縁に先が内へ巻く鉤刃 3 枚 + 開く直前の小さな渦と桃色の閃光」。通常は青紫に光り、
//     アビス強化（レイジ 50 以上）は紅〜マゼンタ。スキル2 の突進は術者が紫（強化は紅）の亡霊の筋になる。
//   - 致命の一撃は金の刃の輪（籠手の輪）が対象の前で回り、紫の三日月が巻き、3 撃ごとに桃白の閃き。
//   - 奥義は溜めの間に紫の細い鎌の軌跡と黒い尾が術者の周りを打ち、前方に青紫の光、紅黒の棘が舞い、拳の前に
//     3 本爪の紅い槍が形になる → 0.76 秒に槍が前へ走り、紅い楔の残像と桃白の速さの線が直線を貫く。
// 状態（レイジ）で変わる見た目: レシピはレイジを読めない（SkillFXDirector は SkillCastEvent.count を読まない）ので、
// パッシブのバッジ（.stacks = Int(レイジ / 50)）を countedSlot にして、バッジが減った = アビス強化を撃った瞬間に、
// 通常版だけの部品（FXMesh.group = normalOnly）を予定ごと消す（SkillFXPlayer.cut。まだ出ていない合図も消える）。
// 消せるのは「メッシュ」だけ・足すことはできない（強化版 ⊆ 通常版）ので、共通の部品は紫と紅の間（マゼンタ）にし、
// 通常版にだけ青紫の光を重ねる。スキル1 の輪の位置は照準点（= 射程の端。通常 4.72m / 強化 6.44m）からの .along と
// 前方のずらしの組で、通常の 3 つ（1.05 / 2.325 / 3.6m）と強化の最初の 3 つ（1.05 / 2.1175 / 3.185m）の両方に合う。
// 強化の 4・5 つ目の輪（4.2525 / 5.32m）は出せない（docs/vfx/H032.md の保留）。
// sim の実際の挙動（Systems/Kits/Kit_H032.swift の Tune。MLBB の画面収録で測った値）に合わせたタイミング:
//   パッシブ 紅血の拳        — cast: レイジが 50・100 に届いた瞬間（バッジの段が増えたとき）: 両手の刃の輪が紅く光る（MLBB は
//                              体に演出が無く、HUD のバーが赤くなるだけなので小さく）。
//                              passiveRelease: アビス強化を放ってバッジの段が 1 → 0 に戻った瞬間（スキルの発動の直後）: 拳の
//                              赤橙の光と、体を包む紅の光（強化の突進の紅い亡霊・強化のスキル1 の拳の赤橙。MLBB vid6 f621・f282）。
//                              empoweredAttack（SimEvent.empoweredAttack = 円撃。通常攻撃 2 回の後の 3 回目の命中）: 判定の瞬間に、
//                              術者の周りの紫の渦と、縁がちょうど判定の半径（circleRadius 2.0m）の輪（外へは消えながら 1.1 倍）、
//                              両腕の刃の 1 回転の振りの軌跡、主対象の桃白の閃き。普段の通常攻撃の演出（Effekseer）の上に重ねる。
//                              empoweredReady: 次が円撃の間、自分だけに足元の判定の半径の細い輪（武器の光は全員に見える）
//   スキル1 赤拳連斬（帯）     — 近接の cone のアーキタイプなので発動と同時に cast と impact。0.26 / 0.46 / 0.66 秒（burstFirstDelay + 0.2 × n）に、
//                              照準の帯の上の衝撃の円（半径 1.12m）で: 0.08 秒前に術者の前の黒い振りの影 → 渦と閃光 → 縁の鉤刃 3 枚と
//                              暗い藍の地（通常版だけ青紫の光の地）。被弾は 1 発ごと（hitPerHit）に桃白の命中の閃き
//   スキル2 紅蓮の踏込        — 1 回目（stage 0、dashStrike: impact は再生されない）: 突進（4.15m を 0.4 秒）の間、術者が亡霊の筋になる
//                              （共通: 桃白〜紅の細い筋・マゼンタの光の尾・黒紫の煙。通常版だけ: 青紫の彗星と体の光）。敵が居なければ
//                              終点に何も出さない（MLBB）。被弾（最初に当たった敵、到着の瞬間）: 桃白の閃き・マゼンタの星・前へ伸びる線・紫の斬線。
//                              2 回目（stage 1 = 致命の一撃、targetedBlink）: 振りかぶり（0.06 秒、強化 0.19 秒）のあと飛びかかり（毎秒 12m）、
//                              到着の瞬間（1 撃目の被弾）から金の刃の輪が回り、紫の大きな三日月が払い、3 撃（0 / 0.13 / 0.2 秒）ごとに
//                              三日月と桃白の閃き。段の演出は recipe(_:stage:_:)（再使用ではレイジが減らないので、通常・強化は同じ見た目）
//   アルティメット 奈落の一撃  — 直線（piercingLine）だが投射物もゾーンも作らない（Kit.hitAreaEach）ので、全部を cast に置く。
//                              0〜0.76 秒の溜め: 紫の鎌の軌跡 4 本と黒い尾 2 本・前方 2m の青紫の光 2 回・紅黒の棘・0.45 秒から拳の前に
//                              3 本爪の紅い槍（金の光 → 桃色の光）。0.76 秒: 槍が直線の端へ走り、紅い楔の残像・紅の光の筋・桃白の速さの線・
//                              紅黒の棘・黒紫の煙。被弾（0.76 秒）: 桃白の閃き・紅の斬線・紅黒の棘
// 光る部品（閃光・鉤刃・光の筋・鎌の軌跡・槍の光）は加算（glowing）、影・地・煙・棘・槍の黒い芯はアルファ合成。

enum FX_H032: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.9, 1.0), primary: RGB(0.76, 0.26, 0.98),
                                   secondary: RGB(0.88, 0.16, 0.3), accent: RGB(0.96, 0.66, 0.36),
                                   dark: RGB(0.07, 0.04, 0.12))

    /// 右の拳（局所座標）。
    private static let fist: SIMD3<Float> = [0.35, 1.0, 0.5]

    /// スキル1 の輪の閃光・渦の閃き（MLBB #F58EF9。通常・強化で同じ）。
    private static let flash = FXTint.rgb(0.96, 0.56, 0.97)
    /// スキル1 の縁の鉤刃（通常 #C443F9 と強化 #E52E7F の間のマゼンタ。通常版は青紫の光の地が重なって紫に寄る）。
    private static let hookTint = FXTint.rgb(0.9, 0.24, 0.68)
    /// スキル1 の通常版だけの青紫の光の地（MLBB #5D2AE4 → #2C28AD）。
    private static let abyssGlow = FXTint.rgb(0.36, 0.17, 0.89)
    /// スキル1 の輪の暗い藍の地（通常 #1E1F3F・強化 #3B2939 の間。アルファ合成）。
    private static let ringFill = FXTint.rgb(0.12, 0.1, 0.26)
    /// 黒い影・煙の筋（振りの影・亡霊の尾・鎌の尾。アルファ合成）。
    private static let shade = FXTint.rgb(0.05, 0.03, 0.09)
    /// 亡霊の尾の黒紫の煙（MLBB vid7 f284〜288 の紺紫）。
    private static let smokeViolet = FXTint.rgb(0.13, 0.09, 0.26)
    /// 突進の光の尾（共通。強化の紅の体 #E94478 寄り）と、通常版だけの青紫の彗星・体（#A250E8 / #8853DA）。
    private static let phantom = FXTint.rgb(0.86, 0.24, 0.5)
    private static let phantomViolet = FXTint.rgb(0.56, 0.3, 0.88)
    /// 奥義の鎌の軌跡（MLBB #D634F5）と、前方の青紫の光（#4A56F7）。
    private static let whip = FXTint.rgb(0.84, 0.2, 0.96)
    private static let bloomBlue = FXTint.rgb(0.29, 0.34, 0.97)
    /// 紅黒の棘・槍の黒い芯（MLBB #C70A19 の暗い側。アルファ合成）。
    private static let thorn = FXTint.rgb(0.6, 0.03, 0.08)
    /// 強化を放った拳の赤橙（MLBB vid6 f621〜622・f282）。
    private static let ember = FXTint.rgb(1.0, 0.38, 0.26)

    /// 通常版（レイジ 50 未満で撃った）だけに出す部品の組。アビス強化（パッシブのバッジが減った瞬間）で SkillFXDirector が消す。
    private static let normalOnly = 1
    /// スキル1 の輪の鉤刃・渦・光の地の高さ（MLBB の輪は地面から浮いて描かれる: 中心が奥へ 0.4 ずれる。推定 0.25m）。
    private static let ringY: Float = 0.25

    // MARK: - sim の時刻・寸法（Kit_H032.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 1 発目の遅れと間隔（通常版も強化も 0.2 秒おき）。
    private static let burstFirst: Float = 0.26
    private static let burstInterval: Float = 0.2
    /// スキル1: 衝撃の円の半径（m）と、照準線（術者 → 照準点 = 射程）の上の円の中心の位置（通常版の 1.05 / 2.325 / 3.6m ÷ 4.72m）。
    private static let burstRadius: Float = 1.12
    private static let burstAlong: [Float] = [0.2225, 0.4926, 0.7627]
    /// スキル1: 射程（照準点までの距離。通常 / アビス強化）・1 つ目の円の中心・強化の円の数（Tune.burstReach / burstReachAbyss /
    /// burstFirstCenter / burstCountAbyss）。
    private static let burstReach: Float = 4.72
    private static let burstReachAbyss: Float = 6.44
    private static let burstFirstCenter: Float = 1.05
    private static let burstCountAbyss = 5
    /// スキル2: 突進の所要（415 / 1040 ≈ 0.4 秒）と、致命の一撃の振りかぶり + 隣の敵への飛びかかりの目安（0.06 + 約 0.1 秒）。
    private static let dashTime: Float = 0.4
    private static let fatalTime: Float = 0.16
    /// 致命の一撃の 2・3 撃目（1 撃目からの秒。sim の 4 / 6 tick 後 = Kit_H032.Tune.fatalTickAfter の当たる tick）。
    private static let fatalTicks: [Float] = [4.0 / 30, 6.0 / 30]
    /// アルティメット: 溜め・射程（直線の長さ）・半幅。
    private static let ultCharge: Float = 0.76
    private static let ultReach: Float = 6.14
    private static let ultHalfWidth: Float = 1.37

    // MARK: - レイジの状態（パッシブのバッジ）

    /// パッシブのバッジ（.stacks = Int(レイジ / 50)、0〜2）が減った = アビス強化を撃った（スキル1・スキル2 の 1 回目）か死亡。
    static var countedSlot: SkillSlot? { .passive }

    /// バッジが減ったら（残り 0・1）、まだ出ていない・追従している通常版だけの部品を消す。
    static func spentGroups(remaining: Int) -> [Int] { remaining < 2 ? [normalOnly] : [] }

    // MARK: - 部品

    /// スキル1 の k 番目の輪の置き方: .along(f) + 前方 z。照準点が射程の端（通常 4.72m / 強化 6.44m）なので、
    /// f × 射程 + z が通常版の中心（1.05 + 1.275k）と強化版の中心（1.05 + 1.0675k）の両方になる f・z を解く。
    private static func burstPlace(_ k: Int) -> (f: Float, z: Float) {
        let normal = burstAlong[k] * burstReach
        let abyss = burstFirstCenter + (burstReachAbyss - burstRadius - burstFirstCenter) * Float(k) / Float(burstCountAbyss - 1)
        let f = (abyss - normal) / (burstReachAbyss - burstReach)
        return (f, normal - f * burstReach)
    }

    /// スキル1 の輪の縁の鉤刃 3 枚: 中心から 0.44m 外へずらした三日月（直径 1.45m）を外向きに置く。先端が内へ巻き、
    /// 頂点が半径 1.12m（衝撃の円の縁）に届く。turn の向きへ少しひねって回る勢いを出す。
    private static func hooks(at t: Float, along f: Float, z: Float, turn: Float, phase: Float) -> [FXCue] {
        let r: Float = 0.44, d: Float = 1.45
        return (0..<3).map { i -> FXCue in
            let a = phase + Float(i) * 120
            let rad = a * .pi / 180
            let m = FXMesh(shape: .disc, tex: .slash, tint: hookTint, alpha: 1, size: [d * 0.75, 1, d * 0.75],
                           sizeEnd: [d, 1, d], ease: .out, life: 0.18, fadeIn: 0.04, fadeOut: 0.45, yaw: a,
                           yawEnd: a - 50 * turn).glowing()
            return .mesh(m, at: t, .along(f), offset: [-r * sin(rad), ringY, z + r * cos(rad)])
        }
    }

    /// 奥義の鎌の軌跡（細い三日月が術者の周りを打つ。加算）。
    private static func whipArc(_ radius: Float, from: Float, to: Float, tilt: Float, life: Float = 0.22) -> FXMesh {
        FXMesh.slash(radius, whip, from: from, to: to, tilt: tilt, life: life, tex: .slashThin).glowing()
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

    /// レイジが 50・100 に届いた瞬間: 両手の刃の輪が紅く光る（MLBB は体に演出が無い。HUD のバーが赤くなるのに合わせた小さな合図）。
    private static func wrathRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        r.cast = [
            .mesh(FXMesh.halo(0.24, .secondary, life: 0.5, spin: 520, tex: .ringDouble).glowing(), .follow, offset: [0.38, 1.0, 0.25]),
            .mesh(FXMesh.halo(0.24, .secondary, life: 0.5, spin: -520, tex: .ringDouble).glowing(), .follow, offset: [-0.38, 1.0, 0.25]),
            .emit(.flare(0.8, .secondary, life: 0.14, tex: .flare4), .follow, offset: [0, 1.0, 0.3]),
        ]
        // パッシブのダメージ（円撃）は通常攻撃（Effekseer）。既定の被弾演出で補われないよう小さな合図だけ置く
        r.hit = [.mesh(.halo(0.35, .secondary, life: 0.25, spin: 200, tex: .ring), .follow, offset: [0, 0.2, 0])]
        return r
    }

    /// アビス強化を放った（レイジの段が 1 → 0）瞬間: 拳の赤橙の光と、体を包む紅の光・右手の輪。released は消費した段の数。
    /// （段が 2 → 1（レイジ 100 から撃った）は SkillFXDirector が解放として扱わないので出ない。docs/vfx/H032.md）
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? {
        [
            .emit(.flare(1.5, ember, life: 0.16, tex: .flare6), .follow, offset: fist),
            .mesh(.sprite(.glow, 1.8, .secondary, life: 0.32, grow: 1.2, alpha: 0.7).glowing(), .follow, offset: [0, 1.0, 0.2]),
            .mesh(FXMesh.halo(0.3, .secondary, life: 0.4, spin: -600, tex: .ringDouble).glowing(), .follow, offset: [0.38, 1.0, 0.3]),
            .emit(.sparks(8, speed: 5, .core, end: .secondary), .follow, offset: fist),
        ]
    }

    // MARK: - パッシブ 円撃（強い通常攻撃。SimEvent.empoweredAttack）

    /// 円撃の判定の半径（m。Kit の circleRadius = 判定の円そのもの。術者の中心から。対象の半径は含まない）。
    static func circleRadius(_ s: FXSkillInfo) -> Float { s.meters("circleRadius") }

    /// 縁 → 縁 × spread へ ease .out で広がる部品が 1.03 倍を越える寿命の比より少し前（消え始めの比。docs/vfx/RANGES.md）。
    static func edgeFade(_ spread: Float) -> Float {
        guard spread > 1.03 else { return 0.4 }
        let e: Float = 0.03 / (spread - 1)
        return max(0.02, (1 - pow(1 - e, 1.0 / 3.0)) * 0.9)
    }

    /// 円撃の縁の広がり（判定の瞬間に縁 = 半径、消えながらこの倍率へ）。
    static let circleSpread: Float = 1.1

    /// 円撃: 判定の瞬間（1 発目の命中 = 0 秒）に、術者の周り（sim の術者の位置 = 判定の円の中心）に紫の渦と、縁がちょうど判定の半径の
    /// 輪（外縁の持ち上がった輪の模型 + 輪の模様の板。外へは消えながら 1.1 倍まで）、両腕の刃が体の高さで 1 回転する紫・紅の振りの
    /// 軌跡、主対象に桃白の閃き。MLBB（docs/kits/Dyrroth.md）: 紫の渦の外縁が術者から 2.0〜2.1。
    static func empoweredAttack(_ s: FXSkillInfo) -> [FXCue]? {
        let r = circleRadius(s)
        let spread = circleSpread
        let side = r / (FXEdge.radial(.ring) ?? 0.4575)
        return [
            // 判定の縁の輪（判定の瞬間に見える縁 = r。外へは消えながら）
            .mesh(FXMesh.model(.ringLip, nil, .primary, size: [r, 1.2, r], sizeEnd: [r * spread, 0.6, r * spread], life: 0.34)
                .with { $0.fadeIn = 0; $0.fadeOut = edgeFade(spread) }.glowing(), offset: [0, 0.02, 0]),
            .mesh(FXMesh(shape: .disc, tex: .ring, tint: hookTint, alpha: 0.95, size: [side, 1, side],
                         sizeEnd: [side * spread, 1, side * spread], ease: .out, life: 0.3, fadeIn: 0,
                         fadeOut: edgeFade(spread)).glowing(), offset: [0, 0.04, 0]),
            // 渦（範囲を示さない模様。縁の内側だけ）: 暗い藍の地（アルファ合成）と、紫に光る渦が回りながら広がる
            .mesh(FXMesh(shape: .disc, tex: .swirl, tint: ringFill, alpha: 0.8, size: [r * 1.1, 1, r * 1.1],
                         sizeEnd: [r * 1.8, 1, r * 1.8], ease: .out, life: 0.42, fadeIn: 0.02, fadeOut: 0.45, spin: 540),
                  offset: [0, 0.03, 0]),
            .mesh(FXMesh(shape: .disc, tex: .swirl, tint: .primary, alpha: 0.9, size: [r * 1.0, 1, r * 1.0],
                         sizeEnd: [r * 1.85, 1, r * 1.85], ease: .out, life: 0.32, fadeIn: 0.02, fadeOut: 0.4, spin: 900).glowing()
                .flowing(.streaks, scroll: [2.5, 0], tiling: 1.5, strength: 0.5, erosion: 0.35, edge: flash),
                  offset: [0, 0.06, 0]),
            // 両腕の刃の 1 回転の振りの軌跡（体の高さ。右の刃は紫、左の刃は紅）と、体の高さを薙ぐ白い弧
            .ribbon(.swing(radius: 1.45, from: 0, to: 360, height: 1.0, duration: 0.2, life: 0.18, width: 0.7, .primary), .follow),
            .ribbon(.swing(radius: 1.3, from: 180, to: 540, height: 0.9, duration: 0.2, life: 0.16, width: 0.55, .secondary),
                    .follow),
            .mesh(FXMesh.sweep(1.6, .core, from: 0, to: 360, life: 0.22).glowing(), .follow, offset: [0, 1.0, 0]),
            // 主対象に桃白の閃き（周りの敵は共通の被弾の閃き）
            .mesh(.sprite(.flare4, 1.5, flash, life: 0.12, grow: 1.3).glowing(), .target, offset: [0, 1.0, 0]),
            .emit(.sheet(.darkWisp, 3.2, .primary, end: smokeViolet, life: 0.4), offset: [0, 0.9, 0]),
            .emit(.sparks(16, speed: 7, .core, end: .primary).with { $0.dir = .outward; $0.spread = 15 }, offset: [0, 0.9, 0]),
            .shake(0.12),
        ]
    }

    /// 次の通常攻撃が円撃の間（通常攻撃 2 回の後）: 足元に円撃の届く半径（判定の円）の紫の細い輪。自分だけに出す
    /// （SkillFXDirector.observeEmpoweredReady。武器の光は全員に見える HeroModelHandle.setEmpoweredReady）。
    static func empoweredReady(_ s: FXSkillInfo) -> [FXCue]? {
        let r = circleRadius(s)
        let side = r / (FXEdge.radial(.thinRing) ?? 0.48)
        return [
            .mesh(FXMesh(shape: .disc, tex: .thinRing, tint: flash, alpha: 0.7, size: [side, 1, side], sizeEnd: [side, 1, side],
                         ease: .linear, life: 2.0, fadeIn: 0.1, fadeOut: 0.85).glowing(), .follow, offset: [0, 0.03, 0]),
            .mesh(FXMesh(shape: .disc, tex: .swirl, tint: .primary, alpha: 0.16, size: [r * 1.6, 1, r * 1.6],
                         sizeEnd: [r * 1.6, 1, r * 1.6], ease: .linear, life: 2.0, fadeIn: 0.1, fadeOut: 0.85, spin: -60).glowing(),
                  .follow, offset: [0, 0.02, 0]),
        ]
    }

    // MARK: - スキル1 赤拳連斬

    /// 0.26 / 0.46 / 0.66 秒に、照準の帯の上の衝撃の円（半径 1.12m）が手前から奥へ開く。
    /// MLBB（vid7 f12〜28・vid6 f620〜650）: 振りの黒い影 → 小さな渦と桃色の閃光（ダメージのコマ）→ 次のコマで縁の鉤刃 3 枚と暗い地が
    /// 円いっぱいに開き、鉤刃は 0.1〜0.15 秒、地は 0.3 秒ほどで消える。通常版は地が青紫に光り、強化版は紅〜マゼンタ。
    private static func burstRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let t0 = burstFirst, dt = burstInterval
        var cast: [FXCue] = []
        var impact: [FXCue] = []
        for k in 0..<burstAlong.count {
            let t = t0 + dt * Float(k)
            let (f, z) = burstPlace(k)
            let turn: Float = k % 2 == 0 ? 1 : -1
            // 振りの黒い影（輪の 0.08 秒前、術者の前。右→左→右）
            cast.append(.emit(.sheet(.slashFade, 1.9, shade, life: 0.22, additive: false).with {
                $0.angle = 25 * turn
                $0.angleVar = 8
            }, at: t - 0.08, .follow, offset: [0, 1.0, 0.35]))
            // 開く直前の小さな渦（鉤刃が巻いた形）と桃色の閃光
            impact.append(.mesh(FXMesh(shape: .disc, tex: .swirl, tint: hookTint, alpha: 1, size: [0.8, 1, 0.8],
                                       sizeEnd: [2.3, 1, 2.3], ease: .out, life: 0.1, fadeIn: 0.05, fadeOut: 0.5,
                                       spin: -1400 * turn).glowing(), at: t - 0.02, .along(f), offset: [0, ringY, z]))
            impact.append(.emit(.flare(1.6, flash, life: 0.1, tex: .flare4), at: t - 0.01, .along(f), offset: [0, ringY + 0.15, z]))
            // 縁の鉤刃 3 枚（共通。マゼンタ）
            impact += hooks(at: t + 0.02, along: f, z: z, turn: turn, phase: 30 * Float(k))
            // 暗い藍の地（共通。アルファ）と、地を這う黒い煙の筋
            impact.append(.mesh(FXMesh(shape: .disc, tex: .smoke, tint: ringFill, alpha: 0.72, size: [1.9, 1, 1.9],
                                       sizeEnd: [2.3, 1, 2.3], ease: .out, life: 0.36, fadeIn: 0.08, fadeOut: 0.45,
                                       spin: 260 * turn), at: t + 0.02, .along(f), offset: [0, 0, z]))
            impact.append(.emit(.groundSheet(.darkWisp, 2.2, shade, life: 0.42, additive: false), at: t + 0.03, .along(f),
                                offset: [0, 0.04, z]))
            // 通常版だけ: 地いっぱいの青紫の光（アビス強化ではバッジが減った瞬間に予定ごと消える）
            impact.append(.mesh(FXMesh(shape: .disc, tex: .glow, tint: abyssGlow, alpha: 0.8, size: [1.6, 1, 1.6],
                                       sizeEnd: [2.4, 1, 2.4], ease: .out, life: 0.22, fadeIn: 0.08, fadeOut: 0.3).glowing()
                .flowing(.noise, scroll: [0.4 * turn, 0.3], tiling: 1.5, strength: 0.5, erosion: 0.3, edge: .primary)
                .with { $0.group = normalOnly }, at: t, .along(f), offset: [0, ringY - 0.05, z]))
        }
        impact.append(.shake(0.12, at: t0))
        impact.append(.shake(0.16, at: t0 + 2 * dt))
        r.cast = cast
        r.impact = impact
        // 1 発ごと: 桃白の命中の閃き（MLBB は的が桃白 → 赤に光るだけ。鈍足の印は出さない）
        r.hit = [
            .emit(.sheet(.hitFlash, 1.3, .core, end: flash, life: 0.16), offset: [0, 1.0, 0]),
            .emit(.flare(0.8, flash, life: 0.1, tex: .flare4), offset: [0, 1.0, 0]),
        ]
        r.hitPerHit = true
        return r
    }

    // MARK: - スキル2 紅蓮の踏込

    /// 1 回目: 亡霊の筋になって突進し、最初の敵の手前で殴って押し出す（照準 = 着地点）。
    /// MLBB（vid7 f276〜284 通常・vid7 f78〜88 / vid6 f282〜288 強化）: 術者が紫（強化は紅）の光の体と彗星の尾になり、中に桃白の細い筋、
    /// 後ろに紺紫の煙。敵が居なければ終点に何も出ない。
    private static func spectreRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let t = dashTime
        r.cast = [
            .emit(.flare(1.2, flash, life: 0.12, tex: .flare4), .follow, offset: [0.3, 1.0, 0.4]),
            // 共通: 桃白 → 紅の細い筋、マゼンタの光の尾、紺紫の煙（突進の間だけ）
            .emit(.trail(.streak, .core, rate: 90, life: 0.28, size: 0.45).with {
                $0.duration = t; $0.stretch = 3.2; $0.dir = .backward; $0.speed = 5; $0.tintEnd = .secondary
            }, .follow, offset: [0, 1.0, 0]),
            .emit(.trail(.glow, phantom, rate: 40, life: 0.32, size: 0.9).with {
                $0.duration = t; $0.dir = .backward; $0.speed = 1.5; $0.grow = 0.6; $0.tintEnd = .secondary
            }, .follow, offset: [0, 1.0, -0.1]),
            .emit(.trail(.smoke, smokeViolet, rate: 30, life: 0.6, size: 0.8).with {
                $0.duration = t + 0.02; $0.additive = false; $0.grow = 1.7; $0.fade = .gradualFadeInOut; $0.tintEnd = nil
                $0.sheet = .smokePuff
            }, .follow, offset: [0, 0.6, -0.2], quality: 1),
            // 通常版だけ: 青紫の彗星の尾（筋の模様が後ろへ流れる）と体の光（アビス強化では予定ごと消える）
            .mesh(FXMesh.ray(.streak, length: 2.6, width: 1.0, phantomViolet, life: t + 0.04, alpha: 0.9).glowing()
                .flowing(.streaks, scroll: [-3, 0], tiling: 2, strength: 0.6, erosion: 0.3, edge: flash).with {
                    $0.group = normalOnly; $0.fadeIn = 0.1; $0.fadeOut = 0.6
                }, at: 0.04, .follow, offset: [0, 0.95, -1.3]),
            .mesh(FXMesh.sprite(.glow, 1.7, phantomViolet, life: t, grow: 1.1, alpha: 0.7).glowing().with {
                $0.group = normalOnly; $0.fadeIn = 0.15; $0.fadeOut = 0.7
            }, at: 0.04, .follow, offset: [0, 1.0, 0]),
        ]
        // 突進（dashStrike）は impact を再生しない。目視確認の実演（-skillDemo）だけが impact を出すので、
        // 既定演出で補われないよう小さな揺れだけ置く
        r.impact = [.shake(0.12)]
        // 最初に当たった敵（到着の瞬間）: 桃白の閃き・マゼンタの星・前へ伸びる細い線・紫の斬線・紺紫の煙（MLBB vid7 f282〜284）
        r.hit = [
            .emit(.sheet(.hitFlash, 1.7, .core, end: flash, life: 0.2), offset: [0, 1.0, 0]),
            .emit(.flare(1.3, hookTint, life: 0.14, tex: .flare4), offset: [0, 1.0, -0.2]),
            .emit(.sparks(8, speed: 9, .core, end: flash).with { $0.dir = .forward; $0.spread = 12; $0.stretch = 4 },
                  offset: [0, 1.0, -0.4]),
            .mesh(.slash(1.1, .primary, from: 60, to: -60, tilt: -15, life: 0.2).glowing(), offset: [0, 1.0, -0.5]),
            .emit(.sheet(.smokePuff, 1.4, smokeViolet, count: 2, life: 0.6, additive: false, radius: 0.3),
                  offset: [0, 0.6, -0.4], quality: 1),
            .shake(0.12),
        ]
        return r
    }

    /// 2 回目（stage 1 = 致命の一撃）: 敵ヒーロー・モンスターへ飛びかかり、3 撃で裂く（防御ダウン 4 秒）。
    /// MLBB（vid7 f290〜306 通常・vid6 f298〜316 強化）: 対象の前で金の刃の輪（籠手の輪 #F4A758）が回り、紫（強化は紅）の三日月が巻き、
    /// 大きな紫の三日月が払う。3 撃ごとに桃白の閃き。防御ダウンの印は見えない（的の防御が 0）。
    static func recipe(_ slot: SkillSlot, stage: Int, _ s: FXSkillInfo) -> SkillFXRecipe? {
        guard slot == .skill2, stage == 1 else { return nil }
        var r = SkillFXRecipe()
        let t = fatalTime
        // 振りかぶりの金の閃き（籠手の輪）と、飛びかかりの桃白 → 紅の筋
        r.cast = [
            .emit(.flare(1.1, .accent, life: 0.12, tex: .flare4), .follow, offset: fist),
            .emit(.trail(.streak, .core, rate: 90, life: 0.24, size: 0.45).with {
                $0.duration = t; $0.stretch = 3; $0.dir = .backward; $0.speed = 4; $0.tintEnd = .secondary
            }, .follow, offset: [0, 1.0, 0]),
        ]
        // 発動時に対象の位置（targetedBlink）: 着いた瞬間の揺れだけ（MLBB は対象に照準の輪を出さない）
        r.impact = [.shake(0.1, at: t)]
        // 到着の瞬間（1 撃目の被弾）から: 金の刃の輪・橙紅の内輪・3 撃の三日月・大きな払い・桃白の閃き
        let hits: [Float] = [0, fatalTicks[0], fatalTicks[1]]
        r.hit = [
            .mesh(FXMesh.halo(0.78, .accent, life: 0.42, spin: 900, tex: .ringDouble, alpha: 1).glowing().with {
                $0.pitch = -20
            }, offset: [0, 0.85, -0.25]),
            .mesh(FXMesh.halo(0.6, .rgb(0.95, 0.38, 0.22), life: 0.36, spin: -700, tex: .ring, alpha: 1).glowing().with {
                $0.pitch = -20
            }, offset: [0, 0.85, -0.25]),
            .mesh(.slash(1.0, .primary, from: 70, to: -70, tilt: -25, life: 0.2).glowing(), at: hits[0], offset: [0, 0.9, -0.25]),
            .mesh(.slash(1.05, hookTint, from: -70, to: 70, tilt: 25, life: 0.2).glowing(), at: hits[1], offset: [0, 0.95, -0.25]),
            .mesh(.slash(1.1, .primary, from: 80, to: -80, tilt: -10, life: 0.2).glowing(), at: hits[2], offset: [0, 0.9, -0.25]),
            // 大きな紫の三日月の払い（MLBB vid7 f296〜298。筋の模様が弧に沿って流れる）
            .mesh(.slash(2.3, .primary, from: 85, to: -85, tilt: -18, life: 0.26).glowing()
                .flowing(.streaks, scroll: [2.5, 0], tiling: 2, strength: 0.5, erosion: 0.3, edge: flash),
                  at: 0.03, offset: [0, 1.0, -0.9]),
            .emit(.sheet(.hitFlash, 1.5, .core, end: flash, life: 0.18), at: hits[0], offset: [0, 1.0, 0]),
            .emit(.sheet(.hitFlash, 1.4, .core, end: flash, life: 0.16), at: hits[1], offset: [0, 1.05, 0]),
            .emit(.sheet(.hitFlash, 1.6, .core, end: flash, life: 0.18), at: hits[2], offset: [0, 1.0, 0]),
            .emit(.sparks(10, speed: 7, .core, end: flash), at: hits[2], offset: [0, 1.0, 0]),
            .shake(0.22),
        ]
        return r
    }

    // MARK: - アルティメット 奈落の一撃

    /// 0〜0.76 秒の溜め → 0.76 秒に前方の直線（6.14m・半幅 1.37m）を紅い槍で貫く。投射物もゾーンも無いので全部 cast。
    /// MLBB（vid6 f697〜726）: 紫の鎌の軌跡と黒い尾が周りを打ち（f697〜715）、前方に青紫の光（f701・f707）、紅黒の棘が舞い、
    /// f711 から拳の前に 3 本爪の紅い槍（金の光 → f717 桃色の光）。f720 に紅い楔の残像と桃白の速さの線、対象の白い閃き、紅黒の棘。
    private static func abysmRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = min(s.range, ultReach)
        let W = min(s.radius, ultHalfWidth)
        let t = ultCharge
        let spearAt: Float = 0.45
        r.cast = [
            // 溜め: 紫の鎌の軌跡 4 本（右・左・上・下を交互に）と黒い尾 2 本
            .mesh(whipArc(1.7, from: 100, to: -40, tilt: -25), offset: [0, 1.1, 0.3]),
            .mesh(whipArc(1.9, from: -120, to: 20, tilt: 30), at: 0.1, offset: [0, 0.7, 0.2]),
            .mesh(whipArc(1.6, from: 160, to: 40, tilt: -35), at: 0.24, offset: [0, 1.3, 0.1]),
            .mesh(whipArc(1.8, from: -60, to: -200, tilt: 20, life: 0.24), at: 0.4, offset: [0, 0.6, 0.2]),
            .mesh(.slash(1.9, shade, from: 150, to: 10, tilt: 10, life: 0.3).with { $0.alpha = 0.75 }, at: 0.06,
                  offset: [0, 0.4, 0]),
            .mesh(.slash(1.7, shade, from: -150, to: -10, tilt: -12, life: 0.3).with { $0.alpha = 0.75 }, at: 0.3,
                  offset: [0, 0.5, 0]),
            // 前方 2m の青紫の光（鎌の先が打つ所。2 回）
            .mesh(.sprite(.glow, 2.0, bloomBlue, life: 0.2, grow: 1.3, alpha: 0.9).glowing(), at: 0.13, offset: [0.2, 0.8, 1.9]),
            .mesh(.sprite(.glow, 2.2, bloomBlue, life: 0.2, grow: 1.3, alpha: 0.9).glowing(), at: 0.33, offset: [-0.1, 0.9, 2.2]),
            .emit(.flare(1.0, .core, life: 0.1, tex: .flare4), at: 0.13, offset: [0.2, 0.8, 1.9]),
            // 紅黒の棘が舞う（アルファ）
            .emit(.flutter(.shard, 12, radius: 1.4, thorn, speed: 3, life: 0.6, size: 0.22).with {
                $0.additive = false; $0.emit = 0.55; $0.tintEnd = shade; $0.gravity = 0
            }, at: 0.05, offset: [0, 1.0, 0.6]),
            // 0.45 秒から拳の前に 3 本爪の紅い槍（黒い芯 + 紅の光）、金の光 → 撃つ直前の桃色の光
            .mesh(FXMesh(shape: .disc, tex: .claw, tint: thorn, alpha: 0.95, size: [0.6, 1, 0.9], sizeEnd: [1.1, 1, 2.4],
                         ease: .out, life: t - spearAt + 0.04, fadeIn: 0.2, fadeOut: 0.9), at: spearAt, offset: [0, 1.05, 1.5]),
            .mesh(FXMesh(shape: .disc, tex: .claw, tint: .secondary, alpha: 1, size: [0.7, 1, 1.0], sizeEnd: [1.25, 1, 2.6],
                         ease: .out, life: t - spearAt + 0.02, fadeIn: 0.25, fadeOut: 0.85).glowing(), at: spearAt + 0.02,
                  offset: [0, 1.08, 1.5]),
            .mesh(.sprite(.glow, 1.5, .accent, life: 0.2, grow: 1.2, alpha: 0.85).glowing(), at: spearAt + 0.02,
                  offset: [0, 1.05, 1.0]),
            .mesh(.sprite(.glow, 2.6, flash, life: 0.14, grow: 1.2, alpha: 0.8).glowing(), at: t - 0.1, offset: [0, 1.05, 1.6]),
            // 0.76 秒: 拳の閃光、槍が直線の端へ走る
            .emit(.flare(2.2, .core, life: 0.16, tex: .flare6), at: t, offset: [0, 1.0, 1.0]),
            .mesh(FXMesh(shape: .disc, tex: .claw, tint: .secondary, alpha: 1, size: [1.1, 1, 2.4], sizeEnd: [1.4, 1, 3.0],
                         ease: .out, life: 0.2, fadeIn: 0.05, fadeOut: 0.6, advance: (L - 2.5) / 0.2).glowing(), at: t,
                  offset: [0, 1.0, 1.6]),
            // 紅い楔の残像（アルファ。筋が前へ流れて欠ける）と、紅の光の筋（加算）
            .mesh(FXMesh.ray(.streak, length: L, width: W * 1.8, thorn, life: 0.34, alpha: 0.6)
                .flowing(.streaks, scroll: [-4, 0], tiling: 2, strength: 0.5, erosion: 0.4, edge: .secondary),
                  at: t, offset: [0, 0.6, L / 2]),
            .mesh(FXMesh.ray(.streak, length: L, width: 1.1, .secondary, life: 0.24).glowing()
                .flowing(.streaks, scroll: [-5, 0], tiling: 3, strength: 0.6, erosion: 0.35, edge: flash),
                  at: t, offset: [0, 0.9, L / 2]),
            // 桃白の速さの線（前へ流れる細い光条）
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: flash, count: 24, emit: 0.06, life: 0.26, size: 0.07, sizeVar: 0.5,
                         grow: 0.5, shape: .box([W * 1.6, 0.8, L * 0.4]), dir: .forward, speed: 16, speedVar: 0.4, drag: 1.0,
                         stretch: 5, fade: .linearFadeOut), at: t, offset: [0, 1.0, L * 0.3]),
            // 線に沿って舞う紅黒の棘と黒紫の煙、端の火花
            .emit(.flutter(.shard, 16, radius: 0.4, thorn, speed: 3.5, life: 0.7, size: 0.22).with {
                $0.additive = false; $0.tintEnd = shade; $0.shape = .box([W * 1.4, 0.6, L * 0.9])
            }, at: t + 0.05, offset: [0, 1.0, L / 2]),
            .emit(.sheet(.smokePuff, 1.8, smokeViolet, count: 4, life: 0.9, additive: false).with {
                $0.shape = .box([W * 1.2, 0.3, L * 0.8])
            }, at: t + 0.06, offset: [0, 0.6, L / 2], quality: 1),
            .emit(.sparks(14, speed: 8, .core, end: .secondary), at: t + 0.05, offset: [0, 1.0, L - 0.4]),
            .shake(0.45, at: t),
        ]
        // 投射物もゾーンも無いので impact / travel は本番では再生されない（目視確認の実演だけ）。既定演出で補われないよう揺れだけ置く
        r.impact = [.shake(0.2)]
        r.travel = [.shake(0.05)]
        // 0.76 秒の被弾: 桃白の閃き・紅の斬線・紅黒の棘（MLBB f720〜726）
        r.hit = [
            .emit(.sheet(.hitFlash, 2.2, .core, end: flash, life: 0.22), offset: [0, 1.0, 0]),
            .mesh(.slash(1.2, .secondary, from: 70, to: -70, tilt: -30, life: 0.22).glowing(), offset: [0, 1.0, -0.5]),
            .emit(.flutter(.shard, 10, radius: 0.5, thorn, speed: 4, life: 0.6, size: 0.2).with {
                $0.additive = false; $0.tintEnd = shade
            }, offset: [0, 1.0, 0]),
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
            // 大きく振りかぶって右から薙ぎ（0.26）、返して左から（0.46）、もう一度右から（0.66）。3 連の衝撃に打撃のキーを合わせる
            // （全長 0.74 + 戻り 0.25 = 0.99 秒）
            m.windup(0.12, side: 1, power: 1.0)
            m.hold(0.1)
            m.slash(0.04, side: 1, power: 1.2)
            m.windup(0.1, side: -1, power: 0.9)
            m.slash(0.1, side: -1, power: 1.1)
            m.windup(0.1, side: 1, power: 0.9)
            m.slash(0.1, side: 1, power: 1.2)
            m.hold(0.08)
        case .skill2:
            // 前傾で駆け（0.4 秒）、踏み込みざまに拳を突き出す（全長 0.58 + 戻り 0.25 = 0.83 秒）
            m.dash(0.05, lean: 0.6)
            m.hold(0.25)
            m.lunge(0.06, distance: 0.6, lean: 0.35)
            m.thrust(0.04)
            m.hold(0.08)
            m.settle(0.1)
        case .ultimate:
            // 腰を落として拳に奈落の気を溜め（0.76 秒）、踏み込んで前へ突き出す（全長 1.04 + 戻り 0.35 = 1.39 秒）
            m.brace(0.06, depth: 0.22)
            m.gather(0.14)
            m.hold(0.46) { $0.glow = 2.2; $0.ring = 1.2 }
            m.windup(0.06, side: 1, power: 1.3)
            m.lunge(0.04, distance: 0.5, lean: 0.4)
            m.thrust(0.04)
            m.hold(0.14) { $0.glow = 2.0 }
            m.settle(0.1)
        }
    }
}
