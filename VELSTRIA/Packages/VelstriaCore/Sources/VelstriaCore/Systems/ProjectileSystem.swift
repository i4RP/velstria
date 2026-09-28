import Foundation

// 担当: core-combat（最小実装）

public enum ProjectileSystem {
    /// 投射物を生成し ID を返す。発射位置は所有者の位置。
    @discardableResult
    public static func spawn(_ s: inout SimState, ownerIndex i: Int, motion: ProjectileMotion, speed: Double,
                             width: Double = 0, pierce: Bool = false, payload: HitPayload, visual: String,
                             origin: Vec2? = nil) -> EntityID {
        let id = s.allocateID()
        let p = Projectile(id: id, ownerID: s.units[i].id, team: s.units[i].team, pos: origin ?? s.units[i].pos,
                           motion: motion, speed: speed, width: width, pierce: pierce, payload: payload, visual: visual)
        s.projectiles.append(p)
        s.emit(.projectileLaunched(projectileID: id, ownerID: s.units[i].id, visual: visual))
        return id
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let dt = Balance.dt
        for k in s.projectiles.indices where !s.projectiles[k].done {
            var p = s.projectiles[k]
            let step = p.speed * dt
            switch p.motion {
            case .homing(let tid):
                guard let t = s.index(of: tid), s.units[t].isAlive else { p.done = true; break }
                let targetPos = s.units[t].pos
                if p.pos.distance(to: targetPos) <= step + s.units[t].radius {
                    p.pos = targetPos
                    p.done = true
                    s.projectiles[k] = p
                    CombatSystem.applyHit(&s, ctx, sourceID: p.ownerID, team: p.team, targetIndex: t,
                                          payload: p.payload, from: p.prevPos)
                    s.emit(.projectileHit(projectileID: p.id, targetID: tid, pos: targetPos))
                    continue
                }
                p.pos = p.pos.moved(toward: targetPos, maxDistance: step)
            case .linear(let dir, let maxDist):
                p.pos += dir * step
                p.traveled += step
                let hits = s.enemies(of: p.team, near: p.pos, radius: p.width)
                    .filter { !p.hitIDs.contains(s.units[$0].id) }
                    .filter { !p.payload.heroesOnly || s.units[$0].kind == .hero }
                for t in hits {
                    p.hitIDs.append(s.units[t].id)
                    s.projectiles[k] = p
                    CombatSystem.applyHit(&s, ctx, sourceID: p.ownerID, team: p.team, targetIndex: t,
                                          payload: p.payload, from: p.pos - dir * 50)
                    s.emit(.projectileHit(projectileID: p.id, targetID: s.units[t].id, pos: p.pos))
                    if !p.pierce { p.done = true; break }
                }
                if p.traveled >= maxDist { p.done = true }
            }
            s.projectiles[k] = p
        }
    }
}
