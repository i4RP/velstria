import Foundation
import VelstriaCore

// 担当: 統合（契約）。フィールド追加は Codable 互換（Optional か既定値付き）で行うこと。
// ロジックは Services/ 側に置き、このファイルはデータ定義のみ。

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, ja, en
    var id: String { rawValue }
}

enum GraphicsQuality: Int, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: Int { rawValue }
}

enum FrameRateOption: Int, Codable, CaseIterable, Identifiable {
    case fps30 = 30, fps60 = 60
    var id: Int { rawValue }
}

enum JoystickMode: Int, Codable, CaseIterable, Identifiable {
    /// 固定位置スティック。
    case fixed
    /// 触れた位置に出現。
    case floating
    var id: Int { rawValue }
}

enum SkillCastMode: Int, Codable, CaseIterable, Identifiable {
    /// タップで自動照準発動、ドラッグで手動照準。
    case smart
    /// 常にドラッグ照準（離して発動）。
    case manual
    var id: Int { rawValue }
}

enum AttackButtonSlot: String, CaseIterable, Identifiable {
    case top, center, bottom
    var id: String { rawValue }
}

enum AgeBracket: Int, Codable, CaseIterable, Identifiable {
    case under13, age13to15, age16to19, adult
    var id: Int { rawValue }

    /// 月間課金上限（円）。nil = 上限なし。
    var monthlySpendLimitJPY: Int? {
        switch self {
        case .under13, .age13to15: return 5_000
        case .age16to19: return 10_000
        case .adult: return nil
        }
    }
}

struct GameSettings: Codable, Equatable {
    var language: AppLanguage = .system
    /// 開発中は同じ曲を繰り返し聴かないよう既定 0（ミュート）。
    var bgmVolume: Double = 0
    var bgmTrack: String = "menu"
    /// 効果音も既定 0（ミュート）。設定画面・一時停止メニューで上げられる。
    var sfxVolume: Double = 0
    var voiceVolume: Double = 0.8
    var hapticsEnabled = true
    var graphicsQuality: GraphicsQuality = .medium
    var frameRate: FrameRateOption = .fps60
    var showDamageNumbers = true
    var joystickMode: JoystickMode = .floating
    var skillCastMode: SkillCastMode = .smart
    /// 中央ボタンの優先対象。既存の保存データのキーを維持する。
    var attackPriority: TargetPriority = .heroesFirst
    var topAttackPriority: TargetPriority = .structuresFirst
    var bottomAttackPriority: TargetPriority = .minionsFirst
    /// 1.0 = 既定。0.8〜1.3。
    var cameraZoom: Double = 1.0
    var leftHandedLayout = false
    /// 色覚サポート（チーム色を青/橙にし、形状マーカーを強調）。
    var colorblindMode = false
    /// HUD の不透明度 0.5〜1.0
    var hudOpacity: Double = 1.0
    var subtitlesEnabled = true
    var notificationsEnabled = false
    var autoLevelSkills = true
    var showRecommendedItems = true

    func attackPriority(for slot: AttackButtonSlot) -> TargetPriority {
        switch slot {
        case .top: return topAttackPriority
        case .center: return attackPriority
        case .bottom: return bottomAttackPriority
        }
    }

    private enum CodingKeys: String, CodingKey {
        case language, bgmVolume, bgmTrack, sfxVolume, voiceVolume, hapticsEnabled
        case graphicsQuality, frameRate, showDamageNumbers, joystickMode, skillCastMode
        case attackPriority, topAttackPriority, bottomAttackPriority
        case cameraZoom, leftHandedLayout, colorblindMode, hudOpacity, subtitlesEnabled
        case notificationsEnabled, autoLevelSkills, showRecommendedItems
    }
}

