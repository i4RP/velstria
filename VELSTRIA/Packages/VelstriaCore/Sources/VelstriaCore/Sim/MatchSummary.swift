import Foundation

// 担当: core-economy
// 試合結果・スコアボード（DESIGN §11）。MVP スコアと評価 S/A/B/C。

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

    public var kda: Double { score.kda }
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

    /// 試合全体の MVP。
    public var mvp: PlayerSummary? { players.first { $0.isMVP } }

    /// チームの選手（MVP スコア降順）。
    public func players(of team: Team) -> [PlayerSummary] {
        players.filter { $0.team == team }.sorted(by: ScoreSystem.ranksBefore)
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

/// MVP スコア・評価。
///
/// MVP スコア（DESIGN §11）:
///   (K×3 + A×2 − D×1.5) + ヒーローへの与ダメ/1000 + タワーダメ/1500 + (回復+シールド)/2000 + CS/20 + 勝利 3
///
/// 評価（チーム内順位 = MVP スコア降順、同点は ID 昇順。KDA = (K+A)/max(1,D)）:
///   S: チーム内 1 位 かつ KDA ≥ 2.5
///   A: (チーム内 2 位以内 かつ KDA ≥ 1.5) または KDA ≥ 4.0
///   B: チーム内 3 位以内 または KDA ≥ 1.0
///   C: それ以外
/// MVP は全体で MVP スコア最大の 1 名（同点は ID 昇順）。試合中（勝者未定）は勝利ボーナスなしで同じ計算。
public enum ScoreSystem {
    public static let winBonus: Double = 3

    public static func mvpScore(_ sc: HeroScore, won: Bool) -> Double {
        var v = Double(sc.kills) * 3 + Double(sc.assists) * 2 - Double(sc.deaths) * 1.5
        v += sc.damageToHeroes / 1000
        v += sc.towerDamage / 1500
        v += (sc.healingDone + sc.shieldingDone) / 2000
        v += Double(sc.creepScore) / 20
        if won { v += winBonus }
        // 表示・比較を安定させるため 0.01 単位に丸める
        return (v * 100).rounded() / 100
    }

    /// teamRank は 1 始まり。
    public static func grade(teamRank: Int, kda: Double) -> String {
        if teamRank == 1 && kda >= 2.5 { return "S" }
        if (teamRank <= 2 && kda >= 1.5) || kda >= 4.0 { return "A" }
        if teamRank <= 3 || kda >= 1.0 { return "B" }
        return "C"
    }

    /// 並び順（MVP スコア降順、同点は ID 昇順）。
    static func ranksBefore(_ a: PlayerSummary, _ b: PlayerSummary) -> Bool {
        if a.mvpScore != b.mvpScore { return a.mvpScore > b.mvpScore }
        return a.entityID < b.entityID
    }

    /// 現在の状態から試合結果を作る（試合中のスコアボードにも使える）。
    public static func summary(_ s: SimState) -> MatchSummary {
        var players: [PlayerSummary] = s.units.compactMap { u in
            guard u.kind == .hero, let h = u.hero else { return nil }
            let won = s.winner != nil && s.winner == u.team
            return PlayerSummary(entityID: u.id, team: u.team, heroID: h.heroID, displayName: h.displayName,
                                 isHuman: h.controller == .human, position: h.position, level: h.level,
                                 items: h.items, score: h.score, mvpScore: mvpScore(h.score, won: won),
                                 grade: "C", isMVP: false)
        }
        // チーム内順位で評価
        for team in Team.allCases {
            let ranked = players.indices.filter { players[$0].team == team }
                .sorted { ranksBefore(players[$0], players[$1]) }
            for (rank, k) in ranked.enumerated() {
                players[k].grade = grade(teamRank: rank + 1, kda: players[k].score.kda)
            }
        }
        if let top = players.indices.min(by: { ranksBefore(players[$0], players[$1]) }) {
            players[top].isMVP = true
        }
        return MatchSummary(mode: s.config.mode, seed: s.config.seed, winner: s.winner,
                            endReason: s.endReason ?? .aborted, duration: s.time,
                            humanTeam: s.unit(s.humanHeroID)?.team, players: players,
                            teamKills: s.teams.map { $0.kills }, towersDestroyed: s.teams.map { $0.towersDestroyed })
    }
}
