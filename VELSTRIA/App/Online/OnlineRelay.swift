import Foundation
import VelstriaCore

// 担当: online。インターネット対戦の中継（リレー）。設計は ARCHITECTURE.md「インターネット対戦（中継）」。
//
// 中継サーバー（リポジトリ直下 relay/。Cloudflare Workers + Durable Object）は中身を解釈しない土管で、部屋コード 1 つに
// ホスト 1 台と参加者（最大 32）をつなぐ。ゲームの手順（OnlineMessage を OnlineFramer で長さ区切りにしたバイト列）は
// そのまま流すので、リッスンサーバー方式（ホストの iPhone が権威シミュレーション）は LAN と変わらない。
// - ホスト: RelayHostLink が role=host で繋ぎ、参加者ごとの仮想接続（RelayGuestEndpoint）を OnlineSession.accept へ渡す。
//   切れたら同じコードで繋ぎ直す（指数バックオフ）。新しいコードが使われていれば作り直す。
// - 参加者: RelayGuestConnection が role=guest で繋ぐ（OnlineConnection 準拠。NWOnlineConnection の代わりに使える）。
// - 配線: ホスト ↔ 中継はヘッダ（種類 1 バイト + 参加者 ID 4 バイト、ビッグエンディアン）付きのバイナリ、参加者 ↔ 中継は中身だけ。
//   1 回の送信は 64 KiB 以下に分ける（中継の上限は 256 KiB。OnlineFramer がストリームとして組み直すので境界はどこでもよい）。
// - 生存確認: 15 秒毎にテキストの ping（中継が pong を自動応答する。携帯回線の NAT のタイムアウト対策）。
// すべての呼び出し・コールバックはメインアクターで行う（URLSession のキューからはメインへ移してから触る）。

/// 中継の設定。配備先の URL はここの 1 か所だけに書く（ほかはすべてここから作る）。
enum OnlineRelayConfig {
    /// 既定の中継サーバー（配備した Worker の URL。統合時に確定値へ置き換える。Debug は -relayURL で上書き）。
    static let defaultBaseURL = "wss://velstria-relay.shoei0205.workers.dev"
    /// 中継の版数（URL の rv。中継と一致しなければ 4010 relay_version で閉じられる）。
    static let relayVersion = 1
    /// 1 回の送信の上限（ヘッダ込み）。中継の上限より十分小さくする。
    static let chunkBytes = 64 * 1024
    /// 中継が受け付ける 1 メッセージの上限（超えると 1009 で閉じられる）。
    static let serverMaxMessageBytes = 256 * 1024
    /// ホスト側で参加者から受け取る 1 メッセージの上限。参加者 → ホストは名乗り・入力・ハッシュ報告など小さなものだけ
    /// （大きなスナップショットはホスト → 参加者）。名乗る前の参加者に 32 MiB を持たせないための歯止め。
    static let guestToHostMaxMessageBytes = 1024 * 1024
    /// 1 部屋の参加者の上限（中継側。ゲームの上限は OnlineProtocol.maxPlayers / maxSpectators）。
    static let maxGuests = 32
    /// テキストの ping の間隔（秒）。
    static let keepaliveInterval: TimeInterval = 15
    /// プライバシーの説明（オンボーディング・設定 > プライバシー）。docs/legal/privacy_policy_* の「オンライン対戦」と合わせる。
    static var privacyNote: String {
        L("オンライン対戦を部屋コードで遊ぶ時だけ、対戦に必要なデータ（操作・表示名・選んだヒーローなど）を中継サーバー（Cloudflare）経由で相手の端末へ送ります。中継サーバーは内容を解釈・保存せず、通信の処理のために接続元の IP アドレスを受け取ります。",
          "Only when you play an online match with a room code, the data the match needs (inputs, display name, chosen hero, etc.) is passed to the other players' devices through a relay server (Cloudflare). The relay neither reads nor stores it; it receives your IP address only to carry the connection.")
    }
    /// 中継へ繋ぐ時間切れ（秒）。DNS + TCP + TLS + WebSocket の昇格を、混んだモバイル回線でも待てるよう LAN（OnlineProtocol.connectTimeout）より長く。
    static let connectTimeout: TimeInterval = 25
    /// ホスト: 中継から何も届かない時間がこれを超えたら切れたとみなして繋ぎ直す（秒。ping 3 回分）。
    static let silenceTimeout: TimeInterval = 50
    /// ホスト: 開いてから pong を待たずに部屋を確保できたとみなすまでの時間（秒）。使われているコードは開いた直後に閉じられる。
    static let confirmDelay: TimeInterval = 2
    /// 再接続の待ち（秒。指数バックオフの初回と上限）。
    static let reconnectBaseDelay: TimeInterval = 1
    static let reconnectMaxDelay: TimeInterval = 30
    /// 再接続を諦めるまでの回数（合計で約 2 分。諦めたら画面の「再試行」で繋ぎ直す）。
    static let maxReconnectAttempts = 8
    /// 新しい部屋コードが使われていた時に作り直す回数。
    static let maxCodeRegenerations = 3
    /// 確保していたコードへの再接続で「使われている」と言われた時に、同じコードで待つ回数
    /// （中継が古い接続の切断に気づくまで。超えたらコードを作り直す）。
    static let roomTakenSameCodeRetries = 3

    /// 使う中継の URL（Debug は -relayURL で差し替え）。
    static var baseURL: URL {
        if let text = DebugLaunch.value(after: "-relayURL"), let url = validatedBaseURL(text) { return url }
        return URL(string: defaultBaseURL)!
    }

