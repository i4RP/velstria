import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// キットの登録と、App・sim から使う小さな facade。H025..H034 のスタブを最初から全部並べる（以後このファイルは変えない）。
// 各キットは isReady を true にした時点で有効になる（有効化する PR で MatchConfig.currentSimVersion を上げる）。

/// 再使用の窓の表示用情報（HUD）。
public struct RecastInfo: Hashable, Sendable {
    public var stage: Int
    public var remaining: Double
    public var total: Double
    public var charges: Int

    public init(stage: Int, remaining: Double, total: Double, charges: Int = 0) {
        self.stage = stage
        self.remaining = remaining
        self.total = total
        self.charges = charges
    }

    public var fraction: Double { total > 0 ? min(1, max(0, remaining / total)) : 0 }
}

/// スキルボタンのバッジ（スタック・形態・タイマー）。
public struct KitBadge: Hashable, Sendable {
    public enum Kind: Int, Hashable, Sendable {
        case stacks, form, timer
    }

    public var kind: Kind
    /// スタック数 / 形態の番号。
    public var value: Int
    public var maxValue: Int
    /// timer 用の残り秒と全体。
    public var remaining: Double
    public var total: Double

    public init(kind: Kind, value: Int = 0, maxValue: Int = 0, remaining: Double = 0, total: Double = 0) {
        self.kind = kind
        self.value = value
        self.maxValue = maxValue
        self.remaining = remaining
        self.total = total
    }
}

/// スキル説明（ja / en のテンプレート）。`{damage} {total} {hits} {shield} {heal} {range} {radius} {cd} {x0}..{x3}` と、
/// extras の `KitStat.key` で引く `{key}` を sim の数値で埋める（説明文の数値と sim をずらさない）。
public struct KitText: Hashable, Sendable {
    public var ja: String
    public var en: String

    public init(ja: String, en: String) {
        self.ja = ja
        self.en = en
    }

    public func template(english: Bool) -> String { english ? en : ja }

    public func filled(english: Bool, numbers: SkillNumbers, targeting: SkillTargeting) -> String {
        KitText.fill(template(english: english), numbers: numbers, targeting: targeting)
    }

    public static func fill(_ template: String, numbers: SkillNumbers, targeting: SkillTargeting) -> String {
        var out = template
        func put(_ key: String, _ text: String) {
            if out.contains(key) { out = out.replacingOccurrences(of: key, with: text) }
        }
        put("{damage}", whole(numbers.damage))
        put("{total}", whole(numbers.totalDamage))
        put("{hits}", String(numbers.hits))
        put("{shield}", whole(numbers.shield))
        put("{heal}", whole(numbers.heal))
        put("{range}", whole(targeting.range))
        put("{radius}", whole(targeting.radius))
        put("{cd}", short(numbers.cooldown))
        for k in 0..<4 {
            put("{x\(k)}", k < numbers.extras.count ? short(numbers.extras[k].value) : "0")
        }
        // 名前で引く {key}（extras の全要素。{x#} と同じ値・同じ書式）。組み込みの名前（damage など）が先に勝ち、
        // 同名の key は先頭のものが勝つ。空の key は無視する。
        for e in numbers.extras where !e.key.isEmpty {
            put("{\(e.key)}", short(e.value))
        }
        return out
    }

    private static func whole(_ v: Double) -> String {
        v.isFinite ? String(Int(v.rounded())) : "0"
    }

    /// 整数に近ければ整数、そうでなければ小数 1 桁。
    private static func short(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        if abs(v - v.rounded()) < 0.05 { return String(Int(v.rounded())) }
        return String(format: "%.1f", v)
    }
}

public enum HeroKits {
    /// H025..H034 のスタブ（isReady == false の間は存在しないのと同じ）。
    static let all: [any HeroKit] = [
        Kit_H025(), Kit_H026(), Kit_H027(), Kit_H028(), Kit_H029(),
        Kit_H030(), Kit_H031(), Kit_H032(), Kit_H033(), Kit_H034(),
    ]

    /// テスト専用の差し込み口（モジュール内からのみ見える。本番のコードは触らない）。
    /// 空でなければ、ここにある isReady のキットが `all` より先に引かれる。
    nonisolated(unsafe) static var testOverride: [any HeroKit] = []

    /// 有効なキットが 1 つも無い間は、ID の照合をせずに抜ける（HUD・ボットが毎フレーム引くため）。
    private static let anyReady: Bool = all.contains { $0.isReady }

    /// 有効（isReady）なキット。
    static func kit(for heroID: String) -> (any HeroKit)? {
        if !testOverride.isEmpty, let k = testOverride.first(where: { $0.heroID == heroID && $0.isReady }) {
            return k
        }
        guard anyReady else { return nil }
        return all.first { $0.heroID == heroID && $0.isReady }
    }

