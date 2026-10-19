import Foundation
import VelstriaCore

// スキル演出: H033 紅牙のヴァルド（Assassin / 巨大な大剣・紺のコート。MLBB の Alucard の Velstria 版）。
// 主題: 蒼く光る大剣の斬撃と、傷から吸い上げる血。MLBB の既定スキンの画面収録（vid11、docs/vfx/H033.md）に合わせ、
// 斬撃・地割れ・衝撃波は蒼（主 #1F75C9・縁の水色 #38B5FA）、回転斬りは濃い藍（#353DCD）、吸収は紫がかった瑠璃（#3B68E3・#8862FE）、
// 命中だけを血の紅（#E3384D）にする。斬撃の帯の本体はアルファ合成で濃く、明るい縁・閃光・光るひびだけを加算にする。
// sim の実際の挙動（Systems/Kits/Kit_H033.swift の Tune）に合わせたタイミング:
//   パッシブ 追撃          — スキルを発動するたび（バッジのタイマーが始まるたび）: 大剣に小さな蒼い閃き
//                            （MLBB は術者に演出が無く、バフのアイコンと射程の円だけ。追撃そのものは通常攻撃の演出）
//   スキル1 裂地撃         — 指定地点へ最大 4.2m を約 0.34 秒（12.5m/s。壁も越える）で跳び込み、着いた tick に半径 1.9m を叩く
//                            （鈍足 40%・2 秒）。転がりは impact を再生しない（ゾーンを作らない）ので、着地の叩きつけは cast の
//                            .target（= 実際の着地点。壁越えで照準とずれても着地点）に 0.34 秒遅れで置く:
//                            頭上から振り下ろす蒼の三日月 → 白い閃光と放射の光条・範囲を染める蒼い光だまり・暗い縁の輪・
//                            放射のひび（光る蒼 + 暗い影）・火の粉・岩片
//   スキル2 旋回斬         — その場で大剣を回す（即時・半径 2.5m）。指を離して 2 コマ（0.06 秒）から、太い藍の三日月が
//                            左回りに約 1.6 周（毎秒 2000°）掃いて 0.4 秒で消える（術者の spin と同じ向き）
//   奥義 核分裂波          — 1 回目（吸収・即時）: 向きの帯（術者から 6.4m・半幅 1.5m）を水色の靄が術者へ流れ込み、
//                            足元に瑠璃の光の円と紫の渦、術者が白く光って大剣を掲げ、蒼い帯が体に巻き上がり、紺の渦の跡が残る（約 0.6 秒）。
//                            弾を出さない（impact は再生されない）ので cast に置く（.along で帯の上）。
//                            2 回目（stage 1、6 秒以内）: 0.16 秒の振りかぶりの後に前方へ大剣を振り抜く（段の演出 recipe(_:stage:_:)）→
//                            貫通する衝撃波（届く 6.4m・半幅 1.65m・10m/s で約 0.48 秒）。衝撃波の travel / impact / hit は共通の演出
//                            （投射物の visual はスキルの演出 ID = 段 0）: 前へ凸の蒼の三日月・水色の前縁・後ろに曳く紺の残像
//   命中（各スキルの hit）  — 1 コマ白桃に光り → 紅の閃き・交差する紅の斬撃が 0.25 秒。吸血（奥義を習得している間 常時）として
//                            傷から紅の光条が術者の方へ飛ぶ（動画は体力が満タンで回復が見えないので、光条は Velstria の推定の演出）
// SkillFXDirector は duration / count を読まない。

enum FX_H033: HeroFXSet {
    // 動画（vid11）で測った色: 主 = S1 の三日月・衝撃波の本体（#1E77C7・#1664CD）、副 = 明るい縁（#39BAFA・#17BAFC）、
    // 差し色 = 命中の紅（#E2394D・#E94257）、暗 = 地割れの影（#10232A）。
    static let palette = FXPalette(core: RGB(0.93, 0.97, 1.0), primary: RGB(0.12, 0.46, 0.79),
                                   secondary: RGB(0.22, 0.71, 0.98), accent: RGB(0.89, 0.22, 0.3),
                                   dark: RGB(0.05, 0.12, 0.17))

