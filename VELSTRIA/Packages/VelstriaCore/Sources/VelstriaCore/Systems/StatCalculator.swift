import Foundation

// 担当: 統合（契約）。合成順序のみ定義。各段の中身は担当システムが実装する。
//   1. HeroGrowth.baseStats   (core-economy) レベル成長
//   2. ItemStats.apply        (core-economy) 装備・エンブレム
//   3. StatusModifiers.apply  (core-combat)  バフ/デバフ

public enum StatCalculator {
    public static func recompute(_ s: inout SimState, _ i: Int, _ ctx: SimContext) {
        let u = s.units[i]
        var stats: Stats
        if let hero = u.hero, let def = ctx.master.hero(hero.heroID) {
            stats = HeroGrowth.baseStats(def: def, level: hero.level)
            s.units[i].baseStats = stats
            ItemStats.apply(items: hero.items, emblem: hero.emblem, to: &stats, ctx: ctx, hero: hero, time: s.time)
            GearEffects.applyStats(hero, to: &stats, master: ctx.master)
            ItemEffects.applyRuntimeStats(s.units[i], to: &stats, time: s.time, master: ctx.master)
            EmblemEffects.applyRuntimeStats(s.units[i], to: &stats, time: s.time, map: ctx.map)
        } else {
            stats = u.baseStats
        }
        StatusModifiers.apply(u.statuses, to: &stats)
        JungleBuffs.applyStatModifiers(u, base: s.units[i].baseStats, to: &stats, map: ctx.map)

        // 制約
        stats.cooldownReduction = min(max(0, stats.cooldownReduction), stats.cooldownReductionCap)
        let isHero = u.kind == .hero
        // 鼓舞（BS12）: 攻撃速度 ×1.55、上限 5（MLBB の Inspire）
        let inspired = u.statuses.contains { $0.tag == "spell.BS12" && $0.kind == .mark }
        finalize(&stats, isHero: isHero, outOfCombat: isHero && s.time - u.lastCombatTime > Balance.combatTimeout,
                 inspired: inspired)
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

    /// 攻撃速度と移動速度を MLBB の式で確定する（合成の最後に 1 回だけ）。追加の攻撃速度・加速・減速は 0 に戻す。
    /// - 攻撃速度 = 基礎 + 追加 × 攻撃速度比率（上限 3）。MLBB の用語注釈「攻撃速度」。
    /// - 移動速度 = 基礎 × (100% + 全加速% − 全減速%)。減速の合計は 90% まで。ヒーローは計算値が 230 未満・420 超で逓減し、
    ///   最後にマップ縮尺（Balance.mapScale）を掛けてワールドの単位/秒にする。MLBB の用語注釈「移動速度」。
    /// outOfCombat = 非戦闘中（直近 5 秒に交戦なし）。装備の非戦闘時の加速をほかの加速と同じく足す。
    public static func finalize(_ stats: inout Stats, isHero: Bool, outOfCombat: Bool = false, inspired: Bool = false) {
        // 攻撃速度 = 基礎 + 追加 × 比率（上限 3）。鼓舞（BS12）は最終値 ×1.55・上限 5
        let attackSpeed = (stats.attackSpeed + stats.extraAttackSpeed * stats.attackSpeedRatio) * (inspired ? 1.55 : 1)
        stats.attackSpeed = min(max(0.1, attackSpeed), inspired ? 5 : Balance.maxAttackSpeed)
        stats.extraAttackSpeed = 0
        if outOfCombat { stats.moveSpeedBonus += max(0, stats.outOfCombatMoveSpeedBonus) }
        let calculated = MoveSpeedMath.calculated(basic: stats.moveSpeed, bonus: stats.moveSpeedBonus,
                                                  slow: stats.moveSpeedSlow, slowReduction: stats.slowReduction,
                                                  decays: isHero)
        stats.moveSpeed = isHero ? max(Balance.minMoveSpeed, calculated * Balance.mapScale) : calculated
        stats.moveSpeedBonus = 0
        stats.moveSpeedSlow = 0
    }
}

/// MLBB の移動速度の式（用語注釈「移動速度」）。
public enum MoveSpeedMath {
    /// 計算移動速度 = 基礎 × (100% + 全加速% − 全減速%)。減速は合計して減速軽減を掛け、上限 Balance.maxSlow（90%）。
    /// decays = true（ヒーロー）なら、加速・減速で 230 未満・420 超へ動いた分を逓減させる（`decayed`）。
    public static func calculated(basic: Double, bonus: Double, slow: Double, slowReduction: Double = 0,
                                  decays: Bool) -> Double {
        let b = max(0, basic)
        let totalSlow = min(Balance.maxSlow, max(0, slow) * (1 - min(1, max(0, slowReduction))))
        let raw = b * max(0, 1 + bonus - totalSlow)
        return decays ? decayed(raw, basic: b) : raw
    }

    /// 加速・減速の効果のうち、230 未満・420 超へはみ出した分に Balance.moveSpeedDecayRate を掛ける
    /// （効果だけが逓減する。基礎がもともと 230 未満・420 超ならその値から先だけ）。率は資料に無く仮の値。
    public static func decayed(_ v: Double, basic: Double) -> Double {
        let k = Balance.moveSpeedDecayRate
        let hi = max(Balance.moveSpeedDecayAbove, basic), lo = min(Balance.moveSpeedDecayBelow, basic)
        if v > hi { return hi + (v - hi) * k }
        if v < lo { return lo - (lo - v) * k }
        return v
    }
}
