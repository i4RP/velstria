import Foundation
import VelstriaCore

// スキル演出: H026 紫電のエウリア（Arcanist / 細身の杖・周囲に浮く小さな雷球。MLBB の Eudora の Velstria 版）。
// 主題: 紫の稲妻。電光の白い芯 × 紫（主）× 水色の電光（副）× 淡い藤色（差し色）× 黒に近い夜（暗）。
// 分岐して走る枝（bolt）と、天から落ちる雷（strike）で「紫電」を見せる。蒼い雷のトレン（H023）より暗く、鋭く、枝分かれする。
// sim の実際の挙動（Systems/Kits/Kit_H026.swift）に合わせた演出:
//   パッシブ 超伝導          — 小さな雷球が身の周りを巡り、紫の電弧が走る（cast）。印の付いた敵に奥義が当たったあとの「雷の炸裂」も
//                              この枠の telegraph（0.5 秒の収束）と impact（炸裂）で出す（炸裂のゾーンの演出 ID がパッシブ）
//   S1 Euria式・一閃        — 前方の扇（射程 6.5m・半角 30°）へ即時に雷。中心と左右に枝分かれして走る（cast の瞬間に impact を再生）
//                              （超伝導の敵に当たると 1 秒の雷の鎖 + 移動速度 +40% が付くが、sim は専用のイベントを出さない）
//   S2 星環シフト           — 対象を追う雷球（travel）が当たって弾け（impact）、当たった敵ごとに痺れの輪（スタン 1 秒）と
//                              魔防ダウンの足元の輪（1.8 秒）が出る（hit。印済みなら周囲の敵にも広がるので、被弾者ごとに再生される）
//   奥義 九天雷鳴           — 地点に紫の魔法陣（外側の円 = 半径 3m、内側の小さな円 = 中心の半径 1.5m）が 0.8 秒開き（telegraph）、
//                              中心に大雷、周囲に雷の柱（impact）。外側は中心の半分の威力。気絶は無い
// SkillFXDirector はまだ stage / count / duration を読まない。

