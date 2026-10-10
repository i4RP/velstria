import Foundation

// 担当: core-economy
// パッシブ Gold・自然回復（戦闘中は半減）・泉の回復/ダメージ・練習場の無限 Gold（DESIGN §2, §4, §8）。

public enum EconomySystem {
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        // 最初の tick で開始レベル・初期スキルポイントを反映（練習場の開始レベルもここ）
        if s.tick == 1 { HeroGrowth.applyMatchStart(&s, ctx) }

        let dt = Balance.dt
        let infinite = EconomyRewards.hasInfiniteGold(ctx)
        let passiveGold = s.time >= Balance.passiveGoldStart ? Balance.passiveGoldPerSecond * dt : 0

        for i in s.units.indices where s.units[i].kind == .hero {
            guard let h = s.units[i].hero else { continue }

            // Gold（死亡中もパッシブ収入は入る）
            if infinite {
                s.units[i].hero!.gold = Balance.Economy.practiceGold
            } else if passiveGold > 0 {
                EconomyRewards.grantGold(&s, heroIndex: i, amount: passiveGold, visible: false)
            }

            guard s.units[i].isAlive, !h.isDead else { continue }
            let st = s.units[i].stats
            let team = s.units[i].team

            // 自然回復（戦闘中は HP 回復半減、重傷などの被回復倍率を反映）
            let inCombat = s.time - s.units[i].lastCombatTime < Balance.combatTimeout
            let hpRegen = st.hpRegen * (inCombat ? Balance.Economy.combatRegenMultiplier : 1)
                * max(0, st.healingReceivedMultiplier)
            var hp = s.units[i].hp + hpRegen * dt
            var res = s.units[i].resource + st.resourceRegen * dt

            // 味方の泉: 毎秒 最大値の 10% 回復
            if ctx.map.isInFountain(s.units[i].pos, team: team) {
                hp += st.maxHP * Balance.fountainHealPct * dt
                res += st.maxResource * Balance.fountainHealPct * dt
            }
            s.units[i].hp = min(st.maxHP, hp)
            s.units[i].resource = min(st.maxResource, max(0, res))

            // 敵の泉: 毎秒 1000 の確定ダメージ
            if team != .neutral, ctx.map.isInFountain(s.units[i].pos, team: team.opponent) {
                CombatSystem.applyDamage(&s, ctx, sourceID: nil, targetIndex: i,
                                         amount: Balance.fountainDamagePerSecond * dt,
                                         type: .trueDamage, source: .fountain)
            }
        }
        // ジャングルのバフ: 宝殻蟹の Gold・苔草の Mana 回復・星喰竜の加護のシールドの張り直し
        JungleBuffs.update(&s, ctx)
    }

    /// 戦闘中か（直近 combatTimeout 秒以内に敵ヒーロー/タワーと交戦）。HUD・移動速度補正が参照。
    public static func isInCombat(_ s: SimState, unitIndex i: Int) -> Bool {
        s.time - s.units[i].lastCombatTime < Balance.combatTimeout
    }
}
