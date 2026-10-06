import Foundation
import VelstriaCore

// スキル演出: H024 夢織のノア（Assassin / 夢の針の双刃・ナイトキャップ・漂う夢の糸）。
// 主題: 夢の糸と星雲。白い芯 × 菫（主）× 桃（副）× 夜空の青（差し色）。細い糸が縫い、星が瞬く。
//   パッシブ 夢糸          — 奇襲の一撃で、相手の周りを夢の糸が縫い、星が瞬く
//   S1 ノア式・一閃         — 針の双刃で細く鋭く切り払い、糸の残光と星屑が舞う（鈍足）
//   S2 星環シフト           — 夢の糸を引いて駆け、着地で星屑が弾けて相手を眠らせる（気絶 = 眠りの星の輪）
//   S3 境界制圧             — 地点に星雲が渦巻いて弾け、敵を押し流す（吹き飛ばし）
//   奥義 夢界縫合            — 背後へ転移し、六本の夢の糸が相手を縫い留める。星雲の繭が閉じて弾ける（根止め）

enum FX_H024: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.95, 1.0), primary: RGB(0.72, 0.45, 1.0),
                                   secondary: RGB(1.0, 0.6, 0.86), accent: RGB(0.55, 0.78, 1.0),
                                   dark: RGB(0.1, 0.04, 0.16))

    /// 星屑（星形の粒が回りながら漂う）。
    private static func stardust(_ n: Int, radius: Float, speed: Float = 2, life: Float = 1.0) -> FXEmit {
        FXEmit.flutter(.star, n, radius: radius, .secondary, speed: speed, life: life, size: 0.16).with {
            $0.tintEnd = .accent; $0.gravity = -0.4
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.ray(.thread, length: 1.6, width: 0.5, .primary, life: 0.5), .follow, offset: [0, 1.1, 0])
                    .repeated(3, every: 0.04, yaw: 60),
                .emit(stardust(10, radius: 0.5, speed: 1.2), .follow, offset: [0, 1.2, 0]),
                .emit(.flare(1.0, .core, life: 0.16, tex: .flare4), .follow, offset: [0, 1.1, 0]),
            ]
            r.hit = []
        case .skill1:
            r.impact = [
                .mesh(.slash(R * 0.95, .primary, from: 85, to: -80, height: 1.0, tilt: -20, life: 0.22, tex: .slashThin), at: 0.07,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.85, .secondary, from: -85, to: 80, height: 1.1, tilt: 20, life: 0.22, tex: .slashThin), at: 0.1,
                      offset: [0, 1.1, 0]),
                .mesh(.ray(.thread, length: R * 1.4, width: 0.5, .secondary, life: 0.45).with { $0.yaw = 90 + 25 }, at: 0.08,
                      offset: [0, 1.0, R * 0.5]),
                .mesh(.ray(.thread, length: R * 1.4, width: 0.5, .primary, life: 0.45).with { $0.yaw = 90 - 25 }, at: 0.1,
                      offset: [0, 1.0, R * 0.5]),
                .emit(.fan(14, .secondary, speed: R * 3.5, spread: 35, life: 0.45, tex: .star, size: 0.16), at: 0.09,
                      offset: [0, 1.0, 0.3]),
                .mesh(.decal(.thread, R * 1.8, .accent, life: 0.9, spin: 30, alpha: 0.7), at: 0.1, offset: [0, 0, R * 0.5]),
                .emit(.flare(1.0, .core, life: 0.14), at: 0.09, offset: [0, 1.0, R * 0.4]),
            ]
            r.hit = [
                .emit(stardust(6, radius: 0.3, speed: 2, life: 0.7), offset: [0, 1.1, 0]),
                .mesh(.ray(.thread, length: 1.2, width: 0.4, .primary, life: 0.3), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            r.cast = [
                .emit(stardust(10, radius: 0.4)),
                .emit(.trail(.thread, .primary, rate: 30, life: 0.5, size: 0.7).with { $0.duration = 0.32; $0.angleVar = 180 },
                      .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.twinkle, .secondary, rate: 40, life: 0.6, size: 0.14).with { $0.duration = 0.32; $0.shape = .sphere(0.4) },
                      .follow, offset: [0, 1.0, 0]),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.18, tex: .flare4), offset: [0, 1.0, 0]),
                .emit(stardust(20, radius: 0.5, speed: 4.5)),
                .mesh(.decal(.star, R * 1.8, .primary, life: 0.8, spin: 120, alpha: 0.8)),
                .mesh(.shockRing(R * 1.2, .secondary, life: 0.4)),
                // 眠りの星の輪
                .mesh(.halo(0.5, .accent, life: 1.0, spin: 200, tex: .ringDouble), at: 0.06, offset: [0, 2.0, 0]),
                .emit(.flutter(.twinkle, 8, radius: 0.4, .accent, speed: 0.6, life: 1.0, size: 0.16), at: 0.06,
                      offset: [0, 2.0, 0], quality: 1),
                .shake(0.12),
            ]
        case .skill3:
            r.cast = [
                .emit(.gather(12, radius: 0.5, .secondary, life: 0.14), offset: [0, 1.3, 0.4]),
                .emit(.flare(1.0, .core, life: 0.14), at: 0.12, offset: [0, 1.3, 0.6]),
            ]
            r.telegraph = [
                .mesh(.decal(.swirl, R * 2.2, .primary, life: 0.6, spin: -300, alpha: 0.75)),
                .mesh(.decal(.thread, R * 2.0, .secondary, life: 0.6, spin: 200, alpha: 0.5)),
                .emit(.vortex(18, radius: R * 0.8, .secondary, life: 0.5, tex: .twinkle, speed: 1.2)),
            ]
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.2, tex: .flare4), offset: [0, 0.8, 0]),
                .emit(.bloom(R * 1.2, .primary, life: 0.45)),
                .mesh(.shockRing(R * 1.3, .secondary)),
                .mesh(.decal(.star, R * 2.0, .primary, life: 1.0, spin: 60, alpha: 0.85)),
                .emit(stardust(26, radius: R * 0.4, speed: 6)),
                .emit(.wave(R * 1.4, .accent, life: 0.5), offset: [0, 0.1, 0]),
                .emit(.fan(16, .secondary, speed: 7, spread: 60, life: 0.4, tex: .twinkle, size: 0.15), offset: [0, 0.8, 0]),
                .shake(0.15),
            ]
        case .ultimate:
            r.cast = [
                .emit(stardust(14, radius: 0.5)),
                .emit(.flare(1.4, .primary, life: 0.2)),
                .mesh(.decal(.thread, 2.0, .secondary, life: 0.5, spin: 300, alpha: 0.7)),
            ]
            r.impact = [
                .emit(.flare(2.2, .core, life: 0.26, tex: .flare4), offset: [0, 1.2, 0]),
                // 六本の夢の糸が縫い留める
                .mesh(.ray(.thread, length: 3.6, width: 0.7, .secondary, life: 1.2), at: 0.05)
                    .repeated(6, every: 0.06, yaw: 30),
                .mesh(.ray(.thread, length: 3.2, width: 0.5, .primary, life: 1.2), at: 0.08, offset: [0, 1.0, 0])
                    .repeated(6, every: 0.06, yaw: 30),
                .mesh(.dome(1.4, .primary, life: 1.1, tex: .thread, alpha: 0.5), at: 0.3),
                .mesh(.decal(.runeCircle, 4.2, .primary, life: 1.5, spin: 70, alpha: 0.85)),
                .mesh(.decal(.star, 3.0, .secondary, life: 1.4, spin: -90, alpha: 0.75)),
                .mesh(.halo(1.2, .accent, life: 1.2, spin: 260, tex: .ringDouble), at: 0.3, offset: [0, 0.4, 0]),
                .emit(stardust(26, radius: 1.2, speed: 1.5, life: 1.3), at: 0.2, offset: [0, 1.0, 0]),
                // 繭が閉じて弾ける
                .emit(.flare(2.6, .secondary, life: 0.26, tex: .flare6), at: 0.85, offset: [0, 1.0, 0]),
                .mesh(.shockRing(3.4, .primary, life: 0.5), at: 0.85),
                .emit(stardust(36, radius: 0.6, speed: 7, life: 1.0), at: 0.85, offset: [0, 1.0, 0]),
                .shake(0.3, at: 0.05),
                .shake(0.5, at: 0.85),
            ]
            r.hit = [
                .emit(stardust(8, radius: 0.3, speed: 3, life: 0.7), offset: [0, 1.1, 0]),
                .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.1, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 針の双刃を交差させ、くるりと身を返す
            m.crossSlash(0.12)
            m.spin(0.14, turns: 0.5, arms: false)
            m.hold(0.08)
        case .skill2:
            // 糸を引いて滑るように駆け、針で突く
            m.dash(0.06, lean: 0.5)
            m.hold(0.08)
            m.thrust(0.06, reach: 1.2)
            m.settle(0.1)
        case .skill3:
            // 針で円を描き（糸を紡ぐ）、前へ押し出す
            m.twirl(0.12, turns: 1)
            m.push(0.06)
            m.hold(0.14)
        case .ultimate:
            // 背後で二回転しながら糸を巻き、交差の縫い留め → 両腕を広げて繭を閉じる
            m.brace(0.04, depth: 0.12)
            m.spin(0.24, turns: 2)
            m.crossSlash(0.12)
            m.raise(0.12, glow: 2.0)
            m.hold(0.22) { $0.ring = 1.3 }
        }
    }
}
