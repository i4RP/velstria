import Foundation

// 担当: core-combat（最小実装）

public enum StatusSystem {
    /// 状態効果・シールド・強化攻撃の時間経過と持続ダメージ。
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let dt = Balance.dt
        for i in s.units.indices where s.units[i].isAlive {
            var burns: [(Double, EntityID?)] = []
            for k in s.units[i].statuses.indices {
                s.units[i].statuses[k].remaining -= dt
                if s.units[i].statuses[k].kind == .burn {
                    burns.append((s.units[i].statuses[k].magnitude * dt, s.units[i].statuses[k].sourceID))
                }
            }
            s.units[i].statuses.removeAll { $0.remaining <= 0 }
            for k in s.units[i].shields.indices { s.units[i].shields[k].remaining -= dt }
            s.units[i].shields.removeAll { $0.remaining <= 0 || $0.amount <= 0 }
            if s.units[i].hero?.empoweredAttack != nil {
                s.units[i].hero!.empoweredAttack!.remaining -= dt
                if s.units[i].hero!.empoweredAttack!.remaining <= 0 { s.units[i].hero!.empoweredAttack = nil }
            }
            for (amount, src) in burns {
                CombatSystem.applyDamage(&s, ctx, sourceID: src, targetIndex: i, amount: amount,
                                         type: .trueDamage, source: .dot)
            }
        }
    }
}

/// ステータス効果を能力値へ反映する。
public enum StatusModifiers {
    public static func apply(_ statuses: [StatusEffect], to stats: inout Stats) {
        var maxSlow: Double = 0
        var speedBoost: Double = 0
        var healCut: Double = 0
        for st in statuses {
            switch st.kind {
            case .slow: maxSlow = max(maxSlow, st.magnitude)
            case .speedBoost: speedBoost += st.magnitude
            case .attackSpeedBoost: stats.attackSpeed *= 1 + st.magnitude
            case .damageBoost: stats.damageBonus += st.magnitude
            case .damageReduction: stats.damageReduction += st.magnitude
            case .healReduction: healCut = max(healCut, st.magnitude)
            case .damageDealtReduction: stats.damageBonus -= st.magnitude
            case .blueBuff:
                stats.cooldownReduction += 0.15
                stats.resourceRegen += 5
            case .wyrmBlessing: stats.damageBonus += 0.10
            case .colossusBlessing: stats.damageBonus += 0.15
            default: break
            }
        }
        stats.moveSpeed *= (1 + speedBoost) * (1 - maxSlow)
        stats.healingReceivedMultiplier *= 1 - healCut
    }
}
