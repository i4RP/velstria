import Foundation

// 担当: core-combat
// tick 内で使い捨てる一様格子（空間ハッシュ）。Dictionary を使わず、セル毎の連結リストを配列で持つため
// 列挙順は「セル行 → セル列 → 登録添字の昇順」で常に決定論的。

struct CombatSpatialGrid {
    /// 1 辺あたりの最大セル数（点群が広い場合はセルを拡大する）。
    static let maxCellsPerAxis = 256

    let cellSize: Double
    let originX: Double
    let originY: Double
    let cols: Int
    let rows: Int
    /// 登録した点（添字 = 要素番号）。
    let positions: [Vec2]
    /// セル毎の先頭要素（-1 = 空）。
    private var head: [Int32]
    /// 同じセル内の次要素（-1 = 末尾）。
    private var next: [Int32]

    init(positions: [Vec2], cellSize requested: Double) {
        self.positions = positions
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for p in positions {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        if positions.isEmpty { minX = 0; minY = 0; maxX = 0; maxY = 0 }
        let extent = max(maxX - minX, maxY - minY)
        let size = max(requested, 1, extent / Double(Self.maxCellsPerAxis - 1))
        cellSize = size
        originX = minX
        originY = minY
        cols = min(Self.maxCellsPerAxis, Int((maxX - minX) / size) + 1)
        rows = min(Self.maxCellsPerAxis, Int((maxY - minY) / size) + 1)
        head = [Int32](repeating: -1, count: cols * rows)
        next = [Int32](repeating: -1, count: positions.count)
        // 逆順に先頭挿入するとセル内の並びが添字昇順になる
        var k = positions.count - 1
        while k >= 0 {
            let c = cellIndex(positions[k])
            next[k] = head[c]
            head[c] = Int32(k)
            k -= 1
        }
    }

    private func column(_ x: Double) -> Int {
        min(cols - 1, max(0, Int(((x - originX) / cellSize).rounded(.down))))
    }

    private func row(_ y: Double) -> Int {
        min(rows - 1, max(0, Int(((y - originY) / cellSize).rounded(.down))))
    }

    private func cellIndex(_ p: Vec2) -> Int { row(p.y) * cols + column(p.x) }

    /// p から中心間距離 radius 以内の要素番号を out に追加する（決定論的な順序）。
    func query(_ p: Vec2, radius: Double, into out: inout [Int]) {
        guard !positions.isEmpty else { return }
        let c0 = column(p.x - radius), c1 = column(p.x + radius)
        let r0 = row(p.y - radius), r1 = row(p.y + radius)
        let r2 = radius * radius
        for r in r0...r1 {
            for c in c0...c1 {
                var k = head[r * cols + c]
                while k >= 0 {
                    let e = Int(k)
                    if positions[e].distanceSquared(to: p) <= r2 { out.append(e) }
                    k = next[e]
                }
            }
        }
    }
}
