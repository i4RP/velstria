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
// 観戦（v2）:
// - 観戦席（role == .spectator）の参加者には、試合開始で spectateMatch を送る（試合中に入った・試合から抜けた参加者は
//   requestSpectate で求める）。観戦画面ができたら spectateLoaded が届き、そこから配信を始める。
// - 観戦者への配信はホスト側で遅延させる（OnlineSpectatorRelay）。ホストの描画ループは試合が終わると止まるので、
//   自前のタイマー（0.1 秒毎）でも出す。試合が終わったら遅延は要らないので残りを送り切り、matchFinished を送る。
// - 途中参加・ずれの再同期は「遅延済みの範囲で最新のキーフレーム」を送る（生の状態は観戦者へ送らない）。
//   スナップショットは間隔を空け（spectatorSnapshotInterval）、符号化はバックグラウンドで行う。
// - 観戦者の入力・loaded は受け付けない（loaded は選手だけ。観戦した試合には選手として戻れない）。
// - ホストが座らずに観戦席に入ると実況（キャスター）: 自分の端末で権威シミュレーションを回して遅延なしで見る。
//
// BattleController は OnlineBattleLink だけを見る（テストはループバック接続で同じ経路を通す）。

/// BattleController が戦闘中に使う窓口。
@MainActor
protocol OnlineBattleLink: AnyObject {
    var isHost: Bool { get }
    /// 相手と繋がっている（クライアント: ホストと。ホスト: 待ち受け中）。
    var isConnected: Bool { get }
    /// 試合が続いている（クライアント: ホストと繋がっていて、ホストが試合を中断していない）。
    var isMatchLive: Bool { get }
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
    // 観戦
    /// 観戦席への配信の遅延（tick。観戦席の端末で意味を持つ。0 = 遅延なし）。
    var spectatorDelayTicks: Int { get }
    /// この試合を観戦している人数（プレイヤーにも見せる）。
    var spectatorCount: Int { get }
    /// 観戦席: 試合が終わった tick（ホストが matchFinished を送ってきた。それまでの配信は全部届いている）。
    var spectatorFinalTick: Int? { get }
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
    /// 観戦の開始（AppModel が観戦席の BattleLaunch を作る）。ホストの実況もこれで始まる。
    @ObservationIgnored var onSpectateStart: ((MatchConfig) -> Void)?
    /// 切断の通知（トースト用）。
    @ObservationIgnored var onDisconnected: ((String) -> Void)?
    /// お知らせ（観戦を断られた等。トースト用）。
    @ObservationIgnored var onNotice: ((String) -> Void)?
    /// テスト用: 現在時刻の供給。
    @ObservationIgnored var now: () -> Date = { Date() }
    /// テスト用: 単調時刻の供給（往復遅延・生存確認）。
    @ObservationIgnored var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

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
    /// 試合の途中で抜けた参加者（部屋には残る。配信しない。loaded で戻る）。
    @ObservationIgnored private var abandonedPeers: Set<OnlinePeerID> = []
    /// ホストが進め始めた（以後は読み込み待ちで止まらない）。
    @ObservationIgnored private var hasBegun = false
    /// 接続毎の最後の受信時刻（生存確認）。
    @ObservationIgnored private var lastInbound: [UUID: TimeInterval] = [:]
    /// 参加者毎の最後のスナップショット（ずれの再同期の間隔を空ける）。
    @ObservationIgnored private var lastSnapshotAt: [OnlinePeerID: TimeInterval] = [:]

    // ホスト側: 観戦
    /// 観戦者への遅延配信の記録。
    @ObservationIgnored private var relay = OnlineSpectatorRelay()
    /// 観戦の配信先（spectateLoaded が届いた参加者）。
    @ObservationIgnored private var spectatorStreams: [OnlinePeerID: SpectatorStream] = [:]
    /// 観戦の案内（spectateMatch）を送り、spectateLoaded を待っている参加者。
    @ObservationIgnored private var invitedSpectators: Set<OnlinePeerID> = []
    /// この試合を観戦した参加者（霧の向こうを見たので、選手としては戻れない）。
    @ObservationIgnored private var spectatedThisMatch: Set<OnlinePeerID> = []
    /// この試合の観戦者への遅延（開始時に部屋の設定から固定する）。
    @ObservationIgnored private var matchSpectatorDelayTicks = 0
    @ObservationIgnored private var spectatorTimer: Timer?
    @ObservationIgnored private var lastSpectatorPump: TimeInterval = -.infinity
    /// 観戦者の基準スナップショットをバックグラウンドで符号化する（テストは false にして同期で送る）。
    @ObservationIgnored var encodesSpectatorSnapshotsInBackground = true
    /// 観戦の基準にするキーフレームの間隔（tick。テストで短くする）。
    @ObservationIgnored var spectatorKeyframeInterval = OnlineProtocol.spectatorKeyframeInterval

    /// 観戦者 1 人への配信の状態。
    private struct SpectatorStream {
        /// 送り終えた最後の tick。
        var cursor = 0
        /// 基準の状態を符号化中（その間は配信を止める）。値は基準の tick（その先の記録を捨てない）。
        var pendingBaseTick: Int?
        /// 符号化の世代（古い符号化の結果を捨てる）。
        var generation = 0
        /// 試合の終わり（matchFinished / matchAborted）を送った。
        var ended = false
    }

    // クライアント側
    @ObservationIgnored private var connection: OnlineConnection?
    /// 試合の配信を受け取る（startMatch から matchEnded / 離脱まで）。
    @ObservationIgnored private var acceptsFrames = false
    /// ホストが試合を中断した。
    @ObservationIgnored private var hostAborted = false
    @ObservationIgnored private var frameBuffer = OnlineFrameQueue()
    @ObservationIgnored private var pendingSnapshot: SimState?
    @ObservationIgnored private var outgoingInputs: [HeroCommand] = []
    @ObservationIgnored private var inputSequence: UInt32 = 0
    /// 名乗りで観戦席を希望する。
    @ObservationIgnored private var wantsSpectateOnJoin = false
    /// いまの戦闘は観戦（spectateMatch を受けた）。
    @ObservationIgnored private var watching = false
    /// 観戦の遅延（spectateMatch で届く）。
    @ObservationIgnored private var watchingDelayTicks = 0
    @ObservationIgnored private(set) var watchingFinalTick: Int?
    /// この試合を観戦した（選手としては戻れない。UI 用）。
    private(set) var watchedCurrentMatch = false
    /// この試合から抜けた（座席は保っている。UI の「試合に戻る」）。
    private(set) var abandonedCurrentMatch = false
    /// 直近のスナップショットの tick（テスト・デバッグ表示）。
    @ObservationIgnored private(set) var lastSnapshotTick: Int?

