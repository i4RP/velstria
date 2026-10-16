import Foundation

/// 草むらの細かい格子（2026-10-16〜）。地図座標の (0, 0) を原点に、一辺 `cell` ユニットのセルが cols × rows 並ぶ
/// （行 0 が y の小さい側）。値 0 = 草むらなし、k + 1 = 草むら k（`MapDefinition.brushes` の添字）。
/// 草むらを矩形で近似せず、MLBB のミニマップの形をそのまま持つ（`tools/map_proto/terrain_grid.mjs`）。
public struct BushMask: Sendable {
    /// セルの一辺（ユニット）。
    public private(set) var cell: Double
    public let cols: Int
    public let rows: Int
    /// 行優先（index = row * cols + col）。
    public private(set) var cells: [UInt8]
    /// 草むらごとのセル数と外接範囲（セルの番号。縮尺に依らない）。index = 草むらの番号。
    private var stats: [Stat]

    struct Stat: Hashable, Sendable {
        var count = 0
        var minCol = Int.max, minRow = Int.max, maxCol = Int.min, maxRow = Int.min
    }

    public init(cell: Double, cols: Int, rows: Int, cells: [UInt8]) {
        precondition(cells.count == cols * rows, "BushMask: セルの数が cols × rows と合わない")
        self.cell = cell
        self.cols = cols
        self.rows = rows
        self.cells = cells
        stats = BushMask.makeStats(cells, cols: cols)
    }

    /// [値 1 バイト][長さ LEB128] の連なりを base64 にしたもの（改行・空白は読み飛ばす）から。
    public init?(cell: Double, cols: Int, rows: Int, runLengthBase64 s: String) {
        guard let data = Data(base64Encoded: s, options: .ignoreUnknownCharacters) else { return nil }
        let bytes = [UInt8](data)
        var out: [UInt8] = []
        out.reserveCapacity(cols * rows)
        var i = 0
        while i < bytes.count {
            let v = bytes[i]
            i += 1
            var n = 0, shift = 0
            while true {
                guard i < bytes.count, shift < 35 else { return nil }
                let b = bytes[i]
                i += 1
                n |= Int(b & 0x7f) << shift
                if b & 0x80 == 0 { break }
                shift += 7
            }
            guard out.count + n <= cols * rows else { return nil }
            out.append(contentsOf: repeatElement(v, count: n))
        }
        guard out.count == cols * rows else { return nil }
        self.init(cell: cell, cols: cols, rows: rows, cells: out)
    }

    /// `init(cell:cols:rows:runLengthBase64:)` で読める文字列。
    public var runLengthBase64: String {
        var bytes: [UInt8] = []
        var q = 0
        while q < cells.count {
            let v = cells[q]
            var n = 0
            while q < cells.count && cells[q] == v { q += 1; n += 1 }
            bytes.append(v)
            while n >= 0x80 { bytes.append(UInt8(n & 0x7f) | 0x80); n >>= 7 }
            bytes.append(UInt8(n))
        }
        return Data(bytes).base64EncodedString()
    }

    private static func makeStats(_ cells: [UInt8], cols: Int) -> [Stat] {
        var out: [Stat] = Array(repeating: Stat(), count: Int(cells.max() ?? 0))
        for (q, v) in cells.enumerated() where v != 0 {
            let r = q / cols, c = q % cols
            let k = Int(v) - 1
            out[k].count += 1
            out[k].minCol = min(out[k].minCol, c)
            out[k].maxCol = max(out[k].maxCol, c)
            out[k].minRow = min(out[k].minRow, r)
            out[k].maxRow = max(out[k].maxRow, r)
        }
        return out
    }

    // MARK: 問い合わせ

    /// 草むらの数（いちばん大きい番号 + 1）。
    public var bushCount: Int { stats.count }

    /// p を含むセルの草むらの番号。
    public func bush(at p: Vec2) -> Int? {
        guard let q = index(at: p) else { return nil }
        let v = cells[q]
        return v == 0 ? nil : Int(v) - 1
    }

    /// p を含むセルの番号（地図の外・NaN は nil）。
    public func index(at p: Vec2) -> Int? {
        let fx = p.x / cell, fy = p.y / cell
        guard fx >= 0, fy >= 0, fx < Double(cols), fy < Double(rows) else { return nil }
        return Int(fy) * cols + Int(fx)
    }

