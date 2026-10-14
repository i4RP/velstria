import Foundation

// 担当: core-skills
// スキル・パッシブの調整定数（DESIGN §6）。統合フェーズで Balance.swift へ集約してよい。
// 他担当の extension と衝突しないよう `Balance.Skills` にまとめる。

extension Balance {
    public enum Skills {
        // MARK: 全体係数は無い（2026-10-14。MLBB の値をそのまま使う）
        // 以前あった倍率（スロット倍率 4.0 / 3.0 / 2.6・物理係数 × 0.6・回復 × 2.4・ミニオンへのスキル × 0.2・CD 倍率）は外した。
        // キットのヒーロー（H025–H034）は公式の表、汎用のヒーロー（H001–H024）は MLBB のロール × 枠の型（GenericTemplate）。
        // ミニオン・モンスターへの補正はスキルごと（HitPayload.minionMultiplier など。MLBB に全体の倍率は無い）。

        // MARK: Skill1
        /// 近接の前方扇形の半角（90° の扇）。
        public static let coneHalfAngle: Double = Double.pi / 4
        /// 遠隔の直線スキルショット: 弾速・当たり幅（半径 = radius × 比率）。
        public static let skillshotSpeed: Double = 1600
        public static let skillshotWidthRatio: Double = 0.5

        // MARK: Skill2
        /// 近接の突進: 距離 = range + この値、速度。
        public static let dashExtraRange: Double = 100
        public static let dashSpeed: Double = 1500
        /// 遠隔のブリンク距離・強化の持続（強化攻撃の追加ダメージは GenericTemplate の値そのもの）。
        public static let blinkDistance: Double = 350
        public static let empowerDuration: Double = 4

        // MARK: 地点 AoE・回復ゾーンの定数（Ult のアーキタイプが使う）
        /// 地点指定 AoE の予告時間。
        public static let groundTelegraph: Double = 0.5
        /// ヴァンガードの自身中心 AoE: 自身へ最大 HP 8% のシールド。
        public static let selfShieldMaxHPRatio: Double = 0.08
        public static let selfShieldDuration: Double = 3

        // MARK: Ultimate
        /// ヴァンガード: 跳躍（最大 range + 200）、着地 AoE radius × 1.4、跳躍速度。
        public static let leapExtraRange: Double = 200
        public static let leapRadiusMultiplier: Double = 1.4
        public static let leapSpeed: Double = 1300
        /// デュエリスト: 3 回（0.6 秒で。1 回のダメージは GenericTemplate）+ 自身 25% 被ダメ軽減 2 秒。
        public static let multiStrikeCount = 3
        public static let multiStrikeDuration: Double = 0.6
        public static let multiStrikeDamageReduction: Double = 0.25
        public static let multiStrikeReductionDuration: Double = 2
        /// レンジャー: 貫通大矢（長さ 2000、幅 = radius）。
        public static let piercingLength: Double = 2000
        public static let piercingSpeed: Double = 2200
        /// アルカニスト: 1.0 秒予告、radius × 1.8。
        public static let arcanistUltTelegraph: Double = 1.0
        public static let arcanistUltRadiusMultiplier: Double = 1.8
        /// サポート: 1500 以内の味方ヒーローを回復（GenericTemplate の値）+ 回復量 × 0.5 のシールド。
        public static let teamHealRadius: Double = 1500
        public static let teamHealShieldRatio: Double = 0.5
        public static let teamHealShieldDuration: Double = 3
        /// アサシン: 失った HP の 12% を追加ダメージ。
        public static let executeMissingHPRatio: Double = 0.12
        /// 対象の背後へ出る時の間隔。
        public static let targetedBlinkGap: Double = 10

        // MARK: パッシブ（DESIGN §6。ヒーロー係数 k = 1.0 + 0.02 × (番号 mod 5)）
        public static let passiveCoefficientStep: Double = 0.02
        /// ヴァンガード: HP 40% 未満で最大 HP 15%×k のシールド（CD 20 秒）。
        public static let vanguardShieldThreshold: Double = 0.40
        public static let vanguardShieldRatio: Double = 0.15
        public static let vanguardShieldCooldown: Double = 20
        public static let vanguardShieldDuration: Double = 4
        /// デュエリスト: 通常攻撃命中毎に攻撃速度 +6%×k（最大 5 スタック、3 秒）。
        public static let duelistAttackSpeedPerStack: Double = 0.06
        public static let duelistMaxStacks = 5
        public static let duelistStackDuration: Double = 3
        /// レンジャー: 4 発毎の通常攻撃が必ずクリティカル（1.75×k 倍）。
        public static let rangerCritEvery = 4
        /// アルカニスト: スキル命中で他スキル CD −0.6 秒×k（1 キャストにつき 1 回）。
        public static let arcanistRefund: Double = 0.6
        /// サポート: スキル使用時、800 以内で HP 割合最低の味方を 40 + 10×Lv×k 回復。
        public static let supportHealBase: Double = 40
        public static let supportHealPerLevel: Double = 10
        public static let supportHealRadius: Double = 800
        /// アサシン: 草むら/ステルス解除後 3 秒以内の最初のダメージ +30%×k、キル/アシストで全 CD −30%。
        public static let assassinAmbushBonus: Double = 0.30
        public static let assassinAmbushWindow: Double = 3
        public static let assassinTakedownRefund: Double = 0.30

