import Foundation
import VelstriaCore

// スキル演出: H030 星砲のライナ（Ranger / 自分の背丈ほどの星の砲・白と金の宇宙服風の戦闘服。MLBB の Layla の Velstria 版）。
// 主題: 星砲のエネルギー。白い芯 × 青（主）× 水色の白（副）× 淡い金（奥義の溜めの閃光だけ）× 紺（暗い殻・照準の線）。
// MLBB の画面収録（vid10。docs/vfx/H030.md）に合わせ、紫・星・金の輪・魔法陣は使わず、
// 「白い頭の青い彗星と電光」「青い光球と長い尾 → 白 → 青 → 藍へ移る光の球」「紺の照準線と暗い球 → 金の閃光 → 細っていく極太の白青のビーム」
// で形を見せる。光る部品は加算（glowing）、暗い殻・照準線はアルファ合成。
// 判定・時刻は Kit の値を読む（FXSkillInfo.kit = HeroKits.fxValues = Kit_H030 の RainaTuning。値を写さない。docs/vfx/RANGES.md）。
// 範囲を示す部品は判定の瞬間に見える縁が判定の縁（±3%）で、外へは消えながらだけ広がる:
//   S1 彗星を包む柔らかい光の横幅 = 砲弾の当たりの半幅（s1Width）、S2 の爆発・刻印の弾けの足元の輪 = 爆発の半径（blastRadius）、
//   奥義のビームの外の円柱の半径 = ビームの半幅（ultWidth）を、貫通弾がその区間を通り過ぎるまで保つ（区間ごとに後から細る）。
// 見せ場の閃き・電光・光の欠片・溜めの粒・レンズの光条は Effekseer の効果を段に重ねる（FXCue.efk。Effects/Effekseer/Kit/H030_*.efk、
// tools/effekseer/heroes/h030_kit.py）。彗星・光球・爆発の球・ビームは SkillFX（sim の時刻・距離と連動し、CI の撮影に写る部品）。
// 砲口の位置は全身のモーション（App/Battle/Heroes/Motions/Motion_H030.swift）の撃つキーの星砲の先（docs/vfx/H030.md「モーション」）。
//   パッシブ 遠星の照準    — 距離補正のバッジが点いた瞬間: 砲口に小さな水色のきらめき（MLBB には見える演出が無い）
//   スキル1 遠星弾         — 溜め（s1Windup）: 砲口に水色の光と紺の電光。発射: 砲口の白い閃光・青い光だまり（H030_muzzle）・砲口から
//                            砲弾へ走る電光。砲弾は白い頭に青い山形の筋の彗星（約 2m）を柔らかい青い光（横幅 = 当たりの幅）が包む。
//                            命中で小さな白い閃き（H030_shot_hit）、敵の体が白く光り、術者の足元に加速の水色の筋と電光
//   スキル2 星爆弾         — 溜め（s2Windup）: 前の上へ掲げた砲口に水色の光。発射: 上へ傾けた砲口の閃光（H030_muzzle_up）。光球は砲口の高さから
//                            放物線を描いて落ちる（白い芯 + 細胞の模様が流れる青い殻）。破裂（爆発の半径）: 白い閃き → 白く膨らむ球 →
//                            青いガラスの球（欠けて消える）→ 藍の靄・足元の水色の輪（範囲の縁）・球の中の電光（H030_s2_burst）。
//                            刻印の弾け（遅れ 0 のゾーン）は同じ破裂に桃の泡・灰色の石の輪・桃の電光・藍の靄（H030_mark_pop）を重ねる
//   アルティメット 星砕の大砲 — 溜め（ultWindup）: 紺の照準線が前へ伸び、砲口の前に暗い殻の球（青い芯 → 金の芯）と紺の渦・吸い込まれる
//                            光の粒（H030_ult_charge）。発射の 0.08 秒前に淡い金の閃光とレンズの光条、発射で白い閃光（H030_ult_flash）。
//                            発射: 射程いっぱい（s.range・半幅 ultWidth）の極太のビーム（白い芯 × 青い外層）。外層は 4 区間で、
//                            貫通弾が区間を通り過ぎてから細る。芯は先に細り、細い水色の線が残る。根元に後ろを向いた青い殻と水色の輪
//                            （H030_ult_root）。命中した敵は白く光る
// SkillFXDirector は duration / count を読まない: 時刻は at（遅れ）で表す。追従のメッシュは弾が消えると止まって寿命まで残るので、
// 彗星と光球は短い寿命の繰り返しで出す（弾が消えると残りの予定は消える）。

enum FX_H030: HeroFXSet {
    // MLBB の画面収録の色（docs/vfx/H030.md）: 芯 #F2FCFF、主 = 弾と球の青 #4A94E8、副 = 明るい縁の水色 #A6F2FF、
    // 差し色 = 奥義の溜めの金 #FDDB82、暗色 = 溜めの球の紺の殻 #16214D。
    static let palette = FXPalette(core: RGB(0.95, 0.99, 1.0), primary: RGB(0.29, 0.58, 0.91),
                                   secondary: RGB(0.65, 0.95, 1.0), accent: RGB(0.99, 0.86, 0.51),
                                   dark: RGB(0.09, 0.13, 0.30))

