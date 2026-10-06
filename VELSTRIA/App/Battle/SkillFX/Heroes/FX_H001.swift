import Foundation
import VelstriaCore

// スキル演出: H001 城門の誓衛アルデン（Vanguard / 広刃剣 + 城門塔の大盾）。
// 主題: 黄金の城門・誓いの光。金（主）× 蒼白の聖光（副）。重く・堅く・荘厳に。
//   パッシブ 不落の誓い    — 瀕死で黄金の六角盾が全身を包む
//   S1 アルデン式・一閃     — 黄金の大振りの横薙ぎ（扇）。刃の光が地を裂き前方へ衝撃が走る
//   S2 星環シフト           — 盾を構えて突進、着地で城門の紋章が地に刻まれ光の楔が立つ（根止め）
//   S3 境界制圧             — 剣を地へ突き立て、黄金の結界のドームと光柱の円陣
//   奥義 第七門・閉鎖令      — 高く跳び、七本の光柱を伴う城門の大紋章ごと叩き潰す

enum FX_H001: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.97, 0.86), primary: RGB(1.0, 0.76, 0.28),
                                   secondary: RGB(0.62, 0.8, 1.0), accent: RGB(1.0, 0.9, 0.55),
                                   dark: RGB(0.16, 0.11, 0.05))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(.flare(2.2, .core, life: 0.25, tex: .flare6), .follow, offset: [0, 1.1, 0]),
                .mesh(.dome(1.3, .primary, life: 1.1, tex: .hexShield, alpha: 0.6), .follow),
                .mesh(.dome(1.15, .secondary, life: 0.7, tex: .glow, alpha: 0.35), .follow),
                .mesh(.halo(1.1, .accent, life: 1.0, spin: 160), .follow, offset: [0, 0.1, 0]),
                .emit(.rising(22, radius: 0.9, .primary, speed: 2.2, life: 0.9), .follow),
                .emit(.motes(12, radius: 0.8, .secondary, life: 1.0), .follow, offset: [0, 1.0, 0], quality: 1),
            ]
            r.hit = []
        case .skill1:
            // 横薙ぎ: 振り抜きは 0.10 秒（モーションの slash に合わせる）
            r.cast = [
                .emit(.gather(10, radius: 0.7, .accent, life: 0.12), offset: [0.4, 1.4, 0.2]),
            ]
            r.impact = [
                .mesh(.slash(R * 1.0, .primary, from: 75, to: -80, height: 1.0, tilt: -8, life: 0.3), at: 0.09,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.92, .core, from: 75, to: -80, height: 1.0, tilt: -8, life: 0.18), at: 0.09,
                      offset: [0, 1.05, 0]),
                .mesh(.slash(R * 1.15, .secondary, from: 60, to: -90, height: 0.9, tilt: -4, life: 0.4).with { $0.alpha = 0.55 },
                      at: 0.11, offset: [0, 0.95, 0], quality: 1),
                .emit(.flare(1.1, .accent, life: 0.18), at: 0.1, offset: [0, 1.0, R * 0.5]),
                .emit(.fan(30, .primary, speed: R * 5, spread: 40, life: 0.38), at: 0.1, offset: [0, 1.0, 0.4]),
                .mesh(.decal(.slash, R * 2.1, .accent, life: 0.55, spin: 0, grow: 1.05, alpha: 0.85), at: 0.1),
                .emit(.lineBurst(R, count: 14, .primary, life: 0.45, size: 0.3), at: 0.12, offset: [0, 0.1, 0.3]),
                .emit(.debris(8, speed: 4.5), at: 0.12, offset: [0, 0, R * 0.6], quality: 1),
                .shake(0.12, at: 0.1),
            ]
            r.hit = [
                .emit(.flare(1.2, .core, life: 0.15), offset: [0, 1.0, 0]),
                .emit(.sparks(12, speed: 6, .accent, end: .primary), offset: [0, 1.0, 0]),
                .mesh(.slash(0.8, .primary, from: 40, to: -40, height: 1.0, life: 0.18), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            // 盾の突進 → 着地で城門の紋章
            r.cast = [
                .emit(.flare(1.6, .core), offset: [0, 1.1, 0.5]),
                .mesh(.wall(.hexShield, width: 1.6, height: 1.9, .primary, life: 0.45, alpha: 0.75), .follow,
                      offset: [0, 0.1, 0.7]),
                .emit(.trail(.glow, .primary, rate: 90, life: 0.35, size: 0.55).with { $0.duration = 0.4 }, .follow,
                      offset: [0, 1.0, 0]),
                .emit(.trail(.streak, .accent, rate: 50, life: 0.3, size: 0.18).with {
                    $0.duration = 0.4; $0.stretch = 2; $0.dir = .backward; $0.speed = 3
                }, .follow, offset: [0, 0.6, 0], quality: 1),
                .emit(.smoke(6, radius: 0.4, life: 0.6, size: 0.5), quality: 1),
            ]
            r.impact = [
                .emit(.flare(2.4, .core, life: 0.22, tex: .flare6), offset: [0, 0.9, 0]),
                .mesh(.decal(.runeCircle, R * 2.3, .primary, life: 1.1, spin: 30, alpha: 0.9)),
                .mesh(.shockRing(R * 1.3, .accent, life: 0.4)),
                .mesh(.pillar(0.18, height: 3.2, .core, life: 0.55, alpha: 0.9)).ringed(4, radius: R * 0.75),
                .mesh(.pillar(0.35, height: 2.4, .primary, life: 0.7, alpha: 0.6)).ringed(4, radius: R * 0.75),
                .emit(.sparks(22, speed: 7, .core, end: .primary), offset: [0, 0.8, 0]),
                .emit(.debris(10, speed: 5)),
                .shake(0.25),
            ]
        case .skill3:
            // 剣を突き立て、黄金の結界
            r.cast = [
                .emit(.flare(2.0, .core, life: 0.25), at: 0.08, offset: [0, 0.5, 0.5]),
                .emit(.gather(16, radius: R, .primary, life: 0.14)),
            ]
            r.impact = [
                .mesh(.decal(.runeCircle, R * 2.2, .primary, life: 1.2, spin: -40, alpha: 0.85), at: 0.1),
                .mesh(.dome(R * 0.95, .primary, life: 1.0, tex: .hexShield, alpha: 0.5), at: 0.1),
                .mesh(.shockRing(R * 1.15, .core, life: 0.35), at: 0.1),
                .mesh(.burstWall(R, height: 2.2, .accent, life: 0.45), at: 0.1),
                .mesh(.pillar(0.22, height: 3.5, .core, life: 0.6)).ringed(6, radius: R * 0.85, every: 0.03),
                .emit(.wave(R * 1.3, .secondary, life: 0.55), at: 0.12, offset: [0, 0.1, 0]),
                .emit(.rising(26, radius: R * 0.9, .accent, speed: 3, life: 0.8), at: 0.12),
                .emit(.motes(14, radius: R * 0.8, .secondary, life: 1.2), at: 0.2, offset: [0, 1.0, 0], quality: 1),
                .shake(0.2, at: 0.1),
            ]
        case .ultimate:
            // 第七門: 跳躍中は着地点に紋章が収束、着地で七本の光柱と大紋章
            r.cast = [
                .emit(.flare(2.2, .core, life: 0.3, tex: .flare6), offset: [0, 1.2, 0]),
                .emit(.wave(1.6, .primary, life: 0.35)),
                .emit(.smoke(8, radius: 0.5, life: 0.8, size: 0.7), quality: 1),
                .emit(.trail(.glow, .accent, rate: 70, life: 0.4, size: 0.6).with { $0.duration = 0.6 }, .follow,
                      offset: [0, 1.0, 0]),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.4, .primary, life: 0.75, spin: 120, grow: 1.0, alpha: 0.75)),
                .mesh(.decal(.ringDouble, R * 2.0, .accent, life: 0.75, spin: -80, alpha: 0.6)),
                .emit(.gather(26, radius: R * 1.1, .primary, life: 0.5), offset: [0, 0.4, 0]),
                .mesh(.pillar(R * 0.25, height: 8, .core, life: 0.5, alpha: 0.5), at: 0.15),
            ]
            r.impact = [
                .emit(.flare(4.2, .core, life: 0.3, tex: .flare6), offset: [0, 1.0, 0]),
                .emit(.bloom(R * 1.1, .primary, life: 0.45)),
                .mesh(.orb(R * 0.5, .core, life: 0.25, grow: 2.4, alpha: 0.7), offset: [0, 0.4, 0]),
                .mesh(.decal(.runeCircle, R * 3.0, .primary, life: 1.8, spin: 25, grow: 1.05, alpha: 0.95)),
                .mesh(.decal(.crack, R * 2.6, .accent, life: 1.6, spin: 0, grow: 1.0, alpha: 0.8)),
                .mesh(.shockRing(R * 1.6, .core, life: 0.4)),
                .mesh(.shockRing(R * 2.1, .primary, life: 0.65), at: 0.06),
                .mesh(.burstWall(R * 1.3, height: 2.6, .accent, life: 0.5)),
                .mesh(.pillar(0.3, height: 6.5, .core, life: 0.75)).ringed(7, radius: R * 0.95, every: 0.035),
                .mesh(.pillar(0.6, height: 4.5, .primary, life: 0.9, alpha: 0.55)).ringed(7, radius: R * 0.95, every: 0.035),
                .emit(.sparks(40, speed: 10, .core, end: .primary, size: 0.09, life: 0.5), offset: [0, 0.6, 0]),
                .emit(.debris(22, speed: 7.5)),
                .emit(.smoke(12, radius: R * 0.8, life: 1.4, size: 1.2), quality: 1),
                .emit(.rising(30, radius: R, .accent, speed: 4, life: 1.0), at: 0.1, quality: 1),
                .emit(.wave(R * 2.2, .secondary, life: 0.7), at: 0.04, offset: [0, 0.1, 0]),
                .shake(0.75),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 大きく振りかぶって一気に横薙ぎ、振り抜いた姿勢で残心
            m.windup(0.06, side: 1, power: 1.2)
            m.brace(0.03, depth: 0.1)
            m.slash(0.07, side: 1, power: 1.3)
            m.hold(0.14) { $0.torsoYaw -= 0.1 }
        case .skill2:
            // 盾を前に突進 → 着地で剣を振り下ろす
            m.dash(0.07, lean: 0.45)
            m.shieldBash(0.08)
            m.hold(0.12)
            m.overhead(0.08)
            m.smash(0.06)
            m.settle(0.1)
        case .skill3:
            // 剣を逆手に掲げ、地へ突き立てる
            m.overhead(0.06)
            m.kneel(0.05)
            m.smash(0.06)
            m.hold(0.22) { $0.glow = 1.8; $0.ring = 1 }
        case .ultimate:
            // 天へ剣を掲げ跳躍 → 空中で振りかぶり → 全体重で叩きつけ
            m.brace(0.06, depth: 0.14)
            m.leap(0.22, height: 1.3, forward: 0.4)
            m.raise(0.08)
            m.overhead(0.1)
            m.land(0.09, depth: 0.28)
            m.smash(0.04)
            m.hold(0.25) { $0.glow = 2.2; $0.ring = 1.3 }
        }
    }
}
