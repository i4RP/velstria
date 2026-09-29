import Foundation

// 担当: core-economy
// 経済・成長・試合進行の追加定数（DESIGN §3, §4, §8, §11）。
// 他担当の `extension Balance` と名前が衝突しないよう `Balance.Economy` にまとめる（統合時に集約可）。

extension Balance {
    public enum Economy {
        // MARK: XP
        /// 2 人以上で XP を分け合う時の合計倍率（DESIGN §8）。
        public static let groupXPMultiplier: Double = 1.3
        /// ヒーローキル XP = base + perLevel × 被害者Lv。
        public static let heroKillXPBase: Double = 100
        public static let heroKillXPPerLevel: Double = 30
        /// アシスト（1400 以内）で等分する XP の割合。
        public static let assistXPShare: Double = 0.6

        // MARK: ミニオン・モンスター報酬（ラストヒット Gold / 共有 XP）
        public static func minionGold(_ type: MinionType) -> Double {
            switch type {
            case .melee: return 22
            case .ranged: return 16
            case .siege: return 50
            }
        }

        public static func minionXP(_ type: MinionType) -> Double {
            switch type {
            case .melee: return 60
            case .ranged: return 32
            case .siege: return 95
            }
        }

        /// ラストヒット Gold（撃破者の monsterGoldBonus で増加）。ボスはチーム報酬のみ。
        /// 小キャンプ = 大 40 + 小 15×2 = 70。
        public static func monsterGold(_ kind: MonsterKind) -> Double {
            switch kind {
            case .campLarge: return 40
            case .campSmall: return 15
            case .blueSentinel, .redSentinel: return 110
            case .astralWyrm, .ancientColossus: return 0
            }
        }

        /// 周囲で共有する XP。小キャンプ = 大 50 + 小 30×2 = 110。ボスはチーム全員に固定値。
        public static func monsterXP(_ kind: MonsterKind) -> Double {
            switch kind {
            case .campLarge: return 50
            case .campSmall: return 30
            case .blueSentinel, .redSentinel: return 180
            case .astralWyrm, .ancientColossus: return 0
            }
        }

        // MARK: オブジェクト
        public static let wyrmTeamGold: Double = 150
        public static let wyrmTeamXP: Double = 200
        public static let wyrmBlessingDuration: Double = 150
        public static let wyrmBlessingDamageBonus: Double = 0.10
        public static let colossusTeamGold: Double = 300
        public static let colossusTeamXP: Double = 300
        public static let colossusBlessingDuration: Double = 180
        public static let colossusBlessingDamageBonus: Double = 0.15
        /// 蒼晶/紅焔バフの持続。
        public static let sentinelBuffDuration: Double = 90
        /// Jungle 装備のモンスター Gold 補正。
        public static let jungleMonsterGoldBonus: Double = 0.20

        // MARK: キル告知
        /// 連続キル（マルチキル）の間隔上限。
        public static let multiKillWindow: Double = 10
        public static let maxMultiKill = 5
        /// 連続キル告知を出すストリーク数。
        public static let killingSpreeStreaks = [3, 5, 8]
        /// この連続キル数以上の相手を倒すとシャットダウン告知。
        public static let shutdownStreak = 3

        // MARK: 装備
        /// ジャングル装備の購入条件となるバトルスペル（狩猟印）。
        public static let smiteSpellID = "BS05"
        /// 練習場の無限 Gold で維持する所持金。
        public static let practiceGold: Double = 99_999

        // MARK: 回復
        /// 戦闘中の HP 自然回復倍率。
        public static let combatRegenMultiplier: Double = 0.5

        // MARK: 帰還門
        /// 帰還門の転移先として有効な味方タワーからの距離。
        public static let teleportTowerRadius: Double = 400

        // MARK: 降参
        public static let surrenderVoteDuration: Double = 15
        /// AI 味方が賛成する条件（どちらか一方）。
        public static let surrenderGoldDeficit: Double = 3000
        public static let surrenderTowerDeficit = 3
        /// AI 味方が投票するまでの遅延（開始からの秒、AI 毎に interval ずつずらす）。
        public static let botVoteDelay: Double = 1.5
        public static let botVoteInterval: Double = 1.0
    }
}
