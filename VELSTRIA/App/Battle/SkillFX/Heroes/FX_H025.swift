import Foundation
import VelstriaCore

// スキル演出: H025 月弦のルミナ（Ranger / 三日月の長弓・月光の矢・白と水色の外套。MLBB の Miya の Velstria 版）。
// 主題: 月光。白い芯 × 水色（主）× 明るい水色（副）× 淡い月の青（差し色）× 濃い青の気・青紫の帳（ローカルの色）。
// MLBB の画面収録 vid3（2026-10-16。1108×512・30fps・62.3 px/m。docs/vfx/H025.md）に合わせた。判定・時刻は Kit の値を読む
// （FXSkillInfo.kit = HeroKits.fxValues = LuminaTuning。Tune を写さない。docs/vfx/RANGES.md）。範囲を示す部品（S2 の予告の細い輪・
// 縁の光の帯）は着弾の判定の時刻（s2Land）に見える縁 = 判定の半径（s2Radius）で、外へは消えながらだけ広がる。
// 見せ場の粒の細部（気の炎の舌・弓の先の星・天へ抜ける矢・立ちのぼる光の矢・分裂の閃光・足元の星・三日月のきらめきと紫の霞）は
// Effekseer の効果を段に重ねる（FXCue.efk。Effects/Effekseer/Kit/H025_*.efk、tools/effekseer/heroes/h025_kit.py）。
// 形の主役はメッシュ（Blender の模型 burstDome・月の紋章の画 moonCrest・帯 FXRibbon・コマ送りのメッシュ。CI のシミュレータの撮影に写る）、
// 炎の舌・粒・筋は RealityKit の粒子（実機だけ）。層は 芯（白飛びの手前の閃光）/ 主（気の殻・光の帯・光の柱）/ 副（渦・光の矢・星）/
// 余韻（薄れる光・粒・霞）+ 地面の印（予告の輪・地面の光）、時刻は 溜め → 閃き → 着弾 → 余韻。
//   パッシブ 月環の導き   — 段の増加は体力バーの下の ▼ 印（UI）だけで、世界の演出は無い。Velstria は HUD のバッジで数を出すので、
//                           段が積もるたび（0.4 秒に 1 回まで・5 段まで。隠れ月光が解けて最大の段になる瞬間も）弓の先の小さな閃きだけ。
//                           最大の段の「月影」（体に重なる淡い金の人影が矢を放つ）は、演出の合図が無いので出せない（記録の保留）
//   スキル1 月弦分矢      — 自己強化 4〜9 秒（ランク。自身中心なので cast と impact を発動と同時に再生）。MLBB では発動で矢は飛ばず、
//                           0.07〜0.33 秒に濃い青の気（加算の青）が全身を包んで消える: 肩の閃き → 炎の殻（burstDome・炎の筋が上へ流れて
//                           縁が欠ける）と青い炎の舌（Effekseer）→ 薄れる粒。効果中は弓の先に白い水色の星が時々きらめく（durationFromCast）
//   スキル2 月蝕の矢      — 弓を天へ向けて引き、着弾の skyFall 秒前（s2Land − 0.33 = 0.30 秒。Motion_H025.skyFall）に天へ放つ:
//                           弓の先の星（Effekseer・コマ送りのメッシュ）と天へ抜ける青い矢。着弾点（ゾーンの telegraph = 発動と同時）には
//                           0.05 秒から細い水色の輪（縁 = 判定の半径）と淡い地面の光だけ（MLBB は着弾まで矢の雨を見せない）。
//                           s2Land（0.633 秒）に着弾: 白い芯の閃光 → 縁の輪が太い光の帯になって渦を巻き（縁 = 判定の半径）、中央を白い
//                           三日月の帯（FXRibbon の弧）が回り、地面から矢じりが上の光の矢が昇る。移動不能の敵は水色の光の檻（hit）。
//                           s2Split（0.967 秒）に範囲が白く光り、6 本の小さな矢（本物の投射物）が散る = travel が各矢に付く
//                           （白い光の矢と青い尾。高さ 0.6 m）。impact は「ゾーンの発動」と「小さな矢 6 本それぞれの終わり」の計 7 回
//                           再生されるので、着弾の本体は telegraph（at = s2Land）に置き、impact は小さな閃きだけにする
//   アルティメット 隠れ月光 — 頭上に大きな月の紋章（三日月と波頭の渦の飾り。Blender の模様）が灯り（約 0.4 秒）、そこから青紫の光の柱が
//                           地へ降りて姿を包み（約 0.45 秒、溶けて消える）、足元で水色の星と横に伸びる光（0.1 秒）、柱の中に青い粒、
//                           三日月は紫の霞になって崩れる。姿が薄くなるのは UnitLayer（隠密の不透明度）。隠密 2 秒のあいだの位置を敵に
//                           見せないよう、演出はすべて発動の位置に置き、追従する合図を置かない
// SkillFXDirector は count を読まない: 時刻は at（遅れ）で表す。duration は durationFromCast の合図（S1 の効果中の演出）だけが使う。

