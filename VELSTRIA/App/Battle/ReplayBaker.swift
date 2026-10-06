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
// - 到達点: シークバーの網掛けは controller.seekReadyTick（状態のある所 = キーフレーム・一度再生した所）を使う
//   （HUD は controller だけを見ればよい。事前計算のキーフレームを採用すると伸びる。年表がリプレイに保存されていても、
//   状態の無い所は網掛けしない）。この型の bakedUntilTick は事前計算の到達点（テスト・計測用）。
// - 先回り: 再生（早送り）・シークのワーカーが事前計算より先の状態を作っていれば、その状態（と年表）へ飛んで続きから計算する
//   （同じ区間を二重に計算しない。端末が熱い時ほど効く）。飛ぶ先はキーフレーム・再生位置・細かい輪のうち年表の範囲内の物。
// - メモリ: キーフレーム 1 つ約 200KB。30 秒（900 tick）間隔で 40 分 = 81 個 ≈ 16MB。上限 maxKeyframes（既定 96 ≈ 19MB）を
//   超える先は年表だけを計算する（シークはその先の最寄りの状態から進める）。細かい輪は 24 個 ≈ 5MB。
// - 端末温度・低電力モードで間を空ける（serious / 低電力: 塊の間に休む、critical: 冷えるまで止める）。stop で即座に打ち切る。
//   読み込み（地面・ウォームアップ）と CPU を取り合わないよう、読み込み幕が上がってから始める。
//
// シーク: controller.seekStateProvider に登録する。最寄りの状態（キーフレーム・細かい輪・今の状態）から目標 tick までを
// 専用の Simulation（ReplaySeekWorker）でメインスレッド外で進めて返す（UI は止まらず、HUD はシーク中の表示を出せる）。
// 目標が年表の先なら、年表の範囲内の状態から進めて年表も伸ばす（穴を開けない）。細かい輪 = 再生位置付近を 5 秒毎に
// 残した状態（±10 秒のシークを短くする）。途中で通った keyframeInterval 毎の状態はキーフレームとして渡す。
// 取り消されても進めた分（年表・キーフレーム・到達した状態）は捨てず、ワーカーも次の呼び出しで続きから進める
// （遠いシークの途中で別の位置を選び直しても、計算をやり直さない）。
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
    /// 事前計算が実際に進めた tick の累計（先回りで飛ばした区間は数えない。テスト・計測用）。
    var simulatedTicks = 0
}