    // 共通
    @ObservationIgnored private weak var controller: BattleController?
    @ObservationIgnored private var heroIDBySeat: [EntityID] = []
    @ObservationIgnored private var pingTimer: Timer?
    @ObservationIgnored private var pingSequence: UInt32 = 0
    @ObservationIgnored private var pingSentAt: [UUID: [UInt32: TimeInterval]] = [:]
    @ObservationIgnored private var closed = false

    static let maxEvents = 30
    static let pingInterval: TimeInterval = 2
    /// ホストが保持する照合用ハッシュの数（hashInterval 毎に 1 つ。600 = 10 分遅れまで照合できる）。
    /// 観戦者は遅延の分だけ遅れて報告するので、最大の遅延より十分長く保つ。
    static let hashHistoryLimit = max(600, (OnlineProtocol.maxSpectatorDelayTicks + 2 * OnlineProtocol.spectatorKeyframeInterval)
                                          / OnlineProtocol.hashInterval * 2)

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

    /// 部屋に入る。接続は未開始のものを渡す（ready になったら名乗る）。wantsSpectate: 観戦席で入る（試合中なら途中から観戦）。
    static func join(peerID: OnlinePeerID, name: String, connection: OnlineConnection, wantsSpectate: Bool = false) -> OnlineSession {
        let s = OnlineSession(role: .client, peerID: peerID, name: name, room: OnlineRoom(name: "", hostPeerID: ""))
        s.wantsSpectateOnJoin = wantsSpectate
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

    /// 自分が見ている試合の遅延（観戦席: ホストが知らせた遅延。選手・ホスト（実況を含む）は遅延なしなので 0）。
    var spectatorDelayTicks: Int { role == .client && watching ? watchingDelayTicks : 0 }
    /// いま試合を観戦している人数（ホストの実況を含む）。
    var spectatorCount: Int { room.watchingCount }
    var spectatorFinalTick: Int? { role == .client && watching ? watchingFinalTick : nil }

    var isMatchLive: Bool {
        switch role {
        case .host: return !closed
        case .client: return isConnected && !hostAborted
        }
    }

    /// 自分の座席。
    var localSeat: OnlineSeat? { room.seat(of: localPeerID) }
    var localSeatIndex: Int? { room.seatIndex(of: localPeerID) }
    /// 接続している参加者数（自分を含む）。
    var connectedPeerCount: Int { room.peers.count }
    /// 自分の役割（観戦席か）。
    var localRole: OnlinePeerRole { room.peer(localPeerID)?.role ?? .player }
    /// いま観戦の戦闘を開いている（観戦の案内を受けてから抜けるまで）。
    var isWatchingMatch: Bool { role == .client && watching }
    /// 試合中に自分は選手として戦っていない（座っていない、または試合から抜けた）。ロビーの「試合中」の画面を出す。
    var isSittingOutMatch: Bool {
        role == .client && room.phase != .lobby
            && (localSeat == nil || abandonedCurrentMatch || room.peer(localPeerID)?.leftMatch == true)
    }
    /// 進行中の試合を観戦できる（座っていない・試合から抜けた参加者。観戦の戦闘を開いていない）。
    var canWatchMatch: Bool {
        isSittingOutMatch && isConnected && room.allowsSpectators && !watching && controller == nil
    }
    /// 抜けた試合に選手として戻れる（座席を保っていて、その試合を観戦していない）。
    var canRejoinMatch: Bool {
        isSittingOutMatch && isConnected && localSeat != nil && !watching && controller == nil
            && !watchedCurrentMatch && room.peer(localPeerID)?.watchedMatch != true
    }

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
        lastInbound[c.id] = nil
        guard let peerID = peerByConnection.removeValue(forKey: c.id) else { return }
        connectionByPeer[peerID] = nil
        pingSentAt[c.id] = nil
        let name = room.peer(peerID)?.name ?? peerID
        // 観戦の配信は止める（再接続したら求め直す）
        endSpectating(peerID)
        if room.phase == .lobby || room.phase == .ended || room.seat(of: peerID) == nil {
            // ロビー、または座っていない参加者（観戦者・待っている人）: 保つものが無いので部屋から外す
            vacate(peerID)
            rememberedLoadouts[peerID] = nil
            room.peers.removeAll { $0.id == peerID }
            droppedPeers.remove(peerID)
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
        lastInbound[c.id] = uptime()
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
            // 選手の戦闘画面の準備完了（観戦は spectateLoaded）。座っていない参加者には生の状態を渡さない
            guard room.phase != .lobby, let i = room.peers.firstIndex(where: { $0.id == peerID }),
                  room.seat(of: peerID) != nil else { return }
            if spectatedThisMatch.contains(peerID) {
                // 観戦した試合（霧の向こうを見た）には選手として戻れない: 開いた戦闘は中断で終わらせる
                send(to: peerID, .matchAborted(reason: L("観戦した試合には選手として戻れません", "You cannot rejoin a match you watched")))
                return
            }
            room.peers[i].loaded = true
            room.peers[i].leftMatch = false
            let returning = droppedPeers.remove(peerID) != nil
            // 抜けた試合に戻った（再接続・「試合に戻る」）: 配信を再開する
            let rejoining = abandonedPeers.remove(peerID) != nil
            // 途中参加（再接続・遅れての読み込み・古い接続が残ったままの再接続）: 既に進んでいれば現在の状態を渡す
            if let controller, controller.state.tick > 0 {
                sendSnapshot(to: peerID)
            }
            if returning || rejoining || controller.map({ $0.state.tick > 0 }) == true {
                // ヒーローを人間に戻す（元から人間なら何もしない）
                if let seat = room.seatIndex(of: peerID) { pendingHandovers.append((seat, .human)) }
            }
            if returning {
                note(L("\(room.peers[i].name) が再接続しました", "\(room.peers[i].name) reconnected"))
            } else if rejoining {
                note(L("\(room.peers[i].name) が試合に戻りました", "\(room.peers[i].name) rejoined the match"))
            }
            if rejoining { broadcastRoom() }
        case .abandonMatch:
            guard room.phase != .lobby, room.seat(of: peerID) != nil, abandonedPeers.insert(peerID).inserted else { return }
            if let i = room.peers.firstIndex(where: { $0.id == peerID }) {
                room.peers[i].loaded = true
                room.peers[i].leftMatch = true
            }
            broadcastRoom()
            if let seat = room.seatIndex(of: peerID) { pendingHandovers.append((seat, .bot)) }
            note(L("\(room.peer(peerID)?.name ?? "?") が試合から抜けました（AI が引き継ぎます）",
                   "\(room.peer(peerID)?.name ?? "?") left the match (AI takes over)"))
        case .input(let commands):
            guard room.phase == .playing || room.phase == .loading else { return }
            // 抜けた参加者（AI が操作中）・観戦者の入力は捨てる
            guard !abandonedPeers.contains(peerID), spectatorStreams[peerID] == nil else { return }
            guard let seat = room.seatIndex(of: peerID), heroIDBySeat.indices.contains(seat) else { return }
            let own = heroIDBySeat[seat]
            for cmd in commands where cmd.heroID == own {
                // 操作者の切り替えはホストだけが発行する
                if case .setController = cmd.command { continue }
                remoteInputs.append(cmd)
            }
        case .hash(let tick, let value):
            if let since = resyncedAt[peerID], tick <= since { return }
            guard let mine = hashHistory[tick], mine != value else { return }
            let name = room.peer(peerID)?.name ?? "?"
            if spectatorStreams[peerID] != nil {
                // 観戦者: 遅延済みの範囲のキーフレームから送り直す（生の状態は渡さない）
                guard canSendSnapshot(to: peerID, interval: OnlineProtocol.spectatorSnapshotInterval) else { return }
                resyncCount += 1
                note(L("観戦者 \(name) の状態がずれました（tick \(tick)）。再同期します",
                       "Spectator \(name) desynced at tick \(tick); resyncing"))
                sendSpectatorBase(to: peerID)
                return
            }
            // 選手だけ（座っていて抜けていない）。それ以外には状態を渡さない
            guard room.seat(of: peerID) != nil, !abandonedPeers.contains(peerID),
                  canSendSnapshot(to: peerID, interval: OnlineProtocol.playerSnapshotInterval) else { return }
            resyncCount += 1
            note(L("\(name) の状態がずれました（tick \(tick)）。再同期します", "\(name) desynced at tick \(tick); resyncing"))
            sendSnapshot(to: peerID)
        case .leave:
            c.close()
            hostLost(c)
        case .ping(let n):
            c.send(.pong(n))
        case .pong(let n):
            if let sent = pingSentAt[c.id]?.removeValue(forKey: n) {
                let rtt = uptime() - sent
                if let i = room.peers.firstIndex(where: { $0.id == peerID }) { room.peers[i].rtt = rtt }
            }
        case .setSpectator(let on):
            guard room.phase == .lobby else { return }
            if let reason = apply(peer: peerID, spectator: on) { send(to: peerID, .spectateDenied(reason: reason)) }
            broadcastRoom()
        case .requestSpectate:
            if let reason = handleSpectateRequest(from: peerID) { send(to: peerID, .spectateDenied(reason: reason)) }
        case .spectateLoaded:
            guard invitedSpectators.contains(peerID) else { return }
            guard room.phase != .lobby else {
                // 案内の後に試合が終わった: 開いた観戦画面を終わらせる
                invitedSpectators.remove(peerID)
                send(to: peerID, .matchAborted(reason: L("試合は終了しました", "The match has ended")))
                return
            }
            startSpectatorStream(peerID)
        case .stopSpectating:
            endSpectating(peerID)
        case .hello, .welcome, .reject, .room, .startMatch, .frames, .snapshot, .matchAborted,
             .spectateMatch, .matchFinished, .spectateDenied:
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
                lastInbound[existing] = nil
                pingSentAt[existing] = nil
                old.close()
            }
            // 古い接続への観戦の配信は止める（観戦し直すなら案内からやり直す）
            endSpectating(hello.peerID)
        }
        let returning = droppedPeers.contains(hello.peerID) || room.seat(of: hello.peerID) != nil
        let known = room.peer(hello.peerID) != nil
        // 観戦席で入る: 観戦を許可している部屋だけ（許可していなければ選手として待つ）
        let asSpectator = !returning && hello.wantsSpectate == true && room.allowsSpectators
        if !returning && !known {
            // 新しい参加者: 選手と観戦席で別々の上限（試合中でも入れる。選手は試合が終わるまで待つか観戦する）
            if asSpectator {
                guard spectatorSlotsUsed(excluding: hello.peerID) < OnlineProtocol.maxSpectators else {
                    reject(L("観戦席が満員です", "No spectator slots left"))
                    return
                }
            } else {
                guard room.players.count < OnlineProtocol.maxPlayers else {
                    reject(L("満員です", "Room is full"))
                    return
                }
            }
        }
        peerByConnection[c.id] = hello.peerID
        connectionByPeer[hello.peerID] = c.id
        let name = hello.name.isEmpty ? L("プレイヤー", "Player") : hello.name
        if let i = room.peers.firstIndex(where: { $0.id == hello.peerID }) {
            room.peers[i].name = name
            room.peers[i].loaded = false
            room.peers[i].isWatching = false
            if asSpectator && room.seat(of: hello.peerID) == nil { room.peers[i].role = .spectator }
        } else {
            room.peers.append(OnlinePeer(id: hello.peerID, name: name, role: asSpectator ? .spectator : .player))
        }
        if let seat = room.seatIndex(of: hello.peerID) { room.seats[seat].name = name }
        c.send(.welcome(room: room))
        if room.phase != .lobby, let config = room.config {
            if returning && !spectatedThisMatch.contains(hello.peerID) && !abandonedPeers.contains(hello.peerID) {
                // 試合中の再接続: 読み込みへ進ませる（loaded が来たらスナップショットを送る）。
                // 自分で抜けた選手は引き戻さない（部屋の「試合に戻る」「観戦する」から選ぶ）
                c.send(.startMatch(config: config))
            } else if room.peer(hello.peerID)?.role == .spectator, room.allowsSpectators {
                // 観戦席の途中参加: 遅延済みの範囲から観戦を始める
                invite(hello.peerID, config: config)
            }
        }
        note(asSpectator ? L("\(name) が観戦席に入りました", "\(name) joined as a spectator") : L("\(name) が参加しました", "\(name) joined"))
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
        // 観戦席から座る: 選手に戻る（選手の上限は座席数と同じなので座れれば必ず収まる）
        if let i = room.peers.firstIndex(where: { $0.id == peer }) { room.peers[i].role = .player }
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

