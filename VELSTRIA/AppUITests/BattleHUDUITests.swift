import XCTest

// 担当: battle-hud。戦闘 HUD の通し UI テスト（練習場: 移動・攻撃・スキル・ショップ・スコアボード・ポーズ・退出、観戦: 速度変更・退出）。

final class BattleHUDUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-skipOnboarding", "-grant"] + args
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    @discardableResult
    private func tap(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10) -> XCUIElement {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "\(id) が表示されない")
        e.tap()
        return e
    }

    func testPracticeControlsShopPauseAndLeave() {
        let app = launch(["-battle", "practice", "-language", "ja"])
        XCTAssertTrue(element(app, "hud_attack").waitForExistence(timeout: 30), "HUD が表示されない")
        snap("hud_practice")

        // スティックを少し倒す
        let stick = element(app, "hud_joystick")
        XCTAssertTrue(stick.exists)
        let from = stick.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 60, dy: -30)))

        tap(app, "hud_attack")
        tap(app, "hud_skill1")
        for id in ["hud_skill2", "hud_skill3", "hud_ult", "hud_spell1", "hud_spell2", "hud_recall", "hud_minimap"] {
            XCTAssertTrue(element(app, id).exists, "\(id) が無い")
        }

        // ショップ
        tap(app, "hud_shop")
        XCTAssertTrue(element(app, "shop_panel").waitForExistence(timeout: 5))
        snap("hud_shop")
        tap(app, "shop_tab_attack")
        tap(app, "shop_close")
        XCTAssertTrue(element(app, "shop_panel").waitForNonExistence(timeout: 5))

        // スコアボード
        tap(app, "hud_scoreboard")
        XCTAssertTrue(element(app, "scoreboard_panel").waitForExistence(timeout: 5))
        snap("hud_scoreboard")
        tap(app, "scoreboard_close")

        // ポーズ → 再開
        tap(app, "hud_pause")
        XCTAssertTrue(element(app, "pause_resume").waitForExistence(timeout: 5))
        snap("hud_pause")
        tap(app, "pause_resume")
        XCTAssertTrue(element(app, "pause_resume").waitForNonExistence(timeout: 5))

        // ポーズ → 退出 → ホーム
        tap(app, "hud_pause")
        tap(app, "pause_leave")
        tap(app, "leave_confirm")
        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 15), "退出後にホームへ戻らない")
    }

    func testTutorialMoveStepAdvancesWithJoystick() {
        let app = launch(["-battle", "tutorial", "-language", "en"])
        let card = element(app, "tutorial_card")
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        XCTAssertTrue(card.label.contains("Move Around"), card.label)
        let stick = element(app, "hud_joystick")
        let from = stick.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.65))
        // スティックを右上へ倒したまま保持する（600 ユニット以上歩く）
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 50, dy: -35)), withVelocity: .default,
                   thenHoldForDuration: 4.0)
        let advanced = NSPredicate(format: "label CONTAINS %@", "Basic Attacks")
        expectation(for: advanced, evaluatedWith: element(app, "tutorial_card"))
        waitForExpectations(timeout: 8)
        snap("hud_tutorial_step2")
        XCTAssertTrue(element(app, "hud_attack").exists)
    }

    func testSpectateSpeedAndLeave() {
        let app = launch(["-battle", "spectate", "-language", "en"])
        XCTAssertTrue(element(app, "spectate_speed_2x").waitForExistence(timeout: 30))
        XCTAssertFalse(element(app, "hud_attack").exists, "観戦では操作ボタンを出さない")
        tap(app, "spectate_speed_2x")
        XCTAssertTrue(element(app, "spectate_speed_2x").isSelected)
        snap("hud_spectate")
        tap(app, "spectate_leave")
        tap(app, "leave_confirm")
        XCTAssertTrue(element(app, "spectate_speed_2x").waitForNonExistence(timeout: 10), "退出後も観戦画面のまま")
    }
}
