import Foundation

// 担当: core-world（最小実装: 全員可視。DESIGN §9 のチーム視界・草むら・ステルスを実装すること）

/// チーム視界格子。cells[row * cols + col] = その格子を見ているチームのビット集合（Team.visionBit）。
public struct VisionState: Codable, Hashable, Sendable {
    public var cols = 0
    public var rows = 0
    public var cells: [UInt8] = []

    public init() {}

    /// 格子座標から team がその地点を見ているか。
    public func isLit(_ p: Vec2, for team: Team) -> Bool {
        guard cols > 0 else { return true }
        let c = min(cols - 1, max(0, Int(p.x / Balance.visionCellSize)))
        let r = min(rows - 1, max(0, Int(p.y / Balance.visionCellSize)))
        return cells[r * cols + c] & team.visionBit != 0
    }
}

public enum VisionSystem {
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        for i in s.units.indices {
            s.units[i].visibleMask = Team.blue.visionBit | Team.red.visionBit
            s.units[i].brushIndex = ctx.map.brushIndex(at: s.units[i].pos)
        }
    }
}
