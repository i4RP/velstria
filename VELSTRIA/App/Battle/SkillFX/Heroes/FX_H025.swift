import Foundation
import VelstriaCore

// スキル演出: H025 月弦のルミナ（Ranger / 三日月の長弓・月光の矢・白と水色の外套。MLBB の Miya の Velstria 版）。
// 主題: 月光。白い芯 × 水色（主）× 明るい水色（副）× 淡い月の青（差し色）× 濃い青の気・青紫の帳（ローカルの色）。
// 2026-10-17 に MLBB の画面収録（vid3、docs/vfx/H025.md）に合わせて作り直した。MLBB の見え方:
//   パッシブ 月環の導き   — 段の増加は体力バーの下の ▼ 印（UI）だけで、世界の演出は無い。Velstria は HUD のバッジで数を出すので、
//                           段が積もるたび（0.4 秒に 1 回まで・5 段まで。隠れ月光が解けて最大の段になる瞬間も）弓の先の小さな閃きだけ。
//                           最大の段の「月影」（体に重なる淡い金の人影が矢を放つ）は、演出の合図が無いので出せない（記録の保留）
//   スキル1 月弦分矢      — 自己強化 4〜9 秒（ランク。自身中心なので cast と impact を発動と同時に再生）。MLBB では発動で矢は飛ばず、
//                           0.07〜0.33 秒に濃い青の気（加算の青）が全身を包んで消える。分裂の矢は通常攻撃の弾（汎用の演出）。
//                           効果中は弓の先に白い水色の星が時々きらめく（MLBB は矢を放つたびに弓の先で閃く。長さは発動のイベントの
//                           duration = 効果時間。0 なら書いた 4 秒: durationFromCast）
//   スキル2 月蝕の矢      — 弓を天へ向けて引き、約0.27秒で天へ矢を放つ（2026-10-23 の収録に更新）: 弓の先で水色の星が閃き、
//                           青い矢が天へ抜ける。着弾点（ゾーンの telegraph = 発動と同時）には 0.05 秒から細い水色の輪だけが出る
//                           （MLBB では着弾まで矢の雨は見えない）。0.65 秒（s2Delay）に着弾: 白い閃光 → 縁の輪が太い光の帯になって渦を巻き、
//                           中央を白い渦が回り、地面から矢じりが上の光の矢が昇る。移動不能 1.2 秒の敵は水色の光の檻（下が明るい円柱）に入る（hit）。
//                           着弾の 0.33 秒後（0.98 秒、s2SplitDelay）に範囲が白く光り、6 本の小さな矢（本物の投射物）が撃った向きから
//                           0° / ±60° / ±120° / 180° へ散る = travel が各矢に付く（毎秒 12.5 m で 4 m、0.32 秒。高さ 0.6 m）。
//                           impact は「ゾーンの発動」と「小さな矢 6 本それぞれの終わり（命中・射程の端）」の計 7 回再生されるので、
//                           着弾の本体は telegraph（at = 0.65）に置き、impact は小さな閃きだけにする
//   アルティメット 隠れ月光 — 頭上に大きな三日月が灯り（約 0.4 秒）、そこから青紫の光の柱が地へ降りて姿を包み（約 0.45 秒）、
//                           足元で水色の閃光（0.1 秒）、柱の中に青い光の粒が漂う。姿が薄くなるのは UnitLayer（隠密の不透明度）。
//                           隠密 2 秒のあいだの位置を敵に見せないよう、演出はすべて発動の位置に置き、追従する合図を置かない
// 光る部品（閃光・光の柱・光の帯・渦・矢）は加算（glowing）。着弾前の細い輪・光の檻の円柱はアルファ合成（地面の上の線・ガラスの檻）。
// SkillFXDirector は count を読まない: 時刻は at（遅れ）で表す。duration は durationFromCast の合図（S1 の効果中の演出）だけが使う。
// 奥義の隠密（2 秒）は位置を見せないため、効果の長さに合わせて追従する合図を置かない。

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

    // MARK: - sim の時刻・寸法（Kit_H025.LuminaTuning と同じ値。sim を変えたらここも合わせる）

    /// スキル1 の効果時間（s1Duration のランク 1。実際の長さ（ランクで 4→9 秒）は発動のイベントの duration から取る）。
    private static let buffTime: Float = 4
    /// スキル2: 着弾までの遅れ（s2Delay 0.65）・半径（s2Radius 170）・移動不能（s2Root）。
    private static let eclipseDelay: Float = 0.65
    private static let eclipseRadius: Float = 1.7
    private static let rootTime: Float = 1.2
    /// 2026-10-23 の収録: 構え始め6.38秒前後 → 矢が見える6.65秒前後。専用クリップの8フレーム目。
    private static let eclipseShoot: Float = 8.0 / 30.0
    /// 6 本の小さな矢が散る時刻（着弾 + s2SplitDelay 0.33）。
    private static let eclipseSplit: Float = 0.98
    /// 小さな矢が射程の端（400）へ着くまで（速度 1250）。
    private static let minorArrowTime: Float = 0.32

    /// 弓を構えた左手の先（局所座標）。
    private static let bow: SIMD3<Float> = [-0.1, 1.35, 0.6]
    /// 天へ向けて引いた弓の先（スキル2）。
    private static let bowHigh: SIMD3<Float> = [-0.1, 1.85, 0.45]

    // MARK: - 部品

    /// 縦に立つ矢（円盤を横倒しにした板。up なら矢じりが上、そうでなければ下）。中心が原点。
    /// repeated(2, yaw: 90) で直交する 2 枚にすると、どの向きから見ても読める。
    private static func uprightArrow(length: Float, width: Float, _ tint: FXTint, life: Float, up: Bool,
                                     alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .disc, tex: .arrow, tint: tint, alpha: alpha, size: [length, 1, width],
               sizeEnd: [length, 1, width], ease: .linear, life: life, fadeIn: 0.05, fadeOut: 0.75, yaw: 45,
               roll: up ? 90 : -90)
    }

    /// 地面の細い光の輪（半径 r の所に線。.ring の画像は一辺の 0.44 倍の半径に線がある）。from = 始まりの大きさの比。
    private static func groundRing(_ r: Float, _ tint: FXTint, life: Float, alpha: Float = 1, from: Float = 1) -> FXMesh {
        let d = r / 0.44
        return FXMesh(shape: .disc, tex: .ring, tint: tint, alpha: alpha, size: [d * from, 1, d * from], sizeEnd: [d, 1, d],
                      ease: .out, life: life, fadeIn: 0.1, fadeOut: 0.85)
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
            return moonArrow()
        case .skill2:
            return eclipse()
        case .ultimate:
            return hiddenMoonlight()
        }
    }

    // MARK: - スキル1 月弦分矢

    /// 自己強化（4〜9 秒）。MLBB: 指を離して 2 コマ後（f54）に肩が青紫に閃き、f55〜60 に濃い青の気が全身を包み、f62（0.33 秒）に消える。
    private static func moonArrow() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        r.cast = [
            // 0.04: 肩の青紫の閃き（f54〜55）
            .emit(.flare(1.0, periwinkle, life: 0.12, tex: .flare4), at: 0.04, .follow, offset: [0, 1.45, 0.05]),
            // 0.04〜0.34: 全身を包む濃い青の気（柔らかい光が膨らみ、下から上へ揺らいで縁から欠ける殻。どちらも加算）
            .mesh(FXMesh.sprite(.glow, 2.0, aura, life: 0.3, grow: 1.12, alpha: 0.85).glowing().with {
                $0.fadeIn = 0.3
                $0.fadeOut = 0.5
            }, at: 0.04, .follow, offset: [0, 1.0, 0]),
            .mesh(FXMesh(shape: .cylinder, tex: .beam, tint: aura, alpha: 0.9, size: [0.42, 1.3, 0.42],
                         sizeEnd: [0.6, 2.0, 0.6], ease: .out, life: 0.3, fadeIn: 0.25, fadeOut: 0.5).glowing()
                .flowing(.noise, scroll: [0.3, -1.8], tiling: 2.5, strength: 0.8, erosion: 0.55, edge: periwinkle),
                  at: 0.05, .follow),
            // 気の縁で上へ揺れる青い炎の舌（コマ送り）
            .emit(.sheet(.flameLoop, 0.85, aura, end: periwinkle, count: 6, life: 0.28, orient: .upright, radius: 0.32).with {
                $0.speed = 0.9
            }, at: 0.06, .follow, offset: [0, 0.45, 0]),
            // 効果中（4〜9 秒 = 発動のイベントの duration）: 弓の先に白い水色の星が時々きらめく
            // （MLBB は矢を放つたびに弓の先で閃く。Velstria の通常攻撃の弾は汎用の演出なので、ここで代わりに見せる）
            .emit(.trail(.twinkle, .secondary, rate: 3, life: 0.3, size: 0.32).with {
                $0.duration = buffTime
                $0.durationFromCast = true
                $0.sheet = .sparkTwinkle
                $0.sheetRandomStart = true
                $0.tintEnd = .core
                $0.speed = 0.1
            }, .follow, offset: bow),
        ]
        // 自身中心なので発動と同時に再生: 足元に広がる青い気（地面の柔らかい光。加算）
        r.impact = [
            .mesh(FXMesh.decal(.glow, 1.9, aura, life: 0.34, spin: 0, grow: 1.1, alpha: 0.6).glowing(), at: 0.05, .follow),
        ]
        // 連弾の矢は通常攻撃の弾（スキルのダメージではない）ので被弾演出は出ない
        r.hit = glint(.secondary)
        return r
    }

    // MARK: - スキル2 月蝕の矢

    /// 天へ放つ（約0.27）→ 着弾点に細い輪だけ（0.05〜0.65）→ 着弾（0.65）: 白い閃光・渦を巻く光の帯・昇る光の矢 →
    /// 範囲が白く光って 6 本の小さな矢が散る（0.98、travel）。
    private static func eclipse() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = eclipseRadius
        let land = eclipseDelay
        let shoot = eclipseShoot
        let split = eclipseSplit
        let skyward = bowHigh + SIMD3<Float>(0, 0.5, 0)
        r.cast = [
            // 離弦: 弓の先で水色の星が閃く（色は旧収録 f329 #7BDBFD / #9EFAFE）
            .emit(.sheet(.hitFlash, 1.3, .secondary, end: .primary, life: 0.16), at: shoot, offset: bowHigh),
            // 天へ抜ける青い矢（f329〜331: 3 本の青い筋。速さに沿って伸びる光の筋）と、矢じりの見える主矢（直交する 2 枚の板）
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: arrowBlue, count: 3, emit: 0.04, life: 0.14, lifeVar: 0.1,
                         size: 0.18, sizeVar: 0.2, grow: 1, shape: .sphere(0.2), dir: .local([0, 1, 0.3]), speed: 22,
                         speedVar: 0.1, spread: 5, stretch: 4, fade: .linearFadeOut), at: shoot, offset: skyward),
            .mesh(uprightArrow(length: 1.5, width: 0.45, arrowBlue, life: 0.16, up: true).with { $0.rise = 20 }.glowing(),
                  at: shoot, offset: skyward).repeated(2, yaw: 90),
        ]
        // ゾーンの telegraph は発動と同時に着弾点で再生される（中心が原点）。着弾の本体もここに at = 0.65 で置く
        var tele: [FXCue] = [
            // 0.05〜0.65: 着弾点に細い水色の輪（照準の円の縁。MLBB f322〜338 #3DC6E8 / #62E3F6・半径 1.76。地面に描く線）
            .mesh(groundRing(R + 0.05, .primary, life: land - 0.03, alpha: 0.95), at: 0.05),
            // 0.65 着弾: 中心の白い閃光（f339 #F4FCFC）と、中心から縁へ走る白い衝撃の輪（コマ送り）
            .mesh(FXMesh.sprite(.glowHard, 1.8, .core, life: 0.14, grow: 1.6).glowing(), at: land, offset: [0, 0.8, 0]),
            .emit(.groundSheet(.shockRing, R * 1.8, .core, life: 0.3), at: land, offset: [0, 0.05, 0]),
            // 縁の輪が太い光の帯に変わり、筋の模様が輪に沿って流れて渦を巻く（f340〜348 #A8F8FC。散る瞬間まで）
            .mesh(FXMesh.halo(R, .secondary, life: split - land + 0.03, spin: 200, tex: .beam, alpha: 1).with {
                $0.size = [R * 0.92, 1, R * 0.92]
                $0.sizeEnd = [R * 1.02, 1, R * 1.02]
                $0.ease = .out
                $0.fadeIn = 0.1
                $0.fadeOut = 0.75
            }.glowing().flowing(.streaks, scroll: [1.6, 0], tiling: 3, strength: 0.7, erosion: 0.3, edge: .core), at: land),
            // 中央を回る白い渦（f341〜344 の白い三日月の渦）
            .mesh(FXMesh.decal(.swirl, R * 1.4, .core, life: 0.3, spin: -480, grow: 1.2, alpha: 1).glowing(), at: land + 0.02),
            // 0.68〜0.95: 輪の中の地面から上へ昇る光の矢（矢じりが上。f340〜348 の白〜青の縦の矢 #5EBAF7）
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: arrowBlue, count: 16, emit: 0.26, life: 0.3, lifeVar: 0.15,
                         size: 0.13, sizeVar: 0.3, grow: 0.8, shape: .disc(R * 0.85), dir: .up, speed: 3.5, speedVar: 0.3,
                         stretch: 3.6, fade: .gradualFadeInOut), at: land + 0.03, offset: [0, 0.2, 0]),
            // 0.98 分裂: 範囲に満ちる白い光（f349〜350 #F6FBFD）
            .mesh(FXMesh(shape: .cylinder, tex: .beam, tint: .core, alpha: 0.9, size: [R * 0.85, 0.6, R * 0.85],
                         sizeEnd: [R * 0.9, 2.4, R * 0.9], ease: .out, life: 0.2, fadeIn: 0.05, fadeOut: 0.35).glowing(),
                  at: split),
            .emit(.flare(2.6, .core, life: 0.14, tex: .flare6), at: split, offset: [0, 0.7, 0]),
            .shake(0.12, at: land),
        ]
        // 矢じりの見える光の矢 3 本（直交する 2 枚の板。着弾から 0.06 秒ずつ遅れて、ゆっくり昇りながら消える）
        let standing: [SIMD3<Float>] = [[0.75, 0.65, 0.35], [-0.6, 0.65, -0.55], [0.1, 0.65, -1.0]]
        for (k, p) in standing.enumerated() {
            tele.append(.mesh(uprightArrow(length: 1.25, width: 0.4, .core, life: 0.3, up: true).with { $0.rise = 1.6 }.glowing(),
                              at: land + 0.03 + 0.06 * Float(k), offset: p).repeated(2, yaw: 90))
        }
        r.telegraph = tele
        // 着弾の 0.33 秒後に散る 6 本の小さな矢（本物の投射物。前方 = 飛ぶ向き。MLBB の高さ 0.5〜0.6）: 白い光の矢と青い筋
        r.travel = [
            .mesh(FXMesh(shape: .disc, tex: .arrow, tint: .core, alpha: 1, size: [1.4, 1, 0.42], sizeEnd: [1.4, 1, 0.42],
                         ease: .linear, life: minorArrowTime + 0.06, fadeIn: 0.02, fadeOut: 0.85, yaw: 90).glowing(), .follow,
                  offset: [0, 0.6, 0]),
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
        // 移動不能 1.2 秒（着弾）: 白い閃き + 水色の光の檻（下の縁が明るく上へ薄れる円柱・半径 0.6・高さ 1.15。f345〜372）と足元の輪
        r.hit = [
            .emit(.sheet(.hitFlash, 1.1, .core, end: .secondary, life: 0.16), offset: [0, 1.0, 0]),
            .mesh(FXMesh(shape: .cylinder, tex: .beam, tint: cage, alpha: 0.55, size: [0.5, 1.15, 0.5],
                         sizeEnd: [0.62, 1.15, 0.62], ease: .out, life: rootTime, fadeIn: 0.04, fadeOut: 0.85), .follow),
            .mesh(groundRing(0.62, .secondary, life: rootTime, from: 0.85).glowing(), .follow),
        ]
        return r
    }

    // MARK: - アルティメット 隠れ月光

    /// 月光の帳に包まれて月影に紛れる（隠密 2 秒・弱体の解除・加速）。演出は発動の位置に置く（隠れた位置を敵に見せない）。
    /// MLBB: f400（発動の次のコマ）頭上に大きな三日月 → f401〜412 その下から青紫の光の柱が地へ降りる → f402〜404 足元の閃光 →
    /// f405〜412 柱の中に青い光の粒。
    private static func hiddenMoonlight() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let crown: SIMD3<Float> = [0, 3.7, 0]
        r.cast = [
            // 0.03〜0.45: 頭上の大きな三日月（直径 1.9・#94CBFF、芯 #E2FCFF）と、その内の渦の飾り
            .mesh(FXMesh.sprite(.moon, 1.9, .accent, life: 0.42, grow: 1.06, alpha: 1).glowing().with {
                $0.fadeIn = 0.1
                $0.fadeOut = 0.6
            }, at: 0.03, offset: crown),
            .mesh(FXMesh.sprite(.swirl, 1.2, .core, life: 0.36, grow: 1.15, alpha: 0.75).glowing().with { $0.fadeIn = 0.15 },
                  at: 0.05, offset: crown + SIMD3<Float>(0.1, 0, 0)),
            // 0.05〜0.53: 三日月から地へ降りる青紫の光の柱（半径 1.0。円柱を逆さに吊るして下へ伸ばす。加算）
            .mesh(FXMesh(shape: .cylinder, tex: .beam, tint: veil, alpha: 0.85, size: [0.85, 0.5, 0.85],
                         sizeEnd: [1.0, 3.6, 1.0], ease: .out, life: 0.48, fadeIn: 0.12, fadeOut: 0.55, roll: 180).glowing()
                .flowing(.streaks, scroll: [0, -0.8], tiling: 3, strength: 0.4, edge: .accent), at: 0.05, offset: crown),
            // 0.1: 足元の閃光（水色の星と、横に伸びる光。0.1 秒。#82CFFF）
            .emit(.sheet(.hitFlash, 1.5, .core, end: .secondary, life: 0.16), at: 0.1, offset: [0, 0.35, 0]),
            .mesh(FXMesh(shape: .billboard, tex: .glow, tint: .secondary, alpha: 1, size: [2.6, 0.22, 1],
                         sizeEnd: [3.2, 0.12, 1], ease: .out, life: 0.15, fadeIn: 0.05, fadeOut: 0.4).glowing(),
                  at: 0.1, offset: [0, 0.35, 0]),
            // 0.18〜: 柱の中に漂う青い光の粒
            .emit(.motes(10, radius: 0.8, .rgb(0.4, 0.6, 1.0), life: 0.6, size: 0.09, rise: 0.4), at: 0.18,
                  offset: [0, 0.45, 0]),
        ]
        // 自身中心なので発動と同時に再生: 柱が地に着く所の淡い光
        r.impact = [
            .mesh(FXMesh.decal(.glow, 2.3, veil, life: 0.5, spin: 0, grow: 1.0, alpha: 0.5).glowing(), at: 0.12),
        ]
        // ダメージは無い
        r.hit = glint(.accent)
        return r
    }

    // MARK: - 詠唱モーション（H025MotionClips の長さと揃える。未読込時の姿勢も同じ動作へ）

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 弦を引き絞って月光を宿し、0.1 秒で離す（MLBB の発動は矢を放たず気をまとうだけ。モーションは以前のまま）
            m.draw(0.08, up: 0.08)
            m.release(0.04)
            m.hold(0.14) { $0.glow = 1.8 }
        case .skill2:
            // 2026-10-23 の収録: すぐ斜め上へ掲げ、約0.27秒で離弦、0.60秒で走りへ戻る。
            m.draw(0.10, up: 0.35)
            m.draw(eclipseShoot - 0.14, up: 0.75)
            m.release(0.04)
            m.hold(0.35 - eclipseShoot) { $0.glow = 1.6; $0.headPitch = -0.25 }
        case .ultimate:
            // 軽く踏み切り、両腕を開いて月光へ浮く。0.70 秒で復帰（クリップ側は接地まで脚を保持）。
            m.fullBody = true
            m.brace(0.08, depth: 0.04)
            m.key(0.15, .out) {
                $0.offset.y = 0.15
                $0.hipsDrop = 0
                $0.torsoYaw = 0.3
                $0.armL = ArmPose(pitch: 0.1, out: 1.05, yaw: -0.2, elbow: 0.2)
                $0.armR = ArmPose(pitch: 0.05, out: 1.0, yaw: 0.2, elbow: 0.25)
                $0.legR = LegPose(pitch: -0.15, out: 0.1, knee: 0.45)
                $0.legL = LegPose(pitch: 0.1, out: 0.1, knee: 0.35)
                $0.glow = 2; $0.ring = 1
            }
            m.key(0.12, .inOut) { $0.offset.y = 0.10; $0.torsoYaw = 0.1 }
        }
    }
}