    /// 回転斬りの藍の帯（f270 #353DCD）と、その明るい縁（#A0C6FF）。
    private static let indigo = FXTint.rgb(0.21, 0.24, 0.80)
    private static let indigoEdge = FXTint.rgb(0.63, 0.78, 1.0)
    /// 吸収の足元の光（f347〜350 #3B68E3・明るい所 #7592FF）、紫の差し（#8862FE）、残る渦の紺（f354〜358 #1C2A9E）。
    private static let lapis = FXTint.rgb(0.23, 0.41, 0.89)
    private static let periwinkle = FXTint.rgb(0.46, 0.57, 1.0)
    private static let violet = FXTint.rgb(0.53, 0.38, 1.0)
    private static let swirlNavy = FXTint.rgb(0.11, 0.16, 0.62)
    /// 衝撃波の後ろに曳く紺（f433〜440 #032FA3）。
    private static let navy = FXTint.rgb(0.02, 0.18, 0.62)
    /// 命中の最初のコマの白桃（f534・f603 #FBA7B8）と、紅の消え際（#A1232F）。
    private static let blush = FXTint.rgb(0.99, 0.66, 0.72)
    private static let blood = FXTint.rgb(0.63, 0.14, 0.18)
    /// 叩きつけの火の粉（f175〜177 #E99B50〜#E27F5E）。
    private static let ember = FXTint.rgb(0.91, 0.55, 0.31)
    /// 土煙（暗い土色のアルファ合成）。
    private static let dust = FXTint.rgb(0.42, 0.34, 0.3)

    // MARK: - sim の時刻・寸法（Kit_H033.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 跳び込みの所要（s1Range 420 / s1Speed 1250 ≈ 0.34 秒。動画 10.3〜10.7 コマ）。
    private static let rollTime: Float = 0.34
    /// 奥義の衝撃波: 届く 6.4m・半幅 1.65m・10m/s（弾の進む 4.75m ≈ 0.48 秒）。振りかぶり 0.16 秒の後に出る。
    private static let waveHalfWidth: Float = 1.65
    private static let waveLife: Float = 0.5
    private static let waveDelay: Float = 0.16

    // MARK: - 見た目の時刻（動画に合わせた値。sim の判定とは関係しない）

    /// スキル2: 帯が出るまで（指を離して 2 コマ）と回る速さ（1 周 5〜6 コマ ≈ 毎秒 2000°）。
    private static let whirlStart: Float = 0.06
    private static let whirlSpin: Float = 2000

    // MARK: - 部品

    /// 斬撃の三日月の板（.slash / .slashThin の外縁は板の 0.47）の直径。外縁の半径 r にする。
    private static func plate(_ r: Float) -> Float { r / 0.47 }

