import Foundation

// 担当: core-world。試合開始時の配置（構造物・ヒーロー・練習用人形）、ミニオンのウェーブ、
// 中立キャンプの出現/再出現、人形の回復・再出現。ユニットの基礎値は UnitFactory（DESIGN §4）。

/// ワールド進行状態（ウェーブ・キャンプ・練習用人形）。
public struct WorldState: Codable, Hashable, Sendable {
    public var waveIndex = 0
    public var nextWaveTime: Double = Balance.firstWaveTime
    /// campID → 次回出現時刻（nil = 出現中）。index = CampSpot.id
    public var campRespawnAt: [Double?] = []
    /// Optional for older replay snapshots. The compact map shares one alternating river objective.
    public var riverObjective: RiverObjectiveState?
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
            s.addUnit(UnitFactory.makeStructure(spot, mapSize: ctx.map.size))
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
        RiverObjectiveSystem.setup(&s, ctx)

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
    /// 宝殻蟹は 3:00 までは子（`crablet`）が出る（`campMembers(_:time:)`）。
    public static func campMembers(_ kind: CampKind) -> [(kind: MonsterKind, offset: Vec2)] {
        switch kind {
        case .small:
            return [(.campLarge, Vec2(0, 0)), (.campSmall, Vec2(-170, 150)), (.campSmall, Vec2(170, -150))]
        // 紫バフは大小 2 体（MLBB の雷狼の親子）
        case .blueSentinel: return [(.blueSentinel, .zero), (.azureWhelp, Vec2(-190, 170))]
        case .redSentinel: return [(.redSentinel, .zero)]
        case .astralWyrm: return [(.astralWyrm, .zero)]
        case .ancientColossus: return [(.ancientColossus, .zero)]
        case .hornLizard: return [(.hornLizard, .zero)]
        case .emberBeetle: return [(.emberBeetle, .zero)]
        case .magmaGolem: return [(.magmaGolem, .zero)]
        case .treasureCrab: return [(.treasureCrab, .zero)]
        case .mossWanderer: return [(.mossWanderer, .zero)]
        }
    }

    /// 出現時刻での構成（宝殻蟹の子は現行の MLBB に無いので、いつも親）。
    static func campMembers(_ kind: CampKind, time: Double) -> [(kind: MonsterKind, offset: Vec2)] {
        campMembers(kind)
    }

    /// 全滅後の再出現時刻。
    static func nextSpawn(_ camp: CampSpot, now: Double) -> Double {
        now + camp.respawn
    }

    /// 全滅したキャンプに再出現時刻を設定し、時刻が来たキャンプを出現させる。
    static func updateCamps(_ s: inout SimState, _ ctx: SimContext) {
        let camps = ctx.map.camps
        if s.world.campRespawnAt.count != camps.count {
            s.world.campRespawnAt = camps.map { $0.firstSpawn }
        }
        RiverObjectiveSystem.update(&s, ctx)
        var alive = [Int](repeating: 0, count: camps.count)
        for u in s.units where u.kind == .monster && u.isAlive {
            if let c = u.monster?.campID, c >= 0, c < alive.count { alive[c] += 1 }
        }
        // 宝殻蟹はロードが出た後は湧かない（MLBB Patch 1.8.56。生きている蟹は残る）
        let crabsClosed = s.world.riverObjective.map { $0.lordEra } ?? (s.time + timeEpsilon >= RiverObjectiveSystem.lordStart)
        for (k, camp) in camps.enumerated() {
            if s.world.riverObjective != nil && camp.kind.isBoss { continue }
            if crabsClosed, camp.kind == .treasureCrab, alive[k] == 0 {
                s.world.campRespawnAt[k] = Double.greatestFiniteMagnitude
                continue
            }
            if let at = s.world.campRespawnAt[k] {
                if s.time + timeEpsilon >= at {
                    spawnCamp(&s, ctx, camp: camp)
                    s.world.campRespawnAt[k] = nil
                }
            } else if alive[k] == 0 {
                // 序盤ボスは 6:00 以降に倒されると再出現しない
                if camp.kind == .astralWyrm, s.time >= Balance.wyrmNoRespawnAfter { continue }
                s.world.campRespawnAt[k] = nextSpawn(camp, now: s.time)
            }
        }
    }

