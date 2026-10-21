import Foundation
import QuartzCore
import UIKit
import VelstriaCore

// 担当: battle-renderer。戦闘の手応え（全ヒーロー共通。描画だけ。判定・数値・sim・リプレイ・オンラインの同期は変えない）。
// - ヒットストップ: 自分が撃った・受けた重い命中で、描画の時間（アニメーション・スキル演出・Effekseer・戦闘数値）を
//   格で 40〜90 ms 止める。キットの強い通常攻撃（三連突き・円撃。SimEvent.empoweredAttack）も軽く 40 ms。位置・カメラ・入力・sim は進める（再開した時に位置が跳ばない）。
// - 奥義: 自分が撃った・受けた奥義で、一瞬の画面の閃光と放射状のぼかし（後処理。低画質は後処理ごと無いので出ない）と
//   カメラの押し込み。ほかの人の近くの奥義は弱い閃光だけ。「視差効果を減らす」の設定ではぼかし・押し込みを出さない。
// 観戦・リプレイ・シーク・一時停止・読み込み中は何もしない（呼び出し側が enabled で渡す）。
// 状態は 1 つ（止める区間・次に止めてよい時刻・奥義の受けの間隔）だけ。ユニットごとのタイマーは持たない。

@MainActor
final class BattleFeel {
    /// 1 フレームの指示。
    struct Frame {
        /// 描画の時間を止める（このフレームの同期を dt = 0 で行う）。
        var hold = false
        var pulse: PostProcessor.ScreenPulse?
        /// カメラの押し込み（m）。
        var pushIn: Float?
    }

    /// 止めた区間（CACurrentMediaTime）。
    private(set) var holdUntil: Double = 0
    private var holdStart: Double = 0
    private var nextHold: Double = 0
    private var nextUltHitPulse: Double = 0

    /// 1 回の止めの上限（秒。重なっても延ばすのはここまで）。
    nonisolated static let maxHold: Double = 0.09
    /// 止めた後、次に止めてよいまでの間（秒。多段の命中で描画がかくつき続けないように）。
    nonisolated static let holdGap: Double = 0.12
    /// 奥義を受けた時の脈の間隔（秒。多段の奥義で何度も光らせない）。
    nonisolated static let ultHitGap: Double = 0.6
    /// ほかの人の奥義で弱く光らせる距離（sim の単位。14 m）。
    nonisolated static let nearbyUltRange: Double = 1400

    func isHolding(now: Double) -> Bool { now < holdUntil }

    /// 止める長さ（秒。nil = 止めない）。自分が撃った・受けた命中で、相手が英雄か練習場の人形の時だけ（ミニオン・モンスターの狩りでは止めない）。
    /// 格: 倒した一撃・自分の奥義 90 ms、受けた奥義 70 ms、自分の S1/S2 55 ms、受けた S1/S2・自分の会心の通常攻撃 40 ms。
    nonisolated static func holdSeconds(source: DamageSource, isCrit: Bool, byMe: Bool, onMe: Bool,
                                        targetIsHero: Bool, killed: Bool) -> Double? {
        guard targetIsHero, byMe || onMe else { return nil }
        if byMe, killed { return 0.09 }
        switch source {
        case .skill(.ultimate): return byMe ? 0.09 : 0.07
        case .skill(.skill1), .skill(.skill2): return byMe ? 0.055 : 0.04
        case .basicAttack: return byMe && isCrit ? 0.04 : nil
        default: return nil
        }
    }

    /// キットの強い通常攻撃（三連突き・円撃）の止め（秒。nil = 止めない）。自分が撃った・受けた強い通常攻撃で、相手が英雄か
    /// 練習場の人形の時だけ（ミニオン・モンスターの狩りでは止めない。会心の通常攻撃と同じ軽い格）。
    nonisolated static let empoweredHold: Double = 0.04

    nonisolated static func empoweredHoldSeconds(byMe: Bool, onMe: Bool, targetIsHero: Bool) -> Double? {
        guard targetIsHero, byMe || onMe else { return nil }
        return empoweredHold
    }

    func reset() {
        holdUntil = 0
        nextHold = 0
        nextUltHitPulse = 0
    }

