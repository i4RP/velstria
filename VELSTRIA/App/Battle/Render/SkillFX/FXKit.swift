import Foundation

// 担当: battle-renderer（スキル演出）。演出の部品（よく使う粒子・メッシュの組み合わせ）。
// AAA の MOBA の演出の基本の重ね方: 白い芯（core）→ 色の主層（primary）→ 外側の副層（secondary / accent）→
// 余韻（煙・残り火・きらめき）。芯は短く、外側ほど長く残すと「光った」ように見える。
// 各部品は FXEmit / FXMesh を返すので、.with { $0.tint = .accent } で細部を変えられる。

extension FXEmit {
    // MARK: 光

    /// 一瞬の閃光（カメラを向く 1 枚の光）。
    static func flare(_ size: Float, _ tint: FXTint = .core, life: Float = 0.22, tex: FXTex = .flare4) -> FXEmit {
        FXEmit(tex: tex, tint: tint, count: 1, life: life, lifeVar: 0, size: size, sizeVar: 0, grow: 1.6,
               fade: .linearFadeOut)
    }

    /// 柔らかい光の玉（膨らんで消える）。
    static func bloom(_ size: Float, _ tint: FXTint = .primary, life: Float = 0.45, grow: Float = 1.8) -> FXEmit {
        FXEmit(tex: .glow, tint: tint, count: 1, life: life, lifeVar: 0, size: size, sizeVar: 0, grow: grow,
               fade: .easeFadeOut)
    }

    /// 火花（外へ飛び散る光条）。
    static func sparks(_ count: Int, speed: Float = 6, _ tint: FXTint = .core, end: FXTint? = .primary,
                       size: Float = 0.11, life: Float = 0.35, gravity: Float = 6) -> FXEmit {
        FXEmit(tex: .streak, tint: tint, tintEnd: end, count: count, life: life, size: size, sizeVar: 0.4, grow: 0.3,
               shape: .sphere(0.15), speed: speed, speedVar: 0.45, gravity: gravity, drag: 2.2, stretch: 2.2,
               fade: .linearFadeOut)
    }

    /// きらめき（漂う小さな光）。
    static func motes(_ count: Int, radius: Float, _ tint: FXTint = .secondary, life: Float = 0.9,
                      size: Float = 0.09, rise: Float = 1.2) -> FXEmit {
        FXEmit(tex: .twinkle, tint: tint, tintEnd: .core, count: count, emit: 0.15, life: life, size: size, sizeVar: 0.5,
               grow: 0.2, shape: .sphere(radius), dir: .up, speed: rise, speedVar: 0.6, drag: 0.8, spin: 120, spinVar: 180,
               fade: .gradualFadeInOut, noise: 0.4)
    }

    /// 地面から立ちのぼる光の粒（円盤の上から上へ）。
    static func rising(_ count: Int, radius: Float, _ tint: FXTint = .primary, speed: Float = 2.5, life: Float = 0.8,
                       size: Float = 0.1, tex: FXTex = .twinkle) -> FXEmit {
        FXEmit(tex: tex, tint: tint, tintEnd: .core, count: count, emit: 0.2, life: life, size: size, sizeVar: 0.5,
               grow: 0.3, shape: .disc(radius), dir: .up, speed: speed, speedVar: 0.5, drag: 0.6, stretch: 0.8,
               fade: .gradualFadeInOut)
    }

    /// 残り火（ゆっくり舞い上がり乱れる）。
    static func embers(_ count: Int, radius: Float, _ tint: FXTint = .accent, life: Float = 1.2) -> FXEmit {
        FXEmit(tex: .glowHard, tint: tint, tintEnd: .primary, count: count, emit: 0.3, life: life, size: 0.06, sizeVar: 0.5,
               grow: 0.2, shape: .disc(radius), dir: .up, speed: 1.4, speedVar: 0.7, gravity: -0.8, drag: 1.0,
               fade: .gradualFadeInOut, noise: 1.2)
    }

    /// 地面を走る衝撃波（寝かせた 1 枚の輪が広がる）。radius = 最終の半径。
    static func wave(_ radius: Float, _ tint: FXTint = .primary, life: Float = 0.45, tex: FXTex = .shockwave,
                     from: Float = 0.15) -> FXEmit {
        FXEmit(tex: tex, tint: tint, count: 1, life: life, lifeVar: 0, size: radius * 2 * from, sizeVar: 0,
               grow: 1 / max(0.02, from), orient: .ground, fade: .easeFadeOut)
    }

