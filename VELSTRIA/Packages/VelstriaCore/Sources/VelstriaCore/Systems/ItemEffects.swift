import Foundation

// 担当: core-economy
// 装備の固有効果（Mobile Legends の装備に倣った作り直し、2026-10。仕様と係数は tools/equipment_spec.mjs）。
// 能力値（攻撃・貫通・吸血など）は ItemStats が足す。ここは「命中したら」「スキルを使ったら」などの振る舞いを持つ効果だけ。
// 効果の種類は ItemDef.effectID（= ItemEffectKind の rawValue）、係数は ItemDef.effectValues。同じ種類を持つ装備を複数持っても 1 つだけ働く。
//
// 確定ダメージを与えるもの: 裁きの一撃（divineJustice）、急襲の牙（breakout）、焼灼（incineration の燃焼）。
// 貫通は能力値（Stats.armorPen* / magicPen*）で、CombatSystem.dealDamage が防御軽減の前に適用する。
// 追加ダメージは DamageSource.item で与える（通常攻撃の命中・奇襲の消費・報復の反射の対象外）。

public enum ItemEffectKind: String, CaseIterable, Codable, Hashable, Sendable {
    // Attack
    case typhoon, steamRoller, hunt, frenzy, divineJustice, despair, eradication
    // Magic
    case geniusShred, incineration, iceBond, antiHeal, echo, bloodWings, reload
    // Defense
    case counter, intimidation, thunder, cursedAura, athena, demonization, twilight, dominance
    // Movement / Utility / Jungle
    case demonShoes, lifeLine, enthusiasm, timeCurrent, immortal, impulse, breakout

    /// `ItemRuntime.readyAt` の添字。
    var slot: Int { ItemEffectKind.slots[self] ?? 0 }
    private static let slots: [ItemEffectKind: Int] = {
        var m: [ItemEffectKind: Int] = [:]
        for (k, c) in allCases.enumerated() { m[c] = k }
        return m
    }()
}

/// ヒーローごとの装備効果の状態（クールダウン・窓・連続命中）。
public struct ItemRuntime: Codable, Hashable, Sendable {
    /// 効果ごとの「次に働ける時刻」（`ItemEffectKind.slot` の添字。足りない分は 0）。
    public var readyAt: [Double] = []
    /// スキル発動後の「次の通常攻撃」を強化する窓の終わり（裁きの一撃）。
    public var armedUntil: Double = 0
    /// 追跡の狩り: 連続で通常攻撃を当てている敵と回数。
    public var hitTargetID: EntityID?
    public var hitCount: Int = 0
    /// 魔人化: 効果の終わり。
    public var buffUntil: Double = 0

    public init() {}

    func ready(_ k: ItemEffectKind, at now: Double) -> Bool {
        let i = k.slot
        return i >= readyAt.count || now + 1e-9 >= readyAt[i]
    }

    mutating func setReady(_ k: ItemEffectKind, at t: Double) {
        let i = k.slot
        if readyAt.count <= i { readyAt.append(contentsOf: [Double](repeating: 0, count: i + 1 - readyAt.count)) }
        readyAt[i] = t
    }
}

public enum ItemEffects {
    typealias Active = (kind: ItemEffectKind, v: [Double])

    /// ヒーローが持つ効果（同じ種類は 1 つだけ。装備の並び順）。
    static func active(_ u: Unit, _ master: MasterData) -> [Active] {
        guard let items = u.hero?.items, !items.isEmpty else { return [] }
        var out: [Active] = []
        for id in items {
            guard let it = master.item(id), !it.effectID.isEmpty, let k = ItemEffectKind(rawValue: it.effectID),
                  !out.contains(where: { $0.kind == k }) else { continue }
            out.append((k, it.effectValues))
        }
        return out
    }

