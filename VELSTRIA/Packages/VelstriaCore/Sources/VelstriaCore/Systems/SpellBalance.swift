import Foundation

// 担当: core-skills
// バトルスペルの調整定数（DESIGN §7）。クールダウンはマスター（SpellDef.cooldownSec）。
// 統合フェーズで Balance.swift へ集約してよい。

extension Balance {
    public enum Spells {
        /// BS01 — battle skill tuning; cooldowns are in the master data.
        public static let blinkDistance: Double = 400
        /// BS02 — battle skill tuning; cooldowns are in the master data.
        public static let cleanseImmunityDuration: Double = 1.2
        /// BS03 — battle skill tuning; cooldowns are in the master data.
        public static let healPct: Double = 0.15
        public static let healAllyRadius: Double = 800
        public static let healSpeedBoost: Double = 0.20
        public static let healSpeedDuration: Double = 2
        /// BS04 — battle skill tuning; cooldowns are in the master data.
        public static let barrierPct: Double = 0.20
        public static let barrierDuration: Double = 5
        /// BS05 — battle skill tuning; cooldowns are in the master data.
        public static let smiteRange: Double = 500
        public static let smiteBase: Double = 520
        public static let smitePerLevel: Double = 80
        /// BS06 — battle skill tuning; cooldowns are in the master data.
        public static let ghostSpeedBoost: Double = 0.50
        public static let ghostDuration: Double = 6
        /// BS07 — battle skill tuning; cooldowns are in the master data.
        public static let igniteRange: Double = 600
        public static let igniteBase: Double = 70
        public static let ignitePerLevel: Double = 20
        public static let igniteDuration: Double = 5
        public static let igniteHealReduction: Double = 0.5
        /// BS08 — battle skill tuning; cooldowns are in the master data.
        public static let stealthDuration: Double = 1.5
        public static let stealthSpeedBoost: Double = 0.25
        /// BS09 — battle skill tuning; cooldowns are in the master data.
        public static let teleportChannel: Double = 3
        /// BS10 — battle skill tuning; cooldowns are in the master data.
        public static let exhaustRange: Double = 650
        public static let exhaustSlow: Double = 0.40
        public static let exhaustDamageDealtReduction: Double = 0.30
        public static let exhaustDuration: Double = 2.5
        /// BS11 — battle skill tuning; cooldowns are in the master data.
        public static let executeRange: Double = 600
        public static let executeBase: Double = 100
        public static let executePerLevel: Double = 10
        public static let executeMissingHPPct: Double = 0.13
        /// BS12 — battle skill tuning; cooldowns are in the master data.
        public static let inspireAttackSpeed: Double = 0.55
        public static let inspireDuration: Double = 5
        /// BS13 — battle skill tuning; cooldowns are in the master data.
        public static let petrifyRadius: Double = 450
        public static let petrifyStun: Double = 0.8
        public static let petrifySlow: Double = 0.50
        public static let petrifySlowAfterStun: Double = 0.8
        /// BS14 — battle skill tuning; cooldowns are in the master data.
        public static let flameshotRange: Double = 2400
        public static let flameshotWidth: Double = 70
        public static let flameshotSpeed: Double = 2000
        public static let flameshotBase: Double = 100
        public static let flameshotPerLevel: Double = 20
        /// BS15 — battle skill tuning; cooldowns are in the master data.
        public static let vengeanceDuration: Double = 3
        public static let vengeanceReduction: Double = 0.35
        public static let vengeanceReflect: Double = 0.40

        /// ステータスのタグ（"spell." + スペル ID）。
        public static func tag(_ spell: BattleSpell) -> String { "spell." + spell.rawValue }
        /// 報復の被ダメ軽減ステータスのタグ（反射の判定に使う）。
        public static let vengeanceTag = "spell.BS15"
    }
}
