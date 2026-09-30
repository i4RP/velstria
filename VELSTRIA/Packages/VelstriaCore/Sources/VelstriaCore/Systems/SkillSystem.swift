import Foundation

// 担当: core-skills
// スキルの照準情報・数値（DESIGN §6）、発動（検証 → 照準 → 消費 → アーキタイプ実行）、CD 進行、パッシブのフック。
// アーキタイプの実行は SkillArchetypes、照準の解決は SkillAiming、ロール別パッシブは SkillPassives。
// 調整定数は Balance.Skills（SkillBalance.swift）。

/// スキルの照準情報（HUD の照準表示・AI の狙い方）。
/// range / radius は実効値（突進 +100、跳躍 +200・×1.4、貫通矢 2000 など補正済み）。
/// - lineSkillshot / piercingLine の radius は弾の当たり幅（半径）。
/// - cone の radius は扇の半径（= range）。
/// - selfAoE / multiStrike / teamHeal の radius は術者中心の効果半径（術者の半径込み）。
/// - targetedBlink の radius は照準点からの対象選択の目安。
public struct SkillTargeting: Codable, Hashable, Sendable {
    public var archetype: SkillArchetype
    public var aim: AimType
    /// 最大射程（照準円の半径）。
    public var range: Double
    /// 効果半径 / 弾幅。
    public var radius: Double
    /// 味方を対象にするか（回復系）。
    public var targetsAllies: Bool

    public init(archetype: SkillArchetype, aim: AimType, range: Double, radius: Double, targetsAllies: Bool = false) {
        self.archetype = archetype
        self.aim = aim
        self.range = range
        self.radius = radius
        self.targetsAllies = targetsAllies
    }
}

extension SkillTargeting {
    /// 術者の中心から対象の縁までで、このスキルが敵に届く最大距離（AI の「撃てる距離か」の判定・自動照準）。
    /// blinkEmpower はブリンク距離のみ（強化攻撃の射程は含まない）。teamHeal は敵への CC の半径。
    public var reach: Double {
        switch archetype {
        case .passive: return 0
        case .cone, .lineSkillshot, .piercingLine, .blinkEmpower, .targetedBlink: return range
        case .dashStrike, .groundAoE, .healZone, .leapSlam: return range + radius
        case .selfAoE, .multiStrike, .teamHeal: return radius
        }
    }
}

/// ランク・能力値込みのスキル数値（UI のツールチップ・AI の判断用）。
/// ダメージ・回復は軽減前の生の値（与ダメ補正・防御は含まない）。
public struct SkillNumbers: Codable, Hashable, Sendable {
    public var rank = 1
    public var damageType: DamageType = .physical
    /// 1 ヒットのダメージ。blinkEmpower は強化通常攻撃の追加ダメージ。
    public var damage: Double = 0
    /// ヒット数（multiStrike は 3）。
    public var hits = 1
    /// 対象の失った HP に対する追加ダメージの割合（targetedBlink）。
    public var missingHealthRatio: Double = 0
    public var cooldown: Double = 0
    public var cost: Double = 0
    public var resource: ResourceKind = .mana
    public var cc: CrowdControl = .none
    public var ccIsUltimate = false
    /// CC の持続（ノックバックは押し出し + スタン）。
    public var ccDuration: Double = 0
    /// 味方 1 体あたりの回復量（healZone / teamHeal）。
    public var heal: Double = 0
    /// シールド量（selfAoE は自身、teamHeal は味方 1 体あたり）。
    public var shield: Double = 0
    public var shieldDuration: Double = 0
    /// 自身の被ダメ軽減（multiStrike）。
    public var damageReduction: Double = 0
    public var damageReductionDuration: Double = 0
    /// 発動までの予告時間（地点 AoE）。
    public var delay: Double = 0

    public init() {}

    /// 1 回の発動の合計ダメージ（追加ダメージ割合を除く）。
    public var totalDamage: Double { damage * Double(hits) }
}

