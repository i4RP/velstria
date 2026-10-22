import CommonCrypto
import Foundation
import GameKit
import UIKit

// 担当: outgame。アカウント（relay の CloudAccount / GameCenterIndex。relay/README.md「アカウント」）。
// アカウント ID = フレンドコード。持ち主は受信箱と同じ鍵（friendCode + inboxKey）。MLBB のアカウント設定と同じく:
// - クラウド保存: 端末のプロフィール（zlib で縮めた JSON）を中継に預ける（パスワードか Game Center を設定した後は自動でも）。
// - パスワード: 別の端末で「アカウント ID + パスワード」でログインすると、預けたプロフィールに切り替わる（フレンドコードと鍵ごと）。
//   端末は PBKDF2-HMAC-SHA256（10 万回、塩 = "velsia-account-v1:<ID>"）の照合値だけを送り、パスワードそのものは送らない。
// - Game Center: 本人確認の署名で連携し、別の端末で同じ Game Center にサインインしていればログインできる。
// 使うのはオンライン機能のルールに同意した 13 歳以上だけ（AppModel.syncsCloudRank と同じ条件）。

/// 中継のアカウントの状態（relay の AccountInfo）。
struct CloudAccountInfo: Codable, Equatable, Sendable {
    var password: Bool
    /// 最後にクラウドへ保存した日時（ミリ秒。端末の時計）。
    var savedAt: Double?
    var size: Int
    var gameCenter: Bool

    var savedDate: Date? { savedAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil } }
}

/// 端末に置くアカウントの状態（Profile.account）。中継の状態の写し（画面と自動保存の判断に使う）。
struct AccountLinkState: Codable, Equatable {
    /// パスワードを設定した。
    var hasPassword = false
    /// 最後にクラウドへ保存できた日時。
    var lastCloudSave: Date?
    /// 連携した Game Center の表示名（nil = 連携していない）。
    var gameCenterAlias: String?

    /// ほかの端末で取り出せる（パスワードか Game Center がある）。
    var isRecoverable: Bool { hasPassword || gameCenterAlias != nil }
}

/// クラウドから取り出したプロフィール。
struct CloudAccountDownload: Sendable {
    var code: String
    /// プロフィールの JSON（縮める前）。
    var json: Data
    var info: CloudAccountInfo
}

/// アカウント設定スコア（MLBB の「アカウント設定スコア」。0〜100）と、まだの項目。
struct AccountScore: Equatable {
    enum Item: String, CaseIterable { case password, gameCenter, cloudSave }

    var value: Int
    var missing: [Item]

    /// オンラインに同意した時点で 20。パスワード +30・Game Center +30・7 日以内のクラウド保存 +20。
    static func of(_ s: AccountLinkState, online: Bool, now: Date = Date()) -> AccountScore {
        guard online else { return AccountScore(value: 0, missing: Item.allCases) }
        var value = 20
        var missing: [Item] = []
        if s.hasPassword { value += 30 } else { missing.append(.password) }
        if s.gameCenterAlias != nil { value += 30 } else { missing.append(.gameCenter) }
        if let saved = s.lastCloudSave, now.timeIntervalSince(saved) < 7 * 86_400 { value += 20 } else { missing.append(.cloudSave) }
        return AccountScore(value: value, missing: missing)
    }
}

// MARK: - パスワード

enum AccountPassword {
    static let minLength = 8
    static let maxLength = 64
    static let iterations: UInt32 = 100_000

    enum Issue: Equatable { case tooShort, tooLong, mismatch }

    static func validate(_ password: String, confirm: String? = nil) -> Issue? {
        let n = password.count
        if n < minLength { return .tooShort }
        if n > maxLength { return .tooLong }
        if let confirm, confirm != password { return .mismatch }
        return nil
    }

    static func message(_ issue: Issue) -> String {
        switch issue {
        case .tooShort: return L("パスワードは \(minLength) 文字以上にしてください", "Use at least \(minLength) characters")
        case .tooLong: return L("パスワードは \(maxLength) 文字までです", "Use at most \(maxLength) characters")
        case .mismatch: return L("確認のパスワードが一致しません", "The passwords don't match")
        }
    }

