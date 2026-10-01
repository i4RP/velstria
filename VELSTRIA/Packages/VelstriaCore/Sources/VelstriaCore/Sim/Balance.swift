import Foundation

/// 調整用定数。docs/DESIGN.md と一致させる。
/// ルール: Wave 1 の各担当はこのファイルを直接編集しない。追加定数は自分の担当ファイル内で
/// `extension Balance { static let ... }` として定義する（統合フェーズで集約）。
public enum Balance {
    // MARK: 時間・マップ
    public static let tickRate: Double = 30
    public static let dt: Double = 1.0 / tickRate
    public static let mapSize: Double = 12000
    public static let mapCenter = Vec2(6000, 6000)
    public static let unitsPerMeter: Double = 100

    // MARK: 試合
    public static let teamSize = 5
    public static let maxLevel = 15
    public static let startingGold: Double = 300
    public static let passiveGoldPerSecond: Double = 3
    public static let passiveGoldStart: Double = 20
    public static let surrenderUnlockTime: Double = 8 * 60
    public static let surrenderCooldown: Double = 60

    // MARK: ミニオン
    public static let firstWaveTime: Double = 20
    public static let waveInterval: Double = 30
    public static let siegeEveryNWaves = 3
    public static let extraMeleeAfter: Double = 10 * 60
    public static let minionScalingPerMinute: Double = 0.03

    // MARK: ヒーロー
    public static let heroRadius: Double = 55
    public static let heroSight: Double = 1200
    public static let meleeAttackSpeed: Double = 0.85
    public static let rangedAttackSpeed: Double = 0.80
    public static let attackSpeedPerLevel: Double = 0.02
    public static let maxAttackSpeed: Double = 2.5
    public static let attackWindupRatio: Double = 0.25
    public static let heroProjectileSpeed: Double = 1500
    public static let energyRegenPerSecond: Double = 12
    public static let combatTimeout: Double = 5
    public static let minMoveSpeed: Double = 100
    /// ヒーロー移動速度の倍率（マスターの move_speed に掛ける）。実機の体感調整で 1.35（平均 257.5 → 約 348 ユニット/秒）。
    public static let heroMoveSpeedScale: Double = 1.35
    public static let critMultiplier: Double = 1.75
    public static let assistWindow: Double = 10
    public static let xpShareRadius: Double = 1400
    /// Lv→Lv+1 に必要な XP（index 0 = Lv1→2）。
    public static let xpToNext: [Double] = [260, 300, 340, 380, 420, 460, 500, 540, 580, 620, 660, 700, 740, 780]

    // MARK: スキル
    public static let basicSkillMaxRank = 4
    public static let ultimateMaxRank = 3
    public static let ultimateUnlockLevels = [4, 8, 12]
    public static let skillDamagePerRank: Double = 0.30
    public static let skillCooldownPerRank: Double = 0.06
    public static let skillAttackScalingFactor: Double = 0.6
    public static let maxCooldownReduction: Double = 0.40
    public static let energyCostMultiplier: Double = 0.6
    public static let maxDamageReduction: Double = 0.60

    // MARK: CC
    public static let slowPct: Double = 0.30
    public static let slowDuration: Double = 1.5
    public static let ultSlowPct: Double = 0.45
    public static let ultSlowDuration: Double = 2.0
    public static let rootDuration: Double = 1.0
    public static let ultRootDuration: Double = 1.5
    public static let stunDuration: Double = 0.75
    public static let ultStunDuration: Double = 1.25
    public static let knockbackDistance: Double = 250
    public static let knockbackTime: Double = 0.25
    public static let knockbackStun: Double = 0.25

    // MARK: 経済
    public static let heroKillBounty: Double = 300
    public static let firstBloodBonus: Double = 100
    public static let streakBonusPerKill: Double = 60
    public static let maxStreakBonus: Double = 480
    public static let deathStreakPenaltyPct: Double = 0.15
    public static let minBounty: Double = 100
    public static let assistBountyShare: Double = 0.5
    public static let minAssistGold: Double = 40
    public static let towerLastHitGold: Double = 150
    public static let towerTeamGold: Double = 120
    public static let itemSlots = 6
    public static let sellRatio: Double = 0.6
    public static let minCombineCostRatio: Double = 0.3

    // MARK: リスポーン・帰還・泉
    public static let respawnBase: Double = 4
    public static let respawnPerLevel: Double = 2
    public static let respawnLateGameTime: Double = 12 * 60
    public static let respawnLateGameMultiplier: Double = 1.25
    public static let respawnMax: Double = 40
    public static let recallChannel: Double = 6
    public static let empoweredRecallChannel: Double = 2
    public static let fountainRadius: Double = 800
    public static let fountainHealPct: Double = 0.10
    public static let fountainDamagePerSecond: Double = 1000

    // MARK: 視界
    public static let visionCellSize: Double = 200
    public static let visionUpdateEveryTicks = 3
    public static let brushRevealRadius: Double = 300
    public static let stealthRevealRadius: Double = 250
    public static let towerTrueSightRadius: Double = 750

    // MARK: 構造物
    public static let outerTowerProtectionUntil: Double = 4 * 60
    public static let outerTowerProtectionReduction: Double = 0.40
    public static let backdoorReduction: Double = 0.50
    public static let towerRampPerHit: Double = 0.30
    public static let towerRampMax: Double = 1.20
    public static let leashRadius: Double = 900
    /// タワー・Core の最大 HP 倍率（AI 対戦の試合時間を 10〜18 分へ寄せる調整値。DESIGN §4 の表に掛ける）。
    public static let structureHPScale: Double = 0.65
}
