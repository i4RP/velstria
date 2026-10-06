import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 観戦の土台: 起動種別ごとの観戦判定・視点・記録、シーク（キーフレーム・イベントを配らない・終わりからの巻き戻し）、
/// リプレイの最終 tick、死亡中の味方追従、設定のカメラ倍率の書き戻し。
@MainActor
final class SpectatorFoundationTests: XCTestCase {
    private func waitForSeek(_ c: BattleController, timeout: TimeInterval = 60) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while c.seekingToTick != nil && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func run(_ c: BattleController, ticks: Int) {
        // 1 フレーム = 1 tick（速度 1、上限内）
        for _ in 0..<ticks where !c.isEnded { c.frame(dt: Balance.dt) }
    }

    // MARK: 起動種別

    func testLaunchMatrix() {
        let standard = BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 1))
        XCTAssertFalse(standard.isSpectating)
        XCTAssertEqual(standard.localTeam, .blue)
        XCTAssertFalse(standard.isOnline)

        let spectate = BattleLaunch(config: MatchFactory.botMatch(seed: 1))
        XCTAssertTrue(spectate.isSpectating)
        XCTAssertNil(spectate.localTeam)

        let allBots = BattleLaunch(config: MatchFactory.customMatch(humanSide: nil, seed: 2))
        XCTAssertTrue(allBots.isAllBotsOffline)
        XCTAssertTrue(allBots.isSpectating, "人間のいない構成は観戦扱い（霧・操作・記録）")

        let online = MatchFactory.onlineMatch(humans: [OnlineHumanSlot(team: .red, position: .mid, heroID: "H002", displayName: "B")], seed: 3)
        let redMid = MatchFactory.onlineSeatIndex(team: .red, position: .mid)
        let seat = BattleLaunch(config: online, onlineSeat: redMid)
        XCTAssertFalse(seat.isSpectating)
        XCTAssertEqual(seat.localTeam, .red)
        let watcher = BattleLaunch(config: online, onlineSpectator: true)
        XCTAssertTrue(watcher.isOnline)
        XCTAssertTrue(watcher.isSpectating)
        XCTAssertNil(watcher.localTeam)
        XCTAssertFalse(watcher.isAllBotsOffline)

        let recorded = ReplayData(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", humanTeam: .red, seed: 4),
                                  frames: [], finalTick: 10, summary: nil)
        let replay = BattleLaunch(config: recorded.config, replay: recorded)
        XCTAssertTrue(replay.isSpectating)
        XCTAssertNil(replay.localTeam)
        XCTAssertEqual(replay.ownerSeat, recorded.config.players.firstIndex { $0.controller == .human })
        XCTAssertEqual(BattleLaunch(config: recorded.config, replay: recorded, replayOwnerSeat: 7).ownerSeat, 7)
    }

    func testControllerRolesVisionAndRecording() {
        let human = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 1)))
        XCTAssertEqual(human.viewerTeam, .blue)
        XCTAssertNotNil(human.humanHeroID)
        XCTAssertFalse(human.isSeekable)
        XCTAssertNotNil(human.recorder)
        human.spectatorVision = .red
        XCTAssertEqual(human.viewerTeam, .blue, "プレイヤーの視界は観戦者の設定で変わらない")

        let spectator = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 1)))
        XCTAssertNil(spectator.viewerTeam, "観戦の既定は全体が見える")
        XCTAssertNil(spectator.humanHeroID)
        XCTAssertTrue(spectator.isSeekable)
        XCTAssertNotNil(spectator.recorder, "AI 同士の観戦も記録する（入力なしの小さなリプレイ）")
        XCTAssertEqual(spectator.keyframes.map(\.tick), [0])
        spectator.spectatorVision = .red
        XCTAssertEqual(spectator.viewerTeam, .red)
        if case .followUnit = spectator.cameraMode {} else { XCTFail("観戦は最初のヒーローを追従: \(spectator.cameraMode)") }
        XCTAssertEqual(spectator.presentationFocusID, {
            if case .followUnit(let id) = spectator.cameraMode { return id } else { return nil }
        }())

        // 観戦者のズーム上書き
        XCTAssertEqual(spectator.effectiveCameraZoom, spectator.cameraZoom)
        spectator.cameraZoomOverride = 1.6
        XCTAssertEqual(spectator.effectiveCameraZoom, 1.6)
    }

    func testReplayFollowsOwnerAndUsesRecordedSummaryWhenLeavingEarly() {
        let config = MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", humanTeam: .red, seed: 9)
        let live = BattleController(launch: BattleLaunch(config: config))
        live.send(.setAutoLevel(enabled: true))
        run(live, ticks: 600)
        let outcome = live.makeOutcome(abandoned: true)
        guard let data = outcome.replay else { return XCTFail("記録されたリプレイ") }
        XCTAssertNotNil(data.timeline, "年表を同梱する")
        XCTAssertEqual(data.finalTick, 600)

        let replay = BattleController(launch: BattleLaunch(config: data.config, replay: data))
        let ownerSeat = data.config.players.firstIndex { $0.controller == .human }!
        XCTAssertEqual(replay.ownerHeroID, replay.heroID(forSeat: ownerSeat))
        XCTAssertEqual(replay.cameraMode, .followUnit(replay.ownerHeroID!), "リプレイは持ち主を追従して始まる")
        XCTAssertNotNil(replay.fullTimeline, "年表入りのリプレイは先まで分かる")
        // 最終 tick で止まり、途中で抜けた記録は中断終了になる
        run(replay, ticks: 700)
        XCTAssertEqual(replay.state.tick, 600)
        XCTAssertTrue(replay.isEnded)
        XCTAssertEqual(replay.state.endReason, .aborted)
        XCTAssertEqual(replay.state.stateHash(), live.state.stateHash())

        // 途中で抜けても記録時の結果を見せる
        let replay2 = BattleController(launch: BattleLaunch(config: data.config, replay: data))
        run(replay2, ticks: 120)
        let early = replay2.makeOutcome(abandoned: true)
        XCTAssertEqual(early.summary, data.summary)
    }

    // MARK: シーク

    func testSeekMatchesLinearPlayAndDispatchesNothing() async {
        let config = MatchFactory.botMatch(seed: 31)
        let linear = BattleController(launch: BattleLaunch(config: config))
        run(linear, ticks: 2000)
        let hashAt1500: UInt64 = {
            let probe = BattleController(launch: BattleLaunch(config: config))
            run(probe, ticks: 1500)
            return probe.state.stateHash()
        }()

        let c = BattleController(launch: BattleLaunch(config: config))
        var delivered = 0
        c.subscribe { delivered += $0.count }
        run(c, ticks: 2000)
        XCTAssertEqual(c.state.stateHash(), linear.state.stateHash())
        XCTAssertEqual(c.keyframes.map(\.tick), [0, 900, 1800], "30 秒毎のキーフレーム")
        let timelineAt2000 = c.timeline
        let epoch = c.presentationEpoch
        delivered = 0

        // 巻き戻し
        c.requestSeek(toTick: 1500)
        XCTAssertEqual(c.seekingToTick, 1500)
        c.frame(dt: Balance.dt)   // シーク中は進まない
        await waitForSeek(c)
        XCTAssertNil(c.seekingToTick)
        XCTAssertEqual(c.state.tick, 1500)
        XCTAssertEqual(c.state.stateHash(), hashAt1500)
        XCTAssertEqual(delivered, 0, "シークで飛ばした区間のイベントは配らない")
        XCTAssertGreaterThan(c.presentationEpoch, epoch)
        XCTAssertTrue(c.timeline.events.allSatisfy { $0.tick <= 1500 }, "現在までの年表")
        XCTAssertEqual(c.knownTimeline, timelineAt2000, "巻き戻しても分かっている先の年表は残る")
        XCTAssertEqual(c.displayTimeline.coveredTick, 2000)

        // 早送りで元の位置へ（保存済みのキーフレーム 1800 から）: 年表も同じ
        c.requestSeek(toTick: 2000)
        await waitForSeek(c)
        XCTAssertEqual(c.state.stateHash(), linear.state.stateHash())
        XCTAssertEqual(c.timeline, timelineAt2000)
        XCTAssertEqual(c.knownTimeline, linear.knownTimeline)

        // 相対シーク・範囲外は丸める
        c.seek(bySeconds: -10_000)
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 0)

        // シーク後もそのまま再生できる
        run(c, ticks: 30)
        XCTAssertEqual(c.state.tick, 30)
        XCTAssertGreaterThan(delivered, 0)
    }

    func testSeekBackFromTheEndResetsEndedAndFrameStepWorks() async {
        let config = MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 12)
        let live = BattleController(launch: BattleLaunch(config: config))
        run(live, ticks: 300)
        guard let data = live.makeOutcome(abandoned: true).replay else { return XCTFail() }

        let c = BattleController(launch: BattleLaunch(config: data.config, replay: data))
        run(c, ticks: 400)
        XCTAssertTrue(c.isEnded)
        c.requestSeek(toTick: 100)
        await waitForSeek(c)
        XCTAssertFalse(c.isEnded, "終わりから戻ると再生できる")
        XCTAssertEqual(c.state.tick, 100)
        XCTAssertNil(c.state.endReason)

        // コマ送りは一時停止中だけ
        c.stepTicks(5)
        XCTAssertEqual(c.state.tick, 100)
        c.isPaused = true
        c.stepTicks(5)
        XCTAssertEqual(c.state.tick, 105)
        c.isPaused = false

        // 最終 tick より先へは行かない
        c.requestSeek(toTick: 10_000)
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 300)
        XCTAssertTrue(c.isEnded)
    }

    func testPlayersCannotSeekAndRestoreBumpsEpoch() {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 2)))
        run(c, ticks: 60)
        c.requestSeek(toTick: 10)
        XCTAssertNil(c.seekingToTick)
        XCTAssertEqual(c.state.tick, 60)
        let epoch = c.presentationEpoch
        c.restore(c.state)
        XCTAssertEqual(c.presentationEpoch, epoch + 1)
        XCTAssertFalse(c.recorder!.isIncomplete, "同じ tick への再同期は記録を壊さない")
        var ahead = c.state
        ahead.tick += 30
        c.restore(ahead)
        XCTAssertTrue(c.recorder!.isIncomplete, "tick が飛ぶ再同期の記録は保存しない")
        XCTAssertNil(c.makeOutcome(abandoned: true).replay)
    }

    // MARK: 死亡中の味方追従・カメラ倍率

    func testDeathSpectateFollowsAlliesOnly() {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 4)))
        let model = HUDModel(controller: c)
        model.start(app: app, onFinish: { _ in })
        defer { model.stop() }
        let s = c.state
        let me = c.humanHeroID!
        let ally = s.heroIndices(team: .blue).map { s.units[$0].id }.first { $0 != me }!
        let enemy = s.heroIndices(team: .red).map { s.units[$0].id }.first!

        // 生きている間は味方も追えない
        model.follow(ally)
        XCTAssertEqual(c.cameraMode, .followHero)
        XCTAssertTrue(model.followableAllies.contains(ally))

        // 死亡中: 味方は追える・敵は追えない
        var dead = c.state
        dead.units[c.humanIndex!].hero?.respawnTimer = 12
        c.restore(dead)
        model.follow(ally)
        XCTAssertEqual(c.cameraMode, .followUnit(ally))
        XCTAssertEqual(c.presentationFocusID, ally)
        model.follow(enemy)
        XCTAssertEqual(c.cameraMode, .followHero, "敵は追えない（霧の向こうが見えてしまう）")
        model.follow(ally)
        // ミニマップで覗いて離すと味方へ戻る
        model.minimapDragged(to: Vec2(5000, 5000))
        if case .free = c.cameraMode {} else { XCTFail() }
        model.minimapReleased()
        XCTAssertEqual(c.cameraMode, .followUnit(ally))
        // 復活したら自分へ戻る（respawned イベント）
        model.handle([.respawned(heroID: me, pos: Vec2(0, 0))])
        XCTAssertEqual(c.cameraMode, .followHero)
        XCTAssertNil(model.cameraFollowID)
    }

    func testRefreshDoesNotRevertControllerZoom() {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 4)))
        let model = HUDModel(controller: c)
        model.start(app: app, onFinish: { _ in })
        defer { model.stop() }
        XCTAssertEqual(c.cameraZoom, app.profile.settings.cameraZoom)
        c.cameraZoom = 1.27
        model.refresh()
        XCTAssertEqual(c.cameraZoom, 1.27, "15Hz の更新で設定値に戻さない")
        model.updateSetting(\.cameraZoom, 0.9)
        XCTAssertEqual(c.cameraZoom, 0.9, "設定を変えた時は反映する")
    }
}
