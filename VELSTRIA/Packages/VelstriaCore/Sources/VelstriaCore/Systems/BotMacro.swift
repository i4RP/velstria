import Foundation

// 担当: core-bots
// マクロ（DESIGN §10）: チーム方針（防衛・オブジェクト・集団での押し込み・押し切り）と、帰還・回復・買い物の段取り。

enum BotMacro {
    // MARK: - チーム方針（1Hz）

    static func updatePlan(_ s: inout SimState, _ ctx: SimContext, team: Team) {
        guard team.rawValue < s.bots.teams.count else { return }
        let w = BotWorld(s, ctx)
        var bots: [Int] = []
        for h in w.heroes where s.units[h].team == team && s.units[h].hero?.controller == .bot {
            bots.append(h)
        }
        guard !bots.isEmpty else {
            s.bots.teams[team.rawValue].plan = BotTeamPlan()
            return
        }
        let difficulty = s.units[bots[0]].hero?.botDifficulty ?? .normal
        let profile = BotProfile.of(difficulty)
        let aliveBots = bots.filter { s.units[$0].isAlive && s.units[$0].hero?.isDead != true }
        let ourAlive = w.aliveHeroes[team.rawValue]
        let enemyAlive = w.aliveHeroes[team.opponent.rawValue]
        let enemyDead = w.deadHeroes[team.opponent.rawValue]
        let enemyAway = max(enemyDead, BotAI.enemiesAway(s, team: team))
        let old = s.bots.teams[team.rawValue].plan
        let intel = s.bots.teams[team.rawValue]
        let t = s.time

        var plan = BotTeamPlan()
        plan.since = t
        let groupPhase = t >= profile.groupStart
        let retryAt = s.bots.teams[team.rawValue].objectiveRetryAt
        let center = centroid(s, aliveBots)
        let blessedDuo = aliveBots.filter { s.units[$0].has(.wyrmBlessing) && s.units[$0].hero?.position != .jungle }

        // 1. 防衛: 敵ヒーローが自軍構造物を攻めている（直前の防衛は少し続けて行ったり来たりを防ぐ）。
        //    集団期に自分たちの押し込みが進んでいる時は、外塔・内塔は取り合いにして押し切りを優先する
        if let threat = threatenedStructure(s, w, intel, team: team, groupPhase: groupPhase)
            ?? lingeringDefense(s, w, intel, old: old),
           !(groupPhase && isRacing(s, w, old: old, team: team, threatened: threat.structure)) {
            let st = threat.structure
            plan.kind = .defend
            plan.lane = st.lane ?? .mid
            plan.targetID = st.id
            plan.point = st.pos
            // 脅威に見合う人数（Core・基部塔は全員）
            let deep = st.isCore || st.tier == .base
            let limit = deep ? 5 : min(5, max(1, threat.heroes + (threat.minions >= 4 ? 1 : 0)))
            plan.members = nearest(s, aliveBots, to: st.pos, count: limit, within: deep || groupPhase ? .infinity : 6500)
        }
        // 2. 進行中のオブジェクトを続ける（揃っている・横取りの危険が無い・時間内）
        else if let keep = continueObjective(s, ctx, intel, old: old, team: team) {
            plan = keep
        }
        // 2b. 終盤の古環の巨像: 押し切りの前に取る（強化ミニオンと 2 秒帰還で守りを崩す）
        else if t >= Balance.Bot.lateSiege, t >= retryAt, let camp = bossCamp(ctx, .ancientColossus), campAlive(s, camp),
                ourAlive >= enemyAlive, aliveBots.count >= 3, blessed(s, aliveBots, .colossusBlessing) == 0,
                enemiesSeenNear(s, intel, camp.pos, radius: 2500, within: 5) == 0 {
            plan.kind = .colossus
            plan.point = camp.pos
            plan.members = aliveBots.map { s.units[$0].id }
        }
        // 3. 押し切り: 人数有利（敵が死亡・帰還で戦線に居ない）・巨像の加護・Core が露出・終盤
        else if ourAlive >= 3 || ourAlive > enemyAlive,
                enemyAway >= 3 || (enemyAway >= 2 && groupPhase)
                    || (blessed(s, aliveBots, .colossusBlessing) >= 3 && ourAlive >= enemyAlive)
                    || (groupPhase && enemyAway >= 1 && w.core(of: team.opponent)?.invulnerable == false)
                    || (t >= Balance.Bot.lateSiege && ourAlive >= enemyAlive),
                let st = siegeTarget(s, w, team: team, preferred: old.lane) {
            plan.kind = .siege
            plan.lane = approachLane(s, ctx, w, intel, team: team, target: st, old: old)
            plan.targetID = st.id
            plan.point = st.pos
            plan.members = aliveBots.map { s.units[$0].id }
        }
        // 3b. 星喰竜の直後: 加護を得た bot レーンの 2 人で、味方ウェーブが押している間だけ塔を押す（集団期の前）。
        //     ジャングラーはキャンプへ戻る
        else if !groupPhase, blessedDuo.count >= 2, let st = w.frontTower(team: team.opponent, lane: .bot),
                (w.front[team.rawValue][Lane.bot.rawValue] ?? 0) > w.laneLength[Lane.bot.rawValue] * 0.5 {
            plan.kind = .push
            plan.lane = .bot
            plan.targetID = st.id
            plan.point = st.pos
            plan.members = blessedDuo.map { s.units[$0].id }
        }
        // 4. 古環の巨像（敵が減っている時・集団が近い時）
        else if t >= Balance.Bot.colossusStart, t >= retryAt, let camp = bossCamp(ctx, .ancientColossus),
                campAlive(s, camp), enemyAway >= 2 || (ourAlive - enemyAlive >= 1 && center.distance(to: camp.pos) < 4500),
                aliveBots.count >= 3,
                enemiesSeenNear(s, intel, camp.pos, radius: 2200, within: 4) == 0 {
            plan.kind = .colossus
            plan.point = camp.pos
            plan.members = aliveBots.map { s.units[$0].id }
        }
        // 5. 星喰竜（2:00 以降、近くに敵が見えない時。集団期は集団が近い時のみ）
        else if t >= Balance.Bot.wyrmStart, t >= retryAt, let camp = bossCamp(ctx, .astralWyrm), campAlive(s, camp),
                !groupPhase || enemyDead >= 1 || center.distance(to: camp.pos) < 4500,
                let members = wyrmTeam(s, aliveBots, pit: camp.pos, groupPhase: groupPhase, ourAlive: ourAlive,
                                       enemyAlive: enemyAlive),
                enemiesSeenNear(s, intel, camp.pos, radius: 2500, within: 5) == 0 {
            plan.kind = .wyrm
            plan.point = camp.pos
            plan.members = members
        }
        // 6. 集団で押し込み（敵の集団が居ないレーンを選び、今のレーンを少し優先。同条件なら mid）
        else if groupPhase {
            let lane = pushLane(s, ctx, w, intel, team: team, old: old, center: center,
                                groupSize: min(profile.groupSize, aliveBots.count))
            plan.kind = .push
            plan.lane = lane
            plan.members = pushMembers(s, ctx.map, aliveBots, count: profile.groupSize, lane: lane)
            plan.point = BotLane.point(ctx.map, lane, team: team,
                                       progress: w.front[team.rawValue][lane.rawValue] ?? 1500)
        }
        // オブジェクトを途中で諦めたら、しばらく再挑戦しない
        if (old.kind == .wyrm || old.kind == .colossus) && plan.kind != old.kind {
            let camp = bossCamp(ctx, old.kind == .wyrm ? .astralWyrm : .ancientColossus)
            if let c = camp, campAlive(s, c) { s.bots.teams[team.rawValue].objectiveRetryAt = t + 45 }
        }
        if plan.kind == old.kind && plan.targetID == old.targetID && plan.lane == old.lane && old.kind != .none {
            plan.since = old.since
        }
        plan.members.sort { $0 < $1 }
        s.bots.teams[team.rawValue].plan = plan
    }

