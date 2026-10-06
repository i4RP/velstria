import XCTest
@testable import VELSTRIA
import VelstriaCore

/// ホスト / クライアントの OnlineSession をループバック接続で結び、ロビー → 試合 → 同期 → 切断 → 再接続を通す。
@MainActor
final class OnlineSessionTests: XCTestCase {
    private let blueMid = MatchFactory.onlineSeatIndex(team: .blue, position: .mid)
    private let redMid = MatchFactory.onlineSeatIndex(team: .red, position: .mid)

    private struct Pair {
        let host: OnlineSession
        let client: OnlineSession
        let hostLink: LoopbackConnection
        let clientLink: LoopbackConnection
    }

    private func makePair(clientID: String = "guest") -> Pair {
        let host = OnlineSession.host(peerID: "host", name: "Host", roomName: "Room")
        let (a, b) = LoopbackConnection.pair()
        host.accept(a)
        let client = OnlineSession.join(peerID: clientID, name: "Guest", connection: b)
        return Pair(host: host, client: client, hostLink: a, clientLink: b)
    }

    /// 両者が着席・ピック・準備完了し、ホストが開始した状態。
    private func startedMatch(seed: UInt64 = 42) -> (pair: Pair, config: MatchConfig, hostSeat: Int, clientSeat: Int) {
        let p = makePair()
        p.host.takeSeat(blueMid)
        p.client.takeSeat(redMid)
        p.host.setLoadout(OnlineLoadout(heroID: "H001"))
        p.client.setLoadout(OnlineLoadout(heroID: "H002"))
        p.host.setReady(true)
        p.client.setReady(true)
        var hostStart: (MatchConfig, Int?)?
        var clientStart: (MatchConfig, Int?)?
        p.host.onMatchStart = { hostStart = ($0, $1) }
        p.client.onMatchStart = { clientStart = ($0, $1) }
        XCTAssertTrue(p.host.startMatch(master: .shared, seed: seed))
        XCTAssertEqual(hostStart?.1, blueMid)
        XCTAssertEqual(clientStart?.1, redMid)
        XCTAssertEqual(hostStart?.0, clientStart?.0)
        return (p, hostStart!.0, blueMid, redMid)
    }

    private func controllers(_ s: (pair: Pair, config: MatchConfig, hostSeat: Int, clientSeat: Int))
        -> (host: BattleController, client: BattleController) {
        let h = BattleController(launch: BattleLaunch(config: s.config, onlineSeat: s.hostSeat), online: s.pair.host)
        let c = BattleController(launch: BattleLaunch(config: s.config, onlineSeat: s.clientSeat), online: s.pair.client)
        return (h, c)
    }

    private func run(_ host: BattleController, _ client: BattleController, frames: Int) {
        for _ in 0..<frames {
            host.frame(dt: Balance.dt)
            client.frame(dt: Balance.dt)
        }
    }

    /// ホストを止めてクライアントを追いつかせる（同じ tick で比較するため）。
    private func catchUp(_ client: BattleController, to host: BattleController) {
        var guardCount = 0
        while client.state.tick < host.state.tick, guardCount < 100 {
            client.frame(dt: Balance.dt)
            guardCount += 1
        }
        XCTAssertEqual(client.state.tick, host.state.tick)
    }

    // MARK: ロビー

