import Foundation
import VelstriaCore

// スキル演出: H009 機巧士オリン（Ranger / 機械腕の連弩・銃型）。
// 主題: 機巧・蒸気。橙の火花（主）× 真鍮（副）× 金（差し色）。白い蒸気と歯車の陣で「機械が唸る」ように。
//   パッシブ 過給機構     — 会心の一射で足元の歯車陣が回り、背の缶から蒸気と火花が噴く
//   S1 オリン式・一閃     — 過給した鋼の矢弾。回る歯車を伴って飛び、命中点に歯車の枷（鈍足）
//   S2 星環シフト         — 背の蒸気缶を噴かして跳ぶ。着地点で過給の放電が弾ける（気絶）
//   S3 境界制圧           — 仰角の榴弾。照準の歯車陣へ落ち、破片と外向きの衝撃で吹き飛ばす
//   奥義 零式過給          — 全機関を過給した貫通の一撃。歯車の環を連ねて飛び、鎖の枷で縛る（根止め）

enum FX_H009: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.95, 0.8), primary: RGB(1.0, 0.55, 0.12),
                                   secondary: RGB(0.95, 0.76, 0.38), accent: RGB(1.0, 0.86, 0.3),
                                   dark: RGB(0.14, 0.1, 0.07))

    /// 白い蒸気（アルファ合成）。
    private static let steam = FXTint.rgb(0.82, 0.8, 0.76)

    /// 投射物の下で回る歯車（地面から浮かせた水平の板）。
    private static func gear(_ size: Float, _ tint: FXTint, life: Float, spin: Float) -> FXMesh {
        FXMesh(shape: .disc, tex: .techCircle, tint: tint, alpha: 0.9, size: [size, 1, size], sizeEnd: [size, 1, size],
               ease: .linear, life: life, fadeIn: 0.05, fadeOut: 0.8, spin: spin)
    }

    /// 銃口の前に立つ光の輪（縦に立てた帯）。
    private static func muzzleRing(_ radius: Float, _ tint: FXTint, life: Float) -> FXMesh {
        FXMesh(shape: .band, tex: .beam, tint: tint, alpha: 0.9, size: [radius * 0.4, 1, radius * 0.4],
               sizeEnd: [radius, 1, radius], ease: .out, life: life, fadeIn: 0.03, fadeOut: 0.4, pitch: 90, spin: 360)
    }

    /// 放電（稲妻の小片がはじける）。
    private static func crackle(_ count: Int, radius: Float, life: Float = 0.2, size: Float = 0.5) -> FXEmit {
        FXEmit(tex: .bolt, tint: .core, tintEnd: .accent, count: count, emit: 0.12, life: life, size: size, sizeVar: 0.4,
               shape: .sphere(radius), angleVar: 180, fade: .linearFadeOut)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(.flare(1.0, .core, life: 0.15), .follow, offset: [0.15, 1.2, 0.5]),
                .mesh(.decal(.techCircle, 1.8, .secondary, life: 0.6, spin: 360, alpha: 0.8), .follow),
                .mesh(.halo(0.65, .primary, life: 0.5, spin: -500), .follow, offset: [0, 1.0, 0]),
                .emit(.sparks(14, speed: 6, .accent, end: .primary), .follow, offset: [0, 1.2, -0.2]),
                .emit(.smoke(5, radius: 0.3, steam, life: 0.8, size: 0.5), offset: [0, 1.4, -0.3], quality: 1),
            ]
            r.hit = []
        case .skill1:
            // 構え → 発射（0.10 秒の recoil）。銃口の閃光と蒸気
            r.cast = [
                .mesh(.decal(.techCircle, 1.6, .secondary, life: 0.4, spin: 400, alpha: 0.6), at: 0.06),
                .emit(.flare(1.3, .core, life: 0.15), at: 0.1, offset: [0.15, 1.2, 0.8]),
                .emit(.fan(14, .accent, speed: 8, spread: 18, life: 0.25), at: 0.1, offset: [0.15, 1.2, 0.8]),
                .emit(.smoke(5, radius: 0.25, steam, life: 0.7, size: 0.4), at: 0.11, offset: [0.1, 1.2, 0.6], quality: 1),
            ]
            r.travel = [
                .mesh(gear(0.8, .secondary, life: 0.7, spin: 1080), .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.glowHard, .primary, rate: 80, life: 0.2, size: 0.35), .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.streak, .accent, rate: 40, life: 0.25, size: 0.12).with {
                    $0.stretch = 2; $0.dir = .backward; $0.speed = 3; $0.spread = 20
                }, .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.smoke, steam, rate: 25, life: 0.6, size: 0.35).with { $0.additive = false; $0.grow = 2.2 },
                      .follow, offset: [0, 1.0, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.5, .core, life: 0.18), offset: [0, 1.0, 0]),
                .emit(.sparks(18, speed: 7, .accent, end: .primary), offset: [0, 1.0, 0]),
                .mesh(.shockRing(R * 1.3, .primary, life: 0.35)),
                .mesh(.decal(.techCircle, R * 2.2, .secondary, life: 0.9, spin: 120, alpha: 0.8)),
                .emit(.smoke(6, radius: 0.4, steam, life: 1.0, size: 0.6), quality: 1),
            ]
            r.hit = [
                // 鈍足: 足元を噛む歯車の枷
                .mesh(.decal(.techCircle, 1.3, .primary, life: 1.0, spin: -60, alpha: 0.85), .follow),
                .mesh(.halo(0.55, .secondary, life: 0.8, spin: 90), .follow, offset: [0, 0.35, 0]),
                .emit(.sparks(8, speed: 5, .accent, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            // 蒸気噴射の跳躍。転移元は蒸気の爆発、転移先は過給の放電
            r.cast = [
                .emit(.smoke(10, radius: 0.5, steam, life: 0.9, size: 0.7)),
                .emit(.sparks(14, speed: 5, .accent, end: .primary).with { $0.dir = .backward; $0.spread = 50 },
                      offset: [0, 0.8, 0]),
                .emit(.flare(1.4, .primary, life: 0.2), offset: [0, 0.6, 0]),
                .mesh(.shockRing(1.4, .secondary, life: 0.3)),
                .mesh(.decal(.techCircle, 1.8, .secondary, life: 0.5, spin: -400, alpha: 0.65)),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.2), at: 0.12, offset: [0, 0.9, 0]),
                .mesh(.decal(.techCircle, R * 2.4, .primary, life: 0.9, spin: 300, alpha: 0.85), at: 0.1),
                .mesh(.shockRing(R * 1.4, .accent, life: 0.35), at: 0.12),
                .mesh(.pillar(0.3, height: 2.2, .secondary, life: 0.35), at: 0.12),
                .emit(crackle(8, radius: R * 0.6), at: 0.12, offset: [0, 0.6, 0]),
                .emit(.sparks(20, speed: 7, .accent, end: .primary), at: 0.12, offset: [0, 0.6, 0]),
                .emit(.smoke(6, radius: R * 0.5, steam, life: 0.9, size: 0.6), at: 0.14, quality: 1),
                .shake(0.12, at: 0.12),
            ]
            r.hit = [
                // 気絶: 頭上で回る火花の輪と放電
                .mesh(.halo(0.42, .accent, life: 0.9, spin: 500), .follow, offset: [0, 2.0, 0]),
                .emit(crackle(4, radius: 0.3, life: 0.3, size: 0.35), .follow, offset: [0, 2.0, 0]),
                .emit(.flare(1.0, .core, life: 0.15), offset: [0, 1.0, 0]),
            ]
        case .skill3:
            // 仰角の発射（0.12 秒）→ 照準の歯車陣へ榴弾が落ちる → 爆発と外向きの衝撃（吹き飛ばし）
            r.cast = [
                .emit(.flare(1.4, .core, life: 0.16), at: 0.12, offset: [0.1, 1.6, 0.6]),
                .emit(.smoke(6, radius: 0.3, steam, life: 0.8, size: 0.5), at: 0.12, offset: [0.1, 1.5, 0.5], quality: 1),
                .emit(.fan(10, .accent, speed: 7, spread: 15, life: 0.3), at: 0.12, offset: [0, 1.5, 0.6]),
            ]
            r.telegraph = [
                .mesh(.decal(.techCircle, R * 2.2, .primary, life: 0.55, spin: 200, alpha: 0.7)),
                .mesh(.decal(.ringDouble, R * 1.6, .accent, life: 0.55, spin: -150, alpha: 0.55)),
                // 落ちてくる榴弾
                .mesh(.sprite(.glowHard, 0.6, .accent, life: 0.5, grow: 1.0).with { $0.rise = -7; $0.fadeOut = 0.9 },
                      offset: [0, 3.6, 0]),
            ]
            r.impact = [
                .emit(.flare(2.0, .core, life: 0.22), offset: [0, 0.8, 0]),
                .emit(.bloom(R * 1.0, .primary, life: 0.4), offset: [0, 0.6, 0]),
                .mesh(.shockRing(R * 1.5, .core, life: 0.35)),
                .mesh(.shockRing(R * 2.0, .primary, life: 0.55), at: 0.05),
                .mesh(.decal(.crack, R * 2.2, .dark, life: 1.3, spin: 0, alpha: 0.8)),
                .mesh(.decal(.techCircle, R * 2.4, .secondary, life: 0.8, spin: -200, alpha: 0.6)),
                .mesh(.ray(.streak, length: 1.4, width: 0.5, .accent, life: 0.3).with { $0.advance = 6 }, at: 0.02)
                    .ringed(6, radius: R * 0.6),
                .emit(.debris(12, speed: 6, .secondary, size: 0.14, tex: .techCircle)),
                .emit(.sparks(22, speed: 9, .accent, end: .primary), offset: [0, 0.5, 0]),
                .emit(.smoke(10, radius: R * 0.6, .dark, life: 1.2), quality: 1),
                .shake(0.2),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.15), offset: [0, 1.0, 0]),
                .mesh(.ray(.streak, length: 1.2, width: 0.45, .primary, life: 0.3).with { $0.advance = 5 }, offset: [0, 0, 0]),
            ]
        case .ultimate:
            // 零式過給: 構え → 0.12 秒で発射。大きな反動と蒸気、足元に過給の歯車陣
            r.cast = [
                .mesh(.decal(.techCircle, 3.4, .primary, life: 0.9, spin: 500, alpha: 0.85)),
                .mesh(.decal(.techCircle, 2.4, .secondary, life: 0.9, spin: -700, alpha: 0.6)),
                .emit(.flare(2.4, .core, life: 0.25, tex: .flare6), at: 0.12, offset: [0.15, 1.2, 0.9]),
                .mesh(.ray(.streak, length: 9, width: 1.2, .primary, life: 0.35, alpha: 0.8), at: 0.12, offset: [0, 0, 4.5]),
                .mesh(muzzleRing(0.9, .accent, life: 0.35), at: 0.12, offset: [0.15, 1.2, 1.0])
                    .repeated(3, every: 0.04, step: [0, 0, 0.8]),
                .emit(.smoke(10, radius: 0.5, steam, life: 1.2, size: 0.8), at: 0.12, quality: 1),
                .emit(.sparks(24, speed: 8, .accent, end: .primary), at: 0.12, offset: [0.15, 1.2, 0.9]),
                .shake(0.5, at: 0.12),
            ]
            r.travel = [
                .mesh(gear(1.4, .secondary, life: 0.9, spin: 1440), .follow, offset: [0, 1.0, 0]),
                .mesh(muzzleRing(0.7, .primary, life: 0.9).with { $0.fadeOut = 0.8; $0.ease = .outBack }, .follow,
                      offset: [0, 1.0, 0]),
                .emit(.trail(.glowHard, .primary, rate: 120, life: 0.25, size: 0.8), .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.streak, .accent, rate: 60, life: 0.3, size: 0.2).with {
                    $0.stretch = 3; $0.dir = .backward; $0.speed = 5; $0.spread = 25
                }, .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.smoke, steam, rate: 30, life: 0.8, size: 0.6).with { $0.additive = false; $0.grow = 2 },
                      .follow, offset: [0, 1.0, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(2.6, .core, life: 0.25), offset: [0, 1.0, 0]),
                .mesh(.shockRing(R * 1.6, .primary, life: 0.45)),
                .mesh(.decal(.techCircle, R * 2.6, .secondary, life: 1.4, spin: 160, alpha: 0.9)),
                .mesh(.burstWall(R * 1.1, height: 2.0, .accent, life: 0.45)),
                .emit(.sparks(30, speed: 10, .accent, end: .primary), offset: [0, 1.0, 0]),
                .emit(.debris(12, speed: 6, .secondary, size: 0.16, tex: .techCircle)),
                .emit(.smoke(10, radius: R * 0.6, steam, life: 1.3, size: 0.9), quality: 1),
                .shake(0.3),
            ]
            r.hit = [
                // 根止め: 歯車の枷と、地へ打ち込まれた鎖
                .mesh(.decal(.techCircle, 1.6, .primary, life: 1.4, spin: -90, alpha: 0.9), .follow),
                .mesh(.ray(.chain, length: 1.4, width: 0.35, .secondary, life: 1.3, alpha: 0.95), .follow)
                    .ringed(3, radius: 0.7),
                .mesh(.halo(0.55, .accent, life: 1.2, spin: 200, tex: .chain), .follow, offset: [0, 0.5, 0]),
                .emit(.sparks(12, speed: 6, .accent, end: .primary), offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 弩を素早く構えて一射、反動を腕で受ける
            m.aim(0.05)
            m.recoil(0.05, power: 1.0)
            m.hold(0.14) { $0.glow = 1.2 }
        case .skill2:
            // しゃがんで蒸気を噴き、低く跳んで着地 → 着地点へ一射
            m.brace(0.03, depth: 0.12)
            m.leap(0.06, height: 0.35, forward: 0.3)
            m.land(0.05, depth: 0.18)
            m.aim(0.06)
            m.recoil(0.04, power: 0.7)
            m.settle(0.1)
        case .skill3:
            // 弩を斜め上へ向け、榴弾を撃ち上げる（大きな反動）
            m.aim(0.07, up: 0.55)
            m.recoil(0.05, power: 1.4)
            m.hold(0.16) { $0.glow = 1.3 }
        case .ultimate:
            // 腰を据えて過給 → 発射の反動で後ろへ滑り、機関が赤熱したまま構え直す
            m.brace(0.03, depth: 0.12)
            m.aim(0.04)
            m.recoil(0.06, power: 2.0)
            m.backstep(0.14, distance: 0.45)
            m.hold(0.2) { $0.glow = 2.2; $0.ring = 1.2 }
            m.settle(0.12)
        }
    }
}
