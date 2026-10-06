import Foundation
import VelstriaCore

// スキル演出: H007 岩脈のガルク（Vanguard / 岩の籠手）。
// 主題: 岩脈を流れる溶岩。溶けた黄白の芯 × 溶岩の橙（主）× 熾火の金（副）× 黒い岩（暗）。
// 光るのは割れ目の溶岩だけ: 岩片・土煙（アルファ）と亀裂の光（加算）の対比で重さを出す。
//   パッシブ 岩心          — 瀕死で全身を岩の殻が覆い、割れ目から溶岩が光る
//   S1 ガルク式・一閃       — 地を殴りつけ、前方へ溶岩の亀裂が扇状に走る（根止め）
//   S2 星環シフト           — 岩塊のように突進、着地点で地面が割れて岩が跳ねる
//   S3 境界制圧             — 踏みつけで周囲の地面が環状に割れ、溶岩が噴く（鈍足）
//   奥義 地脈隆起            — 跳び上がって両拳で叩きつけ、岩の槍が環状に隆起し溶岩柱が噴き上がる（気絶）

enum FX_H007: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.93, 0.7), primary: RGB(1.0, 0.42, 0.08),
                                   secondary: RGB(1.0, 0.68, 0.22), accent: RGB(1.0, 0.85, 0.42),
                                   dark: RGB(0.13, 0.09, 0.07))

    /// 岩の槍（暗い岩の尖塔。溶岩の光と対比させる）。
    private static func spike(_ h: Float, life: Float = 1.0) -> FXMesh {
        FXMesh(shape: .spire, tex: nil, tint: .rgb(0.22, 0.17, 0.14), alpha: 1, size: [0.35, 0.1, 0.35], sizeEnd: [0.45, h, 0.45],
               ease: .outBack, life: life, fadeIn: 0.02, fadeOut: 0.75)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.dome(1.25, .rgb(0.3, 0.22, 0.16), life: 1.1, tex: .crack, alpha: 0.75), .follow),
                .mesh(.dome(1.3, .primary, life: 1.0, tex: .crack, alpha: 0.6).with { $0.spin = -20 }, .follow),
                .emit(.debris(10, speed: 3.5), .follow),
                .emit(.embers(14, radius: 0.7, .secondary, life: 1.0), .follow, quality: 1),
                .emit(.flare(1.4, .accent, life: 0.2), .follow, offset: [0, 1.1, 0]),
            ]
            r.hit = []
        case .skill1:
            r.impact = [
                .emit(.flare(1.4, .accent, life: 0.18), at: 0.1, offset: [0, 0.4, 0.8]),
                .mesh(.decal(.crack, R * 2.2, .primary, life: 1.2, spin: 0, grow: 1.0, alpha: 0.9), at: 0.1,
                      offset: [0, 0, R * 0.5]),
                // 扇状に走る溶岩の亀裂
                .mesh(.ray(.bolt, length: R * 1.1, width: 0.5, .primary, life: 0.9), at: 0.1, offset: [0, 0, R * 0.55]),
                .mesh(.ray(.bolt, length: R, width: 0.45, .secondary, life: 0.85).with { $0.yaw = 90 + 28 }, at: 0.12,
                      offset: [-R * 0.25, 0, R * 0.45]),
                .mesh(.ray(.bolt, length: R, width: 0.45, .secondary, life: 0.85).with { $0.yaw = 90 - 28 }, at: 0.12,
                      offset: [R * 0.25, 0, R * 0.45]),
                .emit(.debris(16, speed: 5.5), at: 0.1, offset: [0, 0, R * 0.5]),
                .emit(.lineBurst(R, count: 18, .primary, life: 0.6, size: 0.3), at: 0.12, offset: [0, 0.1, 0.2]),
                .emit(.smoke(8, radius: R * 0.5, life: 1.0, size: 0.9), at: 0.12, offset: [0, 0, R * 0.5], quality: 1),
                .emit(.embers(12, radius: R * 0.5), at: 0.15, offset: [0, 0, R * 0.5], quality: 1),
                .shake(0.2, at: 0.1),
            ]
            r.hit = [
                .emit(.debris(6, speed: 4)),
                .emit(.sparks(10, speed: 5, .accent, end: .primary), offset: [0, 0.8, 0]),
                .mesh(.halo(0.6, .primary, life: 0.8, spin: 120, tex: .crack), offset: [0, 0.2, 0]),
            ]
        case .skill2:
            r.cast = [
                .emit(.smoke(8, radius: 0.5, life: 0.8, size: 0.8)),
                .emit(.debris(8, speed: 4)),
                .emit(.trail(.smoke, .dark, rate: 40, life: 0.6, size: 0.7).with {
                    $0.duration = 0.35; $0.additive = false; $0.grow = 2
                }, .follow, offset: [0, 0.4, 0], quality: 1),
                .emit(.trail(.glowHard, .primary, rate: 50, life: 0.3, size: 0.4).with { $0.duration = 0.35 }, .follow,
                      offset: [0, 0.9, 0]),
            ]
            r.impact = [
                .emit(.flare(2.0, .accent, life: 0.2), offset: [0, 0.6, 0]),
                .mesh(.decal(.crack, R * 2.6, .primary, life: 1.3, spin: 0, alpha: 0.9)),
                .mesh(.shockRing(R * 1.3, .secondary, life: 0.4)),
                .mesh(spike(1.2, life: 0.9)).ringed(4, radius: R * 0.8, every: 0.03),
                .emit(.debris(20, speed: 7)),
                .emit(.smoke(10, radius: R * 0.6, life: 1.1)),
                .emit(.embers(14, radius: R * 0.7), quality: 1),
                .shake(0.3),
            ]
        case .skill3:
            r.impact = [
                .emit(.flare(1.8, .accent, life: 0.2), at: 0.1, offset: [0, 0.4, 0]),
                .mesh(.decal(.crack, R * 2.4, .primary, life: 1.4, spin: 0, alpha: 0.95), at: 0.1),
                .mesh(.shockRing(R * 1.2, .accent, life: 0.4), at: 0.1),
                .mesh(.burstWall(R, height: 1.4, .primary, life: 0.5), at: 0.1),
                .mesh(.pillar(0.3, height: 2.2, .secondary, life: 0.6)).ringed(6, radius: R * 0.75, every: 0.02),
                .emit(.debris(22, speed: 6.5), at: 0.1, offset: [0, 0, 0]),
                .emit(.smoke(12, radius: R * 0.8, life: 1.2), at: 0.12, quality: 1),
                .emit(.embers(16, radius: R * 0.8), at: 0.15, quality: 1),
                .shake(0.3, at: 0.1),
            ]
        case .ultimate:
            r.cast = [
                .emit(.flare(1.6, .accent, life: 0.2), offset: [0, 1.0, 0]),
                .emit(.debris(14, speed: 6)),
                .emit(.smoke(10, radius: 0.8, life: 1.0)),
                .mesh(.shockRing(2.0, .secondary, life: 0.35)),
            ]
            r.telegraph = [
                .mesh(.decal(.crack, R * 2.2, .primary, life: 0.6, spin: 0, grow: 1.2, alpha: 0.7)),
                .emit(.embers(16, radius: R * 0.9, .primary, life: 0.6)),
                .emit(.gather(18, radius: R, .secondary, life: 0.45), offset: [0, 0.3, 0]),
            ]
            r.impact = [
                .emit(.flare(3.4, .accent, life: 0.3, tex: .flare6), offset: [0, 0.6, 0]),
                .emit(.bloom(R * 1.2, .primary, life: 0.5)),
                .mesh(.decal(.crack, R * 3.2, .primary, life: 2.0, spin: 0, alpha: 1)),
                .mesh(.decal(.runeCircle, R * 2.6, .secondary, life: 1.4, spin: 30, alpha: 0.6)),
                .mesh(.shockRing(R * 1.6, .accent, life: 0.4)),
                .mesh(.shockRing(R * 2.3, .primary, life: 0.7), at: 0.07),
                .mesh(spike(2.4, life: 1.4)).ringed(8, radius: R * 0.85, every: 0.025),
                .mesh(.pillar(0.35, height: 4.5, .primary, life: 0.8)).ringed(4, radius: R * 0.45, every: 0.05),
                .emit(.debris(32, speed: 9, size: 0.18)),
                .emit(.smoke(14, radius: R, life: 1.6, size: 1.3), quality: 1),
                .emit(.embers(24, radius: R, .secondary, life: 1.4), at: 0.1, quality: 1),
                .emit(.sparks(28, speed: 9, .accent, end: .primary, life: 0.5)),
                // 気絶の溶岩の冠
                .mesh(.halo(R * 0.6, .accent, life: 1.0, spin: 200, tex: .ringDouble), at: 0.15, offset: [0, 0.5, 0]),
                .shake(0.8),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 右拳を振りかぶり、地面へ打ち下ろす
            m.windup(0.05, side: 1, power: 1.1)
            m.brace(0.02, depth: 0.18)
            m.smash(0.06)
            m.hold(0.16) { $0.torsoPitch = 0.55 }
        case .skill2:
            // 両拳を前に構えた肩からの体当たり
            m.dash(0.06, lean: 0.5)
            m.push(0.06)
            m.hold(0.12)
            m.settle(0.1)
        case .skill3:
            // 片足を高く上げて踏みつけ、胸を張って吼える
            m.stomp(0.16)
            m.roar(0.1)
            m.hold(0.14)
        case .ultimate:
            // 溜め → 跳躍 → 両拳を振り上げ → 叩きつけ
            m.brace(0.07, depth: 0.2)
            m.leap(0.22, height: 1.4, forward: 0.3)
            m.overhead(0.1)
            m.land(0.08, depth: 0.32)
            m.smash(0.04)
            m.hold(0.24) { $0.glow = 2.2 }
        }
    }
}
