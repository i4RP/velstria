import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// 通常攻撃の整形。CombatSystem.releaseAttack がヒーローの通常攻撃を作った後（命中/発射の前）に
// HeroKit.shapeBasicAttack(plan:) を呼ぶ。追加弾・追加ヒット・突進付きの通常攻撃など。
// 突進や状態変更が要るキットは、フックの中で s を直接書き換えてよい（plan は主攻撃の見た目と追加の命中を決める）。

struct BasicAttackPlan {
    /// 主攻撃の命中内容。
    var payload: HitPayload
    /// 弾で撃つか（false = 即時命中）。
    var ranged: Bool
    /// 弾の速度・見た目（nil = 既定）。
    var projectileSpeed: Double?
    var visual: String?
    /// 追加の弾/ヒット（主攻撃と同じ対象へ、同 tick に配列順で）。
    var extras: [HitPayload] = []
}

enum KitBasicAttack {
    /// ヒーローの通常攻撃にキットの整形を適用する。キットが無ければ plan はそのまま。
    static func shape(_ s: inout SimState, _ ctx: SimContext, attacker i: Int, target t: Int,
                      plan: inout BasicAttackPlan) {
        guard let kit = HeroKits.kit(in: s, i) else { return }
        kit.shapeBasicAttack(&s, ctx, attacker: i, target: t, plan: &plan)
    }
}
