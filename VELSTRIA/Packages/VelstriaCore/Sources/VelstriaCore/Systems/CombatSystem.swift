import Foundation

// 担当: core-combat
// 現在は契約確認用の最小実装。docs/DESIGN.md §5 の完全な処理順・フック呼び出し・アシスト記録を実装すること。
// 公開 API のシグネチャは変更しないこと（他担当が呼び出す）。

public enum CombatSystem {

    // MARK: - ダメージ・回復・シールド・状態（他システムから呼ばれる公開 API）

    /// ダメージを適用する（DESIGN §5 の順序）。戻り値 = HP 減少量 + シールド吸収量。
    /// HP ≤ 0 になったら `s.pendingDeaths` に積む（報酬処理は DeathSystem）。
    @discardableResult
    public static func applyDamage(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, targetIndex t: Int,
                                   amount raw: Double, type: DamageType, source: DamageSource,
                                   isCrit: Bool = false) -> Double {
        guard t < s.units.count, s.units[t].isAlive, raw > 0 else { return 0 }
        if s.units[t].has(.invulnerable) || TowerSystem.isInvulnerable(s, ctx, index: t) { return 0 }

        var amount = raw
        if let a = s.index(of: sourceID) {
            let st = s.units[a].stats
            var bonus = st.damageBonus
            if source == .basicAttack { bonus += st.basicAttackDamageBonus }
            if source.isSkill { bonus += st.skillDamageBonus }
            if s.units[t].kind == .monster { bonus += st.monsterDamageBonus }
            amount *= max(0, 1 + bonus)
        }
        if s.units[t].isStructure {
            amount *= TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: t, sourceIndex: s.index(of: sourceID))
        }
        let target = s.units[t]
        switch type {
        case .physical: amount *= 100 / (100 + max(0, target.stats.armor))
        case .magic: amount *= 100 / (100 + max(0, target.stats.magicResist))
        case .trueDamage: break
        }
        amount *= 1 - min(Balance.maxDamageReduction, max(0, target.stats.damageReduction))

        var remaining = amount
        var absorbed: Double = 0
        for k in s.units[t].shields.indices where remaining > 0 {
            let take = min(remaining, s.units[t].shields[k].amount)
            s.units[t].shields[k].amount -= take
            remaining -= take
            absorbed += take
        }
        s.units[t].shields.removeAll { $0.amount <= 0.01 }
        s.units[t].hp -= remaining
        s.units[t].lastDamagedTime = s.time
        s.units[t].lastAttackerID = sourceID

        s.emit(.damage(DamageEvent(sourceID: sourceID, targetID: s.units[t].id, amount: amount, absorbed: absorbed,
                                   damageType: type, source: source, isCrit: isCrit, pos: s.units[t].pos)))