    /// 彗星の尾の暗い側・電光の筋の濃い青（#2660C3）。
    private static let deepBlue = FXTint.rgb(0.15, 0.38, 0.76)
    /// 破裂の消え際・刻印の弾けの靄の藍（#4558B3）。
    private static let indigo = FXTint.rgb(0.27, 0.35, 0.70)
    /// 刻印の胸の光の玉（#A5AEE2）。
    private static let markTint = FXTint.rgb(0.65, 0.68, 0.89)
    /// 奥義の照準線の黒に近い紺（#030106 の芯）。
    private static let sightDark = FXTint.rgb(0.02, 0.03, 0.08)
    /// 奥義の溜めの球の金に変わる芯の橙（#F3A86B）。
    private static let ember = FXTint.rgb(0.95, 0.66, 0.42)

    /// Effekseer の効果（Effects/Effekseer/Kit/）。s2_burst は爆発の半径 1.9 m で作った（倍率 = 半径 / 1.9）。
    private static let efkMuzzle = "H030_muzzle"
    private static let efkMuzzleUp = "H030_muzzle_up"
    private static let efkShotHit = "H030_shot_hit"
    private static let efkBurst = "H030_s2_burst"
    private static let efkMark = "H030_mark_pop"
    private static let efkCharge = "H030_ult_charge"
    private static let efkFlash = "H030_ult_flash"
    private static let efkRoot = "H030_ult_root"
    private static let burstDesignRadius: Float = 1.9

    // MARK: - sim の時刻・寸法
    // Kit_H030.RainaTuning の値は写さず、FXSkillInfo（HeroKits.fxValues）から読む（照準の表示・判定・演出が同じ値。docs/vfx/RANGES.md）:
    //   S1 s1Windup（溜め → 砲弾）・s1Speed・s1Range・s1Width（砲弾の当たりの半幅）
    //   S2 s2Windup・s2Speed・s2Range・ultRange（奥義の Lv の射程の延長）・blastRadius（爆発と刻印の弾けの半径）
    //   奥義 ultWindup（溜め → ビーム）・ultBeamSpeed（貫通弾の速さ）・ultWidth（ビームの半幅）。射程は s.range（照準の range）

    // MARK: - 砲口（Motion_H030 の撃つキーの星砲の先。術者の足元から x = 右・y = 上・z = 前、m。同梱のスキンの腕・脚の寸法で測った棒人形。±0.1 m）

    /// 砲は少し内へ向けて構え、砲口は体の中心の線（sim の弾・ビームの通り道）の上に来る（x = 0）。
    /// S1: 腰だめに水平に構えた砲口。
    private static let muzzleS1: SIMD3<Float> = [0, 1.28, 1.4]
    /// S2: 前の上 55° へ掲げた砲口。
    private static let muzzleS2: SIMD3<Float> = [0, 2.3, 0.88]
    /// 奥義: 腰を落として胸の高さで前へ据えた砲口。
    private static let muzzleUlt: SIMD3<Float> = [0, 1.28, 1.5]
    /// パッシブ: 待機の砲口（腰だめで前の下）。
    private static let muzzleIdle: SIMD3<Float> = [0.2, 1.0, 1.1]

    // MARK: - 見た目の時刻・寸法（動画に合わせた値。sim の判定とは別）

    /// 彗星（S1）の 1 回の寿命と繰り返しの間隔（弾が消えたら残りの予定は消える）。
    private static let segment: Float = 0.1
    private static let segmentLife: Float = 0.115
    /// 彗星の長さ（動画: 約 1.7〜2m）と、頭の位置（画像の u 0.84 = 板の中心から前へ 0.34）。
    private static let cometLength: Float = 2.0
    /// 彗星の体の板の縦（画像の体の半幅 0.256 × 0.8 m ≈ 0.2 m = 動画の幅 0.35〜0.45 m の半分）。
    private static let cometHeight: Float = 0.8
    /// 砲弾・光球の見た目が砲口から始まって弾（術者の中心から出る）へ追いつくまでの時間。
    private static let leadTime: Float = 0.2
    /// S2 の光球の放物線（動画: 砲口から上がって的の頭の上を越え、胸の高さへ落ちる。4.5 m 先の的に 0.38 秒で胸の高さ）:
    /// 頂きの時刻・重力（m/s²）・区間の長さ。
    private static let orbApex: Float = 0.11
    private static let orbGravity: Float = 39.5
    private static let orbStep: Float = 0.12
    /// 光球の高さの下限（射程いっぱいへ長く飛ぶとき、これより下へは落とさない）。
    private static let orbFloor: Float = 1.0
    /// 奥義のビームの根元（砲口の 0.6m 先。動画: ビームは砲口の少し前から始まる）と、外層の区間の数。
    private static let beamGap: Float = 0.6
    private static let beamSections = 4
    /// 外層の区間が細る長さ（貫通弾が区間の先を通り過ぎてから。動画: 太い 0.1 秒 → 細る 0.17 秒）。
    private static let beamNarrow: Float = 0.16

