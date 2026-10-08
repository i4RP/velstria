import Foundation

public struct TeamState: Codable, Hashable, Sendable {
    public var team: Team
    public var kills = 0
    public var towersDestroyed = 0
    public var wyrmKills = 0
    public var colossusKills = 0
    /// 全滅告知済みの時刻（重複防止）。
    public var lastAceTime: Double = -999

    public init(team: Team) {
        self.team = team
    }
}

public struct PendingDeath: Codable, Hashable, Sendable {
    public var victimID: EntityID
    public var killerID: EntityID?
    public var time: Double

    public init(victimID: EntityID, killerID: EntityID?, time: Double) {
        self.victimID = victimID
        self.killerID = killerID
        self.time = time
    }
}

/// シミュレーションの全状態（値型）。Codable でスナップショット化できる（再接続・デバッグ）。
///
/// 決定論ルール:
/// - `Dictionary` / `Set` を列挙しない（Swift のハッシュ順はプロセス毎にランダム）。列挙は配列で ID 順。
/// - 乱数は `rng` のみ。`Date()` などの実時間を参照しない。
public struct SimState: Codable, Sendable {
    public var config: MatchConfig
    public var tick: Int = 0
    public var time: Double = 0
    public var phase: MatchPhase = .loading
    public var winner: Team?
    public var endReason: EndReason?
    public var rng: SplitMix64
    public var nextEntityID: EntityID = 1

    public var units: [Unit] = []
    public var projectiles: [Projectile] = []
    public var zones: [AreaZone] = []
    /// index = Team.rawValue（0: blue, 1: red）。
    public var teams: [TeamState] = [TeamState(team: .blue), TeamState(team: .red)]
    public var pendingDeaths: [PendingDeath] = []
    /// 当 tick に発生したイベント（Simulation.step が回収してクリア）。
    public var events: [SimEvent] = []
    public var firstBloodTaken = false

    public var world = WorldState()
    public var vision = VisionState()
    public var surrender = SurrenderState()
    public var bots = BotState()

    /// 人間プレイヤーのヒーロー（観戦では nil）。
    public var humanHeroID: EntityID?

    /// ID → units 添字（検索専用・列挙禁止）。
    private var indexByID: [EntityID: Int] = [:]

    enum CodingKeys: String, CodingKey {
        case config, tick, time, phase, winner, endReason, rng, nextEntityID, units, projectiles, zones
        case teams, pendingDeaths, events, firstBloodTaken, world, vision, surrender, bots, humanHeroID
    }

    public init(config: MatchConfig) {
        self.config = config
        self.rng = SplitMix64(seed: config.seed)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        config = try c.decode(MatchConfig.self, forKey: .config)
        tick = try c.decode(Int.self, forKey: .tick)
        time = try c.decode(Double.self, forKey: .time)
        phase = try c.decode(MatchPhase.self, forKey: .phase)
        winner = try c.decodeIfPresent(Team.self, forKey: .winner)
        endReason = try c.decodeIfPresent(EndReason.self, forKey: .endReason)
        rng = try c.decode(SplitMix64.self, forKey: .rng)
        nextEntityID = try c.decode(EntityID.self, forKey: .nextEntityID)
        units = try c.decode([Unit].self, forKey: .units)
        projectiles = try c.decode([Projectile].self, forKey: .projectiles)
        zones = try c.decode([AreaZone].self, forKey: .zones)
        teams = try c.decode([TeamState].self, forKey: .teams)
        pendingDeaths = try c.decode([PendingDeath].self, forKey: .pendingDeaths)
        events = try c.decode([SimEvent].self, forKey: .events)
        firstBloodTaken = try c.decode(Bool.self, forKey: .firstBloodTaken)
        world = try c.decode(WorldState.self, forKey: .world)
        vision = try c.decode(VisionState.self, forKey: .vision)
        surrender = try c.decode(SurrenderState.self, forKey: .surrender)
        bots = try c.decode(BotState.self, forKey: .bots)
        humanHeroID = try c.decodeIfPresent(EntityID.self, forKey: .humanHeroID)
        rebuildIndex()
    }

    // MARK: - ID 管理

