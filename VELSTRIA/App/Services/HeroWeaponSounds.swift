import Foundation

// 担当: app-services。武器ごとの通常攻撃の音の組（tools/audio/sets/weapons.py が作る録音の音。出典は docs/audio/SOURCES.md）。
// 1 つの組 = 通常攻撃 4 種（wpn_<組>_atk_1..4）・命中 3 種（_hit_1..3）・会心 2 種（_crit_1..2）。鳴らすたびに順に替える。
// ヒーロー固有の通常攻撃の音（skill_<ヒーロー>_atk 等。H029・H034）があればそちらが先（SkillSoundKey.fallbackFileName）。

/// 武器の音の組。
enum WeaponSoundSet: String, CaseIterable, Sendable {
    case sword, greatsword, dual, spear, fist, hammer, chain
    case bow, crossbow, gun, cannon
    case magicWater = "magic_water", magicFire = "magic_fire", magicLightning = "magic_lightning"
    case magicLight = "magic_light", magicDark = "magic_dark", magicIce = "magic_ice"

    /// ヒーローの武器の組（HeroBlueprints の weapon・offhand・attack と HeroFXProfiles の弾・命中の種類から決めた）。
    static func of(heroID: String) -> WeaponSoundSet? { table[heroID] }

    static let table: [String: WeaponSoundSet] = [
        "H001": .sword,            // 城門の誓衛アルデン: 広刃の剣と盾
        "H002": .sword,            // 星弦のリラ: 細剣の突き
        "H003": .bow,              // 月弓のフィリエル: 弓
        "H004": .magicWater,       // 潮祈のミレア: 潮の杖・水の弾
        "H005": .magicLightning,   // 黒雷のヴォス: 雷の槍から雷を放つ
        "H006": .dual,             // 月灯のセレン: 三日月の短剣
        "H007": .fist,             // 岩脈のガルク: 岩の拳
        "H008": .spear,            // 風標のニア: 旗の槍の突き
        "H009": .crossbow,         // 機巧士オリン: 機械の弩
        "H010": .magicFire,        // 焔冠のテッサ: 手の炎・火の弾
        "H011": .magicLight,       // 鉄翼のルーク: 盾杖・光の弾
        "H012": .dual,             // 玻璃歌のエリネ: 硝子の短剣の二刀
        "H013": .hammer,           // 獣刻のダガン: 骨の棍棒と獣皮の盾
        "H014": .dual,             // 霧歩のシオ: 刀と小太刀の二刀
        "H015": .gun,              // 戦鐘のヴァルカ: ラッパ銃
        "H016": .magicLight,       // 白環のイリス: 光輪の杖
        "H017": .magicDark,        // 深淵鎖のモルド: 深淵の香炉・闇の弾
        "H018": .dual,             // 花星のセリア: 花弁の刃の二刀
        "H019": .hammer,           // 砦砕のブラム: 攻城槌
        "H020": .sword,            // 光矢のユナ: 光の刃
        "H021": .gun,              // 時砂のキロス: 砂の小銃
        "H022": .dual,             // 蒼爪のレア: 蒼い爪の二刀（三日月の爪を飛ばす）
        "H023": .magicLightning,   // 雷槍のトレン: 雷の槍から雷を放つ
        "H024": .dual,             // 夢織のノア: 夢の針の二刀
        "H025": .bow,              // 月弦のルミナ（ミヤ）: 弓
        "H026": .magicLightning,   // 紫電のエウリア（エウドラ）: 雷の球
        "H027": .spear,            // 竜槍のジャルド（子龍）: 竜の槍
        "H028": .sword,            // 断空のザイル（セイバー）: 光の剣
        "H029": .hammer,           // 聖槌のボルグ（ティグラル）: 聖槌と盾（固有の音が先）
        "H030": .cannon,           // 星砲のライナ（ライラ）: 星の砲
        "H031": .magicIce,         // 氷嵐のオーリア（オーロラ）: 氷の魔法
        "H032": .greatsword,       // 赤拳のディアス（ディロス）: 深淵の刃
        "H033": .greatsword,       // 紅牙のヴァルド（アルカード）: 血の大剣
        "H034": .chain,            // 鎖鉤のゴルム（フランコ）: 鎖鉤（固有の音が先）
    ]

    /// 通常攻撃・命中・会心のファイル名（揺らぎの番号なし。揺らぎは _1 …）。それ以外の段は nil。
    func fileName(_ phase: SkillSoundKey.Phase) -> String? {
        switch phase {
        case .attack: return "wpn_\(rawValue)_atk"
        case .attackHit: return "wpn_\(rawValue)_hit"
        case .crit: return "wpn_\(rawValue)_crit"
        case .cast, .hit, .passive: return nil
        }
    }
}
