import Foundation

public struct RiverObjectiveState: Codable, Hashable, Sendable {
    public var campID: Int
    public var nextSpawnAt: Double?
    public var lordEra = false
    /// 次に出るのがロードか（タートルが 6:00 以降に倒されると、次のタートルは出ずに 2 分後にロードが出る）。
    public var nextIsLord: Bool?
}

/// One neutral objective across both sanctuaries; the next kill moves it to the opposite bank.
/// MLBB の現行の規則（Fandom の Turtle / Lord、Patch 1.9.64）:
///   ・タートルは 2:00 に出て、倒されると 2 分後に反対側の巣へ。6:00 以降に倒されたら次のタートルは出ず、2 分後にロードが出る。
///   ・8:00 に生きているタートルは、5 秒ダメージを受けないとロードになる（9:00 までに）。
///   ・ロードの再出現は 180 秒、18:00 以降は 150 秒。18:00 に 1 度だけ進化する。
public enum RiverObjectiveSystem {
    public static let lordStart: Double = 480
    public static let evolvedStart: Double = 1080
    public static let lordRespawn: Double = 180
    public static let lordRespawnLate: Double = 150
    public static let wyrmRespawn: Double = 120
    /// この時刻以降にタートルが倒されたら、次はロード。
    public static let wyrmLastRespawnBefore: Double = 360
    /// 8:00 以降のタートルは、この秒数ダメージを受けないとロードになる。遅くとも turtleToLordDeadline には変わる。
    public static let turtleToLordQuiet: Double = 5
    public static let turtleToLordDeadline: Double = 540

    /// 倒されてから次のロードまでの秒数（18:00 以降は短い）。
    public static func lordRespawn(at time: Double) -> Double {
        time + SpawnSystem.timeEpsilon >= evolvedStart ? lordRespawnLate : lordRespawn
    }

    static func setup(_ s: inout SimState, _ ctx: SimContext) {
        guard ctx.map.size == MapDefinition.relayout.size,
              let lower = ctx.map.camps.filter({ $0.kind.isBoss }).min(by: { $0.pos.y < $1.pos.y }) else { return }
        s.world.riverObjective = .init(campID: lower.id, nextSpawnAt: lower.firstSpawn)
        syncTimers(&s, ctx)
    }

    static func syncTimers(_ s: inout SimState, _ ctx: SimContext) {
        guard let state = s.world.riverObjective else { return }
        for camp in ctx.map.camps where camp.kind.isBoss {
            s.world.campRespawnAt[camp.id] = camp.id == state.campID ? state.nextSpawnAt : Double.greatestFiniteMagnitude
        }
    }

    static func update(_ s: inout SimState, _ ctx: SimContext) {
        guard var state = s.world.riverObjective else { return }
        let bosses = ctx.map.camps.filter { $0.kind.isBoss }
        let alive = s.units.indices.first {
            s.units[$0].kind == .monster && s.units[$0].team == .neutral && s.units[$0].isAlive
                && s.units[$0].monster?.kind.isBoss == true
        }
        let eps = SpawnSystem.timeEpsilon
        if state.nextSpawnAt == nil && alive == nil {
            state.campID = bosses.first { $0.id != state.campID }?.id ?? state.campID
            if state.lordEra {
                state.nextSpawnAt = s.time + lordRespawn(at: s.time)
            } else {
                // 6:00 以降に倒されたタートルの次は、タートルではなくロード
                state.nextIsLord = s.time + eps >= wyrmLastRespawnBefore
                state.nextSpawnAt = s.time + wyrmRespawn
            }
        }
        // 8:00 以降に生きているタートルは、5 秒ダメージを受けないと（遅くとも 9:00 に）その巣でロードになる（報酬なし）
        if !state.lordEra, s.time + eps >= lordStart, let w = alive, s.units[w].monster?.kind == .astralWyrm,
           s.time - s.units[w].lastDamagedTime + eps >= turtleToLordQuiet || s.time + eps >= turtleToLordDeadline,
           var camp = bosses.first(where: { $0.id == state.campID }) {
            s.units[w].isAlive = false
            s.units[w].hp = 0
            state.lordEra = true
            state.nextSpawnAt = nil
            camp.kind = .ancientColossus
            SpawnSystem.spawnCamp(&s, ctx, camp: camp)
        }
        if let at = state.nextSpawnAt, s.time + eps >= at,
           var camp = bosses.first(where: { $0.id == state.campID }) {
            if state.nextIsLord == true || at + eps >= lordStart { state.lordEra = true }
            camp.kind = state.lordEra ? .ancientColossus : .astralWyrm
            SpawnSystem.spawnCamp(&s, ctx, camp: camp)
            state.nextSpawnAt = nil
        }
        s.world.riverObjective = state
        syncTimers(&s, ctx)
        for i in s.units.indices where s.units[i].isAlive && s.units[i].monster?.kind == .ancientColossus {
            upgrade(&s, ctx, i)
            abilities(&s, ctx, i)
        }
    }