    public mutating func allocateID() -> EntityID {
        let id = nextEntityID
        nextEntityID += 1
        return id
    }

    /// ユニットを追加し ID を返す（unit.id は上書きされる）。
    @discardableResult
    public mutating func addUnit(_ unit: Unit) -> EntityID {
        var u = unit
        u.id = allocateID()
        indexByID[u.id] = units.count
        units.append(u)
        emit(.unitSpawned(unitID: u.id, kind: u.kind, team: u.team, pos: u.pos))
        return u.id
    }

    public func index(of id: EntityID?) -> Int? {
        guard let id else { return nil }
        return indexByID[id]
    }

    public func unit(_ id: EntityID?) -> Unit? {
        guard let i = index(of: id) else { return nil }
        return units[i]
    }

    public mutating func rebuildIndex() {
        indexByID.removeAll(keepingCapacity: true)
        for (i, u) in units.enumerated() { indexByID[u.id] = i }
    }

    public mutating func emit(_ event: SimEvent) {
        events.append(event)
    }

    // MARK: - 便利クエリ（戻り値は units の添字、昇順 = 決定論的）

    public var heroIndices: [Int] { units.indices.filter { units[$0].kind == .hero } }

    public func heroIndices(team: Team) -> [Int] {
        units.indices.filter { units[$0].kind == .hero && units[$0].team == team }
    }

    public var humanHeroIndex: Int? { index(of: humanHeroID) }

    /// team から見て unit i が見えているか。
    public func isVisible(_ i: Int, to team: Team) -> Bool {
        let u = units[i]
        if u.team == team || team == .neutral { return true }
        return u.visibleMask & team.visionBit != 0
    }

    /// team の敵として攻撃・スキル対象にできるか（生存・視認・中立含む）。
    public func isTargetableEnemy(_ i: Int, of team: Team) -> Bool {
        let u = units[i]
        guard u.isAlive, u.team != team else { return false }
        if u.kind == .hero, u.hero?.isDead == true { return false }
        // 対象不可（キット層）。範囲・直線の命中は別経路なので当たる
        if !u.statuses.isEmpty, u.has(.untargetable) { return false }
        return isVisible(i, to: team)
    }

    /// center から radius（+対象半径）以内の、team にとっての敵（中立モンスター含む）。
    public func enemies(of team: Team, near center: Vec2, radius: Double,
                        kinds: Set<UnitKind>? = nil, requireVisible: Bool = true) -> [Int] {
        units.indices.filter { i in
            let u = units[i]
            guard u.isAlive, u.team != team else { return false }
            if u.kind == .hero, u.hero?.isDead == true { return false }
            if let kinds, !kinds.contains(u.kind) { return false }
            if requireVisible && !isVisible(i, to: team) { return false }
            if !u.statuses.isEmpty, u.has(.untargetable) { return false }
            let r = radius + u.radius
            return u.pos.distanceSquared(to: center) <= r * r
        }
    }

    /// center から radius 以内の team の味方（生存）。
    public func allies(of team: Team, near center: Vec2, radius: Double, kinds: Set<UnitKind>? = nil) -> [Int] {
        units.indices.filter { i in
            let u = units[i]
            guard u.isAlive, u.team == team else { return false }
            if u.kind == .hero, u.hero?.isDead == true { return false }
            if let kinds, !kinds.contains(u.kind) { return false }
            let r = radius + u.radius
            return u.pos.distanceSquared(to: center) <= r * r
        }
    }

    /// 候補のうち center に最も近いもの（同距離は添字の小さい方）。
    public func nearest(_ candidates: [Int], to center: Vec2) -> Int? {
        var best: Int?
        var bestD = Double.infinity
        for i in candidates {
            let d = units[i].pos.distanceSquared(to: center)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// 死亡したミニオン・モンスター・人形、完了した投射物・ゾーンを除去し索引を再構築する（tick 末尾で呼ぶ）。
    public mutating func removeFinishedEntities() {
        let before = units.count
        units.removeAll { u in
            !u.isAlive && (u.kind == .minion || u.kind == .monster || u.kind == .dummy)
        }
        if units.count != before { rebuildIndex() }
        projectiles.removeAll { $0.done }
        zones.removeAll { $0.done }
    }
}