extension GameSettings {
    /// 旧版にない設定だけを初期値で補い、保存済みの選択はそのまま読み込む。
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? language
        bgmVolume = try values.decodeIfPresent(Double.self, forKey: .bgmVolume) ?? bgmVolume
        bgmTrack = try values.decodeIfPresent(String.self, forKey: .bgmTrack) ?? bgmTrack
        sfxVolume = try values.decodeIfPresent(Double.self, forKey: .sfxVolume) ?? sfxVolume
        voiceVolume = try values.decodeIfPresent(Double.self, forKey: .voiceVolume) ?? voiceVolume
        hapticsEnabled = try values.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? hapticsEnabled
        graphicsQuality = try values.decodeIfPresent(GraphicsQuality.self, forKey: .graphicsQuality) ?? graphicsQuality
        frameRate = try values.decodeIfPresent(FrameRateOption.self, forKey: .frameRate) ?? frameRate
        showDamageNumbers = try values.decodeIfPresent(Bool.self, forKey: .showDamageNumbers) ?? showDamageNumbers
        joystickMode = try values.decodeIfPresent(JoystickMode.self, forKey: .joystickMode) ?? joystickMode
        skillCastMode = try values.decodeIfPresent(SkillCastMode.self, forKey: .skillCastMode) ?? skillCastMode
        attackPriority = try values.decodeIfPresent(TargetPriority.self, forKey: .attackPriority) ?? attackPriority
        topAttackPriority = try values.decodeIfPresent(TargetPriority.self, forKey: .topAttackPriority) ?? topAttackPriority
        bottomAttackPriority = try values.decodeIfPresent(TargetPriority.self, forKey: .bottomAttackPriority) ?? bottomAttackPriority
        cameraZoom = try values.decodeIfPresent(Double.self, forKey: .cameraZoom) ?? cameraZoom
        leftHandedLayout = try values.decodeIfPresent(Bool.self, forKey: .leftHandedLayout) ?? leftHandedLayout
        colorblindMode = try values.decodeIfPresent(Bool.self, forKey: .colorblindMode) ?? colorblindMode
        hudOpacity = try values.decodeIfPresent(Double.self, forKey: .hudOpacity) ?? hudOpacity
        subtitlesEnabled = try values.decodeIfPresent(Bool.self, forKey: .subtitlesEnabled) ?? subtitlesEnabled
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? notificationsEnabled
        autoLevelSkills = try values.decodeIfPresent(Bool.self, forKey: .autoLevelSkills) ?? autoLevelSkills
        showRecommendedItems = try values.decodeIfPresent(Bool.self, forKey: .showRecommendedItems) ?? showRecommendedItems
    }
}

struct RunePage: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var primaryPath: RunePath
    /// Tier1/2/3 の rune_id（未選択は空文字）。
    var runeIDs: [String]
}

enum RankTier: Int, Codable, CaseIterable, Comparable, Identifiable {
    case meteorite, silverRing, goldRing, whiteStar, azureCrystal, starCrown, starRingSovereign
    var id: Int { rawValue }
    static func < (a: RankTier, b: RankTier) -> Bool { a.rawValue < b.rawValue }
}

struct RankState: Codable, Equatable {
    var tier: RankTier = .meteorite
    /// 3 = III（最下段）… 1 = I。星環王は常に 1。
    var division: Int = 3
    var stars: Int = 0
    /// 星環王のポイント。
    var points: Int = 0
    var highestTier: RankTier = .meteorite
    var seasonWins: Int = 0
    var seasonLosses: Int = 0
    /// 受け取り済みのランク報酬（tier rawValue）。
    var claimedTierRewards: [Int] = []
}

struct HeroCareer: Codable, Equatable {
    var matches = 0
    var wins = 0
    var kills = 0
    var deaths = 0
    var assists = 0
    var mvps = 0
}

struct CareerStats: Codable, Equatable {
    var matches = 0
    var wins = 0
    var kills = 0
    var deaths = 0
    var assists = 0
    var mvps = 0
    var totalDamage: Double = 0
    var totalGold: Double = 0
    var longestWinStreak = 0
    var currentWinStreak = 0
    var pentaKills = 0
    var perHero: [String: HeroCareer] = [:]
}

/// 戦績 1 件（最新 50 件保持）。
struct MatchRecord: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var mode: MatchMode
    var difficulty: Difficulty
    var won: Bool?
    var duration: Double
    var heroID: String
    var kills: Int
    var deaths: Int
    var assists: Int
    var creepScore: Int
    var gold: Double
    var damageToHeroes: Double
    var grade: String
    var isMVP: Bool
    var items: [String]
    /// 保存済みリプレイ（ReplayMeta.id）。
    var replayID: UUID?
    var summary: MatchSummary?
}

