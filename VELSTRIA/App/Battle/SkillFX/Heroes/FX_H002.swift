import Foundation
import VelstriaCore

// スキル演出: H002 星弦のリラ（Duelist / 星の細剣 + 星弦の竪琴弓）。
// 主題: 星の弦・星座。シアン（主）× 銀青（副）× 金の星（差し色）。細く・速く・きらめく。
//   パッシブ 星屑の調律    — 攻撃速度が重なるたび、星弦の輪が身体を巡り金の星が瞬く
//   S1 リラ式・一閃         — 細剣の三連の突きが星弦の扇を描き、切っ先に星が咲く。当たった敵を星の弦で縛る（根止め）
//   S2 星環シフト           — 星の尾を引いて駆け抜け、着地の突きで五つ星の星座が地に灯る
//   S3 境界制圧             — 竪琴弓を爪弾くと地点に星図の陣。星が降り注ぎ、銀の弦が足に絡む（鈍足）
//   奥義 天穹星弦            — 足元に天穹の星図を広げ、星弦の三連撃（突き・薙ぎ・旋回突き）。金の星の冠で気絶させる

enum FX_H002: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.92, 0.99, 1.0), primary: RGB(0.3, 0.86, 1.0),
                                   secondary: RGB(0.68, 0.8, 1.0), accent: RGB(1.0, 0.84, 0.36),
                                   dark: RGB(0.03, 0.07, 0.18))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(.flare(1.2, .accent, life: 0.2), .follow, offset: [0, 1.2, 0]),
                .mesh(.halo(0.9, .primary, life: 0.8, spin: 240, tex: .thread), .follow, offset: [0, 0.9, 0]),
                .mesh(.halo(0.7, .accent, life: 0.7, spin: -280, tex: .thread, alpha: 0.8), at: 0.05, .follow,
                      offset: [0, 1.4, 0]),
                .mesh(.decal(.star, 1.3, .accent, life: 0.7, spin: 90, alpha: 0.6), .follow),
                .emit(.flutter(.star, 8, radius: 0.6, .accent, speed: 1.5, life: 0.9, size: 0.14), .follow,
                      offset: [0, 1.1, 0]),
                .emit(.motes(12, radius: 0.7, .primary, life: 0.9), .follow, offset: [0, 1.0, 0], quality: 1),
            ]
        case .skill1:
            // 三連の突き: 切っ先は 0.10 秒（モーションの thrust に合わせる）
            r.cast = [
                .emit(.gather(10, radius: 0.6, .primary, life: 0.1), offset: [0.3, 1.2, 0.3]),
                .emit(.flare(0.9, .accent, life: 0.14), at: 0.05, offset: [0.3, 1.2, 0.5]),
            ]
            r.impact = [
                // 星弦（細い波打つ光の弦）の扇 + 白い芯の突き
                fanned(line(.thread, R * 0.95, 0.55, .primary, life: 0.34), 3, spread: 40, dist: R * 0.5, height: 1.0,
                       at: 0.09, every: 0.025),
                fanned(line(.streak, R * 0.9, 0.35, .core, life: 0.18), 3, spread: 40, dist: R * 0.47, height: 1.05,
                       at: 0.09, every: 0.025),
                // 切っ先に咲く金の星
                fanned(.sprite(.star, 0.7, .accent, life: 0.4, grow: 1.5), 3, spread: 40, dist: R * 0.95, height: 1.0,
                       at: 0.11, every: 0.025),
                // 地面: 扇の弧と三本の弦
                .mesh(.decal(.slash, R * 2.0, .primary, life: 0.55, spin: 0, grow: 1.05, alpha: 0.7), at: 0.1),
                fanned(line(.thread, R, 0.6, .secondary, life: 0.6, alpha: 0.75), 3, spread: 40, dist: R * 0.5,
                       at: 0.1, every: 0.025),
                .emit(.flare(1.0, .core, life: 0.15), at: 0.09, offset: [0, 1.0, 0.6]),
                .emit(.fan(24, .primary, speed: R * 4.5, spread: 22, life: 0.35), at: 0.09, offset: [0, 1.0, 0.4]),
                .emit(.lineBurst(R, count: 12, .accent, life: 0.5, size: 0.16, tex: .twinkle), at: 0.11,
                      offset: [0, 0.3, 0.3]),
                .shake(0.1, at: 0.1),
            ]
            r.hit = [
                // 根止め: 星の弦が身体に巻きつく
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
                .mesh(.halo(0.65, .primary, life: 0.9, spin: 300, tex: .thread), offset: [0, 0.45, 0]),
                .mesh(.halo(0.55, .accent, life: 0.8, spin: -360, tex: .thread), at: 0.04, offset: [0, 1.0, 0]),
                .mesh(.decal(.star, 1.3, .accent, life: 0.9, spin: 60, alpha: 0.8)),
            ]
        case .skill2:
            // 星の尾を引く突進 → 着地の突きで星座が灯る
            r.cast = [
                .emit(.flare(1.2, .core, life: 0.16), offset: [0, 1.0, 0.4]),
                .mesh(.decal(.star, 1.3, .primary, life: 0.5, spin: 160, alpha: 0.75)),
                .emit(.trail(.glow, .primary, rate: 80, life: 0.3, size: 0.5).with { $0.duration = 0.3 }, .follow,
                      offset: [0, 1.0, 0]),
                .emit(.trail(.star, .accent, rate: 36, life: 0.55, size: 0.16).with {
                    $0.duration = 0.3; $0.angleVar = 180; $0.spin = 200
                }, .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.streak, .secondary, rate: 50, life: 0.25, size: 0.16).with {
                    $0.duration = 0.3; $0.stretch = 2.2; $0.dir = .backward; $0.speed = 3
                }, .follow, offset: [0, 0.6, 0], quality: 1),
            ]
            r.telegraph = [
                .mesh(.decal(.ringDouble, R * 2, .primary, life: 0.4, spin: 160, alpha: 0.6)),
                .mesh(.decal(.star, R * 1.2, .accent, life: 0.4, spin: -200, alpha: 0.6)),
            ]
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.2), offset: [0, 1.0, 0.3]),
                .mesh(line(.streak, 2.2, 0.5, .core, life: 0.2), offset: [0, 1.0, 1.1]),
                .mesh(.decal(.runeCircle, R * 2.2, .primary, life: 0.9, spin: 40, alpha: 0.85)),
                .mesh(.decal(.star, R * 1.1, .accent, life: 0.8, spin: -50, alpha: 0.6), at: 0.03),
                .mesh(.shockRing(R * 1.3, .secondary, life: 0.4)),
                // 五つ星の星座
                .mesh(.sprite(.star, 0.6, .accent, life: 0.55, grow: 1.3), at: 0.04, offset: [0, 0.3, 0])
                    .ringed(5, radius: R * 0.9, every: 0.03),
                .emit(.sparks(18, speed: 6, .core, end: .primary), offset: [0, 0.9, 0]),
                .emit(.flutter(.star, 10, radius: 0.5, .accent, speed: 3.5, life: 0.8, size: 0.15), offset: [0, 0.8, 0]),
                .emit(.wave(R * 1.6, .primary, life: 0.5), offset: [0, 0.1, 0]),
                .shake(0.18),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 5, .accent, end: .primary), offset: [0, 1.0, 0]),
                .mesh(line(.streak, 1.4, 0.3, .primary, life: 0.18), offset: [0, 1.0, 0]),
            ]
        case .skill3:
            // 竪琴弓を爪弾く（0.12 秒）→ 0.5 秒後に星が降る
            r.cast = [
                .emit(.flare(0.9, .secondary, life: 0.15), at: 0.11, offset: [-0.3, 1.3, 0.4]),
                .emit(.flutter(.note, 6, radius: 0.3, .primary, speed: 2.0, life: 0.9, size: 0.2), at: 0.11,
                      offset: [-0.3, 1.3, 0.3]),
                .mesh(.decal(.soundWave, 2.0, .primary, life: 0.45, spin: 0, grow: 1.6, alpha: 0.8).with { $0.yaw = 90 },
                      at: 0.11, offset: [0, 0, 0.8]),
            ]
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.1, .primary, life: 0.65, spin: 70, alpha: 0.7)),
                .mesh(.halo(R * 0.95, .accent, life: 0.6, spin: -120, tex: .thread, alpha: 0.7), offset: [0, 0.1, 0]),
                .emit(.rising(12, radius: R * 0.8, .secondary, speed: 1.4, life: 0.6)),
                // 星の雨（着弾の瞬間に地へ届くよう予告の途中から降らせる）
                .emit(FXEmit(tex: .star, tint: .accent, tintEnd: .core, count: 18, emit: 0.18, life: 0.35, size: 0.24,
                             sizeVar: 0.3, grow: 0.6, shape: .disc(R * 0.8), dir: .down, speed: 14, speedVar: 0.2,
                             spin: 300, spinVar: 200, fade: .linearFadeOut), at: 0.2, offset: [0, 5, 0]),
            ]
            r.impact = [
                .emit(FXEmit(tex: .streak, tint: .core, tintEnd: .primary, count: 20, emit: 0.1, life: 0.28, size: 0.14,
                             shape: .disc(R * 0.85), dir: .down, speed: 18, stretch: 3, fade: .linearFadeOut),
                      offset: [0, 5, 0]),
                .emit(.flare(1.6, .core, life: 0.2), offset: [0, 0.7, 0]),
                .mesh(.pillar(R * 0.3, height: 4, .core, life: 0.35, alpha: 0.8)),
                .mesh(.decal(.runeCircle, R * 2.2, .primary, life: 1.1, spin: -30, alpha: 0.8)),
                .mesh(.decal(.star, R * 1.0, .accent, life: 1.0, spin: 40, alpha: 0.6), at: 0.03),
                .mesh(.shockRing(R * 1.2, .core, life: 0.35), at: 0.03),
                // 鈍足: 放射状に張られた銀の弦
                .mesh(line(.thread, R * 0.9, 0.4, .secondary, life: 1.0, alpha: 0.85), at: 0.05).ringed(6, radius: R * 0.5),
                .emit(.wave(R * 1.3, .primary, life: 0.5), at: 0.03, offset: [0, 0.1, 0]),
                .emit(.motes(14, radius: R * 0.8, .secondary, life: 1.4), at: 0.15, offset: [0, 0.4, 0], quality: 1),
                .shake(0.15, at: 0.03),
            ]
            r.hit = [
                .emit(.flare(0.8, .core, life: 0.14), offset: [0, 1.0, 0]),
                .mesh(.halo(0.6, .secondary, life: 1.0, spin: 200, tex: .thread), offset: [0, 0.25, 0]),
            ]
        case .ultimate:
            // 天穹の星図（術者に追従）+ 0 / 0.3 / 0.6 秒の三連撃（回ごとに左右反転）
            r.cast = [
                .emit(.flare(2.0, .core, life: 0.25, tex: .flare6), offset: [0, 1.2, 0]),
                .mesh(.decal(.runeCircle, R * 2.4, .primary, life: 1.4, spin: 30, alpha: 0.85), .follow),
                .mesh(.decal(.ringDouble, R * 1.9, .accent, life: 1.3, spin: -45, alpha: 0.7), .follow),
                .mesh(.halo(R * 0.8, .secondary, life: 1.2, spin: 140, tex: .thread, alpha: 0.8), .follow,
                      offset: [0, 0.15, 0]),
                .emit(.rising(24, radius: R * 0.8, .primary, speed: 3, life: 0.9), .follow),
                .emit(.flutter(.star, 12, radius: R * 0.6, .accent, speed: 2, life: 1.2, size: 0.16), .follow,
                      offset: [0, 1.0, 0], quality: 1),
                .shake(0.3, at: 0.08),
            ]
            r.impact = [
                .mesh(.sweep(R * 0.95, .primary, from: 120, to: -200, life: 0.3), at: 0.06, offset: [0, 1.0, 0]),
                .mesh(.sweep(R * 0.8, .core, from: 120, to: -200, life: 0.2), at: 0.06, offset: [0, 1.05, 0]),
                .mesh(.slash(R * 0.9, .accent, from: 80, to: -100, height: 1.0, tilt: -15, life: 0.28, tex: .slashThin),
                      at: 0.07, offset: [0, 1.1, 0]),
                .mesh(.halo(R * 0.9, .primary, life: 0.45, spin: 400, tex: .thread), at: 0.07, offset: [0, 0.6, 0]),
                .mesh(.shockRing(R * 1.1, .secondary, life: 0.4), at: 0.07),
                .mesh(.decal(.star, R * 0.7, .accent, life: 0.45, spin: 200, grow: 1.2, alpha: 0.55), at: 0.07),
                .mesh(.sprite(.star, 0.55, .accent, life: 0.4, grow: 1.4), at: 0.08, offset: [0, 1.0, 0])
                    .ringed(5, radius: R * 0.8, every: 0.02),
                .emit(.flare(1.8, .core, life: 0.18), at: 0.07, offset: [0, 1.0, 0]),
                .emit(.sparks(22, speed: 8, .core, end: .primary), at: 0.07, offset: [0, 1.0, 0]),
                .emit(.wave(R * 1.4, .primary, life: 0.45), at: 0.07, offset: [0, 0.1, 0]),
                .shake(0.45, at: 0.07),
            ]
            r.hit = [
                // 気絶: 頭上に金の星の冠
                .emit(.flare(1.0, .core, life: 0.15), offset: [0, 1.1, 0]),
                .mesh(.halo(0.42, .accent, life: 1.0, spin: 400), offset: [0, 2.1, 0]),
                .emit(FXEmit(tex: .star, tint: .accent, tintEnd: .core, count: 6, life: 0.9, size: 0.2, sizeVar: 0.2,
                             shape: .ring(0.42), surface: true, dir: .up, speed: 0.05, spin: 180,
                             fade: .gradualFadeInOut), offset: [0, 2.1, 0]),
            ]
        }
        return r
    }

    // MARK: 部品

    /// 前方へ伸びる横長の画像の帯（画像の横 = 前方）。中心が原点なので offset.z に length / 2 を足して置く。
    private static func line(_ tex: FXTex, _ length: Float, _ width: Float, _ tint: FXTint, life: Float,
                             alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [length, 1, width * 0.4],
               sizeEnd: [length, 1, width], ease: .out, life: life, fadeIn: 0.03, fadeOut: 0.3, yaw: 90)
    }

    /// 前方の扇に n 枚並べる（術者から dist m 先・左右 spread 度・高さ h）。帯は外向き。
    private static func fanned(_ m: FXMesh, _ n: Int, spread: Float, dist: Float, height h: Float = 0, at: Float = 0,
                               every: Float = 0) -> FXCue {
        let a0 = -spread / 2
        let r = a0 * .pi / 180
        let rotated = m.with { $0.yaw += a0; $0.yawEnd = $0.yawEnd.map { $0 + a0 } }
        var c = FXCue.mesh(rotated, at: at, offset: [-dist * sin(r), h, dist * cos(r)])
            .repeated(n, every: every, yaw: n > 1 ? spread / Float(n - 1) : 0)
        c.orbit = 0.0001
        return c
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 細剣を引き絞り、踏み込みと同時に鋭く突く（0.10 秒）→ 切っ先を残して残心
            m.chamber(0.04)
            m.lunge(0.03, distance: 0.35, lean: 0.3)
            m.thrust(0.03, reach: 1.2)
            m.hold(0.14) { $0.glow = 1.8 }
            m.settle(0.1)
        case .skill2:
            // 前傾で駆け、着地で突く → 細剣を手元で一回転させる
            m.dash(0.06, lean: 0.5)
            m.chamber(0.05)
            m.thrust(0.04)
            m.twirl(0.18, turns: 1)
            m.settle(0.08)
        case .skill3:
            // 竪琴弓を構えて弦を爪弾く（0.12 秒）
            m.draw(0.07, up: 0.2)
            m.release(0.05)
            m.hold(0.18) { $0.ring = 1; $0.glow = 1.6 }
        case .ultimate:
            // 三連撃: 突き（0.1 秒）→ 逆からの薙ぎ（0.36 秒）→ 旋回して踏み込み突き（0.67 秒）
            m.brace(0.04, depth: 0.1)
            m.chamber(0.03)
            m.thrust(0.04, reach: 1.2)
            m.hold(0.1) { $0.glow = 1.6 }
            m.windup(0.08, side: -1, power: 1.1)
            m.slash(0.06, side: -1, power: 1.2)
            m.spin(0.18, turns: 1)
            m.chamber(0.06)
            m.lunge(0.04, distance: 0.4, lean: 0.35)
            m.thrust(0.04, reach: 1.3)
            m.hold(0.15) { $0.glow = 2.2; $0.ring = 1.2 }
            m.settle(0.1)
        }
    }
}
