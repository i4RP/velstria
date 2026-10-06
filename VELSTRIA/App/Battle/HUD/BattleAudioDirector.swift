import SwiftUI
import VelstriaCore

// 担当: battle-hud。戦闘の効果音と触覚。SimEvent を購読し、人間プレイヤーに関係する出来事だけを鳴らす。
// - 自分の攻撃・命中・クリティカル、カメラ付近のスキル発動、キル/デス、レベルアップ、Gold、帰還、復活、告知、塔破壊、勝敗
// - 触覚: 大きな被弾、キル、レベルアップ、死亡
// 観戦者（AI 同士の観戦・リプレイ・オンラインの観戦席）:
// - 追従中のユニットが音の主役（その攻撃・命中・スキル・回復・レベルアップ・帰還・復活を少し控えめに鳴らす）。
// - 触覚は出さない（画面に触れずに見ているので、告知のたびに震えない）。終了は勝敗ではなく中立の締めの音。
// - 2 倍速を超えると主要でない音（攻撃・命中・スキル・Gold など）を弱め、4 倍速を超えると鳴らさない。
// シーク・再同期（presentationEpoch の変化）の直後は短い間すべて鳴らさない（追いつきの連続イベントで音が溢れない）。
// 同じ音の連打は AudioService が間引く。ここでは他ユニットのスキル音と被弾の触覚を追加で間引く。

@MainActor
final class BattleAudioDirector {
    /// 1 つのイベントから決まる出力（純粋関数の戻り値。単体テスト対象）。
    enum Cue: Equatable {
        case sound(SFX, gain: Double)
        case haptic(Haptic)
    }

    enum Haptic: Equatable {
        case hitHard(intensity: Double)
        case kill
        case death
        case levelUp
        /// 重要な告知（ファーストブラッド・マルチキル・塔・オブジェクトなど）。
        case announcement
        case victory
        case defeat
    }

    struct Context {
        var humanID: EntityID?
        var humanTeam: Team?
        var humanMaxHP: Double
        /// カメラの中心（距離減衰の基準）。
        var listener: Vec2
        var isSpectating: Bool
        /// 観戦者の音の主役（追従中のユニット）。プレイヤーは nil（自分 = humanID が主役）。
        var focusID: EntityID? = nil
        /// 再生速度（観戦・リプレイ。プレイヤー・オンラインは 1）。
        var speed: Double = 1
        /// シーク・再同期の直後（終了の音以外は鳴らさない）。
        var suppressed = false
    }

    /// カメラからこの距離以内のスキル発動を鳴らす。
    nonisolated static let hearingRadius: Double = 1700
    /// 1 回でこの割合以上の被弾で触覚。
    nonisolated static let hardHitRatio: Double = 0.09
    /// この速度を超えると主要でない音を弱める（さらに dropAboveSpeed を超えると鳴らさない）。
    nonisolated static let dampenAboveSpeed: Double = 2
    nonisolated static let dropAboveSpeed: Double = 4
    /// 弱める時の倍率。
    nonisolated static let dampenedGain: Double = 0.45
    /// シーク・再同期の後に音を止める時間（秒）。
    nonisolated static let suppressAfterDiscontinuity: TimeInterval = 0.4

    private weak var controller: BattleController?
    private weak var app: AppModel?
    private var token: UUID?
    private var lastOtherSkill: TimeInterval = 0
    private var lastHardHit: TimeInterval = 0
    /// 最後に見た presentationEpoch と、変化に気付いてから音を止める期限（systemUptime）。
    private var seenEpoch: Int?
    private var suppressUntil: TimeInterval = 0

    init(controller: BattleController, app: AppModel) {
        self.controller = controller
        self.app = app
    }

    func start() {
        guard token == nil, let controller else { return }
        token = controller.subscribe { [weak self] events in
            self?.handle(events)
        }
        app?.haptics.prepareAll()
    }

    func stop() {
        if let token, let controller { controller.unsubscribe(token) }
        token = nil
    }

    private func handle(_ events: [SimEvent]) {
        guard let controller, let app else { return }
        let s = controller.sim.state
        let humanIndex = controller.humanIndex
        var ctx = Context(humanID: controller.humanHeroID, humanTeam: controller.localTeam,
                          humanMaxHP: humanIndex.map { s.units[$0].stats.maxHP } ?? 1,
                          listener: humanIndex.map { s.units[$0].pos } ?? Balance.mapCenter,
                          isSpectating: controller.isSpectating)
        switch controller.cameraMode {
        case .free(let p): ctx.listener = p
        case .followUnit(let id): if let u = s.unit(id) { ctx.listener = u.pos }
        case .framing(let ids): if let u = ids.first.flatMap({ s.unit($0) }) { ctx.listener = u.pos }
        case .followHero: break
        }
        let now = ProcessInfo.processInfo.systemUptime
        if controller.isSpectating { ctx.focusID = controller.presentationFocusID }
        ctx.speed = controller.isOnline ? 1 : controller.speed
        ctx.suppressed = noteDiscontinuity(epoch: controller.presentationEpoch, now: now)
        for e in events {
            for cue in Self.cues(for: e, context: ctx) {
                switch cue {
                case .sound(let sfx, let gain):
                    if case .skillCast(let c) = e, c.casterID != ctx.humanID, c.casterID != ctx.focusID {
                        guard now - lastOtherSkill > 0.18 else { continue }
                        lastOtherSkill = now
                    }
                    app.audio.play(sfx, gain: gain)
                case .haptic(let h):
                    play(h, app: app, now: now)
                }
            }
        }
    }

