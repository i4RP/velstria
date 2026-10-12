import Foundation

// 担当: online。オンライン機能の安全対策（App Review Guidelines 1.2 / 5.1）。画面は Screens/Online/OnlineSafetyViews.swift。
//
// - 同意: オンライン機能（フレンド・部屋コード・同じ Wi-Fi の対戦）は、コミュニティガイドラインと利用規約のオンラインの条項に
//   同意してから使える（OnlineAccess）。同意するまではフレンドの受信箱へも繋がない。13 歳未満と申告した人は使えない。
// - 不適切語のフィルタ: 他のプレイヤーに見える文字列（表示名・部屋名）を端末内の語表で判定する（ContentFilter）。
//   入力時（PlayerNameRules.validate）に弾き、受け取った側（ホストの名乗り・受信箱・部屋の状態）でも隠す。
//   判定は端末内だけで行い、中継サーバーは中身を検査しない（通信の秘密）。
// - 通報: 相手の表示名・フレンドコードなどを入れたメールの下書きを運営（FeatureFlags.supportEmail）宛てに作る（PlayerReportMail）。
// - ブロック: フレンドコード単位（Profile.blockedPlayers。FriendHub.block）。申請・招待を受け取らず、ホストなら部屋に入れない。

// MARK: - 使えるか

/// オンライン機能を使えるか。
enum OnlineAccess: Equatable {
    case available
    /// コミュニティガイドラインと利用規約（オンラインの条項）への同意がまだ（または版が上がった）。
    case needsConsent
    /// 13 歳未満と申告した（オンライン機能は使えない）。
    case ageRestricted
    /// 機能フラグで無効。
    case disabled

    static func status(for profile: Profile, enabled: Bool = FeatureFlags.lanMatch) -> OnlineAccess {
        guard enabled else { return .disabled }
        // 年齢の申告前（オンボーディング前）も 13 歳未満として扱う（課金の上限と同じ考え方）
        if (profile.ageBracket ?? .under13) == .under13 { return .ageRestricted }
        if profile.acceptedOnlineRulesVersion < FeatureFlags.currentOnlineRulesVersion { return .needsConsent }
        return .available
    }

    static var ageRestrictedMessage: String {
        L("13 歳未満の方は、オンライン機能（オンライン対戦・フレンド）を利用できません",
          "Online features (online matches and friends) are not available to players under 13")
    }
}

extension FriendHub {
    static var blockedMessage: String {
        L("ブロック中のプレイヤーです。設定 > プライバシー でブロックを解除してから申請してください",
          "You have blocked this player. Unblock them in Settings > Privacy before sending a request")
    }
}

// MARK: - 不適切語のフィルタ

/// 他のプレイヤーに見える文字列（表示名・部屋名）の不適切語の判定。
/// 正規化（全角 → 半角・小文字・カタカナ → ひらがな・記号と空白の除去・よくある数字の置き換え）してから、
/// 部分一致の語（誤判定の少ない語）と、単語として一致する語（短く、他の語の一部になりやすい語）を調べる。
enum ContentFilter {
    /// 部分一致で弾く語（正規化後）。ほかの語や実在の姓・地名に含まれる語（例: yamashita の "shit"、fukuda の "fuk"、
    /// badminton の "admin"、コロスケの「ころす」、Sexton・Essex の "sex"、Scunthorpe の "cunt"、Penistone の "penis"、
    /// Nazira の "nazi"、Slutsky の "slut"、公式戦の「公式」、大麻町の「大麻」）は入れず、単語の一致（words）で調べる。
    static let fragments: [String] = [
        // 英語: 卑語・差別語・性的な語
        "fuck", "bitch", "nigger", "nigga", "faggot", "whore", "pussy", "vagina",
        "porn", "hitler", "retard", "motherf", "asshole", "dickhead", "cocksuck", "bullshit",
        "shithead", "bastard", "wanker", "jizz", "titties", "killyourself", "chinpo",
        // 日本語（ひらがなに揃えた形と漢字）
        "死ね", "氏ね", "殺す", "ころしてやる", "ぶっころ", "殺害", "ちんこ", "ちんぽ", "まんこ", "おっぱい", "せっくす", "れいぷ", "強姦",
        "痴漢", "売春", "援交", "きちがい", "気違い", "基地外", "穢多", "支那", "ちゃんころ", "にがー",
        "覚醒剤", "ひとらー", "なちす",
        // 運営・公式のなりすまし（「公式」だけは公式戦などの普通の語に含まれるので、ブランド名との組み合わせで調べる）
        "運営", "official", "moderator", "gamemaster", "velsia", "velstria", "bitcoinpay", "べるしあ",
    ]

