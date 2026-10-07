import Foundation
import VelstriaCore

// スキル演出: H019 砦砕のブラム（Vanguard / 攻城槌、角兜）。
// 主題: 攻城槌で砦を砕く。灼けた橙（主）× 琥珀（副）× 鋼の鉄色（差し色）× 土煙。重く・荒々しく・地を割る。
//   パッシブ 破城衝動       — 瀕死で鉄の城壁の板が身の周りに立ち上がり、火の粉を散らして守る
//   S1 Bram式・一閃         — 槌を低く引きずって横へ薙ぎ払う（扇）。地割れが前へ走り、土煙が足を絡める（鈍足）
//   S2 星環シフト           — 槌を破城槌のように構えて突撃、激突で前方へ衝撃の壁と破片が弾ける。頭上に火花の環（気絶）
//   S3 境界制圧             — 槌を足元へ叩きつけて雄叫び。三重の衝撃波と放射の亀裂が四方へ弾き飛ばし、鉄の守りを得る
//   奥義 城壁崩し            — 高く跳んで全体重で叩き潰す。大地が割れ、鉄の杭の柵が円陣に突き出して足を縫い止める（根止め）

enum FX_H019: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.92, 0.72), primary: RGB(1.0, 0.48, 0.1),
                                   secondary: RGB(1.0, 0.74, 0.26), accent: RGB(0.7, 0.78, 0.9),
                                   dark: RGB(0.22, 0.15, 0.1))

    /// 土煙（明るい土色のアルファ合成。石畳の上でも見える）。
    private static let dust = FXTint.rgb(0.55, 0.45, 0.35)

    /// 突き出す鉄の杭（尖塔の形、鉄色）。
    private static func stake(_ height: Float, life: Float = 1.0) -> FXMesh {
        FXMesh(shape: .spire, tex: .beam, tint: .accent, alpha: 0.95, size: [0.16, 0.1, 0.16],
               sizeEnd: [0.24, height, 0.24], ease: .outBack, life: life, fadeIn: 0.03, fadeOut: 0.7)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            // 瀕死: 鉄の城壁の板が四方に立つ
            r.cast = [
                .emit(.flare(1.6, .core, life: 0.22), .follow, offset: [0, 1.1, 0]),
                .mesh(.wall(.hexShield, width: 1.1, height: 1.9, .accent, life: 1.1, alpha: 0.8)).ringed(4, radius: 0.75),
                .mesh(.halo(1.0, .primary, life: 0.9, spin: 120), .follow, offset: [0, 0.15, 0]),
                .mesh(.shockRing(1.6, .secondary, life: 0.4)),
                .emit(.embers(16, radius: 0.8, .secondary, life: 1.1), .follow),
                .emit(.smoke(6, radius: 0.6, dust, life: 1.0, size: 0.7), quality: 1),
            ]
            r.hit = []
        case .skill1:
            // 低く引きずった槌を横へ薙ぎ払う（0.14 秒）→ 地割れが前へ走る
            r.cast = [
                .emit(.sparks(10, speed: 3, .secondary, end: .primary, gravity: 4), offset: [0.6, 0.15, -0.2]),
            ]
            r.impact = [
                .mesh(.sweep(R * 0.75, .primary, from: 80, to: -90, life: 0.3), at: 0.12, offset: [0, 0.6, 0]),
                .mesh(.slash(R * 0.85, .secondary, from: 80, to: -90, height: 0.6, tilt: -5, life: 0.28), at: 0.13,
                      offset: [0, 0.6, 0]),
                .mesh(.slash(R * 0.8, .core, from: 80, to: -90, height: 0.6, tilt: -5, life: 0.16, tex: .slashThin), at: 0.13,
                      offset: [0, 0.65, 0]),
                // 前へ走る地割れ
                .mesh(.decal(.crack, R * 0.9, .dark, life: 1.1, spin: 0, grow: 1.05, alpha: 0.85), at: 0.14,
                      offset: [0, 0, R * 0.3]).repeated(3, every: 0.05, step: [0, 0, R * 0.25]),
                .mesh(.decal(.slash, R * 1.9, .primary, life: 0.55, spin: 0, grow: 1.05, alpha: 0.8), at: 0.14),
                .emit(.flare(1.2, .core, life: 0.16), at: 0.14, offset: [0, 0.6, R * 0.4]),
                .emit(.lineBurst(R, count: 14, .primary, life: 0.5, size: 0.3), at: 0.15, offset: [0, 0.1, 0.3]),
                .emit(.debris(12, speed: 5), at: 0.15, offset: [0, 0, R * 0.5]),
                // 土煙が前へ流れて足を絡める（鈍足）
                .emit(.smoke(10, radius: 0.6, dust, life: 1.3, size: 1.0).with {
                    $0.dir = .forward; $0.speed = R * 1.6; $0.spread = 40; $0.shape = .sphere(0.5)
                }, at: 0.15, offset: [0, 0.3, 0.6]),
                .shake(0.18, at: 0.14),
            ]
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.15), offset: [0, 0.9, 0]),
                .emit(.sparks(12, speed: 6, .core, end: .primary), offset: [0, 0.9, 0]),
                .emit(.smoke(4, radius: 0.3, dust, life: 0.9, size: 0.6), quality: 1),
            ]
        case .skill2:
            // 破城槌の突撃 → 激突で前方へ衝撃の壁
            r.cast = [
                .emit(.flare(1.2, .secondary, life: 0.16), offset: [0, 1.0, 0.7]),
                .emit(.trail(.smoke, dust, rate: 50, life: 0.7, size: 0.7).with {
                    $0.duration = 0.35; $0.additive = false; $0.grow = 2; $0.fade = .gradualFadeInOut
                }, .follow, offset: [0, 0.2, 0]),
                .emit(.trail(.streak, .primary, rate: 50, life: 0.28, size: 0.2).with {
                    $0.duration = 0.35; $0.stretch = 2.2; $0.dir = .backward; $0.speed = 3
                }, .follow, offset: [0, 0.9, 0]),
                .mesh(.wall(.shockwave, width: 1.6, height: 1.6, .primary, life: 0.35, alpha: 0.7), .follow,
                      offset: [0, 0.2, 0.9]),
            ]
            r.telegraph = [
                .mesh(.decal(.crack, R * 1.8, .dark, life: 0.3, spin: 0, grow: 1.0, alpha: 0.4)),
            ]
            r.impact = [
                .emit(.flare(2.0, .core, life: 0.2), offset: [0, 0.9, 0.3]),
                .mesh(.decal(.crack, R * 2.4, .dark, life: 1.3, spin: 0, grow: 1.0, alpha: 0.9)),
                .mesh(.shockRing(R * 1.4, .primary, life: 0.4)),
                // 前方へ押し寄せる衝撃の壁
                .mesh(.wall(.shockwave, width: R * 2.0, height: 1.6, .secondary, life: 0.4, alpha: 0.85).with {
                    $0.advance = 5
                }, offset: [0, 0, 0.3]),
                .mesh(.burstWall(R * 0.9, height: 1.4, .primary, life: 0.35)),
                .emit(.fan(26, .secondary, speed: 9, spread: 40, life: 0.4), offset: [0, 0.8, 0.3]),
                .emit(.debris(16, speed: 6.5), offset: [0, 0, 0.4]),
                .emit(.smoke(10, radius: R * 0.5, dust, life: 1.2, size: 1.0), quality: 1),
                .shake(0.28),
            ]
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.15), offset: [0, 1.0, 0]),
                // 気絶: 頭上に回る火花の環
                .mesh(.halo(0.42, .secondary, life: 0.9, spin: 400, tex: .ringDouble), .follow, offset: [0, 2.05, 0]),
                .emit(.sparks(8, speed: 2, .secondary, end: .primary, gravity: 0).with { $0.vortex = 6; $0.shape = .ring(0.4) },
                      .follow, offset: [0, 2.05, 0]),
            ]
        case .ultimate:
            // 城壁崩し: 跳躍中に着地点の亀裂が赤く灼け、着地で大地が割れて鉄の杭の柵が円陣に突き出す
            r.cast = [
                .emit(.flare(1.6, .secondary, life: 0.2), offset: [0, 0.6, 0]),
                .emit(.wave(1.8, .primary, life: 0.35)),
                .emit(.smoke(10, radius: 0.6, dust, life: 1.0, size: 0.9)),
                .emit(.debris(10, speed: 5)),
            ]
            r.telegraph = [
                .mesh(.decal(.crack, R * 2.6, .primary, life: 0.5, spin: 0, grow: 1.0, alpha: 0.6)),
                .mesh(.decal(.ringDouble, R * 2.4, .secondary, life: 0.5, spin: 120, alpha: 0.55)),
                .emit(.gather(20, radius: R * 1.2, .primary, life: 0.4), offset: [0, 0.3, 0]),
            ]
            r.impact = [
                .emit(.flare(2.5, .core, life: 0.26), offset: [0, 0.8, 0]),
                .mesh(.orb(0.8, .secondary, life: 0.25, grow: 2.2, alpha: 0.6), offset: [0, 0.3, 0]),
                .mesh(.decal(.crack, R * 3.6, .dark, life: 2.0, spin: 0, grow: 1.0, alpha: 0.95)),
                .mesh(.decal(.crack, R * 3.0, .primary, life: 1.2, spin: 0, grow: 1.05, alpha: 0.8)),
                .mesh(.shockRing(R * 1.6, .core, life: 0.35)),
                .mesh(.shockRing(R * 2.3, .primary, life: 0.55), at: 0.06),
                .mesh(.shockRing(R * 3.0, .secondary, life: 0.75), at: 0.12),
                .mesh(.burstWall(R * 1.4, height: 2.4, .primary, life: 0.45)),
                // 円陣に突き出す鉄の杭（根止め）
                .mesh(stake(1.6, life: 1.2), at: 0.06).ringed(8, radius: R * 1.05, every: 0.015),
                .mesh(.pillar(0.35, height: 3.5, .secondary, life: 0.5, alpha: 0.7)).ringed(4, radius: R * 0.5),
                .emit(.sparks(36, speed: 10, .core, end: .primary, size: 0.1, life: 0.5), offset: [0, 0.6, 0]),
                .emit(.debris(26, speed: 8), at: 0.02),
                .emit(.smoke(16, radius: R, dust, life: 1.7, size: 1.3).with { $0.speed = 2.5 }, at: 0.03),
                .emit(.embers(24, radius: R * 1.2, .secondary, life: 1.4), at: 0.1, quality: 1),
                .shake(0.8),
            ]
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.15), offset: [0, 0.9, 0]),
                // 足を縫い止める鉄の輪
                .mesh(.halo(0.55, .accent, life: 1.2, spin: 200, tex: .chain).with {
                    $0.size = [0.9, 1, 0.9]; $0.sizeEnd = [0.5, 1, 0.5]
                }, .follow, offset: [0, 0.2, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 槌を右後ろの地面に引きずる構え → 腰をひねって低く横へ薙ぎ払う
            m.key(0.08, .out) { p in
                p.armR = ArmPose(pitch: -0.5, out: 0.45, yaw: -0.3, elbow: 0.3)
                p.armL = ArmPose(pitch: 0.2, out: 0.2, yaw: 0.6, elbow: 0.9)
                p.weaponR = 2.2
                p.torsoYaw = 0.75
                p.torsoPitch = 0.25
                p.hipsDrop = 0.14
                p.glow = 0.9
            }
            m.slash(0.06, side: 1, power: 1.6)
            m.hold(0.16) { $0.torsoYaw -= 0.15; $0.hipsDrop = 0.16 }
        case .skill2:
            // 槌の頭を前へ向け、破城槌のように突き出して激突
            m.dash(0.06, lean: 0.6)
            m.key(0.04, .out) { p in
                p.armR = ArmPose(pitch: 1.3, out: 0.1, yaw: 0.3, elbow: 0.7)
                p.armL = ArmPose(pitch: 1.2, out: 0.1, yaw: 0.6, elbow: 0.9)
                p.weaponR = -1.57
            }
            m.hold(0.1)
            m.thrust(0.06, reach: 1.4)
            m.hold(0.1) { $0.glow = 1.6 }
            m.settle(0.1)
        case .ultimate:
            // 深く沈んで高く跳び、空中で振りかぶって全体重で叩き潰す
            m.brace(0.05, depth: 0.18)
            m.leap(0.2, height: 1.6, forward: 0.3)
            m.overhead(0.08)
            m.land(0.08, depth: 0.32)
            m.smash(0.04)
            m.hold(0.26) { $0.glow = 2.4; $0.hipsDrop = 0.3 }
        }
    }
}
