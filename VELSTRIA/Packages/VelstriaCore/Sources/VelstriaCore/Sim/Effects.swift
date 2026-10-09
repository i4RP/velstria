import Foundation

// MARK: - ステータス効果

public enum StatusKind: Int, Codable, Hashable, Sendable {
    // 行動阻害
    case stun
    case root
    case slow            // magnitude = 減速率 (0.3 = −30%)
    case airborne        // ノックバック中（行動不可）
    case silence         // スキル不可
    // 強化
    case speedBoost      // magnitude = 加速率
    case attackSpeedBoost // magnitude = 攻撃速度 +率
    case damageBoost     // magnitude = 与ダメ +率
    case damageReduction // magnitude = 被ダメ −率
    case ccImmune
    case invulnerable
    case stealth
    // 弱体
    case burn            // magnitude = 毎秒の確定ダメージ
    case healReduction   // magnitude = 受ける回復 −率
    case damageDealtReduction // magnitude = 与ダメ −率（星鎖）
    case revealed        // ステルス・草むらでも可視
    // オブジェクト
    case blueBuff
    case redBuff
    case wyrmBlessing
    case colossusBlessing
    // ヒーロー固有スキル（キット層。docs/SKILL_KITS.md）。raw 値を変えないため末尾に追加
    case mark            // magnitude = スタック数（tag に所有者 ID を含める）
    case lifestealBoost  // magnitude = 通常攻撃の吸血 +率
    case spellVampBoost  // magnitude = スキルの吸血 +率
    case attackRangeBoost // magnitude = 通常攻撃の射程 +距離
    case armorShred      // magnitude = 防御の減少率（0.3 = −30%）
    case untargetable    // 単体指定・追尾・通常攻撃の対象から外れる（範囲・直線には当たる）
    case suppress        // 行動不能・移動不能。解除不可で CC 無効も無視する
    case channeling      // キットのスキルの詠唱中（表示用。行動の制限は別に持つ）
    case magicShred      // magnitude = 魔防の減少量（固定値。装備のジーニアスワンド）。raw 値を変えないため末尾に追加
    // 装備と靴の祝福（MLBB の装備への総入れ替え、2026-10）。raw 値を変えないため末尾に追加
    case flatPowerMod    // magnitude = 物理攻撃と魔法攻撃の増減（固定値。負 = 減少。炎撃の狩猟の奪取）
    case flatMoveSpeedMod // magnitude = 移動速度の増減（固定値。負 = 減少。氷刺の狩猟の奪取）
    case flatDefenseMod  // magnitude = 物理防御と魔法防御の増減（固定値。負 = 減少。激励・カースヘルムの呪い）
}

extension StatusKind {
    /// 移動不可にする CC。
    public var preventsMovement: Bool { self == .stun || self == .root || self == .airborne || self == .suppress }
    /// 攻撃・スキル不可にする CC。
    public var preventsActions: Bool { self == .stun || self == .airborne || self == .suppress }
    /// コントロール時間短縮で効果時間が縮む行動阻害・減速。
    public var reducedByCCReduction: Bool { self == .stun || self == .root || self == .silence || self == .slow }
    /// 浄化で解除される弱体。
    public var isCleansable: Bool {
        switch self {
        case .stun, .root, .slow, .silence, .burn, .healReduction, .damageDealtReduction: return true
        default: return false
        }
    }
}

public struct StatusEffect: Codable, Hashable, Sendable {
    public var kind: StatusKind
    public var remaining: Double
    public var duration: Double
    public var magnitude: Double
    public var sourceID: EntityID?
    /// 同一 kind + tag は重ねず上書き（remaining は長い方、magnitude は大きい方）。
    public var tag: String
    /// burn 等の周期処理用。
    public var tickTimer: Double

    public init(kind: StatusKind, duration: Double, magnitude: Double = 0,
                sourceID: EntityID? = nil, tag: String = "") {
        self.kind = kind
        self.remaining = duration
        self.duration = duration
        self.magnitude = magnitude
        self.sourceID = sourceID
        self.tag = tag
        self.tickTimer = 0
    }
}

public struct Shield: Codable, Hashable, Sendable {
    public var amount: Double
    public var remaining: Double
    public var sourceID: EntityID?
    public var tag: String

