import Foundation
import VelstriaCore

// 担当: 観戦（engine）。シークできる観戦・リプレイ（controller.isSeekable: オフラインの AI 同士の観戦・リプレイ）の
// 事前計算と、メインスレッド外での正確なシーク。BattleContainerView が開始・破棄する。
//
// 事前計算（bake）:
// - 別の Simulation（同じ config・MapDefinition.map(for:)・同じリプレイ入力）を優先度の低い切り離しタスクで回し、
//   keyframeInterval tick 毎の状態を controller.adoptKeyframe、年表を controller.adoptFullTimeline で少しずつ渡す。
//   年表を先に渡してからキーフレームを渡す（先のキーフレームへ飛んでも年表に穴が開かない）。
// - リプレイは記録の最終 tick まで（途中で抜けた記録は BattleController と同じくそこで中断終了にする）。
//   AI 同士の観戦は試合の終わり（最大でも maxDuration = controller.seekUpperBound）まで先に計算する。
// - 到達点: シークバーの網掛けは controller.displayTimeline.coveredTick を使う（HUD は controller だけを見ればよい。
//   事前計算の年表を採用すると伸びる）。この型の bakedUntilTick も同じ到達点（テスト・計測用）。
// - メモリ: キーフレーム 1 つ約 200KB。30 秒（900 tick）間隔で 40 分 = 81 個 ≈ 16MB。上限 maxKeyframes（既定 96 ≈ 19MB）を
//   超える先は年表だけを計算する（シークはその先の最寄りの状態から進める）。細かい輪は 24 個 ≈ 5MB。
// - 端末温度・低電力モードで間を空ける（serious / 低電力: 塊の間に休む、critical: 冷えるまで止める）。stop で即座に打ち切る。
//   読み込み（地面・ウォームアップ）と CPU を取り合わないよう、読み込み幕が上がってから始める。
//
// シーク: controller.seekStateProvider に登録する。最寄りの状態（キーフレーム・細かい輪・今の状態）から目標 tick までを
// 専用の Simulation（ReplaySeekWorker）でメインスレッド外で進めて返す（UI は止まらず、HUD はシーク中の表示を出せる）。
// 目標が年表の先なら、年表の範囲内の状態から進めて年表も伸ばす（穴を開けない）。細かい輪 = 再生位置付近を 5 秒毎に
// 残した状態（±10 秒のシークを短くする）。
//
// 決定論: どれも同じ config・同じ入力の Simulation なので、状態・年表は通常の再生と一致する（ReplayBakerTests で stateHash を比較）。
// SimState に観戦の状態は入れない。描画・HUD へイベントは配らない（ここで作るのは状態と年表だけ）。

/// 事前計算の設定（バックグラウンドへ渡す値だけ）。
struct ReplayBakePlan: Sendable {
    var config: MatchConfig
    /// tick → その tick のリプレイ入力（検索専用・列挙しない）。観戦は空。
    var inputs: [Int: [HeroCommand]]
    /// リプレイの最終 tick（観戦は nil）。
    var finalTick: Int?
    /// 計算する最後の tick（試合が先に終わればそこまで）。
    var limitTick: Int
    var keyframeInterval: Int
    /// 渡すキーフレームの上限（tick 0 はコントローラが持っているので数えない）。
    var maxKeyframes: Int
}

/// 事前計算の途中経過（メインへ渡す）。
struct ReplayBakeBatch: Sendable {
    var timeline: ReplayTimeline
    var keyframes: [SimState]
    var bakedTick: Int
    var finished: Bool
}

/// 事前計算・シークで sim を進める手順（BattleController の advanceOneTick + finishReplayIfNeeded と同じ）。
enum ReplayBakeEngine {
    /// 1 回にまとめて進める tick 数（この間隔で取り消し・端末温度を確かめ、他の処理へ譲る）。
    static let chunkTicks = 30

    /// リプレイ入力の表。BattleController と同じ順に連結する（同じ tick の複数フレームは記録順）。
    static func inputTable(_ frames: [ReplayFrame]) -> [Int: [HeroCommand]] {
        var table: [Int: [HeroCommand]] = [:]
        for f in frames { table[f.tick, default: []].append(contentsOf: f.commands) }
        return table
    }

