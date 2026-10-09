import Foundation
import VelstriaCore

// スキル演出: H034 鎖鉤のゴルム（Support / 先に鉤のついた太い鎖・鉄の肩当てと胸当て・大柄）。Franco の Velstria 版（キット: Kit_H034）。
// 主題: 鉄の鎖と錆びた鉤。白い芯 × 鉄の青灰（主）× 錆の赤（副）× 真鍮の褐色（差し色）× 煤けた暗褐色（暗）。
// 地を這う鎖の筋と、突き上がる鉄の鉤、重い衝撃で見せる（聖槌のボルグ H029 の青金の聖なる輝きとは逆に、泥臭く無骨）。
//   パッシブ 鉄鎖の執念      — 太い鎖が身に巻きつき、錆びた火の粉が舞う（無被弾で闘気が 1 秒に 1 つたまるたびに合図が出る = 重なって「帯電」して見える）。
//                              スキルで闘気を使い切った直後は passiveRelease（鎖がはじけて閃く。大きさは消費した数に比例）
//   スキル1 鎖鉤             — 長い鎖鉤を打ち出す。鉤に追従して鎖が手元まで伸びる（travel）。鉤が最初の敵に食い込み（impact）、
//                              相手から手元へ短い鎖が張って縮む（引き寄せの間 = hit）+ 鎖の輪が巻きつく（スタン）
//   スキル2 鉄鎖旋           — 足元から周囲へ鎖が走り、地が割れる（自身中心の範囲・70% 減速）
//   アルティメット 狩猟鎖獄    — 狙った敵ヒーローへ鎖が伸びて縛り上げ、鉄の鉤が輪になって立ち上がる（impact。拘束の間 残る輪もここ）。
//                              拘束の間（1.8 秒）6 回叩き伏せる = hit は 1 発ごとの短い閃きだけ（hitPerHit）
// SkillFXDirector は duration / count を読まない。アルティメットの 6 連撃は 1 発ごとの hit（hitPerHit）で表す。

