import Foundation
import VelstriaCore

// スキル演出: H034 鎖鉤のゴルム（Support / 先に鉤のついた太い鎖・鉄の肩当てと胸当て・大柄）。Franco の Velstria 版（キット: Kit_H034）。
// 主題: 鉄の鎖と錆びた鉤。白い芯 × 鉄の青灰（主）× 錆の赤（副）× 真鍮の褐色（差し色）× 煤けた暗褐色（暗）。
// 地を這う鎖の筋と、突き上がる鉄の鉤、重い衝撃で見せる（聖槌のボルグ H029 の青金の聖なる輝きとは逆に、泥臭く無骨）。
//   パッシブ 鉄鎖の執念      — 太い鎖が身に巻きつき、錆びた火の粉が舞う（無被弾で闘気がたまる）
//   S1 鎖鉤                  — 長い鎖鉤を打ち出す。前へ鎖が走り、鉤が飛んで最初の敵に食い込み、鎖が相手に巻きつく（引き寄せ + スタン）
//   S2 怒りの鎖              — 足元から周囲へ鎖が走り、地が割れる（自身中心の範囲・70% 減速）
//   奥義 狩猟鎖獄            — 狙った敵ヒーローへ鎖が伸びて縛り上げ、鉄の鉤が輪になって立ち上がる。拘束の間（1.8 秒）6 回叩き伏せる
// SkillFXDirector はまだ stage / count / duration を読まない: 奥義の 6 連撃は hit の合図を 0.3 秒おきに繰り返して表す。

