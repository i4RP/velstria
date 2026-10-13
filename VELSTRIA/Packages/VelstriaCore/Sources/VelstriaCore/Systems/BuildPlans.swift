import Foundation

// 担当: core-economy
// ヒーロー別のバトルプラン（MLBB の日本語クライアントの「バトルプラン」画面を写したもの。docs/BUILD_PLANS.md）。
// 1 ヒーロー 3 プラン（画面の上から順）。「有効」のプランが既定で、ボットと、プランを選んでいない人間が使う。
// 人間はヒーロー詳細で別のプランを「使う」にでき、選んだ添字は PlayerSlot.buildPlan → HeroData.buildPlan で試合へ渡る。

/// バトルプラン 1 つ（装備 6 個の購入順・エンブレムと、表示用の名前・タグ・バトルスキル）。
public struct BuildPlan: Codable, Hashable, Sendable {
    /// プラン名（日本語クライアントの表記）。
    public var name: String
    /// プラン名の英語表記。
    public var nameEN: String
    /// タグ（日本語クライアントのチップの文字。無いプランは空）。
    public var tags: [String]
    /// 装備 ID の購入順（靴を含む 6 個）。
    public var items: [String]
    /// 画面のバトルスキル（MLBB の日本語名）。表示用でシミュレーションには使わない。画面に写っていなければ nil。
    public var spellHint: String?
    /// 画面のエンブレム（セット + タレント 3 つ。Lv60）。ボットは「有効」のプランのものを使う。
    /// 人間は保存したヒーローのエンブレムがあればそれ、無ければ選んだプランのもの（docs/EMBLEMS.md）。
    public var emblem: EmblemLoadout

    public init(name: String, nameEN: String, tags: [String] = [], items: [String], spellHint: String? = nil,
                emblem: EmblemLoadout) {
        self.name = name
        self.nameEN = nameEN
        self.tags = tags
        self.items = items
        self.spellHint = spellHint
        self.emblem = emblem
    }
}

