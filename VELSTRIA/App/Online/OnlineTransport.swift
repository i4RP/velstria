import Foundation
import Network
import VelstriaCore

// 担当: online。接続の抽象（OnlineConnection）と実装。
// - LoopbackConnection: 同一プロセス内の対（テスト・自己対戦の検証用）。符号化を通して配達する。
// - NWOnlineConnection / NWOnlineListener / NWOnlineBrowser: Network.framework の TCP + Bonjour（同一 LAN）。
// すべての呼び出し・コールバックはメインアクターで行う（Network.framework のキューからはメインへ移してから触る）。

enum OnlineConnectionState: Equatable {
    case connecting
    case ready
    case failed(String)
    case closed
}

@MainActor
protocol OnlineConnection: AnyObject {
    var id: UUID { get }
    var state: OnlineConnectionState { get }
    /// 相手の表示用アドレス。
    var remoteDescription: String { get }
    var onMessage: ((OnlineMessage) -> Void)? { get set }
    var onStateChange: ((OnlineConnectionState) -> Void)? { get set }
    func start()
    func send(_ message: OnlineMessage)
    func close()
}

// MARK: - ループバック

/// 同一プロセス内で対になる接続。送信は符号化 → 復号を通して相手の onMessage へ届く（配線上と同じ内容になることを保証）。
/// `holdsDelivery` で配達を保留し、`flush()` でまとめて届ける（遅延・詰まりの再現）。
@MainActor
final class LoopbackConnection: OnlineConnection {
    let id = UUID()
    private(set) var state: OnlineConnectionState = .connecting
    var remoteDescription: String { "loopback" }
    /// 受信ハンドラ。設定されるまで届いたメッセージは inbox に留める（接続直後の名乗りを落とさない）。
    var onMessage: ((OnlineMessage) -> Void)? { didSet { if onMessage != nil { deliver() } } }
    var onStateChange: ((OnlineConnectionState) -> Void)?

    private weak var peer: LoopbackConnection?
    private var inbox: [OnlineMessage] = []
    private var delivering = false
    /// true の間、届いたメッセージを inbox に留める。
    var holdsDelivery = false { didSet { if !holdsDelivery { deliver() } } }
    /// 送信したメッセージ数（テスト用）。
    private(set) var sentCount = 0
    /// 送信したバイト数（テスト用）。
    private(set) var sentBytes = 0

    static func pair() -> (LoopbackConnection, LoopbackConnection) {
        let a = LoopbackConnection()
        let b = LoopbackConnection()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    func start() {
        guard state == .connecting else { return }
        state = .ready
        onStateChange?(.ready)
    }

    func send(_ message: OnlineMessage) {
        guard state == .ready, let peer else { return }
        do {
            let data = try OnlineFramer.encode(message)
            sentCount += 1
            sentBytes += data.count
            var framer = OnlineFramer()
            for m in try framer.feed(data) { peer.enqueue(m) }
        } catch {
            assertionFailure("loopback encode failed: \(error)")
        }
    }

    private func enqueue(_ message: OnlineMessage) {
        inbox.append(message)
        deliver()
    }

    private func deliver() {
        guard !delivering, !holdsDelivery, let handler = onMessage else { return }
        delivering = true
        while !inbox.isEmpty, !holdsDelivery, state == .ready {
            let m = inbox.removeFirst()
            handler(m)
        }
        delivering = false
    }

    func close() {
        guard state != .closed else { return }
        state = .closed
        let p = peer
        peer = nil
        inbox.removeAll()
        onStateChange?(.closed)
        p?.peerClosed()
    }

    private func peerClosed() {
        guard state != .closed else { return }
        state = .closed
        peer = nil
        onStateChange?(.closed)
    }
}

// MARK: - Network.framework

enum OnlineNetwork {
    /// TCP（遅延優先: Nagle 無効）。同一 LAN と端末間（peer-to-peer Wi-Fi）を許可。
    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 10
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true
        return params
    }