    func testLobbyFlow() {
        let p = makePair()
        XCTAssertEqual(p.client.status, .lobby)
        XCTAssertEqual(p.client.room.name, "Room")
        XCTAssertEqual(p.client.room.peers.map(\.id), ["host", "guest"])
        XCTAssertEqual(p.host.connectedPeerCount, 2)

        p.host.takeSeat(blueMid)
        p.client.takeSeat(redMid)
        XCTAssertEqual(p.host.room.seatIndex(of: "guest"), redMid)
        XCTAssertEqual(p.client.room, p.host.room, "部屋はホストの正本が配られる")
        XCTAssertEqual(p.client.localSeat?.name, "Guest")

        // 埋まっている席には座れない（元の席に残る）
        p.client.takeSeat(blueMid)
        XCTAssertEqual(p.client.room.seatIndex(of: "guest"), redMid)

        // 同じヒーローは選べない
        p.host.setLoadout(OnlineLoadout(heroID: "H001"))
        p.client.setLoadout(OnlineLoadout(heroID: "H001"))
        XCTAssertNil(p.client.room.seat(of: "guest")?.loadout.heroID)
        p.client.setLoadout(OnlineLoadout(heroID: "H002", spells: ["BS02", "BS04"], runes: ["R001"], skinID: nil, autoLevelSkills: false))
        XCTAssertEqual(p.host.room.seat(of: "guest")?.loadout.heroID, "H002")

        // ヒーロー未選択では準備完了にならない
        XCTAssertFalse(p.host.room.canStart)
        p.host.setReady(true)
        XCTAssertFalse(p.host.room.canStart, "参加者が未準備")
        p.client.setReady(true)
        XCTAssertTrue(p.client.room.canStart)

        // ピックを変えると準備完了が外れる
        p.client.setLoadout(OnlineLoadout(heroID: "H003"))
        XCTAssertFalse(p.host.room.seat(of: "guest")?.ready ?? true)
        p.client.setReady(true)

        // 席を立つと席が空く
        p.client.takeSeat(-1)
        XCTAssertNil(p.host.room.seat(of: "guest"))
        XCTAssertFalse(p.host.room.seats[redMid].isHuman)
        p.client.takeSeat(redMid)
        XCTAssertEqual(p.host.room.seat(of: "guest")?.loadout.heroID, "H003", "ロードアウトは席を移っても保つ")
        p.client.setReady(true)

        p.host.setBotDifficulty(.hard)
        XCTAssertEqual(p.client.room.botDifficulty, .hard)

        // 開始: 構成は座席と一致し、両者に同じものが届く
        var clientConfig: MatchConfig?
        p.client.onMatchStart = { c, seat in
            clientConfig = c
            XCTAssertEqual(seat, self.redMid)
        }
        XCTAssertTrue(p.host.startMatch(master: .shared, seed: 5))
        XCTAssertEqual(clientConfig, p.host.room.config)
        XCTAssertEqual(clientConfig?.players[redMid].heroID, "H003")
        XCTAssertEqual(clientConfig?.players[redMid].spells, ["BS01", "BS03"], "既定スペル（ロードアウト未指定）")
        XCTAssertEqual(clientConfig?.players[blueMid].heroID, "H001")
        XCTAssertEqual(p.client.status, .loading)
        XCTAssertFalse(p.host.startMatch(master: .shared), "開始後は再開始できない")
    }

    func testRejectsVersionMismatchAndSelf() {
        let host = OnlineSession.host(peerID: "host", name: "Host", roomName: "Room")
        let (a, b) = LoopbackConnection.pair()
        host.accept(a)
        var received: [OnlineMessage] = []
        b.onMessage = { received.append($0) }
        b.start()
        b.send(.hello(OnlineHello(peerID: "x", name: "X", protocolVersion: OnlineProtocol.version + 1)))
        guard case .reject? = received.last else { return XCTFail("版数不一致は拒否: \(received)") }
        XCTAssertEqual(host.room.peers.count, 1)

        let (c, d) = LoopbackConnection.pair()
        host.accept(c)
        var received2: [OnlineMessage] = []
        d.onMessage = { received2.append($0) }
        d.start()
        d.send(.hello(OnlineHello(peerID: "host", name: "Me")))
        guard case .reject? = received2.last else { return XCTFail("自分自身は拒否: \(received2)") }
    }

