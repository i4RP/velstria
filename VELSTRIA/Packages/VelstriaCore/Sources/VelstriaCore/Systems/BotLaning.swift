import Foundation

// 担当: core-bots
// レーン戦（DESIGN §10）: 味方ウェーブの後ろで待機、ラストヒット（他ユニットの攻撃を予測）、有利な時のハラス、
// 敵タワーの射程を尊重（味方ミニオンが狙われている間だけ入る）、敵ウェーブが多ければ下がる、サポートはキャリーに付く。

/// レーンでの振る舞い。
enum BotLaneMode: Equatable {
    /// 通常のレーン戦（ラストヒット優先）。
    case farm
    /// ウェーブを押してタワーを削る。
    case push
    /// 押し切り（人数有利）。ミニオンが居なくても構造物を叩く。
    case siege
    /// 自軍タワーを守る。
    case defend
}

/// ラストヒットの見積もり。
struct BotLastHit {
    /// 今攻撃すれば取れるミニオン。
    var now: Int?
    /// 次の攻撃間隔のうちに取れそうなミニオンがある（他を殴らず待つ）。
    var soon: Bool
}

enum BotLaning {
    static func act(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                    _ mem: inout BotHeroMemory, lane: Lane, mode: BotLaneMode) {
        let team = a.team
        let map = ctx.map
        let i = a.i
        let range = s.units[i].stats.attackRange
        let myIDs = w.heroes.filter { s.units[$0].team == team }.map { s.units[$0].id }

        // 敵の最前タワー（レーンの塔が全滅なら Core）
        let enemyTower = w.frontTower(team: team.opponent, lane: lane) ?? w.core(of: team.opponent)
        let tanked = enemyTower.map { w.isTowerTanked($0, by: team, heroIDs: myIDs) } ?? false
        let enemyHeroesNear = a.enemies.contains { $0.distance < 1100 } || a.ghosts.contains { $0.distance < 900 }
        let laneEmpty = isLaneEmpty(s, a, lane: lane, map: map)

        // 前隙中の攻撃は中断しない（移動コマンドは攻撃を取り消してしまう）
        if s.units[i].windupRemaining != nil, s.units[i].attackTargetID != nil { return }
        if mode == .siege, siege(&s, ctx, w, &a, &mem, lane: lane) { return }

        // 1. ラストヒット
        let isSupport = a.position == .support && carryPresent(s, ctx, w, a, lane: lane) != nil
        let lh = lastHit(&s, ctx, w, a, lane: lane, tower: enemyTower, tanked: tanked)
        if let t = lh.now, !isSupport || mode != .farm {
            BotAI.attack(s, &a, &mem, t)
            return
        }

        // 2. サポートはキャリーを殴っている敵ヒーローを追い払う
        if isSupport, s.units[i].hpRatio > 0.5, let carry = carryPresent(s, ctx, w, a, lane: lane),
           let peel = attackerOf(s, a, ally: carry),
           w.enemyStructure(covering: peel.pos, team: a.team, margin: 60) == nil {
            BotCombat.castSkills(&s, ctx, &a, &mem, target: peel, fighting: true)
            BotAI.attack(s, &a, &mem, peel.index)
            return
        }

        // 3. ハラス（有利な小競り合い）
        if mode != .siege, let target = harassTarget(s, ctx, w, a, mem, isSupport: isSupport) {
            mem.lastHarassTime = s.time
            BotCombat.castSkills(&s, ctx, &a, &mem, target: target, fighting: false)
            BotAI.attack(s, &a, &mem, target.index)
            return
        }

        // 4. 押し込み（構造物 → ミニオン）
        let pushing = mode != .farm || laneEmpty || (isSupport == false && !enemyHeroesNear && s.time >= 5 * 60)
        if pushing && !lh.soon {
            if let st = enemyTower, !st.invulnerable, canHitStructure(s, w, a, st, tanked: tanked, mode: mode,
                                                                    enemiesNear: enemyHeroesNear) {
                BotAI.attack(s, &a, &mem, st.index)
                return
            }
            let minions = enemyMinionsNear(s, w, a, radius: range + 420, tower: enemyTower, tanked: tanked)
            if !minions.isEmpty {
                BotCombat.castFarmSkills(&s, ctx, &a, &mem, targets: minions, minCluster: 3)
                if let t = lowestHP(s, minions) {
                    BotAI.attack(s, &a, &mem, t)
                    return
                }
            }
        } else if mode == .defend {
            let minions = enemyMinionsNear(s, w, a, radius: range + 300, tower: enemyTower, tanked: tanked)
            if !lh.soon, let t = lowestHP(s, minions) {
                BotAI.attack(s, &a, &mem, t)
                return
            }
        }

        // 5. 待機位置へ
        let hold = holdPoint(s, ctx, w, a, lane: lane, mode: mode, tower: enemyTower, tanked: tanked)
        BotAI.move(s, ctx, &a, &mem, to: hold)
    }

