import RealityKit
import XCTest
@testable import VELSTRIA

@MainActor
final class FirstPersonVisibilityTests: XCTestCase {
    func testUnsupportedMaterialsStayVisibleAndRestoreAfterMaskCapture() {
        let root = Entity()
        let visible = ModelEntity(mesh: .generateBox(size: 0.2), materials: [SimpleMaterial(color: .white, isMetallic: false)])
        let alreadyHidden = ModelEntity(mesh: .generateBox(size: 0.2), materials: [SimpleMaterial(color: .white, isMetallic: false)])
        alreadyHidden.isEnabled = false
        root.addChild(visible)
        root.addChild(alreadyHidden)
        let visibility = FirstPersonVisibility(root: root)
        XCTAssertFalse(visibility.isReady, "An unsupported material must never produce a successful empty-mask review")
        XCTAssertEqual(visibility.unsupportedMaterialCount, 2)

        visibility.update(enabled: true)
        XCTAssertTrue(visible.isEnabled, "Normal first-person rendering keeps the original mesh visible")
        XCTAssertFalse(alreadyHidden.isEnabled)
        XCTAssertTrue(visible.model?.materials.first is SimpleMaterial)

        visibility.update(enabled: true, mask: true)
        visibility.update(enabled: true, mask: true)
        XCTAssertFalse(visible.isEnabled, "A failed white-mask preparation cannot leak original shading into occupancy counts")
        XCTAssertFalse(alreadyHidden.isEnabled)
        visibility.update(enabled: true)
        XCTAssertTrue(visible.isEnabled, "Repeated mask hiding must preserve the original enabled state")
        XCTAssertFalse(alreadyHidden.isEnabled)
        visibility.update(enabled: false)
        XCTAssertTrue(visible.isEnabled)
        XCTAssertFalse(alreadyHidden.isEnabled)
    }
}
