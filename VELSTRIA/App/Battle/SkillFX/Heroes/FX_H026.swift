import Foundation
import VelstriaCore

// スキル演出: H026 紫電のエウリア（Arcanist / 細身の杖・周囲に浮く小さな雷球。MLBB の Eudora の Velstria 版）。
// 主題: 青い稲妻。MLBB の画面収録（docs/vfx/H026.md）の色に合わせて、水色がかった白い芯（core）× 紺碧の青（主）×
// 水色の電光（副）× 青紫（差し色。奥義の中心の電撃）× 紺の夜（暗）。紫は奥義の中心と炸裂の名残りだけに残す。
// 円い光の床ではなく、「扇へ指のように広がる太い稲妻」「術者と敵を結ぶ細い雷の鎖」「縁の光る泡の雷球」
// 「天から落ちる太い大雷と画面を白く飛ばす閃光・輪に沿って掃く水色の弧」で形を見せる。
// 縦の稲妻は、円盤を横倒しにした板 2 枚を直交させる（どの向きから見ても読める）か、カメラを向く粒を 90° 回して描く。
// 光る部品（稲妻・閃光・光の柱・輪の縁・電光のもや）は加算（glowing）、奥義の深い青の帯と魔防ダウンの盾面はアルファ合成。
// 電光の網目は流れる模様 .cells、這う・まとう電弧はコマ送りの electricArc、命中の星は hitFlash、雷球の弾けは energyBurst。
// sim の実際の挙動（Systems/Kits/Kit_H026.swift の EuriaTuning）に合わせたタイミング。時刻と寸法は MLBB の訓練場の画面収録で
// 測った値（docs/kits/Eudora.md「動画で測った値（2026-10-16）」）:
//   パッシブ 超伝導          — 印そのものの合図はバッジを持たないので試合中は出ない（cast は目視確認の実演用: 頭上の ϟ と体の電弧）。
//                              アルティメットが超伝導の敵に当たると、その敵に追従するゾーン（半径 2.61m・0.83 秒後）が雷の炸裂を起こす。
//                              ゾーンの演出 ID がこのパッシブなので、この枠の telegraph = 0.83 秒の待ち（半径 2.61m の細い水色の輪が
//                              動かずに灯り、最後に中心へ青い光が集まる）、impact = 炸裂（白い縦の雷・深い青に満ちて縁の光る円・這う電弧・
//                              体に残る小さな電光の球）
//   スキル1 分岐雷          — 前方の扇（射程 5.76m・半角 37.5°）へ即時（cast と impact を発動と同時に再生）。0.05 秒に杖の先から
//                              7 本の太い稲妻が指のように扇へ広がり（水色の光の帯 + 紺碧のぎざぎざの芯）、帯が先に消えて細い芯が残り、
//                              扇の中に藍色の電光のもやが広がって細い電弧が這う。
//                              被弾 1 回ごと（扇の初撃・雷の鎖の継続ダメージ 0.12 秒から 0.27 秒おき 4 回・1 秒後の終わりの一撃。hitPerHit）に、
//                              被弾者に白い星の閃き（hitFlash）と体の電弧、術者 → 被弾者の線上に細い稲妻の筋を連ねて「雷の鎖」を描く
//                              （.along。画質 1 以上）。印の無い敵は扇の初撃の 1 回だけ = 稲妻が届く一瞬の筋、印のある敵は継続ダメージの
//                              4 回と終わりの一撃で筋が 1 秒つながる（鎖の見た目は印の有無で sim のヒットの数から自然に分かれる）
//   スキル2 雷球            — 対象を追う雷球（11.5 m/s。追尾弾は向きが決まらないので形は丸いものだけ）: 白い芯・縁の光る水色の泡
//                              （カメラを向く輪）・中を走る電弧・青い彗星の尾。当たって弾ける（白い星の閃光 → 縁の光る青い泡が広がって
//                              0.2 秒で消える・小さな縦の雷）。当たった敵ごと（印済みなら周囲 2.6m にも広がる = 広がった敵にもこの hit）に、
//                              スタン 1 秒の体の電弧と頭上の輪、魔防ダウン 1.8 秒の足元の淡い六角の盾
//   アルティメット 九天雷鳴 — 発動〜0.45 秒: 掲げた手に電光が集まり、足元の地面を水色の電弧が巡る（着弾点には MLBB でも予告が無いので
//                              淡く這う電弧だけ。範囲の予告はゾーンの表示）。0.41 秒（予告の終わりの 1 コマ前）: 天から太い大雷と光の柱が落ちる。
//                              0.45 秒（impact）: 画面が白く飛ぶ閃光の代わりに範囲の外まで覆う淡い光、中心に青紫の電撃、範囲に淡い水色の光 →
//                              深い青の帯（アルファ）。0.14 秒後（見た目だけ。sim は中心と外側を同じ tick に当てる）: 外側の帯に白い稲妻が落ちて
//                              輪に沿って走り、外縁を水色の弧が渦を巻いて掃く
// SkillFXDirector は duration / count を読まない: 時刻は at（遅れ）で表す。