    /// 観戦席に移る / 選手に戻る（ロビー）。断る時は理由を返す。ホスト自身の観戦席 = 実況（上限に数えない）。
    private func apply(peer: OnlinePeerID, spectator: Bool) -> String? {
        guard let i = room.peers.firstIndex(where: { $0.id == peer }) else { return nil }
        guard room.peers[i].role != (spectator ? .spectator : .player) else { return nil }
        if spectator {
            if peer != room.hostPeerID {
                guard room.allowsSpectators else { return L("この部屋は観戦できません", "Spectating is disabled in this room") }
                guard spectatorSlotsUsed(excluding: peer) < OnlineProtocol.maxSpectators else {
                    return L("観戦席が満員です", "No spectator slots left")
                }
            }
            if let seat = room.seat(of: peer) { rememberedLoadouts[peer] = seat.loadout }
            vacate(peer)
            room.peers[i].role = .spectator
        } else {
            guard room.players.count < OnlineProtocol.maxPlayers else { return L("選手の枠が満員です", "No player slots left") }
            room.peers[i].role = .player
        }
        return nil
    }

    /// 観戦席の使用数（観戦席の役割・観戦中・案内中。ホストの実況は数えない）。
    private func spectatorSlotsUsed(excluding id: OnlinePeerID?) -> Int {
        room.peers.filter { p in
            p.id != room.hostPeerID && p.id != id
                && (p.role == .spectator || p.isWatching || invitedSpectators.contains(p.id))
        }.count
    }