    // MARK: - 押し切り

    /// 押し切り: 方針の目標構造物（無ければレーンの最前タワー / Core）へ味方と揃って攻め込む。行動したら true。
    static func siege(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                      _ mem: inout BotHeroMemory, lane: Lane) -> Bool {
        let plan = s.bots.teams[a.team.rawValue].plan
        let target = w.structures.first { $0.id == plan.targetID && $0.team != a.team }
            ?? w.frontTower(team: a.team.opponent, lane: lane) ?? w.core(of: a.team.opponent)
        guard let st = target, !st.invulnerable else { return false }
        let i = a.i
        let reach = s.units[i].stats.attackRange + s.units[i].radius + st.radius
        let d = a.pos.distance(to: st.pos)
        var allies = 0
        for h in w.heroes where s.units[h].team == a.team && s.units[h].isAlive && s.units[h].hero?.isDead != true {
            if s.units[h].pos.distanceSquared(to: st.pos) < 1600 * 1600 { allies += 1 }
        }
        // 遠いうちは方針のレーンに沿って進む（最短路で敵の集団と鉢合わせない）
        if d > st.reach + 1400 {
            let map = ctx.map
            let myProg = BotLane.progress(map, lane, team: a.team, a.pos)
            let goalProg = BotLane.progress(map, lane, team: a.team, st.pos) - (st.reach + 350)
            let next = min(goalProg, max(myProg, 0) + 1800)
            BotAI.move(s, ctx, &a, &mem, to: BotLane.point(map, lane, team: a.team, progress: next))
            return true
        }
        let shield = w.minionsUnder(st, team: a.team)
        let towerOnMe = st.targetID == a.id
        // 盾が無く狙われていて体力が心もとなければ一度射程外へ（塔が落ちかけなら押し切る）
        if towerOnMe && shield == 0 && BotCombat.mustLeaveTower(s, w, a, mem, st) {
            BotCombat.leaveTower(s, ctx, &a, &mem, st)
            return true
        }
        // 攻め込む時機: ミニオンが盾になっている・敵の多くが戦線に居ない・ウェーブを待っても来ない
        var waveComing = false
        for m in w.minions where m.team == a.team && m.pos.distanceSquared(to: st.pos) < 2000 * 2000 {
            waveComing = true
            break
        }
        let window = BotAI.enemiesAway(s, team: a.team) >= 3 || w.aliveHeroes[a.team.opponent.rawValue] == 0
        if shield >= 1 || window || (!waveComing && allies >= 3) || (d <= reach + 40 && allies >= 2 && st.hp < st.maxHP * 0.25) {
            BotAI.attack(s, &a, &mem, st.index)
            return true
        }
        // 味方とウェーブが揃うまで射程の外で待つ
        let away = (ctx.map.fountain(a.team) - st.pos).normalized
        BotAI.move(s, ctx, &a, &mem, to: st.pos + away * (st.reach + Balance.heroRadius + 250))
        return true
    }

    // MARK: - 位置取り

