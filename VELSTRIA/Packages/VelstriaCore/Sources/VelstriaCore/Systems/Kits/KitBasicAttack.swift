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

extension Kit {
    /// キットの強い通常攻撃（三連突き・円撃）の合図（SimEvent.empoweredAttack）。shapeBasicAttack の中 = 1 発目の命中の tick、
    /// attackReleased・その攻撃の命中より前に呼ぶ。描画・音・手応えだけが読み、判定・数値・乱数・状態には触れない。
    /// hits = 命中の回数、interval = 2 発目以降の実際の間隔（秒。`firesAfter` で tick に丸めた値）、radius = 周りの円の半径
    /// （術者の中心から。0 = 単体）。届く距離（reach）は今の通常攻撃の射程（伸びを含む）。
    static func emitEmpoweredAttack(_ s: inout SimState, attacker i: Int, target t: Int, hits: Int, interval: Double = 0,
                                    radius: Double = 0) {
        guard let heroID = s.units[i].hero?.heroID, s.units.indices.contains(t) else { return }
        s.emit(.empoweredAttack(EmpoweredAttackEvent(sourceID: s.units[i].id, targetID: s.units[t].id, heroID: heroID,
                                                     hits: hits, interval: interval, radius: radius,
                                                     reach: s.units[i].stats.attackRange, origin: s.units[i].pos)))
    }

    /// 予約（`schedule` の after 秒）が、予約した tick から実際に何秒後に発火するか（tick に丸めた値）。
    /// 予約は撃った tick を 1 回目に数えて減る（KitRuntime.fireTimers: 0.14 秒の予約は 4 tick 後 = 0.133 秒）。
    static func firesAfter(_ after: Double) -> Double {
        let n = max(1, Int(((after - CombatSystem.timeEpsilon) / Balance.dt).rounded(.up)))
        return Double(n - 1) * Balance.dt
    }
}
