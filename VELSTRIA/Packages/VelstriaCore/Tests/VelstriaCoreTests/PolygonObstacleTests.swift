import XCTest
@testable import VelstriaCore

/// 多角形の壁（Obstacle.polygon）: 判定・距離・法線・写像・滑らかな輪郭と、NavGrid（レイキャスト・壁ずり・経路・押し出し）。
final class PolygonObstacleTests: XCTestCase {
    // MARK: - 図形

    /// L 字（反時計回り）。凹んだ角が (5100, 5100)、その北東が L の内側の空き。
    static let lShape: [Vec2] = [
        Vec2(5000, 5000), Vec2(5300, 5000), Vec2(5300, 5100), Vec2(5100, 5100), Vec2(5100, 5300), Vec2(5000, 5300),
    ]

    /// 45° の斜めの壁（帯）。下側の面は y = x − 1000、上側の面は y = x − 400（厚さ 300√2）。途中に一直線上の頂点を挟む。
    static let wall: Obstacle = .polygon([
        Vec2(4000, 3000), Vec2(5500, 4500), Vec2(7000, 6000), Vec2(6700, 6300), Vec2(5200, 4800), Vec2(3700, 3300),
    ])

    /// 東に口を開けた三日月（C 字。外周 1200・内周 800、45°〜315°）。外周を反時計回り → 内周を時計回り（全体で反時計回り）。
    static let crescentCenter = Vec2(3000, 8000)
    static let crescentVertices: [Vec2] = {
        let c = crescentCenter
        func at(_ deg: Double, _ radius: Double) -> Vec2 {
            let a = deg * .pi / 180
            return Vec2((c.x + cos(a) * radius).rounded(), (c.y + sin(a) * radius).rounded())
        }
        return stride(from: 45.0, through: 315.0, by: 15.0).map { at($0, 1200) }
            + stride(from: 315.0, through: 45.0, by: -15.0).map { at($0, 800) }
    }()
    static let crescent: Obstacle = .polygon(crescentVertices)

    /// 角の丸めを確かめる矩形。
    static let block = Rect2(minX: 8000, minY: 2000, maxX: 8600, maxY: 2400)

    /// 間隔の不揃いな制御点（時計回り。左辺を上り、近い 2 点で角を曲がり、右辺を下りて戻る）。
    static let unevenControl: [Vec2] = [
        Vec2(3000, 3000), Vec2(3000, 4000), Vec2(3080, 4060), Vec2(4200, 4100), Vec2(4300, 3000), Vec2(3600, 2900),
    ]

    /// 斜めの壁・三日月・矩形だけのテスト用マップ（WorldNavTests.testMap と同じ作り方）。
    static let testMap: MapDefinition = {
        var m = MapDefinition.standard
        m.brushes = []
        m.obstacles = [wall, crescent, .rect(block)]
        return m
    }()

    let nav = NavGrid(map: PolygonObstacleTests.testMap)
    let r = Balance.heroRadius
    let sqrt2 = 2.0.squareRoot()

    // MARK: - 判定・距離

    func testConcaveLShapeContainsAndSignedDistance() {
        let l = Obstacle.polygon(Self.lShape)
        XCTAssertEqual(Spline.signedArea(Self.lShape), 50000, accuracy: 1e-9)
        XCTAssertEqual(l.bounds, Rect2(minX: 5000, minY: 5000, maxX: 5300, maxY: 5300))
        // 内部は負（最も近い辺までの距離）
        XCTAssertEqual(l.signedDistance(to: Vec2(5050, 5030)), -30, accuracy: 1e-9)
        XCTAssertEqual(l.signedDistance(to: Vec2(5050, 5050)), -50, accuracy: 1e-9)
        XCTAssertTrue(l.contains(Vec2(5050, 5050)))
        XCTAssertTrue(l.contains(Vec2(5050, 5050), inflatedBy: -40))
        XCTAssertFalse(l.contains(Vec2(5050, 5050), inflatedBy: -60))
        // 凹んだ所（L の内側）は外。2 本の辺から 50
        let notch = Vec2(5150, 5150)
        XCTAssertFalse(l.contains(notch))
        XCTAssertEqual(l.signedDistance(to: notch), 50, accuracy: 1e-9)
        XCTAssertFalse(l.contains(notch, inflatedBy: 49))
        XCTAssertTrue(l.contains(notch, inflatedBy: 50))
        XCTAssertEqual(l.signedDistance(to: Vec2(5200, 5200)), 100, accuracy: 1e-9)
        // 凸の角の外は角の点までのユークリッド距離（丸く膨張する）
        let beyondCorner = Vec2(5350, 5150)
        XCTAssertEqual(l.signedDistance(to: beyondCorner), 50 * sqrt2, accuracy: 1e-9)
        XCTAssertFalse(l.contains(beyondCorner, inflatedBy: 70))
        XCTAssertTrue(l.contains(beyondCorner, inflatedBy: 71))
        XCTAssertEqual(l.signedDistance(to: Vec2(4900, 4900)), 100 * sqrt2, accuracy: 1e-9)
        // 境界上は距離 0 で含む（r = 0）
        let onEdge = Vec2(5300, 5050)
        XCTAssertEqual(l.signedDistance(to: onEdge), 0, accuracy: 1e-12)
        XCTAssertTrue(l.contains(onEdge))
        XCTAssertFalse(l.contains(onEdge, inflatedBy: -1))
        // 境界までの距離がちょうど r のときは含む（signedDistance <= r と一致）
        XCTAssertTrue(l.contains(Vec2(5350, 5050), inflatedBy: 50))
        XCTAssertFalse(l.contains(Vec2(5350, 5050), inflatedBy: 49.999))
    }

