import Foundation

// 担当: online。フレンド機能の型（フレンドコード・フレンドのリンク・受信箱のメッセージ）。設計は relay/README.md「フレンドの受信箱」。
//
// アカウントは作らない。端末ごとに「フレンドコード」（公開の ID。8 文字）と「受信箱の鍵」（本人だけが持つ秘密）を作り、
// 中継サーバーの受信箱（コード 1 つ = 1 つ。最初に繋いだ鍵が持ち主になる）でフレンドからの招待・申請を受け取る。

/// フレンド（承認済みの相手）。
struct Friend: Codable, Equatable, Identifiable {
    var code: String
    var name: String
    var addedAt: Date

    var id: String { code }
}

/// フレンドコード: 8 文字。部屋コードと同じ 31 文字（紛らわしい I L O 0 1 を除く）。端末の乱数で作る。
enum FriendCode {
    static let length = 8
    private static let alphabetSet = Set(RelayRoomCode.alphabet)

    static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in RelayRoomCode.alphabet[Int.random(in: 0..<RelayRoomCode.alphabet.count, using: &rng)] })
    }

    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy { alphabetSet.contains($0) }
    }

    /// 表示用（4 文字ずつ空ける）。
    static func display(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(4)) \(code.suffix(4))"
    }

    enum InputError: Error, Equatable {
        case empty
        case tooShort(Int)
        case tooLong(Int)
        case ambiguous(String)
        case invalid(String)

        var message: String {
            switch self {
            case .empty:
                return L("フレンドコードを入力してください", "Enter a friend code")
            case .tooShort(let n):
                return L("フレンドコードは \(FriendCode.length) 文字です（あと \(FriendCode.length - n) 文字）",
                         "Friend codes have \(FriendCode.length) characters (\(FriendCode.length - n) more)")
            case .tooLong:
                return L("フレンドコードは \(FriendCode.length) 文字です", "Friend codes have \(FriendCode.length) characters")
            case .ambiguous(let chars):
                return L("「\(chars)」はフレンドコードに使われません（I・L・O・0・1 は使いません）",
                         "\"\(chars)\" never appears in friend codes (I, L, O, 0 and 1 are not used)")
            case .invalid(let chars):
                return L("「\(chars)」はフレンドコードに使えない文字です", "\"\(chars)\" cannot appear in a friend code")
            }
        }
    }

    /// 入力を正規化して確かめる（部屋コードと同じ規則: リンク貼り付け・全角 → 半角・大文字・区切り除去。ちょうど 8 文字）。
    static func parse(_ input: String) -> Result<String, InputError> {
        let s = RelayRoomCode.normalized(input)
        guard !s.isEmpty else { return .failure(.empty) }
        let bad = s.filter { !alphabetSet.contains($0) }
        let confusing = bad.filter { RelayRoomCode.ambiguous.contains($0) }
        if !confusing.isEmpty { return .failure(.ambiguous(String(confusing))) }
        if !bad.isEmpty { return .failure(.invalid(String(bad))) }
        if s.count < length { return .failure(.tooShort(s.count)) }
        if s.count > length { return .failure(.tooLong(s.count)) }
        return .success(s)
    }

    /// 入力欄の表示用（正規化して 8 文字までに切る。使えない文字は残してエラーを見せる）。
    static func cleaned(_ input: String) -> String {
        String(RelayRoomCode.normalized(input).prefix(length))
    }
}

/// 受信箱の鍵（URL の key。中継の正規表現 `^[A-Za-z0-9_-]{16,64}$`）。
enum FriendInboxKey {
    static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<32).map { _ in chars[Int.random(in: 0..<chars.count, using: &rng)] })
    }

    static func isValid(_ key: String) -> Bool {
        (16...64).contains(key.count) && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}

/// フレンドのリンク `velstria://friend?code=XXXXXXXX&name=…`（URL スキームは招待リンクと同じ）。
struct FriendLink: Equatable {
    var code: String
    var name: String

    init(code: String, name: String) {
        self.code = code
        self.name = name
    }

    /// 開かれた URL を読む（スキーム・動作・コードが違えば nil）。
    init?(url: URL) {
        guard url.scheme?.lowercased() == OnlineJoinLink.scheme else { return nil }
        let action = (url.host ?? url.pathComponents.first { $0 != "/" } ?? "").lowercased()
        guard action == "friend", let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = comps.queryItems ?? []
        guard let raw = items.first(where: { $0.name.lowercased() == "code" })?.value,
              case .success(let code) = FriendCode.parse(raw) else { return nil }
        self.code = code
        self.name = FriendNames.clean(items.first { $0.name.lowercased() == "name" }?.value ?? "")
    }

