import Foundation

// 担当: core-economy（最小実装。キル/アシスト・バウンティ・連続キル・告知・XP 分配・オブジェクト報酬を実装すること）

public enum DeathSystem {
    public static func process(_ s: inout SimState, _ ctx: SimContext) {
        let deaths = s.pendingDeaths
        s.pendingDeaths.removeAll()
        for d in deaths {
            guard let v = s.index(of: d.victimID) else { continue }
            let victim = s.units[v]
            s.emit(.unitDied(unitID: victim.id, kind: victim.kind, team: victim.team, killerID: d.killerID, pos: victim.pos))
            switch victim.kind {
            case .hero:
                s.units[v].hero?.respawnTimer = RespawnSystem.respawnTime(level: victim.hero?.level ?? 1, time: s.time)
                s.units[v].hero?.score.deaths += 1
                s.units[v].attackTargetID = nil
                s.units[v].moveIntent = .none
                if let k = s.index(of: d.killerID), s.units[k].kind == .hero {
                    s.units[k].hero?.gold += Balance.heroKillBounty
                    s.units[k].hero?.score.kills += 1
                    s.teams[s.units[k].team.rawValue].kills += 1
                }
            case .minion:
                if let k = s.index(of: d.killerID), s.units[k].kind == .hero {
                    let gold: Double = victim.minion?.type == .siege ? 50 : (victim.minion?.type == .ranged ? 16 : 22)
                    s.units[k].hero?.gold += gold
                    s.units[k].hero?.score.minionKills += 1
                    s.emit(.goldGained(heroID: s.units[k].id, amount: gold, pos: victim.pos))
                }
            case .tower, .core:
                s.teams[victim.team.opponent.rawValue].towersDestroyed += 1
                s.emit(.structureDestroyed(unitID: victim.id, kind: victim.kind, team: victim.team,
                                           lane: victim.tower?.lane, tier: victim.tower?.tier, killerID: d.killerID))
            case .monster, .dummy:
                break
            }
        }
    }
}
