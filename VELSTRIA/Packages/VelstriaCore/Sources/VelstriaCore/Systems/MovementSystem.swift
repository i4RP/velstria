import Foundation

// 担当: core-combat（最小実装。障害物に沿った移動・経路追従・ミニオンの押し合いを実装すること）

public enum MovementSystem {
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let dt = Balance.dt
        for i in s.units.indices where s.units[i].isAlive {
            // 強制移動
            if var d = s.units[i].displacement {
                d.elapsed += dt
                let t = min(1, d.elapsed / d.duration)
                s.units[i].pos = Vec2.lerp(d.from, d.to, t)
                s.units[i].displacement = t >= 1 ? nil : d
                continue
            }
            guard s.units[i].canMove, s.units[i].windupRemaining == nil else { continue }
            let speed = s.units[i].stats.moveSpeed
            let step = speed * dt
            switch s.units[i].moveIntent {
            case .none:
                break
            case .direction(let dir):
                let to = s.units[i].pos + dir * step
                s.units[i].pos = ctx.nav.resolveMove(from: s.units[i].pos, to: to, radius: s.units[i].radius)
                s.units[i].facing = dir.angle
            case .point(let p):
                let next = p
                let old = s.units[i].pos
                let new = old.moved(toward: next, maxDistance: step)
                s.units[i].pos = ctx.nav.resolveMove(from: old, to: new, radius: s.units[i].radius)
                if new != old { s.units[i].facing = (new - old).angle }
                if s.units[i].pos.distance(to: p) < 5 { s.units[i].moveIntent = .none }
            case .follow(let tid, let range):
                guard let t = s.index(of: tid), s.units[t].isAlive else {
                    s.units[i].moveIntent = .none
                    continue
                }
                let reach = range + s.units[i].radius + s.units[t].radius
                let old = s.units[i].pos
                if old.distance(to: s.units[t].pos) > reach {
                    let new = old.moved(toward: s.units[t].pos, maxDistance: step)
                    s.units[i].pos = ctx.nav.resolveMove(from: old, to: new, radius: s.units[i].radius)
                    s.units[i].facing = (new - old).angle
                } else {
                    s.units[i].moveIntent = .none
                }
            }
        }
    }

    /// 突進・跳躍を開始。終点は障害物で補正される。戻り値 = 実際の終点。
    @discardableResult
    public static func dash(_ s: inout SimState, _ ctx: SimContext, unitIndex i: Int, to target: Vec2,
                            speed: Double, kind: DisplacementKind = .dash) -> Vec2 {
        let from = s.units[i].pos
        let to = ctx.nav.raycast(from: from, to: target, radius: s.units[i].radius)
        let duration = max(Balance.dt, from.distance(to: to) / max(1, speed))
        s.units[i].displacement = Displacement(kind: kind, from: from, to: to, duration: duration)
        s.units[i].windupRemaining = nil
        s.units[i].facing = (to - from).angle
        s.emit(.displaced(unitID: s.units[i].id, kind: kind, from: from, to: to, duration: duration))
        return to
    }

    public static func knockback(_ s: inout SimState, _ ctx: SimContext, unitIndex i: Int, direction: Vec2,
                                 distance: Double, duration: Double) {
        guard !s.units[i].isStructure else { return }
        let from = s.units[i].pos
        let to = ctx.nav.raycast(from: from, to: from + direction.normalized * distance, radius: s.units[i].radius)
        s.units[i].displacement = Displacement(kind: .knockback, from: from, to: to, duration: duration)
        s.units[i].windupRemaining = nil
        s.emit(.displaced(unitID: s.units[i].id, kind: .knockback, from: from, to: to, duration: duration))
    }

    /// 瞬間移動。戻り値 = 実際の到達点。
    @discardableResult
    public static func blink(_ s: inout SimState, _ ctx: SimContext, unitIndex i: Int, to target: Vec2) -> Vec2 {
        let from = s.units[i].pos
        let to = ctx.nav.raycast(from: from, to: target, radius: s.units[i].radius)
        s.units[i].pos = to
        s.units[i].prevPos = to
        s.units[i].displacement = nil
        s.units[i].facing = (to - from).angle
        s.emit(.blinked(unitID: s.units[i].id, from: from, to: to))
        return to
    }
}