    /// ws / wss でホストのある URL だけを受け付ける。
    static func validatedBaseURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "ws" || scheme == "wss",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// 部屋の URL（`<base>/v1/rooms/<CODE>?role=host|guest&rv=1`）。base にパスがあれば後ろに足す。
    /// resumeKey: ホストの再接続の鍵（hk。ホストだけ。同じ鍵で戻ると、中継が気づいていない前のホストの接続と入れ替わる）。
    static func roomURL(base: URL, code: String, role: RelayRole, resumeKey: String? = nil) -> URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        var path = c.path
        while path.hasSuffix("/") { path.removeLast() }
        c.path = path + "/v1/rooms/" + code
        var items = [URLQueryItem(name: "role", value: role.rawValue),
                     URLQueryItem(name: "rv", value: "\(relayVersion)")]
        if role == .host, let resumeKey { items.append(URLQueryItem(name: "hk", value: resumeKey)) }
        c.queryItems = items
        return c.url ?? base
    }
}

/// 中継での立場。
enum RelayRole: String {
    case host
    case guest
}

// MARK: - 部屋コード

/// 部屋コード: 6 文字。英大文字と数字から紛らわしい I L O 0 1 を除いた 31 文字（中継の正規表現 `^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$`）。
/// 生成は端末の乱数（SystemRandomNumberGenerator。sim の乱数は使わない）。
enum RelayRoomCode {
    static let alphabet: [Character] = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let length = 6
    /// 紛らわしいので使わない文字。入力に含まれていたら打ち間違いとして知らせる（どれもコードに無いので、正しい文字を推測できない）。
    static let ambiguous: Set<Character> = ["I", "L", "O", "0", "1"]
    private static let alphabetSet = Set(alphabet)
    /// 入力から取り除く区切り（空白は別に除く）。
    private static let separators: Set<Character> = ["-", "‐", "‑", "‒", "–", "—", "―", "−", "ー", "ｰ", "_", "・", ".", "･"]

    static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(using: &rng)
    }

    static func generate<R: RandomNumberGenerator>(using rng: inout R) -> String {
        String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
    }

    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy { alphabetSet.contains($0) }
    }

    /// 表示用（3 文字ずつ空ける）。
    static func display(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    enum InputError: Error, Equatable {
        case empty
        case tooShort(Int)
        case tooLong(Int)
        /// 紛らわしい文字（I L O 0 1）。入力に現れた順。
        case ambiguous(String)
        /// それ以外の使えない文字。
        case invalid(String)

        var message: String {
            switch self {
            case .empty:
                return L("部屋コードを入力してください", "Enter a room code")
            case .tooShort(let n):
                return L("部屋コードは 6 文字です（あと \(RelayRoomCode.length - n) 文字）",
                         "Room codes have 6 characters (\(RelayRoomCode.length - n) more)")
            case .tooLong:
                return L("部屋コードは 6 文字です", "Room codes have 6 characters")
            case .ambiguous(let chars):
                return L("「\(chars)」は部屋コードに使われません（I・L・O・0・1 は使いません）",
                         "\"\(chars)\" never appears in room codes (I, L, O, 0 and 1 are not used)")
            case .invalid(let chars):
                return L("「\(chars)」は部屋コードに使えない文字です", "\"\(chars)\" cannot appear in a room code")
            }
        }
    }

    /// 入力を正規化して確かめる。規則:
    /// 1. 招待の文面・リンク（`code=XXXXXX` を含む）を貼り付けた時はそのコードを取り出す
    /// 2. 全角 → 半角、小文字 → 大文字
    /// 3. 空白・ハイフン・中点などの区切りを除く（表示は 3 文字ずつ空けるので、空けて打っても通す）
    /// 4. 紛らわしい文字（I L O 0 1）は置き換えずに弾く。O→0 のような読み替えも、どちらも使わない文字なので行わない
    /// 5. ちょうど 6 文字
    static func parse(_ input: String) -> Result<String, InputError> {
        let s = normalized(input)
        guard !s.isEmpty else { return .failure(.empty) }
        let bad = s.filter { !alphabetSet.contains($0) }
        let confusing = bad.filter { ambiguous.contains($0) }
        if !confusing.isEmpty { return .failure(.ambiguous(String(confusing))) }
        if !bad.isEmpty { return .failure(.invalid(String(bad))) }
        if s.count < length { return .failure(.tooShort(s.count)) }
        if s.count > length { return .failure(.tooLong(s.count)) }
        return .success(s)
    }

    /// 入力欄の表示用（規則 1〜3 を当て、6 文字までに切る。使えない文字は残してエラーを見せる）。
    static func cleaned(_ input: String) -> String {
        String(normalized(input).prefix(length))
    }

    /// 規則 1〜3 を当てた文字列（フレンドコードの入力もこれを使う）。
    static func normalized(_ input: String) -> String {
        var text = input
        if let fromLink = codeInLink(text) { text = fromLink }
        let half = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return String(half.uppercased().filter { c in
            !separators.contains(c) && !c.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
        })
    }

    /// 文面に `code=` があれば、その後ろの英数字を返す（招待リンクの貼り付け）。
    private static func codeInLink(_ text: String) -> String? {
        let half = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        guard let r = half.range(of: "code=", options: .caseInsensitive) else { return nil }
        let rest = half[r.upperBound...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return rest.isEmpty ? nil : String(rest)
    }
}

// MARK: - 招待リンク

/// 招待リンク `velstria://join?code=XXXXXX[&spectate=1]`（URL スキームは project.yml の CFBundleURLTypes）。
struct OnlineJoinLink: Equatable {
    static let scheme = "velstria"
    var code: String
    var spectate = false

    /// 開かれた URL を読む（スキームが違う・コードが不正なら nil）。
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let action = (url.host ?? url.pathComponents.first { $0 != "/" } ?? "").lowercased()
        guard action == "join", let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = comps.queryItems ?? []
        guard let raw = items.first(where: { $0.name.lowercased() == "code" })?.value,
              case .success(let code) = RelayRoomCode.parse(raw) else { return nil }
        self.code = code
        let flag = items.first { $0.name.lowercased() == "spectate" }?.value?.lowercased()
        spectate = flag == "1" || flag == "true" || flag == "yes"
    }

    init(code: String, spectate: Bool = false) {
        self.code = code
        self.spectate = spectate
    }

    /// 共有するリンク（観戦の指定は付けない: 受け取った人が選ぶ）。
    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = "join"
        c.queryItems = [URLQueryItem(name: "code", value: code)] + (spectate ? [URLQueryItem(name: "spectate", value: "1")] : [])
        return c.url!
    }

    /// 共有の文面（コード + リンク）。
    static func shareText(code: String, roomName: String) -> String {
        let link = OnlineJoinLink(code: code).url.absoluteString
        return L("VELSIA のオンライン対戦「\(roomName)」に招待します。\n部屋コード: \(RelayRoomCode.display(code))\n（アプリの「オンライン」→「部屋コードで参加」に入力）\n\(link)",
                 "Join my VELSIA online room \"\(roomName)\".\nRoom code: \(RelayRoomCode.display(code))\n(Online → Join by Room Code in the app)\n\(link)")
    }
}

