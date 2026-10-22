import Foundation

// 担当: core-data
// エンブレム（MLBB の「エンブレム」画面を写したもの。docs/EMBLEMS.md）。旧「ルーン」の置き換え。
// 7 つのセット（画面上のタブの並び）と、3 段のタレント（1 段目 8 個・2 段目 8 個・コア 10 個。ピッカーの並び）。
// 出典: MLBB 日本語クライアントのスクショ（2026-10-14。最大レベルのアカウントと、低いレベルのフレンドのアカウント）と
// MLBB Fandom の Emblems（2026-04 更新、1.9.64 を含む）。セットは「組み換え自由」で、どのセットにもどのタレントでも付けられる
// （各段のタレントはその段のものに限る）。数値は Lv60（最大）の値。
// 日本語名は画面で確かめたものだけ jaConfirmed = true。ほかは仮の訳で、残りのスクショが届いたら差し替える。
// 画面ではタレントを「天賦」（通常天賦 = 1・2 段目、コア天賦）と呼ぶ。能力値の名前は日本語クライアントの用語説明に合わせる。

/// エンブレムのセット（タブの並び = allCases の並び）。生の値は保存データ・リプレイに入るので変えない。
public enum EmblemSetID: String, Codable, Hashable, Sendable, CaseIterable {
    case common = "EM_COMMON"
    case tank = "EM_TANK"
    case assassin = "EM_ASSASSIN"
    case mage = "EM_MAGE"
    case fighter = "EM_FIGHTER"
    case support = "EM_SUPPORT"
    case marksman = "EM_MARKSMAN"
}

/// タレントの段。
public enum EmblemTier: Int, Codable, Hashable, Sendable, CaseIterable {
    /// 1 段目（リングの右上）。
    case tier1 = 1
    /// 2 段目（リングの左）。
    case tier2 = 2
    /// コア（リングの下）。
    case core = 3
}

/// タレント（段ごとにピッカーの並び = allCases の並び）。生の値は保存データ・リプレイに入るので変えない。
public enum EmblemTalentID: String, Codable, Hashable, Sendable, CaseIterable {
    // 1 段目
    case thrill = "TL_THRILL"
    case swift = "TL_SWIFT"
    case vitality = "TL_VITALITY"
    case rupture = "TL_RUPTURE"
    case inspire = "TL_INSPIRE"
    case firmness = "TL_FIRMNESS"
    case agility = "TL_AGILITY"
    case fatal = "TL_FATAL"
    // 2 段目
    case wildernessBlessing = "TL_WILDERNESS_BLESSING"
    case seasonedHunter = "TL_SEASONED_HUNTER"
    case tenacity = "TL_TENACITY"
    case masterAssassin = "TL_MASTER_ASSASSIN"
    case bargainHunter = "TL_BARGAIN_HUNTER"
    case festivalOfBlood = "TL_FESTIVAL_OF_BLOOD"
    case pullYourselfTogether = "TL_PULL_YOURSELF_TOGETHER"
    case weaponMaster = "TL_WEAPON_MASTER"
    // コア
    case impureRage = "TL_IMPURE_RAGE"
    case quantumCharge = "TL_QUANTUM_CHARGE"
    case warCry = "TL_WAR_CRY"
    case temporalReign = "TL_TEMPORAL_REIGN"
    case concussiveBlast = "TL_CONCUSSIVE_BLAST"
    case killingSpree = "TL_KILLING_SPREE"
    case lethalIgnition = "TL_LETHAL_IGNITION"
    case braveSmite = "TL_BRAVE_SMITE"
    case focusingMark = "TL_FOCUSING_MARK"
    case weaknessFinder = "TL_WEAKNESS_FINDER"

    public var tier: EmblemTier {
        switch self {
        case .thrill, .swift, .vitality, .rupture, .inspire, .firmness, .agility, .fatal: return .tier1
        case .wildernessBlessing, .seasonedHunter, .tenacity, .masterAssassin, .bargainHunter, .festivalOfBlood,
             .pullYourselfTogether, .weaponMaster: return .tier2
        default: return .core
        }
    }
}

