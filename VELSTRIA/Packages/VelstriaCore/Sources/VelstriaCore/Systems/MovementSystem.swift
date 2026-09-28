import Foundation

// 担当: core-combat
// 強制移動（突進・ノックバック・跳躍）、移動意図（方向・地点・追跡）、ミニオンの押し合い。
// 障害物と経路は NavGrid（core-world）の API のみを使う。ヒーローはユニットに阻まれない。

public enum MovementSystem {
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        var hasMinions = false
        for i in s.units.indices where s.units[i].isAlive {
            let kind = s.units[i].kind
            if kind == .minion { hasMinions = true }
            if kind == .tower || kind == .core { continue }
            if s.units[i].displacement != nil {
                advanceDisplacement(&s, ctx, i)
                continue
            }
            // CC・前隙中・詠唱中は動かない
            guard s.units[i].canMove, s.units[i].windupRemaining == nil, s.units[i].hero?.channel == nil else { continue }
            let step = currentMoveSpeed(s, i) * Balance.dt
            switch s.units[i].moveIntent {
            case .none:
                if !s.units[i].path.isEmpty { s.units[i].path.removeAll() }
            case .direction(let dir):
                moveInDirection(&s, ctx, i, direction: dir, step: step)
            case .point(let goal):
                moveToPoint(&s, ctx, i, goal: goal, step: step)
            case .follow(let targetID, let range):
                follow(&s, ctx, i, targetID: targetID, range: range, step: step)
            }
        }
        if hasMinions { separateMinions(&s, ctx) }
    }

    /// 現在の移動速度（ヒーローは非戦闘時に outOfCombatMoveSpeedBonus の割合を加算）。
    public static func currentMoveSpeed(_ s: SimState, _ i: Int) -> Double {
        var speed = s.units[i].stats.moveSpeed
        if s.units[i].kind == .hero, s.time - s.units[i].lastCombatTime > Balance.combatTimeout {
            speed *= 1 + max(0, s.units[i].stats.outOfCombatMoveSpeedBonus)
        }
        return max(0, speed)
    }

    // MARK: - 強制移動

    static func advanceDisplacement(_ s: inout SimState, _ ctx: SimContext, _ i: Int) {
        guard var d = s.units[i].displacement else { return }
        d.elapsed += Balance.dt
        let t = min(1, d.elapsed / d.duration)
        if d.kind != .knockback, d.to != d.from { s.units[i].facing = (d.to - d.from).angle }
        if t >= 1 - CombatSystem.timeEpsilon {
            var landing = d.to
            let r = s.units[i].radius
            // 跳躍は壁を越えるため、着地点を歩行可能な最寄り点へ補正する
            if !ctx.nav.isWalkable(landing, radius: r) { landing = ctx.nav.nearestWalkable(landing, radius: r) }
            s.units[i].pos = landing
            s.units[i].displacement = nil
            s.units[i].path.removeAll()
        } else {
            s.units[i].pos = Vec2.lerp(d.from, d.to, t)
            s.units[i].displacement = d
        }
    }

    /// 突進・跳躍を開始。突進は障害物の手前で止まり、跳躍は障害物を越えて歩行可能点に着地する。戻り値 = 実際の終点。
    @discardableResult
    public static func dash(_ s: inout SimState, _ ctx: SimContext, unitIndex i: Int, to target: Vec2,
                            speed: Double, kind: DisplacementKind = .dash) -> Vec2 {
        let from = s.units[i].pos
        let r = s.units[i].radius
        let to: Vec2
        if kind == .leap {
            to = ctx.nav.isWalkable(target, radius: r) ? target : ctx.nav.nearestWalkable(target, radius: r)
        } else {
            to = ctx.nav.raycast(from: from, to: target, radius: r)
        }
        let duration = max(Balance.dt, from.distance(to: to) / max(1, speed))
        s.units[i].displacement = Displacement(kind: kind, from: from, to: to, duration: duration)
        s.units[i].windupRemaining = nil
        s.units[i].path.removeAll()
        if to != from { s.units[i].facing = (to - from).angle }
        s.emit(.displaced(unitID: s.units[i].id, kind: kind, from: from, to: to, duration: duration))
        return to
    }

    /// ノックバック（障害物・マップ端の手前で止まる）。構造物は動かない。
    public static func knockback(_ s: inout SimState, _ ctx: SimContext, unitIndex i: Int, direction: Vec2,
                                 distance: Double, duration: Double) {
        guard s.units[i].isAlive, !s.units[i].isStructure, distance > 0 else { return }
        let dir = direction.normalized
        guard dir != .zero else { return }
        let from = s.units[i].pos
        let to = ctx.nav.raycast(from: from, to: from + dir * distance, radius: s.units[i].radius)
        let d = Displacement(kind: .knockback, from: from, to: to, duration: duration)
        s.units[i].displacement = d
        s.units[i].windupRemaining = nil
        s.units[i].path.removeAll()
        s.emit(.displaced(unitID: s.units[i].id, kind: .knockback, from: from, to: to, duration: d.duration))
    }

    /// 瞬間移動（障害物の手前で止まる）。戻り値 = 実際の到達点。
    @discardableResult
    public static func blink(_ s: inout SimState, _ ctx: SimContext, unitIndex i: Int, to target: Vec2) -> Vec2 {
        let from = s.units[i].pos
        let to = ctx.nav.raycast(from: from, to: target, radius: s.units[i].radius)
        s.units[i].pos = to
        s.units[i].prevPos = to
        s.units[i].displacement = nil
        s.units[i].windupRemaining = nil
        s.units[i].path.removeAll()
        if to != from { s.units[i].facing = (to - from).angle }
        s.emit(.blinked(unitID: s.units[i].id, from: from, to: to))
        return to
    }

    // MARK: - 移動意図

    static func moveInDirection(_ s: inout SimState, _ ctx: SimContext, _ i: Int, direction: Vec2, step: Double) {
        if !s.units[i].path.isEmpty { s.units[i].path.removeAll() }
        let dir = direction.normalized
        guard dir != .zero else { return }
        s.units[i].facing = dir.angle
        guard step > 0 else { return }
        let old = s.units[i].pos
        s.units[i].pos = ctx.nav.resolveMove(from: old, to: old + dir * step, radius: s.units[i].radius)
    }

    static func moveToPoint(_ s: inout SimState, _ ctx: SimContext, _ i: Int, goal: Vec2, step: Double) {
        let r = s.units[i].radius
        let old = s.units[i].pos
        let repathSq = Balance.combatRepathDistance * Balance.combatRepathDistance
        // 経路は一旦取り出して書き戻す（配列のコピーを避ける）
        var path = s.units[i].path
        s.units[i].path = []
        if let last = path.last, last.distanceSquared(to: goal) > repathSq { path.removeAll() }
        if path.isEmpty {
            if old.distanceSquared(to: goal) <= Balance.combatArrivalDistance * Balance.combatArrivalDistance {
                s.units[i].moveIntent = .none
                return
            }
            path = planPath(ctx, from: old, to: goal, radius: r)
            guard let last = path.last else {
                s.units[i].moveIntent = .none
                return
            }
            // 目標が歩行不能で補正された場合は意図の目標も置き換え、毎 tick の再探索を防ぐ
            if last.distanceSquared(to: goal) > repathSq { s.units[i].moveIntent = .point(last) }
        }
        guard step > 0 else {
            s.units[i].path = path
            return
        }
        let new = advance(ctx, from: old, along: &path, step: step, radius: r)
        s.units[i].pos = new
        faceMovement(&s, i, from: old, to: new)
        if path.isEmpty {
            s.units[i].moveIntent = .none
        } else if isStuck(s, i, from: old, to: new, step: step) {
            path.removeAll()
        }
        s.units[i].path = path
    }

    static func follow(_ s: inout SimState, _ ctx: SimContext, _ i: Int, targetID: EntityID, range: Double,
                       step: Double) {
        let team = s.units[i].team
        guard let t = s.index(of: targetID), t != i, CombatSystem.isLiving(s, t),
              s.units[t].team == team || s.isVisible(t, to: team) else {
            s.units[i].moveIntent = .none
            s.units[i].path.removeAll()
            return
        }
        let r = s.units[i].radius
        let old = s.units[i].pos
        let targetPos = s.units[t].pos
        let reach = max(0, range) + r + s.units[t].radius
        let dist = old.distance(to: targetPos)
        if dist <= reach + 0.5 {
            s.units[i].moveIntent = .none
            s.units[i].path.removeAll()
            if dist > 1e-6 { s.units[i].facing = (targetPos - old).angle }
            return
        }
        guard step > 0 else { return }
        let travel = min(step, dist - reach)
        var path = s.units[i].path
        s.units[i].path = []
        let new: Vec2
        if ctx.nav.raycast(from: old, to: targetPos, radius: r).distanceSquared(to: targetPos) < 1 {
            // 見通しが通る: 直進
            path.removeAll()
            new = ctx.nav.resolveMove(from: old, to: old.moved(toward: targetPos, maxDistance: travel), radius: r)
        } else {
            let repathSq = Balance.combatRepathDistance * Balance.combatRepathDistance
            if let last = path.last, last.distanceSquared(to: targetPos) > repathSq { path.removeAll() }
            if path.isEmpty { path = planPath(ctx, from: old, to: targetPos, radius: r) }
            new = advance(ctx, from: old, along: &path, step: travel, radius: r)
            if isStuck(s, i, from: old, to: new, step: travel) { path.removeAll() }
        }
        s.units[i].pos = new
        faceMovement(&s, i, from: old, to: new)
        s.units[i].path = path
    }

    /// 経路（末尾は歩行可能な目標点）。直進できれば A* を省略する。到達不能なら直進（壁ずり）で試みる。
    static func planPath(_ ctx: SimContext, from: Vec2, to target: Vec2, radius: Double) -> [Vec2] {
        let nav = ctx.nav
        let goal = nav.isWalkable(target, radius: radius) ? target : nav.nearestWalkable(target, radius: radius)
        if nav.raycast(from: from, to: goal, radius: radius).distanceSquared(to: goal) < 1 { return [goal] }
        var path = nav.findPath(from: from, to: goal, radius: radius)
        if path.isEmpty { return [goal] }
        if let last = path.last, last.distanceSquared(to: goal) > 1 { path.append(goal) }
        return path
    }

    /// 経由点に沿って step だけ進む（各区間は壁ずり解決）。到達した経由点は path から取り除く。
    static func advance(_ ctx: SimContext, from start: Vec2, along path: inout [Vec2], step: Double,
                        radius: Double) -> Vec2 {
        var pos = start
        var remaining = step
        var reached = 0
        while remaining > 1e-9, reached < path.count {
            let waypoint = path[reached]
            let d = pos.distance(to: waypoint)
            if d <= remaining {
                pos = ctx.nav.resolveMove(from: pos, to: waypoint, radius: radius)
                remaining -= d
                reached += 1
            } else {
                pos = ctx.nav.resolveMove(from: pos, to: pos + (waypoint - pos) * (remaining / d), radius: radius)
                remaining = 0
            }
        }
        if reached > 0 { path.removeFirst(reached) }
        return pos
    }

    /// ほとんど進めなかった場合、数 tick 毎に経路を作り直す（(tick + id) で分散）。
    static func isStuck(_ s: SimState, _ i: Int, from old: Vec2, to new: Vec2, step: Double) -> Bool {
        guard step > 0 else { return false }
        let moved = old.distance(to: new)
        guard moved < step * Balance.combatStuckRatio else { return false }
        return (s.tick + Int(s.units[i].id)) % Balance.combatStuckRepathEveryTicks == 0
    }

    static func faceMovement(_ s: inout SimState, _ i: Int, from old: Vec2, to new: Vec2) {
        let d = new - old
        if d.lengthSquared > 1e-6 { s.units[i].facing = d.angle }
    }

    // MARK: - ミニオンの押し合い

    /// 同じチームのミニオン同士を半径和 × 0.9 まで押し離す（柔らかく数 tick で解消）。
    /// 近傍探索は決定論的な一様格子。移動できない側（CC・強制移動中）は押されない。
    static func separateMinions(_ s: inout SimState, _ ctx: SimContext) {
        var indices: [Int] = []
        var positions: [Vec2] = []
        var radii: [Double] = []
        var teams: [Team] = []
        var movable: [Bool] = []
        var maxRadius = 0.0
        for i in s.units.indices where s.units[i].kind == .minion && s.units[i].isAlive {
            indices.append(i)
            positions.append(s.units[i].pos)
            radii.append(s.units[i].radius)
            teams.append(s.units[i].team)
            movable.append(s.units[i].canMove)
            maxRadius = max(maxRadius, s.units[i].radius)
        }
        let n = indices.count
        guard n > 1 else { return }
        let ratio = Balance.combatMinionSeparationRatio
        let grid = CombatSpatialGrid(positions: positions, cellSize: 2 * maxRadius * ratio)
        var push = [Vec2](repeating: .zero, count: n)
        var near: [Int] = []
        for a in 0..<n {
            near.removeAll(keepingCapacity: true)
            grid.query(positions[a], radius: (radii[a] + maxRadius) * ratio, into: &near)
            for b in near where b > a && teams[b] == teams[a] {
                let minDist = (radii[a] + radii[b]) * ratio
                let delta = positions[a] - positions[b]
                let d2 = delta.lengthSquared
                guard d2 < minDist * minDist else { continue }
                let d = d2.squareRoot()
                let normal: Vec2
                if d > 1e-6 {
                    normal = delta / d
                } else {
                    // 完全に重なった場合は ID から決まる方向へ
                    let seed = Int(s.units[indices[a]].id) &* 7919 &+ Int(s.units[indices[b]].id) &* 104_729
                    normal = Vec2.fromAngle(Double(abs(seed) % 360) * Double.pi / 180)
                }
                let overlap = (minDist - d) * Balance.combatMinionSeparationStiffness
                switch (movable[a], movable[b]) {
                case (true, true):
                    push[a] += normal * (overlap * 0.5)
                    push[b] -= normal * (overlap * 0.5)
                case (true, false):
                    push[a] += normal * overlap
                case (false, true):
                    push[b] -= normal * overlap
                case (false, false):
                    break
                }
            }
        }
        for a in 0..<n where push[a] != .zero {
            let p = push[a].clamped(maxLength: Balance.combatMinionSeparationMaxPush)
            let i = indices[a]
            s.units[i].pos = ctx.nav.resolveMove(from: positions[a], to: positions[a] + p, radius: radii[a])
        }
    }
}