    /// 端末の IPv4 アドレス（Wi-Fi 優先）。ホストが手入力用に表示する。
    static func localIPv4Addresses() -> [String] {
        var out: [(name: String, address: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  (Int32(ifa.ifa_flags) & IFF_UP) != 0, (Int32(ifa.ifa_flags) & IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let name = String(cString: ifa.ifa_name)
            out.append((name, String(cString: host)))
        }
        // en0（Wi-Fi）を先頭に、それ以外は名前順
        return out.sorted { a, b in
            if a.name == "en0" { return true }
            if b.name == "en0" { return false }
            return a.name < b.name
        }.map(\.address)
    }

    /// "host:port" / "host" を分解する（port 省略時は既定）。
    static func parseAddress(_ text: String) -> (host: String, port: UInt16)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let colon = trimmed.lastIndex(of: ":"), trimmed.filter({ $0 == ":" }).count == 1 {
            let host = String(trimmed[..<colon])
            guard let port = UInt16(trimmed[trimmed.index(after: colon)...]), !host.isEmpty else { return nil }
            return (host, port)
        }
        return (trimmed, OnlineProtocol.defaultPort)
    }
}

/// NWConnection を包む接続。受信は Network.framework のキューで受け、メインへ移してから復号する。
@MainActor
final class NWOnlineConnection: OnlineConnection {
    let id = UUID()
    private(set) var state: OnlineConnectionState = .connecting
    let remoteDescription: String
    var onMessage: ((OnlineMessage) -> Void)?
    var onStateChange: ((OnlineConnectionState) -> Void)?

    nonisolated private let connection: NWConnection
    nonisolated private let queue = DispatchQueue(label: "velstria.online.connection", qos: .userInteractive)
    private var framer = OnlineFramer()
    private var started = false

    init(connection: NWConnection) {
        self.connection = connection
        self.remoteDescription = Self.describe(connection.endpoint)
    }

    convenience init(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? .any)
        self.init(connection: NWConnection(to: endpoint, using: OnlineNetwork.parameters()))
    }

    convenience init(endpoint: NWEndpoint) {
        self.init(connection: NWConnection(to: endpoint, using: OnlineNetwork.parameters()))
    }

    nonisolated static func describe(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, let port): return "\(host):\(port)"
        case .service(let name, _, _, _): return name
        default: return "\(endpoint)"
        }
    }

    func start() {
        guard !started else { return }
        started = true
        connection.stateUpdateHandler = { [weak self] st in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(nwState: st) }
            }
        }
        connection.start(queue: queue)
        receiveLoop()
    }

    private func handle(nwState: NWConnection.State) {
        switch nwState {
        case .ready:
            guard state == .connecting else { return }
            state = .ready
            onStateChange?(.ready)
        case .failed(let error):
            fail(error.localizedDescription)
        case .waiting(let error):
            // 相手が見つからない・到達できない間は待つ（タイムアウトは TCP の connectionTimeout）
            if state == .connecting { onStateChange?(.connecting) }
            _ = error
        case .cancelled:
            if state != .closed && state != .connecting { closedByPeer() }
            else if state == .connecting { fail(L("接続できませんでした", "Could not connect")) }
        default:
            break
        }
    }

    nonisolated private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                DispatchQueue.main.async { MainActor.assumeIsolated { self.feed(data) } }
            }
            if let error {
                DispatchQueue.main.async { MainActor.assumeIsolated { self.fail(error.localizedDescription) } }
                return
            }
            if isComplete {
                DispatchQueue.main.async { MainActor.assumeIsolated { self.closedByPeer() } }
                return
            }
            self.receiveLoop()
        }
    }

    private func feed(_ data: Data) {
        guard state == .ready || state == .connecting else { return }
        do {
            for m in try framer.feed(data) { onMessage?(m) }
        } catch {
            fail(L("受信データが壊れています", "Corrupted data received"))
        }
    }

    func send(_ message: OnlineMessage) {
        guard state == .ready else { return }
        guard let data = try? OnlineFramer.encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error, let self else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.fail(error.localizedDescription) } }
        })
    }

    private func fail(_ reason: String) {
        guard state != .closed, state != .failed(reason) else { return }
        if case .failed = state { return }
        state = .failed(reason)
        connection.cancel()
        onStateChange?(state)
    }

    private func closedByPeer() {
        guard state != .closed else { return }
        if case .failed = state { return }
        state = .closed
        connection.cancel()
        onStateChange?(.closed)
    }

    func close() {
        guard state != .closed else { return }
        if case .failed = state { return }
        state = .closed
        connection.cancel()
        onStateChange?(.closed)
    }
}

