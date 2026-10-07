import Foundation
@testable import VELSTRIA

/// 中継サーバー（relay/ の Worker + Durable Object）の振る舞いを Swift で真似るテスト用の代役。
/// 同じ URL（/v1/rooms/<CODE>?role=host|guest&rv=1）・同じバイナリの形式・同じ close コードで応える。
///
/// - 部屋コード 1 つ = 部屋 1 つ。部屋は消さない（参加者 ID は部屋の寿命の間は再利用しない。中継は DO の storage に保つ）。
/// - ホスト: 既にホストがいれば受け入れてから 4009 room_taken（同じ鍵 hk で戻ったホストは、前の接続を 4011 host_replaced で閉じて入れ替わる。
///   前の接続の参加者は 4001 host_left。supportsTakeover = false は入れ替えのない古い中継の再現）。参加者: ホストがいなければ 4004 no_room、32 人なら 4008 room_full。
/// - rv が 1 でなければ受け入れてから 4010 relay_version。不正な部屋コード・role は 400（繋がらない）。
/// - 不正な形式は 1003、256 KiB を超えるメッセージは 1009（その接続だけ閉じる）。ホストが閉じた・切れたら全参加者を 4001 host_left。
/// - テキストの ping には pong（それ以外のテキストは無視）。
/// 配達はキューに積み、呼び出しの終わりにまとめて流す（入れ子の呼び出しにしない。順序は WebSocket と同じく接続毎に保つ）。
@MainActor
final class InMemoryRelay {
    static let baseURL = URL(string: "wss://relay.test")!

    final class Room {
        var host: Socket?
        var guests: [UInt32: Socket] = [:]
        var nextGuestID: UInt32 = 1
    }

    private(set) var rooms: [String: Room] = [:]
    /// false の間は新しい接続を受け付けない（インターネットに繋がらない状態の再現）。
    var isReachable = true
    /// false なら hk を無視する（ホストの入れ替えがない古い中継。room_taken のままになる）。
    var supportsTakeover = true
    /// true の間は配達をキューに留める（false に戻すとまとめて流す）。
    var holdsDelivery = false { didSet { if !holdsDelivery { drain() } } }
    /// 記録（テスト用）: ホスト → 中継・参加者 → 中継の最大メッセージ長、ホストが送ったバイナリの数。
    private(set) var largestHostMessage = 0
    private(set) var largestGuestMessage = 0
    private(set) var hostBinaryCount = 0
    /// 中継が閉じた接続の close コード（順に）。
    private(set) var closeLog: [Int] = []
    /// 作られた接続（順に）。
    private(set) var sockets: [Socket] = []

    private var queue: [() -> Void] = []
    private var draining = false

    /// RelayHostLink / RelayGuestConnection に渡す作り手。
    var factory: RelaySocketFactory {
        { [unowned self] url in
            let s = Socket(relay: self, url: url)
            self.sockets.append(s)
            return s
        }
    }

    func room(_ code: String) -> Room? { rooms[code] }
    func hasHost(_ code: String) -> Bool { rooms[code]?.host != nil }
    func guestCount(_ code: String) -> Int { rooms[code]?.guests.count ?? 0 }

    // MARK: 接続（クライアント側の窓口）

    final class Socket: RelaySocket {
        let url: URL
        private weak var relay: InMemoryRelay?
        var onOpen: (() -> Void)?
        var onBinary: ((Data) -> Void)?
        var onText: ((String) -> Void)?
        var onClose: ((Int, String) -> Void)?
        var onFailure: ((String) -> Void)?
        /// 中継側の登録。
        fileprivate(set) var role: RelayRole?
        fileprivate(set) var code: String?
        fileprivate(set) var guestID: UInt32?
        /// ホストの再接続の鍵（URL の hk。形式が正しい時だけ）。
        fileprivate(set) var resumeKey: String?
        /// 中継が受け入れて、まだどちらも閉じていない。
        fileprivate(set) var isOpen = false
        /// クライアントが close() した（以後コールバックしない）。
        fileprivate(set) var clientClosed = false
        /// 中継が閉じた close コード。
        fileprivate(set) var serverCloseCode: Int?
        /// 受け取ったテキスト（pong の確認用）。
        fileprivate(set) var receivedTexts: [String] = []

        init(relay: InMemoryRelay, url: URL) {
            self.relay = relay
            self.url = url
        }

        func connect() { relay?.connect(self) }
        func send(binary: Data) { relay?.received(binary, from: self) }
        func send(text: String) { relay?.receivedText(text, from: self) }
        func close(code: Int, reason: String) { relay?.clientClose(self) }
    }

    // MARK: 中継の振る舞い

