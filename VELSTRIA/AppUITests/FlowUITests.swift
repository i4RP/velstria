import XCTest

// 担当: ui-flow。オンボーディング → ホーム → 対戦フロー（通常戦・ランク戦ドラフト）→ ロード → リザルトの通し UI テスト。
// 各ステップのスクリーンショットを添付（xcresult から書き出して見た目の確認に使う）。

final class FlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"] + args
        app.launch()
        return app
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func tap(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10) -> XCUIElement {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "\(id) が表示されない")
        e.tap()
        return e
    }

    func testOnboardingReachesHome() {
        let app = launch(["-language", "ja"])
        XCTAssertTrue(element(app, "onb_start").waitForExistence(timeout: 15))
        snap("onb_01_splash")
        tap(app, "onb_start")

        XCTAssertTrue(element(app, "onb_age_2").waitForExistence(timeout: 5))
        tap(app, "onb_age_2")
        snap("onb_02_age")
        tap(app, "onb_age_next")

        XCTAssertTrue(element(app, "onb_terms_accept").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "onb_terms_next").isEnabled, "同意前は進めない")
        tap(app, "onb_terms_accept")
        snap("onb_03_terms")
        tap(app, "onb_terms_next")

        let field = element(app, "onb_name_field")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("P")
        XCTAssertFalse(element(app, "onb_name_next").isEnabled, "1 文字では進めない")
        field.typeText("ilot")
        snap("onb_04_name")
        tap(app, "onb_name_next")

        XCTAssertTrue(element(app, "onb_prepare_progress").waitForExistence(timeout: 5))
        snap("onb_05_prepare")

        XCTAssertTrue(element(app, "onb_tutorial_skip").waitForExistence(timeout: 30))
        snap("onb_06_tutorial")
        tap(app, "onb_tutorial_skip")

        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 10))
        snap("home_ja")
    }

    func testHomeMetaScreens() {
        let app = launch(["-skipOnboarding", "-grant", "-language", "ja"])
        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 15))
        for (id, name) in [("home_profile", "profile"), ("home_mail", "mail"), ("home_notices", "notices"),
                           ("home_records", "records"), ("home_rank", "rank")] {
            tap(app, id)
            XCTAssertTrue(element(app, "nav_back").waitForExistence(timeout: 5), "\(name) に戻るボタンがない")
            snap("meta_\(name)")
            tap(app, "nav_back")
            XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 5))
        }
    }

    func testStandardMatchFlowToResult() {
        let app = launch(["-skipOnboarding", "-grant", "-language", "ja"])
        tap(app, "home_play", timeout: 15)
        XCTAssertTrue(element(app, "flow_mode_standard").waitForExistence(timeout: 5))
        tap(app, "flow_difficulty_2")
        snap("flow_01_mode")
        tap(app, "flow_mode_standard")

        tap(app, "flow_hero_H003")
        snap("flow_02_hero")
        tap(app, "flow_spell_0")
        XCTAssertTrue(element(app, "flow_spellpick_BS07").waitForExistence(timeout: 5))
        snap("flow_03_spells")
        tap(app, "flow_spellpick_BS07")
        tap(app, "flow_next")

        XCTAssertTrue(element(app, "flow_confirm").waitForExistence(timeout: 5))
        snap("flow_04_ready")
        tap(app, "flow_confirm")

        XCTAssertTrue(element(app, "loading_progress").waitForExistence(timeout: 10))
        snap("flow_05_loading")

        tap(app, "battle_stub_simulate", timeout: 20)
        XCTAssertTrue(element(app, "result_close").waitForExistence(timeout: 900))
        sleep(2)
        snap("result_01_table")
        tap(app, "result_tab_eval")
        snap("result_02_eval")
        tap(app, "result_tab_rewards")
        sleep(3)
        snap("result_03_rewards")
        tap(app, "result_report")
        XCTAssertTrue(element(app, "report_send").waitForExistence(timeout: 5))
        snap("result_04_report")
        tap(app, "report_close")
        tap(app, "result_close", timeout: 5)
        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 10))
    }

    func testRankedDraft() {
        let app = launch(["-skipOnboarding", "-language", "ja"])
        tap(app, "home_play", timeout: 15)
        tap(app, "flow_mode_ranked")

        // プレイヤーの BAN（未所持ヒーローも BAN できる）
        XCTAssertTrue(element(app, "flow_draft_timer").waitForExistence(timeout: 10))
        tap(app, "flow_hero_H010")
        snap("draft_01_ban")
        tap(app, "flow_lock")

        // AI の BAN 3 回の後、プレイヤーのピック（B1）
        sleep(1)
        XCTAssertTrue(element(app, "flow_draft_timer").waitForExistence(timeout: 20))
        tap(app, "flow_hero_H003")
        snap("draft_02_pick")
        tap(app, "flow_lock")

        XCTAssertTrue(element(app, "flow_next").waitForExistence(timeout: 40))
        snap("draft_03_done")
        tap(app, "flow_position_2")
        tap(app, "flow_next")
        XCTAssertTrue(element(app, "flow_confirm").waitForExistence(timeout: 5))
        snap("draft_04_ready")
    }

    func testEnglishScreens() {
        let app = launch(["-skipOnboarding", "-grant", "-language", "en"])
        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 15))
        snap("en_home")
        tap(app, "home_play")
        XCTAssertTrue(element(app, "flow_mode_standard").waitForExistence(timeout: 5))
        snap("en_mode")
        tap(app, "flow_mode_standard")
        tap(app, "flow_hero_H001")
        snap("en_hero")
        tap(app, "flow_next")
        XCTAssertTrue(element(app, "flow_confirm").waitForExistence(timeout: 5))
        snap("en_ready")
        tap(app, "flow_back")
        tap(app, "flow_back")
        tap(app, "flow_close")
        tap(app, "home_profile", timeout: 5)
        XCTAssertTrue(element(app, "nav_back").waitForExistence(timeout: 5))
        snap("en_profile")
    }
}
