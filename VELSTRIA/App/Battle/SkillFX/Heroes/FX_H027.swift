import Foundation
import VelstriaCore

// スキル演出: H027 竜槍のジャルド（Duelist / 竜の意匠の長槍・銀青の鎧・赤い房飾り。MLBB の Zilong の Velstria 版）。
// 主題: 竜の炎をまとう槍。白金の芯 × 竜炎の金橙（主。MLBB のスキルの金の槍炎）× 槍の鰭の青（副。モデルの発光色）×
// 房の赤（差し色）× 土煙。上から見下ろすカメラで「敵を頭上越しに背後へ放り投げる」「対象へ一直線に踏み込んで突き通す」
// 「三連の突き」「竜炎のオーラ」が読めるよう、全周の輪を主役にせず、頭上を越える縦の弧・金の筋・突き通す光条・燃え上がる炎で形を見せる。
// sim の実際の挙動（Systems/Kits/Kit_H027.swift の Tune）に合わせたタイミング:
//   パッシブ 竜の三連突き — cast: 竜気が 1 つたまるたび（パッシブのバッジのスタックが増えるたび、0.4 秒に 1 回まで）に、槍の穂先に
//                          小さな金の炎と回る輪。三連突き自体は通常攻撃（Effekseer）の 3 連続ヒット（0.13 秒おき）。
//                          passiveRelease: スキルの発動の直後（0.6 秒以内）に竜気を使い切った = スキル2 の踏み込みからそのまま
//                          三連突き、のときだけ、前方へ 3 本の金の突き（0 / 0.135 / 0.27 秒）と竜頭の閃光
//   スキル1 跳槍撃       — 扇（近接）のアーキタイプなので発動と同時に cast と impact（術者の位置、前方 = 対象）。槍で掬い上げる金の
//                          縦の弧が術者の頭上を越えて背後へ（前方の対象から背後 1.7m へ）、地面にも前後へ走る金の筋。対象の足元で
//                          土と火花が跳ね上がる。被弾（打ち上げ 0.8 秒、背後へ 0.7 秒で飛ぶ）: 被弾者に追従して、飛ぶ間は金の筋と
//                          竜炎が上へ立ちのぼる尾（= 頭上を越える弧の軌跡）、昇る金の輪 → 0.7 秒で着地（追従するので実際の着地点）
//   スキル2 竜牙突き     — 対象指定の突進（ブリンクのアーキタイプ: impact は発動時に対象の位置）。cast: 前に構えた槍の光条が術者と
//                          一緒に走り、金の筋と青い光の尾（突進 ≈ 0.2 秒）。impact: 対象に金の照準の輪が縮む（捕捉）。
//                          被弾（到着の瞬間 = 実際に当たった時刻）: 対象を突き通す光条・前へ吹く竜炎・青い鱗の盾が砕ける（防御ダウン）・
//                          足元の赤いひび（防御ダウン 2 秒）
//   アルティメット 至高の武人 — 自己強化（selfAoE: 発動と同時に cast と impact）。槍を回す金の弧 → 0.05〜0.1 秒で竜炎が渦を巻いて
//                          立ちのぼり（金と青の竜巻・炎の壁・噴き上がる炎）、咆哮の閃光。7.5 秒の強化の間は足元から金の炎が立ちのぼり、
//                          後方へ速さの筋が流れる（追従の継続放出。duration = 7.5）
// 再使用の段（stage）は Zilong に無いので使わない。

