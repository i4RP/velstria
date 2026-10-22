import XCTest
@testable import VELSTRIA

/// アカウント（パスワード・クラウド保存・Game Center の連携。CloudAccountService / AccountCenter）。中継とは代役の送り手で話す。
@MainActor
final class CloudAccountTests: XCTestCase {
    /// 送った要求を覚え、道ごとの応答を返す代役。
    private final class Recorder: @unchecked Sendable {
        var requests: [URLRequest] = []
        var replies: [String: (Int, Data, [String: String])] = [:]
        var fails = false

        func reply(_ suffix: String, _ status: Int, _ body: String, headers: [String: String] = [:]) {
            replies[suffix] = (status, Data(body.utf8), headers)
        }

        func reply(_ suffix: String, _ status: Int, data: Data, headers: [String: String] = [:]) {
            replies[suffix] = (status, data, headers)
        }

        var transport: CloudAccountAPI.Transport {
            { [self] request in
                self.requests.append(request)
                if self.fails { throw URLError(.notConnectedToInternet) }
                let path = request.url?.path ?? ""
                let hit = self.replies.first { path.hasSuffix($0.key) }?.value ?? (404, Data("not_found\n".utf8), [:])
                return (hit.1, HTTPURLResponse(url: request.url!, statusCode: hit.0, httpVersion: nil, headerFields: hit.2)!)
            }
        }
    }

    private let accountJSON = #"{"ok":true,"account":{"password":true,"savedAt":1792000000000,"size":1234,"gameCenter":false}}"#

    // MARK: パスワード

    func testPBKDF2MatchesTheRFC7914Vector() throws {
        let out = try XCTUnwrap(AccountPassword.pbkdf2(password: "passwd", salt: Array("salt".utf8), iterations: 1, length: 64))
        XCTAssertEqual(out.map { String(format: "%02x", $0) }.joined(),
                       "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783")
    }

    /// 照合値の作り方を変えると、設定済みのパスワードでログインできなくなる（値は Node の crypto.pbkdf2Sync で確かめたもの）。
    func testVerifierIsStableHexSaltedByTheAccountID() throws {
        let v = try XCTUnwrap(AccountPassword.verifier(code: "DW9HEAE5", password: "correct horse 1"))
        XCTAssertEqual(v, "56eadbf64a7324b882b00aea0081ea4d3ff599b46519db95d124cef42dd94463")
        XCTAssertNotEqual(AccountPassword.verifier(code: "ABCDEFGH", password: "correct horse 1"), v, "ID ごとに塩が変わる")
        // 合成済みと分解した「é」は同じパスワード
        XCTAssertEqual(AccountPassword.verifier(code: "DW9HEAE5", password: "cafe\u{301}-pass"),
                       "63f9703e2bca0baa8fe7b41058bbd7c0d2bf97c5efb807075d6516ce6a7678b6")
        XCTAssertEqual(AccountPassword.verifier(code: "DW9HEAE5", password: "caf\u{e9}-pass"),
                       "63f9703e2bca0baa8fe7b41058bbd7c0d2bf97c5efb807075d6516ce6a7678b6")
    }

    func testPasswordRules() {
        XCTAssertEqual(AccountPassword.validate("short"), .tooShort)
        XCTAssertEqual(AccountPassword.validate(String(repeating: "a", count: 65)), .tooLong)
        XCTAssertEqual(AccountPassword.validate("long enough", confirm: "long enougH"), .mismatch)
        XCTAssertNil(AccountPassword.validate("long enough", confirm: "long enough"))
    }

    // MARK: 預ける形

    func testCodecRoundTripsTheProfileJSON() throws {
        var p = Profile()
        p.displayName = "Hana"
        p.account.hasPassword = true
        let json = try PersistenceService.makeEncoder().encode(p)
        let packed = try XCTUnwrap(CloudProfileCodec.encode(json: json))
        XCTAssertEqual(packed.prefix(4), Data("VSA1".utf8))
        let back = try XCTUnwrap(CloudProfileCodec.decode(packed))
        let decoded = try PersistenceService.makeDecoder().decode(Profile.self, from: back)
        XCTAssertEqual(decoded.displayName, "Hana")
        XCTAssertTrue(decoded.account.hasPassword)
        XCTAssertNil(CloudProfileCodec.decode(Data("nope".utf8)))
        XCTAssertNil(CloudProfileCodec.decode(Data("VSA1garbage".utf8)))
    }

