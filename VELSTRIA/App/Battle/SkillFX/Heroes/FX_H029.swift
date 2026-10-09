import Foundation
import VelstriaCore

// スキル演出: H029 聖槌のボルグ（Support / 巨大な聖槌・円盾・青と金の重装。MLBB の Tigreal の Velstria 版）。
// 主題: 青金の聖槌。白金の芯 × 青（主）× 金（副）× 淡い青白（差し色）。重く、堅く、叩きつけた衝撃が大地を走る。
// sim の実際の挙動（Systems/Kits/Kit_H029.swift）に合わせた演出:
//   パッシブ 聖鎚の誓い       — 金の光輪と青い盾の紋が身を包み、誓いの光が昇る（4 つたまると次の通常攻撃を無効化する）。
//                              無効化した瞬間（自分に 0.3 秒の「blocked」の印 + パッシブのバッジが 0.3 秒だけタイマーになる）は
//                              通常のパッシブの合図が出る。スキルの発動の直後（0.6 秒以内）の無効化は passiveRelease の金の盾の弾け
//   スキル1 聖槌波           — 前方の扇に衝撃波が 3 回（0.12 / 0.32 / 0.52 秒）。回ごとに扇の半径が広がる（射程の 0.7 / 0.85 / 1.0 倍）ので
//                              衝撃が前へ進んで見える。鈍足は命中ごとに深まる（20 → 40 → 60%）= 3 回目に大きな青い輪
//   スキル2 聖槌突撃         — 1 回目: 盾を構えて突進（約 0.25 秒）して通り道の敵を終点まで押し運ぶ（cast の金の尾）。
//                              再使用（stage 1）: 0.2 秒の振りかぶり（金の光が集まる）のあと、前方の扇に聖槌を叩きつけ、光の柱が立つ。
//                              打ち上げ 0.8 秒。段の演出は recipe(_:stage:_:) に分けてある（突進の尾は出さない）
//   アルティメット 崩落聖域    — 詠唱 0.8 秒。0〜0.3 秒は聖槌を掲げて光が集まる（CC で中断できる）、0.3 秒で青金の渦が敵を引き寄せ、
//                              0.8 秒で聖槌が落ちて崩落の衝撃 + 気絶（1.8 秒）の星の輪
// SkillFXDirector は duration / count を読まない: 段（stage）は recipe(_:stage:_:) で、アルティメットの段は at で表す。

