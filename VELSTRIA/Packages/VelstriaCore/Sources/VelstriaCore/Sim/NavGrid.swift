import Foundation

// 担当: core-world。
// 100 ユニット格子（120×120）に障害物を焼き込む。各格子中心に「最寄りの障害物・マップ端までの距離」
// （クリアランス）を保持し、半径 r の単位は clearance > r の格子だけを通る。
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

    public init(map: MapDefinition, cellSize: Double = 100) {
        self.map = map
        self.cellSize = cellSize
        self.cols = Int((map.size / cellSize).rounded(.up))
        self.rows = cols
        self.obstacles = map.obstacles
        self.obstacleBounds = map.obstacles.map(\.bounds)

        var cl = [Double](repeating: 0, count: cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let p = Vec2((Double(c) + 0.5) * cellSize, (Double(r) + 0.5) * cellSize)
                var d = min(min(p.x, p.y), min(map.size - p.x, map.size - p.y))
                for o in map.obstacles { d = min(d, o.signedDistance(to: p)) }
                cl[r * cols + c] = d
            }
        }
        self.clearance = cl
        self.bakedComponents = NavGrid.labelComponents(clearance: cl, cols: cols, rows: rows,
                                                        radius: NavGrid.bakedRadius)
        self.cache = PathCache()
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
        var d = min(min(p.x, p.y), min(map.size - p.x, map.size - p.y))
        for o in obstacles { d = min(d, o.signedDistance(to: p)) }
        return d
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

    /// 1 tick 分の移動を障害物に沿って解決（壁ずり）。
    public func resolveMove(from: Vec2, to: Vec2, radius: Double) -> Vec2 {
        let r = max(0, radius)
        let target = clampToMap(to, radius: r)
        let move = target - from
        if move.lengthSquared < 1e-12 { return from }
        // 長い移動はすり抜け防止のため直進判定
        if move.length > cellSize * 0.5 {
            return raycast(from: from, to: target, radius: r)
        }
        if isWalkable(target, radius: r) { return target }

        let fromWalkable = isWalkable(from, radius: r)
        if fromWalkable {
            // 1) 接触面に沿った滑り（法線成分を除去）
            if let k = mostPenetrated(at: target, radius: r) {
                let n = obstacles[k].outwardNormal(at: from)
                let into = move.dot(n)
                if into < 0 {
                    let slide = move - n * into
                    let cand = from + slide
                    if slide.lengthSquared > 1e-12, isWalkable(cand, radius: r) { return cand }
                }
            }
            // 2) 軸ごとの射影（進行方向への寄与が大きい方を優先、同値は x を優先）
            let cx = Vec2(target.x, from.y)
            let cy = Vec2(from.x, target.y)
            let okX = abs(move.x) > 1e-9 && isWalkable(cx, radius: r)
            let okY = abs(move.y) > 1e-9 && isWalkable(cy, radius: r)
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
        for o in obstacles where o.contains(q, inflatedBy: r) {
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

    /// 格子 A*（8 近傍・角抜け禁止・octile ヒューリスティック）。同点は (f, h, 添字) の昇順で決定論的に選ぶ。
    func astar(from s: Int, to g: Int, radius r: Double) -> [Int32]? {
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
                guard !closed[j], clearance[j] > r else { continue }
                let isDiag = dc != 0 && dr != 0
                if isDiag {
                    guard clearance[row * cols + nc] > r, clearance[nr * cols + c] > r else { continue }
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
                if MapDefinition.segmentIntersectsRect(a, b, rect.expanded(by: r)) { return false }
            }
        }
        return true
    }

    /// 最も深く食い込んでいる障害物（膨張込み）。
    func mostPenetrated(at p: Vec2, radius r: Double) -> Int? {
        var best: Int?
        var bestD = Double.infinity
        for (k, o) in obstacles.enumerated() {
            let d = o.signedDistance(to: p) - r
            if d <= 0 && d < bestD { bestD = d; best = k }
        }
        return best
    }

    /// a + delta·t（t ∈ [0,1]）が膨張障害物へ最初に入る t。a は障害物の外側であること。
    static func entryTime(_ o: Obstacle, from a: Vec2, delta d: Vec2, radius r: Double) -> Double? {
        switch o {
        case .circle(let c, let radius):
            let rr = radius + r
            let f = a - c
            let qa = d.dot(d)
            let qb = 2 * f.dot(d)
            let qc = f.dot(f) - rr * rr
            let disc = qb * qb - 4 * qa * qc
            guard qa > 1e-12, disc >= 0 else { return nil }
            let t = (-qb - disc.squareRoot()) / (2 * qa)
            return (t >= 0 && t <= 1) ? t : nil
        case .rect(let rect):
            let e = rect.expanded(by: r)
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