    private func send(to peerID: OnlinePeerID, _ m: OnlineMessage) {
        guard let c = connection(of: peerID) else { return }
        c.send(m)
    }

    private func connection(of peerID: OnlinePeerID) -> OnlineConnection? {
        guard let id = connectionByPeer[peerID] else { return nil }
        return connections[id]
    }

    /// 全員へ（名乗りを済ませた接続）。符号化は 1 回。
    private func broadcast(_ m: OnlineMessage) {
        guard let data = try? OnlineFramer.encode(m) else { return }
        for (id, c) in connections where peerByConnection[id] != nil { c.send(encoded: data) }
    }

    private func broadcastRoom() {
        broadcast(.room(room))
        refreshAdvertisement()
    }

    /// Bonjour の広告（進行状況・観戦の可否・人数）を部屋に合わせる。
    private func refreshAdvertisement() {
        listener?.updateAdvertisement(OnlineAdvertisement.entries(for: room))
    }

    /// ずれによるスナップショットを送ってよいか（間隔を空ける）。送るなら時刻を記録する。
    private func canSendSnapshot(to peerID: OnlinePeerID, interval: TimeInterval) -> Bool {
        let t = uptime()
        if let last = lastSnapshotAt[peerID], t - last < interval { return false }
        lastSnapshotAt[peerID] = t
        return true
    }

