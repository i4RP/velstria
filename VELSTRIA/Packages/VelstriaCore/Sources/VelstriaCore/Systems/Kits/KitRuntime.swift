import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// キットの実行時処理: 毎 tick の更新（SkillSystem.update から）・再使用の振り分け（SkillSystem.cast から）・
// 遅延タイマーの消化・経路ヒット突進の判定・ハード CC による中断・死亡リセット。
// キットのヒーロー（HeroData.kit が非 nil）以外では何もしない。

/// キットが使うプリミティブの名前空間（Kit*.swift が extension で足す）。
enum Kit {
    /// 取り消しの対象になるハード CC（スタン・打ち上げ・suppress）。
    static func hasHardCC(_ statuses: [StatusEffect]) -> Bool {
        for st in statuses where st.kind == .stun || st.kind == .airborne || st.kind == .suppress { return true }
        return false
    }

    /// キットのスキル発動の演出イベント（SkillArchetypes.emitCast に stage / shape / duration / count を足したもの）。
    static func emitCast(_ s: inout SimState, _ c: KitCast, origin: Vec2? = nil, target: Vec2, unit: Int? = nil,
                         stage: Int? = nil, shape: AimShape? = nil, halfAngle: Double? = nil, duration: Double = 0,
                         count: Int = 0) {
        SkillArchetypes.emitCast(&s, caster: c.caster, check: c.check, targeting: c.targeting,
                                 origin: origin ?? s.units[c.caster].pos, target: target, unit: unit,
                                 stage: stage ?? c.stage, shape: shape, halfAngle: halfAngle, duration: duration,
                                 count: count)
    }
}

enum KitRuntime {
    // MARK: - 毎 tick

    /// 1 tick の更新（SkillSystem.update から、ヒーロー毎）。順序: カウントダウン → 中断 → 突進の掃引 → タイマー → 窓 → キット固有。
    static func update(_ s: inout SimState, _ ctx: SimContext, hero i: Int) {
        guard s.units[i].hero?.kit != nil, CombatSystem.isLiving(s, i), let kit = HeroKits.kit(in: s, i) else { return }
        let dt = Balance.dt
        let eps = CombatSystem.timeEpsilon

        // 1. カウントダウン（0 まで自動で減る）
        for k in 0..<(s.units[i].hero?.kit?.timers.count ?? 0) {
            let v = s.units[i].hero!.kit!.timers[k]
            if v > 0 { s.units[i].hero!.kit!.timers[k] = max(0, v - dt) }
        }

        // 2. ハード CC: 中断できるタイマーと突進を取り消す
        if Kit.hasHardCC(s.units[i].statuses) { interrupt(&s, ctx, i, kit) }

        // 3. 経路ヒット突進
        stepSweep(&s, ctx, i, kit)

        // 4. 遅延・連撃
        fireTimers(&s, ctx, i, kit, dt: dt, eps: eps)

        // 5. 再使用の窓
        for idx in 0..<(s.units[i].hero?.kit?.windows.count ?? 0) {
            guard let w = s.units[i].hero?.kit?.windows[idx], w.stage > 0, let slot = SkillSlot(rawValue: idx) else {
                continue
            }
            let left = w.remaining - dt
            if left <= eps {
                Kit.closeRecast(&s, ctx, caster: i, slot: slot, expired: true)
            } else {
                s.units[i].hero?.kit?.windows[idx].remaining = left
            }
        }

        // 6. キット固有
        guard CombatSystem.isLiving(s, i) else { return }
        kit.update(&s, ctx, owner: i)
    }

    // MARK: - 中断

    static func interrupt(_ s: inout SimState, _ ctx: SimContext, _ i: Int, _ kit: any HeroKit) {
        guard var k = s.units[i].hero?.kit else { return }
        var cancelled = false
        if let sw = k.sweep, sw.interruptible {
            k.sweep = nil
            cancelled = true
            // 突進そのものも止める（自分で押し出されている最中は触らない）
            if let d = s.units[i].displacement, d.kind == .dash { s.units[i].displacement = nil }
        }
        let before = k.scheduled.count
        if before > 0 { k.scheduled.removeAll { $0.interruptible } }
        if k.scheduled.count != before { cancelled = true }
        guard cancelled else { return }
        s.units[i].hero?.kit = k
        kit.onInterrupted(&s, ctx, owner: i)
    }

    // MARK: - 遅延・連撃

