import Foundation

// 担当: core-bots
// AI ヒーロー（味方・敵）の意思決定（DESIGN §10）。人間と同じ HeroCommand を発行する。
// - 5Hz（ボット毎に tick をずらす）で状態機械を回し、チーム方針（集団行動・オブジェクト）は 1Hz で更新する。
// - 知覚はチーム視界（visibleMask）のみ。霧の中の敵は「最後に見た位置」の記憶で扱う（壁越しの情報は使わない）。
// - 乱数は state.rng のみ。状態はすべて SimState.bots に持ち、スナップショット・リプレイで再現できる。

/// ボットの行動目標（状態機械）。
public enum BotGoal: Int, Codable, Hashable, Sendable, CaseIterable {
    case laning
    case jungling
    case roaming
    case retreat
    case recall
    case shopping
    case objective
    case teamfight
    case defend
    case push
}

/// 帰還の段取り。
public enum BotRecallPlan: Int, Codable, Hashable, Sendable {
    case none
    /// 泉まで歩いて戻る（近い・詠唱できない）。
    case walking
    /// 帰還の詠唱中。
    case channeling
}

/// チーム方針の種類。
public enum BotPlanKind: Int, Codable, Hashable, Sendable {
    case none
    case wyrm
    case colossus
    /// 集団でレーンを押す。
    case push
    /// 自軍の構造物を守る。
    case defend
    /// 人数有利・終盤に全員で押し切る。
    case siege
}

/// チーム方針（1Hz 更新）。
public struct BotTeamPlan: Codable, Hashable, Sendable {
    public var kind: BotPlanKind = .none
    public var lane: Lane?
    /// 集合地点・目標地点。
    public var point: Vec2 = .zero
    /// 目標のユニット（オブジェクト・構造物）。
    public var targetID: EntityID?
    /// 参加するヒーロー（エンティティ ID 昇順）。
    public var members: [EntityID] = []
    public var since: Double = 0

    public init() {}

    public func includes(_ id: EntityID) -> Bool { kind != .none && members.contains(id) }
}

/// ヒーロー 1 体分の記憶。
public struct BotHeroMemory: Codable, Hashable, Sendable {
    public var heroID: EntityID
    public var team: Team
    public var isBot: Bool
    public var position: LanePosition
    /// 担当レーン（ジャングルは nil）。
    public var lane: Lane?
    public var goal: BotGoal
    public var goalSince: Double = 0
    public var lastDecisionTick: Int = -1
    /// 現在の攻撃・追跡対象。
    public var targetID: EntityID?
    public var recall: BotRecallPlan = .none
    public var recallIssuedTime: Double = -999
    /// ジャングルで向かっているキャンプ（CampSpot.id）。
    public var campID: Int?
    public var gankTargetID: EntityID?
    public var gankStart: Double = -999
    /// 直近のスキル照準の誤差（乱数で引いた値。デバッグ・再現用）。
    public var aimAngleError: Double = 0
    public var aimLeadScale: Double = 1
    /// 直近に発行した移動先。
    public var lastMoveGoal: Vec2?
    /// 最後に買い物を試した時の所持 Gold（変化が無ければ見積もりを省く）。
    public var lastShopGold: Double = -1
    /// 詰まり検出の基準点と時刻。
    public var stuckAnchor: Vec2 = .zero
    public var stuckSince: Double = 0
    /// 交戦を始めた地点と時刻（深追いの制限）。
    public var fightAnchor: Vec2 = .zero
    public var fightStart: Double = -999
    public var lastSkillTime: Double = -999
    public var lastHarassTime: Double = -999

    public init(heroID: EntityID, team: Team, isBot: Bool, position: LanePosition) {
        self.heroID = heroID
        self.team = team
        self.isBot = isBot
        self.position = position
        self.lane = BotAI.lane(for: position)
        self.goal = position == .jungle ? .jungling : .laning
    }
}

