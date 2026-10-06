import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

/// 観戦・リプレイの再生バー: 右端（リプレイ = 最終 tick、観戦 = 分かっている所）・網掛け・0.1 秒の時刻・印・次の見どころ、
/// ±秒・最初から・コマ送り・速度の切り替え、再生終了から「もう一度見る」、オンラインの観戦席（LIVE・操作なし）。
@MainActor
final class HUDReplayTransportTests: XCTestCase {
    private var retained: [AnyObject] = []

    override func tearDown() {
        retained.removeAll()
        super.tearDown()
    }

    private func start(_ launch: BattleLaunch) -> (BattleController, HUDModel) {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        retained.append(app)
        let c = BattleController(launch: launch)
        let m = HUDModel(controller: c)
        m.start(app: app, onFinish: { _ in })
        addTeardownBlock { @MainActor in m.stop() }
        return (c, m)
    }

    private func run(_ c: BattleController, ticks: Int) {
        for _ in 0..<ticks where !c.isEnded { c.frame(dt: Balance.dt) }
    }

    private func waitForSeek(_ c: BattleController, timeout: TimeInterval = 60) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while c.seekingToTick != nil && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: 純粋関数

    func testTransportEndForReplayAndLiveSpectate() {
        let replay = HUDSpectatorState.transport(tick: 100, finalTick: 600, coveredTick: 200, upperBound: 600, seekingTo: nil,
                                                 paused: false, speed: 2, ended: false, seekable: true, liveWatcher: false,
                                                 delaySeconds: nil, watchers: 0, nextFightTick: nil)
        XCTAssertEqual(replay.endTick, 600, "リプレイの右端は最終 tick")
        XCTAssertTrue(replay.isEndKnown)
        XCTAssertEqual(replay.coveredTick, 200)
        XCTAssertEqual(replay.fraction, 100.0 / 600, accuracy: 1e-9)

        let live = HUDSpectatorState.transport(tick: 1200, finalTick: nil, coveredTick: 1200, upperBound: 72_000, seekingTo: nil,
                                               paused: false, speed: 1, ended: false, seekable: true, liveWatcher: false,
                                               delaySeconds: nil, watchers: 0, nextFightTick: nil)
        XCTAssertEqual(live.endTick, 1200, "AI 同士の観戦は見た所まで")
        XCTAssertFalse(live.isEndKnown)
        // 巻き戻した後も見た所までがバーに残る
        let rewound = HUDSpectatorState.transport(tick: 300, finalTick: nil, coveredTick: 1200, upperBound: 72_000,
                                                  seekingTo: nil, paused: true, speed: 1, ended: false, seekable: true,
                                                  liveWatcher: false, delaySeconds: nil, watchers: 0, nextFightTick: nil)
        XCTAssertEqual(rewound.endTick, 1200)
        XCTAssertEqual(rewound.fraction, 0.25, accuracy: 1e-9)
        // シーク中は目標の位置を見せる
        let seeking = HUDSpectatorState.transport(tick: 300, finalTick: 600, coveredTick: 600, upperBound: 600, seekingTo: 450,
                                                  paused: false, speed: 1, ended: false, seekable: true, liveWatcher: false,
                                                  delaySeconds: nil, watchers: 0, nextFightTick: nil)
        XCTAssertEqual(seeking.displayTick, 450)
        // オンラインの観戦席（B33）: LIVE と遅延だけ
        let watcher = HUDSpectatorState.transport(tick: 300, finalTick: nil, coveredTick: 300, upperBound: 72_000, seekingTo: nil,
                                                  paused: false, speed: 1, ended: false, seekable: false, liveWatcher: true,
                                                  delaySeconds: 30, watchers: 3, nextFightTick: nil)
        XCTAssertTrue(watcher.isLiveWatcher)
        XCTAssertFalse(watcher.isSeekable)
        XCTAssertEqual(watcher.delaySeconds, 30)
        XCTAssertEqual(watcher.watchers, 3)
        let base = HUDLayout(size: CGSize(width: 874, height: 402), safe: EdgeInsets(top: 0, leading: 62, bottom: 20, trailing: 62),
                             leftHanded: false)
        XCTAssertFalse(HUDSpectatorLayout(base: base, seekable: false).showsTransportRow, "観戦席には再生バーを出さない")
    }

