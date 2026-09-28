import Foundation

// 担当: 統合（契約）。core-bots が DraftAI で置き換え可能（シグネチャ維持）。

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
        var players: [PlayerSlot] = []
        for team in Team.players {
            for pos in LanePosition.allCases {
                if team == humanTeam && pos == humanPos {
                    players.append(PlayerSlot(team: team, heroID: humanHeroID, controller: .human, position: pos,
                                              spells: humanSpells ?? defaultSpells(for: pos), runes: humanRunes,
                                              skinID: humanSkin, displayName: humanName))
                    continue
                }
                let heroID = pickHero(for: pos, used: &used, rng: &rng, master: master)
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
        var players: [PlayerSlot] = []
        for team in Team.players {
            for pos in LanePosition.allCases {
                let heroID = pickHero(for: pos, used: &used, rng: &rng, master: master)
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
