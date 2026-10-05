import XCTest
@testable import VELSTRIA

// battle-renderer（性能）: 読み込み幕の裏のウォームアップ（WarmupScheduler）。
// 段は 1 フレームの予算内でまとめ（重い段は予算の前半でだけ始める。描画が遅いと予算を広げる）、影の両状態、
// 落ち着き + ゲートで完了、上限で必ず終わることを確かめる。

@MainActor
final class WarmupSchedulerTests: XCTestCase {
    /// 時計を手で進める（段の実行に所要時間を持たせる）。
    private final class Clock {
        var now: Double = 100
    }

    private func steps(_ spec: [(String, Bool, Double)], clock: Clock, log: @escaping (String) -> Void) -> [WarmupStep] {
        spec.map { name, heavy, cost in
            WarmupStep(name, heavy: heavy) {
                clock.now += cost
                log(name)
            }
        }
    }

    private func makeScheduler(_ spec: [(String, Bool, Double)], clock: Clock, shadows: Bool = false,
                               gates: [WarmupScheduler.Gate] = [], log: @escaping (String) -> Void = { _ in }) -> WarmupScheduler {
        WarmupScheduler(steps: steps(spec, clock: clock, log: log), targetInterval: 1.0 / 60, warmShadowVariants: shadows,
                        gates: gates, clock: { clock.now })
    }

    /// 1 フレーム進める（描画の間隔 dt だけ時計も進む）。
    private func frame(_ s: WarmupScheduler, _ clock: Clock, dt: Double = 1.0 / 60) -> WarmupScheduler.Directive {
        clock.now += dt
        return s.frame(dt: dt)
    }

    func testHeavyStepsStartOnlyInTheFirstHalfOfTheBudget() {
        let clock = Clock()
        var ran: [[String]] = []
        var current: [String] = []
        // 60fps: 予算 10 ms。heroes（6 ms）の後は前半（5 ms）を過ぎているので重い monsters は次のフレームへ
        let s = makeScheduler([("heroes", true, 0.006), ("monsters", true, 0.001), ("text", false, 0.001),
                               ("props", true, 0.002)], clock: clock) {
            current.append($0)
        }
        while s.phase == .steps {
            current = []
            _ = frame(s, clock)
            ran.append(current)
        }
        XCTAssertEqual(ran, [["heroes"], ["monsters", "text", "props"]])
        XCTAssertEqual(s.timings.map(\.frame), [1, 2, 2, 2])
        XCTAssertEqual(s.timings.first?.ms ?? 0, 6, accuracy: 1e-6)
    }

    /// 描画が遅い環境（GPU の無い CI など）では予算を広げ、段の数だけフレームを費やさない。
    func testSlowFramesWidenTheBudget() {
        let clock = Clock()
        var perFrame: [Int] = []
        var count = 0
        let spec = (0..<12).map { ("heavy\($0)", true, 0.010) }
        let s = makeScheduler(spec, clock: clock) { _ in count += 1 }
        XCTAssertEqual(s.stepBudget(previousDt: 1.0 / 60), 0.010, accuracy: 1e-9)
        XCTAssertEqual(s.stepBudget(previousDt: 0.3), 0.060, accuracy: 1e-9, "上限 60 ms")
        while s.phase == .steps {
            count = 0
            _ = frame(s, clock, dt: 0.3)
            perFrame.append(count)
        }
        // 予算 60 ms・重い段は 30 ms 未満で開始 → 10 ms の段が 3 つずつ
        XCTAssertEqual(perFrame, [3, 3, 3, 3])
    }

    func testLightStepsShareTheFrameBudget() {
        let clock = Clock()
        var perFrame: [Int] = []
        var count = 0
        let spec = (0..<10).map { ("light\($0)", false, 0.0021) } + [("heavy", true, 0.010)]
        let s = makeScheduler(spec, clock: clock) { _ in count += 1 }
        while s.phase == .steps {
            count = 0
            _ = frame(s, clock)
            perFrame.append(count)
        }
        // 2.1 ms × 5 = 10.5 ms で予算（10 ms）に達する → 5・5、重い段は前半を過ぎているので次のフレームの先頭で実行
        XCTAssertEqual(perFrame, [5, 5, 1])
        XCTAssertEqual(s.timings.last?.name, "heavy")
        XCTAssertEqual(s.nextStep, spec.count)
        XCTAssertTrue(s.notes.contains { $0.contains("heavy [heavy]") }, "段の所要は計測ログに残る")
    }

    func testFinishesOnlyAfterStableFramesAndReadyGates() {
        let clock = Clock()
        var programsReady = false
        let s = makeScheduler([("effects", false, 0.001)], clock: clock,
                              gates: [WarmupScheduler.Gate("programs") { programsReady }])
        _ = frame(s, clock)
        XCTAssertEqual(s.phase, .settle)
        // ゲートが揃わない間は、落ち着いていても終えない
        for _ in 0..<20 { XCTAssertFalse(frame(s, clock).finished) }
        programsReady = true
        XCTAssertTrue(frame(s, clock).finished, "揃った時点で落ち着いていれば終える")
        XCTAssertTrue(s.isDone)
        XCTAssertFalse(s.timedOut)
        XCTAssertEqual(s.displayProgress(), 1)
        XCTAssertTrue(s.notes.last?.contains("stable") ?? false)
    }