    /// 選手へ現在の状態を送る（観戦者には送らない: 遅延のない状態になる）。
    private func sendSnapshot(to peerID: OnlinePeerID) {
        guard let controller, room.seat(of: peerID) != nil, spectatorStreams[peerID] == nil else { return }
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

    // MARK: 観戦（ロビー・試合中の操作。UI から）

    /// ロビーで観戦席に移る（true。座席は立つ）/ 選手に戻る（false）。ホストの観戦席 = 実況（座らずに試合を回す）。
    func setSpectator(_ on: Bool) {
        guard room.phase == .lobby else { return }
        switch role {
        case .host:
            if let reason = apply(peer: localPeerID, spectator: on) { onNotice?(reason) }
            broadcastRoom()
        case .client:
            connection?.send(.setSpectator(on))
        }
    }

    /// ホスト: 観戦を許可する（ロビーのみ）。許可しなければ観戦席の参加者は選手に戻る。
    func setAllowsSpectators(_ on: Bool) {
        guard role == .host, room.phase == .lobby, room.allowsSpectators != on else { return }
        room.allowsSpectators = on
        if !on {
            for i in room.peers.indices where room.peers[i].role == .spectator && room.peers[i].id != room.hostPeerID {
                room.peers[i].role = .player
            }
        }
        broadcastRoom()
    }

    /// ホスト: 観戦者への遅延（秒。spectatorDelayOptions のいずれか。ロビーのみ）。
    func setSpectatorDelay(seconds: Int) {
        guard OnlineProtocol.spectatorDelayOptions.contains(seconds) else { return }
        setSpectatorDelay(ticks: OnlineProtocol.ticks(seconds: seconds))
    }

    /// 遅延を tick で設定する（テスト用に選択肢以外も受け付ける。上限で丸める）。
    func setSpectatorDelay(ticks: Int) {
        guard role == .host, room.phase == .lobby else { return }
        room.spectatorDelayTicks = min(max(0, ticks), OnlineProtocol.maxSpectatorDelayTicks)
        broadcastRoom()
    }

    /// クライアント: 進行中の試合を観戦する（座っていない・試合から抜けた参加者）。
    func requestSpectate() {
        guard canWatchMatch else { return }
        connection?.send(.requestSpectate)
    }

    /// クライアント: 抜けた試合に選手として戻る（loaded を送ると、ホストは状態を渡して操作を人間に戻す）。
    func rejoinMatch() {
        guard canRejoinMatch, let config = room.config, let seat = localSeatIndex else { return }
        resetBattleBuffers()
        acceptsFrames = true
        abandonedCurrentMatch = false
        status = .loading
        onMatchStart?(config, seat)
    }

    /// クライアント: 観戦の案内を受けたが開けない（別の戦闘中など）。ホストに断る。
    func declineSpectate() {
        guard role == .client, watching else { return }
        watching = false
        watchingFinalTick = nil
        acceptsFrames = false
        frameBuffer.removeAll()
        connection?.send(.stopSpectating)
    }

    /// ホスト: 試合を開始する（座席から構成を作り、全員を読み込みへ）。観戦席には観戦の案内を送る。
    /// ホストが観戦席（実況）なら、ホストは観戦の画面で権威シミュレーションを回す（onSpectateStart）。
    @discardableResult
    func startMatch(master: MasterData, seed: UInt64? = nil) -> Bool {
        guard role == .host, room.phase == .lobby, room.canStart else { return false }
        var rng = SplitMix64(seed: UInt64(max(0, now().timeIntervalSince1970 * 1000)))
        let config = room.makeConfig(seed: seed ?? rng.next(), master: master)
        room.config = config
        room.phase = .loading
        for i in room.peers.indices {
            room.peers[i].loaded = false
            room.peers[i].isWatching = false
            room.peers[i].leftMatch = false
            room.peers[i].watchedMatch = false
        }
        matchStartedAt = now()
        resetBattleBuffers()
        matchSpectatorDelayTicks = room.spectatorDelayTicks
        relay.reset(active: room.allowsSpectators, delayTicks: matchSpectatorDelayTicks, keyframeInterval: spectatorKeyframeInterval)
        broadcastToPlayers(.startMatch(config: config))
        if room.allowsSpectators {
            for p in room.spectators where connectionByPeer[p.id] != nil { invite(p.id, config: config) }
        }
        broadcastRoom()
        status = .loading
        note(L("試合を開始します", "Starting the match"))
        if room.hostIsCaster {
            onSpectateStart?(config)
        } else {
            onMatchStart?(config, room.seatIndex(of: localPeerID))
        }
        return true
    }

    /// 戦闘が終わった（リザルトへ）。aborted = 自分が途中で抜けた / 中断した。spectating = 観戦の戦闘だった。
    /// ホストは参加者に中断を伝えて部屋をロビーに戻す（観戦者には遅延分の残りを送り切る）。
    /// クライアントは途中なら「抜けた」とホストに伝える。観戦者は観戦をやめたと伝える。
    func matchEnded(aborted: Bool = false, spectating: Bool = false) {
        detach()
        switch role {
        case .host:
            let live = room.phase != .lobby
            if live {
                // 観戦者へ残りを送り切る（試合はもう動かないので遅延は要らない）
                finishSpectatorStreams()
            }
            if aborted && live {
                broadcastToPlayers(.matchAborted(reason: L("ホストが試合を終了しました", "The host ended the match")))
            }
            stopSpectatorTimer()
            spectatorStreams.removeAll()
            invitedSpectators.removeAll()
            spectatedThisMatch.removeAll()
            relay.reset(active: false, delayTicks: 0, keyframeInterval: spectatorKeyframeInterval)
            room.phase = .lobby
            room.config = nil
            // 試合中に落ちて戻らなかった参加者は席を空ける（準備完了できず部屋が始められなくなる）。
            // 再接続していれば（loaded を送らずにいても）部屋に残す
            for peerID in droppedPeers where connectionByPeer[peerID] == nil {
                vacate(peerID)
                rememberedLoadouts[peerID] = nil
                room.peers.removeAll { $0.id == peerID }
            }
            droppedPeers.removeAll()
            abandonedPeers.removeAll()
            for i in room.seats.indices { room.seats[i].ready = false }
            for i in room.peers.indices {
                room.peers[i].loaded = false
                room.peers[i].isWatching = false
                room.peers[i].leftMatch = false
                room.peers[i].watchedMatch = false
            }
            status = .lobby
            broadcastRoom()
        case .client:
            let wasWatching = watching || spectating
            acceptsFrames = false
            frameBuffer.removeAll()
            pendingSnapshot = nil
            if wasWatching {
                watching = false
                watchingFinalTick = nil
                connection?.send(.stopSpectating)
            } else if aborted && room.phase != .lobby && !hostAborted {
                connection?.send(.abandonMatch)
                abandonedCurrentMatch = true
            }
        }
    }

    /// 試合を始められない状態（別の戦闘中など）で開始の合図が来た: 自分の枠は AI に任せる（後で「試合に戻る」で戻れる）。
    func declineMatch() {
        guard role == .client else { return }
        acceptsFrames = false
        frameBuffer.removeAll()
        abandonedCurrentMatch = true
        connection?.send(.abandonMatch)
    }

    /// 部屋から出る（全接続を閉じる）。
    func leave() {
        guard !closed else { return }
        closed = true
        pingTimer?.invalidate()
        pingTimer = nil
        stopSpectatorTimer()
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
                c.send(.hello(OnlineHello(peerID: self.localPeerID, name: self.localName,
                                          wantsSpectate: self.wantsSpectateOnJoin ? true : nil)))
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
        let c = connection
        connection = nil
        c?.close()
        status = .disconnected(reason)
        note(reason)
        onDisconnected?(reason)
    }

    private func clientReceived(_ m: OnlineMessage) {
        if let c = connection { lastInbound[c.id] = uptime() }
        switch m {
        case .welcome(let room):
            self.room = room
            // 試合中に入った時も、ホストが開始（再接続の選手）か観戦の案内を送ってくるまでは部屋で待つ
            status = .lobby
            note(L("\(room.name) に参加しました", "Joined \(room.name)"))
        case .reject(let reason):
            disconnected(reason)
        case .room(let room):
            // ホストが先にリザルトへ進むと部屋はロビーに戻るが、こちらはまだ最後の配信を消化中のことがある。
            // 配信バッファは試合開始（startMatch / spectateMatch）でだけ捨てる
            self.room = room
            if room.phase == .lobby {
                if status != .lobby, status != .connecting { status = .lobby }
                watchedCurrentMatch = false
                abandonedCurrentMatch = false
            }
        case .startMatch(let config):
            room.config = config
            room.phase = .loading
            status = .loading
            resetBattleBuffers()
            acceptsFrames = true
            hostAborted = false
            watchedCurrentMatch = false
            abandonedCurrentMatch = false
            onMatchStart?(config, room.seatIndex(of: localPeerID))
        case .spectateMatch(let config, let delayTicks, _):
            guard controller == nil else {
                // 前の試合（の遅延分の残り）をまだ見ている: いまの配信は捨てず、新しい観戦は断る
                connection?.send(.stopSpectating)
                note(L("次の試合が始まりました（観戦中のため開けませんでした）", "The next match started while you were still watching"))
                return
            }
            room.config = config
            status = .loading
            resetBattleBuffers()
            acceptsFrames = true
            hostAborted = false
            watching = true
            watchingDelayTicks = max(0, delayTicks)
            onSpectateStart?(config)
        case .frames(let frames):
            guard acceptsFrames else { return }
            if status == .loading { status = .playing }
            frameBuffer.append(frames)
        case .matchAborted(let reason):
            guard acceptsFrames else { return }
            hostAborted = true
            note(reason)
        case .matchFinished(let finalTick):
            guard acceptsFrames, watching else { return }
            watchingFinalTick = finalTick
        case .spectateDenied(let reason):
            note(reason)
            onNotice?(reason)
        case .snapshot(let state):
            guard acceptsFrames else { return }
            // これより前に届いた配信はスナップショット以前（選手）か、送り直し前の基準のもの（観戦者）なので捨てる。
            // 後に届く配信はスナップショットの続き
            frameBuffer.removeAll(resettingTo: state.tick)
            pendingSnapshot = state
            lastSnapshotTick = state.tick
            resyncCount += 1
            note(L("ホストの状態に合わせました（tick \(state.tick)）", "Resynced to host (tick \(state.tick))"))
        case .leave:
            disconnected(L("ホストが部屋を閉じました", "The host closed the room"))
        case .ping(let n):
            connection?.send(.pong(n))
        case .pong(let n):
            if let c = connection, let sent = pingSentAt[c.id]?.removeValue(forKey: n) {
                rtt = uptime() - sent
            }
        case .hello, .takeSeat, .setLoadout, .setReady, .loaded, .input, .hash, .abandonMatch,
             .setSpectator, .requestSpectate, .spectateLoaded, .stopSpectating:
            break
        }
    }

    // MARK: - 往復遅延・生存確認

    private func startPing() {
        pingTimer?.invalidate()
        let t = Timer(timeInterval: Self.pingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.ping() }
        }
        RunLoop.main.add(t, forMode: .common)
        pingTimer = t
    }