    /// 地面の閃光（寝かせた光だまり）。
    static func groundGlow(_ radius: Float, _ tint: FXTint = .primary, life: Float = 0.5) -> FXEmit {
        FXEmit(tex: .glow, tint: tint, count: 1, life: life, lifeVar: 0, size: radius * 2, sizeVar: 0, grow: 1.2,
               orient: .ground, fade: .easeFadeOut)
    }

    /// 寝かせた 1 枚の模様（魔法陣・亀裂・爪痕など。回転させられる）。
    static func decal(_ tex: FXTex, _ size: Float, _ tint: FXTint = .primary, life: Float = 0.8, spin: Float = 0,
                      grow: Float = 1.1, additive: Bool = true) -> FXEmit {
        FXEmit(tex: tex, tint: tint, count: 1, life: life, lifeVar: 0, size: size, sizeVar: 0, grow: grow,
               orient: .ground, spin: spin, fade: .gradualFadeInOut, additive: additive)
    }

    /// 煙・土煙（アルファ合成の暗い塊）。
    static func smoke(_ count: Int, radius: Float, _ tint: FXTint = .dark, life: Float = 1.1, size: Float = 0.9) -> FXEmit {
        FXEmit(tex: .smoke, tint: tint, count: count, emit: 0.1, life: life, size: size, sizeVar: 0.4, grow: 2.0,
               shape: .disc(radius), dir: .outward, speed: 1.4, speedVar: 0.5, gravity: -0.4, drag: 2.2,
               angleVar: 180, spin: 20, spinVar: 40, fade: .gradualFadeInOut, additive: false)
    }

    /// 岩片・破片（重力で落ちる、アルファ合成）。
    static func debris(_ count: Int, speed: Float = 5, _ tint: FXTint = .dark, size: Float = 0.14,
                       tex: FXTex = .rock) -> FXEmit {
        FXEmit(tex: tex, tint: tint, count: count, life: 0.9, size: size, sizeVar: 0.5, grow: 0.8, shape: .disc(0.4),
               dir: .up, speed: speed, speedVar: 0.5, spread: 55, gravity: 16, drag: 0.4, angleVar: 180, spin: 300,
               spinVar: 300, fade: .linearFadeOut, additive: false)
    }

    /// 形のある粒（花弁・羽根・結晶・葉など）を舞わせる。
    static func flutter(_ tex: FXTex, _ count: Int, radius: Float, _ tint: FXTint = .primary, speed: Float = 2.5,
                        life: Float = 1.1, size: Float = 0.16) -> FXEmit {
        FXEmit(tex: tex, tint: tint, tintEnd: .secondary, count: count, emit: 0.1, life: life, size: size, sizeVar: 0.4,
               grow: 0.6, shape: .sphere(radius), speed: speed, speedVar: 0.5, gravity: 1.2, drag: 1.8, angleVar: 180,
               spin: 200, spinVar: 250, fade: .gradualFadeInOut, noise: 0.8)
    }

    /// 渦を巻いて立ちのぼる（竜巻・吸い込み）。
    static func vortex(_ count: Int, radius: Float, _ tint: FXTint = .primary, life: Float = 0.9, tex: FXTex = .streak,
                       speed: Float = 3) -> FXEmit {
        FXEmit(tex: tex, tint: tint, tintEnd: .core, count: count, emit: 0.3, life: life, size: 0.12, sizeVar: 0.4,
               grow: 0.4, shape: .ring(radius), surface: true, dir: .up, speed: speed, speedVar: 0.4, drag: 0.5,
               stretch: 1.4, fade: .gradualFadeInOut, vortex: 5, attract: 1.5)
    }

    /// 中心へ吸い込まれる光（溜め）。
    static func gather(_ count: Int, radius: Float, _ tint: FXTint = .primary, life: Float = 0.5) -> FXEmit {
        FXEmit(tex: .streak, tint: tint, tintEnd: .core, count: count, emit: life * 0.6, life: life, lifeVar: 0.1,
               size: 0.08, sizeVar: 0.4, grow: 0.3, shape: .sphere(radius), surface: true, dir: .outward, speed: 0,
               stretch: 1.6, fade: .easeFadeIn, attract: 9)
    }

