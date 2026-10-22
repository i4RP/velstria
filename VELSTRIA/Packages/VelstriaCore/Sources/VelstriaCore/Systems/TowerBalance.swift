import Foundation

// 担当: core-world。塔とベースの数値・規則（MLBB 本サーバー 2.2.16。値と出典の一覧は docs/TOWER_BASE_MLBB.md）。
// 方針: MLBB の値をそのまま入れる（換算も丸めもしない）。距離は MLBB × 100（スキルの幾何と同じ。Balance.mapScale は掛けない）。
// 日本語版の表記: アウタータワー / インナータワー / ベースタワー / ベース、エネルギーシールド、聖なる防御。

extension Balance {
    public enum Tower {
        // MARK: 能力値（通常の試合の値。Hミシック以上の試合のインナー 6700・ベースタワー 8200・ベース 9000 は使わない）

        /// 最大 HP: アウター 4500・インナー 5700・ベースタワー 7300・ベース 7900。
        public static func maxHP(tier: TowerTier, isCore: Bool) -> Double {
            if isCore { return 7900 }
            switch tier {
            case .outer: return 4500
            case .inner: return 5700
            case .base: return 7300
            }
        }

        /// 攻撃の初期値: アウター 320・インナー 360・ベースタワー 520・ベース 539。
        /// 時間での伸びの現在値は資料に無いので伸ばさない（Fandom の「12 分後」の列は版が古く、ベース以外は辻褄が合わない）。
        public static func attack(tier: TowerTier, isCore: Bool) -> Double {
            if isCore { return 539 }
            switch tier {
            case .outer: return 320
            case .inner: return 360
            case .base: return 520
            }
        }

        /// 物理防御・魔法防御: アウター・インナー 20、ベースタワー・ベース 40。
        public static func defense(tier: TowerTier, isCore: Bool) -> Double {
            if isCore { return 40 }
            return tier == .base ? 40 : 20
        }

        /// 1 秒に 1 回攻撃する。
        public static let attacksPerSecond: Double = 1

        // MARK: 攻撃

        /// 同じヒーローに続けて当てると、1 発ごとに攻撃の +75%（+240）。20 発目で止まる（320 → 560 → … → 4880）。
        public static let rampPerHit: Double = 0.75
        public static let rampMaxHits = 20
        /// 2 秒当てなければ連続命中が戻る（対象を替えても 2 秒以内に戻れば続く）。
        public static let rampResetTime: Double = 2
        /// ヒーローへの初撃は −10%（MLBB 1.5.62）。
        public static let firstHitMultiplier: Double = 0.9
        /// アウタータワーは最初のミニオンが出てから 15 秒間は攻撃せず、無敵（体力のバーも出ない）。
        public static let outerWakeDelay: Double = 15
        /// アウタータワーが起きる時刻（最初のウェーブ + 15 秒）。
        public static var outerWakeTime: Double { Balance.firstWaveTime + outerWakeDelay }

        // MARK: エネルギーシールド（アウター）

        /// 5:00 まで、5000 を吸収、被ダメ −30%（遠近とも）。
        public static let shieldAmount: Double = 5000
        public static let shieldDuration: Double = 5 * 60
        public static let shieldReduction: Double = 0.30
        /// シールドを削ったヒーローは 10 ダメージごとに 1 Gold。1 レーン（1 本）の合計は 360 Gold まで
        /// （資料が食い違う: Fandom は「10 ダメージで 1 Gold・1 レーン合計 360」、1.5.16 のパッチノートは 0.8 / 10）。
        public static let shieldGoldPer10: Double = 1
        public static let shieldGoldCap: Double = 360
        /// ミニオンがシールドに与えるダメージは 1 発 75 で固定（1.5.16）。
        public static let shieldMinionDamage: Double = 75
        /// シールドがある間、近くの味方ヒーローの被ダメ −15%（1.5.38）。近くの範囲は資料に無いので塔の射程。
        public static let shieldAllyReduction: Double = 0.15

        // MARK: 保護

        /// バックドアの保護: 射程内に敵ミニオンがいなければ被ダメ −50%。
        /// 1.9.28 で「大幅に増加」とあるが、数値は資料に無いので 50% のまま（docs に記載）。ベースも同じ。
        public static let backdoorReduction: Double = 0.50
        /// ミニオンからベースへのダメージ −50%（1.5.70）。
        public static let coreMinionDamageReduction: Double = 0.50
        /// インナーの保護: 同じレーンのアウターが 8:00 までに壊れたら、1 分間 被ダメ −50%（1.6.42）。
        public static let innerGuardWindow: Double = 8 * 60
        public static let innerGuardDuration: Double = 60
        public static let innerGuardReduction: Double = 0.50
        public static let innerGuardTag = "tower.innerGuard"
        /// ベースタワーの聖なる防御: 同じレーンのインナーが 12:00 までに壊れたら、次に射程に入る敵ミニオンの波に
        /// 最大 HP の 80% の確定ダメージ（1.6.58）。発動の時に、前にいる敵ミニオン（ロードは除く）と敵ヒーローを押し返す（1.9.64）。
        public static let holyDefenseWindow: Double = 12 * 60
        public static let holyDefenseMinionDamagePct: Double = 0.80
        /// 波とみなす範囲（射程の外側のこの距離まで。資料に無い）と、押し返しの距離（資料に無いので通常の押し返しと同じ）。
        public static let holyDefenseWaveMargin: Double = 300
        public static var holyDefenseKnockback: Double { Balance.knockbackDistance }

        // MARK: ベース・泉

        /// ベースは 5 秒ごとに 165 回復する。
        public static let coreRegenAmount: Double = 165
        public static let coreRegenInterval: Double = 5
        /// 泉は敵ヒーローに 0.2 秒ごとに 2000 の確定ダメージ（泉は無敵）。
        public static let fountainDamage: Double = 2000
        public static let fountainInterval: Double = 0.2

        // MARK: ヒーローの攻撃

        /// ヒーローの通常攻撃は塔に 物攻 100% + 魔攻 100%（1.8.08）。
        public static let heroMagicPowerRatio: Double = 1

        // MARK: 報酬

        /// 壊した時のチーム全員への Gold: アウター 60・インナー 80・ベースタワー 100。ラストヒットのボーナスは無い。
        public static func teamGold(tier: TowerTier) -> Double {
            switch tier {
            case .outer: return 60
            case .inner: return 80
            case .base: return 100
            }
        }

        /// 近くにいたヒーローは 50 を分け合う（1 人なら 110 / 130 / 150）。分け方と範囲は資料に無いので、
        /// 等分・ヒーローの XP の分配と同じ範囲（Balance.xpShareRadius）にした。
        public static let nearbyBonusGold: Double = 50
        public static var nearbyRadius: Double { Balance.xpShareRadius }
    }
}
