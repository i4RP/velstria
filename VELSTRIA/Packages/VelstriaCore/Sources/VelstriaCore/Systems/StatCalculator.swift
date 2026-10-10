import Foundation

// 担当: 統合（契約）。合成順序のみ定義。各段の中身は担当システムが実装する。
//   1. HeroGrowth.baseStats   (core-economy) レベル成長
//   2. ItemStats.apply        (core-economy) 装備・ルーン
//   3. StatusModifiers.apply  (core-combat)  バフ/デバフ

public enum StatCalculator {
    public static func recompute(_ s: inout SimState, _ i: Int, _ ctx: SimContext) {
        let u = s.units[i]
        var stats: Stats
        if let hero = u.hero, let def = ctx.master.hero(hero.heroID) {
            stats = HeroGrowth.baseStats(def: def, level: hero.level)
            s.units[i].baseStats = stats
            ItemStats.apply(items: hero.items, runes: hero.runes, to: &stats, ctx: ctx, hero: hero, time: s.time)
            GearEffects.applyStats(hero, to: &stats, master: ctx.master)
            ItemEffects.applyRuntimeStats(s.units[i], to: &stats, time: s.time, master: ctx.master)
        } else {
            stats = u.baseStats
        }
        StatusModifiers.apply(u.statuses, to: &stats)
        JungleBuffs.applyStatModifiers(u, base: s.units[i].baseStats, to: &stats, map: ctx.map)

        // 制約
        stats.cooldownReduction = min(max(0, stats.cooldownReduction), stats.cooldownReductionCap)
        stats.attackSpeed = min(max(0.1, stats.attackSpeed), Balance.maxAttackSpeed)
        stats.moveSpeed = max(stats.moveSpeed, u.kind == .hero ? Balance.minMoveSpeed : 0)
        stats.maxHP = max(1, stats.maxHP)

        // 最大 HP/リソースが変わったら現在値の割合を維持
        let old = s.units[i].stats
        if old.maxHP > 0, abs(old.maxHP - stats.maxHP) > 0.01, s.units[i].isAlive {
            s.units[i].hp = min(stats.maxHP, s.units[i].hp * stats.maxHP / old.maxHP)
        }
        if old.maxResource > 0, abs(old.maxResource - stats.maxResource) > 0.01 {
            s.units[i].resource = min(stats.maxResource, s.units[i].resource * stats.maxResource / old.maxResource)
        }
        s.units[i].stats = stats
    }
}