    private func play(_ h: Haptic, app: AppModel, now: TimeInterval) {
        switch h {
        case .hitHard(let intensity):
            guard now - lastHardHit > 0.35 else { return }
            lastHardHit = now
            app.haptics.impact(.heavy, intensity: intensity)
        case .kill: app.haptics.success()
        case .death: app.haptics.impact(.heavy, intensity: 1)
        case .levelUp: app.haptics.impact(.light, intensity: 0.8)
        case .announcement: app.haptics.impact(.medium, intensity: 0.6)
        case .victory: app.haptics.success()
        case .defeat: app.haptics.error()
        }
    }

    /// presentationEpoch の変化に気付いたら、そこから短い間は音を止める（シーク・再同期の後の追いつきで溢れない）。
    /// 戻り値 = 今は止める時間内か。
    private func noteDiscontinuity(epoch: Int, now: TimeInterval) -> Bool {
        if let seen = seenEpoch, seen != epoch { suppressUntil = now + Self.suppressAfterDiscontinuity }
        seenEpoch = epoch
        return now < suppressUntil
    }

    /// イベント → 音・触覚（副作用なし）。プレイヤー / 観戦者の振り分けの後、再生速度とシーク直後の抑制をかける。
    nonisolated static func cues(for event: SimEvent, context c: Context) -> [Cue] {
        let raw = c.isSpectating ? spectatorCues(for: event, context: c) : playerCues(for: event, context: c)
        // 終了の音（勝敗・観戦の締め）はシーク直後・早送りでもそのまま鳴らす
        if case .matchEnded = event { return raw }
        return adjusted(raw, context: c)
    }

    /// 早送りでも残す音（試合の流れが分かる大きな出来事）。それ以外（攻撃・命中・スキル・Gold・回復など）は主要でない。
    nonisolated static func isEssential(_ sfx: SFX) -> Bool {
        switch sfx {
        case .kill, .death, .multiKill, .towerDestroyed, .objective, .announcement, .victory, .defeat: return true
        default: return false
        }
    }

    /// 再生速度とシーク直後の抑制（終了の音以外）。
    nonisolated static func adjusted(_ cues: [Cue], context c: Context) -> [Cue] {
        if c.suppressed { return [] }
        guard c.speed > dampenAboveSpeed else { return cues }
        return cues.compactMap { cue in
            guard case .sound(let sfx, let gain) = cue, !isEssential(sfx) else { return cue }
            return c.speed > dropAboveSpeed ? nil : .sound(sfx, gain: gain * dampenedGain)
        }
    }

    /// 観戦者: 追従中のユニット（focusID）が主役。触覚なし、購入などの操作の音なし、終了は中立の締めの音。
    nonisolated static func spectatorCues(for event: SimEvent, context c: Context) -> [Cue] {
        let focus = c.focusID
        switch event {
        case .attackReleased(let source, _, let ranged):
            guard source == focus else { return [] }
            return [.sound(ranged ? .attackRanged : .attackMelee, gain: 0.4)]
        case .damage(let d):
            guard d.sourceID == focus, focus != nil, d.source == .basicAttack else { return [] }
            return [.sound(d.isCrit ? .crit : .hit, gain: d.isCrit ? 0.7 : 0.4)]
        case .skillCast(let cast):
            if cast.casterID == focus {
                return [.sound(cast.slot == .ultimate ? .ultimateCast : .skillCast, gain: 0.85)]
            }
            let d = cast.origin.distance(to: c.listener)
            guard d < hearingRadius else { return [] }
            let gain = 0.5 * (1 - d / hearingRadius)
            return gain > 0.05 ? [.sound(cast.slot == .ultimate ? .ultimateCast : .skillCast, gain: gain)] : []
        case .spellCast(let caster, _, _, _):
            return caster == focus ? [.sound(.skillCast, gain: 0.6)] : []
        case .heal(let target, _, let amount):
            return target == focus && amount >= 40 ? [.sound(.heal, gain: 0.45)] : []
        case .shieldGained(let target, _, _):
            return target == focus ? [.sound(.shield, gain: 0.5)] : []
        case .heroKilled(let k):
            if let focus {
                if k.killerID == focus { return [.sound(.kill, gain: 0.85)] }
                if k.victimID == focus { return [.sound(.death, gain: 0.75)] }
            }
            return [.sound(.kill, gain: 0.45)]
        case .levelUp(let hero, _):
            return hero == focus ? [.sound(.levelUp, gain: 0.6)] : []
        case .goldGained(let hero, _, _):
            return hero == focus ? [.sound(.gold, gain: 0.3)] : []
        case .channelStarted(let hero, let kind, _):
            return hero == focus && kind == .recall ? [.sound(.recall, gain: 0.6)] : []
        case .channelCompleted(let hero, _, _):
            return hero == focus ? [.sound(.recall, gain: 0.75)] : []
        case .respawned(let hero, _):
            return hero == focus ? [.sound(.respawn, gain: 0.75)] : []
        case .itemPurchased, .itemSold, .purchaseFailed:
            // 購入の音は操作した本人への手応え。観戦者には鳴らさない
            return []
        case .announcement:
            // 告知の音は同じ、触覚だけ外す
            return playerCues(for: event, context: c).filter { if case .sound = $0 { return true } else { return false } }
        case .matchEnded(_, let reason):
            // 勝ち負けの無い観戦者には勝利・敗北ではなく中立の締めの音
            return reason == .aborted ? [] : [.sound(.objective, gain: 1)]
        default:
            return []
        }
    }

