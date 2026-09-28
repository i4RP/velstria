import Foundation

// 担当: core-world（最小実装。索敵優先度・ヒーローへの反撃ルール・押し合いを実装すること）

public enum MinionSystem {
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        for i in s.units.indices where s.units[i].kind == .minion && s.units[i].isAlive {
            let u = s.units[i]
            if let t = s.index(of: u.attackTargetID), s.isTargetableEnemy(t, of: u.team),
               s.units[t].pos.distance(to: u.pos) <= 900 {
                continue
            }
            let near = s.enemies(of: u.team, near: u.pos, radius: 700)
            if let t = s.nearest(near, to: u.pos) {
                s.units[i].attackTargetID = s.units[t].id
                continue
            }
            s.units[i].attackTargetID = nil
            guard var m = u.minion else { continue }
            let path = ctx.map.lanePath(m.lane, for: u.team)
            if m.waypointIndex < path.count, u.pos.distance(to: path[m.waypointIndex]) < 120 {
                m.waypointIndex = min(path.count - 1, m.waypointIndex + 1)
                s.units[i].minion = m
            }
            s.units[i].moveIntent = .point(path[min(m.waypointIndex, path.count - 1)])
        }
    }
}
