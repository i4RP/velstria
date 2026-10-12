import XCTest
@testable import VELSTRIA
import VelstriaCore

/// オンライン機能の安全対策（App Review Guidelines 1.2 / 5.1）: 不適切語のフィルタ・名前の整形・オンラインの同意と年齢・
/// 通報のメール・法務ページの URL・アプリ内のライセンス表記。
@MainActor
final class OnlineSafetyTests: XCTestCase {
    private var savedLanguage: AppLanguage = .ja

    override func setUp() {
        super.setUp()
        savedLanguage = Loc.current
        Loc.current = .ja
    }

    override func tearDown() {
        Loc.current = savedLanguage
        super.tearDown()
    }

    // MARK: - 不適切語のフィルタ

    func testFilterCatchesOffensiveWordsInCommonDisguises() {
        for name in ["fuck", "FuckYou", "ＦＵＣＫ", "f u c k", "b1tch", "Sh1tHead", "sh!t", "死ね", "チンコ", "ちんこ", "せっくす",
                     "運営スタッフ", "VELSIA公式", "Admin", "GM", "the_rapist", "TheRapist", "kys", "nazi88",
                     "SEX", "SexyBoy", "Nazi", "公式", "slut", "big_boobs", "Cunt"] {
            XCTAssertTrue(ContentFilter.isInappropriate(name), name)
        }
    }

    func testFilterLeavesOrdinaryNamesAlone() {
        // 部分一致の誤判定が起きやすい名前（日本人の姓・英単語）
        for name in ["Yamashita", "Fukuda", "Badminton", "Assassin", "Dickens", "Therapist", "Grape", "コロスケ", "シネマ好き",
                     "星環の旅人", "NovaBlade", "Player2026", "🌟🌟", "Matsushita", "Cocktail",
                     // 実在の姓・地名（部分一致だと弾いてしまう語を、単語の一致に移した）
                     "Sexton", "Essex", "Sussex", "Scunthorpe", "Penistone", "Nazira", "Slutsky", "Booboo", "Kumanko",
                     "公式戦マニア", "大麻町", "池沼太郎",
                     // 連絡先に似ているが連絡先ではないもの
                     "Mr.Bean", "J.Smith", "R@ven", "Max:Power", "Line"] {
            XCTAssertFalse(ContentFilter.isInappropriate(name), name)
        }
    }

    func testFilterRejectsContactDetails() {
        for name in ["090-1234-5678", "http://x.jp", "www.example", "me.com", "line.me/abc",
                     "me@x.io", "a@b.de", "discord.gg/x", "ｄｉｓｃｏｒｄ．ｇｇ/ab", "insta:taro", "IG@taro", "@taro", "x.com/taro", "tg:abc"] {
            XCTAssertTrue(ContentFilter.isInappropriate(name), name)
        }
        XCTAssertFalse(ContentFilter.isInappropriate("Taro123456"), "6 桁までの数字は名前に使える")
    }

    func testNameRulesRejectOffensiveNamesAndSuggestionsStayValid() {
        XCTAssertEqual(PlayerNameRules.validate("fuck"), .inappropriate)
        XCTAssertEqual(PlayerNameRules.validate("運営"), .inappropriate)
        XCTAssertFalse(PlayerNameRules.message(.inappropriate).isEmpty)
        XCTAssertNil(PlayerNameRules.validate("Yamashita"))
        for seed in UInt64(0)..<200 {
            XCTAssertNil(PlayerNameRules.validate(PlayerNameRules.suggestion(seed: seed, english: false)))
            XCTAssertNil(PlayerNameRules.validate(PlayerNameRules.suggestion(seed: seed, english: true)))
        }
    }

    func testRemoteNamesAreCleanedClippedAndHidden() {
        XCTAssertEqual(PlayerNameRules.sanitizedRemote("  Taro\n"), "Taro")
        XCTAssertEqual(PlayerNameRules.sanitizedRemote(String(repeating: "a", count: 40)).count, PlayerNameRules.maxLength)
        XCTAssertEqual(PlayerNameRules.sanitizedRemote("\u{0007}bitch"), "")
        XCTAssertEqual(PlayerNameRules.sanitizedRoomName("Taro のパーティ"), "Taro のパーティ")
        XCTAssertEqual(PlayerNameRules.sanitizedRoomName("死ね のパーティ"), "")
        XCTAssertEqual(PlayerNameRules.sanitizedRoomName(String(repeating: "あ", count: 60)).count, 40)
    }