    /// 投射物に付ける軌跡（継続放出）。
    static func trail(_ tex: FXTex = .glow, _ tint: FXTint = .primary, rate: Float = 60, life: Float = 0.3,
                      size: Float = 0.3) -> FXEmit {
        FXEmit(tex: tex, tint: tint, tintEnd: .secondary, rate: rate, life: life, size: size, sizeVar: 0.3, grow: 0.15,
               shape: .sphere(0.08), speed: 0.2, fade: .linearFadeOut)
    }

    /// 前方へ放つ扇状の粒（扇形スキル・ブレス）。
    static func fan(_ count: Int, _ tint: FXTint = .primary, speed: Float = 9, spread: Float = 35, life: Float = 0.4,
                    tex: FXTex = .streak, size: Float = 0.12) -> FXEmit {
        FXEmit(tex: tex, tint: .core, tintEnd: tint, count: count, emit: 0.08, life: life, size: size, sizeVar: 0.4,
               grow: 0.6, shape: .sphere(0.2), dir: .forward, speed: speed, speedVar: 0.35, spread: spread, drag: 1.6,
               stretch: 1.8, fade: .linearFadeOut)
    }

    /// 前方の線に沿って光を並べる（直線の衝撃・光線の残り）。
    static func lineBurst(_ length: Float, count: Int, _ tint: FXTint = .primary, life: Float = 0.5,
                          size: Float = 0.25, tex: FXTex = .glow) -> FXEmit {
        FXEmit(tex: tex, tint: .core, tintEnd: tint, count: count, emit: 0.05, life: life, size: size, sizeVar: 0.4,
               grow: 0.4, shape: .line(length), dir: .up, speed: 1.2, speedVar: 0.6, drag: 1.5, fade: .linearFadeOut)
    }
}