public enum SkillCatalog {
    /// スキル → アーキタイプ・照準方式（DESIGN §6: スロット × 近接/遠隔 × ロール）。
    public static func targeting(for skill: SkillDef, hero: HeroDef) -> SkillTargeting {
        let k = Balance.Skills.self
        switch skill.slot {
        case .passive:
            return SkillTargeting(archetype: .passive, aim: .none, range: 0, radius: 0)
        case .skill1:
            if hero.isRanged {
                return SkillTargeting(archetype: .lineSkillshot, aim: .direction, range: skill.range,
                                      radius: skill.radius * k.skillshotWidthRatio)
            }
            return SkillTargeting(archetype: .cone, aim: .direction, range: skill.range, radius: skill.range)
        case .skill2:
            if hero.isRanged {
                return SkillTargeting(archetype: .blinkEmpower, aim: .direction, range: k.blinkDistance,
                                      radius: skill.radius)
            }
            return SkillTargeting(archetype: .dashStrike, aim: .direction, range: skill.range + k.dashExtraRange,
                                  radius: skill.radius)
        case .skill3:
            switch hero.role {
            case .vanguard:
                return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0,
                                      radius: skill.radius + Balance.heroRadius)
            case .support:
                return SkillTargeting(archetype: .healZone, aim: .point, range: skill.range, radius: skill.radius,
                                      targetsAllies: true)
            default:
                return SkillTargeting(archetype: .groundAoE, aim: .point, range: skill.range, radius: skill.radius)
            }
        case .ultimate:
            switch hero.role {
            case .vanguard:
                return SkillTargeting(archetype: .leapSlam, aim: .point, range: skill.range + k.leapExtraRange,
                                      radius: skill.radius * k.leapRadiusMultiplier)
            case .duelist:
                return SkillTargeting(archetype: .multiStrike, aim: .none, range: 0,
                                      radius: skill.radius + Balance.heroRadius)
            case .ranger:
                return SkillTargeting(archetype: .piercingLine, aim: .direction, range: k.piercingLength,
                                      radius: skill.radius)
            case .arcanist:
                return SkillTargeting(archetype: .groundAoE, aim: .point, range: skill.range,
                                      radius: skill.radius * k.arcanistUltRadiusMultiplier)
            case .support:
                return SkillTargeting(archetype: .teamHeal, aim: .none, range: k.teamHealRadius,
                                      radius: skill.radius + Balance.heroRadius, targetsAllies: true)
            case .assassin:
                return SkillTargeting(archetype: .targetedBlink, aim: .unit, range: skill.range, radius: skill.radius)
            }
        }
    }

    /// ランク・能力値込みの数値。rank は 1...最大ランクに丸める（未習得の表示は rank 1 相当）。
    /// ダメージ = (base × (1 + 0.30×(rank−1)) + scaling_attack × 総攻撃力 × 0.6 + scaling_power × 魔力) × スロット倍率。
    public static func numbers(for skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats) -> SkillNumbers {
        let k = Balance.Skills.self
        var n = SkillNumbers()
        guard skill.slot != .passive else { return n }
        let r = min(max(1, rank), skill.slot.maxRank)
        let isUlt = skill.slot == .ultimate
        let rankedBase = skill.baseDamage * (1 + Balance.skillDamagePerRank * Double(r - 1))
        let raw = (rankedBase + skill.scalingAttack * stats.attack * Balance.skillAttackScalingFactor
            + skill.scalingPower * stats.abilityPower) * k.damageScale(skill.slot)
        // 回復は基礎値と魔力のみでスケール（攻撃力は乗らない）
        let healBase = (rankedBase + skill.scalingPower * stats.abilityPower) * k.healScale

        n.rank = r
        n.damageType = skill.damageType
        n.damage = raw
        n.cooldown = SkillSystem.cooldown(for: skill, rank: r, cdr: stats.cooldownReduction)
        n.cost = SkillSystem.cost(for: skill, resource: hero.resource)
        n.resource = hero.resource
        n.cc = skill.cc
        n.ccIsUltimate = isUlt
        n.ccDuration = ccDuration(skill.cc, isUltimate: isUlt)

        switch targeting(for: skill, hero: hero).archetype {
        case .passive:
            n.damage = 0
        case .blinkEmpower:
            n.damage = raw * k.empowerRatio
        case .groundAoE:
            n.delay = isUlt ? k.arcanistUltTelegraph : k.groundTelegraph
        case .selfAoE:
            n.shield = stats.maxHP * k.selfShieldMaxHPRatio
            n.shieldDuration = k.selfShieldDuration
        case .healZone:
            n.heal = healBase * k.healZoneRatio
            n.delay = k.groundTelegraph
        case .multiStrike:
            n.damage = raw * k.multiStrikeRatio
            n.hits = k.multiStrikeCount
            n.damageReduction = k.multiStrikeDamageReduction
            n.damageReductionDuration = k.multiStrikeReductionDuration
        case .teamHeal:
            n.damage = 0
            n.heal = healBase * k.teamHealRatio
            n.shield = n.heal * k.teamHealShieldRatio
            n.shieldDuration = k.teamHealShieldDuration
        case .targetedBlink:
            n.missingHealthRatio = k.executeMissingHPRatio
        case .cone, .lineSkillshot, .piercingLine, .dashStrike, .leapSlam:
            break
        }
        return n
    }

    /// CC の持続秒（DESIGN §5。ノックバックは押し出し + スタン）。
    public static func ccDuration(_ cc: CrowdControl, isUltimate: Bool) -> Double {
        switch cc {
        case .none: return 0
        case .slow: return isUltimate ? Balance.ultSlowDuration : Balance.slowDuration
        case .root: return isUltimate ? Balance.ultRootDuration : Balance.rootDuration
        case .stun: return isUltimate ? Balance.ultStunDuration : Balance.stunDuration
        case .knockback: return Balance.knockbackTime + Balance.knockbackStun
        }
    }

    /// ヒーロー固有のパッシブ係数 k = 1.0 + 0.02 × (番号 mod 5)。
    public static func passiveCoefficient(heroNumber: Int) -> Double {
        1 + Balance.Skills.passiveCoefficientStep * Double(heroNumber % 5)
    }
}

