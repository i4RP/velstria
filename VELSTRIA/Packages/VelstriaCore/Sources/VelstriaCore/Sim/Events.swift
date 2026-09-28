import Foundation

/// スキルの挙動分類。描画（演出・照準表示）と AI（照準方法）が参照する。
public enum SkillArchetype: String, Codable, Hashable, Sendable {
    case passive
    /// 前方扇形の即時攻撃。
    case cone
    /// 直線スキルショット（最初の敵に命中）。
    case lineSkillshot
    /// 直線貫通弾。
    case piercingLine
    /// 指定方向への突進 + 着地点 AoE。
    case dashStrike
    /// 短距離ブリンク + 次の通常攻撃強化。
    case blinkEmpower
    /// 地点指定の遅延円形 AoE。
    case groundAoE
    /// 自身中心の即時 AoE（+ 自己シールド）。
    case selfAoE
    /// 味方回復ゾーン（敵にはダメージ/CC）。
    case healZone
    /// 跳躍突撃（着地 AoE）。
    case leapSlam
    /// 範囲内敵ヒーローへの連続攻撃。
    case multiStrike
    /// 味方全体回復 + 周囲 CC。
    case teamHeal
    /// 対象指定ブリンク + 処刑ダメージ。
    case targetedBlink
}

/// 照準方式（HUD のドラッグ照準・AI の狙い方）。
public enum AimType: Int, Codable, Hashable, Sendable {
    case none
    case direction
    case point
    case unit
}

public struct SkillCastEvent: Codable, Hashable, Sendable {
    public var casterID: EntityID
    public var heroID: String
    public var slot: SkillSlot
    public var skillID: String
    public var effectID: String
    public var archetype: SkillArchetype
    public var origin: Vec2
    public var target: Vec2
    public var targetUnitID: EntityID?
    public var range: Double
    public var radius: Double

    public init(casterID: EntityID, heroID: String, slot: SkillSlot, skillID: String, effectID: String,
                archetype: SkillArchetype, origin: Vec2, target: Vec2, targetUnitID: EntityID? = nil,
                range: Double, radius: Double) {
        self.casterID = casterID
        self.heroID = heroID
        self.slot = slot
        self.skillID = skillID
        self.effectID = effectID
        self.archetype = archetype
        self.origin = origin
        self.target = target
        self.targetUnitID = targetUnitID
        self.range = range
        self.radius = radius
    }
}

public struct DamageEvent: Codable, Hashable, Sendable {
    public var sourceID: EntityID?
    public var targetID: EntityID
    /// シールド吸収後に HP から減った量 + シールド吸収量。
    public var amount: Double
    public var absorbed: Double
    public var damageType: DamageType
    public var source: DamageSource
    public var isCrit: Bool
    public var pos: Vec2

    public init(sourceID: EntityID?, targetID: EntityID, amount: Double, absorbed: Double,
                damageType: DamageType, source: DamageSource, isCrit: Bool, pos: Vec2) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.amount = amount
        self.absorbed = absorbed
        self.damageType = damageType
        self.source = source
        self.isCrit = isCrit
        self.pos = pos
    }
}

public struct HeroKillEvent: Codable, Hashable, Sendable {
    public var victimID: EntityID
    public var killerID: EntityID?
    public var assistIDs: [EntityID]
    public var bounty: Double
    public var isFirstBlood: Bool
    /// 10 秒以内の連続キル数（1 = 通常）。
    public var multiKill: Int
    public var killerStreak: Int
    public var isShutdown: Bool

    public init(victimID: EntityID, killerID: EntityID?, assistIDs: [EntityID], bounty: Double,
                isFirstBlood: Bool, multiKill: Int, killerStreak: Int, isShutdown: Bool) {
        self.victimID = victimID
        self.killerID = killerID
        self.assistIDs = assistIDs
        self.bounty = bounty
        self.isFirstBlood = isFirstBlood
        self.multiKill = multiKill
        self.killerStreak = killerStreak
        self.isShutdown = isShutdown
    }
}

