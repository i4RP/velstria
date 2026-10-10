import Foundation

// 担当: core-world。ジャングル（MLBB の現行マップ「Sanctum Island」に合わせたモンスターとバフ）の定数。
// docs/DESIGN.md §2・§4。出典は MLBB Wiki の各モンスターの記載と Patch 2.1.88 / 2.1.90（2026 年 6〜7 月）。
// ヒーローの数値が MLBB と同じ規模なので、バフの回復量・シールド量・確定ダメージは資料の値をそのまま使う。
// モンスターの HP・攻撃は資料の比（紅焔の番人 4941 HP に対する比）を従来の番人（2200 HP）へ掛けて決めた。

extension Balance {
    public enum Jungle {
        // MARK: 出現・再出現（秒）
        /// 両陣地のキャンプ（番人・小キャンプ）の初回出現。Patch 2.1.88 で小キャンプも 0:25 になり、全キャンプが揃って出る。
        public static let campFirstSpawn: Double = 25
        /// 番人（紫・赤バフ）の再出現。
        public static let buffRespawn: Double = 90
        /// 棘角トカゲ・熾甲虫・熔岩の岩人の再出現。
        public static let creepRespawn: Double = 70
        /// 宝殻蟹: 子は 0:42 から 20 秒ごとに出直し、3:00 に親へ替わって以後は 120 秒ごと。
        public static let crabFirstSpawn: Double = 42
        public static let crabletRespawn: Double = 20
        public static let crabUpgradeTime: Double = 180
        public static let crabRespawn: Double = 120
        /// 苔甲の徘徊者（川の中立）。
        public static let wandererFirstSpawn: Double = 45
        public static let wandererRespawn: Double = 120
        /// 熾甲虫を倒すと出る幼体の寿命。
        public static let grubLifetime: Double = 15

        // MARK: 紫バフ（蒼晶の番人。75 秒）
        /// スキルの再使用時間 −10%。
        public static let purpleCooldownReduction: Double = 0.10
        /// スキルの消費: Mana −60% / Energy −25%。
        public static let purpleManaCostMultiplier: Double = 0.40
        public static let purpleEnergyCostMultiplier: Double = 0.75
        /// 敵を倒すと最大 HP の割合で回復: ミニオン 3% / ヒーロー 8% / モンスター 12%。
        public static let purpleKillHealMinion: Double = 0.03
        public static let purpleKillHealHero: Double = 0.08
        public static let purpleKillHealMonster: Double = 0.12

        // MARK: 赤バフ（紅焔の番人。75 秒）
        /// 敵ヒーローに攻撃（通常攻撃・スキル）が当たると溶岩の魂が追撃し、確定ダメージとスロー 1 秒。間隔 3 秒。
        /// 前衛（ヴァンガード・デュエリスト・アサシン）は スロー強め・追撃弱め、後衛（レンジャー・アルカニスト・サポート）は逆。
        public static let redStrikeCooldown: Double = 3
        public static let redStrikeBase: Double = 50
        public static let redSlowDuration: Double = 1
        public static let redFrontAttackRatio: Double = 0.20
        public static let redBackAttackRatio: Double = 0.30
        /// 追撃に足す対象の最大 HP の割合。
        public static let redFrontTargetHPRatio: Double = 0.003
        public static let redBackTargetHPRatio: Double = 0.005
        public static let redFrontSlow: Double = 0.60
        public static let redBackSlow: Double = 0.20
        /// 適応貫通（追加の物攻 ≥ 追加の魔力なら物理、そうでなければ魔法の割合貫通）。
        public static let redFrontPenetration: Double = 0.05
        public static let redBackPenetration: Double = 0.10

        // MARK: 回復バフ（棘角トカゲ・熾甲虫・熔岩の岩人・蒼晶の仔）
        public static let healingBuffHP: Double = 350
        /// 最大 Mana の割合（Energy のヒーローは回復しない）。
        public static let healingBuffManaPct: Double = 0.05

        // MARK: 宝殻蟹の Gold バフ（毎秒に均して入る）
        public static let crabGoldBuffTotal: Double = 60
        public static let crabGoldBuffDuration: Double = 18
        public static let crabletGoldBuffTotal: Double = 30
        public static let crabletGoldBuffDuration: Double = 10

        // MARK: 苔草（苔甲の徘徊者）
        public static let mossGrassDuration: Double = 45
        /// 川（`MapDefinition.isInRiver`）にいる間の移動速度 +15%。
        public static let mossGrassRiverSpeed: Double = 0.15
        /// 苔草を連れたヒーローの近くの味方（本人を含む）の Mana を毎秒 最大値の 1% 回復。
        public static let mossGrassManaPerSecond: Double = 0.01
        public static let mossGrassRadius: Double = 600
        /// 撃破者の近くの味方にも少しの Gold。
        public static let wandererAllyGold: Double = 15
        public static let wandererAllyRadius: Double = 1400

        // MARK: 棘角トカゲ（HP が半分を切ると防御・魔防 +70 → 被ダメ約 −30% に換算）
        public static let lizardHardenThreshold: Double = 0.5
        public static let lizardHardenReduction: Double = 0.30

        // MARK: 星喰竜（序盤ボス）
        /// チーム全員の Gold（1 体目 / 2 体目 / 3 体目以降）。
        public static let wyrmTeamGold: [Double] = [60, 70, 80]
        /// 撃破者の加護（120 秒）: 5 秒被弾しないと張り直すシールド 400 + 40×Lv。
        /// シールドが残っている間は 物攻 20 + 2×Lv か 魔力 25 + 4×Lv（適応）。
        public static let wyrmBlessingDuration: Double = 120
        public static let wyrmShieldBase: Double = 400
        public static let wyrmShieldPerLevel: Double = 40
        public static let wyrmShieldRegenDelay: Double = 5
        public static let wyrmAttackBase: Double = 20
        public static let wyrmAttackPerLevel: Double = 2
        public static let wyrmPowerBase: Double = 25
        public static let wyrmPowerPerLevel: Double = 4
        /// 撃破者以外の味方: 一度きりのシールド 200 + 20×Lv（120 秒）。
        public static let wyrmAllyShieldBase: Double = 200
        public static let wyrmAllyShieldPerLevel: Double = 20
    }
}