/// 発動検証を通ったスキル（cast / canCast 共通）。
struct SkillCastCheck {
    let def: HeroDef
    let skill: SkillDef
    let slot: SkillSlot
    let rank: Int
    /// 実際に消費するリソース（練習場の CD なしでは 0）。
    let cost: Double
    /// 練習場の CD なし（CD・コストなし）。
    let free: Bool
}

public enum SkillSystem {
    /// スキル発動。成功で true（CD・コスト消費、.skillCast 発行）。
    /// 検証: 生存・行動可能（スタン/打ち上げ/沈黙/強制移動中は不可、ルート中は突進・跳躍不可）・ランク > 0・CD 完了・
    /// リソース ≥ コスト。
    /// 照準: .none は射程内の最適な敵ヒーロー → 最寄りの敵 → 向きの順に自動照準。地点は射程内に丸める。
    public static func cast(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, slot: SkillSlot,
                            target: SkillTarget) -> Bool {
        guard let check = validate(s, ctx, heroIndex: i, slot: slot) else { return false }
        let targeting = SkillCatalog.targeting(for: check.skill, hero: check.def)
        let numbers = SkillCatalog.numbers(for: check.skill, hero: check.def, rank: check.rank,
                                           stats: s.units[i].stats)
        // 対象が必要なスキル（連続斬り・対象指定ブリンク）は対象が居なければ消費せず失敗
        guard let aim = SkillAiming.resolve(s, ctx, caster: i, targeting: targeting, target: target) else {
            return false
        }

        // 消費・前隙の取り消し（攻撃は消費しない）・向き
        if check.cost > 0 { s.units[i].resource = max(0, s.units[i].resource - check.cost) }
        s.units[i].hero?.skillCooldowns[slot.rawValue] = check.free ? 0 : numbers.cooldown
        s.units[i].windupRemaining = nil
        s.units[i].facing = aim.direction.angle
        SkillPassives.breakStealth(&s, i)
        SkillPassives.beginCast(&s, i, slot: slot)

        SkillArchetypes.execute(&s, ctx, caster: i, check: check, targeting: targeting, numbers: numbers, aim: aim)
        PassiveHooks.onSkillCast(&s, ctx, caster: i, slot: slot)
        return true
    }

    /// 発動可能か（ランク・CD・コスト・CC）。HUD・AI が参照。対象の有無は含まない。
    public static func canCast(_ s: SimState, _ ctx: SimContext, heroIndex i: Int, slot: SkillSlot) -> Bool {
        validate(s, ctx, heroIndex: i, slot: slot) != nil
    }

    /// 実効クールダウン（ランク・CD 短縮込み、調整倍率 Balance.Skills.cooldownScale 込み）。
    public static func cooldown(for skill: SkillDef, rank: Int, cdr: Double) -> Double {
        let reduction = min(Balance.maxCooldownReduction, max(0, cdr))
        return skill.cooldownSec * (1 - Balance.skillCooldownPerRank * Double(max(0, rank - 1))) * (1 - reduction)
            * Balance.Skills.cooldownScale
    }

    /// 実効コスト。
    public static func cost(for skill: SkillDef, resource: ResourceKind) -> Double {
        resource == .energy ? skill.cost * Balance.energyCostMultiplier : skill.cost
    }