    /// 画面に出す選手の名前: 不適切な名前は隠し、普通の名前と AI の名前（12 文字を超えるものを含む）はそのまま出す。
    func testShownNamesHideOffensiveNamesButKeepAINames() {
        XCTAssertEqual(PlayerNameRules.shown("fuck"), "プレイヤー")
        XCTAssertEqual(PlayerNameRules.shown("me@x.io"), "プレイヤー")
        XCTAssertEqual(PlayerNameRules.shown("Taro"), "Taro")
        XCTAssertEqual(PlayerNameRules.shown("Taro\u{0007}"), "Taro")
        for hero in MasterData.shared.allHeroes {
            let ai = "\(hero.codeName)_AI"
            XCTAssertEqual(PlayerNameRules.shown(ai), ai, "AI の名前を隠さない: \(ai)")
        }
        Loc.current = .en
        XCTAssertEqual(PlayerNameRules.shown("fuck"), "Player", "言語を切り替えたら代わりの名前も切り替わる")
        XCTAssertTrue(PlayerNameRules.isReplacedOnline("fuck"))
        XCTAssertFalse(PlayerNameRules.isReplacedOnline("Taro"))
        XCTAssertFalse(PlayerNameRules.isReplacedOnline(""), "未設定の名前は「プレイヤー」と出るのが普通なので知らせない")
    }

    func testOutgoingNameNeverSendsAnInvalidStoredName() {
        XCTAssertEqual(PlayerNameRules.outgoing(" Taro "), "Taro")
        XCTAssertEqual(PlayerNameRules.outgoing("fuck"), "プレイヤー", "フィルタの導入前に保存された名前は送らない")
        XCTAssertEqual(PlayerNameRules.outgoing("a"), "プレイヤー")
    }

    // MARK: - 同意と年齢

    func testOnlineAccessNeedsConsentAndExcludesUnder13() {
        var p = Profile()
        XCTAssertEqual(OnlineAccess.status(for: p, enabled: false), .disabled)
        XCTAssertEqual(OnlineAccess.status(for: p, enabled: true), .ageRestricted, "年齢の申告前は 13 歳未満として扱う")
        p.ageBracket = .under13
        p.acceptedOnlineRulesVersion = FeatureFlags.currentOnlineRulesVersion
        XCTAssertEqual(OnlineAccess.status(for: p, enabled: true), .ageRestricted)
        p.ageBracket = .age13to15
        p.acceptedOnlineRulesVersion = 0
        XCTAssertEqual(OnlineAccess.status(for: p, enabled: true), .needsConsent)
        p.acceptedOnlineRulesVersion = FeatureFlags.currentOnlineRulesVersion
        XCTAssertEqual(OnlineAccess.status(for: p, enabled: true), .available)
        p.acceptedOnlineRulesVersion = FeatureFlags.currentOnlineRulesVersion - 1
        XCTAssertEqual(OnlineAccess.status(for: p, enabled: true), .needsConsent, "ルールの版が上がったら同意し直す")
    }

    func testAppModelGatesOnlineUntilConsentAndRevokes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OnlineSafety-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = AppModel(persistence: PersistenceService(directory: dir))
        // 単体テストでは中継サーバーへ繋がない（受信箱は無効のまま。申請は送り直し待ちとして記録だけされる）
        app.friends.isEnabled = { false }
        app.profile.onboardingCompleted = true
        app.profile.ageBracket = .adult
        app.profile.displayName = "Taro"
        app.ensurePartyRoom()
        XCTAssertNil(app.online, "ルールに同意する前は部屋を作らない（LAN の広告もしない）")
        // 同意前に開いた招待・フレンドのリンクは、同意の画面へ回してから開き直す
        XCTAssertTrue(app.openOnlineJoinLink(try XCTUnwrap(URL(string: "velstria://join?code=QZ7K4P"))))
        XCTAssertNil(app.online)
        XCTAssertTrue(app.openFriendLink(try XCTUnwrap(URL(string: "velstria://friend?code=ABCDEFGH&name=Hana"))))
        XCTAssertTrue(app.profile.outgoingFriendRequests.isEmpty)
        XCTAssertEqual(app.router.path.last, .onlineLobby)
        app.acceptOnlineRules()
        XCTAssertEqual(app.profile.acceptedOnlineRulesVersion, FeatureFlags.currentOnlineRulesVersion)
        XCTAssertEqual(app.profile.outgoingFriendRequests, ["ABCDEFGH"], "同意したら待たせていたリンク（最後のもの）を開く")
        app.revokeOnlineRules()
        XCTAssertNil(app.online)
        XCTAssertEqual(app.onlineAccess, .needsConsent)

