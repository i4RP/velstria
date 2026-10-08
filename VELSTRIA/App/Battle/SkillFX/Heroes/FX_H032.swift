import Foundation
import VelstriaCore

// スキル演出: H032 赤拳のディアス（Duelist / 刃付きの籠手（拳剣）・赤い気・包帯の腕。MLBB の Dyrroth の Velstria 版）。
// 主題: 赤い気の拳剣。白い芯 × 紅（主）× 朱（副）× 鉄の灰白（差し色）× 黒に近い暗赤（暗）。
// 重く短い斬線と、叩きつけた拳の衝撃、散る火の粉で見せる（竜槍のジャルド H027 の長い突きの線とは逆に、近い間合いの連打）。
// sim の実際の挙動（Systems/Kits/Kit_H032.swift）に合わせた演出:
//   パッシブ 紅血の拳          — 赤い気（レイジ）が腕に巻きつき、残り火が舞う（レイジ 50 以上でアビス強化）。
//                                通常攻撃 2 回に 1 回の円撃は専用のイベントが無いので、通常の攻撃の演出に任せる
//   S1 爆裂連撃（扇）          — 前方の扇へ 0.1 / 0.24 / 0.38 秒の 3 連の斬線（右→左→右）。鈍足の火の粉が残る
//                                アビス強化（SkillCastEvent.count = 5、射程 400）は 0.1 秒間隔の 5 連。Director が count を使うようになれば
//                                追加の斬線を足す（今はレシピが共通なので通常版の 3 連のまま）
//   S2 亡霊の歩み（突進 + 再使用） — 1 回目: 赤い尾を引いて突進し（約 0.17 秒）、最初に当たった敵を殴って軽く押し出す。
//                                2 回目（stage 1）: 敵ヒーローへ飛びかかって叩きつけ、防御ダウン（4 秒）の割れた紋を残す。
//                                どちらも「突進 → 着弾の拳」なので 1 つのレシピを共有する（Director は stage を見ない）
//   奥義 奈落の一撃（溜め + 直線）— 0.5 秒の溜め（足元に紋、赤い気が拳に集まる）→ 前方 4.2 m の直線に重い一撃。
//                                終端に裂け目、当たった敵は炎の枷で鈍る（減速 0.8 秒）。スタンでは止まらない（演出も途切れさせない）

