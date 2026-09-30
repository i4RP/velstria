import Foundation

// 担当: core-skills
// バトルスペルの調整定数（DESIGN §7）。クールダウンはマスター（SpellDef.cooldownSec）。
// 統合フェーズで Balance.swift へ集約してよい。

extension Balance {
    public enum Spells {
        /// BS01 瞬歩: 指定方向へ 400（障害物の手前で停止）。
        public static let blinkDistance: Double = 400
        /// BS02 浄化: 全 CC 解除 + CC 無効。
        public static let cleanseImmunityDuration: Double = 1.5
        /// BS03 治癒波: 自身と 800 以内で HP 割合最低の味方 1 名を最大 HP 15% 回復 + 移動速度 +20% 2 秒。
        public static let healPct: Double = 0.15
        public static let healAllyRadius: Double = 800
        public static let healSpeedBoost: Double = 0.20
        public static let healSpeedDuration: Double = 2
        /// BS04 鉄壁: 3 秒間 最大 HP 20% のシールド。
        public static let barrierPct: Double = 0.20
        public static let barrierDuration: Double = 3
        /// BS05 狩猟印: 500 以内の敵ミニオン/モンスターに 600 + 40×Lv の確定ダメージ。
        public static let smiteRange: Double = 500
        public static let smiteBase: Double = 600
        public static let smitePerLevel: Double = 40
        /// BS06 加速陣: 5 秒間 移動速度 +40%。
        public static let ghostSpeedBoost: Double = 0.40
        public static let ghostDuration: Double = 5
        /// BS07 点火: 600 以内の敵ヒーローに 5 秒で 70 + 20×Lv の確定ダメージ、回復 −50%。
        public static let igniteRange: Double = 600
        public static let igniteBase: Double = 70
        public static let ignitePerLevel: Double = 20
        public static let igniteDuration: Double = 5
        public static let igniteHealReduction: Double = 0.5
        /// BS08 虚像: 1.5 秒ステルス + 移動速度 +25%（攻撃・スキルで解除）。
        public static let stealthDuration: Double = 1.5
        public static let stealthSpeedBoost: Double = 0.25
        /// BS09 帰還門: 3 秒詠唱後に味方タワー/泉へ転移。
        public static let teleportChannel: Double = 3
        /// BS10 星鎖: 650 以内の敵ヒーローにスロー 40% + 与ダメ −30%（2.5 秒）。
        public static let exhaustRange: Double = 650
        public static let exhaustSlow: Double = 0.40
        public static let exhaustDamageDealtReduction: Double = 0.30
        public static let exhaustDuration: Double = 2.5

        /// ステータスのタグ（"spell." + スペル ID）。
        public static func tag(_ spell: BattleSpell) -> String { "spell." + spell.rawValue }
    }
}