    /// 2 秒毎: ping を送り、長く何も届いていない相手は切断扱いにする（テストから直接呼べる）。
    func ping() {
        guard !closed else { return }
        pingSequence &+= 1
        let n = pingSequence
        let t = uptime()
        let targets: [OnlineConnection]
        switch role {
        case .host: targets = connections.compactMap { peerByConnection[$0.key] != nil ? $0.value : nil }
        case .client: targets = connection.map { [$0] } ?? []
        }
        for c in targets where c.state == .ready {
            if let last = lastInbound[c.id], t - last > OnlineProtocol.livenessTimeout {
                switch role {
                case .host:
                    note(L("\(room.peer(peerByConnection[c.id] ?? "")?.name ?? "?") から応答がありません。切断します",
                           "No response from \(room.peer(peerByConnection[c.id] ?? "")?.name ?? "?"); disconnecting"))
                    c.close()
                    hostLost(c)
                case .client:
                    disconnected(L("ホストから応答がありません", "The host stopped responding"))
                }
                continue
            }
            if lastInbound[c.id] == nil { lastInbound[c.id] = t }
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
        if hasBegun { return true }
        let seated = room.peers.filter { room.seat(of: $0.id) != nil }
        if seated.allSatisfy(\.loaded) || (matchStartedAt.map { now().timeIntervalSince($0) > OnlineProtocol.loadTimeout } ?? false) {
            // 一度進め始めたら、以後の再接続・遅れた読み込みでは止まらない（遅れた側にはスナップショットを渡す）
            hasBegun = true
            return true
        }
        return false
    }

    private func resetBattleBuffers() {
        remoteInputs.removeAll()
        hostCommands.removeAll()
        outgoingFrames.removeAll()
        hashHistory.removeAll()
        hashTicks.removeAll()
        resyncedAt.removeAll()
        lastSnapshotAt.removeAll()
        pendingHandovers.removeAll()
        abandonedPeers.removeAll()
        hasBegun = false
        hostAborted = false
        frameBuffer.removeAll()
        pendingSnapshot = nil
        outgoingInputs.removeAll()
        heroIDBySeat.removeAll()
        watching = false
        watchingFinalTick = nil
        lastSnapshotTick = nil
        if role == .host {
            spectatorStreams.removeAll()
            invitedSpectators.removeAll()
            spectatedThisMatch.removeAll()
        }
    }

    func attach(controller: BattleController) {
        self.controller = controller
        let heroes = controller.state.heroIndices
        heroIDBySeat = heroes.map { controller.state.units[$0].id }
        switch role {
        case .host:
            room.phase = .playing
            if let i = room.peers.firstIndex(where: { $0.id == localPeerID }) {
                room.peers[i].loaded = true
                // ホストの実況（座らずに観戦の画面で回す）も観戦者として数える（選手に見せる人数）
                room.peers[i].isWatching = controller.launch.onlineSpectator
            }
            status = .playing
            if relay.isActive { startSpectatorTimer() }
            broadcastRoom()
        case .client:
            // 観戦の戦闘を開いた: この試合には選手として戻れない（案内を断った時は数えない）
            if controller.launch.onlineSpectator { watchedCurrentMatch = true }
            connection?.send(controller.launch.onlineSpectator ? .spectateLoaded : .loaded)
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
            if hashTicks.count > Self.hashHistoryLimit + 64 {
                // 古いものからまとめて捨てる（毎 tick removeFirst しない）
                let drop = hashTicks.count - Self.hashHistoryLimit
                for t in hashTicks[0..<drop] { hashHistory[t] = nil }
                hashTicks.removeFirst(drop)
            }
        }
        // 観戦者への遅延配信の記録（キーフレームを取る tick だけ状態を写す）
        if relay.isActive {
            relay.record(frame) { controller?.state }
        }
    }

    /// 試合をプレイしている（座っていて抜けていない、観戦していない）参加者だけに配る。符号化は 1 回。
    private func broadcastToPlayers(_ m: OnlineMessage) {
        var data: Data?
        for (id, c) in connections {
            guard let peerID = peerByConnection[id], room.seat(of: peerID) != nil, !abandonedPeers.contains(peerID),
                  spectatorStreams[peerID] == nil else { continue }
            if data == nil { data = try? OnlineFramer.encode(m) }
            guard let data else { return }
            c.send(encoded: data)
        }
    }

    private func flushFrames() {
        guard !outgoingFrames.isEmpty else { return }
        broadcastToPlayers(.frames(outgoingFrames))
        outgoingFrames.removeAll(keepingCapacity: true)
    }

    func frame(forTick tick: Int) -> ReplayFrame? {
        frameBuffer.pop(tick: tick)
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
            frameBuffer.drop(through: s.tick)
        }
        return pendingSnapshot
    }

