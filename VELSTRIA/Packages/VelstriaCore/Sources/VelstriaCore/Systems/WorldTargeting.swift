import Foundation

// 担当: core-world。ミニオン・タワー・モンスターの索敵で共有する軽量なユニット情報。
// Unit 全体のコピー（配列・Optional を多く含む）を O(n²) ループで繰り返さないよう、tick 毎に 1 度だけ抜き出す。

/// 索敵用のユニット要約（units の添字昇順）。
struct WorldCandidate {
    var index: Int
    var id: EntityID
    var kind: UnitKind
    var team: Team
    var pos: Vec2
    var radius: Double
    var visibleMask: UInt8
    /// 対象不可（キット層。単体の索敵から外す）。
    var untargetable = false

    var isStructure: Bool { kind == .tower || kind == .core }

    /// team から見て視認できるか（SimState.isVisible と同じ規則）。
    @inline(__always) func isVisible(to team: Team) -> Bool {
        self.team == team || team == .neutral || visibleMask & team.visionBit != 0
    }

    /// team の敵として攻撃対象にできるか（SimState.isTargetableEnemy と同じ規則。生存は抽出時に保証）。
    @inline(__always) func isTargetableEnemy(of team: Team) -> Bool {
        self.team != team && !untargetable && isVisible(to: team)
    }
}

/// 索敵候補の一様格子（1000 単位）。格子毎の候補を平坦な配列に詰める（CSR 形式、候補は添字昇順）。
/// 近傍問い合わせの訪問順は固定なので、呼び出し側は (距離, 添字) で同点を解決すれば決定論的になる。
struct WorldSpatialIndex {
    static let cellSize: Double = 1000
    let cols: Int
    /// 格子 k の候補は items[start[k] ..< start[k + 1]]（candidates の添字）。
    private(set) var start: [Int]
    private(set) var items: [Int]
    /// 候補の最大半径（問い合わせ範囲の拡張に使う）。
    private(set) var maxRadius: Double = 0

    init(_ candidates: [WorldCandidate], mapSize: Double = Balance.mapSize) {
        let cols = max(1, Int((mapSize / WorldSpatialIndex.cellSize).rounded(.up)))
        self.cols = cols
        var counts = [Int](repeating: 0, count: cols * cols + 1)
        var cellOf = [Int](repeating: 0, count: candidates.count)
        var maxR = 0.0
        for (k, c) in candidates.enumerated() {
            let cell = WorldSpatialIndex.cell(c.pos, cols: cols)
            cellOf[k] = cell
            counts[cell + 1] += 1
            maxR = max(maxR, c.radius)
        }
        for k in 1..<counts.count { counts[k] += counts[k - 1] }
        var fill = counts
        var items = [Int](repeating: 0, count: candidates.count)
        for k in candidates.indices {
            items[fill[cellOf[k]]] = k
            fill[cellOf[k]] += 1
        }
        self.start = counts
        self.items = items
        self.maxRadius = maxR
    }

    static func cell(_ p: Vec2, cols: Int) -> Int {
        let c = min(cols - 1, max(0, Int(p.x / cellSize)))
        let r = min(cols - 1, max(0, Int(p.y / cellSize)))
        return r * cols + c
    }

    /// center から radius（+ 候補の最大半径）以内にありうる候補の添字を body に渡す。
    func forEach(near center: Vec2, radius: Double, _ body: (Int) -> Void) {
        let r = radius + maxRadius
        let cs = WorldSpatialIndex.cellSize
        let c0 = max(0, Int((center.x - r) / cs)), c1 = min(cols - 1, Int((center.x + r) / cs))
        let r0 = max(0, Int((center.y - r) / cs)), r1 = min(cols - 1, Int((center.y + r) / cs))
        guard c0 <= c1, r0 <= r1 else { return }
        for row in r0...r1 {
            for col in c0...c1 {
                let k = row * cols + col
                var j = start[k]
                let end = start[k + 1]
                while j < end {
                    body(items[j])
                    j += 1
                }
            }
        }
    }
}

enum WorldTargeting {
    /// 生存中（死亡中のヒーローを除く）の全ユニットの要約。
    static func candidates(_ s: SimState) -> [WorldCandidate] {
        var out: [WorldCandidate] = []
        out.reserveCapacity(s.units.count)
        for i in s.units.indices {
            guard s.units[i].isAlive else { continue }
            let kind = s.units[i].kind
            if kind == .hero, s.units[i].hero?.isDead == true { continue }
            var c = WorldCandidate(index: i, id: s.units[i].id, kind: kind, team: s.units[i].team,
                                   pos: s.units[i].pos, radius: s.units[i].radius,
                                   visibleMask: s.units[i].visibleMask)
            if kind == .hero, !s.units[i].statuses.isEmpty, s.units[i].has(.untargetable) { c.untargetable = true }
            out.append(c)
        }
        return out
    }

    /// 構造物の無敵状態（index = units の添字、構造物以外は false）。1 tick 内で何度も参照するため先に求める。
    static func structureInvulnerability(_ s: SimState) -> [Bool] {
        // 生存中の各レーン・段のタワーと、落ちた基部塔の有無（チーム別）
        var aliveTier = [[[Bool]]](repeating: [[Bool]](repeating: [false, false, false], count: 3), count: 2)
        var baseDown = [false, false]
        for i in s.units.indices where s.units[i].kind == .tower {
            let team = s.units[i].team
            guard team == .blue || team == .red, let td = s.units[i].tower else { continue }
            if s.units[i].isAlive {
                if let lane = td.lane { aliveTier[team.rawValue][lane.rawValue][td.tier.rawValue] = true }
            } else if td.tier == .base {
                baseDown[team.rawValue] = true
            }
        }
        var out = [Bool](repeating: false, count: s.units.count)
        for i in s.units.indices where s.units[i].isStructure {
            let team = s.units[i].team
            guard team == .blue || team == .red, let td = s.units[i].tower else { continue }
            if s.units[i].kind == .core {
                out[i] = !baseDown[team.rawValue]
            } else if let lane = td.lane {
                var blocked = false
                for tier in 0..<td.tier.rawValue where aliveTier[team.rawValue][lane.rawValue][tier] { blocked = true }
                out[i] = blocked
            }
        }
        return out
    }
}

enum WorldSteering {
    /// from から goal へ向かうときの次の目標点。直進できれば goal、壁があれば経路の最初の経由点。
    /// MovementSystem の経路追従に頼らず、ミニオンのレーン復帰やモンスターの帰還が壁に引っかからないようにする。
    static func nextWaypoint(_ ctx: SimContext, from: Vec2, to goal: Vec2, radius: Double) -> Vec2 {
        if ctx.nav.hasLineOfSight(from: from, to: goal, radius: radius) { return goal }
        return ctx.nav.findPath(from: from, to: goal, radius: radius).first ?? goal
    }
}