    /// 1 tick 進める: step → 年表 → afterStep（キーフレーム。中断終了の前の状態 = BattleController と同じ順）→
    /// リプレイの最終 tick に達しても sim が終わっていなければ中断終了。
    static func advance(_ sim: Simulation, inputs: [Int: [HeroCommand]], finalTick: Int?,
                        builder: inout ReplayTimelineBuilder?, afterStep: (SimState) -> Void = { _ in }) {
        let events = sim.step(commands: inputs[sim.state.tick + 1] ?? [])
        builder?.observe(events: events, state: sim.state)
        afterStep(sim.state)
        if let final = finalTick, sim.state.tick >= final, !sim.isEnded {
            sim.abort()
            builder?.observe(events: [.matchEnded(winner: nil, reason: .aborted)], state: sim.state)
        }
    }

    /// 端末の状態に応じた進め方。
    enum Pace: Equatable {
        /// 塊ごとに譲るだけ。
        case full
        /// 塊の間に休む。
        case slow(Duration)
        /// 冷えるまで止める。
        case halt
    }

    static func pace(thermal: ProcessInfo.ThermalState, lowPower: Bool) -> Pace {
        switch thermal {
        case .critical: return .halt
        case .serious: return .slow(.milliseconds(250))
        default: return lowPower ? .slow(.milliseconds(50)) : .full
        }
    }

    private static var currentPace: Pace {
        let info = ProcessInfo.processInfo
        return pace(thermal: info.thermalState, lowPower: info.isLowPowerModeEnabled)
    }

    /// 事前計算の本体（切り離したタスクで実行）。publish が false を返したら（受け取り側がいない）打ち切る。
    static func run(_ plan: ReplayBakePlan, publish: @Sendable (ReplayBakeBatch) async -> Bool) async {
        let sim = Simulation(config: plan.config, map: MapDefinition.map(for: plan.config.mode))
        var builder: ReplayTimelineBuilder? = ReplayTimelineBuilder()
        builder?.begin(state: sim.state)
        let interval = max(1, plan.keyframeInterval)
        var keyframes: [SimState] = []
        var adopted = 0
        var lastPublished = sim.state.tick
        while true {
            if Task.isCancelled { return }
            var n = 0
            while n < chunkTicks && !sim.isEnded && sim.state.tick < plan.limitTick {
                advance(sim, inputs: plan.inputs, finalTick: plan.finalTick, builder: &builder) { s in
                    guard s.tick % interval == 0, adopted < plan.maxKeyframes else { return }
                    keyframes.append(s)
                    adopted += 1
                }
                n += 1
            }
            let tick = sim.state.tick
            let done = sim.isEnded || tick >= plan.limitTick
            if done || !keyframes.isEmpty || tick - lastPublished >= interval {
                guard let timeline = builder?.timeline else { return }
                let batch = ReplayBakeBatch(timeline: timeline, keyframes: keyframes, bakedTick: tick, finished: done)
                keyframes.removeAll()
                lastPublished = tick
                guard await publish(batch) else { return }
            }
            if done { return }
            switch currentPace {
            case .full:
                await Task.yield()
            case .slow(let d):
                try? await Task.sleep(for: d)
            case .halt:
                while currentPace == .halt && !Task.isCancelled { try? await Task.sleep(for: .seconds(1)) }
            }
        }
    }
}