        if s.units[t].hp <= 0 {
            s.units[t].hp = 0
            s.units[t].isAlive = false
            s.units[t].deathTime = s.time
            s.pendingDeaths.append(PendingDeath(victimID: s.units[t].id, killerID: sourceID, time: s.time))
        }
        return amount
    }

    /// 回復。戻り値 = 実回復量。
    @discardableResult
    public static func heal(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, targetIndex t: Int,
                            amount: Double) -> Double {
        guard s.units[t].isAlive, amount > 0 else { return 0 }
        let before = s.units[t].hp
        s.units[t].hp = min(s.units[t].stats.maxHP, before + amount * s.units[t].stats.healingReceivedMultiplier)
        let healed = s.units[t].hp - before
        if healed > 0 { s.emit(.heal(targetID: s.units[t].id, sourceID: sourceID, amount: healed)) }
        return healed
    }

    public static func addShield(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, targetIndex t: Int,
                                 amount: Double, duration: Double, tag: String = "") {
        guard s.units[t].isAlive, amount > 0 else { return }
        if !tag.isEmpty { s.units[t].shields.removeAll { $0.tag == tag } }
        s.units[t].shields.append(Shield(amount: amount, duration: duration, sourceID: sourceID, tag: tag))
        s.emit(.shieldGained(targetID: s.units[t].id, sourceID: sourceID, amount: amount))
    }

    /// 状態効果を付与（同一 kind + tag は上書き）。
    public static func addStatus(_ s: inout SimState, targetIndex t: Int, _ effect: StatusEffect) {
        guard s.units[t].isAlive else { return }
        if let k = s.units[t].statuses.firstIndex(where: { $0.kind == effect.kind && $0.tag == effect.tag }) {
            s.units[t].statuses[k].remaining = max(s.units[t].statuses[k].remaining, effect.remaining)
            s.units[t].statuses[k].magnitude = max(s.units[t].statuses[k].magnitude, effect.magnitude)
        } else {
            s.units[t].statuses.append(effect)
        }
        s.emit(.statusApplied(targetID: s.units[t].id, kind: effect.kind, duration: effect.remaining))
    }

    /// マスター定義の CC を適用（DESIGN §5 の値）。from = ノックバックの起点。
    public static func applyCC(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, targetIndex t: Int,
                               cc: CrowdControl, isUltimate: Bool, from: Vec2) {
        guard cc != .none, s.units[t].isAlive, !s.units[t].isStructure, !s.units[t].has(.ccImmune) else { return }
        switch cc {
        case .none:
            return
        case .slow:
            let d = isUltimate ? Balance.ultSlowDuration : Balance.slowDuration
            addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: d,
                                                        magnitude: isUltimate ? Balance.ultSlowPct : Balance.slowPct,
                                                        sourceID: sourceID))
            s.emit(.ccApplied(targetID: s.units[t].id, cc: cc, duration: d))
        case .root:
            let d = isUltimate ? Balance.ultRootDuration : Balance.rootDuration
            addStatus(&s, targetIndex: t, StatusEffect(kind: .root, duration: d, sourceID: sourceID))
            s.emit(.ccApplied(targetID: s.units[t].id, cc: cc, duration: d))
        case .stun:
            let d = isUltimate ? Balance.ultStunDuration : Balance.stunDuration
            addStatus(&s, targetIndex: t, StatusEffect(kind: .stun, duration: d, sourceID: sourceID))
            s.emit(.ccApplied(targetID: s.units[t].id, cc: cc, duration: d))
        case .knockback:
            let dir = (s.units[t].pos - from).normalized
            let push = dir == .zero ? Vec2(1, 0) : dir
            MovementSystem.knockback(&s, ctx, unitIndex: t, direction: push, distance: Balance.knockbackDistance,
                                     duration: Balance.knockbackTime)
            addStatus(&s, targetIndex: t, StatusEffect(kind: .stun, duration: Balance.knockbackTime + Balance.knockbackStun,
                                                        sourceID: sourceID))
            s.emit(.ccApplied(targetID: s.units[t].id, cc: cc, duration: Balance.knockbackTime + Balance.knockbackStun))
        }
    }

    /// HitPayload を 1 体に適用（投射物・ゾーン・即時スキル共通）。
    public static func applyHit(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, team: Team,
                                targetIndex t: Int, payload: HitPayload, from: Vec2) {
        guard s.units[t].isAlive else { return }
        if s.units[t].team == team {
            guard payload.affectsAllies else { return }
            if payload.healAmount > 0 { heal(&s, ctx, sourceID: sourceID, targetIndex: t, amount: payload.healAmount) }
            if payload.shieldAmount > 0 {
                addShield(&s, ctx, sourceID: sourceID, targetIndex: t, amount: payload.shieldAmount,
                          duration: payload.shieldDuration)
            }
            return
        }
        guard payload.affectsEnemies else { return }
        if payload.heroesOnly && s.units[t].kind != .hero { return }
        if payload.damage > 0 {
            applyDamage(&s, ctx, sourceID: sourceID, targetIndex: t, amount: payload.damage,
                        type: payload.damageType, source: payload.source, isCrit: payload.isCrit)
        }
        applyCC(&s, ctx, sourceID: sourceID, targetIndex: t, cc: payload.cc, isUltimate: payload.ccIsUltimate, from: from)
        for st in payload.statuses { addStatus(&s, targetIndex: t, st) }
    }

    // MARK: - 通常攻撃

    /// attackTargetID を持つ全ユニットの通常攻撃（前隙 → 命中/発射 → 間隔）を進める。
    public static func updateAttacks(_ s: inout SimState, _ ctx: SimContext) {
        for i in s.units.indices {
            if s.units[i].attackCooldown > 0 { s.units[i].attackCooldown -= Balance.dt }
            guard s.units[i].isAlive, let tid = s.units[i].attackTargetID else { continue }
            guard let t = s.index(of: tid), s.isTargetableEnemy(t, of: s.units[i].team) else {
                s.units[i].attackTargetID = nil
                s.units[i].windupRemaining = nil
                continue
            }
            guard s.units[i].canAct else { s.units[i].windupRemaining = nil; continue }
            let reach = s.units[i].stats.attackRange + s.units[i].radius + s.units[t].radius
            let dist = s.units[i].pos.distance(to: s.units[t].pos)

            if var w = s.units[i].windupRemaining {
                w -= Balance.dt
                if w <= 0 {
                    s.units[i].windupRemaining = nil
                    releaseAttack(&s, ctx, attacker: i, target: t)
                } else {
                    s.units[i].windupRemaining = w
                }
                continue
            }
            if dist > reach {
                if s.units[i].kind == .hero || s.units[i].kind == .minion {
                    s.units[i].moveIntent = .follow(targetID: tid, range: s.units[i].stats.attackRange)
                }
                continue
            }
            if s.units[i].attackCooldown <= 0 {
                let interval = 1 / max(0.1, s.units[i].stats.attackSpeed)
                s.units[i].attackCooldown = interval
                s.units[i].windupRemaining = interval * Balance.attackWindupRatio
                s.units[i].facing = (s.units[t].pos - s.units[i].pos).angle
                s.emit(.attackStarted(sourceID: s.units[i].id, targetID: tid))
            }
        }
    }

    static func releaseAttack(_ s: inout SimState, _ ctx: SimContext, attacker i: Int, target t: Int) {
        let u = s.units[i]
        let ranged: Bool
        switch u.kind {
        case .hero: ranged = u.hero?.isRanged ?? false
        case .minion: ranged = u.minion?.type != .melee
        case .tower, .core: ranged = true
        default: ranged = false
        }
        let source: DamageSource
        switch u.kind {
        case .hero: source = .basicAttack
        case .tower, .core: source = .tower
        case .minion: source = .minion
        default: source = .monster
        }
        let damage = u.isStructure ? TowerSystem.attackDamage(&s, ctx, towerIndex: i, targetIndex: t) : u.stats.attack
        let payload = HitPayload(damage: damage, damageType: .physical, source: source, appliesOnHit: u.kind == .hero)
        s.emit(.attackReleased(sourceID: u.id, targetID: s.units[t].id, isRanged: ranged))
        if ranged {
            let speed = u.isStructure ? 1400 : (u.kind == .hero ? Balance.heroProjectileSpeed : 1100)
            ProjectileSystem.spawn(&s, ownerIndex: i, motion: .homing(targetID: s.units[t].id), speed: speed,
                                   payload: payload, visual: u.isStructure ? "tower_shot" : "basic_attack")
        } else {
            applyHit(&s, ctx, sourceID: u.id, team: u.team, targetIndex: t, payload: payload, from: u.pos)
        }
    }

    /// 攻撃ボタン用の対象選択（射程 + 300 以内）。
    public static func selectTarget(_ s: inout SimState, _ ctx: SimContext, attacker i: Int,
                                    priority: TargetPriority) -> Int? {
        let u = s.units[i]
        let candidates = s.enemies(of: u.team, near: u.pos, radius: u.stats.attackRange + u.radius + 300)
        guard !candidates.isEmpty else { return nil }
        let heroes = candidates.filter { s.units[$0].kind == .hero }
        switch priority {
        case .heroesFirst:
            return s.nearest(heroes, to: u.pos) ?? s.nearest(candidates, to: u.pos)
        case .minionsFirst:
            let mins = candidates.filter { s.units[$0].kind == .minion || s.units[$0].kind == .monster }
            return mins.min { s.units[$0].hp < s.units[$1].hp } ?? s.nearest(candidates, to: u.pos)
        case .structuresFirst:
            let st = candidates.filter { s.units[$0].isStructure }
            return s.nearest(st, to: u.pos) ?? s.nearest(candidates, to: u.pos)
        case .lowestHealth:
            return candidates.min { s.units[$0].hpRatio < s.units[$1].hpRatio }
        }
    }
}