    /// 効果 kind の係数（持っていなければ nil）。
    static func values(_ kind: ItemEffectKind, of u: Unit, _ master: MasterData) -> [Double]? {
        guard let items = u.hero?.items else { return nil }
        for id in items {
            if let it = master.item(id), it.effectID == kind.rawValue { return it.effectValues }
        }
        return nil
    }

    // MARK: - 能力値への反映（ItemStats から）

    /// 魔力から最大 HP への換算（血翼の共鳴）。ルーン反映後の魔力で計算する。
    static func bloodWingsHP(items: [String], abilityPower: Double, master: MasterData) -> Double {
        for id in items {
            if let it = master.item(id), it.effectID == ItemEffectKind.bloodWings.rawValue, let r = it.effectValues.first {
                return abilityPower * r
            }
        }
        return 0
    }

    // MARK: - 与ダメ・被ダメ・吸血

    /// 与ダメ補正（断罪の刃: HP が閾値以下の敵へ +25%）。
    static func outgoingDamageBonus(_ s: SimState, _ ctx: SimContext, attacker a: Int, target t: Int) -> Double {
        guard s.units[a].kind == .hero, let v = values(.despair, of: s.units[a], ctx.master), v.count >= 2 else { return 0 }
        return s.units[t].hpRatio <= v[0] ? v[1] : 0
    }

    /// 通常攻撃・スキルの吸血への加算（高揚: HP が低いと +、魔人化: 発動中 +）。
    static func lifestealBonus(_ s: SimState, _ ctx: SimContext, attacker a: Int) -> Double {
        guard s.units[a].kind == .hero, let h = s.units[a].hero, !h.items.isEmpty else { return 0 }
        var r = 0.0
        if let v = values(.enthusiasm, of: s.units[a], ctx.master), v.count >= 2, s.units[a].hpRatio <= v[0] { r += v[1] }
        if s.time < h.itemRuntime.buffUntil, let v = values(.demonization, of: s.units[a], ctx.master), v.count >= 3 { r += v[2] }
        return r
    }

    /// 被ダメ（防御・軽減の後、シールドの前）の補正。黄昏の挑戦: 物理 1 発の上限、魔人化: 発動中の軽減。
    static func modifyIncoming(_ s: SimState, _ ctx: SimContext, victim t: Int, type: DamageType, amount: Double) -> Double {
        guard s.units[t].kind == .hero, let h = s.units[t].hero, !h.items.isEmpty else { return amount }
        var out = amount
        if type == .physical, let v = values(.twilight, of: s.units[t], ctx.master), let cap = v.first { out = min(out, cap) }
        if s.time < h.itemRuntime.buffUntil, let v = values(.demonization, of: s.units[t], ctx.master), v.count >= 2 {
            out *= max(0, 1 - v[1])
        }
        return out
    }

    // MARK: - 通常攻撃

