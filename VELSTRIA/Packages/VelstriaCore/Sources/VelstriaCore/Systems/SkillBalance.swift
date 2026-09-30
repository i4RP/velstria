import Foundation

// 担当: core-skills
// スキル・パッシブの調整定数（DESIGN §6）。統合フェーズで Balance.swift へ集約してよい。
// 他担当の extension と衝突しないよう `Balance.Skills` にまとめる。

extension Balance {
    public enum Skills {
        // MARK: 全体係数（1v1 TTK スモーク `SkillBalanceTests` で調整）
        /// スキルダメージ倍率（DESIGN §6 の式の結果に掛ける）。index = SkillSlot.rawValue。
        /// マスターの base_damage は HP 基準値に対して小さいため、Lv1 の 1v1 でも 15 秒以内に決着する水準へ引き上げる。
        public static let damageScaleBySlot: [Double] = [0, 3.4, 3.0, 3.0, 2.6]
        /// 回復・シールド系スキル（healZone / teamHeal）の倍率。
        public static let healScale: Double = 2.4
        /// クールダウン倍率（DESIGN §6 の式に掛ける）。
        public static let cooldownScale: Double = 0.55

        // MARK: 照準
        /// 攻撃力スケーリングの係数（DESIGN §6: scaling_attack × 総攻撃力 × 0.6）。
        public static let attackScaling: Double = Balance.skillAttackScalingFactor
        /// 自動照準（.none）で対象を探す際の追加距離（対象半径に加算）。
        public static let autoAimSlack: Double = 0

        // MARK: Skill1
        /// 近接の前方扇形の半角（90° の扇）。
        public static let coneHalfAngle: Double = Double.pi / 4
        /// 遠隔の直線スキルショット: 弾速・当たり幅（半径 = radius × 比率）。
        public static let skillshotSpeed: Double = 1600
        public static let skillshotWidthRatio: Double = 0.5

        // MARK: Skill2
        /// 近接の突進: 距離 = range + この値、速度。
        public static let dashExtraRange: Double = 100
        public static let dashSpeed: Double = 1500
        /// 遠隔のブリンク距離・強化攻撃（スキル値の 50%）・強化の持続。
        public static let blinkDistance: Double = 350
        public static let empowerRatio: Double = 0.5
        public static let empowerDuration: Double = 4

        // MARK: Skill3
        /// 地点指定 AoE の予告時間。
        public static let groundTelegraph: Double = 0.5
        /// ヴァンガードの自身中心 AoE: 自身へ最大 HP 8% のシールド。
        public static let selfShieldMaxHPRatio: Double = 0.08
        public static let selfShieldDuration: Double = 3
        /// サポートの回復ゾーン: 回復量 = 基礎値 × 0.8。
        public static let healZoneRatio: Double = 0.8

        // MARK: Ultimate
        /// ヴァンガード: 跳躍（最大 range + 200）、着地 AoE radius × 1.4、跳躍速度。
        public static let leapExtraRange: Double = 200
        public static let leapRadiusMultiplier: Double = 1.4
        public static let leapSpeed: Double = 1300
        /// デュエリスト: 3 回 × 45%（0.6 秒で）+ 自身 25% 被ダメ軽減 2 秒。
        public static let multiStrikeCount = 3
        public static let multiStrikeRatio: Double = 0.45
        public static let multiStrikeDuration: Double = 0.6
        public static let multiStrikeDamageReduction: Double = 0.25
        public static let multiStrikeReductionDuration: Double = 2
        /// レンジャー: 貫通大矢（長さ 2000、幅 = radius）。
        public static let piercingLength: Double = 2000
        public static let piercingSpeed: Double = 2200
        /// アルカニスト: 1.0 秒予告、radius × 1.8。
        public static let arcanistUltTelegraph: Double = 1.0
        public static let arcanistUltRadiusMultiplier: Double = 1.8
        /// サポート: 1500 以内の味方ヒーローを基礎値 × 1.2 回復 + 回復量 × 0.5 のシールド。
        public static let teamHealRadius: Double = 1500
        public static let teamHealRatio: Double = 1.2
        public static let teamHealShieldRatio: Double = 0.5
        public static let teamHealShieldDuration: Double = 3
        /// アサシン: 失った HP の 12% を追加ダメージ。
        public static let executeMissingHPRatio: Double = 0.12
        /// 対象の背後へ出る時の間隔。
        public static let targetedBlinkGap: Double = 10

        // MARK: パッシブ（DESIGN §6。ヒーロー係数 k = 1.0 + 0.02 × (番号 mod 5)）
        public static let passiveCoefficientStep: Double = 0.02
        /// ヴァンガード: HP 40% 未満で最大 HP 15%×k のシールド（CD 20 秒）。
        public static let vanguardShieldThreshold: Double = 0.40
        public static let vanguardShieldRatio: Double = 0.15
        public static let vanguardShieldCooldown: Double = 20
        public static let vanguardShieldDuration: Double = 4
        /// デュエリスト: 通常攻撃命中毎に攻撃速度 +6%×k（最大 5 スタック、3 秒）。
        public static let duelistAttackSpeedPerStack: Double = 0.06
        public static let duelistMaxStacks = 5
        public static let duelistStackDuration: Double = 3
        /// レンジャー: 4 発毎の通常攻撃が必ずクリティカル（1.75×k 倍）。
        public static let rangerCritEvery = 4
        /// アルカニスト: スキル命中で他スキル CD −0.6 秒×k（1 キャストにつき 1 回）。
        public static let arcanistRefund: Double = 0.6
        /// サポート: スキル使用時、800 以内で HP 割合最低の味方を 40 + 10×Lv×k 回復。
        public static let supportHealBase: Double = 40
        public static let supportHealPerLevel: Double = 10
        public static let supportHealRadius: Double = 800
        /// アサシン: 草むら/ステルス解除後 3 秒以内の最初のダメージ +30%×k、キル/アシストで全 CD −30%。
        public static let assassinAmbushBonus: Double = 0.30
        public static let assassinAmbushWindow: Double = 3
        public static let assassinTakedownRefund: Double = 0.30

        // MARK: ステータスのタグ
        public static let duelistPassiveTag = "passive.duelist"
        public static let vanguardPassiveTag = "passive.vanguard"
        public static let multiStrikeTag = "skill.multiStrike"

        /// スロット別のダメージ倍率。
        @inline(__always)
        public static func damageScale(_ slot: SkillSlot) -> Double {
            damageScaleBySlot[slot.rawValue]
        }
    }
}
