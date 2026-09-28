import Foundation

public enum Controller: Int, Codable, Hashable, Sendable {
    case human
    case bot
}

/// 試合中の個人成績。
public struct HeroScore: Codable, Hashable, Sendable {
    public var kills = 0
    public var deaths = 0
    public var assists = 0
    public var minionKills = 0
    public var monsterKills = 0
    public var goldEarned: Double = 0
    public var damageToHeroes: Double = 0
    public var damageTaken: Double = 0
    public var healingDone: Double = 0
    public var shieldingDone: Double = 0
    public var towerDamage: Double = 0
    public var towersDestroyed = 0
    public var objectivesTaken = 0
    public var largestKillStreak = 0
    public var largestMultiKill = 0

    public var creepScore: Int { minionKills + monsterKills }
    public var kda: Double { Double(kills + assists) / Double(max(1, deaths)) }

    public init() {}
}

/// スキル担当が自由に使う汎用パッシブ状態。
public struct PassiveState: Codable, Hashable, Sendable {
    public var stacks = 0
    public var timer: Double = 0
    public var cooldown: Double = 0
    public var flag = false
    public var value: Double = 0
    public var lastTriggerTime: Double = -999

    public init() {}
}

/// 次の通常攻撃を強化する効果（遠隔 Skill2 等）。
public struct EmpoweredAttack: Codable, Hashable, Sendable {
    public var bonusDamage: Double
    public var damageType: DamageType
    public var cc: CrowdControl
    public var remaining: Double
    public var visual: String

    public init(bonusDamage: Double, damageType: DamageType, cc: CrowdControl = .none,
                remaining: Double = 4, visual: String = "") {
        self.bonusDamage = bonusDamage
        self.damageType = damageType
        self.cc = cc
        self.remaining = remaining
        self.visual = visual
    }
}

public struct DamageRecord: Codable, Hashable, Sendable {
    public var sourceID: EntityID
    public var time: Double

    public init(sourceID: EntityID, time: Double) {
        self.sourceID = sourceID
        self.time = time
    }
}

public struct HeroData: Codable, Hashable, Sendable {
    public var heroID: String
    public var role: Role
    public var isRanged: Bool
    public var resourceKind: ResourceKind
    public var controller: Controller
    public var position: LanePosition
    public var displayName: String
    public var botDifficulty: Difficulty

    public var level: Int = 1
    public var xp: Double = 0
    public var gold: Double = Balance.startingGold
    /// 所持装備 ID（最大 Balance.itemSlots）。
    public var items: [String] = []
    /// 各スロットへの投資 Gold（売却額計算用、items と同じ長さ）。
    public var itemInvested: [Double] = []

    /// SkillSlot.rawValue で添字（5 要素）。passive は常に 1。
    public var skillRanks: [Int] = [1, 0, 0, 0, 0]
    /// 残りクールダウン秒（5 要素）。
    public var skillCooldowns: [Double] = [0, 0, 0, 0, 0]
    public var skillPoints: Int = 1
    public var autoLevelSkills: Bool = true

    /// バトルスペル ID（2 要素）。
    public var spells: [String]
    public var spellCooldowns: [Double] = [0, 0]
    public var runes: [String]
    public var skinID: String?

    public var passive = PassiveState()
    public var empoweredAttack: EmpoweredAttack?
    /// 通常攻撃の累計命中数（Ranger パッシブ等）。
    public var basicAttackCount: Int = 0

    /// > 0 の間は死亡中。
    public var respawnTimer: Double = 0
    public var channel: Channel?

    /// アシスト判定用: 自分にダメージ/CC を与えた敵ヒーロー（time 昇順）。
    public var recentDamagers: [DamageRecord] = []
    /// アシスト判定用: 自分を回復/シールドした味方ヒーロー（time 昇順）。
    public var recentSupporters: [DamageRecord] = []

    public var killStreak = 0
    public var deathStreak = 0
    public var multiKillCount = 0
    public var lastKillTime: Double = -999
    public var score = HeroScore()
    public var surrenderVote: Bool?

    public init(heroID: String, role: Role, isRanged: Bool, resourceKind: ResourceKind,
                controller: Controller, position: LanePosition, displayName: String,
                botDifficulty: Difficulty, spells: [String], runes: [String], skinID: String?) {
        self.heroID = heroID
        self.role = role
        self.isRanged = isRanged
        self.resourceKind = resourceKind
        self.controller = controller
        self.position = position
        self.displayName = displayName
        self.botDifficulty = botDifficulty
        self.spells = spells
        self.runes = runes
        self.skinID = skinID
    }

    public var isDead: Bool { respawnTimer > 0 }

