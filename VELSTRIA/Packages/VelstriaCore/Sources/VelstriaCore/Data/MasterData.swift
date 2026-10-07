import Foundation

// MARK: - マスターデータ行（master_runtime.json と 1:1）

public struct HeroDef: Codable, Hashable, Sendable, Identifiable {
    public var id: String { heroID }
    public let heroID: String
    public let codeName: String
    public let displayNameJa: String
    public let role: Role
    public let roleJa: String
    public let difficulty: Int
    public let baseHP: Double
    public let hpGrowth: Double
    public let baseAttack: Double
    public let attackGrowth: Double
    public let baseDefense: Double
    public let defenseGrowth: Double
    public let baseMagicDefense: Double
    public let magicDefenseGrowth: Double
    public let moveSpeed: Double
    public let attackRange: Double
    public let resource: ResourceKind
    public let resourceMax: Double
    public let lore: String
    public let strengths: String
    public let weaknesses: String
    public let counterplay: String

    /// H001 → 1
    public var number: Int { Int(heroID.dropFirst()) ?? 0 }
    public var isRanged: Bool { attackRange >= 300 }

    enum CodingKeys: String, CodingKey {
        case heroID = "hero_id", codeName = "code_name", displayNameJa = "display_name_ja", role
        case roleJa = "role_ja", difficulty, baseHP = "base_hp", hpGrowth = "hp_growth"
        case baseAttack = "base_attack", attackGrowth = "attack_growth", baseDefense = "base_defense"
        case defenseGrowth = "defense_growth", baseMagicDefense = "base_magic_defense"
        case magicDefenseGrowth = "magic_defense_growth", moveSpeed = "move_speed"
        case attackRange = "attack_range", resource, resourceMax = "resource_max", lore, strengths
        case weaknesses, counterplay
    }
}

public struct SkillDef: Codable, Hashable, Sendable, Identifiable {
    public var id: String { skillID }
    public let skillID: String
    public let heroID: String
    public let heroName: String
    public let slot: SkillSlot
    public let nameJa: String
    public let damageType: DamageType
    public let baseDamage: Double
    public let scalingAttack: Double
    public let scalingPower: Double
    public let cooldownSec: Double
    public let cost: Double
    public let range: Double
    public let radius: Double
    public let cc: CrowdControl
    public let effectID: String
    public let description: String

    enum CodingKeys: String, CodingKey {
        case skillID = "skill_id", heroID = "hero_id", heroName = "hero_name", slot, nameJa = "name_ja"
        case damageType = "damage_type", baseDamage = "base_damage", scalingAttack = "scaling_attack"
        case scalingPower = "scaling_power", cooldownSec = "cooldown_sec", cost, range, radius, cc
        case effectID = "effect_id", description
    }
}

public struct ItemDef: Codable, Hashable, Sendable, Identifiable {
    public var id: String { itemID }
    public let itemID: String
    public let nameJa: String
    public let category: ItemCategory
    public let tier: Int
    public let priceGold: Double
    public let attack: Double
    public let abilityPower: Double
    public let hp: Double
    public let armor: Double
    public let magicResist: Double
    public let moveSpeed: Double
    public let cooldownReductionPct: Double
    public let passiveName: String
    public let passiveText: String
    public let buildFrom: [String]

    /// passive_text 中の「N%」の N（見つからなければ 0）。
    public var passivePercent: Double { MasterData.firstPercent(in: passiveText) }

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id", nameJa = "name_ja", category, tier, priceGold = "price_gold", attack
        case abilityPower = "ability_power", hp, armor, magicResist = "magic_resist"
        case moveSpeed = "move_speed", cooldownReductionPct = "cooldown_reduction_pct"
        case passiveName = "passive_name", passiveText = "passive_text", buildFrom = "build_from"
    }
}

public struct SpellDef: Codable, Hashable, Sendable, Identifiable {
    public var id: String { spellID }
    public let spellID: String
    public let nameJa: String
    public let cooldownSec: Double
    public let description: String

    enum CodingKeys: String, CodingKey {
        case spellID = "spell_id", nameJa = "name_ja", cooldownSec = "cooldown_sec", description
    }
}

