import Foundation
import VelstriaCore

// スキル演出: H028 断空のザイル（Assassin / 淡い青の光刃の長剣・光る visor・濃紺の軽装甲。MLBB の Saber の Velstria 版）。
// 主題: 空間を断つ光刃。白い芯 × シアン（主）× 淡い青（副）× 群青（差し色）× 濃紺（暗）。細く鋭い斬線と、断たれた空間の残像。
// sim の実際の挙動（Systems/Kits/Kit_H028.swift）に合わせた演出:
//   パッシブ 空断の理        — ダメージを与えるたびに相手の防御を削る（最大 5 層・5 秒）。visor の光が瞬いて十字の斬線が走る
//                              （層が増えるたび = パッシブのバッジの数が増えるたびに再生される。層そのものは相手の状態表示 = .mark の層で見せる）
//   S1 周回する剣（自己中心）— 5 本の光剣が 5 秒間、周囲を回る。0.5 秒ごとに触れた敵へ接触ダメージ。
//                              周回中にダメージを与えると剣が対象へ飛んで剣撃する（剣撃は hit / 当たり側の演出で見せる）
//   S2 突進（指定方向）      — 光の尾を引いて約 0.2 秒で踏み込み、通り道の敵を斬る。着いたあと 4 秒、刃に光が宿る
//                              （次の通常攻撃の強化 = 追加ダメージ + 鈍足 60%）
//   奥義 三連断空（対象指定）— 敵ヒーローへ空間を断って突進（約 0.2 秒）→ 打ち上げ 1.2 秒 → 0.4 / 0.8 / 1.2 秒に 3 連撃
//                              （弱・弱・最後の十字斬りが強い。最後の 1 撃には剣撃が乗らない）
// SkillCastEvent の shape / duration / count: S1 = selfRing・5（周回の秒）・5（剣の本数）、S2 = dashToPoint・突進の秒数、
//   奥義 = lockOn・約 1.4（突進 + 三連撃の秒）・3（撃数）。再使用の段（stage）は Saber に無いので使わない。