        // 13 歳未満はリンクでも使えない
        app.profile.ageBracket = .under13
        app.profile.acceptedOnlineRulesVersion = FeatureFlags.currentOnlineRulesVersion
        XCTAssertTrue(app.openFriendLink(try XCTUnwrap(URL(string: "velstria://friend?code=JKMNPQRS"))))
        XCTAssertEqual(app.profile.outgoingFriendRequests, ["ABCDEFGH"])
        app.ensurePartyRoom()
        XCTAssertNil(app.online)
    }

    // MARK: - 通報のメール

    func testPlayerReportMailCarriesTargetButNotReporterPlayerID() throws {
        var me = Profile()
        me.friendCode = "ABCDEFGH"
        let target = PlayerReportTarget(name: "Rude", friendCode: "JKMNPQRS", peerID: "PEER-UUID", source: .party, roomCode: "QZ7K4P",
                                        detail: "Seed: 1")
        let body = PlayerReportMail.body(target: target, reason: .harassment, message: "  bad words  ", reporterCode: me.friendCode,
                                         date: Date(timeIntervalSince1970: 0), appVersion: "1.0.0 (1)", systemVersion: "26.0")
        for part in ["bad words", "Rude", "JKMN PQRS", "PEER-UUID", PlayerReportTarget.Source.party.title, "QZ7 K4P",
                     "Seed: 1", "ABCD EFGH", PlayerReportReason.harassment.title, "1970-01-01T00:00:00Z"] {
            XCTAssertTrue(body.contains(part), "\(part) が本文に無い: \(body)")
        }
        XCTAssertFalse(body.contains(me.playerID), "通報した人のプレイヤー ID は入れない")
        let url = try XCTUnwrap(PlayerReportMail.url(subject: PlayerReportMail.subject(.harassment), body: body))
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:\(FeatureFlags.supportEmail)?subject="))
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.queryItems?.first { $0.name == "body" }?.value, body)
        XCTAssertEqual(comps.queryItems?.first { $0.name == "subject" }?.value, "[VELSIA] Player Report: Harassment")
        XCTAssertEqual(Set(PlayerReportReason.allCases.map(\.subjectTag)).count, PlayerReportReason.allCases.count)
    }

    func testReportWithoutFriendCodeSaysUnknown() {
        let target = PlayerReportTarget(name: "", source: .match)
        let body = PlayerReportMail.body(target: target, reason: .other, message: "", reporterCode: "bad", date: Date(),
                                         appVersion: "1", systemVersion: "26")
        XCTAssertTrue(body.contains("不明"))
        XCTAssertTrue(body.contains("（未記入）"))
        XCTAssertEqual(target.displayName, "プレイヤー")
    }

    // MARK: - 公開ページとライセンス

    func testSafetyURLsFollowDisplayLanguageAndUseSiteHost() {
        func urls() -> [URL] {
            [FeatureFlags.communityGuidelinesURL, FeatureFlags.legalIndexURL, FeatureFlags.licensesURL,
             FeatureFlags.safetyURL, FeatureFlags.privacyChoicesURL, FeatureFlags.externalTransmissionURL]
        }
        let ja = urls()
        XCTAssertEqual(ja.map(\.path), ["/community", "/legal", "/licenses", "/safety", "/privacy-choices", "/external-transmission"])
        Loc.current = .en
        let en = urls()
        XCTAssertEqual(en.map(\.path), ["/en/community", "/en/legal", "/en/licenses", "/en/safety", "/en/privacy-choices", "/en/external-transmission"])
        for url in ja + en {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, FeatureFlags.privacyPolicyURLJa.host)
        }
    }

    /// アプリに静的リンクしている Effekseer（MIT）の表記が、同梱のライセンス本文と一致する。
    func testCreditsCarryEffekseerLicenseVerbatim() throws {
        let licenseURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ThirdParty/Effekseer/LICENSE.txt")
        let file = try String(contentsOf: licenseURL, encoding: .utf8)
        let normalize: (String) -> String = { $0.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertEqual(normalize(CreditsCatalog.effekseerLicense), normalize(file))
        XCTAssertTrue(CreditsCatalog.openSource.contains { $0.name == "Effekseer" && $0.license == "MIT License" })
    }

    /// Effekseer に含まれる stb_image（MIT）と LLGI（zlib）の表記が、公開サイトのライセンス表記（docs/legal/licenses/）と一致する。
    func testCreditsCarryBundledLibraryLicensesVerbatim() throws {
        let licenses = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/legal/licenses")
        let normalize: (String) -> String = { $0.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
        for (name, license, file) in [("stb_image", "MIT License", "stb-image.txt"), ("LLGI", "zlib License", "llgi.txt")] {
            let text = try String(contentsOf: licenses.appendingPathComponent(file), encoding: .utf8)
            let entry = try XCTUnwrap(CreditsCatalog.openSource.first { $0.name == name }, name)
            XCTAssertEqual(entry.license, license)
            XCTAssertEqual(normalize(entry.text), normalize(text), name)
        }
    }

    func testSupportHasAbuseCategory() {
        XCTAssertTrue(SupportCategory.allCases.contains(.safety))
        XCTAssertEqual(SupportMail.subject(.safety), "[VELSIA] Safety")
    }
}
