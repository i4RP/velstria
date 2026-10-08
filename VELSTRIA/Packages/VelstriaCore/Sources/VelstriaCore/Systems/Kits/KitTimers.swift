import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// 遅延・連撃。KitState.scheduled を挿入順に消化し、時間が来たら HeroKit.onTimer を呼ぶ（KitRuntime.fireTimers）。
// remaining 0 のタイマーは同じ tick に発火する。interruptible なものはハード CC で取り消される。

extension Kit {
    static func schedule(_ s: inout SimState, caster i: Int, slot: SkillSlot, code: Int, after: Double,
                         targetID: EntityID = 0, index: Int = 0, param: Double = 0, point: Vec2 = .zero,
                         interruptible: Bool = true) {
        guard s.units[i].hero?.kit != nil, code != 0 else { return }
        s.units[i].hero!.kit!.scheduled.append(KitTimer(code: code, slot: slot, remaining: max(0, after),
                                                         targetID: targetID, index: index, param: param,
                                                         point: point, interruptible: interruptible))
    }

    /// slot / code が nil でない条件に合うタイマーを取り消す（両方 nil なら全部）。
    static func cancelScheduled(_ s: inout SimState, caster i: Int, slot: SkillSlot? = nil, code: Int? = nil) {
        guard s.units[i].hero?.kit?.scheduled.isEmpty == false else { return }
        s.units[i].hero!.kit!.scheduled.removeAll {
            (slot == nil || $0.slot == slot) && (code == nil || $0.code == code)
        }
    }

    /// 連撃: firstDelay の後、interval 秒おきに count 回 onTimer(index: 0..<count) が呼ばれる。
    static func strikeSequence(_ s: inout SimState, caster i: Int, slot: SkillSlot, code: Int, count: Int,
                               interval: Double, firstDelay: Double = 0, targetID: EntityID = 0, param: Double = 0,
                               point: Vec2 = .zero, interruptible: Bool = true) {
        guard count > 0 else { return }
        for k in 0..<count {
            schedule(&s, caster: i, slot: slot, code: code, after: firstDelay + interval * Double(k),
                     targetID: targetID, index: k, param: param, point: point, interruptible: interruptible)
        }
    }

    /// 予約中のタイマー数（code が nil なら全部）。
    static func scheduledCount(_ s: SimState, caster i: Int, code: Int? = nil) -> Int {
        guard let list = s.units[i].hero?.kit?.scheduled else { return 0 }
        guard let code else { return list.count }
        return list.filter { $0.code == code }.count
    }
}