    static func fireTimers(_ s: inout SimState, _ ctx: SimContext, _ i: Int, _ kit: any HeroKit, dt: Double,
                           eps: Double) {
        // 予約が無い tick は何もコピーしない（ほとんどの tick）
        guard let count = s.units[i].hero?.kit?.scheduled.count, count > 0 else { return }
        // 時間を進めるだけで、発火するものが無ければ配列を組み直さない（in-place）
        var anyDue = false
        for n in 0..<count {
            s.units[i].hero!.kit!.scheduled[n].remaining -= dt
            if s.units[i].hero!.kit!.scheduled[n].remaining <= eps { anyDue = true }
        }
        guard anyDue, var k = s.units[i].hero?.kit else { return }
        var due: [KitTimer] = []
        var keep: [KitTimer] = []
        for t in k.scheduled {
            if t.remaining <= eps { due.append(t) } else { keep.append(t) }
        }
        k.scheduled = keep
        s.units[i].hero?.kit = k
        // 発火中に積まれた remaining 0 のタイマーも同 tick に消化する（暴走防止に 4 巡まで）
        var rounds = 0
        while !due.isEmpty {
            for t in due {
                guard CombatSystem.isLiving(s, i) else { return }
                kit.onTimer(&s, ctx, owner: i, timer: t)
            }
            rounds += 1
            guard rounds < 4, var again = s.units[i].hero?.kit else { return }
            due.removeAll(keepingCapacity: true)
            var rest: [KitTimer] = []
            for t in again.scheduled {
                if t.remaining <= eps { due.append(t) } else { rest.append(t) }
            }
            if !due.isEmpty {
                again.scheduled = rest
                s.units[i].hero?.kit = again
            }
        }
    }

    // MARK: - 経路ヒット突進

    /// prevPos → pos の線分上の敵に 1 度ずつ当てる。着地（強制移動の終了）で sweep を外して arriveCode のタイマーを呼ぶ。
    static func stepSweep(_ s: inout SimState, _ ctx: SimContext, _ i: Int, _ kit: any HeroKit) {
        guard let sw = s.units[i].hero?.kit?.sweep else { return }
        // 別の強制移動（ノックバック）に置き換えられた: 突進は終わり
        if let d = s.units[i].displacement, d.kind == .knockback {
            s.units[i].hero?.kit?.sweep = nil
            kit.onInterrupted(&s, ctx, owner: i)
            return
        }
        let a = s.units[i].prevPos
        let b = s.units[i].pos
        let team = s.units[i].team
        let ab = b - a
        let lenSq = ab.lengthSquared
        var hits: [(along: Double, index: Int)] = []
        for j in s.units.indices where s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j), !sw.hitIDs.contains(s.units[j].id) else { continue }
            if sw.payload.heroesOnly && s.units[j].kind != .hero { continue }
            guard sw.payload.affectsEnemies else { continue }
            let reach = sw.radius + s.units[j].radius
            guard distancePointToSegment(s.units[j].pos, a, b) <= reach else { continue }
            let along = lenSq > 1e-9 ? max(0, min(1, (s.units[j].pos - a).dot(ab) / lenSq)) : 0
            hits.append((along, j))
        }
        if hits.count > 1 { hits.sort { $0.along != $1.along ? $0.along < $1.along : $0.index < $1.index } }

        let arrived = s.units[i].displacement == nil
        if arrived {
            s.units[i].hero?.kit?.sweep = nil
        } else {
            let ids = hits.map { s.units[$0.index].id }
            s.units[i].hero?.kit?.sweep?.hitIDs.append(contentsOf: ids)
        }
        let casterID = s.units[i].id
        for h in hits {
            CombatSystem.applyHit(&s, ctx, sourceID: casterID, team: team, targetIndex: h.index, payload: sw.payload,
                                  from: a)
        }
        if arrived, sw.arriveCode != 0, CombatSystem.isLiving(s, i) {
            kit.onTimer(&s, ctx, owner: i,
                        timer: KitTimer(code: sw.arriveCode, slot: sw.slot, remaining: 0, interruptible: false))
        }
    }

    // MARK: - 再使用の振り分け

    /// 窓が開いている間の同じ `castSkill`。照準が決まらなければ失敗（窓はそのまま）。CD・コストは消費しない。
    static func recast(_ s: inout SimState, _ ctx: SimContext, kit: any HeroKit, caster i: Int, check: SkillCastCheck,
                       window: RecastWindow, target: SkillTarget) -> Bool {
        let stage = window.stage
        let targeting = HeroKits.targeting(for: check.skill, hero: check.def, stage: stage)
        let numbers = HeroKits.numbers(for: check.skill, hero: check.def, rank: check.rank, stats: s.units[i].stats,
                                       stage: stage)
        guard let aim = SkillAiming.resolve(s, ctx, caster: i, targeting: targeting, target: target, slot: check.slot,
                                            stage: stage) else { return false }
        s.units[i].windupRemaining = nil
        s.units[i].facing = aim.direction.angle
        SkillPassives.breakStealth(&s, i)
        let c = KitCast(caster: i, slot: check.slot, stage: stage, check: check, targeting: targeting, numbers: numbers,
                        aim: aim)
        kit.recast(&s, ctx, c, window: window)
        return true
    }

    // MARK: - 死亡

    /// 死亡で全リセット（DeathSystem.heroDeath から）。キットが残したいものは onDeath で書き戻す。
    static func heroDied(_ s: inout SimState, _ ctx: SimContext, hero i: Int) {
        guard let old = s.units[i].hero?.kit else { return }
        // 死んだ術者が掛けていた suppress は解ける（解除不可の拘束が術者の死後に残らない。ゴルムの奥義など）
        Kit.releaseSuppress(&s, bySource: s.units[i].id)
        var fresh = KitState()
        HeroKits.kit(in: s, i)?.onDeath(old: old, into: &fresh)
        s.units[i].hero?.kit = fresh
    }
}
