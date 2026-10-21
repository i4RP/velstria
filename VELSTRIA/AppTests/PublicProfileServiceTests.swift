import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 第3段: 公開の名刺・ランキング・運営からのメール（relay の Directory。通信は差し替えた送り手で確かめる）。
@MainActor
final class PublicProfileServiceTests: XCTestCase {
    /// 送った要求を覚え、決まった応答を返す送り手。
    private final class FakeRelay: @unchecked Sendable {
        var requests: [URLRequest] = []
        var status = 200
        var body = Data()

        var transport: FriendInboxEraser.Transport {
            { [self] request in
                self.requests.append(request)
                let resp = HTTPURLResponse(url: request.url!, statusCode: self.status, httpVersion: nil, headerFields: nil)!
                return (self.body, resp)
            }
        }

        func json(_ text: String) { body = Data(text.utf8) }

        func lastBody() -> [String: Any] {
            guard let data = requests.last?.httpBody else { return [:] }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
    }

    private static let profileJSON = #"""
    {"code":"ABCD2345","name":"Alice","avatar":"H027","level":30,"country":"JP",
     "heroes":[{"heroID":"H027","matches":40,"wins":25}],"matches":120,"wins":70,
     "rank":{"tier":5,"division":2,"stars":3},"seasonBest":{"tier":6,"division":0,"stars":12},"highest":{"tier":6,"division":0,"stars":30},
     "seasonWins":20,"seasonLosses":11,"updatedAt":"2026-10-21T08:00:00.123Z","lastSeen":"2026-10-21T09:30:00.000Z"}
    """#

    private func card() -> PublicCardPayload {
        PublicCardPayload(name: "Bob", avatar: "H027", frame: nil, level: 5, country: "JP", heroes: [], matches: 3, wins: 1)
    }

    func testLoadDecodesProfilesAndCachesThem() async {
        let relay = FakeRelay()
        relay.json(#"{"ok":true,"profiles":[\#(Self.profileJSON)]}"#)
        let s = PublicProfileService()
        s.transport = relay.transport
        s.isAllowed = { true }
        await s.load(["ABCD2345", "WXYZ6789", "bad"])
        XCTAssertEqual(relay.requests.count, 1)
        XCTAssertEqual(relay.requests.first?.url?.path, "/v1/profiles")
        XCTAssertEqual(relay.lastBody()["codes"] as? [String], ["ABCD2345", "WXYZ6789"], "正しいコードだけ送る")
        let p = s.profiles["ABCD2345"]
        XCTAssertEqual(p?.name, "Alice")
        XCTAssertEqual(p?.seasonBest, PublicRank(tier: 6, division: 0, stars: 12))
        XCTAssertNotNil(p?.lastSeen, "ミリ秒つきの日時も読める")
        XCTAssertNil(s.profiles["WXYZ6789"])
        // キャッシュの間は取り直さない。force なら取り直す
        await s.load(["ABCD2345"])
        XCTAssertEqual(relay.requests.count, 1)
        await s.load(["ABCD2345"], force: true)
        XCTAssertEqual(relay.requests.count, 2)
    }

    func testNothingIsSentWithoutConsent() async {
        let relay = FakeRelay()
        let s = PublicProfileService()
        s.transport = relay.transport
        s.isAllowed = { false }
        s.own = { ("ABCD2345", "k_0123456789abcdef", self.card()) }
        await s.load(["ABCD2345"])
        let sent = await s.publishOwn()
        XCTAssertFalse(sent)
        XCTAssertTrue(relay.requests.isEmpty, "同意していなければ通信しない")
        let ranking = RankingService()
        ranking.transport = relay.transport
        ranking.isAllowed = { false }
        await ranking.load(.global)
        XCTAssertTrue(relay.requests.isEmpty)
        XCTAssertNotNil(ranking.lastError)
    }

    func testPublishSendsTheCardWithTheKeyOnlyWhenItChanged() async {
        let relay = FakeRelay()
        relay.json(#"{"ok":true,"profile":\#(Self.profileJSON)}"#)
        let s = PublicProfileService()
        s.transport = relay.transport
        s.isAllowed = { true }
        var current = card()
        s.own = { ("ABCD2345", "k_0123456789abcdef", current) }
        let first = await s.publishOwn()
        XCTAssertTrue(first)
        XCTAssertEqual(relay.requests.first?.url?.path, "/v1/profile/ABCD2345/put")
        XCTAssertEqual(relay.lastBody()["key"] as? String, "k_0123456789abcdef", "鍵は本文に入れる（URL に載せない）")
        XCTAssertEqual((relay.lastBody()["profile"] as? [String: Any])?["name"] as? String, "Bob")
        XCTAssertNil((relay.lastBody()["profile"] as? [String: Any])?["rank"], "ランクは送らない")
        _ = await s.publishOwn()
        XCTAssertEqual(relay.requests.count, 1, "変わっていなければ送らない")
        current.matches = 4
        _ = await s.publishOwn()
        XCTAssertEqual(relay.requests.count, 2)
        s.forgetPublished()
        _ = await s.publishOwn()
        XCTAssertEqual(relay.requests.count, 3, "忘れた後は送り直す")
    }

    func testRankingSendsTheScopeAndKeepsThePage() async {
        let relay = FakeRelay()
        relay.json(#"{"ok":true,"entries":[{"position":1,"profile":\#(Self.profileJSON)}],"me":null}"#)
        let r = RankingService()
        r.transport = relay.transport
        r.isAllowed = { true }
        r.myCode = { "WXYZ6789" }
        r.friendCodes = { ["ABCD2345", "nope"] }
        await r.load(.friends)
        XCTAssertEqual(relay.requests.first?.url?.path, "/v1/ranking")
        XCTAssertEqual(relay.lastBody()["scope"] as? String, "friends")
        XCTAssertEqual(relay.lastBody()["codes"] as? [String], ["ABCD2345"])
        XCTAssertEqual(relay.lastBody()["me"] as? String, "WXYZ6789")
        XCTAssertEqual(r.pages[.friends]?.entries.first?.profile.code, "ABCD2345")
        XCTAssertNil(r.pages[.friends]?.me, "範囲の外（ランク外）")
        XCTAssertNil(r.lastError)
        await r.load(.country("JP"))
        XCTAssertEqual(relay.lastBody()["scope"] as? String, "country")
        XCTAssertEqual(relay.lastBody()["country"] as? String, "JP")
        // 失敗は文を残し、前のページは消さない
        relay.status = 500
        await r.load(.friends, force: true)
        XCTAssertNotNil(r.lastError)
        XCTAssertNotNil(r.pages[.friends])
    }

    // MARK: 運営からのメール

    private func opsMail(_ id: String, important: Bool = false, category: String = "system", starts: Double = 1_800_000_000_000,
                         expires: Double = 1_805_000_000_000, attachments: [MailAttachment] = []) -> OpsMail {
        OpsMail(id: id, titleJa: "お知らせ", titleEn: "Notice", bodyJa: "本文", bodyEn: "Body", attachments: attachments,
                important: important, category: category, startsAt: starts, expiresAt: expires)
    }

    func testOpsMailIsMergedOnceAndExpiredMailIsSkipped() {
        var p = Profile()
        let before = p.mail.count
        let now = Date(timeIntervalSince1970: 1_800_100_000)
        let list = [
            opsMail("ops_a", important: true, category: "important", attachments: [MailAttachment(kind: .coin, amount: 500)]),
            opsMail("ops_b", category: "gift"),
            opsMail("ops_old", expires: 1_800_000_500_000),
        ]
        XCTAssertEqual(OpsMailService.merge(list, into: &p, now: now), 2)
        XCTAssertEqual(p.mail.count, before + 2)
        let a = p.mail.first { $0.opsID == "ops_a" }
        XCTAssertEqual(a?.important, true)
        XCTAssertEqual(a?.category, .important)
        XCTAssertEqual(a?.attachments, [MailAttachment(kind: .coin, amount: 500)])
        XCTAssertEqual(p.mail.first { $0.opsID == "ops_b" }?.category, .gift)
        XCTAssertTrue(p.seenOpsMailIDs.contains("ops_old"), "期限切れも見た物として覚える")
        // 二度目は入れない。消したメールも戻さない
        XCTAssertEqual(OpsMailService.merge(list, into: &p, now: now), 0)
        p.mail.removeAll { $0.opsID == "ops_a" }
        XCTAssertEqual(OpsMailService.merge(list, into: &p, now: now), 0)
        // 知らない種類は重要の印から決める
        XCTAssertEqual(OpsMailService.merge([opsMail("ops_c", important: true, category: "???")], into: &p, now: now), 1)
        XCTAssertEqual(p.mail.first { $0.opsID == "ops_c" }?.category, .important)
    }

    func testOldMailWithoutTheNewFieldsStillDecodes() throws {
        let old = #"{"id":"6B9E1D3C-1B1B-4F5A-9C7E-1234567890AB","date":0,"title":"t","body":"b","attachments":[],"read":false,"claimed":false}"#
        let m = try JSONDecoder().decode(MailItem.self, from: Data(old.utf8))
        XCTAssertNil(m.important)
        XCTAssertNil(m.opsID)
        XCTAssertNil(m.category)
    }
}