public enum Announcement: Codable, Hashable, Sendable {
    case matchStart
    case minionsSpawned
    case firstBlood(killerID: EntityID, victimID: EntityID)
    case multiKill(killerID: EntityID, count: Int)
    case killingSpree(killerID: EntityID, streak: Int)
    case shutdown(killerID: EntityID, victimID: EntityID)
    /// team = 全滅させた側。
    case ace(team: Team)
    /// team = 失った側。
    case towerDestroyed(team: Team, lane: Lane?, tier: TowerTier)
    case coreVulnerable(team: Team)
    case wyrmSpawned
    case colossusSpawned
    case wyrmSlain(team: Team)
    case colossusSlain(team: Team)
    case surrenderPassed(team: Team)
    case victory(team: Team)
}

public enum EndReason: Int, Codable, Hashable, Sendable {
    case coreDestroyed
    case surrender
    /// 練習場・チュートリアルの終了、プレイヤー離脱など。
    case aborted
    /// 安全装置（最大試合時間）。
    case timeLimit
}

/// 1 tick 内に発生した出来事。描画・HUD・サウンド・分析が購読する。
public enum SimEvent: Codable, Hashable, Sendable {
    case damage(DamageEvent)
    case heal(targetID: EntityID, sourceID: EntityID?, amount: Double)
    case shieldGained(targetID: EntityID, sourceID: EntityID?, amount: Double)
    case attackStarted(sourceID: EntityID, targetID: EntityID)
    /// 近接通常攻撃の命中、または遠隔の発射。
    case attackReleased(sourceID: EntityID, targetID: EntityID, isRanged: Bool)
    case projectileLaunched(projectileID: EntityID, ownerID: EntityID, visual: String)
    case projectileHit(projectileID: EntityID, targetID: EntityID?, pos: Vec2)
    case skillCast(SkillCastEvent)
    case spellCast(casterID: EntityID, spellID: String, origin: Vec2, target: Vec2)
    case zoneCreated(zoneID: EntityID, ownerID: EntityID, team: Team, visual: String, center: Vec2,
                     radius: Double, delay: Double, duration: Double, isBeneficial: Bool)
    case zoneTriggered(zoneID: EntityID, center: Vec2, radius: Double)
    case ccApplied(targetID: EntityID, cc: CrowdControl, duration: Double)
    case statusApplied(targetID: EntityID, kind: StatusKind, duration: Double)
    case displaced(unitID: EntityID, kind: DisplacementKind, from: Vec2, to: Vec2, duration: Double)
    case blinked(unitID: EntityID, from: Vec2, to: Vec2)
    case unitSpawned(unitID: EntityID, kind: UnitKind, team: Team, pos: Vec2)
    case unitDied(unitID: EntityID, kind: UnitKind, team: Team, killerID: EntityID?, pos: Vec2)
    case heroKilled(HeroKillEvent)
    case goldGained(heroID: EntityID, amount: Double, pos: Vec2)
    case levelUp(heroID: EntityID, level: Int)
    case skillLeveled(heroID: EntityID, slot: SkillSlot, rank: Int)
    case itemPurchased(heroID: EntityID, itemID: String)
    case itemSold(heroID: EntityID, itemID: String, refund: Double)
    case purchaseFailed(heroID: EntityID, itemID: String, reason: String)
    case structureDestroyed(unitID: EntityID, kind: UnitKind, team: Team, lane: Lane?, tier: TowerTier?, killerID: EntityID?)
    case objectiveTaken(kind: MonsterKind, team: Team, killerID: EntityID?)
    case respawned(heroID: EntityID, pos: Vec2)
    case channelStarted(heroID: EntityID, kind: ChannelKind, duration: Double)
    case channelCanceled(heroID: EntityID, kind: ChannelKind)
    case channelCompleted(heroID: EntityID, kind: ChannelKind, destination: Vec2)
    case announcement(Announcement)
    case waveSpawned(index: Int)
    case emote(heroID: EntityID, emoteID: String)
    case surrenderVote(team: Team, yes: Int, no: Int, needed: Int)
    case matchEnded(winner: Team?, reason: EndReason)
}