enum FX_H026: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.97, 0.95, 1.0), primary: RGB(0.6, 0.32, 1.0),
                                   secondary: RGB(0.5, 0.85, 1.0), accent: RGB(0.88, 0.7, 1.0),
                                   dark: RGB(0.05, 0.02, 0.1))

    /// 杖の先（局所座標）。
    private static let tip: SIMD3<Float> = [0.2, 1.5, 0.8]
    /// 稲妻の枝の根元（杖の先のすこし手前）。
    private static let root: SIMD3<Float> = [0.2, 1.3, 0.8]

    /// 稲妻の枝（pivot から angle 度（+ = 左）の向きへ length m 走る雷）。
    private static func branch(_ angle: Float, length: Float, _ tint: FXTint, at t: Float = 0,
                             from pivot: SIMD3<Float> = [0, 1.0, 0], life: Float = 0.3) -> FXCue {
        let a = angle * .pi / 180
        let d = length / 2
        return FXCue.mesh(FXMesh.ray(.bolt, length: length, width: 0.8, tint, life: life).with { $0.yaw = 90 + angle },
                          at: t, offset: pivot + SIMD3<Float>(-sin(a) * d, 0, cos(a) * d))
    }

    /// 雷球の電光（小さな玉のまわりに電弧が走る）。
    private static func spark(_ n: Int, radius: Float, speed: Float = 3) -> FXEmit {
        FXEmit.sparks(n, speed: speed, .core, end: .primary, size: 0.1, life: 0.3, gravity: 0).with {
            $0.shape = .sphere(radius)
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .emit(spark(14, radius: 0.6, speed: 2.5), .follow, offset: [0, 1.2, 0]),
                .mesh(.sprite(.bolt, 1.2, .secondary, life: 0.2, grow: 1.1), .follow, offset: [0, 1.2, 0]),
                .mesh(.halo(0.7, .primary, life: 0.7, spin: 480, tex: .ring), .follow, offset: [0, 1.1, 0]),
                .emit(.flare(0.9, .accent, life: 0.14), .follow, offset: [0, 1.6, 0]),
            ]
            // 雷の炸裂（半径 1.9m）の予告: 0.5 秒かけて輪が絞られ、光が集まる（印の付いた敵に追従するゾーンの中心）
            r.telegraph = [
                .mesh(.decal(.techCircle, 3.8, .accent, life: 0.5, spin: -200, alpha: 0.8)),
                .mesh(.halo(1.3, .primary, life: 0.5, spin: 360, tex: .ringDouble), offset: [0, 0.2, 0]),
                .emit(.gather(14, radius: 1.5, .secondary, life: 0.4), offset: [0, 0.6, 0]),
            ]
            // 雷の炸裂: 天からの雷が敵を中心に落ちて弾ける
            r.impact = [
                .mesh(.strike(7, .core, width: 0.6, life: 0.3)),
                .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), offset: [0, 0.8, 0]),
                .mesh(.shockRing(1.9, .secondary, life: 0.4)),
                .mesh(.decal(.ringDouble, 3.8, .primary, life: 0.6, spin: 120, alpha: 0.7), at: 0.03),
                .emit(.sparks(22, speed: 8, .core, end: .primary, life: 0.4), offset: [0, 0.8, 0]),
                .shake(0.25),
            ]
        case .skill1:
            r.cast = [
                .emit(spark(10, radius: 0.25, speed: 2.5), offset: tip),
                .emit(.flare(1.2, .core, life: 0.14, tex: .flare6), at: 0.1, offset: tip),
                .mesh(.sprite(.bolt, 0.8, .secondary, life: 0.16, grow: 1.4), at: 0.1, offset: tip),
            ]
            // 扇（射程 6.5m・半角 30°）に即時に当たる。中心の稲妻から左右へ分かれて走る
            r.impact = [
                .emit(.flare(1.6, .core, life: 0.16, tex: .flare6), at: 0.04, offset: tip),
                branch(0, length: 6.2, .core, at: 0.04, from: root, life: 0.32),
                branch(14, length: 5.4, .secondary, at: 0.07, from: root),
                branch(-14, length: 5.4, .secondary, at: 0.07, from: root),
                branch(28, length: 4.4, .primary, at: 0.1, from: root),
                branch(-28, length: 4.4, .primary, at: 0.1, from: root),
                .emit(.fan(26, .primary, speed: 15, spread: 30, life: 0.35), at: 0.04, offset: tip),
                .emit(.lineBurst(5.8, count: 14, .secondary, life: 0.45), at: 0.06, offset: [0, 0.2, 0.6]),
                .mesh(.decal(.techCircle, 2.0, .primary, life: 0.5, spin: 120, alpha: 0.5), at: 0.1, offset: [0, 0, 5.2]),
            ]
            r.hit = [
                .mesh(.sprite(.bolt, 1.0, .secondary, life: 0.16, grow: 1.1), offset: [0, 1.2, 0]),
                .emit(.sparks(8, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            // 手元に雷球を溜めて投げ放つ
            r.cast = [
                .emit(.gather(10, radius: 0.5, .secondary, life: 0.14), offset: tip),
                .emit(.flare(1.1, .core, life: 0.14, tex: .flare6), at: 0.08, offset: tip),
                .mesh(.sprite(.bolt, 0.9, .accent, life: 0.16, grow: 1.3), at: 0.08, offset: tip),
            ]
            // 対象を追う雷球（travel）
            r.travel = [
                .mesh(FXMesh.orb(0.16, .core, life: 1.0, grow: 1.0, alpha: 0.9).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.15, 0]),
                .mesh(.sprite(.bolt, 1.0, .secondary, life: 1.0, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.15, 0]),
                .emit(.trail(.bolt, .core, rate: 40, life: 0.14, size: 0.8).with { $0.angleVar = 180 }, .follow,
                      offset: [0, 1.15, 0]),
                .emit(.trail(.glow, .primary, rate: 60, life: 0.25, size: 0.5), .follow, offset: [0, 1.15, 0]),
            ]
            // 命中で弾ける（周囲への広がりは被弾者ごとの hit で出る）
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.18, tex: .flare6), offset: [0, 1.1, 0]),
                .mesh(.shockRing(1.3, .secondary, life: 0.35)),
                branch(0, length: 1.6, .core, from: [0, 1.0, 0], life: 0.25),
                branch(90, length: 1.4, .secondary, at: 0.02, from: [0, 1.0, 0], life: 0.25),
                branch(-90, length: 1.4, .secondary, at: 0.02, from: [0, 1.0, 0], life: 0.25),
                branch(180, length: 1.2, .primary, at: 0.04, from: [0, 1.0, 0], life: 0.25),
                .emit(.sparks(18, speed: 6, .core, end: .primary), offset: [0, 1.0, 0]),
                .shake(0.12),
            ]
            // 被弾者ごと: 痺れの輪（スタン 1 秒）と、足元の魔防ダウンの輪（1.8 秒）
            r.hit = [
                .mesh(.halo(0.5, .accent, life: 1.0, spin: 300, tex: .ringDouble), .follow, offset: [0, 2.0, 0]),
                .mesh(.halo(0.75, .secondary, life: 1.8, spin: -240, tex: .ring, alpha: 0.7), .follow, offset: [0, 0.15, 0]),
                .emit(.sparks(8, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .ultimate:
            r.cast = [
                .emit(.gather(24, radius: 1.4, .secondary, life: 0.3), offset: [0, 2.4, 0.2]),
                .emit(.flare(2.2, .core, life: 0.26, tex: .flare6), at: 0.25, offset: [0, 2.6, 0.2]),
                .mesh(.sprite(.bolt, 1.6, .accent, life: 0.4, grow: 1.2), at: 0.2, offset: [0, 2.6, 0.2]),
                .mesh(.halo(1.0, .primary, life: 1.0, spin: 400, tex: .ringDouble), offset: [0, 2.0, 0]),
            ]
            // 予告（0.8 秒）: 外側の円（半径 3m = 外側の威力は半分）の中に、中心の小さな円（半径 1.5m = 重い一撃）
            r.telegraph = [
                .mesh(.decal(.runeCircle, R * 2.0, .primary, life: 0.8, spin: 100, alpha: 0.75)),
                .mesh(.decal(.ringDouble, R * 1.5, .secondary, life: 0.8, spin: 60, alpha: 0.5)),
                .mesh(.decal(.techCircle, 3.0, .accent, life: 0.8, spin: -160, alpha: 0.9)),
                .emit(.rising(18, radius: R * 0.8, .secondary, speed: 2.0, life: 0.7)),
                .emit(.gather(20, radius: R, .accent, life: 0.5), at: 0.3, offset: [0, 0.4, 0]),
            ]
            r.impact = [
                .emit(.flare(3.0, .core, life: 0.3, tex: .flare6), offset: [0, 1.0, 0]),
                // 中心の大雷と、周囲に降る六本の雷
                .mesh(.strike(10, .core, width: 0.9, life: 0.35)),
                .mesh(.strike(9, .secondary, width: 0.5, life: 0.3), at: 0.04),
                .mesh(.strike(8, .accent, width: 0.35, life: 0.26), at: 0.08).ringed(6, radius: R * 0.75, every: 0.07),
                // 地を走る雷の筋
                .mesh(.ray(.bolt, length: R * 1.4, width: 0.9, .secondary, life: 0.3), at: 0.05, offset: [0, 0.15, 0])
                    .ringed(5, radius: R * 0.75),
                .mesh(.decal(.runeCircle, R * 2.0, .primary, life: 1.4, spin: 60, alpha: 0.9)),
                .mesh(.decal(.techCircle, 3.0, .secondary, life: 1.2, spin: -120, alpha: 0.7)),
                .mesh(.shockRing(R * 0.8, .core, life: 0.4)),
                .mesh(.shockRing(R * 1.2, .primary, life: 0.65), at: 0.06),
                .emit(.sparks(34, speed: 10, .core, end: .primary, life: 0.45), offset: [0, 1.0, 0]),
                .emit(.rising(26, radius: R * 0.9, .secondary, speed: 3, life: 0.9), at: 0.15, quality: 1),
                .shake(0.6),
            ]
            r.hit = [
                .mesh(.sprite(.bolt, 1.1, .secondary, life: 0.18, grow: 1.1), offset: [0, 1.2, 0]),
                .emit(.sparks(10, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 杖の先へ雷を寄せ、前へ突き出して放つ（扇に即時に当たる）
            m.gather(0.08)
            m.push(0.06)
            m.hold(0.14) { $0.glow = 1.8 }
        case .skill2:
            // 手元に雷球を溜め、片手で投げ放つ（転移はしない）
            m.gather(0.08)
            m.throwCast(0.14)
            m.settle(0.1)
        case .ultimate:
            // 杖を天へ掲げて九天の雷を呼び → 地へ突き立てて落とす
            m.raise(0.16, glow: 2.0)
            m.hold(0.2) { $0.ring = 1.4; $0.glow = 2.4 }
            m.plant(0.08)
            m.hold(0.2)
        }
    }
}