// MARK: - 配線上の形式

/// ホスト ↔ 中継のバイナリ（ビッグエンディアン）。参加者 ↔ 中継はヘッダ無し（中身だけ）。
enum RelayWire {
    enum Kind: UInt8 {
        /// 中継 → ホスト: 参加者が繋いだ [0x10][u32 guestId]
        case guestOpen = 0x10
        /// 中継 → ホスト: 参加者からの中身 [0x11][u32 guestId][payload]
        case guestData = 0x11
        /// 中継 → ホスト: 参加者が切れた [0x12][u32 guestId]
        case guestClose = 0x12
        /// ホスト → 中継: 参加者へ送る [0x21][u32 guestId][payload]
        case send = 0x21
        /// ホスト → 中継: 参加者を切る（close 4002）[0x22][u32 guestId]
        case kick = 0x22
    }

    static let headerBytes = 5

    /// 中継 → ホスト。
    enum ServerMessage: Equatable {
        case guestOpen(UInt32)
        case guestData(UInt32, Data)
        case guestClose(UInt32)
    }

    /// ホスト → 中継。
    enum HostMessage: Equatable {
        case send(UInt32, Data)
        case kick(UInt32)
    }

    static func encode(_ m: ServerMessage) -> Data {
        switch m {
        case .guestOpen(let id): return header(.guestOpen, id)
        case .guestData(let id, let payload): return header(.guestData, id, reserving: payload.count) + payload
        case .guestClose(let id): return header(.guestClose, id)
        }
    }

    static func encode(_ m: HostMessage) -> Data {
        switch m {
        case .send(let id, let payload): return header(.send, id, reserving: payload.count) + payload
        case .kick(let id): return header(.kick, id)
        }
    }

    /// 中継 → ホストのメッセージを読む（短すぎる・未知の種類・向きの違う種類は nil）。
    static func decodeServerMessage(_ data: Data) -> ServerMessage? {
        guard let (kind, id) = readHeader(data) else { return nil }
        switch kind {
        case .guestOpen: return .guestOpen(id)
        case .guestData: return .guestData(id, payload(data))
        case .guestClose: return .guestClose(id)
        case .send, .kick: return nil
        }
    }

    /// ホスト → 中継のメッセージを読む（中継の振る舞いを真似るテスト用の土台でも使う）。
    static func decodeHostMessage(_ data: Data) -> HostMessage? {
        guard let (kind, id) = readHeader(data) else { return nil }
        switch kind {
        case .send: return .send(id, payload(data))
        case .kick: return .kick(id)
        case .guestOpen, .guestData, .guestClose: return nil
        }
    }

    /// maxBytes 以下に分ける（空なら空の配列）。
    static func chunks(_ data: Data, maxBytes: Int) -> [Data] {
        precondition(maxBytes > 0)
        guard !data.isEmpty else { return [] }
        var out: [Data] = []
        out.reserveCapacity((data.count + maxBytes - 1) / maxBytes)
        var i = data.startIndex
        while i < data.endIndex {
            let end = min(i + maxBytes, data.endIndex)
            out.append(data.subdata(in: i..<end))
            i = end
        }
        return out
    }

    private static func header(_ kind: Kind, _ id: UInt32, reserving extra: Int = 0) -> Data {
        var d = Data(capacity: headerBytes + extra)
        d.append(kind.rawValue)
        var be = id.bigEndian
        withUnsafeBytes(of: &be) { d.append(contentsOf: $0) }
        return d
    }

    private static func readHeader(_ data: Data) -> (Kind, UInt32)? {
        guard data.count >= headerBytes, let kind = Kind(rawValue: data[data.startIndex]) else { return nil }
        let s = data.startIndex
        let id = UInt32(data[s + 1]) << 24 | UInt32(data[s + 2]) << 16 | UInt32(data[s + 3]) << 8 | UInt32(data[s + 4])
        return (kind, id)
    }

    private static func payload(_ data: Data) -> Data {
        data.subdata(in: (data.startIndex + headerBytes)..<data.endIndex)
    }
}

