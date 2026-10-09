import Foundation

// 担当: core-economy
// 死亡中タイマーの進行と泉での復活（DESIGN §8）。

public enum RespawnSystem {
    /// DESIGN §8: 4 + 2×Lv 秒、12:00 以降 ×1.25、上限 40 秒。
    public static func respawnTime(level: Int, time: Double) -> Double {
        var t = Balance.respawnBase + Balance.respawnPerLevel * Double(level)
        if time >= Balance.respawnLateGameTime { t *= Balance.respawnLateGameMultiplier }
        return min(Balance.respawnMax, t)
    }

    /// 復活地点（泉の中でチーム内の並び順に扇状に散らす。試合開始時の配置と同じ並び）。
    public static func respawnPosition(_ s: SimState, _ ctx: SimContext, heroIndex i: Int) -> Vec2 {
        let team = s.units[i].team
        let order = s.heroIndices(team: team).firstIndex(of: i) ?? 0
        let angle = Double(order) * (Double.pi / 2) / 4
        let dir: Double = team == .red ? -1 : 1
        let p = ctx.map.fountain(team) + Vec2(cos(angle) * 300 * dir, sin(angle) * 300 * dir)
        return ctx.nav.nearestWalkable(p, radius: s.units[i].radius)
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        for i in s.units.indices where s.units[i].kind == .hero {
            guard let h = s.units[i].hero, h.respawnTimer > 0 else { continue }
            let t = h.respawnTimer - Balance.dt
            guard t <= 1e-9 else {
                s.units[i].hero!.respawnTimer = t
                continue
            }
            // イモータルの復活は倒れた場所
            let pos = ItemEffects.revivePosition(s, heroIndex: i) ?? respawnPosition(s, ctx, heroIndex: i)
            s.units[i].hero!.respawnTimer = 0
            s.units[i].hero!.channel = nil
            s.units[i].hero!.empoweredAttack = nil
            s.units[i].pos = pos
            s.units[i].prevPos = pos
            s.units[i].facing = s.units[i].team == .red ? -3 * Double.pi / 4 : Double.pi / 4
            s.units[i].isAlive = true
            s.units[i].deathTime = nil
            s.units[i].statuses.removeAll()
            s.units[i].shields.removeAll()
            s.units[i].displacement = nil
            s.units[i].moveIntent = .none
            s.units[i].path = []
            s.units[i].attackTargetID = nil
            s.units[i].windupRemaining = nil
            s.units[i].attackCooldown = 0
            // 死亡中のレベルアップ・装備購入を反映してから全快
            StatCalculator.recompute(&s, i, ctx)
            s.units[i].hp = s.units[i].stats.maxHP
            s.units[i].resource = s.units[i].stats.maxResource
            ItemEffects.afterRespawn(&s, ctx, heroIndex: i)
            s.emit(.respawned(heroID: s.units[i].id, pos: pos))
        }
    }
}
