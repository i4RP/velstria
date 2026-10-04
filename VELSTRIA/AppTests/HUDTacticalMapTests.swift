import XCTest
import SwiftUI
import VelstriaCore
@testable import VELSTRIA

final class HUDTacticalMapTests: XCTestCase {
    func testMapDockAvoidsMovementAndCombatControlsForBothHands() {
        for (width, height, side, bottom) in [(812.0, 375.0, 44.0, 21.0),
                                             (844.0, 390.0, 47.0, 21.0),
                                             (874.0, 402.0, 62.0, 20.0),
                                             (956.0, 440.0, 62.0, 20.0)] {
            for left in [false, true] {
                let layout = HUDLayout(size: CGSize(width: width, height: height),
                                       safe: EdgeInsets(top: 0, leading: side, bottom: bottom, trailing: side),
                                       leftHanded: left)
                let dock = layout.minimapDockFrame
                XCTAssertGreaterThanOrEqual(dock.minX, side)
                XCTAssertLessThanOrEqual(dock.maxX, width - side)
                XCTAssertLessThan(dock.maxY, layout.joystickRest.y - layout.joystickRadius)
                XCTAssertFalse(dock.intersects(layout.joystickZone), "Map taps must never move the hero")
                XCTAssertFalse(dock.intersects(layout.fixedJoystickZone), "Fixed-stick input must also exclude the map")
                XCTAssertEqual(dock.midX > width / 2, left)
                for slot in SkillSlot.actives {
                    let center = layout.skillCenter(slot)
                    let r = (slot == .ultimate ? layout.ultDiameter : layout.skillDiameter) / 2
                    XCTAssertFalse(dock.intersects(CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)))
                }
                let cardWidth = layout.tacticalMapSize + layout.tacticalLegendWidth + 40
                let cardHeight = layout.tacticalMapSize + 78
                XCTAssertLessThan(cardWidth, layout.trailingEdge - layout.leadingEdge)
                XCTAssertLessThan(cardHeight, layout.bottomEdge - layout.topEdge)
            }
        }
    }

    func testMinimapHonorsAsymmetricSafeArea() {
        let safe = EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 16)
        for left in [false, true] {
            let layout = HUDLayout(size: CGSize(width: 874, height: 402), safe: safe, leftHanded: left)
            XCTAssertGreaterThanOrEqual(layout.minimapFrame.minX, safe.leading)
            XCTAssertLessThanOrEqual(layout.minimapFrame.maxX, layout.width - safe.trailing)
            XCTAssertGreaterThanOrEqual(layout.joystickRest.x - layout.joystickRadius, safe.leading)
            XCTAssertLessThanOrEqual(layout.joystickRest.x + layout.joystickRadius, layout.width - safe.trailing)
            for slot in AttackButtonSlot.allCases {
                let radius = layout.attackDiameter(for: slot) / 2
                XCTAssertGreaterThanOrEqual(layout.attackCenter(for: slot).x - radius, safe.leading)
                XCTAssertLessThanOrEqual(layout.attackCenter(for: slot).x + radius, layout.width - safe.trailing)
            }
        }
    }

    @MainActor
    private func fixture() -> (AppModel, HUDModel) {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let config = MatchFactory.practiceMatch(humanHeroID: "H001", humanName: "Map tester",
                                                options: PracticeOptions(), seed: 41)
        let controller = BattleController(launch: BattleLaunch(config: config))
        let model = HUDModel(controller: controller)
        model.start(app: app, onFinish: { _ in })
        return (app, model)
    }

    @MainActor
    func testExpandedMapStopsHeldAttackAndRestoresCameraOnClose() {
        let (app, model) = fixture()
        defer { model.stop(); _ = app }
        model.attackPressed()
        XCTAssertTrue(model.attackHeld)
        model.setTacticalMap(open: true)
        XCTAssertTrue(model.isTacticalMapOpen)
        XCTAssertFalse(model.attackHeld)
        XCTAssertFalse(model.canControl)
        XCTAssertFalse(model.controller.isPaused, "The map is a live tactical view")
        model.attackPressed()
        XCTAssertFalse(model.attackHeld)
        model.minimapDragged(to: Vec2(6500, 7200))
        if case .free = model.controller.cameraMode {} else { XCTFail("Map drag must pan the camera") }
        model.setTacticalMap(open: false)
        XCTAssertTrue(model.canControl)
        if case .followHero = model.controller.cameraMode {} else { XCTFail("Closing restores hero follow") }
    }

    @MainActor
    func testPauseClosesMapAndDoesNotLeaveCameraDetached() {
        let (app, model) = fixture()
        defer { model.stop(); _ = app }
        model.setTacticalMap(open: true)
        model.minimapDragged(to: Vec2(9000, 9000))
        model.openPanel(.pause)
        XCTAssertFalse(model.isTacticalMapOpen)
        XCTAssertEqual(model.panel, .pause)
        XCTAssertTrue(model.controller.isPaused)
        if case .followHero = model.controller.cameraMode {} else { XCTFail("Pause restores hero follow") }
        model.resume()
        XCTAssertTrue(model.canControl)
    }
}