extension ItemSystem {
    /// ヒーロー別のバトルプラン（日本語クライアントの 2026-10-13 のスクショ。画面の上から順に 3 つ）。
    /// 装備の並びは購入順。靴は画面どおりの位置（先頭とは限らない）。祝福のバッジは靴に付くので並びには入らない。
    /// エンブレムは画面のエンブレムの列（セットのアイコン + タレント 3 つ）を、エンブレム画面のタブと Fandom のタレントの画像で照合したもの
    /// （docs/EMBLEMS.md「バトルプランのエンブレム」）。
    public static let heroPlans: [String: [BuildPlan]] = [
        // ルミナ（ミヤ）。1 つ目と 3 つ目は装備・エンブレム・バトルスキルまで同じ（画面どおり）。
        "H025": [
            BuildPlan(name: "攻撃速度＆クリティカル率", nameEN: "Attack Speed & Crit", tags: ["クリティカル", "攻撃速度"],
                      items: ["EQ403", "EQ108", "EQ110", "EQ111", "EQ101", "EQ103"], spellHint: "激励",
                      emblem: EmblemLoadout(.marksman, .fatal, .masterAssassin, .quantumCharge)),
            BuildPlan(name: "攻撃速度効果", nameEN: "Attack Speed Effects", tags: ["クリティカル", "攻撃速度"],
                      items: ["EQ403", "EQ111", "EQ108", "EQ110", "EQ117", "EQ101"], spellHint: "激励",
                      emblem: EmblemLoadout(.marksman, .fatal, .bargainHunter, .weaknessFinder)),
            BuildPlan(name: "ヒット＆アウェイ", nameEN: "Hit & Run", tags: ["クリティカル", "攻撃速度"],
                      items: ["EQ403", "EQ108", "EQ110", "EQ111", "EQ101", "EQ103"], spellHint: "激励",
                      emblem: EmblemLoadout(.marksman, .fatal, .masterAssassin, .quantumCharge)),
        ],
        // エウリア（エウドラ）。3 つとも「魔法バースト」。2 つ目と 3 つ目はエンブレムのタレントだけが違う。
        "H026": [
            BuildPlan(name: "魔法バースト", nameEN: "Magic Burst", tags: ["バースト", "ポーク"],
                      items: ["EQ404", "EQ203", "EQ204", "EQ207", "EQ211", "EQ210"], spellHint: "フリッカー",
                      emblem: EmblemLoadout(.assassin, .rupture, .wildernessBlessing, .lethalIgnition)),
            BuildPlan(name: "魔法バースト", nameEN: "Magic Burst",
                      items: ["EQ404", "EQ203", "EQ115", "EQ204", "EQ210", "EQ211"], spellHint: "フリッカー",
                      emblem: EmblemLoadout(.mage, .rupture, .bargainHunter, .lethalIgnition)),
            BuildPlan(name: "魔法バースト", nameEN: "Magic Burst",
                      items: ["EQ404", "EQ203", "EQ115", "EQ204", "EQ210", "EQ211"], spellHint: "フリッカー",
                      emblem: EmblemLoadout(.mage, .rupture, .weaponMaster, .lethalIgnition)),
        ],
        // ジャルド（趙子龍）。1 つ目は靴が 2 つ目。
        "H027": [
            BuildPlan(name: "持続的ダメージ", nameEN: "Sustained Damage",
                      items: ["EQ119", "EQ402", "EQ108", "EQ111", "EQ110", "EQ103"], spellHint: "激励",
                      emblem: EmblemLoadout(.assassin, .agility, .wildernessBlessing, .lethalIgnition)),
            BuildPlan(name: "爆発力", nameEN: "Burst",
                      items: ["EQ402", "EQ108", "EQ119", "EQ102", "EQ101", "EQ110"], spellHint: "浄化",
                      emblem: EmblemLoadout(.assassin, .fatal, .bargainHunter, .quantumCharge)),
            BuildPlan(name: "終盤の中核", nameEN: "Late-Game Core", tags: ["クリティカル", "攻撃速度"],
                      items: ["EQ402", "EQ108", "EQ111", "EQ110", "EQ106", "EQ102"], spellHint: "激励",
                      emblem: EmblemLoadout(.assassin, .fatal, .bargainHunter, .killingSpree)),
        ],
        // ザイル（セイバー）。靴にジャングルの祝福。1 つ目は靴が 2 つ目。2 つ目と 3 つ目はバトルスキルだけが違う。
        "H028": [
            BuildPlan(name: "DPS", nameEN: "DPS",
                      items: ["EQ105", "EQ405", "EQ116", "EQ109", "EQ112", "EQ106"], spellHint: "天罰",
                      emblem: EmblemLoadout(.assassin, .thrill, .seasonedHunter, .temporalReign)),
            BuildPlan(name: "爆発力", nameEN: "Burst",
                      items: ["EQ407", "EQ115", "EQ107", "EQ105", "EQ106", "EQ104"], spellHint: "天罰",
                      emblem: EmblemLoadout(.assassin, .rupture, .masterAssassin, .lethalIgnition)),
            BuildPlan(name: "持続的ダメージ", nameEN: "Sustained Damage",
                      items: ["EQ407", "EQ115", "EQ107", "EQ105", "EQ106", "EQ104"], spellHint: "処刑",
                      emblem: EmblemLoadout(.assassin, .rupture, .masterAssassin, .lethalIgnition)),
        ],
        // ボルグ（ティグリアル）。3 つとも「生存」。靴にロームの祝福。
        "H029": [
            BuildPlan(name: "生存", nameEN: "Survival",
                      items: ["EQ402", "EQ305", "EQ308", "EQ114", "EQ301", "EQ304"], spellHint: "フリッカー",
                      emblem: EmblemLoadout(.tank, .firmness, .pullYourselfTogether, .concussiveBlast)),
            BuildPlan(name: "生存", nameEN: "Survival", tags: ["ローム", "生存"],
                      items: ["EQ406", "EQ114", "EQ305", "EQ308", "EQ306", "EQ304"], spellHint: "フリッカー",
                      emblem: EmblemLoadout(.tank, .inspire, .pullYourselfTogether, .focusingMark)),
            BuildPlan(name: "生存", nameEN: "Survival",
                      items: ["EQ406", "EQ305", "EQ306", "EQ308", "EQ304", "EQ301"], spellHint: "フリッカー",
                      emblem: EmblemLoadout(.tank, .agility, .pullYourselfTogether, .focusingMark)),
        ],
        // ライナ（ライラ）
        "H030": [
            BuildPlan(name: "攻撃速度＆クリティカル率", nameEN: "Attack Speed & Crit",
                      items: ["EQ407", "EQ108", "EQ110", "EQ111", "EQ101", "EQ103"], spellHint: "フリッカー",
                      emblem: EmblemLoadout(.assassin, .fatal, .weaponMaster, .quantumCharge)),
            BuildPlan(name: "持続的ダメージ", nameEN: "Sustained Damage", tags: ["持続力", "ファーム"],
                      items: ["EQ403", "EQ111", "EQ110", "EQ109", "EQ106", "EQ101"], spellHint: "浄化",
                      emblem: EmblemLoadout(.marksman, .fatal, .bargainHunter, .quantumCharge)),
            BuildPlan(name: "ヒット＆アウェイ", nameEN: "Hit & Run",
                      items: ["EQ403", "EQ111", "EQ110", "EQ101", "EQ106", "EQ112"], spellHint: "フリッカー",
                      emblem: EmblemLoadout(.marksman, .agility, .weaponMaster, .quantumCharge)),
        ],
        // オーリア（オーロラ）。3 つ目のセットは通常共通エンブレム（灰色の盾と剣）。
        "H031": [
            BuildPlan(name: "持続的ダメージ", nameEN: "Sustained Damage",
                      items: ["EQ404", "EQ207", "EQ204", "EQ211", "EQ201", "EQ210"], spellHint: "フリッカー",
                      emblem: EmblemLoadout(.mage, .rupture, .wildernessBlessing, .impureRage)),
            BuildPlan(name: "爆発力", nameEN: "Burst", tags: ["ポーク", "攻防一体"],
                      items: ["EQ404", "EQ207", "EQ205", "EQ201", "EQ211", "EQ210"], spellHint: "フリッカー",
                      emblem: EmblemLoadout(.mage, .rupture, .bargainHunter, .lethalIgnition)),
            BuildPlan(name: "攻防一体", nameEN: "Offense & Defense", tags: ["攻防一体", "持続力"],
                      items: ["EQ404", "EQ205", "EQ208", "EQ207", "EQ203", "EQ201"], spellHint: "炎の弾",
                      emblem: EmblemLoadout(.common, .rupture, .weaponMaster, .lethalIgnition)),
        ],
        // ディアス（ディロス）。3 つ目は靴が 2 つ目。
        "H032": [
            BuildPlan(name: "爆発力", nameEN: "Burst",
                      items: ["EQ406", "EQ105", "EQ116", "EQ302", "EQ301", "EQ308"], spellHint: "復讐",
                      emblem: EmblemLoadout(.fighter, .thrill, .festivalOfBlood, .impureRage)),
            BuildPlan(name: "継続ダメージ", nameEN: "Damage Over Time", tags: ["ジャングル", "攻防一体"],
                      items: ["EQ406", "EQ103", "EQ116", "EQ312", "EQ307", "EQ104"], spellHint: "石化",
                      emblem: EmblemLoadout(.fighter, .swift, .festivalOfBlood, .killingSpree)),
            BuildPlan(name: "ジャングル", nameEN: "Jungle", tags: ["バースト"],
                      items: ["EQ107", "EQ407", "EQ105", "EQ106", "EQ103", "EQ112"], spellHint: "石化",
                      emblem: EmblemLoadout(.assassin, .rupture, .festivalOfBlood, .lethalIgnition)),
        ],
        // ヴァルド（アルカード）。靴にジャングルの祝福。
        "H033": [
            BuildPlan(name: "持続的ダメージ", nameEN: "Sustained Damage", tags: ["ジャングル", "HP吸収"],
                      items: ["EQ406", "EQ116", "EQ109", "EQ106", "EQ312", "EQ104"], spellHint: "復讐",
                      emblem: EmblemLoadout(.assassin, .thrill, .seasonedHunter, .temporalReign)),
            BuildPlan(name: "DPS", nameEN: "DPS", tags: ["ジャングル", "HP吸収"],
                      items: ["EQ406", "EQ116", "EQ104", "EQ109", "EQ106", "EQ312"], spellHint: "天罰",
                      emblem: EmblemLoadout(.assassin, .thrill, .seasonedHunter, .temporalReign)),
            BuildPlan(name: "爆発力", nameEN: "Burst",
                      items: ["EQ406", "EQ105", "EQ106", "EQ109", "EQ112", "EQ104"], spellHint: "天罰",
                      emblem: EmblemLoadout(.assassin, .rupture, .festivalOfBlood, .killingSpree)),
        ],
        // ゴルム（フランコ）。試合中のショップの「ビルド」画面なので、タグ・エンブレム・バトルスキルは写っていない。
        // エンブレムは仮（MLBB のフランコの定番のタンク構成。画面が届いたら差し替える）。
        "H034": [
            BuildPlan(name: "チームバフ", nameEN: "Team Buff",
                      items: ["EQ402", "EQ113", "EQ114", "EQ308", "EQ306", "EQ304"],
                      emblem: EmblemLoadout(.tank, .vitality, .pullYourselfTogether, .focusingMark)),
            BuildPlan(name: "生存", nameEN: "Survival",
                      items: ["EQ402", "EQ113", "EQ114", "EQ305", "EQ306", "EQ308"],
                      emblem: EmblemLoadout(.tank, .vitality, .tenacity, .concussiveBlast)),
            BuildPlan(name: "持続的ダメージ", nameEN: "Sustained Damage",
                      items: ["EQ402", "EQ305", "EQ301", "EQ304", "EQ308", "EQ309"],
                      emblem: EmblemLoadout(.tank, .firmness, .tenacity, .concussiveBlast)),
        ],
    ]

