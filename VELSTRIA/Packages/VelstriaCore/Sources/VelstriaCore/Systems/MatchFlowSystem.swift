import Foundation

// 担当: core-economy（最小実装。降参投票・時間切れ判定・Ace 告知を実装すること）

public struct SurrenderState: Codable, Hashable, Sendable {
    /// index = Team.rawValue。投票中なら締切時刻。
    public var voteDeadline: [Double?] = [nil, nil]
    /// index = Team.rawValue。次に提案可能な時刻。
    public var nextAllowed: [Double] = [Balance.surrenderUnlockTime, Balance.surrenderUnlockTime]

    public init() {}
}

public enum MatchFlowSystem {
    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        guard s.phase == .playing else { return }
        for core in s.units where core.kind == .core && !core.isAlive {
            end(&s, winner: core.team.opponent, reason: .coreDestroyed)
            return
        }
        if s.time >= ctx.config.maxDuration {
            end(&s, winner: nil, reason: .timeLimit)
        }
    }

    public static func vote(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, yes: Bool) {
        s.units[i].hero?.surrenderVote = yes
    }

    public static func end(_ s: inout SimState, winner: Team?, reason: EndReason) {
        guard s.phase != .ended else { return }
        s.phase = .ended
        s.winner = winner
        s.endReason = reason
        if let w = winner { s.emit(.announcement(.victory(team: w))) }
        s.emit(.matchEnded(winner: winner, reason: reason))
    }
}