    func testCrescentCavityAndMouthAreOutside() {
        let c = Self.crescent, o = Self.crescentCenter
        XCTAssertGreaterThan(Spline.signedArea(Self.crescentVertices), 0)
        // 背中（西）の帯の中は内部
        XCTAssertTrue(c.contains(o + Vec2(-1000, 0)))
        XCTAssertLessThan(c.signedDistance(to: o + Vec2(-1000, 0)), -150)
        XCTAssertTrue(c.contains(o + Vec2(0, 1000)))
        XCTAssertTrue(c.contains(o + Vec2(0, -1000)))
        // 空洞・口・外側は外
        XCTAssertFalse(c.contains(o))
        XCTAssertFalse(c.contains(o + Vec2(1000, 0)))
        XCTAssertFalse(c.contains(o + Vec2(-1500, 0)))
        // 中心から内周（弦の中点は半径 800·cos 7.5°）まで
        XCTAssertEqual(c.signedDistance(to: o), 800 * cos(7.5 * .pi / 180), accuracy: 1)
        XCTAssertGreaterThan(c.signedDistance(to: o + Vec2(1000, 0)), 0)
    }

    /// `signedDistance(p) <= r` ⇔ `contains(p, inflatedBy: r)`（ちょうど等しい r も含む）。距離と内外は総当たりの計算とも一致する。
    func testSignedDistanceAgreesWithContainsAndBruteForce() {
        var rng = SplitMix64(seed: 20261016)
        let shapes: [[Vec2]] = [Self.lShape, Self.crescentVertices, Self.polygonVertices(Self.wall),
                                Self.polygonVertices(Obstacle.smoothPolygon(Self.unevenControl))]
        for v in shapes {
            let o = Obstacle.polygon(v)
            let b = o.bounds.expanded(by: 300)
            for _ in 0..<1500 {
                let p = Vec2(rng.nextDouble(in: b.minX..<b.maxX), rng.nextDouble(in: b.minY..<b.maxY))
                let sd = o.signedDistance(to: p)
                for rad in [rng.nextDouble(in: -150..<250), 0, sd, abs(sd)] {
                    XCTAssertEqual(sd <= rad, o.contains(p, inflatedBy: rad), "\(p) r=\(rad) sd=\(sd)")
                }
                // 総当たり: 全辺までの距離の最小・角度の和（回転数）による内外
                var dist = Double.infinity
                var winding = 0.0
                for i in v.indices {
                    let a = v[i], c = v[(i + 1) % v.count]
                    dist = min(dist, distancePointToSegment(p, a, c))
                    winding += atan2((a - p).cross(c - p), (a - p).dot(c - p))
                }
                XCTAssertEqual(abs(sd), dist, accuracy: 1e-9)
                if dist > 1e-6 { XCTAssertEqual(sd < 0, abs(winding) > .pi, "\(p)") }
            }
        }
    }