    /// 18:00 の進化（1 度だけ）。能力値は毎分の伸び（MonsterSystem.grow、18 分で止まる）。進化で変わるのは、味方になった
    /// ロードの加護（近くの味方の追加の魔法ダメージ）と被ダメ軽減（abilities）。
    static func upgrade(_ s: inout SimState, _ ctx: SimContext, _ i: Int) {
        let tier = s.time + SpawnSystem.timeEpsilon >= evolvedStart ? 2 : 0
        let old = s.units[i].monster?.lordTier ?? 0
        guard tier > old else { return }
        s.units[i].monster?.lordTier = tier
    }

    /// Send the captured Lord down our weakest lane (remaining allied tower HP, then lane order).
    static func capture(_ s: inout SimState, _ ctx: SimContext, team: Team) {
        let lane = ctx.map.lanes.min { a, b in
            func health(_ lane: Lane) -> Double {
                s.units.filter { $0.team == team && $0.kind == .tower && $0.tower?.lane == lane && $0.isAlive }
                    .reduce(0) { $0 + $1.hp }
            }
            return health(a) < health(b)
        } ?? .mid
        let path = ctx.map.lanePath(lane, for: team)
        guard let start = path.first else { return }
        let pos = ctx.nav.nearestWalkable(start, radius: 220)
        var lord = UnitFactory.makeMonster(kind: .ancientColossus, campID: -1, pos: pos, time: s.time)
        lord.team = team
        lord.minion = .init(type: .siege, lane: lane, spawnTime: s.time)
        s.addUnit(lord)
        upgrade(&s, ctx, s.units.count - 1)
    }

    static func refresh(_ s: inout SimState, _ i: Int, kind: StatusKind, magnitude: Double, tag: String,
                        duration: Double = 0.2) {
        if let k = s.units[i].statuses.firstIndex(where: { $0.tag == tag }) {
            s.units[i].statuses[k].remaining = duration
        } else {
            s.units[i].statuses.append(.init(kind: kind, duration: duration, magnitude: magnitude, tag: tag))
        }
    }