    func testOldSavesWithoutTheAccountDecodeWithDefaults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CloudAccount-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = PersistenceService(directory: dir)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: PersistenceService.makeEncoder().encode(Profile())) as? [String: Any])
        object.removeValue(forKey: "account")
        let p = try persistence.decodeProfile(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(p.account, AccountLinkState())
        XCTAssertFalse(p.account.isRecoverable)
    }

    func testMatchRecordKeepsRankBeforeAndAfter() throws {
        var r = MatchRecord(date: Date(timeIntervalSince1970: 1_792_000_000), mode: .ranked, difficulty: .normal, won: true, duration: 600,
                            heroID: "H025", kills: 7, deaths: 3, assists: 4, creepScore: 100, gold: 9000, damageToHeroes: 40_000,
                            grade: "S", isMVP: true, items: [], replayID: nil, summary: nil)
        r.rankBefore = PublicRank(tier: RankTier.epic.rawValue, division: 4, stars: 0)
        r.rankAfter = PublicRank(tier: RankTier.epic.rawValue, division: 4, stars: 1)
        let back = try PersistenceService.makeDecoder().decode(MatchRecord.self, from: PersistenceService.makeEncoder().encode(r))
        XCTAssertEqual(back, r)
        XCTAssertEqual(RankInlineText.short(try XCTUnwrap(back.rankAfter)), "IV★1")
        XCTAssertEqual(RankInlineText.short(PublicRank(tier: RankTier.mythic.rawValue, division: 1, stars: 12)), "★12")
    }

    // MARK: スコア

    func testAccountScore() {
        let now = Date()
        var s = AccountLinkState()
        XCTAssertEqual(AccountScore.of(s, online: false, now: now), AccountScore(value: 0, missing: AccountScore.Item.allCases))
        XCTAssertEqual(AccountScore.of(s, online: true, now: now).value, 20)
        s.hasPassword = true
        s.gameCenterAlias = "Hana"
        s.lastCloudSave = now.addingTimeInterval(-3600)
        XCTAssertEqual(AccountScore.of(s, online: true, now: now), AccountScore(value: 100, missing: []))
        s.lastCloudSave = now.addingTimeInterval(-8 * 86_400)
        XCTAssertEqual(AccountScore.of(s, online: true, now: now), AccountScore(value: 80, missing: [.cloudSave]))
        XCTAssertTrue(s.isRecoverable)
    }

    // MARK: 中継との通信

    func testFailureReasons() {
        func f(_ status: Int, _ body: String, retry: String? = nil) -> CloudAccountAPI.Failure {
            CloudAccountAPI.failure(status: status, body: Data(body.utf8), retryAfter: retry)
        }
        XCTAssertEqual(f(404, "not_found\n"), .unsupported, "古い中継")
        XCTAssertEqual(f(404, "no_password\n"), .noPassword)
        XCTAssertEqual(f(404, "no_data\n"), .noData)
        XCTAssertEqual(f(404, "not_linked\n"), .notLinked)
        XCTAssertEqual(f(403, "wrong_password\n"), .wrongPassword)
        XCTAssertEqual(f(403, "forbidden\n"), .forbidden)
        XCTAssertEqual(f(403, "suspended\n"), .suspended)
        XCTAssertEqual(f(403, "gamecenter_expired\n"), .gameCenterInvalid)
        XCTAssertEqual(f(429, "locked\n", retry: "600"), .locked(600))
        XCTAssertEqual(f(409, "gamecenter_taken\n"), .gameCenterTaken)
        XCTAssertEqual(f(413, "too_large\n"), .tooLarge)
        XCTAssertEqual(f(500, ""), .server(500))
    }

    func testSaveSendsBytesWithTheKeyInAHeaderNotTheURL() {
        let key = "k-0123456789abcdef"
        let req = CloudAccountAPI.saveRequest(code: "ABCDEFGH", key: key, data: Data([1, 2, 3]),
                                              savedAt: Date(timeIntervalSince1970: 1_792_000_000.5), base: URL(string: "wss://relay.test")!)
        XCTAssertEqual(req.url?.absoluteString, "https://relay.test/v1/account/ABCDEFGH/save")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertFalse(req.url!.absoluteString.contains(key))
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-velsia-key"), key)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-velsia-saved-at"), "1792000000500")
        XCTAssertEqual(req.httpBody, Data([1, 2, 3]))
    }

    func testLoginSendsOnlyTheVerifierAndUnpacksTheProfile() async throws {
        var p = Profile()
        p.displayName = "Cloud"
        let packed = try XCTUnwrap(CloudProfileCodec.encode(json: PersistenceService.makeEncoder().encode(p)))
        let rec = Recorder()
        rec.reply("/v1/account/login", 200, data: packed,
                  headers: ["x-velsia-code": p.friendCode, "x-velsia-saved-at": "1792000000000", "x-velsia-password": "1", "x-velsia-gamecenter": "0"])
        let result = await CloudAccountAPI.login(code: "DW9HEAE5", password: "correct horse 1", transport: rec.transport)
        let d = try result.get()
        XCTAssertEqual(d.code, p.friendCode)
        XCTAssertTrue(d.info.password)
        XCTAssertEqual(d.info.savedDate, Date(timeIntervalSince1970: 1_792_000_000))
        XCTAssertEqual(try PersistenceService.makeDecoder().decode(Profile.self, from: d.json).displayName, "Cloud")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(rec.requests.first?.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["code": "DW9HEAE5", "verifier": "56eadbf64a7324b882b00aea0081ea4d3ff599b46519db95d124cef42dd94463"],
                       "パスワードそのものは送らない")
        // 誤りは理由で返す
        rec.reply("/v1/account/login", 403, "wrong_password\n")
        let wrong = await CloudAccountAPI.login(code: "DW9HEAE5", password: "nope nope", transport: rec.transport)
        XCTAssertEqual(wrong.failureValue, .wrongPassword)
        let bad = await CloudAccountAPI.login(code: "bad", password: "whatever1", transport: rec.transport)
        XCTAssertEqual(bad.failureValue, .badInput)
    }

    func testEraseTreatsAnOldRelayAsNothingToErase() async {
        let rec = Recorder()
        let code = "ABCDEFGH", key = "k-0123456789abcdef"
        rec.reply("/erase", 200, #"{"ok":true,"result":"erased"}"#)
        let erased = await CloudAccountAPI.erase(code: code, key: key, transport: rec.transport)
        rec.replies = [:]
        let oldRelay = await CloudAccountAPI.erase(code: code, key: key, transport: rec.transport)
        rec.reply("/erase", 500, "")
        let serverError = await CloudAccountAPI.erase(code: code, key: key, transport: rec.transport)
        rec.fails = true
        let offline = await CloudAccountAPI.erase(code: code, key: key, transport: rec.transport)
        XCTAssertTrue(erased)
        XCTAssertTrue(oldRelay, "アカウントに対応していない中継（404）は消すものが無い")
        XCTAssertFalse(serverError)
        XCTAssertFalse(offline)
    }

    // MARK: AccountCenter

    private func makeApp() -> (AppModel, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CloudAccount-\(UUID().uuidString)", isDirectory: true)
        let app = AppModel(persistence: PersistenceService(directory: dir))
        // 受信箱へは繋がない（オンボーディングを終えた時の start を空振りさせてから、アカウントだけ使えるようにする）
        app.friends.isEnabled = { false }
        app.profile.onboardingCompleted = true
        app.profile.ageBracket = .adult
        app.profile.acceptedOnlineRulesVersion = FeatureFlags.currentOnlineRulesVersion
        app.friends.isEnabled = { true }
        return (app, dir)
    }

    func testSetPasswordSendsTheVerifierThenSavesTheProfile() async throws {
        let (app, dir) = makeApp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rec = Recorder()
        rec.reply("/password", 200, accountJSON)
        rec.reply("/save", 200, accountJSON)
        app.account.transport = rec.transport
        let code = app.profile.friendCode
        let result = await app.account.setPassword("correct horse 1")
        XCTAssertNil(result.failureValue)
        XCTAssertEqual(rec.requests.map { $0.url?.path }, ["/v1/account/\(code)/password", "/v1/account/\(code)/save"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(rec.requests[0].httpBody)) as? [String: String])
        XCTAssertEqual(body["verifier"], AccountPassword.verifier(code: code, password: "correct horse 1"))
        XCTAssertEqual(body["key"], app.profile.inboxKey)
        let saved = try XCTUnwrap(CloudProfileCodec.decode(XCTUnwrap(rec.requests[1].httpBody)))
        XCTAssertEqual(try PersistenceService.makeDecoder().decode(Profile.self, from: saved).friendCode, code, "今のプロフィールを預ける")
        XCTAssertTrue(app.profile.account.hasPassword)
        XCTAssertEqual(app.profile.account.lastCloudSave, Date(timeIntervalSince1970: 1_792_000_000))
        XCTAssertTrue(app.profile.inboxRegistered, "中継にデータができたので、全データの削除で消す")
    }

    func testAutoSaveOnlyForRecoverableAccountsAndAtMostEveryTenMinutes() async throws {
        let (app, dir) = makeApp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rec = Recorder()
        rec.reply("/save", 200, accountJSON)
        app.account.transport = rec.transport
        app.account.autoSave()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(rec.requests.isEmpty, "パスワードも Game Center も無いアカウントは預けない（ほかの端末で取り出せない）")
        app.profile.account.hasPassword = true
        let start = Date()
        app.account.autoSave(now: start)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(rec.requests.count, 1)
        app.account.autoSave(now: start.addingTimeInterval(60))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(rec.requests.count, 1, "10 分に 1 回まで")
        app.account.autoSave(now: Date().addingTimeInterval(AccountCenter.autoSaveInterval + 1))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(rec.requests.count, 2)
    }

    func testAccountNeedsTheOnlineRules() async {
        let (app, dir) = makeApp()
        defer { try? FileManager.default.removeItem(at: dir) }
        app.profile.acceptedOnlineRulesVersion = 0
        let rec = Recorder()
        app.account.transport = rec.transport
        let result = await app.account.setPassword("correct horse 1")
        XCTAssertEqual(result.failureValue, .notAllowed)
        XCTAssertTrue(rec.requests.isEmpty, "同意の前は中継へ何も送らない")
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let f) = self { return f }
        return nil
    }
}
