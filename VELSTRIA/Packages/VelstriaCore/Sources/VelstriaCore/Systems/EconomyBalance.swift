import Foundation

// 担当: core-economy
// 経済・成長・試合進行の追加定数（DESIGN §3, §4, §8, §11）。
// 他担当の `extension Balance` と名前が衝突しないよう `Balance.Economy` にまとめる（統合時に集約可）。

extension Balance {
    public enum Economy {
        // MARK: モード別の加速（DESIGN §8）
        /// モード別の Gold 倍率（乱闘は加速）。`grantGold` で適用（無限 Gold 時は適用しない）。
        public static func goldScale(_ mode: MatchMode) -> Double { mode == .brawl ? 2.0 : 1.0 }
        /// モード別の XP 倍率（乱闘は加速）。`grantXP` で適用。
        public static func xpScale(_ mode: MatchMode) -> Double { mode == .brawl ? 2.0 : 1.0 }

        // MARK: XP
        /// 2 人以上で XP を分け合う時の合計倍率（DESIGN §8）。
        public static let groupXPMultiplier: Double = 1.3
        /// ヒーローキル XP = base + perLevel × 被害者Lv。
        public static let heroKillXPBase: Double = 100
        public static let heroKillXPPerLevel: Double = 30
        /// アシスト（1400 以内）で等分する XP の割合。
        public static let assistXPShare: Double = 0.6

        // MARK: ミニオン・モンスター報酬（ラストヒット Gold / 共有 XP）
        /// ミニオン Gold が最大値に達する試合時間（秒）。
        public static let minionGoldGrowthSeconds: Double = 1800

        /// ラストヒット Gold。参照仕様（MLBB Wiki）の値をそのまま使い、開始時の値から 30 分で最大値へ線形に増える
        /// （近接 65 → 120 / 遠隔 33 → 90 / 攻城 100 → 150、REFERENCE_SPEC §5.2）。
        public static func minionGold(_ type: MinionType, at time: Double = 0) -> Double {
            let range: (start: Double, end: Double)
            switch type {
            case .melee: range = (65, 120)
            case .ranged: range = (33, 90)
            case .siege: range = (100, 150)
            }
            return (range.start + (range.end - range.start) * min(1, max(0, time / minionGoldGrowthSeconds))).rounded()
        }

        public static func minionXP(_ type: MinionType) -> Double {
            switch type {
            case .melee: return 60
            case .ranged: return 32
            case .siege: return 95
            }
        }

        /// ラストヒット Gold（撃破者の monsterGoldBonus で増加）。ボスはチーム報酬のみ。
        /// MLBB の値（棘角トカゲ 92・熾甲虫 85・熔岩の岩人 81・紅焔 120・蒼晶 100 + 仔 22）に近づけ、
        /// 1 陣地を一巡したときの合計が旧マップ（番人 2 + 小キャンプ 5）と同じ程度になるよう丸めた。
        /// 宝殻蟹は撃破時の Gold に加えて Gold バフ（Balance.Jungle）。
        public static func monsterGold(_ kind: MonsterKind) -> Double {
            switch kind {
            case .campLarge: return 40
            case .campSmall: return 15
            case .blueSentinel: return 90
            case .azureWhelp: return 20
            case .redSentinel: return 110
            case .hornLizard: return 95
            case .emberBeetle: return 75
            case .emberGrub: return 15
            case .magmaGolem: return 85
            case .treasureCrab: return 40
            case .crablet: return 15
            case .mossWanderer: return 90
            case .astralWyrm, .ancientColossus: return 0
            }
        }

        /// 周囲で共有する XP。ボスはチーム全員に固定値。
        /// MLBB Patch 2.1.88: 小キャンプの主は 1 体で Lv2（240）に届き、番人の XP を下げて「5 キャンプで Lv4（累計 810）」を保つ
        /// （主 240 × 3 + 紅焔 45 + 蒼晶 35 + 仔 10 = 810）。
        public static func monsterXP(_ kind: MonsterKind) -> Double {
            switch kind {
            case .campLarge: return 50
            case .campSmall: return 30
            case .blueSentinel: return 35
            case .azureWhelp: return 10
            case .redSentinel: return 45
            case .hornLizard, .emberBeetle, .magmaGolem: return 240
            case .emberGrub: return 20
            case .treasureCrab: return 60
            case .crablet: return 30
            case .mossWanderer: return 100
            case .astralWyrm, .ancientColossus: return 0
            }
        }

        // MARK: Gold/EXP レーン補正（参照仕様 §3.1・§5.2）
        /// 補正が続く試合時間（秒）。参照では側レーンの最初の 10 ウェーブ（〜5:00）。
        public static let laneBonusEnd: Double = 300
        /// Gold レーン（最初のボスから遠い側レーン）のミニオン Gold 倍率の上乗せ。
        /// 参照は攻城ミニオンだけ +45% だが、VELSIA の攻城は 3 ウェーブに 1 体のため、ウェーブ全体へ換算した値。
        public static let goldLaneGoldBonus: Double = 0.25
        /// EXP レーン（最初のボスに近い側レーン）のミニオン XP 倍率の上乗せ（参照は攻城のみ +35%、同じく換算）。
        public static let expLaneXPBonus: Double = 0.40

        // MARK: オブジェクト
        /// 星喰竜のチーム XP（Gold・加護・シールドは Balance.Jungle）。
        public static let wyrmTeamXP: Double = 200
        public static let colossusTeamGold: Double = 300
        public static let colossusTeamXP: Double = 300
        public static let colossusBlessingDuration: Double = 180
        public static let colossusBlessingDamageBonus: Double = 0.15
        /// 蒼晶/紅焔バフの持続。
        public static let sentinelBuffDuration: Double = 75
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