/// セットの能力値の種類。値は画面の表示どおり（割合の種類は % の数。3 = +3%）。
public enum EmblemAttributeKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// 混合回復（HP 回復と MP 回復。MP は Mana のヒーローだけ）。
    case hybridRegen
    case hp
    /// 適応攻撃（追加の物理攻撃と魔法攻撃の多い方。どちらも同じならヒーローの主なダメージの種類）。
    case adaptiveAttack
    /// 混合防御（物理防御と魔法防御）。
    case hybridDefense
    case hpRegen
    /// 適応貫通（固定値。適応攻撃と同じ向き）。
    case adaptivePenetration
    /// 適応貫通（割合。マークスマンのセット）。
    case adaptivePenetrationPct
    case movementSpeedPct
    case magicPower
    case cooldownReductionPct
    /// 魔法貫通（固定値）。
    case magicPenetration
    /// 混合吸収（通常攻撃吸収とスキル吸収。用語説明の表記）。
    case hybridLifestealPct
    /// 回復効果（与える回復・シールド量）。
    case healingEffectPct
    case attackSpeedPct

    public var isPercent: Bool {
        switch self {
        case .adaptivePenetrationPct, .movementSpeedPct, .cooldownReductionPct, .hybridLifestealPct, .healingEffectPct,
             .attackSpeedPct: return true
        default: return false
        }
    }

    /// 日本語クライアントの表記。
    public var nameJa: String {
        switch self {
        case .hybridRegen: return "混合回復"
        case .hp: return "HP"
        case .adaptiveAttack: return "適応攻撃"
        case .hybridDefense: return "混合防御"
        case .hpRegen: return "HP回復"
        case .adaptivePenetration, .adaptivePenetrationPct: return "適応貫通"
        case .movementSpeedPct: return "移動速度"
        case .magicPower: return "魔法攻撃"
        case .cooldownReductionPct: return "CD短縮"
        case .magicPenetration: return "魔法貫通"
        case .hybridLifestealPct: return "混合吸収"
        case .healingEffectPct: return "回復効果"
        case .attackSpeedPct: return "攻撃速度"
        }
    }

    public var nameEn: String {
        switch self {
        case .hybridRegen: return "Hybrid Regen"
        case .hp: return "HP"
        case .adaptiveAttack: return "Adaptive Attack"
        case .hybridDefense: return "Hybrid Defense"
        case .hpRegen: return "HP Regen"
        case .adaptivePenetration, .adaptivePenetrationPct: return "Adaptive Penetration"
        case .movementSpeedPct: return "Movement Speed"
        case .magicPower: return "Magic Power"
        case .cooldownReductionPct: return "Cooldown Reduction"
        case .magicPenetration: return "Magic Penetration"
        case .hybridLifestealPct: return "Hybrid Lifesteal"
        case .healingEffectPct: return "Healing Effect"
        case .attackSpeedPct: return "Attack Speed"
        }
    }

    /// 日本語クライアントの用語説明（ステータス説明・共通用語）の文。用語説明に無い能力値は nil。
    /// 適応貫通は「適応攻撃と同上の判定」の「同上」を補った。
    public var glossaryJa: String? {
        switch self {
        case .hybridRegen: return "HP+MP回復。"
        case .hybridDefense: return "物理+魔法防御。"
        case .hybridLifestealPct: return "通常攻撃吸収+ スキル吸収。"
        case .adaptiveAttack:
            return "追加物理攻撃が追加魔法攻撃より高い場合、物理攻撃がこのステータス値の分だけ上昇する。追加魔法攻撃の方が高い場合は、魔法攻撃が同じ値だけ上昇する。2つのステータスが同じ場合は、ヒーローのダメージタイプによって決まる。"
        case .adaptivePenetration, .adaptivePenetrationPct: return "適応攻撃と同じ判定で、物理貫通 / 魔法貫通が上昇する。"
        case .hpRegen: return "1秒あたりの基礎HP回復量"
        case .cooldownReductionPct: return "スキルのCD時間を短縮するステータス。通常、短縮率の上限は40%。"
        case .magicPenetration: return "敵の魔法防御を低下させるステータス。"
        case .healingEffectPct: return "自身が与える回復効果とシールドの量に影響するステータス。デフォルトは100%。"
        case .hp, .movementSpeedPct, .magicPower, .attackSpeedPct: return nil
        }
    }

    /// glossaryJa の英訳。
    public var glossaryEn: String? {
        switch self {
        case .hybridRegen: return "HP + Mana Regen."
        case .hybridDefense: return "Physical + Magic Defense."
        case .hybridLifestealPct: return "Lifesteal + Spell Vamp."
        case .adaptiveAttack:
            return "If extra Physical Attack is higher than extra Magic Power, Physical Attack increases by this value; if extra Magic Power is higher, Magic Power increases instead. If they are equal, the hero's damage type decides."
        case .adaptivePenetration, .adaptivePenetrationPct:
            return "Decided like Adaptive Attack: increases Physical or Magic Penetration."
        case .hpRegen: return "Base HP regenerated per second."
        case .cooldownReductionPct: return "Shortens skill cooldowns. Normally capped at 40%."
        case .magicPenetration: return "Lowers the enemy's Magic Defense."
        case .healingEffectPct: return "Affects the healing and shields you give. 100% by default."
        case .hp, .movementSpeedPct, .magicPower, .attackSpeedPct: return nil
        }
    }

    /// 日本語名を画面で確かめたか（エンブレム画面のステータス欄・🔍・用語説明）。
    public var jaConfirmed: Bool {
        switch self {
        // 魔法攻撃はまだ画面に出ていない（魔法貫通・混合吸収は用語説明の表記、攻撃速度はハンターの🔍で確かめた）
        case .magicPower: return false
        default: return true
        }
    }
}

/// セットの能力値 1 つ。
public struct EmblemAttribute: Codable, Hashable, Sendable {
    public var kind: EmblemAttributeKind
    /// Lv60（最大）の値。
    public var maxValue: Double
    /// レベル別の値（添字 0 = Lv1）。nil・範囲外は maxValue を使う。EmblemCatalog.sets は仮の表
    /// （EmblemProgression.levelValues。画面で確かめた点を通り、Lv60 で最大）を持つ。
    public var levelValues: [Double]?
    /// コア属性（キーレベルで大きく伸びる能力値。どのセットもステータス欄の 1 つ目）。画面で確かめたのは通常共通 = 混合回復・
    /// タンク = HP・アサシン = 適応貫通・サポート = 回復効果。メイジ・ファイター・ハンターは 1 つ目と仮定（EmblemSetDef.coreConfirmed）。
    public var isCore: Bool

    public init(_ kind: EmblemAttributeKind, _ maxValue: Double, levelValues: [Double]? = nil, isCore: Bool = false) {
        self.kind = kind
        self.maxValue = maxValue
        self.levelValues = levelValues
        self.isCore = isCore
    }

    /// level での値（表示どおりの単位。割合は % の数）。
    public func value(level: Int) -> Double {
        guard let t = levelValues, level >= 1, level <= t.count else { return maxValue }
        return t[level - 1]
    }
}

