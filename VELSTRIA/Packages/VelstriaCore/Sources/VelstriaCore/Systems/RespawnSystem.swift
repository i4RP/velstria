import Foundation

// 担当: core-economy
// 死亡中タイマーの進行と泉での復活（DESIGN §8）。

public enum RespawnSystem {
    /// 復活までの秒数: 3.2 + 2.1 × Lv + 試合時間（分。切り捨て）、上限 90 秒（MLBB 1.4.86 の式。docs/TOWER_BASE_MLBB.md）。
    /// 18:00 から大きく伸びる（量は資料に無いので、18 分を越えた分は 1 分につき 2 秒にした）。買い戻しは無い。
    public static func respawnTime(level: Int, time: Double) -> Double {
        let minutes = (max(0, time) / 60 + 1e-9).rounded(.down)
        let late = Balance.respawnLateGameTime / 60
        let timeTerm = minutes <= late ? minutes * Balance.respawnPerMinute
            : late * Balance.respawnPerMinute + (minutes - late) * Balance.respawnLateGamePerMinute
        let t = Balance.respawnBase + Balance.respawnPerLevel * Double(level) + timeTerm
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
