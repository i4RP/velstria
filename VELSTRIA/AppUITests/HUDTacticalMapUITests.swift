import XCTest

final class HUDTacticalMapUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testExpandPanAndCloseMap() { verifyMap(leftHanded: false) }
    func testLeftHandedMapStaysOppositeCombatControls() { verifyMap(leftHanded: true) }

    private func verifyMap(leftHanded: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-grant", "-battle", "practice", "-language", "ja"]
        if leftHanded { app.launchArguments.append("-hudLeftHanded") }
        app.launch()
        let expand = element(app, "hud_minimap_expand")
        XCTAssertTrue(expand.waitForExistence(timeout: BattleHUDUITests.battleStartTimeout))
        let map = element(app, "hud_minimap")
        let attack = element(app, "hud_attack")
        XCTAssertEqual(map.frame.midX > attack.frame.midX, leftHanded)
        let compactWidth = map.frame.width
        expand.tap()
        let tactical = element(app, "hud_tactical_map")
        XCTAssertTrue(tactical.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(tactical.frame.width, compactWidth)
        let from = tactical.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.6))
        from.press(forDuration: 0.15, thenDragTo: tactical.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3)))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = leftHanded ? "tactical_map_left_handed" : "tactical_map"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        element(app, "hud_tactical_close").tap()
        XCTAssertTrue(element(app, "hud_tactical_panel").waitForNonExistence(timeout: 5))
        // SwiftUI's custom HUD accessibility elements can report isHittable=false
        // even when XCTest successfully taps them. Verify restored interactions.
        element(app, "hud_attack").tap()
        expand.tap()
        XCTAssertTrue(tactical.waitForExistence(timeout: 5), "Closing the map must restore the HUD's input")
        element(app, "hud_tactical_close").tap()
        XCTAssertTrue(element(app, "hud_tactical_panel").waitForNonExistence(timeout: 5))
    }
}