// MARK: - close コード

/// 中継が接続を閉じる理由（WebSocket の close コード）。
enum RelayCloseCode: Int, CaseIterable {
    case normal = 1000
    case goingAway = 1001
    /// 不正な形式（短すぎる・未知の種類）。
    case unsupportedData = 1003
    /// 1 メッセージが 256 KiB を超えた。
    case messageTooBig = 1009
    /// ホストが閉じた・切れた（参加者全員がこれで閉じられる）。
    case hostLeft = 4001
    /// ホストが KICK した。
    case closedByHost = 4002
    /// その部屋コードにホストがいない。
    case noRoom = 4004
    /// 参加者が 32 人に達している。
    case roomFull = 4008
    /// その部屋コードには既にホストがいる。
    case roomTaken = 4009
    /// 中継の版数（rv）が合わない。
    case relayVersion = 4010
    /// 同じ鍵で戻ってきた新しいホストの接続に入れ替えられた（古いホストの接続がこれで閉じられる）。
    case hostReplaced = 4011

    /// 中継が close の reason に入れる名前。
    var reasonName: String {
        switch self {
        case .normal: return "normal"
        case .goingAway: return "going_away"
        case .unsupportedData: return "malformed"
        case .messageTooBig: return "message_too_big"
        case .hostLeft: return "host_left"
        case .closedByHost: return "closed_by_host"
        case .noRoom: return "no_room"
        case .roomFull: return "room_full"
        case .roomTaken: return "room_taken"
        case .relayVersion: return "relay_version"
        case .hostReplaced: return "host_replaced"
        }
    }

    /// 利用者向けの文言。
    var message: String {
        switch self {
        case .normal, .goingAway:
            return L("中継サーバーとの接続が終了しました", "The relay server closed the connection")
        case .unsupportedData:
            return L("中継サーバーが不正なデータを拒否しました", "The relay server rejected malformed data")
        case .messageTooBig:
            return L("送信データが大きすぎるため中継サーバーに切断されました", "Disconnected by the relay server: message too large")
        case .hostLeft:
            return L("ホストとの接続が切れました（ホストが退出したか、通信が途切れました）",
                     "Lost the host (the host left or their connection dropped)")
        case .closedByHost:
            return L("ホストに切断されました", "The host disconnected you")
        case .noRoom:
            return L("部屋が見つかりません（コードを確かめてください）", "Room not found (check the code)")
        case .roomFull:
            return L("部屋が満員です（中継の上限）", "The room is full (relay limit)")
        case .roomTaken:
            return L("この部屋コードは使われています", "That room code is already in use")
        case .relayVersion:
            return L("中継サーバーとアプリの版が合いません（アプリを更新してください）",
                     "The relay server does not support this app version (please update)")
        case .hostReplaced:
            return L("部屋の接続が新しい接続に入れ替わりました", "The room's connection was replaced by a newer one")
        }
    }

    /// close コードから文言を作る（知らないコードは一般的な文言）。
    static func message(forCode code: Int) -> String {
        RelayCloseCode(rawValue: code)?.message
            ?? L("中継サーバーとの接続が切れました（コード \(code)）", "Lost connection to the relay server (code \(code))")
    }

    /// 繋がらなかった時の文言（HTTP の応答があればそれで分ける）。
    static func connectFailureMessage(httpStatus: Int?, detail: String?) -> String {
        switch httpStatus {
        case 400?: return L("部屋コードが正しくありません", "Invalid room code")
        case 404?: return L("中継サーバーが見つかりません（URL を確かめてください）", "Relay server not found (check the URL)")
        case let s? where s >= 500: return L("中継サーバーが応答しません（HTTP \(s)）", "The relay server is not responding (HTTP \(s))")
        case let s?: return L("中継サーバーに接続できませんでした（HTTP \(s)）", "Could not connect to the relay server (HTTP \(s))")
        case nil:
            if let detail, !detail.isEmpty {
                return L("中継サーバーに接続できませんでした（\(detail)）", "Could not connect to the relay server (\(detail))")
            }
            return L("中継サーバーに接続できませんでした（インターネット接続を確かめてください）",
                     "Could not connect to the relay server (check your internet connection)")
        }
    }
}

// MARK: - WebSocket の抽象

/// 中継への WebSocket（URLSession の実装と、テスト用の InMemoryRelay がある）。
/// コールバックはメインアクターで呼ぶ。自分で close() した後はどのコールバックも呼ばない。
@MainActor
protocol RelaySocket: AnyObject {
    var onOpen: (() -> Void)? { get set }
    var onBinary: ((Data) -> Void)? { get set }
    var onText: ((String) -> Void)? { get set }
    /// 中継が閉じた（close コードと理由）。
    var onClose: ((Int, String) -> Void)? { get set }
    /// 繋がらなかった・close フレーム無しで切れた（利用者向けの文言）。
    var onFailure: ((String) -> Void)? { get set }
    func connect()
    func send(binary: Data)
    func send(text: String)
    func close(code: Int, reason: String)
}

/// URL から中継への接続を作る（テストは InMemoryRelay が作る）。
typealias RelaySocketFactory = @MainActor (URL) -> RelaySocket
/// 遅らせて実行する（再接続のバックオフ。テストは手動で進める）。
typealias RelayScheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void

enum RelayDefaults {
    static let socketFactory: RelaySocketFactory = { URLSessionRelaySocket(url: $0) }
    static let scheduler: RelayScheduler = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
    }
}