    func testSlowFramesResetTheStableCount() {
        let clock = Clock()
        let s = makeScheduler([], clock: clock)
        _ = frame(s, clock)   // 段なし → 落ち着き待ちへ
        for _ in 0..<7 { XCTAssertFalse(frame(s, clock).finished) }
        // シェーダーのコンパイル等で 1 フレーム遅れた → 数え直し
        XCTAssertFalse(frame(s, clock, dt: 0.05).finished)
        for _ in 0..<7 { XCTAssertFalse(frame(s, clock).finished) }
        XCTAssertTrue(frame(s, clock).finished)
        XCTAssertEqual(s.frameCount, 1 + 7 + 1 + 8)
    }

    func testHardCapAlwaysEndsWarmup() {
        let clock = Clock()
        let s = makeScheduler([("effects", false, 0.001)], clock: clock,
                              gates: [WarmupScheduler.Gate("postProcess") { false }])
        var frames = 0
        var finished = false
        while !finished && frames < 1000 {
            finished = frame(s, clock).finished
            frames += 1
        }
        XCTAssertTrue(finished, "ゲートが揃わなくても終わる")
        XCTAssertTrue(s.timedOut)
        XCTAssertLessThanOrEqual(s.elapsed, s.config.hardCap + 0.05)
        XCTAssertGreaterThanOrEqual(s.elapsed, s.config.hardCap - 0.05)
        XCTAssertTrue(s.notes.last?.contains("postProcess") ?? false, "揃わなかったものをログに残す")
    }

    func testStepsCompleteEvenWhenTheyExceedTheCap() {
        let clock = Clock()
        // 1 段 1.5 秒の重い段が 3 つ（合計で上限を超える）→ すべて実行してから終える
        let s = makeScheduler([("a", true, 1.5), ("b", true, 1.5), ("c", true, 1.5)], clock: clock,
                              gates: [WarmupScheduler.Gate("never") { false }])
        var finished = false
        var frames = 0
        while !finished && frames < 100 {
            finished = frame(s, clock).finished
            frames += 1
        }
        XCTAssertTrue(finished)
        XCTAssertEqual(s.timings.map(\.name), ["a", "b", "c"], "準備の段は打ち切らない")
        XCTAssertGreaterThanOrEqual(frames, 3 + s.config.minSettleFrames)
    }

    func testShadowVariantsAreRenderedBeforeSettling() {
        let clock = Clock()
        let s = makeScheduler([("effects", false, 0.001)], clock: clock, shadows: true)
        XCTAssertEqual(frame(s, clock), WarmupScheduler.Directive())
        var inverted = 0
        var directives: [WarmupScheduler.Directive] = []
        for _ in 0..<(s.config.shadowVariantFrames + 1) {
            let d = frame(s, clock)
            directives.append(d)
            if d.invertShadows { inverted += 1 }
        }
        XCTAssertEqual(inverted, s.config.shadowVariantFrames, "影を反転した状態で数フレーム描く")
        XCTAssertFalse(directives.last?.invertShadows ?? true, "その後は元へ戻す")
        XCTAssertTrue(s.shadowVariantsWarmed)
        var finished = false
        for _ in 0..<20 where !finished { finished = frame(s, clock).finished }
        XCTAssertTrue(finished)
        XCTAssertTrue(s.notes.last?.contains("shadow variants warmed") ?? false)
    }

    func testProgressIsMonotonicAndReachesOne() {
        let clock = Clock()
        var ready = false
        let spec = (0..<6).map { ("s\($0)", $0 % 2 == 0, 0.003) }
        let s = makeScheduler(spec, clock: clock, shadows: true, gates: [WarmupScheduler.Gate("g") { ready }])
        var last = s.displayProgress()
        XCTAssertEqual(last, 0)
        var finished = false
        var frames = 0
        while !finished && frames < 400 {
            if frames == 20 { ready = true }
            finished = frame(s, clock, dt: frames % 7 == 3 ? 0.04 : 1.0 / 60).finished
            let p = s.displayProgress()
            XCTAssertGreaterThanOrEqual(p, last)
            XCTAssertLessThanOrEqual(p, 1)
            last = p
            frames += 1
        }
        XCTAssertTrue(finished)
        XCTAssertEqual(last, 1)
    }

    func testEmptyPlanStillSettles() {
        let clock = Clock()
        let s = makeScheduler([], clock: clock)
        var frames = 0
        while !frame(s, clock).finished { frames += 1 }
        XCTAssertEqual(frames + 1, 1 + s.config.stableFrames)
        XCTAssertTrue(s.frame(dt: 0).finished, "完了後は完了を返し続ける")
    }
}