    func testTickAtFractionClockAndSpeedLabels() {
        XCTAssertEqual(HUDSpectatorState.tick(atFraction: 0.5, endTick: 600), 300)
        XCTAssertEqual(HUDSpectatorState.tick(atFraction: -1, endTick: 600), 0)
        XCTAssertEqual(HUDSpectatorState.tick(atFraction: 3, endTick: 600), 600)
        XCTAssertEqual(HUDSpectatorState.tick(atFraction: .nan, endTick: 600), 0)
        XCTAssertEqual(HUDStyle.preciseClock(Double(37) * Balance.dt), "00:01.2", "0.1 秒単位")
        XCTAssertEqual(HUDStyle.preciseClock(754.06), "12:34.0")
        XCTAssertEqual(HUDStyle.preciseClock(3600.55), "1:00:00.5")
        XCTAssertEqual(HUDSpectatorState.speedLabel(0.5), "0.5")
        XCTAssertEqual(HUDSpectatorState.speedLabel(2), "2", "UI テストの spectate_speed_2x")
        XCTAssertEqual(HUDSeekBarGeometry.x(forTick: 150, endTick: 600, width: 200), 50)
        XCTAssertLessThan(HUDSeekBarGeometry.markerRadius(weight: 0.2), HUDSeekBarGeometry.markerRadius(weight: 1))
    }

    func testMarkersAndNextFight() {
        let t = ReplayTimeline(events: [
            TimelineEvent(tick: 100, kind: .objective(kind: .blueSentinel, team: .blue, killerID: nil), pos: nil),
            TimelineEvent(tick: 900, kind: .kill(victimID: 1, killerID: 2, assistIDs: [], killerTeam: .red, isFirstBlood: false,
                                                 multiKill: 1, isShutdown: false), pos: nil),
            TimelineEvent(tick: 1500, kind: .structure(team: .blue, kind: .tower, lane: .top, tier: .outer, killerID: nil), pos: nil),
            TimelineEvent(tick: 1600, kind: .matchEnd(winner: .red, reason: .coreDestroyed), pos: nil),
        ], coveredTick: 1600)
        let markers = HUDSpectatorState.markers(from: t)
        XCTAssertEqual(markers.map(\.kind), [.objective, .kill, .structure, .end])
        XCTAssertEqual(markers.map(\.team), [.blue, .red, .red, .red], "有利になった側（タワーを失ったのはブルー）")
        XCTAssertEqual(markers.map(\.weight), t.events.map(\.weight))

        // 見どころの 5 秒前から。現在位置のすぐ先の出来事は飛ばす
        XCTAssertEqual(HUDSpectatorState.nextFightTick(after: 0, in: t), 900 - HUDSpectatorState.fightLeadIn)
        XCTAssertEqual(HUDSpectatorState.nextFightTick(after: 800, in: t), 1500 - HUDSpectatorState.fightLeadIn)
        XCTAssertEqual(HUDSpectatorState.nextFightTick(after: 1400, in: t), 1600 - HUDSpectatorState.fightLeadIn)
        XCTAssertNil(HUDSpectatorState.nextFightTick(after: 1460, in: t), "目の前（5 秒以内）の出来事は見どころとして飛ばさない")

        let g = HUDSpectatorState.graph(from: ReplayTimeline(samples: [
            TimelineSample(tick: 0, blueGold: 3000, redGold: 3000, blueXP: 0, redXP: 0, blueKills: 0, redKills: 0, blueTowers: 0, redTowers: 0),
            TimelineSample(tick: 300, blueGold: 4500, redGold: 3500, blueXP: 800, redXP: 1000, blueKills: 1, redKills: 0, blueTowers: 0, redTowers: 0),
        ], coveredTick: 300), endTick: 600)
        XCTAssertEqual(g.points.map(\.gold), [0, 1000])
        XCTAssertEqual(g.points.map(\.xp), [0, -200])
        XCTAssertEqual(g.endTick, 600)
        XCTAssertEqual(HUDGoldGraphMath.value(at: 299, in: g.points)?.tick, 0)
        XCTAssertEqual(HUDGoldGraphMath.value(at: 450, in: g.points)?.tick, 300)
        XCTAssertGreaterThanOrEqual(HUDGoldGraphMath.range(g.points), 1000)
    }

    // MARK: 操作（AI 同士の観戦 = シークできる）

