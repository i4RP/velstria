import XCTest
@testable import VelstriaCore

/// NavGrid（経路探索・レイキャスト・壁ずり・最寄り歩行可能点）。
final class WorldNavTests: XCTestCase {
    /// 縦長の壁 1 枚 + 円柱 1 本 + 閉じた箱のあるテスト用マップ。
    static let testMap: MapDefinition = {
        var m = MapDefinition.standard
        m.brushes = []
        m.obstacles = [
            .rect(Rect2(minX: 5000, minY: 3000, maxX: 5400, maxY: 9000)),
            .circle(center: Vec2(2000, 9000), radius: 300),
            // 閉じた箱（内部 7600..8400）
            .rect(Rect2(minX: 7400, minY: 7400, maxX: 8600, maxY: 7600)),
            .rect(Rect2(minX: 7400, minY: 8400, maxX: 8600, maxY: 8600)),
            .rect(Rect2(minX: 7400, minY: 7400, maxX: 7600, maxY: 8600)),
            .rect(Rect2(minX: 8400, minY: 7400, maxX: 8600, maxY: 8600)),
        ]
        return m
    }()

    let nav = NavGrid(map: WorldNavTests.testMap)
    let r = Balance.heroRadius

    func testStraightPathWhenClear() {
        let path = nav.findPath(from: Vec2(1000, 1000), to: Vec2(3000, 2000), radius: r)
        XCTAssertEqual(path, [Vec2(3000, 2000)])
    }

    func testPathGoesAroundWall() {
        let from = Vec2(4000, 6000), to = Vec2(6500, 6000)
        let path = nav.findPath(from: from, to: to, radius: r)
        XCTAssertGreaterThan(path.count, 1)
        XCTAssertEqual(path.last, to)
        var a = from
        var length = 0.0
        for p in path {
            XCTAssertTrue(nav.isWalkable(p, radius: r), "\(p)")
            XCTAssertTrue(nav.hasLineOfSight(from: a, to: p, radius: r - 10), "\(a) -> \(p)")
            length += a.distance(to: p)
            a = p
        }
        // 壁の端（y < 3000 または y > 9000）を回り込む
        XCTAssertTrue(path.contains { $0.y < 3000 || $0.y > 9000 })
        XCTAssertGreaterThan(length, from.distance(to: to) + 1000)
        // 平滑化されている（格子の階段ではない）
        XCTAssertLessThan(path.count, 8)
    }

    func testUnreachableGoalReturnsEmpty() {
        XCTAssertEqual(nav.findPath(from: Vec2(6000, 6000), to: Vec2(8000, 8000), radius: r), [])
        // 半径が異なっても（焼き込み外の半径）到達不能は空
        XCTAssertEqual(nav.findPath(from: Vec2(6000, 6000), to: Vec2(8000, 8000), radius: 32), [])
        // 箱の中どうしは到達可能
        XCTAssertEqual(nav.findPath(from: Vec2(7800, 7800), to: Vec2(8200, 8200), radius: r), [Vec2(8200, 8200)])
    }

    func testGoalInsideObstacleEndsAtNearestWalkable() {
        let path = nav.findPath(from: Vec2(4000, 6000), to: Vec2(5150, 6000), radius: r)
        XCTAssertFalse(path.isEmpty)
        let end = path.last!
        XCTAssertTrue(nav.isWalkable(end, radius: r))
        XCTAssertEqual(end.x, 5000 - r, accuracy: 3)
        XCTAssertEqual(end.y, 6000, accuracy: 3)
    }

    func testLargeRadiusUsesPerRadiusGrid() {
        // 円柱と壁の隙間（x 2300..5000）は半径 220 でも通れるが、閉じた箱には入れない
        let path = nav.findPath(from: Vec2(1000, 9000), to: Vec2(3000, 9000), radius: 220)
        XCTAssertFalse(path.isEmpty)
        for p in path { XCTAssertTrue(nav.isWalkable(p, radius: 220)) }
    }

    func testRaycastStopsBeforeObstacle() {
        let hit = nav.raycast(from: Vec2(4000, 6000), to: Vec2(6000, 6000), radius: r)
        XCTAssertEqual(hit.x, 5000 - r - 1, accuracy: 0.5)
        XCTAssertEqual(hit.y, 6000, accuracy: 1e-9)
        XCTAssertTrue(nav.isWalkable(hit, radius: r))

        let circleHit = nav.raycast(from: Vec2(1000, 9000), to: Vec2(3000, 9000), radius: r)
        XCTAssertEqual(circleHit.x, 2000 - 300 - r - 1, accuracy: 0.5)

        // 障害物が無ければ目標点まで
        XCTAssertEqual(nav.raycast(from: Vec2(1000, 1000), to: Vec2(1400, 1300), radius: r), Vec2(1400, 1300))
        // マップ端
        let edge = nav.raycast(from: Vec2(500, 500), to: Vec2(-1000, 500), radius: r)
        XCTAssertEqual(edge.x, r, accuracy: 1.5)
        XCTAssertTrue(nav.isWalkable(edge, radius: r))
    }

