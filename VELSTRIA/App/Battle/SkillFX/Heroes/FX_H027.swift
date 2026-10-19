import Foundation
import VelstriaCore

// スキル演出: H027 竜槍のジャルド（Duelist / 竜の意匠の長槍・青緑の鎧・赤いマントと房。MLBB の Zilong の Velstria 版）。
// 主題: 水色に光る槍。白い芯 × 水色（主。MLBB の画面収録の槍の光 #28B6E5〜#28B9BE / #83F9FA）× 青緑（副。突進の尾 #36E4B4）×
// 房の深紅（差し色 #A90D14）× 灰色の土煙。奥義だけ白い風 → 黄緑（#94E853）→ 青緑（#1ED2AA）→ 水色の泡と色が移る。
// 上から見下ろすカメラで「対象へ伸びる光の槍と、背に流れる羽根の尾」「頭上を越えて背後へ描く大きな三日月」「対象を貫く 3 本の突き」
// 「身を包む風の渦と、強化の間に体から立ちのぼる水色の筋」が読めるよう、全周の輪を主役にせず、光の帯・縦の弧・渦で形を見せる。
// 見た目の対応（コマ・色）は docs/vfx/H027.md（MLBB の画面収録 vid5、2026-10-16 の訓練場、Lv15）。
// sim の実際の挙動（Systems/Kits/Kit_H027.swift の Tune。幾何と時間は MLBB の画面収録で測った値: docs/kits/Zilong.md
// 「動画で測った値（2026-10-16）」）に合わせたタイミング:
//   パッシブ 竜の三連突き — cast: 竜気が 1 つたまるたび（0.4 秒に 1 回まで）に、槍の穂先に小さな水色の閃き（MLBB は数を足元の射程の円で
//                          示すだけで、たまる瞬間の演出は見えない。小さく短く）。三連突き自体は通常攻撃（Effekseer）の 3 連続ヒット。
//                          passiveRelease: スキルの発動の直後（0.6 秒以内）に竜気を使い切った = スキル2 の踏み込みからそのまま
//                          三連突き、のときだけ、前方へ 3 本の白水色の長い突き（0 / 0.135 / 0.27 秒。1 本ごとに向きが 12° ずれる）と
//                          命中の白い閃き、腕の後ろへ流れる水色の羽根
//   スキル1 跳槍撃       — 扇（近接）のアーキタイプなので発動と同時に cast と impact（術者の位置、前方 = 対象）。0 秒: 低い水色の弧で
//                          対象の足元を掬い、被弾者に白い閃きと灰色の土煙。0〜0.4 秒（持ち上げ）は被弾者の腰の下に穂先の水色の光。
//                          0.4 秒（放り投げ）: 対象が頭上を越える軌跡 = 水色の大きな縦の三日月（芯の白・残る細い線。0.6 秒で細い線だけ）。
//                          0.4〜0.6 秒は被弾者に追従する白水色の光の尾 → 0.6 秒で着地（追従するので実際の着地点）に灰色の土煙
//   スキル2 竜牙突き     — 対象指定の突進（ブリンクのアーキタイプ: impact は発動時に対象の位置）。cast: 蹴り出しの土煙、前に構えた槍の
//                          白水色の光と、背に流れる青緑の羽根の尾・白い光の筋・深紅の房の帯（突進の秒数 = 発動のイベントの長さ:
//                          durationFromCast）。impact: 術者から対象へ伸びる光の槍（穂先 = 対象。0.2 秒で薄れる）。
//                          被弾（到着の瞬間 = 実際に当たった時刻）: 白い閃き（青い光条）→ 青い縁の弾け・突き通す白い光・火花
//   アルティメット 至高の武人 — 自己強化（selfAoE: 発動と同時に cast と impact）。0 秒: 白い風の筋が渦を巻いて身を包み、0.04 秒で
//                          黄緑の渦 → 0.12 秒で胸の高さに青緑の光 → 0.2〜0.7 秒で水色の半透明の泡と縁の明るい地面の円が薄れる。
//                          7.5 秒の強化の間（発動のイベントの長さ: durationFromCast）は体から水色の筋と淡い炎が立ちのぼる（追従の継続放出）
// 光る部品（光の槍・三日月・閃光・渦・泡）は加算（glowing）、土煙・房の帯はアルファ合成。
// 再使用の段（stage）は Zilong に無いので使わない。

