import Foundation

// 担当: online。フレンドの受信箱への接続（中継サーバーの `/v1/inbox/<フレンドコード>?key=…`）。
//
// アプリを開いている間だけ繋ぐ。切れたら指数バックオフで繋ぎ直す（コードを奪われた・版が合わない時は諦める）。
// 送信は ack（delivered / queued / offline）を返す。繋がっていなければ notConnected。
// 生存確認はテキストの ping（中継が pong を自動応答。部屋の中継と同じ）。
// すべての呼び出し・コールバックはメインアクターで行う（RelaySocket の約束）。

extension OnlineRelayConfig {
    /// 受信箱の URL（`<base>/v1/inbox/<CODE>?key=<KEY>&rv=1`）。base にパスがあれば後ろに足す。
    static func inboxURL(base: URL, code: String, key: String) -> URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        var path = c.path
        while path.hasSuffix("/") { path.removeLast() }
        c.path = path + "/v1/inbox/" + code
        c.queryItems = [URLQueryItem(name: "key", value: key), URLQueryItem(name: "rv", value: "\(relayVersion)")]
        return c.url ?? base
    }
}

@MainActor
final class FriendInboxClient {
    enum Status: Equatable {
        /// 繋いでいない（止めている）。
        case offline
        /// 繋いでいる（hello を待っている）・繋ぎ直している。
        case connecting
        /// 受け取れる状態。
        case online
        /// 諦めた（コードが他の端末に使われている・アプリの版が古い）。理由を持つ。
        case failed(String)
    }

    private(set) var status: Status = .offline {
        didSet { if status != oldValue { onStatus?(status) } }
    }
    var onStatus: ((Status) -> Void)?
    var onMessage: ((_ from: String, _ payload: InboxPayload) -> Void)?
    var onPresence: (([String]) -> Void)?

    let baseURL: URL
    let code: String
    private let key: String
    private let makeSocket: RelaySocketFactory
    private let schedule: RelayScheduler

    private var socket: RelaySocket?
    /// 接続の世代（古い接続のコールバック・予約を捨てる）。
    private var generation = 0
    private var started = false
    private var attempts = 0
    private var nextID = 1
    private var pending: [Int: (InboxSendResult) -> Void] = [:]

    init(baseURL: URL, code: String, key: String,
         makeSocket: @escaping RelaySocketFactory = RelayDefaults.socketFactory,
         schedule: @escaping RelayScheduler = RelayDefaults.scheduler) {
        self.baseURL = baseURL
        self.code = code
        self.key = key
        self.makeSocket = makeSocket
        self.schedule = schedule
    }

    /// 繋ぐ（既に動いていれば何もしない）。
    func start() {
        guard !started else { return }
        started = true
        attempts = 0
        connect()
    }

    /// 切って止める（アプリが裏へ回った時など）。
    func stop() {
        guard started else { return }
        started = false
        generation += 1
        socket?.close(code: 1000, reason: "stop")
        socket = nil
        failPending()
        status = .offline
    }

    var isOnline: Bool { status == .online }

    /// フレンドへ送る。queue: 相手が不在なら預ける（申請だけ）。結果は completion（メインアクター）に 1 回。
    func send(to friend: String, payload: InboxPayload, queue: Bool = false, completion: ((InboxSendResult) -> Void)? = nil) {
        let id = nextID
        guard status == .online, let socket, let text = InboxClientMessage.send(to: friend, id: id, payload: payload, queue: queue) else {
            completion?(.notConnected)
            return
        }
        nextID += 1
        if let completion { pending[id] = completion }
        socket.send(text: text)
    }

    /// フレンドの在席を問い合わせる（結果は onPresence）。
    func requestPresence(_ codes: [String]) {
        guard status == .online, let socket, !codes.isEmpty, let text = InboxClientMessage.presence(codes: codes) else { return }
        socket.send(text: text)
    }

    // MARK: - 接続

    private func connect() {
        guard started else { return }
        generation += 1
        let gen = generation
        status = .connecting
        let s = makeSocket(OnlineRelayConfig.inboxURL(base: baseURL, code: code, key: key))
        socket = s
        s.onText = { [weak self] text in
            guard let self, self.generation == gen else { return }
            self.receive(text)
        }
        s.onClose = { [weak self] closeCode, _ in
            guard let self, self.generation == gen else { return }
            self.disconnected(closeCode: closeCode)
        }
        s.onFailure = { [weak self] _ in
            guard let self, self.generation == gen else { return }
            self.disconnected(closeCode: nil)
        }
        s.connect()
        // 開かないまま待たせない（受信箱へ繋ぐのは hello が届くまで）
        schedule(OnlineRelayConfig.connectTimeout) { [weak self] in
            guard let self, self.generation == gen, self.status == .connecting else { return }
            self.disconnected(closeCode: nil)
        }
    }

    private func receive(_ text: String) {
        guard let message = InboxServerMessage.decode(text) else { return }
        switch message {
        case .hello:
            attempts = 0
            status = .online
            keepalive(generation)
        case .message(let from, let payload):
            onMessage?(from, payload)
        case .ack(let id, let result):
            pending.removeValue(forKey: id)?(result)
        case .presence(let online):
            onPresence?(online)
        }
    }

    /// 生存確認の ping（携帯回線の NAT のタイムアウト対策）。世代が変われば止まる。
    private func keepalive(_ gen: Int) {
        schedule(OnlineRelayConfig.keepaliveInterval) { [weak self] in
            guard let self, self.generation == gen, self.status == .online else { return }
            self.socket?.send(text: "ping")
            self.keepalive(gen)
        }
    }

    private func disconnected(closeCode: Int?) {
        generation += 1
        socket?.close(code: 1000, reason: "closed")
        socket = nil
        failPending()
        guard started else { return }
        switch closeCode {
        case 4012:
            started = false
            status = .failed(L("このフレンドコードは別の端末で使われています", "This friend code is in use on another device"))
        case 4010:
            started = false
            status = .failed(RelayCloseCode.relayVersion.message)
        case 4011:
            // 同じ鍵の別の接続に入れ替えられた（別の端末・再接続）。こちらは繋ぎ直さずに身を引く
            started = false
            status = .offline
        default:
            status = .connecting
            let delay = min(OnlineRelayConfig.reconnectMaxDelay, OnlineRelayConfig.reconnectBaseDelay * pow(2, Double(min(attempts, 8))))
            attempts += 1
            let gen = generation
            schedule(delay) { [weak self] in
                guard let self, self.started, self.generation == gen else { return }
                self.connect()
            }
        }
    }

    private func failPending() {
        let callbacks = pending
        pending = [:]
        for (_, completion) in callbacks { completion(.notConnected) }
    }
}