public struct RuneDef: Codable, Hashable, Sendable, Identifiable {
    public var id: String { runeID }
    public let runeID: String
    public let nameJa: String
    public let path: RunePath
    public let tier: Int
    public let effect: String

    /// effect 中の「N%」の N。
    public var percent: Double { MasterData.firstPercent(in: effect) }

    enum CodingKeys: String, CodingKey {
        case runeID = "rune_id", nameJa = "name_ja", path, tier, effect
    }
}

public struct EffectDef: Codable, Hashable, Sendable, Identifiable {
    public var id: String { effectID }
    public let effectID: String
    public let nameJa: String
    public let effectType: EffectType
    public let durationSec: Double
    public let scaleM: Double
    public let particleBudget: Int

    enum CodingKeys: String, CodingKey {
        case effectID = "effect_id", nameJa = "name_ja", effectType = "effect_type"
        case durationSec = "duration_sec", scaleM = "scale_m", particleBudget = "particle_budget"
    }
}

public struct CosmeticDef: Codable, Hashable, Sendable, Identifiable {
    public var id: String { cosmeticID }
    public let cosmeticID: String
    public let nameJa: String
    public let type: CosmeticType
    /// HeroSkin のみ有効（それ以外は空文字）。
    public let heroID: String
    public let rarity: Rarity
    public let competitivePower: Double

    enum CodingKeys: String, CodingKey {
        case cosmeticID = "cosmetic_id", nameJa = "name_ja", type, heroID = "hero_id", rarity
        case competitivePower = "competitive_power"
    }
}

public struct StoreItemDef: Codable, Hashable, Sendable, Identifiable {
    public var id: String { sku }
    public let sku: String
    public let nameJa: String
    public let type: StoreItemType
    public let currency: Currency
    public let price: Int
    /// Cosmetic → cosmetic_id、HeroUnlock → hero_id、Bundle → "BUNDLE_nn"
    public let grantID: String
    public let purchaseLimit: Int
    public let refundPolicy: String
    public let duplicatePolicy: String
    public let competitivePower: Double

    enum CodingKeys: String, CodingKey {
        case sku, nameJa = "name_ja", type, currency, price, grantID = "grant_id"
        case purchaseLimit = "purchase_limit", refundPolicy = "refund_policy"
        case duplicatePolicy = "duplicate_policy", competitivePower = "competitive_power"
    }
}

public struct GameRuleDef: Codable, Hashable, Sendable {
    public let key: String
    public let value: String

    enum CodingKeys: String, CodingKey { case key, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        if let s = try? c.decode(String.self, forKey: .value) {
            value = s
        } else if let i = try? c.decode(Int.self, forKey: .value) {
            value = String(i)
        } else if let d = try? c.decode(Double.self, forKey: .value) {
            value = String(d)
        } else {
            value = ""
        }
    }
}

public struct MasterMeta: Codable, Hashable, Sendable {
    public let gameName: String
    public let version: String
    enum CodingKeys: String, CodingKey { case gameName = "game_name", version }
}

// MARK: - MasterData

/// 実行時マスターデータ（不変）。参照型で共有し、コピーコストを避ける。
/// 配列の順序はマスターの ID 順で決定論的。辞書は「検索専用」（列挙しないこと）。
public final class MasterData: @unchecked Sendable {
    public let meta: MasterMeta
    public let gameRules: [GameRuleDef]
    public let heroes: [HeroDef]
    public let skills: [SkillDef]
    public let items: [ItemDef]
    public let spells: [SpellDef]
    public let runes: [RuneDef]
    public let effects: [EffectDef]
    public let cosmetics: [CosmeticDef]
    public let store: [StoreItemDef]

    private let heroByID: [String: HeroDef]
    private let skillByID: [String: SkillDef]
    private let skillsByHero: [String: [SkillDef]]
    private let itemByID: [String: ItemDef]
    private let spellByID: [String: SpellDef]
    private let runeByID: [String: RuneDef]
    private let effectByID: [String: EffectDef]
    private let cosmeticByID: [String: CosmeticDef]
    private let storeBySKU: [String: StoreItemDef]