    public init(amount: Double, duration: Double, sourceID: EntityID? = nil, tag: String = "") {
        self.amount = amount
        self.remaining = duration
        self.sourceID = sourceID
        self.tag = tag
    }
}

// MARK: - ダメージ

public enum DamageSource: Codable, Hashable, Sendable {
    case basicAttack
    case skill(SkillSlot)
    case spell
    case item
    case tower
    case minion
    case monster
    case fountain
    case dot
    case passive

    public var isSkill: Bool { if case .skill = self { return true } else { return false } }
}

/// 命中時に適用する内容。投射物・ゾーン・即時ヒットで共通。
public struct HitPayload: Codable, Hashable, Sendable {
    public var damage: Double
    public var damageType: DamageType
    public var source: DamageSource
    public var isCrit: Bool
    public var cc: CrowdControl
    /// Ult 用の強い CC 値を使うか。
    public var ccIsUltimate: Bool
    /// 追加で付与するステータス（固有効果など）。
    public var statuses: [StatusEffect]
    /// 敵に当たるか。
    public var affectsEnemies: Bool
    /// 味方に当たるか（回復・シールドゾーン）。
    public var affectsAllies: Bool
    public var healAmount: Double
    public var shieldAmount: Double
    public var shieldDuration: Double
    /// ライフスティール・装備の通常攻撃効果を適用するか（通常攻撃は true）。
    public var appliesOnHit: Bool
    /// ヒーローのみに当たる。
    public var heroesOnly: Bool
    public var skillID: String?
    /// 命中時の追加効果（打ち上げ・引き寄せ・マーク・回復など。キット層）。
    public var effects: [HitEffect]
    /// ダメージの補正（失った HP・距離・マークなど。キット層）。
    public var scaling: DamageScaling?
    /// 距離スケーリングの起点（弾の発射位置など。nil = 所有者の位置）。
    public var originPos: Vec2?
    /// 0 以外ならダメージ適用後にキットの onHit(event:) を呼ぶ。
    public var kitEvent: Int

    public init(damage: Double, damageType: DamageType, source: DamageSource,
                isCrit: Bool = false, cc: CrowdControl = .none, ccIsUltimate: Bool = false,
                statuses: [StatusEffect] = [], affectsEnemies: Bool = true, affectsAllies: Bool = false,
                healAmount: Double = 0, shieldAmount: Double = 0, shieldDuration: Double = 0,
                appliesOnHit: Bool = false, heroesOnly: Bool = false, skillID: String? = nil,
                effects: [HitEffect] = [], scaling: DamageScaling? = nil, originPos: Vec2? = nil, kitEvent: Int = 0) {
        self.damage = damage
        self.damageType = damageType
        self.source = source
        self.isCrit = isCrit
        self.cc = cc
        self.ccIsUltimate = ccIsUltimate
        self.statuses = statuses
        self.affectsEnemies = affectsEnemies
        self.affectsAllies = affectsAllies
        self.healAmount = healAmount
        self.shieldAmount = shieldAmount
        self.shieldDuration = shieldDuration
        self.appliesOnHit = appliesOnHit
        self.heroesOnly = heroesOnly
        self.skillID = skillID
        self.effects = effects
        self.scaling = scaling
        self.originPos = originPos
        self.kitEvent = kitEvent
    }
}

// MARK: - 投射物・ゾーン

public enum ProjectileMotion: Codable, Hashable, Sendable {
    /// 対象を追尾（通常攻撃・対象指定スキル）。対象が死亡/不可視化で消滅。
    case homing(targetID: EntityID)
    /// 直線スキルショット。
    case linear(direction: Vec2, maxDistance: Double)
}

public struct Projectile: Codable, Hashable, Sendable, Identifiable {
    public var id: EntityID
    public var ownerID: EntityID
    public var team: Team
    public var pos: Vec2
    public var prevPos: Vec2
    public var motion: ProjectileMotion
    public var speed: Double
    public var traveled: Double
    /// 直線弾の当たり幅（半径）。
    public var width: Double
    /// true: 貫通（全ヒット）、false: 最初の 1 体で消滅。
    public var pierce: Bool
    public var hitIDs: [EntityID]
    public var payload: HitPayload
    /// 描画用の演出 ID（EffectDef.effectID）または "basic_attack" / "tower_shot" など。
    public var visual: String
    public var done: Bool

