import Foundation

// 担当: app-services
// アカウントごとのランクをクラウド（relay の RankAccount。Cloudflare Durable Object）に置く。
// 鍵はフレンド受信箱と同じ（friendCode + inboxKey）。通信できない時は nil を返し、端末の計算（RankService.apply）のまま進む。

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

    /// relay の https の URL（wss → https）。
    static var baseURL: URL {
        var c = URLComponents(url: OnlineRelayConfig.baseURL, resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "ws" ? "http" : "https"
        return c.url!
    }

    static func get(code: String, key: String) async -> CloudRank? {
        await call(code: code, op: "get", body: ["key": key])
    }

    static func seed(code: String, key: String, local: RankState) async -> CloudRank? {
        guard let state = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(CloudRank(local))) else { return nil }
        return await call(code: code, op: "seed", body: ["key": key, "state": state])
    }

    static func match(code: String, key: String, matchID: String, won: Bool, rating: Double, mvp: Bool) async -> CloudRank? {
        await call(code: code, op: "match",
                   body: ["key": key, "match": ["matchId": matchID, "won": won, "rating": rating, "mvp": mvp]])
    }

    static func erase(code: String, key: String) async {
        _ = await call(code: code, op: "erase", body: ["key": key])
    }

    private static func call(code: String, op: String, body: [String: Any]) async -> CloudRank? {
        let url = baseURL.appendingPathComponent("v1/rank/\(code)/\(op)")
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.ok else { return nil }
        return reply.state
    }
}
