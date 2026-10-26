import RealityKit
import XCTest
@testable import VELSTRIA

@MainActor
final class FirstPersonVisibilityTests: XCTestCase {
    func testForwardAndUpwardViewCannotExposeTenPercent() {
        for degrees in stride(from: Float(-20), through: 85, by: 0.5) {
            let pitch = degrees * .pi / 180
            let band = (FirstPersonVisibility.cutoff(pitch: pitch) + 1) / 2
            XCTAssertEqual(band, 0.09, accuracy: 1e-6)
            XCTAssertLessThan(band, 0.1, "A full-width opaque silhouette still remains below ten percent")
        }
    }

    func testDownwardRevealIsMonotonicAndReturnsToTheSameForwardBoundary() {
        var previous: Float = 0.09
        for degrees in stride(from: Float(-20), through: -85, by: -0.5) {
            let pitch = degrees * .pi / 180
            let fraction = FirstPersonVisibility.visibleFraction(pitch: pitch)
            XCTAssertGreaterThanOrEqual(fraction + 1e-6, previous)
            XCTAssertLessThanOrEqual(fraction, 1)
            previous = fraction
        }
        XCTAssertEqual(FirstPersonVisibility.visibleFraction(pitch: -60 * .pi / 180), 1, accuracy: 1e-6)
        XCTAssertEqual(FirstPersonVisibility.visibleFraction(pitch: 0), 0.09, accuracy: 1e-6,
                       "Returning from down-look must recover the forward limit without retained reveal")
    }

    func testInvalidPitchFailsToTheRestrictedBand() {
        for pitch in [Float.nan, .infinity, -.infinity] {
            XCTAssertEqual(FirstPersonVisibility.visibleFraction(pitch: pitch), 0.09, accuracy: 1e-6)
            XCTAssertTrue(FirstPersonVisibility.cutoff(pitch: pitch).isFinite)
        }
    }

    func testUnsupportedMaterialsHideForwardAndRestoreOriginalEnabledStates() {
        let root = Entity()
        let visible = ModelEntity(mesh: .generateBox(size: 0.2), materials: [SimpleMaterial(color: .white, isMetallic: false)])
        let alreadyHidden = ModelEntity(mesh: .generateBox(size: 0.2), materials: [SimpleMaterial(color: .white, isMetallic: false)])
        alreadyHidden.isEnabled = false
        root.addChild(visible)
        root.addChild(alreadyHidden)
        let visibility = FirstPersonVisibility(root: root)
        XCTAssertFalse(visibility.isReady, "An unsupported material must never produce a successful empty-mask review")
        XCTAssertEqual(visibility.unsupportedMaterialCount, 2)

        visibility.update(enabled: true, pitch: 0)
        XCTAssertFalse(visible.isEnabled)
        XCTAssertFalse(alreadyHidden.isEnabled)
        visibility.update(enabled: true, pitch: 0)
        visibility.update(enabled: false, pitch: 0)
        XCTAssertTrue(visible.isEnabled, "Repeated hiding must retain the enabled state from before first-person entry")
        XCTAssertFalse(alreadyHidden.isEnabled)
        XCTAssertTrue(visible.model?.materials.first is SimpleMaterial)

        visibility.update(enabled: true, pitch: 0)
        visibility.update(enabled: true, pitch: -80 * .pi / 180)
        XCTAssertTrue(visible.isEnabled, "A fully downward view may restore the original unsupported material")
        XCTAssertFalse(alreadyHidden.isEnabled)
        visibility.update(enabled: true, pitch: -80 * .pi / 180, mask: true)
        XCTAssertFalse(visible.isEnabled, "A failed white-mask preparation cannot leak original shading into occupancy counts")
        visibility.update(enabled: false, pitch: 0)
        XCTAssertTrue(visible.isEnabled)
        XCTAssertFalse(alreadyHidden.isEnabled)
    }
}