enum FX_H032: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.94, 0.9), primary: RGB(0.92, 0.12, 0.1),
                                   secondary: RGB(1.0, 0.45, 0.25), accent: RGB(0.72, 0.76, 0.85),
                                   dark: RGB(0.1, 0.01, 0.02))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.halo(0.9, .primary, life: 0.8, spin: 260, tex: .ringDouble), .follow, offset: [0, 0.9, 0]),
                .mesh(.decal(.claw, 2.0, .primary, life: 0.8, spin: 90, alpha: 0.7), .follow),
                .emit(.embers(14, radius: 0.5, .secondary, life: 1.0), .follow),
                .emit(.flare(0.9, .secondary, life: 0.16), .follow, offset: [0.4, 1.1, 0.4]),
            ]
            r.hit = []
        case .skill1:
            // 構え（0.06）→ 3 連の衝撃: 右から左（0.1）、返して左から右（0.24）、もう一度右から左（0.38）。後ろの撃ほど斬線が細く短い
            // （同じ敵への 2 発目以降は威力が落ちる）
            r.cast = [
                .emit(.flare(1.0, .core, life: 0.12), at: 0.06, offset: [0.3, 1.0, 0.8]),
            ]
            r.impact = [
                .mesh(.slash(R * 0.95, .core, from: 80, to: -80, height: 1.0, tilt: -12, life: 0.2, tex: .slashThin), at: 0.1,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 1.0, .primary, from: 80, to: -80, height: 1.05, tilt: -12, life: 0.3), at: 0.1,
                      offset: [0, 1.05, 0]),
                .mesh(.slash(R * 0.9, .secondary, from: -75, to: 75, height: 1.1, tilt: 14, life: 0.26, tex: .slashThin), at: 0.24,
                      offset: [0, 1.1, 0]),
                .mesh(.slash(R * 0.9, .primary, from: -75, to: 75, height: 1.1, tilt: 14, life: 0.26), at: 0.24,
                      offset: [0, 1.1, 0]),
                .mesh(.slash(R * 0.8, .core, from: 70, to: -70, height: 1.0, tilt: -8, life: 0.2, tex: .slashThin), at: 0.38,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.85, .secondary, from: 70, to: -70, height: 1.0, tilt: -8, life: 0.24), at: 0.38,
                      offset: [0, 1.0, 0]),
                .mesh(.decal(.claw, R * 1.8, .primary, life: 0.9, spin: 0, grow: 1.0, alpha: 0.75), at: 0.11,
                      offset: [0, 0, R * 0.5]),
                .emit(.fan(16, .secondary, speed: R * 4, spread: 30, life: 0.35), at: 0.11, offset: [0, 1.0, 0.4]),
                .emit(.flare(1.3, .core, life: 0.16), at: 0.11, offset: [0, 1.0, R * 0.5]),
                .emit(.sparks(10, speed: 6, .accent, end: .primary), at: 0.26, offset: [0, 1.0, R * 0.7]),
                .emit(.sparks(8, speed: 5, .secondary, end: .primary), at: 0.4, offset: [0, 1.0, R * 0.8]),
            ]
            r.hit = [
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.1, 0]),
                .emit(.sparks(8, speed: 5, .secondary, end: .primary), offset: [0, 1.0, 0]),
                // 鈍足（1.5 秒）: 足元の赤い輪
                .mesh(.halo(0.5, .primary, life: 1.2, spin: 100, tex: .ring), .follow, offset: [0, 0.15, 0]),
            ]
        case .skill2:
            // 赤い尾を引いて駆け（約 0.17 秒）、到着の瞬間に拳を叩きつける。impact は対象の足元で再生される
            r.cast = [
                .emit(.bloom(1.3, .primary, life: 0.3), offset: [0, 1.0, 0]),
                .emit(.trail(.streak, .secondary, rate: 80, life: 0.3, size: 0.5).with {
                    $0.duration = 0.3; $0.stretch = 3; $0.dir = .backward; $0.speed = 3
                }, .follow, offset: [0, 1.0, 0]),
                .emit(.smoke(6, radius: 0.5, life: 0.7, size: 0.6), quality: 1),
            ]
            r.impact = [
                .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), at: 0.17, offset: [0, 1.0, 0.3]),
                .mesh(.burstWall(R * 0.7, height: 1.5, .primary, life: 0.4), at: 0.2),
                .mesh(.shockRing(R * 1.3, .core, life: 0.4), at: 0.2),
                .mesh(.shockRing(R * 1.8, .secondary, life: 0.6), at: 0.24),
                .mesh(.decal(.crack, R * 2.3, .primary, life: 1.1, spin: 0, grow: 1.0, alpha: 0.8), at: 0.2),
                .emit(.wave(R * 1.4, .secondary, life: 0.5), at: 0.2, offset: [0, 0.1, 0]),
                .emit(.debris(12, speed: 6), at: 0.2),
                .emit(.sparks(18, speed: 7, .accent, end: .primary), at: 0.2, offset: [0, 0.6, 0]),
                // 防御ダウン: 割れた鎧の破片が散る
                .emit(.flutter(.shard, 10, radius: 0.5, .accent, speed: 3.5, life: 0.7, size: 0.14), at: 0.2, offset: [0, 1.0, 0]),
                .shake(0.3, at: 0.2),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
                // 防御ダウン 4 秒: 足元に割れた紋
                .mesh(.decal(.crack, 1.5, .accent, life: 3.6, spin: 0, grow: 1.0, alpha: 0.6)),
                .emit(.rising(8, radius: 0.4, .secondary, speed: 3, life: 0.5), quality: 1),
            ]
        case .ultimate:
            // 溜め（0〜0.5 秒）: 足元に紋、赤い気が拳に集まる → 0.5 秒で前方 4.2 m の直線に重い一撃。終端（impact）に裂け目
            let L = max(s.range, 4.2)
            r.cast = [
                .emit(.gather(22, radius: 1.3, .primary, life: 0.4), offset: [0.3, 1.0, 0.5]),
                .mesh(.decal(.runeCircle, 3.2, .primary, life: 0.7, spin: 180, alpha: 0.7)),
                .mesh(.halo(0.9, .secondary, life: 0.7, spin: 360, tex: .ringDouble), .follow, offset: [0, 1.0, 0]),
                .emit(.embers(20, radius: 1.0, .secondary, life: 1.0), .follow),
                .emit(.flare(1.6, .secondary, life: 0.2, tex: .flare6), at: 0.3, offset: [0.3, 1.0, 0.5]),
                // 0.5 秒: 一撃。地を這う太い斬線と、前方へ走る衝撃の壁
                .mesh(.ray(.streak, length: L, width: 1.1, .core, life: 0.3, alpha: 0.95), at: 0.5, offset: [0, 0.9, L / 2 + 0.3]),
                .mesh(.ray(.streak, length: L, width: 2.4, .primary, life: 0.5, alpha: 0.65), at: 0.5, offset: [0, 0.8, L / 2 + 0.3]),
                .mesh(.burstWall(1.2, height: 1.6, .primary, life: 0.4), at: 0.5, offset: [0, 0, 1.2]),
                .mesh(.burstWall(1.2, height: 1.6, .secondary, life: 0.4), at: 0.55, offset: [0, 0, L * 0.6]),
                .mesh(.slash(2.2, .core, from: 85, to: -85, height: 1.0, tilt: -18, life: 0.22, tex: .slashThin), at: 0.5,
                      offset: [0, 1.0, 0.4]),
                .emit(.fan(26, .secondary, speed: 12, spread: 14, life: 0.35), at: 0.5, offset: [0, 1.0, 0.6]),
                .shake(0.35, at: 0.5),
            ]
            r.impact = [
                .emit(.flare(2.4, .core, life: 0.24, tex: .flare6), at: 0.5, offset: [0, 0.8, 0]),
                .mesh(.decal(.crack, 3.4, .primary, life: 1.3, spin: 0, grow: 1.0, alpha: 0.85), at: 0.5),
                .mesh(.shockRing(2.2, .core, life: 0.4), at: 0.5),
                .mesh(.shockRing(3.0, .secondary, life: 0.6), at: 0.55),
                .mesh(.pillar(0.5, height: 3.6, .primary, life: 0.45), at: 0.5),
                .emit(.sparks(24, speed: 9, .accent, end: .primary), at: 0.5, offset: [0, 0.8, 0]),
                .emit(.debris(12, speed: 6), at: 0.5),
                .shake(0.45, at: 0.5),
            ]
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.14), offset: [0, 1.0, 0]),
                // 減速（0.8 秒）の炎の枷
                .mesh(.halo(0.6, .primary, life: 0.9, spin: 120, tex: .ring), .follow, offset: [0, 0.15, 0]),
                .emit(.sparks(10, speed: 6, .accent, end: .primary), offset: [0, 1.0, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 右から大きく薙ぎ、返す刃、もう一度薙ぐ（0.1 / 0.24 / 0.38 秒の 3 連の衝撃に合わせる）
            m.windup(0.08, side: 1, power: 1.1)
            m.slash(0.06, side: 1, power: 1.2)
            m.slash(0.07, side: -1, power: 1.0)
            m.slash(0.07, side: 1, power: 1.0)
            m.hold(0.1)
        case .skill2:
            // 前傾で駆け、踏み込んで拳を叩きつける（1 回目は突進の殴り、2 回目は飛びかかりの叩きつけ）
            m.dash(0.06, lean: 0.5)
            m.lunge(0.06, distance: 0.5, lean: 0.3)
            m.smash(0.05)
            m.land(0.06, depth: 0.26)
            m.settle(0.1)
        case .ultimate:
            // 腰を落として拳に気を溜め（0.5 秒）、振り抜く一撃で締める
            m.brace(0.06, depth: 0.2)
            m.hold(0.3) { $0.glow = 2.0; $0.ring = 1.2 }
            m.windup(0.12, side: 1, power: 1.3)
            m.slash(0.06, side: -1, power: 1.4)
            m.thrust(0.05)
            m.hold(0.12) { $0.glow = 2.0 }
        }
    }
}
