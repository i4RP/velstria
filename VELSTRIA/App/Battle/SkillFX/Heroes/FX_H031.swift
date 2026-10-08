import Foundation
import VelstriaCore

// スキル演出: H031 氷嵐のオーリア（Arcanist / 氷の杖・氷の冠・周囲に浮く氷の結晶）。
// 主題: 氷の結晶と凍てつく嵐。白い芯 × 氷青（主）× 白青（副）× 淡い紫（差し色）× 深い群青（暗）。
// 地から突き上がる氷柱と、舞い散る結晶、凍りついた陣で「凍結」を見せる（雷のエウリア H026 とは逆に、静かに冷たく広がる）。
// 実機構（Kit_H031 / docs/kits/Aurora.md の対応表）に合わせた段の使い分け:
//   パッシブ 氷の誇り   — cast: 身の周りに氷の結晶が舞う（アルカニストの合図で出る）。telegraph / impact は S1 の雹（小さな氷）の
//                         ゾーンが借りる（雹のゾーンはパッシブの演出 ID を使う）
//   S1 氷塊と雹         — telegraph: 地点に氷が凝る → impact: 氷塊が砕けて氷柱が咲く（鈍足 = 霜の輪）。続く雹 5 発はパッシブの小さな演出
//   S2 霜風             — cast: 扇状に霜風が広がる（impact はこの時と、扇の先の凍った地面の発動で再生されるので小さな霜の炸裂にする）。
//                         telegraph: 凍った地面（持続 1.8 秒）。凍結は氷の枷
//   奥義 氷河           — cast: 氷の道が前へ走る → travel: 道を走る氷 → telegraph: 道を覆う氷河が育ち、1.2 秒後に砕ける
//                         （砕けの演出は telegraph の at: 1.2 に置く。zone の発動で再生される impact は小さな閃き）→ 凍結
// 氷柱（.spire）のプールは高画質で 5 本なので、1 つの合図は 5 本までにする。

