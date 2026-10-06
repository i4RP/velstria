import Foundation
import VelstriaCore

// 担当: スキル演出。アーキタイプ別の既定演出（ヒーローの定義が空の段を補う・未知のヒーロー用）。
// 個別の演出を書く時の手本にもなるよう、芯 → 主層 → 副層 → 余韻の順に重ねている。

enum FXGeneric {
    static func recipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        let ult = s.slot == .ultimate
        r.hit = [
            .emit(.flare(0.9, .core, life: 0.16), offset: [0, 1.0, 0]),
            .emit(.sparks(10, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
        ]
        switch s.archetype {
        case .passive:
            r.cast = [
                .emit(.bloom(1.6, .primary, life: 0.5), .follow, offset: [0, 1.0, 0]),
                .emit(.rising(16, radius: 0.6, .secondary), .follow),
                .mesh(.halo(0.9, .primary, life: 0.6), .follow, offset: [0, 0.15, 0]),
            ]
        case .cone:
            r.cast = [.emit(.flare(1.4, .core), at: 0.06, offset: [0, 1.1, 0.6])]
            r.impact = [
                .mesh(.slash(R * 0.95, .primary, from: 60, to: -60, height: 1.0), at: 0.05, offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.8, .core, from: 60, to: -60, height: 1.0, life: 0.18), at: 0.05, offset: [0, 1.05, 0]),
                .emit(.fan(26, .primary, speed: R * 4), at: 0.06, offset: [0, 1.0, 0.4]),
                .mesh(.decal(.slash, R * 2, .primary, life: 0.4, spin: 0), at: 0.06),
            ]
        case .lineSkillshot, .piercingLine:
            r.cast = [
                .emit(.flare(1.6, .core), offset: [0, 1.2, 0.7]),
                .emit(.fan(12, .primary, speed: 7, spread: 20), offset: [0, 1.2, 0.6]),
            ]
            r.travel = [
                .emit(.trail(.glow, .primary, rate: 70, life: 0.3, size: ult ? 0.6 : 0.4), .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.twinkle, .secondary, rate: 30, life: 0.5, size: 0.15), .follow, offset: [0, 1.0, 0]),
            ]
            r.impact = [
                .emit(.flare(ult ? 2.6 : 1.8, .core), offset: [0, 1.0, 0]),
                .emit(.sparks(18, speed: 7), offset: [0, 1.0, 0]),
                .emit(.wave(R * 1.2, .primary), offset: [0, 0.1, 0]),
            ]
        case .dashStrike, .leapSlam:
            r.cast = [
                .emit(.bloom(1.4, .primary, life: 0.3), offset: [0, 1.0, 0]),
                .emit(.smoke(6, radius: 0.5, life: 0.7, size: 0.6), quality: 1),
                .emit(.trail(.glow, .primary, rate: 80, life: 0.35, size: 0.5).with { $0.duration = 0.45 }, .follow,
                      offset: [0, 1.0, 0]),
            ]
            r.telegraph = [.mesh(.decal(.runeCircle, R * 2, .primary, life: 0.6, spin: 90, alpha: 0.6))]
            r.impact = [
                .emit(.flare(ult ? 3.2 : 2.2, .core), offset: [0, 0.8, 0]),
                .mesh(.shockRing(R * 1.2, .primary)),
                .emit(.wave(R * 1.4, .secondary, life: 0.6), offset: [0, 0.1, 0]),
                .emit(.debris(ult ? 18 : 10, speed: 6)),
                .emit(.smoke(8, radius: R * 0.6), quality: 1),
                .mesh(.decal(.crack, R * 2.2, .primary, life: 1.2, spin: 0, grow: 1.0, alpha: 0.7)),
                .shake(ult ? 0.5 : 0.25),
            ]
        case .blinkEmpower, .targetedBlink:
            r.cast = [
                .emit(.bloom(1.6, .primary, life: 0.3), offset: [0, 1.0, 0]),
                .emit(.motes(16, radius: 0.5, .secondary), offset: [0, 1.0, 0]),
            ]
            r.impact = [
                .emit(.flare(ult ? 2.8 : 1.8, .core), offset: [0, 1.0, 0]),
                .emit(.sparks(20, speed: 6), offset: [0, 1.0, 0]),
                .mesh(.slash(1.4, .primary, from: 120, to: -120, height: 1.0), offset: [0, 1.0, 0]),
                .emit(.wave(1.8, .primary)),
            ]
        case .groundAoE, .healZone:
            r.cast = [
                .emit(.flare(1.2, .core), offset: [0, 1.6, 0.3]),
                .emit(.gather(14, radius: 0.8, .primary), offset: [0, 1.4, 0.2]),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2, .primary, life: 0.9, spin: 60, alpha: 0.7)),
                .emit(.rising(14, radius: R * 0.8, .secondary, speed: 1.6)),
            ]
            r.impact = [
                .emit(.flare(ult ? 3 : 2, .core), offset: [0, 0.8, 0]),
                .mesh(.pillar(R * 0.6, height: ult ? 7 : 4.5, .primary)),
                .mesh(.shockRing(R, .primary)),
                .emit(.wave(R * 1.1, .secondary, life: 0.55), offset: [0, 0.1, 0]),
                .emit(.sparks(16, speed: 6, .core, end: .primary, gravity: 4), offset: [0, 0.6, 0]),
                .emit(.embers(14, radius: R * 0.7), quality: 1),
                .shake(ult ? 0.4 : 0.15),
            ]
        case .selfAoE, .teamHeal, .multiStrike:
            r.cast = [
                .emit(.bloom(2.0, .primary, life: 0.4), offset: [0, 1.0, 0]),
                .mesh(.decal(.runeCircle, R * 2, .primary, life: 0.7, spin: 120)),
            ]
            r.impact = [
                .mesh(.shockRing(R * 1.1, .primary)),
                .mesh(.burstWall(R, height: 1.6, .secondary)),
                .emit(.wave(R * 1.2, .core, life: 0.4), offset: [0, 0.1, 0]),
                .emit(.sparks(18, speed: 6), offset: [0, 0.9, 0]),
                .shake(ult ? 0.35 : 0.15),
            ]
        }
        return r
    }
}
