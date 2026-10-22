import Foundation
import VelstriaCore

// スキル演出: H030 星砲のライナ（Ranger / 自分の背丈ほどの星の砲・白と金の宇宙服風の戦闘服。MLBB の Layla の Velstria 版）。
// 主題: 魔砲のエネルギー。白い芯 × 青（主）× 水色の白（副）× 淡い金（奥義の溜めの閃光だけ）× 紺（暗い殻・照準の線）。
// MLBB の画面収録（vid10。docs/vfx/H030.md）に合わせ、紫・星・金の輪・魔法陣は使わず、
// 「白い頭の青い彗星と電光」「青い光球と長い尾 → 白 → 青 → 藍へ移る光の球」「紺の照準線と暗い球 → 金の閃光 → 細っていく極太の白青のビーム」
// で形を見せる。光る部品は加算（glowing）、暗い殻・石・藍の靄・照準線はアルファ合成。
// sim の実際の挙動（Systems/Kits/Kit_H030.swift の RainaTuning）に合わせたタイミング:
//   パッシブ 遠星の照準    — 距離補正のバッジが点いた瞬間: 砲口に小さな水色のきらめき（MLBB には見える演出が無い）
//   スキル1 遠星弾         — 0〜0.1 秒（s1Windup）: 砲口に水色の光と紺の電光の筋。0.1 秒に砲弾（19.5 m/s・7.55m ≒ 0.39 秒）:
//                            砲口で前へ伸びる白い閃光と青い光だまり、砲口から砲弾へ走る電光。砲弾は白い頭に青い尾の彗星（約 2m）、
//                            通り道に青いきらめきと小さな電光が残る（travel）。命中で小さな白い閃き（impact）、敵の体が白く光り、
//                            術者の足元に加速の水色の筋と電光（hit）
//   スキル2 星爆弾         — 0〜0.1 秒（s2Windup）: 砲口に水色の光。0.1 秒に光球（10.5 m/s）: 白い芯の青い光球（細胞の模様が流れる）に
//                            長い青い尾。上がる層と落ちる層で弧を描く（travel）。捉えた敵か射程の端で破裂（impact、半径 1.9m）:
//                            白い閃き → 白く膨らむ球 → 青い球（欠けて消える）→ 藍の靄、床の青い光・電光。
//                            刻印の弾け（遅れ 0 のゾーン）は同じ破裂（impact）に telegraph を重ねる: 桃の泡・灰色の石の輪・
//                            桃の電光・床を這う電光・藍の煙。被弾者の体が白く光り、胸に刻印の淡い光の玉（hit。頭上の印は KitStatusVisuals）
//   アルティメット 星砕の大砲 — 0〜0.55 秒（ultWindup）: 0.08 秒に紺の照準線が前へ伸び、0.17 秒に砲口の前に暗い殻の球（青い芯 →
//                            0.4 秒に金の芯）と紺の渦。0.47 秒に淡い金の閃光、0.51 秒に横に伸びるレンズの光条。
//                            0.55 秒: 射程いっぱい（20m・半幅 1.0m）の極太のビーム（砲口の 0.6m 先から。白い芯 × 青い外層、前から・終点から
//                            2 本ずつ重ねて全長の明るさをそろえる）が 0.3 秒で細り、細い水色の線が 0.2 秒残る。根元に青い殻と光の点
//                            （cast）。ビームの先頭（travel）は小さな光と光条。命中した敵は白く光る（impact・hit）
// SkillFXDirector は duration / count を読まない: 時刻は at（遅れ）で表す。追従のメッシュは弾が消えると止まって寿命まで残るので、
// 彗星と落ちる光球は短い寿命の繰り返しで出す（弾が消えると残りの予定は消える）。

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
    /// 刻印の弾けの桃の泡・電光（#A64CC3）。
    private static let magenta = FXTint.rgb(0.65, 0.30, 0.76)
    /// 刻印の弾けの足元の灰色の石（#5A6F88）。
    private static let stone = FXTint.rgb(0.35, 0.44, 0.53)
    /// 刻印の胸の光の玉（#A5AEE2）。
    private static let markTint = FXTint.rgb(0.65, 0.68, 0.89)
    /// 奥義の照準線の黒に近い紺（#030106 の芯）。
    private static let sightDark = FXTint.rgb(0.02, 0.03, 0.08)

    // MARK: - sim の時刻・寸法（Kit_H030.RainaTuning と同じ値。sim を変えたらここも合わせる）

    /// 星爆弾の爆発と刻印の弾けの半径（スキル定義の radius 190）。
    private static let blast: Float = 1.9
    /// 奥義の溜め（ultWindup。動画: 指を離してから 17 コマ = 0.57 秒）。
    private static let windup: Float = 0.55
    /// S1・S2 の溜め（s1Windup / s2Windup。動画: 弾の進みを術者の中心まで戻すと指を離してから 3 コマ）。弾はこの時刻に出る。
    private static let shotWindup: Float = 0.1
    /// 星環弾の光球の弧。travel は弾の地面の位置に付いて動き高さを持たないので、上がる層（0〜orbPeak 秒、毎秒 orbRise m）と
    /// 落ちる層（orbPeak 秒から orbFallLife 秒、毎秒 orbFall m）を重ねて弧に見せる（動画: 砲口の高さ約 1.0 から上がり、
    /// 後半に約 1.5 の頂きを越えて的の胸の高さへ落ちた）。射程いっぱい（5.64m ≒ 0.54 秒）で出た高さに戻り、それより長く追うと
    /// さらに下がる。落ちる層は捉えた敵が逃げて長く追う場合（約 0.9 秒）まで続く。
    private static let orbPeak: Float = 0.25
    private static let orbRise: Float = 1.4
    private static let orbFall: Float = 1.2
    private static let orbFallLife: Float = 0.65

    /// 星の砲の砲口（局所座標）。
    private static let muzzle: SIMD3<Float> = [0.2, 1.2, 0.9]

    // MARK: - 見た目の時刻・寸法（動画に合わせた値。sim の判定とは別）

    /// 彗星（S1）・落ちる光球（S2）の 1 回の寿命と繰り返しの間隔（弾が消えたら残りの予定は消える）。
    private static let segment: Float = 0.1
    private static let segmentLife: Float = 0.115
    /// 落ちる光球の繰り返し（0.25 + 0.2 × 3 = 0.85 秒まで。orbFallLife とほぼ同じ）。
    private static let fallEvery: Float = 0.2
    private static let fallCount = 3
    /// 奥義のビームの根元（砲口の 0.6m 先。動画: ビームは砲口の少し前から始まる）。
    private static let beamGap: Float = 0.6

    // MARK: - 部品

    /// 寝かせた光の円柱（ビーム）。原点から前へ length m 伸びる（back なら後ろへ）。半径 r0 → r1 へ ease で変わる。
    /// 画像（beam）は根元が明るく先へ薄れ、上から見ると中心線が明るく縁へ薄れる。
    private static func beamTube(length: Float, radius r0: Float, to r1: Float, _ tint: FXTint, life: Float,
                                 alpha: Float, back: Bool = false, ease: FXEase = .in, fadeOut: Float = 0.6) -> FXMesh {
        FXMesh(shape: .cylinder, tex: .beam, tint: tint, alpha: alpha, size: [r0, length, r0], sizeEnd: [r1, length, r1],
               ease: ease, life: life, fadeIn: 0.03, fadeOut: fadeOut, pitch: back ? -90 : 90).glowing()
    }

    /// 前を向いて寝かせた光の帯（彗星の体など）。大きさは変えない。
    private static func streakBody(length: Float, width: Float, _ tint: FXTint, life: Float, alpha: Float = 1) -> FXMesh {
        FXMesh.ray(.streak, length: length, width: width, tint, life: life, alpha: alpha).with {
            $0.size = $0.sizeEnd
            $0.fadeIn = 0.05
            $0.fadeOut = 0.8
        }.glowing()
    }

    // MARK: - レシピ

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        switch slot {
        case .passive:
            // MLBB には距離補正の見える演出が無い（動画で見つからない）。バッジが点いた合図だけ、砲口に小さなきらめき
            var r = SkillFXRecipe()
            r.cast = [
                .emit(.flare(0.8, .secondary, life: 0.14, tex: .flare4), .follow, offset: muzzle),
                .emit(.sheet(.sparkTwinkle, 0.45, .secondary, end: .primary, count: 2, life: 0.45, radius: 0.15), .follow,
                      offset: muzzle),
            ]
            r.hit = [.emit(.flare(0.6, .secondary, life: 0.12), offset: [0, 1.0, 0])]
            return r
        case .skill1:
            return maleficBomb()
        case .skill2:
            return voidProjectile()
        case .ultimate:
            return destructionRush(s)
        }
    }

    // MARK: - スキル1 遠星弾

    /// 白い頭に青い尾の彗星（溜め 0.1 秒の後に出る）。MLBB: f1047 砲口の水色の光と紺の電光 → f1048 前へ伸びる白い閃光 →
    /// f1049〜1056 彗星（約 2m）と青い光だまり・電光・通り道のきらめき → f1057 敵の体が白く光る（爆発は無い）。
    private static func maleficBomb() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let t = shotWindup
        let fwd = SIMD3<Float>(0, 0, 1)
        r.cast = [
            // 0〜0.1 秒（溜め）: 砲口に水色の光が集まり、紺の電光の筋が前に跳ねる
            .mesh(.sprite(.flare4, 0.35, .secondary, life: t + 0.04, grow: 1.6, alpha: 0.85).glowing(), .follow,
                  offset: muzzle),
            .emit(.sheet(.electricArc, 0.55, deepBlue, end: .primary, life: 0.14), at: 0.04, .follow,
                  offset: muzzle + SIMD3<Float>(0, 0.08, 0.35)),
            // 0.1 秒: 発射。前へ伸びる白い閃光（加算）と砲口の閃光、すぐ後に残る青い光だまり
            .mesh(.ray(.streak, length: 2.0, width: 0.9, .core, life: 0.1).glowing(), at: t, offset: muzzle + fwd * 1.0),
            .emit(.flare(1.6, .core, life: 0.12, tex: .flare6), at: t, offset: muzzle),
            .emit(.bloom(1.3, .primary, life: 0.22, grow: 1.3), at: t + 0.03, offset: muzzle + fwd * 0.4),
            // 砲口から砲弾へ走る電光（f1051〜1052）と前へ散る水色の火花
            .mesh(.ray(.bolt, length: 2.6, width: 0.45, .primary, life: 0.12).glowing(), at: t + 0.09,
                  offset: muzzle + fwd * 1.4),
            .emit(.sparks(6, speed: 6, .secondary, end: .primary, size: 0.08, life: 0.22, gravity: 2).with {
                $0.dir = .forward
                $0.spread = 25
            }, at: t, offset: muzzle),
        ]
        // 彗星: 白い頭・水色の白の芯の帯・青い外の帯（揺らぎの模様が後ろへ流れる）。0.1 秒ごとに出し直す（7.55m ≒ 0.39 秒）
        let n = 4
        r.travel = [
            .mesh(FXMesh.orb(0.13, .core, life: segmentLife, grow: 1.0, alpha: 1).with {
                $0.fadeIn = 0.05
                $0.fadeOut = 0.8
            }.glowing(), .follow, offset: [0, 1.15, 0.1]).repeated(n, every: segment),
            .mesh(streakBody(length: 1.1, width: 0.34, .secondary, life: segmentLife), .follow, offset: [0, 1.15, -0.45])
                .repeated(n, every: segment),
            .mesh(streakBody(length: 2.0, width: 0.75, .primary, life: segmentLife, alpha: 0.9)
                .flowing(.noise, scroll: [1.5, 0], tiling: 1.5, strength: 0.5, edge: .secondary),
                  .follow, offset: [0, 1.15, -0.85]).repeated(n, every: segment),
            // 尾の青い光・通り道に残る青いきらめきと小さな紺の電光
            .emit(.trail(.glow, .primary, rate: 55, life: 0.18, size: 0.42).with { $0.tintEnd = deepBlue }, .follow,
                  offset: [0, 1.15, -0.2]),
            .emit(.trail(.twinkle, .secondary, rate: 22, life: 0.35, size: 0.14).with {
                $0.tintEnd = .primary
                $0.shape = .sphere(0.3)
                $0.speed = 0.3
            }, .follow, offset: [0, 1.15, -0.3], quality: 1),
            .emit(.trail(.glow, deepBlue, rate: 10, life: 0.16, size: 0.5).with {
                $0.sheet = .electricArc
                $0.sheetRandomStart = true
                $0.angleVar = 180
                $0.tintEnd = .primary
                $0.shape = .sphere(0.25)
            }, .follow, offset: [0, 1.15, -0.4]),
        ]
        // 命中・射程の端: 小さな白い閃き（MLBB に爆発は無い）と前へ散る水色の火花
        r.impact = [
            .mesh(.sprite(.glowHard, 0.9, .secondary, life: 0.1, grow: 1.6).glowing(), offset: [0, 1.1, 0]),
            .emit(.sheet(.hitFlash, 1.3, .core, end: .secondary, life: 0.16), offset: [0, 1.1, 0]),
            .emit(.sparks(8, speed: 6, .secondary, end: .primary).with {
                $0.dir = .forward
                $0.spread = 35
            }, offset: [0, 1.1, 0]),
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

    // MARK: - スキル2 星爆弾

    /// 白い芯の青い光球に長い青い尾（溜め 0.1 秒の後に出て、捉えた敵へ弧を描いて飛ぶ）→ 捉えた敵か射程の端で破裂（半径 1.9m）。
    /// 刻印の弾けは telegraph + 同じ破裂。MLBB: f971 砲口の水色の星 → f972〜984 光球と尾 → f908 白い閃き → f910〜911 白から青の球 →
    /// f913〜914 藍に消える。弾けは f1206 桃の泡 → f1207 白い球と灰色の石の輪 → f1209〜1212 藍の靄と電光。
    private static func voidProjectile() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let E = blast
        let t = shotWindup
        let orbAt: SIMD3<Float> = [0, 1.15, 0]
        // 落ちる層は上がる層の頂き（+0.35 m）から始める
        let peakAt = orbAt + SIMD3<Float>(0, orbRise * orbPeak, 0)
        // 尾の放出は弧の中ほどの高さ（放出は高さを動かせない）
        let trailAt = orbAt + SIMD3<Float>(0, 0.15, 0)
        r.cast = [
            // 0〜0.1 秒（溜め）: 砲口に水色の光
            .mesh(.sprite(.flare4, 0.35, .secondary, life: t + 0.04, grow: 1.6, alpha: 0.85).glowing(), .follow,
                  offset: muzzle),
            // 0.1 秒: 発射（砲口の水色の白の星と青い光だまり）
            .emit(.flare(1.2, .secondary, life: 0.12, tex: .flare4), at: t, offset: muzzle),
            .emit(.bloom(0.9, .primary, life: 0.2, grow: 1.4), at: t, offset: muzzle + SIMD3<Float>(0, 0, 0.2)),
        ]
        // 光球（直径約 0.55m）: 白い芯と、細胞の模様が流れる青い殻（加算）。上がる層と、短い寿命を繰り返す落ちる層で弧にする
        let core = FXMesh.orb(0.13, .core, life: orbPeak, grow: 1.0, alpha: 1).glowing()
        let shell = FXMesh.orb(0.28, .primary, life: orbPeak, grow: 1.0, alpha: 0.85).glowing()
            .flowing(.cells, scroll: [0.8, -0.6], tiling: 1.5, strength: 0.6, edge: .secondary)
        func rising(_ m: FXMesh) -> FXMesh {
            m.with {
                $0.life = orbPeak
                $0.rise = orbRise
                $0.fadeIn = 0.02
                $0.fadeOut = 0.97
            }
        }
        func falling(_ m: FXMesh) -> FXMesh {
            m.with {
                $0.life = fallEvery + 0.02
                $0.rise = -orbFall
                $0.fadeIn = 0.02
                $0.fadeOut = 0.92
            }
        }
        let fallStep = SIMD3<Float>(0, -orbFall * fallEvery, 0)
        r.travel = [
            .mesh(rising(core), .follow, offset: orbAt),
            .mesh(rising(shell), .follow, offset: orbAt),
            .mesh(falling(core), at: orbPeak, .follow, offset: peakAt).repeated(fallCount, every: fallEvery, step: fallStep),
            .mesh(falling(shell), at: orbPeak, .follow, offset: peakAt).repeated(fallCount, every: fallEvery, step: fallStep),
            // 長い青い尾（細りながら消える）と、光球のすぐ後ろの水色の白の芯の尾
            .emit(.trail(.glow, .primary, rate: 70, life: 0.25, size: 0.5).with { $0.tintEnd = deepBlue }, .follow,
                  offset: trailAt),
            .emit(.trail(.glow, .secondary, rate: 50, life: 0.12, size: 0.22).with { $0.tintEnd = .primary }, .follow,
                  offset: trailAt),
        ]
        // 破裂（光球の命中・射程の端・刻印の弾け）: 白い閃き → 白く膨らむ球 → 青い球（模様が欠けて消える）→ 藍の靄
        r.impact = [
            .mesh(.sprite(.glowHard, 1.2, .core, life: 0.08, grow: 1.6).glowing(), offset: [0, 0.9, 0]),
            .mesh(FXMesh.orb(0.5, .core, life: 0.16, grow: 3.2, alpha: 0.95).with { $0.fadeOut = 0.45 }.glowing(), at: 0.03,
                  offset: [0, 0.7, 0]),
            .mesh(FXMesh.orb(1.0, .primary, life: 0.24, grow: 1.7, alpha: 0.85).with { $0.fadeOut = 0.35 }.glowing()
                .flowing(.cells, scroll: [0.4, -0.8], tiling: 2, strength: 0.6, erosion: 0.45, edge: .secondary),
                  at: 0.05, offset: [0, 0.7, 0]),
            .mesh(FXMesh.orb(1.55, indigo, life: 0.26, grow: 1.08, alpha: 0.35).with {
                $0.fadeIn = 0.25
                $0.fadeOut = 0.5
            }, at: 0.1, offset: [0, 0.7, 0]),
            // 球の下の床が青く光る
            .mesh(.decal(.glow, E * 1.9, .primary, life: 0.35, spin: 0, grow: 1.0, alpha: 0.55).glowing(), at: 0.03),
            // 球の中の水色の電光と、外へ散る火花
            .emit(.sheet(.electricArc, 1.0, .secondary, end: .primary, count: 3, life: 0.28, radius: 1.0), at: 0.08,
                  offset: [0, 0.7, 0]),
            .emit(.sparks(12, speed: 7, .core, end: .primary), offset: [0, 0.8, 0]),
            .shake(0.15),
        ]
        // 刻印の弾け（遅れ 0 のゾーン。破裂と同時）: 桃の泡、足元の灰色の石の輪、桃の電光、床を這う電光、藍の煙
        r.telegraph = [
            .mesh(.sprite(.glow, 1.7, magenta, life: 0.12, grow: 1.5).glowing(), offset: [0, 0.9, 0]),
            .mesh(.decal(.crack, E * 1.75, stone, life: 0.7, spin: 0, grow: 1.05, alpha: 0.85), at: 0.03),
            .emit(.debris(10, speed: 2.5, stone, size: 0.18).with { $0.shape = .ring(E * 0.8) }, at: 0.03),
            .emit(.sheet(.electricArc, 1.2, magenta, end: indigo, count: 2, life: 0.3, radius: 0.4), at: 0.06,
                  offset: [0, 0.9, 0]),
            .emit(.groundSheet(.electricArc, E * 1.7, .secondary, life: 0.32), at: 0.1, offset: [0, 0.06, 0]),
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

    /// 0.55 秒溜めて、射程いっぱい（20m）を貫く極太のビーム。MLBB: f373 紺の照準線 → f376〜380 暗い殻の球（青い芯）と紺の渦 →
    /// f383〜384 金の芯 → f385 淡い金の閃光 → f386 横の光条 → f388〜391 極太の白青のビーム → f392〜396 細る → f397〜399 細い水色の線。
    private static func destructionRush(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = s.range
        let W = s.radius
        let t = windup
        let y = muzzle.y
        // ビームの軸（砲口の高さ・右へのずれ）と根元（砲口の beamGap 先）。終点から後ろへ伸ばす層は軸にそろえる
        let axis: SIMD3<Float> = [muzzle.x, y, 0]
        let start = muzzle + SIMD3<Float>(0, 0, beamGap)
        let Lb = max(1, L - start.z)
        let orbPos = muzzle + SIMD3<Float>(0, 0.05, 0.75)
        let sightLength: Float = 10
        let sightAt = start + SIMD3<Float>(0, 0, sightLength * 0.5)
        r.cast = [
            // 0.08〜0.5: 紺の照準線（黒に近い芯・青い縁）が前へ伸びる
            .mesh(.ray(.streak, length: sightLength, width: 0.5, sightDark, life: 0.42, alpha: 0.85).with {
                $0.fadeIn = 0.15
                $0.fadeOut = 0.7
            }, at: 0.08, offset: sightAt),
            .mesh(.ray(.streak, length: sightLength, width: 0.9, .primary, life: 0.42, alpha: 0.7).with {
                $0.fadeIn = 0.15
                $0.fadeOut = 0.7
            }.glowing(), at: 0.08, offset: sightAt - SIMD3<Float>(0, 0.02, 0)),
            // 0.17〜0.53: 砲口の前の暗い殻の球（外縁が暗い輪）。芯は青（〜0.41）→ 金（0.40〜）。紺の渦が巻く
            .mesh(.sprite(.shockwave, 0.8, .dark, life: 0.36, grow: 1.0, alpha: 0.9).with {
                $0.fadeIn = 0.12
                $0.fadeOut = 0.8
            }, at: 0.17, .follow, offset: orbPos),
            .mesh(.sprite(.glowHard, 0.5, .primary, life: 0.24, grow: 0.8).glowing(), at: 0.17, .follow, offset: orbPos),
            .mesh(.sprite(.glowHard, 0.55, .accent, life: 0.14, grow: 1.3).glowing(), at: 0.40, .follow, offset: orbPos),
            .emit(.sheet(.darkWisp, 0.9, deepBlue, end: .dark, count: 2, life: 0.4, additive: false), at: 0.15, .follow,
                  offset: orbPos),
            // 0.47: 淡い金の閃光、0.51: 横に伸びるレンズの光条、0.55: 白い閃光と前へ散る水色の光条
            .emit(.flare(3.0, .accent, life: 0.12, tex: .flare6), at: t - 0.08, offset: orbPos),
            .mesh(.sprite(.streak, 4.5, .core, life: 0.12, grow: 1.25).glowing(), at: t - 0.04, offset: orbPos),
            .emit(.flare(3.0, .core, life: 0.16, tex: .flare6), at: t, offset: start),
            .emit(.fan(20, .secondary, speed: 13, spread: 10, life: 0.3), at: t, offset: start),
            // 0.55: 射程いっぱいの極太のビーム。外の青い円柱と白い芯の円柱を、根元から前へ・終点から後ろへ 2 本ずつ重ね、
            // 太いまま光ってから 0.3 秒で細る（ease .in。動画: 太い 0.1 秒 → 細る → 0.27 秒で細い線）。外の円柱は筋の模様が前へ流れる
            .mesh(beamTube(length: Lb, radius: W, to: W * 0.1, .primary, life: 0.3, alpha: 0.95)
                .flowing(.streaks, scroll: [0, -4], tiling: 3, strength: 0.5, edge: .secondary), at: t, offset: start),
            .mesh(beamTube(length: Lb, radius: W, to: W * 0.1, .primary, life: 0.3, alpha: 0.8, back: true)
                .flowing(.streaks, scroll: [0, 4], tiling: 3, strength: 0.5, edge: .secondary), at: t, .target, offset: axis),
            .mesh(beamTube(length: Lb, radius: W * 0.5, to: W * 0.05, .core, life: 0.28, alpha: 1), at: t, offset: start),
            .mesh(beamTube(length: Lb, radius: W * 0.5, to: W * 0.05, .core, life: 0.28, alpha: 0.85, back: true), at: t,
                  .target, offset: axis),
            // 細った後に残る細い水色の線（全長で同じ明るさ）
            .mesh(FXMesh(shape: .cylinder, tex: nil, tint: .secondary, alpha: 0.9, size: [0.07, Lb, 0.07],
                         sizeEnd: [0.025, Lb, 0.025], ease: .in, life: 0.2, fadeIn: 0.1, fadeOut: 0.4, pitch: 90).glowing(),
                  at: t + 0.2, offset: start),
            // ビームの根元: 後ろを向いた青い殻（縁が明るい）と、細るにつれ目立つ光の点
            .mesh(FXMesh(shape: .dome, tex: .beam, tint: .primary, alpha: 0.7, size: [W * 0.8, W * 0.5, W * 0.8],
                         sizeEnd: [W * 1.1, W * 0.8, W * 1.1], ease: .out, life: 0.26, fadeIn: 0.05, fadeOut: 0.5,
                         pitch: -90).glowing(), at: t + 0.02, offset: start + SIMD3<Float>(0, 0, 0.1)),
            .mesh(.sprite(.glowHard, 0.8, .secondary, life: 0.3, grow: 0.6).with {
                $0.fadeIn = 0.2
                $0.fadeOut = 0.6
            }.glowing(), at: t + 0.1, offset: start),
            .shake(0.45, at: t),
        ]
        // ビームの先頭（70 m/s の貫通弾）: 小さな光と後ろへ流れる水色の光条（MLBB ではビームが一瞬で伸びるので目立たせない）
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
            .emit(.sheet(.hitFlash, 2.0, .core, end: .secondary, life: 0.2), offset: [0, 1.1, 0]),
            .emit(.sparks(14, speed: 9, .secondary, end: .primary).with {
                $0.dir = .forward
                $0.spread = 40
            }, offset: [0, 1.1, 0]),
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

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 砲を構えて（0.1 秒の溜め = s1Windup）撃ち、反動で上体が跳ねる（全体 = 0.27 + 戻り 0.25 = 0.52 秒）
            m.aim(shotWindup)
            m.recoil(0.05, power: 0.6)
            m.hold(0.12) { $0.glow = 1.4 }
        case .skill2:
            // 砲口を少し上げて構え（0.1 秒の溜め = s2Windup）、光球を撃ち出して重い反動を受け止める（全体 = 0.28 + 戻り 0.25 = 0.53 秒）
            m.aim(shotWindup, up: 0.04)
            m.recoil(0.06, power: 0.85)
            m.settle(0.12)
        case .ultimate:
            // 腰を落として砲を据え（0.55 秒の溜め = 0.12 + 0.2 + 0.23。動画: 指を離してから 17 コマ）、撃った反動で上体が大きく
            // 跳ねて半歩下がり、ビームが消えるまで構え続ける（全体 = 1.06 + 戻り 0.35 = 1.41 秒）
            m.brace(0.12, depth: 0.2)
            m.aim(0.2)
            m.hold(0.23) { $0.glow = 2.6; $0.ring = 1.2 }
            m.recoil(0.06, power: 1.2)
            m.hold(0.24) { $0.glow = 2.2 }
            m.settle(0.16)
        }
    }
}
