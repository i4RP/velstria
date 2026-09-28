import Foundation

// 担当: core-world。現在は障害物なし前提の最小実装（API は変更しないこと）。

/// 障害物を焼き込んだ格子と経路探索。
public final class NavGrid: @unchecked Sendable {
    public let cellSize: Double
    public let cols: Int
    public let rows: Int
    public let map: MapDefinition

    public init(map: MapDefinition, cellSize: Double = 100) {
        self.map = map
        self.cellSize = cellSize
        self.cols = Int((map.size / cellSize).rounded(.up))
        self.rows = cols
    }

    /// 点が歩行可能か（マップ内かつ障害物外）。
    public func isWalkable(_ p: Vec2, radius: Double = 0) -> Bool {
        guard p.x >= radius, p.y >= radius, p.x <= map.size - radius, p.y <= map.size - radius else { return false }
        return !map.obstacles.contains { $0.contains(p, inflatedBy: radius) }
    }

    /// from → to の経路（先頭は最初の経由点、末尾は to 付近の歩行可能点）。到達不能なら空。
    public func findPath(from: Vec2, to: Vec2, radius: Double = 0) -> [Vec2] {
        [clampToMap(to)]
    }

    /// from から to へ直進し、障害物/マップ端の手前で止まる点（ブリンク・突進用）。
    public func raycast(from: Vec2, to: Vec2, radius: Double = 0) -> Vec2 {
        clampToMap(to)
    }

    /// 1 tick 分の移動を障害物に沿って解決（壁ずり）。
    public func resolveMove(from: Vec2, to: Vec2, radius: Double) -> Vec2 {
        clampToMap(to)
    }

    /// 最寄りの歩行可能点。
    public func nearestWalkable(_ p: Vec2, radius: Double = 0) -> Vec2 {
        clampToMap(p)
    }

    func clampToMap(_ p: Vec2) -> Vec2 {
        Vec2(max(1, min(map.size - 1, p.x)), max(1, min(map.size - 1, p.y)))
    }
}