    private struct Raw: Decodable {
        let meta: MasterMeta
        let gameRules: [GameRuleDef]
        let heroes: [HeroDef]
        let skills: [SkillDef]
        let equipment: [ItemDef]
        let battleSpells: [SpellDef]
        let runes: [RuneDef]
        let effects: [EffectDef]
        let cosmetics: [CosmeticDef]
        let store: [StoreItemDef]
        enum CodingKeys: String, CodingKey {
            case meta, gameRules = "game_rules", heroes, skills, equipment
            case battleSpells = "battle_spells", runes, effects, cosmetics, store
        }
    }

    public init(jsonData: Data) throws {
        let raw = try JSONDecoder().decode(Raw.self, from: jsonData)
        meta = raw.meta
        gameRules = raw.gameRules
        heroes = raw.heroes.sorted { $0.heroID < $1.heroID }
        skills = raw.skills.sorted { $0.skillID < $1.skillID }
        // 靴（ジャングル靴・ローム靴）は正本マスターに無いので、同じ ID があればマスターを優先して加える
        let gearItems = GearCatalog.items.filter { g in !raw.equipment.contains { $0.itemID == g.itemID } }
        items = (raw.equipment + gearItems).sorted { $0.itemID < $1.itemID }
        spells = raw.battleSpells.sorted { $0.spellID < $1.spellID }
        runes = raw.runes.sorted { $0.runeID < $1.runeID }
        effects = raw.effects.sorted { $0.effectID < $1.effectID }
        cosmetics = raw.cosmetics.sorted { $0.cosmeticID < $1.cosmeticID }
        store = raw.store.sorted { $0.sku < $1.sku }

        heroByID = Dictionary(uniqueKeysWithValues: heroes.map { ($0.heroID, $0) })
        skillByID = Dictionary(uniqueKeysWithValues: skills.map { ($0.skillID, $0) })
        skillsByHero = Dictionary(grouping: skills, by: { $0.heroID })
            .mapValues { $0.sorted { $0.slot.rawValue < $1.slot.rawValue } }
        itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.itemID, $0) })
        spellByID = Dictionary(uniqueKeysWithValues: spells.map { ($0.spellID, $0) })
        runeByID = Dictionary(uniqueKeysWithValues: runes.map { ($0.runeID, $0) })
        effectByID = Dictionary(uniqueKeysWithValues: effects.map { ($0.effectID, $0) })
        cosmeticByID = Dictionary(uniqueKeysWithValues: cosmetics.map { ($0.cosmeticID, $0) })
        storeBySKU = Dictionary(uniqueKeysWithValues: store.map { ($0.sku, $0) })
    }

    /// パッケージ同梱の master_runtime.json を読み込む（アプリ・テスト共通）。
    public static let shared: MasterData = {
        guard let url = Bundle.module.url(forResource: "master_runtime", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let master = try? MasterData(jsonData: data) else {
            fatalError("master_runtime.json の読み込みに失敗しました")
        }
        return master
    }()

    public func hero(_ id: String) -> HeroDef? { heroByID[id] }
    public func skill(_ id: String) -> SkillDef? { skillByID[id] }
    /// Passive, Skill1, Skill2, Ultimate の順（SkillSlot.rawValue 順）。
    public func skills(forHero id: String) -> [SkillDef] { skillsByHero[id] ?? [] }
    public func skill(hero id: String, slot: SkillSlot) -> SkillDef? {
        skillsByHero[id]?.first { $0.slot == slot }
    }
    public func item(_ id: String) -> ItemDef? { itemByID[id] }
    public func spell(_ id: String) -> SpellDef? { spellByID[id] }
    public func rune(_ id: String) -> RuneDef? { runeByID[id] }
    public func effect(_ id: String) -> EffectDef? { effectByID[id] }
    public func cosmetic(_ id: String) -> CosmeticDef? { cosmeticByID[id] }
    public func storeItem(_ sku: String) -> StoreItemDef? { storeBySKU[sku] }
    public func heroes(role: Role) -> [HeroDef] { heroes.filter { $0.role == role } }

    /// 文字列中の最初の「N%」の N を返す。
    public static func firstPercent(in text: String) -> Double {
        guard let r = text.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) else { return 0 }
        return Double(text[r].dropLast()) ?? 0
    }
}