/// ホストの待ち受け（TCP + Bonjour 広告）。
@MainActor
final class NWOnlineListener {
    enum State: Equatable { case idle, starting, ready(port: UInt16), failed(String) }

    private(set) var state: State = .idle
    var onAccept: ((NWOnlineConnection) -> Void)?
    var onStateChange: ((State) -> Void)?

    private var listener: NWListener?
    private let roomName: String
    private var preferredPort: UInt16?
    /// Bonjour で部屋を広告する（テストでは切る）。
    private let advertises: Bool
    nonisolated private let queue = DispatchQueue(label: "velstria.online.listener", qos: .userInteractive)

    init(roomName: String, preferredPort: UInt16? = OnlineProtocol.defaultPort, advertises: Bool = true) {
        self.roomName = roomName
        self.preferredPort = preferredPort
        self.advertises = advertises
    }

    func start() {
        guard listener == nil else { return }
        state = .starting
        startListener(port: preferredPort)
    }

    private func startListener(port: UInt16?) {
        let nwPort = port.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        let l: NWListener
        do {
            l = try NWListener(using: OnlineNetwork.parameters(), on: nwPort)
        } catch {
            if port != nil {
                startListener(port: nil)
            } else {
                state = .failed(error.localizedDescription)
                onStateChange?(state)
            }
            return
        }
        if advertises {
            l.service = NWListener.Service(name: roomName, type: OnlineProtocol.bonjourType,
                                           txtRecord: NWTXTRecord(["name": roomName, "v": "\(OnlineProtocol.version)"]))
        }
        l.stateUpdateHandler = { [weak self] st in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(nwState: st, requestedPort: port) } }
        }
        l.newConnectionHandler = { [weak self] c in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { c.cancel(); return }
                    let wrapped = NWOnlineConnection(connection: c)
                    self.onAccept?(wrapped)
                    wrapped.start()
                }
            }
        }
        listener = l
        l.start(queue: queue)
    }

    private func handle(nwState: NWListener.State, requestedPort: UInt16?) {
        switch nwState {
        case .ready:
            let port = listener?.port?.rawValue ?? requestedPort ?? 0
            state = .ready(port: port)
            onStateChange?(state)
        case .failed(let error):
            listener?.cancel()
            listener = nil
            if requestedPort != nil {
                // 既定ポートが使われていれば OS に選ばせる
                startListener(port: nil)
            } else {
                state = .failed(error.localizedDescription)
                onStateChange?(state)
            }
        default:
            break
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = .idle
    }
}

/// 同一 LAN の部屋を Bonjour で探す。
@MainActor
final class NWOnlineBrowser {
    struct Room: Identifiable, Hashable {
        var id: String { "\(endpoint)" }
        let name: String
        let endpoint: NWEndpoint
    }

    private(set) var rooms: [Room] = []
    private(set) var statusText: String?
    var onChange: (([Room]) -> Void)?
    private var browser: NWBrowser?
    nonisolated private let queue = DispatchQueue(label: "velstria.online.browser")

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: OnlineProtocol.bonjourType, domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let rooms = results.compactMap { r -> Room? in
                guard case .service(let name, _, _, _) = r.endpoint else { return nil }
                return Room(name: name, endpoint: r.endpoint)
            }.sorted { $0.name < $1.name }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.rooms = rooms
                    self.onChange?(rooms)
                }
            }
        }
        b.stateUpdateHandler = { [weak self] st in
            let text: String?
            switch st {
            case .failed(let e): text = e.localizedDescription
            case .waiting(let e): text = e.localizedDescription
            default: text = nil
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.statusText = text } }
        }
        browser = b
        b.start(queue: queue)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        rooms = []
    }
}
