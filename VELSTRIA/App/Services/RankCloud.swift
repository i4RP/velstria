import Foundation

// 担当: app-services
// アカウントごとのランクをクラウド（relay の RankAccount。Cloudflare Durable Object）に置く。
// 鍵はフレンド受信箱と同じ（friendCode + inboxKey）。通信できない時は nil を返し、端末の計算（RankService.apply）のまま進む。
// 送るのはオンライン機能のルールに同意した 13 歳以上だけ（AppModel.syncsCloudRank。OnlineAccess）。
// 消すのは FriendHub.eraseServerData（設定 > プライバシー の「フレンドサーバーのデータを削除」「全データを削除」。受信箱と一緒に消す）。

/// クラウドのランクの形（relay/src/rank.ts の RankState）。
struct CloudRank: Codable, Equatable {
    var tier: String
    var division: Int
    var stars: Int
    var starPoints: Int
    var protectionPoints: Int
    var highestTier: String
    var highestMythicStars: Int
    var wins: Int
    var losses: Int

    static let tierNames = ["warrior", "elite", "master", "grandmaster", "epic", "legend", "mythic"]

    init(_ r: RankState) {
        tier = Self.tierNames[r.tier.rawValue]
        division = r.division
        stars = r.stars
        starPoints = r.starPoints
        protectionPoints = r.protectionPoints
        highestTier = Self.tierNames[r.highestTier.rawValue]
        highestMythicStars = r.highestMythicStars
        wins = r.seasonWins
        losses = r.seasonLosses
    }
}

extension RankState {
    /// クラウドの値で上書きする（報酬の受け取り記録は端末のもの）。
    mutating func adopt(_ c: CloudRank) {
        guard let t = CloudRank.tierNames.firstIndex(of: c.tier).flatMap(RankTier.init(rawValue:)) else { return }
        tier = t
        division = c.division
        stars = c.stars
        starPoints = c.starPoints
        protectionPoints = c.protectionPoints
        highestTier = max(highestTier, CloudRank.tierNames.firstIndex(of: c.highestTier).flatMap(RankTier.init(rawValue:)) ?? t)
        highestMythicStars = c.highestMythicStars
        seasonWins = c.wins
        seasonLosses = c.losses
    }
}

enum RankCloud {
    private struct Reply: Decodable {
        var ok: Bool
        var state: CloudRank
    }

    /// HTTP の送り手（受信箱の消去と同じ形。テストは差し替える）。
    typealias Transport = FriendInboxEraser.Transport

    /// relay の https の URL（wss → https）。
    static var baseURL: URL { httpURL(OnlineRelayConfig.baseURL) }

    /// 中継の URL の ws / wss を http / https に読み替える。
    static func httpURL(_ relay: URL) -> URL {
        var c = URLComponents(url: relay, resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "ws" ? "http" : "https"
        return c.url!
    }

    static func get(code: String, key: String) async -> CloudRank? {
        await call(code: code, op: "get", body: ["key": key])
    }

    static func seed(code: String, key: String, local: RankState, transport: Transport = FriendInboxEraser.urlSession) async -> CloudRank? {
        guard let state = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(CloudRank(local))) else { return nil }
        return await call(code: code, op: "seed", body: ["key": key, "state": state], transport: transport)
    }

    static func match(code: String, key: String, matchID: String, won: Bool, rating: Double, mvp: Bool,
                      transport: Transport = FriendInboxEraser.urlSession) async -> CloudRank? {
        await call(code: code, op: "match",
                   body: ["key": key, "match": ["matchId": matchID, "won": won, "rating": rating, "mvp": mvp]], transport: transport)
    }

    /// 消す。消せた・消すものが無かったら true（200。403 forbidden はほかの鍵の持ち主のコードで、自分のランクは無い）。
    /// 通信の失敗・中継の誤りは false（もう一度試す）。
    @discardableResult
    static func erase(code: String, key: String, base: URL = OnlineRelayConfig.baseURL,
                      transport: Transport = FriendInboxEraser.urlSession) async -> Bool {
        guard FriendCode.isValid(code), FriendInboxKey.isValid(key) else { return true }
        guard let (data, resp) = try? await transport(request(base: base, code: code, op: "erase", body: ["key": key])) else { return false }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return status == 200 || (status == 403 && String(decoding: data, as: UTF8.self).hasPrefix("forbidden"))
    }

    /// `POST <base>/v1/rank/<CODE>/<op>`（鍵は本文に入れ、URL に載せない）。
    static func request(base: URL, code: String, op: String, body: [String: Any]) -> URLRequest {
        var req = URLRequest(url: httpURL(base).appendingPathComponent("v1/rank/\(code)/\(op)"), timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func call(code: String, op: String, body: [String: Any],
                             transport: Transport = FriendInboxEraser.urlSession) async -> CloudRank? {
        guard let (data, resp) = try? await transport(request(base: OnlineRelayConfig.baseURL, code: code, op: op, body: body)),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.ok else { return nil }
        return reply.state
    }
}
