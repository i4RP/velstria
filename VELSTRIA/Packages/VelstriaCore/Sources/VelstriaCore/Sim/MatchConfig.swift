import Foundation

public struct PlayerSlot: Codable, Hashable, Sendable {
    public var team: Team
    public var heroID: String
    public var controller: Controller
    public var position: LanePosition
    /// バトルスペル 2 つ。
    public var spells: [String]
    /// ルーン 3 つ（Tier1/2/3）。
    public var runes: [String]
    public var skinID: String?
    public var displayName: String
    public var botDifficulty: Difficulty
    public var autoLevelSkills: Bool

    public init(team: Team, heroID: String, controller: Controller, position: LanePosition,
                spells: [String] = ["BS01", "BS03"], runes: [String] = [], skinID: String? = nil,
                displayName: String, botDifficulty: Difficulty = .normal, autoLevelSkills: Bool = true) {
        self.team = team
        self.heroID = heroID
        self.controller = controller
        self.position = position
        self.spells = spells
        self.runes = runes
        self.skinID = skinID
        self.displayName = displayName
        self.botDifficulty = botDifficulty
        self.autoLevelSkills = autoLevelSkills
    }
}

public struct PracticeOptions: Codable, Hashable, Sendable {
    public var infiniteGold: Bool
    public var noCooldowns: Bool
    public var spawnMinions: Bool
    public var spawnDummies: Bool
    public var startLevel: Int

    public init(infiniteGold: Bool = false, noCooldowns: Bool = false, spawnMinions: Bool = true,
                spawnDummies: Bool = true, startLevel: Int = 1) {
        self.infiniteGold = infiniteGold
        self.noCooldowns = noCooldowns
        self.spawnMinions = spawnMinions
        self.spawnDummies = spawnDummies
        self.startLevel = startLevel
    }
}

public struct MatchConfig: Codable, Hashable, Sendable {
    /// リプレイ互換性のためのシミュレーション版数。ルール変更時に上げる。
    public static let currentSimVersion = 2

    public var simVersion: Int
    public var mode: MatchMode
    public var seed: UInt64
    /// 通常は 10 人（blue 5 + red 5）。練習場・チュートリアルは人間 1 人のみ。
    public var players: [PlayerSlot]
    public var practice: PracticeOptions?
    /// 安全装置の最大試合時間（秒）。
    public var maxDuration: Double

    public init(mode: MatchMode, seed: UInt64, players: [PlayerSlot], practice: PracticeOptions? = nil,
                maxDuration: Double = 40 * 60) {
        self.simVersion = MatchConfig.currentSimVersion
        self.mode = mode
        self.seed = seed
        self.players = players
        self.practice = practice
        self.maxDuration = maxDuration
    }

    public var humanSlot: PlayerSlot? { players.first { $0.controller == .human } }
}