/// チームが共有する敵の情報（視界に入った時刻・最後に見た位置・速度）と方針。
public struct BotTeamIntel: Codable, Hashable, Sendable {
    public var team: Team
    /// 敵ヒーローの ID（昇順）。以下の配列は同じ添字。
    public var enemyIDs: [EntityID] = []
    /// 見え始めた時刻（見えていなければ -1）。
    public var visibleSince: [Double] = []
    public var lastSeenPos: [Vec2] = []
    public var lastSeenTime: [Double] = []
    public var lastSeenTick: [Int] = []
    /// 観測から推定した移動速度（ユニット/秒）。
    public var velocity: [Vec2] = []
    /// 戦線を離れている（帰還の詠唱・泉に居るのを見た）と見なす時刻。死亡中は別に数える。
    public var awayUntil: [Double] = []
    public var plan = BotTeamPlan()
    /// オブジェクトを諦めた後、再挑戦できる時刻。
    public var objectiveRetryAt: Double = 0

    public init(team: Team) {
        self.team = team
    }

    public func slot(of id: EntityID) -> Int? { enemyIDs.firstIndex(of: id) }
}

/// ボット全体の記憶（ヒーロー毎の状態 + チーム毎の情報）。
public struct BotState: Codable, Hashable, Sendable {
    public var initialized = false
    /// 全ヒーロー分（エンティティ ID 昇順）。人間の枠は isBot = false。
    public var heroes: [BotHeroMemory] = []
    /// index = Team.rawValue（blue, red）。
    public var teams: [BotTeamIntel] = []
    /// 意思決定の累計回数（性能計測用）。
    public var decisions: Int = 0

    public init() {}

    public func memory(for id: EntityID) -> BotHeroMemory? { heroes.first { $0.heroID == id } }

    public func plan(for team: Team) -> BotTeamPlan? {
        team == .neutral || team.rawValue >= teams.count ? nil : teams[team.rawValue].plan
    }
}

/// 敵ヒーローの知覚（視認中、または霧の中の記憶）。
struct BotSighting {
    var index: Int
    var id: EntityID
    var pos: Vec2
    var velocity: Vec2
    var distance: Double
    var visible: Bool
}

/// 1 体のボットの 1 回の意思決定で使う文脈と出力。
struct BotAgent {
    let i: Int
    let slot: Int
    let id: EntityID
    let team: Team
    let profile: BotProfile
    let difficulty: Difficulty
    let pos: Vec2
    let level: Int
    let role: Role
    let position: LanePosition
    let isRanged: Bool
    var commands: [PlayerCommand] = []
    /// 反応済みの視認中の敵（近い順）。
    var enemies: [BotSighting] = []
    /// 霧の中に消えた直後の敵（最後に見た位置）。
    var ghosts: [BotSighting] = []
    /// 近くの生存味方ヒーロー（自分を除く、添字昇順）。
    var allies: [Int] = []

    mutating func emit(_ c: PlayerCommand) { commands.append(c) }

    var nearestEnemyDistance: Double { enemies.first?.distance ?? .infinity }
}

public enum BotAI {
    /// controller == .bot のヒーローのコマンドを生成する。
    public static func generateCommands(_ s: inout SimState, _ ctx: SimContext) -> [HeroCommand] {
        guard s.phase == .playing else { return [] }
        if !s.bots.initialized { initialize(&s, ctx) }
        guard s.bots.heroes.contains(where: \.isBot) else { return [] }
        updateIntel(&s, ctx)
        let interval = Balance.Bot.planIntervalTicks
        for team in Team.players where s.tick % interval == (team == .blue ? 0 : interval / 2) {
            BotMacro.updatePlan(&s, ctx, team: team)
        }

        var out: [HeroCommand] = []
        var world: BotWorld?
        for k in s.bots.heroes.indices where s.bots.heroes[k].isBot {
            guard (s.tick + k) % Balance.Bot.decisionIntervalTicks == 0,
                  let i = s.index(of: s.bots.heroes[k].heroID), s.units[i].hero?.controller == .bot else { continue }
            if world == nil { world = BotWorld(s, ctx) }
            if let w = world { decide(&s, ctx, w, unit: i, slot: k, out: &out) }
        }
        return out
    }