enum FX_H027: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.97, 0.86), primary: RGB(1.0, 0.68, 0.2),
                                   secondary: RGB(0.35, 0.82, 1.0), accent: RGB(1.0, 0.3, 0.22),
                                   dark: RGB(0.14, 0.07, 0.03))

    /// 土煙・土の破片（明るい土色のアルファ合成）。
    private static let dust = FXTint.rgb(0.58, 0.48, 0.34)
    /// 構えた槍の穂先（局所座標。右手に立てた槍）。
    private static let spearTip: SIMD3<Float> = [0.3, 1.7, 0.35]

    // MARK: - sim の時刻（Kit_H027.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 背後へ飛んで着地するまで（flipFlight）・着地点（術者の中心から背後、flipLandingGap）。
    private static let flipFlight: Float = 0.7
    private static let flipLanding: Float = 1.7
    /// スキル2: 突進の所要の目安（最長 450 / 2400 ≈ 0.19 秒）。
    private static let strikeTime: Float = 0.2
    /// パッシブ: 三連突きの間隔（4 tick ≈ 0.133 秒）。
    private static let flurryGap: Float = 0.135
    /// アルティメット: 強化の秒数。
    private static let ultDuration: Float = 7.5

    // MARK: - 部品

    /// 槍で掬い上げる縦の弧（三日月を立てる: pitch −90 で弧の膨らみを真上へ、roll で弦の向きを決める）。前方やや左の地面から
    /// 頭上を越えて背後やや右の地面へ。弦を前後の軸から 40° ずらし、真上から見下ろすカメラの視線と弧の面が重ならない（細い線にならない）ようにする。
    private static func flipArc(_ r: Float, _ tint: FXTint, life: Float, tex: FXTex = .slash) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: 1, size: [r * 1.7, 1, r * 1.7], sizeEnd: [r * 2.1, 1, r * 2.1],
               ease: .out, life: life, fadeIn: 0.04, fadeOut: 0.35, pitch: -90, roll: 50)
    }

    /// 縮んで対象を捕らえる照準の輪（直径 d0 → d1）。
    private static func lockOn(from d0: Float, to d1: Float, _ tint: FXTint, life: Float) -> FXMesh {
        FXMesh(shape: .disc, tex: .ringDouble, tint: tint, alpha: 0.9, size: [d0, 1, d0], sizeEnd: [d1, 1, d1], ease: .in,
               life: life, fadeIn: 0.1, fadeOut: 0.7, spin: 360)
    }

    /// 上へ揺らめく竜の炎（立てた炎の板）。
    private static func dragonFlame(_ count: Int, radius: Float, speed: Float, life: Float, size: Float,
                                    _ tint: FXTint = .core, end: FXTint = .primary) -> FXEmit {
        FXEmit(tex: .flame, tint: tint, tintEnd: end, count: count, emit: 0.15, life: life, size: size, sizeVar: 0.4, grow: 0.5,
               shape: .disc(radius), dir: .up, speed: speed, speedVar: 0.4, orient: .upright, fade: .gradualFadeInOut)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        switch slot {
        case .passive: return chargeRecipe(s)
        case .skill1: return flipRecipe(s)
        case .skill2: return strikeRecipe(s)
        case .ultimate: return warriorRecipe(s)
        }
    }

    // MARK: - パッシブ 竜の三連突き

    /// 竜気が 1 つたまるたび: 穂先の小さな金の炎（頻繁に出るので小さく短く）。
    private static func chargeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        r.cast = [
            .emit(.flare(0.8, .primary, life: 0.14, tex: .flare4), .follow, offset: spearTip),
            .emit(dragonFlame(5, radius: 0.08, speed: 1.2, life: 0.4, size: 0.18), .follow, offset: spearTip),
            .mesh(.halo(0.42, .primary, life: 0.35, spin: 420, tex: .ring), .follow, offset: [0.3, 1.2, 0.3]),
        ]
        // パッシブのダメージは通常攻撃（Effekseer）。既定の被弾演出で補われないよう小さな合図だけ置く
        r.hit = [.mesh(.halo(0.35, .primary, life: 0.25, spin: 200, tex: .ring), .follow, offset: [0, 0.2, 0])]
        return r
    }

    /// スキル2 の踏み込みからそのまま三連突き（竜気を使い切った）: 前方へ 3 本の金の突きと竜頭の閃光。
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? {
        let g = flurryGap
        return [
            .mesh(.ray(.streak, length: 2.4, width: 0.6, .primary, life: 0.16), .follow, offset: [-0.15, 1.05, 1.4])
                .repeated(3, every: g, step: [0.15, 0, 0]),
            .mesh(.ray(.streak, length: 1.8, width: 0.3, .core, life: 0.12), .follow, offset: [-0.15, 1.08, 1.5])
                .repeated(3, every: g, step: [0.15, 0, 0]),
            .emit(.flare(1.2, .primary, life: 0.14, tex: .flare6), .follow, offset: [-0.15, 1.05, 2.5])
                .repeated(3, every: g, step: [0.15, 0, 0]),
            .emit(.fan(10, .primary, speed: 7, spread: 18, life: 0.3, tex: .flame, size: 0.2), at: 2 * g, .follow,
                  offset: [0, 1.05, 1.2]),
            .emit(.sparks(10, speed: 6, .core, end: .accent).with { $0.dir = .forward; $0.spread = 25 }, at: 2 * g, .follow,
                  offset: [0, 1.05, 2.2]),
        ]
    }

    // MARK: - スキル1 跳槍撃

    /// 掬い上げ（0）→ 対象が頭上を越えて背後へ（0〜0.7 秒）→ 着地（0.7 秒）。
    private static func flipRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let flight = flipFlight
        // 低く構えた槍の穂先が地を擦る
        r.cast = [
            .emit(.flare(0.9, .primary, life: 0.12), offset: [0.25, 0.5, 0.8]),
            .emit(.sparks(8, speed: 4, .primary, end: .accent, gravity: 6), offset: [0.25, 0.15, 0.9]),
        ]
        // 発動と同時（術者の位置、前方 = 対象）: 頭上を越える金の縦の弧（外の金 + 芯の白金）と、前後へ走る地面の金の筋。
        // 対象の足元（.target）で土と火花が跳ね上がる
        r.impact = [
            .mesh(flipArc(1.9, .primary, life: 0.42), at: 0.02, offset: [0, 0.25, 0]),
            .mesh(flipArc(1.75, .core, life: 0.28, tex: .slashThin), at: 0.05, offset: [0, 0.3, 0]),
            .mesh(.ray(.streak, length: 2 * flipLanding + 0.6, width: 0.9, .primary, life: 0.55, alpha: 0.8), at: 0.04,
                  offset: [0, 0.02, 0.3]),
            .mesh(.decal(.crack, 1.6, .dark, life: 0.9, spin: 0, grow: 1.0, alpha: 0.6), .target),
            .emit(.flare(1.4, .core, life: 0.16, tex: .flare6), .target, offset: [0, 0.8, 0]),
            .emit(.sparks(14, speed: 7, .core, end: .primary, gravity: 9).with { $0.dir = .up; $0.spread = 30 }, .target,
                  offset: [0, 0.4, 0]),
            .emit(.debris(8, speed: 5, dust), .target),
            .emit(.smoke(6, radius: 0.4, dust, life: 0.8, size: 0.7), .target, quality: 1),
        ]
        // 被弾（打ち上げ 0.8 秒）: 被弾者に追従。飛ぶ間は金の筋と竜炎が上へ立ちのぼる尾、昇る金の輪 → 0.7 秒で実際の着地点に着地
        r.hit = [
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: .primary, rate: 90, duration: flight, life: 0.32, size: 0.2,
                         sizeVar: 0.3, grow: 0.4, shape: .sphere(0.25), dir: .up, speed: 3, stretch: 2.0, fade: .linearFadeOut),
                  .follow, offset: [0, 0.9, 0]),
            .emit(FXEmit(tex: .flame, tint: .primary, tintEnd: .accent, rate: 40, duration: flight, life: 0.4, size: 0.4,
                         sizeVar: 0.3, grow: 0.5, shape: .sphere(0.2), dir: .up, speed: 1.5, orient: .upright,
                         fade: .gradualFadeInOut), .follow, offset: [0, 1.2, 0], quality: 1),
            .mesh(.halo(0.55, .primary, life: 0.8, spin: 420, tex: .ringDouble).with { $0.rise = 1.5 }, .follow,
                  offset: [0, 0.3, 0]),
            // 着地（追従しているので実際の着地点）
            .mesh(.shockRing(1.1, .primary, life: 0.3, tex: .ring), at: flight, .follow),
            .mesh(.decal(.crack, 1.5, .dark, life: 0.9, spin: 0, grow: 1.0, alpha: 0.6), at: flight, .follow),
            .emit(.debris(10, speed: 5, dust), at: flight, .follow),
            .emit(.smoke(6, radius: 0.5, dust, life: 0.8, size: 0.8), at: flight, .follow, quality: 1),
            .shake(0.18, at: flight),
        ]
        return r
    }

    // MARK: - スキル2 竜牙突き

    /// 対象へ踏み込み（≈ 0.2 秒）、到着の瞬間に突き通す（被弾の時刻 = 実際に当たった時刻）。
    private static func strikeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let t = strikeTime
        // 前に構えた槍の光条が術者と一緒に走り、金の筋と青い光の尾を引く
        r.cast = [
            .emit(.flare(1.2, .core, life: 0.12), offset: [0, 1.0, 0.4]),
            .mesh(.ray(.streak, length: 2.2, width: 0.7, .primary, life: t + 0.04).with { $0.fadeOut = 0.7 }, .follow,
                  offset: [0.15, 1.05, 1.3]),
            .emit(.trail(.streak, .primary, rate: 90, life: 0.28, size: 0.45).with {
                $0.duration = t; $0.stretch = 3; $0.dir = .backward; $0.speed = 4; $0.tintEnd = .accent
            }, .follow, offset: [0, 1.0, 0]),
            .emit(.trail(.glow, .secondary, rate: 60, life: 0.3, size: 0.6).with { $0.duration = t }, .follow,
                  offset: [0, 0.9, 0]),
            .emit(.smoke(5, radius: 0.4, dust, life: 0.7, size: 0.6), quality: 1),
        ]
        // 発動時に対象の位置: 金の照準の輪が縮んで捕らえる
        r.impact = [
            .mesh(lockOn(from: 2.4, to: 0.9, .primary, life: t)),
            .emit(.flare(1.0, .secondary, life: 0.14, tex: .flare4), offset: [0, 1.1, 0]),
        ]
        // 到着の瞬間（被弾）: 対象を突き通す光条・前へ吹く竜炎・砕ける青い鱗の盾（防御ダウン）・足元の赤いひび（2 秒）
        r.hit = [
            .mesh(.ray(.streak, length: 3.0, width: 0.75, .core, life: 0.2), offset: [0, 1.05, 0.4]),
            .mesh(.ray(.streak, length: 2.4, width: 1.5, .primary, life: 0.3, alpha: 0.85), offset: [0, 1.0, 0.6]),
            .emit(.flare(1.6, .core, life: 0.16, tex: .flare6), offset: [0, 1.0, 0]),
            .emit(.fan(16, .primary, speed: 9, spread: 22, life: 0.35, tex: .flame, size: 0.26), offset: [0, 1.0, 0.1]),
            .emit(.sparks(12, speed: 8, .core, end: .accent).with { $0.dir = .forward; $0.spread = 30 }, offset: [0, 1.0, 0.2]),
            .mesh(.wall(.hexShield, width: 1.2, height: 1.3, .secondary, life: 0.3, alpha: 0.7).with {
                $0.ease = .out; $0.sizeEnd = [1.6, 1.6, 1]
            }, offset: [0, 0.35, -0.45]),
            .emit(.flutter(.shard, 10, radius: 0.4, .secondary, speed: 3.5, life: 0.7, size: 0.14), offset: [0, 1.0, -0.3]),
            .mesh(.decal(.crack, 1.5, .accent, life: 1.9, spin: 0, grow: 1.0, alpha: 0.65), .follow),
            .shake(0.2),
        ]
        return r
    }

    // MARK: - アルティメット 至高の武人

    /// 槍を回して竜炎が渦を巻いて立ちのぼる → 7.5 秒の強化の間、足元から金の炎と後方への速さの筋。
    private static func warriorRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let d = ultDuration
        r.cast = [
            .emit(.gather(18, radius: 1.2, .primary, life: 0.2), offset: [0, 1.1, 0]),
            .mesh(.sweep(1.5, .primary, from: 90, to: -270, life: 0.3), at: 0.04, offset: [0, 1.0, 0]),
            // 強化の間（7.5 秒）追従: 足元から立ちのぼる金の炎と、後方へ流れる速さの筋
            .emit(FXEmit(tex: .flame, tint: .primary, tintEnd: .accent, rate: 22, duration: d, life: 0.55, size: 0.38,
                         sizeVar: 0.4, grow: 0.5, shape: .ring(0.45), surface: true, dir: .up, speed: 1.8, orient: .upright,
                         fade: .gradualFadeInOut), .follow, offset: [0, 0.1, 0]),
            .emit(.trail(.streak, .secondary, rate: 16, life: 0.4, size: 0.35).with {
                $0.duration = d; $0.stretch = 3; $0.dir = .backward; $0.speed = 4
            }, .follow, offset: [0, 0.9, -0.2], quality: 1),
            .mesh(.halo(0.75, .primary, life: 4.0, spin: 160, tex: .ringDouble, alpha: 0.6), .follow, offset: [0, 0.12, 0]),
        ]
        // 発動と同時: 竜炎が渦を巻いて立ちのぼり（金と青の竜巻・炎の壁・噴き上がる炎）、咆哮の閃光
        r.impact = [
            .mesh(.tornado(1.1, height: 4.2, .primary, life: 0.9, spin: 600), at: 0.05),
            .mesh(.tornado(0.8, height: 3.4, .secondary, life: 0.75, spin: -800), at: 0.08),
            .mesh(FXMesh(shape: .cylinder, tex: .flame, tint: .primary, alpha: 0.85, size: [0.5, 0.4, 0.5],
                         sizeEnd: [1.5, 1.8, 1.5], ease: .out, life: 0.6, fadeIn: 0.05, fadeOut: 0.45), at: 0.08),
            .emit(dragonFlame(26, radius: 1.0, speed: 4.5, life: 0.7, size: 0.4), at: 0.08),
            .emit(.vortex(22, radius: 1.3, .secondary, life: 0.8, speed: 3.5), at: 0.06, quality: 1),
            .emit(.flare(2.4, .core, life: 0.24, tex: .flare6), at: 0.1, offset: [0, 1.3, 0]),
            .emit(.groundGlow(1.6, .primary, life: 0.6), at: 0.08),
            .mesh(.shockRing(2.2, .primary, life: 0.4, tex: .ring), at: 0.1),
            .emit(.embers(16, radius: 1.0, .primary, life: 1.2), at: 0.15, quality: 1),
            .shake(0.35, at: 0.1),
        ]
        // ダメージは無い。既定の被弾演出で補われないよう小さな合図だけ置く
        r.hit = [.mesh(.halo(0.4, .primary, life: 0.3, spin: 160, tex: .ring), .follow, offset: [0, 0.2, 0])]
        return r
    }

    // MARK: - 詠唱モーション

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 低く構え、槍を下から頭上へ掬い上げて敵を背後へ放り投げる
            m.brace(0.05, depth: 0.15)
            m.uppercut(0.12)
            m.hold(0.12) { $0.glow = 1.6 }
            m.settle(0.1)
        case .skill2:
            // 前傾で駆け（≈ 0.2 秒）、踏み込みざまに槍を突き通す
            m.dash(0.05, lean: 0.6)
            m.lunge(0.07, distance: 0.6, lean: 0.35)
            m.thrust(0.05)
            m.hold(0.1) { $0.glow = 1.6 }
            m.settle(0.1)
        case .ultimate:
            // 低く構えて槍を頭上で回し、胸を張って咆哮する（自己強化なので踏み込みも跳躍もしない）
            m.brace(0.06, depth: 0.18)
            m.twirl(0.22, turns: 1.5)
            m.roar(0.12)
            m.hold(0.2) { $0.glow = 2.2 }
            m.settle(0.12)
        }
    }
}