/// シークの目標の状態をメインスレッド外で作る（専用の Simulation を使い回す。呼び出しは直列）。
actor ReplaySeekWorker {
    struct Result: Sendable {
        var state: SimState
        /// 伸ばした年表（年表の先へ進めた時だけ）。
        var timeline: ReplayTimeline?
    }

    private let inputs: [Int: [HeroCommand]]
    private let finalTick: Int?
    private let map: MapDefinition
    private var sim: Simulation?

    init(inputs: [Int: [HeroCommand]], finalTick: Int?, map: MapDefinition) {
        self.inputs = inputs
        self.finalTick = finalTick
        self.map = map
    }

    /// base から goal まで（試合が先に終わればそこまで）進めた状態。timeline を渡すとそれを続けて伸ばす
    /// （base はその年表の範囲内であること）。呼び出し側のタスクが取り消されたら nil。
    func advance(from base: SimState, to goal: Int, timeline: ReplayTimeline?) -> Result? {
        let sim: Simulation
        if let existing = self.sim {
            sim = existing
        } else {
            sim = Simulation(snapshot: base, map: map)
            self.sim = sim
        }
        sim.restore(from: base)
        var builder = timeline.map { ReplayTimelineBuilder(resuming: $0) }
        var n = 0
        while sim.state.tick < goal && !sim.isEnded {
            n += 1
            if n % ReplayBakeEngine.chunkTicks == 0, Task.isCancelled { return nil }
            ReplayBakeEngine.advance(sim, inputs: inputs, finalTick: finalTick, builder: &builder)
        }
        if Task.isCancelled { return nil }
        return Result(state: sim.state, timeline: builder?.timeline)
    }
}

@MainActor
final class ReplayBaker {
    /// 既定のキーフレームの上限（約 200KB × 96 ≈ 19MB。30 秒間隔で 48 分ぶん。既定 40 分の観戦は 80 個で収まる）。
    static let defaultMaxKeyframes = 96
    /// 細かい輪: 再生位置付近の状態を残す間隔（tick）と個数（150 tick = 5 秒、24 個 ≈ 5MB）。
    static let fineInterval = 150
    static let fineRingCapacity = 24

    private weak var controller: BattleController?
    let plan: ReplayBakePlan
    private let worker: ReplaySeekWorker
    /// 事前計算の到達 tick（シークバーの網掛けは controller.displayTimeline.coveredTick を使う。同じ値まで伸びる）。
    private(set) var bakedUntilTick = 0
    /// 試合の終わり（または計算する最後の tick）まで計算し終えた。
    private(set) var isFinished = false
    /// 渡したキーフレームの数（tick 0 を除く）。
    private(set) var adoptedKeyframes = 0
    /// 細かい輪（tick 昇順・重複なし）。
    private(set) var fineRing: [SimState] = []
    private var lastRingTick: Int?
    private var bakeTask: Task<Void, Never>?
    private var ringTask: Task<Void, Never>?

    /// シークできない（プレイヤー・オンライン）なら nil。
    /// keyframeInterval 既定 = BattleController.keyframeInterval、maxKeyframes 既定 = defaultMaxKeyframes、
    /// limitTick 既定 = controller.seekUpperBound（テストは短くする）。
    init?(controller: BattleController, keyframeInterval: Int? = nil, maxKeyframes: Int? = nil, limitTick: Int? = nil) {
        guard controller.isSeekable else { return nil }
        let keyframeInterval = keyframeInterval ?? BattleController.keyframeInterval
        let maxKeyframes = maxKeyframes ?? Self.defaultMaxKeyframes
        self.controller = controller
        let config = controller.launch.config
        let inputs = ReplayBakeEngine.inputTable(controller.launch.replay?.frames ?? [])
        let finalTick = controller.replayFinalTick
        plan = ReplayBakePlan(config: config, inputs: inputs, finalTick: finalTick,
                              limitTick: min(limitTick ?? Int.max, controller.seekUpperBound),
                              keyframeInterval: max(1, keyframeInterval), maxKeyframes: max(0, maxKeyframes))
        worker = ReplaySeekWorker(inputs: inputs, finalTick: finalTick, map: MapDefinition.map(for: config.mode))
    }

    var isRunning: Bool { bakeTask != nil }