    private func enqueue(_ work: @escaping () -> Void) {
        queue.append(work)
        drain()
    }

    private func drain() {
        guard !draining, !holdsDelivery else { return }
        draining = true
        while !queue.isEmpty, !holdsDelivery {
            let work = queue.removeFirst()
            work()
        }
        draining = false
    }

    /// クライアントへ届ける（クライアントが閉じた後は捨てる）。
    private func deliver(to s: Socket, _ event: @escaping (Socket) -> Void) {
        enqueue { [weak s] in
            guard let s, !s.clientClosed else { return }
            event(s)
        }
    }

    private func connect(_ s: Socket) {
        enqueue { [weak self, weak s] in
            guard let self, let s, !s.clientClosed else { return }
            guard self.isReachable else {
                self.deliver(to: s) { $0.onFailure?(RelayCloseCode.connectFailureMessage(httpStatus: nil, detail: "offline")) }
                return
            }
            guard let comps = URLComponents(url: s.url, resolvingAgainstBaseURL: false) else { return }
            let parts = comps.path.split(separator: "/").map(String.init)
            let query = Dictionary((comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            guard parts.count == 3, parts[0] == "v1", parts[1] == "rooms" else {
                self.deliver(to: s) { $0.onFailure?(RelayCloseCode.connectFailureMessage(httpStatus: 404, detail: nil)) }
                return
            }
            let code = parts[2]
            guard Self.isValidCode(code), let role = query["role"].flatMap(RelayRole.init(rawValue:)) else {
                self.deliver(to: s) { $0.onFailure?(RelayCloseCode.connectFailureMessage(httpStatus: 400, detail: nil)) }
                return
            }
            // 受け入れ（WebSocket が開く）
            s.isOpen = true
            self.deliver(to: s) { $0.onOpen?() }
            guard query["rv"] == "\(OnlineRelayConfig.relayVersion)" else {
                self.serverClose(s, .relayVersion)
                return
            }
            let room = self.rooms[code] ?? Room()
            self.rooms[code] = room
            switch role {
            case .host:
                let key = query["hk"].flatMap { Self.isValidResumeKey($0) ? $0 : nil }
                if let old = room.host {
                    guard self.supportsTakeover, let key, old.resumeKey == key else {
                        self.serverClose(s, .roomTaken)
                        return
                    }
                    // 切れたのに気づいていない前のホストの接続と入れ替える（参加者は host_left。unregister が閉じる）
                    self.serverClose(old, .hostReplaced)
                }
                s.role = .host
                s.code = code
                s.resumeKey = key
                room.host = s
            case .guest:
                guard let host = room.host else {
                    self.serverClose(s, .noRoom)
                    return
                }
                guard room.guests.count < OnlineRelayConfig.maxGuests else {
                    self.serverClose(s, .roomFull)
                    return
                }
                let id = room.nextGuestID
                room.nextGuestID += 1
                s.role = .guest
                s.code = code
                s.guestID = id
                room.guests[id] = s
                self.deliver(to: host) { $0.onBinary?(RelayWire.encode(.guestOpen(id))) }
            }
        }
    }

    /// 中継の hk の形式 `^[A-Za-z0-9_-]{16,64}$`。
    static func isValidResumeKey(_ key: String) -> Bool {
        key.range(of: "^[A-Za-z0-9_-]{16,64}$", options: .regularExpression) != nil
    }

    /// 中継の正規表現 `^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$`（アプリの RelayRoomCode とは独立に書く）。
    static func isValidCode(_ code: String) -> Bool {
        code.range(of: "^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$", options: .regularExpression) != nil
    }

    private func received(_ data: Data, from s: Socket) {
        enqueue { [weak self, weak s] in
            guard let self, let s, s.isOpen, let code = s.code, let room = self.rooms[code] else { return }
            if data.count > OnlineRelayConfig.serverMaxMessageBytes {
                self.serverClose(s, .messageTooBig)
                return
            }
            switch s.role {
            case .host?:
                self.largestHostMessage = max(self.largestHostMessage, data.count)
                self.hostBinaryCount += 1
                guard let m = RelayWire.decodeHostMessage(data) else {
                    self.serverClose(s, .unsupportedData)
                    return
                }
                switch m {
                case .send(let id, let payload):
                    if let g = room.guests[id] { self.deliver(to: g) { $0.onBinary?(payload) } }
                case .kick(let id):
                    if let g = room.guests.removeValue(forKey: id) { self.serverClose(g, .closedByHost, unregister: false) }
                }
            case .guest?:
                self.largestGuestMessage = max(self.largestGuestMessage, data.count)
                guard let id = s.guestID, let host = room.host else { return }
                self.deliver(to: host) { $0.onBinary?(RelayWire.encode(.guestData(id, data))) }
            case nil:
                break
            }
        }
    }

    private func receivedText(_ text: String, from s: Socket) {
        enqueue { [weak self, weak s] in
            guard let self, let s, s.isOpen else { return }
            // 中継の setWebSocketAutoResponse（DO を起こさない）
            if text == "ping" {
                self.deliver(to: s) { sock in
                    sock.receivedTexts.append("pong")
                    sock.onText?("pong")
                }
            }
        }
    }

    /// クライアントが閉じた（webSocketClose）。
    private func clientClose(_ s: Socket) {
        s.clientClosed = true
        enqueue { [weak self, weak s] in
            guard let self, let s, s.isOpen else { return }
            s.isOpen = false
            self.unregister(s)
        }
    }

    /// 中継が接続を閉じる。
    private func serverClose(_ s: Socket, _ code: RelayCloseCode, unregister: Bool = true) {
        guard s.isOpen else { return }
        s.isOpen = false
        s.serverCloseCode = code.rawValue
        closeLog.append(code.rawValue)
        if unregister { self.unregister(s) }
        deliver(to: s) { $0.onClose?(code.rawValue, code.reasonName) }
    }

    /// 部屋から外す: ホストなら全参加者を 4001、参加者ならホストへ GUEST_CLOSE。
    private func unregister(_ s: Socket) {
        guard let code = s.code, let room = rooms[code] else { return }
        switch s.role {
        case .host?:
            guard room.host === s else { return }
            room.host = nil
            let guests = room.guests.values
            room.guests.removeAll()
            for g in guests { serverClose(g, .hostLeft, unregister: false) }
        case .guest?:
            guard let id = s.guestID, room.guests[id] === s else { return }
            room.guests[id] = nil
            if let host = room.host { deliver(to: host) { $0.onBinary?(RelayWire.encode(.guestClose(id))) } }
        case nil:
            break
        }
    }

    // MARK: テスト用の操作

    /// ホストの回線が close フレーム無しで切れた（中継は webSocketError → 全参加者を host_left）。
    func dropHost(_ code: String) {
        guard let host = rooms[code]?.host else { return }
        enqueue { [weak self] in
            guard let self, host.isOpen else { return }
            host.isOpen = false
            self.unregister(host)
            self.deliver(to: host) { $0.onFailure?(L("中継サーバーとの接続が切れました", "Lost connection to the relay server")) }
        }
    }

    /// 参加者の回線が切れた（ホストへ GUEST_CLOSE）。
    func dropGuest(_ code: String, id: UInt32) {
        guard let g = rooms[code]?.guests[id] else { return }
        enqueue { [weak self] in
            guard let self, g.isOpen else { return }
            g.isOpen = false
            self.unregister(g)
            self.deliver(to: g) { $0.onFailure?(L("中継サーバーとの接続が切れました", "Lost connection to the relay server")) }
        }
    }

    /// ホストの古い接続が中継に残っている（半開き。中継はまだ切断に気づかない）状態を作る:
    /// ホスト側（アプリ）にだけ切断を知らせ、中継はホストを登録したままにする。
    func strandHost(_ code: String) {
        guard let host = rooms[code]?.host else { return }
        enqueue { [weak self] in
            guard let self else { return }
            self.deliver(to: host) { sock in
                let callback = sock.onFailure
                sock.clientClosed = true
                callback?(L("中継サーバーとの接続が切れました", "Lost connection to the relay server"))
            }
        }
    }

    /// 半開きの古いホストの接続を中継が片付けた（全参加者を host_left）。
    func reapStrandedHost(_ code: String) {
        guard let host = rooms[code]?.host else { return }
        enqueue { [weak self] in
            guard let self, host.isOpen else { return }
            host.isOpen = false
            self.unregister(host)
        }
    }
}

/// 遅らせた実行を手動で進める（再接続のバックオフ・確保の判定）。
@MainActor
final class ManualRelayScheduler {
    private(set) var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    /// 予約された待ち時間（順に）。
    private(set) var delays: [TimeInterval] = []

    var scheduler: RelayScheduler {
        { [unowned self] delay, work in
            self.pending.append((delay, work))
            self.delays.append(delay)
        }
    }

    /// いま予約されているものをすべて実行する（実行中に予約されたものは次回）。
    func runAll() {
        let items = pending
        pending.removeAll()
        for item in items { item.work() }
    }

    /// 予約が無くなるまで実行する（上限つき）。
    func runUntilIdle(limit: Int = 50) {
        var n = 0
        while !pending.isEmpty && n < limit {
            runAll()
            n += 1
        }
    }
}