enum FX_H034: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.98, 0.95, 0.9), primary: RGB(0.65, 0.7, 0.8),
                                   secondary: RGB(0.86, 0.3, 0.16), accent: RGB(0.85, 0.6, 0.32),
                                   dark: RGB(0.1, 0.05, 0.04))

    /// 突き上がる鉄の鉤（地から伸びる尖塔）。
    private static func hook(_ h: Float, life: Float = 0.9) -> FXMesh {
        FXMesh(shape: .spire, tex: .shard, tint: .primary, alpha: 0.9, size: [0.5, 0.1, 0.5], sizeEnd: [0.4, h, 0.4],
               ease: .outBack, life: life, fadeIn: 0.02, fadeOut: 0.6)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.halo(0.9, .primary, life: 0.8, spin: 180, tex: .ringDouble), .follow, offset: [0, 0.9, 0]),
                .mesh(.ray(.chain, length: 1.8, width: 0.45, .primary, life: 0.5), .follow, offset: [0, 1.0, 0])
                    .repeated(3, every: 0.04, yaw: 60),
                .mesh(.decal(.crack, 2.0, .secondary, life: 0.8, spin: 30, alpha: 0.6), .follow),
                .emit(.embers(10, radius: 0.5, .secondary, life: 1.0), .follow),
                .emit(.flare(0.9, .accent, life: 0.16), .follow, offset: [0, 1.2, 0]),
            ]
            r.hit = []
        case .skill1:
            // 射程 6.8m の長い鉤。0.04 秒で鎖が前へ伸び、鉤は弾として飛ぶ（travel）。最初の敵に食い込み（impact）、鎖が巻きつく（hit）
            let L = min(s.range * 0.85, 6.0)
            r.cast = [
                .emit(.flare(1.0, .core, life: 0.12), at: 0.05, offset: [0.3, 1.1, 0.7]),
                .emit(.sparks(8, speed: 4, .primary, end: .secondary), at: 0.05, offset: [0.3, 1.1, 0.7]),
                // 手元から鉤へ張る鎖（2 本を少しずらして太く見せる）
                .mesh(.ray(.chain, length: L, width: 0.6, .primary, life: 0.5), at: 0.04, offset: [0.1, 1.1, L * 0.5 + 0.3]),
                .mesh(.ray(.chain, length: L, width: 0.45, .accent, life: 0.45), at: 0.07, offset: [-0.15, 0.95, L * 0.5 + 0.3]),
            ]
            r.travel = [
                .mesh(.orb(0.2, .core, life: 1.0, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.1, 0]),
                .mesh(.halo(0.45, .accent, life: 1.0, spin: 300, tex: .ring).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.1, 0]),
                .emit(.trail(.glow, .primary, rate: 70, life: 0.25, size: 0.5), .follow, offset: [0, 1.1, 0]),
            ]
            r.impact = [
                // 鉤が食い込む
                .emit(.flare(1.6, .core, life: 0.18, tex: .flare6), offset: [0, 1.1, 0]),
                .mesh(.decal(.crack, 2.2, .secondary, life: 0.9, spin: 0, grow: 1.0, alpha: 0.7)),
                .mesh(.shockRing(1.1, .primary, life: 0.3)),
                .emit(.fan(14, .primary, speed: 6, spread: 25, life: 0.35), offset: [0, 1.0, 0]),
                .emit(.sparks(12, speed: 6, .accent, end: .secondary), offset: [0, 1.0, 0]),
                .emit(.debris(6, speed: 4), offset: [0, 0.1, 0]),
            ]
            r.hit = [
                // 拘束の鎖の輪（引き寄せの間・スタンの間 巻きついている）
                .mesh(.halo(0.55, .primary, life: 1.0, spin: 140, tex: .ringDouble), .follow, offset: [0, 0.9, 0]),
                .mesh(.halo(0.45, .secondary, life: 1.0, spin: -160, tex: .ring), .follow, offset: [0, 0.3, 0]),
                .emit(.sparks(8, speed: 5, .accent, end: .secondary), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            // 自身中心の範囲（半径 2.6m）。足元から鎖が四方へ走り、地が割れる。当たった敵には鎖の足枷（減速）
            r.cast = [
                .emit(.bloom(1.4, .accent, life: 0.3), offset: [0, 1.0, 0]),
                .emit(.trail(.glow, .primary, rate: 60, life: 0.35, size: 0.6).with { $0.duration = 0.3 }, .follow,
                      offset: [0, 1.0, 0]),
                .emit(.smoke(6, radius: 0.5, life: 0.7, size: 0.6), quality: 1),
            ]
            r.impact = [
                .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), offset: [0, 1.0, 0]),
                .mesh(.burstWall(R * 0.5, height: 1.2, .primary, life: 0.4), at: 0.03),
                .mesh(.shockRing(R * 0.9, .core, life: 0.4), at: 0.03),
                .mesh(.shockRing(R * 1.2, .secondary, life: 0.6), at: 0.07),
                .mesh(.decal(.crack, R * 1.8, .secondary, life: 1.1, spin: 0, grow: 1.0, alpha: 0.75), at: 0.03),
                // 四方へ走る鎖（中心を通る三本 = 六方向）
                .mesh(.ray(.chain, length: R * 1.9, width: 0.6, .primary, life: 0.5), at: 0.04, offset: [0, 0.3, 0])
                    .repeated(3, every: 0.02, yaw: 60),
                .emit(.wave(R * 1.0, .accent, life: 0.5), at: 0.03, offset: [0, 0.1, 0]),
                .emit(.debris(14, speed: 6), at: 0.03),
                .shake(0.32, at: 0.03),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
                // 鈍足の鎖の足枷
                .mesh(.halo(0.6, .accent, life: 0.9, spin: 100, tex: .ring), .follow, offset: [0, 0.15, 0]),
                .emit(.sparks(8, speed: 5, .accent, end: .secondary), offset: [0, 1.0, 0]),
            ]
        case .ultimate:
            // 対象指定（狙った敵ヒーロー）。手元から鎖が伸びる（cast）→ 相手の足元に鎖と鉤の輪が立つ（impact）→
            // 拘束の間 0.3 秒おきに 6 回叩きつける（hit を繰り返す）
            r.cast = [
                .emit(.gather(22, radius: 1.5, .accent, life: 0.3), offset: [0, 1.0, 0]),
                .emit(.flare(2.0, .core, life: 0.24, tex: .flare6), at: 0.2, offset: [0, 1.4, 0.2]),
                .mesh(.decal(.runeCircle, 3.0, .secondary, life: 0.8, spin: 90, alpha: 0.7)),
                .mesh(.ray(.chain, length: 3.2, width: 0.5, .primary, life: 0.5), at: 0.1, offset: [0, 0.4, 0])
                    .repeated(3, every: 0.04, yaw: 60),
            ]
            r.impact = [
                .emit(.flare(3.0, .core, life: 0.3, tex: .flare6), at: 0.1, offset: [0, 1.0, 0]),
                .mesh(.ray(.chain, length: R * 2.4, width: 0.8, .primary, life: 1.0), at: 0.1, offset: [0, 0.35, 0])
                    .repeated(4, every: 0.04, yaw: 45),
                .mesh(hook(2.8), at: 0.14).ringed(6, radius: R * 0.8, every: 0.03),
                .mesh(.burstWall(R, height: 1.6, .accent, life: 0.5), at: 0.1),
                .mesh(.shockRing(R * 1.5, .core, life: 0.4), at: 0.1),
                .mesh(.shockRing(R * 2.1, .secondary, life: 0.7), at: 0.15),
                .mesh(.decal(.crack, R * 2.3, .secondary, life: 1.3, spin: 0, grow: 1.0, alpha: 0.7), at: 0.1),
                .emit(.wave(R * 1.4, .primary, life: 0.6), at: 0.1, offset: [0, 0.1, 0]),
                .emit(.debris(14, speed: 7), at: 0.1),
                .shake(0.6, at: 0.1),
            ]
            r.hit = [
                // 縛られている輪（追従）と、6 回の叩きつけの閃き
                .mesh(.halo(0.5, .accent, life: 1.8, spin: 240, tex: .ringDouble), .follow, offset: [0, 2.0, 0]),
                .mesh(.halo(0.6, .primary, life: 1.8, spin: -120, tex: .ring), .follow, offset: [0, 0.8, 0]),
                .emit(.flare(1.2, .core, life: 0.14), at: 0.15, offset: [0, 1.1, 0]).repeated(6, every: 0.3),
                .emit(.sparks(10, speed: 6, .accent, end: .secondary), at: 0.15, offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 鎖鉤を振りかぶって投げ放つ
            m.throwCast(0.14)
            m.hold(0.12)
        case .skill2:
            // 腰を落とし、鎖を足元へ叩きつけて周囲を打ち据える（その場から動かない）
            m.brace(0.06, depth: 0.2)
            m.smash(0.08)
            m.hold(0.1)
            m.settle(0.12)
        case .ultimate:
            // 腰を落として吼え → 地を踏みしめて鎖を呼ぶ
            m.brace(0.06, depth: 0.18)
            m.roar(0.14)
            m.hold(0.12) { $0.ring = 1.3; $0.glow = 2.2 }
            m.stomp(0.16)
            m.hold(0.12)
        }
    }
}