    func testSkipRestartStepAndSpeedOnLiveSpectate() async {
        let (c, m) = start(BattleLaunch(config: MatchFactory.botMatch(seed: 21)))
        run(c, ticks: 600)
        m.refresh()
        XCTAssertTrue(m.spectator.transport.isSeekable)
        XCTAssertEqual(m.spectator.transport.tick, 600)
        XCTAssertEqual(m.spectator.transport.endTick, 600)

        m.spectatorSkip(seconds: -10)
        XCTAssertEqual(c.seekingToTick, 300)
        XCTAssertEqual(m.spectator.transport.seekingTo, 300, "シーク中はすぐに「移動中」と目標の位置を出す")
        XCTAssertEqual(m.spectator.transport.displayTick, 300)
        await waitForSeek(c)
        m.refresh()
        XCTAssertEqual(m.spectator.transport.tick, 300)
        XCTAssertEqual(m.spectator.transport.endTick, 600, "巻き戻しても見た所までがバーに残る")
        XCTAssertEqual(m.spectator.transport.coveredTick, 600)

        m.spectatorSkip(seconds: 10)
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 600)

        m.spectatorRestart()
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 0)

        // コマ送りは一時停止してから 1 tick
        run(c, ticks: 10)
        m.spectatorStep()
        XCTAssertTrue(c.isPaused)
        XCTAssertTrue(m.spectatorPaused)
        XCTAssertEqual(c.state.tick, 11)
        m.spectatorPlayPause()
        XCTAssertFalse(c.isPaused)

        // 速度は 0.5×〜8× を順に
        var seen: [Double] = []
        for _ in BattleController.spectatorSpeeds {
            m.cycleSpectatorSpeed()
            seen.append(c.speed)
        }
        XCTAssertEqual(Set(seen), Set(BattleController.spectatorSpeeds))
        XCTAssertEqual(seen.last, 1, "一巡すると元の速度")

        // ドラッグ中の位置は表示だけ（離すまでシークしない）
        m.spectator.dragPreviewTick = 120
        XCTAssertNil(c.seekingToTick)
        m.spectator.dragPreviewTick = nil
        m.spectatorSeek(toTick: 120)
        XCTAssertEqual(c.seekingToTick, 120)
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 120)
    }

    // MARK: 再生終了

    func testEndOfRecordingThenWatchAgain() async {
        let live = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 14)))
        run(live, ticks: 150)
        guard let data = live.makeOutcome(abandoned: true).replay else { return XCTFail() }
        let (c, m) = start(BattleLaunch(config: data.config, replay: data))
        run(c, ticks: 200)
        XCTAssertTrue(c.isEnded)
        m.refresh()
        XCTAssertTrue(m.spectator.transport.isEnded)
        XCTAssertEqual(m.spectator.transport.tick, 150)
        XCTAssertEqual(m.spectator.transport.endTick, 150)
        XCTAssertNil(m.endPhase, "記録が途中で終わったリプレイは終了演出を出さない（再生終了のカード）")
        XCTAssertNil(m.spectator.transport.nextFightTick)

        // 終わっている時の再生ボタン = 最初から
        m.spectatorPlayPause()
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 0)
        XCTAssertFalse(c.isEnded)
        m.refresh()
        XCTAssertFalse(m.spectator.transport.isEnded)
    }

    func testSeekingBackAfterTheEndReopensTheMatch() async {
        let (c, m) = start(BattleLaunch(config: MatchFactory.botMatch(seed: 9)))
        run(c, ticks: 90)
        m.toggleSpectatorPause()
        m.debugEnd(winner: .blue)
        XCTAssertNotNil(m.endPhase)
        m.spectatorRestart()
        XCTAssertNil(m.endPhase, "巻き戻すと終了演出を閉じる")
        XCTAssertTrue(c.isPaused, "一時停止していたなら一時停止のまま")
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 0)
    }

    func testPlayersHaveNoTransport() {
        let (c, m) = start(BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 2)))
        run(c, ticks: 30)
        m.spectatorSkip(seconds: -10)
        m.spectatorSeek(toTick: 0)
        m.spectatorStep()
        XCTAssertNil(c.seekingToTick)
        XCTAssertEqual(c.state.tick, 30)
        XCTAssertFalse(c.isPaused)
    }
}