enum FX_H034: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.98, 0.95, 0.9), primary: RGB(0.65, 0.7, 0.8),
                                   secondary: RGB(0.86, 0.3, 0.16), accent: RGB(0.85, 0.6, 0.32),
                                   dark: RGB(0.1, 0.05, 0.04))

    /// 突き上がる鉄の鉤（地から伸びる尖塔）。
    private static func hook(_ h: Float, life: Float = 0.9) -> FXMesh {
        FXMesh(shape: .spire, tex: .shard, tint: .primary, alpha: 0.9, size: [0.5, 0.1, 0.5], sizeEnd: [0.4, h, 0.4],
               ease: .outBack, life: life, fadeIn: 0.02, fadeOut: 0.6)
    }

    /// 鉤から手元まで張る鎖（travel。鉤に追従）。鉤は 18m/s で飛ぶので、長さ = 0.3 + 18t、中心は鉤の後ろを毎秒 9m で退く
    /// （鉤の先端に鎖の端が付いたまま伸びる。着弾で追従が外れても、先端は着弾点に残って手元側が伸び続ける）。
    private static func trailingChain(width: Float, _ tint: FXTint, y: Float) -> FXCue {
        let life: Float = 0.32
        var m = FXMesh.ray(.chain, length: 0.3 + 18 * life, width: width, tint, life: life)
        m.size = [0.3, 1, width * 0.4]
        m.ease = .linear
        m.advance = -9
        m.fadeIn = 0.04
        m.fadeOut = 0.6
        return .mesh(m, .follow, offset: [0, y, 0])
    }

    /// 引き寄せの間（0.3 秒）に相手から手元へ張る短い鎖（hit。相手に追従）。相手の端を保ったまま 3m → 1m に縮む。
    private static func pullChain(width: Float, _ tint: FXTint, y: Float) -> FXCue {
        var m = FXMesh.ray(.chain, length: 3.0, width: width, tint, life: 0.35)
        m.size = [3.0, 1, width * 0.4]
        m.sizeEnd = [1.0, 1, width]
        m.ease = .linear
        m.advance = 2.857
        m.fadeIn = 0.04
        m.fadeOut = 0.6
        return .mesh(m, .follow, offset: [0, y, -1.5])
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            // 闘気がたまるたびに出る（1 秒に 1 回）。光輪を長め（1.1 秒）にして重ね、たまっているほど帯びて見える
            r.cast = [
                .mesh(.halo(0.9, .primary, life: 1.1, spin: 180, tex: .ringDouble), .follow, offset: [0, 0.9, 0]),
                .mesh(.ray(.chain, length: 1.8, width: 0.45, .primary, life: 0.5), .follow, offset: [0, 1.0, 0])
                    .repeated(3, every: 0.04, yaw: 60),
                .mesh(.decal(.crack, 2.0, .secondary, life: 0.9, spin: 30, alpha: 0.6), .follow),
                .emit(.embers(10, radius: 0.5, .secondary, life: 1.0), .follow),
                .emit(.flare(0.9, .accent, life: 0.16), .follow, offset: [0, 1.2, 0]),
            ]
            r.hit = []
        case .skill1:
            // 射程 6.8m の長い鉤。鉤は弾として飛び（travel）、鎖が鉤に追従して手元まで伸びる。最初の敵に食い込み（impact）、
            // 相手から手元へ短い鎖が張って縮み（hit）、鎖が巻きつく
            r.cast = [
                .emit(.flare(1.0, .core, life: 0.12), at: 0.05, offset: [0.3, 1.1, 0.7]),
                .emit(.sparks(8, speed: 4, .primary, end: .secondary), at: 0.05, offset: [0.3, 1.1, 0.7]),
            ]
            r.travel = [
                .mesh(.orb(0.2, .core, life: 1.0, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.1, 0]),
                .mesh(.halo(0.45, .accent, life: 1.0, spin: 300, tex: .ring).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.1, 0]),
                .emit(.trail(.glow, .primary, rate: 70, life: 0.25, size: 0.5), .follow, offset: [0, 1.1, 0]),
                // 手元と鉤を繋ぐ鎖（2 本を少しずらして太く見せる）
                trailingChain(width: 0.6, .primary, y: 1.1),
                trailingChain(width: 0.45, .accent, y: 0.95),
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
                // 引き寄せの間 相手と手元を繋ぐ鎖（縮んでいく）
                pullChain(width: 0.55, .primary, y: 1.0),
                pullChain(width: 0.4, .accent, y: 0.75),
                // 拘束の鎖の輪（スタンの間 巻きついている）
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
            // 対象指定（狙った敵ヒーロー）。手元から鎖が伸びる（cast）→ 相手の足元に鎖と鉤の輪が立つ。縛られている間の輪もここ（impact）。
            // 拘束の間は 0.3 秒おきに 6 回叩きつける = 1 発ごとの短い閃き（hit）
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
                // 縛られている輪（拘束の 1.8 秒。相手は動けないので固定でよい）
                .mesh(.halo(0.5, .accent, life: 1.8, spin: 240, tex: .ringDouble), at: 0.15, offset: [0, 2.0, 0]),
                .mesh(.halo(0.6, .primary, life: 1.8, spin: -120, tex: .ring), at: 0.15, offset: [0, 0.8, 0]),
                .emit(.wave(R * 1.4, .primary, life: 0.6), at: 0.1, offset: [0, 0.1, 0]),
                .emit(.debris(14, speed: 7), at: 0.1),
                .shake(0.6, at: 0.1),
            ]
            // 6 回の叩きつけの 1 発ごと: 短い閃きと小さな火花だけ（輪は impact）
            r.hit = [
                .emit(.flare(1.2, .core, life: 0.14), offset: [0, 1.1, 0]),
                .emit(.sparks(5, speed: 5, .accent, end: .secondary), offset: [0, 1.0, 0]),
            ]
            r.hitPerHit = true
        }
        return r
    }

    /// 闘気を使い切った（スキルの発動の直後）ときの、鎖がはじけて閃く合図。released は消費した闘気の数（1...10）で、大きさに比例する。
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? {
        let k = Float(min(max(released, 1), 10)) / 10
        return [
            .emit(.flare(0.9 + 1.4 * k, .core, life: 0.2, tex: .flare6), .follow, offset: [0, 1.1, 0]),
            .mesh(.ray(.chain, length: 2.0 + 2.0 * k, width: 0.5, .primary, life: 0.35), .follow, offset: [0, 1.0, 0])
                .repeated(4, every: 0.02, yaw: 45),
            .mesh(.halo(0.8 + 0.6 * k, .secondary, life: 0.4, spin: 260, tex: .ring), .follow, offset: [0, 0.9, 0]),
            .emit(.sparks(6 + Int(10 * k), speed: 5 + 3 * k, .accent, end: .secondary), .follow, offset: [0, 1.0, 0]),
        ]
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
