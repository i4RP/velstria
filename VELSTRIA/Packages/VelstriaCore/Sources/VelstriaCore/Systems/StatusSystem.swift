import Foundation

// 担当: core-combat
// 状態効果・シールド・強化攻撃の時間経過、燃焼の持続ダメージ、アシスト記録の期限切れ。
// 能力値への反映は StatusModifiers（StatCalculator が毎 tick 呼ぶ）。

public enum StatusSystem {
    /// 状態効果・シールド・強化攻撃の時間経過と持続ダメージ。
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let dt = Balance.dt
        for i in s.units.indices {
            guard CombatSystem.isLiving(s, i) else {
                // 死亡処理（DeathSystem が respawnTimer を設定）済みのヒーローは、前の命のアシスト記録と強化攻撃を捨てる。
                // 記録を残すと復活直後の再死亡で、前回の死亡前に与えたダメージがアシストとして数えられてしまう
                if s.units[i].hero?.isDead == true {
                    CombatSystem.clearAssistRecords(&s, i)
                    if s.units[i].hero?.empoweredAttack != nil { s.units[i].hero?.empoweredAttack = nil }
                }
                continue
            }
            if !s.units[i].statuses.isEmpty { tickStatuses(&s, ctx, i, dt: dt) }

            if !s.units[i].shields.isEmpty {
                for k in s.units[i].shields.indices { s.units[i].shields[k].remaining -= dt }
                s.units[i].shields.removeAll {
                    $0.remaining <= CombatSystem.timeEpsilon || $0.amount <= CombatSystem.deathEpsilon
                }
            }

            if s.units[i].kind == .hero {
                if let emp = s.units[i].hero?.empoweredAttack {
                    let left = emp.remaining - dt
                    if left <= CombatSystem.timeEpsilon {
                        s.units[i].hero?.empoweredAttack = nil
                    } else {
                        s.units[i].hero?.empoweredAttack?.remaining = left
                    }
                }
                CombatSystem.pruneAssistRecords(&s, i)
            }
        }
    }

    /// 残り時間を進め、燃焼は combatBurnTickInterval 毎（と期限切れ時の端数）に確定ダメージを与える。
    /// 1 回の燃焼の合計は magnitude × 持続時間。
    static func tickStatuses(_ s: inout SimState, _ ctx: SimContext, _ i: Int, dt: Double) {
        var burns: [(amount: Double, sourceID: EntityID?)] = []
        var expired = false
        for k in s.units[i].statuses.indices {
            var st = s.units[i].statuses[k]
            let active = min(dt, max(0, st.remaining))
            st.remaining -= dt
            if st.kind == .burn, st.magnitude > 0 {
                st.tickTimer += active
                if st.tickTimer >= Balance.combatBurnTickInterval - CombatSystem.timeEpsilon
                    || st.remaining <= CombatSystem.timeEpsilon {
                    burns.append((st.magnitude * st.tickTimer, st.sourceID))
                    st.tickTimer = 0
                }
            }
            if st.remaining <= CombatSystem.timeEpsilon { expired = true }
            s.units[i].statuses[k] = st
        }
        if expired { s.units[i].statuses.removeAll { $0.remaining <= CombatSystem.timeEpsilon } }
        for b in burns where b.amount > 0 {
            guard CombatSystem.isLiving(s, i) else { break }
            CombatSystem.applyDamage(&s, ctx, sourceID: b.sourceID, targetIndex: i, amount: b.amount,
                                     type: .trueDamage, source: .dot)
        }
    }
}

/// ステータス効果を能力値へ反映する。
/// スロー・回復阻害・与ダメ低下は最大値のみ、加速・攻撃速度・与ダメ上昇・被ダメ軽減は加算。
public enum StatusModifiers {
    public static func apply(_ statuses: [StatusEffect], to stats: inout Stats) {
        guard !statuses.isEmpty else { return }
        var maxSlow = 0.0
        var speedBoost = 0.0
        var attackSpeedBoost = 0.0
        var healCut = 0.0
        var dealtCut = 0.0
        var armorShred = 0.0
        var magicShred = 0.0
        var flatSpeed = 0.0
        for st in statuses {
            switch st.kind {
            case .slow: maxSlow = max(maxSlow, st.magnitude)
            case .speedBoost: speedBoost += st.magnitude
            case .attackSpeedBoost: attackSpeedBoost += st.magnitude
            case .damageBoost: stats.damageBonus += st.magnitude
            case .damageReduction: stats.damageReduction += st.magnitude
            case .healReduction: healCut = max(healCut, st.magnitude)
            // 威嚇（上古の鎧）は物理ダメージだけを下げる（ItemEffects.outgoingDamageBonus）
            case .damageDealtReduction where st.tag != ItemEffects.deterTag: dealtCut = max(dealtCut, st.magnitude)
            case .blueBuff:
                stats.cooldownReduction += Balance.combatBlueBuffCooldownReduction
                stats.resourceRegen += Balance.combatBlueBuffResourceRegen
            case .wyrmBlessing: stats.damageBonus += Balance.combatWyrmBlessingDamageBonus
            case .colossusBlessing: stats.damageBonus += Balance.combatColossusBlessingDamageBonus
            case .lifestealBoost: stats.lifesteal += st.magnitude
            case .spellVampBoost: stats.spellVamp += st.magnitude
            case .attackRangeBoost: stats.attackRange += st.magnitude
            case .armorShred: armorShred = max(armorShred, st.magnitude)
            case .magicShred: magicShred = max(magicShred, st.magnitude)
            case .flatPowerMod:
                stats.attack = max(0, stats.attack + st.magnitude)
                stats.abilityPower = max(0, stats.abilityPower + st.magnitude)
            case .flatMoveSpeedMod: flatSpeed += st.magnitude
            case .flatDefenseMod:
                stats.armor += st.magnitude
                stats.magicResist += st.magnitude
            default:
                // 行動阻害・無敵・ステルス・燃焼・マーク・対象不可・suppress などは能力値に影響しない（各システムが直接参照）
                break
            }
        }
        stats.damageBonus -= dealtCut
        if armorShred > 0 { stats.armor *= 1 - min(1, armorShred) }
        if magicShred > 0 { stats.magicResist = max(0, stats.magicResist - magicShred) }
        stats.attackSpeed *= max(0, 1 + attackSpeedBoost)
        // 減速軽減（ラピッドブーツ）は受ける減速の割合を弱める
        let slow = min(1, max(0, maxSlow)) * (1 - min(1, max(0, stats.slowReduction)))
        stats.moveSpeed = max(0, stats.moveSpeed + flatSpeed)
        stats.moveSpeed *= max(0, 1 + speedBoost) * (1 - slow)
        stats.healingReceivedMultiplier *= 1 - min(1, max(0, healCut))
    }
}