    /// クリティカルが出た時（狂乱の連撃: 攻撃速度 +）。
    static func onCrit(_ s: inout SimState, _ ctx: SimContext, attacker a: Int) {
        guard s.units[a].kind == .hero, let v = values(.frenzy, of: s.units[a], ctx.master), v.count >= 2 else { return }
        CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .attackSpeedBoost, duration: v[1], magnitude: v[0],
                                                                sourceID: s.units[a].id, tag: "item.frenzy"))
    }

    /// 通常攻撃が命中した時（ダメージ適用の後）。確定ダメージ・追加ダメージ・連続命中・周囲への連鎖。
    static func onBasicAttackLanded(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int, dealt: Double) {
        guard s.units[a].kind == .hero, s.units[a].hero?.items.isEmpty == false else { return }
        let effects = active(s.units[a], ctx.master)
        guard !effects.isEmpty, s.units[t].team != s.units[a].team else { return }
        let now = s.time
        let attackerID = s.units[a].id
        let targetID = s.units[t].id

        for (kind, v) in effects {
            guard CombatSystem.isLiving(s, a) else { return }
            switch kind {
            case .hunt:
                // 同じ敵への連続命中を数える（別の敵を殴るとやり直し）
                var h = s.units[a].hero!.itemRuntime
                h.hitCount = h.hitTargetID == targetID ? h.hitCount + 1 : 1
                h.hitTargetID = targetID
                if v.count >= 4, h.hitCount >= Int(v[0]), h.ready(.hunt, at: now) {
                    h.hitCount = 0
                    h.setReady(.hunt, at: now + v[3])
                    s.units[a].hero!.itemRuntime = h
                    CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .speedBoost, duration: v[2], magnitude: v[1],
                                                                            sourceID: attackerID, tag: "item.hunt"))
                } else {
                    s.units[a].hero!.itemRuntime = h
                }
            case .typhoon where v.count >= 3:
                guard s.units[a].hero!.itemRuntime.ready(.typhoon, at: now) else { break }
                s.units[a].hero!.itemRuntime.setReady(.typhoon, at: now + v[0])
                let center = s.units[t].pos
                let team = s.units[a].team
                var hit = 0
                for j in s.units.indices where j != t && hit < Int(v[2]) {
                    guard CombatSystem.isLiving(s, j), s.units[j].team != team, s.units[j].team != .neutral || s.units[j].kind == .monster,
                          s.units[j].kind == .hero || s.units[j].kind == .minion || s.units[j].kind == .monster,
                          s.units[j].pos.distanceSquared(to: center) <= 450 * 450 else { continue }
                    hit += 1
                    CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: j, amount: v[1], type: .magic,
                                            source: .item, isCrit: false, appliesOnHit: false)
                }
            case .divineJustice where v.count >= 5:
                let rt = s.units[a].hero!.itemRuntime
                guard now <= rt.armedUntil + 1e-9, rt.ready(.divineJustice, at: now), CombatSystem.isLiving(s, t) else { break }
                s.units[a].hero!.itemRuntime.armedUntil = 0
                s.units[a].hero!.itemRuntime.setReady(.divineJustice, at: now + v[2])
                let attack = s.units[a].stats.attack
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: attack * v[0], type: .trueDamage,
                                        source: .item, isCrit: false, appliesOnHit: false)
                CombatSystem.heal(&s, ctx, sourceID: attackerID, targetIndex: a, amount: v[3] + attack * v[4])
            case .eradication where v.count >= 2:
                guard CombatSystem.isLiving(s, t) else { break }
                var extra = max(0, s.units[t].hp) * v[0]
                if s.units[t].kind == .monster { extra = min(extra, v[1]) }
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: extra, type: .physical,
                                        source: .item, isCrit: false, appliesOnHit: false)
            case .thunder where v.count >= 4:
                guard s.units[a].hero!.itemRuntime.ready(.thunder, at: now), CombatSystem.isLiving(s, t) else { break }
                s.units[a].hero!.itemRuntime.setReady(.thunder, at: now + v[3])
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: s.units[a].stats.maxHP * v[0],
                                        type: .physical, source: .item, isCrit: false, appliesOnHit: false)
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: v[2], magnitude: v[1],
                                                                        sourceID: attackerID, tag: "item.thunder"))
            case .breakout where v.count >= 5:
                guard s.units[a].hero!.itemRuntime.ready(.breakout, at: now), CombatSystem.isLiving(s, t) else { break }
                s.units[a].hero!.itemRuntime.setReady(.breakout, at: now + v[0])
                let level = Double(s.units[a].hero?.level ?? 1)
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: v[1] + v[2] * (level - 1),
                                        type: .trueDamage, source: .item, isCrit: false, appliesOnHit: false)
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: v[4], magnitude: v[3],
                                                                        sourceID: attackerID, tag: "item.breakout"))
            default:
                break
            }
        }
    }

    // MARK: - スキル

    /// スキルを使った時（裁きの一撃の窓を開く）。
    static func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster c: Int) {
        guard s.units[c].kind == .hero, let v = values(.divineJustice, of: s.units[c], ctx.master), v.count >= 2 else { return }
        s.units[c].hero?.itemRuntime.armedUntil = s.time + v[1]
    }

    /// スキルが敵に命中した時。防御・魔防の低下、燃焼、減速、回復阻害、残響。
    static func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int) {
        guard s.units[a].kind == .hero, s.units[a].hero?.items.isEmpty == false,
              s.units[t].team != s.units[a].team, CombatSystem.isLiving(s, t) else { return }
        let effects = active(s.units[a], ctx.master)
        guard !effects.isEmpty else { return }
        let now = s.time
        let attackerID = s.units[a].id
        for (kind, v) in effects {
            switch kind {
            case .steamRoller where v.count >= 2:
                // 固定値 v[0] の防御低下を、現在の防御に対する割合として与える（armorShred は割合）
                let armor = s.units[t].stats.armor
                guard armor > 0 else { break }
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .armorShred, duration: v[1],
                                                                        magnitude: min(1, v[0] / armor),
                                                                        sourceID: attackerID, tag: "item.steamRoller"))
            case .geniusShred where v.count >= 4:
                let level = Double(s.units[a].hero?.level ?? 1)
                let per = v[0] + (v[1] - v[0]) * (level - 1) / Double(max(1, Balance.maxLevel - 1))
                let cur = s.units[t].statuses.first { $0.kind == .magicShred && $0.tag == "item.geniusShred" }?.magnitude ?? 0
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .magicShred, duration: v[3],
                                                                        magnitude: min(per * v[2], cur + per),
                                                                        sourceID: attackerID, tag: "item.geniusShred"))
            case .incineration where v.count >= 3:
                let total = max(v[2], max(0, s.units[t].hp) * v[1])
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .burn, duration: v[0], magnitude: total / v[0],
                                                                        sourceID: attackerID, tag: "item.incineration"))
            case .iceBond where v.count >= 3:
                let cur = s.units[t].statuses.first { $0.kind == .slow && $0.tag == "item.iceBond" }?.magnitude ?? 0
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: v[1],
                                                                        magnitude: min(v[0] * v[2], cur + v[0]),
                                                                        sourceID: attackerID, tag: "item.iceBond"))
            case .antiHeal where v.count >= 2:
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .healReduction, duration: v[1], magnitude: v[0],
                                                                        sourceID: attackerID, tag: "item.antiHeal"))
            case .echo where v.count >= 3:
                guard s.units[a].hero!.itemRuntime.ready(.echo, at: now) else { break }
                s.units[a].hero!.itemRuntime.setReady(.echo, at: now + v[0])
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t,
                                        amount: v[1] + v[2] * s.units[a].stats.abilityPower, type: .magic,
                                        source: .item, isCrit: false, appliesOnHit: false)
            default:
                break
            }
        }
    }

    // MARK: - 被ダメ・死亡

    /// 被ダメージの後（victim はヒーロー）。反撃・威圧・衝動・命綱・魔人化。
    static func onDamageTaken(_ s: inout SimState, _ ctx: SimContext, victim t: Int, attacker a: Int?, dealt: Double,
                              source: DamageSource) {
        guard s.units[t].kind == .hero, s.units[t].hero?.items.isEmpty == false, dealt > 0,
              CombatSystem.isLiving(s, t) else { return }
        let effects = active(s.units[t], ctx.master)
        guard !effects.isEmpty else { return }
        let now = s.time
        let victimID = s.units[t].id
        let hostile = a.map { s.units[$0].team != s.units[t].team } ?? false
        for (kind, v) in effects {
            guard CombatSystem.isLiving(s, t) else { return }
            switch kind {
            case .counter where v.count >= 1:
                guard hostile, let a, source == .basicAttack, !s.units[a].isStructure, CombatSystem.isLiving(s, a) else { break }
                CombatSystem.dealDamage(&s, ctx, sourceID: victimID, targetIndex: a, amount: s.units[a].stats.attack * v[0],
                                        type: .physical, source: .passive, isCrit: false, appliesOnHit: false)
            case .intimidation where v.count >= 3:
                guard hostile, let a, source == .basicAttack, s.units[a].kind == .hero else { break }
                let cur = s.units[a].statuses.first { $0.kind == .damageDealtReduction && $0.tag == "item.intimidation" }?.magnitude ?? 0
                CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .damageDealtReduction, duration: v[2],
                                                                        magnitude: min(v[0] * v[1], cur + v[0]),
                                                                        sourceID: victimID, tag: "item.intimidation"))
            case .impulse where v.count >= 4:
                guard hostile, dealt >= s.units[t].stats.maxHP * v[0], s.units[t].hero!.itemRuntime.ready(.impulse, at: now) else { break }
                s.units[t].hero!.itemRuntime.setReady(.impulse, at: now + 6)
                for j in aoeTargets(s, team: s.units[t].team, center: s.units[t].pos, radius: v[2]) {
                    CombatSystem.dealDamage(&s, ctx, sourceID: victimID, targetIndex: j, amount: v[1], type: .magic,
                                            source: .item, isCrit: false, appliesOnHit: false)
                    CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(kind: .slow, duration: 1.5, magnitude: v[3],
                                                                            sourceID: victimID, tag: "item.impulse"))
                }
            case .lifeLine where v.count >= 5:
                guard s.units[t].hpRatio < v[0], s.units[t].hero!.itemRuntime.ready(.lifeLine, at: now) else { break }
                s.units[t].hero!.itemRuntime.setReady(.lifeLine, at: now + v[4])
                CombatSystem.addShield(&s, ctx, sourceID: victimID, targetIndex: t,
                                       amount: v[1] + v[2] * s.units[t].stats.maxHP, duration: v[3], tag: "item.lifeLine")
            case .demonization where v.count >= 5:
                guard s.units[t].hpRatio < v[0], s.units[t].hero!.itemRuntime.ready(.demonization, at: now) else { break }
                s.units[t].hero!.itemRuntime.buffUntil = now + v[3]
                s.units[t].hero!.itemRuntime.setReady(.demonization, at: now + v[4])
            default:
                break
            }
        }
    }

    /// 致命傷を受けた時に踏みとどまるか（不死の祝福）。true なら死亡させない。
    static func preventDeath(_ s: inout SimState, _ ctx: SimContext, victim t: Int) -> Bool {
        guard s.units[t].kind == .hero, s.units[t].hero?.items.isEmpty == false,
              let v = values(.immortal, of: s.units[t], ctx.master), v.count >= 4,
              s.units[t].hero!.itemRuntime.ready(.immortal, at: s.time) else { return false }
        s.units[t].hero!.itemRuntime.setReady(.immortal, at: s.time + v[3])
        s.units[t].hp = max(1, s.units[t].stats.maxHP * v[0])
        CombatSystem.addShield(&s, ctx, sourceID: s.units[t].id, targetIndex: t, amount: v[1], duration: v[2], tag: "item.immortal")
        return true
    }

    // MARK: - キル・アシスト

    /// 敵ヒーローを倒した・アシストした時（魔性の恩恵: 回復、時の潮流: 必殺技の CD 短縮）。
    static func onKillOrAssist(_ s: inout SimState, _ ctx: SimContext, hero i: Int) {
        guard s.units[i].kind == .hero, s.units[i].hero?.items.isEmpty == false, CombatSystem.isLiving(s, i) else { return }
        let id = s.units[i].id
        if let v = values(.demonShoes, of: s.units[i], ctx.master), let r = v.first {
            CombatSystem.heal(&s, ctx, sourceID: id, targetIndex: i, amount: s.units[i].stats.maxHP * r)
        }
        if let v = values(.timeCurrent, of: s.units[i], ctx.master), let r = v.first {
            let slot = SkillSlot.ultimate.rawValue
            if let cd = s.units[i].hero?.skillCooldowns[slot], cd > 0 { s.units[i].hero?.skillCooldowns[slot] = cd * (1 - r) }
        }
    }

    /// 敵ヒーローを倒した時（再装填: 最大 HP の割合を回復）。
    static func onKill(_ s: inout SimState, _ ctx: SimContext, hero i: Int) {
        guard s.units[i].kind == .hero, s.units[i].hero?.items.isEmpty == false, CombatSystem.isLiving(s, i),
              let v = values(.reload, of: s.units[i], ctx.master), let r = v.first else { return }
        CombatSystem.heal(&s, ctx, sourceID: s.units[i].id, targetIndex: i, amount: s.units[i].stats.maxHP * r)
    }

    // MARK: - 毎 tick

    /// 守護の盾（一定間隔のシールド）、呪いの怨嗟・凍てつく威圧（周囲への継続効果）。
    static func update(_ s: inout SimState, _ ctx: SimContext, hero i: Int) {
        guard s.units[i].hero?.items.isEmpty == false, CombatSystem.isLiving(s, i) else { return }
        let effects = active(s.units[i], ctx.master)
        guard !effects.isEmpty else { return }
        let now = s.time
        let id = s.units[i].id
        for (kind, v) in effects {
            switch kind {
            case .athena where v.count >= 4:
                guard s.units[i].hero!.itemRuntime.ready(.athena, at: now) else { break }
                s.units[i].hero!.itemRuntime.setReady(.athena, at: now + v[0])
                let amount = min(v[3], v[1] + v[2] * now / 60)
                CombatSystem.addShield(&s, ctx, sourceID: id, targetIndex: i, amount: amount, duration: v[0] - 1, tag: "item.athena")
            case .cursedAura where v.count >= 4:
                guard s.units[i].hero!.itemRuntime.ready(.cursedAura, at: now) else { break }
                s.units[i].hero!.itemRuntime.setReady(.cursedAura, at: now + 1)
                for j in aoeTargets(s, team: s.units[i].team, center: s.units[i].pos, radius: v[2]) {
                    var dmg = v[0] + v[1] * s.units[j].stats.maxHP
                    if s.units[j].kind == .minion { dmg *= 1 + v[3] }
                    CombatSystem.dealDamage(&s, ctx, sourceID: id, targetIndex: j, amount: dmg, type: .magic,
                                            source: .item, isCrit: false, appliesOnHit: false)
                }
            case .dominance where v.count >= 3:
                guard s.units[i].hero!.itemRuntime.ready(.dominance, at: now) else { break }
                s.units[i].hero!.itemRuntime.setReady(.dominance, at: now + 0.5)
                for j in aoeTargets(s, team: s.units[i].team, center: s.units[i].pos, radius: v[0]) where s.units[j].kind == .hero {
                    CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(kind: .attackSpeedBoost, duration: 0.7, magnitude: -v[1],
                                                                            sourceID: id, tag: "item.dominance"))
                    CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(kind: .slow, duration: 0.7, magnitude: v[2],
                                                                            sourceID: id, tag: "item.dominance"))
                }
            default:
                break
            }
        }
    }

    /// center の周囲 radius にいる、team から見た敵（ヒーロー・ミニオン・モンスター。構造物は除く）。
    static func aoeTargets(_ s: SimState, team: Team, center: Vec2, radius: Double) -> [Int] {
        var out: [Int] = []
        let r2 = radius * radius
        for j in s.units.indices where CombatSystem.isLiving(s, j) {
            let u = s.units[j]
            guard u.team != team, u.kind == .hero || u.kind == .minion || u.kind == .monster,
                  !u.has(.invulnerable), u.pos.distanceSquared(to: center) <= r2 else { continue }
            out.append(j)
        }
        return out
    }
}
