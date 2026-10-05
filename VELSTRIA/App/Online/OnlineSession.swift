import Foundation
import Observation
import VelstriaCore

// 担当: online。1 つの部屋への参加状態（ホスト or クライアント）。ロビーから戦闘・リザルトまで生き続け、
// AppModel.online に置かれる。
//
// ホスト: 待ち受け・部屋の正本・座席の受付。戦闘中は各クライアントの入力を集めて権威シミュレーションに適用し、
//         tick 毎の入力を全員へ配信する。クライアントの状態ハッシュを照合し、食い違えばスナップショットを送る。
// クライアント: 入力をホストへ送り、配信された tick の入力を順に自分のシミュレーションへ投入する。
//
// BattleController は OnlineBattleLink だけを見る（テストはループバック接続で同じ経路を通す）。

/// BattleController が戦闘中に使う窓口。
@MainActor
protocol OnlineBattleLink: AnyObject {
    var isHost: Bool { get }
    /// 相手と繋がっている（クライアント: ホストと。ホスト: 待ち受け中）。
    var isConnected: Bool { get }
    /// ホスト: 座っている全員の読み込みが済んだ（または待ち時間切れ）。クライアントは常に true。
    var canBegin: Bool { get }
    /// 戦闘画面がシミュレーションを作った。座席 → ヒーロー ID の対応を確定し、クライアントは loaded を送る。
    func attach(controller: BattleController)
    func detach()
    // ホスト
    /// 前回以降に届いた全クライアントの入力（+ ホストが発行する操作者切り替え）。
    func takeRemoteInputs() -> [HeroCommand]
    /// この tick に適用した入力を配信キューへ（stateHash は照合用。hashInterval の tick のみ非 nil）。
    func publish(frame: ReplayFrame, stateHash: UInt64?)
    // クライアント
    /// 次に進める tick の入力（まだ届いていなければ nil）。
    func frame(forTick tick: Int) -> ReplayFrame?
    /// 未適用の配信済み tick 数。
    var bufferedFrames: Int { get }
    func sendInput(_ command: HeroCommand)
    func reportHash(tick: Int, value: UInt64)
    /// 届いている再同期スナップショット（取り出すと消える）。
    func takeSnapshot() -> SimState?
    // 共通
    /// 1 描画フレームの終わりにまとめて送る。
    func flush()
}

@Observable
@MainActor
final class OnlineSession: OnlineBattleLink {
    enum Role: Equatable { case host, client }

    enum Status: Equatable {
        case starting
        case connecting
        case lobby
        case loading
        case playing
        case disconnected(String)
    }

    let role: Role
    let localPeerID: OnlinePeerID
    let localName: String
    private(set) var room: OnlineRoom
    private(set) var status: Status
    /// 画面に出す直近の出来事（新しいものが末尾）。
    private(set) var events: [String] = []
    /// クライアント: ホストとの往復遅延（秒）。
    private(set) var rtt: Double?
    /// ホスト: 待ち受けポート（Bonjour に加えて手入力で繋ぐ用）。
    private(set) var listenPort: UInt16?
    private(set) var listenError: String?
    /// 再同期の回数（デバッグ表示）。
    private(set) var resyncCount = 0
    /// 試合開始の合図（AppModel が BattleLaunch を作る）。座席番号は自分のもの（座っていなければ nil）。
    @ObservationIgnored var onMatchStart: ((MatchConfig, Int?) -> Void)?
    /// 切断の通知（トースト用）。
    @ObservationIgnored var onDisconnected: ((String) -> Void)?
    /// テスト用: 現在時刻の供給。
    @ObservationIgnored var now: () -> Date = { Date() }

