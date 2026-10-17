import XCTest
@testable import VelstriaCore

final class StageReferenceLayoutTests: XCTestCase {
    func testPinkFloorAndReflectedFloorStayWalkableAndVisible() {
        let map = MapDefinition.relayout
        let nav = NavGrid(map: map)
        for point in StageReferenceLayout.walkableSamples {
            for p in [point, Vec2(map.size - point.x, map.size - point.y)] {
                XCTAssertTrue(nav.isWalkable(p, radius: Balance.heroRadius), "pink floor blocked: \(p)")
                XCTAssertNil(map.bushMask?.bush(at: p), "pink floor became a bush: \(p)")
            }
        }
        XCTAssertEqual(map.validationIssues(), [])
    }
}
