import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 観戦の事前計算（ReplayBaker）: キーフレーム・年表が通常の再生と一致する（stateHash・状態の全体）、リプレイの最終 tick で
/// 中断終了まで同じ、メインスレッド外の正確なシーク（年表に穴を開けない・イベントを配らない）、保存する年表は記録した区間まで、
/// メモリ上限、停止、端末温度での進め方。
@MainActor
final class ReplayBakerTests: XCTestCase {
    private func run(_ c: BattleController, ticks: Int) {
        // 1 フレーム = 1 tick（速度 1、上限内）
        for _ in 0..<ticks where !c.isEnded { c.frame(dt: Balance.dt) }
    }

    private func waitUntil(timeout: TimeInterval = 120, _ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while !condition() && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func waitForSeek(_ c: BattleController) async {
        await waitUntil { c.seekingToTick == nil }
    }

    /// 状態の全体（stateHash に入らない乱数・AI・視界も含む）。
    private func encoded(_ s: SimState) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(s)) ?? Data()
    }

    /// 通常の再生で、指定 tick の状態を集める。
    private func linearStates(_ launch: BattleLaunch, at ticks: Set<Int>, until end: Int) -> (BattleController, [Int: SimState]) {
        let c = BattleController(launch: launch)
        var out: [Int: SimState] = [:]
        if ticks.contains(0) { out[0] = c.state }
        while c.state.tick < end && !c.isEnded {
            c.frame(dt: Balance.dt)
            if ticks.contains(c.state.tick) { out[c.state.tick] = c.state }
        }
        return (c, out)
    }

    // MARK: 事前計算 = 通常の再生

    func testBakedKeyframesAndTimelineMatchLinearPlay() async throws {
        let launch = BattleLaunch(config: MatchFactory.botMatch(seed: 41))
        let c = BattleController(launch: launch)
        var delivered = 0
        c.subscribe { delivered += $0.count }
        let baker = try XCTUnwrap(ReplayBaker(controller: c, keyframeInterval: 300, limitTick: 900))
        baker.start(waitForPresentation: false)
        await waitUntil { baker.isFinished }
        XCTAssertTrue(baker.isFinished)
        XCTAssertEqual(baker.bakedUntilTick, 900)
        XCTAssertEqual(c.keyframes.map(\.tick), [0, 300, 600, 900], "キーフレームは tick 昇順・重複なし")
        XCTAssertEqual(c.displayTimeline.coveredTick, 900, "シークバーの網掛けは displayTimeline.coveredTick")
        XCTAssertEqual(c.state.tick, 0, "事前計算は再生位置を動かさない")
        XCTAssertEqual(delivered, 0, "事前計算はイベントを配らない")

        let (linear, states) = linearStates(launch, at: [300, 600, 900], until: 900)
        for k in c.keyframes where k.tick > 0 {
            let expected = try XCTUnwrap(states[k.tick])
            XCTAssertEqual(k.stateHash(), expected.stateHash(), "tick \(k.tick) の stateHash")
            XCTAssertEqual(encoded(k), encoded(expected), "tick \(k.tick) の状態の全体")
        }
        XCTAssertEqual(c.knownTimeline, linear.knownTimeline, "年表も通常の再生と同じ")
        XCTAssertTrue(c.timeline.events.allSatisfy { $0.tick <= c.state.tick }, "現在までの年表は今の tick まで")

        // 再生すると自前のキーフレームを重複して足さず、通常の再生と同じ状態になる
        run(c, ticks: 900)
        XCTAssertEqual(c.keyframes.map(\.tick), [0, 300, 600, 900])
        XCTAssertEqual(c.state.stateHash(), linear.state.stateHash())
        XCTAssertEqual(c.knownTimeline, linear.knownTimeline)
        baker.stop()
    }

    func testReplayBakeStopsAtFinalTickAndAbortsLikePlayback() async throws {
        let config = MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 7)
        let live = BattleController(launch: BattleLaunch(config: config))
        live.send(.setAutoLevel(enabled: true))
        for k in 0..<300 {
            if k % 45 == 0 { live.joystick(CGVector(dx: k % 90 == 0 ? 1 : -1, dy: -0.4)) }
            live.frame(dt: Balance.dt)
        }
        let data = try XCTUnwrap(live.makeOutcome(abandoned: true).replay)
        XCTAssertEqual(data.finalTick, 300)
        XCTAssertFalse(data.frames.isEmpty, "入力のある記録")

        let launch = BattleLaunch(config: data.config, replay: data)
        let c = BattleController(launch: launch)
        let baker = try XCTUnwrap(ReplayBaker(controller: c, keyframeInterval: 150))
        XCTAssertEqual(baker.plan.limitTick, 300, "リプレイは記録の最終 tick まで")
        baker.start(waitForPresentation: false)
        await waitUntil { baker.isFinished }
        XCTAssertEqual(baker.bakedUntilTick, 300)
        XCTAssertEqual(c.keyframes.map(\.tick), [0, 150, 300])

        let (linear, _) = linearStates(launch, at: [], until: 10_000)
        XCTAssertEqual(linear.state.tick, 300)
        XCTAssertEqual(linear.state.endReason, .aborted, "途中で抜けた記録は最終 tick で中断終了")
        // キーフレームは中断する前の状態（BattleController のキーフレームと同じ）。コアの ReplayPlayer と比べる
        let player = ReplayPlayer(data: data)
        var reference: [Int: SimState] = [:]
        while !player.isFinished {
            player.stepOnce()
            if player.currentTick % 150 == 0 { reference[player.currentTick] = player.state }
        }
        for k in c.keyframes where k.tick > 0 {
            let expected = try XCTUnwrap(reference[k.tick])
            XCTAssertEqual(k.stateHash(), expected.stateHash(), "tick \(k.tick)")
            XCTAssertEqual(encoded(k), encoded(expected), "tick \(k.tick) の状態の全体")
        }
        XCTAssertEqual(c.knownTimeline, linear.knownTimeline, "最終 tick の中断まで年表が同じ")

        // 最終 tick へのシークは通常の再生と同じく中断終了になる
        c.requestSeek(toTick: 300)
        await waitForSeek(c)
        XCTAssertTrue(c.isEnded)
        XCTAssertEqual(c.state.stateHash(), linear.state.stateHash())
        c.requestSeek(toTick: 0)
        await waitForSeek(c)
        XCTAssertFalse(c.isEnded)

        // 事前計算の後の再生も同じ結末
        run(c, ticks: 400)
        XCTAssertTrue(c.isEnded)
        XCTAssertEqual(c.state.stateHash(), linear.state.stateHash())
        XCTAssertEqual(c.state.endReason, .aborted)
        baker.stop()
    }

    // MARK: メインスレッド外の正確なシーク

    func testExactSeeksMatchLinearPlayAndKeepTheTimelineWhole() async throws {
        let launch = BattleLaunch(config: MatchFactory.botMatch(seed: 51))
        let (linear, states) = linearStates(launch, at: [150, 1100, 1200], until: 1200)
        let c = BattleController(launch: launch)
        var delivered = 0
        c.subscribe { delivered += $0.count }
        let baker = try XCTUnwrap(ReplayBaker(controller: c, keyframeInterval: 300, limitTick: 600))
        baker.start(waitForPresentation: false)
        XCTAssertNotNil(c.seekStateProvider, "シークを引き受ける")
        await waitUntil { baker.isFinished }
        XCTAssertEqual(c.knownTimeline.coveredTick, 600)

        // 事前計算の先へ: 年表の範囲内の状態（600）から進め、年表も伸ばす
        c.requestSeek(toTick: 1100)
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 1100)
        XCTAssertEqual(c.state.stateHash(), states[1100]?.stateHash())
        XCTAssertEqual(encoded(c.state), encoded(try XCTUnwrap(states[1100])))
        XCTAssertGreaterThanOrEqual(c.knownTimeline.coveredTick, 1100, "飛んだ区間の年表も作る（穴を開けない）")
        var expected = linear.knownTimeline
        expected.truncate(after: 1100)
        XCTAssertEqual(c.timeline, expected)
        XCTAssertTrue(baker.fineRing.contains { $0.tick == 1100 }, "結果を細かい輪に残す")
        XCTAssertEqual(delivered, 0, "シークで飛ばした区間のイベントは配らない")

        // 巻き戻し
        c.requestSeek(toTick: 150)
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 150)
        XCTAssertEqual(c.state.stateHash(), states[150]?.stateHash())
        XCTAssertEqual(delivered, 0)

        // そのまま再生しても通常の再生と同じ（年表も途切れない）
        run(c, ticks: 1050)
        XCTAssertEqual(c.state.tick, 1200)
        XCTAssertEqual(c.state.stateHash(), states[1200]?.stateHash())
        XCTAssertEqual(c.knownTimeline, linear.knownTimeline)
        XCTAssertGreaterThan(delivered, 0)
        baker.stop()
        XCTAssertNil(c.seekStateProvider, "停止でシークの登録を外す")
    }

    func testBestBasePrefersTheNearestEarlierState() async throws {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 52)))
        let baker = try XCTUnwrap(ReplayBaker(controller: c, keyframeInterval: 300, limitTick: 300))
        run(c, ticks: 160)
        baker.sampleRing()
        XCTAssertEqual(baker.fineRing.map(\.tick), [160], "再生位置を細かい輪に残す")
        run(c, ticks: 100)
        baker.sampleRing()
        XCTAssertEqual(baker.fineRing.map(\.tick), [160], "間隔（150 tick）未満では残さない")
        run(c, ticks: 60)
        baker.sampleRing()
        XCTAssertEqual(baker.fineRing.map(\.tick), [160, 320])
        XCTAssertEqual(baker.bestBase(atOrBefore: 200, controller: c)?.tick, 160, "細かい輪 > キーフレーム 0")
        XCTAssertEqual(baker.bestBase(atOrBefore: 400, controller: c)?.tick, 320, "今の状態")
        XCTAssertEqual(baker.bestBase(atOrBefore: 100, controller: c)?.tick, 0, "試合開始時のキーフレーム")
    }

    // MARK: 保存・上限・停止

    func testRecordedSpectateTimelineStopsAtTheRecording() async throws {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 43)))
        let baker = try XCTUnwrap(ReplayBaker(controller: c, keyframeInterval: 300, limitTick: 600))
        baker.start(waitForPresentation: false)
        await waitUntil { baker.isFinished }
        XCTAssertEqual(c.knownTimeline.coveredTick, 600, "先まで分かっている")
        run(c, ticks: 90)
        baker.stop()
        let replay = try XCTUnwrap(c.makeOutcome(abandoned: true).replay)
        XCTAssertEqual(replay.finalTick, 90)
        let t = try XCTUnwrap(replay.timeline)
        XCTAssertEqual(t.coveredTick, 90, "保存する年表は記録した区間まで")
        XCTAssertTrue(t.events.allSatisfy { $0.tick <= 90 })
        XCTAssertTrue(t.samples.allSatisfy { $0.tick <= 90 })
    }

    func testForwardSeekKeepsTheSpectateRecordingPlayable() async throws {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 46)))
        let baker = try XCTUnwrap(ReplayBaker(controller: c, keyframeInterval: 300, limitTick: 600))
        baker.start(waitForPresentation: false)
        await waitUntil { baker.isFinished }
        run(c, ticks: 30)
        // 事前計算のキーフレーム（300）からメインスレッド外で進めて飛ぶ（途中の tick をここでは進めない）
        c.requestSeek(toTick: 450)
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 450)
        let hash = c.state.stateHash()
        baker.stop()
        let replay = try XCTUnwrap(c.makeOutcome(abandoned: true).replay)
        XCTAssertEqual(replay.finalTick, 450, "飛んだ先まで記録に含める（ここで進めた時と同じ）")
        XCTAssertEqual(replay.timeline?.coveredTick, 450)
        let player = ReplayPlayer(data: replay)
        while !player.isFinished { player.stepOnce() }
        XCTAssertEqual(player.currentTick, 450)
        XCTAssertEqual(player.state.stateHash(), hash, "保存した観戦の記録は飛んだ先の状態を再現する")
    }

    func testKeyframeCapStillBakesTheTimeline() async throws {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 44)))
        let baker = try XCTUnwrap(ReplayBaker(controller: c, keyframeInterval: 150, maxKeyframes: 2, limitTick: 600))
        baker.start(waitForPresentation: false)
        await waitUntil { baker.isFinished }
        XCTAssertEqual(c.keyframes.map(\.tick), [0, 150, 300], "上限を超えたキーフレームは渡さない")
        XCTAssertEqual(baker.adoptedKeyframes, 2)
        XCTAssertEqual(c.displayTimeline.coveredTick, 600, "年表は最後まで作る")
        baker.stop()
    }

    func testStartWaitsForPresentationAndStopCancels() async throws {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 45)))
        let baker = try XCTUnwrap(ReplayBaker(controller: c, keyframeInterval: 150, limitTick: 3000))
        baker.start()
        XCTAssertTrue(baker.isRunning)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(baker.bakedUntilTick, 0, "読み込み幕が上がるまで計算しない")
        c.markPresentationReady()
        await waitUntil { baker.bakedUntilTick > 0 }
        XCTAssertGreaterThan(baker.bakedUntilTick, 0)
        baker.stop()
        XCTAssertFalse(baker.isRunning)
        XCTAssertNil(c.seekStateProvider)
        let stoppedAt = baker.bakedUntilTick
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(baker.bakedUntilTick, stoppedAt, "停止後は採用しない")
        XCTAssertFalse(baker.isFinished)

        // 登録を外した後のシークはコントローラが自分で進める
        c.requestSeek(toTick: 200)
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 200)
    }

    func testOnlyForSeekableLaunches() {
        let player = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P",
                                                                                               seed: 1)))
        XCTAssertNil(ReplayBaker(controller: player), "プレイヤーの試合はシークしない")
        let spectate = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 1)))
        let baker = ReplayBaker(controller: spectate)
        XCTAssertNotNil(baker)
        XCTAssertEqual(baker?.plan.limitTick, spectate.seekUpperBound, "観戦は試合の最大時間まで")
        XCTAssertEqual(baker?.plan.keyframeInterval, BattleController.keyframeInterval)
        XCTAssertEqual(baker?.plan.maxKeyframes, ReplayBaker.defaultMaxKeyframes)
        XCTAssertGreaterThanOrEqual(ReplayBaker.defaultMaxKeyframes * BattleController.keyframeInterval,
                                    Int(MatchFactory.botMatch(seed: 1).maxDuration / Balance.dt),
                                    "既定の観戦（40 分）はキーフレームの上限に収まる")
        XCTAssertNil(spectate.seekStateProvider, "start までは登録しない")
    }

    func testPaceBacksOffWhenHotOrInLowPowerMode() {
        XCTAssertEqual(ReplayBakeEngine.pace(thermal: .nominal, lowPower: false), .full)
        XCTAssertEqual(ReplayBakeEngine.pace(thermal: .fair, lowPower: false), .full)
        XCTAssertEqual(ReplayBakeEngine.pace(thermal: .nominal, lowPower: true), .slow(.milliseconds(50)))
        XCTAssertEqual(ReplayBakeEngine.pace(thermal: .serious, lowPower: false), .slow(.milliseconds(250)))
        XCTAssertEqual(ReplayBakeEngine.pace(thermal: .serious, lowPower: true), .slow(.milliseconds(250)))
        XCTAssertEqual(ReplayBakeEngine.pace(thermal: .critical, lowPower: false), .halt)
    }

    func testInputTableKeepsRecordedOrderWithinATick() {
        let a = HeroCommand(heroID: 1, command: .stop, sequence: 1)
        let b = HeroCommand(heroID: 1, command: .recall, sequence: 2)
        let c = HeroCommand(heroID: 2, command: .stop, sequence: 3)
        let table = ReplayBakeEngine.inputTable([ReplayFrame(tick: 5, commands: [a, b]), ReplayFrame(tick: 9, commands: [c]),
                                                 ReplayFrame(tick: 5, commands: [c])])
        XCTAssertEqual(table[5], [a, b, c])
        XCTAssertEqual(table[9], [c])
        XCTAssertNil(table[6])
    }
}
