import Foundation

// 担当: core-world。
// 50 ユニット格子（2026-10-16 に 100 から細かくした。遊ぶ地図 9720 で 195×195）に障害物を焼き込む。各格子中心に
// 「最寄りの障害物・マップ端までの距離」（クリアランス）を保持し、半径 r の単位は clearance > r の格子だけを通る。
// 経路探索は粗い格子（細かい格子 4×4 = 200 ユニット）で通り道を下見し、その帯（前後左右 1 つ）の中だけを細かい格子で探す
// （見つからなければ全体を探す）。粗い格子は中の細かい格子の最大のクリアランスで通れるかを決めるので、粗い格子で
// 道が無ければ細かい格子にも無い。移動の衝突は格子ではなく壁の形そのもの（多角形・円・矩形）で判定する。
// ヒーロー半径（55）の格子は連結成分まで焼き込み、到達不能判定を O(1) にする。その他の半径は格子毎に判定する。
// 経路はすべて配列・固定順で計算する（決定論）。

/// 障害物を焼き込んだ格子と経路探索。
public final class NavGrid: @unchecked Sendable {
    public let cellSize: Double
    public let cols: Int
    public let rows: Int
    public let map: MapDefinition

    /// 連結成分を焼き込む半径（ヒーロー）。
    public static let bakedRadius: Double = Balance.heroRadius

    /// 格子中心のクリアランス（障害物・マップ端までの距離。障害物内部は負）。index = row * cols + col
    let clearance: [Double]
    /// bakedRadius での連結成分（-1 = 通行不可）。
    let bakedComponents: [Int32]
    /// 障害物（map.obstacles の写し）と外接矩形（前段判定用、同順）。
    let obstacles: [Obstacle]
    let obstacleBounds: [Rect2]
    let cache: PathCache
    /// 粗い格子 1 つに入る細かい格子の数（1 辺）。
    static let coarseFactor = 4
    let coarseCols: Int
    let coarseRows: Int
    /// 粗い格子のクリアランス（中の細かい格子の最大）。
    let coarseClearance: [Double]
    /// 1 tick の移動がこれより長いときは直進判定（すり抜け防止）。格子の細かさと切り離した固定値。
    static let longMoveThreshold: Double = 50

