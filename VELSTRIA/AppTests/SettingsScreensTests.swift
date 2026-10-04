import XCTest
import UserNotifications
@testable import VELSTRIA
import VelstriaCore

// 担当: ui-liveops。設定・サポート画面のロジック（初期化・お問い合わせメール・通知・FAQ・パッチノート）。

final class SettingsScreensTests: XCTestCase {
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

    func testResetKeepsLanguageAndNotificationChoice() {
        var s = GameSettings()
        s.language = .en
        s.notificationsEnabled = true
        s.hudOpacity = 0.5
        s.joystickMode = .fixed
        s.bgmVolume = 0.1
        s.topAttackPriority = .lowestHealth
        s.attackPriority = .minionsFirst
        s.bottomAttackPriority = .heroesFirst
        let reset = SettingsDefaults.reset(s)
        XCTAssertEqual(reset.language, .en)
        XCTAssertTrue(reset.notificationsEnabled)
        XCTAssertEqual(reset.hudOpacity, GameSettings().hudOpacity)
        XCTAssertEqual(reset.joystickMode, GameSettings().joystickMode)
        XCTAssertEqual(reset.bgmVolume, GameSettings().bgmVolume)
        XCTAssertEqual(reset.topAttackPriority, .structuresFirst)
        XCTAssertEqual(reset.attackPriority, .heroesFirst)
        XCTAssertEqual(reset.bottomAttackPriority, .minionsFirst)
    }

    /// 音は既定でミュート（BGM・効果音とも 0）。初期値に戻す・旧版からの移行でも 0 になる。
    /// TestFlight へ上げる前の CI でこのテストを回し、古い既定（効果音 80%・BGM 70%）への逆戻りを止める。
    func testAudioDefaultsAreMuted() {
        XCTAssertEqual(GameSettings().bgmVolume, 0)
        XCTAssertEqual(GameSettings().sfxVolume, 0)
        var s = GameSettings()
        s.bgmVolume = 0.7
        s.sfxVolume = 0.8
        let reset = SettingsDefaults.reset(s)
        XCTAssertEqual(reset.bgmVolume, 0)
        XCTAssertEqual(reset.sfxVolume, 0)
        // 旧版（v1: BGM 70%・効果音 80% / v2: 効果音 80%）の保存データも 0 になる
        for version in [1, 2] {
            var object: [String: Any] = ["schemaVersion": version,
                                         "settings": ["bgmVolume": 0.7, "sfxVolume": 0.8, "voiceVolume": 0.8]]
            ProfileMigrator.migrate(&object, from: version)
            let settings = object["settings"] as? [String: Any]
            XCTAssertEqual((settings?["sfxVolume"] as? NSNumber)?.doubleValue, 0, "v\(version) の効果音")
            if version == 1 { XCTAssertEqual((settings?["bgmVolume"] as? NSNumber)?.doubleValue, 0, "v1 の BGM") }
        }
    }

    func testAttackButtonDefaultsFollowTopCenterBottomOrder() {
        let settings = GameSettings()
        XCTAssertEqual(AttackButtonSlot.allCases, [.top, .center, .bottom])
        XCTAssertEqual(settings.attackPriority(for: .top), .structuresFirst)
        XCTAssertEqual(settings.attackPriority(for: .center), .heroesFirst)
        XCTAssertEqual(settings.attackPriority(for: .bottom), .minionsFirst)
    }

    func testAttackButtonSettingsRoundTripIndependently() throws {
        var settings = GameSettings()
        settings.topAttackPriority = .lowestHealth
        settings.attackPriority = .minionsFirst
        settings.bottomAttackPriority = .heroesFirst
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(GameSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.attackPriority(for: .top), .lowestHealth)
        XCTAssertEqual(decoded.attackPriority(for: .center), .minionsFirst)
        XCTAssertEqual(decoded.attackPriority(for: .bottom), .heroesFirst)
    }