    /// 待機位置: 味方ウェーブの少し後ろ・敵ウェーブから射程分・敵タワーの射程外。
    static func holdPoint(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ a: BotAgent, lane: Lane,
                          mode: BotLaneMode, tower enemyTower: BotStructureInfo?, tanked: Bool) -> Vec2 {
        let team = a.team
        let map = ctx.map
        let len = w.laneLength[lane.rawValue]
        let range = s.units[a.i].stats.attackRange
        let ownTower = w.frontTower(team: team, lane: lane)
        let ownTowerProg = ownTower.map { BotLane.progress(map, lane, team: team, $0.pos) } ?? 700
        let enemyFront = w.visibleEnemyFront(team: team, lane: lane)
        let behind = a.isRanged ? Balance.Bot.rangedHoldBehind : Balance.Bot.meleeHoldBehind

        var hold: Double
        if let af = w.front[team.rawValue][lane.rawValue], af > ownTowerProg - 1800 {
            hold = af - behind
            if let ef = enemyFront, ef.progress < af + 900 {
                hold = min(hold, ef.progress - (range + 70))
            }
        } else if let ef = enemyFront, ef.progress < ownTowerProg + 1400 {
            // 味方ウェーブが居ない: タワーの後ろで敵ウェーブを待つ
            hold = min(ownTowerProg - 150, ef.progress - (range + 200))
        } else {
            hold = ownTowerProg + (mode == .defend ? -100 : 350)
        }
        if mode == .defend { hold = min(hold, ownTowerProg + 200) }

        // 敵ウェーブが大きければ下がる（近くの数で比べる）
        let local = localWaveBalance(s, w, a, lane: lane, around: hold)
        if local.enemy - local.ally >= Balance.Bot.waveDisadvantage { hold -= 450 }

        // サポートはキャリーの少し後ろ
        if a.position == .support, let carry = carryPresent(s, ctx, w, a, lane: lane) {
            let cp = BotLane.progress(map, lane, team: team, s.units[carry].pos)
            hold = min(hold + 100, cp - 120)
        }

        // 敵ヒーローの射程に入らない（有利でない限り。ラストヒットの攻撃は別途踏み込む）
        if mode != .siege {
            let mine = s.units[a.i].hpRatio
            let holdPos = BotLane.point(map, lane, team: team, progress: hold)
            for e in a.enemies where e.distance < 1400 {
                guard mine < s.units[e.index].hpRatio + 0.2 else { continue }
                let need = s.units[e.index].stats.attackRange + Balance.heroRadius * 2 + 110
                let d = holdPos.distance(to: e.pos)
                if d < need { hold -= need - d }
            }
        }

        // 敵タワーの射程外（味方ミニオンが盾になっている間は踏み込める）
        if let st = enemyTower {
            let stProg = BotLane.progress(map, lane, team: team, st.pos)
            let limit = stProg - (st.reach + Balance.heroRadius + Balance.Bot.towerSafetyMargin)
            if !(tanked && (mode == .push || mode == .siege)) || st.invulnerable {
                hold = min(hold, limit)
            } else {
                hold = min(hold, stProg - (st.radius + range * 0.8 + Balance.heroRadius))
            }
        }
        hold = max(300, min(len - 300, hold))
        var p = BotLane.point(map, lane, team: team, progress: hold)
        // 味方同士が重ならないよう横にずらす
        let fwd = BotLane.forward(map, lane, team: team, progress: hold)
        let lateral = Double(a.slot % 3 - 1) * 70
        p += fwd.perpendicular * lateral
        return p
    }

    /// hold 付近の味方 / 敵ミニオン数（視認できる敵のみ）。
    static func localWaveBalance(_ s: SimState, _ w: BotWorld, _ a: BotAgent, lane: Lane,
                                 around hold: Double) -> (ally: Int, enemy: Int) {
        let len = w.laneLength[lane.rawValue]
        var ally = 0, enemy = 0
        for m in w.minions where m.lane == lane {
            let p = m.progress(for: a.team, length: len)
            guard abs(p - hold) < 1000 else { continue }
            if m.team == a.team { ally += 1 } else if m.isVisible(to: a.team) { enemy += 1 }
        }
        return (ally, enemy)
    }