    /// 単語として一致したら弾く語（英字の単語。大文字の切れ目・記号・空白・数字で区切る）。名前全体（正規化後）が一致した時も弾く
    /// （日本語の語は区切れないので、名前全体の一致だけ）。
    static let words: Set<String> = [
        "shit", "dick", "cock", "cum", "anal", "tits", "fag", "rape", "rapist", "kys", "admin", "gm", "staff",
        "sex", "sexy", "cunt", "cunts", "penis", "nazi", "nazis", "slut", "sluts", "boob", "boobs", "twat", "chinko", "manko",
        "公式", "大麻", "池沼",
    ]

    /// 連絡先とみなすトップレベルドメイン（「.」の後にこれが来て、その後が英字でなければ URL・メールとみなす。Mr.Bean のような名前は通す）。
    static let contactTLDs: Set<String> = [
        "com", "net", "org", "io", "gg", "me", "jp", "co", "tv", "xyz", "info", "biz", "app", "dev", "de", "uk", "us", "ru", "cn",
        "kr", "tw", "fr", "ly", "to", "cc", "link", "site", "online", "live", "fm", "be", "ne", "or", "ac",
    ]

    /// SNS などの連絡先の書き方（「insta:taro」「discord@xxx」など、サービス名の直後に : や @）。
    static let contactServices: [String] = [
        "insta", "instagram", "ig", "discord", "dc", "twitter", "tiktok", "snap", "snapchat", "kik", "telegram", "tg",
        "whatsapp", "wechat", "line", "x", "youtube", "yt", "twitch", "skype", "mail", "email",
    ]

    /// 名前に連絡先（URL・メール・SNS のアカウント・電話番号）が入っているか。
    static func containsContactInfo(_ text: String) -> Bool {
        let lower = text.precomposedStringWithCompatibilityMapping.lowercased()
        if ["http", "www.", "line.me"].contains(where: { lower.contains($0) }) { return true }
        // ドメインの形（「.」+ 既知の TLD + 英字以外か終わり）: discord.gg/x、me@x.io、example.com
        let chars = Array(lower)
        var i = 0
        while i < chars.count {
            if chars[i] == ".", i > 0, chars[i - 1].isLetter || chars[i - 1].isNumber {
                var j = i + 1
                var tld = ""
                while j < chars.count, chars[j].isASCII, chars[j].isLetter { tld.append(chars[j]); j += 1 }
                if contactTLDs.contains(tld) { return true }
            }
            i += 1
        }
        // メールアドレス（x@y）と @ で始まるアカウント名（@taro）。R@ven のような文字の置き換えは通す
        if let at = chars.firstIndex(of: "@") {
            let before = at > 0 ? chars[at - 1] : " "
            let after = chars[(at + 1)...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if after.count >= 2, before == " " || at == 0 || chars[(at + 1)...].contains(".") { return true }
        }
        // サービス名の直後の : / @（insta:taro、discord@x）
        let compact = lower.filter { !$0.isWhitespace }
        for service in contactServices {
            var search = compact.startIndex
            while let r = compact.range(of: service, range: search..<compact.endIndex) {
                let startsWord = r.lowerBound == compact.startIndex || !compact[compact.index(before: r.lowerBound)].isLetter
                if startsWord, r.upperBound < compact.endIndex, [":", "@", "#"].contains(compact[r.upperBound]) { return true }
                search = r.upperBound
            }
        }
        // 7 桁以上の数字（電話番号・ID）。区切りを挟んでも数える
        return lower.filter(\.isNumber).count >= 7
    }

    /// 不適切か（表示名・部屋名）。
    static func isInappropriate(_ text: String) -> Bool {
        if containsContactInfo(text) { return true }
        let n = normalized(text)
        if !n.isEmpty, fragments.contains(where: { n.contains($0) }) { return true }
        // 単語の語は、名前全体（記号・置き換えを正規化したもの。例 "sh!t"）か、英字の単語として一致した時だけ
        if words.contains(n) { return true }
        return tokens(text).contains { words.contains($0) }
    }

    /// 正規化: 全角 → 半角（互換分解）・小文字・カタカナ → ひらがな・数字の置き換え（0→o など）・文字以外の除去。
    static func normalized(_ text: String) -> String {
        var s = text.precomposedStringWithCompatibilityMapping.lowercased()
        s = s.applyingTransform(.hiraganaToKatakana, reverse: true) ?? s
        let leet: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
                                           "@": "a", "$": "s", "!": "i", "|": "i"]
        var out = ""
        for ch in s {
            let c = leet[ch] ?? ch
            if c.isLetter { out.append(c) }
        }
        return out
    }