    /// 事前計算・細かい輪・シークの登録を始める。waitForPresentation = 読み込み幕が上がるまで計算を待つ（テストは false）。
    func start(waitForPresentation: Bool = true) {
        guard bakeTask == nil, let controller else { return }
        controller.seekStateProvider = { [weak self] goal in
            await self?.exactState(for: goal)
        }
        let plan = plan
        let target = WeakBaker(self)
        bakeTask = Task.detached(priority: .utility) {
            if waitForPresentation {
                while true {
                    guard let ready = await target.value?.presentationReady() else { return }
                    if ready { break }
                    try? await Task.sleep(for: .milliseconds(250))
                    if Task.isCancelled { return }
                }
            }
            await ReplayBakeEngine.run(plan) { batch in
                await target.value?.adopt(batch) ?? false
            }
        }
        ringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.sampleRing()
            }
        }
    }

    /// 打ち切る（戦闘画面の破棄）。シークの登録も外す。
    func stop() {
        bakeTask?.cancel()
        bakeTask = nil
        ringTask?.cancel()
        ringTask = nil
        controller?.seekStateProvider = nil
        fineRing.removeAll()
    }

    private func presentationReady() -> Bool? {
        controller.map { $0.isPresentationReady }
    }

    /// 途中経過を採用する（年表 → キーフレームの順）。受け取り側がいなければ false（事前計算を打ち切る）。
    @discardableResult
    func adopt(_ batch: ReplayBakeBatch) -> Bool {
        guard let controller, bakeTask != nil else { return false }
        controller.adoptFullTimeline(batch.timeline)
        for k in batch.keyframes { controller.adoptKeyframe(k) }
        adoptedKeyframes += batch.keyframes.count
        bakedUntilTick = max(bakedUntilTick, batch.bakedTick)
        if batch.finished { isFinished = true }
        return true
    }

    // MARK: シーク

    /// 目標 tick の状態（controller.seekStateProvider）。取り消されたら・作れなければ nil（コントローラが自分で進める）。
    func exactState(for goal: Int) async -> SimState? {
        guard let controller, controller.isSeekable else { return nil }
        let known = controller.knownTimeline
        // 目標が年表の先なら、年表を続けて伸ばせるよう年表の範囲内の状態から始める
        let extend = goal > known.coveredTick
        guard let base = bestBase(atOrBefore: extend ? known.coveredTick : goal, controller: controller) else { return nil }
        guard let result = await worker.advance(from: base, to: goal, timeline: extend ? known : nil),
              !Task.isCancelled else { return nil }
        if let t = result.timeline { self.controller?.adoptFullTimeline(t) }
        remember(result.state)
        return result.state
    }

    /// limit 以前で最も新しい状態（キーフレーム・細かい輪・今の状態）。
    func bestBase(atOrBefore limit: Int, controller: BattleController) -> SimState? {
        var base = controller.keyframes.last { $0.tick <= limit }
        if let r = fineRing.last(where: { $0.tick <= limit }), r.tick > (base?.tick ?? -1) { base = r }
        let current = controller.state
        if current.tick <= limit, current.tick > (base?.tick ?? -1) { base = current }
        return base
    }

    // MARK: 細かい輪

    /// 再生位置付近の状態を残す（0.25 秒毎。シーク中は sim が途中の tick を行き来するので見ない）。
    func sampleRing() {
        guard let controller, controller.seekingToTick == nil else { return }
        let s = controller.state
        if let last = lastRingTick, abs(s.tick - last) < Self.fineInterval { return }
        remember(s)
    }

    private func remember(_ s: SimState) {
        lastRingTick = s.tick
        if let i = fineRing.firstIndex(where: { $0.tick >= s.tick }) {
            if fineRing[i].tick == s.tick { return }
            fineRing.insert(s, at: i)
        } else {
            fineRing.append(s)
        }
        // 上限を超えたら今の位置から最も遠いものを捨てる
        while fineRing.count > Self.fineRingCapacity {
            guard let far = fineRing.indices.max(by: { abs(fineRing[$0].tick - s.tick) < abs(fineRing[$1].tick - s.tick) })
            else { break }
            fineRing.remove(at: far)
        }
    }
}

/// 事前計算のタスクから ReplayBaker を弱参照で持つ（破棄された戦闘画面を延命しない）。
private final class WeakBaker: @unchecked Sendable {
    // 作成後は書き換えない（weak 参照の読み出しはスレッド安全。メソッドは主アクターへ移って呼ぶ）
    weak var value: ReplayBaker?
    init(_ value: ReplayBaker) { self.value = value }
}
