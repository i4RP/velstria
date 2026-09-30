import Foundation

// 担当: core-bots
// ジャングル（DESIGN §10: ポジション jungle・狩猟印 BS05）: 0:30 から自陣キャンプを効率よく回り、
// バフ・ボスに狩猟印、敵レーナーが弱っている/出過ぎていて経路が短ければガンク。オブジェクトは BotMacro のチーム方針。

enum BotJungle {
    static func act(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                    _ mem: inout BotHeroMemory) {
        if gank(&s, ctx, w, &a, &mem) { return }
        if let camp = chooseCamp(s, ctx, w, a, mem) {
            clearCamp(&s, ctx, w, &a, &mem, camp: camp)
            return
        }
        // 回れるキャンプが無い: 近いレーンを手伝う（ウェーブを押して経験値・Gold）
        mem.campID = nil
        BotAI.setGoal(&mem, .roaming, s.time)
        BotLaning.act(&s, ctx, w, &a, &mem, lane: assistLane(s, ctx, w, a), mode: .push)
    }

    // MARK: - キャンプ

    /// 次に向かう自陣キャンプ（出現中、または到着までに湧くもの）。バフを優先し、敵が見えるキャンプは避ける。
    static func chooseCamp(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ a: BotAgent,
                           _ mem: BotHeroMemory) -> CampSpot? {
        let speed = max(150, MovementSystem.currentMoveSpeed(s, a.i))
        var best: CampSpot?
        var bestScore = Double.infinity
        for camp in ctx.map.camps where camp.side == a.team {
            let respawnAt = camp.id < s.world.campRespawnAt.count ? s.world.campRespawnAt[camp.id] : nil
            let dist = a.pos.distance(to: camp.pos)
            let travel = dist / speed
            var wait = 0.0
            if let at = respawnAt {
                wait = max(0, at - s.time - travel)
                if wait > 8 { continue }
            }
            // 敵ヒーローが居座っているキャンプは避ける
            if a.enemies.contains(where: { $0.pos.distanceSquared(to: camp.pos) < 1000 * 1000 }) { continue }
            var score = dist + wait * speed
            if camp.kind == .blueSentinel || camp.kind == .redSentinel { score -= 900 }
            // 向かっている途中のキャンプを優先（行ったり来たりを防ぐ）
            if mem.campID == camp.id { score -= 1200 }
            if score < bestScore {
                bestScore = score
                best = camp
            }
        }
        return best
    }

    static func clearCamp(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                          _ mem: inout BotHeroMemory, camp: CampSpot) {
        BotAI.setGoal(&mem, .jungling, s.time)
        mem.campID = camp.id
        let dist = a.pos.distance(to: camp.pos)
        if dist > Balance.Bot.campEngageRadius {
            // キャンプの手前（自陣側）へ
            let approach = camp.pos + (ctx.map.fountain(a.team) - camp.pos).normalized * 250
            BotAI.move(s, ctx, &a, &mem, to: approach)
            return
        }
        var monsters: [Int] = []
        for m in w.monsters where s.units[m].monster?.campID == camp.id && s.isVisible(m, to: a.team) {
            if s.units[m].monster?.leashing == true { continue }
            monsters.append(m)
        }
        guard let target = campTarget(s, monsters) else {
            // まだ湧いていない: 手前で待つ
            let approach = camp.pos + (ctx.map.fountain(a.team) - camp.pos).normalized * 250
            BotAI.move(s, ctx, &a, &mem, to: approach)
            return
        }
        let buff = camp.kind == .blueSentinel || camp.kind == .redSentinel
        let largeLow = s.units[a.i].hpRatio < 0.45 && s.units[target].monster?.kind == .campLarge
        if buff || largeLow { _ = smite(&s, ctx, &a, target) }
        BotCombat.castFarmSkills(&s, ctx, &a, &mem, targets: monsters, minCluster: 1)
        BotAI.attack(s, &a, &mem, target)
    }

    /// キャンプ内の攻撃順: 小型（HP の低い方）→ 大型。
    static func campTarget(_ s: SimState, _ monsters: [Int]) -> Int? {
        var best: Int?
        var bestHP = Double.infinity
        for m in monsters where s.units[m].isAlive && s.units[m].hp < bestHP {
            bestHP = s.units[m].hp
            best = m
        }
        return best
    }

    /// 狩猟印（BS05）: 範囲内で確定ダメージで倒せるなら撃つ。撃ったら true。
    @discardableResult
    static func smite(_ s: inout SimState, _ ctx: SimContext, _ a: inout BotAgent, _ target: Int) -> Bool {
        guard let h = s.units[a.i].hero, let idx = h.spells.firstIndex(of: Balance.Economy.smiteSpellID),
              SpellSystem.canCast(s, ctx, heroIndex: a.i, spellIndex: idx) else { return false }
        let damage = Balance.Bot.smiteBase + Balance.Bot.smitePerLevel * Double(h.level)
        let r = Balance.Bot.smiteRange + s.units[target].radius
        guard s.units[target].hp <= damage, s.units[target].pos.distanceSquared(to: a.pos) <= r * r else { return false }
        a.emit(.castSpell(index: idx, target: .unit(s.units[target].id)))
        return true
    }

