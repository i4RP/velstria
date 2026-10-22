import XCTest
@testable import VelstriaCore

final class StageReferenceLayoutTests: XCTestCase {
    func testReferenceFloorAndReflectedFloorStayWalkableAndVisible() {
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

    func testAllViewsAndBushesHaveMirroredGameplayGeometry() throws {
        let map = MapDefinition.relayout
        XCTAssertEqual(StageReferenceLayout.views.count, 26)
        XCTAssertEqual(Set(StageReferenceLayout.views.map(\.name)).count, 26)
        XCTAssertEqual(map.brushes.count, StageReferenceLayout.bushNames.count * 2)
        let mask = try XCTUnwrap(map.bushMask)
        for row in 0..<mask.rows {
            for col in 0..<mask.cols {
                let p = mask.center(col: col, row: row)
                let mirror = Vec2(map.size-p.x,map.size-p.y)
                XCTAssertEqual(mask.bush(at: p) == nil, mask.bush(at: mirror) == nil)
            }
        }
    }
}