    /// 回る大剣の帯（水平の三日月の板を yaw 度から毎秒 whirlSpin 度で回す。外縁の半径 r）。
    private static func spinBand(_ r: Float, _ tint: FXTint, tex: FXTex, yaw: Float, life: Float,
                                 alpha: Float) -> FXMesh {
        let d = plate(r)
        return FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [d * 0.94, 1, d * 0.94], sizeEnd: [d, 1, d],
                      ease: .out, life: life, fadeIn: 0.06, fadeOut: 0.7, yaw: yaw, spin: whirlSpin)
    }

    /// 外から内へ縮む輪（吸収）。直径 d0 → d1。
    private static func implode(_ d0: Float, to d1: Float, _ tint: FXTint, life: Float, tex: FXTex = .shockwave,
                                spin: Float = 0, alpha: Float = 0.9) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [d0, 1, d0], sizeEnd: [d1, 1, d1], ease: .in,
               life: life, fadeIn: 0.12, fadeOut: 0.8, spin: spin)
    }

    /// 大きさのほぼ変わらない地面の模様（出た瞬間に全体が見える縁の輪・光だまり）。直径 d。
    private static func flat(_ tex: FXTex, _ d: Float, _ tint: FXTint, life: Float, alpha: Float,
                             fadeOut: Float = 0.5) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [d * 0.92, 1, d * 0.92], sizeEnd: [d, 1, d],
               ease: .out, life: life, fadeIn: 0.05, fadeOut: fadeOut)
    }

    /// 前へ進む衝撃波の三日月（前方が凸。横 w × 奥行き d の板）。
    private static func waveCrescent(_ tex: FXTex, _ tint: FXTint, width w: Float, depth d: Float,
                                     alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [w, 1, d], sizeEnd: [w * 1.12, 1, d * 1.1], ease: .out,
               life: waveLife, fadeIn: 0.04, fadeOut: 0.8)
    }

    /// 命中（MLBB: 被弾者が 1 コマ白桃に光り、紅の閃きと交差する紅の斬撃が 0.25 秒・体が紅く残る）。
    private static func bloodHit(_ size: Float) -> [FXCue] {
        [
            .emit(.sheet(.hitFlash, size * 1.3, blush, end: .accent, life: 0.26), offset: [0, 1.0, 0]),
            .emit(.sheet(.slashFade, size * 1.2, .accent, end: blood, life: 0.24), offset: [0, 1.05, 0]),
            .mesh(.sprite(.glow, size, .accent, life: 0.3, grow: 1.15, alpha: 0.75).glowing(), offset: [0, 1.0, 0]),
        ]
    }

    /// 吸血: 傷から紅の光条が術者の方へ飛び（hit の前方 = 術者 → 被弾者なので後ろ向き）、届く頃に術者の胸が紅く脈打つ
    /// （hit の .along(0) = 被弾した瞬間の術者の位置）。動画では体力が満タンで見えない（推定の演出）。
    private static func drain(_ n: Int, at t: Float = 0.08) -> [FXCue] {
        [
            .emit(FXEmit(tex: .streak, tint: .accent, tintEnd: blush, count: n, emit: 0.12, life: 0.32, lifeVar: 0.15,
                         size: 0.09, sizeVar: 0.3, grow: 0.6, shape: .sphere(0.3), dir: .backward, speed: 9, speedVar: 0.2,
                         spread: 14, stretch: 2.2, fade: .linearFadeOut), at: t, offset: [0, 1.0, 0]),
            .mesh(.sprite(.glow, 0.9, .accent, life: 0.28, grow: 1.4, alpha: 0.6).glowing(), at: t + 0.24, .along(0),
                  offset: [0, 1.0, 0]),
        ]
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        switch slot {
        case .passive:
            // 追撃の準備（スキルの発動のたび）: 大剣に小さな蒼い閃き（MLBB は術者に演出が無い。スキルの演出に重なるので小さく短く）
            r.cast = [
                .emit(.flare(0.8, .secondary, life: 0.14, tex: .flare4), .follow, offset: [0.35, 1.15, 0.3]),
                .mesh(.sprite(.slashLine, 1.2, .secondary, life: 0.2, grow: 1.3).glowing(), .follow, offset: [0.3, 1.2, 0.3]),
            ]
            r.hit = []
        case .skill1:
            r = groundsplitterRecipe(s)
        case .skill2:
            r = whirlRecipe(s)
        case .ultimate:
            r = fissionRecipe(s)
        }
        return r
    }

    // MARK: - スキル1 裂地撃

    /// 宙返りで跳び込み（0〜0.34 秒）→ 着地点で大剣を叩きつける。R = 着地の範囲の半径（1.9m）。
    /// MLBB（vid11 f163〜180）: 跳躍中は淡い残像だけ → f172〜173 頭上から振り下ろす大きな蒼の三日月（#1E77C7・縁 #49B9F6）、
    /// f173 白い閃光と放射の蒼い棘 → f174〜178 範囲いっぱいの蒼い光（#1864B7）・暗い縁の輪・放射の暗いひび（#10232A）・火の粉 →
    /// f180 前後で消える（ひびの影だけ少し残る）。
    private static func groundsplitterRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 2.4)
        let T = rollTime
        r.cast = [
            // 宙返りの間の淡い蒼の残像（MLBB は跳び出しに土煙が無い）
            .emit(.trail(.streak, .primary, rate: 60, life: 0.22, size: 0.4).with {
                $0.duration = T - 0.04; $0.stretch = 2.6; $0.dir = .backward; $0.speed = 2.5; $0.tintEnd = .secondary
            }, .follow, offset: [0, 1.0, 0]),
            // 着地の直前: 頭上から振り下ろす大きな蒼の三日月（どの向きに跳んでも画面で弧に見えるようカメラ向き）。
            // 本体はアルファ合成で濃く、走って欠ける明るい縁（コマ送り）は加算
            .mesh(.sprite(.slash, plate(1.5), .primary, life: 0.26, grow: 1.08, alpha: 0.95).with { $0.fadeOut = 0.5 },
                  at: T - 0.04, .target, offset: [0, 0.9, 0]),
            .emit(.sheet(.slashFade, plate(1.55), .secondary, end: .primary, life: 0.26).with { $0.angleVar = 0 },
                  at: T - 0.04, .target, offset: [0, 0.9, 0]),
            // 着地: 白い閃光と放射の光条
            .emit(.sheet(.energyBurst, 2.6, .core, end: .secondary, life: 0.3), at: T, .target, offset: [0, 0.5, 0.2]),
            // 範囲を染める蒼い光（アルファ）・暗い縁の輪・蒼く光る放射のひび（加算・細胞の模様が欠けて消える）・広がる暗いひび
            .mesh(flat(.glow, R * 2.6, .primary, life: 0.5, alpha: 0.8), at: T, .target),
            .mesh(flat(.ring, R / 0.44, .dark, life: 0.5, alpha: 0.85), at: T, .target),
            .mesh(.decal(.crack, R * 1.7, .secondary, life: 0.4, spin: 0, grow: 1.1, alpha: 1).glowing()
                .flowing(.cells, scroll: [0.1, 0.4], tiling: 1.5, strength: 0.5, erosion: 0.3, edge: .core), at: T, .target),
            .emit(.groundSheet(.groundCrack, R * 2.2, .dark, life: 0.8, additive: false), at: T, .target, offset: [0, 0.04, 0]),
            // 火の粉・黒い岩片・土煙
            .emit(.sparks(10, speed: 6, ember, end: .accent, gravity: 8).with { $0.dir = .up; $0.spread = 50 }, at: T + 0.02,
                  .target, offset: [0, 0.3, 0]),
            .emit(.debris(10, speed: 6, .dark), at: T, .target, offset: [0, 0.1, 0]),
            .emit(.sheet(.smokePuff, 1.6, dust, count: 3, life: 0.8, additive: false, radius: R * 0.5), at: T + 0.04, .target,
                  offset: [0, 0.3, 0], quality: 1),
            .shake(0.3, at: T),
        ]
        // 転がり（leapSlam）は impact・telegraph を再生しない（着地の演出は cast の .target）。目視確認の実演（-skillDemo）だけが
        // 出すので、既定演出で補われないよう小さく置く
        r.telegraph = [.mesh(flat(.glow, R * 1.6, .primary, life: 0.3, alpha: 0.4))]
        r.impact = [.shake(0.1)]
        // 着地の範囲の敵: 紅の命中・紅い火の粉（f604〜608 #EE6D60）・吸血の光条
        r.hit = bloodHit(1.3) + [
            .emit(.sparks(8, speed: 5, ember, end: .accent), offset: [0, 1.0, 0]),
        ] + drain(8)
        return r
    }

    // MARK: - スキル2 旋回斬

    /// その場で大剣を 1 回転余り振り回す（左回り。術者の spin と同じ）。R = 範囲の半径（2.5m）。
    /// MLBB（vid11 f266〜278・f533〜546）: f268 から太い藍の三日月（#353DCD、明るい所 #A0C6FF、外縁に白い筋）が
    /// 画面で反時計回りに約 1.6 周（1 周 5〜6 コマ）、帯の後ろに薄い輪の残像。f276〜278 で消える。土煙・火花は無い。
    private static func whirlRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 3.0)
        let t = whirlStart
        // 振りかぶった大剣の小さな閃き
        r.cast = [.emit(.flare(0.9, indigoEdge, life: 0.1, tex: .flare4), offset: [0.4, 1.0, 0.4])]
        // 自己中心なので発動と同時に再生される
        r.impact = [
            // 本体: 濃い藍の三日月（アルファ合成）と外縁の白い筋（加算）が一緒に回る
            .mesh(spinBand(R * 0.96, indigo, tex: .slash, yaw: 30, life: 0.32, alpha: 0.95), at: t, offset: [0, 0.75, 0]),
            .mesh(spinBand(R, indigoEdge, tex: .slashThin, yaw: 36, life: 0.28, alpha: 1).glowing(), at: t,
                  offset: [0, 0.78, 0]),
            // 半周遅れて追う薄い残像と、回転の軌跡の薄い輪（f270〜273）
            .mesh(spinBand(R * 0.9, indigo, tex: .slash, yaw: -150, life: 0.3, alpha: 0.45), at: t + 0.03,
                  offset: [0, 0.7, 0]),
            .mesh(.halo(R * 0.95, indigo, life: 0.3, spin: 0, tex: .beam, alpha: 0.28), at: t + 0.02, offset: [0, 0.4, 0]),
            .shake(0.2, at: t),
        ]
        // 斬られた敵: 紅の命中・吸血の光条（動画は指を離して 2 コマで光り、3 コマで数字）
        r.hit = bloodHit(1.2) + drain(6)
        return r
    }

    // MARK: - 奥義 核分裂波

    /// 1 回目（吸収）の cast と、衝撃波（2 回目の投射物）の travel / impact / hit。
    /// W = 吸収の帯の半幅（1.5m）、L = 帯の届く距離（6.4m。cast の照準点 = 帯の先端なので .along(0〜1) が帯の上）。
    /// MLBB（vid11 f346〜366・f651〜670）: f347〜350 帯の中を水色の靄（#2093BD・#1DB5F5）が術者へ流れ、足元に瑠璃の光の円
    /// （#3B68E3・縁 #7592FF）と紫の差し（#8862FE）、術者は白く光って大剣を掲げる。f352〜361 足元が紺の渦の跡（#1C2A9E）になり、
    /// 蒼い帯が体に巻き上がって f363 前後で消える。その後の奥義の間に術者の演出は無い（体力バーの印だけ）。
    private static func fissionRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let W = min(s.radius, 2.0)
        let L = min(max(s.range, 1), 8.0)
        r.cast = [
            // 帯の中を術者へ流れ込む水色の靄（加算・筋の模様が術者の方へ流れて欠ける）と光条
            .mesh(.ray(.glow, length: L, width: W * 2, .secondary, life: 0.24, alpha: 0.6).glowing()
                .flowing(.streaks, scroll: [0, 3], tiling: 2, strength: 0.8, erosion: 0.55, edge: .core), .along(0.5),
                  offset: [0, 0.05, 0]),
            .emit(FXEmit(tex: .streak, tint: .secondary, tintEnd: .core, count: 24, emit: 0.14, life: 0.3, lifeVar: 0.1,
                         size: 0.12, sizeVar: 0.4, grow: 0.6, shape: .box([W * 1.6, 0.4, L * 0.55]), dir: .backward, speed: 13,
                         speedVar: 0.15, spread: 8, stretch: 2.6, fade: .linearFadeOut), at: 0.02, .along(0.6),
                  offset: [0, 0.6, 0]),
            // 足元: 瑠璃の光の円（アルファ）と光る縁、内へ縮む紫の渦（加算）
            .mesh(flat(.glow, 2.8, lapis, life: 0.42, alpha: 0.85), at: 0.02),
            .mesh(.halo(1.3, periwinkle, life: 0.42, spin: 240, tex: .ring, alpha: 0.9).glowing(), at: 0.02,
                  offset: [0, 0.05, 0]),
            .mesh(implode(3.2, to: 1.4, violet, life: 0.32, tex: .swirl, spin: -500, alpha: 0.8).glowing(), at: 0.02),
            // 術者が白く光り、掲げた大剣の先が閃く
            .mesh(.sprite(.glow, 2.0, periwinkle, life: 0.3, grow: 1.3, alpha: 0.85).glowing(), at: 0.05, .follow,
                  offset: [0, 1.1, 0]),
            .emit(.flare(1.4, .core, life: 0.18, tex: .flare6), at: 0.08, .follow, offset: [0.2, 2.3, 0.1]),
            // 体に巻き上がる蒼い帯（アルファ・筋が上へ流れる）と紫の靄、足元に残る紺の渦の跡
            .mesh(.tornado(0.9, height: 2.4, .primary, life: 0.45, spin: 720)
                .flowing(.streaks, scroll: [0, -2.5], tiling: 2, strength: 0.6, erosion: 0.4, edge: .secondary), at: 0.14,
                  .follow),
            .emit(.sheet(.darkWisp, 2.2, violet, end: indigo, life: 0.5), at: 0.12, .follow, offset: [0, 1.0, 0], quality: 1),
            .mesh(.decal(.swirl, 2.8, swirlNavy, life: 0.75, spin: -160, grow: 1.05, alpha: 0.8), at: 0.14),
            .shake(0.2, at: 0.03),
        ]
        // 目視確認の実演（-skillDemo）だけが出す予告（既定演出で補わない）
        r.telegraph = [.mesh(.decal(.moon, W * 2.4, .primary, life: 0.5, spin: 60, alpha: 0.5))]
        // 衝撃波（投射物に追従。前方 = 進行方向）。MLBB（f429〜442）: 前へ凸の厚い蒼の三日月（#1664CD）に水色の前縁（#0CB5FD）、
        // 後ろに紺の残像（#032FA3）を曳いて進み、届く距離の先で紺に溶けて消える。地割れ・火花は無い
        let w = waveHalfWidth * 2.25
        r.travel = [
            .mesh(waveCrescent(.slash, .primary, width: w, depth: w * 0.62)
                .flowing(.noise, scroll: [0, 1.2], tiling: 1.5, strength: 0.45, erosion: 0.2, edge: .secondary), .follow,
                  offset: [0, 0.6, 0]),
            .mesh(waveCrescent(.slashThin, .secondary, width: w * 1.02, depth: w * 0.64).glowing(), .follow,
                  offset: [0, 0.62, 0.05]),
            .mesh(waveCrescent(.slash, navy, width: w * 0.94, depth: w * 0.85, alpha: 0.7)
                .flowing(.streaks, scroll: [0, 2], tiling: 2, strength: 0.5, erosion: 0.5, edge: .primary), .follow,
                  offset: [0, 0.55, -0.55]),
            .emit(.trail(.glow, .primary, rate: 60, life: 0.3, size: 0.8).with { $0.shape = .box([2.6, 0.2, 0.3]) }, .follow,
                  offset: [0, 0.6, 0]),
            .emit(.trail(.smoke, navy, rate: 30, life: 0.4, size: 0.9).with {
                $0.additive = false; $0.grow = 1.6; $0.fade = .gradualFadeInOut; $0.tintEnd = nil
                $0.shape = .box([2.4, 0.2, 0.3])
            }, .follow, offset: [0, 0.5, -0.5], quality: 1),
        ]
        // 衝撃波が最初の敵に当たった点: 白い芯の爆ぜ（紅の命中は hit）
        r.impact = [
            .emit(.sheet(.energyBurst, 2.2, .core, end: .secondary, life: 0.3), offset: [0, 1.0, 0]),
            .shake(0.35),
        ]
        // 衝撃波に貫かれた敵（吸収そのものはダメージ 0 なので hit を出さない）: 紅の命中・吸血の光条
        r.hit = bloodHit(1.4) + drain(10)
        return r
    }

    /// 奥義の 2 回目（stage 1）: 振りかぶり（0.16 秒。大剣に蒼い光が溜まる）の後に前方へ大剣を振り抜いて衝撃波を放つ
    /// （衝撃波そのものは共通の travel。振り抜きは sim で波が出る時刻）。MLBB（f419〜428）: 止まって構え、大剣に蒼い光、
    /// 振り抜きの蒼いぶれ → 三日月の波。
    static func recipe(_ slot: SkillSlot, stage: Int, _ s: FXSkillInfo) -> SkillFXRecipe? {
        guard slot == .ultimate, stage == 1 else { return nil }
        var r = SkillFXRecipe()
        let D = waveDelay
        r.cast = [
            // 振りかぶり: 大剣に走る蒼い光と、溜まる光
            .mesh(.sprite(.slashLine, 1.3, .secondary, life: D + 0.04, grow: 1.2).glowing(), at: 0.02,
                  offset: [0.35, 1.2, 0.1]),
            .emit(.gather(10, radius: 0.6, .secondary, life: D), offset: [0.35, 1.2, 0.1]),
            // 振り抜き: 前方の水平の三日月（本体アルファ + 明るい縁は加算）・閃光・前へ噴く光条
            .mesh(.slash(2.0, .primary, from: 80, to: -80, life: 0.22), at: D, offset: [0, 0.9, 0.2]),
            .mesh(.slash(2.1, .secondary, from: 85, to: -85, life: 0.18, tex: .slashThin).glowing(), at: D,
                  offset: [0, 0.95, 0.25]),
            .emit(.flare(1.6, .core, life: 0.16, tex: .flare6), at: D, offset: [0, 1.0, 0.7]),
            .emit(.fan(14, .secondary, speed: 10, spread: 25, life: 0.3), at: D, offset: [0, 0.9, 0.4]),
            .shake(0.3, at: D),
        ]
        return r
    }

    // MARK: - 詠唱モーション

    /// 奥義は 2 回とも同じモーション（モーションは段で分けられない）: 低く構えて 0.16 秒に前へ振り抜き（衝撃波が出る時刻。
    /// 吸収は即時なので構えが少し長く見える）、そのまま大剣を掲げて力を吸い上げる。全長 0.6 + 戻り 0.35 = 0.95 秒。
    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 低く転がり出して跳び、頭上から大剣を叩きつける（着地 0.34 秒）。全長 0.5 + 戻り 0.25 = 0.75 秒
            m.dash(0.1, lean: 0.6)
            m.leap(0.16, height: 0.55, forward: 0.2)
            m.overhead(0.04)
            m.smash(0.04)
            m.land(0.06, depth: 0.24)
            m.hold(0.1) { $0.glow = 1.8 }
        case .skill2:
            // 大剣を振りかぶり、その場で左回りに一回転（動画の回転は 0.07〜0.3 秒）。全長 0.48 + 戻り 0.25 = 0.73 秒
            m.windup(0.06, side: 1, power: 1.2)
            m.spin(0.27, turns: 1)
            m.hold(0.05)
            m.settle(0.1)
        case .ultimate:
            m.brace(0.1, depth: 0.12)
            m.slash(0.06, side: 1, power: 1.3)
            m.hold(0.1) { $0.glow = 1.8 }
            m.raise(0.14, glow: 2.0)
            m.hold(0.1) { $0.ring = 1.2 }
            m.settle(0.1)
        }
    }
}
