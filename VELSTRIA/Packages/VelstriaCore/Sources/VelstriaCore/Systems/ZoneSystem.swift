import Foundation

// 担当: core-combat（最小実装。cone / line 形状の判定を実装すること）

public enum ZoneSystem {
    /// 範囲効果を生成し ID を返す。
    @discardableResult
    public static func spawn(_ s: inout SimState, ownerIndex i: Int, center: Vec2, radius: Double,
                             shape: ZoneShape = .circle, delay: Double, duration: Double = 0,
                             tickInterval: Double = 0.5, followsOwner: Bool = false,
                             payload: HitPayload, visual: String) -> EntityID {
        let id = s.allocateID()
        let z = AreaZone(id: id, ownerID: s.units[i].id, team: s.units[i].team, center: center, radius: radius,
                         shape: shape, delay: delay, duration: duration, tickInterval: tickInterval,
                         followsOwner: followsOwner, payload: payload, visual: visual)
        s.zones.append(z)
        s.emit(.zoneCreated(zoneID: id, ownerID: s.units[i].id, team: s.units[i].team, visual: visual, center: center,
                            radius: radius, delay: delay, duration: duration,
                            isBeneficial: payload.affectsAllies && !payload.affectsEnemies))
        return id
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let dt = Balance.dt
        for k in s.zones.indices where !s.zones[k].done {
            if s.zones[k].followsOwner, let o = s.unit(s.zones[k].ownerID) { s.zones[k].center = o.pos }
            if !s.zones[k].triggered {
                s.zones[k].delay -= dt
                guard s.zones[k].delay <= 0 else { continue }
                s.zones[k].triggered = true
                s.emit(.zoneTriggered(zoneID: s.zones[k].id, center: s.zones[k].center, radius: s.zones[k].radius))
                applyZone(&s, ctx, k)
                if s.zones[k].duration <= 0 { s.zones[k].done = true }
                continue
            }
            s.zones[k].duration -= dt
            s.zones[k].tickTimer += dt
            if s.zones[k].tickTimer >= s.zones[k].tickInterval {
                s.zones[k].tickTimer = 0
                applyZone(&s, ctx, k)
            }
            if s.zones[k].duration <= 0 { s.zones[k].done = true }
        }
    }

    static func applyZone(_ s: inout SimState, _ ctx: SimContext, _ k: Int) {
        let z = s.zones[k]
        var targets: [Int] = []
        if z.payload.affectsEnemies { targets += s.enemies(of: z.team, near: z.center, radius: z.radius) }
        if z.payload.affectsAllies { targets += s.allies(of: z.team, near: z.center, radius: z.radius) }
        for t in targets.sorted() {
            CombatSystem.applyHit(&s, ctx, sourceID: z.ownerID, team: z.team, targetIndex: t, payload: z.payload, from: z.center)
        }
    }
}