struct ReplayMeta: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var fileName: String
    var mode: MatchMode
    var heroID: String?
    var won: Bool?
    var duration: Double
}

struct AchievementProgress: Codable, Equatable {
    var progress: Double = 0
    var unlockedAt: Date?
    var claimed = false
}

struct MissionProgress: Codable, Equatable, Identifiable {
    var id: String
    var progress: Int = 0
    var claimed = false
}

struct MissionState: Codable, Equatable {
    /// "yyyy-MM-dd"（端末ローカル日付）。
    var dayKey: String = ""
    var daily: [MissionProgress] = []
    var weeklyKey: String = ""
    var weekly: [MissionProgress] = []
}

struct PassState: Codable, Equatable {
    var seasonID: String = "S1"
    var xp: Int = 0
    var hasPremium = false
    var claimedFree: [Int] = []
    var claimedPremium: [Int] = []
}

struct MailAttachment: Codable, Equatable {
    enum Kind: String, Codable { case coin, gem, cosmetic, hero, passXP }
    var kind: Kind
    var amount: Int = 0
    var refID: String?
}

struct MailItem: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var title: String
    var body: String
    var attachments: [MailAttachment] = []
    var read = false
    var claimed = false
    var expiresAt: Date?
}

/// 課金の付与台帳（Transaction.id で冪等化）。
struct PurchaseRecord: Codable, Equatable, Identifiable {
    var id: UInt64 { transactionID }
    var transactionID: UInt64
    var productID: String
    var gemsGranted: Int
    var priceJPY: Int
    var date: Date
    var revoked = false
}

/// ゲーム内通貨での購入記録（SKU 単位の購入回数）。
struct StorePurchaseCount: Codable, Equatable {
    var sku: String
    var count: Int
}

struct Profile: Codable, Equatable {
    var schemaVersion = 3
    var playerID: String = UUID().uuidString
    var displayName: String = ""
    var createdAt = Date()
    var avatarHeroID: String = "H001"

    // オンボーディング
    var acceptedTermsVersion: Int = 0
    var ageBracket: AgeBracket?
    var onboardingCompleted = false
    var tutorialCompleted = false
    var firstResourcePrepared = false

    // 成長
    var accountLevel = 1
    var accountXP = 0

    // 通貨
    var starlightCoin = 0
    /// 無償 AstralGem（ゲーム内報酬）。
    var freeGem = 0
    /// 有償 AstralGem（課金で購入）。
    var paidGem = 0

    // 所持
    var ownedHeroIDs: [String] = ["H001", "H002", "H003", "H004", "H005", "H006"]
    var ownedCosmeticIDs: [String] = []
    /// heroID → cosmeticID（HeroSkin）
    var equippedSkins: [String: String] = [:]
    var equippedRecall: String?
    var equippedSpawn: String?
    var equippedKillEffect: String?
    var equippedAvatarFrame: String?
    /// エモート 4 枠。
    var equippedEmotes: [String] = []
    var storePurchases: [StorePurchaseCount] = []

    // ロードアウト
    var runePages: [RunePage] = []
    var selectedRunePage: Int = 0
    var defaultSpells: [String] = ["BS01", "BS03"]
    /// heroID → スペル 2 つ（未設定は defaultSpells）
    var heroSpells: [String: [String]] = [:]
    /// heroID → 装備 ID 列（カスタムビルド）
    var customBuilds: [String: [String]] = [:]
    var lastPickedHeroID: String?
    var preferredDifficulty: Difficulty = .normal

    // 競技・記録
    var rank = RankState()
    var career = CareerStats()
    var matchHistory: [MatchRecord] = []
    var replays: [ReplayMeta] = []
    var achievements: [String: AchievementProgress] = [:]
    var missions = MissionState()
    var pass = PassState()
    var lastFirstWinDayKey: String = ""

    // ログイン・メール
    var lastLoginDayKey: String = ""
    var loginStreak = 0
    var totalLoginDays = 0
    var mail: [MailItem] = []
    var readNoticeIDs: [String] = []

    // 課金
    var purchaseLedger: [PurchaseRecord] = []
    /// "yyyy-MM" → 当月課金額（円）
    var monthlySpendJPY: [String: Int] = [:]

    var settings = GameSettings()

    var totalGem: Int { freeGem + paidGem }
}
