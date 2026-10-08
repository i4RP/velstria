import Foundation

/// ユニットの能力値。`Unit.stats` は毎回 `StatCalculator.recompute` で再計算される実効値。
/// ボーナス系（*Bonus / damageReduction）は加算の割合（0.1 = +10%）。
public struct Stats: Codable, Hashable, Sendable {
    public var maxHP: Double = 1
    public var maxResource: Double = 0
    public var attack: Double = 0
    public var abilityPower: Double = 0
    public var armor: Double = 0
    public var magicResist: Double = 0
    /// 毎秒の通常攻撃回数。
    public var attackSpeed: Double = 1
    public var moveSpeed: Double = 0
    public var attackRange: Double = 0
    public var sightRange: Double = 0
    /// 0...Balance.maxCooldownReduction
    public var cooldownReduction: Double = 0
    public var critChance: Double = 0
    public var critMultiplier: Double = Balance.critMultiplier
    public var lifesteal: Double = 0
    public var spellVamp: Double = 0
    /// 毎秒回復量。
    public var hpRegen: Double = 0
    public var resourceRegen: Double = 0
    /// 全与ダメ補正（加算）。
    public var damageBonus: Double = 0
    /// 通常攻撃のみの与ダメ補正（Attack 装備パッシブ等）。
    public var basicAttackDamageBonus: Double = 0
    /// スキルのみの与ダメ補正（Magic 装備パッシブ・Arcana ルーン等）。
    public var skillDamageBonus: Double = 0
    /// モンスターへの与ダメ補正（Jungle 装備）。
    public var monsterDamageBonus: Double = 0
    /// モンスター撃破 Gold 補正（Jungle 装備）。
    public var monsterGoldBonus: Double = 0
    /// 被ダメ軽減（合計は Balance.maxDamageReduction で頭打ち）。
    public var damageReduction: Double = 0
    /// 与える回復・シールド量の補正。
    public var healShieldPower: Double = 0
    /// 受ける回復量の倍率（重傷で 0.5 など）。
    public var healingReceivedMultiplier: Double = 1
    /// 非戦闘時の移動速度補正（Movement 装備）。MovementSystem が非戦闘時のみ加算。
    public var outOfCombatMoveSpeedBonus: Double = 0
    /// 貫通（装備）。敵の防御・魔防を割合（0.4 = 40%）で無視してから、固定値を引く（下限 0）。
    /// ヒーローの与ダメージにだけ効き、構造物には効かない。割合は同名の固有効果なので最大値を採る（ItemStats）。
    public var armorPenPct: Double = 0
    public var armorPenFlat: Double = 0
    public var magicPenPct: Double = 0
    public var magicPenFlat: Double = 0

    public init() {}
}
