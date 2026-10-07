import Foundation

// 担当: core-combat
// DESIGN §5 の戦闘計算・回復/シールド・状態効果/CC・通常攻撃・攻撃ボタンの対象選択。
// 公開 API のシグネチャは変更しないこと（他担当が呼び出す）。

public enum CombatSystem {

    // MARK: - ステータスのタグ（同一 kind + tag は上書き）

    static let tagSlow = "cc.slow"
    static let tagUltSlow = "cc.slow.ult"
    static let tagRoot = "cc.root"
    static let tagStun = "cc.stun"
    static let tagKnockback = "cc.knockback"
    static let tagRedBuff = "redBuff"

    /// これ以下の HP は 0 とみなす（浮動小数の端数で 1e-9 だけ生き残るのを防ぐ）。
    static let deathEpsilon = 1e-6
    static let timeEpsilon = 1e-9

    // MARK: - ダメージ

    /// ダメージを適用する（DESIGN §5 の順序）。戻り値 = HP 減少量 + シールド吸収量。
    /// HP ≤ 0 になったら `s.pendingDeaths` に積む（報酬処理は DeathSystem）。
    @discardableResult
    public static func applyDamage(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, targetIndex t: Int,
                                   amount raw: Double, type: DamageType, source: DamageSource,
                                   isCrit: Bool = false) -> Double {
        dealDamage(&s, ctx, sourceID: sourceID, targetIndex: t, amount: raw, type: type, source: source,
                   isCrit: isCrit, appliesOnHit: source == .basicAttack)
    }

    /// applyDamage の本体。appliesOnHit = 通常攻撃のライフスティールを適用するか（HitPayload.appliesOnHit）。
    @discardableResult
    static func dealDamage(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, targetIndex t: Int,
                           amount raw: Double, type: DamageType, source: DamageSource, isCrit: Bool,
                           appliesOnHit: Bool) -> Double {
        guard s.units.indices.contains(t), isLiving(s, t), raw > 0, raw.isFinite else { return 0 }
        // 1. 無敵
        if isInvulnerable(s, ctx, t) { return 0 }

        let a = s.index(of: sourceID)
        // 泉は環境ダメージ: 与ダメ補正・被ダメ軽減の対象外
        let environmental = source == .fountain
        var amount = raw

        // 3. 与ダメ補正（加算合計、負にはしない）
        if let a, !environmental {
            let st = s.units[a].stats
            var bonus = st.damageBonus
            switch source {
            case .basicAttack: bonus += st.basicAttackDamageBonus
            case .skill: bonus += st.skillDamageBonus
            default: break
            }
            if s.units[t].kind == .monster { bonus += st.monsterDamageBonus }
            bonus += PassiveHooks.outgoingDamageBonus(&s, ctx, attacker: a, target: t, source: source)
            amount *= max(0, 1 + bonus)
        }
        // 構造物: 序盤保護・裏取り保護・攻城補正（core-world）
        if s.units[t].isStructure {
            amount *= max(0, TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: t, sourceIndex: a))
        }
        // 4. 防御軽減（確定ダメージは無視）
        amount *= mitigationMultiplier(type, armor: s.units[t].stats.armor, magicResist: s.units[t].stats.magicResist)
        // 5. 被ダメ軽減（上限 60%）
        if !environmental { amount *= damageReductionMultiplier(s.units[t].stats.damageReduction) }
        guard amount > 0, amount.isFinite else { return 0 }

        // 6. シールド（古いものから）→ HP
        var remaining = amount
        var absorbed = 0.0
        var turretShieldAbsorbed = 0.0
        if !s.units[t].shields.isEmpty {
            for k in s.units[t].shields.indices where remaining > 0 {
                let take = min(remaining, max(0, s.units[t].shields[k].amount))
                s.units[t].shields[k].amount -= take
                remaining -= take
                absorbed += take
                if s.units[t].shields[k].tag == TowerSystem.shieldTag { turretShieldAbsorbed += take }
            }
            s.units[t].shields.removeAll { $0.amount <= deathEpsilon }
        }
        // 外塔のシールドを削ったヒーローは、削ったダメージ 10 につき 0.8 Gold を得る（参照仕様 §3.1）
        if turretShieldAbsorbed > 0, let a, s.units[a].kind == .hero, s.units[a].team != s.units[t].team {
            EconomyRewards.grantGold(&s, heroIndex: a,
                                     amount: turretShieldAbsorbed / 10 * Balance.outerTowerShieldGoldPer10,
                                     at: s.units[t].pos, visible: false)
        }
        let hpBefore = max(0, s.units[t].hp)
        let hpLoss = min(hpBefore, remaining)
        s.units[t].hp = hpBefore - hpLoss
        let dealt = absorbed + hpLoss

