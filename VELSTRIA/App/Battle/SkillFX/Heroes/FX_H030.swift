import Foundation
import VelstriaCore

// スキル演出: H030 星砲のライナ（Ranger / 自分の背丈ほどの星の砲・白と金の宇宙服風の戦闘服。MLBB の Layla の Velstria 版）。
// 主題: 星の砲。白い芯 × 桃（主）× 白桃（副）× 金（差し色）、星爆弾だけ虚空の紫。円い光の床ではなく、
// 「衝撃の輪をまとって飛ぶ砲弾」「稲光をまとう光球の破裂」「射程いっぱいを貫く極太の光の円柱」で形を見せる。
// sim の実際の挙動（Systems/Kits/Kit_H030.swift の RainaTuning）に合わせたタイミング:
//   パッシブ 遠星の照準    — 距離補正（バッジを持たないので試合中は合図が出ない。目視確認の実演用）: 足元に照準の陣、頭上に星
//   スキル1 遠星弾         — 発動の tick に砲弾が出る（速度 16 m/s・射程 6.5m = 約 0.4 秒）。砲口の閃光と前を向く衝撃の輪、
//                            砲弾は白い芯に桃の彗星の尾をひき、通った後ろに衝撃の輪が次々と広がる（travel）。
//                            命中・射程の端で砕け（impact）、命中した敵には閃光、術者の足元に金の輪（命中で加速・射程延長）
//   スキル2 星爆弾         — 光球（15 m/s）が紫の殻と回る輪・稲光をまとって飛び（travel）、最初の敵か射程の端で破裂（impact、半径 1.9m）:
//                            紫の球が膨らんで弾け、地を這う 5 本の稲光・虚空の陣・星屑。爆発を受けた敵の足元に刻印の陣と減速の輪（hit）。
//                            刻印の弾け（刻印した敵に通常攻撃・S1・奥義が当たる。遅れ 0 のゾーン）は telegraph（頭上の刻印が砕けて
//                            縦の稲光が落ちる = 0.25 秒のスタン）と同じ破裂（impact）が同時に出る
//   アルティメット 星砕の大砲 — 0〜0.2 秒（ultWindup）: 腰を落として砲を据え、砲口へ光が吸い込まれ、前を向く照準の陣が回る。
//                            0.2 秒: 射程いっぱい（20m）の極太のビーム。光の円柱を砲口から前へ・終点から後ろへ 2 本重ねて全長を均一に、
//                            芯に白い光条、地に焼け跡。ビームの先頭（70 m/s の貫通弾）に閃光と光の尾（travel）、最初の命中か終点で星の破裂、
//                            貫かれた敵ごとに光条と星（hit）
// SkillFXDirector は duration / count を読まない: 時刻は at（遅れ）で表す。

enum FX_H030: HeroFXSet {
    // 造形（白と金の砲・水色の動力球）と MLBB の Layla の既定スキンに合わせ、水色のエネルギーを主色、虚空の紫を副色、金を差し色にする。
    static let palette = FXPalette(core: RGB(0.96, 0.99, 1.0), primary: RGB(0.36, 0.82, 1.0),
                                   secondary: RGB(0.68, 0.5, 1.0), accent: RGB(1.0, 0.84, 0.36),
                                   dark: RGB(0.03, 0.04, 0.16))

    /// 虚空の紫（星爆弾の光球と刻印）。
    private static let voidTint = FXTint.rgb(0.64, 0.38, 1.0)
    /// 硝煙（明るい桃灰色のアルファ合成）。
    private static let powder = FXTint.rgb(0.92, 0.82, 0.88)

    // MARK: - sim の時刻・寸法（Kit_H030.RainaTuning と同じ値。sim を変えたらここも合わせる）

    /// 星爆弾の爆発と刻印の弾けの半径（スキル定義の radius 190）。
    private static let blast: Float = 1.9
    /// 奥義の溜め（ultWindup）。
    private static let windup: Float = 0.2

    /// 星の砲の砲口（局所座標）。
    private static let muzzle: SIMD3<Float> = [0.2, 1.2, 0.9]

    // MARK: - 部品

