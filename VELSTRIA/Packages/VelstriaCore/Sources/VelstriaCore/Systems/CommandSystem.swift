import Foundation

// 担当: 統合（契約）。入力を各システムへ振り分けるだけの薄い層。

public enum CommandSystem {
    public static func apply(_ commands: [HeroCommand], _ s: inout SimState, _ ctx: SimContext) {
        for c in commands {
            guard let i = s.index(of: c.heroID), s.units[i].kind == .hero, let hero = s.units[i].hero else { continue }
            let dead = hero.isDead

            switch c.command {
            case .move(let dir):
                guard !dead else { continue }
                if dir.length < 0.05 {
                    if case .direction = s.units[i].moveIntent { s.units[i].moveIntent = .none }
                } else {
                    s.units[i].moveIntent = .direction(dir.normalized)
                    s.units[i].path = []
                    s.units[i].attackTargetID = nil
                    s.units[i].windupRemaining = nil
                    RecallSystem.cancelChannel(&s, i)
                }
            case .moveTo(let p):
                guard !dead else { continue }
                s.units[i].moveIntent = .point(p)
                s.units[i].path = []
                s.units[i].attackTargetID = nil
                s.units[i].windupRemaining = nil
                RecallSystem.cancelChannel(&s, i)
            case .stop:
                s.units[i].moveIntent = .none
                s.units[i].path = []
                s.units[i].attackTargetID = nil
            case .attack(let targetID):
                guard !dead, let t = s.index(of: targetID), s.isTargetableEnemy(t, of: s.units[i].team) else { continue }
                s.units[i].attackTargetID = targetID
                s.units[i].moveIntent = .none
                RecallSystem.cancelChannel(&s, i)
            case .attackNearest(let priority):
                guard !dead else { continue }
                attackNearest(&s, ctx, i, priority: priority, heroLock: false, chase: true, activeMonsterOnly: false)
            case .attackNearestWith(let priority, let heroLock, let activeMonsterOnly):
                guard !dead else { continue }
                attackNearest(&s, ctx, i, priority: priority, heroLock: heroLock, chase: heroLock,
                              activeMonsterOnly: activeMonsterOnly)
            case .castSkill(let slot, let target):
                guard !dead else { continue }
                if SkillSystem.cast(&s, ctx, heroIndex: i, slot: slot, target: target) {
                    RecallSystem.cancelChannel(&s, i)
                }
            case .castSpell(let index, let target):
                guard !dead else { continue }
                if SpellSystem.cast(&s, ctx, heroIndex: i, spellIndex: index, target: target) {
                    // 帰還門は自身が詠唱なので中断しない
                    if s.units[i].hero?.channel?.kind != .teleport { RecallSystem.cancelChannel(&s, i) }
                }
            case .levelSkill(let slot):
                SkillLeveling.levelUp(&s, ctx, heroIndex: i, slot: slot)
            case .setAutoLevel(let enabled):
                s.units[i].hero?.autoLevelSkills = enabled
                if enabled { SkillLeveling.autoLevel(&s, ctx, heroIndex: i) }
            case .buyItem(let itemID):
                ItemSystem.buy(&s, ctx, heroIndex: i, itemID: itemID)
            case .sellItem(let slotIndex):
                ItemSystem.sell(&s, ctx, heroIndex: i, slotIndex: slotIndex)
            case .setGearOption(let option):
                GearSystem.setOption(&s, ctx, heroIndex: i, option: option)
            case .useItemActive:
                guard !dead else { continue }
                ItemEffects.useActive(&s, ctx, heroIndex: i)
            case .useGearActive:
                guard !dead else { continue }
                GearSystem.useActive(&s, ctx, heroIndex: i)
            case .recall:
                guard !dead else { continue }
                RecallSystem.startRecall(&s, ctx, heroIndex: i)
            case .emote(let emoteID):
                s.emit(.emote(heroID: s.units[i].id, emoteID: emoteID))
            case .surrenderVote(let yes):
                MatchFlowSystem.vote(&s, ctx, heroIndex: i, yes: yes)
            case .removeTutorialDummies:
                guard ctx.config.mode == .tutorial, c.heroID == s.humanHeroID else { continue }
                SpawnSystem.removeTutorialDummies(&s)
            case .setController(let controller):
                guard hero.controller != controller else { continue }
                s.units[i].hero?.controller = controller
                if controller == .bot {
                    // AI に引き継ぐ: 人間の操作意図を捨て、スキルは自動習得にする
                    s.units[i].moveIntent = .none
                    s.units[i].path = []
                    s.units[i].attackTargetID = nil
                    s.units[i].hero?.autoLevelSkills = true
                    SkillLeveling.autoLevel(&s, ctx, heroIndex: i)
                }
            }
        }
    }

    /// 攻撃ボタン: 優先度に従って対象を選び、通常攻撃の対象にする（ヒーローを狙ったときは追撃の記録を残す）。
    private static func attackNearest(_ s: inout SimState, _ ctx: SimContext, _ i: Int, priority: TargetPriority,
                                      heroLock: Bool, chase: Bool, activeMonsterOnly: Bool) {
        guard let t = CombatSystem.selectAttackTarget(&s, ctx, attacker: i, priority: priority, heroLock: heroLock,
                                                      chase: chase, activeMonsterOnly: activeMonsterOnly) else { return }
        s.units[i].attackTargetID = s.units[t].id
        if s.units[t].kind == .hero { CombatSystem.markStickyTarget(&s, attacker: i, target: t) }
        s.units[i].moveIntent = .none
        RecallSystem.cancelChannel(&s, i)
    }
}