/// URLSessionWebSocketTask の実装。受信・状態は URLSession のキューで受けてメインへ移す。
@MainActor
final class URLSessionRelaySocket: RelaySocket {
    let url: URL
    var onOpen: (() -> Void)?
    var onBinary: ((Data) -> Void)?
    var onText: ((String) -> Void)?
    var onClose: ((Int, String) -> Void)?
    var onFailure: ((String) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var opened = false
    private var finished = false

    init(url: URL) {
        self.url = url
    }

    func connect() {
        guard task == nil, !finished else { return }
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        let proxy = Proxy()
        proxy.owner = self
        let session = URLSession(configuration: config, delegate: proxy, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        // 中継の上限（256 KiB）+ ヘッダより大きく（アプリは 64 KiB 以下で送るが、受信は余裕を持たせる）
        task.maximumMessageSize = 2 * OnlineRelayConfig.serverMaxMessageBytes
        self.session = session
        self.task = task
        task.resume()
        receiveNext()
        // 開かないまま待たせない（相手が見つからない・回線が無い）
        DispatchQueue.main.asyncAfter(deadline: .now() + OnlineRelayConfig.connectTimeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.opened, !self.finished else { return }
                self.fail(L("中継サーバーに接続できませんでした（時間切れ）", "Could not connect to the relay server (timed out)"))
            }
        }
    }

    func send(binary: Data) {
        guard !finished, let task else { return }
        task.send(.data(binary)) { [weak self] error in
            guard let error else { return }
            let text = error.localizedDescription
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.sendFailed(text) } }
        }
    }

    func send(text: String) {
        guard !finished, let task else { return }
        task.send(.string(text)) { _ in }
    }

    func close(code: Int, reason: String) {
        guard !finished else { return }
        finished = true
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure
        task?.cancel(with: closeCode, reason: reason.data(using: .utf8))
        session?.finishTasksAndInvalidate()
        task = nil
        session = nil
    }

    private func receiveNext() {
        guard let task else { return }
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, !self.finished, self.task === task else { return }
                    switch result {
                    case .success(let message):
                        // 受信できた = 開いている（開いた通知より先に届くことがある）
                        self.handleOpen()
                        switch message {
                        case .data(let d): self.onBinary?(d)
                        case .string(let s): self.onText?(s)
                        @unknown default: break
                        }
                        if !self.finished { self.receiveNext() }
                    case .failure:
                        // 閉じた理由（close コード）は delegate（didClose / didComplete）で届くのでそちらに任せる。
                        // どちらも来ない時の保険
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                            MainActor.assumeIsolated { self?.fail(RelayCloseCode.connectFailureMessage(httpStatus: nil, detail: nil)) }
                        }
                    }
                }
            }
        }
    }

    fileprivate func handleOpen() {
        guard !opened, !finished else { return }
        opened = true
        onOpen?()
    }

    fileprivate func handleClose(code: Int, reason: String) {
        guard !finished else { return }
        finish()
        onClose?(code, reason)
    }

    fileprivate func handleComplete(error: String?, httpStatus: Int?, closeCode: Int, reason: String) {
        guard !finished else { return }
        if closeCode != URLSessionWebSocketTask.CloseCode.invalid.rawValue {
            handleClose(code: closeCode, reason: reason)
            return
        }
        if !opened {
            fail(RelayCloseCode.connectFailureMessage(httpStatus: httpStatus == 101 ? nil : httpStatus, detail: error))
        } else {
            fail(L("中継サーバーとの接続が切れました", "Lost connection to the relay server") + (error.map { "（\($0)）" } ?? ""))
        }
    }

    private func sendFailed(_ text: String) {
        guard !finished else { return }
        fail(L("中継サーバーへの送信に失敗しました（\(text)）", "Failed to send to the relay server (\(text))"))
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        finish()
        onFailure?(message)
    }

    private func finish() {
        finished = true
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }

    /// URLSession の delegate（URLSession は delegate を強く持つので、ソケットは弱く持つ）。
    private final class Proxy: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
        weak var owner: URLSessionRelaySocket?

        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.owner?.handleOpen() }
            }
        }

        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
            let code = closeCode.rawValue
            let text = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.owner?.handleClose(code: code, reason: text) }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let status = (task.response as? HTTPURLResponse)?.statusCode
            let ws = task as? URLSessionWebSocketTask
            let code = ws?.closeCode.rawValue ?? URLSessionWebSocketTask.CloseCode.invalid.rawValue
            let reason = ws?.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let message = error?.localizedDescription
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.owner?.handleComplete(error: message, httpStatus: status, closeCode: code, reason: reason)
                }
            }
        }
    }
}

// MARK: - 中継の状態

/// ホストの中継の状態（画面の表示と再試行の判断）。
enum OnlineRelayStatus: Equatable {
    /// 繋いでいる（部屋コードの確保を待っている）。
    case connecting
    /// 部屋コードで参加を受け付けている。
    case ready
    /// 切れたので繋ぎ直している（直近の理由）。
    case reconnecting(String)
    /// 諦めた（画面の「再試行」で繋ぎ直す）。
    case failed(String)

    var isReady: Bool { self == .ready }
}

// MARK: - ホスト