    /// 攻められている自軍構造物と脅威の大きさ（Core > 基部 > 内 > 外の順）。
    /// 塔が実際に削られている時だけ（レーン戦の押し引きでは動かない）。集団期より前の外塔は敵ヒーロー 2 人以上。
    static func threatenedStructure(_ s: SimState, _ w: BotWorld, _ intel: BotTeamIntel, team: Team,
                                    groupPhase: Bool) -> (structure: BotStructureInfo, heroes: Int, minions: Int)? {
        var best: (structure: BotStructureInfo, heroes: Int, minions: Int)?
        var bestRank = -1
        for st in w.structures where st.team == team {
            guard s.time - s.units[st.index].lastDamagedTime < 4 else { continue }
            let heroes = enemiesSeenNear(s, intel, st.pos, radius: st.reach + 600, within: 2)
            var minions = 0
            for m in w.minions where m.team != team && m.isVisible(to: team) {
                if m.pos.distanceSquared(to: st.pos) < (st.reach + 250) * (st.reach + 250) { minions += 1 }
            }
            let deep = st.isCore || st.tier == .base
            var threatened = heroes >= 1 || (deep && minions >= 3)
            if !groupPhase && st.tier == .outer && !st.isCore { threatened = heroes >= 2 }
            guard threatened else { continue }
            let rank = st.isCore ? 4 : 3 - st.tier.rawValue
            if rank > bestRank {
                bestRank = rank
                best = (st, heroes, minions)
            }
        }
        return best
    }