    // MARK: - 部品

    /// 円い模様の板の一辺: 見える縁（板の FXEdge.radial(tex) 倍）が半径 r になる大きさ。
    private static func edgeSize(_ r: Float, _ tex: FXTex) -> SIMD3<Float> {
        let side = r / (FXEdge.radial(tex) ?? 0.4575)
        return [side, 1, side]
    }

    /// 縁 → 縁 × spread へ ease .out で広がる部品が 1.03 倍を越える寿命の比より少し前（消え始めの比）。
    private static func edgeFade(_ spread: Float) -> Float {
        guard spread > 1.03 else { return 0.4 }
        let e: Float = 0.03 / (spread - 1)
        return max(0.02, (1 - pow(1 - e, 1.0 / 3.0)) * 0.9)
    }

    /// 寝かせた光の円柱（ビーム）。原点から前へ length m 伸びる（back なら後ろへ）。半径 r0 → r1 へ ease で変わる。
    private static func beamTube(length: Float, radius r0: Float, to r1: Float, _ tint: FXTint, life: Float, alpha: Float,
                                 tex: FXTex? = .beam, back: Bool = false, ease: FXEase = .in, fadeIn: Float = 0.03,
                                 fadeOut: Float = 0.6) -> FXMesh {
        FXMesh(shape: .cylinder, tex: tex, tint: tint, alpha: alpha, size: [r0, length, r0], sizeEnd: [r1, length, r1],
               ease: ease, life: life, fadeIn: fadeIn, fadeOut: fadeOut, pitch: back ? -90 : 90).glowing()
    }