/// ホスト側の中継。role=host で繋ぎ、参加者ごとの仮想接続を onAccept で渡す（OnlineSession.accept に入る）。
/// 切れたら全仮想接続を failed にし、同じコードで繋ぎ直す（指数バックオフ。部屋＝OnlineSession は残す）。
/// コードが使われていたら: 新しいコードなら作り直す（最大 3 回）。確保していたコードへの再接続なら、中継が古い接続の
/// 切断に気づくまで同じコードで数回待ってから作り直す。-relayCode で決めたコードは作り直さない。
@MainActor
final class RelayHostLink {
    let baseURL: URL
    /// 部屋コード。
    private(set) var code: String
    /// 決められたコード（-relayCode。使われていても作り直さない）。
    let fixedCode: Bool
    private(set) var status: OnlineRelayStatus = .connecting
    /// 参加者が繋いだ（仮想接続。未開始のまま渡す）。
    var onAccept: ((RelayGuestEndpoint) -> Void)?
    var onStatusChange: ((OnlineRelayStatus) -> Void)?
    var onCodeChange: ((String) -> Void)?
    /// コードの作り方（テストで差し替える）。
    var makeCode: () -> String = { RelayRoomCode.generate() }
    /// テスト用: 単調時刻の供給（生存確認）。
    var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    private let makeSocket: RelaySocketFactory
    private let schedule: RelayScheduler
    private var socket: RelaySocket?
    private var endpoints: [UInt32: RelayGuestEndpoint] = [:]
    private var started = false
    private var stopped = false
    /// いまのソケットで部屋を確保できた（pong か中継からのバイナリが届いた、または開いて confirmDelay 経った）。
    private var confirmed = false
    /// このコードで部屋を確保したことがある（再接続ではコードを保つ）。
    private var codeEstablished = false
    /// 続けて失敗した回数（確保できたら 0）。
    private var attempt = 0
    private var regenerations = 0
    private var roomTakenRetries = 0
    /// 接続の世代（予約した再接続・確保の判定が古いソケットのものなら捨てる）。
    private var generation = 0
    private var keepaliveTimer: Timer?
    private var lastInbound: TimeInterval = 0
    /// 再接続の鍵（この部屋の間は同じ。中継に渡る hk）。端末の外へは中継にしか出ない。参加者には渡らない。
    private let resumeKey = RelayHostLink.makeResumeKey()

    init(baseURL: URL, code: String? = nil,
         makeSocket: @escaping RelaySocketFactory = RelayDefaults.socketFactory,
         schedule: @escaping RelayScheduler = RelayDefaults.scheduler) {
        self.baseURL = baseURL
        if let code, RelayRoomCode.isValid(code) {
            self.code = code
            fixedCode = true
        } else {
            self.code = RelayRoomCode.generate()
            fixedCode = false
        }
        self.makeSocket = makeSocket
        self.schedule = schedule
    }

    /// 繋いでいる参加者の数（仮想接続）。
    var guestCount: Int { endpoints.count }

    /// 128 ビットの乱数（16 進 32 文字。中継の hk の形式: 英数・_・- の 16〜64 文字）。
    private static func makeResumeKey() -> String {
        var rng = SystemRandomNumberGenerator()
        return (0..<2).map { _ in String(UInt64.random(in: .min ... .max, using: &rng), radix: 16).leftPadded(to: 16) }.joined()
    }

    func start() {
        guard !started, !stopped else { return }
        started = true
        if !fixedCode { code = makeCode() }
        onCodeChange?(code)
        connect()
    }

    /// 画面の「再試行」: 待ちを捨てて今すぐ繋ぎ直す。
    func retry() {
        guard started, !stopped else { return }
        if socket != nil, status == .ready { return }
        closeSocket()
        attempt = 0
        roomTakenRetries = 0
        if case .failed = status {
            regenerations = 0
            setStatus(.connecting)
        }
        connect()
    }

    /// 中継を閉じる（部屋を閉じる時）。中継は参加者全員を host_left で閉じる。
    func stop() {
        guard !stopped else { return }
        stopped = true
        generation += 1
        closeSocket()
        let lost = Array(endpoints.values)
        endpoints.removeAll()
        for e in lost { e.linkLost(L("部屋を閉じました", "The room was closed")) }
    }

    /// 生存確認（15 秒毎。テストから直接呼べる）: 長く何も届かなければ繋ぎ直し、そうでなければ ping を送る。
    func keepaliveTick() {
        guard let socket, !stopped else { return }
        if uptime() - lastInbound > OnlineRelayConfig.silenceTimeout {
            closeSocket()
            socketEnded(closeCode: nil, reason: L("中継サーバーから応答がありません", "The relay server stopped responding"))
            return
        }
        socket.send(text: "ping")
    }

    // MARK: 接続

    private func connect() {
        generation += 1
        let gen = generation
        confirmed = false
        let s = makeSocket(OnlineRelayConfig.roomURL(base: baseURL, code: code, role: .host, resumeKey: resumeKey))
        socket = s
        if attempt == 0 && !codeEstablished { setStatus(.connecting) }
        s.onOpen = { [weak self, weak s] in
            guard let self, let s, self.socket === s else { return }
            self.opened(generation: gen)
        }
        s.onBinary = { [weak self, weak s] data in
            guard let self, let s, self.socket === s else { return }
            self.received(data)
        }
        s.onText = { [weak self, weak s] _ in
            guard let self, let s, self.socket === s else { return }
            // pong（中継の自動応答）
            self.lastInbound = self.uptime()
            self.confirm()
        }
        s.onClose = { [weak self, weak s] code, _ in
            guard let self, let s, self.socket === s else { return }
            self.dropSocket()
            self.socketEnded(closeCode: code, reason: RelayCloseCode.message(forCode: code))
        }
        s.onFailure = { [weak self, weak s] reason in
            guard let self, let s, self.socket === s else { return }
            self.dropSocket()
            self.socketEnded(closeCode: nil, reason: reason)
        }
        s.connect()
    }