    static func abilities(_ s: inout SimState, _ ctx: SimContext, _ i: Int) {
        let tier = s.units[i].monster?.lordTier ?? 0
        if s.units[i].team == .neutral {
            neutralCombat(&s, ctx, i)
        } else {
            chargeTower(&s, ctx, i)
            alliedProtection(&s, i, evolved: tier >= 2)
        }
        guard tier >= 1 else { return }
        if s.time >= (s.units[i].monster?.lordChargeAt ?? 0),
           let t = s.index(of: s.units[i].attackTargetID), s.units[t].isAlive,
           s.units[i].pos.distance(to: s.units[t].pos) > s.units[i].stats.attackRange {
            refresh(&s, i, kind: .speedBoost, magnitude: 1.5, tag: "lord.charge", duration: 4)
            s.units[i].monster?.lordChargeAt = s.time + 12
        }
        let team = s.units[i].team
        guard team != .neutral else { return }
        let pos = s.units[i].pos
        for ally in s.units.indices where s.units[ally].team == team && s.units[ally].isAlive {
            if s.units[ally].kind == .minion {
                refresh(&s, ally, kind: .speedBoost, magnitude: 0.2, tag: "lord.march")
            } else if tier == 2 && s.units[ally].kind == .hero && s.units[ally].pos.distance(to: pos) <= Balance.Jungle.lordAuraRadius {
                // 近くの味方が敵ヒーローを攻撃すると追加の魔法ダメージ（JungleBuffs.lordAuraStrike、MLBB Patch 1.6.84）
                refresh(&s, ally, kind: .mark, magnitude: 1, tag: JungleBuffs.lordAuraTag)
            }
        }
    }