    /// セル（列 c・行 r）の中心。
    public func center(col c: Int, row r: Int) -> Vec2 {
        Vec2((Double(c) + 0.5) * cell, (Double(r) + 0.5) * cell)
    }

    /// 草むら k のセル数。
    public func cellCount(of k: Int) -> Int { stats.indices.contains(k) ? stats[k].count : 0 }

    /// 草むら k の外接矩形（セルの縁まで。セルが無ければ nil）。
    public func bounds(of k: Int) -> Rect2? {
        guard stats.indices.contains(k), stats[k].count > 0 else { return nil }
        let s = stats[k]
        return Rect2(minX: Double(s.minCol) * cell, minY: Double(s.minRow) * cell,
                     maxX: Double(s.maxCol + 1) * cell, maxY: Double(s.maxRow + 1) * cell)
    }

    /// 草むら k の中の点: 外接矩形の中心に最も近いセルの中心（細い三日月形でも必ず草むらの中）。
    public func interiorPoint(of k: Int) -> Vec2? {
        guard stats.indices.contains(k), stats[k].count > 0 else { return nil }
        let s = stats[k]
        let mc = Double(s.minCol + s.maxCol) / 2, mr = Double(s.minRow + s.maxRow) / 2
        var best: (d: Double, c: Int, r: Int)?
        for r in s.minRow...s.maxRow {
            for c in s.minCol...s.maxCol where cells[r * cols + c] == UInt8(k + 1) {
                let d = (Double(c) - mc) * (Double(c) - mc) + (Double(r) - mr) * (Double(r) - mr)
                if best == nil || d < best!.d { best = (d, c, r) }
            }
        }
        return best.map { center(col: $0.c, row: $0.r) }
    }

    /// 草むら k を覆う重ならない矩形（行ごとのセルの連なり）。step > 1 は step × step セルのまとまりにして粗くする
    /// （まとまりの中心のセルで判定。描画用）。
    public func rects(of k: Int, step: Int = 1) -> [Rect2] {
        guard stats.indices.contains(k), stats[k].count > 0 else { return [] }
        let s = stats[k], st = max(1, step), v = UInt8(k + 1)
        var out: [Rect2] = []
        var r0 = s.minRow
        while r0 <= s.maxRow {
            let rs = min(rows - 1, r0 + st / 2)
            var c0 = s.minCol
            var runStart: Int?
            while c0 <= s.maxCol + st {
                let cs = min(cols - 1, c0 + st / 2)
                let inside = c0 <= s.maxCol && cells[rs * cols + cs] == v
                if inside, runStart == nil { runStart = c0 }
                if !inside, let a = runStart {
                    out.append(Rect2(minX: Double(a) * cell, minY: Double(r0) * cell,
                                     maxX: Double(min(c0, s.maxCol + 1)) * cell, maxY: Double(min(r0 + st, s.maxRow + 1)) * cell))
                    runStart = nil
                }
                c0 += st
            }
            r0 += st
        }
        return out
    }

    /// 中心 c・半径 radius の円と重なる草むらの番号（昇順）。
    public func bushes(overlappingCircle c: Vec2, radius: Double) -> [Int] {
        var out: [Int] = []
        guard radius.isFinite, radius >= 0, c.x.isFinite, c.y.isFinite else { return out }
        func cellOf(_ v: Double, _ n: Int) -> Int { Int(min(max(v / cell, -1), Double(n)).rounded(.down)) }
        let lo0 = cellOf(c.x - radius, cols), hi0 = cellOf(c.x + radius, cols)
        let lo1 = cellOf(c.y - radius, rows), hi1 = cellOf(c.y + radius, rows)
        for (k, s) in stats.enumerated() where s.count > 0 {
            let c0 = max(lo0, s.minCol, 0), c1 = min(hi0, s.maxCol, cols - 1)
            let r0 = max(lo1, s.minRow, 0), r1 = min(hi1, s.maxRow, rows - 1)
            guard c0 <= c1, r0 <= r1 else { continue }
            let v = UInt8(k + 1)
            search: for r in r0...r1 {
                for col in c0...c1 where cells[r * cols + col] == v {
                    // セルの正方形で最も円の中心に近い点
                    let qx = min(max(c.x, Double(col) * cell), Double(col + 1) * cell)
                    let qy = min(max(c.y, Double(r) * cell), Double(r + 1) * cell)
                    if (qx - c.x) * (qx - c.x) + (qy - c.y) * (qy - c.y) <= radius * radius {
                        out.append(k)
                        break search
                    }
                }
            }
        }
        return out
    }