    private func opened(generation gen: Int) {
        lastInbound = uptime()
        startKeepalive()
        // 確保の確認: pong が届けば確保できている（使われているコードは開いた直後に 4009 で閉じられる）
        socket?.send(text: "ping")
        schedule(OnlineRelayConfig.confirmDelay) { [weak self] in
            guard let self, self.generation == gen, self.socket != nil else { return }
            self.confirm()
        }
    }

    private func confirm() {
        guard !confirmed, socket != nil else { return }
        confirmed = true
        codeEstablished = true
        attempt = 0
        roomTakenRetries = 0
        regenerations = 0
        setStatus(.ready)
    }

    private func received(_ data: Data) {
        lastInbound = uptime()
        confirm()
        // 知らない形式は捨てる（中継の版が上がって種類が増えても落ちない）
        guard let m = RelayWire.decodeServerMessage(data) else { return }
        switch m {
        case .guestOpen(let id):
            endpoints.removeValue(forKey: id)?.linkLost(L("同じ参加者 ID で繋ぎ直されました", "Replaced by a new connection"))
            let e = RelayGuestEndpoint(guestID: id, link: self)
            endpoints[id] = e
            if let onAccept {
                onAccept(e)
            } else {
                e.close()
            }
        case .guestData(let id, let payload):
            endpoints[id]?.receive(payload)
        case .guestClose(let id):
            endpoints.removeValue(forKey: id)?.remoteClosed()
        }
    }

    /// 仮想接続からの送信（64 KiB 以下に分けて SEND で送る）。
    fileprivate func send(_ data: Data, to guestID: UInt32) {
        guard let socket, endpoints[guestID] != nil else { return }
        for chunk in RelayWire.chunks(data, maxBytes: OnlineRelayConfig.chunkBytes - RelayWire.headerBytes) {
            socket.send(binary: RelayWire.encode(.send(guestID, chunk)))
        }
    }

    /// 仮想接続を閉じる（KICK。中継はその参加者を 4002 で閉じる）。
    fileprivate func kick(_ guestID: UInt32) {
        guard endpoints.removeValue(forKey: guestID) != nil else { return }
        socket?.send(binary: RelayWire.encode(.kick(guestID)))
    }

    // MARK: 切断・再接続

    private func closeSocket() {
        let s = socket
        dropSocket()
        s?.close(code: RelayCloseCode.normal.rawValue, reason: "bye")
    }

    private func dropSocket() {
        socket = nil
        confirmed = false
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
    }

    private func socketEnded(closeCode: Int?, reason: String) {
        guard !stopped else { return }
        // 中継は参加者全員を host_left で閉じるので、仮想接続もすべて切れる（OnlineSession が AI 引き継ぎ・退出を処理する）
        let lost = Array(endpoints.values)
        endpoints.removeAll()
        for e in lost { e.linkLost(L("中継の接続が切れました", "The relay connection dropped")) }

        switch closeCode.flatMap(RelayCloseCode.init(rawValue:)) {
        case .relayVersion?:
            setStatus(.failed(reason))
        case .roomTaken?:
            if !fixedCode && !codeEstablished {
                // 新しいコードが偶然使われていた: すぐ作り直す
                regenerateOrFail(reason)
            } else if !fixedCode && roomTakenRetries >= OnlineRelayConfig.roomTakenSameCodeRetries {
                // 確保していたコードを中継がまだ古い接続のものとしている: 待ちきれないので作り直す
                regenerateOrFail(reason)
            } else {
                roomTakenRetries += 1
                scheduleReconnect(reason)
            }
        default:
            scheduleReconnect(reason)
        }
    }

    private func regenerateOrFail(_ reason: String) {
        guard regenerations < OnlineRelayConfig.maxCodeRegenerations else {
            setStatus(.failed(L("部屋コードを確保できませんでした", "Could not reserve a room code")))
            return
        }
        regenerations += 1
        roomTakenRetries = 0
        codeEstablished = false
        attempt = 0
        code = makeCode()
        onCodeChange?(code)
        connect()
    }

    private func scheduleReconnect(_ reason: String) {
        attempt += 1
        guard attempt <= OnlineRelayConfig.maxReconnectAttempts else {
            setStatus(.failed(reason))
            return
        }
        setStatus(.reconnecting(reason))
        let delay = min(OnlineRelayConfig.reconnectMaxDelay,
                        OnlineRelayConfig.reconnectBaseDelay * pow(2, Double(attempt - 1)))
        let gen = generation
        schedule(delay) { [weak self] in
            guard let self, !self.stopped, self.generation == gen, self.socket == nil else { return }
            self.connect()
        }
    }

    private func setStatus(_ s: OnlineRelayStatus) {
        guard status != s else { return }
        status = s
        onStatusChange?(s)
    }

    private func startKeepalive() {
        keepaliveTimer?.invalidate()
        let t = Timer(timeInterval: OnlineRelayConfig.keepaliveInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepaliveTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        keepaliveTimer = t
    }
}

/// ホスト側の仮想接続（中継の向こうの参加者 1 人）。OnlineSession からは LAN の接続と同じに見える。
@MainActor
final class RelayGuestEndpoint: OnlineConnection {
    let id = UUID()
    /// 中継が振った参加者 ID（部屋の寿命の間は再利用されない）。
    let guestID: UInt32
    private(set) var state: OnlineConnectionState = .connecting
    var remoteDescription: String { L("中継 #\(guestID)", "Relay #\(guestID)") }
    var onMessage: ((OnlineMessage) -> Void)?
    var onStateChange: ((OnlineConnectionState) -> Void)?

