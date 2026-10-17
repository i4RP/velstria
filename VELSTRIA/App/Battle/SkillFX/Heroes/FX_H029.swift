import Foundation
import VelstriaCore

// スキル演出: H029 聖槌のボルグ（Support / 巨大な聖槌・円盾・青と金の重装。MLBB の Tigreal の Velstria 版）。
// 主題: 金の聖槌が大地を打つ。白金の芯 × 金（主）× 鋼の青（副）× 温かい白（差し色）× 炎の橙・焦げた暗い朱。
// 上から見下ろすカメラで「前へ 3 回はじける」「突進して押し運ぶ」「振り上げて打ち上げる」「吸い寄せて叩き潰す」が読めるよう、
// 円い輪を主役にせず、前方の爆ぜ・S 字の地割れ・炎の球・渦の刃・四芒星の岩盤で形を見せる。
// sim の実際の挙動（Systems/Kits/Kit_H029.swift の Tune）に合わせたタイミング:
//   パッシブ 聖鎚の誓い       — 誓いが積まれる / 防御が発動する（バッジのタイマー）たびに、左腕の盾に小さな金のきらめき。
//                              スキルの発動の直後（0.6 秒以内）の防御は passiveRelease: 青い六角の盾の殻と金の盾面が弾ける
//   スキル1 聖槌波           — 0.25 秒で槌が地を打ち、前方の台形（奥行き 6.1m）に衝撃波が手前 → 中 → 奥へ 3 回はじける
//                              （0.25 / 0.58 / 0.92 秒 = waveFirstDelay + waveInterval × n、帯の中心は奥行きの 1/4・1/2・3/4）。
//                              回ごとに光の棘の爆ぜ → 黄に光る S 字の地割れ → 橙の溶岩のひび → 焦げた暗いひび、爆炎、火花・残り火・焦げた煙
//   スキル2 聖槌突撃         — 1 回目: 盾を前に突進（5.25m を約 0.67 秒）。体を包む炎の殻と前の金の三日月、背に炎の帯。
//                              突進は impact を再生しない（ゾーンを作らない）ので、終点の演出は cast の .target に 0.67 秒遅れで置く。
//                              再使用（stage 1、4 秒以内）: 0.2 秒（smashDelay）で槌を下から振り上げ（縦の弧の軌跡と三日月）、
//                              前方の扇（2.15m）に光の棘・爆炎・2 重の光の柱・昇る輪 = 打ち上げ（0.6 秒）。段の演出は recipe(_:stage:_:)
//   アルティメット 崩落聖域    — 詠唱 1.0 秒。0 秒: 半径 2.78m の範囲が淡い金に満ち、輪の上の勾玉形の金の刃が渦を巻いて中心へ
//                              吸い込まれる（引き寄せ 0.67 秒）。足元に四芒星、掲げた槌の後ろに金の光輪。
//                              1.0 秒: 槌が落ちて崩落 = 範囲を覆う光の棘と爆炎・白熱の閃光・金に光って盛り上がる四芒星の岩盤 →
//                              溶岩の網が光る焦げた盤・放射状のひび・2 重の衝撃の輪・跳ね上がる白い岩板 + 気絶（発動から 1.8 秒）の星
// 時刻と寸法は MLBB の画面収録で測った値（docs/kits/Tigreal.md「動画で測った値」）。見た目の対応は docs/vfx/H029.md。
// 光る部品（閃光・光の柱・衝撃波・光るひび・爆炎）は加算（glowing）、煙・焦げ跡・岩はアルファ合成。
// 形の主役はメッシュ（Blender の模型・コマ送りのメッシュ。CI の撮影で写る）、火花・残り火・岩片・煙は粒子（実機だけ）。
// SkillFXDirector は duration / count を読まない: 波の回数・段は at（遅れ）と recipe(_:stage:_:) で表す。
// 扇・自身中心のアーキタイプ（S1・S2 の再使用・奥義）は発動と同時に cast と impact を再生する（impact の at が sim の時刻）。

