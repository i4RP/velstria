import Foundation

// 担当: core（マジックチェス）。ロール（6 種）を軸にしたシナジー。閾値 2 / 4。
// 盤上のユニークな heroID 数で数える（オートチェス準拠。同名の★違いは 1 とする）。
// 効果は AutoCombatResolver が戦闘開始時に各ユニットのステータスへ直接適用する。

public enum MagicChessSynergy {
    public static let firstThreshold = 2
    public static let secondThreshold = 4

    /// 盤上のロール別ユニーク heroID 数と発動段階（0/1/2）。count > 0 のロールのみ返す。
    public static func tiers(board: [BoardUnit], master: MasterData) -> [SynergyTier] {
        var byRole: [Role: Set<String>] = [:]
        for u in board {
            guard let def = master.hero(u.heroID) else { continue }
            byRole[def.role, default: []].insert(u.heroID)
        }
        var out: [SynergyTier] = []
        for role in Role.allCases {
            let count = byRole[role]?.count ?? 0
            guard count > 0 else { continue }
            let tier = count >= secondThreshold ? 2 : (count >= firstThreshold ? 1 : 0)
            out.append(SynergyTier(role: role, count: count, tier: tier))
        }
        return out.sorted { $0.role.rawValue < $1.role.rawValue }
    }

    /// 閾値（UI 表示用）。
    public static func thresholdLabel(_ role: Role) -> String { "\(firstThreshold)/\(secondThreshold)" }

    /// 効果の説明（UI 表示用・二言語）。
    public static func effectText(_ role: Role) -> (ja: String, en: String) {
        switch role {
        case .vanguard: return ("味方全体の被ダメージ軽減", "Allies take less damage")
        case .duelist: return ("味方全体の攻撃速度上昇", "Allies attack faster")
        case .ranger: return ("レンジャーの攻撃力上昇", "Rangers deal more damage")
        case .arcanist: return ("アルカニストの魔法ダメージ上昇", "Arcanists deal more magic damage")
        case .support: return ("味方全体にシールドと回復", "Shields and healing for allies")
        case .assassin: return ("アサシンの攻撃力と会心上昇", "Assassins gain attack and crit")
        }
    }
}
