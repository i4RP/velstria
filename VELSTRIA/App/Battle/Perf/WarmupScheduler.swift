import Foundation
import os
import QuartzCore

// 担当: battle-renderer（性能）。読み込み幕の裏のウォームアップを複数フレームに分けて実行し、
// 「準備ができた」という合図で幕を上げる（固定フレーム数で上げない）。
//
// 1. 準備の段（BattleWorld.makeWarmupPlan）: 1 フレームの予算（通常 10 ms）内でまとめて実行。重い段は予算の前半でだけ始める。
//    描画が遅い環境（GPU の無い CI のシミュレータ・高負荷時）では前フレームの間隔の半分（最大 60 ms）まで詰め、
//    段の数だけフレームを費やして読み込みが何十秒にも延びないようにする
// 2. 影の両状態: 画質の自動調整が影を切り替えうるとき、太陽の影を反転した状態で数フレーム描く（試合中に影のシェーダーを作らない）
// 3. 落ち着き待ち（ギャラリー）: 目標間隔の 1.5 倍未満のフレームが N 回続き、かつ各ゲート
//    （マテリアルの Program・後処理のパイプライン）が揃ったら完了。どれかが揃わなくても上限（約 3 秒）で必ず終える
// 各段は signpost（"warmup.step"）で囲み、所要時間を notes に残す（PerfRun のレポート・Instruments で確認する）。

@MainActor
final class WarmupScheduler {
    struct Config {
        /// 準備の段に使う 1 フレームの予算（秒）。60fps の端末ではロード表示のアニメーションを止めない範囲。
        var stepBudget: Double = 0.010
        /// 描画が遅いとき、前フレームの間隔のこの割合まで予算を広げる（表示はどのみち滑らかでないため、早く終える方を取る）。
        var slowFrameShare: Double = 0.5
        /// 予算の上限（秒）。
        var maxBudget: Double = 0.060
        /// 重い段（予算を超えうる）は、そのフレームの経過が予算のこの割合未満のときだけ始める。
        var heavyStartShare: Double = 0.5
        /// 落ち着いたとみなす連続フレーム数と、そのフレーム間隔の上限（目標間隔の倍率）。
        var stableFrames = 8
        var stableFactor = 1.5
        /// 開始からこの秒数を過ぎたら、落ち着き・ゲートを待たずに終える（読み込みが終わらない事態を防ぐ）。
        var hardCap: Double = 3
        /// 影を反転して描くフレーム数。
        var shadowVariantFrames = 3
        /// 上限に達しても最低限描く落ち着き待ちのフレーム数。
        var minSettleFrames = 2
    }

    /// 幕を上げる前に揃っていてほしいもの（例: マテリアルの Program、後処理のパイプライン）。
    struct Gate {
        let name: String
        let isReady: @MainActor () -> Bool

        init(_ name: String, isReady: @escaping @MainActor () -> Bool) {
            self.name = name
            self.isReady = isReady
        }
    }

    enum Phase: Equatable {
        case steps
        case shadowVariants
        case settle
        case done
    }

    /// このフレームの描画に対する指示。
    struct Directive: Equatable {
        /// true の間は太陽の影を反転した状態で描く。
        var invertShadows = false
        /// ウォームアップ完了（呼び出し側が幕を上げる）。
        var finished = false
    }

    struct StepTiming: Equatable {
        var name: String
        var heavy: Bool
        var ms: Double
        /// 何フレーム目に実行したか（1 始まり）。
        var frame: Int
    }

    let config: Config
    let targetInterval: Double
    let warmsShadowVariants: Bool
    private let steps: [WarmupStep]
    private let gates: [Gate]
    private let clock: () -> Double
    private(set) var phase: Phase = .steps
    private(set) var nextStep = 0
    private(set) var frameCount = 0
    private(set) var timings: [StepTiming] = []
    private(set) var notes: [String] = []
    /// 影の反転フレームを描き終えた（画質の自動調整が影を切り替えてよい）。
    private(set) var shadowVariantsWarmed = false
    /// 上限で打ち切った。
    private(set) var timedOut = false
    private var start: Double?
    private var stepsEnd: Double?
    private var variantFrames = 0
    private var settleFrames = 0
    private var stable = 0
    private var gateReadyAt: [String: Double] = [:]
    private var shownProgress: Double = 0
    private var interval: OSSignpostIntervalState?
    private let totalWeight: Double
    private var doneWeight: Double = 0

    init(steps: [WarmupStep], targetInterval: Double, warmShadowVariants: Bool, gates: [Gate] = [],
         config: Config = Config(), clock: @escaping () -> Double = { CACurrentMediaTime() }) {
        self.steps = steps
        self.targetInterval = targetInterval
        self.warmsShadowVariants = warmShadowVariants
        self.gates = gates
        self.config = config
        self.clock = clock
        totalWeight = steps.reduce(0) { $0 + WarmupScheduler.weight($1) }
    }

    var isDone: Bool { phase == .done }
    var elapsed: Double { start.map { clock() - $0 } ?? 0 }