    /// 前を向いて寝かせた横長の板（彗星の体・柔らかい光）。大きさは変えない。advance = 前への移動（m/s、負 = 後ろへ）。
    private static func plate(_ tex: FXTex, length: Float, height: Float, _ tint: FXTint, life: Float, alpha: Float,
                              advance: Float = 0, fadeIn: Float = 0.05) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [length, 1, height], sizeEnd: [length, 1, height],
               ease: .linear, life: life, fadeIn: fadeIn, fadeOut: 0.8, yaw: 90, advance: advance).glowing()
    }

    // MARK: - レシピ

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        switch slot {
        case .passive:
            // MLBB には距離補正の見える演出が無い（動画で見つからない）。バッジが点いた合図だけ、砲口に小さなきらめき
            var r = SkillFXRecipe()
            r.cast = [
                .emit(.flare(0.8, .secondary, life: 0.14, tex: .flare4), .follow, offset: muzzleIdle),
                .emit(.sheet(.sparkTwinkle, 0.45, .secondary, end: .primary, count: 2, life: 0.45, radius: 0.15), .follow,
                      offset: muzzleIdle),
            ]
            r.hit = [.emit(.flare(0.6, .secondary, life: 0.12), offset: [0, 1.0, 0])]
            return r
        case .skill1:
            return farstarShot(s)
        case .skill2:
            return starburstShell(s)
        case .ultimate:
            return starbreakerCannon(s)
        }
    }

    // MARK: - スキル1 遠星弾

    /// 白い頭に青い尾の彗星（溜め s1Windup の後に出る）。MLBB: f1047 砲口の水色の光と紺の電光 → f1048 前へ伸びる白い閃光 →
    /// f1049〜1056 彗星（約 2m）と青い光だまり・電光・通り道のきらめき → f1057 敵の体が白く光る（爆発は無い）。
    private static func farstarShot(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let t = s.seconds("s1Windup")
        let speed = s.speed("s1Speed")
        let flight = speed > 0 ? s.meters("s1Range") / speed : 0.4
        let half = s.meters("s1Width")
        let fwd = SIMD3<Float>(0, 0, 1)
        let m = muzzleS1
        r.cast = [
            // 溜め: 砲口に水色の光が集まり、紺の電光の筋が前に跳ねる
            .mesh(.sprite(.flare4, 0.35, .secondary, life: t + 0.04, grow: 1.6, alpha: 0.85).glowing(), .follow, offset: m),
            .emit(.sheet(.electricArc, 0.55, deepBlue, end: .primary, life: 0.14), at: t * 0.4, .follow,
                  offset: m + SIMD3<Float>(0, 0.08, 0.35)),
            // 発射: 前へ伸びる白い閃光（加算の板）と、砲口の閃光・光だまり・水色の輪・きらめき・紺の電光（Effekseer。3D の上）
            .mesh(.ray(.streak, length: 2.0, width: 2.4, .core, life: 0.1).glowing().with { $0.onTop = true }, at: t,
                  offset: m + fwd * 1.0),
            .efk(efkMuzzle, at: t, .origin, offset: m, onTop: true),
            .emit(.bloom(1.3, .primary, life: 0.22, grow: 1.3), at: t + 0.03, offset: m + fwd * 0.4),
            // 砲口から砲弾へ走る電光（f1051〜1052）
            .mesh(.ray(.bolt, length: 2.6, width: 0.45, .primary, life: 0.12).glowing(), at: t + 0.09, offset: m + fwd * 1.4),
        ]
        // 彗星（0.1 秒ごとに出し直す。射程いっぱい = flight 秒を覆う数）: 柔らかい青い光（見える横幅 = 砲弾の当たりの幅。範囲の縁）、
        // 水色の白の彗星の体（山形の筋）、白い頭の球。弾は術者の中心から出るので、見た目は砲口の高さ・横・前から始めて
        // leadTime 秒で弾に追いつく（前へのずれを advance で戻す）
        let n = max(1, Int((flight / segment).rounded(.up)))
        let glowHeight = half / (FXEdge.linearHalfWidth(.cometGlow) ?? 0.4)
        let back = advanceBack(lead: m.z, time: leadTime)
        func seg(_ k: Int) -> (z: Float, advance: Float) {
            let t0 = Float(k) * segment
            let z0 = max(0, m.z - back * t0)
            return (z0, t0 < leadTime - 1e-4 ? -back : 0)
        }
        var travel: [FXCue] = []
        for k in 0..<n {
            let (z0, adv) = seg(k)
            let at = Float(k) * segment
            let head: SIMD3<Float> = [m.x, m.y, z0]
            // 1 回目は砲口の前で光が術者に重ならないよう、柔らかい光をゆっくり立ち上げる
            travel += [
                .mesh(plate(.cometGlow, length: 2.2, height: glowHeight, .primary, life: segmentLife, alpha: 0.35, advance: adv,
                            fadeIn: k == 0 ? 0.6 : 0.05), at: at, .follow, offset: head - fwd * 0.55),
                .mesh(plate(.comet, length: cometLength, height: cometHeight, .primary, life: segmentLife, alpha: 1,
                            advance: adv), at: at, .follow, offset: head - fwd * (cometLength * 0.34)),
                .mesh(FXMesh.orb(0.13, .core, life: segmentLife, grow: 1.0, alpha: 1).with {
                    $0.fadeIn = 0.05
                    $0.fadeOut = 0.8
                    $0.advance = adv
                }.glowing(), at: at, .follow, offset: head),
            ]
        }
        // 尾の青い光・通り道に残る青いきらめきと小さな紺の電光（粒子。実機だけ）
        travel += [
            .emit(.trail(.glow, .primary, rate: 55, life: 0.18, size: 0.42).with { $0.tintEnd = deepBlue }, .follow,
                  offset: [m.x, m.y, -0.2]),
            .emit(.trail(.twinkle, .secondary, rate: 22, life: 0.35, size: 0.14).with {
                $0.tintEnd = .primary
                $0.shape = .sphere(0.3)
                $0.speed = 0.3
            }, .follow, offset: [m.x, m.y, -0.3], quality: 1),
            .emit(.trail(.glow, deepBlue, rate: 10, life: 0.16, size: 0.5).with {
                $0.sheet = .electricArc
                $0.sheetRandomStart = true
                $0.angleVar = 180
                $0.tintEnd = .primary
                $0.shape = .sphere(0.25)
            }, .follow, offset: [m.x, m.y, -0.4]),
        ]
        r.travel = travel
        // 命中・射程の端: 小さな白い閃き（MLBB に爆発は無い）と前へ散る水色の火花（Effekseer）
        r.impact = [
            .mesh(.sprite(.glowHard, 0.9, .secondary, life: 0.1, grow: 1.6).glowing(), offset: [0, 1.1, 0]),
            .efk(efkShotHit, .origin, offset: [0, 1.1, 0], onTop: true),
        ]
        // 命中した敵（1 体）: 体が白く光る（f1057）。命中で術者が加速する = 術者の足元（along(0)）に水色の速さの筋と電光（f505〜514）
        r.hit = [
            .mesh(.sprite(.glow, 1.4, .white, life: 0.1, grow: 1.0, alpha: 0.75).glowing(), .follow, offset: [0, 0.9, 0]),
            .emit(.rising(10, radius: 0.45, .secondary, speed: 3.5, life: 0.45, size: 0.1, tex: .streak), .along(0),
                  offset: [0, 0.1, 0]),
            .emit(.sheet(.electricArc, 1.1, .primary, end: .secondary, life: 0.3), .along(0), offset: [0, 0.9, 0]),
        ]
        return r
    }

    /// 砲口の前へのずれ lead（m）を time 秒で 0 へ戻す速さ（m/s）。
    private static func advanceBack(lead: Float, time: Float) -> Float { time > 0 ? lead / time : 0 }

    // MARK: - スキル2 星爆弾

    /// 白い芯の青い光球（溜め s2Windup の後、前の上へ掲げた砲口から）が放物線を描いて捉えた敵へ → 捉えた敵か射程の端で破裂
    /// （半径 blastRadius）。刻印の弾けは telegraph + 同じ破裂。MLBB: f971 砲口の水色の星 → f972〜984 光球と尾（上がって落ちる）→
    /// f908 白い閃き → f910〜911 白から青の球 → f913〜914 藍に消える。弾けは f1206 桃の泡 → f1207 白い球と灰色の石の輪 → 藍の靄と電光。
    private static func starburstShell(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.meters("blastRadius")
        let t = s.seconds("s2Windup")
        let speed = s.speed("s2Speed")
        // 最も遠い飛行（基本の射程 + 奥義の Lv3 の延長 + 捉えた敵が逃げる分の余裕 1 m）
        let reach = s.meters("s2Range") + (s.ratiosMeters("ultRange").max() ?? 0) + 1
        let flight = speed > 0 ? reach / speed : 0.7
        let m = muzzleS2
        r.cast = [
            // 溜め: 掲げた砲口に水色の光（粒子。メッシュの枠は光球の弧と破裂に使う）
            .emit(.flare(0.5, .secondary, life: t + 0.04, tex: .flare4), .follow, offset: m),
            // 発射: 前の上 55° へ傾けた砲口の閃光・光だまり・輪・水色の白の星形の閃光（Effekseer）と、水色の白の星
            .efk(efkMuzzleUp, at: t, .origin, offset: m, scale: 0.9, onTop: true),
            .emit(.flare(1.2, .secondary, life: 0.12, tex: .flare4), at: t, offset: m),
        ]
        // 光球（直径約 0.55〜0.65m）: 白い芯と尾（彗星の模様）と、細胞の模様が流れる青い殻（加算）。放物線（砲口の高さから orbApex 秒で頂き、重力 orbGravity）を
        // orbStep 秒の区間に分けて出し直す（区間の始めの高さ・上向きの速さ・重力）。前へのずれは leadTime 秒で 0 へ
        let v0 = orbGravity * orbApex
        let back = advanceBack(lead: m.z, time: leadTime)
        let n = max(1, Int((flight / orbStep).rounded(.up)))
        // 白い芯と尾は彗星の模様の板（頭の楕円 = 光球の芯、体 = 細りながら消える尾 2 m）。殻は細胞の模様が流れる青い球
        let tail = plate(.comet, length: 2.4, height: 0.95, .secondary, life: orbStep, alpha: 1)
        let shell = FXMesh.orb(0.32, .primary, life: orbStep, grow: 1.0, alpha: 0.9).glowing()
            .flowing(.cells, scroll: [0.8, -0.6], tiling: 1.5, strength: 0.6, edge: .secondary)
        var travel: [FXCue] = []
        for k in 0..<n {
            let t0 = Float(k) * orbStep
            func height(_ t: Float) -> Float { m.y + v0 * t - 0.5 * orbGravity * t * t }
            var y = height(t0)
            var rise = v0 - orbGravity * t0
            var g = orbGravity
            if y <= orbFloor {
                // 床の高さで水平に飛ぶ（射程いっぱいへ長く追うとき）
                y = orbFloor
                rise = 0
                g = 0
            } else if height(t0 + orbStep) < orbFloor {
                // この区間で床を下回る: 区間の終わりに床の高さへ着く直線にする
                rise = (orbFloor - y) / orbStep
                g = 0
            }
            let z = max(0, m.z - back * t0)
            let adv: Float = t0 < leadTime - 1e-4 ? -back : 0
            let last = k == n - 1
            for (part, back) in [(tail, Float(2.4 * 0.34)), (shell, Float(0))] {
                travel.append(.mesh(part.with {
                    $0.life = orbStep + (last ? 0.05 : 0.02)
                    $0.rise = rise
                    $0.gravity = g
                    $0.advance = adv
                    $0.fadeIn = k == 0 ? 0.15 : 0.02
                    $0.fadeOut = 0.92
                }, at: t0, .follow, offset: [m.x, y, z - back]))
            }
        }
        // 長い青い尾（細りながら消える）と、光球のすぐ後ろの水色の白の芯の尾（粒子。高さは弧の中ほど）
        travel += [
            .emit(.trail(.glow, .primary, rate: 70, life: 0.25, size: 0.5).with { $0.tintEnd = deepBlue }, .follow,
                  offset: [0, 1.9, 0]),
            .emit(.trail(.glow, .secondary, rate: 50, life: 0.12, size: 0.22).with { $0.tintEnd = .primary }, .follow,
                  offset: [0, 1.9, 0]),
        ]
        r.travel = travel
        // 破裂（光球の命中・射程の端・刻印の弾け）: 白い閃き（Effekseer）→ 白く膨らむ球 → 青いガラスの球（模様が欠けて消える）→ 藍の靄。
        // 足元の水色の輪は判定の瞬間に縁 = 爆発の半径 R、消えながら 1.06R へ（範囲の縁）
        r.impact = [
            // 破裂の瞬間の白飛びの手前の芯（3D の上）
            .mesh(.sprite(.glowHard, R * 1.4, .core, life: 0.12, grow: 1.5).glowing().with { $0.fadeIn = 0; $0.onTop = true },
                  offset: [0, 0.9, 0]),
            .mesh(FXMesh.orb(0.5, .core, life: 0.16, grow: 3.2, alpha: 0.95).with { $0.fadeOut = 0.45 }.glowing(), at: 0.03,
                  offset: [0, 0.9, 0]),
            .mesh(FXMesh.orb(R * 0.53, .primary, life: 0.26, grow: 1.6, alpha: 0.95).with { $0.fadeOut = 0.4 }.glowing()
                .flowing(.cells, scroll: [0.4, -0.8], tiling: 2, strength: 0.6, erosion: 0.25, edge: .secondary),
                  at: 0.05, offset: [0, 0.9, 0]),
            .mesh(FXMesh.orb(R * 0.82, indigo, life: 0.26, grow: 1.08, alpha: 0.35).with {
                $0.fadeIn = 0.25
                $0.fadeOut = 0.5
            }, at: 0.1, offset: [0, 0.9, 0]),
            .mesh(FXMesh(shape: .disc, tex: .ring, tint: .secondary, alpha: 0.6, size: edgeSize(R, .ring),
                         sizeEnd: edgeSize(R * 1.06, .ring), ease: .out, life: 0.3, fadeIn: 0, fadeOut: edgeFade(1.06)).glowing()),
            // 球の下の床が青く光る
            .mesh(.decal(.glow, R * 1.9, .primary, life: 0.35, spin: 0, grow: 1.0, alpha: 0.55).glowing(), at: 0.03),
            // 閃き・球の中の電光・飛ぶ光の欠片・ガラスの縁・ラベンダーの残り光（Effekseer。3D の上）
            .efk(efkBurst, .origin, offset: [0, 0.9, 0], scale: R / burstDesignRadius, onTop: true),
            .emit(.sparks(12, speed: 7, .core, end: .primary), offset: [0, 0.8, 0]),
            .shake(0.15),
        ]
        // 刻印の弾け（遅れ 0 のゾーン。破裂と同時）: 桃の泡・足元の灰色の尖った石の輪・桃の電光・床を這う電光・藍の靄（Effekseer）
        r.telegraph = [
            .efk(efkMark, .origin, scale: R / burstDesignRadius),
            .emit(.sheet(.smokePuff, 1.5, indigo, count: 3, life: 0.5, additive: false, radius: 0.9), at: 0.12,
                  offset: [0, 0.6, 0], quality: 1),
        ]
        // 破裂・弾けを受けた敵: 体が白く光り、胸に刻印の淡い光の玉（付いたことの合図。刻印の残りは頭上の印で出る）
        r.hit = [
            .emit(.sheet(.hitFlash, 1.2, .core, end: .secondary, life: 0.16), offset: [0, 1.0, 0]),
            .mesh(FXMesh.orb(0.16, markTint, life: 0.7, grow: 1.0, alpha: 0.95).with {
                $0.fadeIn = 0.3
                $0.fadeOut = 0.6
            }.glowing(), at: 0.15, .follow, offset: [0, 1.0, 0]),
            .mesh(.sprite(.glow, 0.75, .primary, life: 0.7, grow: 1.0, alpha: 0.7).with {
                $0.fadeIn = 0.3
                $0.fadeOut = 0.6
            }.glowing(), at: 0.15, .follow, offset: [0, 1.0, 0]),
        ]
        return r
    }

    // MARK: - アルティメット 星砕の大砲

    /// ultWindup 秒溜めて、射程いっぱい（s.range）を貫く極太のビーム（半幅 ultWidth）。MLBB: f373 紺の照準線 → f376〜380 暗い殻の球
    /// （青い芯）と紺の渦 → f383〜384 金の芯 → f385 淡い金の閃光 → f386 横の光条 → f388〜391 極太の白青のビーム → f392〜396 細る →
    /// f397〜399 細い水色の線。sim のビームは術者の中心から ultBeamSpeed で進む貫通弾なので、外層の区間 k は弾が区間の先を
    /// 通り過ぎる時刻まで半径 = ultWidth を保ち（判定の瞬間に縁 = 判定の幅）、それから beamNarrow 秒で細る。
    static func beamSectionTimes(_ s: FXSkillInfo) -> [(z0: Float, z1: Float, hold: Float)] {
        let L = s.range
        let start = muzzleUlt.z + beamGap
        let v = max(1, s.speed("ultBeamSpeed"))
        let len = max(1, L - start) / Float(beamSections)
        return (0..<beamSections).map { k in
            let z0 = start + Float(k) * len, z1 = z0 + len
            // 弾の 1 tick の区間の判定が区間の先に届く時刻（発射の予約が tick に丸まり、弾が次の tick から進む分の 2 tick を足す）
            return (z0, z1, z1 / v + 2 * Float(Balance.dt))
        }
    }

    private static func starbreakerCannon(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = s.range
        let W = s.meters("ultWidth")
        let t = s.seconds("ultWindup")
        let m = muzzleUlt
        // ビームの軸（砲口の高さ・右へのずれ）と根元（砲口の beamGap 先）。終点から後ろへ伸ばす層は軸にそろえる
        let axis: SIMD3<Float> = [0, m.y, 0]
        let start = m + SIMD3<Float>(0, 0, beamGap)
        let Lb = max(1, L - start.z)
        let orbPos = m + SIMD3<Float>(0, 0.05, 0.6)
        let sightLength: Float = 10
        let sightAt = start + SIMD3<Float>(0, 0, sightLength * 0.5)
        var cast: [FXCue] = [
            // 0.08〜: 紺の照準線（黒に近い芯・青い縁）が前へ伸びる
            .mesh(.ray(.streak, length: sightLength, width: 2.2, sightDark, life: t - 0.13, alpha: 0.85).with {
                $0.fadeIn = 0.15
                $0.fadeOut = 0.7
            }, at: 0.08, offset: sightAt),
            .mesh(.ray(.streak, length: sightLength, width: 3.4, .primary, life: t - 0.13, alpha: 0.7).with {
                $0.fadeIn = 0.15
                $0.fadeOut = 0.7
            }.glowing(), at: 0.08, offset: sightAt - SIMD3<Float>(0, 0.02, 0)),
            // 0.17〜: 砲口の前の暗い殻の球（外縁が暗い輪）。芯は青 → 金（発射の 0.15 秒前から）。吸い込まれる光の粒と紺の渦（Effekseer）
            .mesh(.sprite(.shockwave, 0.8, .dark, life: t - 0.19, grow: 1.0, alpha: 0.9).with {
                $0.fadeIn = 0.12
                $0.fadeOut = 0.8
            }, at: 0.17, .follow, offset: orbPos),
            .mesh(.sprite(.glowHard, 0.5, .primary, life: t - 0.31, grow: 0.8).glowing(), at: 0.17, .follow, offset: orbPos),
            .mesh(.sprite(.glowHard, 0.55, ember, life: 0.14, grow: 1.3).glowing(), at: t - 0.15, .follow, offset: orbPos),
            .efk(efkCharge, at: 0.17, .follow, offset: orbPos),
            .emit(.sheet(.darkWisp, 0.9, deepBlue, end: .dark, count: 2, life: 0.4, additive: false), at: 0.15, .follow,
                  offset: orbPos),
            // 発射の 0.08 秒前: 淡い金の閃光と横に伸びるレンズの光条 → 発射: 白い閃光（Effekseer。3D の上）。加算の光条の板と前へ散る光条
            .efk(efkFlash, at: t - 0.08, .origin, offset: orbPos, onTop: true),
            .mesh(.sprite(.streak, 4.5, .core, life: 0.12, grow: 1.25).glowing().with { $0.onTop = true }, at: t - 0.04,
                  offset: orbPos),
            .emit(.fan(20, .secondary, speed: 13, spread: 10, life: 0.3), at: t, offset: start),
        ]
        // 発射: 射程いっぱいの極太のビーム。外の青い円柱は 4 区間（筋の模様が前へ流れる）。区間ごとに、弾が区間の先を通り過ぎるまで
        // 半径 W（= 判定の半幅）を保ち、それから細る（保つ円柱 + 細る円柱）。白い芯の円柱は全長を前から・終点から 2 本で、先に細る
        for sec in beamSectionTimes(s) {
            let len = sec.z1 - sec.z0
            let at: SIMD3<Float> = [0, m.y, sec.z0]
            cast += [
                .mesh(beamTube(length: len, radius: W, to: W, .primary, life: sec.hold, alpha: 0.95, tex: nil, ease: .linear,
                               fadeIn: 0.02, fadeOut: 0.97)
                    .flowing(.streaks, scroll: [0, -4], tiling: 3, strength: 0.5, edge: .secondary), at: t, offset: at),
                .mesh(beamTube(length: len, radius: W, to: W * 0.12, .primary, life: beamNarrow, alpha: 0.95, tex: nil, ease: .out,
                               fadeIn: 0, fadeOut: 0.5)
                    .flowing(.streaks, scroll: [0, -4], tiling: 3, strength: 0.5, edge: .secondary), at: t + sec.hold, offset: at),
            ]
        }
        cast += [
            .mesh(beamTube(length: Lb, radius: W * 0.5, to: W * 0.05, .core, life: 0.28, alpha: 1), at: t, offset: start),
            .mesh(beamTube(length: Lb, radius: W * 0.5, to: W * 0.05, .core, life: 0.28, alpha: 0.85, back: true), at: t,
                  .target, offset: axis),
            // 細った後に残る細い水色の線（全長で同じ明るさ）
            .mesh(FXMesh(shape: .cylinder, tex: nil, tint: .secondary, alpha: 0.9, size: [0.07, Lb, 0.07],
                         sizeEnd: [0.025, Lb, 0.025], ease: .in, life: 0.2, fadeIn: 0.1, fadeOut: 0.4, pitch: 90).glowing(),
                  at: t + 0.26, offset: start),
            // ビームの根元: 後ろを向いた青い殻（縁が明るい）と、細るにつれ目立つ光の点。前を向いた水色の輪と散る火花（Effekseer）
            .mesh(FXMesh(shape: .dome, tex: .beam, tint: .primary, alpha: 0.7, size: [W * 0.8, W * 0.5, W * 0.8],
                         sizeEnd: [W * 1.1, W * 0.8, W * 1.1], ease: .out, life: 0.26, fadeIn: 0.05, fadeOut: 0.5,
                         pitch: -90).glowing(), at: t + 0.02, offset: start + SIMD3<Float>(0, 0, 0.1)),
            .mesh(.sprite(.glowHard, 0.8, .secondary, life: 0.3, grow: 0.6).with {
                $0.fadeIn = 0.2
                $0.fadeOut = 0.6
            }.glowing(), at: t + 0.1, offset: start),
            .efk(efkRoot, at: t, .origin, offset: start, onTop: true),
            .shake(0.45, at: t),
        ]
        r.cast = cast
        // ビームの先頭（ultBeamSpeed の貫通弾）: 小さな光（MLBB ではビームが一瞬で伸びるので目立たせない）
        r.travel = [
            .mesh(.sprite(.glowHard, 1.6, .secondary, life: 0.3, grow: 1.0, alpha: 0.9).with { $0.fadeOut = 0.8 }.glowing(),
                  .follow, offset: axis),
            .emit(.trail(.streak, .secondary, rate: 120, life: 0.2, size: 0.5).with {
                $0.dir = .backward
                $0.speed = 6
                $0.stretch = 3
                $0.shape = .sphere(W * 0.7)
                $0.tintEnd = .primary
            }, .follow, offset: axis),
        ]
        // 最初に貫いた敵（誰にも当たらなければ射程の端）: 白い閃きと前へ散る火花（MLBB に爆発は無い）
        r.impact = [
            .mesh(.sprite(.glowHard, 1.8, .core, life: 0.1, grow: 1.4).glowing(), offset: [0, 1.1, 0]),
            .efk(efkShotHit, .origin, offset: [0, 1.1, 0], scale: 1.4, onTop: true),
            .shake(0.3),
        ]
        // 貫かれた敵ごと: 体が白く光る（f387・f1293）
        r.hit = [
            .mesh(.sprite(.glow, 1.8, .white, life: 0.1, grow: 1.0, alpha: 0.8).glowing(), .follow, offset: [0, 0.9, 0]),
            .emit(.sheet(.hitFlash, 1.4, .core, end: .secondary, life: 0.18), offset: [0, 1.1, 0]),
            .emit(.sparks(8, speed: 7, .secondary, end: .primary).with {
                $0.dir = .forward
                $0.spread = 25
            }, offset: [0, 1.0, 0]),
        ]
        return r
    }

    // MARK: - 詠唱モーション

    /// 全身のモーション（Motion_H030。HeroSkillMotions が先）が無い時の従来の詠唱（目録から外したときの予備）。
    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            m.aim(0.1)
            m.recoil(0.05, power: 0.6)
            m.hold(0.12) { $0.glow = 1.4 }
        case .skill2:
            m.aim(0.1, up: 0.04)
            m.recoil(0.06, power: 0.85)
            m.settle(0.12)
        case .ultimate:
            m.brace(0.12, depth: 0.2)
            m.aim(0.2)
            m.hold(0.23) { $0.glow = 2.6; $0.ring = 1.2 }
            m.recoil(0.06, power: 1.2)
            m.hold(0.24) { $0.glow = 2.2 }
            m.settle(0.16)
        }
    }
}

extension FXSkillInfo {
    /// 距離の表（KitFXValue の values）を m で。
    fileprivate func ratiosMeters(_ key: String) -> [Float] {
        guard let v = kit[key], v.unit == .distance else {
            FXSkillInfo.misses.insert("\(heroID) \(slot) \(stage) \(key)")
            return []
        }
        return v.values.map { Float($0 / Balance.unitsPerMeter) }
    }
}
