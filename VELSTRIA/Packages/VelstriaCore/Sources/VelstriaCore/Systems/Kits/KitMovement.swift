import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// 移動系のプリミティブ: 経路ヒット突進・引き寄せ・押し出し。
// 引き寄せ/押し出しは `kind: .knockback` の変位（新しい DisplacementKind は作らない）。

extension Kit {
    /// 経路上の敵に 1 度ずつ当たる突進。MovementSystem.dash + KitSweep。毎 tick prevPos → pos の線分上の敵に payload を適用し、
    /// 着地した tick に arriveCode（0 以外）で HeroKit.onTimer を呼ぶ。戻り値 = 実際の終点。
    @discardableResult
    static func dashSweeping(_ s: inout SimState, _ ctx: SimContext, caster i: Int, slot: SkillSlot, to target: Vec2,
                             speed: Double, payload: HitPayload, radius: Double, arriveCode: Int = 0,
                             interruptible: Bool = true) -> Vec2 {
        let landing = MovementSystem.dash(&s, ctx, unitIndex: i, to: target, speed: speed, kind: .dash)
        guard s.units[i].hero?.kit != nil else { return landing }
        var p = payload
        if p.originPos == nil { p.originPos = s.units[i].pos }
        s.units[i].hero!.kit!.sweep = KitSweep(slot: slot, payload: p, radius: radius, arriveCode: arriveCode,
                                               interruptible: interruptible)
        return landing
    }

    /// 強制移動を受けられる相手か（生存・構造物以外・CC 無効/無敵でない）。
    static func canDisplace(_ s: SimState, _ ctx: SimContext, _ t: Int) -> Bool {
        guard s.units.indices.contains(t), CombatSystem.isLiving(s, t), !s.units[t].isStructure,
              !s.units[t].has(.ccImmune), !CombatSystem.isInvulnerable(s, ctx, t) else { return false }
        return true
    }

    /// target を point へ引き寄せる。gap = 止まる位置の中心間距離の下限（近づきすぎない）。壁の手前で止まる。
    /// 動かせたら true。
    @discardableResult
    static func pull(_ s: inout SimState, _ ctx: SimContext, target t: Int, toward point: Vec2, distance: Double,
                     duration: Double, gap: Double = 0) -> Bool {
        guard canDisplace(s, ctx, t), distance > 0 else { return false }
        let delta = point - s.units[t].pos
        let d = delta.length
        let travel = min(distance, d - max(0, gap))
        guard d > 1e-6, travel > 1e-6 else { return false }
        MovementSystem.knockback(&s, ctx, unitIndex: t, direction: delta / d, distance: travel, duration: duration)
        return true
    }

    /// target を point から遠ざける向きへ押し出す（point に重なっていれば術者の向き/右）。壁の手前で止まる。
    @discardableResult
    static func pushAway(_ s: inout SimState, _ ctx: SimContext, target t: Int, from point: Vec2, distance: Double,
                         duration: Double, fallbackDirection: Vec2 = Vec2(1, 0)) -> Bool {
        guard canDisplace(s, ctx, t), distance > 0 else { return false }
        var dir = (s.units[t].pos - point).normalized
        if dir == .zero { dir = fallbackDirection.normalized }
        guard dir != .zero else { return false }
        MovementSystem.knockback(&s, ctx, unitIndex: t, direction: dir, distance: distance, duration: duration)
        return true
    }
}
