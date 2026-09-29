import Foundation

// 担当: core-economy
// 帰還（全員共通）と帰還門（BS09）の詠唱・中断・転移（DESIGN §7）。
// 到着時の回復は行わない（泉の回復は EconomySystem が担当）。

public enum RecallSystem {
    /// 帰還の詠唱時間（巨像の加護中は短縮）。
    public static func recallDuration(_ u: Unit) -> Double {
        u.has(.colossusBlessing) ? Balance.empoweredRecallChannel : Balance.recallChannel
    }

    public static func startRecall(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard s.units[i].kind == .hero, s.units[i].isAlive, let h = s.units[i].hero, !h.isDead,
              h.channel == nil, s.units[i].canAct else { return }
        let duration = recallDuration(s.units[i])
        // 到着地点は泉の中でチーム内の並び順に散らす（復活と同じ配置。全員が泉の中心 1 点に重ならない）
        let destination = RespawnSystem.respawnPosition(s, ctx, heroIndex: i)
        s.units[i].hero?.channel = Channel(kind: .recall, duration: duration, target: destination)
        s.units[i].moveIntent = .none
        s.units[i].path = []
        s.units[i].attackTargetID = nil
        s.units[i].windupRemaining = nil
        s.emit(.channelStarted(heroID: s.units[i].id, kind: .recall, duration: duration))
    }

    /// 帰還門（BS09）の転移先を検証する。味方の生存タワーから 400 以内、または味方の泉の中なら
    /// 実際の到着地点（構造物の衝突半径の外・歩行可能点）を返し、無効なら nil。
    /// SpellSystem はクールダウン消費前にこれで確認できる。
    public static func teleportDestination(_ s: SimState, _ ctx: SimContext, heroIndex i: Int,
                                           requested: Vec2) -> Vec2? {
        let team = s.units[i].team
        guard team != .neutral else { return nil }
        let radius = s.units[i].radius
        if ctx.map.isInFountain(requested, team: team) {
            return ctx.nav.nearestWalkable(requested, radius: radius)
        }
        let r = Balance.Economy.teleportTowerRadius
        var best: Int?
        var bestD = Double.infinity
        for k in s.units.indices {
            let u = s.units[k]
            guard u.kind == .tower, u.team == team, u.isAlive else { continue }
            let d = u.pos.distanceSquared(to: requested)
            if d <= r * r, d < bestD {
                bestD = d
                best = k
            }
        }
        guard let t = best else { return nil }
        // タワーに重ならないよう、衝突半径の外へ押し出す（真上指定なら自陣の泉側へ）
        let tower = s.units[t]
        let minDist = tower.radius + radius + 10
        var dest = requested
        if dest.distance(to: tower.pos) < minDist {
            var dir = (dest - tower.pos).normalized
            if dir == .zero { dir = (ctx.map.fountain(team) - tower.pos).normalized }
            if dir == .zero { dir = Vec2(1, 0) }
            dest = tower.pos + dir * minDist
        }
        return ctx.nav.nearestWalkable(dest, radius: radius)
    }

    /// 帰還門（BS09）の詠唱開始。SpellSystem から呼ばれる。転移先が無効なら開始せず .channelCanceled を発行する。
    public static func startTeleport(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, destination: Vec2,
                                     duration: Double) {
        guard s.units[i].kind == .hero, s.units[i].isAlive, s.units[i].hero?.isDead == false else { return }
        guard let dest = teleportDestination(s, ctx, heroIndex: i, requested: destination) else {
            s.emit(.channelCanceled(heroID: s.units[i].id, kind: .teleport))
            return
        }
        if s.units[i].hero?.channel != nil { cancelChannel(&s, i) }
        s.units[i].hero?.channel = Channel(kind: .teleport, duration: duration, target: dest)
        s.units[i].moveIntent = .none
        s.units[i].path = []
        s.units[i].attackTargetID = nil
        s.units[i].windupRemaining = nil
        s.emit(.channelStarted(heroID: s.units[i].id, kind: .teleport, duration: duration))
    }

    /// 詠唱中なら中断（移動・攻撃・スキル・被ダメで呼ばれる）。
    public static func cancelChannel(_ s: inout SimState, _ i: Int) {
        guard let ch = s.units[i].hero?.channel else { return }
        s.units[i].hero?.channel = nil
        s.emit(.channelCanceled(heroID: s.units[i].id, kind: ch.kind))
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        for i in s.units.indices where s.units[i].kind == .hero {
            guard var ch = s.units[i].hero?.channel else { continue }
            if !s.units[i].isAlive || s.units[i].hero?.isDead == true {
                s.units[i].hero?.channel = nil
                continue
            }
            // 詠唱開始以降に被ダメ、または行動不能 CC・強制移動を受けたら中断
            let started = s.time - (ch.total - ch.remaining)
            if s.units[i].lastDamagedTime >= started - Balance.dt * 0.5
                || !s.units[i].canAct || s.units[i].displacement != nil {
                cancelChannel(&s, i)
                continue
            }
            ch.remaining -= Balance.dt
            guard ch.remaining <= 1e-9 else {
                s.units[i].hero?.channel = ch
                continue
            }
            let dest: Vec2
            if ch.kind == .teleport {
                // 転移先のタワーが詠唱中に破壊されていたら失敗
                guard let d = teleportDestination(s, ctx, heroIndex: i, requested: ch.target ?? s.units[i].pos) else {
                    cancelChannel(&s, i)
                    continue
                }
                dest = d
            } else {
                dest = ctx.nav.nearestWalkable(ch.target ?? ctx.map.fountain(s.units[i].team),
                                               radius: s.units[i].radius)
            }
            s.units[i].hero?.channel = nil
            s.units[i].pos = dest
            s.units[i].prevPos = dest
            s.units[i].moveIntent = .none
            s.units[i].path = []
            s.units[i].attackTargetID = nil
            s.emit(.channelCompleted(heroID: s.units[i].id, kind: ch.kind, destination: dest))
        }
    }
}
