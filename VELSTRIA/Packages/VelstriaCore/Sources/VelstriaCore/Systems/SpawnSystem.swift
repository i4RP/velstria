import Foundation

// 担当: core-world。試合開始時の配置（構造物・ヒーロー・練習用人形）、ミニオンのウェーブ、
// 中立キャンプの出現/再出現、人形の回復・再出現。ユニットの基礎値は UnitFactory（DESIGN §4）。

/// ワールド進行状態（ウェーブ・キャンプ・練習用人形）。
public struct WorldState: Codable, Hashable, Sendable {
    public var waveIndex = 0
    public var nextWaveTime: Double = Balance.firstWaveTime
    /// campID → 次回出現時刻（nil = 出現中）。index = CampSpot.id
    public var campRespawnAt: [Double?] = []
    /// 練習用人形の定位置（index = 人形番号）。
    public var dummySpots: [Vec2] = []
    /// 人形の陣営（練習する人間の敵チーム）。
    public var dummyTeam: Team = .red
    /// 各人形の現在のエンティティ ID（nil = 撃破され再出現待ち）。
    public var dummyIDs: [EntityID?] = []
    /// 各人形の再出現時刻（nil = 出現中）。
    public var dummyRespawnAt: [Double?] = []

    public init() {}
}

public enum SpawnSystem {
    /// 時刻比較の許容誤差（tick × dt の丸め誤差対策）。
    static let timeEpsilon = 1e-6

    /// 試合開始時の配置（構造物・ヒーロー・人形）。
    public static func setupMatch(_ s: inout SimState, _ ctx: SimContext) {
        for spot in ctx.map.towers {
            s.addUnit(UnitFactory.makeStructure(spot))
        }
        let practice = isPracticeMode(ctx.config)
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

        if practice && (ctx.config.practice ?? PracticeOptions()).spawnDummies {
            s.world.dummyTeam = (ctx.config.humanSlot?.team ?? .blue).opponent
            s.world.dummySpots = dummySpots(ctx.map)
            s.world.dummyIDs = s.world.dummySpots.map { _ in nil }
            s.world.dummyRespawnAt = s.world.dummySpots.map { _ in nil }
            for k in s.world.dummySpots.indices { spawnDummy(&s, ctx, slot: k) }
        }
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        updateWaves(&s, ctx)
        updateCamps(&s, ctx)
        updateDummies(&s, ctx)
    }

    static func isPracticeMode(_ config: MatchConfig) -> Bool {
        config.mode == .practice || config.mode == .tutorial
    }

    // MARK: - ミニオン

    /// このウェーブの構成（前列から順: 近接 → 攻城 → 遠隔）。DESIGN §3。
    public static func waveComposition(waveIndex: Int, time: Double) -> [MinionType] {
        var melee = 3
        if time + timeEpsilon >= Balance.extraMeleeAfter { melee += 1 }
        var types = [MinionType](repeating: .melee, count: melee)
        if (waveIndex + 1) % Balance.siegeEveryNWaves == 0 { types.append(.siege) }
        types += [MinionType](repeating: .ranged, count: 3)
        return types
    }

    static func updateWaves(_ s: inout SimState, _ ctx: SimContext) {
        if isPracticeMode(ctx.config) && ctx.config.practice?.spawnMinions == false { return }
        if s.time + timeEpsilon >= s.world.nextWaveTime {
            spawnWave(&s, ctx)
            s.world.waveIndex += 1
            s.world.nextWaveTime += Balance.waveInterval
        }
    }