        let victimTeam = s.units[t].team
        let victimKind = s.units[t].kind
        s.units[t].lastDamagedTime = s.time
        if let sourceID { s.units[t].lastAttackerID = sourceID }

        // 交戦時刻・アシスト・スコア
        let hostile = a.map { s.units[$0].team != victimTeam } ?? true
        if let a, hostile {
            let attackerKind = s.units[a].kind
            if victimKind == .hero && (attackerKind == .hero || attackerKind == .tower || attackerKind == .core) {
                s.units[a].lastCombatTime = s.time
                s.units[t].lastCombatTime = s.time
            }
            if attackerKind == .hero {
                recordDamager(&s, attacker: a, victim: t)
                if victimKind == .hero {
                    s.units[a].hero?.score.damageToHeroes += dealt
                } else if victimKind == .tower || victimKind == .core {
                    s.units[a].hero?.score.towerDamage += dealt
                }
            }
        }
        if victimKind == .hero { s.units[t].hero?.score.damageTaken += dealt }

        s.emit(.damage(DamageEvent(sourceID: sourceID, targetID: s.units[t].id, amount: dealt, absorbed: absorbed,
                                   damageType: type, source: source, isCrit: isCrit, pos: s.units[t].pos)))

        // 敵からの被ダメで詠唱（帰還・帰還門）を中断
        if victimKind == .hero, hostile, s.units[t].hero?.channel != nil {
            RecallSystem.cancelChannel(&s, t)
        }

        // 報復（BS15）: 受けたダメージの一部を攻撃者へ確定ダメージで反射する（反射ダメージは .passive で、再反射しない）
        if dealt > 0, hostile, let a, a != t, !s.units[a].isStructure, reflectsDamage(source),
           s.units[t].statuses.contains(where: { $0.kind == .damageReduction && $0.tag == Balance.Spells.vengeanceTag }) {
            dealDamage(&s, ctx, sourceID: s.units[t].id, targetIndex: a, amount: dealt * Balance.Spells.vengeanceReflect,
                       type: .trueDamage, source: .passive, isCrit: false, appliesOnHit: false)
        }

        // 7. ライフスティール（通常攻撃）/ スペルヴァンプ（スキル）
        if let a, dealt > 0, !environmental {
            let ratio: Double
            if source == .basicAttack && appliesOnHit {
                ratio = s.units[a].stats.lifesteal
            } else if source.isSkill {
                ratio = s.units[a].stats.spellVamp
            } else {
                ratio = 0
            }
            if ratio > 0 {
                restoreHealth(&s, ctx, sourceID: sourceID, targetIndex: a, amount: dealt * ratio, isVamp: true)
            }
        }

        // 8. 死亡（キル・アシスト判定は DeathSystem で一括）
        if s.units[t].hp <= deathEpsilon { commitDeath(&s, t, killerID: sourceID) }

