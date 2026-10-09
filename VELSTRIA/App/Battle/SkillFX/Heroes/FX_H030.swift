import Foundation
import VelstriaCore

// スキル演出: H030 星砲のライナ（Ranger / 自分の背丈ほどの星の砲・白と金の宇宙服風の戦闘服）。
// 主題: 星の砲弾と星砕の大ビーム。白い芯 × 桃（主）× 白桃（副）× 金（差し色）。弾は星をまとって飛び、命中で星屑が弾ける。
// 月の矢（H025）の細い筋とは逆に、太く重い砲弾と、画面を貫く一本の極太のビームで見せる。
//   パッシブ 遠星の照準      — 遠くの敵ほど痛い。頭上に照準の星が灯り、足元に星の陣が巡る
//   スキル1 遠星弾           — 砲口に大きな閃光が一つ咲き、前へ走る光の筋とともに砲弾が一直線に飛ぶ。命中で星屑が弾ける（命中で射程が伸び、加速する）
//   スキル2 星爆弾           — 星環弾（桃の光球）が飛び、最初の敵の位置（何にも当たらなければ射程の端）で大きく爆ぜて刻印を残す。
//                              着弾の演出は弾が消えた位置で再生される（sim の射程の端の爆発と同じ場所）。刻印へ当てると同じ爆発が再び弾けて短くスタン
//   アルティメット 星砕の大砲 — 星を背に 0.2 秒溜めて砲を構え、星砕の大ビームが一直線に貫く（弾は一瞬で届く）。命中で大きな星の紋が咲く

