import SwiftUI
import VelstriaCore

// 担当: battle-hud。戦闘の効果音と触覚。SimEvent を購読し、人間プレイヤーに関係する出来事だけを鳴らす。
// - 自分の攻撃・命中・クリティカル、カメラ付近のスキル発動、キル/デス、レベルアップ、Gold、帰還、復活、告知、塔破壊、勝敗
// - 触覚: 大きな被弾、キル、レベルアップ、死亡
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
    }

    /// カメラからこの距離以内のスキル発動を鳴らす。
    nonisolated static let hearingRadius: Double = 1700
    /// 1 回でこの割合以上の被弾で触覚。
    nonisolated static let hardHitRatio: Double = 0.09

    private weak var controller: BattleController?
    private weak var app: AppModel?
    private var token: UUID?
    private var lastOtherSkill: TimeInterval = 0
    private var lastHardHit: TimeInterval = 0

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
        var ctx = Context(humanID: controller.humanHeroID, humanTeam: controller.isSpectating ? nil : .blue,
                          humanMaxHP: humanIndex.map { s.units[$0].stats.maxHP } ?? 1,
                          listener: humanIndex.map { s.units[$0].pos } ?? Balance.mapCenter,
                          isSpectating: controller.isSpectating)
        switch controller.cameraMode {
        case .free(let p): ctx.listener = p
        case .followUnit(let id): if let u = s.unit(id) { ctx.listener = u.pos }
        case .followHero: break
        }
        let now = ProcessInfo.processInfo.systemUptime
        for e in events {
            for cue in Self.cues(for: e, context: ctx) {
                switch cue {
                case .sound(let sfx, let gain):
                    if case .skillCast(let c) = e, c.casterID != ctx.humanID {
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
        case .victory: app.haptics.success()
        case .defeat: app.haptics.error()
        }
    }

    /// イベント → 音・触覚（副作用なし）。
    nonisolated static func cues(for event: SimEvent, context c: Context) -> [Cue] {
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
            case .multiKill: return [.sound(.multiKill, gain: 1)]
            case .towerDestroyed: return [.sound(.towerDestroyed, gain: 1)]
            case .wyrmSlain, .colossusSlain: return [.sound(.objective, gain: 1)]
            case .victory: return []
            case .minionsSpawned, .matchStart, .wyrmSpawned, .colossusSpawned: return [.sound(.announcement, gain: 0.7)]
            default: return [.sound(.announcement, gain: 1)]
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