/// 事前計算の先回り: 既に作られている先の状態と、その tick まで分かっている年表。
struct ReplayBakeSkip: Sendable {
    var state: SimState
    var timeline: ReplayTimeline
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
    /// skipAhead（事前計算の今の tick → 先にある状態）が状態を返したら、そこへ飛んで続きから計算する。
    static func run(_ plan: ReplayBakePlan, skipAhead: @Sendable (Int) async -> ReplayBakeSkip? = { _ in nil },
                    publish: @Sendable (ReplayBakeBatch) async -> Bool) async {
        let sim = Simulation(config: plan.config, map: MapDefinition.map(for: plan.config.mode))
        var builder: ReplayTimelineBuilder? = ReplayTimelineBuilder()
        builder?.begin(state: sim.state)
        let interval = max(1, plan.keyframeInterval)
        var keyframes: [SimState] = []
        var adopted = 0
        var simulated = 0
        var lastPublished = sim.state.tick
        while true {
            if Task.isCancelled { return }
            // 再生・シークが先の状態を作っていれば飛ぶ（年表はその状態の tick まで分かっているので続けて伸ばせる）
            if let skip = await skipAhead(sim.state.tick), skip.state.tick > sim.state.tick,
               skip.state.config == plan.config, skip.timeline.coveredTick >= skip.state.tick {
                sim.restore(from: skip.state)
                builder = ReplayTimelineBuilder(resuming: skip.timeline)
            }
            var n = 0
            while n < chunkTicks && !sim.isEnded && sim.state.tick < plan.limitTick {
                advance(sim, inputs: plan.inputs, finalTick: plan.finalTick, builder: &builder) { s in
                    guard s.tick % interval == 0, adopted < plan.maxKeyframes else { return }
                    keyframes.append(s)
                    adopted += 1
                }
                n += 1
            }
            simulated += n
            let tick = sim.state.tick
            let done = sim.isEnded || tick >= plan.limitTick
            if done || !keyframes.isEmpty || tick - lastPublished >= interval {
                guard let timeline = builder?.timeline else { return }
                let batch = ReplayBakeBatch(timeline: timeline, keyframes: keyframes, bakedTick: tick, finished: done,
                                            simulatedTicks: simulated)
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
        /// 到達した状態（取り消された時は途中の状態）。
        var state: SimState
        /// 伸ばした年表（年表の先へ進めた時だけ。取り消された時は到達した tick まで）。
        var timeline: ReplayTimeline?
        /// 途中で通った keyframeInterval 毎の状態（tick 昇順、上限 keyframeLimit 個）。
        var keyframes: [SimState] = []
        /// 目標（または試合の終わり）まで進めた。false = 取り消されて途中で止めた。
        var completed: Bool
    }

    private let inputs: [Int: [HeroCommand]]
    private let finalTick: Int?
    private let map: MapDefinition
    private var sim: Simulation?
    /// 前回の呼び出しで到達した状態と年表（取り消されても残す。次の呼び出しで base より先・goal 以前なら続きから進める）。
    private var reached: (state: SimState, timeline: ReplayTimeline?)?

    init(inputs: [Int: [HeroCommand]], finalTick: Int?, map: MapDefinition) {
        self.inputs = inputs
        self.finalTick = finalTick
        self.map = map
    }

    /// base から goal まで（試合が先に終わればそこまで）進めた状態。timeline を渡すとそれを続けて伸ばす
    /// （base はその年表の範囲内であること）。呼び出し側のタスクが取り消されたら、そこまで進めた途中の結果を返す（completed = false）。
    func advance(from base: SimState, to goal: Int, timeline: ReplayTimeline?,
                 keyframeInterval: Int, keyframeLimit: Int = .max) -> Result {
        let sim: Simulation
        if let existing = self.sim {
            sim = existing
        } else {
            sim = Simulation(snapshot: base, map: map)
            self.sim = sim
        }
        var start = base
        var resume = timeline
        if let r = reached, r.state.tick > base.tick, r.state.tick <= goal, r.state.phase != .ended, r.state.config == base.config {
            // 前回（取り消された遠いシークなど）の続きから進める。年表を伸ばす時は、その tick まで分かっている方を使う
            // （決定論なので、どちらの年表も先頭は同じ）
            let longer = [r.timeline, timeline].compactMap { $0 }.max { $0.coveredTick < $1.coveredTick }
            if timeline == nil {
                start = r.state
            } else if let longer, longer.coveredTick >= r.state.tick {
                start = r.state
                resume = longer
            }
        }
        sim.restore(from: start)
        var builder = resume.map { ReplayTimelineBuilder(resuming: $0) }
        let interval = max(1, keyframeInterval)
        var keyframes: [SimState] = []
        var cancelled = false
        var n = 0
        while sim.state.tick < goal && !sim.isEnded {
            n += 1
            if n % ReplayBakeEngine.chunkTicks == 0, Task.isCancelled {
                cancelled = true
                break
            }
            ReplayBakeEngine.advance(sim, inputs: inputs, finalTick: finalTick, builder: &builder) { s in
                guard s.tick % interval == 0, keyframes.count < keyframeLimit else { return }
                keyframes.append(s)
            }
        }
        reached = (sim.state, builder?.timeline)
        return Result(state: sim.state, timeline: builder?.timeline, keyframes: keyframes, completed: !cancelled)
    }
}

@MainActor
final class ReplayBaker {
    /// 既定のキーフレームの上限（約 200KB × 96 ≈ 19MB。30 秒間隔で 48 分ぶん。既定 40 分の観戦は 80 個で収まる）。
    static let defaultMaxKeyframes = 96
    /// 細かい輪: 再生位置付近の状態を残す間隔（tick）と個数（150 tick = 5 秒、24 個 ≈ 5MB）。
    static let fineInterval = 150
    static let fineRingCapacity = 24
    /// 事前計算の先回り: これ以上先の状態があれば飛ぶ（150 tick = 5 秒。すぐ先なら飛ばずに進める）。
    static let skipAheadMinTicks = 150

    private weak var controller: BattleController?
    let plan: ReplayBakePlan
    private let worker: ReplaySeekWorker
    /// 事前計算の到達 tick（シークバーの網掛けは controller.seekReadyTick を使う。事前計算のキーフレームと一緒に伸びる）。
    private(set) var bakedUntilTick = 0
    /// 事前計算が実際に進めた tick の累計（先回りで飛ばした区間は数えない。テスト・計測用）。
    private(set) var simulatedTicks = 0
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
            await ReplayBakeEngine.run(plan, skipAhead: { tick in
                await target.value?.skipAheadState(after: tick)
            }, publish: { batch in
                await target.value?.adopt(batch) ?? false
            })
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
        simulatedTicks = max(simulatedTicks, batch.simulatedTicks)
        if batch.finished { isFinished = true }
        return true
    }

    // MARK: シーク

    /// 目標 tick の状態（controller.seekStateProvider）。取り消されたら・作れなければ nil（コントローラが自分で進める）。
    /// 取り消されても、ワーカーが進めた分は keep で残す（次のシーク・事前計算の先回りが続きから使う）。
    func exactState(for goal: Int) async -> SimState? {
        guard let controller, controller.isSeekable else { return nil }
        let known = controller.knownTimeline
        // 目標が年表の先なら、年表を続けて伸ばせるよう年表の範囲内の状態から始める
        let extend = goal > known.coveredTick
        guard let base = bestBase(atOrBefore: extend ? known.coveredTick : goal, controller: controller) else { return nil }
        let room = max(0, plan.maxKeyframes + 1 - controller.keyframes.count)
        let result = await worker.advance(from: base, to: goal, timeline: extend ? known : nil,
                                          keyframeInterval: plan.keyframeInterval, keyframeLimit: room)
        keep(result)
        guard result.completed, !Task.isCancelled else { return nil }
        return result.state
    }

    /// ワーカーが進めた分を残す: 年表 → キーフレーム（上限まで。年表を先に渡して穴を開けない）→ 到達した状態を細かい輪へ。
    private func keep(_ result: ReplaySeekWorker.Result) {
        guard let controller else { return }
        if let t = result.timeline { controller.adoptFullTimeline(t) }
        for k in result.keyframes where controller.keyframes.count <= plan.maxKeyframes { controller.adoptKeyframe(k) }
        remember(result.state)
    }

    /// 事前計算の先回り先: 事前計算（bakeTick）より skipAheadMinTicks 以上先にある状態のうち最も先の物（キーフレーム・
    /// 再生位置・細かい輪）。年表がその tick まで分かっていること・終わっていないこと（中断の状態へは飛ばない）。
    func skipAheadState(after bakeTick: Int) -> ReplayBakeSkip? {
        guard let controller, bakeTask != nil else { return nil }
        let known = controller.knownTimeline
        var best: SimState?
        func consider(_ s: SimState?) {
            guard let s, s.phase != .ended, s.tick <= known.coveredTick, s.tick > (best?.tick ?? bakeTick) else { return }
            best = s
        }
        consider(controller.keyframes.last)
        // シーク中の sim は途中の tick を行き来するので見ない
        if controller.seekingToTick == nil { consider(controller.state) }
        consider(fineRing.last)
        guard let best, best.tick >= bakeTick + Self.skipAheadMinTicks else { return nil }
        return ReplayBakeSkip(state: best, timeline: known)
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
