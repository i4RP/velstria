import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// 地形を無視する引き寄せ（壁越しの鉤など）。`Kit.pull`（KitMovement.swift）は壁の手前で止まるが、
// こちらは終点が歩ける場所なら壁を素通りして直線で運ぶ。変位は `kind: .knockback`（新しい DisplacementKind は作らない）。

extension Kit {
    /// target を point へ直線で引き寄せる。終点（point から gap 手前。Kit.pull と同じ位置）が歩ける場所なら、途中の壁を無視して運ぶ。
    /// 途中に壁が無いとき・終点が壁の中などで歩けないときは `Kit.pull`（壁の手前で止まる）と同じ。動かせたら true。
    @discardableResult
    static func pullIgnoringTerrain(_ s: inout SimState, _ ctx: SimContext, target t: Int, toward point: Vec2,
                                    distance: Double, duration: Double, gap: Double = 0) -> Bool {
        guard canDisplace(s, ctx, t), distance > 0 else { return false }
        let from = s.units[t].pos
        let delta = point - from
        let d = delta.length
        let travel = min(distance, d - max(0, gap))
        guard d > 1e-6, travel > 1e-6 else { return false }
        // Kit.pull → MovementSystem.knockback と同じ式で終点を出す（壁が無ければ結果は完全に同じ）
        let dir = (delta / d).normalized
        let to = from + dir * travel
        let r = s.units[t].radius
        let blocked = ctx.nav.raycast(from: from, to: to, radius: r)
        guard blocked.distanceSquared(to: to) > 1e-6, ctx.nav.isWalkable(to, radius: r) else {
            return pull(&s, ctx, target: t, toward: point, distance: distance, duration: duration, gap: gap)
        }
        let disp = Displacement(kind: .knockback, from: from, to: to, duration: duration)
        s.units[t].displacement = disp
        s.units[t].windupRemaining = nil
        s.units[t].path.removeAll()
        s.emit(.displaced(unitID: s.units[t].id, kind: .knockback, from: from, to: to, duration: disp.duration))
        return true
    }
}
