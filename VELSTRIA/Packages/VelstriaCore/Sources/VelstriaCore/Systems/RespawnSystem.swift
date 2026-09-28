import Foundation

// 担当: core-economy（最小実装）

public enum RespawnSystem {
    /// DESIGN §8: 4 + 2×Lv 秒、12:00 以降 ×1.25、上限 40 秒。
    public static func respawnTime(level: Int, time: Double) -> Double {
        var t = Balance.respawnBase + Balance.respawnPerLevel * Double(level)
        if time >= Balance.respawnLateGameTime { t *= Balance.respawnLateGameMultiplier }
        return min(Balance.respawnMax, t)
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        for i in s.units.indices where s.units[i].kind == .hero {
            guard let h = s.units[i].hero, h.respawnTimer > 0 else { continue }
            let t = h.respawnTimer - Balance.dt
            if t <= 0 {
                s.units[i].hero?.respawnTimer = 0
                let pos = ctx.map.fountain(s.units[i].team)
                s.units[i].pos = pos
                s.units[i].prevPos = pos
                s.units[i].isAlive = true
                s.units[i].deathTime = nil
                s.units[i].hp = s.units[i].stats.maxHP
                s.units[i].resource = s.units[i].stats.maxResource
                s.units[i].statuses.removeAll()
                s.units[i].shields.removeAll()
                s.units[i].displacement = nil
                s.units[i].moveIntent = .none
                s.units[i].attackTargetID = nil
                s.emit(.respawned(heroID: s.units[i].id, pos: pos))
            } else {
                s.units[i].hero?.respawnTimer = t
            }
        }
    }
}