    /// ポジション → 担当レーン（ジャングルは nil）。
    public static func lane(for position: LanePosition) -> Lane? {
        switch position {
        case .top: return .top
        case .mid: return .mid
        case .carry, .support: return .bot
        case .jungle: return nil
        }
    }

    // MARK: - 初期化・情報

    static func initialize(_ s: inout SimState, _ ctx: SimContext) {
        var heroes: [BotHeroMemory] = []
        for i in s.units.indices where s.units[i].kind == .hero {
            guard let h = s.units[i].hero else { continue }
            var m = BotHeroMemory(heroID: s.units[i].id, team: s.units[i].team, isBot: h.controller == .bot,
                                  position: h.position)
            m.stuckAnchor = s.units[i].pos
            heroes.append(m)
        }
        heroes.sort { $0.heroID < $1.heroID }
        var teams: [BotTeamIntel] = []
        for team in Team.players {
            var intel = BotTeamIntel(team: team)
            intel.enemyIDs = heroes.filter { $0.team != team && $0.team != .neutral }.map(\.heroID)
            let n = intel.enemyIDs.count
            intel.visibleSince = [Double](repeating: -1, count: n)
            intel.lastSeenPos = [Vec2](repeating: .zero, count: n)
            intel.lastSeenTime = [Double](repeating: -999, count: n)
            intel.lastSeenTick = [Int](repeating: -1, count: n)
            intel.velocity = [Vec2](repeating: .zero, count: n)
            intel.awayUntil = [Double](repeating: -999, count: n)
            teams.append(intel)
        }
        s.bots.heroes = heroes
        s.bots.teams = teams
        s.bots.initialized = true
    }

    /// 敵ヒーローの視認状況を毎 tick 記録する（反応遅延・霧の記憶・予測射撃の速度推定）。
    static func updateIntel(_ s: inout SimState, _ ctx: SimContext) {
        let time = s.time
        let tick = s.tick
        for t in s.bots.teams.indices {
            let bit = s.bots.teams[t].team.visionBit
            for k in s.bots.teams[t].enemyIDs.indices {
                guard let e = s.index(of: s.bots.teams[t].enemyIDs[k]) else { continue }
                let alive = s.units[e].isAlive && s.units[e].hero?.isDead != true
                let visible = alive && s.units[e].visibleMask & bit != 0
                guard visible else {
                    s.bots.teams[t].visibleSince[k] = -1
                    // 死亡した敵は霧の記憶から消す（復活まで脅威にならない）
                    if !alive { s.bots.teams[t].lastSeenTime[k] = -999 }
                    continue
                }
                if s.bots.teams[t].visibleSince[k] < 0 { s.bots.teams[t].visibleSince[k] = time }
                let p = s.units[e].pos
                if s.bots.teams[t].lastSeenTick[k] == tick - 1 {
                    var v = (p - s.bots.teams[t].lastSeenPos[k]) / Balance.dt
                    // ブリンク・転移は速度にしない
                    if v.lengthSquared > 1200 * 1200 { v = .zero }
                    s.bots.teams[t].velocity[k] = s.bots.teams[t].velocity[k] * 0.4 + v * 0.6
                } else {
                    s.bots.teams[t].velocity[k] = .zero
                }
                s.bots.teams[t].lastSeenPos[k] = p
                s.bots.teams[t].lastSeenTime[k] = time
                s.bots.teams[t].lastSeenTick[k] = tick
                // 帰還の詠唱（見える演出）・泉に居る敵はしばらく戦線に戻らない
                let enemyTeam = s.units[e].team
                if s.units[e].hero?.channel?.kind == .recall {
                    s.bots.teams[t].awayUntil[k] = time + Balance.Bot.recallAwaySeconds
                } else if p.distanceSquared(to: ctx.map.fountain(enemyTeam)) < 1500 * 1500 {
                    s.bots.teams[t].awayUntil[k] = max(s.bots.teams[t].awayUntil[k], time + Balance.Bot.fountainAwaySeconds)
                } else {
                    s.bots.teams[t].awayUntil[k] = -999
                }
            }
        }
    }