    /// プレイヤー: 自分のヒーロー（humanID）に関係する音と触覚。
    nonisolated static func playerCues(for event: SimEvent, context c: Context) -> [Cue] {
        let me = c.humanID
        switch event {
        case .attackReleased(let source, _, let ranged):
            guard source == me else { return [] }
            return [.sound(ranged ? .attackRanged : .attackMelee, gain: 0.55)]
        case .damage(let d):
            var out: [Cue] = []
            if d.sourceID == me, d.source == .basicAttack {
                out.append(.sound(d.isCrit ? .crit : .hit, gain: d.isCrit ? 0.9 : 0.55))
            }
            if d.targetID == me, me != nil, c.humanMaxHP > 0 {
                let ratio = (d.amount) / c.humanMaxHP
                if ratio >= hardHitRatio {
                    out.append(.haptic(.hitHard(intensity: min(1, 0.45 + ratio * 3))))
                }
            }
            return out
        case .skillCast(let cast):
            if cast.casterID == me {
                return [.sound(cast.slot == .ultimate ? .ultimateCast : .skillCast, gain: 1)]
            }
            let d = cast.origin.distance(to: c.listener)
            guard d < hearingRadius else { return [] }
            let gain = 0.55 * (1 - d / hearingRadius)
            return gain > 0.05 ? [.sound(cast.slot == .ultimate ? .ultimateCast : .skillCast, gain: gain)] : []
        case .spellCast(let caster, _, _, _):
            return caster == me ? [.sound(.skillCast, gain: 0.75)] : []
        case .heal(let target, _, let amount):
            return target == me && amount >= 40 ? [.sound(.heal, gain: 0.6)] : []
        case .shieldGained(let target, _, _):
            return target == me ? [.sound(.shield, gain: 0.7)] : []
        case .heroKilled(let k):
            if let me {
                if k.killerID == me { return [.sound(.kill, gain: 1), .haptic(.kill)] }
                if k.victimID == me { return [.sound(.death, gain: 1), .haptic(.death)] }
                if k.assistIDs.contains(me) { return [.sound(.kill, gain: 0.55)] }
                return []
            }
            return c.isSpectating ? [.sound(.kill, gain: 0.45)] : []
        case .levelUp(let hero, _):
            return hero == me ? [.sound(.levelUp, gain: 1), .haptic(.levelUp)] : []
        case .goldGained(let hero, _, _):
            return hero == me ? [.sound(.gold, gain: 0.45)] : []
        case .channelStarted(let hero, let kind, _):
            return hero == me && kind == .recall ? [.sound(.recall, gain: 0.8)] : []
        case .channelCompleted(let hero, _, _):
            return hero == me ? [.sound(.recall, gain: 1)] : []
        case .respawned(let hero, _):
            return hero == me ? [.sound(.respawn, gain: 1)] : []
        case .itemPurchased(let hero, _):
            return hero == me ? [.sound(.purchase, gain: 1)] : []
        case .itemSold(let hero, _, _):
            return hero == me ? [.sound(.gold, gain: 0.8)] : []
        case .purchaseFailed(let hero, _, _):
            return hero == me ? [.sound(.uiError, gain: 0.8)] : []
        case .announcement(let a):
            switch a {
            case .multiKill: return [.sound(.multiKill, gain: 1), .haptic(.announcement)]
            case .towerDestroyed: return [.sound(.towerDestroyed, gain: 1), .haptic(.announcement)]
            case .wyrmSlain, .colossusSlain: return [.sound(.objective, gain: 1), .haptic(.announcement)]
            case .victory: return []
            case .minionsSpawned, .matchStart, .wyrmSpawned, .colossusSpawned: return [.sound(.announcement, gain: 0.7)]
            default: return [.sound(.announcement, gain: 1), .haptic(.announcement)]
            }
        case .matchEnded(let winner, let reason):
            guard reason != .aborted else { return [] }
            if let team = c.humanTeam {
                return winner == team ? [.sound(.victory, gain: 1), .haptic(.victory)]
                                      : [.sound(.defeat, gain: 1), .haptic(.defeat)]
            }
            return [.sound(.victory, gain: 1)]
        default:
            return []
        }
    }
}
