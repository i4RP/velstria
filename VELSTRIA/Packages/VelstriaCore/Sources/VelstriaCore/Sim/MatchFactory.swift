import Foundation

// 担当: 統合（契約）。core-bots が DraftAI で改善（シグネチャ維持）。

/// 試合構成（10 人の編成）を作るヘルパー。アプリ・テスト・観戦で共通利用。
public enum MatchFactory {
    /// ポジション毎の適性ロール（先頭ほど優先）。
    public static func preferredRoles(for position: LanePosition) -> [Role] {
        switch position {
        case .top: return [.vanguard, .duelist]
        case .jungle: return [.assassin, .duelist]
        case .mid: return [.arcanist, .assassin]
        case .carry: return [.ranger, .arcanist]
        case .support: return [.support, .vanguard]
        }
    }

    /// ヒーローのロールに最も合うポジション。
    public static func defaultPosition(for role: Role) -> LanePosition {
        switch role {
        case .vanguard: return .top
        case .duelist: return .top
        case .assassin: return .jungle
        case .arcanist: return .mid
        case .ranger: return .carry
        case .support: return .support
        }
    }

    /// 既定スペル（ジャングルは狩猟印）。
    public static func defaultSpells(for position: LanePosition) -> [String] {
        switch position {
        case .jungle: return ["BS05", "BS01"]
        case .support: return ["BS01", "BS04"]
        default: return ["BS01", "BS03"]
        }
    }

    /// 人間 1 人 + AI 9 人の 5v5 を作る。banned / 人間のヒーローは AI が選ばない。
    /// AI のピックは DraftAI（ポジション適性・編成の補完・相性）で、両チーム交互に行う。
    public static func standardMatch(mode: MatchMode = .standard, humanHeroID: String, humanName: String,
                                     humanTeam: Team = .blue, humanSpells: [String]? = nil,
                                     humanRunes: [String] = [], humanSkin: String? = nil,
                                     humanPosition: LanePosition? = nil,
                                     allyDifficulty: Difficulty = .normal, enemyDifficulty: Difficulty = .normal,
                                     banned: [String] = [], seed: UInt64,
                                     master: MasterData = .shared) -> MatchConfig {
        var rng = SplitMix64(seed: seed ^ 0xD1B5_4A32_D192_ED03)
        var used = Set(banned + [humanHeroID])
        let humanDef = master.hero(humanHeroID)
        let humanPos = humanPosition ?? defaultPosition(for: humanDef?.role ?? .duelist)
        var picks = draftTeams(used: &used, rng: &rng, master: master,
                               fixed: [(humanTeam, humanPos, humanHeroID)])
        var players: [PlayerSlot] = []
        for team in Team.players {
            for pos in LanePosition.allCases {
                if team == humanTeam && pos == humanPos {
                    players.append(PlayerSlot(team: team, heroID: humanHeroID, controller: .human, position: pos,
                                              spells: humanSpells ?? defaultSpells(for: pos), runes: humanRunes,
                                              skinID: humanSkin, displayName: humanName))
                    continue
                }
                let heroID = picks[team.rawValue][pos.rawValue] ?? pickHero(for: pos, used: &used, rng: &rng, master: master)
                picks[team.rawValue][pos.rawValue] = heroID
                let diff = team == humanTeam ? allyDifficulty : enemyDifficulty
                let name = master.hero(heroID)?.codeName ?? heroID
                players.append(PlayerSlot(team: team, heroID: heroID, controller: .bot, position: pos,
                                          spells: defaultSpells(for: pos), runes: [],
                                          displayName: "\(name)_AI", botDifficulty: diff))
            }
        }
        return MatchConfig(mode: mode, seed: seed, players: players)
    }

