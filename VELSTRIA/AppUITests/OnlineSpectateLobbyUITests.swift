import XCTest

/// オンライン観戦のロビー（ホスト 1 台で通せる範囲）: 実況（座らずに観戦）への切り替えと解除、観戦の設定（遅延）、
/// 参加者一覧。2 台目の端末が要る観戦の配信は AppTests/OnlineSpectatorTests（ループバック）で確かめる。
final class OnlineSpectateLobbyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// 開いている吹き出し（popover）を閉じる。
    private func dismissPopover(_ app: XCUIApplication) {
        let region = app.otherElements["PopoverDismissRegion"]
        if region.exists {
            region.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap()
        }
    }

    func testHostCanCastAndChangeSpectatorDelay() {
        let app = XCUIApplication()
        // 待ち受けポートは OS 任せ（並行して動く他の検証とぶつけない）
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-grant", "-onlineHost", "0", "-language", "ja"]
        app.launch()

        // 座っていないホスト: 実況（座らずに観戦）に切り替えられる
        let cast = element(app, "online_caster")
        XCTAssertTrue(cast.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["左の座席をタップして着席してください"].exists)
        cast.tap()
        XCTAssertTrue(app.staticTexts["実況（キャスター）として観戦します"].waitForExistence(timeout: 5))
        // 選手が誰も座っていないので、実況でもまだ開始できない
        XCTAssertFalse(element(app, "online_start").isEnabled)

        // 観戦の設定: 遅延を 15 秒にする
        let settings = element(app, "online_spectate_settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.label.contains("30"), settings.label)
        settings.tap()
        let delay15 = element(app, "online_delay_15")
        XCTAssertTrue(delay15.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "online_allow_spectators").exists)
        delay15.tap()
        dismissPopover(app)
        XCTAssertTrue(delay15.waitForNonExistence(timeout: 5))
        XCTAssertTrue(settings.label.contains("15"), settings.label)

        // 参加者一覧（選手・実況・観戦席）
        let counts = element(app, "online_counts")
        XCTAssertTrue(counts.exists)
        counts.tap()
        let members = element(app, "online_members")
        XCTAssertTrue(members.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "online_members"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        dismissPopover(app)
        XCTAssertTrue(members.waitForNonExistence(timeout: 5))

        // 実況をやめると選手に戻る（着席の案内に戻る）
        cast.tap()
        XCTAssertTrue(app.staticTexts["左の座席をタップして着席してください"].waitForExistence(timeout: 5))
    }
}