enum FX_H029: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.97, 0.82), primary: RGB(1.0, 0.76, 0.24),
                                   secondary: RGB(0.3, 0.56, 1.0), accent: RGB(1.0, 0.92, 0.72),
                                   dark: RGB(0.12, 0.09, 0.05))

    /// 土煙・土の破片（明るい土色のアルファ合成。草地・石畳・水の上でも見える）。
    private static let dust = FXTint.rgb(0.58, 0.48, 0.34)
    /// MLBB の聖槌の爆発の炎（橙）と、その消え際（暗い朱）。
    private static let flame = FXTint.rgb(1.0, 0.64, 0.22)
    private static let ember = FXTint.rgb(0.45, 0.2, 0.1)
    /// 崩落で飛ぶ白い岩の破片。
    private static let rock = FXTint.rgb(0.86, 0.82, 0.74)
    /// 爆ぜの光の棘・光る地割れの黄（MLBB の爆発の芯 #F8EE6E・地を走る線 #D7D485 の間）。
    private static let hot = FXTint.rgb(1.0, 0.9, 0.42)
    /// 冷えてゆく溶岩のひびの橙（MLBB の 3.3 秒の焦げたひびの縁の光）。
    private static let lava = FXTint.rgb(1.0, 0.42, 0.1)
    /// 焦げた暗いひび・焦げ跡（MLBB の #614832 より暗い朱。アルファ合成）。
    private static let char = FXTint.rgb(0.2, 0.09, 0.05)
    /// 焦げた煙（MLBB の #40322E）。
    private static let soot = FXTint.rgb(0.32, 0.25, 0.22)

    // MARK: - sim の時刻（Kit_H029.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 1 回目の衝撃波の遅れ・間隔・回ごとの帯の中心（奥行きに対する比。帯 = waveBandStart + waveBandLength / 2）。
    private static let waveFirst: Float = 0.25
    private static let waveInterval: Float = 1.0 / 3.0
    private static let waveScale: [Float] = [0.25, 0.5, 0.75]
    /// スキル2: 突進の所要（5.25m / 7.8m/s ≈ 0.67 秒）、再使用の振り上げまでの遅れと扇の奥行き（m）。
    private static let dashTime: Float = 0.67
    private static let smashDelay: Float = 0.2
    private static let smashReach: Float = 2.15
    /// アルティメット: 引き寄せの始まり（発動の瞬間）と崩落（ultTotal）。
    private static let ultPull: Float = 0
    private static let ultSlam: Float = 1.0

    // MARK: - 部品

    /// 地面に寝かせた 1 枚の地割れ・焦げ跡（大きさは変えない。直径 size、向き yaw）。
    private static func crack(_ tex: FXTex, _ size: Float, _ tint: FXTint, life: Float, yaw: Float = 0,
                              alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [size, 1, size], sizeEnd: [size * 1.03, 1, size * 1.03],
               ease: .out, life: life, fadeIn: 0.03, fadeOut: 0.5, yaw: yaw)
    }

    /// 外から内へ縮む衝撃の輪（引き寄せ）。直径 from → to。
    private static func implodeRing(from d0: Float, to d1: Float, _ tint: FXTint, life: Float,
                                    tex: FXTex = .shockwave, spin: Float = 0, alpha: Float = 0.9) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [d0, 1, d0], sizeEnd: [d1, 1, d1], ease: .in,
               life: life, fadeIn: 0.12, fadeOut: 0.8, spin: spin)
    }

    /// 地面の衝撃の輪（外縁の持ち上がった輪の模型が radius まで広がる）。refract = 輪の縁の画面の歪み（実機の後処理だけ）。
    private static func ring(_ radius: Float, _ tint: FXTint, life: Float, from: Float = 0.25, lift: Float = 1.2,
                             refract: Float = 0) -> FXMesh {
        FXMesh.model(.ringLip, nil, tint, size: [radius * from, lift, radius * from], sizeEnd: [radius, lift * 0.6, radius],
                     life: life).with {
            $0.fadeIn = 0.02
            $0.fadeOut = 0.35
            $0.refract = refract
        }.glowing()
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        switch slot {
        case .passive:
            // 誓いが積まれる・防御が発動する: 左腕の盾にきらめき（スキルの発動のたびにも出るので小さく短く）
            r.cast = [
                .emit(.flare(0.9, .core, life: 0.14, tex: .flare4), .follow, offset: [-0.45, 1.1, 0.35]),
                .mesh(.decal(.hexShield, 1.5, .secondary, life: 0.4, spin: 0, grow: 1.15, alpha: 0.5), .follow),
                .emit(.motes(6, radius: 0.3, .primary, life: 0.6), .follow, offset: [-0.4, 1.0, 0.3]),
            ]
            r.hit = []
        case .skill1:
            r = waveRecipe(s)
        case .skill2:
            r = chargeRecipe(s)
        case .ultimate:
            r = implosionRecipe(s)
        }
        return r
    }

    // MARK: - スキル1 聖槌波

    /// 0.25 秒で槌が地を打つ → 台形に 3 回、前へ進みながらはじける（R = 台形の奥行き 6.1m = 射程）。
    /// MLBB の画面収録（docs/vfx/H029.md）: 振り下ろす金の軌跡と地を前へ走るぎざぎざの金の筋 → 回ごとに白金の芯から放射状の
    /// 黄の光の棘（約 3.5m）、黄に光る S 字の太い地割れ（約 2.4m）→ 0.13 秒で橙の雲 → 0.2 秒で暗い朱のひびに橙の縁 → 焦げて消える。
    private static func waveRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.range, 6.5)
        let t0 = waveFirst
        r.cast = [
            // 槌を頭上から前の地面へ振り下ろす金の軌跡（前と上の縦の弧。右手の槌 = やや右）
            .ribbon(.swing(radius: 1.45, from: 130, to: -38, height: 1.0, roll: 90, duration: 0.17, life: 0.16, width: 0.75,
                           .primary), at: t0 - 0.19, offset: [0.32, 0, 0.1]),
            // 槌の頭が地を打つ点: 白金の閃光と小さな衝撃の輪
            .emit(.flare(1.6, .core, life: 0.14, tex: .flare6), at: t0 - 0.02, offset: [0.25, 0.4, 0.95]),
            .mesh(ring(1.1, .accent, life: 0.28, refract: 0.004), at: t0 - 0.02, offset: [0.25, 0, 0.95]),
            // 地を前へ走る金のぎざぎざの筋（衝撃波の通り道。2 本を少し開いて）
            .mesh(FXMesh.ray(.bolt, length: R * 0.5, width: 0.55, hot, life: 0.34).glowing().with { $0.yaw = 90 + 5 }, at: t0 - 0.01,
                  offset: [0.15, 0.02, 0.95 + R * 0.25]),
            .mesh(FXMesh.ray(.bolt, length: R * 0.42, width: 0.45, .primary, life: 0.3).glowing().with { $0.yaw = 90 - 6 },
                  at: t0 + 0.02, offset: [-0.1, 0.02, 0.95 + R * 0.21]),
        ]
        var impact: [FXCue] = []
        for (k, scale) in waveScale.enumerated() {
            let t = t0 + waveInterval * Float(k)
            let pos = SIMD3<Float>(0, 0, R * scale)
            let big = 1 + 0.12 * Float(k)
            let yaw = Float(k) * 41 - 20
            impact += [
                // 白金の芯から放射状に伸びる黄の光の棘（地面に寝かせたコマ送り）
                .mesh(.groundFlipbook(.spikes, 3.4 * big, hot, life: 0.42, grow: 1.08).with { $0.yaw = yaw * 1.7 }, at: t,
                      offset: pos),
                // S 字の地割れ: 黄に光る（〜0.3 秒）→ 橙の溶岩（模様が流れ、溶けて消える）→ 焦げた暗いひび（溶けて消える）
                .mesh(crack(.crackS, 2.5 * big, hot, life: 0.34, yaw: yaw).glowing(), at: t, offset: pos),
                .mesh(crack(.crackS, 2.5 * big, lava, life: 0.95, yaw: yaw).glowing()
                    .flowing(.lava, scroll: [0.04, 0.1], tiling: 1.3, strength: 0.75, edge: hot)
                    .dissolving(from: 0.45, edge: hot, width: 0.08).with { $0.fadeIn = 0.22; $0.fadeOut = 0.9 },
                      at: t + 0.05, offset: pos),
                .mesh(crack(.crackS, 2.55 * big, char, life: 1.5, yaw: yaw, alpha: 0.85)
                    .dissolving(from: 0.55, tiling: 2.5, edge: ember, width: 0.06).with { $0.fadeIn = 0.18; $0.fadeOut = 0.95 },
                      at: t + 0.1, offset: pos),
                // 橙の爆炎（色付きのコマ送り。画像の白 → 黄 → 橙 → 暗い朱）
                .mesh(.flipbook(.fireball, 2.6 * big, .white, life: 0.62, grow: 1.15), at: t + 0.04, offset: pos + [0, 0.85, 0]),
                // 火花（上と外へ）・残り火・焦げた煙
                .emit(.sparks(12, speed: 6 + Float(k) * 2, .core, end: .primary, gravity: 9).with {
                    $0.dir = .up
                    $0.spread = 35
                    $0.shape = .disc(0.9)
                }, at: t, offset: pos + [0, 0.2, 0]),
                .emit(.embers(10, radius: 1.0, flame, life: 1.0), at: t + 0.08, offset: pos, quality: 1),
                .emit(.sheet(.smokeHD, 1.9, soot, count: 2, life: 1.0, additive: false, radius: 0.7).with {
                    $0.speed = 0.6
                    $0.dir = .up
                }, at: t + 0.16, offset: pos + [0, 0.4, 0], quality: 1),
                .shake(0.16 + 0.06 * Float(k), at: t),
            ]
        }
        r.impact = impact
        // 3 回の衝撃波が 1 発ごとに当たる: 小さな火花と、足元の青い鈍足の輪（命中ごとに深まる）
        r.hit = [
            .emit(.sparks(6, speed: 4, .core, end: .primary), offset: [0, 0.9, 0]),
            .mesh(.shockRing(0.55, .secondary, life: 0.3), .follow),
        ]
        r.hitPerHit = true
        return r
    }

    // MARK: - スキル2 聖槌突撃

    /// 1 回目: 盾を前に突進して、通り道の敵を終点まで押し運ぶ。MLBB: 体を包む金〜橙の炎の殻、前で弧を描く金の光、背に炎の尾、
    /// ぶつかった所で白熱の芯の炎の球（半径 1.3〜1.5m）が渦を巻いて弾ける。
    private static func chargeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = min(s.range, 6.0)
        r.cast = [
            // 盾を構えて踏み出す閃き
            .emit(.flare(1.3, .core, life: 0.14), .follow, offset: [-0.3, 1.0, 0.7]),
            // 体を包む金と橙の炎の殻（炎の半球の模型・炎の筋が上へ流れて縁が欠ける）と、盾の前の金の三日月
            .mesh(.model(.burstDome, nil, flame, size: [0.85, 1.0, 0.85], sizeEnd: [1.0, 1.15, 1.0], life: dashTime + 0.06)
                .glowing().flowing(.flame, scroll: [0.2, -1.6], tiling: 1.5, strength: 0.8, erosion: 0.55, edge: .core).with {
                    $0.alpha = 0.75
                    $0.fadeIn = 0.1
                    $0.fadeOut = 0.75
                    $0.spin = 90
                }, .follow, offset: [0, 0.05, 0.15]),
            .mesh(.model(.crescent, .swoosh, .primary, size: [1.25, 1.3, 1.25], life: dashTime).glowing().with {
                $0.pitch = -14
                $0.fadeIn = 0.06
                $0.fadeOut = 0.7
            }, .follow, offset: [0, 0.7, 0.25]),
            // 背に流れる炎の帯（縦の帯。炎の筋が後ろへ流れ、縁が欠ける）
            .ribbon(FXRibbon.trail(width: 1.5, life: 0.32, duration: dashTime, upright: true, flame)
                .flowing(.flame, scroll: [-2.0, 0], tiling: 1.5, strength: 0.7, erosion: 0.45, edge: .core), .follow,
                    offset: [0, 0.85, -0.2]),
            // 背の炎の粒（コマ送り）と金の光条、土煙（突進の間だけ）
            .emit(.trail(.glow, flame, rate: 30, life: 0.36, size: 1.0).with {
                $0.duration = dashTime; $0.sheet = .flameLoop; $0.sheetRandomStart = true; $0.tintEnd = ember
                $0.dir = .backward; $0.speed = 2.5; $0.grow = 0.6
            }, .follow, offset: [0, 0.8, -0.3]),
            .emit(.trail(.streak, .core, rate: 50, life: 0.25, size: 0.2).with {
                $0.duration = dashTime; $0.stretch = 2.4; $0.dir = .backward; $0.speed = 4; $0.tintEnd = .primary
            }, .follow, offset: [0, 1.0, 0]),
            .emit(.trail(.smoke, dust, rate: 18, life: 0.7, size: 0.9).with {
                $0.duration = dashTime + 0.03; $0.additive = false; $0.grow = 1.6; $0.fade = .gradualFadeInOut; $0.tintEnd = nil
                $0.sheet = .smokePuff
            }, .follow, offset: [0, 0.3, 0], quality: 1),
            // 通り道に焼き付く金の筋（光る。前へ流れる）
            .mesh(.ray(.streak, length: L, width: 1.1, .primary, life: 0.45).glowing()
                .flowing(.streaks, scroll: [-2.0, 0], tiling: 2, strength: 0.5, erosion: 0.3, edge: .core),
                  at: 0.02, .along(0.5)),
            // 終点: 押し運んだ敵ごと止まる炎の球（模型が膨らんで渦を巻き、溶けて消える）・爆炎・白熱の閃光・衝撃の輪・破片
            .mesh(.model(.burstDome, nil, flame, size: [0.9, 0.9, 0.9], sizeEnd: [1.8, 1.6, 1.8], life: 0.5).glowing()
                .flowing(.flame, scroll: [0.15, -1.2], tiling: 1.4, strength: 0.85, edge: .core)
                .dissolving(from: 0.35, edge: .core, width: 0.12).with { $0.spin = 160; $0.fadeOut = 0.9 },
                  at: dashTime, .target, offset: [0, 0, 0.3]),
            .mesh(.flipbook(.fireball, 3.0, .white, life: 0.55), at: dashTime + 0.02, .target, offset: [0, 1.0, 0.3]),
            .mesh(.sprite(.glowHard, 2.4, .core, life: 0.16, grow: 1.6).glowing(), at: dashTime, .target, offset: [0, 0.9, 0.3]),
            .mesh(ring(2.4, .accent, life: 0.4, refract: 0.008), at: dashTime, .target, offset: [0, 0, 0.4]),
            .emit(.debris(10, speed: 5, dust), at: dashTime, .target, offset: [0, 0, 0.5]),
            .emit(.sparks(16, speed: 8, .core, end: .primary, life: 0.45), at: dashTime, .target, offset: [0, 0.9, 0.3]),
            .shake(0.22, at: dashTime),
        ]
        // 突進（dashStrike）は impact を再生しない（終点の演出は cast の .target）。目視確認の実演（-skillDemo）だけが
        // impact を出すので、既定演出で補われないよう小さな揺れだけ置く
        r.impact = [.shake(0.1)]
        // 突進に巻き込まれた敵: ぶつかった瞬間の白金の閃光と押される向きへ散る火花、押し運ばれる間の土煙
        r.hit = [
            .emit(.sheet(.hitFlash, 1.8, .core, end: .primary, life: 0.22), offset: [0, 1.0, 0]),
            .emit(.sparks(10, speed: 6, .core, end: .primary).with { $0.dir = .forward; $0.spread = 35 },
                  offset: [0, 1.0, -0.2]),
            .emit(.trail(.smoke, dust, rate: 30, life: 0.5, size: 0.5).with {
                $0.duration = dashTime; $0.additive = false; $0.grow = 1.8; $0.fade = .gradualFadeInOut; $0.tintEnd = nil
            }, .follow, offset: [0, 0.2, 0], quality: 1),
        ]
        return r
    }

    /// 再使用（stage 1）: 0.2 秒で聖槌を下から振り上げ、前方の扇（2.15m）の敵を打ち上げる（0.6 秒）。
    /// MLBB: 下から上へ振り上げる金の弧の軌跡と縦の白金の三日月、打ち上げた敵の所で黄の爆ぜ。突進の尾（共通の cast）は出さない。
    static func recipe(_ slot: SkillSlot, stage: Int, _ s: FXSkillInfo) -> SkillFXRecipe? {
        guard slot == .skill2, stage == 1 else { return nil }
        var r = SkillFXRecipe()
        let t = smashDelay
        let mid: SIMD3<Float> = [0, 0, smashReach * 0.5]
        // 槌を低く構えて金の光を溜め、下から振り上げる（前と上の縦の弧の軌跡。右手の槌）
        r.cast = [
            .emit(.gather(16, radius: 0.9, .primary, life: t), .follow, offset: [0.35, 0.5, 0.6]),
            .emit(.sparks(8, speed: 3, .primary, end: .accent, gravity: 4), at: 0.08, offset: [0.4, 0.15, 0.7]),
            .ribbon(.swing(radius: 1.6, from: -55, to: 105, height: 0.95, roll: 90, duration: 0.16, life: 0.2, width: 0.95,
                           .primary), at: t - 0.07, offset: [0.28, 0, 0.15]),
        ]
        // 扇のアーキタイプなので発動と同時に再生される。振り上げは smashDelay の後
        r.impact = [
            // 縦に振り上げる白金の三日月（三日月の模型を前と上の縦の面に立てる）
            .mesh(.model(.crescent, .swoosh, .core, size: [1.5, 1.5, 1.5], sizeEnd: [1.85, 1.85, 1.85], life: 0.26).glowing()
                .with {
                    $0.roll = 90
                    $0.fadeIn = 0.03
                    $0.fadeOut = 0.35
                }, at: t, offset: [0.1, 0.95, smashReach * 0.3]),
            // 打ち上げの爆ぜ（光の棘・爆炎）と、天へ立つ 2 重の金の光の柱（炎の筋が上へ流れる）
            .mesh(.groundFlipbook(.spikes, 3.0, hot, life: 0.4), at: t, offset: mid),
            .mesh(.flipbook(.fireball, 2.6, .white, life: 0.55), at: t + 0.03, offset: mid + [0, 1.2, 0]),
            .mesh(.model(.pillar2, nil, .primary, size: [0.6, 1.5, 0.6], sizeEnd: [0.38, 5.5, 0.38], life: 0.5).glowing()
                .flowing(.flame, scroll: [0, -2.4], tiling: 1.6, strength: 0.7, erosion: 0.3, edge: .core), at: t, offset: mid),
            // 焦げた放射状のひび（溶けて消える）・足元の衝撃の輪
            .mesh(crack(.crackRadial, 3.0, char, life: 1.1, alpha: 0.8).dissolving(from: 0.5, tiling: 2.5, edge: ember, width: 0.06),
                  at: t, offset: mid),
            .mesh(ring(1.9, .accent, life: 0.35, refract: 0.006), at: t, offset: mid),
            // 打ち上げ: 地面から昇る輪が 3 つ続く（光る）
            .mesh(FXMesh.halo(0.9, .accent, life: 0.6, spin: 200, tex: .ringDouble).with { $0.rise = 3.5 }.glowing(), at: t,
                  offset: [0, 0.2, smashReach * 0.5]).repeated(3, every: 0.08),
            // 扇の幅から上へ噴く火花・昇る光の筋・跳ね上がる土の破片
            .emit(.sparks(22, speed: 10, .core, end: .primary, size: 0.12, life: 0.55, gravity: 7).with {
                $0.dir = .up; $0.spread = 20; $0.shape = .box([2.4, 0.1, 1.8])
            }, at: t, offset: [0, 0.2, smashReach * 0.5]),
            .emit(.rising(18, radius: 1.3, .primary, speed: 6, life: 0.6, size: 0.14, tex: .streak), at: t, offset: mid),
            .emit(.debris(12, speed: 8, dust), at: t, offset: mid),
            .shake(0.3, at: t),
        ]
        // 打ち上げ（0.6 秒）: 被弾者の足元から昇る金の輪と光の粒
        r.hit = [
            .emit(.sheet(.hitFlash, 1.6, .core, end: .primary, life: 0.2), offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 6, .core, end: .primary).with { $0.dir = .up; $0.spread = 30 }, offset: [0, 0.8, 0]),
            .mesh(FXMesh.halo(0.55, .primary, life: 0.6, spin: 300, tex: .ringDouble).with { $0.rise = 2.0 }.glowing(), .follow,
                  offset: [0, 0.3, 0]),
            .emit(.rising(8, radius: 0.4, .accent, speed: 4, life: 0.5), .follow),
        ]
        return r
    }

    // MARK: - アルティメット 崩落聖域

    /// 詠唱 1.0 秒: 発動の瞬間から吸い寄せ（0〜0.67）しながら掲げて集める → 崩落（1.0）。R = 引き寄せ・爆発の半径（2.78m）。
    /// MLBB: 範囲の円が淡い金に満ち、輪の上の勾玉形の白金の刃（約 0.9m）が渦を巻いて中心へ寄り、足元に四芒星、
    /// 掲げた槌の後ろに金の光輪 → 崩落の直前に縦の細い光の筋 → 範囲を覆う白熱の爆ぜ（約 6m）→ 金に光って盛り上がる
    /// 四芒星の岩盤 → 暗い朱の焦げた盤に橙のひび、白い岩板が跳ねて落ちる。
    private static func implosionRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 6.0)
        let p = ultPull, t = ultSlam
        // 掲げた槌の頭（右手・頭上）に金の光が集まり、後ろに金の光輪が立つ（崩落の少し前まで）
        r.cast = [
            .emit(.gather(20, radius: 1.2, .primary, life: t - 0.2), .follow, offset: [0.3, 2.5, 0.1]),
            .emit(.flare(1.8, .core, life: 0.3, tex: .flare6), at: 0.14, .follow, offset: [0.3, 2.7, 0.1]),
            .mesh(.sprite(.ringDouble, 2.2, .primary, life: 0.62, grow: 1.15, alpha: 0.85).glowing().with {
                $0.fadeIn = 0.3
                $0.fadeOut = 0.6
            }, at: 0.3, .follow, offset: [0.1, 2.3, 0]),
        ]
        r.impact = [
            // 0〜: 範囲が淡い金に満ちる（縁ほど明るい輪の画像 + 柔らかい光）。縁は弧に沿って流れる金の筋
            .mesh(.decal(.shockwave, R * 2, .primary, life: t - 0.02, spin: 0, grow: 1.0, alpha: 0.42).glowing().with {
                $0.size = [R * 2, 1, R * 2]
                $0.ease = .linear
                $0.fadeIn = 0.06
                $0.fadeOut = 0.85
            }, at: p),
            .mesh(.decal(.glow, R * 2.3, .accent, life: t - 0.05, spin: 0, grow: 1.0, alpha: 0.2).glowing().with {
                $0.size = [R * 2.3, 1, R * 2.3]
                $0.ease = .linear
                $0.fadeOut = 0.8
            }, at: p),
            .mesh(.halo(R, .primary, life: t - 0.02, spin: -120, tex: .beam, alpha: 1).glowing()
                .flowing(.streaks, scroll: [1.6, 0], tiling: 3, strength: 0.85, erosion: 0.45, edge: .core).with {
                    $0.size = [R, 1, R]
                    $0.sizeEnd = [R * 0.98, 1, R * 0.98]
                }, at: p),
            // 渦の刃: 輪の上の勾玉形の白金の刃が渦を巻きながら中心へ吸い込まれる（2 層。外は大きく遅く、内は速い）
            .mesh(.model(.bladeRing, .blade, .core, size: [R, 1, R], sizeEnd: [R * 0.3, 1, R * 0.3], life: 0.92, ease: .in)
                .glowing().with {
                    $0.spin = -150
                    $0.fadeIn = 0.08
                    $0.fadeOut = 0.8
                }, at: p, offset: [0, 0.05, 0]),
            .mesh(.model(.bladeRing, .blade, .primary, size: [R * 0.82, 1, R * 0.82], sizeEnd: [R * 0.18, 1, R * 0.18], life: 0.85,
                         alpha: 0.85, ease: .in).glowing().with {
                $0.spin = -230
                $0.yaw = 11
                $0.fadeIn = 0.15
                $0.fadeOut = 0.75
            }, at: p + 0.05, offset: [0, 0.06, 0]),
            // 足元の四芒星（白金。ゆっくり回る）
            .mesh(.decal(.star4, 1.9, .core, life: 0.88, spin: 25, grow: 1.05, alpha: 1).glowing().with {
                $0.fadeIn = 0.12
                $0.fadeOut = 0.7
                $0.ease = .out
            }, at: p),
            // 外から内へ縮む衝撃の輪、吸い込まれる光の筋と土煙
            .mesh(implodeRing(from: R * 2, to: 1.2, .primary, life: 0.42).glowing(), at: p),
            .emit(FXEmit(tex: .streak, tint: .primary, tintEnd: .core, count: 48, emit: 0.18, life: 0.42, lifeVar: 0.1,
                         size: 0.14, sizeVar: 0.4, grow: 0.5, shape: .ring(R * 0.9), surface: true, dir: .outward,
                         speed: 0, stretch: 2.4, fade: .easeFadeIn, vortex: 4, attract: 14),
                  at: p, offset: [0, 0.4, 0]),
            .emit(.smoke(10, radius: R * 0.85, dust, life: 0.6, size: 1.0).with {
                $0.shape = .ring(R * 0.85); $0.surface = true; $0.speed = 0; $0.attract = 6
            }, at: p, quality: 1),
            .shake(0.2, at: p),
            // 崩落の直前: 槌の上から天へ立つ細い光の筋（光る。筋が上へ流れる）
            .mesh(.pillar(0.16, height: 9, .core, life: 0.32, alpha: 1).glowing()
                .flowing(.streaks, scroll: [0, -3], tiling: 2, strength: 0.6, edge: .primary), at: t - 0.24,
                  offset: [0.3, 1.2, 0.1]),
            // 1.0: 聖槌が落ちて崩落 — 範囲を覆う光の棘・白熱の閃光・爆炎
            .mesh(.groundFlipbook(.spikes, R * 2.3, hot, life: 0.5, grow: 1.1), at: t),
            .mesh(.sprite(.glowHard, 4.2, .core, life: 0.22, grow: 1.5).glowing(), at: t, offset: [0, 1.0, 0.2]),
            .mesh(.flipbook(.fireball, R * 1.9, .white, life: 0.72, grow: 1.12), at: t + 0.02, offset: [0, 1.2, 0]),
            // 四芒星の岩盤: 金に光って盛り上がる → 暗く焦げた盤に溶岩の網が光り、溶けて消える
            .mesh(.model(.starCross, nil, hot, size: [R * 0.85, 1.6, R * 0.85], sizeEnd: [R * 0.9, 1.0, R * 0.9], life: 0.5,
                         ease: .outBack).glowing().with { $0.fadeOut = 0.35 }, at: t),
            .mesh(.model(.starCross, nil, char, size: [R * 0.86, 1.2, R * 0.86], life: 1.6)
                .flowing(.lava, scroll: [0.03, 0.08], tiling: 2, strength: 0.9, edge: lava)
                .dissolving(from: 0.55, edge: lava, width: 0.08).with { $0.fadeIn = 0.15; $0.fadeOut = 0.95 }, at: t + 0.06),
            // 放射状のひび: 橙に光る → 暗い焦げたひびと焦げ跡（溶けて消える）
            .mesh(crack(.crackRadial, R * 2.1, lava, life: 0.7).glowing()
                .flowing(.lava, scroll: [0.05, 0.1], tiling: 1.5, strength: 0.5, edge: hot), at: t + 0.02),
            .mesh(crack(.crackRadial, R * 2.15, char, life: 1.8, alpha: 0.9)
                .dissolving(from: 0.6, tiling: 2.5, edge: ember, width: 0.05).with { $0.fadeIn = 0.15; $0.fadeOut = 0.95 },
                  at: t + 0.05),
            .mesh(.decal(.scorch, R * 2.1, char, life: 1.8, spin: 0, grow: 1.0, alpha: 0.55)
                .dissolving(from: 0.5, tiling: 2.5, edge: ember, width: 0.05).with {
                    $0.size = [R * 2.1, 1, R * 2.1]
                    $0.ease = .linear
                    $0.fadeOut = 0.95
                }, at: t + 0.05),
            // 2 重の衝撃の輪（白金 → 橙）
            .mesh(ring(R * 1.05, .core, life: 0.35, from: 0.3, lift: 1.4, refract: 0.012), at: t),
            .mesh(ring(R * 1.35, flame, life: 0.55, from: 0.4, refract: 0.008), at: t + 0.06),
            // 白い岩板が跳ね上がって落ちる（岩板の輪の模型が広がりながら放物線を描く）
            .mesh(.model(.shardRing, nil, rock, size: [R * 0.45, 1, R * 0.45], sizeEnd: [R * 1.15, 1, R * 1.15], life: 0.75)
                .with {
                    $0.rise = 4.5
                    $0.gravity = 12
                    $0.spin = 40
                    $0.fadeOut = 0.7
                }, at: t),
            // 天へ立つ 2 重の光の柱（炎の筋が上へ流れる）
            .mesh(.model(.pillar2, nil, .core, size: [0.75, 3, 0.75], sizeEnd: [0.4, 8, 0.4], life: 0.38).glowing()
                .flowing(.flame, scroll: [0, -3], tiling: 1.6, strength: 0.6, erosion: 0.25, edge: .primary), at: t - 0.02),
            // 火花・白い岩片（回る岩のコマ送り）・土煙・残り火
            .emit(.sparks(30, speed: 11, .core, end: .primary, size: 0.12, life: 0.55), at: t, offset: [0, 0.6, 0]),
            .emit(.debris(16, speed: 8, .rgb(0.92, 0.9, 0.85), size: 0.3).with {
                $0.sheet = .rockTumble
                $0.sheetRandomStart = true
                $0.shape = .disc(R * 0.5)
                $0.life = 1.0
                $0.gravity = 14
            }, at: t),
            .emit(.sheet(.smokeHD, 2.6, dust, count: 4, life: 1.3, additive: false, radius: R * 0.6), at: t + 0.08,
                  offset: [0, 0.6, 0], quality: 1),
            .emit(.embers(14, radius: R * 0.8, lava, life: 1.4), at: t + 0.1, quality: 1),
            .shake(0.65, at: t),
        ]
        // 崩落の瞬間の被弾（残りの気絶 0.8 秒。発動から合計 1.8 秒）: 白金の閃光・頭上を回る金の輪と星のきらめき
        r.hit = [
            .emit(.flare(1.2, .core, life: 0.15), offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 4, .primary, end: .accent), offset: [0, 1.0, 0]),
            .mesh(FXMesh.halo(0.5, .primary, life: 0.8, spin: 300, tex: .ringDouble).glowing(), .follow, offset: [0, 2.0, 0]),
            .emit(.flutter(.star, 6, radius: 0.35, .primary, speed: 0.5, life: 1.2, size: 0.16).with {
                $0.gravity = 0; $0.vortex = 5
            }, .follow, offset: [0, 2.0, 0], quality: 1),
        ]
        return r
    }

    // MARK: - パッシブの解放

    /// 誓いを使い切った（防御の発動がスキルの直後）ときの盾の弾け。released は消費した誓いの数（4）。
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? {
        [
            .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), .follow, offset: [-0.4, 1.1, 0.45]),
            .mesh(.dome(1.1, .secondary, life: 0.45, tex: .hexShield, alpha: 0.6), .follow),
            .mesh(.wall(.hexShield, width: 1.3, height: 1.5, .primary, life: 0.35, alpha: 0.8), .follow,
                  offset: [0, 0.2, 0.7]),
            .mesh(.shockRing(1.3, .primary, life: 0.35), .follow),
            .emit(.sparks(14, speed: 5, .core, end: .primary), .follow, offset: [-0.3, 1.1, 0.5]),
        ]
    }

    // MARK: - 詠唱モーション

    /// 再使用の段もスキル2 と同じモーション（モーションは段で分けられない）: 盾で突っ込み、そのまま槌を下から振り上げる。
    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 槌を頭上へ振りかぶり、0.25 秒（1 回目の衝撃波）で地へ叩きつけ、3 回目（0.92 秒）の手前まで押し込んで光らせる
            // （基本スキルのモーションの上限 1.1 秒に収める。戻りの分を含めて 1.09 秒）
            m.overhead(0.18)
            m.smash(0.07)
            m.hold(0.33) { $0.glow = 2.0; $0.torsoPitch = 0.55 }
            m.hold(0.26) { $0.glow = 2.4 }
        case .skill2:
            // 盾を前に前傾で突っ込み（突進 0.67 秒）、槌を下から振り上げる（再使用の打ち上げ 0.2 秒にほぼ合わせる）
            m.dash(0.04, lean: 0.5)
            m.shieldBash(0.06)
            m.uppercut(0.12)
            m.hold(0.1) { $0.glow = 1.8 }
            m.settle(0.1)
        case .ultimate:
            // 足を踏ん張って槌を天へ掲げ（発動の瞬間から引き寄せ）、光を溜めて 1.0 秒で地へ叩き落とす
            m.brace(0.06, depth: 0.08)
            m.raise(0.12, glow: 1.8)
            m.hold(0.12) { $0.ring = 1.2 }
            m.hold(0.62) { $0.glow = 2.6; $0.ring = 1.6; $0.torsoPitch = -0.3 }
            m.smash(0.08)
            m.hold(0.2) { $0.glow = 2.0; $0.hipsDrop = 0.22 }
        }
    }
}
