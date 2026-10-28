import XCTest

/// 固定ワールドから遷移しても共通ヘッダーとフレンド欄が残ることを確認する。
final class WorldShellUITests: XCTestCase {
    @MainActor
    func testFirstLaunchStartsInPartyWorld() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-language", "ja"]
        app.launch()
        XCTAssertTrue(app.buttons["party_start"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["nav_back"].exists)
        XCTAssertTrue(app.buttons["party_tab_friends"].exists)
        capture("01-first-launch")
        app.buttons["party_start"].tap()
        restoreSidebar(app)
        XCTAssertTrue(app.buttons["party_tab_friends"].exists)
        capture("02-setup-in-world")
    }

    @MainActor
    func testFeatureNavigationKeepsWorldFrame() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-grant", "-language", "ja"]
        app.launch()
        XCTAssertTrue(app.buttons["home_menu"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["nav_back"].exists)
        let menuX = app.buttons["home_menu"].frame.midX
        capture("03-party-home")
        for route in ["store", "heroes", "events", "settings"] {
            app.buttons["home_menu"].tap()
            let entry = app.buttons["world_menu_\(route)"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            XCTAssertTrue(app.buttons["world_restore_sidebar"].waitForExistence(timeout: 5))
            XCTAssertGreaterThan(app.buttons["home_menu"].frame.midX, menuX + 80)
            if route == "store" { capture("04-store-expanded") }
            restoreSidebar(app)
            XCTAssertTrue(app.buttons["party_tab_friends"].exists)
            XCTAssertTrue(app.buttons["party_difficulty"].exists)
            capture("04-\(route)")
            app.buttons["nav_back"].tap()
            // 座標タップは、右へ移動中のメニューボタンが着地してから送る。
            Thread.sleep(forTimeInterval: 0.65)
        }
        XCTAssertTrue(app.buttons["party_start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nav_back"].exists)
        app.buttons["party_start"].tap()
        restoreSidebar(app)
        XCTAssertTrue(app.buttons["party_tab_friends"].exists)
        capture("05-match-modes")
    }

    @MainActor private func restoreSidebar(_ app: XCUIApplication) {
        let restore = app.buttons["world_restore_sidebar"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(app.buttons["party_tab_friends"].waitForExistence(timeout: 5))
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