    public init(map: MapDefinition, cellSize: Double = 50) {
        self.map = map
        self.cellSize = cellSize
        self.cols = Int((map.size / cellSize).rounded(.up))
        self.rows = cols
        self.obstacles = map.obstacles
        let bounds = map.obstacles.map(\.bounds)
        self.obstacleBounds = bounds

        var cl = [Double](repeating: 0, count: cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let p = Vec2((Double(c) + 0.5) * cellSize, (Double(r) + 0.5) * cellSize)
                let edge = min(min(p.x, p.y), min(map.size - p.x, map.size - p.y))
                cl[r * cols + c] = NavGrid.nearestObstacleDistance(map.obstacles, bounds, at: p, upTo: edge)
            }
        }
        self.clearance = cl
        let f = NavGrid.coarseFactor
        let cc = (cols + f - 1) / f, cr = (rows + f - 1) / f
        var coarse = [Double](repeating: -.infinity, count: cc * cr)
        for r in 0..<rows {
            for c in 0..<cols {
                let k = (r / f) * cc + c / f
                coarse[k] = max(coarse[k], cl[r * cols + c])
            }
        }
        self.coarseCols = cc
        self.coarseRows = cr
        self.coarseClearance = coarse
        self.bakedComponents = NavGrid.labelComponents(clearance: cl, cols: cols, rows: rows,
                                                        radius: NavGrid.bakedRadius)
        self.cache = PathCache()
    }

    /// 地図ごとに 1 つの格子を共有する（焼き込みは地図ごとに 1 回。格子は不変で、経路のキャッシュは決定論的な値だけを持つ）。
    public static func shared(for map: MapDefinition) -> NavGrid { sharedStore.grid(for: map) }

    private static let sharedStore = SharedStore()

    private final class SharedStore: @unchecked Sendable {
        private let lock = NSLock()
        private var grids: [NavGrid] = []

        func grid(for map: MapDefinition) -> NavGrid {
            lock.lock()
            defer { lock.unlock() }
            if let hit = grids.first(where: { $0.map == map }) { return hit }
            let grid = NavGrid(map: map)
            grids.append(grid)
            // テストは小さな地図をたくさん作るので、古いものから捨てる
            if grids.count > 8 { grids.removeFirst() }
            return grid
        }
    }

    // MARK: - 点の判定

    /// 点が歩行可能か（マップ内かつ障害物外）。
    public func isWalkable(_ p: Vec2, radius: Double = 0) -> Bool {
        guard p.x >= radius, p.y >= radius, p.x <= map.size - radius, p.y <= map.size - radius else { return false }
        for k in obstacleBounds.indices {
            let b = obstacleBounds[k]
            if p.x < b.minX - radius || p.x > b.maxX + radius || p.y < b.minY - radius || p.y > b.maxY + radius { continue }
            if obstacles[k].contains(p, inflatedBy: radius) { return false }
        }
        return true
    }

    /// 点のクリアランス（最寄りの障害物・マップ端までの距離。内部は負）。
    public func clearance(at p: Vec2) -> Double {
        let edge = min(min(p.x, p.y), min(map.size - p.x, map.size - p.y))
        return NavGrid.nearestObstacleDistance(obstacles, obstacleBounds, at: p, upTo: edge)
    }

    /// 外接矩形による前段判定の余裕（距離の計算誤差 ≈ 1e-12 より十分大きく、地図の尺度より十分小さい）。
    /// 前段判定で省いた障害物は、省かずに測っても結果に効かないことをこの余裕で保証する。
    static let boundsSlack: Double = 1e-6

    /// 点から最も近い障害物までの符号付き距離（limit 以下に切り詰める）。外接矩形が最も近い障害物を先に測って
    /// 最小値を詰め、残りは外接矩形までの距離がその最小値より遠ければ測らない（障害物までの距離 ≥ 外接矩形までの距離
    /// なので、全部を測った場合と結果は同じ）。多角形は辺の数だけ重いので、格子の焼き込みで効く。
    static func nearestObstacleDistance(_ obstacles: [Obstacle], _ bounds: [Rect2], at p: Vec2, upTo limit: Double) -> Double {
        var d = limit
        var first = -1
        var firstBox = Double.infinity
        for k in bounds.indices {
            let q = boxDistanceSquared(bounds[k], p)
            if q < firstBox { firstBox = q; first = k }
        }
        guard first >= 0, !boxIsFarther(firstBox, than: d) else { return d }
        d = min(d, obstacles[first].signedDistance(to: p))
        for k in bounds.indices where k != first && !boxIsFarther(boxDistanceSquared(bounds[k], p), than: d) {
            d = min(d, obstacles[k].signedDistance(to: p))
        }
        return d
    }

    /// 点から外接矩形までの距離の 2 乗（矩形の中なら 0）。
    @inline(__always) static func boxDistanceSquared(_ b: Rect2, _ p: Vec2) -> Double {
        let dx = max(b.minX - p.x, 0, p.x - b.maxX), dy = max(b.minY - p.y, 0, p.y - b.maxY)
        return dx * dx + dy * dy
    }

    /// 外接矩形の外にある点（boxD2 > 0。障害物の外でもある）について、その障害物までの距離が確実に d より大きいか。
    @inline(__always) static func boxIsFarther(_ boxD2: Double, than d: Double) -> Bool {
        guard boxD2 > 0 else { return false }
        let lim = d + boundsSlack
        return lim <= 0 || boxD2 >= lim * lim
    }

    /// 線分 a→b を半径 radius の単位が障害物・マップ端に触れずに通れるか。
    public func hasLineOfSight(from a: Vec2, to b: Vec2, radius: Double = 0) -> Bool {
        segmentClear(a, b, radius: radius)
    }

    // MARK: - 経路探索

    /// from → to の経路（先頭は最初の経由点、末尾は to 付近の歩行可能点）。到達不能なら空。
    public func findPath(from: Vec2, to: Vec2, radius: Double = 0) -> [Vec2] {
        let r = max(0, radius)
        guard r * 2 < map.size else { return [] }
        let goal = nearestWalkable(to, radius: r)
        guard isWalkable(goal, radius: r) else { return [] }
        var start = from
        var prefix: [Vec2] = []
        if !isWalkable(from, radius: r) {
            // 障害物に食い込んでいる場合はまず最寄りの歩行可能点へ抜ける
            start = nearestWalkable(from, radius: r)
            guard isWalkable(start, radius: r) else { return [] }
            prefix = [start]
        }
        if segmentClear(start, goal, radius: r) {
            return prefix.last == goal ? prefix : prefix + [goal]
        }
        guard let startCell = nearestWalkableCell(to: start, radius: r),
              let goalCell = nearestWalkableCell(to: goal, radius: r) else { return [] }
        if abs(r - NavGrid.bakedRadius) < 1e-9, bakedComponents[startCell] != bakedComponents[goalCell] {
            return []
        }
        guard let cells = cachedCellPath(from: startCell, to: goalCell, radius: r) else { return [] }

        // 格子中心列 → 実座標（始点・終点は正確な点）→ 視線による平滑化
        var pts: [Vec2] = [start]
        pts.reserveCapacity(cells.count + 2)
        for cell in cells.dropFirst() { pts.append(center(ofCell: Int(cell))) }
        if cells.count > 1 { pts.removeLast() }
        pts.append(goal)
        return prefix + smooth(pts, radius: r)
    }

    /// from から to へ直進し、障害物/マップ端の手前で止まる点（ブリンク・突進用）。
    public func raycast(from: Vec2, to: Vec2, radius: Double = 0) -> Vec2 {
        let r = max(0, radius)
        let a = clampToMap(from, radius: r)
        let d = to - a
        let len = d.length
        if len < 1e-9 { return a }
        var tHit = 1.0
        // マップ端（[r, size - r] の箱）から出る位置
        let lo = r, hi = map.size - r
        if d.x > 0 { tHit = min(tHit, (hi - a.x) / d.x) } else if d.x < 0 { tHit = min(tHit, (lo - a.x) / d.x) }
        if d.y > 0 { tHit = min(tHit, (hi - a.y) / d.y) } else if d.y < 0 { tHit = min(tHit, (lo - a.y) / d.y) }
        tHit = max(0, tHit)
        // 障害物へ入る位置（始点を含む障害物は抜け出す向きなので無視）
        for (k, o) in obstacles.enumerated() {
            let b = obstacleBounds[k].expanded(by: r)
            if max(a.x, to.x) < b.minX || min(a.x, to.x) > b.maxX || max(a.y, to.y) < b.minY || min(a.y, to.y) > b.maxY {
                continue
            }
            if o.contains(a, inflatedBy: r) { continue }
            if let t = NavGrid.entryTime(o, from: a, delta: d, radius: r), t < tHit { tHit = t }
        }
        if tHit >= 1 { return clampToMap(to, radius: r) }
        // 接触点の手前（1 ユニット）で止める
        let dist = max(0, tHit * len - 1)
        var p = a + d * (dist / len)
        if !isWalkable(p, radius: r) && isWalkable(a, radius: r) {
            // 数値誤差で食い込んだ場合は少しずつ戻す
            var back = dist
            while back > 0 && !isWalkable(p, radius: r) {
                back = max(0, back - 2)
                p = a + d * (back / len)
            }
        }
        return p
    }

    /// ブリンクの着地点（MLBB のフラッシュと同じく壁を越えられる）。to が歩行可能ならそこ、壁の中なら from 側へ
    /// 戻って最初の歩行可能点。始点から歩いて行けない閉じた区画には降りない。見つからなければ raycast と同じ。
    public func blinkLanding(from: Vec2, to: Vec2, radius: Double = 0) -> Vec2 {
        let r = max(0, radius)
        let a = clampToMap(from, radius: r)
        let b = clampToMap(to, radius: r)
        let d = b - a
        let len = d.length
        if len < 1e-9 { return a }
        let baked = abs(r - NavGrid.bakedRadius) < 1e-9
        let startComp = baked ? bakedComponents[cellIndex(of: a)] : -1
        let step = max(1, cellSize * 0.1)
        var dist = len
        while dist > 0 {
            let p = a + d * (dist / len)
            if isWalkable(p, radius: r) {
                let comp = baked ? bakedComponents[cellIndex(of: p)] : -1
                if startComp < 0 || comp < 0 || comp == startComp { return p }
            }
            dist -= step
        }
        return raycast(from: a, to: b, radius: r)
    }

    /// 1 tick 分の移動を障害物に沿って解決（壁ずり）。
    public func resolveMove(from: Vec2, to: Vec2, radius: Double) -> Vec2 {
        let r = max(0, radius)
        let target = clampToMap(to, radius: r)
        let move = target - from
        if move.lengthSquared < 1e-12 { return from }
        // 長い移動はすり抜け防止のため直進判定
        if move.length > NavGrid.longMoveThreshold {
            return raycast(from: from, to: target, radius: r)
        }
        // 短い歩行でも線分全体を調べる。終点だけでは薄い壁や角を横切れる。
        if isWalkable(target, radius: r) {
            return raycast(from: from, to: target, radius: r)
        }

        let fromWalkable = isWalkable(from, radius: r)
        if fromWalkable {
            // 1) 接触面に沿った滑り（法線成分を除去）
            if let k = mostPenetrated(at: target, radius: r) {
                let n = obstacles[k].outwardNormal(at: from)
                let into = move.dot(n)
                if into < 0 {
                    let slide = move - n * into
                    let cand = from + slide
                    if slide.lengthSquared > 1e-12, segmentClear(from, cand, radius: r) { return cand }
                }
            }
            // 2) 軸ごとの射影（進行方向への寄与が大きい方を優先、同値は x を優先）
            let cx = Vec2(target.x, from.y)
            let cy = Vec2(from.x, target.y)
            let okX = abs(move.x) > 1e-9 && segmentClear(from, cx, radius: r)
            let okY = abs(move.y) > 1e-9 && segmentClear(from, cy, radius: r)
            if okX && okY { return abs(move.x) >= abs(move.y) ? cx : cy }
            if okX { return cx }
            if okY { return cy }
            return from
        }
        // 障害物に食い込んでいる（押し込まれた等）: クリアランスが増える移動のみ許可
        let c0 = clearance(at: from)
        if clearance(at: target) > c0 { return target }
        let cx = Vec2(target.x, from.y), cy = Vec2(from.x, target.y)
        let gx = clearance(at: cx), gy = clearance(at: cy)
        if gx > c0 || gy > c0 { return gx >= gy ? cx : cy }
        return from
    }

    /// 最寄りの歩行可能点。
    public func nearestWalkable(_ p: Vec2, radius: Double = 0) -> Vec2 {
        let r = max(0, radius)
        let q = clampToMap(p, radius: r)
        if isWalkable(q, radius: r) { return q }
        var best: Vec2?
        var bestD = Double.infinity
        func consider(_ c: Vec2) {
            guard isWalkable(c, radius: r) else { return }
            let d = c.distanceSquared(to: q)
            if d < bestD { bestD = d; best = c }
        }
        // 1) 単一障害物からの解析的な押し出し（最も近い境界の外側）
        for (k, o) in obstacles.enumerated() {
            // 外接矩形（r 膨張）の外なら含まない（多角形の判定は重いので先に省く）
            let b = obstacleBounds[k], lim = r + NavGrid.boundsSlack
            if q.x < b.minX - lim || q.x > b.maxX + lim || q.y < b.minY - lim || q.y > b.maxY + lim { continue }
            guard o.contains(q, inflatedBy: r) else { continue }
            switch o {
            case .circle(let c, let radius):
                let dir = (q - c).normalized == .zero ? Vec2(1, 0) : (q - c).normalized
                consider(clampToMap(c + dir * (radius + r + 1), radius: r))
            case .rect(let rect):
                let e = rect.expanded(by: r + 1)
                consider(clampToMap(Vec2(e.minX, q.y), radius: r))
                consider(clampToMap(Vec2(e.maxX, q.y), radius: r))
                consider(clampToMap(Vec2(q.x, e.minY), radius: r))
                consider(clampToMap(Vec2(q.x, e.maxY), radius: r))
            case .polygon(let v):
                // 最も近い境界の点から外向きに r + 1（凹んだ所では別の辺に掛かることがあるので consider が確かめる）
                let probe = Obstacle.probePolygon(v, q)
                guard probe.edge >= 0 else { continue }
                consider(clampToMap(probe.closest + Obstacle.polygonNormal(v, q, probe) * (r + 1), radius: r))
            }
        }
        // 2) 格子の螺旋探索（複数障害物の隙間など）→ 見つけた格子中心から q へ二分探索で境界まで寄せる
        if let cell = nearestWalkableCell(to: q, radius: r) {
            let c = center(ofCell: cell)
            var lo = 0.0, hi = 1.0 // lo: 歩行可能側（c）からの割合
            for _ in 0..<14 {
                let mid = (lo + hi) / 2
                if isWalkable(Vec2.lerp(c, q, mid), radius: r) { lo = mid } else { hi = mid }
            }
            consider(Vec2.lerp(c, q, lo))
            consider(c)
        }
        return best ?? q
    }

    func clampToMap(_ p: Vec2) -> Vec2 {
        Vec2(max(1, min(map.size - 1, p.x)), max(1, min(map.size - 1, p.y)))
    }

    func clampToMap(_ p: Vec2, radius r: Double) -> Vec2 {
        let lo = max(1, r), hi = map.size - max(1, r)
        return Vec2(max(lo, min(hi, p.x)), max(lo, min(hi, p.y)))
    }

    // MARK: - 格子

    @inline(__always) func cellIndex(of p: Vec2) -> Int {
        let c = min(cols - 1, max(0, Int(p.x / cellSize)))
        let r = min(rows - 1, max(0, Int(p.y / cellSize)))
        return r * cols + c
    }

    @inline(__always) func center(ofCell i: Int) -> Vec2 {
        Vec2((Double(i % cols) + 0.5) * cellSize, (Double(i / cols) + 0.5) * cellSize)
    }

    @inline(__always) func cellWalkable(_ i: Int, radius r: Double) -> Bool {
        clearance[i] > r
    }

    /// p に最も近い（格子中心距離）通行可能格子。同距離は添字の小さい方。
    func nearestWalkableCell(to p: Vec2, radius r: Double) -> Int? {
        let home = cellIndex(of: p)
        if cellWalkable(home, radius: r) { return home }
        let hc = home % cols, hr = home / cols
        var best: Int?
        var bestD = Double.infinity
        let maxRing = max(cols, rows)
        var ring = 1
        while ring <= maxRing {
            // この環の最短距離が既知の最良より遠ければ終了
            let ringMin = (Double(ring) - 1) * cellSize
            if best != nil && ringMin * ringMin > bestD { break }
            for dr in -ring...ring {
                let rr = hr + dr
                guard rr >= 0 && rr < rows else { continue }
                let step = (dr == -ring || dr == ring) ? 1 : 2 * ring
                var dc = -ring
                while dc <= ring {
                    let cc = hc + dc
                    if cc >= 0 && cc < cols {
                        let i = rr * cols + cc
                        if cellWalkable(i, radius: r) {
                            let d = center(ofCell: i).distanceSquared(to: p)
                            if d < bestD || (d == bestD && i < (best ?? Int.max)) { bestD = d; best = i }
                        }
                    }
                    dc += step
                }
            }
            ring += 1
        }
        return best
    }

    static func labelComponents(clearance: [Double], cols: Int, rows: Int, radius: Double) -> [Int32] {
        var label = [Int32](repeating: -1, count: cols * rows)
        var next: Int32 = 0
        var stack: [Int] = []
        for seed in 0..<(cols * rows) where clearance[seed] > radius && label[seed] < 0 {
            label[seed] = next
            stack.append(seed)
            while let i = stack.popLast() {
                let c = i % cols, r = i / cols
                for (dc, dr) in neighborOffsets {
                    let nc = c + dc, nr = r + dr
                    guard nc >= 0, nc < cols, nr >= 0, nr < rows else { continue }
                    let j = nr * cols + nc
                    guard clearance[j] > radius, label[j] < 0 else { continue }
                    if dc != 0 && dr != 0 {
                        // 角抜け禁止
                        guard clearance[r * cols + nc] > radius, clearance[nr * cols + c] > radius else { continue }
                    }
                    label[j] = next
                    stack.append(j)
                }
            }
            next += 1
        }
        return label
    }

    /// 8 近傍（固定順）。
    static let neighborOffsets: [(Int, Int)] = [(1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, 1), (-1, -1), (1, -1)]

    // MARK: - A*

    func cachedCellPath(from s: Int, to g: Int, radius r: Double) -> [Int32]? {
        let key = PathCache.Key(start: Int32(s), goal: Int32(g), radiusBits: r.bitPattern)
        if let hit = cache.lookup(key) { return hit.isEmpty ? nil : hit }
        let result = astar(from: s, to: g, radius: r)
        cache.store(key, result ?? [])
        return result
    }

    /// 細かい格子の経路（始点と終点を含む）。粗い格子で通り道を下見し、その帯の中だけを細かく探す。
    /// 帯の中で見つからなければ全体を探す。粗い格子で道が無ければ細かい格子にも無い（nil）。
    func astar(from s: Int, to g: Int, radius r: Double) -> [Int32]? {
        if s == g { return [Int32(s)] }
        // クロージャへ渡すので先に値として取り出す
        let f = NavGrid.coarseFactor
        let cols = self.cols, rows = self.rows, clearance = self.clearance
        let coarseCols = self.coarseCols, coarseRows = self.coarseRows, coarseClearance = self.coarseClearance
        func coarseIndex(_ i: Int) -> Int { (i / cols / f) * coarseCols + (i % cols) / f }
        let sc = coarseIndex(s), gc = coarseIndex(g)
        let near = max(abs(sc % coarseCols - gc % coarseCols), abs(sc / coarseCols - gc / coarseCols)) <= 2
        if !near {
            guard let coarsePath = NavGrid.gridAstar(cols: coarseCols, rows: coarseRows, from: sc, to: gc, cornerCheck: false,
                                                      passable: { coarseClearance[$0] > r }) else { return nil }
            var allowed = [Bool](repeating: false, count: coarseCols * coarseRows)
            for k in coarsePath {
                let kc = Int(k) % coarseCols, kr = Int(k) / coarseCols
                for dr in -1...1 {
                    for dc in -1...1 {
                        let rr = kr + dr, cc = kc + dc
                        if rr >= 0, cc >= 0, rr < coarseRows, cc < coarseCols { allowed[rr * coarseCols + cc] = true }
                    }
                }
            }
            if let path = NavGrid.gridAstar(cols: cols, rows: rows, from: s, to: g, cornerCheck: true, passable: { j in
                clearance[j] > r && allowed[coarseIndex(j)]
            }) {
                return path
            }
        }
        return NavGrid.gridAstar(cols: cols, rows: rows, from: s, to: g, cornerCheck: true, passable: { clearance[$0] > r })
    }

    /// 格子 A*（8 近傍・octile ヒューリスティック）。cornerCheck なら角抜けを禁止する（斜めに進むときは両隣も通れること）。
    /// 同点は (f, h, 添字) の昇順で決定論的に選ぶ。
    static func gridAstar(cols: Int, rows: Int, from s: Int, to g: Int, cornerCheck: Bool,
                          passable: (Int) -> Bool) -> [Int32]? {
        if s == g { return [Int32(s)] }
        let n = cols * rows
        var gScore = [Double](repeating: .infinity, count: n)
        var parent = [Int32](repeating: -1, count: n)
        var closed = [Bool](repeating: false, count: n)
        var heap = NavHeap()
        let gc = g % cols, gr = g / cols
        let diag = 2.0.squareRoot()
        func heuristic(_ i: Int) -> Double {
            let dx = Double(abs(i % cols - gc)), dy = Double(abs(i / cols - gr))
            return (dx + dy) + (diag - 2) * min(dx, dy)
        }
        gScore[s] = 0
        heap.push(NavHeap.Node(f: heuristic(s), h: heuristic(s), index: Int32(s)))
        while let node = heap.pop() {
            let i = Int(node.index)
            if closed[i] { continue }
            if i == g { break }
            closed[i] = true
            let c = i % cols, row = i / cols
            let gi = gScore[i]
            for (dc, dr) in NavGrid.neighborOffsets {
                let nc = c + dc, nr = row + dr
                guard nc >= 0, nc < cols, nr >= 0, nr < rows else { continue }
                let j = nr * cols + nc
                guard !closed[j], passable(j) else { continue }
                let isDiag = dc != 0 && dr != 0
                if isDiag && cornerCheck {
                    guard passable(row * cols + nc), passable(nr * cols + c) else { continue }
                }
                let ng = gi + (isDiag ? diag : 1)
                if ng < gScore[j] - 1e-12 {
                    gScore[j] = ng
                    parent[j] = Int32(i)
                    let h = heuristic(j)
                    heap.push(NavHeap.Node(f: ng + h, h: h, index: Int32(j)))
                }
            }
        }
        guard parent[g] >= 0 else { return nil }
        var out: [Int32] = [Int32(g)]
        var cur = g
        while cur != s {
            cur = Int(parent[cur])
            out.append(Int32(cur))
        }
        out.reverse()
        return out
    }

    /// 視線による経路の平滑化（紐引き）。pts[0] は始点（出力に含めない）。
    func smooth(_ pts: [Vec2], radius r: Double) -> [Vec2] {
        guard pts.count > 2 else { return Array(pts.dropFirst()) }
        var out: [Vec2] = []
        var anchor = pts[0]
        var k = 1
        while k < pts.count {
            var j = k
            while j + 1 < pts.count && segmentClear(anchor, pts[j + 1], radius: r) { j += 1 }
            out.append(pts[j])
            anchor = pts[j]
            k = j + 1
        }
        return out
    }

    // MARK: - 幾何

    /// 線分が半径 r で障害物・マップ端に触れないか。
    func segmentClear(_ a: Vec2, _ b: Vec2, radius r: Double) -> Bool {
        let lo = r, hi = map.size - r
        guard a.x >= lo, a.y >= lo, a.x <= hi, a.y <= hi, b.x >= lo, b.y >= lo, b.x <= hi, b.y <= hi else { return false }
        let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
        for k in obstacleBounds.indices {
            let bb = obstacleBounds[k]
            if maxX < bb.minX - r || minX > bb.maxX + r || maxY < bb.minY - r || minY > bb.maxY + r { continue }
            switch obstacles[k] {
            case .circle(let c, let radius):
                let rr = radius + r
                if distancePointToSegment(c, a, b) <= rr { return false }
            case .rect(let rect):
                // 角を半径 r で丸めた膨張 = 横に膨らませた矩形 ∪ 縦に膨らませた矩形 ∪ 角の 4 円
                if MapDefinition.segmentIntersectsRect(a, b, Rect2(minX: rect.minX - r, minY: rect.minY, maxX: rect.maxX + r, maxY: rect.maxY))
                    || MapDefinition.segmentIntersectsRect(a, b, Rect2(minX: rect.minX, minY: rect.minY - r, maxX: rect.maxX, maxY: rect.maxY + r)) {
                    return false
                }
                for c in NavGrid.corners(rect) where distancePointToSegment(c, a, b) <= r { return false }
            case .polygon(let v):
                // 端点が内部・辺と交わる・辺から r 以内（各辺のカプセル）
                if Obstacle.polygonTouchesSegment(v, a, b, radius: r) { return false }
            }
        }
        return true
    }

    /// 最も深く食い込んでいる障害物（膨張込み）。
    func mostPenetrated(at p: Vec2, radius r: Double) -> Int? {
        var best: Int?
        var bestD = Double.infinity
        let lim = r + NavGrid.boundsSlack
        for (k, o) in obstacles.enumerated() {
            // 外接矩形（r 膨張）の外は食い込んでいない（多角形の距離は重いので先に省く）
            let b = obstacleBounds[k]
            if p.x < b.minX - lim || p.x > b.maxX + lim || p.y < b.minY - lim || p.y > b.maxY + lim { continue }
            let d = o.signedDistance(to: p) - r
            if d <= 0 && d < bestD { bestD = d; best = k }
        }
        return best
    }

    /// a + delta·t（t ∈ [0,1]）が膨張障害物へ最初に入る t。a は障害物の外側であること。
    static func entryTime(_ o: Obstacle, from a: Vec2, delta d: Vec2, radius r: Double) -> Double? {
        switch o {
        case .circle(let c, let radius):
            return circleEntryTime(c, radius + r, from: a, delta: d)
        case .rect(let rect):
            // 角を半径 r で丸めた膨張 = 横に膨らませた矩形 ∪ 縦に膨らませた矩形 ∪ 角の 4 円（a はどれの外側でもある）
            var best: Double?
            func take(_ t: Double?) { if let t, t < (best ?? .infinity) { best = t } }
            take(rectEntryTime(Rect2(minX: rect.minX - r, minY: rect.minY, maxX: rect.maxX + r, maxY: rect.maxY), from: a, delta: d))
            take(rectEntryTime(Rect2(minX: rect.minX, minY: rect.minY - r, maxX: rect.maxX, maxY: rect.maxY + r), from: a, delta: d))
            if r > 0 { for c in corners(rect) { take(circleEntryTime(c, r, from: a, delta: d)) } }
            return best
        case .polygon(let v):
            // 膨張した多角形 = 多角形 ∪ 各辺のカプセル。a は外側なので、境界から r 以内へ最初に入る時刻
            // = 各辺のカプセルへ入る時刻の最小（r = 0 なら辺との交点）
            let lo = Vec2(min(a.x, a.x + d.x) - r, min(a.y, a.y + d.y) - r)
            let hi = Vec2(max(a.x, a.x + d.x) + r, max(a.y, a.y + d.y) + r)
            var best: Double?
            let n = v.count
            for i in 0..<n {
                let p0 = v[i], p1 = v[i + 1 == n ? 0 : i + 1]
                // 移動の範囲（r 膨張）と外接矩形が離れている辺は測らない
                if max(p0.x, p1.x) < lo.x || min(p0.x, p1.x) > hi.x || max(p0.y, p1.y) < lo.y || min(p0.y, p1.y) > hi.y { continue }
                if let t = edgeEntryTime(p0, p1, r, from: a, delta: d), t < (best ?? .infinity) { best = t }
            }
            return best
        }
    }

    /// 辺 p0–p1 から r 以内（カプセル: 辺に沿った幅 2r の帯 + 端の円）へ a + delta·t が最初に入る t（r = 0 なら辺との交点）。
    /// 終点 p1 の円は次の辺の始点の円と同じなので、始点 p0 の円だけを測る。
    static func edgeEntryTime(_ p0: Vec2, _ p1: Vec2, _ r: Double, from a: Vec2, delta d: Vec2) -> Double? {
        let e = p1 - p0
        let len = e.length
        guard len > 1e-9 else { return r > 0 ? circleEntryTime(p0, r, from: a, delta: d) : nil }
        // 帯は辺の向き u・法線 n の座標で [0, len] × [−r, r] の矩形（r = 0 なら厚さ 0 = 辺そのもの）
        let u = e / len, n = u.perpendicular
        let la = Vec2((a - p0).dot(u), (a - p0).dot(n)), ld = Vec2(d.dot(u), d.dot(n))
        var best = rectEntryTime(Rect2(minX: 0, minY: -r, maxX: len, maxY: r), from: la, delta: ld)
        if r > 0, let t = circleEntryTime(p0, r, from: a, delta: d), t < (best ?? .infinity) { best = t }
        return best
    }

    static func corners(_ r: Rect2) -> [Vec2] {
        [Vec2(r.minX, r.minY), Vec2(r.maxX, r.minY), Vec2(r.minX, r.maxY), Vec2(r.maxX, r.maxY)]
    }

    static func circleEntryTime(_ c: Vec2, _ rr: Double, from a: Vec2, delta d: Vec2) -> Double? {
        let f = a - c
        let qa = d.dot(d)
        let qb = 2 * f.dot(d)
        let qc = f.dot(f) - rr * rr
        let disc = qb * qb - 4 * qa * qc
        guard qa > 1e-12, disc >= 0 else { return nil }
        let t = (-qb - disc.squareRoot()) / (2 * qa)
        return (t >= 0 && t <= 1) ? t : nil
    }

    static func rectEntryTime(_ e: Rect2, from a: Vec2, delta d: Vec2) -> Double? {
        var t0 = 0.0, t1 = 1.0
        let p = [-d.x, d.x, -d.y, d.y]
        let q = [a.x - e.minX, e.maxX - a.x, a.y - e.minY, e.maxY - a.y]
        for k in 0..<4 {
            if abs(p[k]) < 1e-12 {
                if q[k] < 0 { return nil }
            } else {
                let t = q[k] / p[k]
                if p[k] < 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
                if t0 > t1 { return nil }
            }
        }
        return t0
    }
}