enum FX_H030: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.97, 0.96), primary: RGB(1.0, 0.45, 0.72),
                                   secondary: RGB(1.0, 0.82, 0.92), accent: RGB(1.0, 0.82, 0.3),
                                   dark: RGB(0.16, 0.03, 0.1))

    /// 星の砲の砲口（局所座標）。
    private static let muzzle: SIMD3<Float> = [0.2, 1.2, 0.9]

    /// 星屑（星形の粒が弾けて漂う）。
    private static func starburst(_ n: Int, radius: Float, speed: Float = 3, life: Float = 0.8) -> FXEmit {
        FXEmit.flutter(.star, n, radius: radius, .accent, speed: speed, life: life, size: 0.16).with {
            $0.tintEnd = .secondary; $0.gravity = -0.3
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.sprite(.star, 0.6, .accent, life: 0.6, grow: 1.3, alpha: 0.95), .follow, offset: [0, 2.3, 0]),
                .emit(.flare(0.9, .core, life: 0.18, tex: .flare4), .follow, offset: [0, 2.3, 0]),
                .mesh(.halo(0.9, .primary, life: 0.8, spin: 200, tex: .ringDouble), .follow, offset: [0, 0.3, 0]),
                .mesh(.decal(.star, 2.0, .secondary, life: 0.8, spin: 80, alpha: 0.7), .follow),
                .emit(.rising(12, radius: 0.5, .primary, speed: 1.8, life: 0.8), .follow),
            ]
            r.hit = []
        case .skill1:
            // 砲口に大きな閃光を一つ（0.1 秒）と、前へ走る光の筋。弾の速さ（前方への勢い）を筋で見せる
            r.cast = [
                .emit(.gather(10, radius: 0.5, .primary, life: 0.12), offset: muzzle),
                .emit(.flare(2.2, .core, life: 0.2, tex: .flare6), at: 0.1, offset: muzzle),
                .mesh(.sprite(.star, 0.7, .accent, life: 0.26, grow: 1.9, alpha: 0.9), at: 0.1, offset: muzzle),
                .mesh(.ray(.streak, length: 3.4, width: 0.55, .accent, life: 0.2, alpha: 0.9), at: 0.1, offset: [0, 1.2, 1.9]),
                .emit(.fan(8, .secondary, speed: 10, spread: 14, life: 0.3), at: 0.1, offset: muzzle),
            ]
            r.travel = [
                .mesh(.orb(0.18, .core, life: 1.0, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.15, 0]),
                .mesh(.sprite(.star, 0.55, .primary, life: 1.0, grow: 1.0, alpha: 0.9).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.15, 0]),
                .emit(.trail(.glow, .primary, rate: 70, life: 0.25, size: 0.5), .follow, offset: [0, 1.15, 0]),
                .emit(.trail(.star, .accent, rate: 22, life: 0.45, size: 0.2).with { $0.spin = 240; $0.speed = 0.5 }, .follow,
                      offset: [0, 1.15, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.5, .core, life: 0.18, tex: .flare6), offset: [0, 1.1, 0]),
                .mesh(.sprite(.star, 1.2, .accent, life: 0.3, grow: 1.5), offset: [0, 1.2, 0]),
                .mesh(.decal(.star, R * 2.6, .primary, life: 0.7, spin: 60, alpha: 0.8)),
                .mesh(.shockRing(R * 1.3, .secondary, life: 0.35)),
                .emit(starburst(10, radius: 0.5, speed: 4, life: 0.7), at: 0.02, offset: [0, 1.0, 0]),
                .emit(.sparks(12, speed: 7, .core, end: .primary), offset: [0, 1.0, 0]),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.1, 0]),
                .emit(.sparks(8, speed: 5, .secondary, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            // 星環弾: 砲口の閃光 → 光球が飛ぶ → 最初の敵の位置で爆発（半径 1.9m）。刻印へ当てた炸裂も同じ爆発（telegraph が刻印の閃き）
            let E: Float = 1.9
            r.cast = [
                .emit(.flare(1.4, .core, life: 0.16, tex: .flare6), offset: muzzle),
                .mesh(.ray(.streak, length: 2.4, width: 0.8, .accent, life: 0.2, alpha: 0.9), offset: [0, 1.2, 1.6]),
                .emit(.fan(10, .secondary, speed: 10, spread: 14, life: 0.3), offset: muzzle),
            ]
            r.travel = [
                .mesh(.orb(0.26, .core, life: 1.2, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.15, 0]),
                .mesh(.halo(0.5, .primary, life: 1.2, spin: 260, tex: .ring).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.15, 0]),
                .emit(.trail(.glow, .primary, rate: 60, life: 0.3, size: 0.55), .follow, offset: [0, 1.15, 0]),
                .emit(.trail(.star, .accent, rate: 20, life: 0.5, size: 0.2).with { $0.spin = 200; $0.speed = 0.5 }, .follow,
                      offset: [0, 1.15, 0], quality: 1),
            ]
            r.telegraph = [
                .mesh(.sprite(.star, 0.8, .accent, life: 0.3, grow: 1.6, alpha: 0.95), offset: [0, 1.2, 0]),
                .emit(.flare(1.0, .core, life: 0.14, tex: .flare4), offset: [0, 1.2, 0]),
            ]
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.2, tex: .flare6), offset: [0, 1.0, 0]),
                .mesh(.sprite(.star, 1.5, .accent, life: 0.35, grow: 1.5), offset: [0, 1.2, 0]),
                .mesh(.decal(.star, E * 2.4, .primary, life: 0.9, spin: 90, alpha: 0.85)),
                .mesh(.decal(.ringDouble, E * 2.0, .secondary, life: 0.8, spin: -80, grow: 1.1, alpha: 0.8)),
                .mesh(.shockRing(E * 1.3, .accent, life: 0.4)),
                .mesh(.shockRing(E * 1.9, .primary, life: 0.55), at: 0.05),
                .emit(starburst(12, radius: 0.8, speed: 3, life: 0.9), at: 0.04, offset: [0, 0.8, 0]),
                .emit(.sparks(18, speed: 8, .core, end: .primary), offset: [0, 1.0, 0]),
                .shake(0.2),
            ]
            r.hit = [
                // 刻印の星の輪（追従）
                .mesh(.halo(0.55, .accent, life: 0.9, spin: 140, tex: .ring), .follow, offset: [0, 0.15, 0]),
                .emit(.sparks(8, speed: 5, .secondary, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .ultimate:
            r.cast = [
                .emit(.gather(30, radius: 1.6, .primary, life: 0.2), offset: muzzle),
                // 背後の高い位置に大きな星を掲げる（上方カメラで体を覆わないよう、後ろ・半透明）
                .mesh(.sprite(.star, 1.8, .accent, life: 0.6, grow: 1.15, alpha: 0.7), offset: [0, 2.7, -1.5]),
                .mesh(.decal(.star, 3.4, .primary, life: 0.8, spin: 140, alpha: 0.75)),
                .mesh(.halo(0.9, .secondary, life: 0.6, spin: 200, tex: .ringDouble), offset: [0, 1.0, 0.2]),
                .emit(.flare(2.6, .core, life: 0.25, tex: .flare6), at: 0.2, offset: muzzle),
                .emit(.fan(24, .secondary, speed: 12, spread: 12, life: 0.35), at: 0.2, offset: muzzle),
                // 0.2 秒の溜めの後、砲口から前へ一直線に走る極太のビーム
                .mesh(.ray(.streak, length: 14, width: 1.6, .core, life: 0.5, alpha: 0.95), at: 0.2, offset: [0, 1.2, 7.4]),
                .mesh(.ray(.streak, length: 14, width: 3.2, .primary, life: 0.7, alpha: 0.6), at: 0.2, offset: [0, 1.15, 7.4]),
                .shake(0.35, at: 0.2),
            ]
            r.travel = [
                .mesh(.ray(.streak, length: 5, width: 2.0, .core, life: 1.1, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.1, -1.5]),
                .mesh(.sprite(.star, 1.6, .accent, life: 1.1, grow: 1.0, alpha: 0.85).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.1, 0.2]),
                .emit(.trail(.glow, .primary, rate: 90, life: 0.35, size: 1.1), .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.star, .accent, rate: 22, life: 0.6, size: 0.4).with { $0.spin = 200; $0.dir = .up; $0.speed = 0.6 },
                      .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.streak, .secondary, rate: 80, life: 0.3, size: 0.4).with {
                    $0.shape = .sphere(0.6); $0.stretch = 3; $0.dir = .backward; $0.speed = 4
                }, .follow, offset: [0, 1.1, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(3.0, .core, life: 0.28, tex: .flare6), offset: [0, 1.1, 0]),
                .mesh(.sprite(.star, 2.6, .accent, life: 0.5, grow: 1.4), offset: [0, 1.4, 0]),
                .mesh(.decal(.star, R * 3.2, .primary, life: 1.3, spin: 60, alpha: 0.9)),
                .mesh(.decal(.ringDouble, R * 2.6, .accent, life: 1.1, spin: -90, alpha: 0.85)),
                .mesh(.shockRing(R * 2.4, .core, life: 0.4)),
                .mesh(.shockRing(R * 3.2, .primary, life: 0.65), at: 0.06),
                // 星の紋から六条の光が走る
                .mesh(.ray(.streak, length: 4.4, width: 0.7, .secondary, life: 0.4), at: 0.03, offset: [0, 0.3, 0])
                    .repeated(3, every: 0.02, yaw: 60),
                .emit(.sparks(34, speed: 10, .core, end: .primary, life: 0.45), offset: [0, 1.1, 0]),
                .emit(starburst(20, radius: R, speed: 3, life: 1.2), at: 0.1, offset: [0, 0.6, 0], quality: 1),
                .shake(0.55),
            ]
            r.hit = [
                .emit(.flare(1.4, .core, life: 0.16), offset: [0, 1.1, 0]),
                .mesh(.sprite(.star, 0.9, .accent, life: 0.3, grow: 1.5), offset: [0, 1.3, 0]),
                .emit(.fan(10, .primary, speed: 7, spread: 20), offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 砲を構えて撃ち、軽い反動を受ける
            m.aim(0.08)
            m.recoil(0.05, power: 0.4)
            m.hold(0.1)
        case .skill2:
            // 星環弾を構えて撃ち、反動を受け止める（ブリンクはしない）
            m.aim(0.1, up: 0.05)
            m.recoil(0.06, power: 0.7)
            m.settle(0.12)
        case .ultimate:
            // 腰を落とし大砲を構えて溜め（約 0.2 秒）→ 撃って大きな反動で半歩下がる
            m.brace(0.06, depth: 0.18)
            m.aim(0.1, up: 0.05)
            m.hold(0.06) { $0.glow = 2.4; $0.ring = 1.2 }
            m.recoil(0.06, power: 1.0)
            m.settle(0.22)
        }
    }
}
