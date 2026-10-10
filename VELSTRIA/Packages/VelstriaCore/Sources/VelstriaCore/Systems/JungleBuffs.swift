import Foundation

// 担当: core-world
// ジャングルのバフ（MLBB の現行マップに合わせた効果。docs/DESIGN.md §2・§4、定数は Balance.Jungle）。
//   紫バフ（蒼晶の番人）: スキルの再使用時間 −10%・消費 Mana −60% / Energy −25%・敵を倒すと回復
//   赤バフ（紅焔の番人）: 敵ヒーローに攻撃が当たると溶岩の魂が追撃（確定ダメージ + スロー、3 秒毎）・適応貫通
//   回復バフ（小キャンプの主・蒼晶の仔）: 350 HP と最大 Mana の 5%
//   Gold バフ（宝殻蟹）: 一定時間 Gold が入り続ける
//   苔草（苔甲の徘徊者）: 川で移動速度 +15%・近くの味方の Mana 回復
//   星喰竜の加護: 撃破者に張り直すシールドと攻撃力、味方に一度きりのシールド

public enum JungleBuffs {
    /// 星喰竜の撃破者のシールド（張り直す）と、味方の一度きりのシールドのタグ。
    static let wyrmShieldTag = "wyrm_shield"
    static let wyrmAllyShieldTag = "wyrm_ally_shield"
    /// 棘角トカゲの硬化（被ダメ軽減）のタグ。
    static let lizardHardenTag = "lizard_harden"

    // MARK: - 紫バフ

    /// スキルの消費の倍率（紫バフ: Mana −60% / Energy −25%）。
    public static func skillCostMultiplier(_ u: Unit) -> Double {
        guard u.has(.blueBuff), let h = u.hero else { return 1 }
        return h.resourceKind == .energy ? Balance.Jungle.purpleEnergyCostMultiplier : Balance.Jungle.purpleManaCostMultiplier
    }

    /// 撃破時の効果（DeathSystem が死亡 1 件ごとに呼ぶ）。紫バフを持つヒーローが敵を倒すと最大 HP の割合で回復。
    static func onKill(_ s: inout SimState, _ ctx: SimContext, victimIndex v: Int, killerID: EntityID?) {
        guard let k = s.index(of: killerID), s.units[k].kind == .hero, s.units[k].isAlive,
              s.units[k].hero?.isDead == false, s.units[k].has(.blueBuff),
              s.units[v].team != s.units[k].team else { return }
        let pct: Double
        switch s.units[v].kind {
        case .minion: pct = Balance.Jungle.purpleKillHealMinion
        case .hero: pct = Balance.Jungle.purpleKillHealHero
        case .monster: pct = Balance.Jungle.purpleKillHealMonster
        case .tower, .core, .dummy: return
        }
        CombatSystem.heal(&s, ctx, sourceID: nil, targetIndex: k, amount: s.units[k].stats.maxHP * pct)
    }

    // MARK: - 赤バフ

    /// 前衛（スロー強め・追撃弱め）か。ヴァンガード・デュエリスト・アサシンが前衛、レンジャー・アルカニスト・サポートが後衛。
    static func isFrontline(_ role: Role?) -> Bool {
        switch role {
        case .vanguard, .duelist, .assassin: return true
        case .ranger, .arcanist, .support, .none: return false
        }
    }

    /// 赤バフの付与（撃破者のロールで貫通の割合を決め、magnitude に入れる）。
    static func redBuff(for hero: Unit, sourceID: EntityID) -> StatusEffect {
        let pen = isFrontline(hero.hero?.role) ? Balance.Jungle.redFrontPenetration : Balance.Jungle.redBackPenetration
        return StatusEffect(kind: .redBuff, duration: Balance.Economy.sentinelBuffDuration, magnitude: pen,
                            sourceID: sourceID, tag: "sentinel")
    }

