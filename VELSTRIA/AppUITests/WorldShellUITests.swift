import XCTest

/// 固定ワールドから遷移しても共通ヘッダーとフレンド欄が残ることを確認する。
final class WorldShellUITests: XCTestCase {
    @MainActor
    func testFirstLaunchStartsInPartyWorld() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-language", "ja"]
        app.launch()
        XCTAssertTrue(app.buttons["party_start"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["party_tab_friends"].exists)
        capture("01-first-launch")
        app.buttons["party_start"].tap()
        XCTAssertTrue(app.buttons["party_tab_friends"].exists)
        capture("02-setup-in-world")
    }

    @MainActor
    func testFeatureNavigationKeepsWorldFrame() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-grant", "-language", "ja"]
        app.launch()
        XCTAssertTrue(app.buttons["home_menu"].waitForExistence(timeout: 15))
        capture("03-party-home")
        for route in ["store", "heroes", "events", "settings"] {
            app.buttons["home_menu"].tap()
            let entry = app.buttons["world_menu_\(route)"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            XCTAssertTrue(app.buttons["party_tab_friends"].exists)
            XCTAssertTrue(app.buttons["party_difficulty"].exists)
            capture("04-\(route)")
            app.buttons["nav_back"].tap()
        }
        XCTAssertTrue(app.buttons["party_start"].waitForExistence(timeout: 5))
        app.buttons["party_start"].tap()
        XCTAssertTrue(app.buttons["party_tab_friends"].exists)
        capture("05-match-modes")
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