enum FX_H028: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.95, 1.0, 1.0), primary: RGB(0.2, 0.85, 1.0),
                                   secondary: RGB(0.6, 0.78, 1.0), accent: RGB(0.3, 0.5, 1.0),
                                   dark: RGB(0.02, 0.04, 0.14))

    /// 光刃の斬線（細く立つ光の線。roll で傾ける）。
    private static func cut(_ width: Float, _ tint: FXTint, roll: Float, at t: Float = 0, y: Float = 1.0) -> FXCue {
        FXCue.mesh(FXMesh.wall(.slashLine, width: width, height: 0.5, tint, life: 0.28, alpha: 0.95).with { $0.roll = roll },
                   at: t, offset: [0, y, 0.2])
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.ray(.slashLine, length: 1.8, width: 0.4, .primary, life: 0.4), .follow, offset: [0, 1.1, 0])
                    .repeated(2, every: 0.05, yaw: 90),
                .emit(.flare(0.9, .core, life: 0.16, tex: .flare4), .follow, offset: [0, 1.65, 0.1]),
                .mesh(.halo(0.8, .secondary, life: 0.6, spin: 320, tex: .ring), .follow, offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 3, .core, end: .primary, life: 0.3, gravity: 0).with { $0.shape = .sphere(0.5) },
                      .follow, offset: [0, 1.1, 0]),
            ]
            r.hit = []
        case .skill1:
            // 周回する剣: 5 本の光剣が放射状に飛び出し（0.3 秒）、周囲の輪になって 5 秒間回る。radius = 周回半径（2.3 m）
            let R = s.radius
            r.cast = [
                .emit(.flare(1.4, .core, life: 0.2, tex: .flare6), offset: [0, 1.0, 0]),
                .emit(.gather(12, radius: 0.8, .primary, life: 0.2), offset: [0, 1.0, 0]),
                // 剣が放射状に飛び出す
                .mesh(.ray(.slashLine, length: R * 0.8, width: 0.4, .core, life: 0.3), offset: [0, 1.0, 0])
                    .ringed(5, radius: R * 0.4),
                // 周回する輪（内向き・逆向きの 2 重。メッシュの寿命は 4 秒までなので 2 回に分けて 5 秒に届かせる）
                .mesh(.halo(R * 0.7, .primary, life: 3.9, spin: 420, tex: .ringDouble), .follow, offset: [0, 0.9, 0])
                    .repeated(2, every: 2.4),
                .mesh(.halo(R * 0.5, .secondary, life: 3.9, spin: -300, tex: .ring), .follow, offset: [0, 1.2, 0])
                    .repeated(2, every: 2.4),
                // 5 本の剣（輪の上を舞う光の刃）
                .emit(.flutter(.shard, 5, radius: R * 0.7, .core, speed: 2.0, life: 2.4, size: 0.22), .follow,
                      offset: [0, 1.0, 0]).repeated(2, every: 2.4),
            ]
            r.impact = [
                .mesh(.shockRing(R, .secondary, life: 0.5), at: 0.05),
                .mesh(.decal(.techCircle, R * 1.9, .primary, life: 1.2, spin: 120, alpha: 0.7), at: 0.05),
                .emit(.wave(R, .primary, life: 0.5), at: 0.05, offset: [0, 0.1, 0]),
            ]
            // 剣が当たった敵（接触・剣撃）。接触は 0.5 秒おき・剣撃は別に飛ぶので、1 発ごとに出す
            r.hit = [
                .mesh(.sprite(.slashThin, 1.2, .core, life: 0.18, grow: 1.1), offset: [0, 1.1, 0]),
                .emit(.sparks(8, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
            ]
            r.hitPerHit = true
        case .skill2:
            // 突進: 光の尾を引いて駆け（約 0.2 秒）、着地点で鋭い一閃。着いたあと 4 秒、刃に光が宿る（次の通常攻撃が強化）
            let W: Float = max(s.radius, 1.6)
            r.cast = [
                .emit(.bloom(1.2, .primary, life: 0.3), offset: [0, 1.0, 0]),
                .emit(.trail(.streak, .primary, rate: 80, life: 0.3, size: 0.5).with {
                    $0.duration = 0.25; $0.stretch = 3; $0.dir = .backward; $0.speed = 3
                }, .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.glow, .secondary, rate: 60, life: 0.3, size: 0.4).with { $0.duration = 0.25 }, .follow,
                      offset: [0, 1.0, 0]),
                // 強化通常攻撃: 刃に宿る光（4 秒）
                .mesh(.halo(0.6, .core, life: 3.9, spin: 240, tex: .ring), at: 0.2, .follow, offset: [0, 1.2, 0.5]),
            ]
            r.impact = [
                .mesh(.slash(W * 0.95, .core, from: 80, to: -80, height: 1.0, tilt: -15, life: 0.2, tex: .slashThin), at: 0.1,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(W * 1.0, .primary, from: 80, to: -80, height: 1.05, tilt: -15, life: 0.3), at: 0.1,
                      offset: [0, 1.05, 0]),
                .mesh(.ray(.slashLine, length: W * 1.4, width: 0.45, .secondary, life: 0.3), at: 0.1,
                      offset: [0, 1.0, -W * 0.5]),
                .mesh(.decal(.slash, W * 2, .secondary, life: 0.5, spin: 0, alpha: 0.7), at: 0.1),
                .emit(.fan(16, .primary, speed: W * 4, spread: 25, life: 0.35), at: 0.1, offset: [0, 1.0, 0]),
                .emit(.flare(1.3, .core, life: 0.16), at: 0.1, offset: [0, 1.0, 0.2]),
            ]
            // 斬られた敵: 防御ダウンの層（空断の理）が走る
            r.hit = [
                .mesh(.sprite(.slashThin, 1.2, .core, life: 0.18, grow: 1.1), offset: [0, 1.1, 0]),
                .emit(.sparks(8, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .ultimate:
            // 三連断空: 空間を断って突進（0 〜 0.2 秒）→ 打ち上げ → 0.4 / 0.8 / 1.2 秒の三連斬（最後は十字斬り）。
            // impact は対象の足元で再生される（lockOn）
            let R = min(max(s.radius, 1.2), 2.0)
            r.cast = [
                .emit(.flare(1.8, .core, life: 0.2, tex: .flare6), offset: [0, 1.0, 0]),
                .mesh(.ray(.slashLine, length: 3.6, width: 0.6, .primary, life: 0.35), offset: [0, 1.0, 1.8]),
                .emit(.sparks(16, speed: 5, .core, end: .accent, gravity: 0).with { $0.shape = .sphere(0.5) },
                      offset: [0, 1.0, 0]),
                .mesh(.decal(.techCircle, 2.4, .secondary, life: 0.5, spin: 240, alpha: 0.7)),
            ]
            r.impact = [
                // ロックオン → 到着の閃光 → 打ち上げ
                .mesh(.decal(.techCircle, R * 2.4, .secondary, life: 0.5, spin: 240, alpha: 0.75)),
                .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), at: 0.19, offset: [0, 1.0, 0]),
                .mesh(.halo(R * 0.5, .accent, life: 1.2, spin: 280, tex: .ringDouble), at: 0.22, offset: [0, 1.9, 0]),
                .emit(.rising(14, radius: R * 0.5, .secondary, speed: 4, life: 0.8), at: 0.22, quality: 1),
                // 1 撃目（0.4 秒）・2 撃目（0.8 秒）
                .mesh(.slash(R * 1.5, .core, from: 85, to: -85, height: 1.6, tilt: 28, life: 0.22, tex: .slashThin), at: 0.4,
                      offset: [0, 1.6, 0]),
                .mesh(.slash(R * 1.6, .primary, from: 85, to: -85, height: 1.65, tilt: 28, life: 0.3), at: 0.4,
                      offset: [0, 1.65, 0]),
                .mesh(.slash(R * 1.5, .core, from: -85, to: 85, height: 1.8, tilt: -28, life: 0.22, tex: .slashThin), at: 0.8,
                      offset: [0, 1.8, 0]),
                .mesh(.slash(R * 1.6, .primary, from: -85, to: 85, height: 1.85, tilt: -28, life: 0.3), at: 0.8,
                      offset: [0, 1.85, 0]),
                .emit(.sparks(14, speed: 8, .core, end: .accent), at: 0.4, offset: [0, 1.7, 0]).repeated(2, every: 0.4),
                // 締めの十字斬り（縦と横。剣撃は乗らない大きな 1 撃）
                .mesh(.slash(R * 1.8, .core, from: 80, to: -80, height: 1.9, tilt: 90, life: 0.26, tex: .slashThin), at: 1.2,
                      offset: [0, 1.9, 0]),
                .mesh(.slash(R * 1.8, .secondary, from: 80, to: -80, height: 1.9, tilt: 0, life: 0.3), at: 1.2,
                      offset: [0, 1.9, 0]),
                cut(2.4, .core, roll: 35, at: 1.2, y: 1.9),
                cut(2.4, .core, roll: -35, at: 1.2, y: 1.9),
                .emit(.flare(2.6, .core, life: 0.26, tex: .flare6), at: 1.2, offset: [0, 1.9, 0]),
                .emit(.sparks(20, speed: 9, .core, end: .accent), at: 1.2, offset: [0, 1.8, 0]),
                .mesh(.decal(.slash, R * 2.8, .secondary, life: 0.9, spin: 45, alpha: 0.75), at: 1.2),
                .mesh(.shockRing(R * 2.2, .secondary, life: 0.45), at: 1.2),
                .mesh(.shockRing(R * 3.0, .primary, life: 0.65), at: 1.26),
                .shake(0.2, at: 0.4),
                .shake(0.2, at: 0.8),
                .shake(0.5, at: 1.2),
            ]
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.14), offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 6, .core, end: .secondary), offset: [0, 1.0, 0]),
                .mesh(.halo(0.5, .accent, life: 1.0, spin: 300, tex: .ringDouble), .follow, offset: [0, 2.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 剣を呼ぶ: 低く構え、体を回して光剣を周囲へ放つ
            m.brace(0.05, depth: 0.12)
            m.spin(0.2, turns: 1)
            m.hold(0.12) { $0.glow = 1.6 }
            m.settle(0.1)
        case .skill2:
            // 前傾で踏み込み、振りかぶって一閃
            m.dash(0.06, lean: 0.5)
            m.windup(0.05, side: 1, power: 1.0)
            m.slash(0.06, side: 1, power: 1.1)
            m.hold(0.1)
        case .ultimate:
            // 空間を断って低く構え → 右・左と斬り返し（0.4 / 0.8 秒）→ 十字に切り上げる（1.2 秒）
            m.brace(0.04, depth: 0.14)
            m.hold(0.3)
            m.slash(0.06, side: 1, power: 1.2)
            m.hold(0.28)
            m.slash(0.06, side: -1, power: 1.2)
            m.hold(0.24)
            m.uppercut(0.1)
            m.hold(0.14) { $0.glow = 2.0 }
            m.settle(0.1)
        }
    }
}
