import Foundation
import Observation

// 担当: outgame（第3段）。公開の名刺の読み書きとランキング（relay の Directory。relay/README.md「名刺・ランキング・メール」）。
// 型は PublicProfileModels.swift。名刺を送るのはオンラインに同意した 13 歳以上だけ（クラウドのランクと同じ条件。AppModel.syncsCloudRank）。
// 書き込みは受信箱と同じ鍵（コードの持ち主）。読み出しはコードをまとめて指定する。消すのはランクの消去と一緒（relay がランクの消去で名刺も消す）。

/// 中継の応答の日時（JavaScript の toISOString。ミリ秒つき）を読む。
enum RelayJSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(text)"))
        }
        return d
    }()

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// `POST <relay>/<path>`（本文は JSON）。
    static func post(_ path: String, body: [String: Any], base: URL) -> URLRequest {
        var req = URLRequest(url: RankCloud.httpURL(base).appendingPathComponent(path), timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }
}

@MainActor
@Observable
final class PublicProfileService {
    /// 取ってきた名刺（フレンドコード → 名刺）。画面はこれを見る。
    private(set) var profiles: [String: PublicProfile] = [:]

    /// 通信の送り手と中継の場所（テストは差し替える）。
    @ObservationIgnored var transport: FriendInboxEraser.Transport = FriendInboxEraser.urlSession
    @ObservationIgnored var base: () -> URL = { OnlineRelayConfig.baseURL }
    /// 送ってよいか（AppModel が渡す: オンラインに同意した 13 歳以上）。
    @ObservationIgnored var isAllowed: () -> Bool = { false }
    /// 自分のコード・鍵・名刺の中身（AppModel が Profile から作る）。
    @ObservationIgnored var own: () -> (code: String, key: String, card: PublicCardPayload)? = { nil }
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var lastPublished: (code: String, card: PublicCardPayload)?

    /// 名刺のキャッシュの寿命（秒）。
    static let cacheLifetime: TimeInterval = 300
    /// まとめて読む上限（relay の MAX_BATCH_CODES）。
    static let batchLimit = 100

    private struct ProfilesReply: Decodable {
        var ok: Bool
        var profiles: [PublicProfile]
    }

    private struct PutReply: Decodable {
        var ok: Bool
        var profile: PublicProfile
    }

    /// まとめて取る（100 件まで。新しいキャッシュがあれば通信しない。force で取り直す）。同意していない・オフラインなら何もしない。
    func load(_ codes: [String], force: Bool = false) async {
        guard isAllowed() else { return }
        let now = Date()
        var need: [String] = []
        for c in codes where FriendCode.isValid(c) && !need.contains(c) {
            if force || fetchedAt[c].map({ now.timeIntervalSince($0) > Self.cacheLifetime }) ?? true { need.append(c) }
        }
        guard !need.isEmpty else { return }
        let batch = Array(need.prefix(Self.batchLimit))
        let req = RelayJSON.post("v1/profiles", body: ["codes": batch], base: base())
        guard let (data, resp) = try? await transport(req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? RelayJSON.decoder.decode(ProfilesReply.self, from: data), reply.ok else { return }
        for c in batch {
            fetchedAt[c] = now
            if !reply.profiles.contains(where: { $0.code == c }) { profiles[c] = nil }
        }
        for p in reply.profiles { profiles[p.code] = p }
    }

    /// 自分の名刺を送る（オンラインに同意している時だけ。前に送った中身から変わった時だけ）。送れたら true。
    @discardableResult
    func publishOwn(force: Bool = false) async -> Bool {
        guard isAllowed(), let me = own() else { return false }
        if !force, let last = lastPublished, last.code == me.code, last.card == me.card { return true }
        guard let card = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(me.card)) else { return false }
        let req = RelayJSON.post("v1/profile/\(me.code)/put", body: ["key": me.key, "profile": card], base: base())
        guard let (data, resp) = try? await transport(req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? RelayJSON.decoder.decode(PutReply.self, from: data), reply.ok else { return false }
        lastPublished = (me.code, me.card)
        profiles[me.code] = reply.profile
        fetchedAt[me.code] = Date()
        return true
    }

    /// 送った記録を忘れる（データの削除・同意の取り消しの後。次は必ず送る）。
    func forgetPublished() {
        lastPublished = nil
        profiles = [:]
        fetchedAt = [:]
    }
}

@MainActor
@Observable
final class RankingService {
    /// 範囲ごとの直近のページ。
    private(set) var pages: [RankingScope: RankingPage] = [:]
    /// 読み込み中の範囲。
    private(set) var loading: Set<RankingScope> = []
    /// 直近の失敗（利用者向けの文。成功したら nil）。
    private(set) var lastError: String?

    @ObservationIgnored var transport: FriendInboxEraser.Transport = FriendInboxEraser.urlSession
    @ObservationIgnored var base: () -> URL = { OnlineRelayConfig.baseURL }
    @ObservationIgnored var isAllowed: () -> Bool = { false }
    /// 自分のコード・フレンドのコード（AppModel が渡す）。
    @ObservationIgnored var myCode: () -> String? = { nil }
    @ObservationIgnored var friendCodes: () -> [String] = { [] }

    /// ページを取り直すまでの間（秒）。
    static let pageLifetime: TimeInterval = 60

    private struct Reply: Decodable {
        var ok: Bool
        var entries: [RankingEntry]
        var me: RankingEntry?
    }

    /// 取る（新しいページがあれば通信しない。force で取り直す）。
    func load(_ scope: RankingScope, force: Bool = false) async {
        guard isAllowed() else {
            lastError = L("オンライン機能に同意すると、ランキングを見られます", "Agree to the online rules to see the ranking")
            return
        }
        if !force, let page = pages[scope], Date().timeIntervalSince(page.fetchedAt) < Self.pageLifetime { return }
        guard !loading.contains(scope) else { return }
        loading.insert(scope)
        defer { loading.remove(scope) }
        var body: [String: Any] = [:]
        switch scope {
        case .global:
            body["scope"] = "global"
        case .country(let c):
            body["scope"] = "country"
            body["country"] = c
        case .friends:
            body["scope"] = "friends"
            body["codes"] = Array(friendCodes().filter(FriendCode.isValid).prefix(200))
        }
        if let me = myCode(), FriendCode.isValid(me) { body["me"] = me }
        let req = RelayJSON.post("v1/ranking", body: body, base: base())
        guard let (data, resp) = try? await transport(req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? RelayJSON.decoder.decode(Reply.self, from: data), reply.ok else {
            lastError = L("ランキングを読み込めませんでした", "Couldn't load the ranking")
            return
        }
        pages[scope] = RankingPage(entries: reply.entries, me: reply.me, fetchedAt: Date())
        lastError = nil
    }
}