    /// team の情報で、戦線に居ない（死亡中・帰還中・泉）の敵の数。
    static func enemiesAway(_ s: SimState, team: Team) -> Int {
        guard team.rawValue < s.bots.teams.count else { return 0 }
        let intel = s.bots.teams[team.rawValue]
        var n = 0
        for k in intel.enemyIDs.indices {
            guard let e = s.index(of: intel.enemyIDs[k]) else { continue }
            if !s.units[e].isAlive || s.units[e].hero?.isDead == true || s.time < intel.awayUntil[k] { n += 1 }
        }
        return n
    }

    /// ボットの知覚: 反応遅延を過ぎた視認中の敵、霧に消えた直後の敵、近くの味方。
    static func perceive(_ s: SimState, _ w: BotWorld, _ a: inout BotAgent) {
        let intel = s.bots.teams[a.team.rawValue]
        let r2 = Balance.Bot.awarenessRadius * Balance.Bot.awarenessRadius
        for k in intel.enemyIDs.indices {
            guard let e = s.index(of: intel.enemyIDs[k]) else { continue }
            let since = intel.visibleSince[k]
            if since >= 0 {
                // 新しく見えた脅威は反応時間が過ぎるまで無視する
                guard s.time - since >= a.profile.reaction - 1e-9 else { continue }
                let p = s.units[e].pos
                let d2 = p.distanceSquared(to: a.pos)
                guard d2 <= r2 else { continue }
                a.enemies.append(BotSighting(index: e, id: intel.enemyIDs[k], pos: p, velocity: intel.velocity[k],
                                             distance: d2.squareRoot(), visible: true))
            } else if s.time - intel.lastSeenTime[k] <= Balance.Bot.fogMemory {
                let p = intel.lastSeenPos[k]
                let d2 = p.distanceSquared(to: a.pos)
                guard d2 <= r2 else { continue }
                a.ghosts.append(BotSighting(index: e, id: intel.enemyIDs[k], pos: p, velocity: .zero,
                                            distance: d2.squareRoot(), visible: false))
            }
        }
        a.enemies.sort { $0.distance != $1.distance ? $0.distance < $1.distance : $0.index < $1.index }
        let ar2 = Balance.Bot.allyRadius * Balance.Bot.allyRadius
        for h in w.heroes where h != a.i && s.units[h].team == a.team && s.units[h].isAlive {
            if s.units[h].pos.distanceSquared(to: a.pos) <= ar2 { a.allies.append(h) }
        }
    }

    // MARK: - 意思決定

    static func decide(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, unit i: Int, slot k: Int,
                       out: inout [HeroCommand]) {
        guard let hero = s.units[i].hero else { return }
        var mem = s.bots.heroes[k]
        mem.lastDecisionTick = s.tick
        s.bots.decisions += 1
        var a = BotAgent(i: i, slot: k, id: s.units[i].id, team: s.units[i].team,
                         profile: BotProfile.of(hero.botDifficulty), difficulty: hero.botDifficulty,
                         pos: s.units[i].pos, level: hero.level, role: hero.role, position: hero.position,
                         isRanged: hero.isRanged)
        think(&s, ctx, w, &a, &mem)
        s.bots.heroes[k] = mem
        for c in a.commands { out.append(HeroCommand(heroID: a.id, command: c)) }
    }