    // ホスト側
    @ObservationIgnored private var listener: NWOnlineListener?
    @ObservationIgnored private var connections: [UUID: OnlineConnection] = [:]
    @ObservationIgnored private var peerByConnection: [UUID: OnlinePeerID] = [:]
    @ObservationIgnored private var connectionByPeer: [OnlinePeerID: UUID] = [:]
    @ObservationIgnored private var remoteInputs: [HeroCommand] = []
    @ObservationIgnored private var hostCommands: [HeroCommand] = []
    @ObservationIgnored private var outgoingFrames: [ReplayFrame] = []
    @ObservationIgnored private var hashHistory: [Int: UInt64] = [:]
    @ObservationIgnored private var hashTicks: [Int] = []
    /// 再同期を送った tick（それ以前の報告は無視する）。
    @ObservationIgnored private var resyncedAt: [OnlinePeerID: Int] = [:]
    @ObservationIgnored private var matchStartedAt: Date?
    /// 試合中に落ちて座席を保っている参加者（再接続で戻る）。
    @ObservationIgnored private var droppedPeers: Set<OnlinePeerID> = []
    /// 席を立った参加者のロードアウト（座り直した時に戻す）。
    @ObservationIgnored private var rememberedLoadouts: [OnlinePeerID: OnlineLoadout] = [:]
    /// 座席 → 操作者の切り替え予約（読み込み中に落ちた時など、ヒーロー ID が確定する前に積む）。
    @ObservationIgnored private var pendingHandovers: [(seat: Int, controller: Controller)] = []

    // クライアント側
    @ObservationIgnored private var connection: OnlineConnection?
    @ObservationIgnored private var frameBuffer: [ReplayFrame] = []
    @ObservationIgnored private var pendingSnapshot: SimState?
    @ObservationIgnored private var outgoingInputs: [HeroCommand] = []
    @ObservationIgnored private var inputSequence: UInt32 = 0

    // 共通
    @ObservationIgnored private weak var controller: BattleController?
    @ObservationIgnored private var heroIDBySeat: [EntityID] = []
    @ObservationIgnored private var pingTimer: Timer?
    @ObservationIgnored private var pingSequence: UInt32 = 0
    @ObservationIgnored private var pingSentAt: [UUID: [UInt32: TimeInterval]] = [:]
    @ObservationIgnored private var closed = false

    static let maxEvents = 30
    static let pingInterval: TimeInterval = 2
    /// ホストが保持する照合用ハッシュの数（tick 単位）。
    static let hashHistoryLimit = 20

    private init(role: Role, peerID: OnlinePeerID, name: String, room: OnlineRoom) {
        self.role = role
        self.localPeerID = peerID
        self.localName = name
        self.room = room
        self.status = role == .host ? .lobby : .connecting
    }

    // MARK: - 生成

    /// 部屋を作る（待ち受けは `startListening` で開く。テストはループバック接続を `accept` で渡す）。
    static func host(peerID: OnlinePeerID, name: String, roomName: String) -> OnlineSession {
        var room = OnlineRoom(name: roomName, hostPeerID: peerID)
        room.peers = [OnlinePeer(id: peerID, name: name)]
        let s = OnlineSession(role: .host, peerID: peerID, name: name, room: room)
        s.startPing()
        return s
    }

    /// 部屋に入る。接続は未開始のものを渡す（ready になったら名乗る）。
    static func join(peerID: OnlinePeerID, name: String, connection: OnlineConnection) -> OnlineSession {
        let s = OnlineSession(role: .client, peerID: peerID, name: name, room: OnlineRoom(name: "", hostPeerID: ""))
        s.connect(connection)
        s.startPing()
        return s
    }

    var isHost: Bool { role == .host }

    var isConnected: Bool {
        guard !closed else { return false }
        switch role {
        case .host: return true
        case .client: return connection?.state == .ready
        }
    }

    /// 自分の座席。
    var localSeat: OnlineSeat? { room.seat(of: localPeerID) }
    var localSeatIndex: Int? { room.seatIndex(of: localPeerID) }
    /// 接続している参加者数（自分を含む）。
    var connectedPeerCount: Int { room.peers.count }

    private func note(_ text: String) {
        events.append(text)
        if events.count > Self.maxEvents { events.removeFirst(events.count - Self.maxEvents) }
    }

    // MARK: - ホスト: 待ち受け

