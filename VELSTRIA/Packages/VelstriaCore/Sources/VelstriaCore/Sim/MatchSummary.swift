import Foundation

// 担当: core-economy（最小実装。MVP スコア・評価 S/A/B/C を DESIGN §11 通りに実装すること）

public struct PlayerSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: EntityID { entityID }
    public var entityID: EntityID
    public var team: Team
    public var heroID: String
    public var displayName: String
    public var isHuman: Bool
    public var position: LanePosition
    public var level: Int
    public var items: [String]
    public var score: HeroScore
    public var mvpScore: Double
    /// "S" / "A" / "B" / "C"
    public var grade: String
    public var isMVP: Bool

    public init(entityID: EntityID, team: Team, heroID: String, displayName: String, isHuman: Bool,
                position: LanePosition, level: Int, items: [String], score: HeroScore, mvpScore: Double,
                grade: String, isMVP: Bool) {
        self.entityID = entityID
        self.team = team
        self.heroID = heroID
        self.displayName = displayName
        self.isHuman = isHuman
        self.position = position
        self.level = level
        self.items = items
        self.score = score
        self.mvpScore = mvpScore
        self.grade = grade
        self.isMVP = isMVP
    }
}

/// 試合結果（リザルト画面・報酬計算・戦績保存に使う）。
public struct MatchSummary: Codable, Hashable, Sendable {
    public var mode: MatchMode
    public var seed: UInt64
    public var winner: Team?
    public var endReason: EndReason
    public var duration: Double
    public var humanTeam: Team?
    public var players: [PlayerSummary]
    /// index = Team.rawValue
    public var teamKills: [Int]
    /// index = Team.rawValue（そのチームが破壊した数）
    public var towersDestroyed: [Int]

    public var humanPlayer: PlayerSummary? { players.first { $0.isHuman } }
    public var humanWon: Bool? {
        guard let w = winner, let t = humanTeam else { return nil }
        return w == t
    }

    public init(mode: MatchMode, seed: UInt64, winner: Team?, endReason: EndReason, duration: Double,
                humanTeam: Team?, players: [PlayerSummary], teamKills: [Int], towersDestroyed: [Int]) {
        self.mode = mode
        self.seed = seed
        self.winner = winner
        self.endReason = endReason
        self.duration = duration
        self.humanTeam = humanTeam
        self.players = players
        self.teamKills = teamKills
        self.towersDestroyed = towersDestroyed
    }
}

public enum ScoreSystem {
    /// 現在の状態から試合結果を作る（試合中のスコアボードにも使える）。
    public static func summary(_ s: SimState) -> MatchSummary {
        let heroes = s.units.filter { $0.kind == .hero }
        let players: [PlayerSummary] = heroes.compactMap { u in
            guard let h = u.hero else { return nil }
            let sc = h.score
            let mvp = Double(sc.kills) * 3 + Double(sc.assists) * 2 - Double(sc.deaths) * 1.5
            return PlayerSummary(entityID: u.id, team: u.team, heroID: h.heroID, displayName: h.displayName,
                                 isHuman: h.controller == .human, position: h.position, level: h.level, items: h.items,
                                 score: sc, mvpScore: mvp, grade: "B", isMVP: false)
        }
        return MatchSummary(mode: s.config.mode, seed: s.config.seed, winner: s.winner,
                            endReason: s.endReason ?? .aborted, duration: s.time,
                            humanTeam: s.unit(s.humanHeroID)?.team, players: players,
                            teamKills: s.teams.map { $0.kills }, towersDestroyed: s.teams.map { $0.towersDestroyed })
    }
}
