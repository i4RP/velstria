import Foundation
import VelstriaCore

// スキル演出: H013 獣刻のダガン（Vanguard / 骨の棍棒・獣皮の盾・獣の仮面）。
// 主題: 獣の刻印と咆哮。白熱の芯 × 血の赤（主）× 燃える朱（副）× 骨の白（差し色）。爪痕・咆哮の衝撃波で野性の暴力を見せる。
//   パッシブ 獣性解放      — 瀕死で赤い獣の気が噴き上がり、足元に爪の刻印が刻まれる
//   S1 ダガン式・一閃       — 棍棒の大振りが三条の赤い爪痕となって前方を裂く
//   S2 星環シフト           — 獣のように突進、着地で爪痕の刻印と土煙（鈍足）
//   S3 境界制圧             — 天を仰いで吼える。咆哮の衝撃波が三重に広がり、敵がすくむ（気絶）
//   奥義 獣王刻印            — 跳躍から叩きつけ、巨大な獣の爪の刻印が地に焼き付き周囲を吹き飛ばす

enum FX_H013: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.9, 0.84), primary: RGB(1.0, 0.18, 0.12),
                                   secondary: RGB(1.0, 0.5, 0.25), accent: RGB(0.98, 0.92, 0.78),
                                   dark: RGB(0.12, 0.03, 0.02))

    /// 爪痕（地面の三条の裂け目）。
    private static func clawMark(_ size: Float, _ tint: FXTint = .primary, life: Float = 1.0, yaw: Float = 0) -> FXMesh {
        FXMesh(shape: .disc, tex: .claw, tint: tint, alpha: 0.95, size: [size * 0.6, 1, size], sizeEnd: [size * 0.75, 1, size * 1.05],
               ease: .out, life: life, fadeIn: 0.03, fadeOut: 0.6, yaw: yaw)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.burstWall(1.0, height: 2.4, .primary, life: 0.7), .follow),
                .mesh(clawMark(2.0, .secondary, life: 1.0, yaw: 20), .follow),
                .emit(.rising(20, radius: 0.7, .primary, speed: 3.4, life: 0.8, tex: .flame), .follow),
                .emit(.flare(1.3, .secondary, life: 0.2), .follow, offset: [0, 1.6, 0]),
            ]
            r.hit = []
        case .skill1:
            r.impact = [
                .mesh(.slash(R * 1.0, .primary, from: 80, to: -85, height: 1.0, tilt: -15, life: 0.26), at: 0.1, offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.85, .core, from: 80, to: -85, height: 1.0, tilt: -15, life: 0.14, tex: .slashThin), at: 0.1,
                      offset: [0, 1.0, 0]),
                .mesh(clawMark(R * 1.5, .primary, life: 1.1), at: 0.11, offset: [0, 0, R * 0.55]),
                .mesh(.ray(.claw, length: R * 1.2, width: R * 0.9, .secondary, life: 0.3, alpha: 0.8).with { $0.advance = 3 },
                      at: 0.11, offset: [0, 1.0, R * 0.4]),
                .emit(.fan(20, .secondary, speed: R * 4.5, spread: 38, life: 0.35), at: 0.11, offset: [0, 1.0, 0.3]),
                .emit(.debris(10, speed: 4.5, tex: .shard), at: 0.12, offset: [0, 0, R * 0.6]),
                .emit(.flare(1.2, .accent, life: 0.15), at: 0.11, offset: [0, 1.0, R * 0.5]),
                .shake(0.15, at: 0.11),
            ]
            r.hit = [
                .mesh(.sprite(.claw, 1.0, .primary, life: 0.25, grow: 1.2), offset: [0, 1.1, 0]),
                .emit(.sparks(10, speed: 5, .accent, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            r.cast = [
                .emit(.smoke(8, radius: 0.5, life: 0.8, size: 0.8)),
                .emit(.trail(.flame, .primary, rate: 50, life: 0.35, size: 0.45).with { $0.duration = 0.35; $0.dir = .up; $0.speed = 1 },
                      .follow, offset: [0, 0.8, 0]),
                .emit(.trail(.smoke, .dark, rate: 30, life: 0.6, size: 0.7).with { $0.duration = 0.35; $0.additive = false; $0.grow = 2 },
                      .follow, offset: [0, 0.4, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.8, .accent, life: 0.2), offset: [0, 0.8, 0]),
                .mesh(clawMark(R * 2.0, .primary, life: 1.3)),
                .mesh(.shockRing(R * 1.3, .secondary, life: 0.4)),
                .emit(.debris(16, speed: 6)),
                .emit(.smoke(10, radius: R * 0.6, life: 1.2)),
                .emit(.sparks(16, speed: 6, .accent, end: .primary), offset: [0, 0.8, 0]),
                .shake(0.25),
            ]
        case .skill3:
            r.impact = [
                .emit(.flare(1.8, .secondary, life: 0.22), at: 0.12, offset: [0, 1.7, 0]),
                .mesh(.shockRing(R * 1.2, .primary, life: 0.45, tex: .ringDouble), at: 0.12).repeated(3, every: 0.12),
                .mesh(.decal(.soundWave, R * 2.0, .secondary, life: 0.5, spin: 0, grow: 1.4, alpha: 0.7), at: 0.12)
                    .ringed(4, radius: R * 0.4),
                .mesh(clawMark(R * 2.2, .primary, life: 1.2, yaw: 45), at: 0.12),
                .mesh(.burstWall(R, height: 2.0, .primary, life: 0.45), at: 0.12),
                .emit(.wave(R * 1.4, .accent, life: 0.45), at: 0.12, offset: [0, 0.1, 0]),
                .emit(.debris(14, speed: 5), at: 0.12),
                // すくみの星
                .mesh(.halo(R * 0.6, .accent, life: 0.9, spin: 300, tex: .ringDouble), at: 0.2, offset: [0, 0.4, 0]),
                .shake(0.3, at: 0.12),
            ]
        case .ultimate:
            r.cast = [
                .emit(.flare(1.6, .secondary, life: 0.2), offset: [0, 1.2, 0]),
                .emit(.rising(16, radius: 0.6, .primary, speed: 3, life: 0.6, tex: .flame)),
                .emit(.smoke(10, radius: 0.7, life: 1.0)),
            ]
            r.telegraph = [
                .mesh(clawMark(R * 2.2, .primary, life: 0.7).with { $0.alpha = 0.6 }),
                .emit(.gather(20, radius: R, .secondary, life: 0.45), offset: [0, 0.3, 0]),
            ]
            r.impact = [
                .emit(.flare(3.2, .accent, life: 0.3, tex: .flare6), offset: [0, 0.8, 0]),
                .emit(.bloom(R * 1.1, .primary, life: 0.5)),
                .mesh(clawMark(R * 3.2, .primary, life: 2.0)),
                .mesh(clawMark(R * 2.6, .secondary, life: 1.6, yaw: 90).with { $0.alpha = 0.7 }),
                .mesh(.decal(.crack, R * 2.8, .secondary, life: 1.8, spin: 0, alpha: 0.85)),
                .mesh(.decal(.runeCircle, R * 2.6, .primary, life: 1.4, spin: -50, alpha: 0.6)),
                .mesh(.shockRing(R * 1.6, .accent, life: 0.4)),
                .mesh(.shockRing(R * 2.3, .primary, life: 0.65, tex: .ringDouble), at: 0.07),
                .mesh(.burstWall(R * 1.2, height: 2.8, .primary, life: 0.5)),
                .emit(.debris(28, speed: 8.5)),
                .emit(.smoke(14, radius: R, life: 1.5, size: 1.2), quality: 1),
                .emit(.sparks(30, speed: 9, .accent, end: .primary, life: 0.5), offset: [0, 0.6, 0]),
                .emit(.rising(24, radius: R * 0.9, .primary, speed: 4, life: 0.9, tex: .flame), at: 0.08, quality: 1),
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
            // 棍棒を大きく振りかぶり、獣のように薙ぎ払う
            m.windup(0.07, side: 1, power: 1.3)
            m.slash(0.06, side: 1, power: 1.5)
            m.lunge(0.04, distance: 0.2, lean: 0.25)
            m.hold(0.12)
        case .skill2:
            // 盾を前に四つ足のような低い突進 → 盾で打つ
            m.brace(0.04, depth: 0.2)
            m.dash(0.06, lean: 0.7)
            m.hold(0.08)
            m.shieldBash(0.07)
            m.settle(0.1)
        case .skill3:
            // 身を沈め、天を仰いで吼える
            m.brace(0.06, depth: 0.16)
            m.roar(0.08)
            m.hold(0.26) { $0.headPitch = -0.6; $0.glow = 2.0 }
        case .ultimate:
            // 吼えて跳び、棍棒を両手で叩きつける
            m.roar(0.08)
            m.leap(0.22, height: 1.5, forward: 0.4)
            m.overhead(0.1)
            m.land(0.08, depth: 0.32)
            m.smash(0.04)
            m.hold(0.26) { $0.glow = 2.2 }
        }
    }
}