    /// 全員 AI の 5v5（観戦・テスト用）。
    public static func botMatch(difficulty: Difficulty = .normal, seed: UInt64, master: MasterData = .shared) -> MatchConfig {
        var rng = SplitMix64(seed: seed ^ 0x9E37_79B9)
        var used = Set<String>()
        var picks = draftTeams(used: &used, rng: &rng, master: master, fixed: [])
        var players: [PlayerSlot] = []
        for team in Team.players {
            for pos in LanePosition.allCases {
                let heroID = picks[team.rawValue][pos.rawValue] ?? pickHero(for: pos, used: &used, rng: &rng, master: master)
                picks[team.rawValue][pos.rawValue] = heroID
                let name = master.hero(heroID)?.codeName ?? heroID
                players.append(PlayerSlot(team: team, heroID: heroID, controller: .bot, position: pos,
                                          spells: defaultSpells(for: pos), displayName: "\(name)_AI",
                                          botDifficulty: difficulty))
            }
        }
        return MatchConfig(mode: .spectate, seed: seed, players: players)
    }

    /// 練習場（人間 1 人）。
    public static func practiceMatch(humanHeroID: String, humanName: String, options: PracticeOptions,
                                     tutorial: Bool = false, seed: UInt64, master: MasterData = .shared) -> MatchConfig {
        let role = master.hero(humanHeroID)?.role ?? .duelist
        let pos = defaultPosition(for: role)
        let slot = PlayerSlot(team: .blue, heroID: humanHeroID, controller: .human, position: pos,
                              spells: defaultSpells(for: pos), displayName: humanName)
        return MatchConfig(mode: tutorial ? .tutorial : .practice, seed: seed, players: [slot], practice: options,
                           maxDuration: 60 * 60)
    }

    /// 乱闘（単レーン・ジャングル無し）の 5v5。ジャングルスペル（BS05）は付けず、`humanHeroID` が nil なら
    /// シードからランダムに選ぶ。短縮クロック（15 分）。マップは `MapDefinition.map(for: .brawl)` が担う。
    public static func brawlMatch(humanHeroID: String? = nil, humanName: String,
                                  humanTeam: Team = .blue, humanSpells: [String]? = nil,
                                  humanRunes: [String] = [], humanSkin: String? = nil,
                                  humanPosition: LanePosition? = nil,
                                  allyDifficulty: Difficulty = .normal, enemyDifficulty: Difficulty = .normal,
                                  banned: [String] = [], seed: UInt64,
                                  master: MasterData = .shared) -> MatchConfig {
        var rng = SplitMix64(seed: seed ^ 0xB7A1_55C2_9E3F_1D04)
        var used = Set(banned)
        let humanHero: String = humanHeroID ?? {
            let pool = master.heroes.map(\.heroID).filter { !used.contains($0) }
            return rng.pick(pool) ?? master.heroes[0].heroID
        }()
        used.insert(humanHero)
        let humanPos = humanPosition ?? defaultPosition(for: master.hero(humanHero)?.role ?? .duelist)
        var picks = draftTeams(used: &used, rng: &rng, master: master,
                               fixed: [(humanTeam, humanPos, humanHero)])
        var players: [PlayerSlot] = []
        for team in Team.players {
            for pos in LanePosition.allCases {
                if team == humanTeam && pos == humanPos {
                    players.append(PlayerSlot(team: team, heroID: humanHero, controller: .human, position: pos,
                                              spells: humanSpells ?? ["BS01", "BS03"], runes: humanRunes,
                                              skinID: humanSkin, displayName: humanName))
                    continue
                }
                let heroID = picks[team.rawValue][pos.rawValue] ?? pickHero(for: pos, used: &used, rng: &rng, master: master)
                picks[team.rawValue][pos.rawValue] = heroID
                let diff = team == humanTeam ? allyDifficulty : enemyDifficulty
                let name = master.hero(heroID)?.codeName ?? heroID
                // ジャングルが無いので全員 BS05 無しの汎用スペル。
                players.append(PlayerSlot(team: team, heroID: heroID, controller: .bot, position: pos,
                                          spells: ["BS01", "BS03"], runes: [],
                                          displayName: "\(name)_AI", botDifficulty: diff))
            }
        }
        return MatchConfig(mode: .brawl, seed: seed, players: players, maxDuration: 15 * 60)
    }

