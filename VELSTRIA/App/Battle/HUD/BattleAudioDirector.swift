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
// Star Core の終幕（Core の破壊で決着）: 決着の瞬間は崩壊の音だけを鳴らし、勝敗の音（cues の .matchEnded）は勝敗のバナーが
// 出る時刻（TowerTimeline.finaleResult）まで遅らせる。それまでに巻き戻す・試合を出たら鳴らさない。

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
    /// ほかのヒーローの通常攻撃・その命中を最後に鳴らした時刻（間引き）。
    private var lastOtherAttack: TimeInterval = 0
    private var lastOtherHit: TimeInterval = 0
    /// 最後に見た presentationEpoch と、変化に気付いてから音を止める期限（systemUptime）。
    private var seenEpoch: Int?
    private var suppressUntil: TimeInterval = 0
    /// パッシブの演出を最後に出した sim の時刻（ユニットごと。音を鳴らさなかった時も更新する）。
    private var lastPassiveFire: [EntityID: Double] = [:]
    /// キットの強い通常攻撃の命中の音に替える間（源ごと。sim の秒。三連突きの 3 発目まで）。
    private var empoweredUntil: [EntityID: Double] = [:]
    /// 終幕の後に鳴らす勝敗の音（バナーの時刻まで待つ）。
    private var resultTask: Task<Void, Never>?

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
        // 試合に出るヒーローのスキルの音を裏で読む（プレイ中にファイルを読まない）
        app?.audio.preloadSkillSounds(heroIDs: controller.ctx.config.players.map(\.heroID))
        // 塔・Star Core の立ち上がり・倒壊の音（描画側の時刻表で鳴る。StructureFX.swift）
        let audio = app?.audio
        StructureAudio.sink = { [weak audio] sfx, gain in audio?.play(sfx, gain: gain) }
        // ヒーローのパッシブの音（自分・追従中は 0.6、ほかは聞こえる距離で弱める）
        SkillFXAudio.passiveSink = { [weak self] unit, heroID in self?.playPassive(unit: unit, heroID: heroID) }
    }

    func stop() {
        if let token, let controller { controller.unsubscribe(token) }
        token = nil
        StructureAudio.sink = nil
        SkillFXAudio.passiveSink = nil
        lastPassiveFire = [:]
        empoweredUntil = [:]
        app?.audio.releaseSkillSounds()
        resultTask?.cancel()
        resultTask = nil
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
        // この呼び出しで強い通常攻撃の振りを鳴らした源（その攻撃の普段の振りの音は鳴らさない）
        var empoweredSwings: Set<EntityID> = []
        for e in events {
            // キットの強い通常攻撃（三連突き・円撃）: 専用の振り。命中は窓の間だけ専用の命中の音に替える
            if case .empoweredAttack(let x) = e {
                if playEmpowered(x, state: s, context: ctx, app: app) { empoweredSwings.insert(x.sourceID) }
                continue
            }
            if case .attackReleased(let source, _, _) = e, empoweredSwings.contains(source) { continue }
            // 強い通常攻撃の命中は専用の音（普段の命中・会心の音は重ねない。触覚はそのまま）
            var empoweredHit = false
            if case .damage(let d) = e { empoweredHit = playEmpoweredHit(d, state: s, context: ctx, app: app) }
            if CoreFinale.isTrigger(e), let delay = CoreFinale.remainingUntilResult(s), delay > 0 {
                // 終幕: 今は Core の崩壊の音、勝敗の音はバナーと一緒に
                app.audio.play(.towerDestroyed, gain: 1)
                if !ctx.isSpectating { app.haptics.impact(.heavy, intensity: 1) }
                deferResult(Self.cues(for: e, context: ctx), after: delay, epoch: controller.presentationEpoch)
                continue
            }
            for cue in Self.cues(for: e, context: ctx) {
                switch cue {
                case .sound(let sfx, let gain):
                    if empoweredHit, sfx == .hit || sfx == .crit { continue }
                    if case .skillCast(let c) = e, c.casterID != ctx.humanID, c.casterID != ctx.focusID {
                        guard now - lastOtherSkill > 0.18 else { continue }
                        lastOtherSkill = now
                    }
                    // ヒーローのスキルの音（溜め・振り・着弾・余韻。無ければ汎用の発動の音）。奥義の時は他の音を少し下げる
                    if case .skillCast(let c) = e, sfx == .skillCast || sfx == .ultimateCast {
                        if c.slot == .ultimate { app.audio.duckForUltimate() }
                        if app.audio.playSkill(SkillSoundKey(heroID: c.heroID, slot: c.slot, stage: c.stage), gain: gain,
                                               pan: Self.pan(c.origin, listener: ctx.listener)) {
                            continue
                        }
                    }
                    // ヒーローの通常攻撃の振り・発射と命中（揺らぎ。無ければ汎用の音）
                    if case .attackReleased(let source, _, _) = e, sfx == .attackMelee || sfx == .attackRanged,
                       let u = s.unit(source), let heroID = u.hero?.heroID,
                       app.audio.playSkill(SkillSoundKey(heroID: heroID, phase: .attack), gain: gain,
                                           pan: Self.pan(u.pos, listener: ctx.listener)) {
                        continue
                    }
                    // 会心は会心の音（武器の組の重い打撃 + 鳴り）、無ければ命中の音
                    if case .damage(let d) = e, sfx == .hit || sfx == .crit, let src = d.sourceID, let heroID = s.unit(src)?.hero?.heroID {
                        let pan = Self.pan(d.pos, listener: ctx.listener)
                        if d.isCrit, app.audio.playSkill(SkillSoundKey(heroID: heroID, phase: .crit), gain: gain, pan: pan) { continue }
                        if app.audio.playSkill(SkillSoundKey(heroID: heroID, phase: .attackHit), gain: gain, pan: pan) { continue }
                    }
                    app.audio.play(sfx, gain: gain)
                case .haptic(let h):
                    play(h, app: app, now: now)
                }
            }
            // ほかのヒーローの通常攻撃と、自分が受けた通常攻撃（武器の組の音。聞こえる距離で弱める）
            if !empoweredHit { otherHeroAttack(e, state: s, context: ctx, now: now, app: app) }
            // スキルの命中の音（そのスキルの音があるヒーローだけ。自分が関わる命中と、聞こえる距離の命中）
            if case .damage(let d) = e, case .skill(let slot) = d.source, let src = d.sourceID,
               let heroID = s.unit(src)?.hero?.heroID {
                let gain = Self.skillHitGain(d, context: ctx)
                if gain > 0 {
                    app.audio.playSkill(SkillSoundKey(heroID: heroID, slot: slot, hit: true), gain: gain,
                                        pan: Self.pan(d.pos, listener: ctx.listener))
                }
            }
        }
    }

    /// ほかのヒーローの通常攻撃の振り・発射（聞こえる距離の 6 割まで）と、その命中（自分が受けた命中は大きく）。
    /// 自分・観戦の追従中のユニットの通常攻撃は cues で鳴らす。速い再生・シークの直後は鳴らさない。同時に多い時は間引く。
    private func otherHeroAttack(_ e: SimEvent, state s: SimState, context c: Context, now: TimeInterval, app: AppModel) {
        guard !c.suppressed, c.speed <= Self.dampenAboveSpeed else { return }
        let me = c.isSpectating ? c.focusID : c.humanID
        switch e {
        case .attackReleased(let source, _, _):
            guard source != me, let u = s.unit(source), let heroID = u.hero?.heroID,
                  now - lastOtherAttack >= Self.otherAttackGap else { return }
            let gain = Self.otherCombatGain(u.pos, listener: c.listener, scale: 0.32)
            guard gain > 0.03 else { return }
            lastOtherAttack = now
            app.audio.playSkill(SkillSoundKey(heroID: heroID, phase: .attack), gain: gain, pan: Self.pan(u.pos, listener: c.listener))
        case .damage(let d):
            guard d.source == .basicAttack, let src = d.sourceID, src != me, let heroID = s.unit(src)?.hero?.heroID,
                  now - lastOtherHit >= Self.otherAttackGap else { return }
            let gain = d.targetID == me && me != nil ? 0.55 : Self.otherCombatGain(d.pos, listener: c.listener, scale: 0.26)
            guard gain > 0.03 else { return }
            lastOtherHit = now
            let pan = Self.pan(d.pos, listener: c.listener)
            if d.isCrit, app.audio.playSkill(SkillSoundKey(heroID: heroID, phase: .crit), gain: gain, pan: pan) { return }
            app.audio.playSkill(SkillSoundKey(heroID: heroID, phase: .attackHit), gain: gain, pan: pan)
        default:
            return
        }
    }

    /// キットの強い通常攻撃の振りを鳴らす（ヒーローの専用の音があれば true）。自分・追従中のユニットが撃った・受けたものは大きく、
    /// ほかは聞こえる距離で弱める。音の有無によらず、命中を専用の音に替える窓（三連突きの 3 発目まで）を開く。
    private func playEmpowered(_ x: EmpoweredAttackEvent, state s: SimState, context c: Context, app: AppModel) -> Bool {
        if empoweredUntil.count > 32 { empoweredUntil = empoweredUntil.filter { $0.value >= s.time } }
        empoweredUntil[x.sourceID] = s.time + Self.empoweredHitWindow(x)
        guard !c.suppressed, c.speed <= Self.dropAboveSpeed, let u = s.unit(x.sourceID) else { return false }
        let gain = Self.empoweredGain(x, sourcePos: u.pos, context: c)
        guard gain > 0.03 else { return false }
        return app.audio.playSkill(SkillSoundKey(heroID: x.heroID, phase: .empowered), gain: gain,
                                   pan: Self.pan(u.pos, listener: c.listener))
    }

    /// 強い通常攻撃の窓の中の、その源の通常攻撃の命中（周りの命中も）を専用の命中の音で鳴らす。鳴らしたら true（普段の命中の音は重ねない）。
    private func playEmpoweredHit(_ d: DamageEvent, state s: SimState, context c: Context, app: AppModel) -> Bool {
        guard d.source == .basicAttack, let src = d.sourceID, let until = empoweredUntil[src], s.time <= until,
              let heroID = s.unit(src)?.hero?.heroID else { return false }
        guard !c.suppressed, c.speed <= Self.dropAboveSpeed else { return true }
        let me = c.isSpectating ? c.focusID : c.humanID
        let gain: Double
        if src == me || (d.targetID == me && me != nil) {
            gain = 0.7
        } else {
            gain = Self.otherCombatGain(d.pos, listener: c.listener, scale: 0.35)
        }
        guard gain > 0.03 else { return true }
        return app.audio.playSkill(SkillSoundKey(heroID: heroID, phase: .empoweredHit), gain: gain,
                                   pan: Self.pan(d.pos, listener: c.listener))
    }

    /// 強い通常攻撃の命中を専用の音にする窓（sim の秒）: 最後の命中（interval × (hits − 1)）+ 1 tick の余裕。
    nonisolated static func empoweredHitWindow(_ x: EmpoweredAttackEvent) -> Double {
        x.interval * Double(max(0, x.hits - 1)) + Balance.dt * 1.5
    }

    /// 強い通常攻撃の振りの音量: 自分（観戦は追従中）が撃った 0.8・受けた（主対象、円撃は円の中）0.6、ほかは聞こえる距離で 0.4 まで。
    nonisolated static func empoweredGain(_ x: EmpoweredAttackEvent, sourcePos: Vec2, context c: Context) -> Double {
        let me = c.isSpectating ? c.focusID : c.humanID
        if x.sourceID == me { return 0.8 }
        if let me, x.targetID == me { return 0.6 }
        if let me, c.humanID == me, x.radius > 0, c.listener.distance(to: x.origin) <= x.radius + Balance.heroRadius { return 0.6 }
        return otherCombatGain(sourcePos, listener: c.listener, scale: 0.4)
    }

    /// ほかのヒーローの通常攻撃の音量（聞き手からの距離で、聞こえる距離の 6 割で 0）。
    nonisolated static func otherCombatGain(_ pos: Vec2, listener: Vec2, scale: Double) -> Double {
        let r = hearingRadius * 0.6
        let d = pos.distance(to: listener)
        return d >= r ? 0 : scale * (1 - d / r)
    }

    /// ほかのヒーローの通常攻撃の音の最短間隔（大勢の乱戦で鳴りすぎない）。
    nonisolated static let otherAttackGap: TimeInterval = 0.07

    /// 画面の左右（-1〜1）。カメラは回らないので、聞き手（カメラの中心）からの横の距離で決める（画面の半分の幅 ≈ 9 m で端）。
    nonisolated static func pan(_ pos: Vec2, listener: Vec2) -> Float {
        Float(max(-1, min(1, (pos.x - listener.x) / panHalfWidth))) * 0.85
    }

    /// 左右の端とする横の距離（sim の単位）。
    nonisolated static let panHalfWidth: Double = 900

    /// パッシブの音（SkillFXAudio.passiveSink から）。自分・追従中のユニットは 0.6、ほかは聞こえる距離で 0.3 まで。
    /// 演出が passiveQuiet 秒以上止んでいた時だけ鳴らす（ゴルムの闘気のように毎秒たまるパッシブは、たまり始めの 1 回だけ。
    /// MLBB のフランコも回復が始まる時に 1 回）。シークの直後・速い再生では鳴らさない。
    private func playPassive(unit: EntityID, heroID: String) {
        guard let controller, let app, let u = controller.sim.state.unit(unit) else { return }
        let t = controller.sim.state.time
        defer { lastPassiveFire[unit] = t }
        guard Self.passiveSounds(lastFire: lastPassiveFire[unit], now: t) else { return }
        let speed = controller.isOnline ? 1 : controller.speed
        guard ProcessInfo.processInfo.systemUptime >= suppressUntil, speed <= Self.dampenAboveSpeed else { return }
        let me = controller.isSpectating ? controller.presentationFocusID : controller.humanHeroID
        var listener = u.pos
        if let i = controller.humanIndex { listener = controller.sim.state.units[i].pos }
        let gain: Double
        if unit == me {
            gain = 0.6
        } else {
            let d = u.pos.distance(to: listener)
            guard d < Self.hearingRadius else { return }
            gain = 0.3 * (1 - d / Self.hearingRadius)
        }
        app.audio.playSkill(SkillSoundKey(heroID: heroID, phase: .passive), gain: gain, pan: Self.pan(u.pos, listener: listener))
    }

    /// パッシブの演出が止んでから音を鳴らせるまでの sim の秒数。
    nonisolated static let passiveQuiet: Double = 3

    /// パッシブの音を鳴らすか（前の演出から passiveQuiet 秒以上。巻き戻し（時刻が戻った）なら鳴らす）。
    nonisolated static func passiveSounds(lastFire: Double?, now: Double) -> Bool {
        guard let lastFire, now >= lastFire else { return true }
        return now - lastFire >= passiveQuiet
    }

    /// スキルの命中の音の音量（0 = 鳴らさない）。自分（観戦者は追従中のユニット）が撃った・受けた命中は 0.8、
    /// ほかは聞こえる距離（hearingRadius）で弱めて 0.5 まで。再生速度・シーク直後の抑制は cues と同じ。
    nonisolated static func skillHitGain(_ d: DamageEvent, context c: Context) -> Double {
        guard !c.suppressed, c.speed <= dropAboveSpeed else { return 0 }
        let me = c.isSpectating ? c.focusID : c.humanID
        var gain: Double
        if let me, d.sourceID == me || d.targetID == me {
            gain = 0.8
        } else {
            let dist = d.pos.distance(to: c.listener)
            guard dist < hearingRadius else { return 0 }
            gain = 0.5 * (1 - dist / hearingRadius)
        }
        if c.speed > dampenAboveSpeed { gain *= dampenedGain }
        return gain
    }

    /// 勝敗の音を終幕の後（バナーの時刻）に鳴らす。巻き戻し・再同期（presentationEpoch の変化）・退出の後は鳴らさない。
    private func deferResult(_ cues: [Cue], after delay: Double, epoch: Int) {
        resultTask?.cancel()
        resultTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let controller = self.controller, let app = self.app,
                  controller.isEnded, controller.presentationEpoch == epoch else { return }
            let now = ProcessInfo.processInfo.systemUptime
            for cue in cues {
                switch cue {
                case .sound(let sfx, let gain): app.audio.play(sfx, gain: gain)
                case .haptic(let h): self.play(h, app: app, now: now)
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