/// エンブレムのセット 1 つ。
public struct EmblemSetDef: Hashable, Sendable, Identifiable {
    public var id: EmblemSetID
    public var nameJa: String
    public var nameEn: String
    /// 日本語名を画面で確かめたか。
    public var jaConfirmed: Bool
    /// コア属性（EmblemAttribute.isCore）を画面のキーレベルの表示で確かめたか。
    public var coreConfirmed: Bool = false
    /// ステータス欄の 3 つ（画面の上から順）。
    public var attributes: [EmblemAttribute]
    /// セットの既定のタレント（MLBB の既定。プロフィールに選択が無い時・ロール別の既定のボット）。
    public var defaultTier1: EmblemTalentID
    public var defaultTier2: EmblemTalentID
    public var defaultCore: EmblemTalentID
}

/// タレント 1 つ。
public struct EmblemTalentDef: Hashable, Sendable, Identifiable {
    public var id: EmblemTalentID
    public var nameJa: String
    public var nameEn: String
    /// 日本語名を画面で確かめたか。
    public var jaConfirmed: Bool
    /// ピッカーの橙の小見出し（1 段目には無い）。
    public var subtitleJa: String?
    public var subtitleEn: String?
    /// 説明（日本語は textConfirmed のものだけ画面の文。ほかは Fandom の英文からの仮の訳）。
    public var descriptionJa: String
    public var descriptionEn: String
    /// 日本語の説明（本文）を画面で確かめたか（ピッカーか、🔍 の「エンブレムステータス」）。
    public var textConfirmed: Bool
    /// 日本語の橙の小見出しを画面で確かめたか（ピッカーにしか出ない）。
    public var subtitleConfirmed: Bool = false
    /// このタレントを付けられるようになるセットのレベル（nil = 不明。画面は期間限定の「全天賦解放」中で確かめられない）。
    /// nil の間は段の解放レベル（EmblemProgression.talentUnlockLevels。仮: 1 段目 Lv10・2 段目 Lv15・コア Lv20）。
    public var unlockLevel: Int?
    /// 効果の係数（表示・テスト用。シミュレーションは Balance.Emblems の同じ値を使う）。
    public var params: [String: Double]

    public var tier: EmblemTier { id.tier }
}

/// 使うエンブレム 1 式（セット + 各段のタレント 1 つずつ + セットのレベル）。どの組み合わせでもよい（段は合っていること）。
public struct EmblemLoadout: Codable, Hashable, Sendable {
    public var set: EmblemSetID
    public var tier1: EmblemTalentID
    public var tier2: EmblemTalentID
    public var core: EmblemTalentID
    /// セットのレベル（1...60）。能力値はこのレベルの値（EmblemAttribute.value）、天賦は解放レベル以上の段だけ働く
    /// （isActive）。人間はプレイヤーのセットのレベル、ボットは 60。古いデータでキーが無ければ 60。
    public var level: Int

    public init(set: EmblemSetID, tier1: EmblemTalentID, tier2: EmblemTalentID, core: EmblemTalentID,
                level: Int = EmblemCatalog.maxLevel) {
        self.set = set
        self.tier1 = tier1
        self.tier2 = tier2
        self.core = core
        self.level = level
    }

    /// 並べて書く用（バトルプランの表）。
    public init(_ set: EmblemSetID, _ tier1: EmblemTalentID, _ tier2: EmblemTalentID, _ core: EmblemTalentID,
                level: Int = EmblemCatalog.maxLevel) {
        self.init(set: set, tier1: tier1, tier2: tier2, core: core, level: level)
    }

    enum CodingKeys: String, CodingKey { case set, tier1, tier2, core, level }

    /// 古い・壊れたデータでも読めるようにする: 知らないセットは通常共通、知らない・段の違うタレントはそのセットの既定、
    /// レベルが無ければ 60（1...60 に丸める）。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let setRaw = (try? c.decodeIfPresent(String.self, forKey: .set)) ?? nil
        let set = setRaw.flatMap(EmblemSetID.init(rawValue:)) ?? .common
        let def = EmblemCatalog.set(set)
        func talent(_ key: CodingKeys, _ tier: EmblemTier, _ fallback: EmblemTalentID) -> EmblemTalentID {
            let raw = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil
            guard let id = raw.flatMap(EmblemTalentID.init(rawValue:)), id.tier == tier else { return fallback }
            return id
        }
        self.set = set
        tier1 = talent(.tier1, .tier1, def.defaultTier1)
        tier2 = talent(.tier2, .tier2, def.defaultTier2)
        core = talent(.core, .core, def.defaultCore)
        let lv = (try? c.decodeIfPresent(Int.self, forKey: .level)) ?? nil
        level = EmblemCatalog.clampLevel(lv ?? EmblemCatalog.maxLevel)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(set.rawValue, forKey: .set)
        try c.encode(tier1.rawValue, forKey: .tier1)
        try c.encode(tier2.rawValue, forKey: .tier2)
        try c.encode(core.rawValue, forKey: .core)
        try c.encode(level, forKey: .level)
    }

    /// 段の合ったタレントか（どのセットとも組み合わせられる）。
    public var isValid: Bool {
        tier1.tier == .tier1 && tier2.tier == .tier2 && core.tier == .core && (1...EmblemCatalog.maxLevel).contains(level)
    }

    /// 各段のタレントを順に（1 段目・2 段目・コア）。
    public var talents: [EmblemTalentID] { [tier1, tier2, core] }

    /// 段 tier のタレント。
    public func talent(_ tier: EmblemTier) -> EmblemTalentID {
        switch tier {
        case .tier1: return tier1
        case .tier2: return tier2
        case .core: return core
        }
    }

    /// 段 tier のタレントを付け替えたもの（段の違うタレントは無視）。
    public func replacing(_ id: EmblemTalentID) -> EmblemLoadout {
        var out = self
        switch id.tier {
        case .tier1: out.tier1 = id
        case .tier2: out.tier2 = id
        case .core: out.core = id
        }
        return out
    }

    /// talent を付けているか。
    public func has(_ id: EmblemTalentID) -> Bool { tier1 == id || tier2 == id || core == id }

    /// 段 tier の天賦がこのレベルで働くか（解放レベル未満の段は付けていても働かない。EmblemProgression.unlockLevel）。
    public func isActive(_ tier: EmblemTier) -> Bool { level >= EmblemProgression.unlockLevel(talent: talent(tier)) }

    /// 働いている 1 段目・2 段目・コアの天賦（解放レベル未満は nil）。試合の効果はこちらを見る。
    public var activeTier1: EmblemTalentID? { isActive(.tier1) ? tier1 : nil }
    public var activeTier2: EmblemTalentID? { isActive(.tier2) ? tier2 : nil }
    public var activeCore: EmblemTalentID? { isActive(.core) ? core : nil }
}

