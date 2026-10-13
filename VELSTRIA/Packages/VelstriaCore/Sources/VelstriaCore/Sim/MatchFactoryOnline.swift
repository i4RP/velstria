import Foundation

// 担当: 統合（契約）。オンライン対戦（リッスンサーバー）の試合構成。

/// オンライン対戦の人間 1 人分の枠（ロビーの座席）。
public struct OnlineHumanSlot: Codable, Hashable, Sendable {
    public var team: Team
    public var position: LanePosition
    public var heroID: String
    public var displayName: String
    public var spells: [String]?
    /// エンブレム（nil = 選んだバトルプランのエンブレム。旧版のロビーには無いので任意）。
    public var emblem: EmblemLoadout?
    public var skinID: String?
    public var autoLevelSkills: Bool
    /// 選んだバトルプランの添字（nil = 「有効」のプラン。旧版のロビーには無いので任意）。
    public var buildPlan: Int?

    public init(team: Team, position: LanePosition, heroID: String, displayName: String,
                spells: [String]? = nil, emblem: EmblemLoadout? = nil, skinID: String? = nil, autoLevelSkills: Bool = true,
                buildPlan: Int? = nil) {
        self.team = team
        self.position = position
        self.heroID = heroID
        self.displayName = displayName
        self.spells = spells
        self.emblem = emblem
        self.skinID = skinID
        self.autoLevelSkills = autoLevelSkills
        self.buildPlan = buildPlan
    }
}

extension MatchFactory {
    /// 座席番号（0...9）。players 配列の添字と一致する（Blue 5 → Red 5、ポジション順）。
    public static func onlineSeatIndex(team: Team, position: LanePosition) -> Int {
        team.rawValue * LanePosition.allCases.count + position.rawValue
    }

    /// 座席番号 → (チーム, ポジション)。
    public static func onlineSeat(_ index: Int) -> (team: Team, position: LanePosition)? {
        let n = LanePosition.allCases.count
        guard index >= 0, index < n * Team.players.count,
              let pos = LanePosition(rawValue: index % n) else { return nil }
        return (Team.players[index / n], pos)
    }

    /// 人間が複数いる 5v5（オンライン対戦）。人間が占めない枠は AI（DraftAI が人間のピックを避けて選ぶ）。
    /// players の並びは standardMatch と同じ（Blue のポジション順 → Red のポジション順）なので、
    /// 座席番号 `onlineSeatIndex` がそのまま players の添字になる。同じ (team, position) の人間が複数いれば後の方は無視する。
    public static func onlineMatch(humans: [OnlineHumanSlot], botDifficulty: Difficulty = .normal,
                                   seed: UInt64,
                                   master: MasterData = .shared) -> MatchConfig {
        var rng = SplitMix64(seed: seed ^ 0x5EED_0A11_1E57_C0DE)
        var bySeat: [Int: OnlineHumanSlot] = [:]
        for h in humans where h.team != .neutral && master.hero(h.heroID) != nil {
            let i = onlineSeatIndex(team: h.team, position: h.position)
            if bySeat[i] == nil { bySeat[i] = h }
        }
        let seats = bySeat.keys.sorted()
        var used = Set(seats.map { bySeat[$0]!.heroID })
        var picks = draftTeams(used: &used, rng: &rng, master: master,
                               fixed: seats.map { (bySeat[$0]!.team, bySeat[$0]!.position, bySeat[$0]!.heroID) })
        var players: [PlayerSlot] = []
        for team in Team.players {
            for pos in LanePosition.allCases {
                if let h = bySeat[onlineSeatIndex(team: team, position: pos)] {
                    players.append(PlayerSlot(team: team, heroID: h.heroID, controller: .human, position: pos,
                                              spells: h.spells ?? defaultSpells(for: pos),
                                              emblem: h.emblem ?? humanDefaultEmblem(h.heroID, plan: h.buildPlan, master: master),
                                              skinID: h.skinID, displayName: h.displayName,
                                              autoLevelSkills: h.autoLevelSkills, buildPlan: h.buildPlan))
                    continue
                }
                let heroID = picks[team.rawValue][pos.rawValue] ?? pickHero(for: pos, used: &used, rng: &rng, master: master)
                picks[team.rawValue][pos.rawValue] = heroID
                let name = master.hero(heroID)?.codeName ?? heroID
                players.append(PlayerSlot(team: team, heroID: heroID, controller: .bot, position: pos,
                                          spells: defaultSpells(for: pos), emblem: EmblemCatalog.botLoadout(heroID: heroID, master: master),
                                          displayName: "\(name)_AI", botDifficulty: botDifficulty))
            }
        }
        return MatchConfig(mode: .online, seed: seed, players: players)
    }
}