    /// 砲口から前を向いて広がる衝撃の輪（進行方向を向いて立つ輪）。
    private static func muzzleRing(_ size: Float, _ tint: FXTint, life: Float = 0.26, grow: Float = 2.4,
                                   tex: FXTex = .ring) -> FXEmit {
        FXEmit(tex: tex, tint: tint, count: 1, life: life, lifeVar: 0, size: size, sizeVar: 0, grow: grow,
               orient: .facing, fade: .easeFadeOut)
    }

    /// 寝かせた光の円柱（ビーム）。原点から前へ length m 伸びる（back なら後ろへ）。
    /// 画像（beam）は根元が明るく先へ薄れ、上から見ると中心線が明るく縁へ薄れる。
    private static func beamTube(length: Float, radius r0: Float, to r1: Float, _ tint: FXTint, life: Float,
                                 alpha: Float, back: Bool = false) -> FXMesh {
        FXMesh(shape: .cylinder, tex: .beam, tint: tint, alpha: alpha, size: [r0, length, r0], sizeEnd: [r1, length, r1],
               ease: .out, life: life, fadeIn: 0.03, fadeOut: 0.45, pitch: back ? -90 : 90)
    }

    /// 縦の稲光の粒（カメラを向く板を 90° 回して、稲妻の模様を上下にする）。
    private static func boltFlash(_ size: Float, _ tint: FXTint, life: Float = 0.18) -> FXEmit {
        FXEmit(tex: .bolt, tint: tint, tintEnd: voidTint, count: 1, life: life, lifeVar: 0, size: size, sizeVar: 0,
               grow: 1.0, angle: 90, angleVar: 8, fade: .linearFadeOut)
    }