    // MARK: 作り替え

    /// 地図と同じ倍率で縮めた格子（セルの並びはそのまま）。
    public func scaled(by k: Double) -> BushMask {
        var m = self
        m.cell *= k
        return m
    }

    /// ミッドの対向する草むらは三本の直線をつないだ細長い Z。描画・ミニマップ・隠蔽で同じ格子を使う。
    func withMidZBrushes() -> BushMask {
        let extent = Double(cols) * cell
        let scale = extent / 9720
        let path = [Vec2(4900, 4250), Vec2(5100, 4050), Vec2(5800, 4650), Vec2(6000, 4450)].map { $0 * scale }
        let halfWidth = 140.0 * scale
        func inside(_ p: Vec2) -> Bool {
            for (a, b) in zip(path, path.dropFirst()) {
                let edge = b - a
                let length = edge.length
                let dir = edge / length
                let q = p - a
                let along = q.x * dir.x + q.y * dir.y
                let across = abs(q.x * dir.y - q.y * dir.x)
                if along >= -halfWidth && along <= length + halfWidth && across <= halfWidth { return true }
            }
            return false
        }
        var out = cells.map { ($0 == 14 || $0 == 38) ? UInt8(0) : $0 }
        // 一方だけをラスタライズし、セル番号で反転して完全な点対称にする。
        for row in 0..<rows {
            for col in 0..<cols {
                let p = center(col: col, row: row)
                guard p.x >= 4300 * scale, p.x <= 6400 * scale,
                      p.y >= 3600 * scale, p.y <= 4900 * scale, inside(p) else { continue }
                out[row * cols + col] = 14
                out[(rows - 1 - row) * cols + cols - 1 - col] = 38
            }
        }
        return BushMask(cell: cell, cols: cols, rows: rows, cells: out)
    }

    /// 中心が壁の中（または壁から margin 以内）に入るセルを草むらから外す（草むらと壁を重ねない）。
    public func carved(by obstacles: [Obstacle], margin: Double = 0) -> BushMask {
        let boxes = obstacles.map { $0.bounds.expanded(by: margin + cell) }
        var out = cells
        var changed = false
        for (q, v) in cells.enumerated() where v != 0 {
            let p = center(col: q % cols, row: q / cols)
            for (i, o) in obstacles.enumerated() where boxes[i].contains(p) && o.contains(p, inflatedBy: margin) {
                out[q] = 0
                changed = true
                break
            }
        }
        return changed ? BushMask(cell: cell, cols: cols, rows: rows, cells: out) : self
    }

    /// 各セルの中心から最も近い草むらのセルの中心までの距離（セル単位。草むらの中は 0）。
    /// 2 パスの面取り距離（直交 1・斜め √2。真の距離との差は 8% 以内）。描画の配置の判定用。
    public func distanceField() -> [Float] {
        let inf = Float.greatestFiniteMagnitude / 4
        var d = cells.map { $0 == 0 ? inf : 0 }
        let s2 = Float(2).squareRoot()
        for r in 0..<rows {
            for c in 0..<cols {
                let q = r * cols + c
                var v = d[q]
                if c > 0 { v = min(v, d[q - 1] + 1) }
                if r > 0 {
                    v = min(v, d[q - cols] + 1)
                    if c > 0 { v = min(v, d[q - cols - 1] + s2) }
                    if c < cols - 1 { v = min(v, d[q - cols + 1] + s2) }
                }
                d[q] = v
            }
        }
        for r in stride(from: rows - 1, through: 0, by: -1) {
            for c in stride(from: cols - 1, through: 0, by: -1) {
                let q = r * cols + c
                var v = d[q]
                if c < cols - 1 { v = min(v, d[q + 1] + 1) }
                if r < rows - 1 {
                    v = min(v, d[q + cols] + 1)
                    if c < cols - 1 { v = min(v, d[q + cols + 1] + s2) }
                    if c > 0 { v = min(v, d[q + cols - 1] + s2) }
                }
                d[q] = v
            }
        }
        return d
    }
}

