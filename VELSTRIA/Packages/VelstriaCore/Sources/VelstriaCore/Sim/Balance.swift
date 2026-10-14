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
    // 能力値の式は MLBB の用語注釈に合わせる（2026-10-14。docs/HERO_STATS.md）。ヒーローごとの基礎値・成長は master。
    public static let heroRadius: Double = 55
    public static let heroSight: Double = 1200
    /// 攻撃速度の上限（毎秒の攻撃回数）。MLBB の用語注釈「攻撃速度」: 毎秒 3 回まで。
    public static let maxAttackSpeed: Double = 3.0
    public static let attackWindupRatio: Double = 0.25
    public static let heroProjectileSpeed: Double = 1500
    public static let combatTimeout: Double = 5
    /// 移動速度の下限（ワールドの単位/秒。MLBB の式の後の安全弁。減速の上限 90% と逓減で通常は届かない）。
    public static let minMoveSpeed: Double = 100
    /// 移動速度のマップ縮尺（MLBB の移動速度の式の後に、全ヒーローへ一律に掛ける）。**MLBB に無い唯一の値**。
    /// マップの大きさが MLBB の単位（距離 ×100）と合っているか未確認のため、外すと全員がマップとミニオンに対して 26% 遅くなる。
    /// 歩行時間の実測（同じ区間を MLBB と Velstria で歩く）で決め直す（docs/HERO_STATS.md「MLBB に無い値」）。
    public static let mapScale: Double = 1.35
    /// クリティカルダメージの既定（MLBB の日本語クライアント「クリティカルダメージ … デフォルトは200%」）。
    public static let critMultiplier: Double = 2.0
    /// 防御の式の定数: 受けるダメージ = 120 / (120 + 防御)（MLBB の用語注釈「物理防御」「魔法防御」。物理・魔法とも）。
    public static let defenseConstant: Double = 120
    /// 実効防御の下限（貫通・防御低下の後）。−60 で受けるダメージは最大 200%（MLBB の用語注釈「… −60 を下回らない」）。
    public static let minDefense: Double = -60
    /// エナジーの上限（MLBB のエナジーのヒーローは最大 100）。
    public static let energyMax: Double = 100
    /// 減速の上限（合計。MLBB: 移動速度の最大 90% まで）。
    public static let maxSlow: Double = 0.9
    /// 移動速度の逓減（MLBB の用語注釈「移動速度」: 計算値が 230 未満・420 超では加速も減速も逓減する）。
    /// 率は資料に無い（Fandom も「unknown rate」）。0.5 = 閾値を越えた分の半分だけ効く、は仮の値（実機の計測待ち）。
    public static let moveSpeedDecayBelow: Double = 230
    public static let moveSpeedDecayAbove: Double = 420
    public static let moveSpeedDecayRate: Double = 0.5
    /// 強靭（コントロール時間短縮）で縮めた後の CC の下限（秒。MLBB: 0.1 秒より短くならない）。
    public static let minCrowdControlDuration: Double = 0.1
    public static let assistWindow: Double = 10
    public static let xpShareRadius: Double = 1400
    /// Lv→Lv+1 に必要な XP（index 0 = Lv1→2）。
    public static let xpToNext: [Double] = [240, 270, 300, 350, 400, 450, 500, 550, 600, 650, 700, 750, 800, 850]

    // MARK: スキル
    public static let basicSkillMaxRank = 4
    public static let ultimateMaxRank = 3
    public static let ultimateUnlockLevels = [4, 8, 12]
    public static let skillDamagePerRank: Double = 0.30
    public static let skillCooldownPerRank: Double = 0.06
    public static let skillAttackScalingFactor: Double = 0.6
    /// CD 短縮の上限（MLBB の日本語クライアント「通常、短縮率の上限は40%」）。魔導の護符などは Stats.cooldownReductionCap を上げる。
    public static let maxCooldownReduction: Double = 0.40
    /// エナジーのヒーローの汎用スキルのコスト倍率（master の cost は Mana 基準）。エナジーの上限を MLBB の 100 にした
    /// （2026-10-14）ので、以前の 0.6（上限約 500 の時）に 100/500 を掛けて、発動の間隔（コスト / 上限）を保つ。暫定。
    public static let energyCostMultiplier: Double = 0.12

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
    /// 合成の最低支払い（価格に対する割合）。MLBB は素材の合計を引いた差額だけを払うので 0。
    public static let minCombineCostRatio: Double = 0

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
    /// 草むら（MLBB の Bush）: 同じ草むらに敵の視界源が居なければ、入って 0.25 秒で隠れる。
    /// 入る直前に敵に見られていたら 0.75 秒。草むらの外からは距離によらず見えない。
    public static let brushConcealDelay: Double = 0.25
    public static let brushConcealDelaySeen: Double = 0.75
    /// 敵ヒーローへのダメージ・敵ミニオンや構造物への通常攻撃から 3 秒は草むらでも隠れない。
    public static let brushExposeDuration: Double = 3
    public static let stealthRevealRadius: Double = 250
    public static let towerTrueSightRadius: Double = 750

    // MARK: 構造物
    /// 外塔のエネルギーシールド（参照仕様 §5.4）: 開始時に付き、5:00 で消える。シールドがある間は被ダメ −30%（遠近とも）。
    /// シールドに与えたダメージ 10 につき 0.8 Gold を攻撃したヒーローが得る（参照 §3.1）。
    public static let outerTowerShield: Double = 5000
    public static let outerTowerShieldDuration: Double = 5 * 60
    public static let outerTowerShieldReduction: Double = 0.30
    public static let outerTowerShieldGoldPer10: Double = 0.8
    public static let backdoorReduction: Double = 0.50
    public static let towerRampPerHit: Double = 0.30
    public static let towerRampMax: Double = 1.20
    public static let leashRadius: Double = 900
    /// バフ番人の多人数軽減: 近くのヒーロー（敵味方を問わない）1 人につき被ダメ −15%、最大 −60%（参照仕様 §3.3）。
    public static let sentinelGangRadius: Double = 900
    public static let sentinelGangReductionPerHero: Double = 0.15
    public static let sentinelGangMaxReduction: Double = 0.60
    /// 序盤ボスはこの試合時間（秒）以降に倒されると再出現しない（参照仕様 §5.1）。
    public static let wyrmNoRespawnAfter: Double = 6 * 60
    /// タワー・Core の最大 HP 倍率（AI 対戦の試合時間を 10〜18 分へ寄せる調整値。DESIGN §4 の表に掛ける）。
    public static let structureHPScale: Double = 0.65
}