    /// 赤バフの追撃（CombatSystem.applyHit が、ヒーローの通常攻撃・スキルが敵ヒーローに当たった後に呼ぶ）。
    /// 3 秒に 1 回、確定ダメージ（50 + 物攻 × 割合 + 対象の最大 HP × 割合）とスロー 1 秒。
    /// 間隔は赤バフ自身の tickTimer に「次に撃てる時刻」として持つ（赤バフは燃焼ではないので tickTimer を使わない）。
    static func redBuffStrike(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int,
                              source: DamageSource) {
        switch source {
        case .basicAttack, .skill: break
        default: return
        }
        guard s.units[a].kind == .hero, s.units[t].kind == .hero, s.units[t].team != s.units[a].team,
              CombatSystem.isLiving(s, t),
              let k = s.units[a].statuses.firstIndex(where: { $0.kind == .redBuff }),
              s.time + CombatSystem.timeEpsilon >= s.units[a].statuses[k].tickTimer else { return }
        s.units[a].statuses[k].tickTimer = s.time + Balance.Jungle.redStrikeCooldown
        typealias J = Balance.Jungle
        let front = isFrontline(s.units[a].hero?.role)
        let damage = J.redStrikeBase
            + s.units[a].stats.attack * (front ? J.redFrontAttackRatio : J.redBackAttackRatio)
            + s.units[t].stats.maxHP * (front ? J.redFrontTargetHPRatio : J.redBackTargetHPRatio)
        let attackerID = s.units[a].id
        CombatSystem.applyDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: damage, type: .trueDamage,
                                 source: .passive)
        guard CombatSystem.isLiving(s, t) else { return }
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: J.redSlowDuration,
                                                                magnitude: front ? J.redFrontSlow : J.redBackSlow,
                                                                sourceID: attackerID, tag: CombatSystem.tagRedBuff))
    }

    // MARK: - 小キャンプ・宝殻蟹・徘徊者の報酬

    /// 回復バフ: 350 HP と最大 Mana の 5%（Energy のヒーローは HP のみ）。
    static func grantHealingBuff(_ s: inout SimState, _ ctx: SimContext, heroIndex k: Int) {
        guard s.units[k].isAlive, s.units[k].hero?.isDead == false else { return }
        CombatSystem.heal(&s, ctx, sourceID: nil, targetIndex: k, amount: Balance.Jungle.healingBuffHP)
        if s.units[k].hero?.resourceKind == .mana {
            let st = s.units[k].stats
            s.units[k].resource = min(st.maxResource, s.units[k].resource + st.maxResource * Balance.Jungle.healingBuffManaPct)
        }
    }

    /// Gold バフ（宝殻蟹）: total を duration 秒に均して入れる。
    static func grantGoldBuff(_ s: inout SimState, heroIndex k: Int, total: Double, duration: Double, sourceID: EntityID) {
        guard duration > 0, s.units[k].isAlive else { return }
        CombatSystem.addStatus(&s, targetIndex: k, StatusEffect(kind: .goldBuff, duration: duration,
                                                                magnitude: total / duration, sourceID: sourceID, tag: "crab"))
    }

    /// 苔草（苔甲の徘徊者）を撃破者に付け、近くの味方に少しの Gold。
    static func wandererReward(_ s: inout SimState, _ ctx: SimContext, killer k: Int?, team: Team, at pos: Vec2,
                               sourceID: EntityID) {
        if let k, s.units[k].isAlive {
            CombatSystem.addStatus(&s, targetIndex: k, StatusEffect(kind: .mossGrass, duration: Balance.Jungle.mossGrassDuration,
                                                                    sourceID: sourceID, tag: "moss"))
        }
        let r2 = Balance.Jungle.wandererAllyRadius * Balance.Jungle.wandererAllyRadius
        for i in s.heroIndices(team: team) where i != k && s.units[i].isAlive && s.units[i].pos.distanceSquared(to: pos) <= r2 {
            EconomyRewards.grantGold(&s, heroIndex: i, amount: Balance.Jungle.wandererAllyGold, at: pos)
        }
    }

    // MARK: - 星喰竜

    /// 星喰竜の報酬: チーム全員に Gold（撃破数で 60 / 70 / 80）と XP、撃破者に加護（張り直すシールド）、
    /// 撃破者以外の生存している味方に一度きりのシールド。`kills` は今回を含まない撃破数。
    static func wyrmReward(_ s: inout SimState, _ ctx: SimContext, team: Team, killer k: Int?, kills: Int,
                           sourceID: EntityID) {
        typealias J = Balance.Jungle
        let gold = J.wyrmTeamGold[min(kills, J.wyrmTeamGold.count - 1)]
        for i in s.heroIndices(team: team) {
            EconomyRewards.grantGold(&s, heroIndex: i, amount: gold)
            HeroGrowth.grantXP(&s, ctx, heroIndex: i, amount: Balance.Economy.wyrmTeamXP)
        }
        for i in s.heroIndices(team: team) where s.units[i].isAlive && s.units[i].hero?.isDead == false {
            let level = Double(s.units[i].hero?.level ?? 1)
            if i == k {
                let shield = J.wyrmShieldBase + J.wyrmShieldPerLevel * level
                CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .wyrmBlessing, duration: J.wyrmBlessingDuration,
                                                                        magnitude: shield, sourceID: sourceID, tag: "wyrm"))
                CombatSystem.addShield(&s, ctx, sourceID: nil, targetIndex: i, amount: shield,
                                       duration: J.wyrmBlessingDuration, tag: wyrmShieldTag)
            } else {
                CombatSystem.addShield(&s, ctx, sourceID: nil, targetIndex: i,
                                       amount: J.wyrmAllyShieldBase + J.wyrmAllyShieldPerLevel * level,
                                       duration: J.wyrmBlessingDuration, tag: wyrmAllyShieldTag)
            }
        }
    }

    // MARK: - 毎 tick

    /// Gold バフの収入・苔草の Mana 回復・星喰竜の加護のシールドの張り直し（EconomySystem が毎 tick 呼ぶ）。
    static func update(_ s: inout SimState, _ ctx: SimContext) {
        let dt = Balance.dt
        typealias J = Balance.Jungle
        for i in s.units.indices where s.units[i].kind == .hero && s.units[i].isAlive && s.units[i].hero?.isDead == false {
            guard !s.units[i].statuses.isEmpty else { continue }
            if let g = s.units[i].status(.goldBuff), g.magnitude > 0 {
                EconomyRewards.grantGold(&s, heroIndex: i, amount: g.magnitude * dt, visible: false)
            }
            if s.units[i].has(.mossGrass) {
                let r2 = J.mossGrassRadius * J.mossGrassRadius
                let pos = s.units[i].pos
                for j in s.heroIndices(team: s.units[i].team)
                where s.units[j].isAlive && s.units[j].hero?.resourceKind == .mana && s.units[j].pos.distanceSquared(to: pos) <= r2 {
                    let st = s.units[j].stats
                    s.units[j].resource = min(st.maxResource, s.units[j].resource + st.maxResource * J.mossGrassManaPerSecond * dt)
                }
            }
            if let b = s.units[i].status(.wyrmBlessing), b.magnitude > 0,
               s.time - s.units[i].lastDamagedTime >= J.wyrmShieldRegenDelay {
                let cur = s.units[i].shields.first { $0.tag == wyrmShieldTag }?.amount ?? 0
                if cur < b.magnitude - 1e-6 {
                    s.units[i].shields.removeAll { $0.tag == wyrmShieldTag }
                    s.units[i].shields.append(Shield(amount: b.magnitude, duration: b.remaining, tag: wyrmShieldTag))
                }
            }
        }
    }

    // MARK: - 能力値（StatCalculator が StatusModifiers の後に呼ぶ）

    /// 位置・レベル・シールドに依存する補正: 赤バフの適応貫通、苔草の川での加速、星喰竜の加護の攻撃力。
    static func applyStatModifiers(_ u: Unit, base: Stats, to stats: inout Stats, map: MapDefinition) {
        guard u.kind == .hero, !u.statuses.isEmpty else { return }
        // 適応: 追加の魔力が追加の物攻を上回れば魔法、そうでなければ物理
        let magical = stats.abilityPower - base.abilityPower > stats.attack - base.attack
        if let red = u.status(.redBuff), red.magnitude > 0 {
            if magical { stats.magicPenPct += red.magnitude } else { stats.armorPenPct += red.magnitude }
        }
        if u.has(.mossGrass), map.isInRiver(u.pos) {
            stats.moveSpeed *= 1 + Balance.Jungle.mossGrassRiverSpeed
        }
        if u.has(.wyrmBlessing), u.shields.contains(where: { $0.tag == wyrmShieldTag && $0.amount > 0 }) {
            let level = Double(u.hero?.level ?? 1)
            typealias J = Balance.Jungle
            if magical {
                stats.abilityPower += J.wyrmPowerBase + J.wyrmPowerPerLevel * level
            } else {
                stats.attack += J.wyrmAttackBase + J.wyrmAttackPerLevel * level
            }
        }
    }
}
