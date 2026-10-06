import SwiftUI
import VelstriaCore

// 担当: battle-hud。HUD 表示用のスナップショット（15Hz で SimState から作る値型）と表示用の対応表。
// 値が変わった時だけ HUDModel のプロパティへ代入し、SwiftUI の再描画を必要最小限にする。

enum HUDSpace {
    /// HUD 全面の座標空間（ジェスチャーの位置とレイアウト座標を一致させる）。
    static let name = "velstria.hud"
}

struct HUDTopSnapshot: Equatable {
    var blueKills = 0
    var redKills = 0
    var seconds = 0
    var kills = 0
    var deaths = 0
    var assists = 0
    var creepScore = 0
    var blueTowers = 0
    var redTowers = 0
}

struct HUDStatusIcon: Equatable, Identifiable {
    var id: Int
    var kind: StatusKind
    var remaining: Double
    var duration: Double
    var isBuff: Bool

    var fraction: Double { duration > 0 ? min(1, max(0, remaining / duration)) : 0 }
}

struct HUDChannel: Equatable {
    var kind: ChannelKind
    var remaining: Double
    var total: Double
}

/// HP・リソース（毎 tick 変わるのでヒーローの他の情報と分けて観測させる）。
struct HUDVitals: Equatable {
    var hp: Double = 0
    var maxHP: Double = 1
    var shield: Double = 0
    var resource: Double = 0
    var maxResource: Double = 0
    var resourceKind: ResourceKind = .mana

    var hpRatio: Double { maxHP > 0 ? min(1, max(0, hp / maxHP)) : 0 }
}

struct HUDHeroSnapshot: Equatable {
    var heroID = ""
    var role: Role = .duelist
    var level = 1
    var xpProgress: Double = 0
    var gold = 0
    var items: [String] = []
    var statuses: [HUDStatusIcon] = []
    var isDead = false
    var respawn: Double = 0
    var channel: HUDChannel?
    var skillPoints = 0
}

struct HUDSkillSnapshot: Equatable, Identifiable {
    var id: Int { slot.rawValue }
    var slot: SkillSlot
    var skillID = ""
    var archetype: SkillArchetype = .groundAoE
    var targeting = SkillTargeting(archetype: .groundAoE, aim: .point, range: 0, radius: 0)
    var rank = 0
    var cooldown: Double = 0
    var cooldownTotal: Double = 1
    var cost: Double = 0
    var castable = false
    var affordable = true
    var silenced = false
    var canLevel = false

    var learned: Bool { rank > 0 }
    var isReady: Bool { learned && castable && affordable && cooldown <= 0 }
    var cooldownFraction: Double { cooldown > 0 && cooldownTotal > 0 ? min(1, cooldown / cooldownTotal) : 0 }
}

struct HUDSpellSnapshot: Equatable, Identifiable {
    var id: Int { index }
    var index: Int
    var spellID = ""
    var cooldown: Double = 0
    var cooldownTotal: Double = 1
    var castable = false

    var cooldownFraction: Double { cooldown > 0 && cooldownTotal > 0 ? min(1, cooldown / cooldownTotal) : 0 }
}

/// 死亡中の表示。
struct HUDDeathInfo: Equatable {
    var killerHeroID: String?
    var killerKind: UnitKind?
    var killerTeam: Team?
}

/// 告知バナー。
struct HUDBanner: Equatable, Identifiable {
    enum Tone: Equatable { case ally, enemy, neutral, epic }
    var id: Int
    var tone: Tone
    var title: String
    var subtitle: String?
    var symbol: String
    var leftHeroID: String?
    var rightHeroID: String?
    /// 大きいほど優先（キューが詰まった時に低いものから捨てる）。
    var priority: Int
    /// 起きた時の試合時間（秒）。早送り中に古くなった告知を捨てる。
    var gameTime: Double = 0
}

struct HUDKillFeedEntry: Equatable, Identifiable {
    var id: Int
    var killerHeroID: String?
    var killerTeam: Team?
    var victimHeroID: String
    var victimTeam: Team
    var assists: Int
    var involvesHuman: Bool
    var createdAt: TimeInterval
    /// 起きた時の試合時間（秒）。表示時間は試合時間で数える（早送りでは速く流れ、一時停止中は残る）。
    var gameTime: Double = 0
}

