import Foundation

// 担当: core-world。ジャングル（MLBB の現行マップ「Sanctum Island」に合わせたモンスターとバフ）の定数。
// docs/DESIGN.md §2・§4。出典は MLBB Wiki の各モンスターの記載と Patch 2.1.88 / 2.1.90（2026 年 6〜7 月）。
// ヒーローの数値が MLBB と同じ規模なので、バフの回復量・シールド量・確定ダメージは資料の値をそのまま使う。
// モンスターの能力値・Gold は、最後に公開された Fandom の表（2021〜2022 年）に、その後の公式の変更率を掛けた値（丸めない）。
// 2.2.16 の絶対値はどこにも公開されていない。2.1.88 の増減（紫 HP 増・赤 HP 減・小キャンプ HP 増）は量が非公表なので入っていない。
// 作り方と出典は docs/JUNGLE_ROAM_MLBB.md。

extension Balance {
    public enum Jungle {
        // MARK: 出現・再出現（秒）
        /// 両陣地のキャンプ（番人・小キャンプ）の初回出現。Patch 2.1.88 で小キャンプも 0:25 になり、全キャンプが揃って出る。
        public static let campFirstSpawn: Double = 25
        /// 番人（紫・赤バフ）の再出現。
        public static let buffRespawn: Double = 90
        /// 棘角トカゲ・熾甲虫・熔岩の岩人の再出現。
        public static let creepRespawn: Double = 70
        /// 宝殻蟹: 0:42 に出て、45 秒で再出現（MLBB Patch 1.9.90）。子は出ない。ロードが出た後は湧かない（1.8.56）。
        public static let crabFirstSpawn: Double = 42
        public static let crabRespawn: Double = 45
        /// 苔甲の徘徊者（川の中立）。
        public static let wandererFirstSpawn: Double = 45
        public static let wandererRespawn: Double = 120
        /// 熾甲虫を倒すと出る幼体の寿命。
        public static let grubLifetime: Double = 15
        // MARK: モンスターの能力値の変更率（Fandom の値に掛ける）
        /// Patch 1.9.90: バフ 2 体と小キャンプ 3 種は HP +30%・攻撃 −15%。
        public static let campHPScale1990: Double = 1.3
        public static let campAttackScale1990: Double = 0.85
        /// Patch 2.1.18: 全モンスターの Gold −7.5%。Patch 2.1.90: バフ +20%・小キャンプ +15%。Patch 2.2.16: 小キャンプ −13%。
        public static let goldScale2118: Double = 0.925
        public static let buffGoldScale2190: Double = 1.2
        public static let campGoldScale2190: Double = 1.15
        public static let campGoldScale2216: Double = 0.87
        /// 棘角トカゲ: HP が半分を切ると物理防御・魔法防御 +70。
        public static let lizardHardenDefense: Double = 70

        // MARK: ロード
        /// ロードの能力値の伸びが止まる分（MLBB: 18 分）。
        public static let lordGrowthCapMinutes: Double = 18
        /// 味方になったロードが突進で塔に与える確定ダメージ（塔の最大 HP の割合。MLBB Patch 1.9.64、8:00〜18:00）。
        public static let lordTowerChargeRatio: Double = 0.30
        /// 中立のロードの通常攻撃: 攻撃の 20% + 対象の最大 HP の 10% の物理ダメージ（MLBB Patch 1.8.30）。
        public static let lordAttackRatio: Double = 0.20
        public static let lordAttackTargetHPRatio: Double = 0.10
        /// 中立のロードの雷撃: 50 + 対象の最大 HP の 15% の確定ダメージ（1.8.30）。間隔 4 秒は Fandom の Thunder Strike、
        /// 範囲（ロードの縁から 600）は仮。
        public static let lordStrikeBase: Double = 50
        public static let lordStrikeTargetHPRatio: Double = 0.15
        public static let lordStrikeInterval: Double = 4
        public static let lordStrikeRadius: Double = 600
        /// 中立のロード: 戦闘中は毎秒 物理貫通 +10%（最大 10 回。1.8.92）。
        public static let lordPenPerStack: Double = 0.10
        public static let lordPenMaxStacks = 10
        /// 中立のロードの被ダメ軽減 40%、縁から 500 のヒーロー 1 人ごとに −5%、下限 15%（1.6.42）。
        public static let lordBaseReduction: Double = 0.40
        public static let lordReductionPerHero: Double = 0.05
        public static let lordMinReduction: Double = 0.15
        public static let lordReductionRadius: Double = 500
        /// 味方になって進化したロード: 周りの味方ヒーロー 0〜5 人に応じて被ダメ 15〜35% 軽減（1.9.64）。範囲 800 は仮。
        public static let alliedLordBaseReduction: Double = 0.15
        public static let alliedLordReductionPerHero: Double = 0.04
        public static let lordAuraRadius: Double = 800
        /// 味方になって進化したロードの加護: 近くの味方が敵ヒーローを攻撃すると、追加の魔法ダメージ
        /// 400 + 物理攻撃 60% + 魔法攻撃 60% + 最大 HP 3%（攻撃した味方の値。CD 2 秒。MLBB Patch 1.6.84）。
        public static let lordAuraBase: Double = 400
        public static let lordAuraAttackRatio: Double = 0.6
        public static let lordAuraPowerRatio: Double = 0.6
        public static let lordAuraMaxHPRatio: Double = 0.03
        public static let lordAuraCooldown: Double = 2

        // MARK: 川の流れ（MLBB Patch 1.8.44 / 1.9.90）
        /// タートルの出現のこの秒数前から、そのタートルが倒されるまで、川の流れが巣へ向かう。
        public static let riverCurrentLead: Double = 15
        /// 流れに沿って動くときの移動速度の上乗せ（最大）。
        public static let riverCurrentSpeed: Double = 0.5

        // MARK: 序盤の規則（MLBB）
        /// この時刻（秒）まで序盤の規則が働く。
        public static let earlyJungleRuleEnd: Double = 120
        /// 敵のジャングルにいるヒーローの被ダメ倍率（+20%。MLBB Patch 1.8.78C）。
        public static let invaderDamageTaken: Double = 1.2
        /// 自陣のジャングルで倒れたモンスターの報酬を受け取る、自陣の狩猟印持ちの距離（MLBB Patch 1.9.06）。
        public static let homeJungleRewardRadius: Double = 1400
        /// 自陣のバフは、この秒数以内にダメージを与えた狩猟持ちが近くに居れば、最も近い狩猟持ちに付く（MLBB Patch 2.1.18。秒数は仮）。
        public static let homeBuffHitWindow: Double = 5

        // MARK: 紫バフ（蒼晶の番人。75 秒）
        /// スキルの再使用時間 −10%。
        public static let purpleCooldownReduction: Double = 0.10
        /// スキルの消費: Mana −40% / Energy −20%（MLBB Patch 1.8.78）。
        public static let purpleManaCostMultiplier: Double = 0.60
        public static let purpleEnergyCostMultiplier: Double = 0.80
        /// 敵を倒すと最大 HP の割合で回復: ミニオン 3% / ヒーロー 5%（MLBB Patch 1.6.58 で 8 → 5）/ モンスター 12%。
        public static let purpleKillHealMinion: Double = 0.03
        public static let purpleKillHealHero: Double = 0.05
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

        // MARK: 棘角トカゲ（HP が半分を切ると物理防御・魔法防御 +70。値は lizardHardenDefense）
        public static let lizardHardenThreshold: Double = 0.5

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
