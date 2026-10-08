import Foundation
import VelstriaCore

// スキル演出: H029 聖槌のボルグ（Support / 巨大な聖槌・円盾・青と金の重装。MLBB の Tigreal の Velstria 版）。
// 主題: 青金の聖槌。白金の芯 × 青（主）× 金（副）× 淡い青白（差し色）。重く、堅く、叩きつけた衝撃が大地を走る。
// sim の実際の挙動（Systems/Kits/Kit_H029.swift）に合わせた演出:
//   パッシブ 聖鎚の誓い       — 金の光輪と青い盾の紋が身を包み、誓いの光が昇る（4 つたまると次の通常攻撃を無効化する）
//   S1 Borg式・一閃          — 前方の扇に衝撃波が 3 回（0.12 / 0.32 / 0.52 秒）。回ごとに地が割れ、衝撃が大きくなる。
//                              鈍足は命中ごとに深まる（20 → 40 → 60%）= 3 回目に青い足枷の輪
//   S2 聖槌の踏み込み        — 1 回目: 盾を構えて突進（約 0.25 秒）して通り道の敵を終点まで押し運ぶ（cast の金の尾）。
//                              再使用（0.2 秒の振りかぶり後）: 前方の扇に聖槌を叩きつけ、光の柱が立つ（impact）。打ち上げ 0.8 秒
//   奥義 崩落聖域（Implosion）— 詠唱 0.7 秒。0〜0.2 秒は聖槌を掲げて光が集まる（CC で中断できる）、0.2 秒で青金の渦が敵を引き寄せ、
//                              0.7 秒で聖槌が落ちて崩落の衝撃 + 気絶（1.8 秒）の星の輪
// SkillFXDirector はまだ stage / count / duration を読まない: S2 は「cast = 突進の構え」「impact = 再使用の叩きつけ」
// （impact は扇のアーキタイプ = 再使用の発動だけで再生される）、奥義の段は at で表す。

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
            // 槌を叩きつけるのは 0.08 秒。衝撃波は同じ扇に 3 回（R = 扇の半径 3m）
            r.cast = [
                .emit(.flare(1.2, .core, life: 0.14), at: 0.06, offset: [0, 1.4, 0.7]),
            ]
            r.impact = [
                .mesh(.slash(R * 0.95, .secondary, from: 75, to: -75, height: 0.6, life: 0.28), at: 0.08, offset: [0, 0.6, 0]),
                .mesh(.decal(.crack, R * 1.2, .secondary, life: 1.6, spin: 0, grow: 1.0, alpha: 0.7), at: 0.12,
                      offset: [0, 0, R * 0.5]),
                // 1 回目（0.12 秒）→ 2 回目（0.32）→ 3 回目（0.52）: 衝撃が回ごとに大きくなる
                .emit(.flare(1.8, .core, life: 0.18, tex: .flare6), at: 0.12, offset: [0, 0.6, 1.0]),
                .mesh(.burstWall(R * 0.45, height: 1.0, .primary, life: 0.4), at: 0.12, offset: [0, 0, R * 0.5]),
                .emit(.wave(R * 0.6, .primary, life: 0.5), at: 0.12, offset: [0, 0.1, 0.8]),
                .mesh(.burstWall(R * 0.6, height: 1.2, .primary, life: 0.4), at: 0.32, offset: [0, 0, R * 0.5]),
                .emit(.wave(R * 0.8, .primary, life: 0.5), at: 0.32, offset: [0, 0.1, 0.8]),
                .mesh(.burstWall(R * 0.75, height: 1.4, .primary, life: 0.4), at: 0.52, offset: [0, 0, R * 0.5]),
                .emit(.wave(R * 1.0, .accent, life: 0.55), at: 0.52, offset: [0, 0.1, 0.8]),
                // 鈍足（深まる）の青い輪: 1 回目は淡く、3 回目は大きく
                .mesh(.shockRing(R * 0.6, .accent, life: 0.35), at: 0.12),
                .mesh(.shockRing(R * 0.85, .accent, life: 0.4), at: 0.32),
                .mesh(.shockRing(R * 1.1, .core, life: 0.45), at: 0.52),
                .emit(.debris(8, speed: 5), at: 0.12, offset: [0, 0.1, 1.2]),
                .emit(.debris(10, speed: 5), at: 0.52, offset: [0, 0.1, 1.6]),
                .shake(0.18, at: 0.12),
                .shake(0.22, at: 0.32),
                .shake(0.3, at: 0.52),
            ]
            r.hit = [
                .emit(.sparks(8, speed: 5, .secondary, end: .primary), offset: [0, 1.0, 0]),
                .mesh(.halo(0.6, .primary, life: 0.8, spin: 120, tex: .ring), .follow, offset: [0, 0.15, 0]),
            ]
        case .skill2:
            // cast: 盾を構えて踏み込む金の尾（突進は約 0.25 秒）。再使用の発動でも振りかぶりの光として再生される
            r.cast = [
                .emit(.bloom(1.4, .secondary, life: 0.3), offset: [0, 1.0, 0]),
                .emit(.trail(.glow, .secondary, rate: 60, life: 0.35, size: 0.6).with { $0.duration = 0.25 }, .follow,
                      offset: [0, 1.0, 0]),
                .mesh(FXMesh.ray(.streak, length: 3.6, width: 0.8, .secondary, life: 0.3), at: 0.02, offset: [0, 0.9, 1.9]),
                .emit(.smoke(6, radius: 0.5, life: 0.7, size: 0.6), quality: 1),
            ]
            // impact（再使用）: 0.2 秒の振りかぶりのあと、前方の扇に聖槌を叩きつけて光の柱。打ち上げ
            r.impact = [
                .emit(.gather(14, radius: 1.0, .secondary, life: 0.18), offset: [0, 2.0, 0.4]),
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
        case .ultimate:
            // 詠唱 0.7 秒の段: 0〜0.2 掲げて集める（cast）→ 0.2 引き寄せ（渦）→ 0.55 聖槌が落ちる → 0.7 崩落の衝撃
            // R は引き寄せの半径（4.2m）。粒子の大きさは 2.2m に抑える
            let P = min(R, 2.2)
            r.cast = [
                .emit(.gather(24, radius: 1.5, .secondary, life: 0.25), offset: [0, 2.2, 0.2]),
                .emit(.flare(2.0, .core, life: 0.22, tex: .flare6), at: 0.12, offset: [0, 2.4, 0.2]),
                .mesh(.decal(.runeCircle, R * 1.6, .secondary, life: 0.9, spin: 90, alpha: 0.7)),
            ]
            r.impact = [
                // 0.2 秒: 周囲の敵を引き寄せる青金の渦（外から内へ）
                .emit(.gather(40, radius: P * 1.4, .primary, life: 0.4), at: 0.2, offset: [0, 0.8, 0]),
                .mesh(.shockRing(R * 0.9, .accent, life: 0.4), at: 0.2),
                .mesh(.decal(.runeCircle, R * 1.2, .primary, life: 0.5, spin: -240, alpha: 0.6), at: 0.2),
                // 聖槌が落ちる（0.55）→ 崩落の衝撃（0.7）
                .mesh(.pillar(0.7, height: 6, .core, life: 0.45, alpha: 0.9), at: 0.5),
                .emit(.flare(3.0, .core, life: 0.3, tex: .flare6), at: 0.7, offset: [0, 1.0, 0]),
                .mesh(.burstWall(P * 0.9, height: 1.8, .accent, life: 0.5), at: 0.7),
                .mesh(.shockRing(R * 0.5, .core, life: 0.4), at: 0.7),
                .mesh(.shockRing(R * 0.9, .secondary, life: 0.7), at: 0.75),
                .emit(.wave(P * 1.4, .primary, life: 0.6), at: 0.7, offset: [0, 0.1, 0]),
                .emit(.debris(14, speed: 7), at: 0.7),
                .mesh(.decal(.crack, R * 1.0, .secondary, life: 1.4, spin: 0, grow: 1.0, alpha: 0.75), at: 0.7),
                .mesh(.decal(.runeCircle, R * 1.4, .secondary, life: 1.4, spin: -50, alpha: 0.7), at: 0.7),
                .mesh(.halo(P * 0.9, .secondary, life: 1.3, spin: 160, tex: .ringDouble), at: 0.75, offset: [0, 0.4, 0]),
                .shake(0.2, at: 0.2),
                .shake(0.6, at: 0.7),
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
            // 片膝をついて祈り → 槌を天へ掲げ（引き寄せ）、地へ叩き落とす（0.7 秒の詠唱に合わせる）
            m.kneel(0.12)
            m.raise(0.16, glow: 2.0)
            m.hold(0.26) { $0.ring = 1.4; $0.glow = 2.4 }
            m.smash(0.07)
            m.hold(0.12)
        }
    }
}