struct HUDToast: Equatable, Identifiable {
    var id: Int
    var text: String
    var symbol: String
    var isError: Bool
    var createdAt: TimeInterval
}

struct HUDSurrenderSnapshot: Equatable {
    var yes = 0
    var no = 0
    var needed = 3
    var total = 5
    var secondsLeft = 0
    var myVote: Bool?
    /// 投票終了後の結果表示（nil = 投票中）。
    var passed: Bool?
}

enum HUDMatchResultKind: Equatable {
    case victory
    case defeat
    case draw
    /// 観戦: 勝利チーム。
    case teamWin(Team)
}

enum HUDEndPhase: Equatable {
    case banner(HUDMatchResultKind, EndReason)
    case prompt(HUDMatchResultKind, EndReason)

    var kind: HUDMatchResultKind {
        switch self {
        case .banner(let k, _), .prompt(let k, _): return k
        }
    }

    var reason: EndReason {
        switch self {
        case .banner(_, let r), .prompt(_, let r): return r
        }
    }
}

enum HUDPanel: Equatable {
    case shop
    case scoreboard
    case pause
}

/// 観戦・リプレイ用。
struct HUDSpectateHero: Equatable, Identifiable {
    var id: EntityID
    var heroID: String
    var team: Team
    var level: Int
    var hpRatio: Double
    var isDead: Bool
    var respawn: Double
    /// 必殺技（Ultimate）を使える（習得済み・クールダウン明け）。
    var ultReady = false
    /// リプレイの持ち主（記録した本人）。
    var isOwner = false
}

struct HUDSpectateSnapshot: Equatable {
    var heroes: [HUDSpectateHero] = []
    var blueGold = 0
    var redGold = 0
    /// ブルーから見たゴールド差（100 単位。正 = ブルー有利）。
    var goldDiff = 0
}

/// ヒーローパネルの表示値（HUDModel.buildHeroPanel の純粋な出力。プレイヤーの HUD と観戦のヒーロー詳細で共用）。
struct HUDHeroPanelBuild: Equatable {
    var hero = HUDHeroSnapshot()
    var vitals = HUDVitals()
    var skills: [HUDSkillSnapshot] = SkillSlot.actives.map { HUDSkillSnapshot(slot: $0) }
    var spells: [HUDSpellSnapshot] = [HUDSpellSnapshot(index: 0), HUDSpellSnapshot(index: 1)]
}

/// 観戦: 追従中のヒーローの詳細（情報パネル）。
struct HUDHeroCardSnapshot: Equatable {
    var id: EntityID
    var team: Team
    var isOwner = false
    var panel = HUDHeroPanelBuild()
    var kills = 0
    var deaths = 0
    var assists = 0
    var creepScore = 0
    /// 所持 Gold + 装備の価値。
    var netWorth = 0
    var damageDealt = 0
    var damageTaken = 0
    /// 回復 + シールド。
    var healing = 0
    var towerDamage = 0
}

/// 観戦: 再生バーと再生操作の状態（15Hz）。
struct HUDTransportSnapshot: Equatable {
    /// 現在の tick。
    var tick = 0
    /// バーの右端（リプレイ = 最終 tick、観戦 = 分かっている所まで）。
    var endTick = 1
    /// すぐにシークできる所まで（網掛け。事前計算のキーフレーム・一度見た区間。年表だけ分かっている所は含めない）。
    var coveredTick = 0
    /// シークできる最後の tick（観戦は試合の最大時間）。
    var upperBound = 1
    /// 右端が試合の終わり（リプレイ）。
    var isEndKnown = false
    /// シーク中の目標 tick。
    var seekingTo: Int?
    var isPaused = false
    var speed: Double = 1
    var isEnded = false
    var isSeekable = false
    /// オンラインの観戦席（LIVE 表示。一時停止・速度・シークは効かない）。
    var isLiveWatcher = false
    var delaySeconds: Double?
    var watchers = 0
    /// 「次の見どころ」へ飛ぶ先（無ければ nil）。
    var nextFightTick: Int?