enum FX_H027: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.92, 1.0, 1.0), primary: RGB(0.16, 0.74, 0.84),
                                   secondary: RGB(0.24, 0.9, 0.74), accent: RGB(0.68, 0.06, 0.1),
                                   dark: RGB(0.05, 0.1, 0.12))

    /// 土煙（MLBB の蹴り出し・着地の灰色の煙。アルファ合成）。
    private static let dust = FXTint.rgb(0.6, 0.62, 0.58)
    /// 槍の光の明るい層（MLBB の三日月・持ち上げの光の明るい側 #83F9FA〜#9EF4FA）。
    private static let glowCyan = FXTint.rgb(0.55, 0.97, 0.98)
    /// 突進の到着の閃きの青い光条（#4679B4）。
    private static let hitBlue = FXTint.rgb(0.27, 0.47, 0.71)
    /// 奥義: 白い風（#E5F9EC）→ 黄緑（#94E853）→ 青緑（#1ED2AA）、強化の間の体の光（#40AAA7）。
    private static let wind = FXTint.rgb(0.9, 0.98, 0.93)
    private static let lime = FXTint.rgb(0.58, 0.91, 0.33)
    private static let teal = FXTint.rgb(0.12, 0.82, 0.66)
    private static let aura = FXTint.rgb(0.25, 0.67, 0.66)
    /// 構えた槍の穂先（局所座標。右手に立てた槍）。
    private static let spearTip: SIMD3<Float> = [0.3, 1.7, 0.35]

    // MARK: - sim の時刻（Kit_H027.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 持ち上げている時間（flipHold）・背後へ飛ぶ時間（flipFlight）・着地点（術者の中心から背後、flipLandingGap）。
    private static let flipHold: Float = 0.4
    private static let flipFlight: Float = 0.2
    private static let flipLanding: Float = 1.44
    /// スキル2: 突進の所要の目安（画面収録の 3.4〜3.7m を毎秒 15.2m ≈ 0.22〜0.24 秒。最長 450 / 1520 ≈ 0.30 秒）。
    private static let strikeTime: Float = 0.24
    /// パッシブ: 三連突きの間隔（4 tick ≈ 0.133 秒。MLBB の画面収録の 4 コマおきと同じ）。
    private static let flurryGap: Float = 0.135
    /// アルティメット: 強化の秒数。
    private static let ultDuration: Float = 7.5

    // MARK: - 見た目の寸法（MLBB の画面収録から。sim の値ではない）

    /// スキル1: 投げる前の対象の距離（画面収録 2.07〜2.23m）。三日月の弦は前方のこの点から背後 flipLanding まで。
    private static let flipFront: Float = 2.1
    /// スキル2: 対象へ伸びる光の槍の長さ（画面収録の 1 コマ目 f130 で術者から対象の手前まで ≈ 3.4m。推定）。
    private static let lanceLength: Float = 3.4
    /// パッシブの解放: 1 本ごとの突きの向きの差（度。画面収録 f484 / f488 / f492 で突きの向きが少しずつ変わる。推定）。
    private static let flurryFan: Float = 12

    // MARK: - 部品

    /// 頭上を越える縦の三日月（三日月を立てる: pitch −90 で弧の膨らみを真上へ、roll で弦の向きを決める）。前方やや左から
    /// 頭上を越えて背後やや右へ。弦を前後の軸から 40° ずらし、真上から見下ろすカメラの視線と弧の面が重ならない（細い線にならない）ようにする。
    /// MLBB（f471〜f477）: 現れて 0.03 秒で最も太く、0.15 秒で細り、0.2 秒で細い線だけが残る。
    private static func flipArc(_ r: Float, _ tint: FXTint, life: Float, tex: FXTex = .slash, alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [r * 1.7, 1, r * 1.7], sizeEnd: [r * 2.0, 1, r * 2.0],
               ease: .out, life: life, fadeIn: 0.15, fadeOut: 0.45, pitch: -90, roll: 50)
    }

    /// 三日月の中心（弦の中点: 前方 flipFront と背後 flipLanding の間。弧の両端が持ち上げた対象の高さに来るよう少し上げる）。
    private static var arcCenter: SIMD3<Float> { [0, 0.55, (flipFront - flipLanding) * 0.5] }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        switch slot {
        case .passive: return chargeRecipe(s)
        case .skill1: return flipRecipe(s)
        case .skill2: return strikeRecipe(s)
        case .ultimate: return warriorRecipe(s)
        }
    }

    // MARK: - パッシブ 竜の三連突き

    /// 竜気が 1 つたまるたび: 穂先の小さな水色の閃き（頻繁に出るので小さく短く）。
    private static func chargeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        r.cast = [
            .emit(.flare(0.55, .primary, life: 0.12, tex: .flare4), .follow, offset: spearTip),
            .emit(.motes(4, radius: 0.12, .primary, life: 0.35, size: 0.07), .follow, offset: spearTip),
        ]
        // パッシブのダメージは通常攻撃（Effekseer）。既定の被弾演出で補われないよう小さな合図だけ置く
        r.hit = [.mesh(.halo(0.3, .primary, life: 0.2, spin: 200, tex: .ring), .follow, offset: [0, 0.2, 0])]
        return r
    }

    /// スキル2 の踏み込みからそのまま三連突き（竜気を使い切った）: 前方へ 3 本の白水色の長い突き（対象を貫いて奥まで）と命中の閃き。
    /// MLBB（f484 / f488 / f492）: 白い芯に水色の縁の細長い光の帯が、穂先から対象を貫いて 1.5m ほど先まで伸び、1 本ごとに向きが変わる。
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? {
        let g = flurryGap
        let fan = flurryFan
        return [
            .mesh(.ray(.streak, length: 3.2, width: 0.5, .primary, life: 0.14).glowing()
                .flowing(.streaks, scroll: [-3, 0], tiling: 1.5, strength: 0.5, erosion: 0.3, edge: .core)
                .with { $0.yaw = 90 - fan }, .follow, offset: [-0.1, 1.05, 2.0])
                .repeated(3, every: g, yaw: fan),
            .mesh(.ray(.streak, length: 2.6, width: 0.18, .core, life: 0.11).glowing().with { $0.yaw = 90 - fan }, .follow,
                  offset: [-0.1, 1.07, 2.1])
                .repeated(3, every: g, yaw: fan),
            .emit(.sheet(.hitFlash, 1.3, .core, end: .primary, life: 0.18), .follow, offset: [0, 1.05, 1.9])
                .repeated(3, every: g),
            // 槍を振る腕の後ろへ流れる水色の羽根（槍の鰭の残像）
            .emit(FXEmit(tex: .feather, tint: .primary, tintEnd: .secondary, count: 8, emit: 2 * g, life: 0.28, size: 0.3,
                         sizeVar: 0.4, grow: 0.6, shape: .box([0.3, 0.2, 1.2]), dir: .backward, speed: 1.2, spread: 20,
                         angleVar: 40, fade: .gradualFadeInOut), .follow, offset: [0.1, 1.05, 0.9]),
            .emit(.sparks(10, speed: 7, .core, end: .primary).with { $0.dir = .forward; $0.spread = 25 }, at: 2 * g, .follow,
                  offset: [0, 1.05, 2.2]),
        ]
    }

    // MARK: - スキル1 跳槍撃

    /// 掬い上げ（0 秒）→ 持ち上げ（0〜0.4 秒）→ 対象が頭上を越えて背後へ（0.4〜0.6 秒）→ 着地（0.6 秒）。打ち上げは 1.0 秒まで。
    private static func flipRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let hold = flipHold
        let flight = flipFlight
        let land = hold + flight
        // 0 秒: 低く構えた槍で対象の足元を掬う（水色の低い弧・光る）と、穂先の閃き・蹴った土煙（MLBB f459〜f460）
        r.cast = [
            .mesh(.slash(1.7, .primary, from: -70, to: 5, life: 0.2, tex: .slashThin).glowing(), offset: [0.1, 0.35, 0.2]),
            .emit(.flare(0.8, .core, life: 0.1, tex: .flare4), offset: [0.25, 0.4, 1.0]),
            .emit(.sheet(.smokePuff, 0.9, dust, count: 2, life: 0.55, additive: false, radius: 0.3), offset: [0.2, 0.2, 0.9],
                  quality: 1),
        ]
        // 0.4 秒（放り投げ）: 術者の位置（前方 = 対象）から頭上を越える水色の大きな縦の三日月（MLBB f471〜f477）。
        // 外の水色（光る。筋の模様が弧に沿って流れ、縁から欠ける）+ 芯の白 + 0.6 秒まで残る細い線
        r.impact = [
            .mesh(flipArc(2.1, .primary, life: 0.22).glowing()
                .flowing(.streaks, scroll: [2.4, 0], tiling: 1.5, strength: 0.55, erosion: 0.35, edge: glowCyan),
                  at: hold, offset: arcCenter),
            .mesh(flipArc(2.0, .core, life: 0.15, tex: .slashThin).glowing(), at: hold + 0.02, offset: arcCenter),
            .mesh(flipArc(2.05, glowCyan, life: 0.3, tex: .slashThin, alpha: 0.7).glowing(), at: hold + 0.06, offset: arcCenter),
        ]
        // 被弾（打ち上げ 1.0 秒）: 被弾者に追従
        r.hit = [
            // 0 秒: 命中の白い閃き・上へ跳ねる水色の火花・足元の灰色の土煙（f459）
            .emit(.sheet(.hitFlash, 1.6, .core, end: .primary, life: 0.2), offset: [0, 1.0, 0]),
            .emit(.sparks(12, speed: 6, .core, end: .primary, gravity: 8).with { $0.dir = .up; $0.spread = 30 },
                  offset: [0, 0.5, 0]),
            .emit(.sheet(.smokePuff, 1.0, dust, count: 2, life: 0.6, additive: false, radius: 0.3), offset: [0, 0.25, 0],
                  quality: 1),
            // 0〜0.4 秒（持ち上げ）: 被弾者の腰の下に穂先の水色の光ときらめき（f462〜f470）
            .mesh(.sprite(.glow, 1.3, glowCyan, life: hold, grow: 1.1, alpha: 0.75).glowing().with {
                $0.fadeIn = 0.15; $0.fadeOut = 0.7
            }, .follow, offset: [0, 0.6, 0]),
            .emit(.flare(0.9, glowCyan, life: 0.3, tex: .flare4), at: 0.04, .follow, offset: [0, 0.55, 0]),
            .emit(FXEmit(tex: .twinkle, tint: .primary, tintEnd: .core, rate: 16, duration: hold, life: 0.35, size: 0.1,
                         sizeVar: 0.4, grow: 0.4, shape: .sphere(0.35), dir: .up, speed: 1.2, fade: .gradualFadeInOut),
                  .follow, offset: [0, 0.8, 0], quality: 1),
            // 0.4〜0.6 秒（飛ぶ間）: 被弾者に追従する白水色の光の尾（三日月の軌跡に沿う）
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: .primary, rate: 70, duration: flight, life: 0.25, size: 0.18,
                         sizeVar: 0.3, grow: 0.4, shape: .sphere(0.3), dir: .up, speed: 1.0, stretch: 1.6,
                         fade: .linearFadeOut), at: hold, .follow, offset: [0, 1.0, 0]),
            // 0.6 秒（着地。追従しているので実際の着地点）: 灰色の土煙と淡い水色の輪（MLBB に地割れは無い）
            .emit(.sheet(.smokePuff, 1.2, dust, count: 3, life: 0.7, additive: false, radius: 0.4), at: land, .follow,
                  offset: [0, 0.3, 0], quality: 1),
            .mesh(.shockRing(0.9, .primary, life: 0.28, tex: .ring).glowing(), at: land, .follow),
            .shake(0.15, at: land),
        ]
        return r
    }

    // MARK: - スキル2 竜牙突き

    /// 対象へ踏み込み（≈ 0.2 秒）、到着の瞬間に突き通す（被弾の時刻 = 実際に当たった時刻）。
    /// 突進の間だけの部品は durationFromCast（発動のイベントの長さ = 実際の突進の秒数。0 なら書いた strikeTime）。
    private static func strikeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let t = strikeTime
        let L = lanceLength
        r.cast = [
            // 蹴り出しの灰色の土煙（MLBB f349〜f353）
            .emit(.sheet(.smokePuff, 1.1, dust, count: 2, life: 0.65, additive: false, radius: 0.25), offset: [0, 0.25, -0.1],
                  quality: 1),
            // 前に構えた槍の白水色の光（術者と一緒に走る）
            .mesh(.ray(.streak, length: 1.9, width: 0.55, glowCyan, life: t).glowing().with {
                $0.fadeOut = 0.7; $0.durationFromCast = true
            }, .follow, offset: [0.1, 1.05, 1.2]),
            // 背に流れる青緑の羽根の尾（f131〜f134）・白い光の筋・深紅の房の帯（アルファ合成）
            .emit(.trail(.feather, .secondary, rate: 70, life: 0.32, size: 0.42).with {
                $0.duration = t; $0.durationFromCast = true; $0.tintEnd = .primary; $0.dir = .backward; $0.speed = 1.6
                $0.stretch = 1.2; $0.grow = 0.6; $0.angleVar = 25; $0.shape = .sphere(0.25); $0.fade = .gradualFadeInOut
            }, .follow, offset: [0, 1.0, -0.25]),
            .emit(.trail(.streak, .core, rate: 60, life: 0.22, size: 0.22).with {
                $0.duration = t; $0.durationFromCast = true; $0.stretch = 3; $0.dir = .backward; $0.speed = 3
                $0.tintEnd = .primary
            }, .follow, offset: [0, 1.1, 0]),
            .emit(.trail(.streak, .accent, rate: 36, life: 0.3, size: 0.16).with {
                $0.duration = t; $0.durationFromCast = true; $0.stretch = 4; $0.dir = .backward; $0.speed = 1.5
                $0.tintEnd = .accent; $0.additive = false
            }, .follow, offset: [-0.2, 1.25, -0.35]),
        ]
        // 発動時に対象の位置（前方 = 術者 → 対象）: 術者から対象へ伸びる光の槍（穂先 = 対象。f130 で最も明るく、f134 で消える）。
        // 水色の外層（光る。筋の模様が対象へ流れる）+ 白い芯 + 穂先の白い閃き
        r.impact = [
            .mesh(.ray(.streak, length: L, width: 1.0, .primary, life: 0.2).glowing()
                .flowing(.streaks, scroll: [-3, 0], tiling: 1.5, strength: 0.6, erosion: 0.3, edge: .core),
                  offset: [0, 1.0, -L * 0.5]),
            .mesh(.ray(.streak, length: L * 0.75, width: 0.38, .core, life: 0.16).glowing(), offset: [0, 1.02, -L * 0.4]),
            .emit(.flare(1.2, .core, life: 0.14, tex: .flare4), offset: [0, 1.0, -0.35]),
        ]
        // 到着の瞬間（被弾）: 白い閃き（青い光条。f136 / f356）→ 青い縁の弾け・突き通す白い光・前へ散る火花。
        // 物理防御ダウン（2 秒）の印は MLBB の画面にも出ない（HUD の状態の表示に任せる）
        r.hit = [
            .emit(.sheet(.hitFlash, 2.0, .core, end: hitBlue, life: 0.22), offset: [0, 1.0, 0]),
            .emit(.sheet(.energyBurst, 1.7, .primary, end: hitBlue, life: 0.3), at: 0.02, offset: [0, 1.0, 0]),
            .mesh(.ray(.streak, length: 2.4, width: 0.42, .core, life: 0.14).glowing(), offset: [0, 1.0, 0.5]),
            .emit(.sparks(12, speed: 7, .core, end: .primary).with { $0.dir = .forward; $0.spread = 35 }, offset: [0, 1.0, 0.2]),
            .shake(0.16),
        ]
        return r
    }

    // MARK: - アルティメット 至高の武人

    /// 風の渦が身を包む（0〜0.3 秒）→ 青緑の光（0.12 秒）→ 水色の泡（0.2〜0.7 秒）→ 7.5 秒の強化の間、体から立ちのぼる水色の筋。
    private static func warriorRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let d = ultDuration
        // 強化の間（発動のイベントの長さ = 7.5 秒。0 なら書いた ultDuration）追従: 体から立ちのぼる水色の細い筋と淡い炎（f600〜f740）
        r.cast = [
            .emit(FXEmit(tex: .streak, tint: aura, tintEnd: .core, rate: 18, duration: d, life: 0.5, size: 0.14, sizeVar: 0.4,
                         grow: 0.6, shape: .disc(0.42), dir: .up, speed: 1.9, speedVar: 0.35, stretch: 2.6,
                         fade: .gradualFadeInOut).with { $0.durationFromCast = true }, .follow, offset: [0, 0.35, 0]),
            .emit(FXEmit(tex: .flame, tint: .primary, tintEnd: aura, rate: 10, duration: d, life: 0.55, size: 0.5, sizeVar: 0.35,
                         grow: 0.7, shape: .ring(0.3), surface: true, dir: .up, speed: 0.9, orient: .upright,
                         fade: .gradualFadeInOut).with { $0.durationFromCast = true }, .follow, offset: [0, 0.5, 0],
                  quality: 1),
        ]
        // 発動と同時（MLBB f526〜f541）
        r.impact = [
            // 0 秒: 白い風の筋が渦を巻いて身を包む（コマ送りの渦巻く筋 + 白い竜巻。光る・縁から欠ける）
            .emit(.sheet(.darkWisp, 3.4, wind, end: lime, life: 0.3), offset: [0, 1.0, 0]),
            .mesh(.tornado(1.5, height: 2.4, wind, life: 0.3, spin: 720).glowing()
                .flowing(.noise, scroll: [1.5, -1.2], tiling: 2, strength: 0.6, erosion: 0.5, edge: .core), offset: [0, 0.05, 0]),
            .emit(.flare(1.6, wind, life: 0.18, tex: .flare6), at: 0.02, offset: [0, 1.3, 0]),
            // 0.04 秒: 黄緑の渦（逆回り）
            .emit(.sheet(.darkWisp, 2.9, lime, end: teal, life: 0.3), at: 0.04, offset: [0, 0.9, 0]),
            .mesh(.tornado(1.25, height: 2.0, lime, life: 0.28, spin: -900).glowing()
                .flowing(.streaks, scroll: [-1.8, -1.0], tiling: 2, strength: 0.6, erosion: 0.45, edge: wind), at: 0.04,
                  offset: [0, 0.05, 0]),
            .emit(.vortex(14, radius: 1.1, teal, life: 0.55, speed: 2.5), at: 0.05, quality: 1),
            // 0.12 秒: 胸の高さに青緑の光が膨らむ
            .mesh(.sprite(.glow, 2.6, teal, life: 0.3, grow: 1.35, alpha: 0.85).glowing(), at: 0.12, offset: [0, 1.0, 0]),
            // 0.2〜0.7 秒: 水色の半透明の泡（縁が明るいドーム）と、縁の明るい地面の円が広がって薄れる・水色のきらめき
            .mesh(.dome(1.9, .primary, life: 0.5, tex: .beam, alpha: 0.4).glowing(), at: 0.2),
            .mesh(FXMesh(shape: .disc, tex: .shockwave, tint: .primary, alpha: 0.75, size: [2.9, 1, 2.9],
                         sizeEnd: [3.9, 1, 3.9], ease: .out, life: 0.5, fadeIn: 0.1, fadeOut: 0.45).glowing(), at: 0.2),
            .emit(.motes(14, radius: 1.3, .primary, life: 0.8, size: 0.09), at: 0.18, offset: [0, 0.8, 0], quality: 1),
            .shake(0.25, at: 0.05),
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
            // 低く構え、槍を下から頭上へ掬い上げ（〜0.17 秒）、敵を頭上に掲げたまま持ち上げ（〜0.4 秒）、胸を反らして頭上を越えて
            // 背後へ振り抜き放り投げる（0.4〜0.55 秒。sim の flipHold / flipFlight）。全体 0.67 秒 + 戻り 0.25 秒
            m.brace(0.05, depth: 0.15)
            m.uppercut(0.12)
            m.hold(0.23) { $0.glow = 1.6 }
            m.key(0.15, .snap) { p in
                p.armR = ArmPose(pitch: 3.3, out: 0.2, yaw: 0, elbow: 0.15)
                p.weaponR = 1.0
                p.torsoPitch = -0.4
                p.headPitch = -0.35
                p.glow = 1.8
            }
            m.settle(0.12)
        case .skill2:
            // 前傾で駆け（毎秒 15.2m ≈ 0.22〜0.24 秒）、着く瞬間に踏み込みざまに槍を突き通す。全体 0.43 秒 + 戻り 0.25 秒
            m.dash(0.1, lean: 0.6)
            m.lunge(0.08, distance: 0.6, lean: 0.35)
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