        // MARK: ステータスのタグ
        public static let duelistPassiveTag = "passive.duelist"
        public static let vanguardPassiveTag = "passive.vanguard"
        public static let multiStrikeTag = "skill.multiStrike"
    }
}

// MARK: - 汎用スキル（H001–H024）の MLBB の型（docs/GENERIC_SKILLS.md）

extension Balance.Skills {
    /// 汎用のスキル 1 つ分の型（MLBB の同じロール・同じ枠のスキルの中央値。出典と導き方は docs/GENERIC_SKILLS.md）。
    /// ダメージ（回復）= base[段] × (base_damage / meanBase) + ratio × (係数 / meanScaling) × 能力値。
    /// 能力値は物理のスキル = 総物理攻撃、魔法のスキル = 魔法攻撃（MLBB のスキルは 1 つの能力値で伸びる。もう片方の master の係数は使わない）。
    /// 「÷ mean」の 2 つは各ヒーローの個性（master の base_damage と係数の、同じロール・枠の平均に対する比）を残すため。
    public struct GenericTemplate: Hashable, Sendable {
        /// 段ごとの基礎値（スキル1・2 = Lv1〜6、アルティメット = Lv1〜3）。多段（デュエリストの奥義）は 1 撃、
        /// ブリンク + 強化攻撃（遠隔のスキル2）は強化攻撃の追加分、味方全体回復（サポートの奥義）は 1 体あたりの回復量。
        public var base: [Double]
        /// 能力値の係数（物理 = 総物理攻撃、魔法 = 魔法攻撃）。
        public var ratio: Double
        /// 同じロール・枠の汎用ヒーロー 4 体の master の base_damage の平均。
        public var meanBase: Double
        /// 同じロール・枠の汎用ヒーロー 4 体の master の係数の平均（物理 = scaling_attack、魔法 = scaling_power）。
        public var meanScaling: Double

        public init(base: [Double], ratio: Double, meanBase: Double, meanScaling: Double) {
            self.base = base
            self.ratio = ratio
            self.meanBase = meanBase
            self.meanScaling = meanScaling
        }

        /// 段の基礎値（rank は 1...base.count に丸める）。
        public func base(rank: Int) -> Double { base[min(max(1, rank), base.count) - 1] }
    }

