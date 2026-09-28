import XCTest

// 担当: ui-liveops。ライブオプス・設定画面の UI テスト（DebugLaunch の -route で直行）。

final class LiveOpsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(route: String, language: String = "ja") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-skipOnboarding", "-grant", "-route", route, "-language", language]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    func testLiveOpsScreensShowPrimaryControls() {
        let expectations: [(String, String)] = [
            ("missions", "missions_tab_weekly"),
            ("starPass", "starpass_premium_info"),
            ("spectateSetup", "spectate_start"),
            ("tutorialMenu", "tutorial_start"),
            ("practiceSetup", "practice_start"),
            ("events", "nav_back"),
            ("replays", "nav_back"),
        ]
        for (route, id) in expectations {
            let app = launch(route: route)
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 10), "\(route): \(id) が見つからない")
            app.terminate()
        }
    }

    func testSettingsHubOpensSubscreensAndSwitchesLanguage() {
        let app = launch(route: "settings")
        let controls = element(app, "settings_controls")
        XCTAssertTrue(controls.waitForExistence(timeout: 10))
        controls.tap()
        XCTAssertTrue(element(app, "controls_joystick_0").waitForExistence(timeout: 5))
        element(app, "nav_back").tap()

        let language = element(app, "settings_language")
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.tap()
        let english = element(app, "language_en")
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        english.tap()
        // 即時に英語表示へ切り替わる
        XCTAssertTrue(app.staticTexts["Language"].waitForExistence(timeout: 5))
        element(app, "language_ja").tap()
        XCTAssertTrue(app.staticTexts["言語"].waitForExistence(timeout: 5))
    }

    func testPracticeOptionToggles() {
        let app = launch(route: "practiceSetup")
        let toggle = element(app, "practice_no_cooldowns")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        // Toggle はスイッチとして 0 / 1 の値を公開する
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(element(app, "practice_hero_H010").exists)
    }

    func testFAQExpandsAnswer() {
        let app = launch(route: "faq", language: "en")
        let question = element(app, "faq_gameplay_offline")
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        question.tap()
        let answer = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "no internet connection is needed")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
    }

    func testDeleteAllDataRequiresTwoConfirmations() {
        let app = launch(route: "privacySettings")
        let delete = element(app, "privacy_delete_all")
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        // 1 段目: 画面内の確認
        let proceed = element(app, "privacy_delete_continue")
        XCTAssertTrue(proceed.waitForExistence(timeout: 5))
        proceed.tap()
        // 2 段目: 最終確認アラート
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["完全に削除する"].tap()
        // プロフィールが初期化され、プライバシー画面から離れる
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5))
    }
}