    /// hot path: 先に hero.kit != nil で弾く。
    static func kit(of u: Unit) -> (any HeroKit)? {
        guard u.hero?.kit != nil, let id = u.hero?.heroID else { return nil }
        return kit(for: id)
    }

    /// Unit を丸ごとコピーしないための版（s.units[i] の hero.kit が非 nil のときだけレジストリを引く）。
    @inline(__always)
    static func kit(in s: SimState, _ i: Int) -> (any HeroKit)? {
        guard s.units[i].hero?.kit != nil, let id = s.units[i].hero?.heroID else { return nil }
        return kit(for: id)
    }

    public static func hasKit(_ heroID: String) -> Bool { kit(for: heroID) != nil }

    /// 汎用の結果を土台にしたキットの照準情報（キットが無ければ汎用）。
    public static func targeting(for skill: SkillDef, hero: HeroDef, stage: Int) -> SkillTargeting {
        let base = SkillCatalog.genericTargeting(for: skill, hero: hero)
        guard let kit = kit(for: hero.heroID) else { return base }
        return kit.targeting(slot: skill.slot, stage: stage, skill: skill, hero: hero, base: base)
    }

    /// 汎用の結果を土台にしたキットの数値（キットが無ければ汎用）。
    public static func numbers(for skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats, stage: Int = 0) -> SkillNumbers {
        let base = SkillCatalog.genericNumbers(for: skill, hero: hero, rank: rank, stats: stats)
        guard let kit = kit(for: hero.heroID) else { return base }
        return kit.numbers(slot: skill.slot, stage: stage, skill: skill, hero: hero,
                           rank: min(max(1, rank), max(1, skill.slot.maxRank)), stats: stats, base: base)
    }

    /// 再使用の窓が開いていればその段、なければ 0（通常の発動）。
    public static func activeStage(_ hero: HeroData, slot: SkillSlot) -> Int {
        guard let k = hero.kit, slot.rawValue < k.windows.count else { return 0 }
        let w = k.windows[slot.rawValue]
        return w.isOpen ? w.stage : 0
    }

    public static func recast(_ hero: HeroData, slot: SkillSlot) -> RecastInfo? {
        guard let k = hero.kit, slot.rawValue < k.windows.count else { return nil }
        let w = k.windows[slot.rawValue]
        guard w.isOpen else { return nil }
        return RecastInfo(stage: w.stage, remaining: w.remaining, total: w.total, charges: w.charges)
    }

    public static func badge(_ hero: HeroData, slot: SkillSlot) -> KitBadge? {
        guard hero.kit != nil, let kit = kit(for: hero.heroID) else { return nil }
        return kit.badge(slot: slot, hero: hero)
    }

    public static func text(heroID: String, slot: SkillSlot) -> KitText? {
        kit(for: heroID)?.text(slot: slot)
    }

    /// 再使用の窓が開いているか（CD・コストを無視して撃てる状態）。
    static func isRecasting(_ s: SimState, _ i: Int, _ slot: SkillSlot) -> Bool {
        guard let k = s.units[i].hero?.kit, slot.rawValue < k.windows.count else { return false }
        return k.windows[slot.rawValue].isOpen
    }

    /// ボットのスキル判断の上書き（キットが無ければ既定）。
    static func botCast(_ s: SimState, _ ctx: SimContext, bot i: Int, slot: SkillSlot, targeting: SkillTargeting,
                        target: Int, fighting: Bool) -> BotKitDecision {
        guard let kit = kit(in: s, i) else { return .useDefault }
        return kit.botCast(s, ctx, bot: i, slot: slot, targeting: targeting, target: target, fighting: fighting)
    }

    /// ボットのファーム時の突入系スキルの許可（キットが無ければ false）。
    static func botFarm(_ s: SimState, _ ctx: SimContext, bot i: Int, slot: SkillSlot, targeting: SkillTargeting,
                        center: Vec2, count: Int) -> Bool {
        guard let kit = kit(in: s, i) else { return false }
        return kit.botFarm(s, ctx, bot: i, slot: slot, targeting: targeting, center: center, count: count)
    }

    /// ボットの撤退時のスキル判断（キットが無ければ既定）。
    static func botEscape(_ s: SimState, _ ctx: SimContext, bot i: Int, slot: SkillSlot, targeting: SkillTargeting,
                          flee: Vec2, enemyDistance: Double) -> BotKitDecision {
        guard let kit = kit(in: s, i) else { return .useDefault }
        return kit.botEscape(s, ctx, bot: i, slot: slot, targeting: targeting, flee: flee, enemyDistance: enemyDistance)
    }
}