    /// 0〜1 の進み具合（戻らない）。準備の段 80%・影 5%・落ち着き待ち 15%。
    var progress: Double {
        let stepPart = totalWeight > 0 ? doneWeight / totalWeight : 1
        var p = stepPart * 0.8
        if phase != .steps {
            let shadow = warmsShadowVariants ? Double(variantFrames) / Double(max(1, config.shadowVariantFrames)) : 1
            p += 0.05 * min(1, shadow)
        }
        if phase == .settle {
            let ready = gates.isEmpty ? 1 : Double(gates.filter { gateReadyAt[$0.name] != nil }.count) / Double(gates.count)
            let calm = min(1, Double(stable) / Double(max(1, config.stableFrames)))
            let byTime = min(1, elapsed / max(0.001, config.hardCap))
            p += 0.15 * max(min(calm, ready), byTime)
        }
        if phase == .done { p = 1 }
        return min(1, p)
    }

    /// 表示用の進み具合（前回より小さくならない）。
    func displayProgress() -> Double {
        shownProgress = max(shownProgress, progress)
        return shownProgress
    }

    /// ウォームアップ中の毎フレーム（描画同期の後）に呼ぶ。dt = 前フレームからの経過秒。
    func frame(dt: Double) -> Directive {
        guard phase != .done else { return Directive(finished: true) }
        frameCount += 1
        let now = clock()
        if start == nil {
            start = now
            interval = FrameStats.signposter.beginInterval("battle.warmup")
        }
        if phase == .steps {
            runSteps(previousDt: dt)
            guard nextStep >= steps.count else { return Directive() }
            stepsEnd = clock()
            notes.append(String(format: "warmup steps: %d in %d frames, %.0f ms", steps.count, frameCount,
                                (stepsEnd! - start!) * 1000))
            phase = warmsShadowVariants ? .shadowVariants : .settle
            return Directive()
        }
        if phase == .shadowVariants {
            if variantFrames < config.shadowVariantFrames {
                variantFrames += 1
                return Directive(invertShadows: true)
            }
            shadowVariantsWarmed = true
            phase = .settle
        }
        // 落ち着き待ち
        settleFrames += 1
        stable = dt <= targetInterval * config.stableFactor ? stable + 1 : 0
        for g in gates where gateReadyAt[g.name] == nil && g.isReady() {
            gateReadyAt[g.name] = now - (start ?? now)
        }
        let allReady = gateReadyAt.count == gates.count
        if stable >= config.stableFrames && allReady {
            finish(reason: "stable")
            return Directive(finished: true)
        }
        if now - (start ?? now) >= config.hardCap && settleFrames >= config.minSettleFrames {
            timedOut = true
            var missing = gates.filter { gateReadyAt[$0.name] == nil }.map(\.name)
            if stable < config.stableFrames { missing.append("stable \(stable)/\(config.stableFrames)") }
            finish(reason: "hard cap (" + missing.joined(separator: ", ") + ")")
            return Directive(finished: true)
        }
        return Directive()
    }

    /// このフレームの予算（前フレームの間隔が長いほど広げる）。
    func stepBudget(previousDt dt: Double) -> Double {
        min(config.maxBudget, max(config.stepBudget, dt * config.slowFrameShare))
    }

    /// 予算内で段を続けて実行する。各フレーム最低 1 段は進め、重い段は予算の前半でだけ始める。
    private func runSteps(previousDt: Double) {
        let budget = stepBudget(previousDt: previousDt)
        let frameStart = clock()
        var ranAny = false
        while nextStep < steps.count {
            let step = steps[nextStep]
            let used = clock() - frameStart
            if ranAny && (used >= budget || (step.heavy && used >= budget * config.heavyStartShare)) { break }
            run(step)
            nextStep += 1
            ranAny = true
        }
    }

    private func run(_ step: WarmupStep) {
        let state = FrameStats.signposter.beginInterval("warmup.step", id: FrameStats.signposter.makeSignpostID(),
                                                        "\(step.name, privacy: .public)")
        let t0 = clock()
        step.run()
        let ms = (clock() - t0) * 1000
        FrameStats.signposter.endInterval("warmup.step", state)
        timings.append(StepTiming(name: step.name, heavy: step.heavy, ms: ms, frame: frameCount))
        doneWeight += WarmupScheduler.weight(step)
        notes.append(String(format: "warmup step %@%@ %.1f ms (frame %d)", step.name, step.heavy ? " [heavy]" : "", ms,
                            frameCount))
    }

    private func finish(reason: String) {
        phase = .done
        let total = elapsed
        var gateText = gates.map { g in
            gateReadyAt[g.name].map { String(format: "%@ %.0f ms", g.name, $0 * 1000) } ?? "\(g.name) not ready"
        }.joined(separator: ", ")
        if gateText.isEmpty { gateText = "no gates" }
        notes.append(String(format: "warmup done: %@ after %d frames, %.0f ms (settle %d frames; %@; shadow variants %@)",
                            reason, frameCount, total * 1000, settleFrames, gateText,
                            warmsShadowVariants ? (shadowVariantsWarmed ? "warmed" : "skipped") : "not needed"))
        if let interval { FrameStats.signposter.endInterval("battle.warmup", interval) }
        interval = nil
    }

    private static func weight(_ step: WarmupStep) -> Double { step.heavy ? 3 : 1 }
}