    /// PBKDF2-HMAC-SHA256（RFC 8018）。テストは RFC 7914 の値で確かめる。
    static func pbkdf2(password: String, salt: [UInt8], iterations: UInt32, length: Int = 32) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: length)
        let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count, salt, salt.count,
                                          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &out, out.count)
        return status == Int32(kCCSuccess) ? out : nil
    }

    /// 中継へ送る照合値（64 桁の 16 進）。ID ごとに塩が変わるので、同じパスワードでも別の値になる。
    static func verifier(code: String, password: String, iterations: UInt32 = iterations) -> String? {
        let normalized = password.precomposedStringWithCanonicalMapping
        guard let bytes = pbkdf2(password: normalized, salt: Array("velsia-account-v1:\(code)".utf8), iterations: iterations) else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 預けるプロフィールの形

enum CloudProfileCodec {
    /// 先頭の印（形を変えたら上げる）。
    static let magic = Data("VSA1".utf8)

    /// プロフィール → 預ける形（印 + zlib）。
    static func encode(json: Data) -> Data? {
        guard let z = try? (json as NSData).compressed(using: .zlib) as Data else { return nil }
        return magic + z
    }

    /// 預けた形 → プロフィールの JSON。
    static func decode(_ data: Data) -> Data? {
        guard data.count > magic.count, data.prefix(magic.count) == magic else { return nil }
        return try? (Data(data.dropFirst(magic.count)) as NSData).decompressed(using: .zlib) as Data
    }
}

// MARK: - 中継との通信

enum CloudAccountAPI {
    typealias Transport = FriendInboxEraser.Transport

    enum Failure: Error, Equatable {
        /// 通信できない。
        case offline
        /// 中継がまだアカウントに対応していない（古い版。404 not_found）。
        case unsupported
        /// このコードの持ち主の鍵ではない。
        case forbidden
        case wrongPassword
        /// 続けて違えたのでロック中（秒）。
        case locked(Int)
        case noPassword
        case noData
        case notLinked
        case gameCenterTaken
        case gameCenterInvalid
        case suspended
        case tooLarge
        case badInput
        case server(Int)

        var message: String {
            switch self {
            case .offline: return L("サーバーに接続できませんでした。通信状態を確かめてください", "Couldn't reach the server. Check your connection")
            case .unsupported: return L("サーバーが更新されるまで使えません（しばらくお待ちください）", "Not available until the server is updated")
            case .forbidden: return L("このアカウントを操作できません", "You can't change this account")
            case .wrongPassword: return L("アカウント ID かパスワードが違います", "Wrong account ID or password")
            case .locked(let s): return L("パスワードを続けて間違えたため、\(max(1, s / 60)) 分ほどロックされています", "Too many attempts. Try again in about \(max(1, s / 60)) min")
            case .noPassword: return L("このアカウントにはパスワードが設定されていません", "This account has no password")
            case .noData: return L("このアカウントにはクラウドのデータがありません", "This account has no cloud data")
            case .notLinked: return L("この Game Center に連携したアカウントはありません", "No account is linked to this Game Center")
            case .gameCenterTaken: return L("この Game Center は別のアカウントに連携されています", "This Game Center is linked to another account")
            case .gameCenterInvalid: return L("Game Center の本人確認に失敗しました。もう一度お試しください", "Game Center verification failed. Try again")
            case .suspended: return L("このアカウントは利用が停止されています", "This account is suspended")
            case .tooLarge: return L("データが大きすぎて保存できません", "The data is too large to save")
            case .badInput: return L("入力を確かめてください", "Check your input")
            case .server(let s): return L("サーバーの誤りです（\(s)）", "Server error (\(s))")
            }
        }
    }

    private struct Reply: Decodable {
        var ok: Bool
        var account: CloudAccountInfo
    }

    static func url(_ path: String, base: URL = OnlineRelayConfig.baseURL) -> URL {
        RankCloud.httpURL(base).appendingPathComponent(path)
    }

    static func jsonRequest(_ path: String, body: [String: Any], base: URL = OnlineRelayConfig.baseURL) -> URLRequest {
        var req = URLRequest(url: url(path, base: base), timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// 誤りの応答（平文の理由）を読み替える。
    static func failure(status: Int, body: Data, retryAfter: String? = nil) -> Failure {
        let reason = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        switch (status, reason) {
        case (404, "not_found"): return .unsupported
        case (404, "no_password"): return .noPassword
        case (404, "no_data"): return .noData
        case (404, "not_linked"): return .notLinked
        case (403, "wrong_password"): return .wrongPassword
        case (403, "suspended"): return .suspended
        case (403, "gamecenter_invalid"), (403, "gamecenter_expired"), (502, _): return .gameCenterInvalid
        case (403, _): return .forbidden
        case (429, _): return .locked(Int(retryAfter ?? "") ?? 900)
        case (409, _): return .gameCenterTaken
        case (413, _): return .tooLarge
        case (400, _): return .badInput
        default: return .server(status)
        }
    }

    private static func info(_ req: URLRequest, transport: Transport) async -> Result<CloudAccountInfo, Failure> {
        guard let (data, resp) = try? await transport(req), let http = resp as? HTTPURLResponse else { return .failure(.offline) }
        guard http.statusCode == 200 else { return .failure(failure(status: http.statusCode, body: data)) }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.ok else { return .failure(.server(http.statusCode)) }
        return .success(reply.account)
    }

    private static func download(_ req: URLRequest, transport: Transport) async -> Result<CloudAccountDownload, Failure> {
        guard let (data, resp) = try? await transport(req), let http = resp as? HTTPURLResponse else { return .failure(.offline) }
        guard http.statusCode == 200 else {
            return .failure(failure(status: http.statusCode, body: data, retryAfter: http.value(forHTTPHeaderField: "retry-after")))
        }
        guard let code = http.value(forHTTPHeaderField: "x-velsia-code"), FriendCode.isValid(code),
              let json = CloudProfileCodec.decode(data) else { return .failure(.noData) }
        let info = CloudAccountInfo(password: http.value(forHTTPHeaderField: "x-velsia-password") == "1",
                                    savedAt: Double(http.value(forHTTPHeaderField: "x-velsia-saved-at") ?? ""),
                                    size: data.count,
                                    gameCenter: http.value(forHTTPHeaderField: "x-velsia-gamecenter") == "1")
        return .success(CloudAccountDownload(code: code, json: json, info: info))
    }

    static func status(code: String, key: String, transport: Transport = FriendInboxEraser.urlSession) async -> Result<CloudAccountInfo, Failure> {
        await info(jsonRequest("v1/account/\(code)/status", body: ["key": key]), transport: transport)
    }

    static func setPassword(code: String, key: String, verifier: String,
                            transport: Transport = FriendInboxEraser.urlSession) async -> Result<CloudAccountInfo, Failure> {
        await info(jsonRequest("v1/account/\(code)/password", body: ["key": key, "verifier": verifier]), transport: transport)
    }

    /// 預ける（本文はバイト列、鍵は見出し。URL に載せない）。
    static func saveRequest(code: String, key: String, data: Data, savedAt: Date, base: URL = OnlineRelayConfig.baseURL) -> URLRequest {
        var req = URLRequest(url: url("v1/account/\(code)/save", base: base), timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-velsia-key")
        req.setValue(String(Int64(savedAt.timeIntervalSince1970 * 1000)), forHTTPHeaderField: "x-velsia-saved-at")
        req.httpBody = data
        return req
    }

    static func save(code: String, key: String, data: Data, savedAt: Date,
                     transport: Transport = FriendInboxEraser.urlSession) async -> Result<CloudAccountInfo, Failure> {
        await info(saveRequest(code: code, key: key, data: data, savedAt: savedAt), transport: transport)
    }

    static func linkGameCenter(code: String, key: String, proof: GameCenterProof,
                               transport: Transport = FriendInboxEraser.urlSession) async -> Result<CloudAccountInfo, Failure> {
        await info(jsonRequest("v1/account/\(code)/gamecenter", body: ["key": key, "gc": proof.json]), transport: transport)
    }

    static func unlinkGameCenter(code: String, key: String,
                                 transport: Transport = FriendInboxEraser.urlSession) async -> Result<CloudAccountInfo, Failure> {
        await info(jsonRequest("v1/account/\(code)/unlink-gamecenter", body: ["key": key]), transport: transport)
    }

    /// 消す。消せた・消すものが無かった・中継がまだ対応していない（404）なら true。通信の失敗は false。
    static func erase(code: String, key: String, base: URL = OnlineRelayConfig.baseURL,
                      transport: Transport = FriendInboxEraser.urlSession) async -> Bool {
        guard FriendCode.isValid(code), FriendInboxKey.isValid(key) else { return true }
        guard let (data, resp) = try? await transport(jsonRequest("v1/account/\(code)/erase", body: ["key": key], base: base)),
              let status = (resp as? HTTPURLResponse)?.statusCode else { return false }
        return status == 200 || status == 404 || (status == 403 && String(decoding: data, as: UTF8.self).hasPrefix("forbidden"))
    }

    static func login(code: String, password: String,
                      transport: Transport = FriendInboxEraser.urlSession) async -> Result<CloudAccountDownload, Failure> {
        guard FriendCode.isValid(code), let verifier = AccountPassword.verifier(code: code, password: password) else { return .failure(.badInput) }
        return await download(jsonRequest("v1/account/login", body: ["code": code, "verifier": verifier]), transport: transport)
    }

    static func loginGameCenter(proof: GameCenterProof,
                                transport: Transport = FriendInboxEraser.urlSession) async -> Result<CloudAccountDownload, Failure> {
        await download(jsonRequest("v1/account/login-gamecenter", body: ["gc": proof.json]), transport: transport)
    }
}

// MARK: - Game Center

/// 本人確認の署名（GKLocalPlayer.fetchItems(forIdentityVerificationSignature:)）。中継が Apple の公開鍵で確かめる。
struct GameCenterProof: Equatable, Sendable {
    var playerID: String
    var bundleID: String
    var publicKeyURL: String
    var signature: Data
    var salt: Data
    var timestamp: UInt64

    var json: [String: Any] {
        ["playerId": playerID, "bundleId": bundleID, "publicKeyUrl": publicKeyURL,
         "signature": signature.base64EncodedString(), "salt": salt.base64EncodedString(), "timestamp": timestamp]
    }
}

@MainActor
enum GameCenterAuth {
    struct Player: Equatable {
        var teamPlayerID: String
        var alias: String
    }

    enum Failure: Error, Equatable {
        case cancelled
        case unavailable(String)

        var message: String {
            switch self {
            case .cancelled:
                return L("Game Center にサインインしませんでした。iPhone の「設定 > Game Center」からサインインできます",
                         "Game Center sign-in was cancelled. You can sign in from Settings > Game Center")
            case .unavailable(let detail):
                return L("Game Center を使えません", "Game Center isn't available") + (detail.isEmpty ? "" : "（\(detail)）")
            }
        }
    }

    private static var waiters: [CheckedContinuation<Result<Player, Failure>, Never>] = []
    private static var attempt = 0

    static var current: Player? {
        let local = GKLocalPlayer.local
        return local.isAuthenticated ? Player(teamPlayerID: local.teamPlayerID, alias: local.alias) : nil
    }

    /// サインインする（済んでいればそのまま）。必要なら Game Center のサインイン画面を出す。
    static func authenticate() async -> Result<Player, Failure> {
        if let current { return .success(current) }
        attempt += 1
        let token = attempt
        return await withCheckedContinuation { cont in
            waiters.append(cont)
            GKLocalPlayer.local.authenticateHandler = { viewController, error in
                DispatchQueue.main.async { MainActor.assumeIsolated { handle(viewController, error) } }
            }
            // サインイン画面を閉じても呼ばれないことがあるので、待ちすぎない
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(120))
                if attempt == token { finish(.failure(.unavailable(L("時間切れ", "timed out")))) }
            }
        }
    }

    private static func handle(_ viewController: UIViewController?, _ error: Error?) {
        if let viewController {
            present(viewController)
            return
        }
        if let current {
            finish(.success(current))
        } else if let error = error as? GKError, error.code == .cancelled {
            finish(.failure(.cancelled))
        } else {
            finish(.failure(.unavailable(error?.localizedDescription ?? "")))
        }
    }

    private static func finish(_ result: Result<Player, Failure>) {
        attempt += 1
        let pending = waiters
        waiters = []
        for w in pending { w.resume(returning: result) }
    }

    private static func present(_ viewController: UIViewController) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        top?.present(viewController, animated: true)
    }

    /// 本人確認の署名を作る（サインイン済みの時だけ）。
    static func proof() async -> Result<GameCenterProof, Failure> {
        let local = GKLocalPlayer.local
        guard local.isAuthenticated else { return .failure(.unavailable(L("サインインしていません", "not signed in"))) }
        let playerID = local.teamPlayerID
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        return await withCheckedContinuation { cont in
            local.fetchItems(forIdentityVerificationSignature: { url, signature, salt, timestamp, error in
                if let url, let signature, let salt, error == nil {
                    cont.resume(returning: .success(GameCenterProof(playerID: playerID, bundleID: bundleID, publicKeyURL: url.absoluteString,
                                                                    signature: signature, salt: salt, timestamp: timestamp)))
                } else {
                    cont.resume(returning: .failure(.unavailable(error?.localizedDescription ?? "")))
                }
            })
        }
    }
}