    static func spawnCamp(_ s: inout SimState, _ ctx: SimContext, camp: CampSpot) {
        // 配置オフセットは Red 側で点対称に反転する（マップの対称性を保つ）
        let flip: Double = camp.side == .red ? -1 : 1
        for member in campMembers(camp.kind, time: s.time) {
            let pos = ctx.nav.nearestWalkable(camp.pos + member.offset * flip,
                                              radius: UnitFactory.monsterProfile(member.kind).radius)
            var u = UnitFactory.makeMonster(kind: member.kind, campID: camp.id, pos: pos, time: s.time)
            u.facing = (Vec2(ctx.map.size / 2, ctx.map.size / 2) - camp.pos).angle
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
            ?? Vec2(4650, 4650)
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
    /// 毎分の HP の伸び（MLBB の「HP +x/分」）。maxHP は試合開始時（0:00）の値。
    public var hpPerMinute: Double = 0
    /// 毎分の物理攻撃の伸び。
    public var attackPerMinute: Double = 0
    /// 毎分の物理防御・魔法防御の伸び。
    public var armorPerMinute: Double = 0
    public var magicResistPerMinute: Double = 0
    /// 伸びが止まる分（ロードは 18 分）。nil は止まらない。
    public var growthCapMinutes: Double?

    /// リーシュ半径（巣からこれ以上離れたら帰還）。
    public var leashRadius: Double { isBoss ? Balance.bossLeashRadius : Balance.leashRadius }

    /// 伸びに数える分（試合時間の分を切り捨て、上限あり）。
    public func growthMinutes(at time: Double) -> Double {
        let m = (max(0, time) / 60 + 1e-9).rounded(.down)
        return growthCapMinutes.map { min($0, m) } ?? m
    }

    /// time の時点の最大 HP（初期値 + 毎分の伸び）。
    public func maxHP(at time: Double) -> Double { maxHP + hpPerMinute * growthMinutes(at: time) }

    /// time の時点の物理攻撃（初期値 + 毎分の伸び）。
    public func attack(at time: Double) -> Double { attack + attackPerMinute * growthMinutes(at: time) }

    /// time の時点の物理防御・魔法防御（初期値 + 毎分の伸び）。
    public func armor(at time: Double) -> Double { armor + armorPerMinute * growthMinutes(at: time) }
    public func magicResist(at time: Double) -> Double { magicResist + magicResistPerMinute * growthMinutes(at: time) }
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
                          botDifficulty: slot.botDifficulty, spells: slot.spells,
                          emblem: slot.emblem.map { $0.isValid ? $0 : EmblemCatalog.defaultLoadout(set: $0.set) },
                          skinID: slot.skinID)
        u.hero?.autoLevelSkills = slot.autoLevelSkills
        u.hero?.buildPlan = slot.buildPlan
        // キットが有効なヒーローだけ状態を持つ（無効なら nil のまま = これまでと同じ）
        if HeroKits.hasKit(def.heroID) { u.hero?.kit = KitState() }
        return u
    }

    public static func makeStructure(_ spot: TowerSpot, mapSize: Double = Balance.mapSize) -> Unit {
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
        u.facing = (Vec2(mapSize / 2, mapSize / 2) - spot.pos).angle
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
        if lane != .mid { st.moveSpeed *= Balance.sideLaneMinionSpeedMultiplier }
        st.maxHP *= scale
        st.attack *= scale
        st.sightRange = Balance.minionSight
        var u = Unit(id: 0, kind: .minion, team: team, pos: pos, radius: radius, stats: st)
        u.minion = MinionData(type: type, lane: lane, spawnTime: time)
        return u
    }

