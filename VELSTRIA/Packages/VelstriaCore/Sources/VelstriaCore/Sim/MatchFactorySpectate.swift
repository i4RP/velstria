import Foundation

// 担当: 統合（契約）。観戦（AI 同士）の試合構成: マップ・チーム別の AI 難易度・枠ごとのヒーロー指定・最大時間。
// botMatch(difficulty:seed:) の出力は変えない（UI テストのシード 20261001 や既存のリプレイが前提にしている）。
// 標準マップで指定なし・両チーム同じ難易度なら botMatch と完全に同じ構成になる（同じ塩・同じドラフト順）。

/// 観戦のマップ（マップは mode から導出する: 標準 = .spectate、乱闘 = .brawl の全員 AI）。
public enum SpectateMap: Int, Codable, Hashable, Sendable, CaseIterable {
    case standard, brawl

    /// この構成のマップ（mode から導出）。
    public static func of(_ config: MatchConfig) -> SpectateMap {
        config.mode == .brawl ? .brawl : .standard
    }
}

/// 観戦で枠に固定するヒーロー。
public struct SpectatePick: Codable, Hashable, Sendable {
    public var team: Team
    public var position: LanePosition
    public var heroID: String

    public init(team: Team, position: LanePosition, heroID: String) {
        self.team = team
        self.position = position
        self.heroID = heroID
    }
}

/// 観戦の試合構成の選択（アプリの準備画面から）。
public struct SpectateMatchOptions: Codable, Hashable, Sendable {
    public var map: SpectateMap
    public var blueDifficulty: Difficulty
    public var redDifficulty: Difficulty
    /// 固定するヒーロー（指定の無い枠は AI がドラフトする）。同じ枠・同じヒーローの重複は先の方を採る。
    public var picks: [SpectatePick]
    /// 最大試合時間（秒）。nil ならマップの既定（標準 40 分・乱闘 15 分）。
    public var maxDuration: Double?

    public init(map: SpectateMap = .standard, blueDifficulty: Difficulty = .normal, redDifficulty: Difficulty = .normal,
                picks: [SpectatePick] = [], maxDuration: Double? = nil) {
        self.map = map
        self.blueDifficulty = blueDifficulty
        self.redDifficulty = redDifficulty
        self.picks = picks
        self.maxDuration = maxDuration
    }

    public func difficulty(for team: Team) -> Difficulty { team == .red ? redDifficulty : blueDifficulty }
}

extension MatchFactory {
    /// 観戦で選べる最大時間の範囲（秒）。
    public static let spectateMaxDurationRange: ClosedRange<Double> = 5 * 60 ... 60 * 60

    /// マップ既定の最大時間（秒）。
    public static func defaultMaxDuration(for map: SpectateMap) -> Double {
        map == .brawl ? 15 * 60 : 40 * 60
    }

    /// 全員 AI の 5v5（観戦）。標準マップは mode .spectate、乱闘マップは mode .brawl（人間がいないので観戦扱い）。
    /// 不正な指定（存在しないヒーロー・中立チーム・重複）は無視する。
    public static func spectateMatch(options: SpectateMatchOptions, seed: UInt64,
                                     master: MasterData = .shared) -> MatchConfig {
        // 標準マップは botMatch と同じ塩（指定なしなら botMatch と同じ編成になる）
        var rng = SplitMix64(seed: seed ^ (options.map == .brawl ? 0xB7A1_5EC7_A7E5_0B02 : 0x9E37_79B9))
        var fixed: [(Team, LanePosition, String)] = []
        var used = Set<String>()
        for pick in options.picks where pick.team != .neutral && master.hero(pick.heroID) != nil {
            guard !used.contains(pick.heroID),
                  !fixed.contains(where: { $0.0 == pick.team && $0.1 == pick.position }) else { continue }
            used.insert(pick.heroID)
            fixed.append((pick.team, pick.position, pick.heroID))
        }
        var picks = draftTeams(used: &used, rng: &rng, master: master, fixed: fixed)
        var players: [PlayerSlot] = []
        for team in Team.players {
            for pos in LanePosition.allCases {
                let heroID = picks[team.rawValue][pos.rawValue] ?? pickHero(for: pos, used: &used, rng: &rng, master: master)
                picks[team.rawValue][pos.rawValue] = heroID
                let name = master.hero(heroID)?.codeName ?? heroID
                // 乱闘はジャングルが無いので狩猟印（BS05）を持たせない
                let spells = options.map == .brawl ? ["BS01", "BS03"] : defaultSpells(for: pos)
                players.append(PlayerSlot(team: team, heroID: heroID, controller: .bot, position: pos,
                                          spells: spells, displayName: "\(name)_AI",
                                          botDifficulty: options.difficulty(for: team)))
            }
        }
        let fallback = defaultMaxDuration(for: options.map)
        let duration = options.maxDuration.map {
            $0.isFinite ? min(spectateMaxDurationRange.upperBound, max(spectateMaxDurationRange.lowerBound, $0)) : fallback
        } ?? fallback
        return MatchConfig(mode: options.map == .brawl ? .brawl : .spectate, seed: seed, players: players,
                           maxDuration: duration)
    }

    /// 構成から観戦の選択を読み戻す（リザルトの「次の観戦」用）。枠の固定は引き継がない（次はドラフトし直す）。
    public static func spectateOptions(from config: MatchConfig) -> SpectateMatchOptions {
        let map = SpectateMap.of(config)
        let blue = config.players.first { $0.team == .blue }?.botDifficulty ?? .normal
        let red = config.players.first { $0.team == .red }?.botDifficulty ?? blue
        let fallback = defaultMaxDuration(for: map)
        return SpectateMatchOptions(map: map, blueDifficulty: blue, redDifficulty: red, picks: [],
                                    maxDuration: config.maxDuration == fallback ? nil : config.maxDuration)
    }
}
