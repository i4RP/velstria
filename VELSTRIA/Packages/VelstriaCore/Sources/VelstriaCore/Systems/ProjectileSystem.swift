import Foundation

// 担当: core-combat
// 投射物: 追尾弾（通常攻撃・対象指定）と直線弾（スキルショット）。
// 直線弾は 1 tick の移動区間を線分として掃引判定し、高速弾のすり抜けを防ぐ。
// 直線弾は視界に関係なく当たり、構造物には当たらない。

public enum ProjectileSystem {
    /// 投射物を生成し ID を返す。発射位置は所有者の位置（origin 指定時はその位置）。
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
        // 命中処理中に生成された投射物は次 tick から進める
        let count = s.projectiles.count
        for k in 0..<count where !s.projectiles[k].done {
            switch s.projectiles[k].motion {
            case .homing(let targetID):
                stepHoming(&s, ctx, k, targetID: targetID)
            case .linear(let direction, let maxDistance):
                stepLinear(&s, ctx, k, direction: direction, maxDistance: maxDistance)
            }
        }
    }

    // MARK: - 追尾弾

    static func stepHoming(_ s: inout SimState, _ ctx: SimContext, _ k: Int, targetID: EntityID) {
        var p = s.projectiles[k]
        guard let t = s.index(of: targetID), isValidHomingTarget(s, t, team: p.team) else {
            fizzle(&s, k, p)
            return
        }
        let targetPos = s.units[t].pos
        let step = p.speed * Balance.dt
        let dist = p.pos.distance(to: targetPos)
        if dist <= step + s.units[t].radius {
            let from = p.pos
            p.traveled += min(step, dist)
            p.pos = targetPos
            p.hitIDs.append(targetID)
            p.done = true
            s.projectiles[k] = p
            s.emit(.projectileHit(projectileID: p.id, targetID: targetID, pos: targetPos))
            CombatSystem.applyHit(&s, ctx, sourceID: p.ownerID, team: p.team, targetIndex: t, payload: p.payload,
                                  from: from)
            return
        }
        p.pos = p.pos.moved(toward: targetPos, maxDistance: step)
        p.traveled += step
        if p.traveled >= Balance.combatHomingMaxTravel {
            fizzle(&s, k, p)
            return
        }
        s.projectiles[k] = p
    }

    /// 追尾対象が有効か（生存中。敵なら視認中 = 不可視化・対象不可で消滅）。
    static func isValidHomingTarget(_ s: SimState, _ t: Int, team: Team) -> Bool {
        guard CombatSystem.isLiving(s, t) else { return false }
        if s.units[t].team == team { return true }
        if !s.units[t].statuses.isEmpty, s.units[t].has(.untargetable) { return false }
        return s.isVisible(t, to: team)
    }

    static func fizzle(_ s: inout SimState, _ k: Int, _ projectile: Projectile) {
        var p = projectile
        p.done = true
        s.projectiles[k] = p
        s.emit(.projectileHit(projectileID: p.id, targetID: nil, pos: p.pos))
    }

    // MARK: - 直線弾

    static func stepLinear(_ s: inout SimState, _ ctx: SimContext, _ k: Int, direction: Vec2, maxDistance: Double) {
        var p = s.projectiles[k]
        let dir = direction.normalized
        let remaining = maxDistance - p.traveled
        guard dir != .zero, remaining > 1e-9, p.speed > 0 else {
            fizzle(&s, k, p)
            return
        }
        let start = p.pos
        var length = min(p.speed * Balance.dt, remaining)
        // マップ端で止める
        let edge = distanceToMapEdge(from: start, direction: dir, size: ctx.map.size)
        var reachedEdge = false
        if edge <= length {
            length = max(0, edge)
            reachedEdge = true
        }

        // 区間 start → start + dir × length に掛かる対象を、進行方向の手前から順に
        var hits: [(entry: Double, index: Int)] = []
        for i in s.units.indices {
            guard canCollide(s, i, with: p) else { continue }
            let rr = s.units[i].radius + p.width
            let rel = s.units[i].pos - start
            let along = rel.dot(dir)
            guard along >= -rr, along <= length + rr else { continue }
            let perpSq = max(0, rel.lengthSquared - along * along)
            guard perpSq <= rr * rr else { continue }
            let closest = min(max(along, 0), length)
            let cx = rel.x - dir.x * closest, cy = rel.y - dir.y * closest
            guard cx * cx + cy * cy <= rr * rr else { continue }
            let entry = min(max(along - (rr * rr - perpSq).squareRoot(), 0), length)
            hits.append((entry, i))
        }
        if hits.count > 1 {
            hits.sort { $0.entry != $1.entry ? $0.entry < $1.entry : $0.index < $1.index }
        }

        for h in hits {
            guard CombatSystem.isLiving(s, h.index) else { continue }
            let targetID = s.units[h.index].id
            p.hitIDs.append(targetID)
            let hitPos = start + dir * h.entry
            if !p.pierce {
                p.pos = hitPos
                p.traveled += h.entry
                p.done = true
            }
            s.projectiles[k] = p
            s.emit(.projectileHit(projectileID: p.id, targetID: targetID, pos: hitPos))
            // ノックバックは弾の進行方向へ
            CombatSystem.applyHit(&s, ctx, sourceID: p.ownerID, team: p.team, targetIndex: h.index,
                                  payload: p.payload, from: s.units[h.index].pos - dir * 100)
            if p.done { return }
        }

        p.pos = start + dir * length
        p.traveled += length
        if reachedEdge || p.traveled >= maxDistance - 1e-6 {
            fizzle(&s, k, p)
            return
        }
        s.projectiles[k] = p
    }

    /// 直線弾がユニット i に当たり得るか（未命中・生存・構造物以外・陣営と payload の条件）。
    static func canCollide(_ s: SimState, _ i: Int, with p: Projectile) -> Bool {
        guard CombatSystem.isLiving(s, i), !s.units[i].isStructure else { return false }
        if p.payload.heroesOnly && s.units[i].kind != .hero { return false }
        if s.units[i].team == p.team {
            guard p.payload.affectsAllies, s.units[i].id != p.ownerID else { return false }
        } else {
            guard p.payload.affectsEnemies else { return false }
        }
        return !p.hitIDs.contains(s.units[i].id)
    }

    /// start から dir 方向にマップ（0...size の正方形）の端までの距離。
    static func distanceToMapEdge(from start: Vec2, direction dir: Vec2, size: Double) -> Double {
        var t = Double.infinity
        if dir.x > 1e-12 { t = min(t, (size - start.x) / dir.x) } else if dir.x < -1e-12 { t = min(t, -start.x / dir.x) }
        if dir.y > 1e-12 { t = min(t, (size - start.y) / dir.y) } else if dir.y < -1e-12 { t = min(t, -start.y / dir.y) }
        return max(0, t)
    }
}