    /// カスタム対戦（対 AI、標準マップ）。`humanSide` が nil なら全員 AI。side 別に難易度を指定できる。
    /// 乱闘マップを使いたい場合は呼び出し側で `brawlMatch` を使う（マップは mode から導出するため）。
    public static func customMatch(humanSide: Team? = .blue, humanHeroID: String? = nil, humanName: String = "Player",
                                   humanSpells: [String]? = nil, humanRunes: [String] = [], humanSkin: String? = nil,
                                   humanPosition: LanePosition? = nil,
                                   allyDifficulty: Difficulty = .normal, enemyDifficulty: Difficulty = .normal,
                                   banned: [String] = [], seed: UInt64,
                                   master: MasterData = .shared) -> MatchConfig {
        if let humanSide, let humanHeroID {
            return standardMatch(mode: .custom, humanHeroID: humanHeroID, humanName: humanName,
                                 humanTeam: humanSide, humanSpells: humanSpells, humanRunes: humanRunes,
                                 humanSkin: humanSkin, humanPosition: humanPosition,
                                 allyDifficulty: allyDifficulty, enemyDifficulty: enemyDifficulty,
                                 banned: banned, seed: seed, master: master)
        }
        var rng = SplitMix64(seed: seed ^ 0x51ED_2701_44AB_9CF3)
        var used = Set(banned)
        var picks = draftTeams(used: &used, rng: &rng, master: master, fixed: [])
        var players: [PlayerSlot] = []
        for team in Team.players {
            for pos in LanePosition.allCases {
                let heroID = picks[team.rawValue][pos.rawValue] ?? pickHero(for: pos, used: &used, rng: &rng, master: master)
                picks[team.rawValue][pos.rawValue] = heroID
                let diff = team == .blue ? allyDifficulty : enemyDifficulty
                let name = master.hero(heroID)?.codeName ?? heroID
                players.append(PlayerSlot(team: team, heroID: heroID, controller: .bot, position: pos,
                                          spells: defaultSpells(for: pos), displayName: "\(name)_AI",
                                          botDifficulty: diff))
            }
        }
        return MatchConfig(mode: .custom, seed: seed, players: players)
    }

    /// ポジション順に Blue / Red 交互で AI がピックする。fixed は事前に決まっている枠（人間）。
    /// 戻り値 [Team.rawValue][LanePosition.rawValue]。
    static func draftTeams(used: inout Set<String>, rng: inout SplitMix64, master: MasterData,
                           fixed: [(Team, LanePosition, String)]) -> [[String?]] {
        var picks: [[String?]] = [[String?]](repeating: [String?](repeating: nil, count: LanePosition.allCases.count),
                                             count: 2)
        for (team, pos, id) in fixed where team != .neutral {
            picks[team.rawValue][pos.rawValue] = id
        }
        for pos in LanePosition.allCases {
            for team in Team.players where picks[team.rawValue][pos.rawValue] == nil {
                let allies = picks[team.rawValue].compactMap { $0 }
                let enemies = picks[team.opponent.rawValue].compactMap { $0 }
                let available = master.heroes.map(\.heroID).filter { !used.contains($0) }
                guard !available.isEmpty else { continue }
                let id = DraftAI.draftPick(available: available, allyPicks: allies, enemyPicks: enemies,
                                           position: pos, rng: &rng, master: master)
                guard !id.isEmpty else { continue }
                used.insert(id)
                picks[team.rawValue][pos.rawValue] = id
            }
        }
        return picks
    }

    /// ポジション適性のみでの抽選（DraftAI が候補を返せない時の予備）。
    static func pickHero(for pos: LanePosition, used: inout Set<String>, rng: inout SplitMix64,
                         master: MasterData) -> String {
        for role in preferredRoles(for: pos) {
            let pool = master.heroes(role: role).map(\.heroID).filter { !used.contains($0) }
            if let h = rng.pick(pool) {
                used.insert(h)
                return h
            }
        }
        let pool = master.heroes.map(\.heroID).filter { !used.contains($0) }
        let h = rng.pick(pool) ?? master.heroes[0].heroID
        used.insert(h)
        return h
    }
}
