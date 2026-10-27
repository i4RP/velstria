import Foundation

public enum PracticeCommand: Codable, Hashable, Sendable {
    case setLevel(Int)
    case resetSkills
    case learnSkills
    case clearItems
    case refillGold
}

/// 練習の試し直し。入力として記録し、通常のステータス・装備処理を通す。
enum PracticeSystem {
    static func apply(_ command: PracticeCommand, _ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard ctx.config.mode == .practice, s.units[i].id == s.humanHeroID,
              s.units[i].hero?.controller == .human else { return }
        switch command {
        case .setLevel(let requested):
            guard var h = s.units[i].hero else { return }
            let level = min(Balance.maxLevel, max(1, requested))
            guard level != h.level else { return }
            let raised = level > h.level
            if !raised { resetSkills(&h) }
            h.level = level
            h.xp = 0
            h.skillPoints = HeroGrowth.totalSkillPoints(level: level) - HeroGrowth.spentSkillPoints(h)
            s.units[i].hero = h
            StatCalculator.recompute(&s, i, ctx)
            if s.units[i].isAlive {
                s.units[i].hp = s.units[i].stats.maxHP
                s.units[i].resource = s.units[i].stats.maxResource
            }
            if h.autoLevelSkills { SkillLeveling.autoLevel(&s, ctx, heroIndex: i) }
            if raised { s.emit(.levelUp(heroID: s.units[i].id, level: level)) }
        case .resetSkills:
            guard var h = s.units[i].hero else { return }
            resetSkills(&h)
            s.units[i].hero = h
        case .learnSkills:
            SkillLeveling.autoLevel(&s, ctx, heroIndex: i)
        case .clearItems:
            // 既存の売却経路で投資額・靴の祝福・能力値も更新する。最大 6 枠。
            let count = s.units[i].hero?.items.count ?? 0
            for slot in (0..<count).reversed() {
                ItemSystem.sell(&s, ctx, heroIndex: i, slotIndex: slot)
            }
        case .refillGold:
            s.units[i].hero?.gold = Balance.Economy.practiceGold
        }
    }

    private static func resetSkills(_ hero: inout HeroData) {
        for slot in SkillSlot.actives { hero.skillRanks[slot.rawValue] = 0 }
        hero.skillPoints = HeroGrowth.totalSkillPoints(level: hero.level)
        hero.autoLevelSkills = false
    }
}
