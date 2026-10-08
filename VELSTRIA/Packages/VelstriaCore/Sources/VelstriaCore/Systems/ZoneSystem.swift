import Foundation

// 担当: core-combat
// 地面の範囲効果: 予告（delay）→ 発動 → 持続中は tickInterval 毎に再適用。
// 形状は円 / 扇形 / 線分（いずれも対象の半径を含めて判定）。視界に関係なく当たり、構造物には当たらない。
// 所有者が死亡・消滅しても発動・持続は続く（followsOwner は生存中のみ追従）。

public enum ZoneSystem {
    /// 範囲効果を生成し ID を返す。
    @discardableResult
    public static func spawn(_ s: inout SimState, ownerIndex i: Int, center: Vec2, radius: Double,
                             shape: ZoneShape = .circle, delay: Double, duration: Double = 0,
                             tickInterval: Double = 0.5, followsOwner: Bool = false,
                             followsTargetID: EntityID? = nil, payload: HitPayload, visual: String) -> EntityID {
        let id = s.allocateID()
        let z = AreaZone(id: id, ownerID: s.units[i].id, team: s.units[i].team, center: center, radius: radius,
                         shape: shape, delay: delay, duration: duration, tickInterval: tickInterval,
                         followsOwner: followsOwner, followsTargetID: followsTargetID, payload: payload,
                         visual: visual)
        s.zones.append(z)
        s.emit(.zoneCreated(zoneID: id, ownerID: s.units[i].id, team: s.units[i].team, visual: visual, center: center,
                            radius: radius, delay: delay, duration: duration,
                            isBeneficial: payload.affectsAllies && !payload.affectsEnemies))
        return id
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let dt = Balance.dt
        let eps = CombatSystem.timeEpsilon
        // 適用中に生成されたゾーンは次 tick から進める
        let count = s.zones.count
        for k in 0..<count where !s.zones[k].done {
            if s.zones[k].followsOwner, let o = s.index(of: s.zones[k].ownerID), CombatSystem.isLiving(s, o) {
                s.zones[k].center = s.units[o].pos
            }
            // 対象に追従するゾーン（キット層）: 対象が消えた/死亡したらゾーンは終わる
            if let targetID = s.zones[k].followsTargetID {
                guard let t = s.index(of: targetID), CombatSystem.isLiving(s, t) else {
                    s.zones[k].done = true
                    continue
                }
                s.zones[k].center = s.units[t].pos
            }
            if !s.zones[k].triggered {
                s.zones[k].delay -= dt
                guard s.zones[k].delay <= eps else { continue }
                s.zones[k].delay = 0
                s.zones[k].triggered = true
                s.zones[k].tickTimer = 0
                s.emit(.zoneTriggered(zoneID: s.zones[k].id, center: s.zones[k].center, radius: s.zones[k].radius))
                applyZone(&s, ctx, k)
                if s.zones[k].duration <= eps { s.zones[k].done = true }
                continue
            }
            s.zones[k].duration -= dt
            s.zones[k].tickTimer += dt
            let interval = max(dt, s.zones[k].tickInterval)
            if s.zones[k].tickTimer >= interval - eps {
                s.zones[k].tickTimer -= interval
                applyZone(&s, ctx, k)
            }
            if s.zones[k].duration <= eps { s.zones[k].done = true }
        }
    }

    /// ゾーン k の範囲内の対象に payload を適用する（添字昇順）。
    static func applyZone(_ s: inout SimState, _ ctx: SimContext, _ k: Int) {
        let z = s.zones[k]
        let bounds = boundingCircle(shape: z.shape, center: z.center, radius: z.radius)
        var targets: [Int] = []
        for i in s.units.indices {
            guard CombatSystem.isLiving(s, i), !s.units[i].isStructure else { continue }
            if s.units[i].team == z.team {
                guard z.payload.affectsAllies else { continue }
            } else {
                guard z.payload.affectsEnemies else { continue }
            }
            if z.payload.heroesOnly && s.units[i].kind != .hero { continue }
            let pos = s.units[i].pos
            let r = s.units[i].radius
            let reach = bounds.radius + r
            guard pos.distanceSquared(to: bounds.center) <= reach * reach else { continue }
            guard contains(shape: z.shape, center: z.center, radius: z.radius, point: pos, pointRadius: r) else { continue }
            targets.append(i)
        }
        guard !targets.isEmpty else { return }
        if z.duration <= 0 {
            for t in targets { s.zones[k].hitIDs.append(s.units[t].id) }
        }
        for t in targets {
            CombatSystem.applyHit(&s, ctx, sourceID: z.ownerID, team: z.team, targetIndex: t, payload: z.payload,
                                  from: z.center)
        }
    }

    /// 形状の外接円（広域判定用）。
    static func boundingCircle(shape: ZoneShape, center: Vec2, radius: Double) -> (center: Vec2, radius: Double) {
        switch shape {
        case .circle, .cone:
            return (center, radius)
        case .line(let direction, let length):
            let dir = direction.normalized
            let half = max(0, length) / 2
            return (center + dir * half, half + radius)
        }
    }

    /// 半径 pointRadius の円（ユニット）が形状と重なるか。
    /// - circle: 中心から radius
    /// - cone: 中心から radius の扇形（direction 方向、半角 halfAngle）
    /// - line: center から direction へ length の線分、半幅 radius
    public static func contains(shape: ZoneShape, center: Vec2, radius: Double, point: Vec2,
                                pointRadius: Double) -> Bool {
        switch shape {
        case .circle:
            let reach = radius + pointRadius
            return point.distanceSquared(to: center) <= reach * reach
        case .cone(let direction, let halfAngle):
            let reach = radius + pointRadius
            let rel = point - center
            let d2 = rel.lengthSquared
            if d2 > reach * reach { return false }
            if d2 <= pointRadius * pointRadius { return true }
            let dir = direction.normalized
            if dir == .zero || halfAngle >= Double.pi { return true }
            if halfAngle < 0 { return false }
            // 角度内なら外周（radius + 対象半径）で判定済み
            if rel.dot(dir) / d2.squareRoot() >= cos(halfAngle) { return true }
            // 角度外: 扇の両辺までの距離が対象半径以内なら重なる
            let edgeA = center + dir.rotated(by: halfAngle) * radius
            let edgeB = center + dir.rotated(by: -halfAngle) * radius
            return distancePointToSegment(point, center, edgeA) <= pointRadius
                || distancePointToSegment(point, center, edgeB) <= pointRadius
        case .line(let direction, let length):
            let dir = direction.normalized
            let end = center + dir * max(0, length)
            return distancePointToSegment(point, center, end) <= radius + pointRadius
        }
    }
}
