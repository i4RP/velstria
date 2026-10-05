import Foundation

// 担当: core-economy
// 勝敗（Core 破壊・降参・時間切れ）と降参投票（DESIGN §3）。

public struct SurrenderState: Codable, Hashable, Sendable {
    /// index = Team.rawValue。投票中なら締切時刻。
    public var voteDeadline: [Double?] = [nil, nil]
    /// index = Team.rawValue。次に提案可能な時刻。
    public var nextAllowed: [Double] = [Balance.surrenderUnlockTime, Balance.surrenderUnlockTime]

    public init() {}

    public func isVoting(_ team: Team) -> Bool {
        team != .neutral && voteDeadline[team.rawValue] != nil
    }
}

/// 降参投票の集計（HUD 表示用）。
public struct SurrenderTally: Hashable, Sendable {
    public var yes: Int
    public var no: Int
    /// 未投票。
    public var pending: Int
    /// 成立に必要な賛成数。
    public var needed: Int

    public init(yes: Int, no: Int, pending: Int, needed: Int) {
        self.yes = yes
        self.no = no
        self.pending = pending
        self.needed = needed
    }
}

public enum MatchFlowSystem {
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        guard s.phase == .playing else { return }
        // Core 破壊（添字順 = 決定論。同 tick 相打ちは Blue Core 側を先に判定）
        for i in s.units.indices where s.units[i].kind == .core && !s.units[i].isAlive {
            let team = s.units[i].team
            guard team != .neutral else { continue }
            end(&s, winner: team.opponent, reason: .coreDestroyed)
            return
        }
        // 降参投票の進行（AI 味方の投票・締切）
        for team in Team.players where s.surrender.isVoting(team) {
            castBotVotes(&s, ctx, team: team)
            resolveVote(&s, ctx, team: team)
            if s.phase != .playing { return }
        }
        // 時間切れ: 破壊タワー数 → キル数 → 引き分け
        if s.time >= ctx.config.maxDuration {
            end(&s, winner: timeLimitWinner(s), reason: .timeLimit)
        }
    }

    /// 時間切れ時の勝者（タワー破壊数、同数ならキル数。どちらも同じなら nil）。
    public static func timeLimitWinner(_ s: SimState) -> Team? {
        let b = s.teams[Team.blue.rawValue], r = s.teams[Team.red.rawValue]
        if b.towersDestroyed != r.towersDestroyed { return b.towersDestroyed > r.towersDestroyed ? .blue : .red }
        if b.kills != r.kills { return b.kills > r.kills ? .blue : .red }
        return nil
    }

    // MARK: - 降参

    /// 降参が使えるモードか（人間がいる対 AI 戦のみ。練習場・チュートリアル・観戦は不可）。
    public static func surrenderEnabled(_ ctx: SimContext) -> Bool {
        switch ctx.config.mode {
        case .standard, .ranked, .brawl:
            return true
        case .custom:
            // カスタムは人間がいるときだけ降参可（全 AI 観戦相当では不可）。
            return ctx.config.humanSlot != nil
        case .practice, .tutorial, .spectate, .magicChess:
            return false
        }
    }

    /// team が今、降参を提案できるか（HUD のボタン活性）。
    public static func canProposeSurrender(_ s: SimState, _ ctx: SimContext, team: Team) -> Bool {
        guard s.phase == .playing, surrenderEnabled(ctx), team != .neutral else { return false }
        return !s.surrender.isVoting(team) && s.time >= s.surrender.nextAllowed[team.rawValue]
    }

    /// 成立に必要な賛成数（過半数。5 人なら 3）。
    public static func votesNeeded(_ s: SimState, team: Team) -> Int {
        s.heroIndices(team: team).count / 2 + 1
    }

    public static func tally(_ s: SimState, team: Team) -> SurrenderTally {
        var yes = 0, no = 0, pending = 0
        for i in s.heroIndices(team: team) {
            switch s.units[i].hero?.surrenderVote {
            case true?: yes += 1
            case false?: no += 1
            case nil: pending += 1
            }
        }
        return SurrenderTally(yes: yes, no: no, pending: pending, needed: votesNeeded(s, team: team))
    }

    /// AI 味方が賛成する条件: チームゴールド差 ≥ 3000 または タワー差 ≥ 3（相手が上回っている）。
    public static func botWantsSurrender(_ s: SimState, team: Team) -> Bool {
        guard team != .neutral else { return false }
        let enemy = team.opponent
        let goldDeficit = EconomyRewards.teamGoldEarned(s, team: enemy) - EconomyRewards.teamGoldEarned(s, team: team)
        let towerDeficit = s.teams[enemy.rawValue].towersDestroyed - s.teams[team.rawValue].towersDestroyed
        return goldDeficit >= Balance.Economy.surrenderGoldDeficit || towerDeficit >= Balance.Economy.surrenderTowerDeficit
    }

    /// 降参投票。人間の賛成で投票開始（8:00 以降・CD 明け）、投票中は各ヒーロー 1 票。
    public static func vote(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, yes: Bool) {
        guard s.phase == .playing, surrenderEnabled(ctx), let h = s.units[i].hero else { return }
        let team = s.units[i].team
        guard team != .neutral else { return }

        if !s.surrender.isVoting(team) {
            // 開始できるのは人間の賛成のみ
            guard h.controller == .human, yes, s.time >= s.surrender.nextAllowed[team.rawValue] else { return }
            for k in s.heroIndices(team: team) { s.units[k].hero?.surrenderVote = nil }
            s.surrender.voteDeadline[team.rawValue] = s.time + Balance.Economy.surrenderVoteDuration
            s.units[i].hero?.surrenderVote = true
            emitTally(&s, team: team)
            resolveVote(&s, ctx, team: team)
            return
        }
        guard h.surrenderVote == nil else { return }
        // AI は条件を満たす時だけ賛成できる
        let v = h.controller == .bot ? (yes && botWantsSurrender(s, team: team)) : yes
        s.units[i].hero?.surrenderVote = v
        emitTally(&s, team: team)
        resolveVote(&s, ctx, team: team)
    }

    /// 投票開始から順に（チーム内の添字順で botVoteInterval ずつ遅らせて）AI 味方が投票する。
    static func castBotVotes(_ s: inout SimState, _ ctx: SimContext, team: Team) {
        guard let deadline = s.surrender.voteDeadline[team.rawValue] else { return }
        let start = deadline - Balance.Economy.surrenderVoteDuration
        var order = 0
        for i in s.heroIndices(team: team) where s.units[i].hero?.controller == .bot {
            defer { order += 1 }
            guard s.units[i].hero?.surrenderVote == nil else { continue }
            let at = start + Balance.Economy.botVoteDelay + Balance.Economy.botVoteInterval * Double(order)
            guard s.time >= at - 1e-9 else { continue }
            let wants = botWantsSurrender(s, team: team)
            s.units[i].hero?.surrenderVote = wants
            emitTally(&s, team: team)
        }
    }

    /// 成立（賛成 ≥ 必要数）/ 不成立（届かないことが確定、または締切）を判定する。
    static func resolveVote(_ s: inout SimState, _ ctx: SimContext, team: Team) {
        guard let deadline = s.surrender.voteDeadline[team.rawValue] else { return }
        let t = tally(s, team: team)
        if t.yes >= t.needed {
            clearVote(&s, team: team)
            s.emit(.announcement(.surrenderPassed(team: team)))
            end(&s, winner: team.opponent, reason: .surrender)
            return
        }
        if t.yes + t.pending < t.needed || s.time >= deadline - 1e-9 {
            clearVote(&s, team: team)
            s.surrender.nextAllowed[team.rawValue] = s.time + Balance.surrenderCooldown
            // 締切時の未投票は反対扱いで最終結果を通知
            s.emit(.surrenderVote(team: team, yes: t.yes, no: t.no + t.pending, needed: t.needed))
        }
    }

    static func clearVote(_ s: inout SimState, team: Team) {
        s.surrender.voteDeadline[team.rawValue] = nil
        for k in s.heroIndices(team: team) { s.units[k].hero?.surrenderVote = nil }
    }

    static func emitTally(_ s: inout SimState, team: Team) {
        let t = tally(s, team: team)
        s.emit(.surrenderVote(team: team, yes: t.yes, no: t.no, needed: t.needed))
    }

    // MARK: - 終了

    public static func end(_ s: inout SimState, winner: Team?, reason: EndReason) {
        guard s.phase != .ended else { return }
        s.phase = .ended
        s.winner = winner
        s.endReason = reason
        for team in Team.players { s.surrender.voteDeadline[team.rawValue] = nil }
        if let w = winner { s.emit(.announcement(.victory(team: w))) }
        s.emit(.matchEnded(winner: winner, reason: reason))
    }
}