// MARK: - 補助型

/// A* 用の二分ヒープ（(f, h, index) 昇順）。
struct NavHeap {
    struct Node {
        var f: Double
        var h: Double
        var index: Int32

        @inline(__always) static func less(_ a: Node, _ b: Node) -> Bool {
            if a.f != b.f { return a.f < b.f }
            if a.h != b.h { return a.h < b.h }
            return a.index < b.index
        }
    }

    private var nodes: [Node] = []

    init() { nodes.reserveCapacity(1024) }

    mutating func push(_ n: Node) {
        nodes.append(n)
        var i = nodes.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            guard Node.less(nodes[i], nodes[p]) else { break }
            nodes.swapAt(i, p)
            i = p
        }
    }

    mutating func pop() -> Node? {
        guard let first = nodes.first else { return nil }
        let last = nodes.removeLast()
        if !nodes.isEmpty {
            nodes[0] = last
            var i = 0
            let n = nodes.count
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < n && Node.less(nodes[l], nodes[m]) { m = l }
                if r < n && Node.less(nodes[r], nodes[m]) { m = r }
                if m == i { break }
                nodes.swapAt(i, m)
                i = m
            }
        }
        return first
    }
}

/// 格子経路の固定サイズ・直接写像キャッシュ（LRU なし）。
/// 値は (始点格子, 終点格子, 半径) だけで決まる純関数の結果なので、キャッシュの有無で結果は変わらない（決定論を保つ）。
final class PathCache: @unchecked Sendable {
    struct Key: Hashable {
        var start: Int32
        var goal: Int32
        var radiusBits: UInt64

