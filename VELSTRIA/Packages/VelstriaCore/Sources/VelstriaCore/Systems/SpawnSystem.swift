import Foundation

// 担当: core-world（最小実装。キャンプ出現・ボス・練習場人形・ミニオン強化を実装すること）

/// ワールド進行状態（ウェーブ・キャンプ）。
public struct WorldState: Codable, Hashable, Sendable {
    public var waveIndex = 0
    public var nextWaveTime: Double = Balance.firstWaveTime
    /// campID → 次回出現時刻（nil = 出現中）。index = CampSpot.id
    public var campRespawnAt: [Double?] = []

    public init() {}
}

public enum SpawnSystem {
    /// 試合開始時の配置（構造物・ヒーロー・人形）。
    public static func setupMatch(_ s: inout SimState, _ ctx: SimContext) {
        for spot in ctx.map.towers {
            s.addUnit(UnitFactory.makeStructure(spot))
        }
        let practice = ctx.config.mode == .practice || ctx.config.mode == .tutorial
        for (n, slot) in ctx.config.players.enumerated() {
            guard let def = ctx.master.hero(slot.heroID) else { continue }
            let perTeamIndex = ctx.config.players[..<n].filter { $0.team == slot.team }.count
            let angle = Double(perTeamIndex) * (Double.pi / 2) / 4
            let fountain = ctx.map.fountain(slot.team)
            let dir: Double = slot.team == .blue ? 1 : -1
            let pos = fountain + Vec2(cos(angle) * 300 * dir, sin(angle) * 300 * dir)
            let id = s.addUnit(UnitFactory.makeHero(def: def, slot: slot, pos: pos))
            if slot.controller == .human && s.humanHeroID == nil { s.humanHeroID = id }
            if practice, let p = ctx.config.practice, p.startLevel > 1, let i = s.index(of: id) {
                s.units[i].hero?.level = min(Balance.maxLevel, p.startLevel)
            }
        }
        s.world.campRespawnAt = ctx.map.camps.map { $0.firstSpawn }
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let practice = ctx.config.mode == .practice || ctx.config.mode == .tutorial
        if practice && ctx.config.practice?.spawnMinions == false { return }
        if s.time >= s.world.nextWaveTime {
            spawnWave(&s, ctx)
            s.world.waveIndex += 1
            s.world.nextWaveTime += Balance.waveInterval
        }
    }

    static func spawnWave(_ s: inout SimState, _ ctx: SimContext) {
        var types: [MinionType] = [.melee, .melee, .melee, .ranged, .ranged, .ranged]
        if (s.world.waveIndex + 1) % Balance.siegeEveryNWaves == 0 { types.insert(.siege, at: 3) }
        for team in Team.players {
            for lane in Lane.allCases {
                let path = ctx.map.lanePath(lane, for: team)
                let start = path[0]
                let dir = (path[1] - path[0]).normalized
                for (k, type) in types.enumerated() {
                    let pos = start + dir * (250 + Double(k) * 60) + dir.perpendicular * Double((k % 2) * 40 - 20)
                    s.addUnit(UnitFactory.makeMinion(type: type, team: team, lane: lane, pos: pos, time: s.time))
                }
            }
        }
        s.emit(.waveSpawned(index: s.world.waveIndex))
        if s.world.waveIndex == 0 { s.emit(.announcement(.minionsSpawned)) }
    }
}

/// ユニット生成（DESIGN §4 の基礎値）。
public enum UnitFactory {
    public static func makeHero(def: HeroDef, slot: PlayerSlot, pos: Vec2) -> Unit {
        let stats = HeroGrowth.baseStats(def: def, level: 1)
        var u = Unit(id: 0, kind: .hero, team: slot.team, pos: pos, radius: Balance.heroRadius, stats: stats)
        u.facing = slot.team == .blue ? Double.pi / 4 : -3 * Double.pi / 4
        u.hero = HeroData(heroID: def.heroID, role: def.role, isRanged: def.isRanged, resourceKind: def.resource,
                          controller: slot.controller, position: slot.position, displayName: slot.displayName,
                          botDifficulty: slot.botDifficulty, spells: slot.spells, runes: slot.runes, skinID: slot.skinID)
        u.hero?.autoLevelSkills = slot.autoLevelSkills
        return u
    }

    public static func makeStructure(_ spot: TowerSpot) -> Unit {
        var st = Stats()
        if spot.isCore {
            st.maxHP = 7000; st.attack = 360; st.armor = 110; st.magicResist = 110; st.attackRange = 800
        } else {
            switch spot.tier {
            case .outer: st.maxHP = 4200; st.attack = 260; st.armor = 80; st.magicResist = 80
            case .inner: st.maxHP = 4600; st.attack = 290; st.armor = 90; st.magicResist = 90
            case .base: st.maxHP = 5000; st.attack = 320; st.armor = 100; st.magicResist = 100
            }
            st.attackRange = 750
        }
        st.attackSpeed = 1
        st.sightRange = 1100
        var u = Unit(id: 0, kind: spot.isCore ? .core : .tower, team: spot.team, pos: spot.pos,
                     radius: spot.isCore ? 250 : 110, stats: st)
        u.tower = TowerData(lane: spot.lane, tier: spot.tier)
        return u
    }

    public static func makeMinion(type: MinionType, team: Team, lane: Lane, pos: Vec2, time: Double) -> Unit {
        let scale = 1 + Balance.minionScalingPerMinute * (time / 60)
        var st = Stats()
        let radius: Double
        switch type {
        case .melee:
            st.maxHP = 520; st.attack = 22; st.attackRange = 120; st.attackSpeed = 1 / 1.2; st.moveSpeed = 240; radius = 36
        case .ranged:
            st.maxHP = 330; st.attack = 32; st.attackRange = 500; st.attackSpeed = 1 / 1.5; st.moveSpeed = 240; radius = 32
        case .siege:
            st.maxHP = 950; st.attack = 55; st.attackRange = 550; st.attackSpeed = 1 / 2.0; st.moveSpeed = 230; radius = 48
            st.armor = 40; st.magicResist = 40
        }
        st.maxHP *= scale
        st.attack *= scale
        st.sightRange = 800
        var u = Unit(id: 0, kind: .minion, team: team, pos: pos, radius: radius, stats: st)
        u.minion = MinionData(type: type, lane: lane, spawnTime: time)
        return u
    }
}