    /// 同じレーンに居るキャリー（ボット・人間を問わず、泉や遠くに居る場合は nil）。
    static func carryPresent(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ a: BotAgent, lane: Lane) -> Int? {
        for h in w.heroes where h != a.i && s.units[h].team == a.team && s.units[h].isAlive {
            guard s.units[h].hero?.position == .carry else { continue }
            let p = s.units[h].pos
            if s.units[h].hero?.channel != nil || ctx.map.isInFountain(p, team: a.team) { return nil }
            guard BotLane.blueProgress(ctx.map, lane, p).distance < 900 || p.distance(to: a.pos) < 1300 else { return nil }
            return h
        }
        return nil
    }

    /// 味方 ally を直近に殴った、視認中の敵ヒーロー（自分の射程付近に居るもの）。
    static func attackerOf(_ s: SimState, _ a: BotAgent, ally: Int) -> BotSighting? {
        guard s.time - s.units[ally].lastDamagedTime < 1.5, let id = s.units[ally].lastAttackerID else { return nil }
        let reach = s.units[a.i].stats.attackRange + s.units[a.i].radius + Balance.heroRadius + 40
        return a.enemies.first { $0.id == id && $0.distance <= reach }
    }

    /// 自分のレーン付近に敵ヒーローがしばらく見えていないか。
    static func isLaneEmpty(_ s: SimState, _ a: BotAgent, lane: Lane, map: MapDefinition) -> Bool {
        let intel = s.bots.teams[a.team.rawValue]
        for k in intel.enemyIDs.indices where s.time - intel.lastSeenTime[k] <= Balance.Bot.emptyLaneSeconds {
            if intel.lastSeenPos[k].distanceSquared(to: a.pos) < 2200 * 2200 { return false }
        }
        return true
    }

    // MARK: - ハラス

    /// 有利なら殴る敵ヒーロー（自分も相手も敵タワーの外、周囲の敵ミニオンが少ない）。
    static func harassTarget(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ a: BotAgent,
                             _ mem: BotHeroMemory, isSupport: Bool) -> BotSighting? {
        guard let e = a.enemies.first,
              e.pos.distance(to: ctx.map.fountain(a.team.opponent)) > Balance.fountainRadius + 250 else { return nil }
        let i = a.i
        let interval = a.difficulty == .easy ? 6.0 : (a.difficulty == .normal ? 3.5 : 2.5)
        guard s.time - mem.lastHarassTime >= interval, s.units[i].attackCooldown <= 0.05 else { return nil }
        let reach = s.units[i].stats.attackRange + s.units[i].radius + s.units[e.index].radius
        guard e.distance <= reach + 40 else { return nil }
        guard w.enemyStructure(covering: a.pos, team: a.team, margin: 40) == nil,
              w.enemyStructure(covering: e.pos, team: a.team, margin: 40) == nil else { return nil }
        let mine = s.units[i].hpRatio
        let theirs = s.units[e.index].hpRatio
        // 射程差で一方的に殴れる（遠隔 → 近接で相手の射程外）
        let theirReach = s.units[e.index].stats.attackRange + s.units[i].radius + s.units[e.index].radius
        let freePoke = e.distance > theirReach + 60
        let edge = a.difficulty == .easy ? 0.2 : Balance.Bot.harassHPEdge
        guard mine > 0.45, freePoke || mine - theirs >= edge || theirs < 0.45 else { return nil }
        let myLevel = s.units[i].hero?.level ?? 1
        let theirLevel = s.units[e.index].hero?.level ?? 1
        guard myLevel >= theirLevel - 1 else { return nil }
        // 敵ミニオンの援護（救援要請）を受ける数
        var minions = 0
        for m in w.minions where m.team != a.team && m.isVisible(to: a.team) {
            if m.pos.distanceSquared(to: a.pos) < 700 * 700 { minions += 1 }
        }
        let tolerance = isSupport ? 3 : 2
        guard minions <= tolerance || theirs < 0.3 else { return nil }
        return e
    }

    // MARK: - ラストヒット