    public func rank(_ slot: SkillSlot) -> Int { skillRanks[slot.rawValue] }
    public func cooldown(_ slot: SkillSlot) -> Double { skillCooldowns[slot.rawValue] }
}

public struct MinionData: Codable, Hashable, Sendable {
    public var type: MinionType
    public var lane: Lane
    /// 次に向かうレーン経路点のインデックス（チーム視点の経路）。
    public var waypointIndex: Int
    public var empowered: Bool
    public var spawnTime: Double

    public init(type: MinionType, lane: Lane, waypointIndex: Int = 1, empowered: Bool = false, spawnTime: Double) {
        self.type = type
        self.lane = lane
        self.waypointIndex = waypointIndex
        self.empowered = empowered
        self.spawnTime = spawnTime
    }
}

public struct TowerData: Codable, Hashable, Sendable {
    /// Core は nil。
    public var lane: Lane?
    public var tier: TowerTier
    /// 連続命中ボーナスの対象。
    public var rampTargetID: EntityID?
    public var rampHits: Int = 0

    public init(lane: Lane?, tier: TowerTier) {
        self.lane = lane
        self.tier = tier
    }
}

public struct MonsterData: Codable, Hashable, Sendable {
    public var kind: MonsterKind
    public var campID: Int
    public var home: Vec2
    public var leashing: Bool = false

    public init(kind: MonsterKind, campID: Int, home: Vec2) {
        self.kind = kind
        self.campID = campID
        self.home = home
    }
}

/// 全ユニット共通の状態。種別固有の状態は hero/minion/tower/monster に入る。
public struct Unit: Codable, Hashable, Sendable, Identifiable {
    public var id: EntityID
    public var kind: UnitKind
    public var team: Team
    public var pos: Vec2
    /// 前 tick の位置（描画補間用。Simulation.step の冒頭で更新）。
    public var prevPos: Vec2
    /// 向き（ラジアン）。
    public var facing: Double
    public var radius: Double
    public var hp: Double
    public var resource: Double
    /// レベル/装備/バフ適用前の素の値（非ヒーローは固定値）。
    public var baseStats: Stats
    /// 実効値（StatCalculator.recompute で更新）。
    public var stats: Stats
    public var isAlive: Bool = true
    public var deathTime: Double?

    public var statuses: [StatusEffect] = []
    public var shields: [Shield] = []

    // 戦闘
    public var attackTargetID: EntityID?
    /// 次の通常攻撃を開始できるまでの秒。
    public var attackCooldown: Double = 0
    /// 前隙中なら残り秒（nil = 前隙中でない）。
    public var windupRemaining: Double?
    /// 敵ヒーロー/タワーとの交戦最終時刻。
    public var lastCombatTime: Double = -999
    public var lastDamagedTime: Double = -999
    public var lastAttackerID: EntityID?

    // 移動
    public var moveIntent: MoveIntent = .none
    /// 経路（MoveIntent.point / follow 用、先頭が次の経由点）。
    public var path: [Vec2] = []
    public var displacement: Displacement?

    // 視界
    /// このユニットを現在視認しているチームのビット集合（Team.visionBit）。
    public var visibleMask: UInt8 = 0
    /// 現在いる草むらのインデックス（MapDefinition.brushes）。
    public var brushIndex: Int?

    public var hero: HeroData?
    public var minion: MinionData?
    public var tower: TowerData?
    public var monster: MonsterData?

    public init(id: EntityID, kind: UnitKind, team: Team, pos: Vec2, radius: Double, stats: Stats) {
        self.id = id
        self.kind = kind
        self.team = team
        self.pos = pos
        self.prevPos = pos
        self.facing = 0
        self.radius = radius
        self.baseStats = stats
        self.stats = stats
        self.hp = stats.maxHP
        self.resource = stats.maxResource
    }

    public var hpRatio: Double { stats.maxHP > 0 ? max(0, hp) / stats.maxHP : 0 }
    public var isStructure: Bool { kind == .tower || kind == .core }
    public var totalShield: Double { shields.reduce(0) { $0 + $1.amount } }

    public func has(_ kind: StatusKind) -> Bool { statuses.contains { $0.kind == kind } }
    public func status(_ kind: StatusKind) -> StatusEffect? {
        statuses.filter { $0.kind == kind }.max { $0.magnitude < $1.magnitude }
    }

    /// 移動可能か（CC・強制移動・死亡を考慮）。
    public var canMove: Bool {
        isAlive && displacement == nil && !statuses.contains { $0.kind.preventsMovement }
    }

    /// 攻撃・スキル可能か。
    public var canAct: Bool {
        isAlive && displacement == nil && !statuses.contains { $0.kind.preventsActions }
    }

    public var canCast: Bool { canAct && !has(.silence) }
}