public enum EmblemCatalog {
    /// セットの最大レベル（画面の「MAX」）。
    public static let maxLevel = 60

    public static func clampLevel(_ level: Int) -> Int { min(maxLevel, max(1, level)) }

    /// 7 つのセット（タブの並び）。maxValue は Lv60 の値、levelValues は仮のレベル別の表（EmblemProgression.levelValues）。
    public static let sets: [EmblemSetDef] = baseSets.map(EmblemProgression.attachingLevelTables)

    /// 7 つのセットの Lv60 の値（画面・Fandom）。
    private static let baseSets: [EmblemSetDef] = [
        // スクショ: 通常共通エンブレム Lv60（混合回復 +12.00 / HP +275.00 / 適応攻撃 +22.00）。タレントは衝撃 / 山野の主 / 不純な怒り。
        // フレンドの 🔍（Lv42）: 次のキーレベル Lv45 で「コア属性大幅アップ 混合回復」。
        EmblemSetDef(id: .common, nameJa: "通常共通エンブレム", nameEn: "Basic Common Emblem", jaConfirmed: true, coreConfirmed: true,
                     attributes: [EmblemAttribute(.hybridRegen, 12, isCore: true), EmblemAttribute(.hp, 275), EmblemAttribute(.adaptiveAttack, 22)],
                     defaultTier1: .thrill, defaultTier2: .wildernessBlessing, defaultCore: .impureRage),
        // スクショ: オーダーエンブレム(タンク) Lv60（HP +500.00 / 混合防御 +10.00 / HP回復 +4.00）。タレントは活力 / 強靭 / 強震撃。
        // フレンドの 🔍（Lv28）: 次のキーレベル Lv30 で「コア属性大幅アップ 最大HP」。
        EmblemSetDef(id: .tank, nameJa: "オーダーエンブレム(タンク)", nameEn: "Custom Tank Emblem", jaConfirmed: true, coreConfirmed: true,
                     attributes: [EmblemAttribute(.hp, 500, isCore: true), EmblemAttribute(.hybridDefense, 10), EmblemAttribute(.hpRegen, 4)],
                     defaultTier1: .vitality, defaultTier2: .tenacity, defaultCore: .concussiveBlast),
        // フレンドのスクショ（Lv26）で名前・並び・タレント（破砕 / 暗殺の達人 / 殺戮の連鎖）を確かめた。数値は Fandom の Lv60。
        EmblemSetDef(id: .assassin, nameJa: "オーダーエンブレム(アサシン)", nameEn: "Custom Assassin Emblem", jaConfirmed: true, coreConfirmed: true,
                     attributes: [EmblemAttribute(.adaptivePenetration, 14, isCore: true), EmblemAttribute(.adaptiveAttack, 10),
                                  EmblemAttribute(.movementSpeedPct, 3)],
                     defaultTier1: .rupture, defaultTier2: .masterAssassin, defaultCore: .killingSpree),
        // 名前は仮（ほかのセットの表記から）。数値・タレントは Fandom。
        EmblemSetDef(id: .mage, nameJa: "オーダーエンブレム(メイジ)", nameEn: "Custom Mage Emblem", jaConfirmed: false,
                     attributes: [EmblemAttribute(.magicPower, 30, isCore: true), EmblemAttribute(.cooldownReductionPct, 5),
                                  EmblemAttribute(.magicPenetration, 8)],
                     defaultTier1: .inspire, defaultTier2: .bargainHunter, defaultCore: .lethalIgnition),
        // 名前は仮。
        EmblemSetDef(id: .fighter, nameJa: "オーダーエンブレム(ファイター)", nameEn: "Custom Fighter Emblem", jaConfirmed: false,
                     attributes: [EmblemAttribute(.hybridLifestealPct, 10, isCore: true), EmblemAttribute(.adaptiveAttack, 16),
                                  EmblemAttribute(.hybridDefense, 8)],
                     defaultTier1: .firmness, defaultTier2: .festivalOfBlood, defaultCore: .braveSmite),
        // フレンドのスクショ（Lv29）で名前・並び・タレント（敏捷 / 立て直し / 集中マーク）を確かめた。数値は Fandom の Lv60。
        EmblemSetDef(id: .support, nameJa: "オーダーエンブレム(サポート)", nameEn: "Custom Support Emblem", jaConfirmed: true, coreConfirmed: true,
                     attributes: [EmblemAttribute(.healingEffectPct, 12, isCore: true), EmblemAttribute(.cooldownReductionPct, 10),
                                  EmblemAttribute(.movementSpeedPct, 6)],
                     defaultTier1: .agility, defaultTier2: .pullYourselfTogether, defaultCore: .focusingMark),
        // 🔍 の「エンブレムステータス」（Lv60）で名前と 攻撃速度 +15.00% / 適応攻撃 +16.00 / 適応貫通 +10.00%（割合）、
        // 天賦（致命 / 武器マスター / 弱点分析）を確かめた。
        EmblemSetDef(id: .marksman, nameJa: "オーダーエンブレム(ハンター)", nameEn: "Custom Marksman Emblem", jaConfirmed: true,
                     attributes: [EmblemAttribute(.attackSpeedPct, 15, isCore: true), EmblemAttribute(.adaptiveAttack, 16),
                                  EmblemAttribute(.adaptivePenetrationPct, 10)],
                     defaultTier1: .fatal, defaultTier2: .weaponMaster, defaultCore: .weaknessFinder),
    ]