    // MARK: - レシピ

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        switch slot {
        case .passive:
            var r = SkillFXRecipe()
            r.cast = [
                .mesh(.decal(.techCircle, 1.6, .accent, life: 0.6, spin: 160, alpha: 0.7), .follow),
                .mesh(.sprite(.star, 0.45, .accent, life: 0.5, grow: 1.4, alpha: 0.95), .follow, offset: [0, 2.2, 0]),
                .emit(.flare(0.9, .core, life: 0.16, tex: .flare4), .follow, offset: muzzle),
                .emit(muzzleRing(0.4, .primary, life: 0.3, grow: 2.0, tex: .ringDouble), .follow, offset: muzzle),
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

    /// 衝撃の輪をまとって飛ぶ砲弾（発動の tick に出る）。
    private static func maleficBomb() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let ahead = muzzle + SIMD3<Float>(0, 0, 1.3)
        r.cast = [
            .emit(.flare(1.9, .core, life: 0.16, tex: .flare6), offset: muzzle),
            .emit(muzzleRing(0.5, .secondary, life: 0.24, grow: 2.6), offset: muzzle + SIMD3<Float>(0, 0, 0.2)),
            .mesh(.ray(.streak, length: 2.6, width: 0.7, .accent, life: 0.16, alpha: 0.9), offset: ahead),
            .emit(.sparks(10, speed: 7, .core, end: .accent, size: 0.09, life: 0.25, gravity: 3).with {
                $0.dir = .forward
                $0.spread = 28
            }, offset: muzzle),
            .emit(.smoke(5, radius: 0.15, powder, life: 0.6, size: 0.45).with {
                $0.dir = .forward
                $0.speed = 2
            }, offset: muzzle, quality: 1),
        ]
        // 砲弾: 白い芯の光弾に桃の彗星の尾。通った後ろに前を向く衝撃の輪が次々と広がる
        r.travel = [
            .mesh(.orb(0.2, .core, life: 0.45, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.8 }, .follow,
                  offset: [0, 1.15, 0]),
            .mesh(FXMesh.ray(.streak, length: 1.8, width: 0.75, .primary, life: 0.45).with {
                $0.size = [1.8, 1, 0.75]
                $0.fadeOut = 0.8
            }, .follow, offset: [0, 1.15, -0.6]),
            .emit(FXEmit(tex: .ring, tint: .secondary, tintEnd: .primary, rate: 22, life: 0.22, lifeVar: 0, size: 0.45,
                         sizeVar: 0, grow: 2.4, orient: .facing, fade: .easeFadeOut), .follow, offset: [0, 1.15, 0]),
            .emit(.trail(.glow, .primary, rate: 60, life: 0.22, size: 0.45), .follow, offset: [0, 1.15, 0]),
            .emit(.trail(.star, .accent, rate: 16, life: 0.4, size: 0.16).with {
                $0.spin = 240
                $0.speed = 0.5
            }, .follow, offset: [0, 1.15, 0], quality: 1),
        ]
        // 命中・射程の端: 砲弾が砕けて、前へ星屑と破片が抜ける
        r.impact = [
            .emit(.flare(1.6, .core, life: 0.18, tex: .flare6), offset: [0, 1.1, 0]),
            .mesh(.sprite(.star, 0.9, .accent, life: 0.28, grow: 1.7), offset: [0, 1.2, 0]),
            .mesh(.shockRing(0.9, .secondary, life: 0.28, tex: .ring)),
            .emit(.fan(14, .primary, speed: 8, spread: 40, life: 0.28), offset: [0, 1.1, 0]),
            .emit(.flutter(.shard, 8, radius: 0.2, .secondary, speed: 5, life: 0.45, size: 0.13), offset: [0, 1.1, 0]),
        ]
        // 命中した敵（1 体）: 閃光と押される向きの火花。命中で術者が加速し射程が伸びる = 術者の足元（along(0)）に金の輪
        r.hit = [
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.1, 0]),
            .emit(.sparks(8, speed: 6, .core, end: .primary).with {
                $0.dir = .forward
                $0.spread = 30
            }, offset: [0, 1.0, 0]),
            .mesh(.halo(0.7, .accent, life: 0.6, spin: 300, tex: .ringDouble), .along(0), offset: [0, 0.15, 0]),
        ]
        return r
    }

    // MARK: - スキル2 星爆弾

    /// 紫の殻と稲光をまとう光球 → 最初の敵か射程の端で破裂（半径 1.9m）。刻印の弾けは telegraph + 同じ破裂。
    private static func voidProjectile() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let E = blast
        let orbAt: SIMD3<Float> = [0, 1.15, 0]
        r.cast = [
            .emit(.flare(1.5, .core, life: 0.16, tex: .flare6), offset: muzzle),
            .emit(muzzleRing(0.6, voidTint, life: 0.28, grow: 2.2, tex: .ringDouble), offset: muzzle + SIMD3<Float>(0, 0, 0.2)),
            .emit(.sparks(8, speed: 6, .secondary, end: .primary, size: 0.09, life: 0.25, gravity: 2).with {
                $0.dir = .forward
                $0.spread = 30
            }, offset: muzzle),
        ]
        r.travel = [
            .mesh(.orb(0.2, .core, life: 0.6, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow, offset: orbAt),
            .mesh(.orb(0.42, voidTint, life: 0.6, grow: 1.0, alpha: 0.5).with { $0.fadeOut = 0.85 }, .follow, offset: orbAt),
            .mesh(.halo(0.5, .primary, life: 0.6, spin: 420, tex: .ringDouble).with {
                $0.size = [0.5, 1, 0.5]
                $0.fadeOut = 0.85
            }, .follow, offset: orbAt),
            .emit(.trail(.bolt, .secondary, rate: 30, life: 0.12, size: 0.7).with {
                $0.angleVar = 180
                $0.tintEnd = voidTint
            }, .follow, offset: orbAt),
            .emit(.trail(.glow, voidTint, rate: 55, life: 0.3, size: 0.6), .follow, offset: orbAt),
        ]
        // 破裂（光球の命中・射程の端・刻印の弾け）: 紫の球が膨らんで弾け、地を這う 5 本の稲光・虚空の陣・星屑
        r.impact = [
            .emit(.flare(2.3, .core, life: 0.2, tex: .flare6), offset: [0, 0.9, 0]),
            .mesh(.orb(0.5, voidTint, life: 0.32, grow: 3.0, alpha: 0.55), offset: [0, 0.8, 0]),
            .mesh(.orb(0.3, .core, life: 0.16, grow: 2.2, alpha: 0.8), offset: [0, 0.9, 0]),
            .mesh(.shockRing(E, .primary, life: 0.35, tex: .ring)),
            .mesh(FXMesh.ray(.bolt, length: E, width: 0.7, .secondary, life: 0.24), at: 0.02, offset: [0, 0.15, 0])
                .ringed(5, radius: E * 0.5),
            .mesh(.decal(.runeCircle, E * 1.6, voidTint, life: 0.7, spin: -120, alpha: 0.6), at: 0.02),
            .emit(.sparks(16, speed: 8, .core, end: .primary), offset: [0, 0.9, 0]),
            .emit(.flutter(.star, 10, radius: 0.5, .accent, speed: 3.5, life: 0.8, size: 0.15), at: 0.03,
                  offset: [0, 0.8, 0]),
            .shake(0.15),
        ]
        // 刻印の弾け（遅れ 0 のゾーン。破裂と同時）: 頭上の刻印が砕け、縦の稲光が落ちる（0.25 秒のスタン）
        r.telegraph = [
            .mesh(.sprite(.ringDouble, 0.8, voidTint, life: 0.3, grow: 2.0), offset: [0, 2.1, 0]),
            .emit(.flare(1.4, .accent, life: 0.16, tex: .flare4), offset: [0, 2.1, 0]),
            .emit(boltFlash(2.2, .core), offset: [0, 1.1, 0]),
            .emit(.flutter(.shard, 8, radius: 0.3, voidTint, speed: 4, life: 0.5, size: 0.14), offset: [0, 2.0, 0]),
        ]
        // 破裂・弾けを受けた敵: 足元に虚空の刻印の陣（刻印 3 秒の付与）と減速の輪
        r.hit = [
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.1, 0]),
            .mesh(.decal(.runeCircle, 1.3, voidTint, life: 1.0, spin: 140, alpha: 0.75), .follow),
            .mesh(.halo(0.5, .secondary, life: 1.0, spin: -200, tex: .ring), .follow, offset: [0, 0.15, 0]),
        ]
        return r
    }

    // MARK: - アルティメット 星砕の大砲

    /// 0.2 秒溜めて、射程いっぱい（20m）を貫く極太のビーム。
    private static func destructionRush(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = s.range
        let W = s.radius
        let t = windup
        let y = muzzle.y
        // ビームの軸（砲口の高さ・右へのずれ）。終点・線上に置く層もこの軸にそろえる
        let axis: SIMD3<Float> = [muzzle.x, y, 0]
        let coreAxis: SIMD3<Float> = [muzzle.x, y + 0.05, 0]
        let sigil = muzzle + SIMD3<Float>(0, 0, 0.35)
        r.cast = [
            // 0〜0.2: 砲を据えて溜める（砲口へ光が吸い込まれ、前を向く照準の陣が回り、足元に金の陣）
            .emit(.gather(24, radius: 1.3, .primary, life: t), offset: muzzle),
            .emit(FXEmit(tex: .techCircle, tint: .accent, count: 1, life: t + 0.12, lifeVar: 0, size: 1.3, sizeVar: 0,
                         grow: 1.4, orient: .facing, spin: 260, fade: .easeFadeOut), offset: sigil),
            .mesh(.decal(.techCircle, 2.6, .accent, life: t + 0.5, spin: 140, alpha: 0.75)),
            // 0.2: 発射。白い閃光・前を向く衝撃の輪・砲口から前へ流れる火花
            .emit(.flare(3.2, .core, life: 0.26, tex: .flare6), at: t, offset: muzzle),
            .emit(muzzleRing(1.0, .secondary, life: 0.3, grow: 2.6), at: t, offset: sigil),
            .emit(.fan(26, .secondary, speed: 14, spread: 12, life: 0.35), at: t, offset: muzzle),
            // 射程いっぱいの極太のビーム: 光の円柱を砲口から前へ・終点から後ろへ 2 本重ねて全長の明るさをそろえ、芯に白い光条
            .mesh(beamTube(length: L, radius: W * 0.3, to: W * 0.85, .primary, life: 0.6, alpha: 0.9), at: t,
                  offset: muzzle),
            .mesh(beamTube(length: L, radius: W * 0.3, to: W * 0.75, .secondary, life: 0.55, alpha: 0.7, back: true), at: t,
                  .target, offset: axis),
            .mesh(.ray(.streak, length: L * 0.55, width: W * 0.7, .core, life: 0.4), at: t, .along(0.28), offset: coreAxis),
            .mesh(.ray(.streak, length: L * 0.55, width: W * 0.7, .core, life: 0.4), at: t + 0.02, .along(0.72),
                  offset: coreAxis),
            // 地の焼け跡（暗い帯）と、ビームに沿って舞い上がる光
            .mesh(.ray(.streak, length: L * 0.55, width: W * 1.5, .dark, life: 1.0, alpha: 0.45), at: t + 0.03,
                  .along(0.28)),
            .mesh(.ray(.streak, length: L * 0.55, width: W * 1.5, .dark, life: 1.0, alpha: 0.45), at: t + 0.05,
                  .along(0.72)),
            .emit(.lineBurst(L * 0.5, count: 30, .primary, life: 0.5, size: 0.3), at: t + 0.03, .along(0.5),
                  offset: [0, 0.4, 0]),
            .emit(.smoke(8, radius: 0.4, powder, life: 0.9, size: 0.8).with {
                $0.dir = .backward
                $0.speed = 2.5
            }, at: t, offset: [0, 0.6, 0], quality: 1),
            .shake(0.45, at: t),
        ]
        // ビームの先頭（70 m/s の貫通弾。前方 = 撃った向き）: 白い閃光と、後ろへ引く光の尾・星
        r.travel = [
            .mesh(.sprite(.flare6, 2.0, .core, life: 0.32, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.8 }, .follow,
                  offset: axis),
            .emit(.trail(.streak, .secondary, rate: 140, life: 0.22, size: 0.6).with {
                $0.dir = .backward
                $0.speed = 6
                $0.stretch = 3
                $0.shape = .sphere(0.5)
            }, .follow, offset: axis),
            .emit(.trail(.star, .accent, rate: 40, life: 0.5, size: 0.3).with {
                $0.spin = 200
                $0.dir = .up
                $0.speed = 0.8
            }, .follow, offset: axis, quality: 1),
        ]
        // 最初に貫いた敵（誰にも当たらなければ射程の端）: 星の破裂
        r.impact = [
            .emit(.flare(2.6, .core, life: 0.24, tex: .flare6), offset: [0, 1.1, 0]),
            .mesh(.sprite(.star, 1.6, .accent, life: 0.4, grow: 1.5), offset: [0, 1.3, 0]),
            .mesh(.shockRing(1.6, .secondary, life: 0.4, tex: .ring)),
            .emit(.fan(18, .primary, speed: 11, spread: 45, life: 0.35), offset: [0, 1.1, 0]),
            .emit(.flutter(.star, 12, radius: 0.6, .accent, speed: 4, life: 1.0, size: 0.18), at: 0.04,
                  offset: [0, 1.0, 0], quality: 1),
            .shake(0.3),
        ]
        // 貫かれた敵ごと: 体を抜ける光条と星
        r.hit = [
            .emit(.flare(1.3, .core, life: 0.16), offset: [0, 1.1, 0]),
            .mesh(.ray(.streak, length: 2.8, width: 1.0, .core, life: 0.2), offset: [0, 1.15, 0]),
            .mesh(.sprite(.star, 0.9, .accent, life: 0.28, grow: 1.5), offset: [0, 1.3, 0]),
            .emit(.fan(10, .primary, speed: 8, spread: 25), offset: [0, 1.0, 0]),
        ]
        return r
    }

    // MARK: - 詠唱モーション

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 砲を構えて撃ち（砲弾は発動と同時）、反動で上体が跳ねる
            m.aim(0.05)
            m.recoil(0.05, power: 0.6)
            m.hold(0.12) { $0.glow = 1.4 }
        case .skill2:
            // 光球を撃ち出し、重い反動を受け止める
            m.aim(0.05, up: 0.04)
            m.recoil(0.06, power: 0.85)
            m.settle(0.12)
        case .ultimate:
            // 腰を落として砲を据え（0.2 秒の溜め）、撃った反動で上体が大きく跳ねて半歩下がり、ビームが消えるまで構え続ける
            m.brace(0.06, depth: 0.2)
            m.aim(0.08)
            m.hold(0.06) { $0.glow = 2.6; $0.ring = 1.2 }
            m.recoil(0.06, power: 1.2)
            m.hold(0.24) { $0.glow = 2.2 }
            m.settle(0.16)
        }
    }
}