    func testResolveMoveSlidesAlongWall() {
        let start = Vec2(5000 - r - 0.5, 6000)
        XCTAssertTrue(nav.isWalkable(start, radius: r))
        // 斜めに壁へ向かう → x は止まり y だけ進む
        let slid = nav.resolveMove(from: start, to: start + Vec2(6, 6), radius: r)
        XCTAssertEqual(slid.x, start.x, accuracy: 1e-9)
        XCTAssertEqual(slid.y, 6006, accuracy: 1e-9)
        // 真正面は止まる
        XCTAssertEqual(nav.resolveMove(from: start, to: start + Vec2(8, 0), radius: r), start)
        // 離れる向きはそのまま
        XCTAssertEqual(nav.resolveMove(from: start, to: start + Vec2(-8, 3), radius: r), start + Vec2(-8, 3))

        // 円柱に斜めに当たると接線方向へ滑る
        let c = Vec2(2000, 9000)
        let p = c + Vec2(-(300 + r + 0.5), 0)
        let moved = nav.resolveMove(from: p, to: p + Vec2(6, 6), radius: r)
        XCTAssertTrue(nav.isWalkable(moved, radius: r))
        XCTAssertGreaterThan(moved.y, p.y + 3)
    }

    func testResolveMoveLetsUnitsEscapeFromInsideObstacle() {
        let inside = Vec2(5000 - 20, 6000) // 半径 55 では食い込んでいる
        XCTAssertFalse(nav.isWalkable(inside, radius: r))
        XCTAssertEqual(nav.resolveMove(from: inside, to: inside + Vec2(-8, 0), radius: r), inside + Vec2(-8, 0))
        XCTAssertEqual(nav.resolveMove(from: inside, to: inside + Vec2(8, 0), radius: r), inside)
    }

    func testNearestWalkable() {
        let q = nav.nearestWalkable(Vec2(5100, 6000), radius: r)
        XCTAssertTrue(nav.isWalkable(q, radius: r))
        XCTAssertEqual(q.x, 5000 - r - 1, accuracy: 2)
        XCTAssertEqual(q.y, 6000, accuracy: 1e-9)
        let q2 = nav.nearestWalkable(Vec2(5300, 6000), radius: r)
        XCTAssertEqual(q2.x, 5400 + r + 1, accuracy: 2)
        // 歩行可能ならそのまま
        XCTAssertEqual(nav.nearestWalkable(Vec2(3000, 3000), radius: r), Vec2(3000, 3000))
        // マップ外はマップ内へ
        let out = nav.nearestWalkable(Vec2(-100, 5000), radius: r)
        XCTAssertTrue(nav.isWalkable(out, radius: r))
        XCTAssertEqual(out.y, 5000, accuracy: 1e-9)
    }

    func testFindPathIsDeterministicAndCacheTransparent() {
        let other = NavGrid(map: WorldNavTests.testMap)
        let a = nav.findPath(from: Vec2(4000, 6000), to: Vec2(6500, 6200), radius: r)
        let b = nav.findPath(from: Vec2(4000, 6000), to: Vec2(6500, 6200), radius: r) // キャッシュヒット
        let c = other.findPath(from: Vec2(4000, 6000), to: Vec2(6500, 6200), radius: r)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, c)
    }

    func testCrossMapPathPerformance() {
        let map = MapDefinition.standard
        let from = map.fountain(.blue), to = map.fountain(.red)
        var worst = 0.0
        var path: [Vec2] = []
        for _ in 0..<5 {
            let grid = NavGrid(map: map) // キャッシュが空の状態で計測
            let t0 = DispatchTime.now().uptimeNanoseconds
            path = grid.findPath(from: from, to: to, radius: Balance.heroRadius)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            worst = max(worst, ms)
        }
        XCTAssertEqual(path.last, to)
        // 障害物を迂回する経路（ジャングル横断）でも計測
        let grid = NavGrid(map: map)
        let t0 = DispatchTime.now().uptimeNanoseconds
        let jungle = grid.findPath(from: Vec2(2800, 5000), to: Vec2(9200, 7000), radius: Balance.heroRadius)
        worst = max(worst, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        XCTAssertFalse(jungle.isEmpty)
        #if DEBUG
        XCTAssertLessThan(worst, 60)
        #else
        XCTAssertLessThan(worst, 3, "cross-map path took \(worst) ms")
        #endif
        print("cross-map path worst: \(worst) ms")
    }
}