    /// 取り合い（ベースレース）を続けるべきか: 味方の集団が目標の構造物に取り付いていて、こちらの目標の方が削れている。
    /// 守る側が Core の場合は、こちらも Core を削っていて相手の Core の方が低い時だけ。
    static func isRacing(_ s: SimState, _ w: BotWorld, old: BotTeamPlan, team: Team,
                         threatened: BotStructureInfo) -> Bool {
        guard old.kind == .push || old.kind == .siege else { return false }
        if threatened.isCore || threatened.tier == .base {
            guard let theirCore = w.core(of: team.opponent), !theirCore.invulnerable, old.targetID == theirCore.id,
                  let ourCore = w.core(of: team) else { return false }
            let theirs = theirCore.hp / max(1, theirCore.maxHP)
            let ours = ourCore.hp / max(1, ourCore.maxHP)
            guard theirs < ours - 0.1 else { return false }
        }
        let target = w.structures.first { $0.id == old.targetID && $0.team != team }
            ?? old.lane.flatMap { w.frontTower(team: team.opponent, lane: $0) }
        guard let st = target, !st.invulnerable else { return false }
        var near = 0
        for id in old.members {
            guard let h = s.index(of: id), s.units[h].isAlive, s.units[h].hero?.isDead != true else { continue }
            if s.units[h].pos.distanceSquared(to: st.pos) < 1800 * 1800 { near += 1 }
        }
        let ours = st.hp / max(1, st.maxHP)
        let theirs = threatened.hp / max(1, threatened.maxHP)
        return near >= 2 && ours <= theirs + 0.2
    }

    /// 直前まで守っていた構造物（生存中・開始から 12 秒以内）。
    static func lingeringDefense(_ s: SimState, _ w: BotWorld, _ intel: BotTeamIntel,
                                 old: BotTeamPlan) -> (structure: BotStructureInfo, heroes: Int, minions: Int)? {
        guard old.kind == .defend, s.time - old.since < 12,
              let st = w.structures.first(where: { $0.id == old.targetID }) else { return nil }
        return (st, max(1, old.members.count), 0)
    }

    /// kind のバフを持つ生存ボットの数。
    static func blessed(_ s: SimState, _ bots: [Int], _ kind: StatusKind) -> Int {
        bots.filter { s.units[$0].has(kind) }.count
    }

    /// 生存ボットの重心。
    static func centroid(_ s: SimState, _ bots: [Int]) -> Vec2 {
        guard !bots.isEmpty else { return Balance.mapCenter }
        var sum = Vec2.zero
        for b in bots { sum += s.units[b].pos }
        return sum / Double(bots.count)
    }