    static func spawnWave(_ s: inout SimState, _ ctx: SimContext) {
        let types = waveComposition(waveIndex: s.world.waveIndex, time: s.time)
        for team in Team.players {
            for lane in ctx.map.lanes {
                let path = ctx.map.lanePath(lane, for: team)
                let start = path[0]
                let dir = (path[1] - path[0]).normalized
                for (k, type) in types.enumerated() {
                    // 前列（近接）ほど Core から遠い。左右に少しずらして縦列の重なりを減らす
                    let along = Balance.minionSpawnDistance - Double(k) * Balance.minionSpawnSpacing
                    let side = Double((k % 2) * 2 - 1) * 30
                    let pos = ctx.nav.nearestWalkable(start + dir * along + dir.perpendicular * side, radius: 50)
                    var u = UnitFactory.makeMinion(type: type, team: team, lane: lane, pos: pos, time: s.time)
                    u.facing = dir.angle
                    s.addUnit(u)
                }
            }
        }
        s.emit(.waveSpawned(index: s.world.waveIndex))
        if s.world.waveIndex == 0 { s.emit(.announcement(.minionsSpawned)) }
    }

    // MARK: - 中立キャンプ

    /// キャンプの構成（モンスター種別と、キャンプ中心からの配置オフセット）。
    public static func campMembers(_ kind: CampKind) -> [(kind: MonsterKind, offset: Vec2)] {
        switch kind {
        case .small:
            return [(.campLarge, Vec2(0, 0)), (.campSmall, Vec2(-170, 150)), (.campSmall, Vec2(170, -150))]
        case .blueSentinel: return [(.blueSentinel, .zero)]
        case .redSentinel: return [(.redSentinel, .zero)]
        case .astralWyrm: return [(.astralWyrm, .zero)]
        case .ancientColossus: return [(.ancientColossus, .zero)]
        }
    }

    /// 全滅したキャンプに再出現時刻を設定し、時刻が来たキャンプを出現させる。
    static func updateCamps(_ s: inout SimState, _ ctx: SimContext) {
        let camps = ctx.map.camps
        if s.world.campRespawnAt.count != camps.count {
            s.world.campRespawnAt = camps.map { $0.firstSpawn }
        }
        var alive = [Int](repeating: 0, count: camps.count)
        for u in s.units where u.kind == .monster && u.isAlive {
            if let c = u.monster?.campID, c >= 0, c < alive.count { alive[c] += 1 }
        }
        for (k, camp) in camps.enumerated() {
            if let at = s.world.campRespawnAt[k] {
                if s.time + timeEpsilon >= at {
                    spawnCamp(&s, ctx, camp: camp)
                    s.world.campRespawnAt[k] = nil
                }
            } else if alive[k] == 0 {
                // 序盤ボスは 6:00 以降に倒されると再出現しない
                if camp.kind == .astralWyrm, s.time >= Balance.wyrmNoRespawnAfter { continue }
                s.world.campRespawnAt[k] = s.time + camp.respawn
            }
        }
    }

    static func spawnCamp(_ s: inout SimState, _ ctx: SimContext, camp: CampSpot) {
        // 配置オフセットは Red 側で点対称に反転する（マップの対称性を保つ）
        let flip: Double = camp.side == .red ? -1 : 1
        for member in campMembers(camp.kind) {
            let pos = ctx.nav.nearestWalkable(camp.pos + member.offset * flip,
                                              radius: UnitFactory.monsterProfile(member.kind).radius)
            var u = UnitFactory.makeMonster(kind: member.kind, campID: camp.id, pos: pos)
            u.facing = (Balance.mapCenter - camp.pos).angle
            s.addUnit(u)
        }
        switch camp.kind {
        case .astralWyrm: s.emit(.announcement(.wyrmSpawned))
        case .ancientColossus: s.emit(.announcement(.colossusSpawned))
        default: break
        }
    }

    // MARK: - 練習用人形

    /// ミニオンが進軍できるよう人形を退場させ、再出現も止める。
    static func removeTutorialDummies(_ s: inout SimState) {
        for i in s.units.indices where s.units[i].kind == .dummy {
            // 添字は tick 末尾まで維持する。撃破イベント・報酬は発生させない。
            s.units[i].isAlive = false
            s.units[i].hp = 0
        }
        s.world.dummySpots.removeAll()
        s.world.dummyIDs.removeAll()
        s.world.dummyRespawnAt.removeAll()
    }