    func flush() {
        switch role {
        case .host:
            flushFrames()
            // 観戦者へはまとめて出す（遅延しているので描画フレーム毎に送らなくてよい）
            if relay.isActive, uptime() - lastSpectatorPump >= OnlineProtocol.spectatorReleaseInterval {
                pumpSpectators()
            }
        case .client:
            guard !outgoingInputs.isEmpty else { return }
            connection?.send(.input(outgoingInputs))
            outgoingInputs.removeAll(keepingCapacity: true)
        }
    }

    // MARK: - ホスト: 観戦の配信

    /// 観戦の案内を送る（観戦画面ができたら spectateLoaded が返る）。
    private func invite(_ peerID: OnlinePeerID, config: MatchConfig) {
        invitedSpectators.insert(peerID)
        send(to: peerID, .spectateMatch(config: config, delayTicks: matchSpectatorDelayTicks, baseTick: relay.baseTick))
    }

    /// 試合中の観戦の求め。断る時は理由を返す。
    private func handleSpectateRequest(from peerID: OnlinePeerID) -> String? {
        guard room.phase != .lobby, let config = room.config else {
            return L("試合はまだ始まっていません", "No match is in progress")
        }
        guard room.allowsSpectators else { return L("この部屋は観戦できません", "Spectating is disabled in this room") }
        if room.seat(of: peerID) != nil && !abandonedPeers.contains(peerID) {
            return L("試合に参加中です", "You are playing in this match")
        }
        guard spectatorStreams[peerID] == nil, !invitedSpectators.contains(peerID) else { return nil }
        guard spectatorSlotsUsed(excluding: peerID) < OnlineProtocol.maxSpectators else {
            return L("観戦席が満員です", "No spectator slots left")
        }
        // 座っていない参加者は観戦席に移る（次の試合も観戦する）。抜けた選手は座席を保つ
        if room.seat(of: peerID) == nil, let i = room.peers.firstIndex(where: { $0.id == peerID }) {
            room.peers[i].role = .spectator
        }
        invite(peerID, config: config)
        broadcastRoom()
        return nil
    }

    /// 観戦画面ができた: 配信を始める（遅延済みの範囲の基準 + 記録）。
    private func startSpectatorStream(_ peerID: OnlinePeerID) {
        invitedSpectators.remove(peerID)
        spectatedThisMatch.insert(peerID)
        spectatorStreams[peerID] = SpectatorStream()
        if let i = room.peers.firstIndex(where: { $0.id == peerID }) {
            room.peers[i].isWatching = true
            room.peers[i].watchedMatch = true
        }
        note(L("\(room.peer(peerID)?.name ?? "?") が観戦を始めました", "\(room.peer(peerID)?.name ?? "?") started watching"))
        lastSnapshotAt[peerID] = uptime()
        sendSpectatorBase(to: peerID)
        broadcastRoom()
    }

    /// 観戦者へ基準を送り、その先の記録を続けて送る。基準は公開済みの範囲で最新のキーフレーム（無ければ tick 0 = 状態を送らない）。
    /// 状態は数百 KB あるので、既定ではバックグラウンドで符号化する（その間この観戦者への配信は止める）。
    private func sendSpectatorBase(to peerID: OnlinePeerID) {
        guard var stream = spectatorStreams[peerID] else { return }
        // 再同期の前に送った配信・報告は捨てる（公開済みの範囲までは基準からやり直すので照合しない）
        resyncedAt[peerID] = relay.releasedTick
        stream.generation &+= 1
        let generation = stream.generation
        guard let base = relay.baseState else {
            stream.pendingBaseTick = nil
            stream.cursor = 0
            spectatorStreams[peerID] = stream
            flushSpectatorStream(peerID)
            return
        }
        stream.pendingBaseTick = base.tick
        spectatorStreams[peerID] = stream
        let deliver: (Data?) -> Void = { [weak self] data in
            guard let self, var stream = self.spectatorStreams[peerID], stream.generation == generation else { return }
            guard let data else {
                // 符号化できない（起こらないはず）: 配信をやめる
                self.endSpectating(peerID)
                self.send(to: peerID, .matchAborted(reason: L("観戦の準備に失敗しました", "Could not start spectating")))
                return
            }
            self.connection(of: peerID)?.send(encoded: data)
            stream.pendingBaseTick = nil
            stream.cursor = base.tick
            self.spectatorStreams[peerID] = stream
            self.flushSpectatorStream(peerID)
        }
        if encodesSpectatorSnapshotsInBackground {
            Task { @MainActor in
                let data = await Task.detached(priority: .utility) { try? OnlineFramer.encodeDetached(.snapshot(base)) }.value
                deliver(data)
            }
        } else {
            deliver(try? OnlineFramer.encode(.snapshot(base)))
        }
    }

    /// 観戦の配信を止める（観戦をやめた・切断・案内を断った）。観戦中の印が外れたら部屋を配り直す。
    private func endSpectating(_ peerID: OnlinePeerID) {
        invitedSpectators.remove(peerID)
        let streamed = spectatorStreams.removeValue(forKey: peerID) != nil
        if let i = room.peers.firstIndex(where: { $0.id == peerID }), room.peers[i].isWatching, peerID != localPeerID {
            room.peers[i].isWatching = false
            broadcastRoom()
        }
        if streamed {
            note(L("\(room.peer(peerID)?.name ?? "?") が観戦をやめました", "\(room.peer(peerID)?.name ?? "?") stopped watching"))
        }
    }

