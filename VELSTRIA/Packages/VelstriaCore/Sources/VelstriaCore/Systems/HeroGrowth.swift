import Foundation

// 担当: core-economy（最小実装。XP 分配・レベルアップ処理を実装すること）

public enum HeroGrowth {
    /// レベル成長込みの素の能力値（DESIGN §4）。
    public static func baseStats(def: HeroDef, level: Int) -> Stats {
        let n = Double(max(1, level) - 1)
        var st = Stats()
        st.maxHP = def.baseHP + def.hpGrowth * n
        st.maxResource = def.resourceMax
        st.attack = def.baseAttack + def.attackGrowth * n
        st.armor = def.baseDefense + def.defenseGrowth * n
        st.magicResist = def.baseMagicDefense + def.magicDefenseGrowth * n
        let baseAS = def.isRanged ? Balance.rangedAttackSpeed : Balance.meleeAttackSpeed
        st.attackSpeed = baseAS * (1 + Balance.attackSpeedPerLevel * n)
        st.moveSpeed = def.moveSpeed
        st.attackRange = def.attackRange
        st.sightRange = Balance.heroSight
        st.hpRegen = 4 + 0.6 * Double(level)
        st.resourceRegen = def.resource == .energy ? Balance.energyRegenPerSecond : 3 + 0.35 * Double(level)
        return st
    }

    /// Lv → Lv+1 に必要な XP（最大レベルでは .infinity）。
    public static func xpToNext(level: Int) -> Double {
        guard level >= 1, level < Balance.maxLevel else { return .infinity }
        return Balance.xpToNext[level - 1]
    }

    /// XP を加算しレベルアップを処理する。
    public static func grantXP(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, amount: Double) {
        guard amount > 0, var h = s.units[i].hero else { return }
        h.xp += amount
        var leveled = false
        while h.level < Balance.maxLevel, h.xp >= xpToNext(level: h.level) {
            h.xp -= xpToNext(level: h.level)
            h.level += 1
            h.skillPoints += 1
            leveled = true
            s.emit(.levelUp(heroID: s.units[i].id, level: h.level))
        }
        if h.level >= Balance.maxLevel { h.xp = 0 }
        s.units[i].hero = h
        if leveled {
            StatCalculator.recompute(&s, i, ctx)
            if h.autoLevelSkills { SkillLeveling.autoLevel(&s, ctx, heroIndex: i) }
        }
    }
}

/// スキルポイントの割り振り（DESIGN §6）。
public enum SkillLeveling {
    /// その枠を今上げられるか。
    public static func canLevel(_ hero: HeroData, slot: SkillSlot) -> Bool {
        guard slot != .passive, hero.skillPoints > 0 else { return false }
        let rank = hero.rank(slot)
        guard rank < slot.maxRank else { return false }
        if slot == .ultimate {
            return rank < Balance.ultimateUnlockLevels.filter { hero.level >= $0 }.count
        }
        // 基本スキルは (Lv+1)/2 までに制限
        return rank < (hero.level + 1) / 2
    }

    public static func levelUp(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, slot: SkillSlot) {
        guard var h = s.units[i].hero, canLevel(h, slot: slot) else { return }
        h.skillRanks[slot.rawValue] += 1
        h.skillPoints -= 1
        s.units[i].hero = h
        s.emit(.skillLeveled(heroID: s.units[i].id, slot: slot, rank: h.skillRanks[slot.rawValue]))
    }

    /// 自動習得: Ult > Skill1 > Skill2 > Skill3（未習得スキルを優先）。
    public static func autoLevel(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        while let h = s.units[i].hero, h.skillPoints > 0 {
            let order: [SkillSlot] = [.ultimate, .skill1, .skill2, .skill3]
            let unlearned = order.filter { h.rank($0) == 0 && canLevel(h, slot: $0) }
            guard let slot = unlearned.first ?? order.first(where: { canLevel(h, slot: $0) }) else { return }
            levelUp(&s, ctx, heroIndex: i, slot: slot)
        }
    }
}