    func testOutwardNormalOnDiagonalWall() {
        let w = Self.wall
        let out = Vec2(1, -1).normalized
        let foot = Vec2(4500, 3500) // 下側の面 y = x − 1000 上
        assertClose(w.outwardNormal(at: foot + out * 100), out)
        // 内側では最も近い境界の点へ向かう向き（外向き）
        assertClose(w.outwardNormal(at: foot - out * 50), out)
        // 境界上はその辺の外向き法線
        assertClose(w.outwardNormal(at: foot), out)
        // 上側の面
        assertClose(w.outwardNormal(at: Vec2(5000, 4600) + Vec2(-1, 1).normalized * 80), Vec2(-1, 1).normalized)
        // 凸の角 (7000, 6000) の外は角の点から外へ（丸く回り込む）
        assertClose(w.outwardNormal(at: Vec2(7100, 6000)), Vec2(1, 0))
        // L 字の凹んだ所は近い方の辺の外向き
        assertClose(Obstacle.polygon(Self.lShape).outwardNormal(at: Vec2(5180, 5120)), Vec2(0, 1))
    }

    func testMirroredAndReflectedStayCounterClockwiseAndMapPoints() {
        var rng = SplitMix64(seed: 7)
        for o in [Obstacle.polygon(Self.lShape), Self.wall, Self.crescent] {
            let v = Self.polygonVertices(o)
            let m = o.mirrored, d = o.reflectedAcrossDiagonal
            let mv = Self.polygonVertices(m), dv = Self.polygonVertices(d)
            XCTAssertGreaterThan(Spline.signedArea(mv), 0)
            XCTAssertGreaterThan(Spline.signedArea(dv), 0)
            XCTAssertEqual(mv, v.map(\.mirrored))
            XCTAssertEqual(dv, v.reversed().map { Vec2($0.y, $0.x) })
            XCTAssertEqual(m.bounds, o.bounds.mirrored)
            XCTAssertEqual(m.mirrored, o)
            XCTAssertEqual(d.reflectedAcrossDiagonal, o)
            let b = o.bounds.expanded(by: 200)
            for _ in 0..<300 {
                let p = Vec2(rng.nextDouble(in: b.minX..<b.maxX), rng.nextDouble(in: b.minY..<b.maxY))
                let swapped = Vec2(p.y, p.x)
                XCTAssertEqual(m.signedDistance(to: p.mirrored), o.signedDistance(to: p), accuracy: 1e-6)
                XCTAssertEqual(d.signedDistance(to: swapped), o.signedDistance(to: p), accuracy: 1e-6)
                XCTAssertEqual(m.contains(p.mirrored, inflatedBy: 30), o.contains(p, inflatedBy: 30))
                assertClose(m.outwardNormal(at: p.mirrored), -o.outwardNormal(at: p), accuracy: 1e-6)
                let n = o.outwardNormal(at: p)
                assertClose(d.outwardNormal(at: swapped), Vec2(n.y, n.x), accuracy: 1e-6)
            }
        }
    }

    func testSmoothPolygonIsCounterClockwiseAndPassesThroughControlPoints() {
        // 制御点は時計回り → 反時計回りに直る
        XCTAssertLessThan(Spline.signedArea(Self.unevenControl), 0)
        let o = Obstacle.smoothPolygon(Self.unevenControl)
        let v = Self.polygonVertices(o)
        XCTAssertGreaterThan(Spline.signedArea(v), 0)
        XCTAssertEqual(v.count, Self.unevenControl.count * 6)
        for p in Self.unevenControl { XCTAssertTrue(v.contains(p), "\(p) is not a vertex") }
        // 頂点は 1/64 単位: 点対称を 2 回掛けると元の壁に戻る
        XCTAssertEqual(o.mirrored.mirrored, o)
        for p in v {
            XCTAssertEqual(p.x * 64, (p.x * 64).rounded())
            XCTAssertEqual(p.y * 64, (p.y * 64).rounded())
        }
        // 自己交差しない（隣り合わない辺どうしが交わらない）・尖らない（隣の辺との折れが 90° 未満）
        let n = v.count
        for i in 0..<n {
            let a = v[i], b = v[(i + 1) % n], c = v[(i + 2) % n]
            XCTAssertGreaterThan((b - a).dot(c - b), 0, "cusp at \(b)")
            for j in stride(from: i + 2, to: n, by: 1) where !(i == 0 && j == n - 1) {
                XCTAssertFalse(MapDefinition.segmentsIntersect(a, b, v[j], v[(j + 1) % n]), "edges \(i) and \(j) cross")
            }
        }
        // 曲線は制御点の多角形から大きく外れない
        let hull = Obstacle.polygon(Array(Self.unevenControl.reversed()))
        for p in v { XCTAssertLessThan(hull.signedDistance(to: p), 150, "\(p)") }
        // 制御点の向き・始点を変えても同じ曲線
        let rotated = Array(Self.unevenControl[2...] + Self.unevenControl[..<2])
        XCTAssertEqual(Set(Self.polygonVertices(Obstacle.smoothPolygon(rotated))), Set(v))
        XCTAssertEqual(Set(Self.polygonVertices(Obstacle.smoothPolygon(Self.unevenControl.reversed()))), Set(v))
        // 重なった制御点は無視する
        var doubled = Self.unevenControl
        doubled.insert(doubled[3], at: 3)
        XCTAssertEqual(Self.polygonVertices(Obstacle.smoothPolygon(doubled)), v)
    }