        /// 固定の混合関数（Swift の Hasher はプロセス毎に種が変わるため使わない）。
        var slotHash: UInt64 {
            var z = UInt64(UInt32(bitPattern: start)) &* 0x9E37_79B9_7F4A_7C15
            z ^= UInt64(UInt32(bitPattern: goal)) &* 0xC2B2_AE3D_27D4_EB4F
            z ^= radiusBits &* 0x1656_67B1_9E37_79F9
            z ^= z >> 29
            return z
        }
    }

    static let capacity = 512
    private var keys: [Key?]
    private var values: [[Int32]]
    private let lock = NSLock()

    init() {
        keys = [Key?](repeating: nil, count: PathCache.capacity)
        values = [[Int32]](repeating: [], count: PathCache.capacity)
    }

    /// ヒットすれば格子列（到達不能は空配列）を返す。
    func lookup(_ key: Key) -> [Int32]? {
        let slot = Int(key.slotHash % UInt64(PathCache.capacity))
        lock.lock()
        defer { lock.unlock() }
        return keys[slot] == key ? values[slot] : nil
    }

    func store(_ key: Key, _ value: [Int32]) {
        let slot = Int(key.slotHash % UInt64(PathCache.capacity))
        lock.lock()
        keys[slot] = key
        values[slot] = value
        lock.unlock()
    }
}