    var url: URL {
        var c = URLComponents()
        c.scheme = OnlineJoinLink.scheme
        c.host = "friend"
        c.queryItems = [URLQueryItem(name: "code", value: code)] + (name.isEmpty ? [] : [URLQueryItem(name: "name", value: name)])
        return c.url!
    }

    /// 共有の文面（コード + リンク）。
    static func shareText(code: String, name: String) -> String {
        let link = FriendLink(code: code, name: name).url.absoluteString
        return L("VELSIA でフレンドになろう！\n\(name) のフレンドコード: \(FriendCode.display(code))\n（アプリの「オンライン」→「フレンド」に入力）\n\(link)",
                 "Be my friend on VELSIA!\n\(name)'s friend code: \(FriendCode.display(code))\n(Online → Friends in the app)\n\(link)")
    }
}

/// 相手が名乗った表示名の整形（受信箱の中身は相手が自由に書けるので、制御文字を除き長さを揃える）。
enum FriendNames {
    static func clean(_ raw: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(.newlines).union(.illegalCharacters)
        let scalars = raw.unicodeScalars.filter { !forbidden.contains($0) }
        let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(PlayerNameRules.maxLength))
    }

    /// 空なら代わりの名前（表示用）。
    static func display(_ name: String) -> String {
        name.isEmpty ? L("フレンド", "Friend") : name
    }
}

// MARK: - 受信箱のメッセージ

/// フレンド同士で送り合う中身（中継は解釈しない JSON）。知らない種類は無視する（将来の版との互換）。
struct InboxPayload: Codable, Equatable {
    enum Kind: String {
        /// フレンド申請（name = 申請者の表示名）。
        case friendRequest
        /// 申請の承認（name = 承認した人の表示名）。
        case friendAccept
        /// パーティの招待（room = 部屋コード、roomName = 部屋の名前、name = 招待した人）。
        case partyInvite
        /// 招待への返事（room = 招待された部屋、answer = Answer、wait = 待ってほしい秒数）。
        case inviteReply
    }

    enum Answer: String {
        case accept
        case decline
        /// 少し待ってほしい（wait 秒後に参加する）。
        case wait
        /// 試合中などで受けられない。
        case busy
    }

    var k: String
    var name: String?
    var room: String?
    var roomName: String?
    var answer: String?
    var wait: Int?

    var kind: Kind? { Kind(rawValue: k) }

    init(_ kind: Kind, name: String? = nil, room: String? = nil, roomName: String? = nil,
         answer: Answer? = nil, wait: Int? = nil) {
        self.k = kind.rawValue
        self.name = name
        self.room = room
        self.roomName = roomName
        self.answer = answer?.rawValue
        self.wait = wait
    }
}

/// 中継 → アプリ。
enum InboxServerMessage: Equatable {
    case hello(code: String)
    case message(from: String, payload: InboxPayload)
    case ack(id: Int, result: InboxSendResult)
    case presence(online: [String])

    private struct Wire: Decodable {
        var t: String
        var code: String?
        var from: String?
        var m: InboxPayload?
        var id: Int?
        var result: String?
        var online: [String]?
    }

    /// テキストのメッセージを読む（形式が違う・知らない種類は nil）。
    static func decode(_ text: String) -> InboxServerMessage? {
        guard let data = text.data(using: .utf8), let w = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        switch w.t {
        case "hello":
            guard let code = w.code else { return nil }
            return .hello(code: code)
        case "msg":
            guard let from = w.from, FriendCode.isValid(from), let m = w.m else { return nil }
            return .message(from: from, payload: m)
        case "ack":
            guard let id = w.id, let r = w.result.flatMap(InboxSendResult.init(rawValue:)) else { return nil }
            return .ack(id: id, result: r)
        case "presence":
            return .presence(online: (w.online ?? []).filter(FriendCode.isValid))
        default:
            return nil
        }
    }
}

/// 送信の結果（中継の ack）。
enum InboxSendResult: String, Equatable {
    /// 相手の受信箱に渡した（相手がアプリを開いている）。
    case delivered
    /// 相手が不在なので預かった（申請だけ。相手が繋いだ時に渡る）。
    case queued
    /// 相手が不在で、預けられない種類（招待）。または送りすぎで断られた。
    case offline
    /// こちらの受信箱が繋がっていない（中継の ack ではなくアプリが作る）。
    case notConnected
}

/// アプリ → 中継（JSON 文字列）。
enum InboxClientMessage {
    static func send(to code: String, id: Int, payload: InboxPayload, queue: Bool) -> String? {
        struct Wire: Encodable {
            var t = "send"
            var to: String
            var id: Int
            var queue: Bool?
            var m: InboxPayload
        }
        return encode(Wire(to: code, id: id, queue: queue ? true : nil, m: payload))
    }

    static func presence(codes: [String]) -> String? {
        struct Wire: Encodable {
            var t = "presence"
            var codes: [String]
        }
        return encode(Wire(codes: codes))
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