enum FX_H025: HeroFXSet {
    // MLBB の Miya の既定スキンの月光（水色の輪 #3DC6E8・白い芯 #F4FCFC・明るい水色 #A8F8FC・三日月 #94CBFF）に合わせる。
    static let palette = FXPalette(core: RGB(0.93, 0.99, 1.0), primary: RGB(0.24, 0.78, 0.92),
                                   secondary: RGB(0.6, 0.95, 1.0), accent: RGB(0.6, 0.8, 1.0),
                                   dark: RGB(0.02, 0.05, 0.14))

    /// スキル1 の濃い青の気（MLBB: 発動前のコマとの差 = 加算の青 (6, 8, 83)。地面と混ざって #3462BC / #557CEF に見える）。
    private static let aura = FXTint.rgb(0.12, 0.22, 1.0)
    /// スキル1 の気の立ち上がりの閃き（f55 の #82A0FD）。
    private static let periwinkle = FXTint.rgb(0.55, 0.66, 1.0)
    /// 奥義の光の柱の青紫（発動前との差 (24, 36, 100)。地面と混ざって #427EBF / #569BE0）。
    private static let veil = FXTint.rgb(0.26, 0.38, 1.0)
    /// 天へ放つ矢・散る矢の筋の青（f330 #2071DB / #4CAFFF）。
    private static let arrowBlue = FXTint.rgb(0.16, 0.48, 0.95)
    /// バインドの光の檻（f356〜368 #5EBCEC / #78EEFF）。
    private static let cage = FXTint.rgb(0.45, 0.82, 1.0)
    /// 奥義の三日月（#94CBFF、芯 #E2FCFF）と、崩れる紫の霞（f409〜412）。
    private static let moonBlue = FXTint.rgb(0.62, 0.84, 1.0)
    private static let wisp = FXTint.rgb(0.6, 0.45, 1.0)

    /// Effekseer の効果（Effects/Effekseer/Kit/）。s2_land / s2_split は判定の半径 1.7 m で作った（倍率 = 半径 / 1.7）。
    private static let efkAura = "H025_s1_aura"
    private static let efkBowStar = "H025_bow_star"
    private static let efkSky = "H025_s2_sky"
    private static let efkLand = "H025_s2_land"
    private static let efkSplit = "H025_s2_split"
    private static let efkUltFlash = "H025_ult_flash"
    private static let efkUltMoon = "H025_ult_moon"
    private static let landDesignRadius: Float = 1.7

    // MARK: - sim の時刻・寸法
    // LuminaTuning の値は写さず、FXSkillInfo（HeroKits.fxValues）から読む（照準の表示・判定・演出が同じ値。docs/vfx/RANGES.md）:
    //   S1 s1Duration（効果時間の表。実際の長さは発動のイベントの duration）
    //   S2 s2Radius（着弾の半径）・s2Land（着弾 = ゾーンの発動の時刻）・s2Split（6 本に分かれる時刻）・s2Root（バインド）・
    //      s2ArrowSpeed / s2ArrowRange（小さな矢の速さ・射程）

