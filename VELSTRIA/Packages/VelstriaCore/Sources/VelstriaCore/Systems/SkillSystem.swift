import Foundation

// 担当: core-skills（Wave 2）。現在はスタブ（スキルは発動しない）。

/// スキルの照準情報（HUD の照準表示・AI の狙い方）。
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

public enum SkillCatalog {
    /// スキル ID → アーキタイプ・照準方式。
    public static func targeting(for skill: SkillDef, hero: HeroDef) -> SkillTargeting {
        if skill.slot == .passive {
            return SkillTargeting(archetype: .passive, aim: .none, range: 0, radius: 0)
        }
        return SkillTargeting(archetype: .groundAoE, aim: .point, range: skill.range, radius: skill.radius)
    }
}

public enum SkillSystem {
    /// スキル発動。成功で true（CD・コスト消費、.skillCast 発行）。
    public static func cast(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, slot: SkillSlot,
                            target: SkillTarget) -> Bool {
        false
    }

    /// 発動可能か（ランク・CD・コスト・CC）。HUD・AI が参照。
    public static func canCast(_ s: SimState, _ ctx: SimContext, heroIndex i: Int, slot: SkillSlot) -> Bool {
        guard let h = s.units[i].hero, slot != .passive else { return false }
        return h.rank(slot) > 0 && h.cooldown(slot) <= 0 && s.units[i].canCast
    }

    /// 実効クールダウン（ランク・CD 短縮込み）。
    public static func cooldown(for skill: SkillDef, rank: Int, cdr: Double) -> Double {
        skill.cooldownSec * (1 - Balance.skillCooldownPerRank * Double(max(0, rank - 1))) * (1 - cdr)
    }

    /// 実効コスト。
    public static func cost(for skill: SkillDef, resource: ResourceKind) -> Double {
        resource == .energy ? skill.cost * Balance.energyCostMultiplier : skill.cost
    }

    /// CD 進行・パッシブのタイマー。
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let noCD = ctx.config.practice?.noCooldowns == true
        for i in s.units.indices where s.units[i].kind == .hero {
            guard s.units[i].hero != nil else { continue }
            for k in 0..<5 {
                let v = s.units[i].hero!.skillCooldowns[k]
                if v > 0 { s.units[i].hero!.skillCooldowns[k] = noCD ? 0 : max(0, v - Balance.dt) }
            }
        }
    }
}

/// 戦闘処理から呼ばれるパッシブのフック（core-skills が実装）。
public enum PassiveHooks {
    /// 与ダメ補正（加算割合）。CombatSystem.applyDamage が呼ぶ。
    public static func outgoingDamageBonus(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                                           source: DamageSource) -> Double { 0 }
    /// 通常攻撃がクリティカルになるかの上書き（nil = 通常の確率判定）。
    public static func forceCrit(_ s: inout SimState, _ ctx: SimContext, attacker: Int) -> Bool? { nil }
    public static func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                                        damage: Double) {}
    public static func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                                  slot: SkillSlot, damage: Double) {}
    public static func onDamageTaken(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?,
                                     amount: Double) {}
    public static func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) {}
    public static func onKillOrAssist(_ s: inout SimState, _ ctx: SimContext, hero: Int, victim: Int) {}
}
