import Foundation

// 担当: core-economy（最小実装。泉のダメージ・戦闘中回復減・練習場の無限 Gold を実装すること）

public enum EconomySystem {
    /// パッシブ Gold・自然回復・泉回復。
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let dt = Balance.dt
        for i in s.units.indices where s.units[i].kind == .hero && s.units[i].isAlive {
            if s.time >= Balance.passiveGoldStart {
                s.units[i].hero?.gold += Balance.passiveGoldPerSecond * dt
            }
            let st = s.units[i].stats
            s.units[i].hp = min(st.maxHP, s.units[i].hp + st.hpRegen * dt)
            s.units[i].resource = min(st.maxResource, s.units[i].resource + st.resourceRegen * dt)
            if ctx.map.isInFountain(s.units[i].pos, team: s.units[i].team) {
                s.units[i].hp = min(st.maxHP, s.units[i].hp + st.maxHP * Balance.fountainHealPct * dt)
                s.units[i].resource = min(st.maxResource, s.units[i].resource + st.maxResource * Balance.fountainHealPct * dt)
            }
        }
    }
}