    /// ロール × 枠の型（MLBB のロール: ヴァンガード = タンク、デュエリスト = ファイター、レンジャー = マークスマン、
    /// アルカニスト = メイジ、サポート = サポート、アサシン = アサシン）。値は docs/GENERIC_SKILLS.md の表と同じ。
    /// base = MLBB 52 体（キットの 10 体 + Liquipedia の 42 体）の同じロール・枠の主ダメージの Lv1 と最終 Lv の中央値を、
    /// 段で等差に結んだもの（MLBB の段の表はどれも等差）。ratio = 同じスキルたちの係数の中央値。例外:
    /// - 遠隔のスキル2（ブリンク + 強化通常攻撃）は、そのロールのスキル2 の中央値の半分（強化攻撃 1 発ぶん。以前の汎用の「強化攻撃 = スキル値の 50%」と同じ考え）。
    /// - デュエリストの奥義（3 連撃）は、ファイターの奥義の中央値を 3 で割った 1 撃。
    /// - サポートの奥義（味方全体回復）は、MLBB の味方全体回復の奥義（フローリンのブルーム 250 +100% 魔法攻撃）を Lv1 に、1 段 +100。
    /// meanBase / meanScaling は master の H001–H024 から計算した値（SkillArchetypeTests.testGenericTemplateMeansMatchTheMaster が master と照合する）。
    public static func genericTemplate(role: Role, slot: SkillSlot) -> GenericTemplate? {
        switch (role, slot) {
        // タンク（魔法）: 前方扇形 / 突進 / 跳躍
        case (.vanguard, .skill1): return GenericTemplate(base: [275, 316, 357, 398, 439, 480], ratio: 0.9, meanBase: 165.5, meanScaling: 0.65)
        case (.vanguard, .skill2): return GenericTemplate(base: [200, 210, 220, 230, 240, 250], ratio: 0.6, meanBase: 194.5, meanScaling: 0.5)
        case (.vanguard, .ultimate): return GenericTemplate(base: [300, 388, 475], ratio: 0.85, meanBase: 237.5, meanScaling: 0.5)
        // ファイター（物理）: 前方扇形 / 突進 / 3 連撃（1 撃）
        case (.duelist, .skill1): return GenericTemplate(base: [200, 234, 268, 302, 336, 370], ratio: 0.8, meanBase: 182.5, meanScaling: 0.66)
        case (.duelist, .skill2): return GenericTemplate(base: [200, 220, 240, 260, 280, 300], ratio: 0.6, meanBase: 106.5, meanScaling: 0.63)
        case (.duelist, .ultimate): return GenericTemplate(base: [133, 158, 183], ratio: 0.4, meanBase: 254.5, meanScaling: 0.72)
        // マークスマン（物理）: 直線の弾 / ブリンク + 強化攻撃（追加分）/ 貫通の直線
        case (.ranger, .skill1): return GenericTemplate(base: [200, 220, 240, 260, 280, 300], ratio: 0.8, meanBase: 147, meanScaling: 0.63)
        case (.ranger, .skill2): return GenericTemplate(base: [110, 125, 140, 155, 170, 185], ratio: 0.26, meanBase: 123.5, meanScaling: 0.75)
        case (.ranger, .ultimate): return GenericTemplate(base: [280, 340, 400], ratio: 1.0, meanBase: 271.5, meanScaling: 0.69)
        // メイジ（魔法）: 直線の弾 / ブリンク + 強化攻撃（追加分）/ 地点範囲
        case (.arcanist, .skill1): return GenericTemplate(base: [288, 325, 363, 400, 438, 475], ratio: 1.0, meanBase: 111.5, meanScaling: 0.5)
        case (.arcanist, .skill2): return GenericTemplate(base: [150, 158, 165, 173, 180, 188], ratio: 0.45, meanBase: 140.5, meanScaling: 0.65)
        case (.arcanist, .ultimate): return GenericTemplate(base: [470, 510, 550], ratio: 1.08, meanBase: 236, meanScaling: 0.65)
        // サポート（魔法）: 直線の弾 / ブリンク + 強化攻撃（追加分）/ 味方全体回復（1 体の回復量）
        case (.support, .skill1): return GenericTemplate(base: [225, 260, 295, 330, 365, 400], ratio: 1.0, meanBase: 128.5, meanScaling: 0.65)
        case (.support, .skill2): return GenericTemplate(base: [150, 165, 180, 195, 210, 225], ratio: 0.35, meanBase: 157.5, meanScaling: 0.5)
        case (.support, .ultimate): return GenericTemplate(base: [250, 350, 450], ratio: 1.0, meanBase: 200.5, meanScaling: 0.5)
        // アサシン（物理）: 前方扇形 / 突進 / 対象の背後へ（+ 失った HP の 12%）
        case (.assassin, .skill1): return GenericTemplate(base: [150, 176, 202, 228, 254, 280], ratio: 0.5, meanBase: 145.5, meanScaling: 0.69)
        case (.assassin, .skill2): return GenericTemplate(base: [155, 172, 189, 206, 223, 240], ratio: 0.5, meanBase: 174.5, meanScaling: 0.66)
        case (.assassin, .ultimate): return GenericTemplate(base: [235, 298, 360], ratio: 1.2, meanBase: 217.5, meanScaling: 0.75)
        case (_, .passive): return nil
        }
    }

    /// 汎用の CD の段の倍率（master の cooldown_sec に掛ける）。MLBB 52 体の段の表の「最終 Lv の CD ÷ Lv1 の CD」の中央値:
    /// スキル1・2 は 0.79（96 件）→ Lv6 で 80%（1 段 −4%）、アルティメットは 0.815（42 件）→ Lv3 で 82%（1 段 −9%）。docs/GENERIC_SKILLS.md。
    public static func genericCooldownFactor(slot: SkillSlot, rank: Int) -> Double {
        let r = Double(min(max(1, rank), max(1, slot.maxRank)) - 1)
        switch slot {
        case .passive: return 1
        case .ultimate: return 1 - genericUltCooldownStep * r
        case .skill1, .skill2: return 1 - genericBasicCooldownStep * r
        }
    }

    public static let genericBasicCooldownStep: Double = 0.04
    public static let genericUltCooldownStep: Double = 0.09

    /// 汎用スキルの 1 回分の値（ダメージ・回復。軽減前）。型が無ければ master の base_damage + 係数 × 能力値。
    public static func genericValue(_ skill: SkillDef, role: Role, rank: Int, stats: Stats) -> Double {
        let magic = skill.damageType == .magic
        let scaling = magic ? skill.scalingPower : skill.scalingAttack
        let stat = magic ? stats.abilityPower : stats.attack
        guard let t = genericTemplate(role: role, slot: skill.slot) else { return skill.baseDamage + scaling * stat }
        let baseIdentity = t.meanBase > 0 ? skill.baseDamage / t.meanBase : 1
        let ratioIdentity = t.meanScaling > 0 ? scaling / t.meanScaling : 1
        return t.base(rank: rank) * baseIdentity + t.ratio * ratioIdentity * stat
    }
}