    /// エンブレムが画面に写っていないプランのヒーロー（エンブレムは仮。docs/EMBLEMS.md）。
    public static let provisionalPlanEmblems: Set<String> = ["H034"]

    /// 「有効」のプランの添字（画面で「有効」になっていたもの。ボットと、プランを選んでいない人間が使う）。
    public static let defaultPlanIndex: [String: Int] = [
        "H025": 2, "H026": 0, "H027": 1, "H028": 0, "H029": 0,
        "H030": 0, "H031": 0, "H032": 0, "H033": 1, "H034": 0,
    ]

    /// ヒーローのバトルプラン（無いヒーローは空）。
    public static func plans(forHero heroID: String) -> [BuildPlan] {
        heroPlans[heroID] ?? []
    }

    /// 使うプランの添字。chosen が範囲内ならそれ、nil・範囲外なら「有効」のプラン。プランの無いヒーローは nil。
    public static func planIndex(heroID: String, chosen: Int?) -> Int? {
        let plans = plans(forHero: heroID)
        guard !plans.isEmpty else { return nil }
        if let chosen, plans.indices.contains(chosen) { return chosen }
        let k = defaultPlanIndex[heroID] ?? 0
        return plans.indices.contains(k) ? k : 0
    }

    /// 使うプラン（planIndex で選んだもの）。プランの無いヒーローは nil。
    public static func plan(heroID: String, chosen: Int?) -> BuildPlan? {
        guard let k = planIndex(heroID: heroID, chosen: chosen) else { return nil }
        return plans(forHero: heroID)[k]
    }
}