    /// Blue mid 外塔の前方（タワー射程外）に横一列。
    static func dummySpots(_ map: MapDefinition) -> [Vec2] {
        let tower = map.towers.first { $0.team == .blue && $0.lane == .mid && $0.tier == .outer && !$0.isCore }?.pos
            ?? Vec2(4300, 4300)
        let dir = (map.core(.red) - map.core(.blue)).normalized
        let front = tower + dir * Balance.dummyForwardDistance
        return [-1.0, 0, 1].map { front + dir.perpendicular * ($0 * Balance.dummySpacing) }
    }

    static func spawnDummy(_ s: inout SimState, _ ctx: SimContext, slot k: Int) {
        let pos = ctx.nav.nearestWalkable(s.world.dummySpots[k], radius: Balance.dummyRadius)
        var u = UnitFactory.makeDummy(team: s.world.dummyTeam, pos: pos)
        u.facing = (ctx.map.fountain(s.world.dummyTeam.opponent) - pos).angle
        let id = s.addUnit(u)
        s.world.dummyIDs[k] = id
        s.world.dummyRespawnAt[k] = nil
    }

    /// 最後の被ダメから一定時間で全回復、撃破されたら一定時間後に再出現。常に両チームから可視。
    static func updateDummies(_ s: inout SimState, _ ctx: SimContext) {
        for k in s.world.dummySpots.indices {
            if let id = s.world.dummyIDs[k] {
                guard let i = s.index(of: id), s.units[i].isAlive else {
                    s.world.dummyIDs[k] = nil
                    s.world.dummyRespawnAt[k] = s.time + Balance.dummyRespawnDelay
                    continue
                }
                if s.units[i].hp < s.units[i].stats.maxHP && s.time - s.units[i].lastDamagedTime >= Balance.dummyRegenDelay {
                    let amount = s.units[i].stats.maxHP - s.units[i].hp
                    s.units[i].hp = s.units[i].stats.maxHP
                    s.emit(.heal(targetID: id, sourceID: nil, amount: amount))
                }
                keepRevealed(&s, i)
            } else if let at = s.world.dummyRespawnAt[k], s.time + timeEpsilon >= at {
                spawnDummy(&s, ctx, slot: k)
            }
        }
    }

    static func keepRevealed(_ s: inout SimState, _ i: Int) {
        if let k = s.units[i].statuses.firstIndex(where: { $0.kind == .revealed && $0.tag == UnitFactory.dummyTag }) {
            s.units[i].statuses[k].remaining = 60
        } else {
            s.units[i].statuses.append(StatusEffect(kind: .revealed, duration: 60, tag: UnitFactory.dummyTag))
        }
    }
}

/// 中立モンスターの基礎値（DESIGN §4）。
public struct MonsterProfile: Hashable, Sendable {
    public var maxHP: Double
    public var attack: Double
    /// 攻撃間隔（秒）。
    public var attackInterval: Double
    public var armor: Double
    public var magicResist: Double
    public var radius: Double
    public var attackRange: Double
    public var moveSpeed: Double
    public var isBoss: Bool

    /// リーシュ半径（巣からこれ以上離れたら帰還）。
    public var leashRadius: Double { isBoss ? Balance.bossLeashRadius : Balance.leashRadius }
}