    /// team の情報で、center の radius 以内に直近 within 秒以内に見えた敵ヒーロー数。
    static func enemiesSeenNear(_ s: SimState, _ intel: BotTeamIntel, _ center: Vec2, radius: Double,
                                within: Double) -> Int {
        var n = 0
        for k in intel.enemyIDs.indices where s.time - intel.lastSeenTime[k] <= within {
            if intel.lastSeenPos[k].distanceSquared(to: center) <= radius * radius { n += 1 }
        }
        return n
    }

    /// 押し切りの目標: 攻撃可能な敵構造物のうち、前回のレーン（無ければ mid）を優先して最も手前。
    static func siegeTarget(_ s: SimState, _ w: BotWorld, team: Team, preferred: Lane?) -> BotStructureInfo? {
        let enemy = team.opponent
        var candidates: [BotStructureInfo] = []
        for st in w.structures where st.team == enemy && !st.invulnerable { candidates.append(st) }
        guard !candidates.isEmpty else { return nil }
        if let core = candidates.first(where: \.isCore) { return core }
        let order: [Lane] = [preferred ?? .mid, .mid, .bot, .top]
        for lane in order {
            if let st = candidates.filter({ $0.lane == lane }).min(by: { $0.tier.rawValue < $1.tier.rawValue }) {
                return st
            }
        }
        return candidates[0]
    }

    /// 押し切りで目標へ向かうレーン。塔はそのレーン、Core は塔が全滅したレーンのうち敵の集団が見えていない方
    /// （両チームが同じ mid で鉢合わせて睨み合い続けないように）。
    static func approachLane(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ intel: BotTeamIntel, team: Team,
                             target st: BotStructureInfo, old: BotTeamPlan) -> Lane {
        if let lane = st.lane { return lane }
        var best: Lane = .mid
        var bestScore = -Double.infinity
        for lane in ctx.map.lanes where w.frontTower(team: team.opponent, lane: lane) == nil {
            let len = w.laneLength[lane.rawValue]
            let approach = BotLane.point(ctx.map, lane, team: team, progress: len * 0.6)
            var score = -Double(enemiesSeenNear(s, intel, approach, radius: 3000, within: 8))
            if old.kind == .siege && old.lane == lane { score += 0.8 }
            if lane == .mid { score += 0.2 }
            if score > bestScore {
                bestScore = score
                best = lane
            }
        }
        return best
    }

    /// 集団で押すレーン。敵の集団が見えているレーンを避け（空いている塔を取って守りに来させる）、
    /// 本拠点に近い塔・削れている塔・味方ウェーブが前に出ているレーンを選ぶ。今のレーンを少し優先する。
    static func pushLane(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ intel: BotTeamIntel, team: Team,
                         old: BotTeamPlan, center: Vec2, groupSize: Int) -> Lane {
        let enemy = team.opponent
        var best: Lane = .mid
        var bestScore = -Double.infinity
        for lane in ctx.map.lanes {
            // 目標: レーンの最前の敵塔（無ければ攻撃可能な Core）
            var target = w.frontTower(team: enemy, lane: lane)
            if target == nil, let core = w.core(of: enemy), !core.invulnerable { target = core }
            guard let st = target else { continue }
            let len = w.laneLength[lane.rawValue]
            let front = w.front[team.rawValue][lane.rawValue] ?? len * 0.3
            let frontPos = BotLane.point(ctx.map, lane, team: team, progress: front)
            let presence = enemiesSeenNear(s, intel, frontPos, radius: 2500, within: 8)
                + enemiesSeenNear(s, intel, st.pos, radius: 1800, within: 8)
            // 敵の集団が見えているレーンは避ける（空いている塔を取り、守りに来させて塔の下で迎え撃つ）。
            // 大きく数で勝る時だけは狩りに行く
            var score = presence > 0 && presence <= groupSize - 2 ? 0.6 : -Double(presence) * 1.1
            score += Double(st.tier.rawValue) * 0.5 + (st.isCore ? 2 : 0) + (1 - st.hp / max(1, st.maxHP)) * 1.5
            if front > len * 0.5 { score += 0.6 }
            score -= center.distance(to: frontPos) / 4000
            if old.kind == .push && old.lane == lane { score += 0.9 }
            if lane == .mid { score += 0.3 }
            if score > bestScore {
                bestScore = score
                best = lane
            }
        }
        return best
    }

