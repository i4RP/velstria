import Foundation

public struct RiverObjectiveState: Codable, Hashable, Sendable {
    public var campID: Int
    public var nextSpawnAt: Double?
    public var lordEra = false
}

/// One neutral objective across both sanctuaries; the next kill moves it to the opposite bank.
public enum RiverObjectiveSystem {
    public static let lordStart: Double = 480
    public static let enhancedStart: Double = 720
    public static let evolvedStart: Double = 1080
    public static let lordRespawn: Double = 180

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
        if state.nextSpawnAt == nil && alive == nil {
            state.campID = bosses.first { $0.id != state.campID }?.id ?? state.campID
            state.nextSpawnAt = s.time + (state.lordEra ? lordRespawn : 120)
        }
        if !state.lordEra && s.time + SpawnSystem.timeEpsilon >= lordStart {
            state.lordEra = true
            state.nextSpawnAt = lordStart
            if let alive {
                s.units[alive].isAlive = false
                s.units[alive].hp = 0
            }
        }
        if let at = state.nextSpawnAt, s.time + SpawnSystem.timeEpsilon >= at,
           var camp = bosses.first(where: { $0.id == state.campID }) {
            camp.kind = state.lordEra ? .ancientColossus : .astralWyrm
            SpawnSystem.spawnCamp(&s, ctx, camp: camp)
            state.nextSpawnAt = nil
        }
        s.world.riverObjective = state
        syncTimers(&s, ctx)
        for i in s.units.indices where s.units[i].isAlive && s.units[i].monster?.kind == .ancientColossus {
            upgrade(&s, i)
            abilities(&s, ctx, i)
        }
    }

    static func upgrade(_ s: inout SimState, _ i: Int) {
        let tier = s.time >= evolvedStart ? 2 : s.time >= enhancedStart ? 1 : 0
        let old = s.units[i].monster?.lordTier ?? 0
        guard tier > old else { return }
        let hpFraction = s.units[i].hp / max(1, s.units[i].stats.maxHP)
        let profile = UnitFactory.monsterProfile(.ancientColossus)
        s.units[i].baseStats.maxHP = profile.maxHP * (tier == 2 ? 1.8 : 1.35)
        s.units[i].baseStats.attack = profile.attack * (tier == 2 ? 1.6 : 1.25)
        s.units[i].stats = s.units[i].baseStats
        s.units[i].hp = s.units[i].stats.maxHP * hpFraction
        s.units[i].monster?.lordTier = tier
        if tier == 2 {
            s.units[i].statuses.append(.init(kind: .damageReduction, duration: 3600, magnitude: 0.25, tag: "lord.evolved"))
        }
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
        var lord = UnitFactory.makeMonster(kind: .ancientColossus, campID: -1, pos: pos)
        lord.team = team
        lord.minion = .init(type: .siege, lane: lane, spawnTime: s.time)
        s.addUnit(lord)
        upgrade(&s, s.units.count - 1)
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
            } else if tier == 2 && s.units[ally].kind == .hero && s.units[ally].pos.distance(to: pos) <= 800 {
                refresh(&s, ally, kind: .mark, magnitude: 100, tag: "lord.magic")
            }
        }
    }

    /// Preserve the kind-based API for bots while the physical camp alternates.
    static func camp(_ s: SimState, _ ctx: SimContext, kind: CampKind) -> CampSpot? {
        guard let state = s.world.riverObjective else { return ctx.map.camps.first { $0.kind == kind } }
        guard kind == (state.lordEra ? .ancientColossus : .astralWyrm),
              var camp = ctx.map.camps.first(where: { $0.id == state.campID }) else { return nil }
        camp.kind = kind
        return camp
    }
}
