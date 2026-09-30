import Foundation

// 担当: core-skills
// アーキタイプ別の発動処理（DESIGN §6）。消費・検証は SkillSystem.cast 済みの前提。
// - 即時（扇形・自身中心・味方全体回復・対象指定ブリンク）はこの場で命中処理する。
// - 予告・着地・連撃は ZoneSystem、弾は ProjectileSystem に任せる（視界に関係なく当たり、構造物には当たらない）。
// - 突進/跳躍の着地 AoE は移動と同じ時間の予告ゾーンにし、着地した tick に発動させる。

enum SkillArchetypes {
    static func execute(_ s: inout SimState, _ ctx: SimContext, caster i: Int, check c: SkillCastCheck,
                        targeting t: SkillTargeting, numbers n: SkillNumbers, aim: SkillAim) {
        let k = Balance.Skills.self
        let origin = s.units[i].pos
        let visual = c.skill.effectID

        switch t.archetype {
        case .passive:
            return

        case .cone:
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: origin + aim.direction * t.range,
                     unit: aim.unit)
            hitArea(&s, ctx, caster: i, center: origin, radius: t.range,
                    shape: .cone(direction: aim.direction, halfAngle: k.coneHalfAngle),
                    payload: payload(c, damage: n.damage))

        case .lineSkillshot:
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: origin + aim.direction * t.range,
                     unit: aim.unit)
            ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: aim.direction, maxDistance: t.range),
                                   speed: k.skillshotSpeed, width: t.radius, pierce: false,
                                   payload: payload(c, damage: n.damage), visual: visual)

        case .piercingLine:
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: origin + aim.direction * t.range,
                     unit: aim.unit)
            ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: aim.direction, maxDistance: t.range),
                                   speed: k.piercingSpeed, width: t.radius, pierce: true,
                                   payload: payload(c, damage: n.damage), visual: visual)

        case .dashStrike:
            // 対象に向かう場合は対象の縁で止まる（着地 AoE の中心に対象を収める）
            var distance = aim.distance
            if let u = aim.unit { distance = min(t.range, max(0, aim.distance - s.units[u].radius)) }
            let landing = MovementSystem.dash(&s, ctx, unitIndex: i, to: origin + aim.direction * distance,
                                              speed: k.dashSpeed, kind: .dash)
            let duration = s.units[i].displacement?.duration ?? Balance.dt
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: landing, unit: aim.unit)
            ZoneSystem.spawn(&s, ownerIndex: i, center: landing, radius: t.radius, delay: duration,
                             payload: payload(c, damage: n.damage), visual: visual)

        case .blinkEmpower:
            let to = MovementSystem.blink(&s, ctx, unitIndex: i, to: origin + aim.direction * aim.distance)
            s.units[i].hero?.empoweredAttack = EmpoweredAttack(bonusDamage: n.damage, damageType: c.skill.damageType,
                                                               cc: c.skill.cc, remaining: k.empowerDuration,
                                                               visual: visual)
            // 次の通常攻撃をすぐ出せるようにする（攻撃間隔のリセット）
            s.units[i].attackCooldown = 0
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: to, unit: aim.unit)

        case .groundAoE:
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: aim.point, unit: aim.unit)
            ZoneSystem.spawn(&s, ownerIndex: i, center: aim.point, radius: t.radius, delay: n.delay,
                             payload: payload(c, damage: n.damage), visual: visual)

        case .selfAoE:
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: origin, unit: nil)
            hitArea(&s, ctx, caster: i, center: origin, radius: t.radius, shape: .circle,
                    payload: payload(c, damage: n.damage))
            CombatSystem.addShield(&s, ctx, sourceID: s.units[i].id, targetIndex: i, amount: n.shield,
                                   duration: n.shieldDuration, tag: "skill." + c.skill.skillID)

        case .healZone:
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: aim.point, unit: aim.unit)
            var p = payload(c, damage: n.damage)
            p.affectsAllies = true
            p.healAmount = n.heal
            ZoneSystem.spawn(&s, ownerIndex: i, center: aim.point, radius: t.radius, delay: n.delay,
                             payload: p, visual: visual)

        case .leapSlam:
            var distance = aim.distance
            if let u = aim.unit { distance = min(t.range, max(0, aim.distance - s.units[u].radius)) }
            let landing = MovementSystem.dash(&s, ctx, unitIndex: i, to: origin + aim.direction * distance,
                                              speed: k.leapSpeed, kind: .leap)
            let duration = s.units[i].displacement?.duration ?? Balance.dt
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: landing, unit: aim.unit)
            ZoneSystem.spawn(&s, ownerIndex: i, center: landing, radius: t.radius, delay: duration,
                             payload: payload(c, damage: n.damage), visual: visual)

        case .multiStrike:
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: aim.unit.map { s.units[$0].pos } ?? origin,
                     unit: aim.unit)
            // 0 / 0.3 / 0.6 秒の 3 連撃（術者に追従）。CC は初撃のみ
            let count = max(1, k.multiStrikeCount)
            let interval = count > 1 ? k.multiStrikeDuration / Double(count - 1) : 0
            for strike in 0..<count {
                var p = payload(c, damage: n.damage, heroesOnly: true)
                if strike > 0 { p.cc = .none }
                ZoneSystem.spawn(&s, ownerIndex: i, center: origin, radius: t.radius, delay: interval * Double(strike),
                                 followsOwner: true, payload: p, visual: visual)
            }
            CombatSystem.addStatus(&s, targetIndex: i,
                                   StatusEffect(kind: .damageReduction, duration: n.damageReductionDuration,
                                                magnitude: n.damageReduction, sourceID: s.units[i].id,
                                                tag: k.multiStrikeTag))

        case .teamHeal:
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: origin, unit: nil)
            teamHeal(&s, ctx, caster: i, check: c, targeting: t, numbers: n)

        case .targetedBlink:
            guard let u = aim.unit else { return }
            blinkBehind(&s, ctx, caster: i, target: u)
            emitCast(&s, caster: i, check: c, targeting: t, origin: origin, target: s.units[u].pos, unit: u)
            let missing = max(0, s.units[u].stats.maxHP - max(0, s.units[u].hp))
            let p = payload(c, damage: n.damage + missing * n.missingHealthRatio, heroesOnly: true)
            CombatSystem.applyHit(&s, ctx, sourceID: s.units[i].id, team: s.units[i].team, targetIndex: u,
                                  payload: p, from: s.units[i].pos)
        }
    }

    // MARK: - 部品

    /// スキルの命中内容（ダメージ種別・CC はスキル定義、Ult は強い CC）。
    static func payload(_ c: SkillCastCheck, damage: Double, heroesOnly: Bool = false) -> HitPayload {
        HitPayload(damage: damage, damageType: c.skill.damageType, source: .skill(c.slot), cc: c.skill.cc,
                   ccIsUltimate: c.slot == .ultimate, heroesOnly: heroesOnly, skillID: c.skill.skillID)
    }

    static func emitCast(_ s: inout SimState, caster i: Int, check c: SkillCastCheck, targeting t: SkillTargeting,
                         origin: Vec2, target: Vec2, unit: Int?) {
        s.emit(.skillCast(SkillCastEvent(casterID: s.units[i].id, heroID: c.def.heroID, slot: c.slot,
                                         skillID: c.skill.skillID, effectID: c.skill.effectID,
                                         archetype: t.archetype, origin: origin, target: target,
                                         targetUnitID: unit.map { s.units[$0].id }, range: t.range,
                                         radius: t.radius)))
    }

    /// 即時の範囲命中（扇形・円）。対象を先に確定してから添字昇順に適用する
    /// （命中中のノックバック・死亡で判定が変わらないように）。視界に関係なく当たり、構造物には当たらない。
    static func hitArea(_ s: inout SimState, _ ctx: SimContext, caster i: Int, center: Vec2, radius: Double,
                        shape: ZoneShape, payload: HitPayload) {
        let team = s.units[i].team
        var targets: [Int] = []
        for j in s.units.indices where s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j) else { continue }
            if payload.heroesOnly && s.units[j].kind != .hero { continue }
            guard ZoneSystem.contains(shape: shape, center: center, radius: radius, point: s.units[j].pos,
                                      pointRadius: s.units[j].radius) else { continue }
            targets.append(j)
        }
        guard !targets.isEmpty else { return }
        let casterID = s.units[i].id
        for j in targets {
            CombatSystem.applyHit(&s, ctx, sourceID: casterID, team: team, targetIndex: j, payload: payload,
                                  from: center)
        }
    }

    /// 味方全体回復: 1500 以内の味方ヒーロー（自身含む）を回復 + シールド、効果半径内の敵に CC。
    static func teamHeal(_ s: inout SimState, _ ctx: SimContext, caster i: Int, check c: SkillCastCheck,
                         targeting t: SkillTargeting, numbers n: SkillNumbers) {
        let team = s.units[i].team
        let center = s.units[i].pos
        let casterID = s.units[i].id
        let tag = "skill." + c.skill.skillID
        for j in s.units.indices where s.units[j].kind == .hero && s.units[j].team == team {
            guard CombatSystem.isLiving(s, j) else { continue }
            let r = t.range + s.units[j].radius
            guard s.units[j].pos.distanceSquared(to: center) <= r * r else { continue }
            CombatSystem.heal(&s, ctx, sourceID: casterID, targetIndex: j, amount: n.heal)
            CombatSystem.addShield(&s, ctx, sourceID: casterID, targetIndex: j, amount: n.shield,
                                   duration: n.shieldDuration, tag: tag)
        }
        guard c.skill.cc != .none else { return }
        hitArea(&s, ctx, caster: i, center: center, radius: t.radius, shape: .circle,
                payload: payload(c, damage: 0))
    }

    /// 対象の背後（術者から見て奥）へ瞬間移動する。壁で塞がれていれば対象側の歩行可能点。戻り値 = 到達点。
    @discardableResult
    static func blinkBehind(_ s: inout SimState, _ ctx: SimContext, caster i: Int, target u: Int) -> Vec2 {
        let from = s.units[i].pos
        let tp = s.units[u].pos
        let r = s.units[i].radius
        var dir = (tp - from).normalized
        if dir == .zero { dir = Vec2.fromAngle(s.units[i].facing) }
        let gap = s.units[u].radius + r + Balance.Skills.targetedBlinkGap
        var to = ctx.nav.raycast(from: tp, to: tp + dir * gap, radius: r)
        if !ctx.nav.isWalkable(to, radius: r) { to = ctx.nav.nearestWalkable(to, radius: r) }
        s.units[i].pos = to
        s.units[i].prevPos = to
        s.units[i].displacement = nil
        s.units[i].windupRemaining = nil
        s.units[i].path.removeAll()
        let face = tp - to
        if face != .zero { s.units[i].facing = face.angle }
        s.emit(.blinked(unitID: s.units[i].id, from: from, to: to))
        return to
    }
}