    /// 発動条件の検証（成功時は消費量などを返す）。
    static func validate(_ s: SimState, _ ctx: SimContext, heroIndex i: Int, slot: SkillSlot) -> SkillCastCheck? {
        guard slot != .passive, s.units.indices.contains(i), s.units[i].kind == .hero,
              let h = s.units[i].hero, !h.isDead, s.units[i].isAlive, s.units[i].canCast else { return nil }
        let rank = h.rank(slot)
        guard rank > 0, let def = ctx.master.hero(h.heroID),
              let skill = ctx.master.skill(hero: h.heroID, slot: slot) else { return nil }
        let free = ctx.config.practice?.noCooldowns == true
        guard free || h.cooldown(slot) <= CombatSystem.timeEpsilon else { return nil }
        let cost = free ? 0 : cost(for: skill, resource: h.resourceKind)
        guard s.units[i].resource + 1e-9 >= cost else { return nil }
        // ルート中は突進・跳躍できない（ブリンクは可）
        if s.units[i].has(.root) {
            switch SkillCatalog.targeting(for: skill, hero: def).archetype {
            case .dashStrike, .leapSlam: return nil
            default: break
            }
        }
        return SkillCastCheck(def: def, skill: skill, slot: slot, rank: rank, cost: cost, free: free)
    }

    /// CD 進行・パッシブのタイマー。
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let noCD = ctx.config.practice?.noCooldowns == true
        let dt = Balance.dt
        for i in s.units.indices where s.units[i].kind == .hero {
            guard s.units[i].hero != nil else { continue }
            for k in 0..<5 {
                let v = s.units[i].hero?.skillCooldowns[k] ?? 0
                if v > 0 { s.units[i].hero?.skillCooldowns[k] = noCD ? 0 : max(0, v - dt) }
            }
            SkillPassives.update(&s, ctx, i, dt: dt)
        }
    }
}

/// 戦闘処理から呼ばれるパッシブのフック（DESIGN §6 のロール別パッシブ）。
/// 状態は HeroData.passive（役割はロール毎に SkillPassives に記載）。
public enum PassiveHooks {
    /// 与ダメ補正（加算割合）。CombatSystem.applyDamage が呼ぶ。アサシンの奇襲。
    public static func outgoingDamageBonus(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                                           source: DamageSource) -> Double {
        guard s.units[attacker].hero?.role == .assassin else { return 0 }
        return SkillPassives.consumeAmbush(&s, ctx, attacker: attacker, target: target, source: source)
    }

    /// 通常攻撃がクリティカルになるかの上書き（nil = 通常の確率判定）。ヒーローの通常攻撃の発射毎に呼ばれる。
    /// レンジャーの 4 発毎の確定クリティカル。攻撃の発射でステルス（虚像）も解除する。
    public static func forceCrit(_ s: inout SimState, _ ctx: SimContext, attacker: Int) -> Bool? {
        SkillPassives.breakStealth(&s, attacker)
        guard s.units[attacker].hero?.role == .ranger else { return nil }
        return SkillPassives.rangerForceCrit(&s, ctx, attacker: attacker)
    }

    /// 通常攻撃の命中。デュエリストの攻撃速度スタック。
    public static func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                                        damage: Double) {
        guard s.units[attacker].hero?.role == .duelist else { return }
        SkillPassives.duelistStack(&s, ctx, attacker: attacker)
    }

    /// スキルの命中（ダメージ 0 の CC のみの命中を含む）。アルカニストの CD 短縮。
    public static func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                                  slot: SkillSlot, damage: Double) {
        guard s.units[attacker].hero?.role == .arcanist else { return }
        SkillPassives.arcanistRefund(&s, ctx, caster: attacker, slot: slot)
    }

    /// ヒーローの被ダメ（死亡した場合も呼ばれる）。ヴァンガードの低 HP シールド。
    public static func onDamageTaken(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?,
                                     amount: Double) {
        guard s.units[victim].hero?.role == .vanguard else { return }
        SkillPassives.vanguardShield(&s, ctx, hero: victim)
    }

    /// スキル発動の完了。サポートの回復。
    public static func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) {
        guard s.units[caster].hero?.role == .support else { return }
        SkillPassives.supportHeal(&s, ctx, caster: caster)
    }

    /// ヒーローのキル/アシスト（DeathSystem が呼ぶ）。アサシンの全 CD −30%。
    public static func onKillOrAssist(_ s: inout SimState, _ ctx: SimContext, hero: Int, victim: Int) {
        guard s.units[hero].hero?.role == .assassin else { return }
        SkillPassives.assassinTakedown(&s, hero: hero)
    }
}