    func testLateJoinerDuringMatchWaitsInRoomAndCanWatch() {
        // v2: 試合中の新規参加は拒否せず、座席なしで部屋に入れる（試合が終わるまで待つか、観戦を求める）
        let s = startedMatch()
        let (a, b) = LoopbackConnection.pair()
        s.pair.host.accept(a)
        var started = false
        let late = OnlineSession.join(peerID: "late", name: "Late", connection: b)
        late.onMatchStart = { _, _ in started = true }
        XCTAssertEqual(late.status, .lobby, "試合中でも部屋には入れる: \(late.status)")
        XCTAssertTrue(s.pair.host.room.peers.contains { $0.id == "late" })
        XCTAssertNil(late.localSeat)
        XCTAssertEqual(late.localRole, .player)
        XCTAssertTrue(late.isSittingOutMatch, "ロビーには「試合中」の画面を出す")
        XCTAssertTrue(late.canWatchMatch)
        XCTAssertFalse(late.canRejoinMatch, "座席が無いので選手としては入れない")
        XCTAssertFalse(started, "座っていない参加者には開始の合図を送らない")
        XCTAssertFalse(late.isWatchingMatch, "観戦は求めるまで始まらない")
    }

    // MARK: 戦闘の同期

    func testLockstepKeepsClientInSyncAndAppliesClientInput() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        XCTAssertEqual(host.localTeam, .blue)
        XCTAssertEqual(client.localTeam, .red)
        XCTAssertEqual(client.viewerTeam, .red)
        XCTAssertNotEqual(host.humanHeroID, client.humanHeroID)
        XCTAssertEqual(client.humanHeroID, client.heroID(forSeat: redMid))
        XCTAssertEqual(client.state.unit(client.humanHeroID)?.hero?.heroID, "H002")

        // ホストは参加者の読み込みを待つ
        s.pair.host.attach(controller: host)
        XCTAssertFalse(s.pair.host.canBegin)
        host.frame(dt: Balance.dt)
        XCTAssertEqual(host.state.tick, 0)
        XCTAssertEqual(host.onlineStatus, .waitingForPlayers)

        s.pair.client.attach(controller: client)
        XCTAssertTrue(s.pair.host.canBegin)
        XCTAssertEqual(s.pair.host.room.phase, .playing)

        // クライアントの入力はホストで適用され、配信でクライアントにも反映される
        let clientHero = client.humanHeroID!
        let start = host.state.unit(clientHero)!.pos
        client.send(.move(direction: Vec2(1, 0)))
        client.frame(dt: Balance.dt)   // 入力を送る（配信はまだ無いので待つ）
        XCTAssertEqual(client.state.tick, 0)

        run(host, client, frames: 120)
        XCTAssertGreaterThanOrEqual(host.state.tick, 118)
        XCTAssertGreaterThanOrEqual(client.state.tick, host.state.tick - BattleController.onlineJitterBuffer - 2)
        XCTAssertNotEqual(host.state.unit(clientHero)!.pos, start, "ホスト上で参加者のヒーローが動いた")
        XCTAssertEqual(host.state.unit(clientHero)?.hero?.controller, .human)

        catchUp(client, to: host)
        XCTAssertEqual(client.state.stateHash(), host.state.stateHash())
        XCTAssertEqual(client.state.unit(clientHero)!.pos, host.state.unit(clientHero)!.pos)
        XCTAssertEqual(s.pair.host.resyncCount, 0)
        XCTAssertEqual(s.pair.client.resyncCount, 0)
        XCTAssertEqual(client.onlineStatus, .none)

        // ホストの入力も同様に両者へ
        let hostHero = host.humanHeroID!
        let hostStart = host.state.unit(hostHero)!.pos
        host.send(.move(direction: Vec2(0, 1)))
        run(host, client, frames: 60)
        catchUp(client, to: host)
        XCTAssertNotEqual(client.state.unit(hostHero)!.pos, hostStart)
        XCTAssertEqual(client.state.stateHash(), host.state.stateHash())