    public init(id: EntityID, ownerID: EntityID, team: Team, pos: Vec2, motion: ProjectileMotion,
                speed: Double, width: Double = 0, pierce: Bool = false, payload: HitPayload, visual: String) {
        self.id = id
        self.ownerID = ownerID
        self.team = team
        self.pos = pos
        self.prevPos = pos
        self.motion = motion
        self.speed = speed
        self.traveled = 0
        self.width = width
        self.pierce = pierce
        self.hitIDs = []
        self.payload = payload
        self.visual = visual
        self.done = false
    }
}

public enum ZoneShape: Codable, Hashable, Sendable {
    case circle
    /// 扇形。direction = 中心方向（正規化）、halfAngle = 半角（ラジアン）。
    case cone(direction: Vec2, halfAngle: Double)
    /// 線分（center から direction へ length、幅 = radius）。
    case line(direction: Vec2, length: Double)
}

/// 地面の範囲効果。delay 後に発動し、duration > 0 なら tickInterval 毎に再適用。
public struct AreaZone: Codable, Hashable, Sendable, Identifiable {
    public var id: EntityID
    public var ownerID: EntityID
    public var team: Team
    public var center: Vec2
    public var radius: Double
    public var shape: ZoneShape
    /// 発動までの残り時間（予告表示中）。
    public var delay: Double
    public var totalDelay: Double
    /// 発動後の持続時間（0 = 単発）。
    public var duration: Double
    public var tickInterval: Double
    public var tickTimer: Double
    public var triggered: Bool
    /// 発動済み単発ゾーン・持続切れで true。
    public var done: Bool
    /// true の場合、中心が所有者に追従する。
    public var followsOwner: Bool
    /// 非 nil の場合、中心がそのユニットに追従する（対象が消えた/死亡したらゾーンは終わる。キット層）。
    public var followsTargetID: EntityID?
    public var payload: HitPayload
    public var visual: String
    /// 単発ヒット済みユニット（持続ゾーンでは毎 tick 再判定のため未使用）。
    public var hitIDs: [EntityID]

    public init(id: EntityID, ownerID: EntityID, team: Team, center: Vec2, radius: Double,
                shape: ZoneShape = .circle, delay: Double, duration: Double = 0, tickInterval: Double = 0.5,
                followsOwner: Bool = false, followsTargetID: EntityID? = nil, payload: HitPayload, visual: String) {
        self.id = id
        self.ownerID = ownerID
        self.team = team
        self.center = center
        self.radius = radius
        self.shape = shape
        self.delay = delay
        self.totalDelay = delay
        self.duration = duration
        self.tickInterval = tickInterval
        self.tickTimer = 0
        self.triggered = false
        self.done = false
        self.followsOwner = followsOwner
        self.followsTargetID = followsTargetID
        self.payload = payload
        self.visual = visual
        self.hitIDs = []
    }
}

// MARK: - 移動系

public enum MoveIntent: Codable, Hashable, Sendable {
    case none
    /// 仮想スティック方向（正規化ベクトル）。
    case direction(Vec2)
    /// 地点へ経路移動。
    case point(Vec2)
    /// ユニットを射程 range まで追跡。
    case follow(targetID: EntityID, range: Double)
}

public enum DisplacementKind: Int, Codable, Hashable, Sendable {
    case dash
    case knockback
    case leap
}

/// 強制移動（突進・ノックバック・跳躍）。進行中は通常移動・攻撃を行わない。
public struct Displacement: Codable, Hashable, Sendable {
    public var kind: DisplacementKind
    public var from: Vec2
    public var to: Vec2
    public var duration: Double
    public var elapsed: Double

    public init(kind: DisplacementKind, from: Vec2, to: Vec2, duration: Double) {
        self.kind = kind
        self.from = from
        self.to = to
        self.duration = max(duration, Balance.dt)
        self.elapsed = 0
    }
}

public enum ChannelKind: Int, Codable, Hashable, Sendable {
    case recall
    case teleport
}

/// 詠唱（帰還・帰還門）。被ダメ・移動・攻撃で中断。
public struct Channel: Codable, Hashable, Sendable {
    public var kind: ChannelKind
    public var remaining: Double
    public var total: Double
    public var target: Vec2?

    public init(kind: ChannelKind, duration: Double, target: Vec2? = nil) {
        self.kind = kind
        self.remaining = duration
        self.total = duration
        self.target = target
    }
}
