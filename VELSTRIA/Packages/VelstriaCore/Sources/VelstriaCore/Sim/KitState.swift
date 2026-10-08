import Foundation

// ヒーロー固有スキル（キット）の状態（docs/SKILL_KITS.md）。
// 固定フィールドのみ（Dictionary / Set は列挙順が非決定的なので使わない）。キットを持つヒーローだけ HeroData.kit が非 nil。
// 値型・Codable なので、途中でシリアライズして再開しても同じ結果になる。

/// 再使用の窓（スキルを撃った後、一定時間内に同じスロットをもう一度撃てる）。
public struct RecastWindow: Codable, Hashable, Sendable {
    /// 次に撃つ段（0 = 窓なし、1 以上 = 再使用の何段目か）。
    public var stage = 0
    /// 窓が閉じるまでの残り秒。
    public var remaining: Double = 0
    public var total: Double = 0
    /// 残りの再使用回数。
    public var charges = 0
    /// 窓が閉じたときに設定するクールダウン（秒）。負ならクールダウンに触れない。
    public var cooldownOnClose: Double = -1

    public var isOpen: Bool { stage > 0 && remaining > 0 }

    public init() {}
}

/// 遅延・連撃のタイマー。時間が来るとキットの `onTimer` が呼ばれる（挿入順）。
public struct KitTimer: Codable, Hashable, Sendable {
    /// キットが `onTimer` で解釈する種別（0 以外）。
    public var code: Int
    public var slot: SkillSlot
    public var remaining: Double
    /// 対象ユニット（0 = なし）。
    public var targetID: EntityID
    /// 連撃の番号など。
    public var index: Int
    public var param: Double
    public var point: Vec2
    /// ハード CC（スタン・打ち上げ・suppress）で取り消すか。
    public var interruptible: Bool

    public init(code: Int, slot: SkillSlot, remaining: Double, targetID: EntityID = 0, index: Int = 0,
                param: Double = 0, point: Vec2 = .zero, interruptible: Bool = true) {
        self.code = code
        self.slot = slot
        self.remaining = remaining
        self.targetID = targetID
        self.index = index
        self.param = param
        self.point = point
        self.interruptible = interruptible
    }
}

/// 経路上の敵に 1 度ずつ当たる突進（`Kit.dashSweeping`）。
public struct KitSweep: Codable, Hashable, Sendable {
    public var slot: SkillSlot
    public var payload: HitPayload
    /// 経路の線分に対する当たり半径（対象の半径は別に足す）。
    public var radius: Double
    public var hitIDs: [EntityID]
    /// 着地した tick に `onTimer` へ渡す code（0 = 呼ばない）。
    public var arriveCode: Int
    public var interruptible: Bool

    public init(slot: SkillSlot, payload: HitPayload, radius: Double, arriveCode: Int = 0, interruptible: Bool = true) {
        self.slot = slot
        self.payload = payload
        self.radius = radius
        self.hitIDs = []
        self.arriveCode = arriveCode
        self.interruptible = interruptible
    }
}

public struct KitState: Codable, Hashable, Sendable {
    /// 4 要素。SkillSlot.rawValue で添字。
    public var windows: [RecastWindow] = Array(repeating: RecastWindow(), count: 4)
    /// 8 レジスタ（スタック・カウンタ・フラグ）。各キットが名前付きアクセサを `extension KitState` に置く。
    public var ints: [Int] = Array(repeating: 0, count: 8)
    public var reals: [Double] = Array(repeating: 0, count: 8)
    /// 8 カウントダウン（毎 tick 0 まで自動で減る）。
    public var timers: [Double] = Array(repeating: 0, count: 8)
    /// 4 要素（0 = なし）。
    public var ids: [EntityID] = Array(repeating: 0, count: 4)
    public var form = 0
    /// 遅延・連撃（挿入順に消化する）。
    public var scheduled: [KitTimer] = []
    /// 経路上にヒットする突進（進行中のみ）。
    public var sweep: KitSweep?

    public init() {}
}
