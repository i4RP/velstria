import XCTest
@testable import VelstriaCore

/// 草むらの細かい格子（BushMask。MLBB のミニマップの形のまま、tools/map_proto/terrain_grid.mjs）。
final class BushMaskTests: XCTestCase {
    typealias Kit = WorldTestKit

    func testSanctumGridDecodesAndIsPointSymmetric() {
        let m = BushMask.sanctum
        XCTAssertEqual(m.cols, 600)
        XCTAssertEqual(m.rows, 600)
        XCTAssertEqual(m.cell, 20)
        XCTAssertEqual(m.cell * Double(m.cols), Balance.mapSize)
        XCTAssertEqual(m.bushCount, 48)  // 設計図の草むら Blue 24 + Red 24
        let half = m.bushCount / 2
        var mismatched = 0
        for q in m.cells.indices {
            let v = Int(m.cells[q]), w = Int(m.cells[m.cells.count - 1 - q])
            let expected = v == 0 ? 0 : (v - 1 < half ? v + half : v - half)
            if w != expected { mismatched += 1 }
        }
        XCTAssertEqual(mismatched, 0)
        for k in 0..<m.bushCount {
            // どの草むらも 2 m² 以上（細い線や点ではない）
            XCTAssertGreaterThan(Double(m.cellCount(of: k)) * m.cell * m.cell, 20_000, "bush \(k)")
        }
    }

    func testRunLengthRoundTripAndCodable() throws {
        let m = BushMask.sanctum
        let again = try XCTUnwrap(BushMask(cell: m.cell, cols: m.cols, rows: m.rows, runLengthBase64: m.runLengthBase64))
        XCTAssertEqual(again, m)
        let data = try JSONEncoder().encode(m)
        XCTAssertLessThan(data.count, 100_000)
        XCTAssertEqual(try JSONDecoder().decode(BushMask.self, from: data), m)
        XCTAssertNil(BushMask(cell: 20, cols: 600, rows: 600, runLengthBase64: "AAE="))
    }

    func testLookupOutsideAndNaNIsNil() {
        let m = BushMask.sanctum
        XCTAssertNil(m.bush(at: Vec2(-1, 100)))
        XCTAssertNil(m.bush(at: Vec2(100, 12_000)))
        XCTAssertNil(m.bush(at: Vec2(.nan, 100)))
        XCTAssertNil(m.bush(at: Vec2(.infinity, 100)))
        XCTAssertEqual(m.bushes(overlappingCircle: Vec2(.nan, 0), radius: 100), [])
    }

    func testRelayoutUsesGridBushes() {
        let map = MapDefinition.relayout
        let m = try! XCTUnwrap(map.bushMask)
        XCTAssertEqual(m.cell, 20 * 0.81, accuracy: 1e-9)
        XCTAssertEqual(map.brushes.count, 48)
        XCTAssertEqual(map.brushes.map(\.id), Array(0..<48))
        XCTAssertEqual(map.brushes.map(\.bush), Array(0..<48))
        XCTAssertEqual(map.validationIssues(), [])
        for k in map.brushes.indices {
            XCTAssertGreaterThan(m.cellCount(of: k), 0, "bush \(k) が壁で消えた")
            let p = map.brushInteriorPoint(k)
            XCTAssertEqual(map.brushIndex(at: p), k)
            XCTAssertTrue(map.brush(k, contains: p))
            XCTAssertTrue(map.brushes[k].rect.contains(p))
            XCTAssertNil(map.obstacleIndex(at: p), "bush \(k) の中心のセルが壁の中")
            XCTAssertEqual(map.brushIndices(overlappingCircle: p, radius: 5), [k])
            // 描画用の矩形は重ならず、合計がセルの面積
            let rects = map.brushRects(k)
            XCTAssertEqual(rects.reduce(0) { $0 + $1.width * $1.height }, map.brushArea(k), accuracy: 1)
        }
        // 草むらの外接矩形は形の近似ではないので、矩形の中でも草むらでない所がある（三日月形など）
        XCTAssertTrue(map.brushes.indices.contains { k in
            let r = map.brushes[k].rect
            return map.brushIndex(at: Vec2(r.minX + 1, r.minY + 1)) != k || map.brushIndex(at: Vec2(r.maxX - 1, r.maxY - 1)) != k
        })
        // standard（比較用の保存版）は従来の矩形のまま
        XCTAssertNil(MapDefinition.standard.bushMask)
    }

    func testEmptiedBrushesDisableGridLookup() {
        var map = MapDefinition.relayout
        let p = map.brushInteriorPoint(3)
        map.brushes = []
        XCTAssertNil(map.brushIndex(at: p))
        XCTAssertEqual(map.brushIndices(overlappingCircle: p, radius: 100), [])
    }

    func testDistanceFieldIsZeroInsideAndGrowsOutside() {
        let m = BushMask.sanctum
        let d = m.distanceField()
        let p = MapDefinition.relayout.brushInteriorPoint(6) / 0.81
        let q = try! XCTUnwrap(m.index(at: p))
        XCTAssertEqual(d[q], 0)
        // 草むらの外接矩形から 10 セル外は 10 セル前後
        let r = try! XCTUnwrap(m.bounds(of: 6))
        let outside = try! XCTUnwrap(m.index(at: Vec2(r.maxX + 10 * m.cell - 1, r.center.y)))
        XCTAssertGreaterThanOrEqual(d[outside], 9.5)
    }

    /// 細かい格子の草むらでも、MLBB と同じく外からは見えず、同じ草むらの中からは見える。
    func testHeroHiddenInGridBushUnlessSameBush() {
        let map = MapDefinition.relayout
        var (s, ctx) = Kit.makeState(Kit.emptyConfig(), map: map)
        Kit.setTime(&s, 60)
        Kit.suppressWaves(&s)
        // 構造物から遠いジャングルの草むら（熾甲虫の右）
        let k = 6
        let inside = map.brushInteriorPoint(k)
        // 600 離れた草むらの外（方向は草むらの形に合わせて選ぶ）
        let outside = [Vec2(-600, 0), Vec2(600, 0), Vec2(0, -600), Vec2(0, 600)].map { inside + $0 }
            .first { map.brushIndex(at: $0) == nil && map.obstacleIndex(at: $0) == nil }!
        let hider = Kit.addHero(&s, ctx, team: .red, pos: inside)
        let scout = Kit.addHero(&s, ctx, team: .blue, pos: outside)
        for _ in 0..<3 { VisionSystem.update(&s, ctx) }
        XCTAssertEqual(s.units[hider].brushIndex, k)
        XCTAssertNil(s.units[scout].brushIndex)
        XCTAssertTrue(s.vision.isLit(inside, for: .blue))
        XCTAssertFalse(s.isVisible(hider, to: .blue), "hidden in grid bush")

        // 同じ草むらの別のセル（いちばん遠いセル）に入ると見える
        let m = map.bushMask!
        var far = inside
        for (q, v) in m.cells.enumerated() where Int(v) == k + 1 {
            let c = m.center(col: q % m.cols, row: q / m.cols)
            if c.distance(to: inside) > far.distance(to: inside) { far = c }
        }
        XCTAssertGreaterThan(far.distance(to: inside), 150)
        s.units[scout].pos = far
        VisionSystem.update(&s, ctx)
        XCTAssertEqual(s.units[scout].brushIndex, k)
        XCTAssertTrue(s.isVisible(hider, to: .blue))
    }
}