    func testSegmentDistanceAndRectOverlapForValidation() {
        let l = Obstacle.polygon(Self.lShape)
        XCTAssertEqual(MapDefinition.distance(from: l, toSegment: Vec2(5400, 5000), Vec2(5400, 5300)), 100, accuracy: 1e-9)
        XCTAssertEqual(MapDefinition.distance(from: l, toSegment: Vec2(4900, 5050), Vec2(5400, 5050)), 0)
        XCTAssertEqual(MapDefinition.distance(from: l, toSegment: Vec2(5020, 5020), Vec2(5080, 5080)), 0) // 内部
        XCTAssertEqual(MapDefinition.distance(from: l, toSegment: Vec2(5150, 5150), Vec2(5250, 5250)), 50, accuracy: 1e-9)
        // 開いた矩形と内部の重なり（辺の共有・接触は重ならない）
        XCTAssertTrue(MapDefinition.rect(Rect2(minX: 5010, minY: 5010, maxX: 5090, maxY: 5090), overlaps: l)) // 中にすっぽり
        XCTAssertTrue(MapDefinition.rect(Rect2(minX: 5250, minY: 4950, maxX: 5350, maxY: 5050), overlaps: l)) // 角に掛かる
        XCTAssertTrue(MapDefinition.rect(Rect2(minX: 4900, minY: 4900, maxX: 5400, maxY: 5400), overlaps: l)) // 全体を覆う
        XCTAssertFalse(MapDefinition.rect(Rect2(minX: 5110, minY: 5110, maxX: 5290, maxY: 5290), overlaps: l)) // 凹みの中
        XCTAssertFalse(MapDefinition.rect(Rect2(minX: 5100, minY: 5100, maxX: 5200, maxY: 5200), overlaps: l)) // 辺を共有
        XCTAssertFalse(MapDefinition.rect(Rect2(minX: 5300, minY: 4900, maxX: 5400, maxY: 5000), overlaps: l)) // 角で接する
        // 斜めの辺が矩形の対角線を通るだけでも重なる
        let tri = Obstacle.polygon([Vec2(0, 0), Vec2(100, 0), Vec2(100, 100)])
        XCTAssertTrue(MapDefinition.rect(Rect2(minX: 0, minY: 0, maxX: 100, maxY: 100), overlaps: tri))
        XCTAssertFalse(MapDefinition.rect(Rect2(minX: 0, minY: 50, maxX: 40, maxY: 100), overlaps: tri))
    }

    // MARK: - NavGrid

    func testRaycastStopsBeforeDiagonalWall() {
        let s = Vec2(6000, 4000)
        let inward = Vec2(-1, 1).normalized
        // 面へ垂直に: 面（y = x − 1000）まで 1000/√2、その r 手前のさらに 1 手前で止まる
        let hit = nav.raycast(from: s, to: s + inward * 1000, radius: r)
        XCTAssertEqual(hit.distance(to: s), 1000 / sqrt2 - r - 1, accuracy: 0.5)
        XCTAssertTrue(nav.isWalkable(hit, radius: r))
        XCTAssertFalse(Self.wall.contains(hit, inflatedBy: r))
        // 斜めに（真西へ）: 面から r になる x = 5000 + r√2 の 1 手前
        let west = nav.raycast(from: s, to: Vec2(4000, 4000), radius: r)
        XCTAssertEqual(west.x, 5000 + r * sqrt2 + 1, accuracy: 0.5)
        XCTAssertEqual(west.y, 4000, accuracy: 1e-9)
        XCTAssertTrue(nav.isWalkable(west, radius: r))
        // 半径 0 は面そのものの 1 手前
        XCTAssertEqual(nav.raycast(from: s, to: Vec2(4000, 4000), radius: 0).x, 5001, accuracy: 0.5)
        // 面と平行に r + 5 離れて進むと最後まで行ける（r − 5 は線分が塞がる）
        let out = Vec2(1, -1).normalized
        let a = Vec2(4200, 3200) + out * (r + 5), b = Vec2(6800, 5800) + out * (r + 5)
        XCTAssertEqual(nav.raycast(from: a, to: b, radius: r), b)
        XCTAssertTrue(nav.hasLineOfSight(from: a, to: b, radius: r))
        XCTAssertFalse(nav.hasLineOfSight(from: a, to: b, radius: r + 10))
        XCTAssertFalse(nav.hasLineOfSight(from: s, to: Vec2(4000, 6000), radius: 0))
        // ブリンクは壁を越えて向こう側（上側の面の外）へ降りる
        let over = s + inward * 1300
        let landing = nav.blinkLanding(from: s, to: over, radius: r)
        XCTAssertEqual(landing.distance(to: over), 0, accuracy: 1e-6)
    }

