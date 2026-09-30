import Foundation

// 担当: core-bots
// AI（ボット）の調整定数（DESIGN §10）。他担当の extension と衝突しないよう `Balance.Bot` にまとめる。

extension Balance {
    public enum Bot {
        // MARK: 意思決定
        /// 意思決定の間隔（tick）。30Hz / 6 = 5Hz。ボット毎に 1 tick ずつずらす。
        public static let decisionIntervalTicks = 6
        /// チーム方針（集団行動・オブジェクト）の更新間隔（tick）。
        public static let planIntervalTicks = 30
        /// 視界から消えた敵を「居るかもしれない」とみなす秒数（霧の中の記憶）。
        public static let fogMemory: Double = 3.5

        // MARK: 知覚
        /// 敵ヒーローを戦闘判断に含める半径。
        public static let awarenessRadius: Double = 1400
        /// 味方ヒーローを戦力に数える半径。
        public static let allyRadius: Double = 1500
        /// 帰還を始めてよい敵との距離。
        public static let recallSafeRadius: Double = 1200

        // MARK: 撤退・帰還
        public static let retreatHP: Double = 0.30
        public static let retreatHPOutnumbered: Double = 0.45
        /// 泉で回復を待つ HP / リソースの割合。
        public static let fountainLeaveHP: Double = 0.92
        public static let fountainLeaveResource: Double = 0.7
        /// この距離より泉が近ければ帰還せず歩く。
        public static let walkHomeDistance: Double = 2200
        /// 買い物のための帰還（所持 Gold と HP の条件）。
        public static let shopRecallGold: Double = 1300
        public static let shopRecallGoldAlways: Double = 2300
        public static let shopRecallMaxHP: Double = 0.75

        // MARK: レーン
        /// 敵タワーの射程（+ 半径）に対する安全余白。
        public static let towerSafetyMargin: Double = 90
        /// 味方ミニオンの最前線からの待機距離（遠隔 / 近接）。
        public static let rangedHoldBehind: Double = 260
        public static let meleeHoldBehind: Double = 90
        /// 敵ウェーブがこの数以上多ければ下がる。
        public static let waveDisadvantage = 3
        /// ラストヒット候補を探す距離（射程への追加分）。
        public static let lastHitSearchBonus: Double = 260
        /// この秒数、敵ヒーローを見ていないレーンは「空き」とみなしてウェーブを押す。
        public static let emptyLaneSeconds: Double = 6
        /// ヒーロー同士の小競り合い（ハラス）を始める HP 割合の差。
        public static let harassHPEdge: Double = 0.12

        // MARK: 戦闘
        /// 劣勢で撤退する戦力比。
        public static let fleeRatio: Double = 0.62
        /// 追跡をやめる距離（戦闘開始地点から）。
        public static let chaseLimit: Double = 1600
        /// 遠隔ヒーローが近接に詰められたとみなす距離。
        public static let kiteDistance: Double = 260

        // MARK: ジャングル
        public static let jungleStart: Double = 30
        /// ガンクに向かう最大経路長。
        public static let gankMaxPath: Double = 4200
        /// ガンクを諦める秒数。
        public static let gankTimeout: Double = 24
        /// 狩猟印（BS05）のダメージ = base + perLevel × Lv（DESIGN §7）。
        public static let smiteBase: Double = 600
        public static let smitePerLevel: Double = 40
        public static let smiteRange: Double = 500
        /// キャンプ中心から「キャンプに居る」とみなす距離。
        public static let campEngageRadius: Double = 900

        // MARK: マクロ
        /// 星喰竜を狙い始める時刻。
        public static let wyrmStart: Double = 120
        /// 古環の巨像を狙い始める時刻。
        public static let colossusStart: Double = 8 * 60
        /// 集団行動（押し込み）を始める時刻。
        public static let groupStart: Double = 10 * 60
        /// 全員で押し切る終盤の時刻。
        public static let lateSiege: Double = 20 * 60
        /// オブジェクトを諦める秒数。
        public static let objectiveTimeout: Double = 55

        // MARK: スペル（DESIGN §7）
        public static let flashDistance: Double = 400
        public static let igniteRange: Double = 600
        public static let chainRange: Double = 650
        public static let healWaveRange: Double = 800
    }
}

/// 難易度毎の AI 特性（DESIGN §10）。
struct BotProfile {
    /// 新しく見えた脅威に反応するまでの秒数。
    var reaction: Double
    /// スキル照準の精度（予測射撃が意図どおりに入る確率）。
    var accuracy: Double
    /// 撃てる状況でスキルを使う確率（意思決定毎）。
    var skillChance: Double
    /// 交戦を始める戦力比。
    var engageRatio: Double
    /// ラストヒットで他ユニットの攻撃を予測する精度（0 = 予測しない）。
    var lastHitSkill: Double
    /// 確実なキルならタワー下へ踏み込む。
    var divesForKill: Bool
    /// 集団行動に加わる味方の数（チーム方針のメンバー上限）。
    var groupSize: Int
    /// スキルでミニオンを倒す（押し込み）ときの最低リソース割合（1 超 = 使わない）。
    var farmSkillResource: Double
    /// 集団行動を始める時刻。
    var groupStart: Double

    static func of(_ d: Difficulty) -> BotProfile {
        switch d {
        case .easy:
            return BotProfile(reaction: 0.6, accuracy: 0.55, skillChance: 0.35, engageRatio: 1.0, lastHitSkill: 0.4,
                              divesForKill: false, groupSize: 3, farmSkillResource: 2, groupStart: 12 * 60)
        case .normal:
            return BotProfile(reaction: 0.35, accuracy: 0.75, skillChance: 0.7, engageRatio: 1.15, lastHitSkill: 0.8,
                              divesForKill: false, groupSize: 4, farmSkillResource: 0.7, groupStart: Balance.Bot.groupStart)
        case .hard:
            return BotProfile(reaction: 0.15, accuracy: 0.92, skillChance: 1.0, engageRatio: 1.1, lastHitSkill: 1.0,
                              divesForKill: true, groupSize: 5, farmSkillResource: 0.5, groupStart: 9 * 60)
        }
    }
}