    /// 表示上の位置（シーク中は目標）。
    var displayTick: Int { seekingTo ?? tick }
    var fraction: Double { min(1, max(0, Double(displayTick) / Double(max(1, endTick)))) }
}

/// シークバーの印（年表の出来事）。
struct HUDTimelineMarker: Equatable {
    enum Kind: Equatable { case kill, structure, objective, ace, end }
    var tick: Int
    var kind: Kind
    /// 有利になった側（nil = 中立・不明）。
    var team: Team?
    /// 重要度（0〜1。印の大きさ）。
    var weight: Double
}

/// 観戦: 出来事の一覧の 1 行（試合時間・タップでその時刻へ）。
struct HUDEventLogEntry: Equatable, Identifiable {
    var id: Int
    var tick: Int
    var title: String
    var subtitle: String?
    var symbol: String
    /// 有利になった側。
    var team: Team?
    var weight: Double
    var leftHeroID: String?
    var rightHeroID: String?
    /// カメラを向ける対象（倒した側 / 倒された側のヒーロー）。
    var focusID: EntityID?
    var pos: Vec2?
}

/// ゴールド・経験値の推移の 1 点（ブルーから見た差）。
struct HUDGraphPoint: Equatable {
    var tick: Int
    var gold: Double
    var xp: Double
}

struct HUDGoldGraphSnapshot: Equatable {
    var points: [HUDGraphPoint] = []
    /// 横軸の右端（tick）。
    var endTick = 1
}

/// 観戦: 目標（星喰竜・古環の巨像）の出現までの時間と、チームの加護の残り時間。
struct HUDObjectiveTimer: Equatable, Identifiable {
    enum Kind: Equatable { case wyrm, colossus, wyrmBlessing, colossusBlessing }
    var kind: Kind
    /// 加護を持っているチーム（出現タイマーは nil）。
    var team: Team?
    /// 残り秒（nil = 出現中）。
    var seconds: Int?

    var id: String { "\(kind)-\(team.map { "\($0.rawValue)" } ?? "n")" }
}

/// スコアボードの 1 行。
struct HUDScoreRow: Equatable, Identifiable {
    var id: EntityID
    var heroID: String
    var name: String
    var team: Team
    var isHuman: Bool
    var level: Int
    var kills: Int
    var deaths: Int
    var assists: Int
    var creepScore: Int
    var items: [String]
    var spells: [String]
    /// 味方のみ（敵は nil）。
    var spellCooldowns: [Double]?
    var isDead: Bool
    var respawn: Double
    /// 所持 Gold + 装備の価値（観戦者の列。100 単位）。
    var netWorth = 0
    /// ヒーローへの与ダメージ（観戦者の列。100 単位）。
    var damage = 0
    /// カメラが追従中（観戦者）。
    var isFocus = false
}

struct HUDScoreboardSnapshot: Equatable {
    var blue: [HUDScoreRow] = []
    var red: [HUDScoreRow] = []
    var blueKills = 0
    var redKills = 0
    var blueTowers = 0
    var redTowers = 0
    var blueObjectives = 0
    var redObjectives = 0
    var blueWyrms = 0
    var redWyrms = 0
    var blueColossi = 0
    var redColossi = 0
    var seconds = 0
}

// MARK: - 表示用の対応表

enum HUDSymbols {
    /// スキルのアーキタイプ → アイコン。
    static func skill(_ a: SkillArchetype) -> String {
        switch a {
        case .passive: return "seal.fill"
        case .cone: return "wind"
        case .lineSkillshot: return "bolt.horizontal.fill"
        case .piercingLine: return "arrow.right.to.line"
        case .dashStrike: return "chevron.right.2"
        case .blinkEmpower: return "sparkles"
        case .groundAoE: return "target"
        case .selfAoE: return "dot.radiowaves.left.and.right"
        case .healZone: return "cross.circle.fill"
        case .leapSlam: return "burst.fill"
        case .multiStrike: return "bolt.fill"
        case .teamHeal: return "heart.circle.fill"
        case .targetedBlink: return "scope"
        }
    }