    /// 他ユニットの攻撃（飛翔中の弾・前隙・攻撃間隔）を予測して、今取れるミニオンを選ぶ。
    static func lastHit(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: BotAgent, lane: Lane,
                        tower: BotStructureInfo?, tanked: Bool) -> BotLastHit {
        let i = a.i
        let st = s.units[i].stats
        let search = st.attackRange + s.units[i].radius + Balance.Bot.lastHitSearchBonus
        var cands: [Int] = []
        for m in w.minions where m.team != a.team && m.isVisible(to: a.team) {
            let r = search + 40
            guard m.pos.distanceSquared(to: a.pos) <= r * r else { continue }
            // 盾の無い敵タワー下のミニオンは狙わない
            if let t = tower, !tanked, m.pos.distanceSquared(to: t.pos) <= (t.reach + 80) * (t.reach + 80) { continue }
            cands.append(m.index)
            if cands.count >= 10 { break }
        }
        guard !cands.isEmpty else { return BotLastHit(now: nil, soon: false) }

        let interval = CombatSystem.attackInterval(st)
        let windup = interval * Balance.attackWindupRatio
        let speed = max(1, MovementSystem.currentMoveSpeed(s, i))
        var hit = [Double](repeating: 0, count: cands.count)
        var later = [Double](repeating: 0, count: cands.count)
        var mine = [Double](repeating: 0, count: cands.count)
        for (k, t) in cands.enumerated() {
            let d = s.units[i].pos.distance(to: s.units[t].pos)
            let reach = st.attackRange + s.units[i].radius + s.units[t].radius
            let move = max(0, d - reach) / speed
            var ready = max(0, s.units[i].attackCooldown) + windup
            if s.units[i].attackTargetID == s.units[t].id, let wr = s.units[i].windupRemaining { ready = wr }
            let travel = a.isRanged ? min(d, reach) / Balance.heroProjectileSpeed : 0
            hit[k] = max(move, 0) + ready + travel
            later[k] = hit[k] + interval
            mine[k] = CombatSystem.estimateBasicAttackDamage(s, ctx, attacker: i, target: t)
        }
        // 予測を使うか（難易度）
        let predict = a.profile.lastHitSkill >= 1 || s.rng.nextDouble() < a.profile.lastHitSkill
        var soon1 = [Double](repeating: 0, count: cands.count)
        var soon2 = [Double](repeating: 0, count: cands.count)
        if predict { incomingDamage(s, ctx, targets: cands, h1: hit, h2: later, me: i, out1: &soon1, out2: &soon2) }

        var best: Int?
        var bestGold = -1.0
        var bestHP = Double.infinity
        var soon = false
        let margin = a.difficulty == .hard ? 1.0 : 0.96
        for (k, t) in cands.enumerated() {
            let hp = s.units[t].hp + s.units[t].totalShield
            let at = hp - soon1[k]
            if at > 0 && at <= mine[k] * margin {
                let gold = Balance.Economy.minionGold(s.units[t].minion?.type ?? .ranged)
                if gold > bestGold || (gold == bestGold && at < bestHP) {
                    best = t
                    bestGold = gold
                    bestHP = at
                }
            } else if hp - soon2[k] > 0 && hp - soon2[k] <= mine[k] * 1.1 {
                soon = true
            }
        }
        return BotLastHit(now: best, soon: soon)
    }

