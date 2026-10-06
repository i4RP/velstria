import Foundation
import VelstriaCore

// スキル演出: H005 黒雷のヴォス（Support / 黒雷の槍・雷の光輪）。
// 主題: 黒い稲妻。白い雷光の芯 × 紫電（主）× 黒い煙（暗）。走る稲妻と闇の渦で「重く危うい」雷を見せる。
//   パッシブ 雷脈充填      — 味方を癒やすと、その身に紫の稲妻がまとわりつき雷の輪が灯る
//   S1 ヴォス式・一閃       — 黒雷の投槍。稲妻の尾と黒煙を引き、命中で放射状の雷が走る（気絶 = 雷の冠）
//   S2 星環シフト           — 稲妻になって走り、転移先に雷が落ちて周囲を弾き飛ばす（吹き飛ばし）
//   S3 境界制圧             — 地点に雷の陣、黒雷が降りて敵を縫い止める（根止め）。味方には紫の癒やし
//   奥義 黒雷天墜            — 槍を天へ。黒い雷雲から五条の雷が降り、味方を雷の結界が包む

enum FX_H005: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.96, 0.92, 1.0), primary: RGB(0.62, 0.32, 1.0),
                                   secondary: RGB(0.86, 0.74, 1.0), accent: RGB(0.95, 0.96, 1.0),
                                   dark: RGB(0.06, 0.02, 0.1))

    /// 槍の穂先（局所座標）。
    private static let tip: SIMD3<Float> = [0.25, 1.5, 0.9]

    /// 放射状の稲妻（地面に n 本）。
    private static func boltStar(_ n: Int, length: Float, _ tint: FXTint, life: Float = 0.3, at: Float = 0) -> FXCue {
        FXCue.mesh(.ray(.bolt, length: length, width: 0.55, tint, life: life), at: at, offset: [0, 0, length / 2])
            .ringed(n, radius: 0)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(.flare(1.0, .secondary, life: 0.18, tex: .flare6), .follow, offset: [0, 1.2, 0]),
                .emit(.sparks(14, speed: 3, .accent, end: .primary, life: 0.3, gravity: 0).with { $0.shape = .sphere(0.5) },
                      .follow, offset: [0, 1.0, 0]),
                .mesh(.halo(0.75, .primary, life: 0.7, spin: 360, tex: .ringDouble), .follow, offset: [0, 0.2, 0]),
                .mesh(.sprite(.bolt, 1.0, .secondary, life: 0.2, grow: 1.2), .follow, offset: [0, 1.4, 0]),
            ]
            r.hit = []
        case .skill1:
            r.cast = [
                .emit(.sparks(12, speed: 2, .accent, end: .primary, life: 0.2, gravity: 0).with { $0.shape = .sphere(0.3) },
                      offset: tip),
                .emit(.flare(1.2, .core, life: 0.15, tex: .flare6), at: 0.1, offset: tip),
                .mesh(.ray(.bolt, length: 2.5, width: 0.8, .secondary, life: 0.18), at: 0.1, offset: [0, 1.4, 1.6]),
            ]
            r.travel = [
                .emit(.trail(.bolt, .secondary, rate: 40, life: 0.14, size: 0.9).with { $0.angleVar = 180; $0.grow = 1 },
                      .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.glowHard, .primary, rate: 60, life: 0.2, size: 0.45), .follow, offset: [0, 1.1, 0]),
                .emit(.trail(.smoke, .dark, rate: 26, life: 0.5, size: 0.5).with { $0.additive = false; $0.grow = 2 },
                      .follow, offset: [0, 1.0, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.18, tex: .flare6), offset: [0, 1.0, 0]),
                boltStar(5, length: R * 1.4, .secondary),
                .mesh(.decal(.crack, R * 2.0, .primary, life: 0.7, spin: 0, alpha: 0.8)),
                .emit(.sparks(18, speed: 7, .accent, end: .primary), offset: [0, 1.0, 0]),
                .emit(.smoke(5, radius: 0.4, .dark, life: 0.8, size: 0.7), quality: 1),
                .mesh(.halo(0.45, .secondary, life: 0.8, spin: 420, tex: .ringDouble), at: 0.05, offset: [0, 2.0, 0]),
            ]
            r.hit = [
                .mesh(.sprite(.bolt, 1.1, .secondary, life: 0.16, grow: 1.1), offset: [0, 1.2, 0]),
                .emit(.sparks(8, speed: 5, .accent, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            r.cast = [
                .mesh(.pillar(0.25, height: 4, .accent, life: 0.25, alpha: 0.95, tex: .bolt)),
                .emit(.flare(1.4, .secondary, life: 0.16), offset: [0, 1.0, 0]),
                .emit(.smoke(6, radius: 0.4, .dark, life: 0.7, size: 0.6), quality: 1),
                .emit(.sparks(14, speed: 5, .accent, end: .primary)),
            ]
            r.impact = [
                // 天から落ちる雷
                .mesh(.strike(7, .accent, width: 0.3, life: 0.22), offset: [0, 0, 0]),
                .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), offset: [0, 0.8, 0]),
                boltStar(6, length: 2.2, .secondary, at: 0.02),
                .mesh(.shockRing(2.2, .primary, life: 0.4)),
                .emit(.wave(2.4, .secondary, life: 0.4), offset: [0, 0.1, 0]),
                .emit(.smoke(8, radius: 0.8, .dark, life: 0.9, size: 0.8), quality: 1),
                .shake(0.2),
            ]
        case .skill3:
            r.cast = [
                .emit(.flare(1.0, .secondary, life: 0.15), at: 0.12, offset: tip),
                .mesh(.decal(.runeCircle, 1.6, .primary, life: 0.5, spin: 200, alpha: 0.7), at: 0.1),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.1, .primary, life: 0.6, spin: 160, alpha: 0.75)),
                .emit(.smoke(8, radius: R * 0.7, .dark, life: 0.7, size: 0.8), quality: 1),
                .emit(.sparks(16, speed: 1.5, .accent, end: .primary, life: 0.5, gravity: 0).with {
                    $0.shape = .disc(R * 0.8); $0.emit = 0.4
                }),
            ]
            r.impact = [
                .mesh(.strike(7, .accent, width: 0.4, life: 0.25)),
                .emit(.flare(2.0, .core, life: 0.22, tex: .flare6), offset: [0, 0.6, 0]),
                boltStar(6, length: R * 1.1, .secondary),
                .mesh(.decal(.ringDouble, R * 2.2, .primary, life: 1.2, spin: -120, alpha: 0.85)),
                .mesh(.halo(R * 0.85, .secondary, life: 1.1, spin: 260, tex: .chain), at: 0.05, offset: [0, 0.35, 0]),
                .emit(.rising(20, radius: R * 0.8, .secondary, speed: 2, life: 0.9), at: 0.1),
                .shake(0.15),
            ]
        case .ultimate:
            r.cast = [
                .emit(.flare(2.2, .core, life: 0.3, tex: .flare6), at: 0.2, offset: [0, 2.6, 0]),
                .mesh(.decal(.runeCircle, 4.0, .primary, life: 1.2, spin: 90, alpha: 0.85)),
                .emit(.smoke(12, radius: 1.6, .dark, life: 1.3, size: 1.2).with { $0.gravity = -1.5 }, quality: 1),
                .mesh(.strike(8, .accent, width: 0.4, life: 0.25), at: 0.22),
            ]
            r.impact = [
                // 五条の雷
                .mesh(.strike(7.5, .accent, width: 0.35, life: 0.24), at: 0.25)
                    .ringed(5, radius: 3.0, every: 0.07),
                .emit(.flare(1.6, .secondary, life: 0.2), at: 0.25, offset: [0, 0.6, 3]).ringed(5, radius: 0, every: 0.07),
                .mesh(.dome(3.4, .primary, life: 1.3, tex: .hexShield, alpha: 0.45), at: 0.2),
                .mesh(.shockRing(4.0, .secondary, life: 0.6), at: 0.22),
                boltStar(8, length: 3.2, .secondary, life: 0.35, at: 0.24),
                .mesh(.halo(2.2, .primary, life: 1.2, spin: 180, tex: .ringDouble), at: 0.25, offset: [0, 0.3, 0]),
                .emit(.rising(30, radius: 2.5, .secondary, speed: 3, life: 1.0), at: 0.3),
                .emit(.sparks(30, speed: 8, .accent, end: .primary, life: 0.45), at: 0.25, offset: [0, 1.0, 0]),
                .shake(0.55, at: 0.25),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 槍を肩へ引き、投槍のように突き出す
            m.chamber(0.05)
            m.thrust(0.06, reach: 1.3)
            m.hold(0.15) { $0.glow = 1.6 }
        case .skill2:
            // 身を低くして稲妻のように前へ跳ぶ
            m.brace(0.04, depth: 0.12)
            m.dash(0.07, lean: 0.55)
            m.hold(0.08)
            m.settle(0.12)
        case .skill3:
            // 槍を振り上げ、穂先を地へ突き立てる
            m.overhead(0.07)
            m.plant(0.06)
            m.hold(0.16) { $0.ring = 1 }
        case .ultimate:
            // 槍を天へ突き上げ、雷雲を呼ぶ号令
            m.brace(0.06, depth: 0.1)
            m.command(0.16)
            m.hold(0.24) { $0.glow = 2.4; $0.ring = 1.4; $0.wings = 1.3 }
            m.smash(0.08)
            m.hold(0.12)
        }
    }
}
