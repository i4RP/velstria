import Foundation

// 担当: core-economy
// レベル成長・XP 付与/分配・スキルポイント（DESIGN §4, §6, §8）。

public enum HeroGrowth {
    /// レベル成長込みの素の能力値（DESIGN §4）。
    public static func baseStats(def: HeroDef, level: Int) -> Stats {
        let lv = min(max(1, level), Balance.maxLevel)
        let n = Double(lv - 1)
        var st = Stats()
        st.maxHP = def.baseHP + def.hpGrowth * n
        st.maxResource = def.resourceMax
        st.attack = def.baseAttack + def.attackGrowth * n
        st.armor = def.baseDefense + def.defenseGrowth * n
        st.magicResist = def.baseMagicDefense + def.magicDefenseGrowth * n
        let baseAS = def.isRanged ? Balance.rangedAttackSpeed : Balance.meleeAttackSpeed
        st.attackSpeed = baseAS * (1 + Balance.attackSpeedPerLevel * n)
        st.moveSpeed = def.moveSpeed * Balance.heroMoveSpeedScale
        st.attackRange = def.attackRange
        st.sightRange = Balance.heroSight
        st.hpRegen = 4 + 0.6 * Double(lv)
        st.resourceRegen = def.resource == .energy ? Balance.energyRegenPerSecond : 3 + 0.35 * Double(lv)
        return st
    }

    /// Lv → Lv+1 に必要な XP（最大レベルでは .infinity）。
    public static func xpToNext(level: Int) -> Double {
        guard level >= 1, level < Balance.maxLevel else { return .infinity }
        return Balance.xpToNext[level - 1]
    }

    /// Lv1 から level に到達するまでの累計 XP。
    public static func totalXP(toReach level: Int) -> Double {
        let lv = min(max(1, level), Balance.maxLevel)
        return Balance.xpToNext.prefix(lv - 1).reduce(0, +)
    }

    /// 次のレベルまでの進捗 0...1（HUD の XP バー。最大レベルは 1）。
    public static func levelProgress(_ hero: HeroData) -> Double {
        let need = xpToNext(level: hero.level)
        guard need.isFinite, need > 0 else { return 1 }
        return min(1, max(0, hero.xp / need))
    }

    /// 現在のレベルで保有しているべきスキルポイント総数（Lv1 で 1、以後 +1）。
    public static func totalSkillPoints(level: Int) -> Int { max(1, level) }

    /// 割り振り済みのスキルポイント数（パッシブを除く）。
    public static func spentSkillPoints(_ hero: HeroData) -> Int {
        SkillSlot.actives.reduce(0) { $0 + hero.rank($1) }
    }

    /// XP を加算しレベルアップを処理する。
    public static func grantXP(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, amount: Double) {
        // 乱闘などモード別の XP 加速。
        let scaled = amount * Balance.Economy.xpScale(ctx.config.mode)
        guard scaled > 0, var h = s.units[i].hero, h.level < Balance.maxLevel else { return }
        h.xp += scaled
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

    /// ミニオン・モンスターの XP を team の周囲ヒーローで分配する（DESIGN §8）。
    /// 1 人なら ×1.0、2 人以上なら合計 ×1.3 を等分。対象は pos から xpShareRadius 以内の生存ヒーロー。
    public static func shareXP(_ s: inout SimState, _ ctx: SimContext, team: Team, around pos: Vec2, amount: Double) {
        guard amount > 0, team != .neutral else { return }
        let receivers = nearbyHeroes(s, team: team, around: pos, radius: Balance.xpShareRadius)
        guard !receivers.isEmpty else { return }
        let total = receivers.count == 1 ? amount : amount * Balance.Economy.groupXPMultiplier
        let each = total / Double(receivers.count)
        for i in receivers { grantXP(&s, ctx, heroIndex: i, amount: each) }
    }

    /// pos から radius 以内にいる team の生存ヒーロー（添字昇順）。
    public static func nearbyHeroes(_ s: SimState, team: Team, around pos: Vec2, radius: Double) -> [Int] {
        let r2 = radius * radius
        return s.units.indices.filter { i in
            let u = s.units[i]
            guard u.kind == .hero, u.team == team, u.isAlive, u.hero?.isDead == false else { return false }
            return u.pos.distanceSquared(to: pos) <= r2
        }
    }

    /// 試合開始時（最初の tick）の初期化: 練習場の開始レベル反映・スキルポイント付与・自動習得。
    /// 何度呼んでも結果が変わらない（冪等）。
    public static func applyMatchStart(_ s: inout SimState, _ ctx: SimContext) {
        let practice = ctx.config.mode == .practice || ctx.config.mode == .tutorial
        let startLevel = practice ? min(Balance.maxLevel, max(1, ctx.config.practice?.startLevel ?? 1)) : 1
        for i in s.heroIndices {
            guard var h = s.units[i].hero else { continue }
            let raised = h.level < startLevel
            if raised {
                h.level = startLevel
                h.xp = 0
            }
            // 保有すべきポイント − 割り振り済み が不足していれば補う
            let owed = totalSkillPoints(level: h.level) - spentSkillPoints(h)
            if h.skillPoints < owed { h.skillPoints = owed }
            s.units[i].hero = h
            if raised {
                StatCalculator.recompute(&s, i, ctx)
                if s.units[i].isAlive {
                    s.units[i].hp = s.units[i].stats.maxHP
                    s.units[i].resource = s.units[i].stats.maxResource
                }
            }
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

    /// 自動習得: Ult > Skill1 > Skill2（未習得スキルを優先）。
    public static func autoLevel(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        while let h = s.units[i].hero, h.skillPoints > 0 {
            let order: [SkillSlot] = [.ultimate, .skill1, .skill2]
            let unlearned = order.filter { h.rank($0) == 0 && canLevel(h, slot: $0) }
            guard let slot = unlearned.first ?? order.first(where: { canLevel(h, slot: $0) }) else { return }
            levelUp(&s, ctx, heroIndex: i, slot: slot)
        }
    }
}