    /// 英字の単語に分ける（小文字 → 大文字の切れ目、英字以外で区切る）。
    static func tokens(_ text: String) -> [String] {
        let s = text.precomposedStringWithCompatibilityMapping
        var result: [String] = []
        var current = ""
        var previousLower = false
        for ch in s {
            guard ch.isASCII, ch.isLetter else {
                if !current.isEmpty { result.append(current.lowercased()) }
                current = ""
                previousLower = false
                continue
            }
            if ch.isUppercase, previousLower, !current.isEmpty {
                result.append(current.lowercased())
                current = ""
            }
            current.append(ch)
            previousLower = ch.isLowercase
        }
        if !current.isEmpty { result.append(current.lowercased()) }
        return result
    }
}

extension PlayerNameRules {
    /// 他のプレイヤーから受け取った名前の整形（制御文字を除き長さを揃え、不適切なら空にする。空なら呼び出し側が代わりの名前を出す）。
    /// 改変したクライアントは入力時の検査を通らない名前を送れるので、受け取った側でも確かめる。
    static func sanitizedRemote(_ raw: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(.newlines).union(.illegalCharacters)
        let scalars = raw.unicodeScalars.filter { !forbidden.contains($0) }
        let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(text.prefix(maxLength))
        return ContentFilter.isInappropriate(clipped) ? "" : clipped
    }

    /// 他のプレイヤーへ送る自分の名前（規則を満たさない古い保存データの名前は送らない）。
    static func outgoing(_ raw: String) -> String {
        let name = normalized(raw)
        return validate(name) == nil ? name : L("プレイヤー", "Player")
    }

    /// 保存している名前が規則（不適切語のフィルタを含む）を満たさず、オンラインでは「プレイヤー」と表示されるか。
    static func isReplacedOnline(_ raw: String) -> Bool {
        let name = normalized(raw)
        return !name.isEmpty && validate(name) != nil
    }

    /// 画面に出す選手の名前（試合中の頭上・スコアボード・ロード画面・リザルト。リプレイの再生を含む）。
    /// ホストから届いた試合の構成や、共有されたリプレイの名前は改変されうるので、表示の直前に不適切な名前を隠す。
    /// 試合の構成・状態そのものは変えない（名前は状態のハッシュに入らないが、スナップショットや年表の照合に触れないように）。
    /// 長さは切らない（AI の名前「〈ヒーロー〉_AI」は 12 文字を超えることがある）。
    static func shown(_ raw: String) -> String {
        shownCache.value(for: raw) { raw in
            let forbidden = CharacterSet.controlCharacters.union(.newlines).union(.illegalCharacters)
            let scalars = raw.unicodeScalars.filter { !forbidden.contains($0) }
            let text = String(String.UnicodeScalarView(scalars))
            return ContentFilter.isInappropriate(text) ? L("プレイヤー", "Player") : text
        }
    }

    /// shown の結果の覚え（毎フレームのスコアボードで正規化をやり直さない）。言語の切り替えで代わりの名前が変わるので、言語ごとに覚える。
    private static let shownCache = ShownNameCache()

    /// 受け取った部屋名の整形（招待・近くの部屋・部屋の状態）。不適切なら空。
    static func sanitizedRoomName(_ raw: String, maxLength: Int = 40) -> String {
        let forbidden = CharacterSet.controlCharacters.union(.newlines).union(.illegalCharacters)
        let scalars = raw.unicodeScalars.filter { !forbidden.contains($0) }
        let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(text.prefix(maxLength))
        return ContentFilter.isInappropriate(clipped) ? "" : clipped
    }
}

/// 表示用の名前の覚え（スレッドをまたいでも安全なように鍵で守る）。
private final class ShownNameCache: @unchecked Sendable {
    private let lock = NSLock()
    private var table: [String: String] = [:]

    func value(for raw: String, make: (String) -> String) -> String {
        let key = (Loc.isEnglish ? "en|" : "ja|") + raw
        lock.lock()
        if let hit = table[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let made = make(raw)
        lock.lock()
        if table.count > 512 { table.removeAll() }
        table[key] = made
        lock.unlock()
        return made
    }
}

// MARK: - ブロック

/// ブロックしたプレイヤー（フレンドコード単位）。
struct BlockedPlayer: Codable, Equatable, Identifiable {
    var code: String
    var name: String
    var blockedAt: Date

    var id: String { code }
}

// MARK: - 通報

/// 通報・ブロックの対象（オンラインで出会ったプレイヤー）。
struct PlayerReportTarget: Identifiable, Equatable {
    /// どこで出会ったか（運営の確認用）。
    enum Source: String, Equatable {
        case party, room, friend, request, invite, match