    private weak var link: RelayHostLink?
    private var framer = OnlineFramer(maxMessageBytes: OnlineRelayConfig.guestToHostMaxMessageBytes)
    /// 開始前に届いた中身（開始で流す）。
    private var pending: [Data] = []

    init(guestID: UInt32, link: RelayHostLink) {
        self.guestID = guestID
        self.link = link
    }

    private var isActive: Bool { state == .connecting || state == .ready }

    func start() {
        guard state == .connecting else { return }
        state = .ready
        onStateChange?(.ready)
        let queued = pending
        pending.removeAll()
        for d in queued where state == .ready { feed(d) }
    }

    /// 中継から届いた中身（GUEST_DATA）。
    func receive(_ data: Data) {
        switch state {
        case .connecting: pending.append(data)
        case .ready: feed(data)
        default: break
        }
    }

    private func feed(_ data: Data) {
        do {
            for m in try framer.feed(data) {
                guard state == .ready else { return }
                onMessage?(m)
            }
        } catch {
            link?.kick(guestID)
            fail(L("受信データが壊れています", "Corrupted data received"))
        }
    }

    func send(_ message: OnlineMessage) {
        guard state == .ready, let data = try? OnlineFramer.encode(message) else { return }
        send(encoded: data)
    }

    func send(encoded data: Data) {
        guard state == .ready else { return }
        link?.send(data, to: guestID)
    }

    func close() {
        guard isActive else { return }
        state = .closed
        link?.kick(guestID)
        onStateChange?(.closed)
    }

    /// 参加者が切れた（GUEST_CLOSE）。
    func remoteClosed() {
        guard isActive else { return }
        state = .closed
        onStateChange?(.closed)
    }

    /// ホストと中継の接続が切れた。
    func linkLost(_ reason: String) {
        guard isActive else { return }
        state = .failed(reason)
        onStateChange?(state)
    }

    private func fail(_ reason: String) {
        guard isActive else { return }
        state = .failed(reason)
        onStateChange?(state)
    }
}

// MARK: - 参加者

/// 参加者側の中継の接続（role=guest）。受信したバイナリはそのまま OnlineFramer へ、送信は 64 KiB 以下に分けて送る。
/// 中継に閉じられたら close コードを利用者向けの文言にして failed に載せる（no_room →「部屋が見つかりません」等）。
@MainActor
final class RelayGuestConnection: OnlineConnection {
    let id = UUID()
    /// 部屋コード（正規化済み）。
    let code: String
    let baseURL: URL
    private(set) var state: OnlineConnectionState = .connecting
    var remoteDescription: String { L("部屋コード \(RelayRoomCode.display(code))", "Room code \(RelayRoomCode.display(code))") }
    var onMessage: ((OnlineMessage) -> Void)?
    var onStateChange: ((OnlineConnectionState) -> Void)?

    private let makeSocket: RelaySocketFactory
    private var socket: RelaySocket?
    private var framer = OnlineFramer()
    private var started = false
    private var keepaliveTimer: Timer?

    init(code: String, baseURL: URL = OnlineRelayConfig.baseURL,
         makeSocket: @escaping RelaySocketFactory = RelayDefaults.socketFactory) {
        self.code = code
        self.baseURL = baseURL
        self.makeSocket = makeSocket
    }

    private var isActive: Bool { state == .connecting || state == .ready }

    func start() {
        guard !started else { return }
        started = true
        guard RelayRoomCode.isValid(code) else {
            fail(L("部屋コードが正しくありません", "Invalid room code"))
            return
        }
        let s = makeSocket(OnlineRelayConfig.roomURL(base: baseURL, code: code, role: .guest))
        socket = s
        s.onOpen = { [weak self] in self?.opened() }
        s.onBinary = { [weak self] data in self?.feed(data) }
        s.onText = { _ in }   // pong
        s.onClose = { [weak self] code, _ in
            self?.socket = nil
            self?.fail(RelayCloseCode.message(forCode: code))
        }
        s.onFailure = { [weak self] reason in
            self?.socket = nil
            self?.fail(reason)
        }
        s.connect()
    }

    private func opened() {
        guard state == .connecting else { return }
        state = .ready
        let t = Timer(timeInterval: OnlineRelayConfig.keepaliveInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendKeepalive() }
        }
        RunLoop.main.add(t, forMode: .common)
        keepaliveTimer = t
        onStateChange?(.ready)
    }

    /// テキストの ping（中継が pong を返す。NAT のタイムアウト対策。テストから直接呼べる）。
    func sendKeepalive() {
        guard state == .ready else { return }
        socket?.send(text: "ping")
    }

    private func feed(_ data: Data) {
        guard state == .ready else { return }
        do {
            for m in try framer.feed(data) {
                guard state == .ready else { return }
                onMessage?(m)
            }
        } catch {
            fail(L("受信データが壊れています", "Corrupted data received"))
        }
    }

    func send(_ message: OnlineMessage) {
        guard state == .ready, let data = try? OnlineFramer.encode(message) else { return }
        send(encoded: data)
    }

    func send(encoded data: Data) {
        guard state == .ready, let socket else { return }
        for chunk in RelayWire.chunks(data, maxBytes: OnlineRelayConfig.chunkBytes) {
            socket.send(binary: chunk)
        }
    }

    func close() {
        guard isActive else { return }
        state = .closed
        stopSocket()
        onStateChange?(.closed)
    }

    private func fail(_ reason: String) {
        guard isActive else { return }
        state = .failed(reason)
        stopSocket()
        onStateChange?(state)
    }

    private func stopSocket() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        let s = socket
        socket = nil
        s?.close(code: RelayCloseCode.normal.rawValue, reason: "bye")
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}