    /// 押し込みのメンバー: 担当レーンが近い順（mid → jungle → support → carry → top）。
    static func pushMembers(_ s: SimState, _ map: MapDefinition, _ bots: [Int], count: Int, lane: Lane) -> [EntityID] {
        func rank(_ p: LanePosition?) -> Int {
            switch p {
            case .mid?: return lane == .mid ? 0 : 3
            case .jungle?: return 1
            case .support?: return 2
            case .carry?: return lane == map.lane(for: .carry) ? 0 : 3
            case .top?: return lane == map.lane(for: .top) ? 0 : 4
            case nil: return 5
            }
        }
        let sorted = bots.sorted {
            let ra = rank(s.units[$0].hero?.position), rb = rank(s.units[$1].hero?.position)
            return ra != rb ? ra < rb : $0 < $1
        }
        return sorted.prefix(max(1, count)).map { s.units[$0].id }
    }

    /// 星喰竜に向かうメンバー（序盤はジャングル + bot の 2〜3 人、集団期は全員）。巣から遠すぎる者は除く。
    static func wyrmTeam(_ s: SimState, _ bots: [Int], pit: Vec2, groupPhase: Bool, ourAlive: Int,
                         enemyAlive: Int) -> [EntityID]? {
        let healthy = bots.filter { s.units[$0].hpRatio > 0.6 }
        if groupPhase {
            guard ourAlive >= enemyAlive, healthy.count >= 3 else { return nil }
            return healthy.map { s.units[$0].id }
        }
        let crew = healthy.filter {
            let p = s.units[$0].hero?.position
            return (p == .jungle || p == .carry || p == .support) && s.units[$0].pos.distance(to: pit) < 5000
        }
        guard crew.count >= 2, crew.contains(where: { s.units[$0].hero?.position == .jungle }) else { return nil }
        return crew.map { s.units[$0].id }
    }

    /// 進行中のオブジェクト方針を続けるか（生存メンバーで更新）。続けないなら nil。
    static func continueObjective(_ s: SimState, _ ctx: SimContext, _ intel: BotTeamIntel, old: BotTeamPlan,
                                  team: Team) -> BotTeamPlan? {
        guard old.kind == .wyrm || old.kind == .colossus,
              let camp = bossCamp(ctx, old.kind == .wyrm ? .astralWyrm : .ancientColossus), campAlive(s, camp),
              s.time - old.since < Balance.Bot.objectiveTimeout else { return nil }
        var plan = old
        plan.members = old.members.filter { id in
            guard let h = s.index(of: id), s.units[h].isAlive, s.units[h].hero?.isDead != true else { return false }
            return s.units[h].hpRatio > 0.3
        }
        guard plan.members.count >= 2 else { return nil }
        // 巣の近くの敵がこちらの人数以上なら諦める
        let threats = enemiesSeenNear(s, intel, camp.pos, radius: 1800, within: 3)
        guard threats < plan.members.count else { return nil }
        return plan
    }

    static func nearest(_ s: SimState, _ bots: [Int], to p: Vec2, count: Int, within: Double) -> [EntityID] {
        let sorted = bots.filter { s.units[$0].pos.distance(to: p) <= within }.sorted {
            let da = s.units[$0].pos.distanceSquared(to: p), db = s.units[$1].pos.distanceSquared(to: p)
            return da != db ? da < db : $0 < $1
        }
        return sorted.prefix(count).map { s.units[$0].id }
    }

    static func bossCamp(_ ctx: SimContext, _ kind: CampKind) -> CampSpot? {
        ctx.map.camps.first { $0.kind == kind }
    }

    /// キャンプが出現中か（ボスの出現・撃破は全体告知されるため両チームが知っている）。
    static func campAlive(_ s: SimState, _ camp: CampSpot) -> Bool {
        camp.id < s.world.campRespawnAt.count && s.world.campRespawnAt[camp.id] == nil
    }

