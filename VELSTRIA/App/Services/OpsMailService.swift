import Foundation

// 担当: outgame（第3段）。運営からのメール（relay の GET /v1/mail。運営だけが秘密の鍵で登録する。relay/README.md）。
// 起動時と前面に戻った時に取りに来て、運営のメールの ID で重複を除き、端末のメール（Profile.mail）に入れる。添付は端末で受け取る
// （今までのメールと同じ）。「重要」の印と、メールの種類（MLBB のタブ: 重要なお知らせ・システム・通報の結果・受信箱・ギフト）を持つ。

/// 中継から届く運営のメール（relay の OpsMail と同じ形。時刻はミリ秒）。
struct OpsMail: Decodable, Equatable {
    var id: String
    var titleJa: String
    var titleEn: String
    var bodyJa: String
    var bodyEn: String
    var attachments: [MailAttachment]
    var important: Bool
    var category: String
    var startsAt: Double
    var expiresAt: Double
}

enum OpsMailService {
    /// 覚えておく運営のメールの ID の数（古い物から忘れる。中継は 60 日で配らなくなる）。
    static let maxSeen = 300

    private struct Reply: Decodable {
        var ok: Bool
        var mail: [OpsMail]
    }

    /// 今公開中の運営のメール（通信の失敗は nil）。
    static func fetch(base: URL, transport: FriendInboxEraser.Transport) async -> [OpsMail]? {
        var req = URLRequest(url: RankCloud.httpURL(base).appendingPathComponent("v1/mail"), timeoutInterval: 10)
        req.httpMethod = "GET"
        guard let (data, resp) = try? await transport(req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.ok else { return nil }
        return reply.mail
    }

    /// まだ受け取っていない運営のメールを、端末のメールの先頭に入れる（見出しと本文は今の言語）。入れた数を返す。
    @discardableResult
    static func merge(_ mail: [OpsMail], into profile: inout Profile, now: Date = Date()) -> Int {
        var added = 0
        for m in mail.sorted(by: { $0.startsAt > $1.startsAt }) where !profile.seenOpsMailIDs.contains(m.id) {
            let expires = Date(timeIntervalSince1970: m.expiresAt / 1000)
            profile.seenOpsMailIDs.append(m.id)
            guard expires > now, !profile.mail.contains(where: { $0.opsID == m.id }) else { continue }
            var item = MailItem(date: Date(timeIntervalSince1970: m.startsAt / 1000),
                                title: L(m.titleJa, m.titleEn), body: L(m.bodyJa, m.bodyEn),
                                attachments: m.attachments, expiresAt: expires)
            item.important = m.important
            item.opsID = m.id
            item.category = MailCategory(rawValue: m.category) ?? (m.important ? .important : .system)
            profile.mail.insert(item, at: 0)
            added += 1
        }
        if profile.seenOpsMailIDs.count > maxSeen {
            profile.seenOpsMailIDs.removeFirst(profile.seenOpsMailIDs.count - maxSeen)
        }
        return added
    }
}
