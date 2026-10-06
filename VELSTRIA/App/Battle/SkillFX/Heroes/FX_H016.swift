import Foundation
import VelstriaCore

// スキル演出: H016 白環のイリス（Arcanist / 環の杖、頭上に白い光輪）。
// 主題: 白い光輪と聖光。白金の芯 × 金（主）× 澄んだ空色（副）。幾重もの輪が回り、天から光が降りる。
//   パッシブ 白環結界       — スキルが敵の英雄に当たると、頭上の光輪が二重に輝いて広がり、光の粒が昇る
//   S1 Iris式・一閃         — 回る光輪を投げる（直線）。命中で輪が弾け、前方へ光の衝撃が押し出す（吹き飛ばし）
//   S2 星環シフト           — 光の柱になって消え、転移先に天から光輪が降りて締まる（根止め）
//   S3 境界制圧             — 杖で天を指し、頭上の魔法陣から聖光の柱が地点を撃つ
//   奥義 白環再生            — 幾重もの光輪が天から降りる 1 秒の祈り。大紋章と八本の光柱が地を清め、光の輪が足を重くする（鈍足）

enum FX_H016: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.99, 0.94), primary: RGB(1.0, 0.8, 0.32),
                                   secondary: RGB(0.55, 0.82, 1.0), accent: RGB(1.0, 0.93, 0.62),
                                   dark: RGB(0.2, 0.16, 0.08))

    /// 杖先（構えた右手の先。局所座標）。
    private static let staffTip: SIMD3<Float> = [0.3, 1.7, 0.5]

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(.flare(1.2, .core, life: 0.2, tex: .flare6), .follow, offset: [0, 2.15, 0]),
                .mesh(.halo(0.55, .primary, life: 0.8, spin: 240, tex: .ringDouble).with {
                    $0.size = [0.3, 1, 0.3]; $0.sizeEnd = [0.75, 1, 0.75]; $0.rise = 0.3
                }, .follow, offset: [0, 2.05, 0]),
                .mesh(.halo(0.9, .secondary, life: 0.7, spin: -180, tex: .ring, alpha: 0.7), .follow, offset: [0, 1.0, 0]),
                .mesh(.decal(.ringDouble, 1.8, .primary, life: 0.7, spin: 90, alpha: 0.7), .follow),
                .emit(.rising(14, radius: 0.6, .accent, speed: 2.2, life: 0.8), .follow),
            ]
            r.hit = []
        case .skill1:
            // 光輪を押し出す（0.12 秒の push に合わせる）
            r.cast = [
                .emit(.gather(10, radius: 0.6, .primary, life: 0.1), offset: staffTip),
                .emit(.flare(1.2, .core, life: 0.16, tex: .flare6), at: 0.11, offset: [0.15, 1.3, 0.8]),
                .mesh(.halo(0.5, .primary, life: 0.25, spin: 600, tex: .ringDouble), at: 0.11, offset: [0, 1.2, 0.8]),
            ]
            r.travel = [
                // 回る光輪（地面と平行の輪が回りながら飛ぶ）
                .emit(.trail(.ringDouble, .primary, rate: 50, life: 0.16, size: 1.0).with {
                    $0.orient = .ground; $0.spin = 720; $0.grow = 1.0; $0.tintEnd = .accent
                }, .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.glowHard, .core, rate: 90, life: 0.1, size: 0.45), .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.twinkle, .accent, rate: 40, life: 0.45, size: 0.12).with {
                    $0.shape = .ring(0.45); $0.speed = 0.6; $0.dir = .up
                }, .follow, offset: [0, 1.1, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.18, tex: .flare6), offset: [0, 1.0, 0]),
                .mesh(.sprite(.ringDouble, 1.6, .primary, life: 0.3, grow: 1.8), offset: [0, 1.1, 0]),
                .mesh(.shockRing(R * 2.0, .primary, life: 0.4, tex: .ringDouble)),
                .mesh(.decal(.runeCircle, R * 2.6, .primary, life: 0.7, spin: 80, alpha: 0.75)),
                // 前方へ押し出す光（吹き飛ばし）
                .mesh(.ray(.streak, length: R * 2.6, width: R * 1.4, .secondary, life: 0.3, alpha: 0.8).with {
                    $0.advance = 4
                }, offset: [0, 0.05, R * 1.0]),
                .emit(.fan(20, .primary, speed: 9, spread: 30, life: 0.35), offset: [0, 0.9, 0]),
                .shake(0.12),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
                .emit(.fan(10, .secondary, speed: 7, spread: 18, life: 0.3), offset: [0, 0.9, 0]),
            ]
        case .skill2:
            // 光の柱になって消える（転移元）→ 転移先に天から光輪が降りて締まる
            r.cast = [
                .emit(.flare(1.4, .core, life: 0.2), offset: [0, 1.0, 0]),
                .mesh(.pillar(0.5, height: 4.5, .core, life: 0.45, alpha: 0.85)),
                .mesh(.pillar(0.9, height: 3.5, .primary, life: 0.6, alpha: 0.5)),
                .emit(.rising(16, radius: 0.5, .accent, speed: 4, life: 0.6)),
                .mesh(.decal(.ringDouble, 1.8, .primary, life: 0.6, spin: 120, alpha: 0.7)),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.2, tex: .flare6), at: 0.05, offset: [0, 1.0, 0]),
                .mesh(.pillar(0.45, height: 4, .core, life: 0.4, alpha: 0.9)),
                // 天から降りて締まる光輪（根止め）
                .mesh(.halo(R, .primary, life: 0.7, spin: 220, tex: .ringDouble).with {
                    $0.size = [R * 1.3, 1, R * 1.3]; $0.sizeEnd = [R * 0.75, 1, R * 0.75]; $0.ease = .in; $0.rise = -3.6
                }, offset: [0, 2.4, 0]),
                .mesh(.halo(R * 0.7, .secondary, life: 0.65, spin: -260, tex: .ring).with {
                    $0.size = [R * 1.0, 1, R * 1.0]; $0.sizeEnd = [R * 0.55, 1, R * 0.55]; $0.ease = .in; $0.rise = -2.4
                }, at: 0.06, offset: [0, 1.7, 0]),
                .mesh(.decal(.runeCircle, R * 2.2, .primary, life: 1.0, spin: -60, alpha: 0.85), at: 0.12),
                .mesh(.shockRing(R * 1.2, .core, life: 0.35), at: 0.14),
                .emit(.wave(R * 1.3, .secondary, life: 0.5), at: 0.14, offset: [0, 0.05, 0]),
                .emit(.motes(12, radius: R * 0.7, .accent, life: 1.0), at: 0.16, offset: [0, 0.6, 0], quality: 1),
                .shake(0.15, at: 0.14),
            ]
            r.hit = [
                .mesh(.halo(0.6, .primary, life: 1.0, spin: 280, tex: .ringDouble).with {
                    $0.size = [1.0, 1, 1.0]; $0.sizeEnd = [0.5, 1, 0.5]
                }, .follow, offset: [0, 0.25, 0]),
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.0, 0]),
            ]
        case .skill3:
            // 杖で天を指し（0.1 秒）、頭上の魔法陣から聖光の柱
            r.cast = [
                .emit(.flare(1.2, .core, life: 0.2, tex: .flare6), at: 0.09, offset: [0.25, 2.3, 0.1]),
                .mesh(.halo(0.6, .primary, life: 0.5, spin: 300, tex: .ringDouble), at: 0.09, offset: [0, 2.4, 0]),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.4, .primary, life: 0.6, spin: 90, grow: 1.0, alpha: 0.75)),
                // 頭上に浮かぶ光の輪（ここから柱が落ちる）
                .mesh(.halo(R * 0.9, .accent, life: 0.65, spin: -180, tex: .ringDouble).with { $0.rise = -1 },
                      offset: [0, 3.2, 0]),
                .emit(.gather(16, radius: R * 1.1, .primary, life: 0.45), offset: [0, 0.4, 0]),
            ]
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.2, tex: .flare6), offset: [0, 1.0, 0]),
                .mesh(.pillar(R * 0.5, height: 7, .core, life: 0.5)),
                .mesh(.pillar(R * 0.9, height: 5.5, .primary, life: 0.7, alpha: 0.6)),
                .mesh(.shockRing(R * 1.6, .primary, life: 0.4, tex: .ringDouble)),
                .mesh(.decal(.runeCircle, R * 2.6, .accent, life: 0.9, spin: -50, alpha: 0.8)),
                .emit(.rising(22, radius: R * 0.8, .accent, speed: 4, life: 0.8), at: 0.04),
                .emit(.sparks(16, speed: 6, .core, end: .primary, gravity: 3), offset: [0, 0.5, 0]),
                .shake(0.15),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.15), offset: [0, 1.0, 0]),
                .mesh(.pillar(0.3, height: 2.5, .primary, life: 0.35, alpha: 0.7)),
            ]
        case .ultimate:
            // 白環再生: 1.0 秒の祈り。幾重もの光輪が天から降り、着いた瞬間に大紋章と八本の光柱
            r.cast = [
                .emit(.flare(1.6, .core, life: 0.25, tex: .flare6), at: 0.1, offset: [0, 2.3, 0]),
                .mesh(.halo(0.9, .primary, life: 1.0, spin: 360, tex: .ringDouble), at: 0.1, offset: [0, 2.2, 0]),
                .mesh(.halo(1.3, .secondary, life: 0.9, spin: -240, tex: .ring, alpha: 0.7), at: 0.14, offset: [0, 2.0, 0]),
                .emit(.rising(18, radius: 0.8, .accent, speed: 3, life: 0.9), at: 0.1),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.4, .primary, life: 1.05, spin: 60, grow: 1.0, alpha: 0.7)),
                .mesh(.decal(.ringDouble, R * 2.1, .secondary, life: 1.05, spin: -90, grow: 1.0, alpha: 0.6)),
                // 降りてくる三重の光輪
                .mesh(.halo(R * 0.95, .primary, life: 1.0, spin: 200, tex: .ringDouble).with {
                    $0.rise = -3.0; $0.ease = .out
                }, offset: [0, 3.4, 0]),
                .mesh(.halo(R * 0.7, .accent, life: 1.0, spin: -260, tex: .ring).with { $0.rise = -2.6 }, at: 0.1,
                      offset: [0, 3.0, 0]),
                .mesh(.halo(R * 0.45, .secondary, life: 0.9, spin: 320, tex: .ringDouble).with { $0.rise = -2.2 },
                      at: 0.2, offset: [0, 2.4, 0]),
                .emit(.gather(28, radius: R * 1.1, .primary, life: 0.9), offset: [0, 0.5, 0]),
                .mesh(.pillar(R * 0.3, height: 8, .core, life: 0.6, alpha: 0.45), at: 0.45),
            ]
            r.impact = [
                .emit(.flare(2.4, .core, life: 0.26, tex: .flare6), offset: [0, 1.2, 0]),
                .emit(.bloom(1.8, .primary, life: 0.45)),
                .mesh(.decal(.runeCircle, R * 2.8, .primary, life: 1.8, spin: 25, grow: 1.05, alpha: 0.95)),
                .mesh(.decal(.ringDouble, R * 2.4, .accent, life: 1.6, spin: -40, grow: 1.05, alpha: 0.8)),
                .mesh(.pillar(R * 0.45, height: 9, .core, life: 0.6)),
                .mesh(.pillar(R * 0.8, height: 6.5, .primary, life: 0.85, alpha: 0.55)),
                .mesh(.pillar(0.22, height: 5, .core, life: 0.6)).ringed(8, radius: R * 0.9, every: 0.03),
                .mesh(.shockRing(R * 1.5, .core, life: 0.4)),
                .mesh(.shockRing(R * 2.0, .primary, life: 0.65, tex: .ringDouble), at: 0.06),
                .emit(.wave(R * 2.1, .secondary, life: 0.7, tex: .ring), at: 0.04, offset: [0, 0.05, 0]),
                .emit(.rising(36, radius: R, .accent, speed: 4.5, life: 1.0), at: 0.05),
                .emit(.sparks(30, speed: 9, .core, end: .primary, gravity: 3), offset: [0, 0.8, 0]),
                .emit(.motes(16, radius: R * 0.9, .secondary, life: 1.4), at: 0.2, offset: [0, 1.0, 0], quality: 1),
                .shake(0.6),
            ]
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.15), offset: [0, 1.0, 0]),
                // 鈍足: 足元に重い光の輪
                .mesh(.halo(0.6, .secondary, life: 1.2, spin: 90, tex: .ringDouble), .follow, offset: [0, 0.15, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 杖を胸元に引き寄せ、光輪を前へ押し出す
            m.gather(0.06)
            m.push(0.06, high: 0.1)
            m.hold(0.14) { $0.glow = 1.4 }
        case .skill2:
            // 現れた先で杖を掲げ、地へ突き立てて輪を落とす
            m.raise(0.08, glow: 2.0)
            m.plant(0.06)
            m.hold(0.16) { $0.ring = 1.3 }
        case .skill3:
            // 杖で天を指し、標的へ振り下ろして指し示す
            m.command(0.09)
            m.hold(0.1) { $0.glow = 1.8 }
            m.push(0.07, high: -0.35)
            m.hold(0.12)
        case .ultimate:
            // 両腕を天へ、宙へ浮き上がって祈り、光を地へ注ぐ
            m.raise(0.1, glow: 2.2)
            m.hold(0.3) { p in
                p.offset.y = 0.3
                p.ring = 1.6
                p.wings = 1.4
                p.headPitch = -0.5
            }
            m.push(0.08, high: 0.5)
            m.key(0.3, .inOut) { p in
                p.offset.y = 0.05
                p.glow = 2.2
                p.ring = 1.4
            }
        }
    }
}
