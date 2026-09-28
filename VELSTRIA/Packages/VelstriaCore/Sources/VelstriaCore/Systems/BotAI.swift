import Foundation

// 担当: core-bots（Wave 2）。現在はスタブ（ボットはレーンへ歩いて近くの敵を殴るだけ）。

/// ボット全体の記憶（ヒーロー毎の状態）。
public struct BotState: Codable, Hashable, Sendable {
    public init() {}
}

public enum BotAI {
    /// controller == .bot のヒーローのコマンドを生成する。
    public static func generateCommands(_ s: inout SimState, _ ctx: SimContext) -> [HeroCommand] {
        var out: [HeroCommand] = []
        // 5Hz・ヒーロー毎にずらす
        for i in s.heroIndices {
            let u = s.units[i]
            guard let h = u.hero, h.controller == .bot, !h.isDead, u.isAlive else { continue }
            guard (s.tick + i) % 6 == 0 else { continue }
            let lane: Lane = h.position == .top ? .top : (h.position == .mid || h.position == .jungle ? .mid : .bot)
            let near = s.enemies(of: u.team, near: u.pos, radius: u.stats.attackRange + 400)
            if let t = s.nearest(near, to: u.pos) {
                out.append(HeroCommand(heroID: u.id, command: .attack(targetID: s.units[t].id)))
            } else {
                let path = ctx.map.lanePath(lane, for: u.team)
                let goal = path[min(2, path.count - 1)]
                out.append(HeroCommand(heroID: u.id, command: .moveTo(point: goal)))
            }
        }
        return out
    }
}