        // リプレイは両者で同じ入力列を記録する
        XCTAssertEqual(host.recorder?.frames, client.recorder?.frames)
    }

    func testClientInputForForeignHeroIsIgnored() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        let hostHero = host.humanHeroID!
        let start = host.state.unit(hostHero)!.pos
        // 他人のヒーローへの入力・操作者の切り替えは捨てられる
        s.pair.client.sendInput(HeroCommand(heroID: hostHero, command: .move(direction: Vec2(1, 0))))
        s.pair.client.sendInput(HeroCommand(heroID: client.humanHeroID!, command: .setController(.bot)))
        s.pair.client.flush()
        run(host, client, frames: 60)
        XCTAssertEqual(host.state.unit(hostHero)!.pos, start)
        XCTAssertEqual(host.state.unit(client.humanHeroID)?.hero?.controller, .human)
    }

    func testClientWaitsWhenFramesAreDelayedThenCatchesUp() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        run(host, client, frames: 30)
        catchUp(client, to: host)

        // 配信を止める → クライアントは進まず「待ち」になる
        s.pair.clientLink.holdsDelivery = true
        let tick = client.state.tick
        for _ in 0..<60 {
            host.frame(dt: Balance.dt)
            client.frame(dt: Balance.dt)
        }
        XCTAssertEqual(client.state.tick, tick)
        XCTAssertEqual(client.interpolationAlpha, 1)
        guard case .waitingForHost = client.onlineStatus else { return XCTFail("待機表示: \(client.onlineStatus)") }

        // 再開 → 溜まった分を早送りで消化し追いつく
        s.pair.clientLink.holdsDelivery = false
        XCTAssertGreaterThan(s.pair.client.bufferedFrames, BattleController.onlineCatchUpThreshold)
        for _ in 0..<20 { client.frame(dt: Balance.dt) }
        XCTAssertEqual(client.state.tick, host.state.tick)
        XCTAssertEqual(client.state.stateHash(), host.state.stateHash())
        XCTAssertEqual(client.onlineStatus, .none)
    }

    func testDesyncIsDetectedAndResynced() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        run(host, client, frames: 40)

        // クライアントの状態を壊す（ヒーローを別の場所へ）
        var corrupted = client.state
        let i = client.humanIndex!
        corrupted.units[i].pos = corrupted.units[i].pos + Vec2(500, 500)
        client.restore(corrupted)
        XCTAssertNotEqual(client.state.stateHash(), host.state.stateHash())

        // 次のハッシュ報告（30 tick 毎）で検出され、スナップショットで戻る
        run(host, client, frames: 90)
        XCTAssertEqual(s.pair.host.resyncCount, 1)
        XCTAssertEqual(s.pair.client.resyncCount, 1)
        catchUp(client, to: host)
        XCTAssertEqual(client.state.stateHash(), host.state.stateHash())

        // 以後は再同期が増えない
        run(host, client, frames: 120)
        catchUp(client, to: host)
        XCTAssertEqual(client.state.stateHash(), host.state.stateHash())
        XCTAssertEqual(s.pair.host.resyncCount, 1)
    }

    // MARK: 切断・再接続

    func testClientDisconnectHandsHeroToBotAndReconnectRestoresIt() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        run(host, client, frames: 30)
        let clientHero = client.humanHeroID!

        // 切断 → ホストは AI に引き継ぐ。クライアント側は試合が終わる
        s.pair.clientLink.close()
        XCTAssertFalse(s.pair.client.isConnected)
        host.frame(dt: Balance.dt)
        XCTAssertEqual(host.state.unit(clientHero)?.hero?.controller, .bot)
        XCTAssertEqual(s.pair.host.room.seatIndex(of: "guest"), redMid, "座席は保つ")
        XCTAssertTrue(s.pair.host.room.peers.contains { $0.id == "guest" })
        client.frame(dt: Balance.dt)
        XCTAssertTrue(client.isEnded)
        XCTAssertEqual(client.onlineStatus, .disconnected)
        XCTAssertEqual(client.state.endReason, .aborted)
        run(host, host, frames: 30)

        // 再接続（同じ peerID）: 試合の構成が届き、読み込み完了でスナップショットと操作権が戻る
        let (a2, b2) = LoopbackConnection.pair()
        s.pair.host.accept(a2)
        var relaunch: (MatchConfig, Int?)?
        let client2 = OnlineSession.join(peerID: "guest", name: "Guest", connection: b2)
        client2.onMatchStart = { relaunch = ($0, $1) }
        // onMatchStart は join 直後の welcome/startMatch で呼ばれるため、設定前なら room から読む
        if relaunch == nil { relaunch = (client2.room.config!, client2.room.seatIndex(of: "guest")) }
        XCTAssertEqual(relaunch?.1, redMid)
        XCTAssertEqual(relaunch?.0, s.config)
        XCTAssertEqual(client2.status, .loading)

        let controller2 = BattleController(launch: BattleLaunch(config: s.config, onlineSeat: redMid), online: client2)
        client2.attach(controller: controller2)
        XCTAssertEqual(client2.resyncCount, 1, "スナップショットが届く")
        host.frame(dt: Balance.dt)   // setController(.human) を適用・配信
        controller2.frame(dt: Balance.dt)   // スナップショット適用 + 配信を消化
        XCTAssertEqual(host.state.unit(clientHero)?.hero?.controller, .human)
        run(host, controller2, frames: 60)
        catchUp(controller2, to: host)
        XCTAssertEqual(controller2.state.stateHash(), host.state.stateHash())
        XCTAssertEqual(controller2.state.unit(clientHero)?.hero?.controller, .human)
        XCTAssertEqual(controller2.humanHeroID, clientHero)
    }

    func testHostLeaveEndsClientMatch() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        run(host, client, frames: 30)
        var toast: String?
        s.pair.client.onDisconnected = { toast = $0 }
        s.pair.host.leave()
        XCTAssertFalse(s.pair.client.isConnected)
        XCTAssertNotNil(toast)
        client.frame(dt: Balance.dt)
        XCTAssertTrue(client.isEnded)
        let outcome = client.makeOutcome(abandoned: false)
        XCTAssertEqual(outcome.summary.humanTeam, .red)
        XCTAssertEqual(outcome.summary.players.filter(\.isHuman).count, 1, "自分だけが人間として記録される")
        XCTAssertEqual(outcome.summary.humanPlayer?.heroID, "H002")
    }

    func testClientFinishesTrailingFramesAfterHostReturnsToLobby() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        run(host, client, frames: 30)
        // ホストだけ進める（配信はクライアントのバッファに溜まる）→ ホストが試合を終えてロビーへ戻す
        for _ in 0..<45 { host.frame(dt: Balance.dt) }
        let hostTick = host.state.tick
        s.pair.host.matchEnded()
        XCTAssertEqual(s.pair.client.room.phase, .lobby)
        XCTAssertGreaterThan(s.pair.client.bufferedFrames, 0, "ロビーに戻っても未消化の配信は残る")
        for _ in 0..<60 { client.frame(dt: Balance.dt) }
        XCTAssertEqual(client.state.tick, hostTick)
        XCTAssertEqual(client.state.stateHash(), host.state.stateHash())
    }

    func testDisconnectDuringLoadingHandsOverOnceHeroesExist() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        // 読み込み中（ホストの controller 未接続）に参加者が落ちる
        s.pair.clientLink.close()
        XCTAssertTrue(s.pair.host.room.peers.first { $0.id == "guest" }?.loaded ?? false, "落ちた参加者は待たない")
        s.pair.host.attach(controller: host)
        XCTAssertTrue(s.pair.host.canBegin)
        host.frame(dt: Balance.dt)
        XCTAssertEqual(host.state.unit(client.humanHeroID)?.hero?.controller, .bot, "ヒーロー確定後に AI へ引き継ぐ")
    }

    func testReconnectOverStaleConnectionGetsSnapshot() {
        // 古い接続がまだ生きているうちに同じ playerID で繋ぎ直す（経路が片側だけ死んだ時）
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        run(host, client, frames: 60)
        let clientHero = client.humanHeroID!

        let (a2, b2) = LoopbackConnection.pair()
        s.pair.host.accept(a2)
        let client2 = OnlineSession.join(peerID: "guest", name: "Guest", connection: b2)
        XCTAssertEqual(s.pair.clientLink.state, .closed, "古い接続は置き換えられて閉じる")
        XCTAssertEqual(client2.status, .loading)
        XCTAssertEqual(client2.room.config, s.config)
        XCTAssertTrue(s.pair.host.canBegin, "再接続の読み込み待ちでホストは止まらない")
        run(host, host, frames: 30)

        let controller2 = BattleController(launch: BattleLaunch(config: s.config, onlineSeat: redMid), online: client2)
        client2.attach(controller: controller2)
        XCTAssertEqual(client2.resyncCount, 1, "進んでいる試合に入るのでスナップショットが届く")
        run(host, controller2, frames: 60)
        catchUp(controller2, to: host)
        XCTAssertEqual(controller2.state.stateHash(), host.state.stateHash())
        XCTAssertEqual(host.state.unit(clientHero)?.hero?.controller, .human)
        XCTAssertEqual(controller2.onlineStatus, .none)
    }

    func testLateLoaderAfterTimeoutGetsSnapshot() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        XCTAssertFalse(s.pair.host.canBegin)
        // 読み込み待ちの上限を過ぎたら参加者抜きで進め始める
        let start = Date()
        s.pair.host.now = { start.addingTimeInterval(OnlineProtocol.loadTimeout + 1) }
        XCTAssertTrue(s.pair.host.canBegin)
        run(host, host, frames: 90)
        XCTAssertGreaterThan(host.state.tick, 0)

        // 遅れて読み込みを終えた参加者には現在の状態が渡り、以後同期する
        s.pair.client.attach(controller: client)
        XCTAssertEqual(s.pair.client.resyncCount, 1)
        run(host, client, frames: 60)
        catchUp(client, to: host)
        XCTAssertEqual(client.state.stateHash(), host.state.stateHash())
        XCTAssertEqual(host.state.unit(client.humanHeroID)?.hero?.controller, .human)
    }

    func testHostAbortPropagatesToClients() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        run(host, client, frames: 30)
        // ホストだけ進めてから退出（配信はクライアントのバッファに残る）
        for _ in 0..<10 { host.frame(dt: Balance.dt) }
        let hostTick = host.state.tick
        _ = host.makeOutcome(abandoned: true)
        s.pair.host.matchEnded(aborted: true)
        XCTAssertTrue(s.pair.client.isConnected)
        XCTAssertFalse(s.pair.client.isMatchLive)
        XCTAssertEqual(s.pair.client.room.phase, .lobby)
        // 届いていた分は消化してから中断終了する
        for _ in 0..<20 { client.frame(dt: Balance.dt) }
        XCTAssertTrue(client.isEnded)
        XCTAssertEqual(client.state.endReason, .aborted)
        XCTAssertEqual(client.state.tick, hostTick, "中断前の配信は最後まで再生する")
        XCTAssertEqual(client.onlineStatus, .disconnected)
        // 部屋には残っていて、次の試合を始められる
        s.pair.client.matchEnded(aborted: false)
        XCTAssertEqual(s.pair.host.room.peers.count, 2)
        s.pair.host.setReady(true)
        s.pair.client.setReady(true)
        XCTAssertTrue(s.pair.host.startMatch(master: .shared, seed: 9))
    }

    func testClientAbandonHandsHeroToBotAndStaysInRoom() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        run(host, client, frames: 30)
        let clientHero = client.humanHeroID!
        _ = client.makeOutcome(abandoned: true)
        s.pair.client.matchEnded(aborted: true)
        host.frame(dt: Balance.dt)
        XCTAssertEqual(host.state.unit(clientHero)?.hero?.controller, .bot)
        XCTAssertTrue(s.pair.host.room.peers.contains { $0.id == "guest" })
        XCTAssertEqual(s.pair.host.room.seatIndex(of: "guest"), redMid)
        // 抜けた参加者には配信しない（溜まらない）
        run(host, host, frames: 30)
        XCTAssertEqual(s.pair.client.bufferedFrames, 0)
        s.pair.host.matchEnded()
        XCTAssertEqual(s.pair.client.room.phase, .lobby)
        s.pair.host.setReady(true)
        s.pair.client.setReady(true)
        XCTAssertTrue(s.pair.host.startMatch(master: .shared, seed: 10))
    }

    func testDroppedPeerIsRemovedWhenMatchEnds() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        run(host, client, frames: 10)
        s.pair.clientLink.close()
        host.frame(dt: Balance.dt)
        XCTAssertEqual(s.pair.host.room.seatIndex(of: "guest"), redMid, "試合中は席を保つ")
        s.pair.host.matchEnded()
        XCTAssertNil(s.pair.host.room.seatIndex(of: "guest"), "戻らなかった参加者の席は空く")
        XCTAssertEqual(s.pair.host.room.peers.map(\.id), ["host"])
        s.pair.host.setReady(true)
        XCTAssertTrue(s.pair.host.room.canStart)
    }

    func testHostPauseDoesNotStopTheWorld() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        host.isPaused = true
        XCTAssertFalse(host.isPaused, "オンラインでは一時停止にならない")
        run(host, client, frames: 30)
        XCTAssertGreaterThanOrEqual(host.state.tick, 29)
        client.isPaused = true
        XCTAssertFalse(client.isPaused)
    }

    func testUnseatedPeerDoesNotReceiveFrames() {
        // 座らず観戦席にも入っていない参加者（選手の役割のまま待っている人）には、開始の合図も配信も送らない。
        // 観戦の配信は観戦席・観戦を求めた参加者だけ（OnlineSpectatorTests）
        let p2 = makePair(clientID: "watcher")
        p2.host.takeSeat(blueMid)
        p2.host.setLoadout(OnlineLoadout(heroID: "H001"))
        p2.host.setReady(true)
        var watcherStart = false
        p2.client.onMatchStart = { _, _ in watcherStart = true }
        XCTAssertTrue(p2.host.startMatch(master: .shared, seed: 3))
        XCTAssertFalse(watcherStart, "座っていない参加者には開始の合図を送らない")
        XCTAssertEqual(p2.client.room.phase, .loading, "部屋の状態は届く")
        let h2 = BattleController(launch: BattleLaunch(config: p2.host.room.config!, onlineSeat: blueMid), online: p2.host)
        p2.host.attach(controller: h2)
        run(h2, h2, frames: 30)
        XCTAssertEqual(p2.client.bufferedFrames, 0)
    }

    func testLivenessTimeoutDisconnectsSilentPeer() {
        let p = makePair()
        var hostClock = ProcessInfo.processInfo.systemUptime
        p.host.uptime = { hostClock }
        p.host.ping()
        p.client.takeSeat(redMid)   // 応答があれば切れない
        hostClock += OnlineProtocol.livenessTimeout - 1
        p.host.ping()
        XCTAssertTrue(p.client.isConnected)
        hostClock += OnlineProtocol.livenessTimeout + 1
        p.client.takeSeat(redMid)   // この受信は hostClock 更新前の時刻で記録されている
        p.host.uptime = { hostClock + OnlineProtocol.livenessTimeout + 1 }
        p.host.ping()
        XCTAssertFalse(p.client.isConnected, "長く何も届かない参加者は切断される")
        XCTAssertEqual(p.host.room.peers.map(\.id), ["host"])

        // クライアント側も同様にホストの無応答を検出する
        let q = makePair()
        var clientClock = ProcessInfo.processInfo.systemUptime
        q.client.uptime = { clientClock }
        q.client.ping()
        clientClock += OnlineProtocol.livenessTimeout + 1
        q.client.ping()
        guard case .disconnected = q.client.status else { return XCTFail("ホストの無応答で切断: \(q.client.status)") }
    }

    func testMatchEndedReturnsRoomToLobby() {
        let s = startedMatch()
        let (host, client) = controllers(s)
        s.pair.host.attach(controller: host)
        s.pair.client.attach(controller: client)
        run(host, client, frames: 10)
        s.pair.client.matchEnded()
        s.pair.host.matchEnded()
        XCTAssertEqual(s.pair.host.room.phase, .lobby)
        XCTAssertEqual(s.pair.client.room.phase, .lobby)
        XCTAssertEqual(s.pair.client.status, .lobby)
        XCTAssertTrue(s.pair.host.room.seats.allSatisfy { !$0.ready })
        XCTAssertEqual(s.pair.host.room.seatIndex(of: "guest"), redMid)
        // もう一度開始できる
        s.pair.host.setReady(true)
        s.pair.client.setReady(true)
        XCTAssertTrue(s.pair.host.startMatch(master: .shared, seed: 8))
    }
}
