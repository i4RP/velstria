import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// ダメージ補正（DamageScaling）と命中時の追加効果（HitEffect）。HitPayload に載り、CombatSystem.applyHit が評価する。
// scaling は dealDamage の前（payload.damage を補正）、effects は命中の後（HP 減少量 dealt を使える）。

/// 命中時に追加で起きること（HitPayload.effects。順に適用する）。
public enum HitEffect: Codable, Hashable, Sendable {
    /// 打ち上げ（.airborne）。CC 無効・無敵には効かない。
    case knockUp(duration: Double)
    /// 所有者の位置へ引き寄せる。gap = 止まる位置の端同士の隙間（所有者・対象の半径は自動で足す）。
    case pullToOwner(distance: Double, duration: Double, gap: Double)
    /// 所有者から遠ざけるように押し出す。
    case pushAway(distance: Double, duration: Double)
    /// マークを積む（name は KitTags.mark の name。所有者ごとに分かれる）。
    case addMark(name: String, stacks: Int, maxStacks: Int, duration: Double)
    /// 所有者を回復する（flat + 与えたダメージ × ratio）。
    case healOwner(flat: Double, ratioOfDealt: Double)
    /// 所有者のスキルのクールダウンを縮める。
    case refundCooldown(slot: SkillSlot, seconds: Double)
}

/// ダメージの補正（HitPayload.scaling）。payload.damage > 0 のときだけ評価する。
public enum DamageScaling: Codable, Hashable, Sendable {
    /// 失った HP の割合に応じて増える: 倍率 = 1 + maxBonus × (1 − HP 割合)。
    case missingHealth(maxBonus: Double)
    /// 対象の最大 HP の割合を加算する（軽減前）。
    case maxHealth(ratio: Double)
    /// 発射位置（originPos、なければ所有者の位置）からの距離で増減: near 以下で minMult、far 以上で maxMult、間は線形。
    case distance(near: Double, far: Double, minMult: Double, maxMult: Double)
    /// 所有者が積んだマークの数で増える: 倍率 = 1 + perStack × スタック数。consume でヒット後にマークを消費する。
    case marks(name: String, perStack: Double, consume: Bool)
}

extension HitPayload {
    /// 命中時にキット側の処理が要るか（applyHit の hot path を軽く保つ）。
    @inline(__always)
    var hasKitPart: Bool { !effects.isEmpty || scaling != nil || kitEvent != 0 }
}

enum KitDamage {
    /// scaling を反映したダメージ（dealDamage の前に評価する。HP・マークはダメージを与える前の値）。
    static func scaledDamage(_ s: SimState, sourceID: EntityID?, target t: Int, payload: HitPayload) -> Double {
        guard let sc = payload.scaling, payload.damage > 0 else { return payload.damage }
        let owner = s.index(of: sourceID)
        switch sc {
        case .missingHealth(let maxBonus):
            return payload.damage * (1 + max(0, maxBonus) * (1 - min(1, max(0, s.units[t].hpRatio))))
        case .maxHealth(let ratio):
            return payload.damage + s.units[t].stats.maxHP * max(0, ratio)
        case .distance(let near, let far, let minMult, let maxMult):
            guard let origin = payload.originPos ?? owner.map({ s.units[$0].pos }) else { return payload.damage }
            let d = origin.distance(to: s.units[t].pos)
            let f = far > near ? min(1, max(0, (d - near) / (far - near))) : (d >= far ? 1 : 0)
            return payload.damage * (minMult + (maxMult - minMult) * f)
        case .marks(let name, let perStack, _):
            guard let owner, let heroID = s.units[owner].hero?.heroID else { return payload.damage }
            let tag = KitTags.mark(heroID, name, owner: s.units[owner].id)
            return payload.damage * (1 + perStack * Double(Kit.markStacks(s, target: t, tag: tag)))
        }
    }

    /// 命中の後始末: マークの消費・追加効果・キットの onHit。ダメージを与えた後に呼ぶ（dealt = 実際に減った量）。
    static func afterHit(_ s: inout SimState, _ ctx: SimContext, sourceID: EntityID?, target t: Int,
                         payload: HitPayload, dealt: Double, from: Vec2) {
        let owner = s.index(of: sourceID)
        if case .marks(let name, _, let consume)? = payload.scaling, consume, let owner,
           let heroID = s.units[owner].hero?.heroID {
            Kit.consumeMarks(&s, target: t, tag: KitTags.mark(heroID, name, owner: s.units[owner].id))
        }
        for effect in payload.effects {
            apply(&s, ctx, effect, owner: owner, ownerID: sourceID, target: t, dealt: dealt, from: from)
        }
        if payload.kitEvent != 0, let owner, let kit = HeroKits.kit(in: s, owner) {
            kit.onHit(&s, ctx, owner: owner, target: t, event: payload.kitEvent, dealt: dealt)
        }
    }

    static func apply(_ s: inout SimState, _ ctx: SimContext, _ effect: HitEffect, owner: Int?, ownerID: EntityID?,
                      target t: Int, dealt: Double, from: Vec2) {
        switch effect {
        case .knockUp(let duration):
            guard CombatSystem.isLiving(s, t) else { return }
            Kit.knockUp(&s, target: t, duration: duration, sourceID: ownerID)
        case .pullToOwner(let distance, let duration, let gap):
            guard let owner, CombatSystem.isLiving(s, t) else { return }
            Kit.pull(&s, ctx, target: t, toward: s.units[owner].pos, distance: distance, duration: duration,
                     gap: s.units[owner].radius + s.units[t].radius + max(0, gap))
        case .pushAway(let distance, let duration):
            guard CombatSystem.isLiving(s, t) else { return }
            let origin = owner.map { s.units[$0].pos } ?? from
            let facing = owner.map { Vec2.fromAngle(s.units[$0].facing) } ?? Vec2(1, 0)
            Kit.pushAway(&s, ctx, target: t, from: origin, distance: distance, duration: duration,
                         fallbackDirection: facing)
        case .addMark(let name, let stacks, let maxStacks, let duration):
            guard let owner, let heroID = s.units[owner].hero?.heroID else { return }
            Kit.addMark(&s, target: t, ownerID: s.units[owner].id, tag: KitTags.mark(heroID, name, owner: s.units[owner].id),
                        stacks: stacks, maxStacks: maxStacks, duration: duration)
        case .healOwner(let flat, let ratio):
            guard let owner else { return }
            CombatSystem.heal(&s, ctx, sourceID: s.units[owner].id, targetIndex: owner, amount: flat + dealt * ratio)
        case .refundCooldown(let slot, let seconds):
            guard let owner else { return }
            Kit.refundCooldown(&s, ctx, caster: owner, slot: slot, seconds: seconds)
        }
    }
}