    func startListening(preferredPort: UInt16? = OnlineProtocol.defaultPort, advertises: Bool = true) {
        guard role == .host, listener == nil else { return }
        let l = NWOnlineListener(roomName: room.name, preferredPort: preferredPort, advertises: advertises)
        l.onAccept = { [weak self] c in self?.accept(c) }
        l.onStateChange = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready(let port):
                self.listenPort = port
                self.listenError = nil
                self.note(L("待ち受けを開始しました（ポート \(port)）", "Listening on port \(port)"))
            case .failed(let reason):
                self.listenError = reason
                self.note(L("待ち受けに失敗: \(reason)", "Listen failed: \(reason)"))
            default: break
            }
        }
        listener = l
        l.start()
    }

    /// 接続を受け入れる（名乗りを待つ）。
    func accept(_ c: OnlineConnection) {
        guard role == .host, !closed else { c.close(); return }
        connections[c.id] = c
        c.onMessage = { [weak self, weak c] m in
            guard let self, let c else { return }
            self.hostReceived(m, from: c)
        }
        c.onStateChange = { [weak self, weak c] st in
            guard let self, let c else { return }
            switch st {
            case .closed, .failed: self.hostLost(c)
            default: break
            }
        }
        if c.state == .connecting { c.start() }
    }

    private func hostLost(_ c: OnlineConnection) {
        connections[c.id] = nil
        guard let peerID = peerByConnection.removeValue(forKey: c.id) else { return }
        connectionByPeer[peerID] = nil
        pingSentAt[c.id] = nil
        let name = room.peer(peerID)?.name ?? peerID
        if room.phase == .lobby || room.phase == .ended {
            vacate(peerID)
            rememberedLoadouts[peerID] = nil
            room.peers.removeAll { $0.id == peerID }
            note(L("\(name) が退出しました", "\(name) left"))
            broadcastRoom()
        } else {
            // 試合中: 座席は残し、ヒーローを AI に引き継ぐ。再接続で戻る
            droppedPeers.insert(peerID)
            if let i = room.peers.firstIndex(where: { $0.id == peerID }) { room.peers[i].loaded = true }
            if let seat = room.seatIndex(of: peerID) { pendingHandovers.append((seat, .bot)) }
            note(L("\(name) との接続が切れました（AI が引き継ぎます）", "\(name) disconnected (AI takes over)"))
            broadcastRoom()
        }
    }

    private func hostReceived(_ m: OnlineMessage, from c: OnlineConnection) {
        if case .hello(let hello) = m {
            handleHello(hello, from: c)
            return
        }
        guard let peerID = peerByConnection[c.id] else { return }
        switch m {
        case .takeSeat(let index):
            guard room.phase == .lobby else { return }
            apply(peer: peerID, takeSeat: index)
            broadcastRoom()
        case .setLoadout(let loadout):
            guard room.phase == .lobby else { return }
            apply(peer: peerID, loadout: loadout)
            broadcastRoom()
        case .setReady(let ready):
            guard room.phase == .lobby else { return }
            apply(peer: peerID, ready: ready)
            broadcastRoom()
        case .loaded:
            guard let i = room.peers.firstIndex(where: { $0.id == peerID }) else { return }
            room.peers[i].loaded = true
            if droppedPeers.remove(peerID) != nil {
                // 再接続: 現在の状態を渡し、ヒーローを人間に戻す
                sendSnapshot(to: peerID)
                if let seat = room.seatIndex(of: peerID) { pendingHandovers.append((seat, .human)) }
                note(L("\(room.peers[i].name) が再接続しました", "\(room.peers[i].name) reconnected"))
            }
        case .input(let commands):
            guard room.phase == .playing || room.phase == .loading else { return }
            guard let seat = room.seatIndex(of: peerID), heroIDBySeat.indices.contains(seat) else { return }
            let own = heroIDBySeat[seat]
            for cmd in commands where cmd.heroID == own {
                // 操作者の切り替えはホストだけが発行する
                if case .setController = cmd.command { continue }
                remoteInputs.append(cmd)
            }
        case .hash(let tick, let value):
            if let since = resyncedAt[peerID], tick <= since { return }
            guard let mine = hashHistory[tick] else { return }
            if mine != value {
                resyncCount += 1
                note(L("\(room.peer(peerID)?.name ?? "?") の状態がずれました（tick \(tick)）。再同期します",
                       "\(room.peer(peerID)?.name ?? "?") desynced at tick \(tick); resyncing"))
                sendSnapshot(to: peerID)
            }
        case .leave:
            c.close()
            hostLost(c)
        case .ping(let n):
            c.send(.pong(n))
        case .pong(let n):
            if let sent = pingSentAt[c.id]?.removeValue(forKey: n) {
                let rtt = ProcessInfo.processInfo.systemUptime - sent
                if let i = room.peers.firstIndex(where: { $0.id == peerID }) { room.peers[i].rtt = rtt }
            }
        case .hello, .welcome, .reject, .room, .startMatch, .frames, .snapshot:
            break
        }
    }

    private func handleHello(_ hello: OnlineHello, from c: OnlineConnection) {
        func reject(_ reason: String) {
            c.send(.reject(reason: reason))
            note(L("接続を拒否: \(reason)", "Rejected: \(reason)"))
            connections[c.id] = nil
            // 送り切ってから閉じる
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { c.close() }
        }
        guard hello.protocolVersion == OnlineProtocol.version else {
            reject(L("アプリの版数が違います（相手 \(hello.protocolVersion) / 自分 \(OnlineProtocol.version)）",
                     "Version mismatch (theirs \(hello.protocolVersion) / ours \(OnlineProtocol.version))"))
            return
        }
        guard hello.simVersion == MatchConfig.currentSimVersion else {
            reject(L("ゲームルールの版数が違います", "Rules version mismatch"))
            return
        }
        guard hello.peerID != localPeerID else {
            reject(L("自分自身には接続できません", "Cannot connect to yourself"))
            return
        }
        if let existing = connectionByPeer[hello.peerID], existing != c.id {
            // 同じ参加者の古い接続を置き換える
            if let old = connections[existing] {
                peerByConnection[existing] = nil
                connections[existing] = nil
                old.close()
            }
        }
        let returning = droppedPeers.contains(hello.peerID) || room.seat(of: hello.peerID) != nil
        if room.phase != .lobby && !returning {
            reject(L("試合中です", "A match is in progress"))
            return
        }
        guard room.peers.count < 10 || returning else {
            reject(L("満員です", "Room is full"))
            return
        }
        peerByConnection[c.id] = hello.peerID
        connectionByPeer[hello.peerID] = c.id
        let name = hello.name.isEmpty ? L("プレイヤー", "Player") : hello.name
        if let i = room.peers.firstIndex(where: { $0.id == hello.peerID }) {
            room.peers[i].name = name
            room.peers[i].loaded = false
        } else {
            room.peers.append(OnlinePeer(id: hello.peerID, name: name))
        }
        if let seat = room.seatIndex(of: hello.peerID) { room.seats[seat].name = name }
        c.send(.welcome(room: room))
        if room.phase != .lobby, let config = room.config {
            // 試合中の再接続: 読み込みへ進ませる（loaded が来たらスナップショットを送る）
            c.send(.startMatch(config: config))
        }
        note(L("\(name) が参加しました", "\(name) joined"))
        broadcastRoom()
    }

    // MARK: - ホスト: 部屋の操作

    private func vacate(_ peerID: OnlinePeerID) {
        for i in room.seats.indices where room.seats[i].peerID == peerID {
            room.seats[i] = OnlineSeat.empty(i)
        }
    }

    private func apply(peer: OnlinePeerID, takeSeat index: Int) {
        let name = room.peer(peer)?.name ?? ""
        let previous = room.seat(of: peer)
        if let previous { rememberedLoadouts[peer] = previous.loadout }
        vacate(peer)
        guard room.seats.indices.contains(index) else { return }   // -1 = 立つ
        guard room.seats[index].peerID == nil else {
            // 埋まっていたら元の席に戻す
            if let p = previous { room.seats[p.index] = p }
            return
        }
        var seat = OnlineSeat.empty(index)
        seat.peerID = peer
        seat.name = name
        seat.loadout = previous?.loadout ?? rememberedLoadouts[peer] ?? OnlineLoadout()
        // 立っている間に他の人が選んだヒーローは手放す
        if let hero = seat.loadout.heroID,
           room.seats.contains(where: { $0.peerID != nil && $0.peerID != peer && $0.loadout.heroID == hero }) {
            seat.loadout.heroID = nil
        }
        seat.ready = false
        room.seats[index] = seat
    }

    private func apply(peer: OnlinePeerID, loadout: OnlineLoadout) {
        guard let i = room.seatIndex(of: peer) else { return }
        var l = loadout
        if let hero = l.heroID {
            let taken = room.seats.contains { $0.peerID != nil && $0.peerID != peer && $0.loadout.heroID == hero }
            if taken { l.heroID = room.seats[i].loadout.heroID }
        }
        if l.heroID != room.seats[i].loadout.heroID { room.seats[i].ready = false }
        room.seats[i].loadout = l
    }

    private func apply(peer: OnlinePeerID, ready: Bool) {
        guard let i = room.seatIndex(of: peer) else { return }
        room.seats[i].ready = ready && room.seats[i].loadout.heroID != nil
    }

    private func send(to peerID: OnlinePeerID, _ m: OnlineMessage) {
        guard let id = connectionByPeer[peerID], let c = connections[id] else { return }
        c.send(m)
    }

    private func broadcast(_ m: OnlineMessage) {
        for (id, c) in connections where peerByConnection[id] != nil { c.send(m) }
    }

    private func broadcastRoom() {
        broadcast(.room(room))
    }

    private func sendSnapshot(to peerID: OnlinePeerID) {
        guard let controller else { return }
        flushFrames()
        resyncedAt[peerID] = controller.state.tick
        send(to: peerID, .snapshot(controller.state))
    }

    // MARK: - ロビー操作（UI から。ホストは自分で適用、クライアントはホストへ送る）

    func takeSeat(_ index: Int) {
        guard room.phase == .lobby else { return }
        switch role {
        case .host:
            apply(peer: localPeerID, takeSeat: index)
            broadcastRoom()
        case .client:
            connection?.send(.takeSeat(index))
        }
    }

    func setLoadout(_ loadout: OnlineLoadout) {
        guard room.phase == .lobby else { return }
        switch role {
        case .host:
            apply(peer: localPeerID, loadout: loadout)
            broadcastRoom()
        case .client:
            connection?.send(.setLoadout(loadout))
        }
    }

    func setReady(_ ready: Bool) {
        guard room.phase == .lobby else { return }
        switch role {
        case .host:
            apply(peer: localPeerID, ready: ready)
            broadcastRoom()
        case .client:
            connection?.send(.setReady(ready))
        }
    }

    func setBotDifficulty(_ d: Difficulty) {
        guard role == .host, room.phase == .lobby else { return }
        room.botDifficulty = d
        broadcastRoom()
    }

    /// ホスト: 試合を開始する（座席から構成を作り、全員を読み込みへ）。
    @discardableResult
    func startMatch(master: MasterData, seed: UInt64? = nil) -> Bool {
        guard role == .host, room.phase == .lobby, room.canStart else { return false }
        var rng = SplitMix64(seed: UInt64(max(0, now().timeIntervalSince1970 * 1000)))
        let config = room.makeConfig(seed: seed ?? rng.next(), master: master)
        room.config = config
        room.phase = .loading
        for i in room.peers.indices { room.peers[i].loaded = false }
        matchStartedAt = now()
        resetBattleBuffers()
        broadcast(.startMatch(config: config))
        broadcastRoom()
        status = .loading
        note(L("試合を開始します", "Starting the match"))
        onMatchStart?(config, room.seatIndex(of: localPeerID))
        return true
    }

    /// 戦闘が終わった（リザルトへ）。ホストは部屋をロビーに戻す。
    func matchEnded() {
        detach()
        guard role == .host else { return }
        room.phase = .lobby
        room.config = nil
        for i in room.seats.indices { room.seats[i].ready = false }
        for i in room.peers.indices { room.peers[i].loaded = false }
        droppedPeers.removeAll()
        status = .lobby
        broadcastRoom()
    }

    /// 部屋から出る（全接続を閉じる）。
    func leave() {
        guard !closed else { return }
        closed = true
        pingTimer?.invalidate()
        pingTimer = nil
        switch role {
        case .host:
            broadcast(.leave)
            listener?.stop()
            listener = nil
            let all = Array(connections.values)
            connections.removeAll()
            peerByConnection.removeAll()
            connectionByPeer.removeAll()
            // 送信を終えてから閉じる
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { for c in all { c.close() } }
        case .client:
            connection?.send(.leave)
            let c = connection
            connection = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { c?.close() }
        }
        status = .disconnected(L("退出しました", "Left the room"))
    }

    // MARK: - クライアント

    private func connect(_ c: OnlineConnection) {
        connection = c
        c.onMessage = { [weak self] m in self?.clientReceived(m) }
        c.onStateChange = { [weak self, weak c] st in
            guard let self, let c else { return }
            switch st {
            case .ready:
                c.send(.hello(OnlineHello(peerID: self.localPeerID, name: self.localName)))
            case .failed(let reason):
                self.disconnected(reason)
            case .closed:
                self.disconnected(L("ホストとの接続が切れました", "Lost connection to the host"))
            case .connecting:
                break
            }
        }
        c.start()
    }

    private func disconnected(_ reason: String) {
        guard !closed else { return }
        closed = true
        pingTimer?.invalidate()
        pingTimer = nil
        connection = nil
        status = .disconnected(reason)
        note(reason)
        onDisconnected?(reason)
    }

    private func clientReceived(_ m: OnlineMessage) {
        switch m {
        case .welcome(let room):
            self.room = room
            status = room.phase == .lobby ? .lobby : .loading
            note(L("\(room.name) に参加しました", "Joined \(room.name)"))
        case .reject(let reason):
            disconnected(reason)
        case .room(let room):
            // ホストが先にリザルトへ進むと部屋はロビーに戻るが、こちらはまだ最後の配信を消化中のことがある。
            // 配信バッファは試合開始（startMatch）でだけ捨てる
            self.room = room
            if room.phase == .lobby, status != .lobby, status != .connecting { status = .lobby }
        case .startMatch(let config):
            room.config = config
            room.phase = .loading
            status = .loading
            resetBattleBuffers()
            onMatchStart?(config, room.seatIndex(of: localPeerID))
        case .frames(let frames):
            if status == .loading { status = .playing }
            frameBuffer.append(contentsOf: frames)
        case .snapshot(let state):
            pendingSnapshot = state
            resyncCount += 1
            note(L("ホストの状態に合わせました（tick \(state.tick)）", "Resynced to host (tick \(state.tick))"))
        case .leave:
            disconnected(L("ホストが部屋を閉じました", "The host closed the room"))
        case .ping(let n):
            connection?.send(.pong(n))
        case .pong(let n):
            if let c = connection, let sent = pingSentAt[c.id]?.removeValue(forKey: n) {
                rtt = ProcessInfo.processInfo.systemUptime - sent
            }
        case .hello, .takeSeat, .setLoadout, .setReady, .loaded, .input, .hash:
            break
        }
    }

    // MARK: - 往復遅延

    private func startPing() {
        pingTimer?.invalidate()
        let t = Timer(timeInterval: Self.pingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.ping() }
        }
        RunLoop.main.add(t, forMode: .common)
        pingTimer = t
    }

    private func ping() {
        guard !closed else { return }
        pingSequence &+= 1
        let n = pingSequence
        let t = ProcessInfo.processInfo.systemUptime
        let targets: [OnlineConnection]
        switch role {
        case .host: targets = connections.compactMap { peerByConnection[$0.key] != nil ? $0.value : nil }
        case .client: targets = connection.map { [$0] } ?? []
        }
        for c in targets where c.state == .ready {
            var sent = pingSentAt[c.id] ?? [:]
            sent[n] = t
            if sent.count > 8 { sent = sent.filter { $0.key > n &- 8 } }
            pingSentAt[c.id] = sent
            c.send(.ping(n))
        }
    }

    // MARK: - OnlineBattleLink

    var canBegin: Bool {
        guard role == .host else { return true }
        let seated = room.peers.filter { room.seat(of: $0.id) != nil }
        if seated.allSatisfy(\.loaded) { return true }
        if let t = matchStartedAt, now().timeIntervalSince(t) > OnlineProtocol.loadTimeout { return true }
        return false
    }

    private func resetBattleBuffers() {
        remoteInputs.removeAll()
        hostCommands.removeAll()
        outgoingFrames.removeAll()
        hashHistory.removeAll()
        hashTicks.removeAll()
        resyncedAt.removeAll()
        pendingHandovers.removeAll()
        frameBuffer.removeAll()
        pendingSnapshot = nil
        outgoingInputs.removeAll()
        heroIDBySeat.removeAll()
    }

    func attach(controller: BattleController) {
        self.controller = controller
        let heroes = controller.state.heroIndices
        heroIDBySeat = heroes.map { controller.state.units[$0].id }
        switch role {
        case .host:
            room.phase = .playing
            if let i = room.peers.firstIndex(where: { $0.id == localPeerID }) { room.peers[i].loaded = true }
            status = .playing
            broadcastRoom()
        case .client:
            connection?.send(.loaded)
        }
    }

    func detach() {
        controller = nil
    }

    func takeRemoteInputs() -> [HeroCommand] {
        guard role == .host else { return [] }
        if !heroIDBySeat.isEmpty, !pendingHandovers.isEmpty {
            for h in pendingHandovers where heroIDBySeat.indices.contains(h.seat) {
                hostCommands.append(HeroCommand(heroID: heroIDBySeat[h.seat], command: .setController(h.controller)))
            }
            pendingHandovers.removeAll()
        }
        let out = hostCommands + remoteInputs
        hostCommands.removeAll(keepingCapacity: true)
        remoteInputs.removeAll(keepingCapacity: true)
        return out
    }

    func publish(frame: ReplayFrame, stateHash: UInt64?) {
        guard role == .host else { return }
        outgoingFrames.append(frame)
        if let stateHash {
            hashHistory[frame.tick] = stateHash
            hashTicks.append(frame.tick)
            while hashTicks.count > Self.hashHistoryLimit {
                hashHistory[hashTicks.removeFirst()] = nil
            }
        }
    }

    private func flushFrames() {
        guard !outgoingFrames.isEmpty else { return }
        broadcast(.frames(outgoingFrames))
        outgoingFrames.removeAll(keepingCapacity: true)
    }

    func frame(forTick tick: Int) -> ReplayFrame? {
        while let first = frameBuffer.first, first.tick < tick { frameBuffer.removeFirst() }
        guard let first = frameBuffer.first, first.tick == tick else { return nil }
        frameBuffer.removeFirst()
        return first
    }

    var bufferedFrames: Int { frameBuffer.count }

    func sendInput(_ command: HeroCommand) {
        guard role == .client else { return }
        inputSequence &+= 1
        var c = command
        c.sequence = inputSequence
        outgoingInputs.append(c)
    }

    func reportHash(tick: Int, value: UInt64) {
        guard role == .client else { return }
        connection?.send(.hash(tick: tick, value: value))
    }

    func takeSnapshot() -> SimState? {
        defer { pendingSnapshot = nil }
        if let s = pendingSnapshot {
            // スナップショット以前の tick は捨てる
            frameBuffer.removeAll { $0.tick <= s.tick }
        }
        return pendingSnapshot
    }

    func flush() {
        switch role {
        case .host:
            flushFrames()
        case .client:
            guard !outgoingInputs.isEmpty else { return }
            connection?.send(.input(outgoingInputs))
            outgoingInputs.removeAll(keepingCapacity: true)
        }
    }
}
