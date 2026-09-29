import Foundation

// 担当: core-world。チーム視界（DESIGN §9）。10Hz（Simulation が 3 tick 毎に呼ぶ）。
// 1) 各チームの視界円（ヒーロー 1200 / ミニオン 800 / タワー・Core 1100 / 泉 1500）を 200 単位格子へ焼く。
// 2) ユニット毎に各チームから見えるかを判定し visibleMask に書く:
//    味方は常に可視。敵・中立は「格子が照らされている」かつ「草むら外、または同じ草むらに観測者が居る/観測者が 300 以内」
//    かつ「ステルスでない、または観測者が 250 以内/自軍タワーの真視界 750 内/自軍の泉内」。.revealed は両チームに可視。
//    構造物（タワー・Core）は地形として常に両チームに可視（破壊後も）。

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
    /// 視界を与える観測者（草むら・ステルスの看破判定用）。
    struct Observer {
        var pos: Vec2
        var brush: Int?
        var isStructure: Bool
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let cellSize = Balance.visionCellSize
        let cols = Int((ctx.map.size / cellSize).rounded(.up))
        let rows = cols
        var cells = [UInt8](repeating: 0, count: cols * rows)

        // 草むら位置の更新
        for i in s.units.indices {
            s.units[i].brushIndex = s.units[i].isAlive ? ctx.map.brushIndex(at: s.units[i].pos) : nil
        }

        // 視界円の焼き込みと観測者の収集
        var observers: [[Observer]] = [[], []]
        for team in Team.players {
            stamp(&cells, cols: cols, rows: rows, center: ctx.map.fountain(team), radius: Balance.fountainSight,
                  bit: team.visionBit)
        }
        for i in s.units.indices {
            let team = s.units[i].team
            guard team == .blue || team == .red, let radius = sightRadius(s, i) else { continue }
            let pos = s.units[i].pos
            stamp(&cells, cols: cols, rows: rows, center: pos, radius: radius, bit: team.visionBit)
            observers[team.rawValue].append(Observer(pos: pos, brush: s.units[i].brushIndex,
                                                     isStructure: s.units[i].isStructure))
        }
        s.vision.cols = cols
        s.vision.rows = rows
        s.vision.cells = cells

        // ユニットの可視判定
        for i in s.units.indices {
            let team = s.units[i].team
            var mask: UInt8 = team.visionBit
            let target = Target(s, i)
            for viewer in Team.players where viewer != team {
                if isVisible(target, to: viewer, cells: cells, cols: cols, rows: rows,
                             observers: observers[viewer.rawValue], ctx: ctx) {
                    mask |= viewer.visionBit
                }
            }
            s.units[i].visibleMask = mask
        }
    }

    /// 可視判定に必要なユニットの要約。
    struct Target {
        var pos: Vec2
        var brush: Int?
        var alive: Bool
        var isStructure: Bool
        var revealed: Bool
        var stealthed: Bool

        /// units[i] の要約（Unit 全体をコピーしないよう、必要な項目だけを読む）。
        init(_ s: SimState, _ i: Int) {
            pos = s.units[i].pos
            brush = s.units[i].brushIndex
            alive = s.units[i].isAlive && (s.units[i].hero?.respawnTimer ?? 0) <= 0
            isStructure = s.units[i].isStructure
            var revealed = false, stealthed = false
            for k in s.units[i].statuses.indices {
                let kind = s.units[i].statuses[k].kind
                if kind == .revealed { revealed = true } else if kind == .stealth { stealthed = true }
            }
            self.revealed = revealed
            self.stealthed = stealthed
        }
    }

    /// units[i] の視界半径（視界を与えないユニットは nil）。死亡中のヒーローは視界なし。
    static func sightRadius(_ s: SimState, _ i: Int) -> Double? {
        guard s.units[i].isAlive else { return nil }
        let sight = s.units[i].stats.sightRange
        switch s.units[i].kind {
        case .hero:
            guard (s.units[i].hero?.respawnTimer ?? 0) <= 0 else { return nil }
            return sight > 0 ? sight : Balance.heroSight
        case .minion:
            return sight > 0 ? sight : Balance.minionSight
        case .tower, .core:
            return sight > 0 ? sight : Balance.towerSight
        case .monster, .dummy:
            return nil
        }
    }

    /// 敵チーム team から u が見えるか。
    static func isVisible(_ u: Target, to team: Team, cells: [UInt8], cols: Int, rows: Int,
                          observers: [Observer], ctx: SimContext) -> Bool {
        // 構造物は地形の一部として常に見える（破壊後の残骸も。攻撃対象かどうかは isAlive で別に判定される）
        if u.isStructure { return true }
        guard u.alive else { return false }
        if u.revealed { return true }
        let c = min(cols - 1, max(0, Int(u.pos.x / Balance.visionCellSize)))
        let r = min(rows - 1, max(0, Int(u.pos.y / Balance.visionCellSize)))
        guard cells[r * cols + c] & team.visionBit != 0 else { return false }

        if let b = u.brush {
            let rr = Balance.brushRevealRadius * Balance.brushRevealRadius
            var revealed = false
            for o in observers where o.brush == b || o.pos.distanceSquared(to: u.pos) <= rr {
                revealed = true
                break
            }
            if !revealed { return false }
        }
        if u.stealthed {
            let near = Balance.stealthRevealRadius * Balance.stealthRevealRadius
            let trueSight = Balance.towerTrueSightRadius * Balance.towerTrueSightRadius
            var revealed = ctx.map.isInFountain(u.pos, team: team)
            for o in observers where !revealed {
                let d = o.pos.distanceSquared(to: u.pos)
                if d <= near || (o.isStructure && d <= trueSight) { revealed = true }
            }
            if !revealed { return false }
        }
        return true
    }

    /// 円内（格子中心が半径以内）の格子に bit を立てる。行毎に列の範囲を解析的に求めて塗る。
    static func stamp(_ cells: inout [UInt8], cols: Int, rows: Int, center: Vec2, radius: Double, bit: UInt8) {
        let cs = Balance.visionCellSize
        let r0 = max(0, Int(((center.y - radius) / cs - 0.5).rounded(.up)))
        let r1 = min(rows - 1, Int(((center.y + radius) / cs - 0.5).rounded(.down)))
        guard r0 <= r1 else { return }
        let rSq = radius * radius
        cells.withUnsafeMutableBufferPointer { buf in
            for r in r0...r1 {
                let dy = (Double(r) + 0.5) * cs - center.y
                let span = rSq - dy * dy
                if span < 0 { continue }
                let dx = span.squareRoot()
                // 格子中心 x = (c + 0.5)·cs が [cx − dx, cx + dx] に入る列
                let c0 = max(0, Int(((center.x - dx) / cs - 0.5).rounded(.up)))
                let c1 = min(cols - 1, Int(((center.x + dx) / cs - 0.5).rounded(.down)))
                guard c0 <= c1 else { continue }
                let base = r * cols
                for c in c0...c1 { buf[base + c] |= bit }
            }
        }
    }
}