    /// 手伝うレーン: 自陣に近い敵ウェーブがあるレーン、無ければ最寄りのレーン。
    static func assistLane(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ a: BotAgent) -> Lane {
        var best = ctx.map.nearestLane(to: a.pos).lane
        var bestScore = Double.infinity
        for lane in Lane.allCases {
            let d = BotLane.blueProgress(ctx.map, lane, a.pos).distance
            var score = d
            if let ef = w.visibleEnemyFront(team: a.team, lane: lane) {
                // 自陣深くまで来ている敵ウェーブを優先
                score += ef.progress * 0.4 - 800
            }
            if score < bestScore {
                bestScore = score
                best = lane
            }
        }
        return best
    }

    // MARK: - ガンク

    /// ガンク: 対象を追いかける。新しい対象の評価は 2 秒毎。行動したら true。
    static func gank(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                     _ mem: inout BotHeroMemory) -> Bool {
        let intel = s.bots.teams[a.team.rawValue]
        if let gid = mem.gankTargetID {
            guard let k = intel.slot(of: gid), let e = s.index(of: gid), s.units[e].isAlive,
                  s.time - mem.gankStart < Balance.Bot.gankTimeout,
                  s.time - intel.lastSeenTime[k] < 4,
                  s.units[a.i].hpRatio > 0.4,
                  w.enemyStructure(covering: intel.lastSeenPos[k], team: a.team, margin: 100) == nil else {
                mem.gankTargetID = nil
                return false
            }
            BotAI.setGoal(&mem, .roaming, s.time)
            BotAI.move(s, ctx, &a, &mem, to: cutOff(ctx, w, a, target: intel.lastSeenPos[k]))
            return true
        }
        guard s.time >= 150, s.units[a.i].hpRatio > 0.6, s.time - mem.gankStart >= 2 else { return false }
        // 対象の評価（チームが今見ている敵のみ）
        var best: Int?
        var bestScore = Double.infinity
        for k in intel.enemyIDs.indices where intel.visibleSince[k] >= 0 {
            guard let e = s.index(of: intel.enemyIDs[k]) else { continue }
            let p = s.units[e].pos
            let lane = ctx.map.nearestLane(to: p)
            guard lane.distance < 800 else { continue }
            let d = p.distance(to: a.pos)
            guard d < 3600 else { continue }
            guard w.enemyStructure(covering: p, team: a.team, margin: 200) == nil else { continue }
            let ratio = s.units[e].hpRatio
            let ownTower = w.frontTower(team: a.team, lane: lane.lane)
            let ownProg = ownTower.map { BotLane.progress(ctx.map, lane.lane, team: a.team, $0.pos) } ?? 700
            // 自陣側に出過ぎている（レーン中央より手前、または味方の塔に近い）
            let prog = BotLane.progress(ctx.map, lane.lane, team: a.team, p)
            let overextended = prog < ownProg + 1300 || prog < w.laneLength[lane.lane.rawValue] * 0.5
            guard ratio < 0.7 || overextended else { continue }
            // 味方のレーナーが近くに居ること
            var support = false
            for h in w.heroes where s.units[h].team == a.team && h != a.i && s.units[h].isAlive {
                if s.units[h].pos.distanceSquared(to: p) < 1500 * 1500 { support = true }
            }
            guard support else { continue }
            let score = d + ratio * 1500
            if score < bestScore {
                bestScore = score
                best = k
            }
        }
        mem.gankStart = s.time
        guard let k = best, let e = s.index(of: intel.enemyIDs[k]) else { return false }
        let path = ctx.nav.findPath(from: a.pos, to: s.units[e].pos, radius: Balance.heroRadius)
        var length = 0.0
        var prev = a.pos
        for q in path {
            length += prev.distance(to: q)
            prev = q
        }
        guard !path.isEmpty, length <= Balance.Bot.gankMaxPath else { return false }
        mem.gankTargetID = intel.enemyIDs[k]
        BotAI.setGoal(&mem, .roaming, s.time)
        BotAI.move(s, ctx, &a, &mem, to: cutOff(ctx, w, a, target: s.units[e].pos))
        return true
    }

    /// ガンクの接近先: 遠いうちは対象の退路側（敵の塔の方向）へ回り込み、近づいたら対象そのもの。
    static func cutOff(_ ctx: SimContext, _ w: BotWorld, _ a: BotAgent, target p: Vec2) -> Vec2 {
        guard a.pos.distance(to: p) > 900 else { return p }
        let lane = ctx.map.nearestLane(to: p).lane
        let prog = BotLane.progress(ctx.map, lane, team: a.team, p)
        // 相手の退路 = こちら視点で進行度が大きい方向
        return BotLane.point(ctx.map, lane, team: a.team, progress: prog + 450)
    }
}