    static func think(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                      _ mem: inout BotHeroMemory) {
        let i = a.i
        guard let hero = s.units[i].hero else { return }

        // 死亡中: まとめ買い
        if hero.isDead || !s.units[i].isAlive {
            BotShop.shop(s, ctx, &a, &mem)
            setGoal(&mem, .shopping, s.time)
            mem.recall = .none
            mem.targetID = nil
            return
        }
        perceive(s, w, &a)

        // 詠唱中（帰還・帰還門）: 脅威が迫らない限り動かない
        if let ch = hero.channel {
            let threatened = a.enemies.contains { $0.distance < 900 }
            if !threatened || ch.kind == .teleport { return }
        } else if mem.recall == .channeling {
            // 詠唱が中断された（被ダメ等）: 状況を見直す
            mem.recall = .none
        }

        // 泉: 回復と買い物
        if ctx.map.isInFountain(a.pos, team: a.team) {
            BotShop.shop(s, ctx, &a, &mem)
            mem.recall = .none
            let u = s.units[i]
            let resourceOK = u.stats.maxResource <= 0 || u.resource >= u.stats.maxResource * Balance.Bot.fountainLeaveResource
            if (u.hpRatio < Balance.Bot.fountainLeaveHP || !resourceOK) && a.enemies.isEmpty {
                setGoal(&mem, .shopping, s.time)
                stop(s, &a)
                return
            }
        }

        // 行動不能（スタン・ノックバック中）: 浄化だけ試す
        if !s.units[i].canAct {
            BotCombat.useDefensiveSpells(&s, ctx, w, &a, &mem, fighting: true)
            return
        }

        // 予告中の敵の範囲攻撃から出る
        if BotCombat.dodgeZones(s, ctx, &a, &mem) { return }

        // 戦闘・撤退
        if BotCombat.handleCombat(&s, ctx, w, &a, &mem) { return }

        // 帰還（撤退中・買い物・回復）
        if BotMacro.handleRecall(&s, ctx, w, &a, &mem) { return }

        // 役割・チーム方針に沿った行動
        BotMacro.act(&s, ctx, w, &a, &mem)
        checkStuck(s, ctx, &a, &mem)
    }

    static func setGoal(_ mem: inout BotHeroMemory, _ goal: BotGoal, _ time: Double) {
        if mem.goal != goal {
            mem.goal = goal
            mem.goalSince = time
        }
    }

    // MARK: - コマンド

    /// 地点移動（同じ目標への再発行は省く。敵の泉には入らない）。
    static func move(_ s: SimState, _ ctx: SimContext, _ a: inout BotAgent, _ mem: inout BotHeroMemory, to p: Vec2) {
        let goal = safeGoal(ctx, team: a.team, p)
        let i = a.i
        mem.lastMoveGoal = goal
        if s.units[i].attackTargetID == nil {
            switch s.units[i].moveIntent {
            case .point(let cur) where cur.distanceSquared(to: goal) < 90 * 90:
                return
            case .none where s.units[i].pos.distanceSquared(to: goal) < 70 * 70:
                return
            default:
                break
            }
        }
        a.emit(.moveTo(point: goal))
    }

    /// 通常攻撃（同じ対象への再発行は省く）。
    static func attack(_ s: SimState, _ a: inout BotAgent, _ mem: inout BotHeroMemory, _ t: Int) {
        let tid = s.units[t].id
        mem.targetID = tid
        if s.units[a.i].attackTargetID == tid {
            switch s.units[a.i].moveIntent {
            case .point, .direction: break
            default: return
            }
        }
        a.emit(.attack(targetID: tid))
    }

    static func stop(_ s: SimState, _ a: inout BotAgent) {
        let u = s.units[a.i]
        if u.attackTargetID != nil || u.moveIntent != .none { a.emit(.stop) }
    }