    func testLegacyProfileDecodingPreservesSettingsAndAddsAttackButtons() throws {
        var profile = Profile()
        profile.displayName = "Existing player"
        profile.starlightCoin = 123
        profile.settings.attackPriority = .lowestHealth
        profile.settings.language = .en
        profile.settings.bgmVolume = 0.25
        profile.settings.hapticsEnabled = false
        profile.settings.leftHandedLayout = true
        profile.settings.joystickMode = .fixed
        profile.settings.skillCastMode = .manual
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        settings.removeValue(forKey: "topAttackPriority")
        settings.removeValue(forKey: "bottomAttackPriority")
        object["settings"] = settings

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.settings.attackPriority(for: .top), .structuresFirst)
        XCTAssertEqual(decoded.settings.attackPriority(for: .center), .lowestHealth)
        XCTAssertEqual(decoded.settings.attackPriority(for: .bottom), .minionsFirst)
    }

    func testMissingAttackSettingsDecodeWithDefaults() throws {
        let decoded = try JSONDecoder().decode(GameSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, GameSettings())
    }

    @MainActor
    func testSettingsBindingWritesThroughProfile() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SettingsTests-\(UUID().uuidString)", isDirectory: true)
        let app = AppModel(persistence: PersistenceService(directory: dir))
        let binding = settingsBinding(app, \.hudOpacity)
        binding.wrappedValue = 0.6
        XCTAssertEqual(app.profile.settings.hudOpacity, 0.6)
        settingsBinding(app, \.attackPriority).wrappedValue = .lowestHealth
        XCTAssertEqual(app.profile.settings.attackPriority, .lowestHealth)
        settingsBinding(app, \.topAttackPriority).wrappedValue = .minionsFirst
        settingsBinding(app, \.bottomAttackPriority).wrappedValue = .structuresFirst
        XCTAssertEqual(app.profile.settings.attackPriority(for: .top), .minionsFirst)
        XCTAssertEqual(app.profile.settings.attackPriority(for: .center), .lowestHealth)
        XCTAssertEqual(app.profile.settings.attackPriority(for: .bottom), .structuresFirst)
        XCTAssertEqual(binding.wrappedValue, 0.6)
    }

    func testSettingsTextCoversAllOptionsInBothLanguages() {
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            for m in JoystickMode.allCases {
                XCTAssertFalse(SettingsText.joystick(m).isEmpty)
                XCTAssertFalse(SettingsText.joystickDetail(m).isEmpty)
            }
            for m in SkillCastMode.allCases { XCTAssertFalse(SettingsText.castModeDetail(m).isEmpty) }
            for p in SettingsText.allPriorities {
                XCTAssertFalse(SettingsText.attackPriorityDetail(p).isEmpty)
                XCTAssertFalse(SettingsText.attackPrioritySymbol(p).isEmpty)
            }
            for slot in AttackButtonSlot.allCases { XCTAssertFalse(SettingsText.attackButtonSlot(slot).isEmpty) }
            for q in GraphicsQuality.allCases { XCTAssertFalse(SettingsText.qualityDetail(q).isEmpty) }
            for f in FrameRateOption.allCases { XCTAssertFalse(SettingsText.frameRateDetail(f).isEmpty) }
            for l in AppLanguage.allCases { XCTAssertFalse(SettingsText.language(l).isEmpty) }
        }
        XCTAssertEqual(Set(SettingsText.allPriorities.map(\.rawValue)).count, 4)
        XCTAssertEqual(SettingsText.percent(0.7), "70%")
        XCTAssertEqual(SettingsText.language(.ja), "日本語")
        XCTAssertEqual(SettingsText.language(.en), "English")
    }

    // MARK: お問い合わせ

    private let info = SupportDeviceInfo(appVersion: "1.0.0", build: "7", device: "iPhone17,3", os: "iOS 18.4.0",
                                         playerID: "PLAYER-1", language: "ja")

    func testSupportMailURLEncodesSubjectAndBody() throws {
        let message = "対戦中に落ちました & 再現 = 100% #1 + α?\n2 行目"
        let url = try XCTUnwrap(SupportMail.url(to: "support@velstria.example", category: .bug, message: message, info: info))
        XCTAssertEqual(url.scheme, "mailto")
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.path, "support@velstria.example")
        let items = try XCTUnwrap(comps.queryItems)
        XCTAssertEqual(items.map(\.name), ["subject", "body"])
        XCTAssertEqual(items[0].value, "[VELSTRIA] Bug")
        let body = try XCTUnwrap(items[1].value)
        XCTAssertTrue(body.hasPrefix(message))
        XCTAssertTrue(body.contains("App: VELSTRIA 1.0.0 (7)"))
        XCTAssertTrue(body.contains("Device: iPhone17,3"))
        XCTAssertTrue(body.contains("Player ID: PLAYER-1"))
    }

    func testSupportMailTrimsMessageAndUsesFixedTags() {
        XCTAssertTrue(SupportMail.body(message: "  hello \n", info: info).hasPrefix("hello\n\n---\n"))
        XCTAssertEqual(Set(SupportCategory.allCases.map(\.subjectTag)).count, SupportCategory.allCases.count)
        XCTAssertEqual(SupportMail.encode("a b&c=d"), "a%20b%26c%3Dd")
        XCTAssertEqual(SupportMail.encode("日本"), "%E6%97%A5%E6%9C%AC")
    }

    func testAppVersionInfoIsPopulated() {
        XCTAssertFalse(AppVersionInfo.version.isEmpty)
        XCTAssertFalse(AppVersionInfo.build.isEmpty)
        XCTAssertFalse(AppVersionInfo.deviceModel.isEmpty)
        XCTAssertTrue(AppVersionInfo.systemVersion.hasPrefix("iOS "))
    }

    // MARK: 通知

    func testDailyReminderRequest() throws {
        XCTAssertEqual(DailyReminder.identifier, "velstria.daily")
        let ja = DailyReminder.makeRequest(language: .ja)
        XCTAssertEqual(ja.identifier, "velstria.daily")
        XCTAssertEqual(ja.content.body, "デイリーミッションが更新されました")
        XCTAssertEqual(DailyReminder.makeRequest(language: .en).content.body, "Daily missions have been refreshed")
        let trigger = try XCTUnwrap(ja.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 19)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertNil(trigger.dateComponents.day)
        XCTAssertEqual(DailyReminder.timeText(), "19:00")
        XCTAssertTrue(DailyReminder.isAllowed(.authorized))
        XCTAssertTrue(DailyReminder.isAllowed(.provisional))
        XCTAssertFalse(DailyReminder.isAllowed(.denied))
        XCTAssertFalse(DailyReminder.isAllowed(.notDetermined))
    }

    // MARK: コンテンツ

    func testFAQCatalogIsCompleteAndBilingual() {
        let entries = FAQCatalog.entries
        XCTAssertGreaterThanOrEqual(entries.count, 12)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        for c in FAQEntry.Category.allCases {
            XCTAssertFalse(entries.filter { $0.category == c }.isEmpty, "\(c) に FAQ が無い")
        }
        for e in entries {
            XCTAssertFalse(e.questionJa.isEmpty)
            XCTAssertFalse(e.questionEn.isEmpty)
            XCTAssertFalse(e.answerJa.isEmpty)
            XCTAssertFalse(e.answerEn.isEmpty)
        }
        // 年齢別の課金上限は DESIGN §12 と一致させる
        let limits = entries.first { $0.id == "safety_limits" }
        XCTAssertTrue(limits?.answerJa.contains("5,000") == true)
        XCTAssertTrue(limits?.answerJa.contains("10,000") == true)
    }

    func testPatchNotesCoverCurrentVersionInBothLanguages() {
        let current = PatchNotesCatalog.notes.first { $0.version == "1.0.0" }
        XCTAssertNotNil(current)
        for section in current?.sections ?? [] {
            XCTAssertFalse(section.itemsJa.isEmpty)
            XCTAssertEqual(section.itemsJa.count, section.itemsEn.count, section.id)
        }
        Loc.current = .en
        XCTAssertEqual(current?.headline, current?.headlineEn)
    }

    func testCreditsMentionTechnologies() {
        XCTAssertEqual(CreditsCatalog.technologies, ["SwiftUI", "RealityKit", "StoreKit"])
        XCTAssertFalse(CreditsCatalog.roles.isEmpty)
    }
}
