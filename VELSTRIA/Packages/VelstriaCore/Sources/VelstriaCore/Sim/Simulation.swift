import Foundation

/// 固定 tick（30Hz）の決定論シミュレーション。クライアント（オフライン）でもサーバーでも同じコードで動く。
///
/// 使い方:
/// ```
/// let sim = Simulation(config: config)
/// while !sim.isEnded { let events = sim.step(commands: humanCommands) }
/// ```
public final class Simulation {
    public private(set) var state: SimState
    public let ctx: SimContext
    /// 人間の入力を記録する（リプレイ用）。nil なら記録しない。
    public var recorder: ReplayRecorder?

    public init(config: MatchConfig, master: MasterData = .shared, map: MapDefinition = .standard) {
        self.ctx = SimContext(master: master, map: map, config: config)
        self.state = SimState(config: config)
        SpawnSystem.setupMatch(&state, ctx)
        for i in state.units.indices { StatCalculator.recompute(&state, i, ctx) }
        VisionSystem.update(&state, ctx)
    }

    /// スナップショットから再開（再接続・デバッグ）。
    public init(snapshot: SimState, master: MasterData = .shared, map: MapDefinition = .standard) {
        self.ctx = SimContext(master: master, map: map, config: snapshot.config)
        self.state = snapshot
    }

    public var isEnded: Bool { state.phase == .ended }

    /// 1 tick 進め、この tick に発生したイベントを返す。
    /// - Parameter commands: 人間プレイヤー（またはネットワーク）からの入力。AI の入力は内部で生成する。
    @discardableResult
    public func step(commands: [HeroCommand] = []) -> [SimEvent] {
        guard state.phase != .ended else { return [] }
        if state.phase == .loading {
            state.phase = .playing
            state.emit(.announcement(.matchStart))
        }
        state.tick += 1
        state.time = Double(state.tick) * Balance.dt
        for i in state.units.indices { state.units[i].prevPos = state.units[i].pos }
        for i in state.projectiles.indices { state.projectiles[i].prevPos = state.projectiles[i].pos }

        recorder?.record(tick: state.tick, commands: commands)

        // 1. 入力（人間 + AI）
        let botCommands = BotAI.generateCommands(&state, ctx)
        CommandSystem.apply(commands + botCommands, &state, ctx)

        // 2. 出現
        SpawnSystem.update(&state, ctx)

        // 3. 状態効果 → 能力値
        StatusSystem.update(&state, ctx)
        for i in state.units.indices { StatCalculator.recompute(&state, i, ctx) }

        // 4. 詠唱（帰還・転移）
        RecallSystem.update(&state, ctx)

        // 5. 非ヒーローの行動決定
        MinionSystem.update(&state, ctx)
        MonsterSystem.update(&state, ctx)
        TowerSystem.update(&state, ctx)

        // 6. 移動 → 通常攻撃
        MovementSystem.update(&state, ctx)
        CombatSystem.updateAttacks(&state, ctx)

        // 7. 投射物・ゾーン・スキル・スペル
        ProjectileSystem.update(&state, ctx)
        ZoneSystem.update(&state, ctx)
        SkillSystem.update(&state, ctx)
        SpellSystem.update(&state, ctx)

        // 8. 経済・回復
        EconomySystem.update(&state, ctx)

        // 9. 死亡処理 → 報酬 → 復活
        DeathSystem.process(&state, ctx)
        RespawnSystem.update(&state, ctx)

        // 10. 視界
        if state.tick % Balance.visionUpdateEveryTicks == 0 {
            VisionSystem.update(&state, ctx)
        }

        // 11. 勝敗
        MatchFlowSystem.update(&state, ctx)

        // 12. 後片付け
        state.removeFinishedEntities()

        let events = state.events
        state.events.removeAll(keepingCapacity: true)
        return events
    }

    /// 人間入力なしで試合終了（または maxTime 秒）まで回す。テスト・観戦の高速進行用。
    @discardableResult
    public func runHeadless(maxTime: Double? = nil, onEvents: (([SimEvent]) -> Void)? = nil) -> SimState {
        let limit = maxTime ?? state.config.maxDuration
        while !isEnded && state.time < limit {
            let ev = step()
            onEvents?(ev)
        }
        return state
    }

    /// 状態をスナップショットで置き換える（オンライン対戦の再同期・デバッグ）。
    /// 同じ config のスナップショットであること（ctx は作り直さない）。
    public func restore(from snapshot: SimState) {
        state = snapshot
        state.rebuildIndex()
    }

    /// 試合を中断終了（練習場の退出など）。
    public func abort() {
        guard state.phase != .ended else { return }
        state.phase = .ended
        state.endReason = .aborted
        state.emit(.matchEnded(winner: nil, reason: .aborted))
    }
}
