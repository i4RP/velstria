import Foundation

/// エンティティ ID。試合内で単調増加・再利用しない。
public typealias EntityID = Int32

public enum Team: Int, Codable, Hashable, Sendable, CaseIterable {
    case blue = 0
    case red = 1
    case neutral = 2

    /// blue ⇄ red。neutral は neutral。
    public var opponent: Team {
        switch self {
        case .blue: return .red
        case .red: return .blue
        case .neutral: return .neutral
        }
    }

    /// 視界ビットマスク用のビット（neutral は 0）。
    public var visionBit: UInt8 {
        switch self {
        case .blue: return 1
        case .red: return 2
        case .neutral: return 0
        }
    }

    public static let players: [Team] = [.blue, .red]
}

public enum UnitKind: Int, Codable, Hashable, Sendable {
    case hero
    case minion
    case tower
    case core
    case monster
    /// 練習場のターゲット人形。
    case dummy
}

public enum Lane: Int, Codable, Hashable, Sendable, CaseIterable {
    case top = 0, mid = 1, bot = 2
}

/// AI・ドラフト用のポジション。
public enum LanePosition: Int, Codable, Hashable, Sendable, CaseIterable {
    case top = 0, jungle, mid, carry, support
}

public enum Role: String, Codable, Hashable, Sendable, CaseIterable {
    case vanguard = "Vanguard"
    case duelist = "Duelist"
    case ranger = "Ranger"
    case arcanist = "Arcanist"
    case support = "Support"
    case assassin = "Assassin"

    public var nameJa: String {
        switch self {
        case .vanguard: return "ヴァンガード"
        case .duelist: return "デュエリスト"
        case .ranger: return "レンジャー"
        case .arcanist: return "アルカニスト"
        case .support: return "サポート"
        case .assassin: return "アサシン"
        }
    }
}

public enum ResourceKind: String, Codable, Hashable, Sendable {
    case mana = "Mana"
    case energy = "Energy"
}

public enum DamageType: String, Codable, Hashable, Sendable {
    case physical = "Physical"
    case magic = "Magic"
    case trueDamage = "True"
}

public enum CrowdControl: String, Codable, Hashable, Sendable, CaseIterable {
    case none = "None"
    case slow = "Slow"
    case knockback = "Knockback"
    case root = "Root"
    case stun = "Stun"
}

/// スキル枠。rawValue は配列インデックス（skillRanks / skillCooldowns）。
/// JSON では "Passive" / "Skill1" / "Skill2" / "Skill3" / "Ultimate" の文字列。
public enum SkillSlot: Int, Hashable, Sendable, CaseIterable, Codable {
    case passive = 0, skill1 = 1, skill2 = 2, skill3 = 3, ultimate = 4

    public static let actives: [SkillSlot] = [.skill1, .skill2, .skill3, .ultimate]

    public var masterName: String {
        switch self {
        case .passive: return "Passive"
        case .skill1: return "Skill1"
        case .skill2: return "Skill2"
        case .skill3: return "Skill3"
        case .ultimate: return "Ultimate"
        }
    }

    public var maxRank: Int {
        switch self {
        case .passive: return 1
        case .ultimate: return Balance.ultimateMaxRank
        default: return Balance.basicSkillMaxRank
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self),
           let v = SkillSlot.allCases.first(where: { $0.masterName == s }) {
            self = v
        } else if let i = try? c.decode(Int.self), let v = SkillSlot(rawValue: i) {
            self = v
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown SkillSlot")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(masterName)
    }
}

public enum MinionType: Int, Codable, Hashable, Sendable {
    case melee, ranged, siege
}

public enum TowerTier: Int, Codable, Hashable, Sendable, CaseIterable {
    case outer = 0, inner = 1, base = 2
}

public enum MonsterKind: Int, Codable, Hashable, Sendable {
    case campLarge
    case campSmall
    case blueSentinel   // 蒼晶の番人
    case redSentinel    // 紅焔の番人
    case astralWyrm     // 星喰竜
    case ancientColossus // 古環の巨像
}

public enum ItemCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case attack = "Attack"
    case magic = "Magic"
    case defense = "Defense"
    case movement = "Movement"
    case utility = "Utility"
    case jungle = "Jungle"
}

public enum RunePath: String, Codable, Hashable, Sendable, CaseIterable {
    case valor = "Valor"
    case arcana = "Arcana"
    case resolve = "Resolve"
    case cunning = "Cunning"
    case harmony = "Harmony"
}

public enum EffectType: String, Codable, Hashable, Sendable {
    case burst = "Burst"
    case trail = "Trail"
    case area = "Area"
    case shield = "Shield"
    case projectile = "Projectile"
}

public enum CosmeticType: String, Codable, Hashable, Sendable, CaseIterable {
    case heroSkin = "HeroSkin"
    case recall = "Recall"
    case spawn = "Spawn"
    case emote = "Emote"
    case avatarFrame = "AvatarFrame"
    case killEffect = "KillEffect"
}

public enum Rarity: String, Codable, Hashable, Sendable, CaseIterable {
    case common = "Common"
    case rare = "Rare"
    case epic = "Epic"
    case mythic = "Mythic"
}

public enum StoreItemType: String, Codable, Hashable, Sendable {
    case cosmetic = "Cosmetic"
    case heroUnlock = "HeroUnlock"
    case bundle = "Bundle"
}

public enum Currency: String, Codable, Hashable, Sendable {
    case astralGem = "AstralGem"
    case starlightCoin = "StarlightCoin"
}

public enum Difficulty: Int, Codable, Hashable, Sendable, CaseIterable {
    case easy = 0, normal = 1, hard = 2
}

public enum MatchMode: Int, Codable, Hashable, Sendable {
    /// 5v5 対 AI（通常）。
    case standard
    /// ランク戦（対 AI、BAN あり）。
    case ranked
    /// 練習場（敵ヒーローなし・人形あり）。
    case practice
    /// チュートリアル（練習場ベース + ガイド）。
    case tutorial
    /// 観戦（10 体すべて AI）。
    case spectate
    /// オンライン対戦（リッスンサーバー: 人間が複数、空いた枠は AI。報酬・ランクの対象外）。
    case online
}

public enum MatchPhase: Int, Codable, Hashable, Sendable {
    case loading, playing, ended
}

/// 通常攻撃ボタンのターゲット優先度。
public enum TargetPriority: Int, Codable, Hashable, Sendable {
    case heroesFirst
    case minionsFirst
    case structuresFirst
    case lowestHealth
}
