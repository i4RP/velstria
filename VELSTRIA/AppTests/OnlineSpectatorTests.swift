import XCTest
@testable import VELSTRIA
import VelstriaCore

/// オンライン観戦（プロトコル v2）: ループバック接続でホスト・選手・観戦者をつなぎ、
/// 観戦の案内 → 遅延配信 → 途中参加（遅延済みのキーフレーム）→ ずれの再同期 → 観戦の停止・再開 → 試合の終わり、
/// 上限・入力の拒否・ホストの実況（B1）・抜けた選手の復帰（B3）・再接続した参加者の扱い（B4）を通す。
@MainActor
final class OnlineSpectatorTests: XCTestCase {
    private let blueMid = MatchFactory.onlineSeatIndex(team: .blue, position: .mid)
    private let redMid = MatchFactory.onlineSeatIndex(team: .red, position: .mid)
    /// テストの遅延（2 秒）とキーフレーム間隔（2 秒）。本番の 30 秒 / 10 秒では debug の sim が遅すぎる。
    private let delay = 60
    private let keyframeInterval = 60

    private struct Joined {
        let session: OnlineSession
        /// ホスト側の端（閉じると切断）。
        let hostSide: LoopbackConnection
        let clientSide: LoopbackConnection
    }

    /// テスト用のホスト（スナップショットは同期で符号化。単調時刻は手動で進める）。
    private final class Clock {
        var now: TimeInterval = 1000
    }

    private func makeHost(clock: Clock? = nil) -> OnlineSession {
        let host = OnlineSession.host(peerID: "host", name: "Host", roomName: "Room")
        host.encodesSpectatorSnapshotsInBackground = false
        host.spectatorKeyframeInterval = keyframeInterval
        if let clock { host.uptime = { clock.now } }
        host.setSpectatorDelay(ticks: delay)
        return host
    }

    private func join(_ host: OnlineSession, id: String, spectate: Bool = false) -> Joined {
        let (a, b) = LoopbackConnection.pair()
        host.accept(a)
        let s = OnlineSession.join(peerID: id, name: id.capitalized, connection: b, wantsSpectate: spectate)
        return Joined(session: s, hostSide: a, clientSide: b)
    }

    /// ホストが座って H001 を選び準備完了。
    private func seatHost(_ host: OnlineSession) {
        host.takeSeat(blueMid)
        host.setLoadout(OnlineLoadout(heroID: "H001"))
        host.setReady(true)
    }

    private func seat(_ s: OnlineSession, _ index: Int, hero: String) {
        s.takeSeat(index)
        s.setLoadout(OnlineLoadout(heroID: hero))
        s.setReady(true)
    }

    /// 観戦の戦闘を作って接続する（AppModel.wire が作るものと同じ）。
    private func watcherController(_ s: OnlineSession) -> BattleController {
        let c = BattleController(launch: BattleLaunch(config: s.room.config!, onlineSpectator: true), online: s)
        s.attach(controller: c)
        return c
    }

    /// 1 tick = 1 フレーム。ホスト → 観戦配信 → 各クライアントの順に進め、ホストの各 tick の状態ハッシュを記録する。
    private func run(host: BattleController, session: OnlineSession, clients: [BattleController], frames: Int,
                     clock: Clock? = nil, hashes: inout [Int: UInt64], check: (() -> Void)? = nil) {
        for _ in 0..<frames {
            host.frame(dt: Balance.dt)
            hashes[host.state.tick] = host.state.stateHash()
            clock?.now += Balance.dt
            session.pumpSpectators()
            for c in clients { c.frame(dt: Balance.dt) }
            check?()
        }
    }

    /// 観戦者の tick は常にホストの tick − 遅延 以下（生の状態に追いつかない）。
    private func assertDelayed(_ watcher: BattleController, behind host: BattleController, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(watcher.state.tick, max(0, host.state.tick - delay),
                                 "観戦者 \(watcher.state.tick) / ホスト \(host.state.tick)", file: file, line: line)
    }

    // MARK: 観戦席 → 試合開始 → 遅延配信