    /// 各対象が h1 / h2 秒以内に（自分以外から）受ける予測ダメージ。
    static func incomingDamage(_ s: SimState, _ ctx: SimContext, targets: [Int], h1: [Double], h2: [Double],
                               me: Int, out1: inout [Double], out2: inout [Double]) {
        var ids: [EntityID] = []
        ids.reserveCapacity(targets.count)
        for t in targets { ids.append(s.units[t].id) }
        let myID = s.units[me].id
        // 飛翔中の弾
        for p in s.projectiles where !p.done && p.ownerID != myID {
            guard case .homing(let tid) = p.motion, let k = ids.firstIndex(of: tid) else { continue }
            let t = targets[k]
            let eta = p.pos.distance(to: s.units[t].pos) / max(1, p.speed)
            var dmg = p.payload.damage
            if p.payload.damageType != .trueDamage {
                dmg *= CombatSystem.mitigationMultiplier(p.payload.damageType, armor: s.units[t].stats.armor,
                                                         magicResist: s.units[t].stats.magicResist)
            }
            if eta <= h1[k] { out1[k] += dmg }
            if eta <= h2[k] { out2[k] += dmg }
        }
        // これから当たる通常攻撃（前隙中・攻撃間隔）
        for x in s.units.indices where x != me {
            guard let tid = s.units[x].attackTargetID, s.units[x].isAlive, let k = ids.firstIndex(of: tid) else { continue }
            let t = targets[k]
            let ux = s.units[x]
            let interval = CombatSystem.attackInterval(ux.stats)
            let windup = interval * Balance.attackWindupRatio
            let dist = ux.pos.distance(to: s.units[t].pos)
            let reach = ux.stats.attackRange + ux.radius + s.units[t].radius
            let ranged = CombatSystem.isRangedAttacker(ux)
            let speed: Double
            switch ux.kind {
            case .hero: speed = Balance.heroProjectileSpeed
            case .tower, .core: speed = Balance.combatStructureProjectileSpeed
            default: speed = Balance.combatMinionProjectileSpeed
            }
            let travel = ranged ? min(dist, reach) / speed : 0
            let approach = ux.isStructure ? 0 : max(0, dist - reach) / max(1, ux.stats.moveSpeed)
            if ux.isStructure && dist > reach + 10 { continue }
            var first: Double
            if let w = ux.windupRemaining { first = w + travel } else { first = approach + max(0, ux.attackCooldown) + windup + travel }
            let dmg: Double
            switch ux.kind {
            case .tower, .core:
                let pct: Double
                switch s.units[t].minion?.type ?? .melee {
                case .melee: pct = Balance.towerMeleeMinionDamagePct
                case .ranged: pct = Balance.towerRangedMinionDamagePct
                case .siege: pct = Balance.towerSiegeMinionDamagePct
                }
                dmg = pct * s.units[t].stats.maxHP
            case .hero:
                dmg = CombatSystem.estimateBasicAttackDamage(s, ctx, attacker: x, target: t)
            default:
                dmg = ux.stats.attack * max(0, 1 + ux.stats.damageBonus)
                    * CombatSystem.mitigationMultiplier(.physical, armor: s.units[t].stats.armor, magicResist: 0)
            }
            var n = 0
            while first <= h2[k] && n < 6 {
                if first <= h1[k] { out1[k] += dmg }
                out2[k] += dmg
                first += interval
                n += 1
            }
        }
    }

    // MARK: - 押し込み

    /// 構造物を叩いてよいか: 射程に近い・無敵でない・味方ミニオンが盾（押し切りなら敵が居なければ可）。
    static func canHitStructure(_ s: SimState, _ w: BotWorld, _ a: BotAgent, _ st: BotStructureInfo, tanked: Bool,
                                mode: BotLaneMode, enemiesNear: Bool) -> Bool {
        let reach = s.units[a.i].stats.attackRange + s.units[a.i].radius + st.radius
        guard a.pos.distance(to: st.pos) <= reach + 450 else { return false }
        if st.targetID == a.id { return false }
        if tanked && !enemiesNear { return true }
        if mode == .siege {
            // 押し切り: 周囲に敵ヒーローが居ない、またはタワーが他を狙っている
            return !enemiesNear || (st.targetID != nil && st.targetID != a.id && st.hp < st.maxHP * 0.25)
        }
        return false
    }

    /// 近くの攻撃できる敵ミニオン（盾の無い敵タワー下を除く）。
    static func enemyMinionsNear(_ s: SimState, _ w: BotWorld, _ a: BotAgent, radius: Double,
                                 tower: BotStructureInfo?, tanked: Bool) -> [Int] {
        var out: [Int] = []
        for m in w.minions where m.team != a.team && m.isVisible(to: a.team) {
            guard m.pos.distanceSquared(to: a.pos) <= radius * radius else { continue }
            if let t = tower, !tanked, m.pos.distanceSquared(to: t.pos) <= (t.reach + 80) * (t.reach + 80) { continue }
            out.append(m.index)
        }
        return out
    }

    static func lowestHP(_ s: SimState, _ candidates: [Int]) -> Int? {
        var best: Int?
        var bestHP = Double.infinity
        for c in candidates where s.units[c].hp < bestHP {
            bestHP = s.units[c].hp
            best = c
        }
        return best
    }
}