    // MARK: - 見た目の寸法（動画で測った値・推定。sim には無い）

    /// 弓を構えた左手の先（局所座標）。
    private static let bow: SIMD3<Float> = [-0.08, 1.35, 0.65]
    /// 天へ向けて引いた弓の先（スキル2。Motion_H025.eclipse の約 45° 上の満引き = 左肩から前と上へ 0.55 m）。
    private static let bowHigh: SIMD3<Float> = [-0.06, 1.75, 0.42]
    /// 奥義の三日月の中心（頭上。画面の位置から逆算した推定）。
    private static let crown: SIMD3<Float> = [0, 3.5, 0]

    // MARK: - 部品

    /// 縦に立つ矢（円盤を横倒しにした板。up なら矢じりが上、そうでなければ下）。中心が原点。
    /// repeated(2, yaw: 90) で直交する 2 枚にすると、どの向きから見ても読める。
    private static func uprightArrow(length: Float, width: Float, _ tint: FXTint, life: Float, up: Bool,
                                     alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .disc, tex: .arrow, tint: tint, alpha: alpha, size: [length, 1, width],
               sizeEnd: [length, 1, width], ease: .linear, life: life, fadeIn: 0.05, fadeOut: 0.75, yaw: 45,
               roll: up ? 90 : -90)
    }

    /// 円い模様の板の一辺: 見える縁（板の FXEdge.radial(tex) 倍）が半径 r になる大きさ。
    private static func edgeSize(_ r: Float, _ tex: FXTex) -> SIMD3<Float> {
        let side = r / (FXEdge.radial(tex) ?? 0.4575)
        return [side, 1, side]
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
            // 段が積もるたび（MLBB は ▼ 印の UI だけ）: 弓の先の小さな水色の閃きと、胸元から昇る数粒の光
            r.cast = [
                .emit(.flare(0.5, .secondary, life: 0.12, tex: .flare4), .follow, offset: bow),
                .emit(.motes(4, radius: 0.22, .primary, life: 0.45, size: 0.06, rise: 1.0), .follow, offset: [0, 1.25, 0]),
            ]
            // パッシブ由来のスキルのダメージは無い（月影は通常攻撃）
            r.hit = glint(.secondary)
            return r
        case .skill1:
            return moonArrow(s)
        case .skill2:
            return eclipse(s)
        case .ultimate:
            return hiddenMoonlight()
        }
    }

    // MARK: - スキル1 月弦分矢

    /// 自己強化（4〜9 秒）。MLBB: 指を離して 2 コマ後（f54）に肩が青紫に閃き、f55〜60 に濃い青の気が全身（幅 1.8 m・高さ 2 m）を包み、
    /// 縁が炎のように上へ揺れ、f62（0.33 秒）に消える。モーション（Motion_H025）は 0.06 秒に弓を胸へ引き寄せ、0.18 秒に胸を開く。
    private static func moonArrow(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let buff = max(1, s.seconds("s1Duration"))
        r.cast = [
            // 芯: 0.04 肩の青紫の閃き（f54〜55）
            .emit(.flare(1.0, periwinkle, life: 0.12, tex: .flare4), at: 0.04, .follow, offset: [0, 1.45, 0.05]),
            // 主: 0.05〜0.35 全身を包む濃い青の気 — 柔らかい光が膨らみ、炎の殻（burstDome の模型。炎の筋が上へ流れて縁から欠ける）が
            // 体を覆う（加算の青。体の上に描く = MLBB も体が青く染まる）
            .mesh(FXMesh.sprite(.glow, 2.1, aura, life: 0.3, grow: 1.12, alpha: 0.95).glowing().with {
                $0.fadeIn = 0.3
                $0.fadeOut = 0.5
            }, at: 0.04, .follow, offset: [0, 1.0, 0]),
            .mesh(FXMesh.model(.burstDome, nil, aura, size: [0.75, 1.6, 0.75], sizeEnd: [0.95, 2.0, 0.95], life: 0.3, alpha: 1)
                .glowing().flowing(.flame, scroll: [0.15, -1.8], tiling: 1.6, strength: 0.85, erosion: 0.4, edge: periwinkle).with {
                    $0.fadeIn = 0.22
                    $0.fadeOut = 0.5
                    $0.spin = 60
                    $0.onTop = true
                }, at: 0.05, .follow),
            // 副: 上へ揺れる青い炎の舌・昇る水色の粒（Effekseer。3D の上）と、気の縁の炎の舌（コマ送りの粒子。実機）
            .efk(efkAura, at: 0.04, .follow, onTop: true),
            .emit(.sheet(.flameLoop, 0.85, aura, end: periwinkle, count: 6, life: 0.28, orient: .upright, radius: 0.32).with {
                $0.speed = 0.9
            }, at: 0.06, .follow, offset: [0, 0.45, 0]),
            // 効果中（4〜9 秒 = 発動のイベントの duration）: 弓の先に白い水色の星が時々きらめく
            // （MLBB は矢を放つたびに弓の先で閃く。Velstria の通常攻撃の弾は汎用の演出なので、ここで代わりに見せる）
            .emit(.trail(.twinkle, .secondary, rate: 3, life: 0.3, size: 0.32).with {
                $0.duration = buff
                $0.durationFromCast = true
                $0.sheet = .sparkTwinkle
                $0.sheetRandomStart = true
                $0.tintEnd = .core
                $0.speed = 0.1
            }, .follow, offset: bow),
        ]
        // 地面の印（自身中心なので発動と同時に再生）: 足元に広がる青い気（地面の柔らかい光。加算）
        r.impact = [
            .mesh(FXMesh.decal(.glow, 1.9, aura, life: 0.34, spin: 0, grow: 1.1, alpha: 0.6).glowing(), at: 0.05, .follow),
        ]
        // 連弾の矢は通常攻撃の弾（スキルのダメージではない）ので被弾演出は出ない
        r.hit = glint(.secondary)
        return r
    }

    // MARK: - スキル2 月蝕の矢

    /// 天へ放つ（s2Land − skyFall）→ 着弾点に細い輪だけ（0.05〜s2Land）→ 着弾（s2Land）: 白い芯の閃光・渦を巻く光の帯・回る白い帯・
    /// 昇る光の矢 → 範囲が白く光って 6 本の小さな矢が散る（s2Split、travel）。R = 判定の半径（s2Radius）。
    private static func eclipse(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.meters("s2Radius")
        let land = s.seconds("s2Land")
        let split = s.seconds("s2Split")
        let rootTime = s.seconds("s2Root")
        let speed = s.speed("s2ArrowSpeed")
        let minorTime = speed > 0 ? s.meters("s2ArrowRange") / speed : 0.32
        let shoot = max(0.18, land - Motion_H025.skyFall)
        let skyward = bowHigh + SIMD3<Float>(0, 0.5, 0)
        let k = R / landDesignRadius
        r.cast = [
            // 0.30: 天へ放つ瞬間、弓の先で水色の星が閃く（f329 #7BDBFD / #9EFAFE）。コマ送りのメッシュ + Effekseer
            .mesh(FXMesh.flipbook(.hitFlash, 1.0, .secondary, life: 0.16, grow: 1.1), at: shoot, offset: bowHigh),
            .efk(efkBowStar, at: shoot, offset: bowHigh, scale: 0.7, onTop: true),
            // 天へ抜ける青い矢（f329〜331: 3 本の青い筋）: Effekseer の矢と、矢じりの見える主矢（直交する 2 枚の板）・速さに沿って伸びる光の筋
            .efk(efkSky, at: shoot, offset: bowHigh, onTop: true),
            .mesh(uprightArrow(length: 1.5, width: 0.45, arrowBlue, life: 0.16, up: true).with { $0.rise = 20 }.glowing(),
                  at: shoot, offset: skyward).repeated(2, yaw: 90),
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: arrowBlue, count: 3, emit: 0.04, life: 0.14, lifeVar: 0.1,
                         size: 0.18, sizeVar: 0.2, grow: 1, shape: .sphere(0.2), dir: .local([0, 1, 0.3]), speed: 22,
                         speedVar: 0.1, spread: 5, stretch: 4, fade: .linearFadeOut), at: shoot, offset: skyward),
        ]
        // ゾーンの telegraph は発動と同時に着弾点で再生される（中心が原点）。着弾の本体もここに at = s2Land で置く
        var tele: [FXCue] = [
            // 地面の印: 0.05〜着弾 細い水色の輪（MLBB f322〜338 #3DC6E8 / #62E3F6。地面に描く線）。見える縁 = 判定の半径 R
            // （以前は板の一辺を半径 ÷ 0.44 + 5 cm にしていて +7%）。着弾の 0.05 秒後まで残して消える
            .mesh(FXMesh(shape: .disc, tex: .ring, tint: .primary, alpha: 0.95, size: edgeSize(R, .ring), sizeEnd: edgeSize(R, .ring),
                         ease: .linear, life: land + 0.03, fadeIn: 0.15, fadeOut: 0.88), at: 0.05),
            // 輪の中の淡い光（MLBB f336〜338 の淡い満ち。範囲は示さない柔らかい光）
            .mesh(FXMesh.decal(.glow, R * 2.1, .primary, life: land - 0.05, spin: 0, grow: 1.0, alpha: 0.16).glowing().with {
                $0.fadeIn = 0.4
                $0.fadeOut = 0.8
            }, at: 0.05),
            // 芯: 着弾の中心の白い閃光（f339 #F4FCFC。白飛びの手前のアルファ）と、白い芯・水色の放射の光・立ちのぼる光の矢・縁のきらめき（Effekseer）
            .mesh(FXMesh.sprite(.glowHard, 1.8, .core, life: 0.14, grow: 1.6, alpha: 0.9).glowing().with { $0.onTop = true }, at: land,
                  offset: [0, 0.8, 0]),
            .efk(efkLand, at: land, scale: k, onTop: true),
            // 中心から縁へ走る白い衝撃の輪（コマ送りのメッシュ。範囲の縁ではない飾り）
            .mesh(FXMesh.groundFlipbook(.shockRing, R * 1.8, .core, life: 0.3, onTop: false), at: land, offset: [0, 0.04, 0]),
            // 主: 縁の輪が太い光の帯に変わり、筋の模様が輪に沿って流れて渦を巻く（f340〜348 #A8F8FC。散る瞬間まで）。
            // 着弾の瞬間に外縁 = R、消えながら 1.02R まで（外へは消えながらだけ）
            .mesh(FXMesh.halo(R, .secondary, life: split - land + 0.05, spin: 200, tex: .beam, alpha: 1).with {
                $0.size = [R, 1, R]
                $0.sizeEnd = [R * 1.02, 1, R * 1.02]
                $0.ease = .out
                $0.fadeIn = 0.0
                $0.fadeOut = 0.7
            }.glowing().flowing(.streaks, scroll: [1.6, 0], tiling: 3, strength: 0.7, erosion: 0.3, edge: .core), at: land),
            // 副: 中央を回る白い三日月の帯（f340〜342 の白い弧が輪の内側を一周する。帯の頭が 0.2 秒で 1.1 周）と、白い渦
            .ribbon(FXRibbon.swing(radius: R * 0.82, from: 20, to: 420, height: 0.12, roll: 0, duration: 0.2, life: 0.12, width: 0.55,
                                   .core).with {
                $0.ease = .out
                $0.onTop = false
            }, at: land + 0.01),
            .mesh(FXMesh.decal(.swirl, R * 1.4, .core, life: 0.3, spin: -480, grow: 1.2, alpha: 0.9).glowing(), at: land + 0.02),
            // 余韻: 地面に残る淡い水色の光（散る瞬間まで）
            .mesh(FXMesh.decal(.glow, R * 2.0, .secondary, life: split - land + 0.2, spin: 0, grow: 1.0, alpha: 0.3).glowing().with {
                $0.fadeIn = 0.05
                $0.fadeOut = 0.55
            }, at: land),
            // 輪の中の地面から上へ昇る光の矢（矢じりが上。f340〜348 の白〜青の縦の矢 #5EBAF7。粒子は実機）
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: arrowBlue, count: 16, emit: 0.26, life: 0.3, lifeVar: 0.15,
                         size: 0.13, sizeVar: 0.3, grow: 0.8, shape: .disc(R * 0.85), dir: .up, speed: 3.5, speedVar: 0.3,
                         stretch: 3.6, fade: .gradualFadeInOut), at: land + 0.03, offset: [0, 0.2, 0]),
            // 分裂（s2Split）: 範囲に満ちる白い光（f349〜350 #F6FBFD。地面の光 + 低い光の円柱、円柱の下端は範囲の内側）と閃光・
            // Effekseer の白い光の柱と放射の筋（以前の高さ 2.4 m の円柱は上から見ると青い泡に見えた。2026-10-21 の撮影）
            .mesh(FXMesh.decal(.glow, R * 2.0, .core, life: 0.2, spin: 0, grow: 1.05, alpha: 0.75).glowing().with {
                $0.fadeIn = 0.05
                $0.fadeOut = 0.4
            }, at: split),
            .mesh(FXMesh(shape: .cylinder, tex: .beam, tint: .core, alpha: 0.5, size: [R * 0.8, 0.3, R * 0.8],
                         sizeEnd: [R * 0.88, 1.2, R * 0.88], ease: .out, life: 0.18, fadeIn: 0.05, fadeOut: 0.35).glowing(),
                  at: split),
            .efk(efkSplit, at: split, scale: k, onTop: true),
            .emit(.flare(2.6, .core, life: 0.14, tex: .flare6), at: split, offset: [0, 0.7, 0]),
            .shake(0.12, at: land),
        ]
        // 矢じりの見える光の矢 1 本（直交する 2 枚の板。着弾の直後にゆっくり昇りながら消える。CI の撮影にも写る。残りの矢は Effekseer）
        let standing: [SIMD3<Float>] = [[0.62, 0.65, 0.3]]
        for (n, p) in standing.enumerated() {
            tele.append(.mesh(uprightArrow(length: 1.25, width: 0.4, .core, life: 0.3, up: true).with { $0.rise = 1.6 }.glowing(),
                              at: land + 0.03 + 0.06 * Float(n), offset: p * (R / landDesignRadius)).repeated(2, yaw: 90))
        }
        r.telegraph = tele
        // 6 本の小さな矢（本物の投射物。前方 = 飛ぶ向き。MLBB の高さ 0.5〜0.6）: 白い光の矢と後ろへ伸びる青い尾（どちらも細い板 =
        // 判定の幅を示さない飾り）。帯（FXRibbon）は 6 本同時に使うとプールが足りないので、尾は板で描く
        r.travel = [
            .mesh(FXMesh(shape: .disc, tex: .arrow, tint: .core, alpha: 1, size: [1.4, 1, 0.42], sizeEnd: [1.4, 1, 0.42],
                         ease: .linear, life: minorTime + 0.06, fadeIn: 0.02, fadeOut: 0.85, yaw: 90).glowing(), .follow,
                  offset: [0, 0.6, 0]),
            .mesh(FXMesh(shape: .disc, tex: .streak, tint: arrowBlue, alpha: 0.85, size: [0.6, 1, 0.5], sizeEnd: [1.7, 1, 0.42],
                         ease: .out, life: minorTime + 0.06, fadeIn: 0.02, fadeOut: 0.8, yaw: 90).glowing(), .follow,
                  offset: [0, 0.6, -0.55]),
            .emit(.trail(.streak, .primary, rate: 40, life: 0.14, size: 0.2).with {
                $0.dir = .backward
                $0.speed = 3
                $0.stretch = 2.6
                $0.tintEnd = arrowBlue
            }, .follow, offset: [0, 0.6, 0], quality: 1),
        ]
        // ゾーンの発動（中心）と、小さな矢 6 本それぞれの終わり（命中・射程の端）: 小さな閃きだけ（MLBB の矢は消えるだけ）
        r.impact = [
            .emit(.flare(0.7, .secondary, life: 0.1, tex: .flare4), offset: [0, 0.6, 0]),
        ]
        // 移動不能（着弾。s2Root 秒）: 白い閃き + 水色の光の檻（下の縁が明るく上へ薄れる円柱・半径 0.6・高さ 1.15。f345〜372。
        // 縦の筋がゆっくり昇り、終わりに溶けて消える）と足元の輪
        r.hit = [
            .emit(.sheet(.hitFlash, 1.1, .core, end: .secondary, life: 0.16), offset: [0, 1.0, 0]),
            .mesh(FXMesh(shape: .cylinder, tex: .beam, tint: cage, alpha: 0.55, size: [0.5, 1.15, 0.5],
                         sizeEnd: [0.62, 1.15, 0.62], ease: .out, life: rootTime, fadeIn: 0.04, fadeOut: 0.85)
                .flowing(.streaks, scroll: [0, -0.8], tiling: 3, strength: 0.45, edge: .secondary)
                .dissolving(from: 0.78, edge: .secondary, width: 0.08), .follow),
            .mesh(FXMesh(shape: .disc, tex: .ring, tint: .secondary, alpha: 1, size: edgeSize(0.62 * 0.85, .ring),
                         sizeEnd: edgeSize(0.62, .ring), ease: .out, life: rootTime, fadeIn: 0.1, fadeOut: 0.85).glowing(), .follow),
        ]
        return r
    }

    // MARK: - アルティメット 隠れ月光

    /// 月光の帳に包まれて月影に紛れる（隠密 2 秒・弱体の解除・加速）。演出は発動の位置に置く（隠れた位置を敵に見せない）。
    /// MLBB: f400（発動の次のコマ）頭上に大きな三日月（波頭の渦の飾り）→ f401〜412 その下から青紫の光の柱が地へ降りる →
    /// f402〜404 足元の閃光と横に伸びる光 → f405〜412 柱の中に青い光の粒 → f409〜 三日月が紫の霞になって崩れる。
    private static func hiddenMoonlight() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        r.cast = [
            // 主: 0.03〜0.48 頭上の月の紋章（Blender の模様 moonCrest: 外縁の明るい線・内縁の細い線・渦の飾り。直径 1.9 m・#94CBFF）と、
            // その後ろの柔らかい青い光。消え際は紫の縁で溶ける
            .mesh(FXMesh.sprite(.glow, 2.6, veil, life: 0.42, grow: 1.05, alpha: 0.5).glowing().with {
                $0.fadeIn = 0.15
                $0.fadeOut = 0.55
            }, at: 0.03, offset: crown),
            // 紋章の下に同じ形の濃い青（アルファ合成）を敷いて、明るい地面・壁の前でも縁が読めるようにする
            .mesh(FXMesh.sprite(.moonCrest, 2.2, .rgb(0.16, 0.3, 0.85), life: 0.45, grow: 1.06, alpha: 0.5).with {
                $0.fadeIn = 0.1
                $0.fadeOut = 0.7
            }, at: 0.03, offset: crown + SIMD3<Float>(0, 0, -0.02)),
            .mesh(FXMesh.sprite(.moonCrest, 2.1, moonBlue, life: 0.45, grow: 1.06, alpha: 1).glowing().with {
                $0.fadeIn = 0.1
                $0.fadeOut = 0.75
            }.dissolving(from: 0.6, edge: wisp, width: 0.12), at: 0.03, offset: crown),
            .efk(efkUltMoon, at: 0.03, offset: crown, onTop: true),
            // 0.05〜0.53 三日月から地へ降りる青紫の光の柱（半径 1.0。円柱を逆さに吊るして下へ伸ばす。加算・筋が流れ、終わりに溶ける）
            // カメラを向く柔らかい光の柱（幅 2 m。MLBB の柱は上から見ても一様な帯）を重ねる
            .mesh(FXMesh(shape: .billboard, tex: .glow, tint: veil, alpha: 0.5, size: [1.9, 2.4, 1], sizeEnd: [2.1, 3.4, 1],
                         ease: .out, life: 0.46, fadeIn: 0.15, fadeOut: 0.55).glowing(), at: 0.05, offset: [0, 1.8, 0]),
            .mesh(FXMesh(shape: .cylinder, tex: .beam, tint: veil, alpha: 0.55, size: [0.85, 0.5, 0.85],
                         sizeEnd: [1.0, 3.4, 1.0], ease: .out, life: 0.48, fadeIn: 0.12, fadeOut: 0.6, roll: 180).glowing()
                .flowing(.streaks, scroll: [0, -0.8], tiling: 3, strength: 0.4, edge: .accent)
                .dissolving(from: 0.55, edge: wisp, width: 0.1), at: 0.05, offset: crown),
            // 芯: 0.1 足元の閃光（水色の星と、横に伸びる光。#82CFFF）。コマ送りのメッシュ・板 + Effekseer の星・横の光・柱の中の青い粒
            .mesh(FXMesh.flipbook(.hitFlash, 1.5, .core, life: 0.16, grow: 1.1), at: 0.1, offset: [0, 0.35, 0]),
            .mesh(FXMesh(shape: .billboard, tex: .glow, tint: .secondary, alpha: 1, size: [2.6, 0.22, 1],
                         sizeEnd: [3.4, 0.12, 1], ease: .out, life: 0.16, fadeIn: 0.04, fadeOut: 0.4).glowing().with { $0.onTop = true },
                  at: 0.1, offset: [0, 0.35, 0]),
            .efk(efkUltFlash, at: 0.1, onTop: true),
            // 余韻: 柱の中に漂う青い光の粒（粒子は実機）
            .emit(.motes(10, radius: 0.8, .rgb(0.4, 0.6, 1.0), life: 0.6, size: 0.09, rise: 0.4), at: 0.18,
                  offset: [0, 0.45, 0]),
        ]
        // 地面の印（自身中心なので発動と同時に再生）: 柱が地に着く所の淡い光と、足元の細い水色の輪（f399〜402）
        r.impact = [
            .mesh(FXMesh.decal(.glow, 2.3, veil, life: 0.5, spin: 0, grow: 1.0, alpha: 0.5).glowing(), at: 0.12),
            .mesh(FXMesh(shape: .disc, tex: .ring, tint: .secondary, alpha: 0.6, size: edgeSize(0.75, .ring), sizeEnd: edgeSize(0.9, .ring),
                         ease: .out, life: 0.36, fadeIn: 0.1, fadeOut: 0.5).glowing(), at: 0.02),
        ]
        // ダメージは無い
        r.hit = glint(.accent)
        return r
    }

    // MARK: - 詠唱モーション
    // 全身のモーション（App/Battle/Heroes/Motions/Motion_H025.swift。HeroSkillMotions の目録）が優先される。下は目録から外した時の
    // 上半身だけの詠唱（2026-10-17 以前のまま）。

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 弦を引き絞って月光を宿し、0.1 秒で離す（MLBB の発動は矢を放たず気をまとうだけ）
            m.draw(0.08, up: 0.08)
            m.release(0.04)
            m.hold(0.14) { $0.glow = 1.8 }
        case .skill2:
            // 弓を天へゆっくり向けて引き（画面収録: 指を離してから 0.27〜0.32 秒）、0.32 秒で放ち、矢が落ちるまで空を見上げる
            // （0.32 + 0.2 + 0.1 + 戻り 0.25 = 0.87 秒）
            m.draw(0.12, up: 0.35)
            m.draw(0.16, up: 0.75)
            m.release(0.04)
            m.hold(0.2) { $0.glow = 1.6; $0.headPitch = -0.35 }
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