    private typealias K = Balance.Emblems

    /// 26 のタレント（段ごとにピッカーの並び。1 段目 → 2 段目 → コア）。
    public static let talents: [EmblemTalentDef] = [
        // MARK: 1 段目（ピッカー: 1 行目 衝撃・迅速・活力 / 2 行目 破砕・啓発・堅固 / 3 行目 敏捷・致命）
        EmblemTalentDef(id: .thrill, nameJa: "衝撃", nameEn: "Thrill", jaConfirmed: true,
                        descriptionJa: "16の適応攻撃を獲得する。", descriptionEn: "Gain 16 Adaptive Attack.",
                        textConfirmed: true, params: ["adaptive_attack": K.thrillAdaptive]),
        EmblemTalentDef(id: .swift, nameJa: "迅速", nameEn: "Swift", jaConfirmed: false,
                        descriptionJa: "追加攻撃速度が10%上昇する。", descriptionEn: "Gain 10% extra Attack Speed.",
                        textConfirmed: false, params: ["attack_speed": K.swiftAttackSpeed]),
        EmblemTalentDef(id: .vitality, nameJa: "活力", nameEn: "Vitality", jaConfirmed: true,
                        descriptionJa: "最大HPが225上昇する。", descriptionEn: "Gain 225 extra Max HP.",
                        textConfirmed: true, params: ["hp": K.vitalityHP]),
        EmblemTalentDef(id: .rupture, nameJa: "破砕", nameEn: "Rupture", jaConfirmed: false,
                        descriptionJa: "適応貫通が5上昇する。追加物理攻撃が追加魔法攻撃より高い時は物理貫通、それ以外は魔法貫通になる。",
                        descriptionEn: "Gain 5 Adaptive Penetration (Physical if extra Physical Attack is higher than extra Magic Power; otherwise Magic).",
                        textConfirmed: false, params: ["adaptive_penetration": K.rupturePenetration]),
        EmblemTalentDef(id: .inspire, nameJa: "啓発", nameEn: "Inspire", jaConfirmed: false,
                        descriptionJa: "CD短縮が5%、MP回復が2上昇する。", descriptionEn: "Gain 5% Cooldown Reduction and 2 Mana Regen.",
                        textConfirmed: false, params: ["cooldown_reduction": K.inspireCooldownReduction, "mana_regen": K.inspireManaRegen]),
        EmblemTalentDef(id: .firmness, nameJa: "堅固", nameEn: "Firmness", jaConfirmed: false,
                        descriptionJa: "物理防御と魔法防御が8上昇する。", descriptionEn: "Gain 8 extra Physical & Magic Defense.",
                        textConfirmed: false, params: ["hybrid_defense": K.firmnessDefense]),
        EmblemTalentDef(id: .agility, nameJa: "敏捷", nameEn: "Agility", jaConfirmed: false,
                        descriptionJa: "移動速度が4%上昇する。", descriptionEn: "Gain 4% extra Movement Speed.",
                        textConfirmed: false, params: ["move_speed": K.agilityMoveSpeed]),
        EmblemTalentDef(id: .fatal, nameJa: "致命", nameEn: "Fatal", jaConfirmed: true,
                        descriptionJa: "クリティカル率が5%、クリティカルダメージが5%上昇する。",
                        descriptionEn: "Gain 5% Crit Chance and 5% extra Crit Damage.",
                        textConfirmed: true, params: ["crit_chance": K.fatalCritChance, "crit_damage": K.fatalCritDamage]),

        // MARK: 2 段目（ピッカー: 1 行目 山野の主・熟練ハンター・強靭 / 2 行目 暗殺の達人・掘り出し上手・血の祭典 /
        //       3 行目 立て直し・武器マスター）
        EmblemTalentDef(id: .wildernessBlessing, nameJa: "山野の主", nameEn: "Wilderness Blessing", jaConfirmed: true,
                        subtitleJa: "ジャングルと川で加速", subtitleEn: "Faster in the jungle and river",
                        descriptionJa: "ジャングルと川エリアでの移動速度が10%上昇する。敵ヒーロー、ロード、またはタートルと戦闘中の場合、この効果は半減する。",
                        descriptionEn: "Movement Speed in the jungle and river is increased by 10%. This bonus is halved when in combat with enemy heroes, Lord or Turtle.",
                        textConfirmed: true, params: ["move_speed": K.wildernessMoveSpeed, "combat_scale": K.wildernessCombatScale]),
        EmblemTalentDef(id: .seasonedHunter, nameJa: "熟練ハンター", nameEn: "Seasoned Hunter", jaConfirmed: false,
                        subtitleJa: "ボスへのダメージ上昇", subtitleEn: "More damage to bosses",
                        descriptionJa: "星喰竜と古環の巨像へのダメージが15%上昇する。ほかのモンスターへは半分になり、狩猟印のダメージには効かない。",
                        descriptionEn: "Damage against the bosses is increased by 15% (halved against other creeps; doesn't affect Retribution).",
                        textConfirmed: false, params: ["boss": K.seasonedBossBonus, "creep": K.seasonedCreepBonus]),
        EmblemTalentDef(id: .tenacity, nameJa: "強靭", nameEn: "Tenacity", jaConfirmed: true,
                        subtitleJa: "低HP時防御力上昇", subtitleEn: "More defense at low HP",
                        descriptionJa: "HPが50%未満の時、ダメージ軽減が5%上昇する。",
                        descriptionEn: "When HP is below 50%, Damage Reduction is increased by 5%.",
                        textConfirmed: true, subtitleConfirmed: true,
                        params: ["hp_ratio": K.tenacityHPRatio, "damage_reduction": K.tenacityDamageReduction]),
        EmblemTalentDef(id: .masterAssassin, nameJa: "暗殺の達人", nameEn: "Master Assassin", jaConfirmed: false,
                        subtitleJa: "1対1で与ダメージ上昇", subtitleEn: "More damage one-on-one",
                        descriptionJa: "近くにいる敵ヒーローが1体だけの時、そのヒーローへのダメージが7%上昇する。",
                        descriptionEn: "If there is only one enemy hero nearby, damage dealt to them is increased by 7%.",
                        textConfirmed: false, params: ["damage": K.masterAssassinBonus, "radius": K.masterAssassinRadius]),
        EmblemTalentDef(id: .bargainHunter, nameJa: "掘り出し上手", nameEn: "Bargain Hunter", jaConfirmed: false,
                        subtitleJa: "装備を割引で購入", subtitleEn: "Cheaper equipment",
                        descriptionJa: "装備を基本価格の95%で購入できる。", descriptionEn: "Equipment can be purchased at 95% of their base price.",
                        textConfirmed: false, params: ["price": K.bargainPriceRatio]),
        EmblemTalentDef(id: .festivalOfBlood, nameJa: "血の祭典", nameEn: "Festival of Blood", jaConfirmed: false,
                        subtitleJa: "スキル吸収上昇", subtitleEn: "More Spell Vamp",
                        descriptionJa: "スキル吸収が6%上昇する。ヒーローのキル・アシストごとにさらに0.5%上昇する（最大12スタック）。",
                        descriptionEn: "Gain 6% Spell Vamp. Each hero kill or assist grants an additional 0.5%, up to 12 stacks.",
                        textConfirmed: false,
                        params: ["spell_vamp": K.festivalSpellVamp, "per_stack": K.festivalPerStack,
                                 "max_stacks": Double(K.festivalMaxStacks)]),
        EmblemTalentDef(id: .pullYourselfTogether, nameJa: "立て直し", nameEn: "Pull Yourself Together", jaConfirmed: false,
                        subtitleJa: "スペルと装備のCD短縮", subtitleEn: "Shorter spell & item cooldowns",
                        descriptionJa: "バトルスペルと装備のアクティブスキルのCDが12%短縮される。ヒーローのキル・アシストごとにさらに1%短縮される（最大8スタック）。",
                        descriptionEn: "Cooldowns of Battle Spells and equipment active skills are reduced by 12%. Each hero kill or assist grants an additional 1%, up to 8 stacks.",
                        textConfirmed: false,
                        params: ["cooldown": K.pullCooldownReduction, "per_stack": K.pullPerStack, "max_stacks": Double(K.pullMaxStacks)]),
        EmblemTalentDef(id: .weaponMaster, nameJa: "武器マスター", nameEn: "Weapon Master", jaConfirmed: true,
                        subtitleJa: "装備などの攻撃力上昇", subtitleEn: "More attack from gear",
                        descriptionJa: "装備、エンブレム、スキルから獲得する物理攻撃と魔法攻撃が8%増加する。",
                        descriptionEn: "Physical Attack and Magic Power gained from equipment, emblem, talents, and skills are increased by 8%.",
                        textConfirmed: true, params: ["bonus": K.weaponMasterBonus]),

        // MARK: コア（ピッカー: 1 行目 不純な怒り・量子チャージ・鬨の声 / 2 行目 時の支配・強震撃・殺戮の連鎖 /
        //       3 行目 致死の発火・勇猛の一撃・集中マーク / 4 行目 弱点分析）
        EmblemTalentDef(id: .impureRage, nameJa: "不純な怒り", nameEn: "Impure Rage", jaConfirmed: true,
                        subtitleJa: "スキルで最大HP割合ダメージ", subtitleEn: "Skills deal Max HP damage",
                        descriptionJa: "スキルでダメージを与えると、対象の最大HPの4%分の追加適応ダメージを与え、命中時にMPを2%回復する。ヒーローがMPを使用しない場合、代わりにHPを1%回復する。ヒーロー以外のユニットに与える追加適応ダメージは最大120まで。CD時間：5秒",
                        descriptionEn: "Skill damage deals 4% of the target's Max HP as extra Adaptive Damage and restores 2% Mana (1% HP without Mana). Up to 120 against non-heroes. Cooldown: 5s.",
                        textConfirmed: true,
                        params: ["max_hp": K.impureRageMaxHP, "mana": K.impureRageMana, "hp": K.impureRageHP,
                                 "non_hero_cap": K.impureRageNonHeroCap, "cooldown": K.impureRageCooldown]),
        EmblemTalentDef(id: .quantumCharge, nameJa: "量子チャージ", nameEn: "Quantum Charge", jaConfirmed: false,
                        subtitleJa: "通常攻撃で加速と回復", subtitleEn: "Basic Attacks speed up and heal",
                        descriptionJa: "通常攻撃でダメージを与えると、1.5秒間移動速度が30%上昇し、HPを75〜180回復する（レベルに応じる）。CD時間：10秒。",
                        descriptionEn: "Dealing Basic Attack damage grants 30% Movement Speed for 1.5s and restores 75-180 HP (scales with level). Cooldown: 10s.",
                        textConfirmed: false,
                        params: ["move_speed": K.quantumMoveSpeed, "duration": K.quantumDuration, "heal_min": K.quantumHealMin,
                                 "heal_max": K.quantumHealMax, "cooldown": K.quantumCooldown]),
        EmblemTalentDef(id: .warCry, nameJa: "鬨の声", nameEn: "War Cry", jaConfirmed: false,
                        subtitleJa: "3回の命中で与ダメージ上昇", subtitleEn: "Damage up after 3 hits",
                        descriptionJa: "通常攻撃かスキルが敵ヒーローに3回命中するたびに、6秒間与えるダメージが8%上昇する（何度もダメージを与える1回の通常攻撃・スキルは1回と数える）。CD時間：6秒。",
                        descriptionEn: "After every 3 separate Basic Attacks or skills hit an enemy hero, all damage dealt increases by 8% for 6s. Cooldown: 6s.",
                        textConfirmed: false,
                        params: ["hits": Double(K.warCryHits), "damage": K.warCryBonus, "duration": K.warCryDuration,
                                 "cooldown": K.warCryCooldown]),
        EmblemTalentDef(id: .temporalReign, nameJa: "時の支配", nameEn: "Temporal Reign", jaConfirmed: false,
                        subtitleJa: "必殺技の後にCD加速", subtitleEn: "Faster cooldowns after the Ultimate",
                        descriptionJa: "次に必殺技を使うと、4秒間ほかのアクティブスキルの残りCDが1.5倍の速さで減る。ヒーローのキル・アシストで2秒延長される（自分にだけ効く）。CD時間：20秒。",
                        descriptionEn: "The next Ultimate makes other active skills' cooldowns tick 1.5x faster for 4s (extended by 2s on hero kills or assists). Cooldown: 20s.",
                        textConfirmed: false,
                        params: ["rate": K.temporalRate, "duration": K.temporalDuration, "extend": K.temporalExtend,
                                 "cooldown": K.temporalCooldown]),
        EmblemTalentDef(id: .concussiveBlast, nameJa: "強震撃", nameEn: "Concussive Blast", jaConfirmed: true,
                        subtitleJa: "通常攻撃で範囲魔法ダメージ", subtitleEn: "Basic Attack blasts nearby enemies",
                        descriptionJa: "次の通常攻撃後、周囲の敵に100(+7%最大HP)の魔法ダメージを与える。CD時間：15秒。",
                        descriptionEn: "After the next Basic Attack, deal 100 (+7% Total HP) Magic Damage to nearby enemies. Cooldown: 15s.",
                        textConfirmed: true,
                        params: ["base": K.concussiveBase, "max_hp": K.concussiveMaxHP, "radius": K.concussiveRadius,
                                 "cooldown": K.concussiveCooldown]),
        EmblemTalentDef(id: .killingSpree, nameJa: "殺戮の連鎖", nameEn: "Killing Spree", jaConfirmed: false,
                        subtitleJa: "低HPの敵で回復と加速", subtitleEn: "Heal and speed vs low-HP heroes",
                        descriptionJa: "HPが30%未満の敵ヒーローにダメージを与えると、失ったHPの15%を即座に回復し、3秒間移動速度が20%上昇する。敵ヒーローを倒すとCDがリセットされる。CD時間：30秒。",
                        descriptionEn: "Damaging heroes below 30% HP instantly recovers 15% of lost HP and grants 20% Movement Speed for 3s. Killing an enemy hero resets the cooldown. Cooldown: 30s.",
                        textConfirmed: false,
                        params: ["hp_ratio": K.killingSpreeHPRatio, "lost_hp": K.killingSpreeLostHP, "move_speed": K.killingSpreeMoveSpeed,
                                 "duration": K.killingSpreeDuration, "cooldown": K.killingSpreeCooldown]),
        EmblemTalentDef(id: .lethalIgnition, nameJa: "致死の発火", nameEn: "Lethal Ignition", jaConfirmed: false,
                        subtitleJa: "続けて大ダメージで追加ダメージ", subtitleEn: "Burst bonus damage",
                        descriptionJa: "5秒以内に敵ヒーローの最大HPの7%を超えるダメージを3回与えると、対象を焼いて162〜750の適応ダメージを与える（レベルに応じる）。CD時間：15秒。",
                        descriptionEn: "Dealing damage greater than 7% of an enemy hero's Max HP 3 times within 5s scorches the target for 162-750 Adaptive Damage (scales with level). Cooldown: 15s.",
                        textConfirmed: false,
                        params: ["max_hp": K.lethalThreshold, "hits": Double(K.lethalHits), "window": K.lethalWindow,
                                 "damage_min": K.lethalDamageMin, "damage_max": K.lethalDamageMax, "cooldown": K.lethalCooldown]),
        EmblemTalentDef(id: .braveSmite, nameJa: "勇猛の一撃", nameEn: "Brave Smite", jaConfirmed: false,
                        subtitleJa: "スキル命中でHP回復", subtitleEn: "Skills heal you",
                        descriptionJa: "敵ヒーローにスキルでダメージを与えると、最大HPの5%を回復する。CD時間：6秒。",
                        descriptionEn: "Dealing skill damage to an enemy hero recovers 5% Max HP. Cooldown: 6s.",
                        textConfirmed: false, params: ["max_hp": K.braveSmiteHeal, "cooldown": K.braveSmiteCooldown]),
        EmblemTalentDef(id: .focusingMark, nameJa: "集中マーク", nameEn: "Focusing Mark", jaConfirmed: false,
                        subtitleJa: "味方の与ダメージ上昇", subtitleEn: "Allies deal more damage",
                        descriptionJa: "敵ヒーローにダメージを与えると、3秒間、味方ヒーローがその敵に与えるダメージが6%上昇し、その敵を攻撃した味方の移動速度が10%上昇する。CD時間：4秒。",
                        descriptionEn: "After damaging an enemy hero, allied heroes deal 6% more damage to them and gain 10% Movement Speed for 3s. Cooldown: 4s.",
                        textConfirmed: false,
                        params: ["damage": K.focusBonus, "move_speed": K.focusMoveSpeed, "duration": K.focusDuration,
                                 "cooldown": K.focusCooldown]),
        EmblemTalentDef(id: .weaknessFinder, nameJa: "弱点分析", nameEn: "Weakness Finder", jaConfirmed: true,
                        subtitleJa: "通常攻撃で敵を減速", subtitleEn: "Basic Attacks slow enemies",
                        descriptionJa: "通常攻撃は敵の移動速度を50%、攻撃速度を30%低下させる。持続時間：1秒。CD時間：10秒（通常攻撃を行うたびに1秒短縮される。最小3秒まで）。",
                        descriptionEn: "Basic Attacks slow enemies by 50% and reduce their Attack Speed by 30% for 1s. Cooldown: 10s (each Basic Attack reduces it by 1s, down to 3s).",
                        textConfirmed: true, subtitleConfirmed: true,
                        params: ["slow": K.weaknessSlow, "attack_speed": K.weaknessAttackSpeed, "duration": K.weaknessDuration,
                                 "cooldown": K.weaknessCooldown, "per_attack": K.weaknessPerAttack, "min_cooldown": K.weaknessMinCooldown]),
    ]