    /// 移動目標を歩行可能・敵の泉の外・マップ内に補正する。
    static func safeGoal(_ ctx: SimContext, team: Team, _ p: Vec2) -> Vec2 {
        let margin = Balance.heroRadius + 20
        var q = Vec2(max(margin, min(ctx.map.size - margin, p.x)), max(margin, min(ctx.map.size - margin, p.y)))
        let fountain = ctx.map.fountain(team.opponent)
        let keep = Balance.fountainRadius + 250
        if q.distanceSquared(to: fountain) < keep * keep {
            var dir = (q - fountain).normalized
            if dir == .zero { dir = (ctx.map.fountain(team) - fountain).normalized }
            q = fountain + dir * keep
        }
        if !ctx.nav.isWalkable(q, radius: Balance.heroRadius) {
            q = ctx.nav.nearestWalkable(q, radius: Balance.heroRadius)
        }
        return q
    }

    /// 移動中なのに進めていなければ、少しずらした地点へ向かい直す。
    static func checkStuck(_ s: SimState, _ ctx: SimContext, _ a: inout BotAgent, _ mem: inout BotHeroMemory) {
        let moving: Bool
        switch s.units[a.i].moveIntent {
        case .point, .follow: moving = true
        default: moving = false
        }
        if !moving || a.pos.distanceSquared(to: mem.stuckAnchor) > 60 * 60 {
            mem.stuckAnchor = a.pos
            mem.stuckSince = s.time
            return
        }
        guard s.time - mem.stuckSince > 2.5, let goal = mem.lastMoveGoal else { return }
        let side = (goal - a.pos).normalized.perpendicular
        let detour = ctx.nav.nearestWalkable(a.pos + side * 250 + (goal - a.pos).normalized * 150,
                                             radius: Balance.heroRadius)
        a.emit(.moveTo(point: detour))
        mem.stuckAnchor = a.pos
        mem.stuckSince = s.time
    }

    // MARK: - 共通の見積もり

    /// ヒーローの戦力（持続 DPS と実効 HP）。スキルは Lv と能力値からの概算。
    static func strength(_ s: SimState, _ i: Int) -> (dps: Double, ehp: Double) {
        let st = s.units[i].stats
        let level = Double(s.units[i].hero?.level ?? 1)
        let crit = 1 + st.critChance * max(0, st.critMultiplier - 1)
        let basic = st.attack * min(st.attackSpeed, Balance.maxAttackSpeed)
            * max(0.2, 1 + st.damageBonus + st.basicAttackDamageBonus) * crit
        let skill = (40 + 16 * level + 0.5 * st.abilityPower + 0.25 * st.attack) * max(0.2, 1 + st.skillDamageBonus)
        let hp = max(0, s.units[i].hp) + s.units[i].totalShield
        let ehp = hp * (1 + (max(0, st.armor) + max(0, st.magicResist)) / 200)
            / max(0.4, 1 - min(Balance.maxDamageReduction, max(0, st.damageReduction)))
        return (basic + skill, ehp)
    }

    /// ヒーロー i が対象 t に数秒で与えられる瞬間火力（準備済みスキル + 通常攻撃 3 発）。
    static func burst(_ s: SimState, _ ctx: SimContext, _ i: Int, target t: Int) -> Double {
        guard let h = s.units[i].hero else { return 0 }
        var total = CombatSystem.estimateBasicAttackDamage(s, ctx, attacker: i, target: t) * 3
        let st = s.units[i].stats
        for slot in SkillSlot.actives where h.rank(slot) > 0 && h.cooldown(slot) <= 0 {
            guard let def = ctx.master.skill(hero: h.heroID, slot: slot) else { continue }
            let rank = Double(h.rank(slot) - 1)
            var dmg = def.baseDamage * (1 + Balance.skillDamagePerRank * rank)
                + def.scalingAttack * st.attack * Balance.skillAttackScalingFactor + def.scalingPower * st.abilityPower
            dmg *= max(0, 1 + st.damageBonus + st.skillDamageBonus)
            dmg *= CombatSystem.mitigationMultiplier(def.damageType, armor: s.units[t].stats.armor,
                                                    magicResist: s.units[t].stats.magicResist)
            total += dmg
        }
        return total * CombatSystem.damageReductionMultiplier(s.units[t].stats.damageReduction)
    }
}
