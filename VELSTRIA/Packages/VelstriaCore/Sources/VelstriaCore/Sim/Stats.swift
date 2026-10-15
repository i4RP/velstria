import Foundation

/// ユニットの能力値。`Unit.stats` は毎回 `StatCalculator.recompute` で再計算される実効値。
/// ボーナス系（*Bonus / damageReduction）は加算の割合（0.1 = +10%）。
public struct Stats: Codable, Hashable, Sendable {
    public var maxHP: Double = 1
    public var maxResource: Double = 0
    public var attack: Double = 0
    /// 追加物理攻撃（MLBB の「追加物理攻撃」= 装備・エンブレム・スキルで増えた分。レベルの基礎値と成長を除く）。
    /// StatCalculator.recompute が最後に attack − 基礎（Unit.baseStats.attack）で入れる。キットの「+N% 追加物理攻撃」の係数が使う。
    public var extraAttack: Double = 0
    public var abilityPower: Double = 0
    public var armor: Double = 0
    public var magicResist: Double = 0
    /// 毎秒の通常攻撃回数。合成の途中（HeroGrowth〜状態効果）は基礎（レベル成長込み）だけで、StatCalculator が最後に
    /// 「基礎 + 追加 × 攻撃速度比率」（上限 Balance.maxAttackSpeed）にする（MLBB の用語注釈「攻撃速度」）。
    public var attackSpeed: Double = 1
    /// 追加の攻撃速度（毎秒の攻撃回数。装備・エンブレム・スキルの「攻撃速度 +30%」は +0.30）。
    public var extraAttackSpeed: Double = 0
    /// 攻撃速度比率（追加の攻撃速度が効く割合。MLBB のほとんどのヒーローは 100%）。
    public var attackSpeedRatio: Double = 1
    /// 移動速度。合成の途中は基礎移動速度（ヒーローは MLBB の値 + 固定の加算）で、StatCalculator が最後に
    /// 「基礎 × (100% + 全加速% − 全減速%)」と逓減を掛け、ヒーローはさらに Balance.mapScale を掛けてワールドの単位/秒にする。
    public var moveSpeed: Double = 0
    /// 移動速度の加速の合計（0.1 = +10%。装備・エンブレム・スキル・非戦闘時の装備の加速）。
    public var moveSpeedBonus: Double = 0
    /// 移動速度の減速の合計（0.3 = −30%。減速は足し合わせ、上限 Balance.maxSlow）。
    public var moveSpeedSlow: Double = 0
    public var attackRange: Double = 0
    public var sightRange: Double = 0
    /// 0...cooldownReductionCap（StatCalculator が切る）
    public var cooldownReduction: Double = 0
    public var critChance: Double = 0
    /// クリティカルダメージの倍率（既定 2.0 = 200% + 増加の合計）。被クリティカルダメージ軽減は攻撃時に引く。
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
    /// スキルのみの与ダメ補正（Magic 装備パッシブ等）。
    public var skillDamageBonus: Double = 0
    /// モンスターへの与ダメ補正（Jungle 装備）。
    public var monsterDamageBonus: Double = 0
    /// モンスター撃破 Gold 補正（Jungle 装備）。
    public var monsterGoldBonus: Double = 0
    /// 被ダメ軽減（防御の後の最終ダメージを割合で減らす。MLBB は上限なし・確定ダメージには効かない）。
    public var damageReduction: Double = 0
    /// 与える回復・シールド量の補正（MLBB「回復効果」。既定 100% に足す）。
    public var healShieldPower: Double = 0
    /// 受ける回復・シールドの倍率（MLBB「シールド＆HP回復」。重傷で 0.5 など）。
    public var healingReceivedMultiplier: Double = 1
    /// 非戦闘時の移動速度補正（Movement 装備）。MovementSystem が非戦闘時のみ加算。
    public var outOfCombatMoveSpeedBonus: Double = 0
    /// 貫通（装備）。敵の防御・魔防を割合（0.4 = 40%）で無視してから、固定値を引く（下限 Balance.minDefense = −60）。
    /// ヒーローの与ダメージにだけ効き、構造物には効かない。割合は同名の固有効果なので最大値を採る（ItemStats）。
    public var armorPenPct: Double = 0
    public var armorPenFlat: Double = 0
    public var magicPenPct: Double = 0
    public var magicPenFlat: Double = 0
    /// 強靭（コントロール時間短縮。0.3 = 行動阻害の効果時間 −30%）。出どころが違えば掛け算で重ねる: 1 − Π(1 − r)
    /// （`Stats.addResilience`。MLBB の Resilience）。
    public var ccReduction: Double = 0
    /// 減速軽減（0.35 = 受ける減速 −35%。装備）。
    public var slowReduction: Double = 0
    /// 受けるクリティカルダメージの軽減（0.2 = クリティカルダメージ −20% ポイント。MLBB: 元 × (200% + 増加 − 減少)）。
    public var critDamageReduction: Double = 0
    /// クールダウン短縮の上限（装備で上がる）。
    public var cooldownReductionCap: Double = Balance.maxCooldownReduction

    public init() {}

    /// 強靭を 1 つの出どころ分だけ足す（違う出どころは掛け算: 1 − (1 − 今) × (1 − r)。MLBB の Resilience）。
    public mutating func addResilience(_ r: Double) {
        guard r != 0 else { return }
        ccReduction = 1 - (1 - min(1, max(0, ccReduction))) * (1 - min(1, max(0, r)))
    }
}