        var title: String {
            switch self {
            case .party: return L("パーティ", "Party")
            case .room: return L("部屋（ヒーロー選択）", "Room (hero pick)")
            case .friend: return L("フレンド一覧", "Friends list")
            case .request: return L("フレンド申請", "Friend request")
            case .invite: return L("パーティの招待", "Party invite")
            case .match: return L("オンライン対戦の試合", "Online match")
            }
        }
    }

    var name: String
    var friendCode: String?
    /// 相手のプレイヤー ID（部屋で名乗った値。自己申告）。
    var peerID: OnlinePeerID?
    var source: Source
    /// 部屋コード（部屋コードの部屋のとき）。
    var roomCode: String?
    /// 試合の情報など（通報の本文に添える）。
    var detail: String?
    /// 試合の座席（リザルトからの通報。同じ名前の参加者を区別する）。
    var seat: Int?

    var id: String { [source.rawValue, friendCode ?? "", peerID ?? "", name, seat.map(String.init) ?? ""].joined(separator: "|") }
    /// ブロック中の相手の名前の代わり（パーティの枠と同じ）。
    static var blockedName: String { L("ブロック中のプレイヤー", "Blocked player") }
    /// 表示名（空なら代わりの名前）。
    var displayName: String { name.isEmpty ? L("プレイヤー", "Player") : name }
}

/// 通報の理由。
enum PlayerReportReason: String, CaseIterable, Identifiable {
    case inappropriateName, harassment, cheating, griefing, impersonation, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inappropriateName: return L("不適切な名前", "Offensive name")
        case .harassment: return L("嫌がらせ・差別", "Harassment / hate")
        case .cheating: return L("不正行為（チート・改造）", "Cheating / modding")
        case .griefing: return L("迷惑行為（放置・妨害・しつこい申請）", "Griefing / spam")
        case .impersonation: return L("なりすまし", "Impersonation")
        case .other: return L("その他", "Other")
        }
    }

    var symbol: String {
        switch self {
        case .inappropriateName: return "textformat.abc.dottedunderline"
        case .harassment: return "exclamationmark.bubble.fill"
        case .cheating: return "wrench.and.screwdriver.fill"
        case .griefing: return "hand.raised.slash.fill"
        case .impersonation: return "person.crop.circle.badge.questionmark"
        case .other: return "ellipsis.bubble.fill"
        }
    }

    /// 件名の分類タグ（運営の仕分け用に言語によらず固定）。
    var subjectTag: String {
        switch self {
        case .inappropriateName: return "Name"
        case .harassment: return "Harassment"
        case .cheating: return "Cheating"
        case .griefing: return "Griefing"
        case .impersonation: return "Impersonation"
        case .other: return "Other"
        }
    }
}

/// プレイヤーの通報のメール（運営宛ての下書き）。
enum PlayerReportMail {
    static let maxLength = 1000

    static func subject(_ reason: PlayerReportReason) -> String {
        "[VELSIA] Player Report: \(reason.subjectTag)"
    }

    /// 本文: 通報の内容・対象（表示名・フレンドコード・プレイヤー ID・場所・部屋コード）・通報した人のフレンドコード・環境。
    static func body(target: PlayerReportTarget, reason: PlayerReportReason, message: String, reporterCode: String,
                     date: Date, appVersion: String, systemVersion: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        lines.append(L("■ 通報の内容", "■ Details"))
        lines.append(trimmed.isEmpty ? L("（未記入）", "(empty)") : String(trimmed.prefix(maxLength)))
        lines.append("")
        lines.append(L("■ 対象のプレイヤー", "■ Reported player"))
        lines.append("\(L("理由", "Reason")): \(reason.title)")
        lines.append("\(L("表示名", "Name")): \(target.displayName)")
        lines.append("\(L("フレンドコード", "Friend code")): \(target.friendCode.map(FriendCode.display) ?? L("不明", "unknown"))")
        if let id = target.peerID { lines.append("Player ID: \(id)") }
        lines.append("\(L("場所", "Where")): \(target.source.title)")
        if let code = target.roomCode { lines.append("\(L("部屋コード", "Room code")): \(RelayRoomCode.display(code))") }
        if let detail = target.detail, !detail.isEmpty { lines.append(detail) }
        lines.append("")
        lines.append(L("■ 通報した人", "■ Reporter"))
        lines.append("\(L("フレンドコード", "Friend code")): \(FriendCode.isValid(reporterCode) ? FriendCode.display(reporterCode) : "-")")
        lines.append("\(L("日時", "Date")): \(ISO8601DateFormatter().string(from: date))")
        lines.append("App: \(appVersion)")
        lines.append("iOS: \(systemVersion)")
        return lines.joined(separator: "\n")
    }

    static func url(subject: String, body: String) -> URL? {
        ReportMail.url(to: FeatureFlags.supportEmail, subject: subject, body: body)
    }
}