    // MARK: - 行動

    /// チーム方針のメンバーなら方針に、そうでなければ役割（レーン・ジャングル）に従う。
    static func act(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                    _ mem: inout BotHeroMemory) {
        let plan = s.bots.teams[a.team.rawValue].plan
        if plan.includes(a.id) {
            switch plan.kind {
            case .wyrm, .colossus:
                objective(&s, ctx, w, &a, &mem, plan: plan)
                return
            case .push:
                BotAI.setGoal(&mem, .push, s.time)
                BotLaning.act(&s, ctx, w, &a, &mem, lane: plan.lane ?? .mid, mode: .push)
                return
            case .siege:
                BotAI.setGoal(&mem, .push, s.time)
                BotLaning.act(&s, ctx, w, &a, &mem, lane: plan.lane ?? .mid, mode: .siege)
                return
            case .defend:
                BotAI.setGoal(&mem, .defend, s.time)
                BotLaning.act(&s, ctx, w, &a, &mem, lane: plan.lane ?? .mid, mode: .defend)
                return
            case .none:
                break
            }
        }
        if mem.position == .jungle {
            BotJungle.act(&s, ctx, w, &a, &mem)
            return
        }
        // サポートは生きているジャングラーに付いて回る（無ければレーン戦）
        if mem.position == .support, BotRoam.follow(&s, ctx, w, &a, &mem) { return }
        let lane = mem.lane ?? .mid
        BotAI.setGoal(&mem, .laning, s.time)
        teleportToLane(&s, ctx, w, &a, lane: lane)
        BotLaning.act(&s, ctx, w, &a, &mem, lane: lane, mode: .farm)
    }

    /// オブジェクト（星喰竜・古環の巨像）: 巣に集まり、揃ったら攻撃。狩猟印で止め。
    static func objective(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                          _ mem: inout BotHeroMemory, plan: BotTeamPlan) {
        BotAI.setGoal(&mem, .objective, s.time)
        let pit = plan.point
        let dist = a.pos.distance(to: pit)
        var boss: Int?
        for m in w.monsters {
            guard let kind = s.units[m].monster?.kind, kind == .astralWyrm || kind == .ancientColossus,
                  s.units[m].pos.distanceSquared(to: pit) < 1200 * 1200, s.isVisible(m, to: a.team) else { continue }
            boss = m
        }
        let staging = pit + (ctx.map.fountain(a.team) - pit).normalized * 650
        guard let b = boss, dist < 1300 else {
            BotAI.move(s, ctx, &a, &mem, to: dist > 900 ? staging : pit)
            return
        }
        // 仲間が揃うまで巣の手前で待つ（既に削り始めていれば加勢）
        var gathered = 0
        for id in plan.members {
            if let h = s.index(of: id), s.units[h].isAlive, s.units[h].pos.distanceSquared(to: pit) < 1300 * 1300 {
                gathered += 1
            }
        }
        let started = s.units[b].hp < s.units[b].stats.maxHP * 0.98
        guard started || gathered >= min(2, plan.members.count) else {
            BotAI.move(s, ctx, &a, &mem, to: staging)
            return
        }
        BotJungle.smite(&s, ctx, &a, b)
        BotCombat.castFarmSkills(&s, ctx, &a, &mem, targets: [b], minCluster: 1)
        BotAI.attack(s, &a, &mem, b)
    }

    /// 帰還門（BS09）を持っていれば、遠いレーンの味方タワーへ転移する。
    static func teleportToLane(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent, lane: Lane) {
        guard let h = s.units[a.i].hero, let idx = h.spells.firstIndex(of: "BS09"),
              SpellSystem.canCast(s, ctx, heroIndex: a.i, spellIndex: idx),
              ctx.map.isInFountain(a.pos, team: a.team),
              let tower = w.frontTower(team: a.team, lane: lane), tower.pos.distance(to: a.pos) > 5000 else { return }
        let dest = tower.pos + (ctx.map.fountain(a.team) - tower.pos).normalized * 250
        a.emit(.castSpell(index: idx, target: .point(dest)))
    }

