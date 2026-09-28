import Foundation

// 担当: core-world（最小実装。DESIGN §4 のターゲット優先・連続命中・序盤保護・裏取り保護・ミニオン割合ダメージを実装すること）

public enum TowerSystem {
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        for i in s.units.indices where s.units[i].isStructure && s.units[i].isAlive {
            let u = s.units[i]
            let reach = u.stats.attackRange + u.radius
            if let t = s.index(of: u.attackTargetID), s.isTargetableEnemy(t, of: u.team),
               s.units[t].pos.distance(to: u.pos) <= reach + s.units[t].radius {
                continue
            }
            let near = s.enemies(of: u.team, near: u.pos, radius: reach)
            let minions = near.filter { s.units[$0].kind == .minion }
            let pick = s.nearest(minions, to: u.pos) ?? s.nearest(near, to: u.pos)
            s.units[i].attackTargetID = pick.map { s.units[$0].id }
        }
    }

    /// 構造物（タワー/Core）の通常攻撃 1 発のダメージ（対ミニオンは最大 HP 割合、対ヒーローは連続命中補正込み）。
    /// CombatSystem が構造物の攻撃命中時に呼ぶ。
    public static func attackDamage(_ s: inout SimState, _ ctx: SimContext, towerIndex i: Int, targetIndex t: Int) -> Double {
        s.units[i].stats.attack
    }

    /// 構造物が受けるダメージの倍率（序盤保護・裏取り保護・攻城ミニオン ×1.5 など）。CombatSystem.applyDamage が呼ぶ。
    public static func damageTakenMultiplier(_ s: SimState, _ ctx: SimContext, structureIndex i: Int,
                                             sourceIndex: Int?) -> Double {
        1
    }

    /// 構造物が現在無敵か（同レーンの前段タワー生存中 / Core は基部塔が 1 本も落ちていない間）。
    public static func isInvulnerable(_ s: SimState, _ ctx: SimContext, index i: Int) -> Bool {
        let u = s.units[i]
        guard u.isStructure, let td = u.tower else { return false }
        if u.kind == .core {
            let baseTowerDown = s.units.contains {
                $0.kind == .tower && $0.team == u.team && $0.tower?.tier == .base && !$0.isAlive
            }
            return !baseTowerDown
        }
        return s.units.contains {
            $0.kind == .tower && $0.team == u.team && $0.isAlive && $0.tower?.lane == td.lane
                && ($0.tower?.tier.rawValue ?? 0) < td.tier.rawValue
        }
    }
}