    /// 1 フレーム分。このフレームで同期するイベントを見て、止めるか・脈・押し込みを決める。
    func frame(events: [SimEvent], controller: BattleController, now: Double, enabled: Bool) -> Frame {
        var out = Frame()
        guard enabled, let me = controller.humanHeroID else {
            holdUntil = 0
            return out
        }
        let s = controller.state
        var hold: Double = 0
        for e in events {
            switch e {
            case .damage(let d):
                let byMe = d.sourceID == me, onMe = d.targetID == me
                guard byMe || onMe else { continue }
                let target = s.unit(d.targetID)
                let isHero = target.map { $0.kind == .hero || $0.kind == .dummy } ?? false
                let killed = target.map { !$0.isAlive } ?? false
                if let h = BattleFeel.holdSeconds(source: d.source, isCrit: d.isCrit, byMe: byMe, onMe: onMe,
                                                  targetIsHero: isHero, killed: killed) {
                    hold = max(hold, h)
                }
                if onMe, case .skill(.ultimate) = d.source, now >= nextUltHitPulse,
                   let heroID = s.unit(d.sourceID)?.hero?.heroID {
                    nextUltHitPulse = now + BattleFeel.ultHitGap
                    out.pulse = BattleFeel.stronger(out.pulse, BattleFeel.pulse(heroID: heroID, flash: 0.16, blur: 0.28, now: now))
                    out.pushIn = max(out.pushIn ?? 0, 0.5)
                }
            case .empoweredAttack(let e):
                let target = s.unit(e.targetID)
                let isHero = target.map { $0.kind == .hero || $0.kind == .dummy } ?? false
                // 円撃は周りも巻き込む: 主対象でなくても円の中に居れば受けた側
                var onMe = e.targetID == me
                if !onMe, e.radius > 0, let mine = s.unit(me), let caster = s.unit(e.sourceID), mine.team != caster.team {
                    onMe = mine.pos.distance(to: e.origin) <= e.radius + mine.radius
                }
                if let h = BattleFeel.empoweredHoldSeconds(byMe: e.sourceID == me, onMe: onMe, targetIsHero: isHero || onMe) {
                    hold = max(hold, h)
                }
            case .skillCast(let c) where c.slot == .ultimate:
                if c.casterID == me {
                    out.pulse = BattleFeel.stronger(out.pulse, BattleFeel.pulse(heroID: c.heroID, flash: 0.28, blur: 0.5, now: now))
                    out.pushIn = max(out.pushIn ?? 0, 1.1)
                } else if let mine = s.unit(me), mine.pos.distance(to: c.origin) < BattleFeel.nearbyUltRange {
                    out.pulse = BattleFeel.stronger(out.pulse, BattleFeel.pulse(heroID: c.heroID, flash: 0.07, blur: 0, now: now))
                }
            default:
                break
            }
        }
        if hold > 0 {
            if now >= nextHold {
                holdStart = now
                holdUntil = now + hold
                nextHold = holdUntil + BattleFeel.holdGap
            } else if now < holdUntil {
                holdUntil = min(max(holdUntil, now + hold), holdStart + BattleFeel.maxHold)
            }
        }
        if UIAccessibility.isReduceMotionEnabled {
            out.pushIn = nil
            if var p = out.pulse {
                p.blur = 0
                out.pulse = p
            }
        }
        out.hold = now < holdUntil
        return out
    }

    /// 奥義の脈（色はそのヒーローの主色を白へ寄せたもの。中心は自分のヒーロー = 画面の中央のやや下）。
    static func pulse(heroID: String, flash: Float, blur: Float, now: Double) -> PostProcessor.ScreenPulse {
        let c = SkillFXCatalog.palette(heroID).primary.mixed(RGB(1, 1, 1), 0.45)
        return PostProcessor.ScreenPulse(color: SIMD3(Float(c.r), Float(c.g), Float(c.b)), flash: flash, blur: blur,
                                         center: [0.5, 0.56], start: now)
    }

    nonisolated static func stronger(_ a: PostProcessor.ScreenPulse?, _ b: PostProcessor.ScreenPulse) -> PostProcessor.ScreenPulse {
        guard let a else { return b }
        return b.flash + b.blur > a.flash + a.blur ? b : a
    }
}