    // MARK: - 帰還

    /// 撤退の締めくくり・回復・買い物のための帰還。行動したら true。
    static func handleRecall(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                             _ mem: inout BotHeroMemory) -> Bool {
        let i = a.i
        guard let hero = s.units[i].hero else { return false }
        let hpRatio = s.units[i].hpRatio
        let fountain = ctx.map.fountain(a.team)
        if ctx.map.isInFountain(a.pos, team: a.team) {
            mem.recall = .none
            if mem.goal == .retreat || mem.goal == .recall || mem.goal == .shopping {
                BotAI.setGoal(&mem, mem.position == .jungle ? .jungling : .laning, s.time)
            }
            return false
        }
        var want = mem.recall != .none
        if mem.goal == .retreat && !want {
            if hpRatio >= 0.45 {
                // 劣勢で下がっただけで体力は残っている: 敵が居なくなるまで安全な位置で待ち、役割へ戻る
                if a.enemies.isEmpty {
                    BotAI.setGoal(&mem, mem.position == .jungle ? .jungling : .laning, s.time)
                } else {
                    BotAI.move(s, ctx, &a, &mem, to: BotCombat.safePoint(s, ctx, w, a))
                    return true
                }
            } else {
                want = true
            }
        }
        if !want { want = wantsRecall(s, ctx, a, mem, hero: hero) }
        guard want else { return false }

        BotAI.setGoal(&mem, .recall, s.time)
        let danger = a.enemies.contains { $0.distance < Balance.Bot.recallSafeRadius }
            || a.ghosts.contains { $0.distance < 900 }
        let home = a.pos.distance(to: fountain)
        if home < Balance.Bot.walkHomeDistance || danger || s.time - s.units[i].lastDamagedTime < 1.2 {
            // 近い・追われている・被弾中: 歩いて戻る（安全になれば次の判断で詠唱）。帰ると決めたら泉に着くまで続ける
            mem.recall = .walking
            if danger { BotCombat.useDefensiveSpells(&s, ctx, w, &a, &mem, fighting: false) }
            BotAI.move(s, ctx, &a, &mem, to: danger ? BotCombat.safePoint(s, ctx, w, a) : fountain)
            return true
        }
        if hero.channel == nil {
            // 攻撃・移動中の意図を消してから詠唱（CommandSystem が順に処理する）
            a.emit(.stop)
            a.emit(.recall)
            mem.recall = .channeling
            mem.recallIssuedTime = s.time
        }
        return true
    }

    /// 帰還したい理由（HP・リソース不足・買い物）。
    static func wantsRecall(_ s: SimState, _ ctx: SimContext, _ a: BotAgent, _ mem: BotHeroMemory, hero: HeroData) -> Bool {
        let u = s.units[a.i]
        let hpRatio = u.hpRatio
        let busyWithObjective = mem.goal == .objective || mem.goal == .teamfight
        if hpRatio < 0.22 { return true }
        if hpRatio < 0.35 && !busyWithObjective {
            // キャンプを削っている途中のジャングラーは片付けてから
            if mem.position == .jungle, u.attackTargetID != nil, s.time - u.lastDamagedTime < 1.5, hpRatio > 0.25 {
                return false
            }
            return true
        }
        let resourceLow = u.stats.maxResource > 0 && u.resource < u.stats.maxResource * 0.12
        if resourceLow && hpRatio < 0.6 { return true }
        guard !busyWithObjective, a.enemies.isEmpty, hero.gold >= Balance.Bot.shopRecallGold else { return false }
        // 買える物が無い（ビルド完成・枠が埋まっている）なら買い物のためには帰らない
        guard ItemSystem.nextRecommendedPurchase(hero, ctx: ctx) != nil else { return false }
        if hero.gold >= Balance.Bot.shopRecallGoldAlways { return true }
        if hpRatio < Balance.Bot.shopRecallMaxHP {
            return hero.gold >= min(BotShop.goldForNextItem(hero, ctx: ctx), 1250)
        }
        return false
    }
}