enum FX_H029: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.98, 0.88), primary: RGB(0.25, 0.5, 1.0),
                                   secondary: RGB(1.0, 0.82, 0.3), accent: RGB(0.78, 0.9, 1.0),
                                   dark: RGB(0.04, 0.07, 0.18))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.halo(0.9, .secondary, life: 0.8, spin: 160, tex: .ringDouble), .follow, offset: [0, 1.0, 0]),
                .mesh(.decal(.hexShield, 2.0, .primary, life: 0.8, spin: 40, alpha: 0.7), .follow),
                .emit(.rising(12, radius: 0.5, .secondary, speed: 1.8, life: 0.8), .follow),
                .emit(.flare(1.0, .core, life: 0.18, tex: .flare4), .follow, offset: [0, 1.2, 0]),
            ]
            r.hit = []
        case .skill1:
            // 槌を叩きつけるのは 0.08 秒。衝撃波は同じ向きの扇に 3 回、半径が 0.45 → 0.75 → 1.0 倍と広がる（R = 扇の半径 3m）
            r.cast = [
                .emit(.flare(1.2, .core, life: 0.14), at: 0.06, offset: [0, 1.4, 0.7]),
            ]
            r.impact = [
                .mesh(.slash(R * 0.95, .secondary, from: 75, to: -75, height: 0.6, life: 0.28), at: 0.08, offset: [0, 0.6, 0]),
                .mesh(.decal(.crack, R * 1.2, .secondary, life: 1.6, spin: 0, grow: 1.0, alpha: 0.7), at: 0.12,
                      offset: [0, 0, R * 0.5]),
                // 1 回目（0.12 秒・射程の 0.7 倍）→ 2 回目（0.32・0.85 倍）→ 3 回目（0.52・1.0 倍）: 衝撃が前へ進む
                .emit(.flare(1.8, .core, life: 0.18, tex: .flare6), at: 0.12, offset: [0, 0.6, 1.0]),
                .mesh(.burstWall(R * 0.7, height: 1.0, .primary, life: 0.4), at: 0.12, offset: [0, 0, R * 0.4]),
                .emit(.wave(R * 0.7, .primary, life: 0.5), at: 0.12, offset: [0, 0.1, 0.8]),
                .mesh(.burstWall(R * 0.85, height: 1.2, .primary, life: 0.4), at: 0.32, offset: [0, 0, R * 0.5]),
                .emit(.wave(R * 0.85, .primary, life: 0.5), at: 0.32, offset: [0, 0.1, 0.8]),
                .mesh(.burstWall(R * 1.0, height: 1.4, .primary, life: 0.4), at: 0.52, offset: [0, 0, R * 0.6]),
                .emit(.wave(R * 1.0, .accent, life: 0.55), at: 0.52, offset: [0, 0.1, 0.8]),
                // 鈍足（深まる）の青い輪: 1 回目は淡く、3 回目は大きく
                .mesh(.shockRing(R * 0.7, .accent, life: 0.35), at: 0.12),
                .mesh(.shockRing(R * 0.85, .accent, life: 0.4), at: 0.32),
                .mesh(.shockRing(R * 1.0, .core, life: 0.45), at: 0.52),
                .emit(.debris(8, speed: 5), at: 0.12, offset: [0, 0.1, 1.2]),
                .emit(.debris(10, speed: 5), at: 0.52, offset: [0, 0.1, 1.6]),
                .shake(0.18, at: 0.12),
                .shake(0.22, at: 0.32),
                .shake(0.3, at: 0.52),
            ]
            // 3 回の衝撃波が 1 発ごとに当たる: 被弾演出は 1 発ごとの小さな火花だけ（輪は impact に移した）
            r.hit = [
                .emit(.sparks(5, speed: 4, .secondary, end: .primary), offset: [0, 1.0, 0]),
            ]
            r.hitPerHit = true
        case .skill2:
            // cast: 盾を構えて踏み込む金の尾（突進は約 0.25 秒）。再使用（stage 1）の演出は recipe(_:stage:_:) 側。
            // 突進（dashStrike）は impact を再生しないので、impact は書かない
            r.cast = [
                .emit(.bloom(1.4, .secondary, life: 0.3), offset: [0, 1.0, 0]),
                .emit(.trail(.glow, .secondary, rate: 60, life: 0.35, size: 0.6).with { $0.duration = 0.25 }, .follow,
                      offset: [0, 1.0, 0]),
                .mesh(FXMesh.ray(.streak, length: 3.6, width: 0.8, .secondary, life: 0.3), at: 0.02, offset: [0, 0.9, 1.9]),
                .emit(.smoke(6, radius: 0.5, life: 0.7, size: 0.6), quality: 1),
            ]
            // 突進に巻き込まれた敵: 衝撃と火花（押し運ばれる）
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
                .emit(.sparks(8, speed: 5, .secondary, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .ultimate:
            // 詠唱 0.8 秒の段: 0〜0.3 掲げて集める（cast）→ 0.3 引き寄せ（渦）→ 0.7 聖槌が落ちる → 0.8 崩落の衝撃
            // R は引き寄せの半径（5.2m）。粒子の大きさは 2.2m に抑える
            let P = min(R, 2.2)
            r.cast = [
                .emit(.gather(24, radius: 1.5, .secondary, life: 0.3), offset: [0, 2.2, 0.2]),
                .emit(.flare(2.0, .core, life: 0.22, tex: .flare6), at: 0.18, offset: [0, 2.4, 0.2]),
                .mesh(.decal(.runeCircle, R * 1.2, .secondary, life: 1.0, spin: 90, alpha: 0.7)),
            ]
            r.impact = [
                // 0.3 秒: 周囲の敵を引き寄せる青金の渦（外から内へ。0.38 秒かけて集める）
                .emit(.gather(40, radius: P * 1.4, .primary, life: 0.38), at: 0.3, offset: [0, 0.8, 0]),
                .mesh(.shockRing(R * 0.6, .accent, life: 0.4), at: 0.3),
                .mesh(.decal(.runeCircle, R * 0.9, .primary, life: 0.45, spin: -240, alpha: 0.6), at: 0.3),
                // 聖槌が落ちる（0.7）→ 崩落の衝撃（0.8）
                .mesh(.pillar(0.7, height: 6, .core, life: 0.45, alpha: 0.9), at: 0.68),
                .emit(.flare(3.0, .core, life: 0.3, tex: .flare6), at: 0.8, offset: [0, 1.0, 0]),
                .mesh(.burstWall(P * 0.9, height: 1.8, .accent, life: 0.5), at: 0.8),
                .mesh(.shockRing(R * 0.45, .core, life: 0.4), at: 0.8),
                .mesh(.shockRing(R * 0.8, .secondary, life: 0.7), at: 0.85),
                .emit(.wave(P * 1.4, .primary, life: 0.6), at: 0.8, offset: [0, 0.1, 0]),
                .emit(.debris(14, speed: 7), at: 0.8),
                .mesh(.decal(.crack, R * 0.8, .secondary, life: 1.4, spin: 0, grow: 1.0, alpha: 0.75), at: 0.8),
                .mesh(.decal(.runeCircle, R * 1.1, .secondary, life: 1.4, spin: -50, alpha: 0.7), at: 0.8),
                .mesh(.halo(P * 0.9, .secondary, life: 1.3, spin: 160, tex: .ringDouble), at: 0.85, offset: [0, 0.4, 0]),
                .shake(0.2, at: 0.3),
                .shake(0.6, at: 0.8),
            ]
            // hit は爆発の瞬間（気絶 1.8 秒）: 頭上の星の輪を 2 回
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.14), offset: [0, 1.0, 0]),
                .mesh(.halo(0.5, .accent, life: 1.0, spin: 240, tex: .ringDouble), .follow, offset: [0, 2.0, 0])
                    .repeated(2, every: 0.9),
                .emit(.flutter(.star, 6, radius: 0.4, .secondary, speed: 0.6, life: 1.0, size: 0.14), .follow,
                      offset: [0, 2.0, 0], quality: 1),
            ]
        }
        return r
    }

    /// 再使用（stage 1）: スキル2 の聖槌の叩きつけ。0.2 秒の振りかぶり（金の光が集まる）→ 前方の扇に聖槌が落ちる。
    /// 突進の尾（共通の cast）は出さない。被弾演出は打ち上げの輪つき（共通の hit は突進の火花だけ）。
    static func recipe(_ slot: SkillSlot, stage: Int, _ s: FXSkillInfo) -> SkillFXRecipe? {
        guard slot == .skill2, stage == 1 else { return nil }
        var r = SkillFXRecipe()
        // 振りかぶり: 槌を頭上へ振り上げて光が集まる
        r.cast = [
            .emit(.gather(14, radius: 1.0, .secondary, life: 0.2), offset: [0, 2.0, 0.4]),
            .emit(.flare(1.0, .core, life: 0.14), at: 0.1, offset: [0, 2.3, 0.3]),
        ]
        // 扇のアーキタイプなので発動と同時に再生される。叩きつけは振りかぶりのあと（0.2 秒）
        r.impact = [
            .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), at: 0.2, offset: [0, 1.0, 1.4]),
            .mesh(.pillar(0.6, height: 4.5, .secondary, life: 0.7), at: 0.2, offset: [0, 0, 1.8]),
            .mesh(.shockRing(2.0, .core, life: 0.4), at: 0.2, offset: [0, 0, 1.4]),
            .mesh(.shockRing(2.8, .primary, life: 0.6), at: 0.24, offset: [0, 0, 1.4]),
            .mesh(.decal(.crack, 3.4, .secondary, life: 1.1, spin: 0, grow: 1.0, alpha: 0.75), at: 0.2,
                  offset: [0, 0, 1.8]),
            .emit(.wave(2.8, .accent, life: 0.5), at: 0.2, offset: [0, 0.1, 1.2]),
            .emit(.debris(12, speed: 6), at: 0.2, offset: [0, 0, 1.6]),
            .shake(0.3, at: 0.2),
        ]
        r.hit = [
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 5, .secondary, end: .primary), offset: [0, 1.0, 0]),
            // 打ち上げ（0.8 秒）: 頭上に淡い輪
            .mesh(.halo(0.5, .accent, life: 0.8, spin: 240, tex: .ringDouble), .follow, offset: [0, 1.8, 0]),
        ]
        return r
    }

    /// 誓いを使い切った（無効化の発動が直後の）ときの金の盾の弾け。released は消費した誓いの数（4）。
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? {
        [
            .emit(.flare(1.8, .core, life: 0.2, tex: .flare6), .follow, offset: [0, 1.1, 0.4]),
            .mesh(.decal(.hexShield, 2.4, .secondary, life: 0.45, spin: 0, grow: 1.25, alpha: 0.85), .follow),
            .mesh(.halo(1.1, .secondary, life: 0.5, spin: 220, tex: .ringDouble), .follow, offset: [0, 1.0, 0]),
            .mesh(.shockRing(1.1, .accent, life: 0.4), .follow),
            .emit(.sparks(12, speed: 5, .secondary, end: .core), .follow, offset: [0, 1.0, 0]),
        ]
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 槌を頭上へ振りかぶり、叩きつける
            m.overhead(0.12)
            m.smash(0.06)
            m.hold(0.12)
        case .skill2:
            // 盾を構えて駆け、体ごとぶつかって槌を叩き込む
            m.dash(0.06, lean: 0.4)
            m.shieldBash(0.07)
            m.stomp(0.14)
            m.settle(0.1)
        case .ultimate:
            // 片膝をついて祈り → 槌を天へ掲げ（0.3 秒で引き寄せ）、地へ叩き落とす（0.8 秒の詠唱に合わせる）
            m.kneel(0.12)
            m.raise(0.18, glow: 2.0)
            m.hold(0.32) { $0.ring = 1.4; $0.glow = 2.4 }
            m.smash(0.08)
            m.hold(0.12)
        }
    }
}