    static func status(_ k: StatusKind) -> String {
        switch k {
        case .stun: return "exclamationmark.triangle.fill"
        case .root: return "lock.fill"
        case .slow: return "tortoise.fill"
        case .airborne: return "arrow.up.circle.fill"
        case .silence: return "speaker.slash.fill"
        case .speedBoost: return "hare.fill"
        case .attackSpeedBoost: return "bolt.fill"
        case .damageBoost: return "flame.fill"
        case .damageReduction: return "shield.fill"
        case .ccImmune: return "sparkles"
        case .invulnerable: return "checkmark.shield.fill"
        case .stealth: return "eye.slash.fill"
        case .burn: return "flame"
        case .healReduction: return "bandage.fill"
        case .damageDealtReduction: return "arrow.down.circle.fill"
        case .revealed: return "eye.fill"
        case .blueBuff: return "drop.fill"
        case .redBuff: return "flame.circle.fill"
        case .wyrmBlessing: return "hurricane"
        case .colossusBlessing: return "crown.fill"
        }
    }

    static func isBuff(_ k: StatusKind) -> Bool {
        switch k {
        case .stun, .root, .slow, .airborne, .silence, .burn, .healReduction, .damageDealtReduction, .revealed:
            return false
        default:
            return true
        }
    }

    static func statusName(_ k: StatusKind) -> String {
        switch k {
        case .stun: return L("スタン", "Stun")
        case .root: return L("拘束", "Root")
        case .slow: return L("スロー", "Slow")
        case .airborne: return L("打ち上げ", "Airborne")
        case .silence: return L("沈黙", "Silence")
        case .speedBoost: return L("加速", "Haste")
        case .attackSpeedBoost: return L("攻撃速度上昇", "Attack speed up")
        case .damageBoost: return L("与ダメージ上昇", "Damage up")
        case .damageReduction: return L("被ダメージ軽減", "Damage reduction")
        case .ccImmune: return L("CC 無効", "CC immune")
        case .invulnerable: return L("無敵", "Invulnerable")
        case .stealth: return L("ステルス", "Stealth")
        case .burn: return L("燃焼", "Burn")
        case .healReduction: return L("重傷", "Grievous wounds")
        case .damageDealtReduction: return L("与ダメージ低下", "Damage down")
        case .revealed: return L("発見", "Revealed")
        case .blueBuff: return L("蒼晶の加護", "Azure blessing")
        case .redBuff: return L("紅焔の加護", "Crimson blessing")
        case .wyrmBlessing: return L("竜の加護", "Wyrm blessing")
        case .colossusBlessing: return L("巨像の加護", "Colossus blessing")
        }
    }

    static func statusColor(_ k: StatusKind) -> Color {
        switch k {
        case .blueBuff: return Color(red: 0.35, green: 0.70, blue: 1.0)
        case .redBuff: return Color(red: 1.0, green: 0.45, blue: 0.30)
        case .wyrmBlessing: return Color(red: 0.70, green: 0.55, blue: 1.0)
        case .colossusBlessing: return Theme.gold
        default: return isBuff(k) ? Theme.success : Theme.danger
        }
    }

    /// HUD で使う全アイコン（存在確認テスト用）。
    static var all: [String] {
        let archetypes: [SkillArchetype] = [.passive, .cone, .lineSkillshot, .piercingLine, .dashStrike, .blinkEmpower,
                                            .groundAoE, .selfAoE, .healZone, .leapSlam, .multiStrike, .teamHeal,
                                            .targetedBlink]
        let statuses: [StatusKind] = [.stun, .root, .slow, .airborne, .silence, .speedBoost, .attackSpeedBoost,
                                      .damageBoost, .damageReduction, .ccImmune, .invulnerable, .stealth, .burn,
                                      .healReduction, .damageDealtReduction, .revealed, .blueBuff, .redBuff,
                                      .wyrmBlessing, .colossusBlessing]
        return archetypes.map(skill) + statuses.map(status) + ui
    }