    private static let setIndex: [EmblemSetID: Int] = {
        var m: [EmblemSetID: Int] = [:]
        for (k, d) in sets.enumerated() { m[d.id] = k }
        return m
    }()

    private static let talentIndex: [EmblemTalentID: Int] = {
        var m: [EmblemTalentID: Int] = [:]
        for (k, d) in talents.enumerated() { m[d.id] = k }
        return m
    }()

    public static func set(_ id: EmblemSetID) -> EmblemSetDef { sets[setIndex[id] ?? 0] }
    public static func talent(_ id: EmblemTalentID) -> EmblemTalentDef { talents[talentIndex[id] ?? 0] }

    /// 段 tier のタレント（ピッカーの並び）。
    public static func talents(tier: EmblemTier) -> [EmblemTalentDef] { talents.filter { $0.tier == tier } }

    /// セットの既定のタレントの 1 式（level のセット）。
    public static func defaultLoadout(set id: EmblemSetID, level: Int = maxLevel) -> EmblemLoadout {
        let d = set(id)
        return EmblemLoadout(set: id, tier1: d.defaultTier1, tier2: d.defaultTier2, core: d.defaultCore, level: clampLevel(level))
    }

    /// ロールに合うセット（MLBB のロール: タンク = ヴァンガード、ファイター = デュエリスト、メイジ = アルカニスト、
    /// ハンター（マークスマン）= レンジャー）。
    public static func setForRole(_ role: Role) -> EmblemSetID {
        switch role {
        case .vanguard: return .tank
        case .duelist: return .fighter
        case .assassin: return .assassin
        case .arcanist: return .mage
        case .ranger: return .marksman
        case .support: return .support
        }
    }

    /// ロール別の既定（バトルプランの無いヒーロー）: ロールのセットと、そのセットの既定のタレント（MLBB の既定と同じ定番）。
    public static func roleDefault(_ role: Role) -> EmblemLoadout { defaultLoadout(set: setForRole(role)) }

    /// ヒーローのエンブレム: 選んだバトルプラン（nil・範囲外は「有効」のプラン）のエンブレム、プランが無ければロール別の既定。Lv60。
    /// ボットは常に plan = nil（「有効」のプラン）。heroID のロールと role が違う時（テストの差し替え）はロール別。
    public static func loadout(heroID: String, role: Role, plan: Int? = nil, master: MasterData = .shared) -> EmblemLoadout {
        if master.hero(heroID)?.role == role, let p = ItemSystem.plan(heroID: heroID, chosen: plan) { return p.emblem }
        return roleDefault(role)
    }

    /// ボットのエンブレム（「有効」のプランのエンブレム。無ければロール別の既定。Lv60）。
    public static func botLoadout(heroID: String, master: MasterData = .shared) -> EmblemLoadout? {
        guard let def = master.hero(heroID) else { return nil }
        return loadout(heroID: heroID, role: def.role, plan: nil, master: master)
    }
}
