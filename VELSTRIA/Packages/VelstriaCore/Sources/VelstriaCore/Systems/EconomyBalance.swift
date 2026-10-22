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

        /// MLBB の値は非公開。1 ウェーブが MLBB と同じ 3〜4 体になったので、MLBB の目安
        /// 「中央・EXP レーンは 4 ウェーブ目（約 2:00）で Lv4（累計 810）」に合わせた（中央 近接 + 遠隔 3 = 210、EXP レーン 238）。
        public static func minionXP(_ type: MinionType) -> Double {
            switch type {
            case .melee: return 60
            case .ranged: return 50
            case .siege: return 95
            }
        }

        /// ラストヒット Gold（撃破者の monsterGoldBonus で増加）。ボスはチーム報酬のみ。
        /// Fandom の撃破 Gold（蒼晶 100 + 仔 22・紅焔 120・棘角トカゲ 92・熔岩の岩人 81・苔甲の徘徊者 92）に、その後の公式の
        /// 変更率を掛けた値（丸めない。docs/JUNGLE_ROAM_MLBB.md）: 2.1.18 全モンスター −7.5%、2.1.90 バフ +20%・小キャンプ +15%、
        /// 2.2.16 小キャンプ −13%。熾甲虫・幼体は資料に無いので旧来の値。宝殻蟹は Gold レーン側だけ（DeathSystem）。
        public static func monsterGold(_ kind: MonsterKind) -> Double {
            typealias J = Balance.Jungle
            let buff = J.goldScale2118 * J.buffGoldScale2190
            let camp = J.goldScale2118 * J.campGoldScale2190 * J.campGoldScale2216
            switch kind {
            case .campLarge: return 40
            case .campSmall: return 15
            case .blueSentinel: return 100 * buff
            case .azureWhelp: return 22 * buff
            case .redSentinel: return 120 * buff
            case .hornLizard: return 92 * camp
            case .emberBeetle: return 75
            case .emberGrub: return 15
            case .magmaGolem: return 81 * camp
            case .treasureCrab: return 40
            case .crablet: return 15
            case .mossWanderer: return 92 * J.goldScale2118
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
            // 宝殻蟹: EXP レーン側だけ。Gold レーン側の Gold 40 と同じ値（MLBB Patch 1.8.78。額は非公表）
            case .treasureCrab: return 40
            case .crablet: return 30
            case .mossWanderer: return 100
            case .astralWyrm, .ancientColossus: return 0
            }
        }

        // MARK: Gold/EXP レーン補正（参照仕様 §3.1・§5.2）
        /// 最初の 10 ウェーブ（Balance.earlyWaveCount、〜4:41 に出る分）の攻城ミニオンだけに付く（MLBB と同じ）。
        /// Gold レーン（最初のボスから遠い側レーン）の攻城ミニオンの Gold 倍率の上乗せ。
        public static let goldLaneGoldBonus: Double = 0.45
        /// EXP レーン（最初のボスに近い側レーン）の攻城ミニオンの XP 倍率の上乗せ。
        public static let expLaneXPBonus: Double = 0.35

        // MARK: チーム賞金（MLBB の Team Bounty。DeathSystem.teamBounty）
        /// 発動に要るチームの Gold の差（MLBB 2.2.16: 2000 → 1500）。
        public static let teamBountyDeficit: Double = 1500
        /// 倒されたヒーローの Gold が倒した側の平均を上回る分のうち、倒した側の全員へ配る割合（等分）。
        /// MLBB の式は資料に無い仮の値（docs/TOWER_BASE_MLBB.md）。
        public static let teamBountyShare: Double = 0.25

        // MARK: オブジェクト
        /// 星喰竜のチーム XP（Gold・加護・シールドは Balance.Jungle）。
        public static let wyrmTeamXP: Double = 200
        /// ロードのチーム全員への Gold = 50 + 10 × 試合時間（分）（MLBB Patch 2.1.40a）。
        public static let colossusTeamGoldBase: Double = 50
        public static let colossusTeamGoldPerMinute: Double = 10
        public static func colossusTeamGold(at time: Double) -> Double {
            colossusTeamGoldBase + colossusTeamGoldPerMinute * (max(0, time) / 60 + 1e-9).rounded(.down)
        }
        public static let colossusTeamXP: Double = 300
        /// 蒼晶/紅焔バフの持続。
        public static let sentinelBuffDuration: Double = 75
        /// Jungle 装備のモンスター Gold 補正。
        public static let jungleMonsterGoldBonus: Double = 0

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