    /// 中立モンスターの基礎値。
    public static func monsterProfile(_ kind: MonsterKind) -> MonsterProfile {
        typealias J = Balance.Jungle
        switch kind {
        case .campLarge:
            return MonsterProfile(maxHP: 900, attack: 40, attackInterval: 1.2, armor: 15, magicResist: 15,
                                  radius: 80, attackRange: 125, moveSpeed: 250, isBoss: false)
        case .campSmall:
            return MonsterProfile(maxHP: 400, attack: 20, attackInterval: 1.2, armor: 15, magicResist: 15,
                                  radius: 50, attackRange: 110, moveSpeed: 260, isBoss: false)
        // ジャングル: Fandom の表（初期値 / 毎分）に、その後の公式の変更率を掛けた値（docs/JUNGLE_ROAM_MLBB.md）。
        // バフ 2 体と小キャンプ 3 種は Patch 1.9.90 の HP +30%・攻撃 −15%。攻撃間隔・半径・射程・速さは旧来の値。
        case .redSentinel:
            return MonsterProfile(maxHP: 4941 * J.campHPScale1990, attack: 214 * J.campAttackScale1990, attackInterval: 1.2,
                                  armor: 37, magicResist: 37, radius: 110, attackRange: 150, moveSpeed: 250, isBoss: false,
                                  hpPerMinute: 158.22 * J.campHPScale1990, attackPerMinute: 3.84 * J.campAttackScale1990,
                                  armorPerMinute: 2, magicResistPerMinute: 2)
        case .blueSentinel:
            return MonsterProfile(maxHP: 4090 * J.campHPScale1990, attack: 226 * J.campAttackScale1990, attackInterval: 1.2,
                                  armor: 60, magicResist: 0, radius: 110, attackRange: 150, moveSpeed: 250, isBoss: false,
                                  hpPerMinute: 230.22 * J.campHPScale1990, attackPerMinute: 3.84 * J.campAttackScale1990,
                                  armorPerMinute: 2)
        case .azureWhelp:
            // 仔: HP は低いが攻撃が速い
            return MonsterProfile(maxHP: 450, attack: 30, attackInterval: 0.8, armor: 15, magicResist: 0,
                                  radius: 60, attackRange: 120, moveSpeed: 270, isBoss: false)
        case .hornLizard:
            // 遠隔（舌の攻撃）。HP が半分を切ると防御 +70（MonsterSystem）
            return MonsterProfile(maxHP: 3019 * J.campHPScale1990, attack: 110 * J.campAttackScale1990, attackInterval: 1.0,
                                  armor: 37, magicResist: 37, radius: 80, attackRange: 400, moveSpeed: 250, isBoss: false,
                                  hpPerMinute: 156.69 * J.campHPScale1990, attackPerMinute: 2.30 * J.campAttackScale1990)
        case .emberBeetle:
            return MonsterProfile(maxHP: 2501 * J.campHPScale1990, attack: 113 * J.campAttackScale1990, attackInterval: 1.0,
                                  armor: 37, magicResist: 37, radius: 80, attackRange: 130, moveSpeed: 260, isBoss: false,
                                  hpPerMinute: 126.69 * J.campHPScale1990, attackPerMinute: 2.30 * J.campAttackScale1990)
        case .emberGrub:
            return MonsterProfile(maxHP: 300, attack: 18, attackInterval: 1.0, armor: 10, magicResist: 10,
                                  radius: 50, attackRange: 110, moveSpeed: 270, isBoss: false)
        case .magmaGolem:
            return MonsterProfile(maxHP: 3000 * J.campHPScale1990, attack: 156 * J.campAttackScale1990, attackInterval: 1.0,
                                  armor: 37, magicResist: 37, radius: 95, attackRange: 140, moveSpeed: 240, isBoss: false,
                                  hpPerMinute: 81.50 * J.campHPScale1990, attackPerMinute: 2.30 * J.campAttackScale1990)
        case .treasureCrab:
            // 防御 0（Patch 1.9.90）
            return MonsterProfile(maxHP: 3640, attack: 55, attackInterval: 1.0, armor: 0, magicResist: 0,
                                  radius: 85, attackRange: 130, moveSpeed: 250, isBoss: false, hpPerMinute: 384.30,
                                  attackPerMinute: 1.15)
        case .crablet:
            return MonsterProfile(maxHP: 650, attack: 10, attackInterval: 1.0, armor: 10, magicResist: 10,
                                  radius: 55, attackRange: 110, moveSpeed: 260, isBoss: false)
        case .mossWanderer:
            // 反撃しない（攻撃 0）。物理に硬く魔法に弱い（MLBB: 物防 60・魔防 0）
            return MonsterProfile(maxHP: 2251, attack: 0, attackInterval: 1.0, armor: 60, magicResist: 0,
                                  radius: 75, attackRange: 100, moveSpeed: 220, isBoss: false, hpPerMinute: 345.90)
        case .astralWyrm:
            // MLBB のタートル（攻撃間隔 1 秒は Fandom）
            return MonsterProfile(maxHP: 10367, attack: 260, attackInterval: 1.0, armor: 15, magicResist: 15,
                                  radius: 180, attackRange: 175, moveSpeed: 230, isBoss: true, hpPerMinute: 1067.15,
                                  attackPerMinute: 21.72, armorPerMinute: 10, magicResistPerMinute: 10)
        case .ancientColossus:
            // MLBB のロード（能力値は 18 分で伸びが止まる。攻撃間隔 1 秒は Fandom）
            return MonsterProfile(maxHP: 31743, attack: 428, attackInterval: 1.0, armor: 37, magicResist: 37,
                                  radius: 220, attackRange: 175, moveSpeed: 220, isBoss: true, hpPerMinute: 2242,
                                  attackPerMinute: 20.15, growthCapMinutes: J.lordGrowthCapMinutes)
        }
    }

    /// 中立モンスター（team = neutral、巣 = 出現位置）。HP・攻撃は出現した時刻（time）の値で、その後も毎分伸びる
    /// （MonsterSystem.grow）。
    public static func makeMonster(kind: MonsterKind, campID: Int, pos: Vec2, time: Double = 0) -> Unit {
        let p = monsterProfile(kind)
        var st = Stats()
        st.maxHP = p.maxHP(at: time)
        st.attack = p.attack(at: time)
        st.attackSpeed = 1 / p.attackInterval
        st.armor = p.armor(at: time)
        st.magicResist = p.magicResist(at: time)
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