enum FX_H026: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.86, 0.97, 1.0), primary: RGB(0.2, 0.47, 1.0),
                                   secondary: RGB(0.32, 0.82, 1.0), accent: RGB(0.52, 0.4, 1.0),
                                   dark: RGB(0.04, 0.07, 0.22))

    /// スキル1 の扇に広がる藍色の電光のもや（動画 #4161C5〜#4C6EE4）。
    private static let haze = FXTint.rgb(0.27, 0.38, 0.85)
    /// 奥義の後に範囲に残る深い青の帯（アルファ合成。動画 #2942C8〜#3F61D0）。
    private static let deep = FXTint.rgb(0.14, 0.27, 0.82)
    /// 画面が白く飛ぶ閃光の色（動画 f485 / f1019 の淡い水色がかった白）。
    private static let pale = FXTint.rgb(0.72, 0.88, 1.0)

    // MARK: - sim の時刻・寸法（Kit_H026.EuriaTuning と同じ値。sim を変えたらここも合わせる）

    /// 雷の炸裂の遅れ（burstDelay 0.83）・半径（burstRadius 261）。
    private static let burstDelay: Float = 0.83
    private static let burstRadius: Float = 2.61
    /// アルティメット: 予告（ultDelay 0.45）・中心の半径（ultCenterRadius 115）。
    private static let ultDelay: Float = 0.45
    private static let ultCenter: Float = 1.15
    /// スキル2: スタン・魔防ダウンの長さ。
    private static let stunTime: Float = 1.0
    private static let shredTime: Float = 1.8

    // MARK: - 見た目の時刻（動画に合わせた値。sim の時刻ではない）

    /// 奥義の外側の雷が中心の雷に遅れる見た目の時間（動画の 4〜5 コマ = 0.13〜0.17 秒）。
    private static let outerLag: Float = 0.14

    /// 杖の先（局所座標）。
    private static let tip: SIMD3<Float> = [0.2, 1.5, 0.8]
    /// 稲妻の枝の根元（杖の先のすこし手前）。
    private static let root: SIMD3<Float> = [0.2, 1.25, 0.8]

    // MARK: - 部品

    /// 地を這う・宙を走る稲妻の芯（pivot から angle 度（+ = 左）の向きへ length m の細いぎざぎざ）。flip で模様の向きを逆にする。
    private static func branch(_ angle: Float, length: Float, _ tint: FXTint, at t: Float = 0,
                               from pivot: SIMD3<Float>, life: Float = 0.26, width: Float = 0.8,
                               flip: Bool = false) -> FXCue {
        let a = angle * .pi / 180
        let d = length / 2
        let mid = pivot + SIMD3<Float>(-sin(a) * d, 0, cos(a) * d)
        let m = FXMesh.ray(.bolt, length: length, width: width, tint, life: life).glowing().with {
            $0.yaw = (flip ? 270 : 90) + angle
        }
        return .mesh(m, at: t, offset: mid)
    }

    /// 稲妻の太い光の帯（光の筋の板。電光の網目が流れ、縁から欠けて細りながら消える）。向き・長さは branch と同じ。
    private static func tendril(_ angle: Float, length: Float, _ tint: FXTint, at t: Float,
                                from pivot: SIMD3<Float>, life: Float, width: Float) -> FXCue {
        let a = angle * .pi / 180
        let d = length / 2
        let mid = pivot + SIMD3<Float>(-sin(a) * d, 0, cos(a) * d)
        let m = FXMesh.ray(.streak, length: length, width: width, tint, life: life).glowing()
            .flowing(.cells, scroll: [-4, 0], tiling: 1.5, strength: 0.6, erosion: 0.45, edge: .core).with {
                $0.yaw = 90 + angle
                $0.fadeOut = 0.35
            }
        return .mesh(m, at: t, offset: mid)
    }

    /// 縦の稲妻（円盤を横倒しにした板。稲妻の模様が上下に走る。光る）。中心が原点。repeated(2, yaw: 90) で直交の 2 枚にする。
    private static func bolt(height: Float, width: Float, _ tint: FXTint, life: Float, alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .disc, tex: .bolt, tint: tint, alpha: alpha, size: [height, 1, width * 0.6],
               sizeEnd: [height, 1, width], ease: .out, life: life, fadeIn: 0.02, fadeOut: 0.35, yaw: 45, roll: 90).glowing()
    }

    /// 縦の稲光の粒（カメラを向く板を 90° 回して、稲妻の模様を上下にする）。
    private static func boltFlash(_ size: Float, _ tint: FXTint, count: Int = 1, life: Float = 0.18) -> FXEmit {
        FXEmit(tex: .bolt, tint: tint, tintEnd: .primary, count: count, life: life, lifeVar: 0.2, size: size,
               sizeVar: 0.15, grow: 1.0, angle: 90, angleVar: 12, fade: .linearFadeOut)
    }

    /// 雷球の電光（小さな玉のまわりに電弧が走る）。
    private static func spark(_ n: Int, radius: Float, speed: Float = 3) -> FXEmit {
        FXEmit.sparks(n, speed: speed, .core, end: .primary, size: 0.1, life: 0.3, gravity: 0).with {
            $0.shape = .sphere(radius)
        }
    }

    /// まとう・這う電弧（コマ送りの electricArc。繰り返しの画像を寿命の間だけ流す）。radius の円盤の中に count 枚。
    private static func arcs(_ size: Float, _ tint: FXTint = .secondary, end: FXTint? = .primary, count: Int,
                             life: Float, radius: Float = 0, ground: Bool = false) -> FXEmit {
        .sheet(.electricArc, size, tint, end: end, count: count, life: life, orient: ground ? .ground : .billboard,
               radius: radius)
    }

    /// n 本の放射（半径 r の輪に並べて外向きに向ける）。start = 1 本目の向き（度、+ = 左）。
    private static func radial(_ m: FXMesh, _ n: Int, radius r: Float, start: Float = 0, at t: Float = 0,
                               height: Float = 0.12, quality: Int = 0) -> FXCue {
        let a = start * .pi / 180
        var c = FXCue.mesh(m.with { $0.yaw += start }, at: t, offset: [-sin(a) * r, height, cos(a) * r],
                           quality: quality)
        c.count = n
        c.stepYaw = 360 / Float(max(1, n))
        c.orbit = 0.0001
        return c
    }

    /// 地面の円の板（直径 d0 → d1。tex = 円の模様）。
    private static func groundDisc(_ tex: FXTex, _ d0: Float, _ d1: Float, _ tint: FXTint, alpha: Float, life: Float,
                                   fadeIn: Float = 0.05, fadeOut: Float = 0.45) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [d0, 1, d0], sizeEnd: [d1, 1, d1], ease: .out,
               life: life, fadeIn: fadeIn, fadeOut: fadeOut)
    }

    /// 細い輪の画像（.ring）の線が半径 r に来る板の直径（画像の輪は板の半径の 0.88 の所に描かれている）。
    private static func ringSpan(_ r: Float) -> Float { r * 2 / 0.88 }
    /// 衝撃波の画像（.shockwave）の明るい縁が半径 r に来る板の直径（縁の山は板の半径の 0.94 の所）。
    private static func rimSpan(_ r: Float) -> Float { r * 2 / 0.94 }

    /// 塗りつぶした円（平たく潰した球。縁まで同じ濃さで地面を染める。アルファ合成）。半径 r0 → r1。
    /// 画像の無いメッシュは加算・流れる模様にしない（その材質は形に .glow の画像を使うので、球の UV では一様に塗れない）。
    private static func fill(_ r0: Float, _ r1: Float, _ tint: FXTint, alpha: Float, life: Float,
                             fadeIn: Float = 0.1, fadeOut: Float = 0.45) -> FXMesh {
        FXMesh(shape: .sphere, tex: nil, tint: tint, alpha: alpha, size: [r0, 0.02, r0], sizeEnd: [r1, 0.02, r1],
               ease: .out, life: life, fadeIn: fadeIn, fadeOut: fadeOut)
    }

    /// 小さな光（スキルのダメージが出ない段を既定の演出で補わせないための詰め物）。
    private static func glint(_ tint: FXTint) -> [FXCue] {
        [.emit(.flare(0.6, tint, life: 0.12), offset: [0, 1.0, 0])]
    }

    // MARK: - レシピ

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        switch slot {
        case .passive:
            return superconductor()
        case .skill1:
            return forkedLightning(s)
        case .skill2:
            return ballLightning()
        case .ultimate:
            return thundersWrath(s)
        }
    }

    // MARK: - パッシブ 超伝導（と雷の炸裂）

    private static func superconductor() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let B = burstRadius
        // 実演用の合図: MLBB の印（敵の頭上の白い ϟ）のように頭上に縦の稲光が灯り、体を電弧が走って水色の輪が巡る
        r.cast = [
            .emit(boltFlash(0.7, .core, life: 0.6).with {
                $0.angleVar = 0
                $0.lifeVar = 0
                $0.tintEnd = .secondary
            }, .follow, offset: [0, 2.35, 0]),
            .emit(arcs(1.0, count: 3, life: 0.3, radius: 0.3), .follow, offset: [0, 1.1, 0]),
            .mesh(.halo(0.6, .secondary, life: 0.5, spin: 480, tex: .ring).glowing(), .follow, offset: [0, 1.0, 0]),
            .emit(.flare(0.8, .core, life: 0.14), .follow, offset: [0, 1.6, 0]),
        ]
        // 炸裂の待ち（0.83 秒。超伝導の敵の位置が原点）: MLBB f1024〜1043 = 半径 2.61m の細い水色の輪が縮まずに灯り続け、
        // 炸裂の直前（f1043）に中心へ青い光が集まる。輪の中は暗くならない
        r.telegraph = [
            .mesh(groundDisc(.ring, ringSpan(B), ringSpan(B), .secondary, alpha: 0.9, life: burstDelay, fadeIn: 0.2,
                             fadeOut: 0.97)
                .glowing(), offset: [0, 0.04, 0]),
            .emit(.gather(12, radius: 1.2, .secondary, life: 0.2), at: burstDelay - 0.22, offset: [0, 0.9, 0]),
            .mesh(.sprite(.glow, 1.4, .primary, life: 0.16, grow: 1.3).glowing(), at: burstDelay - 0.12,
                  offset: [0, 0.9, 0]),
        ]
        // 炸裂（f1044〜1056）: 白い縦の雷が敵へ落ち、半径 2.61m の円が青に満ちて縁が水色に光り（0.2 秒で薄れる）、
        // 円の中を電弧が這う。敵の体に小さな電光の球が約 0.4 秒残る
        r.impact = [
            .mesh(bolt(height: 6, width: 1.3, .core, life: 0.22), offset: [0, 3.0, 0]).repeated(2, yaw: 90),
            .emit(.flare(2.2, .core, life: 0.2, tex: .flare6), offset: [0, 1.0, 0]),
            .mesh(groundDisc(.shockwave, rimSpan(B * 0.94), rimSpan(B), .secondary, alpha: 0.95, life: 0.32, fadeIn: 0.02,
                             fadeOut: 0.4)
                .glowing(), offset: [0, 0.05, 0]),
            .mesh(fill(B * 0.95, B, .primary, alpha: 0.32, life: 0.34, fadeIn: 0.02, fadeOut: 0.4),
                  offset: [0, 0.03, 0]),
            .mesh(groundDisc(.glow, B * 1.8, B * 2, .primary, alpha: 0.6, life: 0.36, fadeIn: 0.02).glowing()
                .flowing(.cells, scroll: [0.3, 0.8], tiling: 2, strength: 0.7, erosion: 0.4, edge: .core),
                  offset: [0, 0.06, 0]),
            .emit(arcs(1.4, .core, end: .secondary, count: 6, life: 0.28, radius: B * 0.75, ground: true), at: 0.02,
                  offset: [0, 0.07, 0]),
            .emit(arcs(0.9, count: 3, life: 0.45, radius: 0.25).with { $0.emit = 0.15 }, at: 0.15, offset: [0, 1.0, 0]),
            .mesh(.orb(0.3, .primary, life: 0.45, grow: 1.3, alpha: 0.5), at: 0.15, offset: [0, 1.0, 0]),
            .emit(.sparks(16, speed: 8, .core, end: .secondary, life: 0.35), offset: [0, 0.8, 0]),
            .shake(0.2),
        ]
        // 炸裂のダメージはアルティメット（skill(.ultimate)）として出るので、この枠の hit は再生されない
        r.hit = glint(.secondary)
        return r
    }

    // MARK: - スキル1 分岐雷

    /// 扇（射程 5.76m・半角 37.5°）へ即時に指のように広がる 7 本の稲妻。被弾ごとに雷の鎖の筋（hitPerHit）。
    /// MLBB（f102〜112）: 指を離して 5 コマ後に全部が同じコマで出る。水色の太い帯（#29B6FD、芯 #71FAFE）が 0.1 秒光り、
    /// 細い紺碧の芯（#3C6EDF）が残り、扇の中に藍色のもや（#4161C5）と細い電弧が 0.3 秒ほど残る。
    private static func forkedLightning(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = min(s.range, 7)
        let t: Float = 0.05
        r.cast = [
            .emit(spark(10, radius: 0.25, speed: 2.5), offset: tip),
            .emit(.flare(1.4, .core, life: 0.14, tex: .flare6), at: t, offset: tip),
        ]
        // (向き（度、+ = 左）, 長さの比)。中央から外へ 0.01 秒ずつ（ほぼ同じコマ）
        let fingers: [(Float, Float)] = [(0, 1.0), (12, 0.93), (-12, 0.95), (24, 0.86), (-24, 0.9), (35, 0.78), (-35, 0.8)]
        var impact: [FXCue] = []
        for (k, f) in fingers.enumerated() {
            let dt = t + 0.01 * Float((k + 1) / 2)
            // 水色の太い光の帯（先に消える）と、紺碧のぎざぎざの芯（長く残る。隣どうしで模様の向きを逆に）
            impact.append(tendril(f.0, length: L * f.1, .secondary, at: dt, from: root, life: 0.17, width: k == 0 ? 2.0 : 1.7))
            impact.append(branch(f.0, length: L * f.1, .primary, at: dt, from: root, life: 0.3, width: k == 0 ? 1.2 : 1.0,
                                 flip: k % 2 == 1))
        }
        // 扇に広がる藍色の電光のもや（光る。雲の模様が揺らいで縁から欠ける）
        impact.append(.mesh(FXMesh(shape: .disc, tex: .glow, tint: haze, alpha: 0.55, size: [L * 0.7, 1, L * 0.6],
                                   sizeEnd: [L * 1.25, 1, L * 0.95], ease: .out, life: 0.42, fadeIn: 0.1, fadeOut: 0.5)
            .glowing().flowing(.noise, scroll: [0.3, -0.8], tiling: 1.6, strength: 0.65, erosion: 0.4, edge: .accent),
                            at: t + 0.06, offset: [0, 0.15, L * 0.55]))
        // 扇へ散る電光の粒と、もやの中に残って這う細い電弧
        impact.append(.emit(.fan(20, .secondary, speed: 15, spread: 37, life: 0.3), at: t, offset: tip))
        impact.append(.emit(arcs(1.0, count: 6, life: 0.3).with {
            $0.emit = 0.2
            $0.shape = .box([L * 0.6, 0.4, L * 0.35])
        }, at: t + 0.08, offset: [0, 0.9, L * 0.6]))
        r.impact = impact
        // 被弾 1 回ごと（扇の初撃・鎖の継続ダメージ 0.12 / 0.39 / 0.66 / 0.93 秒・1 秒の終わりの一撃）: 白い星の閃き（MLBB の
        // 命中の白い星）、体を走る電弧、術者 → 被弾者の線上（.along(0) = 術者、1 = 被弾者）に細い稲妻の筋を 3 本連ねて雷の鎖にする
        // （寿命 0.3 秒 > 継続ダメージの間隔 0.27 秒なので、印のある敵には 1 秒つながって見える）。多くの敵に当たる扇の初撃もあるので、
        // 鎖の筋は画質 1 以上だけ
        r.hit = [
            .emit(.sheet(.hitFlash, 1.5, .core, end: .secondary, life: 0.24), offset: [0, 1.1, 0]),
            .emit(arcs(1.1, count: 1, life: 0.22), .follow, offset: [0, 1.0, 0]),
            .mesh(FXMesh.ray(.bolt, length: 2.3, width: 0.9, .core, life: 0.3).glowing().with { $0.yaw = 94 }, .along(0.2),
                  offset: [0, 1.2, 0], quality: 1),
            .mesh(FXMesh.ray(.bolt, length: 2.3, width: 0.9, .secondary, life: 0.3).glowing().with { $0.yaw = 268 },
                  at: 0.02, .along(0.5), offset: [0, 1.15, 0], quality: 1),
            .mesh(FXMesh.ray(.bolt, length: 2.1, width: 0.8, .core, life: 0.28).glowing().with { $0.yaw = 87 }, at: 0.03,
                  .along(0.8), offset: [0, 1.1, 0], quality: 1),
            .emit(.sparks(6, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
        ]
        r.hitPerHit = true
        return r
    }

    // MARK: - スキル2 雷球

    /// 対象を追う雷球 → 当たって弾ける。被弾者ごとにスタン 1 秒と魔防ダウン 1.8 秒。
    /// MLBB（f300〜328）: 縁の光る水色の泡（直径約 0.6m、#347DF3 / 縁 #9CC7F4）の中を白い電弧が走り、青い尾（約 2m）を引く。
    /// 当たると白い星の閃光（#ECF4FB）→ 縁の光る青い泡（直径約 1.5m、#6092F6）が 0.2 秒で消え、スタンの間は体に小さな電弧。
    private static func ballLightning() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let hand: SIMD3<Float> = [0.3, 1.45, 0.55]
        let ball: SIMD3<Float> = [0, 1.15, 0]
        r.cast = [
            .emit(.gather(12, radius: 0.5, .secondary, life: 0.1), offset: hand),
            .emit(.flare(1.2, .core, life: 0.14, tex: .flare6), at: 0.02, offset: hand),
            .emit(arcs(0.9, count: 2, life: 0.16), at: 0.02, offset: hand),
        ]
        // 雷球（追尾弾は向きが決まらないので、丸い芯・カメラを向く泡の縁・ばらばらの向きの電弧と稲光・尾だけ）。
        // 毎秒 11.5m で射程 5.05m の端まで約 0.45 秒。尾の長さ = 速さ × 寿命 ≈ 2.3m
        r.travel = [
            .mesh(.orb(0.2, .core, life: 0.55, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow,
                  offset: ball),
            .mesh(.sprite(.ring, 0.72, .secondary, life: 0.55, grow: 1.0).glowing().with { $0.fadeOut = 0.85 }, .follow,
                  offset: ball),
            .emit(arcs(0.6, .core, end: .secondary, count: 1, life: 0.14).with { $0.rate = 16 }, .follow, offset: ball),
            .emit(.trail(.glow, .primary, rate: 70, life: 0.2, size: 0.62).with {
                $0.grow = 0.35
                $0.tintEnd = .rgb(0.1, 0.22, 0.65)
            }, .follow, offset: ball),
            .emit(.trail(.bolt, .core, rate: 30, life: 0.12, size: 0.9).with {
                $0.angleVar = 25
                $0.grow = 1
                $0.tintEnd = .secondary
            }, .follow, offset: ball),
        ]
        // 当たって弾ける: 白い星の閃光と芯 → 縁の光る青い泡（コマ送りの energyBurst と光る球）と中の電弧・小さな縦の雷
        r.impact = [
            .emit(.sheet(.hitFlash, 2.4, .core, end: .secondary, life: 0.22), offset: [0, 1.1, 0]),
            .mesh(.sprite(.glowHard, 1.9, .core, life: 0.12, grow: 1.4).glowing(), offset: [0, 1.1, 0]),
            .emit(.sheet(.energyBurst, 2.0, .secondary, end: .primary, life: 0.3), at: 0.03, offset: [0, 1.05, 0]),
            .mesh(.orb(0.45, .primary, life: 0.3, grow: 1.7, alpha: 0.4), at: 0.03, offset: [0, 1.0, 0]),
            .emit(arcs(1.3, .core, end: .secondary, count: 3, life: 0.28, radius: 0.3), at: 0.03, offset: [0, 1.0, 0]),
            .mesh(bolt(height: 2.6, width: 0.9, .secondary, life: 0.16), at: 0.02, offset: [0, 1.3, 0]).repeated(2, yaw: 90),
            .emit(.sparks(14, speed: 6, .core, end: .primary), offset: [0, 1.0, 0]),
            .shake(0.12),
        ]
        // 被弾者ごと: スタン 1 秒（体を小さな電弧が走り続け、頭上を輪が回る）と、魔防ダウン 1.8 秒（足元の淡い六角の盾。
        // MLBB は数値の表示だけで見た目が無いので、読める程度に淡く）
        r.hit = [
            .emit(arcs(0.85, count: 1, life: 0.22).with {
                $0.rate = 7
                $0.duration = stunTime
                $0.shape = .sphere(0.35)
            }, .follow, offset: [0, 1.0, 0]),
            .mesh(.halo(0.42, .secondary, life: stunTime, spin: 420, tex: .ringDouble).glowing(), .follow,
                  offset: [0, 2.05, 0]),
            .mesh(.decal(.hexShield, 1.3, .primary, life: shredTime, spin: 30, alpha: 0.35), .follow),
            .emit(boltFlash(1.5, .core), offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
        ]
        return r
    }

    // MARK: - アルティメット 九天雷鳴

    /// 掲げた手に電光・足元を巡る電弧（〜0.45）→ 0.41 秒に天から大雷 → 0.45 秒に白く飛ぶ閃光・中心の青紫の電撃・範囲の光と深い青 →
    /// 0.14 秒後に外側の稲妻と外縁を掃く水色の弧。
    /// MLBB（f471〜506 / f1006〜1032）: 着弾点に予告は無い。中心 #7268DB / #5E51E8（青紫）、範囲 #3F61D0、外縁の弧 #51CEED。焼け跡は残らない。
    private static func thundersWrath(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 3.2)
        let C = ultCenter
        let land = ultDelay
        let lag = outerLag
        let high: SIMD3<Float> = [0.25, 2.3, 0.3]
        r.cast = [
            .emit(.gather(18, radius: 1.0, .secondary, life: 0.14), .follow, offset: high),
            .emit(.flare(1.6, .core, life: 0.2, tex: .flare6), at: 0.1, .follow, offset: high),
            // 足元を這って巡る電弧（f473〜484 / f1007〜1017: 半径 1m ほどの地面を水色の細い電弧が回る）
            .emit(arcs(1.2, count: 7, life: 0.26, ground: true).with {
                $0.emit = 0.36
                $0.shape = .ring(1.0)
                $0.surface = true
            }, .follow, offset: [0, 0.06, 0]),
            .mesh(.halo(1.05, .secondary, life: land + 0.05, spin: 300, tex: .bolt, alpha: 0.8).glowing()
                .flowing(.cells, scroll: [1.2, 0], tiling: 2, strength: 0.6, erosion: 0.4, edge: .core), .follow,
                  offset: [0, 0.08, 0]),
        ]
        // 予告（0.45 秒。中心が原点）: 着弾点の地面を細い電弧が淡く這い（f1011〜1016。推定）、予告の終わりの 1 コマ前（f1018）に
        // 天から太い大雷（白い芯の直交の板）と水色の光の柱が落ちてくる
        r.telegraph = [
            .emit(arcs(1.3, count: 5, life: 0.24, ground: true).with {
                $0.emit = 0.3
                $0.shape = .ring(R * 0.7)
                $0.surface = true
            }, at: 0.05, offset: [0, 0.05, 0], quality: 1),
            .mesh(bolt(height: 11, width: 2.2, .core, life: 0.3), at: land - 0.04, offset: [0, 5.5, 0]).repeated(2, yaw: 90),
            .mesh(FXMesh(shape: .cylinder, tex: .beam, tint: .secondary, alpha: 0.9, size: [0.9, 11, 0.9],
                         sizeEnd: [0.25, 11, 0.25], ease: .out, life: 0.22, fadeIn: 0.05, fadeOut: 0.4).glowing()
                .flowing(.streaks, scroll: [0, 3], tiling: 2, strength: 0.6, edge: .core), at: land - 0.04),
        ]
        r.impact = [
            // 0.45 秒（f485 / f1019）: 画面が白く飛ぶ閃光の代わりに、範囲の外まで覆う淡い光（一瞬）
            .mesh(groundDisc(.glow, 12, 14, pale, alpha: 0.7, life: 0.16, fadeIn: 0.02, fadeOut: 0.3).glowing(),
                  offset: [0, 0.2, 0]),
            .emit(.flare(3.6, .core, life: 0.22, tex: .flare6), offset: [0, 1.2, 0]),
            // 中心: 青紫の電撃が弾ける（f486〜489、半径 1.2m ほど）
            .mesh(bolt(height: 8, width: 1.4, .accent, life: 0.26), at: 0.03, offset: [0.25, 4.0, -0.15]).repeated(2, yaw: 90),
            .mesh(.decal(.glow, C * 2.4, .accent, life: 0.35, spin: 0, grow: 1.1, alpha: 0.85).glowing()
                .flowing(.cells, scroll: [0.4, 0.9], tiling: 1.6, strength: 0.7, erosion: 0.35, edge: .core), at: 0.02,
                  offset: [0, 0.06, 0]),
            .emit(arcs(1.9, .core, end: .accent, count: 5, life: 0.3, radius: C * 0.6), at: 0.02, offset: [0, 0.9, 0]),
            // 範囲を覆う淡い水色の光（f488〜489）→ 深い青の帯が残る（f492〜498。地面を青く染めるアルファ合成）と外縁の細い輪
            .mesh(.decal(.glow, R * 2.2, .secondary, life: 0.3, spin: 0, grow: 1.0, alpha: 0.45).glowing(), at: 0.04),
            .mesh(fill(R * 0.9, R, deep, alpha: 0.32, life: 0.6, fadeIn: 0.15), at: 0.08, offset: [0, 0.02, 0]),
            .mesh(groundDisc(.ring, ringSpan(R), ringSpan(R * 1.02), .secondary, alpha: 0.8, life: 0.55, fadeOut: 0.5)
                .glowing(), at: 0.04, offset: [0, 0.05, 0]),
            // 外側の雷（中心の 0.14 秒後。f489〜491 / f1028）: 外側の帯に白い稲妻が落ち、輪に沿って稲妻が走る
            .emit(boltFlash(3.0, .core, count: 6, life: 0.2).with {
                $0.emit = 0.1
                $0.shape = .ring(R * 0.78)
                $0.surface = true
                $0.tintEnd = .secondary
            }, at: lag, offset: [0, 1.5, 0]),
            radial(FXMesh.ray(.bolt, length: R * 0.85, width: 1.1, .core, life: 0.24).glowing().with { $0.yaw += 90 }, 5,
                   radius: R * 0.78, start: 20, at: lag),
            // 外縁に沿って水色の弧が渦を巻いて掃く（f492〜496）
            .mesh(FXMesh.sweep(R * 0.95, .secondary, from: 30, to: -200, life: 0.38).glowing()
                .flowing(.streaks, scroll: [2.5, 0], tiling: 2, strength: 0.6, erosion: 0.5, edge: .core), at: lag + 0.06,
                  offset: [0, 0.1, 0]),
            .mesh(FXMesh.sweep(R * 0.8, .secondary, from: 210, to: -20, life: 0.36).glowing()
                .flowing(.streaks, scroll: [2.5, 0], tiling: 2, strength: 0.6, erosion: 0.5, edge: .core), at: lag + 0.1,
                  offset: [0, 0.1, 0]),
            .emit(.sparks(28, speed: 9, .core, end: .secondary, life: 0.4), offset: [0, 0.8, 0]),
            .emit(.rising(16, radius: R * 0.8, .secondary, speed: 2.5, life: 0.6), at: 0.12, quality: 1),
            .shake(0.6),
        ]
        // 大雷・雷の炸裂を受けた敵: 白い星の閃き、縦の稲光が体を貫き、電弧が 0.3 秒まとわりつく
        r.hit = [
            .emit(.sheet(.hitFlash, 1.6, .core, end: .secondary, life: 0.22), offset: [0, 1.1, 0]),
            .emit(boltFlash(2.4, .core), offset: [0, 1.3, 0]),
            .emit(arcs(1.0, end: .accent, count: 1, life: 0.18).with {
                $0.rate = 10
                $0.duration = 0.3
                $0.shape = .sphere(0.3)
            }, .follow, offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
        ]
        return r
    }

    // MARK: - 詠唱モーション

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 杖の先へ雷を寄せ（0.05 秒）、両手を前へ突き出して扇へ放つ
            m.gather(0.05)
            m.push(0.05)
            m.hold(0.16) { $0.glow = 2.0 }
        case .skill2:
            // 手元に雷球を溜め、片手で投げ放つ（雷球は発動と同時に飛ぶ）
            m.gather(0.06)
            m.throwCast(0.12)
            m.hold(0.06) { $0.glow = 1.6 }
            m.settle(0.1)
        case .ultimate:
            // 杖を天へ掲げて雷を呼び（0.12 秒で掲げきる。足元を電弧が巡る）、0.45 秒の落雷に合わせて杖を地へ突き立てる
            // （0.12 + 0.26 + 0.07 = 0.45 秒に突き立て、戻りを足して 0.96 秒）
            m.raise(0.12, glow: 2.0)
            m.hold(0.26) { $0.ring = 1.4; $0.glow = 2.6 }
            m.plant(0.07)
            m.hold(0.16) { $0.glow = 2.2 }
        }
    }
}