/// ユニット生成（DESIGN §4 の基礎値）。
public enum UnitFactory {
    static let dummyTag = "practice_dummy"

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
            st.maxHP = 7000; st.attack = 360; st.armor = 110; st.magicResist = 110; st.attackRange = Balance.coreRange
        } else {
            switch spot.tier {
            case .outer: st.maxHP = 4200; st.attack = 260; st.armor = 80; st.magicResist = 80
            case .inner: st.maxHP = 4600; st.attack = 290; st.armor = 90; st.magicResist = 90
            case .base: st.maxHP = 5000; st.attack = 320; st.armor = 100; st.magicResist = 100
            }
            st.attackRange = Balance.towerRange
        }
        st.maxHP *= Balance.structureHPScale
        st.attackSpeed = 1
        st.sightRange = Balance.towerSight
        var u = Unit(id: 0, kind: spot.isCore ? .core : .tower, team: spot.team, pos: spot.pos,
                     radius: spot.isCore ? Balance.coreRadius : Balance.towerRadius, stats: st)
        u.facing = (Balance.mapCenter - spot.pos).angle
        u.tower = TowerData(lane: spot.lane, tier: spot.tier)
        // 外塔にはエネルギーシールド（開始〜5:00）。参照仕様 §5.4
        if !spot.isCore, spot.tier == .outer {
            u.shields.append(Shield(amount: Balance.outerTowerShield, duration: Balance.outerTowerShieldDuration,
                                    tag: TowerSystem.shieldTag))
        }
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
        st.sightRange = Balance.minionSight
        var u = Unit(id: 0, kind: .minion, team: team, pos: pos, radius: radius, stats: st)
        u.minion = MinionData(type: type, lane: lane, spawnTime: time)
        return u
    }

    /// 中立モンスターの基礎値。
    public static func monsterProfile(_ kind: MonsterKind) -> MonsterProfile {
        switch kind {
        case .campLarge:
            return MonsterProfile(maxHP: 900, attack: 40, attackInterval: 1.2, armor: 15, magicResist: 15,
                                  radius: 80, attackRange: 125, moveSpeed: 250, isBoss: false)
        case .campSmall:
            return MonsterProfile(maxHP: 400, attack: 20, attackInterval: 1.2, armor: 15, magicResist: 15,
                                  radius: 50, attackRange: 110, moveSpeed: 260, isBoss: false)
        case .blueSentinel, .redSentinel:
            return MonsterProfile(maxHP: 2200, attack: 65, attackInterval: 1.2, armor: 25, magicResist: 25,
                                  radius: 110, attackRange: 150, moveSpeed: 250, isBoss: false)
        case .astralWyrm:
            return MonsterProfile(maxHP: 5500, attack: 120, attackInterval: 1.5, armor: 40, magicResist: 40,
                                  radius: 180, attackRange: 175, moveSpeed: 230, isBoss: true)
        case .ancientColossus:
            return MonsterProfile(maxHP: 9000, attack: 180, attackInterval: 1.5, armor: 60, magicResist: 60,
                                  radius: 220, attackRange: 175, moveSpeed: 220, isBoss: true)
        }
    }

    /// 中立モンスター（team = neutral、巣 = 出現位置）。
    public static func makeMonster(kind: MonsterKind, campID: Int, pos: Vec2) -> Unit {
        let p = monsterProfile(kind)
        var st = Stats()
        st.maxHP = p.maxHP
        st.attack = p.attack
        st.attackSpeed = 1 / p.attackInterval
        st.armor = p.armor
        st.magicResist = p.magicResist
        st.attackRange = p.attackRange
        st.moveSpeed = p.moveSpeed
        var u = Unit(id: 0, kind: .monster, team: .neutral, pos: pos, radius: p.radius, stats: st)
        u.monster = MonsterData(kind: kind, campID: campID, home: pos)
        return u
    }

    /// 練習用人形（攻撃・移動しない、3000 HP、防御/魔防 30、常に可視）。
    public static func makeDummy(team: Team, pos: Vec2) -> Unit {
        var st = Stats()
        st.maxHP = Balance.dummyHP
        st.armor = Balance.dummyArmor
        st.magicResist = Balance.dummyArmor
        st.attackSpeed = 1
        var u = Unit(id: 0, kind: .dummy, team: team, pos: pos, radius: Balance.dummyRadius, stats: st)
        u.statuses.append(StatusEffect(kind: .revealed, duration: 60, tag: dummyTag))
        // 次の視界更新（最大 3 tick 後）を待たずに出現直後から狙えるようにする
        u.visibleMask = Team.blue.visionBit | Team.red.visionBit
        return u
    }
}