enum FX_H031: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.95, 0.99, 1.0), primary: RGB(0.35, 0.75, 1.0),
                                   secondary: RGB(0.78, 0.93, 1.0), accent: RGB(0.7, 0.6, 1.0),
                                   dark: RGB(0.02, 0.08, 0.2))

    /// 杖の先（局所座標）。
    private static let tip: SIMD3<Float> = [0.2, 1.7, 0.8]

    /// 氷河の半径（Kit_H031 の ultGlacierRadius 360 = 3.6m）。
    private static let glacier: Float = 3.6

    /// 地から突き上がる氷柱（結晶の尖塔）。
    private static func spike(_ h: Float, _ tint: FXTint = .secondary, life: Float = 0.9) -> FXMesh {
        FXMesh(shape: .spire, tex: .shard, tint: tint, alpha: 0.85, size: [0.45, 0.1, 0.45], sizeEnd: [0.38, h, 0.38],
               ease: .outBack, life: life, fadeIn: 0.02, fadeOut: 0.6)
    }

    /// 舞い散る氷の結晶。
    private static func frost(_ n: Int, radius: Float, speed: Float = 2.5, life: Float = 0.9) -> FXEmit {
        FXEmit.flutter(.shard, n, radius: radius, .secondary, speed: speed, life: life, size: 0.16).with {
            $0.tintEnd = .accent; $0.gravity = 0.6
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(frost(10, radius: 0.7, speed: 0.8, life: 1.0), .follow, offset: [0, 1.3, 0]),
                .mesh(.halo(0.8, .primary, life: 0.8, spin: 140, tex: .ringDouble), .follow, offset: [0, 0.4, 0]),
                .mesh(.decal(.runeCircle, 2.0, .secondary, life: 0.8, spin: 50, alpha: 0.7), .follow),
                .emit(.flare(0.9, .accent, life: 0.16, tex: .flare4), .follow, offset: [0, 1.7, 0]),
                .emit(.rising(10, radius: 0.5, .secondary, speed: 1.6, life: 0.8, tex: .shard), .follow),
            ]
            // 雹（小さな氷）の予告と着弾
            r.telegraph = [
                .mesh(.decal(.ripple, 1.5, .secondary, life: 0.5, spin: 0, alpha: 0.6)),
            ]
            r.impact = [
                .mesh(spike(0.9, life: 0.6)),
                .mesh(.shockRing(0.9, .secondary, life: 0.25)),
                .emit(.sparks(6, speed: 4, .core, end: .secondary, life: 0.3), offset: [0, 0.3, 0]),
            ]
            r.hit = []
        case .skill1:
            r.cast = [
                .emit(.gather(10, radius: 0.5, .secondary, life: 0.14), offset: tip),
                .emit(.flare(1.2, .core, life: 0.15, tex: .flare6), at: 0.12, offset: tip),
                .mesh(.sprite(.twinkle, 0.7, .secondary, life: 0.22, grow: 1.5, alpha: 0.9), at: 0.12, offset: tip),
            ]
            // 着弾点に氷が凝る（0.5 秒かけて氷塊が落ちる）
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.2, .primary, life: 0.6, spin: 80, alpha: 0.7)),
                .mesh(.decal(.ripple, R * 1.6, .secondary, life: 0.55, spin: -100, alpha: 0.6)),
                .emit(.gather(14, radius: R * 0.7, .secondary, life: 0.45), offset: [0, 3.2, 0]),
                .emit(.rising(8, radius: R * 0.8, .secondary, speed: 1.4, life: 0.6, tex: .shard), at: 0.1),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.18, tex: .flare6), offset: [0, 1.0, 0]),
                .mesh(.decal(.crack, R * 2.6, .secondary, life: 0.9, spin: 0, grow: 1.0, alpha: 0.75)),
                // 氷塊が砕けて氷柱が咲く
                .mesh(spike(1.5), at: 0.02).ringed(4, radius: R * 0.5, every: 0.02),
                .mesh(.shockRing(R * 1.3, .secondary, life: 0.35)),
                .emit(frost(10, radius: 0.6, speed: 4, life: 0.7), at: 0.02, offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 6, .core, end: .accent), offset: [0, 1.0, 0]),
                .shake(0.15),
            ]
            r.hit = [
                // 鈍足の霜の輪
                .mesh(.halo(0.6, .secondary, life: 0.9, spin: 100, tex: .ring), .follow, offset: [0, 0.15, 0]),
                .emit(.sparks(8, speed: 5, .core, end: .secondary), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            // 霜風: 杖から扇状に冷気が広がる（0.3 秒かけて扇の端まで届く）
            r.cast = [
                .emit(.bloom(1.2, .secondary, life: 0.3), offset: tip),
                .emit(.fan(22, .secondary, speed: 15, spread: 30, life: 0.55), at: 0.1, offset: tip),
                .mesh(.slash(6.0, .secondary, from: 30, to: -30, height: 0.9, life: 0.32), at: 0.12, offset: [0, 0.9, 0]),
                .mesh(.slash(4.4, .core, from: 28, to: -28, height: 1.0, life: 0.24), at: 0.16, offset: [0, 1.0, 0]),
                .emit(.wave(5.0, .secondary, life: 0.55), at: 0.14, offset: [0, 0.1, 0.5]),
                .emit(frost(8, radius: 0.6, speed: 3, life: 0.7), at: 0.1, offset: [0, 1.0, 0.6]),
            ]
            // 凍った地面（扇の先。発動から 1.8 秒）。術者の足元にも小さく出る
            r.telegraph = [
                .mesh(.decal(.ripple, 3.6, .secondary, life: 0.9, spin: 0, alpha: 0.65)),
                .mesh(.decal(.crack, 3.8, .primary, life: 1.2, spin: 0, grow: 1.0, alpha: 0.6)),
            ]
            r.impact = [
                .emit(.flare(1.3, .core, life: 0.16), offset: [0, 0.8, 0]),
                .mesh(spike(1.2), at: 0.03).ringed(3, radius: 0.9, every: 0.03),
                .mesh(.shockRing(1.5, .accent, life: 0.35)),
                .emit(frost(8, radius: 0.8, speed: 2.5, life: 0.8), at: 0.02, offset: [0, 0.6, 0]),
                .emit(.sparks(8, speed: 5, .core, end: .secondary), offset: [0, 0.6, 0]),
            ]
            r.hit = [
                // 凍結の氷の枷
                .mesh(.halo(0.5, .accent, life: 1.0, spin: 160, tex: .ringDouble), .follow, offset: [0, 0.25, 0]),
                .emit(.sparks(8, speed: 5, .core, end: .secondary), offset: [0, 1.0, 0]),
            ]
        case .ultimate:
            let G = glacier
            // 氷の道: 杖を掲げて前へ走らせる（長さ 7.7m の霜の筋）
            r.cast = [
                .emit(.gather(24, radius: 1.4, .secondary, life: 0.3), offset: [0, 2.6, 0.2]),
                .emit(.flare(2.2, .core, life: 0.26, tex: .flare6), at: 0.25, offset: [0, 2.7, 0.2]),
                .mesh(.sprite(.twinkle, 1.8, .accent, life: 0.4, grow: 1.2), at: 0.2, offset: [0, 2.7, 0.2]),
                .mesh(.halo(1.0, .primary, life: 1.0, spin: 300, tex: .ringDouble), offset: [0, 2.0, 0]),
                .mesh(.ray(.streak, length: 7.7, width: 1.5, .secondary, life: 0.7, alpha: 0.7), at: 0.2, offset: [0, 0.15, 3.9]),
            ]
            r.travel = [
                .mesh(.ray(.arrow, length: 2.2, width: 1.2, .secondary, life: 0.6, alpha: 0.9).with { $0.fadeOut = 0.8 }, .follow,
                      offset: [0, 0.4, -0.6]),
                .mesh(.sprite(.shard, 0.9, .core, life: 0.6, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.8 }, .follow,
                      offset: [0, 0.6, 0]),
                .emit(.trail(.glow, .primary, rate: 70, life: 0.4, size: 0.8), .follow, offset: [0, 0.4, 0]),
                .emit(.trail(.shard, .secondary, rate: 30, life: 0.7, size: 0.22).with {
                    $0.spin = 180; $0.speed = 0.6; $0.shape = .sphere(0.4)
                }, .follow, offset: [0, 0.4, 0], quality: 1),
            ]
            // 氷河（直径 7.2m）が道を覆って育ち、1.2 秒後に砕ける
            r.telegraph = [
                .mesh(.decal(.runeCircle, G * 2.0, .primary, life: 1.3, spin: 60, grow: 1.1, alpha: 0.75)),
                .mesh(.decal(.ripple, G * 1.7, .secondary, life: 1.1, spin: -90, alpha: 0.6)),
                .mesh(.decal(.crack, G * 1.9, .secondary, life: 1.2, spin: 0, grow: 1.0, alpha: 0.7), at: 0.2),
                // 育つ氷柱（砕ける直前に消える）
                .mesh(spike(2.4, .secondary, life: 0.85), at: 0.3).ringed(5, radius: G * 0.6, every: 0.12),
                .emit(.rising(18, radius: G * 0.8, .secondary, speed: 1.6, life: 0.8, tex: .shard), at: 0.2),
                .emit(.gather(20, radius: G, .accent, life: 0.6), at: 0.6, offset: [0, 0.4, 0]),
                // 砕ける（1.2 秒）
                .emit(.flare(3.2, .core, life: 0.3, tex: .flare6), at: 1.2, offset: [0, 1.0, 0]),
                .mesh(spike(5.0, .core, life: 1.0), at: 1.2),
                .mesh(spike(3.2, .secondary, life: 1.1), at: 1.24).ringed(4, radius: G * 0.7, every: 0.03),
                .mesh(.dome(G * 1.0, .secondary, life: 1.4, tex: .hexShield, alpha: 0.5), at: 1.3),
                .mesh(.shockRing(G * 0.9, .core, life: 0.4), at: 1.2),
                .mesh(.shockRing(G * 1.3, .primary, life: 0.65), at: 1.26),
                .emit(.sparks(30, speed: 10, .core, end: .accent, life: 0.45), at: 1.2, offset: [0, 1.0, 0]),
                .emit(frost(26, radius: G * 0.8, speed: 5, life: 1.2), at: 1.25, offset: [0, 0.8, 0]),
                .emit(.rising(24, radius: G * 0.9, .secondary, speed: 2.4, life: 1.0, tex: .shard), at: 1.35, quality: 1),
                .shake(0.5, at: 1.2),
            ]
            // 道の最初の命中・氷河の発動では小さな閃きだけ（砕けは telegraph の遅れで出す）
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.2, tex: .flare6), offset: [0, 0.8, 0]),
                .emit(frost(8, radius: 0.6, speed: 3, life: 0.6), offset: [0, 0.8, 0]),
            ]
            r.hit = [
                .mesh(.halo(0.5, .accent, life: 1.0, spin: 240, tex: .ringDouble), .follow, offset: [0, 2.0, 0]),
                .emit(.sparks(10, speed: 5, .core, end: .secondary), offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 杖の先へ冷気を寄せ、前へ突き出して氷塊を落とす
            m.gather(0.08)
            m.push(0.06, high: 0.05)
            m.hold(0.12) { $0.glow = 1.8 }
        case .skill2:
            // 杖を横に払って霜風を広げる（身を引き、杖に冷気を纏う）
            m.backstep(0.1, distance: 0.35)
            m.command(0.12)
            m.settle(0.1)
        case .ultimate:
            // 冷気を集め、杖を天へ掲げて氷の道を呼び → 地へ突き立てて走らせる
            m.gather(0.12)
            m.raise(0.16, glow: 2.2)
            m.hold(0.16) { $0.ring = 1.5; $0.glow = 2.4 }
            m.plant(0.08)
            m.hold(0.16)
        }
    }
}