    /// その他の HUD アイコン。
    static let ui: [String] = [
        "house.fill", "bag.fill", "pause.fill", "play.fill", "list.bullet.rectangle.fill", "xmark", "plus",
        "person.3.fill", "building.columns.fill", "flag.fill", "crown.fill", "xmark.octagon.fill", "hurricane",
        "speaker.wave.2.fill", "music.note", "camera.metering.center.weighted", "textformat.123",
        "rectangle.portrait.and.arrow.right", "hand.thumbsup.fill", "hand.thumbsdown.fill", "arrow.uturn.backward",
        "bolt.heart.fill", "figure.walk", "hand.tap.fill", "checkmark.circle.fill", "star.fill", "trophy.fill",
        "shield.lefthalf.filled", "chevron.right", "arrow.right", "eye.fill", "video.fill", "circle.dashed",
        "exclamationmark.circle.fill", "cart.fill", "arrow.up.forward.circle.fill", "circle.hexagongrid.fill",
        "chevron.right.2", "lock.fill", "drop.fill", "checkmark", "ellipsis", "door.left.hand.open", "diamond.fill",
        "circle.fill", "forward.fill", "backward.fill",
        // 観戦
        "gobackward.10", "goforward.10", "gobackward.30", "goforward.30", "forward.frame.fill", "forward.end.fill",
        "arrow.counterclockwise", "eye.slash.fill", "chevron.left", "slider.horizontal.3", "camera.fill",
        "dot.radiowaves.left.and.right", "chart.xyaxis.line", "list.bullet", "person.crop.square.fill",
        "scope", "timer", "map.fill", "star.circle.fill", "hurricane", "eye",
    ]
}

enum HUDText {
    static func laneName(_ lane: Lane?) -> String {
        switch lane {
        case .top?: return L("上レーン", "Top lane")
        case .mid?: return L("中央レーン", "Mid lane")
        case .bot?: return L("下レーン", "Bot lane")
        case nil: return L("本拠点", "Base")
        }
    }

    static func tierName(_ tier: TowerTier) -> String {
        switch tier {
        case .outer: return L("外塔", "Outer tower")
        case .inner: return L("内塔", "Inner tower")
        case .base: return L("基部塔", "Base tower")
        }
    }

    static func teamName(_ team: Team) -> String {
        switch team {
        case .blue: return L("ブルー", "Blue")
        case .red: return L("レッド", "Red")
        case .neutral: return L("中立", "Neutral")
        }
    }

    static func purchaseFailure(_ reason: String) -> String {
        switch PurchaseFailure(rawValue: reason) {
        case .slotsFull?: return L("装備枠がいっぱいです", "Your item slots are full")
        case .notEnoughGold?: return L("Gold が足りません", "Not enough gold")
        case .uniqueCategory?: return L("このカテゴリの装備は 1 つまでです", "Only one item of this category")
        case .requiresSmite?:
            let smite = MasterData.shared.spell(Balance.Economy.smiteSpellID).map { MasterText.spell($0) } ?? "BS05"
            return L("\(smite) を装備していないと購入できません", "Requires the \(smite) spell")
        case .unknownItem?, nil: return L("購入できません", "Can't buy this item")
        }
    }

    static func endReason(_ r: EndReason) -> String? {
        switch r {
        case .coreDestroyed: return L("Star Core 破壊", "Star Core destroyed")
        case .surrender: return L("降参", "Surrender")
        case .timeLimit: return L("時間切れ判定", "Time limit")
        case .aborted: return nil
        }
    }

    static func unitKind(_ k: UnitKind) -> String {
        switch k {
        case .hero: return L("ヒーロー", "Hero")
        case .minion: return L("ミニオン", "Minion")
        case .tower: return L("タワー", "Tower")
        case .core: return "Star Core"
        case .monster: return L("モンスター", "Monster")
        case .dummy: return L("訓練人形", "Dummy")
        }
    }

    static func channelName(_ k: ChannelKind) -> String {
        switch k {
        case .recall: return L("帰還中", "Recalling")
        case .teleport: return L("転移中", "Teleporting")
        }
    }
}