    /// 遅延を過ぎた分を観戦者へ出す（描画ループの flush とタイマーから。テストは直接呼ぶ）。
    /// ホストの試合が終わっていたら残りをすべて出し、試合の終わりを知らせる。
    func pumpSpectators() {
        guard role == .host, relay.isActive else { return }
        lastSpectatorPump = uptime()
        if relay.finalTick == nil, let controller, controller.state.phase == .ended {
            relay.finish()
        }
        relay.release()
        flushAllSpectatorStreams()
        relay.trim(pinnedTick: spectatorStreams.values.compactMap(\.pendingBaseTick).min())
    }

    /// 全観戦者へ未送信の範囲を送る（同じ範囲の観戦者には 1 回の符号化で）。
    private func flushAllSpectatorStreams() {
        var byCursor: [Int: [OnlinePeerID]] = [:]
        for (peerID, stream) in spectatorStreams where stream.pendingBaseTick == nil && !stream.ended {
            byCursor[stream.cursor, default: []].append(peerID)
        }
        for (cursor, peers) in byCursor {
            sendSpectatorFrames(after: cursor, to: peers)
        }
    }

    private func flushSpectatorStream(_ peerID: OnlinePeerID) {
        guard let stream = spectatorStreams[peerID], stream.pendingBaseTick == nil, !stream.ended else { return }
        sendSpectatorFrames(after: stream.cursor, to: [peerID])
    }

    /// (cursor, releasedTick] の記録を送る。試合が終わって送り切ったら終わりも知らせる。
    private func sendSpectatorFrames(after cursor: Int, to peers: [OnlinePeerID]) {
        let released = relay.releasedTick
        if released > cursor {
            guard let frames = relay.frames(after: cursor, through: released) else {
                // 記録がもう無い（起こらないはず）: 基準から送り直す
                for p in peers { sendSpectatorBase(to: p) }
                return
            }
            if let data = try? OnlineFramer.encode(.frames(frames)) {
                for p in peers { connection(of: p)?.send(encoded: data) }
            }
            for p in peers { spectatorStreams[p]?.cursor = released }
        }
        if let final = relay.finalTick, released >= final {
            // 中断でも matchFinished: 観戦者は遅延のまま最後の tick まで見て、自然に終わっていなければ中断として終える
            // （中断を知らせると残りを早送りで消化してしまう）
            guard let data = try? OnlineFramer.encode(.matchFinished(finalTick: final)) else { return }
            for p in peers {
                connection(of: p)?.send(encoded: data)
                spectatorStreams[p]?.ended = true
            }
        }
    }

    /// 試合が終わった（ホストが抜けた・リザルトへ進んだ）: 観戦者へ残りを送り切る。基準を符号化中・案内中の観戦者は中断で終える。
    private func finishSpectatorStreams() {
        guard relay.isActive else { return }
        // 自然に終わった試合はタイマー（pumpSpectators）が先に終わりを記録している（終了の演出の間に必ず回る）
        relay.finish()
        relay.release()
        flushAllSpectatorStreams()
        let waiting = Set(spectatorStreams.filter { $0.value.pendingBaseTick != nil }.map(\.key)).union(invitedSpectators)
        if !waiting.isEmpty, let data = try? OnlineFramer.encode(.matchAborted(reason: L("試合は終了しました", "The match has ended"))) {
            for p in waiting { connection(of: p)?.send(encoded: data) }
        }
    }

    private func startSpectatorTimer() {
        guard spectatorTimer == nil else { return }
        let t = Timer(timeInterval: OnlineProtocol.spectatorReleaseInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pumpSpectators() }
        }
        RunLoop.main.add(t, forMode: .common)
        spectatorTimer = t
    }

    private func stopSpectatorTimer() {
        spectatorTimer?.invalidate()
        spectatorTimer = nil
    }

    /// テスト・表示用: 観戦者へ出した最後の tick。
    var spectatorReleasedTick: Int { relay.releasedTick }
    /// テスト用: 観戦の配信先の数。
    var spectatorStreamCount: Int { spectatorStreams.count }
    /// テスト用: 保持している観戦用の記録。
    var spectatorRelayRetained: (frames: Int, keyframes: [Int]) { (relay.retainedFrameCount, relay.retainedKeyframeTicks) }
}

/// クライアントの配信バッファ（tick 昇順・重複なし）。先頭の位置を進めるだけで取り出し、たまに詰める
/// （観戦の途中参加・遅延分の前倒しで数千 tick 溜まっても removeFirst の O(n²) にならない）。
struct OnlineFrameQueue {
    private var items: [ReplayFrame] = []
    private var head = 0
    /// これまでに受け取った最後の tick（これ以下は重複として捨てる）。
    private var lastTick = Int.min

    var count: Int { items.count - head }
    var isEmpty: Bool { count == 0 }
    var first: ReplayFrame? { head < items.count ? items[head] : nil }

    /// 届いた配信を足す（届いた最後の tick より前のものは重複として捨てる）。
    mutating func append(_ frames: [ReplayFrame]) {
        for f in frames where f.tick > lastTick {
            items.append(f)
            lastTick = f.tick
        }
    }

    /// tick の配信を取り出す（それより前は捨てる）。まだ届いていなければ nil。
    mutating func pop(tick: Int) -> ReplayFrame? {
        while head < items.count, items[head].tick < tick { head += 1 }
        guard head < items.count, items[head].tick == tick else {
            compactIfNeeded()
            return nil
        }
        let f = items[head]
        head += 1
        compactIfNeeded()
        return f
    }

    /// tick 以下を捨てる。
    mutating func drop(through tick: Int) {
        while head < items.count, items[head].tick <= tick { head += 1 }
        compactIfNeeded()
    }

    /// すべて捨てる。resettingTo: 以後はこの tick より後だけ受け付ける（スナップショットの続き）。
    mutating func removeAll(resettingTo tick: Int? = nil) {
        items.removeAll(keepingCapacity: true)
        head = 0
        lastTick = tick ?? .min
    }

    private mutating func compactIfNeeded() {
        if head == items.count {
            items.removeAll(keepingCapacity: true)
            head = 0
        } else if head >= 1024 && head * 2 >= items.count {
            items.removeFirst(head)
            head = 0
        }
    }
}