    /// 味方になったロード（8:00〜18:00）: 狙っている敵の塔へ突進し、届いたら塔の最大 HP の 30% の確定ダメージ
    /// （塔ごとに 1 回。MLBB Patch 1.9.64）。
    static func chargeTower(_ s: inout SimState, _ ctx: SimContext, _ i: Int) {
        let team = s.units[i].team
        guard team != .neutral, s.time < evolvedStart, let t = s.index(of: s.units[i].attackTargetID),
              s.units[t].isAlive, s.units[t].kind == .tower, s.units[t].team == team.opponent else { return }
        var charged = s.units[i].monster?.lordChargedTowers ?? []
        guard !charged.contains(s.units[t].id) else { return }
        guard CombatSystem.inAttackRange(s, attacker: i, target: t) else {
            refresh(&s, i, kind: .speedBoost, magnitude: 1.5, tag: "lord.towerCharge", duration: 0.5)
            return
        }
        charged.append(s.units[t].id)
        s.units[i].monster?.lordChargedTowers = charged
        s.units[i].statuses.removeAll { $0.tag == "lord.towerCharge" }
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[i].id, targetIndex: t,
                                 amount: s.units[t].stats.maxHP * Balance.Jungle.lordTowerChargeRatio,
                                 type: .trueDamage, source: .monster)
    }

    /// 味方になったロード: 18:00 の進化の後は、周りの味方ヒーロー 0〜5 人に応じて被ダメ 15〜35% 軽減（MLBB Patch 1.9.64）。
    static func alliedProtection(_ s: inout SimState, _ i: Int, evolved: Bool) {
        guard evolved else { return }
        typealias J = Balance.Jungle
        let r2 = J.lordAuraRadius * J.lordAuraRadius
        let pos = s.units[i].pos, team = s.units[i].team
        let n = s.heroIndices(team: team).filter {
            s.units[$0].isAlive && s.units[$0].hero?.isDead == false && s.units[$0].pos.distanceSquared(to: pos) <= r2
        }.count
        let dr = J.alliedLordBaseReduction + J.alliedLordReductionPerHero * Double(min(5, n))
        if let k = s.units[i].statuses.firstIndex(where: { $0.tag == "lord.evolved" }) {
            s.units[i].statuses[k].remaining = 0.2
            s.units[i].statuses[k].magnitude = dr
        } else {
            s.units[i].statuses.append(.init(kind: .damageReduction, duration: 0.2, magnitude: dr, tag: "lord.evolved"))
        }
    }

    /// 中立のロード: 戦闘中は毎秒 物理貫通 +10%（最大 10 回、MLBB Patch 1.8.92）、4 秒ごとに雷撃（周りの敵ヒーローに
    /// 50 + 対象の最大 HP の 15% の確定ダメージ、MLBB Patch 1.8.30。間隔は Fandom の Thunder Strike）。
    static func neutralCombat(_ s: inout SimState, _ ctx: SimContext, _ i: Int) {
        typealias J = Balance.Jungle
        guard s.units[i].monster?.leashing == false, s.units[i].attackTargetID != nil else {
            s.units[i].monster?.lordPenStacks = nil
            s.units[i].monster?.lordPenNextAt = nil
            s.units[i].monster?.lordStrikeAt = nil
            return
        }
        let now = s.time
        if now + SpawnSystem.timeEpsilon >= (s.units[i].monster?.lordPenNextAt ?? now) {
            let stacks = min(J.lordPenMaxStacks, (s.units[i].monster?.lordPenStacks ?? -1) + 1)
            s.units[i].monster?.lordPenStacks = stacks
            s.units[i].monster?.lordPenNextAt = now + 1
        }
        guard let at = s.units[i].monster?.lordStrikeAt else {
            s.units[i].monster?.lordStrikeAt = now + J.lordStrikeInterval
            return
        }
        guard now + SpawnSystem.timeEpsilon >= at else { return }
        s.units[i].monster?.lordStrikeAt = now + J.lordStrikeInterval
        let r = J.lordStrikeRadius + s.units[i].radius
        let pos = s.units[i].pos
        let lordID = s.units[i].id
        for t in s.units.indices where s.units[t].kind == .hero && s.units[t].team != .neutral
            && CombatSystem.isLiving(s, t) && s.units[t].pos.distanceSquared(to: pos) <= r * r {
            CombatSystem.applyDamage(&s, ctx, sourceID: lordID, targetIndex: t,
                                     amount: J.lordStrikeBase + J.lordStrikeTargetHPRatio * s.units[t].stats.maxHP,
                                     type: .trueDamage, source: .monster)
        }
    }

    /// 中立のロードが受けるダメージの倍率: 被ダメ軽減 40%、周り 500 のヒーロー 1 人ごとに −5%（下限 15%。MLBB Patch 1.6.42）。
    static func neutralLordDamageTakenMultiplier(_ s: SimState, _ i: Int) -> Double {
        guard s.units[i].team == .neutral, s.units[i].monster?.kind == .ancientColossus else { return 1 }
        typealias J = Balance.Jungle
        let r = J.lordReductionRadius + s.units[i].radius
        let pos = s.units[i].pos
        let n = s.units.indices.filter {
            s.units[$0].kind == .hero && s.units[$0].isAlive && s.units[$0].hero?.isDead == false
                && s.units[$0].pos.distanceSquared(to: pos) <= r * r
        }.count
        let dr = max(J.lordMinReduction, J.lordBaseReduction - J.lordReductionPerHero * Double(n))
        return 1 - dr
    }

    /// 川の流れが向かう巣（タートルの出現の 15 秒前から、そのタートルが倒されるまで。それ以外は nil）。MLBB Patch 1.9.90。
    static func riverCurrentTarget(_ s: SimState, _ ctx: SimContext) -> Vec2? {
        guard let state = s.world.riverObjective, !state.lordEra else { return nil }
        // ロードの前で次の出現が決まっていない = タートルが生きている（倒されると update が次の出現を決める）。毎 tick 全ユニットを見ない
        let turtleAlive = state.nextSpawnAt == nil
        var active = turtleAlive
        if !active, state.nextIsLord != true, let at = state.nextSpawnAt,
           s.time >= at - Balance.Jungle.riverCurrentLead, s.time < at {
            active = true
        }
        guard active else { return nil }
        return ctx.map.camps.first(where: { $0.id == state.campID })?.pos
    }

    /// Preserve the kind-based API for bots while the physical camp alternates.
    static func camp(_ s: SimState, _ ctx: SimContext, kind: CampKind) -> CampSpot? {
        guard let state = s.world.riverObjective else { return ctx.map.camps.first { $0.kind == kind } }
        let lordNext = state.lordEra || (state.nextIsLord == true && state.nextSpawnAt != nil)
        guard kind == (lordNext ? .ancientColossus : .astralWyrm),
              var camp = ctx.map.camps.first(where: { $0.id == state.campID }) else { return nil }
        camp.kind = kind
        return camp
    }
}