        // パッシブのフック（被害者が死亡している場合もある）
        if victimKind == .hero {
            PassiveHooks.onDamageTaken(&s, ctx, victim: t, attacker: a, amount: dealt)
        }
        if case .skill(let slot) = source, let a {
            PassiveHooks.onSkillHit(&s, ctx, attacker: a, target: t, slot: slot, damage: dealt)
        }
        return dealt
    }

    /// 報復で反射できるダメージ源か（継続・泉・パッシブ由来は反射しない）。
    static func reflectsDamage(_ source: DamageSource) -> Bool {
        switch source {
        case .dot, .fountain, .passive: return false
        default: return true
        }
    }

    /// 死亡を確定し pendingDeaths に 1 回だけ積む。
    static func commitDeath(_ s: inout SimState, _ t: Int, killerID: EntityID?) {
        guard s.units[t].isAlive else { return }
        s.units[t].hp = 0
        s.units[t].isAlive = false
        s.units[t].deathTime = s.time
        s.units[t].windupRemaining = nil
        s.units[t].displacement = nil
        s.units[t].path.removeAll()
        let id = s.units[t].id
        if !s.pendingDeaths.contains(where: { $0.victimID == id }) {
            s.pendingDeaths.append(PendingDeath(victimID: id, killerID: killerID, time: s.time))
        }
    }

    /// 防御軽減の倍率（物理 = 100/(100+防御)、魔法 = 100/(100+魔防)、確定 = 1）。
    public static func mitigationMultiplier(_ type: DamageType, armor: Double, magicResist: Double) -> Double {
        switch type {
        case .physical: return 100 / (100 + max(0, armor))
        case .magic: return 100 / (100 + max(0, magicResist))
        case .trueDamage: return 1
        }
    }

    /// 被ダメ軽減の倍率 1 − min(0.6, damageReduction)。
    public static func damageReductionMultiplier(_ damageReduction: Double) -> Double {
        1 - min(Balance.maxDamageReduction, max(0, damageReduction))
    }

    /// 無敵状態か（Invulnerable ステータス、または保護中の構造物）。
    public static func isInvulnerable(_ s: SimState, _ ctx: SimContext, _ t: Int) -> Bool {
        if s.units[t].has(.invulnerable) { return true }
        return s.units[t].isStructure && TowerSystem.isInvulnerable(s, ctx, index: t)
    }

    /// 生存中か（死亡中のヒーローを除く）。
    @inline(__always)
    static func isLiving(_ s: SimState, _ i: Int) -> Bool {
        s.units[i].isAlive && (s.units[i].hero?.respawnTimer ?? 0) <= 0
    }

    /// 戦闘中か（DESIGN §4: 直近 5 秒以内に敵ヒーロー/タワーと交戦）。
    public static func isInCombat(_ s: SimState, _ i: Int) -> Bool {
        s.time - s.units[i].lastCombatTime <= Balance.combatTimeout
    }

    // MARK: - 回復・シールド

    /// 回復。戻り値 = 実回復量。
    @discardableResult
    public static func heal(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, targetIndex t: Int,
                            amount: Double) -> Double {
        restoreHealth(&s, ctx, sourceID: sourceID, targetIndex: t, amount: amount, isVamp: false)
    }

    /// 回復の本体。isVamp = ライフスティール/スペルヴァンプ（回復強化・回復量スコア・アシスト記録の対象外）。
    @discardableResult
    static func restoreHealth(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, targetIndex t: Int,
                              amount: Double, isVamp: Bool) -> Double {
        guard s.units.indices.contains(t), isLiving(s, t), amount > 0, amount.isFinite else { return 0 }
        let src = s.index(of: sourceID)
        var value = amount
        if !isVamp, let src { value *= max(0, 1 + s.units[src].stats.healShieldPower) }
        value *= max(0, s.units[t].stats.healingReceivedMultiplier)
        let before = s.units[t].hp
        let after = min(s.units[t].stats.maxHP, before + value)
        let healed = after - before
        guard healed > 0 else { return 0 }
        s.units[t].hp = after
        s.emit(.heal(targetID: s.units[t].id, sourceID: sourceID, amount: healed))
        if !isVamp, let src, s.units[src].kind == .hero {
            s.units[src].hero?.score.healingDone += healed
            recordSupporter(&s, supporter: src, target: t)
        }
        return healed
    }

    /// シールド付与（古いものから消費される）。tag が空でなければ同じ tag のシールドを置き換える。
    public static func addShield(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, targetIndex t: Int,
                                 amount: Double, duration: Double, tag: String = "") {
        guard s.units.indices.contains(t), isLiving(s, t), amount > 0, amount.isFinite else { return }
        let src = s.index(of: sourceID)
        var value = amount
        if let src { value *= max(0, 1 + s.units[src].stats.healShieldPower) }
        guard value > 0 else { return }
        let d = duration > 0 ? duration : Balance.combatDefaultShieldDuration
        if !tag.isEmpty { s.units[t].shields.removeAll { $0.tag == tag } }
        s.units[t].shields.append(Shield(amount: value, duration: d, sourceID: sourceID, tag: tag))
        s.emit(.shieldGained(targetID: s.units[t].id, sourceID: sourceID, amount: value))
        if let src, s.units[src].kind == .hero {
            s.units[src].hero?.score.shieldingDone += value
            recordSupporter(&s, supporter: src, target: t)
        }
    }

    // MARK: - アシスト記録

    /// 敵ヒーローからのダメージ/CC を被害者ヒーローに記録する（発生源毎に 1 件、time 昇順）。
    static func recordDamager(_ s: inout SimState, attacker a: Int, victim t: Int) {
        guard s.units[a].kind == .hero, s.units[t].kind == .hero, s.units[t].hero != nil,
              s.units[a].team != s.units[t].team else { return }
        refreshRecord(&s.units[t].hero!.recentDamagers, sourceID: s.units[a].id, time: s.time)
    }

    /// 味方ヒーローからの回復/シールドを記録する。
    static func recordSupporter(_ s: inout SimState, supporter src: Int, target t: Int) {
        guard src != t, s.units[t].kind == .hero, s.units[t].hero != nil,
              s.units[src].team == s.units[t].team else { return }
        refreshRecord(&s.units[t].hero!.recentSupporters, sourceID: s.units[src].id, time: s.time)
    }

    static func refreshRecord(_ records: inout [DamageRecord], sourceID: EntityID, time: Double) {
        let cutoff = time - Balance.assistWindow
        records.removeAll { $0.sourceID == sourceID || $0.time < cutoff }
        records.append(DamageRecord(sourceID: sourceID, time: time))
    }

    /// アシスト窓（10 秒）より古い記録を捨てる。
    static func pruneAssistRecords(_ s: inout SimState, _ i: Int) {
        guard s.units[i].hero != nil else { return }
        let cutoff = s.time - Balance.assistWindow
        if let first = s.units[i].hero!.recentDamagers.first, first.time < cutoff {
            s.units[i].hero!.recentDamagers.removeAll { $0.time < cutoff }
        }
        if let first = s.units[i].hero!.recentSupporters.first, first.time < cutoff {
            s.units[i].hero!.recentSupporters.removeAll { $0.time < cutoff }
        }
    }

    /// アシスト記録をすべて捨てる（死亡処理が済んだヒーロー用）。
    static func clearAssistRecords(_ s: inout SimState, _ i: Int) {
        guard s.units[i].hero != nil else { return }
        if !s.units[i].hero!.recentDamagers.isEmpty { s.units[i].hero!.recentDamagers.removeAll() }
        if !s.units[i].hero!.recentSupporters.isEmpty { s.units[i].hero!.recentSupporters.removeAll() }
    }

    // MARK: - 状態効果・CC

    /// 状態効果を付与（同一 kind + tag は重ねず、残り時間・強さはそれぞれ大きい方）。
    /// CC 無効中・構造物には行動阻害を、無敵・構造物には弱体を付与しない。
    public static func addStatus(_ s: inout SimState, targetIndex t: Int, _ effect: StatusEffect) {
        guard s.units.indices.contains(t), isLiving(s, t), effect.remaining > 0 else { return }
        let kind = effect.kind
        if kind.combatIsHarmful && (s.units[t].isStructure || s.units[t].has(.invulnerable)) { return }
        if kind.combatIsCrowdControl && s.units[t].has(.ccImmune) { return }

        if let k = s.units[t].statuses.firstIndex(where: { $0.kind == kind && $0.tag == effect.tag }) {
            var cur = s.units[t].statuses[k]
            // 付与元は効果を延長した側（燃焼のダメージ帰属）
            if effect.remaining >= cur.remaining, let src = effect.sourceID { cur.sourceID = src }
            cur.remaining = max(cur.remaining, effect.remaining)
            cur.duration = max(cur.duration, effect.duration)
            cur.magnitude = max(cur.magnitude, effect.magnitude)
            s.units[t].statuses[k] = cur
        } else {
            s.units[t].statuses.append(effect)
        }
        s.emit(.statusApplied(targetID: s.units[t].id, kind: kind, duration: effect.remaining))

        guard kind.combatIsHarmful else { return }
        let src = s.index(of: effect.sourceID)
        let hostile = src.map { s.units[$0].team != s.units[t].team } ?? true
        if hostile, let src { recordDamager(&s, attacker: src, victim: t) }
        // 行動不能 CC は前隙と詠唱を中断する
        if kind.preventsActions {
            s.units[t].windupRemaining = nil
            if hostile, s.units[t].hero?.channel != nil { RecallSystem.cancelChannel(&s, t) }
        }
    }

    /// マスター定義の CC を適用（DESIGN §5 の値）。from = ノックバックの起点。
    public static func applyCC(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, targetIndex t: Int,
                               cc: CrowdControl, isUltimate: Bool, from: Vec2) {
        guard cc != .none, s.units.indices.contains(t), isLiving(s, t), !s.units[t].isStructure,
              !s.units[t].has(.ccImmune), !isInvulnerable(s, ctx, t) else { return }
        let duration: Double
        switch cc {
        case .none:
            return
        case .slow:
            duration = isUltimate ? Balance.ultSlowDuration : Balance.slowDuration
            addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: duration,
                                                        magnitude: isUltimate ? Balance.ultSlowPct : Balance.slowPct,
                                                        sourceID: sourceID, tag: isUltimate ? tagUltSlow : tagSlow))
        case .root:
            duration = isUltimate ? Balance.ultRootDuration : Balance.rootDuration
            addStatus(&s, targetIndex: t, StatusEffect(kind: .root, duration: duration, sourceID: sourceID, tag: tagRoot))
        case .stun:
            duration = isUltimate ? Balance.ultStunDuration : Balance.stunDuration
            addStatus(&s, targetIndex: t, StatusEffect(kind: .stun, duration: duration, sourceID: sourceID, tag: tagStun))
        case .knockback:
            // 押し出し（knockbackTime）+ 着地後の短いスタン（knockbackStun）
            duration = Balance.knockbackTime + Balance.knockbackStun
            var dir = (s.units[t].pos - from).normalized
            if dir == .zero {
                if let a = s.index(of: sourceID) { dir = Vec2.fromAngle(s.units[a].facing) } else { dir = Vec2(1, 0) }
            }
            MovementSystem.knockback(&s, ctx, unitIndex: t, direction: dir, distance: Balance.knockbackDistance,
                                     duration: Balance.knockbackTime)
            addStatus(&s, targetIndex: t, StatusEffect(kind: .airborne, duration: Balance.knockbackTime,
                                                        sourceID: sourceID, tag: tagKnockback))
            addStatus(&s, targetIndex: t, StatusEffect(kind: .stun, duration: duration, sourceID: sourceID,
                                                        tag: tagKnockback))
        }
        s.emit(.ccApplied(targetID: s.units[t].id, cc: cc, duration: duration))
    }

    /// 浄化: 解除可能な弱体（isCleansable）をすべて外す。
    public static func cleanse(_ s: inout SimState, targetIndex t: Int) {
        guard s.units.indices.contains(t) else { return }
        s.units[t].statuses.removeAll { $0.kind.isCleansable }
    }

    // MARK: - 命中

    /// HitPayload を 1 体に適用（投射物・ゾーン・即時ヒット共通）。
    /// 味方には回復・シールド・強化、敵にはダメージ・CC・弱体。通常攻撃（source = .basicAttack かつ appliesOnHit）は
    /// 命中時効果（紅焔バフ・命中数・パッシブ）も処理する。
    public static func applyHit(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, team: Team,
                                targetIndex t: Int, payload: HitPayload, from: Vec2) {
        guard s.units.indices.contains(t), isLiving(s, t) else { return }
        if payload.heroesOnly && s.units[t].kind != .hero { return }

        if s.units[t].team == team {
            guard payload.affectsAllies else { return }
            if payload.healAmount > 0 {
                heal(&s, ctx, sourceID: sourceID, targetIndex: t, amount: payload.healAmount)
            }
            if payload.shieldAmount > 0 {
                addShield(&s, ctx, sourceID: sourceID, targetIndex: t, amount: payload.shieldAmount,
                          duration: payload.shieldDuration, tag: payload.skillID.map { "skill." + $0 } ?? "")
            }
            for st in payload.statuses where st.kind.combatIsBeneficial {
                addStatus(&s, targetIndex: t, withSource(st, sourceID))
            }
            return
        }

        guard payload.affectsEnemies, !isInvulnerable(s, ctx, t) else { return }
        var dealt = 0.0
        if payload.damage > 0 {
            dealt = dealDamage(&s, ctx, sourceID: sourceID, targetIndex: t, amount: payload.damage,
                               type: payload.damageType, source: payload.source, isCrit: payload.isCrit,
                               appliesOnHit: payload.appliesOnHit)
        }
        if isLiving(s, t) {
            if payload.cc != .none {
                applyCC(&s, ctx, sourceID: sourceID, targetIndex: t, cc: payload.cc,
                        isUltimate: payload.ccIsUltimate, from: from)
            }
            for st in payload.statuses where !st.kind.combatIsBeneficial {
                addStatus(&s, targetIndex: t, withSource(st, sourceID))
            }
        }
        guard let a = s.index(of: sourceID) else { return }
        if payload.source == .basicAttack && payload.appliesOnHit {
            basicAttackLanded(&s, ctx, attacker: a, target: t, dealt: dealt)
        } else if payload.damage <= 0, case .skill(let slot) = payload.source {
            // ダメージの無いスキル（CC のみ）も命中として通知する
            PassiveHooks.onSkillHit(&s, ctx, attacker: a, target: t, slot: slot, damage: 0)
        }
    }

    static func withSource(_ st: StatusEffect, _ sourceID: EntityID?) -> StatusEffect {
        guard st.sourceID == nil else { return st }
        var e = st
        e.sourceID = sourceID
        return e
    }

    /// ヒーローの通常攻撃が命中した時の効果（紅焔バフ・命中数・パッシブ）。
    static func basicAttackLanded(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int,
                                  dealt: Double) {
        if s.units[a].has(.redBuff), isLiving(s, t), !s.units[t].isStructure {
            let level = Double(s.units[a].hero?.level ?? 1)
            let total = Balance.combatRedBuffBurnBase + Balance.combatRedBuffBurnPerLevel * level
            let attackerID = s.units[a].id
            addStatus(&s, targetIndex: t, StatusEffect(kind: .burn, duration: Balance.combatRedBuffBurnDuration,
                                                        magnitude: total / Balance.combatRedBuffBurnDuration,
                                                        sourceID: attackerID, tag: tagRedBuff))
            addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: Balance.combatRedBuffSlowDuration,
                                                        magnitude: Balance.combatRedBuffSlowPct,
                                                        sourceID: attackerID, tag: tagRedBuff))
        }
        if s.units[a].hero != nil { s.units[a].hero!.basicAttackCount += 1 }
        PassiveHooks.onBasicAttackHit(&s, ctx, attacker: a, target: t, damage: dealt)
    }

    // MARK: - 通常攻撃

    /// 攻撃間隔（秒）。
    public static func attackInterval(_ stats: Stats) -> Double {
        1 / max(0.1, stats.attackSpeed)
    }

    /// 通常攻撃を弾で撃つか（遠隔ヒーロー・遠隔/攻城ミニオン・構造物）。
    public static func isRangedAttacker(_ u: Unit) -> Bool {
        switch u.kind {
        case .hero: return u.hero?.isRanged ?? false
        case .minion: return u.minion.map { $0.type != .melee } ?? false
        case .tower, .core: return true
        default: return false
        }
    }

    /// attackTargetID を持つ全ユニットの通常攻撃（前隙 → 命中/発射 → 間隔）を進める。
    /// attackCooldown は「次の前隙を開始できるまでの秒」で、発射時に (間隔 − 前隙) を設定する。
    /// そのため前隙の取り消し（本関数・移動入力など）では攻撃は消費されない。
    public static func updateAttacks(_ s: inout SimState, _ ctx: SimContext) {
        for i in s.units.indices {
            if s.units[i].attackCooldown > 0 { s.units[i].attackCooldown -= Balance.dt }
            // 今 tick に 0 を跨いだ端数は次の前隙へ持ち越し、平均の攻撃間隔を正確に保つ
            let carry = min(0, s.units[i].attackCooldown)
            if s.units[i].attackCooldown < 0 { s.units[i].attackCooldown = 0 }
            stepAttacker(&s, ctx, i, carry: carry)
        }
    }

    static func stepAttacker(_ s: inout SimState, _ ctx: SimContext, _ i: Int, carry: Double) {
        guard isLiving(s, i), s.units[i].kind != .dummy, let tid = s.units[i].attackTargetID else {
            s.units[i].windupRemaining = nil
            return
        }
        let team = s.units[i].team
        guard let t = s.index(of: tid), s.isTargetableEnemy(t, of: team) else {
            // 対象の死亡・不可視化: 攻撃を消費せずに取り消す
            s.units[i].attackTargetID = nil
            s.units[i].windupRemaining = nil
            if case .follow(let fid, _) = s.units[i].moveIntent, fid == tid {
                s.units[i].moveIntent = .none
                s.units[i].path.removeAll()
            }
            return
        }
        // 行動不能・詠唱中は前隙を取り消す（攻撃は消費しない）
        if !s.units[i].canAct || s.units[i].hero?.channel != nil {
            s.units[i].windupRemaining = nil
            return
        }

        let range = s.units[i].stats.attackRange
        let reach = range + s.units[i].radius + s.units[t].radius
        let delta = s.units[t].pos - s.units[i].pos
        let dist = delta.length

        if let w = s.units[i].windupRemaining {
            if dist <= reach + Balance.combatWindupRangeLeeway {
                if dist > 1e-6 { s.units[i].facing = delta.angle }
                let nw = w - Balance.dt
                if nw <= timeEpsilon {
                    s.units[i].windupRemaining = nil
                    releaseAttack(&s, ctx, attacker: i, target: t, overshoot: max(0, -nw))
                } else {
                    s.units[i].windupRemaining = nw
                }
                return
            }
            // 対象が射程外へ出た: 攻撃を消費せずに取り消し、追跡へ
            s.units[i].windupRemaining = nil
        }

        if dist > reach {
            // 射程外: ヒーローとミニオンは追跡する（モンスター・構造物は各システムが移動を決める）
            if chasesAttackTarget(s.units[i].kind) {
                // 経路キャッシュは MovementSystem が目標とのずれで検証するため、ここでは消さない
                let intent = MoveIntent.follow(targetID: tid, range: chaseRange(range))
                if s.units[i].moveIntent != intent { s.units[i].moveIntent = intent }
            }
            return
        }

        // 射程内: 追跡をやめて対象を向く。ミニオンはレーン行進（.point）も止めて殴る。
        // ヒーローの地点移動とモンスターの帰還（リーシュ）は各システムの判断なのでここでは消さない
        switch s.units[i].moveIntent {
        case .follow:
            s.units[i].moveIntent = .none
            s.units[i].path.removeAll()
        case .point where s.units[i].kind == .minion:
            s.units[i].moveIntent = .none
            s.units[i].path.removeAll()
        default:
            break
        }
        if dist > 1e-6 { s.units[i].facing = delta.angle }
        guard s.units[i].attackCooldown <= timeEpsilon else { return }
        let interval = attackInterval(s.units[i].stats)
        s.units[i].windupRemaining = max(timeEpsilon * 2, interval * Balance.attackWindupRatio + carry)
        s.emit(.attackStarted(sourceID: s.units[i].id, targetID: tid))
    }

    /// 通常攻撃の対象を射程外から追跡する種別（モンスター・構造物は各システムが移動を決める）。
    static func chasesAttackTarget(_ kind: UnitKind) -> Bool { kind == .hero || kind == .minion }

    /// 追跡で止まる距離（射程境界での往復を防ぐため射程より少し内側）。
    static func chaseRange(_ attackRange: Double) -> Double {
        max(0, attackRange - Balance.combatFollowRangeMargin)
    }

    /// 移動意図が無いユニットの攻撃対象が射程外なら追跡の意図を返す（MovementSystem が使う）。
    /// 攻撃コマンドは発行の度に意図を .none に戻すため、同じ tick の移動で追跡を続けるのに必要。
    static func chaseIntent(_ s: SimState, _ i: Int) -> MoveIntent? {
        guard chasesAttackTarget(s.units[i].kind), let tid = s.units[i].attackTargetID,
              let t = s.index(of: tid), s.isTargetableEnemy(t, of: s.units[i].team) else { return nil }
        let range = s.units[i].stats.attackRange
        let reach = range + s.units[i].radius + s.units[t].radius
        guard s.units[i].pos.distanceSquared(to: s.units[t].pos) > reach * reach else { return nil }
        return .follow(targetID: tid, range: chaseRange(range))
    }

    /// 前隙完了: 近接は即命中、遠隔は追尾弾を発射する。overshoot = 前隙が 0 を超えて経過した端数。
    static func releaseAttack(_ s: inout SimState, _ ctx: SimContext, attacker i: Int, target t: Int,
                              overshoot: Double = 0) {
        let interval = attackInterval(s.units[i].stats)
        s.units[i].attackCooldown = interval * (1 - Balance.attackWindupRatio) - overshoot

        let attackerID = s.units[i].id
        let targetID = s.units[t].id
        let team = s.units[i].team
        let ranged = isRangedAttacker(s.units[i])
        var payload: HitPayload
        var bonus: (payload: HitPayload, visual: String)?

        switch s.units[i].kind {
        case .hero:
            var isCrit = false
            if let forced = PassiveHooks.forceCrit(&s, ctx, attacker: i) {
                isCrit = forced
            } else {
                let chance = s.units[i].stats.critChance
                if chance >= 1 {
                    isCrit = true
                } else if chance > 0 {
                    isCrit = s.rng.nextDouble() < chance
                }
            }
            let multiplier = isCrit ? max(1, s.units[i].stats.critMultiplier) : 1
            payload = HitPayload(damage: s.units[i].stats.attack * multiplier, damageType: .physical,
                                 source: .basicAttack, isCrit: isCrit, appliesOnHit: true)
            // 強化攻撃: 追加ダメージ（自身の種別）と CC を別インスタンスで与えて消費
            if let emp = s.units[i].hero?.empoweredAttack {
                s.units[i].hero?.empoweredAttack = nil
                let p = HitPayload(damage: emp.bonusDamage, damageType: emp.damageType, source: .basicAttack,
                                   cc: emp.cc, appliesOnHit: false)
                bonus = (p, emp.visual.isEmpty ? "empowered_attack" : emp.visual)
            }
        case .tower, .core:
            let damage = TowerSystem.attackDamage(&s, ctx, towerIndex: i, targetIndex: t)
            // 対ミニオンは最大 HP 割合（DESIGN §4）をそのまま削るため確定ダメージ
            let type: DamageType = s.units[t].kind == .minion ? .trueDamage : .physical
            payload = HitPayload(damage: damage, damageType: type, source: .tower)
        case .minion:
            payload = HitPayload(damage: s.units[i].stats.attack, damageType: .physical, source: .minion)
        case .monster:
            payload = HitPayload(damage: s.units[i].stats.attack, damageType: .physical, source: .monster)
        default:
            // 練習用の人形などは攻撃しない
            return
        }

        s.emit(.attackReleased(sourceID: attackerID, targetID: targetID, isRanged: ranged))
        if ranged {
            let speed: Double
            let visual: String
            switch s.units[i].kind {
            case .hero: speed = Balance.heroProjectileSpeed; visual = "basic_attack"
            case .tower, .core: speed = Balance.combatStructureProjectileSpeed; visual = "tower_shot"
            default: speed = Balance.combatMinionProjectileSpeed; visual = "basic_attack"
            }
            ProjectileSystem.spawn(&s, ownerIndex: i, motion: .homing(targetID: targetID), speed: speed,
                                   payload: payload, visual: visual)
            if let bonus {
                ProjectileSystem.spawn(&s, ownerIndex: i, motion: .homing(targetID: targetID), speed: speed,
                                       payload: bonus.payload, visual: bonus.visual)
            }
        } else {
            let from = s.units[i].pos
            applyHit(&s, ctx, sourceID: attackerID, team: team, targetIndex: t, payload: payload, from: from)
            if let bonus {
                applyHit(&s, ctx, sourceID: attackerID, team: team, targetIndex: t, payload: bonus.payload, from: from)
            }
        }
    }

    // MARK: - 対象選択

    /// 攻撃ボタン用の対象選択（射程 + 300 以内・視認中・無敵でない敵）。同条件は添字の小さい方。
    public static func selectTarget(_ s: inout SimState, _ ctx: SimContext, attacker i: Int,
                                    priority: TargetPriority) -> Int? {
        guard s.units.indices.contains(i), isLiving(s, i) else { return nil }
        let pos = s.units[i].pos
        let searchRadius = s.units[i].stats.attackRange + s.units[i].radius + Balance.combatTargetSearchBonus
        let candidates = s.enemies(of: s.units[i].team, near: pos, radius: searchRadius)
            .filter { !isInvulnerable(s, ctx, $0) }
        guard !candidates.isEmpty else { return nil }

        switch priority {
        case .heroesFirst:
            let heroes = candidates.filter { s.units[$0].kind == .hero }
            return lowest(heroes) { effectiveHealth(s.units[$0]) } ?? s.nearest(candidates, to: pos)
        case .minionsFirst:
            let creeps = candidates.filter { s.units[$0].kind == .minion || s.units[$0].kind == .monster }
            let killable = creeps.filter {
                estimateBasicAttackDamage(s, ctx, attacker: i, target: $0) >= s.units[$0].hp + s.units[$0].totalShield
            }
            if let k = s.nearest(killable, to: pos) { return k }
            return lowest(creeps) { s.units[$0].hp + s.units[$0].totalShield } ?? s.nearest(candidates, to: pos)
        case .structuresFirst:
            let structures = candidates.filter { s.units[$0].isStructure }
            return s.nearest(structures, to: pos) ?? s.nearest(candidates, to: pos)
        case .lowestHealth:
            return lowest(candidates) { s.units[$0].hp + s.units[$0].totalShield }
        }
    }

    /// key が最小の候補（候補は昇順なので同値は添字の小さい方）。
    static func lowest(_ candidates: [Int], by key: (Int) -> Double) -> Int? {
        var best: Int?
        var bestKey = Double.infinity
        for c in candidates {
            let k = key(c)
            if k < bestKey { bestKey = k; best = c }
        }
        return best
    }

    /// 物理ダメージに対する実効 HP（シールド・防御・被ダメ軽減込み）。
    public static func effectiveHealth(_ u: Unit) -> Double {
        (max(0, u.hp) + u.totalShield) / mitigationMultiplier(.physical, armor: u.stats.armor, magicResist: 0)
            / max(0.01, damageReductionMultiplier(u.stats.damageReduction))
    }

    /// 通常攻撃 1 発の推定ダメージ（クリティカル・パッシブ・シールド除く）。対象選択と AI のラストヒット判定用。
    public static func estimateBasicAttackDamage(_ s: SimState, _ ctx: SimContext, attacker i: Int,
                                                 target t: Int) -> Double {
        let st = s.units[i].stats
        var bonus = st.damageBonus
        if s.units[i].kind == .hero { bonus += st.basicAttackDamageBonus }
        if s.units[t].kind == .monster { bonus += st.monsterDamageBonus }
        var damage = st.attack * max(0, 1 + bonus)
        if s.units[t].isStructure {
            damage *= max(0, TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: t, sourceIndex: i))
        }
        damage *= mitigationMultiplier(.physical, armor: s.units[t].stats.armor, magicResist: 0)
        damage *= damageReductionMultiplier(s.units[t].stats.damageReduction)
        return damage
    }
}