    /// レイキャストの入る時刻は、移動の途中の点を細かく測った結果と一致する（どの辺・角から当たっても）。
    func testRaycastEntryTimeMatchesDenseSampling() {
        var rng = SplitMix64(seed: 99)
        var hits = 0
        for o in [Self.wall, Self.crescent, Obstacle.polygon(Self.lShape)] {
            let b = o.bounds.expanded(by: 400)
            for rad in [0.0, r, 140] {
                var tried = 0
                while tried < 300 {
                    let a = Vec2(rng.nextDouble(in: b.minX..<b.maxX), rng.nextDouble(in: b.minY..<b.maxY))
                    guard !o.contains(a, inflatedBy: rad) else { continue }
                    tried += 1
                    let d = Vec2(rng.nextDouble(in: -800..<800), rng.nextDouble(in: -800..<800))
                    let t = NavGrid.entryTime(o, from: a, delta: d, radius: rad)
                    let samples = 400
                    var firstInside: Int?
                    for k in 0...samples where o.contains(a + d * (Double(k) / Double(samples)), inflatedBy: rad) {
                        firstInside = k
                        break
                    }
                    let step = 1.0 / Double(samples)
                    if let t {
                        hits += 1
                        // 当たった点は膨張した境界の上、それより手前（標本の間隔ぶん手前まで）は外
                        XCTAssertEqual(o.signedDistance(to: a + d * t), rad, accuracy: 1e-6)
                        if let k = firstInside { XCTAssertLessThanOrEqual(t, Double(k) * step + 1e-9) }
                        let before = Int((t / step).rounded(.down)) - 1
                        if before >= 0 { XCTAssertFalse(o.contains(a + d * (Double(before) * step), inflatedBy: rad)) }
                    } else {
                        XCTAssertNil(firstInside, "missed entry from \(a) by \(d) r=\(rad)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(hits, 300)
    }

    /// 視線（線分が半径 r で壁に触れないか）は、線分上を細かく測ったクリアランスと一致する。
    func testLineOfSightMatchesDenseSampling() {
        var rng = SplitMix64(seed: 5)
        var blocked = 0, clear = 0
        for o in [Self.wall, Self.crescent] {
            let b = o.bounds.expanded(by: 500)
            for k in 0..<600 {
                // 半分は外接矩形を横切る長い線分（壁を越えるものが多い）、半分は短い線分（角をかすめるものを含む）
                let a = Vec2(rng.nextDouble(in: b.minX..<b.maxX), rng.nextDouble(in: b.minY..<b.maxY))
                let c = k % 2 == 0
                    ? Vec2(rng.nextDouble(in: b.minX..<b.maxX), rng.nextDouble(in: b.minY..<b.maxY))
                    : a + Vec2(rng.nextDouble(in: -500..<500), rng.nextDouble(in: -500..<500))
                let rad = rng.nextDouble(in: 0..<150)
                guard nav.isWalkable(a, radius: rad), nav.isWalkable(c, radius: rad) else { continue }
                let samples = 600
                var minClearance = Double.infinity
                for k in 0...samples { minClearance = min(minClearance, nav.clearance(at: Vec2.lerp(a, c, Double(k) / Double(samples)))) }
                let spacing = a.distance(to: c) / Double(samples)
                if nav.hasLineOfSight(from: a, to: c, radius: rad) {
                    clear += 1
                    XCTAssertGreaterThan(minClearance, rad - 1e-6, "\(a) -> \(c) r=\(rad)")
                } else {
                    blocked += 1
                    XCTAssertLessThanOrEqual(minClearance, rad + spacing, "\(a) -> \(c) r=\(rad)")
                }
            }
        }
        XCTAssertGreaterThan(blocked, 50, "blocked \(blocked) clear \(clear)")
        XCTAssertGreaterThan(clear, 50, "blocked \(blocked) clear \(clear)")
    }

    func testResolveMoveSlidesAlongDiagonalWall() {
        let tangent = Vec2(1, 1).normalized
        // 下側の面（外向き (1, −1)/√2）に真上へ押し込む → 面に沿って北東へ滑る（一直線上の頂点 (5500, 4500) も越える）
        let lower = Vec2(1, -1).normalized
        var pos = Vec2(5300, 4300) + lower * (r + 0.5)
        XCTAssertTrue(nav.isWalkable(pos, radius: r))
        var progress = 0.0
        for _ in 0..<100 {
            let before = pos
            pos = nav.resolveMove(from: pos, to: pos + Vec2(0, 6), radius: r)
            XCTAssertTrue(nav.isWalkable(pos, radius: r), "\(pos)")
            XCTAssertFalse(Self.wall.contains(pos, inflatedBy: r), "\(pos)")
            XCTAssertGreaterThan((pos - before).dot(tangent), 4, "stuck at \(before)")
            progress += (pos - before).dot(tangent)
        }
        XCTAssertGreaterThan(progress, 400)
        XCTAssertEqual(Self.wall.signedDistance(to: pos), r + 0.5, accuracy: 1e-6)

        // 上側の面（外向き (−1, 1)/√2）に真東へ押し込む → 同じく北東へ
        let upper = Vec2(-1, 1).normalized
        var q = Vec2(5000, 4600) + upper * (r + 0.5)
        for _ in 0..<60 {
            let before = q
            q = nav.resolveMove(from: q, to: q + Vec2(6, 0), radius: r)
            XCTAssertTrue(nav.isWalkable(q, radius: r), "\(q)")
            XCTAssertGreaterThan((q - before).dot(tangent), 4, "stuck at \(before)")
        }
        // 真正面（法線の逆向き）は止まる
        let front = Vec2(5000, 4000) + lower * (r + 0.5)
        XCTAssertEqual(nav.resolveMove(from: front, to: front - lower * 6, radius: r), front)
    }

    func testResolveMoveAroundDiagonalWallNeverEntersIt() {
        // いろいろな向きから壁へ押し込み続けても、壁（膨張込み）の中には入らない
        var rng = SplitMix64(seed: 3)
        let w = Self.wall
        let b = w.bounds.expanded(by: 300)
        var moved = 0
        for _ in 0..<200 {
            var pos = Vec2(rng.nextDouble(in: b.minX..<b.maxX), rng.nextDouble(in: b.minY..<b.maxY))
            guard nav.isWalkable(pos, radius: r) else { continue }
            let toward = (Vec2(5350, 4650) - pos).normalized.rotated(by: rng.nextDouble(in: -1.2..<1.2))
            let start = pos
            for _ in 0..<80 {
                pos = nav.resolveMove(from: pos, to: pos + toward * 7, radius: r)
                XCTAssertTrue(nav.isWalkable(pos, radius: r), "\(pos)")
            }
            if pos.distance(to: start) > 1 { moved += 1 }
        }
        XCTAssertGreaterThan(moved, 50)
    }

    func testFindPathRoutesAroundConcaveCrescent() {
        let o = Self.crescentCenter
        let from = o + Vec2(300, 0) // C の空洞（口の奥）
        let to = o + Vec2(-2000, 0) // C の背中の向こう
        XCTAssertTrue(nav.isWalkable(from, radius: r))
        XCTAssertFalse(nav.hasLineOfSight(from: from, to: to, radius: r))
        let path = nav.findPath(from: from, to: to, radius: r)
        XCTAssertGreaterThan(path.count, 1)
        XCTAssertEqual(path.last, to)
        var a = from
        var length = 0.0
        for p in path {
            XCTAssertTrue(nav.isWalkable(p, radius: r), "\(p)")
            XCTAssertFalse(Self.crescent.contains(p, inflatedBy: r), "\(p)")
            XCTAssertTrue(nav.hasLineOfSight(from: a, to: p, radius: r - 10), "\(a) -> \(p)")
            length += a.distance(to: p)
            a = p
        }
        // 口から出て、先端を回り込んで外周の外を通る
        XCTAssertTrue(path.contains { $0.distance(to: o) > 1200 }, "\(path)")
        XCTAssertGreaterThan(length, from.distance(to: to) + 1000)
        // 平滑化されている（格子の階段ではない）
        XCTAssertLessThan(path.count, 16)
        // 逆向きも通れる
        XCTAssertEqual(nav.findPath(from: to, to: from, radius: r).last, from)
    }

    func testNearestWalkableFromInsidePolygonLandsOutside() {
        // 斜めの壁の帯の中心線（y = x − 700）から: どちらかの面の外へ、帯の半分の厚さ（150√2）+ r + 1 ほど
        let inside = Vec2(5350, 4650)
        XCTAssertTrue(Self.wall.contains(inside))
        let q = nav.nearestWalkable(inside, radius: r)
        XCTAssertTrue(nav.isWalkable(q, radius: r))
        XCTAssertFalse(Self.wall.contains(q, inflatedBy: r))
        XCTAssertEqual(q.distance(to: inside), 150 * sqrt2 + r + 1, accuracy: 2)
        // 面のすぐ内側からは近い方の面の外へ
        let shallow = Vec2(5000, 4000) - Vec2(1, -1).normalized * 20
        let q1 = nav.nearestWalkable(shallow, radius: r)
        XCTAssertTrue(nav.isWalkable(q1, radius: r))
        XCTAssertEqual(q1.distance(to: shallow), 20 + r + 1, accuracy: 2)
        // 三日月の背中の帯の中から
        let ring = Self.crescentCenter + Vec2(-1000, 0)
        XCTAssertTrue(Self.crescent.contains(ring))
        let q2 = nav.nearestWalkable(ring, radius: r)
        XCTAssertTrue(nav.isWalkable(q2, radius: r))
        XCTAssertFalse(Self.crescent.contains(q2, inflatedBy: r))
        XCTAssertLessThan(q2.distance(to: ring), 200 + r + 5)
    }

    /// 矩形の膨張は角が丸い: 角から斜めに L∞ で 0.8r（四角い膨張なら中）でも、ユークリッドで r より遠ければ歩ける。
    func testRectCornersInflateRounded() {
        let corner = Vec2(Self.block.maxX, Self.block.maxY)
        let off = corner + Vec2(0.8 * r, 0.8 * r)
        XCTAssertGreaterThan(off.distance(to: corner), r)
        XCTAssertTrue(nav.isWalkable(off, radius: r))
        XCTAssertFalse(Obstacle.rect(Self.block).contains(off, inflatedBy: r))
        XCTAssertEqual(Obstacle.rect(Self.block).signedDistance(to: off), 0.8 * r * sqrt2, accuracy: 1e-9)
        // 角からユークリッドで r 未満は歩けない・辺の正面は従来どおり r まで
        XCTAssertFalse(nav.isWalkable(corner + Vec2(0.6 * r, 0.6 * r), radius: r))
        XCTAssertFalse(nav.isWalkable(Vec2(8300, Self.block.maxY + 0.8 * r), radius: r))
        // 角をかすめる斜めの線分も通れる（角まで四角く膨張すると塞がる）
        let a = off + Vec2(-200, 200), b = off + Vec2(200, -200)
        XCTAssertTrue(nav.hasLineOfSight(from: a, to: b, radius: r))
        XCTAssertEqual(nav.raycast(from: a, to: b, radius: r), b)
        // 角の外の法線は角の点から外へ
        assertClose(Obstacle.rect(Self.block).outwardNormal(at: off), Vec2(1, 1).normalized)
    }

    /// 外接矩形で省いても、格子のクリアランス・点のクリアランス・最も食い込んだ障害物は全部を測った場合と完全に同じ。
    func testPrefilteredDistancesMatchBruteForceExactly() {
        for map in [Self.testMap, MapDefinition.standard, MapDefinition.relayout] {
            let grid = NavGrid(map: map)
            func brute(_ p: Vec2) -> Double {
                var d = min(min(p.x, p.y), min(map.size - p.x, map.size - p.y))
                for o in map.obstacles { d = min(d, o.signedDistance(to: p)) }
                return d
            }
            var mismatches = 0
            for i in 0..<(grid.cols * grid.rows) where grid.clearance[i] != brute(grid.center(ofCell: i)) { mismatches += 1 }
            XCTAssertEqual(mismatches, 0)
            var rng = SplitMix64(seed: 42)
            for k in 0..<3000 {
                // 半分は障害物の近く
                let p: Vec2
                if k % 2 == 0, !map.obstacles.isEmpty {
                    let b = map.obstacles[k / 2 % map.obstacles.count].bounds.expanded(by: 250)
                    p = Vec2(rng.nextDouble(in: b.minX..<b.maxX), rng.nextDouble(in: b.minY..<b.maxY))
                } else {
                    p = Vec2(rng.nextDouble(in: 0..<map.size), rng.nextDouble(in: 0..<map.size))
                }
                XCTAssertEqual(grid.clearance(at: p), brute(p))
                let rad = rng.nextDouble(in: 0..<250)
                var best: Int?
                var bestD = Double.infinity
                for (j, o) in map.obstacles.enumerated() {
                    let d = o.signedDistance(to: p) - rad
                    if d <= 0 && d < bestD { bestD = d; best = j }
                }
                XCTAssertEqual(grid.mostPenetrated(at: p, radius: rad), best)
            }
        }
    }

    /// 滑らかな多角形の壁を 100 個（各 48 頂点）並べた地図: 格子の焼き込みは外接矩形の前段判定で総当たりより速く、
    /// 結果は総当たりと完全に同じ。壁の近くの点・線分の問い合わせの時間も出す（Release でのみ計測）。
    func testManyPolygonWallsBakeFastAndExactly() throws {
        #if DEBUG
        throw XCTSkip("Release でのみ計測する（swift test -c release --filter PolygonObstacleTests）")
        #else
        var rng = SplitMix64(seed: 2026)
        var walls: [Obstacle] = []
        for _ in 0..<100 {
            let c = Vec2(rng.nextDouble(in: 800..<11200), rng.nextDouble(in: 800..<11200))
            let size = rng.nextDouble(in: 150..<450)
            let control = (0..<8).map { k -> Vec2 in
                let a = Double(k) / 8 * 2 * .pi
                return c + Vec2(cos(a), sin(a)) * (size * rng.nextDouble(in: 0.6..<1.4))
            }
            walls.append(.smoothPolygon(control))
        }
        XCTAssertEqual(walls.map { Self.polygonVertices($0).count }, Array(repeating: 48, count: 100))
        var map = MapDefinition.standard
        map.brushes = []
        map.obstacles = walls
        func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
        let t0 = now()
        let grid = NavGrid(map: map)
        let bakeMs = Double(now() - t0) / 1e6
        let t1 = now()
        var mismatches = 0
        for i in 0..<(grid.cols * grid.rows) {
            let p = grid.center(ofCell: i)
            var d = min(min(p.x, p.y), min(map.size - p.x, map.size - p.y))
            for o in map.obstacles { d = min(d, o.signedDistance(to: p)) }
            if grid.clearance[i] != d { mismatches += 1 }
        }
        let bruteMs = Double(now() - t1) / 1e6
        XCTAssertEqual(mismatches, 0)
        XCTAssertLessThan(bakeMs, bruteMs)
        // 壁の近く（外接矩形 + 200 の中）の点・移動・線分の問い合わせ
        var points: [Vec2] = []
        for k in 0..<20000 {
            let b = walls[k % walls.count].bounds.expanded(by: 200)
            points.append(Vec2(rng.nextDouble(in: b.minX..<b.maxX), rng.nextDouble(in: b.minY..<b.maxY)))
        }
        var sink = 0.0
        let t2 = now()
        for p in points where grid.isWalkable(p, radius: r) { sink += 1 }
        let walkUs = Double(now() - t2) / 1e3 / Double(points.count)
        let t3 = now()
        for (k, p) in points.enumerated() { sink += grid.raycast(from: p, to: points[(k + 1) % points.count] * 0.02 + p * 0.98, radius: r).x }
        let rayUs = Double(now() - t3) / 1e3 / Double(points.count)
        let t4 = now()
        for (k, p) in points.enumerated() where grid.hasLineOfSight(from: p, to: points[(k + 7) % points.count], radius: r) { sink += 1 }
        let losUs = Double(now() - t4) / 1e3 / Double(points.count)
        print(String(format: "polygon walls: bake %.1f ms (all distances brute force %.1f ms), isWalkable %.2f us, raycast %.2f us, lineOfSight %.2f us (%.0f)",
                     bakeMs, bruteMs, walkUs, rayUs, losUs, sink))
        #endif
    }

    // MARK: - 補助

    static func polygonVertices(_ o: Obstacle) -> [Vec2] {
        guard case .polygon(let v) = o else { return [] }
        return v
    }

    private func assertClose(_ a: Vec2, _ b: Vec2, accuracy: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, "\(a) vs \(b)", file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, "\(a) vs \(b)", file: file, line: line)
    }
}