    func testWatcherGetsSpectateMatchAndDelayedFrames() {
        let host = makeHost()
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertEqual(host.room.spectators.map(\.id), ["watcher"])
        XCTAssertEqual(w.session.localRole, .spectator)
        var spectateConfig: MatchConfig?
        var watcherPlayerStart = false
        w.session.onSpectateStart = { spectateConfig = $0 }
        w.session.onMatchStart = { _, _ in watcherPlayerStart = true }
        var hostSeat: Int?
        host.onMatchStart = { hostSeat = $1 }

        XCTAssertTrue(host.startMatch(master: .shared, seed: 77))
        XCTAssertEqual(hostSeat, blueMid)
        XCTAssertEqual(spectateConfig, host.room.config, "観戦席には観戦の案内が届く")
        XCTAssertFalse(watcherPlayerStart, "観戦席には選手の開始を送らない")
        XCTAssertTrue(w.session.isWatchingMatch)
        XCTAssertEqual(w.session.spectatorDelayTicks, delay)

        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        XCTAssertTrue(host.canBegin, "観戦者の読み込みは待たない")
        let wc = watcherController(w.session)
        XCTAssertTrue(wc.isOnlineClient)
        XCTAssertTrue(wc.isSpectating)
        XCTAssertNil(wc.humanHeroID)
        XCTAssertNil(wc.recorder, "観戦席は記録しない")
        XCTAssertEqual(wc.onlineSpectatorDelaySeconds ?? -1, Double(delay) * Balance.dt, accuracy: 1e-9)
        XCTAssertEqual(host.spectatorStreamCount, 1)
        XCTAssertEqual(host.room.watchingCount, 1)
        XCTAssertEqual(hc.onlineSpectatorCount, 1, "選手にも観戦者数が見える")
        XCTAssertEqual(hc.onlineSpectatorDelaySeconds, nil, "選手の視点は遅延なし")

        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 240, hashes: &hashes) {
            self.assertDelayed(wc, behind: hc)
        }
        XCTAssertGreaterThanOrEqual(wc.state.tick, 240 - delay - BattleController.onlineSpectatorJitterBuffer - 4)
        XCTAssertEqual(wc.state.stateHash(), hashes[wc.state.tick], "遅れた tick でホストと同じ状態")
        XCTAssertEqual(host.resyncCount, 0, "観戦者のハッシュ報告はすべて一致")
        XCTAssertNil(w.session.lastSnapshotTick, "開始から見ている観戦者には状態を送らない（構成から作れる）")
    }

    // MARK: 途中参加

    func testMidMatchSpectatorJoinConvergesFromDelayedKeyframe() {
        let host = makeHost()
        seatHost(host)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 5))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [], frames: 400, hashes: &hashes)
        XCTAssertEqual(host.spectatorReleasedTick, 400 - delay)
        XCTAssertLessThanOrEqual(host.spectatorRelayRetained.frames, delay + 3 * keyframeInterval, "古い記録は捨てる")
        XCTAssertTrue(host.spectatorRelayRetained.keyframes.allSatisfy { $0 >= 300 }, "基準より古いキーフレームは捨てる")

        // 試合中に観戦席で入る: 名乗りで観戦を希望 → 観戦の案内
        let w = join(host, id: "late", spectate: true)
        XCTAssertTrue(w.session.isWatchingMatch, "途中参加の観戦者にも観戦の案内が届く")
        XCTAssertEqual(host.room.peer("late")?.role, .spectator)
        let wc = watcherController(w.session)
        // 基準は遅延済みの範囲で最新のキーフレーム（生の状態ではない）
        let base = try! XCTUnwrap(w.session.lastSnapshotTick)
        XCTAssertEqual(base % keyframeInterval, 0)
        XCTAssertLessThanOrEqual(base, hc.state.tick - delay, "観戦者へは遅延済みの状態だけ")
        XCTAssertGreaterThan(base, 0)

        run(host: hc, session: host, clients: [wc], frames: 150, hashes: &hashes) {
            self.assertDelayed(wc, behind: hc)
        }
        XCTAssertGreaterThan(wc.state.tick, base)
        XCTAssertEqual(wc.state.stateHash(), hashes[wc.state.tick], "途中参加でもホストの遅れた tick に一致")
        XCTAssertEqual(host.resyncCount, 0)
    }

    func testBackgroundSnapshotEncodingKeepsOrder() async {
        let host = makeHost()
        host.encodesSpectatorSnapshotsInBackground = true
        seatHost(host)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 6))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [], frames: 200, hashes: &hashes)
        let w = join(host, id: "late", spectate: true)
        let wc = watcherController(w.session)
        // 符号化の間もホストは進む（その観戦者への配信は基準が届くまで止める）
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(20))
        while w.session.lastSnapshotTick == nil && clock.now < deadline {
            run(host: hc, session: host, clients: [wc], frames: 1, hashes: &hashes)
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(w.session.lastSnapshotTick, "バックグラウンドの符号化が終わって基準が届く")
        run(host: hc, session: host, clients: [wc], frames: 120, hashes: &hashes) {
            self.assertDelayed(wc, behind: hc)
        }
        XCTAssertEqual(wc.state.stateHash(), hashes[wc.state.tick])
        XCTAssertEqual(host.resyncCount, 0)
    }

    func testStaleBackgroundBaseIsDroppedAfterWatchingAgain() async throws {
        // 観戦をやめて観戦し直した: やめる前に始めた基準の符号化が後から終わっても、新しい配信先へは送らない
        // （配信先を作り直すと世代が 0 から数え直しになり、古い結果を新しい配信先のものと取り違えていた）
        let host = makeHost()
        host.encodesSpectatorSnapshotsInBackground = true
        seatHost(host)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 8))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [], frames: 200, hashes: &hashes)
        let w = join(host, id: "late", spectate: true)
        _ = watcherController(w.session)   // spectateLoaded → 基準の符号化が始まる（まだ届かない）
        w.session.detach()
        w.session.matchEnded(aborted: true, spectating: true)
        XCTAssertEqual(host.spectatorStreamCount, 0)
        run(host: hc, session: host, clients: [], frames: 2 * keyframeInterval, hashes: &hashes)

        // 観戦し直す（新しい基準はもっと新しいキーフレーム）
        w.session.requestSpectate()
        let wc = watcherController(w.session)
        let clock = ContinuousClock()
        var deadline = clock.now.advanced(by: .seconds(20))
        while w.session.lastSnapshotTick == nil && clock.now < deadline {
            run(host: hc, session: host, clients: [wc], frames: 1, hashes: &hashes)
            try? await Task.sleep(for: .milliseconds(5))
        }
        let base = try XCTUnwrap(w.session.lastSnapshotTick, "観戦し直した基準が届く")
        // 古い符号化の結果が届く時間を与える
        deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            run(host: hc, session: host, clients: [wc], frames: 1, hashes: &hashes)
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(w.session.resyncCount, 1, "観戦し直した後の基準だけが届く")
        XCTAssertGreaterThan(base, 2 * keyframeInterval, "やめる前の古い基準（tick \(2 * keyframeInterval)）ではない")
        run(host: hc, session: host, clients: [wc], frames: 60, hashes: &hashes) {
            self.assertDelayed(wc, behind: hc)
        }
        XCTAssertEqual(wc.state.stateHash(), hashes[wc.state.tick])
        XCTAssertEqual(host.resyncCount, 0)
    }

    // MARK: ずれの再同期

    func testHashMismatchSendsDelayedKeyframeNotLiveStateAndIsRateLimited() {
        let clock = Clock()
        let host = makeHost(clock: clock)
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 11))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        var hashes: [Int: UInt64] = [:]
        // スナップショットの最短間隔（5 秒）を過ぎるまで進める
        run(host: hc, session: host, clients: [wc], frames: 330, clock: clock, hashes: &hashes)

        // 観戦者の状態を壊す → 次のハッシュ報告で検出 → 遅延済みのキーフレームから送り直す
        var corrupted = wc.state
        let hero = corrupted.heroIndices[0]
        corrupted.units[hero].pos = corrupted.units[hero].pos + Vec2(300, 300)
        wc.restore(corrupted)
        var snapshotTick: Int?
        var hostTickAtSnapshot = 0
        run(host: hc, session: host, clients: [wc], frames: 60, clock: clock, hashes: &hashes) {
            if snapshotTick == nil, let t = w.session.lastSnapshotTick {
                snapshotTick = t
                hostTickAtSnapshot = hc.state.tick
            }
        }
        XCTAssertEqual(host.resyncCount, 1)
        let t = try! XCTUnwrap(snapshotTick, "再同期の状態が届く")
        XCTAssertLessThanOrEqual(t, hostTickAtSnapshot - delay, "生の状態ではなく遅延済みの状態")
        XCTAssertEqual(t % keyframeInterval, 0, "キーフレーム")
        run(host: hc, session: host, clients: [wc], frames: 60, clock: clock, hashes: &hashes) {
            self.assertDelayed(wc, behind: hc)
        }
        XCTAssertEqual(wc.state.stateHash(), hashes[wc.state.tick], "再同期で戻る")

        // すぐにまたずれても、間隔を空けるまで送らない
        var again = wc.state
        again.units[hero].pos = again.units[hero].pos + Vec2(200, 0)
        wc.restore(again)
        run(host: hc, session: host, clients: [wc], frames: 40, clock: clock, hashes: &hashes)
        XCTAssertEqual(host.resyncCount, 1, "スナップショットは 5 秒に 1 回まで")
        run(host: hc, session: host, clients: [wc], frames: 150, clock: clock, hashes: &hashes)
        XCTAssertEqual(host.resyncCount, 2, "間隔を過ぎたら送り直す")
        run(host: hc, session: host, clients: [wc], frames: 60, clock: clock, hashes: &hashes)
        XCTAssertEqual(wc.state.stateHash(), hashes[wc.state.tick])
    }

    func testResyncBeforeFirstReleasedKeyframeRestartsFromMatchStart() {
        // 最初のキーフレームが公開される前のずれ: 試合開始時の状態から送り直す
        // （以前は状態を送らずに記録だけ送り直し、観戦者は重複として捨ててずれたまま見続けた）
        let clock = Clock()
        let host = makeHost(clock: clock)
        host.spectatorKeyframeInterval = 600   // 最初のキーフレームの公開（600 + 遅延）を試験の間より後にする
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 13))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 75, clock: clock, hashes: &hashes)
        XCTAssertLessThan(wc.state.tick, OnlineProtocol.hashInterval, "最初のハッシュ報告の前")
        // スナップショットの間隔を過ぎた状態で観戦者の状態を壊す → tick 30 の報告で検出
        clock.now += 10
        var corrupted = wc.state
        let hero = corrupted.heroIndices[0]
        corrupted.units[hero].pos = corrupted.units[hero].pos + Vec2(300, 300)
        wc.restore(corrupted)
        run(host: hc, session: host, clients: [wc], frames: 60, clock: clock, hashes: &hashes)
        XCTAssertEqual(host.resyncCount, 1)
        XCTAssertEqual(w.session.lastSnapshotTick, 0, "キーフレームがまだ無いので試合開始時の状態を送る")
        XCTAssertLessThan(host.spectatorReleasedTick, 600, "キーフレームはまだ公開されていない")
        run(host: hc, session: host, clients: [wc], frames: 90, clock: clock, hashes: &hashes) {
            self.assertDelayed(wc, behind: hc)
        }
        XCTAssertGreaterThan(wc.state.tick, 2 * OnlineProtocol.hashInterval)
        XCTAssertEqual(wc.state.stateHash(), hashes[wc.state.tick], "試合開始時から進め直してホストに一致")
        XCTAssertEqual(host.resyncCount, 1, "送り直しは 1 回で直る")
        XCTAssertEqual(host.spectatorRelayRetained.keyframes, [], "キーフレームは 600 tick まで無い")
    }

    func testWatcherDesyncAfterMatchFinishedStillGetsTheTail() {
        // ホストの試合が終わり（ホストは終わりの画面のまま）、観戦者へ残りと終わりを送り切った後のずれ:
        // 基準に戻した先の残りと終わりも送り直す（以前は基準だけ届いて配信が止まり、残りを失って待ち続けた）
        let clock = Clock()
        let host = makeHost(clock: clock)
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 14))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 200, clock: clock, hashes: &hashes)
        let finalTick = hc.state.tick
        // ホストの試合が終わる（ここでは中断で止める。matchEnded はまだ呼ばない = 終わりの画面で止まっている）
        _ = hc.makeOutcome(abandoned: true)
        host.pumpSpectators()
        XCTAssertEqual(w.session.spectatorFinalTick, finalTick, "残りと終わりを送り切った")
        XCTAssertEqual(host.spectatorStreamCount, 1)

        clock.now += 10
        var corrupted = wc.state
        let hero = corrupted.heroIndices[0]
        corrupted.units[hero].pos = corrupted.units[hero].pos + Vec2(300, 300)
        wc.restore(corrupted)
        var finalHash: UInt64?
        var guardCount = 0
        while !wc.isEnded && guardCount < delay + 120 {
            wc.frame(dt: Balance.dt)
            host.pumpSpectators()
            if wc.state.tick == finalTick && !wc.isEnded { finalHash = wc.state.stateHash() }
            guardCount += 1
        }
        XCTAssertEqual(host.resyncCount, 1, "試合が終わった後のずれも再同期する")
        let base = try! XCTUnwrap(w.session.lastSnapshotTick)
        XCTAssertLessThan(base, finalTick)
        XCTAssertTrue(wc.isEnded, "基準の先の残りが届いて最後まで見られる（止まったまま待たない）")
        XCTAssertEqual(wc.state.tick, finalTick)
        XCTAssertEqual(finalHash, hashes[finalTick], "最後の状態はホストと同じ")
        XCTAssertEqual(w.session.spectatorFinalTick, finalTick)
    }

    // MARK: 観戦者は操作できない・生の状態をもらえない

    func testWatcherInputsAndLoadedAreIgnored() {
        let host = makeHost()
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 12))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 90, hashes: &hashes)
        let hostHero = hc.humanHeroID!
        let start = hc.state.unit(hostHero)!.pos

        // 観戦の戦闘からは操作を送れない
        wc.send(.move(direction: Vec2(1, 0)))
        // 偽の入力（他人のヒーロー・操作者の切り替え）も捨てる
        w.session.sendInput(HeroCommand(heroID: hostHero, command: .move(direction: Vec2(1, 0))))
        w.session.sendInput(HeroCommand(heroID: hostHero, command: .setController(.bot)))
        w.session.flush()
        XCTAssertTrue(host.takeRemoteInputs().isEmpty, "観戦者の入力は受け付けない")
        // 偽の loaded（選手の再接続のふり）で生の状態をもらえない
        w.clientSide.send(.loaded)
        run(host: hc, session: host, clients: [wc], frames: 30, hashes: &hashes)
        XCTAssertEqual(hc.state.unit(hostHero)!.pos, start)
        XCTAssertEqual(hc.state.unit(hostHero)?.hero?.controller, .human)
        XCTAssertNil(w.session.lastSnapshotTick, "観戦者へ生の状態は送らない")
        assertDelayed(wc, behind: hc)
    }

    // MARK: 上限

    func testSeparateCapsForPlayersAndSpectators() {
        let host = makeHost()
        var keep: [Joined] = []
        for i in 0..<OnlineProtocol.maxSpectators {
            let j = join(host, id: "s\(i)", spectate: true)
            XCTAssertEqual(j.session.status, .lobby)
            keep.append(j)
        }
        XCTAssertEqual(host.room.spectators.count, OnlineProtocol.maxSpectators)
        let overflow = join(host, id: "s-extra", spectate: true)
        guard case .disconnected(let reason) = overflow.session.status else { return XCTFail("観戦席の上限: \(overflow.session.status)") }
        XCTAssertFalse(reason.isEmpty)

        // 選手は別枠（ホストを含めて座席数まで）
        for i in 0..<(OnlineProtocol.maxPlayers - 1) {
            let j = join(host, id: "p\(i)")
            XCTAssertEqual(j.session.status, .lobby, "選手 \(i)")
            keep.append(j)
        }
        XCTAssertEqual(host.room.players.count, OnlineProtocol.maxPlayers)
        let extraPlayer = join(host, id: "p-extra")
        guard case .disconnected = extraPlayer.session.status else { return XCTFail("選手の上限") }

        // 観戦席が満員なら選手は観戦席に移れない。選手の枠が満員なら観戦者は戻れない
        var notice: String?
        keep.last!.session.onNotice = { notice = $0 }
        keep.last!.session.setSpectator(true)
        XCTAssertEqual(host.room.peer(keep.last!.session.localPeerID)?.role, .player)
        XCTAssertNotNil(notice, "断った理由が届く")
        keep[0].session.setSpectator(false)
        XCTAssertEqual(host.room.peer("s0")?.role, .spectator)
        _ = keep
    }

    func testRehelloAsSpectatorRespectsSpectatorCap() {
        let host = makeHost()
        var keep: [Joined] = []
        for i in 0..<OnlineProtocol.maxSpectators { keep.append(join(host, id: "s\(i)", spectate: true)) }
        keep.append(join(host, id: "p"))
        XCTAssertEqual(host.room.peer("p")?.role, .player)
        // 部屋にいる選手が観戦席の希望で名乗り直す（アプリの再起動で古い接続が残っている等）: 満員なら選手のまま
        let again = join(host, id: "p", spectate: true)
        XCTAssertEqual(again.session.status, .lobby)
        XCTAssertEqual(host.room.peer("p")?.role, .player)
        XCTAssertEqual(host.room.spectators.count, OnlineProtocol.maxSpectators)
        // 空きができれば観戦席に入れる
        keep[0].clientSide.close()
        let third = join(host, id: "p", spectate: true)
        XCTAssertEqual(third.session.status, .lobby)
        XCTAssertEqual(host.room.peer("p")?.role, .spectator)
        _ = keep
    }

    func testDisallowedSpectatorsCannotWatch() {
        let host = makeHost()
        seatHost(host)
        host.setAllowsSpectators(false)
        let w = join(host, id: "w", spectate: true)
        XCTAssertEqual(host.room.peer("w")?.role, .player, "観戦できない部屋では選手として待つ")
        w.session.setSpectator(true)
        XCTAssertEqual(host.room.peer("w")?.role, .player)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 3))
        XCTAssertFalse(w.session.isWatchingMatch)
        XCTAssertFalse(w.session.canWatchMatch)
        var notice: String?
        w.session.onNotice = { notice = $0 }
        w.clientSide.send(.requestSpectate)   // UI では出ないボタンを偽って押す
        XCTAssertNotNil(notice)
        XCTAssertFalse(w.session.isWatchingMatch)
        XCTAssertEqual(host.spectatorStreamCount, 0)
    }

    // MARK: 観戦をやめる・観戦し直す

    func testStopWatchingThenWatchAgain() {
        let host = makeHost()
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 21))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 150, hashes: &hashes)
        XCTAssertEqual(host.room.watchingCount, 1)

        // 観戦をやめる（BattleSessionView → matchEnded(spectating: true)）
        _ = wc.makeOutcome(abandoned: true)
        w.session.detach()
        w.session.matchEnded(aborted: true, spectating: true)
        XCTAssertEqual(host.spectatorStreamCount, 0)
        XCTAssertEqual(host.room.watchingCount, 0)
        XCTAssertEqual(w.session.bufferedFrames, 0)
        XCTAssertEqual(host.room.peer("watcher")?.role, .spectator, "観戦席の役割はそのまま（次の試合も観戦する）")
        run(host: hc, session: host, clients: [], frames: 60, hashes: &hashes)
        XCTAssertEqual(w.session.bufferedFrames, 0, "やめた観戦者には配信しない")
        XCTAssertTrue(w.session.isSittingOutMatch)
        XCTAssertTrue(w.session.canWatchMatch)

        // 観戦し直す: 遅延済みのキーフレームから
        var restarted: MatchConfig?
        w.session.onSpectateStart = { restarted = $0 }
        w.session.requestSpectate()
        XCTAssertEqual(restarted, host.room.config)
        let wc2 = watcherController(w.session)
        XCTAssertNotNil(w.session.lastSnapshotTick)
        run(host: hc, session: host, clients: [wc2], frames: 120, hashes: &hashes) {
            self.assertDelayed(wc2, behind: hc)
        }
        XCTAssertEqual(wc2.state.stateHash(), hashes[wc2.state.tick])
        XCTAssertEqual(host.room.watchingCount, 1)
    }

    func testSpectatorDisconnectIsRemovedImmediately() {
        let host = makeHost()
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 22))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 30, hashes: &hashes)
        w.clientSide.close()
        XCTAssertNil(host.room.peer("watcher"), "座席の無い参加者は試合中でも保つものが無いので外す")
        XCTAssertEqual(host.spectatorStreamCount, 0)
        XCTAssertEqual(host.room.watchingCount, 0)
        run(host: hc, session: host, clients: [], frames: 10, hashes: &hashes)
    }

    // MARK: 試合の終わり

    func testMatchEndFlushesTailAndWatcherPlaysItAtNormalSpeed() {
        let host = makeHost()
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 31))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 200, hashes: &hashes)
        let finalTick = hc.state.tick

        // ホストが試合を終えてロビーへ戻る: 遅延分の残りを送り切り、終わった tick を知らせる
        host.matchEnded(aborted: false)
        XCTAssertEqual(host.room.phase, .lobby)
        XCTAssertEqual(w.session.spectatorFinalTick, finalTick)
        XCTAssertGreaterThan(w.session.bufferedFrames, delay / 2, "残りは前倒しで届く")
        XCTAssertTrue(w.session.isMatchLive, "部屋がロビーに戻っても観戦者は残りを見られる")

        // 前倒しで届いた残りは早送りせず通常の速さで見せる
        let before = wc.state.tick
        for _ in 0..<20 { wc.frame(dt: Balance.dt) }
        XCTAssertLessThanOrEqual(wc.state.tick - before, 20 + BattleController.onlineSpectatorJitterBuffer)
        XCTAssertFalse(wc.isEnded)
        var guardCount = 0
        while wc.state.tick < finalTick && guardCount < delay + 40 {
            wc.frame(dt: Balance.dt)
            guardCount += 1
        }
        XCTAssertEqual(wc.state.tick, finalTick, "最後の tick まで見る")
        XCTAssertEqual(wc.state.stateHash(), hashes[finalTick], "ホストの最後の状態と一致")
        // ホストの試合は step の外で終わった（ここでは途中でロビーへ戻した）: 最後の tick を見たら中断として終える
        wc.frame(dt: Balance.dt)
        XCTAssertTrue(wc.isEnded, "終わった tick で終わる")
        XCTAssertEqual(wc.state.endReason, .aborted)

        // 抜けると観戦をやめたと伝える（部屋に残る）
        w.session.detach()
        w.session.matchEnded(aborted: false, spectating: true)
        XCTAssertTrue(host.room.peers.contains { $0.id == "watcher" })
        XCTAssertFalse(w.session.isWatchingMatch)
    }

    func testHostAbortSendsTailAndEndsWatchers() {
        let host = makeHost()
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 32))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 150, hashes: &hashes)
        let hostTick = hc.state.tick
        _ = hc.makeOutcome(abandoned: true)
        host.detach()
        host.matchEnded(aborted: true)
        XCTAssertEqual(w.session.spectatorFinalTick, hostTick, "中断でも終わった tick を知らせる")
        XCTAssertTrue(w.session.isMatchLive, "観戦者は遅延のまま残りを見る（中断を知らせると早送りになる）")
        // 残りは通常の速さで再生する
        let before = wc.state.tick
        for _ in 0..<20 { wc.frame(dt: Balance.dt) }
        XCTAssertLessThanOrEqual(wc.state.tick - before, 20 + BattleController.onlineSpectatorJitterBuffer)
        XCTAssertFalse(wc.isEnded)
        var guardCount = 0
        var finalHash: UInt64?
        while !wc.isEnded && guardCount < delay + 60 {
            wc.frame(dt: Balance.dt)
            if wc.state.tick == hostTick && !wc.isEnded { finalHash = wc.state.stateHash() }
            guardCount += 1
        }
        XCTAssertTrue(wc.isEnded)
        XCTAssertEqual(wc.state.tick, hostTick, "中断前の分は最後まで再生する")
        XCTAssertEqual(finalHash, hashes[hostTick], "中断前の最後の状態はホストと同じ")
        XCTAssertEqual(wc.state.endReason, .aborted)
        XCTAssertEqual(wc.onlineStatus, .disconnected, "中断の終わり（重ね表示が「観戦を終える」を出す）")
    }

    func testHostLeavingRoomEndsWatchersAfterBufferedFrames() {
        // ホストが部屋ごと閉じた（接続が切れた）: 届いている分を消化して中断で終える（待ち続けない）
        let host = makeHost()
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 35))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 150, hashes: &hashes)
        w.hostSide.close()
        XCTAssertFalse(w.session.isMatchLive)
        var guardCount = 0
        while !wc.isEnded && guardCount < 30 {
            wc.frame(dt: Balance.dt)
            guardCount += 1
        }
        XCTAssertTrue(wc.isEnded)
        XCTAssertEqual(wc.state.endReason, .aborted)
        XCTAssertEqual(wc.onlineStatus, .disconnected)
    }

    func testWatcherKeepsNormalSpeedForTailWhenHostClosesRoomAfterFinish() {
        // 試合が終わって残りが全部届いた後に、ホストが部屋を閉じた（接続が切れた）: 残りは早送りせず最後まで見せる
        let host = makeHost()
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 36))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 150, hashes: &hashes)
        let hostTick = hc.state.tick
        _ = hc.makeOutcome(abandoned: true)
        host.detach()
        host.matchEnded(aborted: true)
        XCTAssertEqual(w.session.spectatorFinalTick, hostTick)
        w.hostSide.close()
        XCTAssertFalse(w.session.isMatchLive)
        let before = wc.state.tick
        for _ in 0..<20 { wc.frame(dt: Balance.dt) }
        XCTAssertLessThanOrEqual(wc.state.tick - before, 20 + BattleController.onlineSpectatorJitterBuffer,
                                 "接続が切れても残りは通常の速さ")
        XCTAssertFalse(wc.isEnded)
        var guardCount = 0
        while !wc.isEnded && guardCount < delay + 60 {
            wc.frame(dt: Balance.dt)
            guardCount += 1
        }
        XCTAssertTrue(wc.isEnded)
        XCTAssertEqual(wc.state.tick, hostTick, "最後の tick まで見る")
        XCTAssertEqual(wc.state.endReason, .aborted)
        XCTAssertEqual(wc.onlineStatus, .disconnected)
    }

    func testNewMatchDoesNotClobberWatcherStillPlayingTail() {
        let host = makeHost()
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 33))
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 120, hashes: &hashes)
        host.detach()
        host.matchEnded(aborted: false)
        let buffered = w.session.bufferedFrames
        XCTAssertGreaterThan(buffered, 0)

        // 観戦者がまだ残りを見ている間にホストが次の試合を始める: 今の配信は捨てず、新しい観戦は断る
        host.setReady(true)
        var opened = false
        w.session.onSpectateStart = { _ in opened = true }
        XCTAssertTrue(host.startMatch(master: .shared, seed: 34))
        XCTAssertFalse(opened)
        XCTAssertEqual(w.session.bufferedFrames, buffered, "前の試合の残りは残る")
        XCTAssertEqual(host.spectatorStreamCount, 0)
        for _ in 0..<(delay + 60) { wc.frame(dt: Balance.dt) }
        XCTAssertTrue(wc.isEnded)
    }

    func testWatcherStillOnPreviousMatchOpensNextMatchAfterClosingIt() {
        // 観戦席が前の試合の残り・リザルトを見ている間に次の試合が始まった: 何も変えずに断り、閉じたら観戦を求め直して開く
        // （以前は断ったまま。ロビーの「観戦する」を押すまで開かず、トーストも戦闘の画面の裏で見えなかった）
        let host = makeHost()
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        w.session.spectateResumeDelay = 0
        var battleOpen = true
        w.session.isBattleOpen = { battleOpen }
        var opened: MatchConfig?
        w.session.onSpectateStart = { opened = $0 }

        // 閉じる前にその試合が終わった: 求め直さない（見る試合が無い）
        XCTAssertTrue(host.startMatch(master: .shared, seed: 39))
        XCTAssertNil(opened, "戦闘を開いている間は観戦の案内を断る")
        XCTAssertTrue(w.session.resumesSpectateAfterBattle, "観戦席は閉じたら求め直す")
        host.matchEnded(aborted: true)
        XCTAssertFalse(w.session.resumesSpectateAfterBattle)
        battleOpen = false
        w.session.battleClosed()
        XCTAssertNil(opened)

        // 次の試合: 断った後、閉じたら（AppModel.dismissBattle → battleClosed）観戦の案内が届いて開く
        battleOpen = true
        seatHost(host)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 40))
        XCTAssertNil(opened)
        XCTAssertEqual(host.spectatorStreamCount, 0)
        XCTAssertFalse(w.session.isWatchingMatch)
        battleOpen = false
        w.session.battleClosed()
        XCTAssertEqual(opened, host.room.config, "閉じたら次の試合の観戦画面が開く")
        XCTAssertFalse(w.session.resumesSpectateAfterBattle)
        let hc = BattleController(launch: BattleLaunch(config: host.room.config!, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let wc = watcherController(w.session)
        XCTAssertEqual(host.spectatorStreamCount, 1)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [wc], frames: 120, hashes: &hashes) {
            self.assertDelayed(wc, behind: hc)
        }
        XCTAssertEqual(wc.state.stateHash(), hashes[wc.state.tick])
    }

    func testSpectateOfferDuringLoadingBattleChangesNothing() {
        // 観戦の案内が、まだ読み込み中の戦闘（「試合に戻る」・前の試合の観戦）を開いている時に届いた:
        // 断るだけで配信の状態は作り直さない（以前は先に作り直し、読み込み中の戦闘の配信を受け付けなくしていた）
        let host = makeHost()
        seatHost(host)
        let p = join(host, id: "guest")
        seat(p.session, redMid, hero: "H002")
        XCTAssertTrue(host.startMatch(master: .shared, seed: 54))
        let config = host.room.config!
        let hc = BattleController(launch: BattleLaunch(config: config, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let pc = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: pc)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [pc], frames: 60, hashes: &hashes)
        let guestHero = pc.humanHeroID!
        p.session.detach()
        p.session.matchEnded(aborted: true)
        run(host: hc, session: host, clients: [], frames: 5, hashes: &hashes)

        // AppModel と同じ判断（戦闘を開いていれば観戦は断る）
        var battleOpen = false
        var spectateOpened = false
        p.session.isBattleOpen = { battleOpen }
        p.session.onSpectateStart = { _ in
            if battleOpen { p.session.declineSpectate() } else { spectateOpened = true }
        }
        var rejoinSeat: Int?
        p.session.onMatchStart = { _, seat in
            rejoinSeat = seat
            battleOpen = true
        }

        // 「観戦する」の返事を待つ間は「観戦する」「試合に戻る」を出さない（両方を押せない）
        p.clientSide.holdsDelivery = true
        p.session.requestSpectate()
        XCTAssertTrue(p.session.isAwaitingSpectate)
        XCTAssertFalse(p.session.canWatchMatch)
        XCTAssertFalse(p.session.canRejoinMatch)
        p.session.rejoinMatch()
        XCTAssertNil(rejoinSeat, "返事を待つ間は試合に戻れない")
        // 断られたら（ここでは案内を受けて観戦をやめた）また選べる
        p.clientSide.holdsDelivery = false
        XCTAssertFalse(p.session.isAwaitingSpectate)
        XCTAssertTrue(spectateOpened)
        p.session.matchEnded(aborted: true, spectating: true)
        XCTAssertTrue(p.session.canWatchMatch)
        XCTAssertTrue(p.session.canRejoinMatch, "観戦の戦闘を開く前に断ったので、まだ試合に戻れる")

        // 古い求め（返事が遅れて届く）と「試合に戻る」が重なった: 読み込み中の戦闘があるので観戦は何も変えずに断る
        spectateOpened = false
        p.clientSide.holdsDelivery = true
        p.clientSide.send(.requestSpectate)
        p.session.rejoinMatch()
        XCTAssertEqual(rejoinSeat, redMid)
        p.clientSide.holdsDelivery = false
        XCTAssertFalse(spectateOpened)
        XCTAssertFalse(p.session.resumesSpectateAfterBattle, "選手は求め直さない")
        // 読み込みが済んだ: ホストは状態を渡して操作を人間に戻し、配信も届く
        let pc2 = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: pc2)
        XCTAssertNotNil(p.session.lastSnapshotTick, "戻った戦闘に状態が届く")
        run(host: hc, session: host, clients: [pc2], frames: 60, hashes: &hashes)
        XCTAssertEqual(hc.state.unit(guestHero)?.hero?.controller, .human)
        for _ in 0..<100 where pc2.state.tick < hc.state.tick { pc2.frame(dt: Balance.dt) }
        XCTAssertEqual(pc2.state.tick, hc.state.tick, "配信が届いて進む（観戦の案内で止まらない）")
        XCTAssertEqual(pc2.state.stateHash(), hc.state.stateHash())
    }

    func testAbortedSpectateStillLoadingIsNotRevivedByNextMatch() {
        // 前の試合の観戦画面がまだ読み込み中に、その試合の中断と次の試合の案内が届いた: 中断の印を消さない
        // （以前は次の試合の案内で配信の状態を作り直し、読み込み後の観戦画面が待ち続けた）
        let host = makeHost()
        seatHost(host)
        let w = join(host, id: "watcher")
        w.session.setSpectator(true)
        var battleOpen = false
        w.session.isBattleOpen = { battleOpen }
        w.session.onSpectateStart = { _ in
            if battleOpen { w.session.declineSpectate() } else { battleOpen = true }
        }
        XCTAssertTrue(host.startMatch(master: .shared, seed: 55))
        let firstConfig = host.room.config!
        XCTAssertTrue(battleOpen, "観戦画面を開いた（まだ読み込み中）")
        let hc = BattleController(launch: BattleLaunch(config: firstConfig, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [], frames: 30, hashes: &hashes)
        _ = hc.makeOutcome(abandoned: true)
        host.detach()
        host.matchEnded(aborted: true)
        seatHost(host)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 56))

        // 前の試合の観戦画面の読み込みが済んだ: 中断として終わる（待ち続けない）
        let wc = BattleController(launch: BattleLaunch(config: firstConfig, onlineSpectator: true), online: w.session)
        w.session.attach(controller: wc)
        for _ in 0..<30 where !wc.isEnded { wc.frame(dt: Balance.dt) }
        XCTAssertTrue(wc.isEnded)
        XCTAssertEqual(wc.onlineStatus, .disconnected)
    }

    // MARK: ホストの実況（B1）

    func testUnseatedHostCanCastTheMatch() {
        let host = makeHost()
        let p = join(host, id: "guest")
        seat(p.session, redMid, hero: "H002")
        XCTAssertFalse(host.room.canStart, "座っていないホストは開始できない")
        XCTAssertFalse(host.startMatch(master: .shared, seed: 40))
        host.setSpectator(true)
        XCTAssertTrue(host.room.hostIsCaster)
        XCTAssertTrue(host.room.canStart)
        var castConfig: MatchConfig?
        var hostPlayerStart = false
        host.onSpectateStart = { castConfig = $0 }
        host.onMatchStart = { _, _ in hostPlayerStart = true }
        var guestSeat: Int?
        p.session.onMatchStart = { guestSeat = $1 }
        XCTAssertTrue(host.startMatch(master: .shared, seed: 40))
        XCTAssertNotNil(castConfig, "ホストは観戦の画面で試合を回す")
        XCTAssertFalse(hostPlayerStart)
        XCTAssertEqual(guestSeat, redMid)

        let hc = BattleController(launch: BattleLaunch(config: castConfig!, onlineSpectator: true), online: host)
        XCTAssertTrue(hc.isOnlineHost)
        XCTAssertTrue(hc.isSpectating)
        XCTAssertNil(hc.humanHeroID)
        XCTAssertEqual(hc.onlineSpectatorDelaySeconds, 0, "ホストの実況は遅延なし")
        XCTAssertNotNil(hc.recorder, "ホストの実況は試合を最初から回すので記録する（観戦席とは違う）")
        host.attach(controller: hc)
        XCTAssertFalse(host.canBegin, "座っている選手の読み込みを待つ")
        let pc = BattleController(launch: BattleLaunch(config: castConfig!, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: pc)
        XCTAssertTrue(host.canBegin)
        XCTAssertEqual(pc.onlineSpectatorCount, 1, "選手にはホストの実況が観戦者として見える")

        let guestHero = pc.humanHeroID!
        let start = hc.state.unit(guestHero)!.pos
        pc.send(.move(direction: Vec2(1, 0)))
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [pc], frames: 90, hashes: &hashes)
        XCTAssertNotEqual(hc.state.unit(guestHero)!.pos, start, "選手の入力はホストの実況でも適用される")
        for _ in 0..<100 where pc.state.tick < hc.state.tick { pc.frame(dt: Balance.dt) }
        XCTAssertEqual(pc.state.tick, hc.state.tick)
        XCTAssertEqual(pc.state.stateHash(), hc.state.stateHash())
        XCTAssertEqual(host.resyncCount, 0)
        let outcome = hc.makeOutcome(abandoned: false)
        XCTAssertNil(outcome.summary.humanTeam, "実況のリザルトは観戦扱い")

        // 実況の記録は選手の入力を含み、再生するとホストの状態に戻る（リザルトの「リプレイを見る」・保存の対象）
        let replay = try! XCTUnwrap(outcome.replay, "実況したホストのリプレイ")
        XCTAssertEqual(replay.finalTick, hc.state.tick)
        XCTAssertTrue(replay.frames.contains { $0.commands.contains { $0.heroID == guestHero } }, "選手の入力を記録する")
        let player = ReplayPlayer(data: replay)
        while !player.isFinished { _ = player.stepOnce() }
        XCTAssertEqual(player.simulation.state.stateHash(), hc.state.stateHash(), "記録から同じ試合を再現できる")
        XCTAssertNil(ReplayArchiveService.ownerSeat(for: outcome), "実況のリプレイは持ち主なし（保存の可否は ReplayLibraryTests の表）")
    }

    func testHostCasterLeaveWarnsItEndsTheMatchForEveryone() {
        // ホストの実況の「観戦をやめる」は部屋の試合そのものを終わらせる（ホストの matchEnded(aborted:) が全員へ中断を配る）。
        // 確認は観戦者の「進行状況は保存されません」ではなく、全員の試合が終わると伝える
        let host = makeHost()
        let p = join(host, id: "guest")
        seat(p.session, redMid, hero: "H002")
        host.setSpectator(true)
        XCTAssertTrue(host.startMatch(master: .shared, seed: 41))
        let config = host.room.config!
        let hc = BattleController(launch: BattleLaunch(config: config, onlineSpectator: true), online: host)
        host.attach(controller: hc)
        let pc = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: pc)
        let casterKind = HUDLeaveKind.of(mode: hc.launch.config.mode, isSpectating: hc.isSpectating, isOnlineHost: hc.isOnlineHost)
        XCTAssertEqual(casterKind, .endsMatchForEveryone)
        XCTAssertEqual(casterKind.menuButtonTitle, L("試合を終了", "End Match"))
        XCTAssertNotEqual(casterKind.message, HUDLeaveKind.plain.message)
        XCTAssertNotEqual(casterKind.confirmTitle, HUDLeaveKind.plain.confirmTitle)
        // 観戦席の参加者・選手の参加者は、自分だけが抜ける
        let w = join(host, id: "late", spectate: true)
        let wc = watcherController(w.session)
        XCTAssertEqual(HUDLeaveKind.of(mode: wc.launch.config.mode, isSpectating: wc.isSpectating, isOnlineHost: wc.isOnlineHost), .plain)
        XCTAssertEqual(HUDLeaveKind.of(mode: pc.launch.config.mode, isSpectating: pc.isSpectating, isOnlineHost: pc.isOnlineHost), .plain)
        // 席に着いたホストも同じ（抜けると全員の試合が終わる）
        XCTAssertEqual(HUDLeaveKind.of(mode: .online, isSpectating: false, isOnlineHost: true), .endsMatchForEveryone)
        // オフラインは従来どおり
        XCTAssertEqual(HUDLeaveKind.of(mode: .ranked, isSpectating: false, isOnlineHost: false), .countsAsLoss)
        XCTAssertEqual(HUDLeaveKind.of(mode: .standard, isSpectating: true, isOnlineHost: false), .plain)

        // 確認どおり: 実況をやめると選手の試合は中断で終わる
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [pc], frames: 30, hashes: &hashes)
        _ = hc.makeOutcome(abandoned: true)
        host.detach()
        host.matchEnded(aborted: true, spectating: true)
        for _ in 0..<40 where !pc.isEnded { pc.frame(dt: Balance.dt) }
        XCTAssertTrue(pc.isEnded)
        XCTAssertEqual(pc.state.endReason, .aborted)
    }

    // MARK: 抜けた選手の復帰（B3）・観戦した後は戻れない

    func testAbandonedPlayerCanRejoinAndGetsFramesAgain() {
        let host = makeHost()
        seatHost(host)
        let p = join(host, id: "guest")
        seat(p.session, redMid, hero: "H002")
        XCTAssertTrue(host.startMatch(master: .shared, seed: 50))
        let config = host.room.config!
        let hc = BattleController(launch: BattleLaunch(config: config, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let pc = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: pc)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [pc], frames: 60, hashes: &hashes)
        let guestHero = pc.humanHeroID!

        // 抜ける → AI が引き継ぐ。抜けた選手の入力は捨てる
        _ = pc.makeOutcome(abandoned: true)
        p.session.detach()
        p.session.matchEnded(aborted: true)
        run(host: hc, session: host, clients: [], frames: 5, hashes: &hashes)
        XCTAssertEqual(hc.state.unit(guestHero)?.hero?.controller, .bot)
        XCTAssertEqual(host.room.peer("guest")?.leftMatch, true)
        XCTAssertTrue(p.session.isSittingOutMatch)
        XCTAssertTrue(p.session.canRejoinMatch)
        XCTAssertTrue(p.session.canWatchMatch)
        p.session.sendInput(HeroCommand(heroID: guestHero, command: .move(direction: Vec2(-1, 0))))
        p.session.flush()
        XCTAssertFalse(host.takeRemoteInputs().contains { $0.heroID == guestHero }, "抜けた選手（AI が操作中）の入力は捨てる")
        run(host: hc, session: host, clients: [], frames: 30, hashes: &hashes)
        XCTAssertEqual(hc.state.unit(guestHero)?.hero?.controller, .bot)

        // 試合に戻る（B3: 以前は配信が止まったまま固まっていた）
        var relaunchSeat: Int?
        p.session.onMatchStart = { relaunchSeat = $1 }
        p.session.rejoinMatch()
        XCTAssertEqual(relaunchSeat, redMid)
        let pc2 = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: pc2)
        XCTAssertNotNil(p.session.lastSnapshotTick, "進んでいる試合なので状態が届く")
        run(host: hc, session: host, clients: [pc2], frames: 60, hashes: &hashes)
        XCTAssertEqual(hc.state.unit(guestHero)?.hero?.controller, .human, "操作が人間に戻る")
        XCTAssertGreaterThan(pc2.state.tick, 60, "配信が届いて進む")
        for _ in 0..<100 where pc2.state.tick < hc.state.tick { pc2.frame(dt: Balance.dt) }
        XCTAssertEqual(pc2.state.tick, hc.state.tick)
        XCTAssertEqual(pc2.state.stateHash(), hc.state.stateHash())
        XCTAssertEqual(host.room.peer("guest")?.leftMatch, false)
        XCTAssertFalse(p.session.isSittingOutMatch)
    }

    func testOnlineClientResyncAtSameTickDropsTheRecording() {
        // オンラインの選手がずれて、同じ tick のホストの状態で置き換えた: 記録した入力列からは再現できないので保存しない
        let host = makeHost()
        seatHost(host)
        let p = join(host, id: "guest")
        seat(p.session, redMid, hero: "H002")
        XCTAssertTrue(host.startMatch(master: .shared, seed: 57))
        let config = host.room.config!
        let hc = BattleController(launch: BattleLaunch(config: config, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let pc = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: pc)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [pc], frames: 40, hashes: &hashes)
        for _ in 0..<20 where pc.state.tick < hc.state.tick { pc.frame(dt: Balance.dt) }
        XCTAssertEqual(pc.state.tick, hc.state.tick)
        XCTAssertFalse(pc.recorder!.isIncomplete)
        pc.restore(hc.state)
        XCTAssertTrue(pc.recorder!.isIncomplete, "同じ tick でも置き換えた記録は保存しない")
        XCTAssertNil(pc.makeOutcome(abandoned: false).replay)
        XCTAssertNotNil(hc.makeOutcome(abandoned: false).replay, "ホストの記録はそのまま")
    }

    func testPlayerWhoWatchedCannotRejoinTheSameMatch() {
        let host = makeHost()
        seatHost(host)
        let p = join(host, id: "guest")
        seat(p.session, redMid, hero: "H002")
        XCTAssertTrue(host.startMatch(master: .shared, seed: 51))
        let config = host.room.config!
        let hc = BattleController(launch: BattleLaunch(config: config, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let pc = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: pc)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [pc], frames: 30, hashes: &hashes)
        let guestHero = pc.humanHeroID!
        p.session.detach()
        p.session.matchEnded(aborted: true)

        // 抜けた選手が観戦する（座席は保つ）
        p.session.requestSpectate()
        XCTAssertTrue(p.session.isWatchingMatch)
        XCTAssertEqual(host.room.seatIndex(of: "guest"), redMid, "抜けた選手は座席を保つ")
        let wc = watcherController(p.session)
        run(host: hc, session: host, clients: [wc], frames: 30, hashes: &hashes)
        p.session.detach()
        p.session.matchEnded(aborted: true, spectating: true)
        XCTAssertFalse(p.session.canRejoinMatch, "観戦した試合には戻れない")
        XCTAssertTrue(p.session.canWatchMatch)

        // 偽って選手の戦闘を開いても、ホストは操作を戻さず中断で終わらせる
        let forced = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: forced)
        run(host: hc, session: host, clients: [], frames: 5, hashes: &hashes)
        XCTAssertEqual(hc.state.unit(guestHero)?.hero?.controller, .bot)
        XCTAssertNil(p.session.lastSnapshotTick, "生の状態は渡さない")
    }

    // MARK: 再接続した参加者を試合の終わりで外さない（B4）

    func testReconnectedPeerWithoutLoadedStaysAfterMatchEnd() {
        let host = makeHost()
        seatHost(host)
        let p = join(host, id: "guest")
        seat(p.session, redMid, hero: "H002")
        XCTAssertTrue(host.startMatch(master: .shared, seed: 60))
        let config = host.room.config!
        let hc = BattleController(launch: BattleLaunch(config: config, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let pc = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: pc)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [pc], frames: 20, hashes: &hashes)
        p.clientSide.close()
        run(host: hc, session: host, clients: [], frames: 5, hashes: &hashes)

        // 再接続したが読み込みを終えない（別の戦闘中で断った等）
        let again = join(host, id: "guest")
        XCTAssertEqual(again.session.status, .loading, "座席を保っているので試合へ")
        again.session.declineMatch()
        host.detach()
        host.matchEnded()
        XCTAssertTrue(host.room.peers.contains { $0.id == "guest" }, "繋がっている参加者は試合の終わりで外さない")
        XCTAssertEqual(host.room.seatIndex(of: "guest"), redMid)
        XCTAssertEqual(again.session.room.phase, .lobby)
    }

    // MARK: 再接続

    func testAbandonedPlayerWhoReconnectsChoosesToRejoinOrWatch() {
        let host = makeHost()
        seatHost(host)
        let p = join(host, id: "guest")
        seat(p.session, redMid, hero: "H002")
        XCTAssertTrue(host.startMatch(master: .shared, seed: 52))
        let config = host.room.config!
        let hc = BattleController(launch: BattleLaunch(config: config, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let pc = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: pc)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [pc], frames: 30, hashes: &hashes)
        let guestHero = pc.humanHeroID!
        p.session.detach()
        p.session.matchEnded(aborted: true)
        p.clientSide.close()
        run(host: hc, session: host, clients: [], frames: 5, hashes: &hashes)

        // 自分で抜けた選手は再接続しても試合へ引き戻さない（部屋で「試合に戻る」「観戦する」を選ぶ）
        let again = join(host, id: "guest")
        var pulled = false
        again.session.onMatchStart = { _, _ in pulled = true }
        XCTAssertEqual(again.session.status, .lobby)
        XCTAssertFalse(pulled)
        XCTAssertTrue(again.session.isSittingOutMatch)
        XCTAssertTrue(again.session.canRejoinMatch)
        XCTAssertTrue(again.session.canWatchMatch)
        again.session.rejoinMatch()
        XCTAssertTrue(pulled)
        let pc2 = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: again.session)
        again.session.attach(controller: pc2)
        run(host: hc, session: host, clients: [pc2], frames: 30, hashes: &hashes)
        XCTAssertEqual(hc.state.unit(guestHero)?.hero?.controller, .human)
        for _ in 0..<100 where pc2.state.tick < hc.state.tick { pc2.frame(dt: Balance.dt) }
        XCTAssertEqual(pc2.state.stateHash(), hc.state.stateHash())
    }

    func testWatcherWhoReconnectsStillCannotRejoinAsPlayer() {
        let host = makeHost()
        seatHost(host)
        let p = join(host, id: "guest")
        seat(p.session, redMid, hero: "H002")
        XCTAssertTrue(host.startMatch(master: .shared, seed: 53))
        let config = host.room.config!
        let hc = BattleController(launch: BattleLaunch(config: config, onlineSeat: blueMid), online: host)
        host.attach(controller: hc)
        let pc = BattleController(launch: BattleLaunch(config: config, onlineSeat: redMid), online: p.session)
        p.session.attach(controller: pc)
        var hashes: [Int: UInt64] = [:]
        run(host: hc, session: host, clients: [pc], frames: 30, hashes: &hashes)
        p.session.detach()
        p.session.matchEnded(aborted: true)
        p.session.requestSpectate()
        let wc = watcherController(p.session)
        run(host: hc, session: host, clients: [wc], frames: 30, hashes: &hashes)
        XCTAssertEqual(host.room.peer("guest")?.watchedMatch, true)
        p.clientSide.close()

        // 新しい接続（端末の再起動など）でも、観戦した試合には戻れないことが部屋から分かる
        let again = join(host, id: "guest")
        XCTAssertEqual(again.session.status, .lobby, "観戦した試合へは引き戻さない")
        XCTAssertTrue(again.session.isSittingOutMatch)
        XCTAssertFalse(again.session.canRejoinMatch)
        XCTAssertTrue(again.session.canWatchMatch)
        host.detach()
        host.matchEnded()
        XCTAssertEqual(host.room.peer("guest")?.watchedMatch, false, "次の試合では選手に戻れる")
        XCTAssertEqual(host.room.seatIndex(of: "guest"), redMid)
    }

    // MARK: 版の違い

    func testVersion1HelloIsRejectedCleanly() throws {
        let host = makeHost()
        let (a, b) = LoopbackConnection.pair()
        host.accept(a)
        var received: [OnlineMessage] = []
        b.onMessage = { received.append($0) }
        b.start()
        // v1 のアプリが送る名乗りそのもの（wantsSpectate なし）
        let body = Data(#"{"hello":{"_0":{"peerID":"old","name":"Old","protocolVersion":1,"simVersion":\#(MatchConfig.currentSimVersion)}}}"#.utf8)
        var frame = Data()
        var length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(body)
        b.send(encoded: frame)
        guard case .reject(let reason)? = received.last else { return XCTFail("v1 は版数で断る: \(received)") }
        XCTAssertTrue(reason.contains("1"), reason)
        XCTAssertNil(host.room.peer("old"))
        XCTAssertEqual(host.room.peers.count, 1)
        // v1 の観戦希望（あり得ないが）でも同じ
        let (c, d) = LoopbackConnection.pair()
        host.accept(c)
        var received2: [OnlineMessage] = []
        d.onMessage = { received2.append($0) }
        d.start()
        d.send(.hello(OnlineHello(peerID: "old2", name: "Old", protocolVersion: 1, wantsSpectate: true)))
        guard case .reject? = received2.last else { return XCTFail("\(received2)") }
        XCTAssertNil(host.room.peer("old2"))
        XCTAssertEqual(host.room.spectators.count, 0)
    }

    // MARK: 部品

    func testFrameQueueHandlesLargeBacklogInOrder() {
        var q = OnlineFrameQueue()
        q.append((1...20_000).map { ReplayFrame(tick: $0, commands: []) })
        q.append((19_990...20_010).map { ReplayFrame(tick: $0, commands: []) })   // 重複は捨てる
        XCTAssertEqual(q.count, 20_010)
        let clock = ContinuousClock()
        let started = clock.now
        for t in 1...15_000 { XCTAssertEqual(q.pop(tick: t)?.tick, t) }
        XCTAssertLessThan(clock.now - started, .seconds(2), "先頭からの取り出しは O(1)（removeFirst の O(n²) にしない）")
        XCTAssertEqual(q.count, 5_010)
        XCTAssertNil(q.pop(tick: 30_000))
        XCTAssertEqual(q.count, 0, "それより前は捨てる")
        q.append([ReplayFrame(tick: 5, commands: [])])
        XCTAssertEqual(q.count, 0, "届いた最後の tick より前は捨てる")
        q.removeAll(resettingTo: 3)
        q.append((3...6).map { ReplayFrame(tick: $0, commands: []) })
        XCTAssertEqual(q.first?.tick, 4, "スナップショットの続きだけ受け付ける")
        q.drop(through: 5)
        XCTAssertEqual(q.pop(tick: 6)?.tick, 6)
        XCTAssertTrue(q.isEmpty)
    }

    func testRelayReleasesAfterDelayAndKeepsOnlyWhatJoinsNeed() {
        let config = MatchFactory.onlineMatch(humans: [OnlineHumanSlot(team: .blue, position: .mid, heroID: "H001", displayName: "A")], seed: 1)
        let initial = Simulation(config: config).state
        var relay = OnlineSpectatorRelay()
        relay.reset(active: true, delayTicks: 90, keyframeInterval: 30)
        func state(_ t: Int) -> SimState { var s = initial; s.tick = t; return s }
        for t in 1...200 {
            relay.record(ReplayFrame(tick: t, commands: []), state: { state(t) })
            relay.release()
            relay.trim(pinnedTick: nil)
        }
        XCTAssertEqual(relay.liveTick, 200)
        XCTAssertEqual(relay.releasedTick, 110, "遅延を過ぎた分だけ")
        XCTAssertEqual(relay.baseTick, 90, "公開済みの範囲で最新のキーフレーム")
        XCTAssertEqual(relay.frames(after: relay.baseTick, through: relay.releasedTick)?.map(\.tick), Array(91...110))
        XCTAssertNil(relay.frames(after: 0, through: 10), "基準より古い記録は捨てている")
        XCTAssertTrue(relay.retainedKeyframeTicks.allSatisfy { $0 >= 90 })
        XCTAssertLessThanOrEqual(relay.retainedFrameCount, 200 - 90 + 2 * 30)
        // 終わったら残りをすべて公開
        relay.finish()
        XCTAssertEqual(relay.releasedTick, 200)
        XCTAssertEqual(relay.finalTick, 200)
        XCTAssertEqual(relay.frames(after: 110, through: 200)?.count, 90)
        // 観戦を許可していない部屋は何も記録しない
        var off = OnlineSpectatorRelay()
        off.reset(active: false, delayTicks: 0, keyframeInterval: 30)
        off.record(ReplayFrame(tick: 1, commands: []), state: { state(1) })
        XCTAssertFalse(off.release())
        XCTAssertEqual(off.retainedFrameCount, 0)
    }
}