// 比較・ハッシュ・保存: 36 万セルを毎回なめないよう、ハッシュは形の大きさだけ、保存は連長圧縮の文字列にする。
extension BushMask: Hashable {
    public static func == (a: BushMask, b: BushMask) -> Bool {
        a.cell == b.cell && a.cols == b.cols && a.rows == b.rows && a.cells == b.cells
    }

    public func hash(into h: inout Hasher) {
        h.combine(cell)
        h.combine(cols)
        h.combine(rows)
        h.combine(stats.count)
    }
}

extension BushMask: Codable {
    private enum CodingKeys: String, CodingKey { case cell, cols, rows, rle }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cell = try c.decode(Double.self, forKey: .cell)
        let cols = try c.decode(Int.self, forKey: .cols), rows = try c.decode(Int.self, forKey: .rows)
        guard let m = BushMask(cell: cell, cols: cols, rows: rows, runLengthBase64: try c.decode(String.self, forKey: .rle)) else {
            throw DecodingError.dataCorruptedError(forKey: .rle, in: c, debugDescription: "BushMask の連長圧縮が壊れている")
        }
        self = m
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cell, forKey: .cell)
        try c.encode(cols, forKey: .cols)
        try c.encode(rows, forKey: .rows)
        try c.encode(runLengthBase64, forKey: .rle)
    }
}

// MARK: - 地図の草むら（矩形の草むらと細かい格子の草むらを同じ問い合わせで扱う）

extension MapDefinition {
    /// 草むら k（`brushes` の添字）が点 p を含むか。
    public func brush(_ k: Int, contains p: Vec2) -> Bool {
        guard brushes.indices.contains(k) else { return false }
        if let m = bushMask { return m.bush(at: p) == k }
        return brushes[k].rect.contains(p)
    }

    /// 草むら k の面積（ユニット²）。
    public func brushArea(_ k: Int) -> Double {
        guard brushes.indices.contains(k) else { return 0 }
        if let m = bushMask { return Double(m.cellCount(of: k)) * m.cell * m.cell }
        return brushes[k].rect.width * brushes[k].rect.height
    }

    /// 草むら k を覆う重ならない矩形（描画用。格子の草むらは行ごとのセルの連なり、step セルずつまとめて粗くできる）。
    public func brushRects(_ k: Int, step: Int = 1) -> [Rect2] {
        guard brushes.indices.contains(k) else { return [] }
        if let m = bushMask { return m.rects(of: k, step: step) }
        return [brushes[k].rect]
    }

    /// 草むら k の中の点（矩形の草むらは中心）。
    public func brushInteriorPoint(_ k: Int) -> Vec2 {
        if let m = bushMask, let p = m.interiorPoint(of: k) { return p }
        return brushes[k].rect.center
    }

    /// 円と重なる草むら（`brushes` の添字、昇順）。
    public func brushIndices(overlappingCircle c: Vec2, radius: Double) -> [Int] {
        if let m = bushMask { return m.bushes(overlappingCircle: c, radius: radius).filter { $0 < brushes.count } }
        return brushes.indices.filter { brushes[$0].rect.closestPoint(to: c).distanceSquared(to: c) <= radius * radius }
    }

    /// 細かい格子の草むら（壁に重なるセルを除いた後）から、草むらごとの外接矩形を `brushes` にする。
    static func brushAreas(of mask: BushMask) -> [BrushArea] {
        (0..<mask.bushCount).map { k in
            // 壁に削られて消えた草むらも番号を保つため残す（セルが無いので判定・描画には出ない）
            BrushArea(id: k, rect: mask.bounds(of: k) ?? Rect2(minX: 0, minY: 0, maxX: 0, maxY: 0), bush: k)
        }
    }

    /// MLBB の草むら（`BushMask.sanctum`）を地図の倍率 k で縮め、壁に重なるセルを除いて入れる。
    mutating func applySanctumBushes(scale k: Double) {
        let mask = BushMask.sanctum.scaled(by: k).withMidZBrushes().carved(by: obstacles)
        bushMask = mask
        brushes = MapDefinition.brushAreas(of: mask)
    }
}
