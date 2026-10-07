import Foundation
import VelstriaCore

// スキル演出: H008 風標のニア（Duelist / 風の旗槍）。
// 主題: 風の旗槍・竜巻。青緑（主）× 白い風（副）× 空色（差し色）。軽く・速く・渦を巻く。
//   パッシブ 追い風       — 足元から旋風が巻き上がり、羽根が舞う（攻撃速度のスタック）
//   S1 ニア式・一閃       — 旗槍の大薙ぎ。三日月の後を追って風の刃が扇状に飛ぶ
//   S2 星環シフト         — 風をまとって突進、着地で槍を突き立てると渦の陣が敵の足を絡め取る（鈍足）
//   S3 境界制圧           — 槍を切り上げて風を送り、地点に竜巻を立てて敵を巻き上げる（気絶）
//   奥義 風界標定          — 足元に風界の大紋章を標し、三連の旋風斬り。外へ吹き飛ばす突風の放射

enum FX_H008: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.92, 1.0, 0.98), primary: RGB(0.16, 0.95, 0.78),
                                   secondary: RGB(0.72, 1.0, 0.95), accent: RGB(0.42, 0.84, 1.0),
                                   dark: RGB(0.04, 0.16, 0.14))

    /// 前方へ飛ぶ風の刃（三日月が前を向いたまま進む）。
    private static func windBlade(_ size: Float, speed: Float, _ tint: FXTint, life: Float = 0.32) -> FXMesh {
        FXMesh.slash(size, tint, from: 55, to: -55, height: 0.6, life: life, tex: .slashThin).with {
            $0.advance = speed
            $0.fadeOut = 0.55
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(.flare(1.2, .core, life: 0.18), .follow, offset: [0, 1.0, 0]),
                .mesh(.tornado(0.85, height: 1.9, .primary, life: 0.75, spin: 720).with { $0.alpha = 0.6 }, .follow),
                .mesh(.decal(.swirl, 2.0, .secondary, life: 0.7, spin: 320, alpha: 0.75), .follow),
                .mesh(.halo(0.75, .accent, life: 0.6, spin: -420), .follow, offset: [0, 0.6, 0]),
                .emit(.vortex(16, radius: 0.7, .secondary, life: 0.7, speed: 2.4), .follow),
                .emit(.flutter(.feather, 8, radius: 0.6, .secondary, speed: 2.2), .follow, offset: [0, 1.1, 0], quality: 1),
            ]
            r.hit = []
        case .skill1:
            // 大薙ぎ: 振り抜きは 0.10 秒（モーションの slash）。左から右へ払い、風の刃が後を追う
            r.cast = [
                .emit(.gather(10, radius: 0.6, .secondary, life: 0.1), offset: [-0.4, 1.3, 0.2]),
            ]
            r.impact = [
                .mesh(.slash(R * 0.9, .primary, from: -70, to: 75, height: 1.0, tilt: 8, life: 0.3), at: 0.1,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.8, .core, from: -70, to: 75, height: 1.0, tilt: 8, life: 0.16), at: 0.1,
                      offset: [0, 1.05, 0]),
                .mesh(.slash(R * 1.05, .accent, from: -55, to: 90, height: 0.9, tilt: 4, life: 0.42, tex: .slashThin)
                    .with { $0.alpha = 0.6 }, at: 0.12, offset: [0, 0.95, 0], quality: 1),
                // 風の刃: 正面と左右 30° へ（正面は 2 枚重なって太く見える）
                .mesh(windBlade(1.0, speed: R * 3.2, .secondary), at: 0.12, offset: [0, 0.6, 0.3])
                    .repeated(2, every: 0.03, yaw: 30),
                .mesh(windBlade(1.0, speed: R * 3.2, .secondary), at: 0.12, offset: [0, 0.6, 0.3])
                    .repeated(2, every: 0.03, yaw: -30),
                .mesh(.decal(.swirl, R * 1.3, .primary, life: 0.6, spin: -300, alpha: 0.7), at: 0.1,
                      offset: [0, 0, R * 0.45]),
                .emit(.fan(24, .primary, speed: R * 4.5, spread: 45, life: 0.4), at: 0.1, offset: [0, 1.0, 0.4]),
                .emit(.flutter(.feather, 10, radius: 0.4, .secondary, speed: 6).with { $0.dir = .forward; $0.spread = 50 },
                      at: 0.11, offset: [0, 1.0, 0.6]),
                .emit(.wave(R * 0.8, .accent, life: 0.4, tex: .ring), at: 0.1, offset: [0, 0.05, R * 0.3]),
                .shake(0.1, at: 0.1),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.15), offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 6, .core, end: .primary), offset: [0, 1.0, 0]),
                .mesh(.slash(0.7, .secondary, from: 45, to: -45, height: 1.0, life: 0.18, tex: .slashThin), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            // 風に乗って突進 → 着地で槍を突き立て、渦の陣（鈍足）
            r.cast = [
                .emit(.trail(.streak, .secondary, rate: 70, life: 0.3, size: 0.2).with {
                    $0.duration = 0.35; $0.stretch = 2.5; $0.dir = .backward; $0.speed = 4
                }, .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.feather, .primary, rate: 25, life: 0.5, size: 0.16).with {
                    $0.duration = 0.35; $0.spin = 200; $0.spinVar = 200
                }, .follow, offset: [0, 0.9, 0], quality: 1),
                .mesh(.tornado(0.6, height: 1.6, .secondary, life: 0.4, spin: 900).with { $0.alpha = 0.55 }, .follow),
                .emit(.wave(1.2, .accent, life: 0.3, tex: .ring)),
            ]
            r.telegraph = [
                .mesh(.decal(.swirl, R * 1.8, .primary, life: 0.4, spin: 400, alpha: 0.55)),
            ]
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.2), offset: [0, 0.8, 0]),
                .mesh(.pillar(0.12, height: 2.6, .core, life: 0.35)),
                .mesh(.decal(.swirl, R * 2.2, .primary, life: 1.1, spin: -220, alpha: 0.85)),
                .mesh(.decal(.ringDouble, R * 2.0, .accent, life: 0.9, spin: 120, alpha: 0.6), at: 0.04),
                .mesh(.shockRing(R * 1.2, .core, life: 0.35)),
                .mesh(.tornado(R * 0.55, height: 2.4, .primary, life: 0.8, spin: -700)),
                .emit(.vortex(22, radius: R * 0.9, .secondary, life: 0.9, speed: 2)),
                .emit(.flutter(.feather, 12, radius: R * 0.5, .secondary), offset: [0, 0.8, 0], quality: 1),
                .shake(0.2),
            ]
            r.hit = [
                // 鈍足: 足元に絡みつく小さな渦
                .mesh(.decal(.swirl, 1.4, .accent, life: 0.8, spin: 360, alpha: 0.8), .follow),
                .emit(.sparks(10, speed: 5, .core, end: .secondary), offset: [0, 1.0, 0]),
            ]
        case .ultimate:
            // 風界標定: 発動で風界の紋章を標し、三連の旋風斬り（0 / 0.3 / 0.6 秒、回ごとに左右反転）
            r.cast = [
                .emit(.flare(2.0, .core, life: 0.25, tex: .flare6), offset: [0, 1.1, 0]),
                .mesh(.decal(.swirl, R * 3.0, .primary, life: 1.4, spin: 200, grow: 1.05, alpha: 0.8)),
                .mesh(.decal(.runeCircle, R * 2.4, .accent, life: 1.3, spin: -90, alpha: 0.6)),
                .mesh(.tornado(R * 0.8, height: 4.0, .secondary, life: 1.3, spin: 800).with { $0.alpha = 0.45 }, .follow),
                .emit(.vortex(30, radius: R * 1.1, .secondary, life: 1.0, speed: 3), .follow),
                .emit(.flutter(.feather, 14, radius: R * 0.6, .primary), offset: [0, 1.0, 0], quality: 1),
                .shake(0.3),
            ]
            r.impact = [
                .mesh(.sweep(R * 1.0, .primary, from: 90, to: -270, life: 0.32), offset: [0, 0.9, 0]),
                .mesh(.sweep(R * 0.9, .core, from: 90, to: -200, life: 0.2), offset: [0, 0.95, 0]),
                .mesh(.slash(R * 1.1, .accent, from: 80, to: -80, height: 1.0, tilt: -15, life: 0.3), at: 0.05,
                      offset: [0, 1.1, 0]),
                .mesh(.shockRing(R * 1.5, .secondary, life: 0.4), at: 0.05),
                .mesh(.burstWall(R * 1.2, height: 1.8, .primary, life: 0.4), at: 0.05),
                .mesh(.decal(.swirl, R * 2.2, .accent, life: 0.6, spin: -500, alpha: 0.7), at: 0.05),
                // 吹き飛ばし: 外へ走る突風の筋
                .mesh(.ray(.streak, length: 2.0, width: 0.6, .secondary, life: 0.32).with { $0.advance = 7 }, at: 0.05)
                    .ringed(6, radius: R * 0.8),
                .emit(.flare(2.2, .core, life: 0.2), at: 0.05, offset: [0, 1.0, 0]),
                .emit(.sparks(24, speed: 9, .core, end: .primary), at: 0.05, offset: [0, 1.0, 0]),
                .emit(.wave(R * 1.8, .primary, life: 0.5), at: 0.06, offset: [0, 0.1, 0]),
                .emit(.flutter(.feather, 10, radius: 0.6, .secondary, speed: 7), at: 0.06, offset: [0, 1.0, 0], quality: 1),
                .shake(0.35, at: 0.05),
            ]
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.15), offset: [0, 1.0, 0]),
                .emit(.sparks(12, speed: 7, .core, end: .accent), offset: [0, 1.0, 0]),
                .mesh(.slash(0.8, .secondary, from: 50, to: -50, height: 1.0, life: 0.2), offset: [0, 1.0, 0]),
                .mesh(.ray(.streak, length: 1.6, width: 0.5, .accent, life: 0.3).with { $0.advance = 5 }, offset: [0, 0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 旗槍を左へ引き、右へ大きく薙ぎ払う。振り抜いた後に旗がたなびく
            m.windup(0.05, side: -1, power: 1.1)
            m.slash(0.05, side: -1, power: 1.3)
            m.hold(0.14) { $0.torsoYaw += 0.1; $0.cape = 0.8 }
        case .skill2:
            // 槍を引き絞って突進 → 一直線に突き → 旗をたなびかせて残心
            m.chamber(0.04)
            m.dash(0.06, lean: 0.5)
            m.thrust(0.05, reach: 1.2)
            m.hold(0.12) { $0.cape = 1 }
            m.settle(0.1)
        case .ultimate:
            // 右薙ぎ → 一回転して左薙ぎ → 小さく跳んで叩きつけ（三連の旋風）
            m.windup(0.04, side: 1, power: 1.2)
            m.slash(0.05, side: 1, power: 1.4)
            m.spin(0.22, turns: 1)
            m.slash(0.06, side: -1, power: 1.4)
            m.leap(0.14, height: 0.5)
            m.land(0.08, depth: 0.25)
            m.smash(0.04)
            m.hold(0.2) { $0.glow = 2; $0.cape = 1; $0.ring = 1 }
        }
    }
}