extension FXMesh {
    /// 地面の模様（魔法陣など）。size = 直径。
    static func decal(_ tex: FXTex, _ size: Float, _ tint: FXTint = .primary, life: Float = 0.9, spin: Float = 40,
                      grow: Float = 1.0, alpha: Float = 0.9) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [size * 0.6, 1, size * 0.6],
               sizeEnd: [size * grow, 1, size * grow], ease: .outBack, life: life, fadeIn: 0.12, fadeOut: 0.55, spin: spin)
    }

    /// 地面を走る衝撃波の輪。radius = 最終の半径。
    static func shockRing(_ radius: Float, _ tint: FXTint = .primary, life: Float = 0.45, tex: FXTex = .shockwave,
                          alpha: Float = 0.95) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [radius * 0.3, 1, radius * 0.3],
               sizeEnd: [radius * 2, 1, radius * 2], ease: .out, life: life, fadeIn: 0.02, fadeOut: 0.3)
    }

    /// 光の柱（下から伸びて細りながら消える）。
    static func pillar(_ radius: Float, height: Float, _ tint: FXTint = .primary, life: Float = 0.6,
                       alpha: Float = 0.85, tex: FXTex = .beam) -> FXMesh {
        FXMesh(shape: .cylinder, tex: tex, tint: tint, alpha: alpha, size: [radius, height * 0.2, radius],
               sizeEnd: [radius * 0.35, height, radius * 0.35], ease: .out, life: life, fadeIn: 0.05, fadeOut: 0.4)
    }

    /// 立ちのぼる光の壁の輪（円柱が外へ広がる）。
    static func burstWall(_ radius: Float, height: Float, _ tint: FXTint = .primary, life: Float = 0.5) -> FXMesh {
        FXMesh(shape: .cylinder, tex: .beam, tint: tint, alpha: 0.8, size: [radius * 0.3, height, radius * 0.3],
               sizeEnd: [radius, height * 0.3, radius], ease: .out, life: life, fadeIn: 0.02, fadeOut: 0.25)
    }

    /// 竜巻（上へ広がる漏斗が回る）。
    static func tornado(_ radius: Float, height: Float, _ tint: FXTint = .primary, life: Float = 0.8,
                        spin: Float = 540) -> FXMesh {
        FXMesh(shape: .funnel, tex: .swirl, tint: tint, alpha: 0.75, size: [radius * 0.5, height * 0.4, radius * 0.5],
               sizeEnd: [radius, height, radius], ease: .out, life: life, fadeIn: 0.1, fadeOut: 0.5, spin: spin)
    }

    /// 斬撃の三日月（刃の届く半径 radius の三日月が一瞬で現れ、少し広がりながら消える）。
    /// from / to = 振りの始まりと終わりの向き（度、+ = 左）。三日月はその中間を向き、振りの向きへ少し流れる。
    /// height = 振る高さ、tilt = 刃の傾き（度、+ = 右肩下がり）。
    static func slash(_ radius: Float, _ tint: FXTint = .primary, from: Float = 70, to: Float = -110,
                      height: Float = 1.0, tilt: Float = 0, life: Float = 0.26, tex: FXTex = .slash) -> FXMesh {
        let mid = (from + to) / 2
        let drift = (to - from) * 0.12
        return FXMesh(shape: .disc, tex: tex, tint: tint, alpha: 1, size: [radius * 1.7, 1, radius * 1.7],
                      sizeEnd: [radius * 2.1, 1, radius * 2.1], ease: .out, life: life, fadeIn: 0.04, fadeOut: 0.3,
                      yaw: mid - drift, yawEnd: mid + drift, roll: tilt)
    }

    /// 回転斬りの軌跡（水平の半円の帯が yaw → yawEnd へ掃く）。
    static func sweep(_ radius: Float, _ tint: FXTint = .primary, from: Float = 90, to: Float = -270,
                      life: Float = 0.35, tex: FXTex = .beam) -> FXMesh {
        FXMesh(shape: .arc, tex: tex, tint: tint, alpha: 1, size: [radius, 1, radius], sizeEnd: [radius * 1.1, 1, radius * 1.1],
               ease: .out, life: life, fadeIn: 0.02, fadeOut: 0.4, yaw: from, yawEnd: to)
    }

    /// 結界・盾の半球。
    static func dome(_ radius: Float, _ tint: FXTint = .primary, life: Float = 0.8, tex: FXTex = .hexShield,
                     alpha: Float = 0.55) -> FXMesh {
        FXMesh(shape: .dome, tex: tex, tint: tint, alpha: alpha, size: [radius * 0.7, radius * 0.7, radius * 0.7],
               sizeEnd: [radius, radius, radius], ease: .outBack, life: life, fadeIn: 0.1, fadeOut: 0.6, spin: 30)
    }

    /// 光の球。
    static func orb(_ radius: Float, _ tint: FXTint = .core, life: Float = 0.3, grow: Float = 2.2, alpha: Float = 0.8) -> FXMesh {
        FXMesh(shape: .sphere, tex: nil, tint: tint, alpha: alpha, size: SIMD3(repeating: radius),
               sizeEnd: SIMD3(repeating: radius * grow), ease: .out, life: life, fadeIn: 0.02, fadeOut: 0.2)
    }

    /// 前方へ伸びる帯（光線・稲妻・鎖の線。高さ height に寝かせる）。length は m、width は幅。
    static func ray(_ tex: FXTex, length: Float, width: Float, _ tint: FXTint = .primary, life: Float = 0.35,
                    height: Float = 1.0, alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [width * 0.4, 1, length],
               sizeEnd: [width, 1, length], ease: .out, life: life, fadeIn: 0.03, fadeOut: 0.3)
    }

    /// 前方を向いて立つ板（刃の残像・盾面・門）。
    static func wall(_ tex: FXTex, width: Float, height: Float, _ tint: FXTint = .primary, life: Float = 0.5,
                     alpha: Float = 0.9) -> FXMesh {
        FXMesh(shape: .wall, tex: tex, tint: tint, alpha: alpha, size: [width * 0.7, height * 0.7, 1],
               sizeEnd: [width, height, 1], ease: .outBack, life: life, fadeIn: 0.08, fadeOut: 0.5)
    }

    /// カメラを向く板（大きな閃光・紋章）。
    static func sprite(_ tex: FXTex, _ size: Float, _ tint: FXTint = .core, life: Float = 0.3, grow: Float = 1.5,
                       alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .billboard, tex: tex, tint: tint, alpha: alpha, size: SIMD3(repeating: size),
               sizeEnd: SIMD3(repeating: size * grow), ease: .out, life: life, fadeIn: 0.02, fadeOut: 0.3)
    }

    /// 水平の光の輪の帯（浮かぶ輪・回る光輪）。
    static func halo(_ radius: Float, _ tint: FXTint = .primary, life: Float = 0.8, spin: Float = 180,
                     tex: FXTex = .beam, alpha: Float = 0.9) -> FXMesh {
        FXMesh(shape: .band, tex: tex, tint: tint, alpha: alpha, size: [radius * 0.6, 1, radius * 0.6],
               sizeEnd: [radius, 1, radius], ease: .outBack, life: life, fadeIn: 0.1, fadeOut: 0.55, spin: spin)
    }
}
