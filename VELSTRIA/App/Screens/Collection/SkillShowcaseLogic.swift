import Foundation
import VelstriaCore

// 担当: ui-collection。ヒーロー詳細・スキル詳細（Mobile Legends 風の「左: ヒーロー情報 / 右: スキル詳細」レイアウト）の
// 純粋な計算。SwiftUI に依存させず、色は RGB の値で持つ（View 側で Color にする）。AppTests/SkillShowcaseTests で検証。

// MARK: - 色（SwiftUI 非依存）

/// 0...1 の RGB。
struct SkillRGB: Equatable {
    var r: Double
    var g: Double
    var b: Double
}

// MARK: - スキルのタグ

/// タグの見た目（名前・記号・色）。
struct SkillTagStyle: Equatable {
    var key: String
    var name: String
    var symbol: String
    var rgb: SkillRGB
}

/// スキルのタグ（バフ・範囲技・減速・衝突・妨害 など）。キーは小文字の英字（`HeroKits.tags` と同じ語彙）。
enum SkillTags {
    /// 画面が知っているキー。これ以外のキーは名前をそのまま出し、灰色にする。
    static let knownKeys = ["buff", "aoe", "slow", "clash", "disrupt", "burst", "mobility", "heal", "shield",
                            "control", "stun", "pull", "execute"]

    /// 1 つのスキルに付けるタグの最大数。
    static let maxTagsPerSkill = 2

    // MARK: 色（唯一の対応表）

    private static let buffRGB = SkillRGB(r: 0.20, g: 0.74, b: 0.74)       // バフ = ティール
    private static let aoeRGB = SkillRGB(r: 0.93, g: 0.52, b: 0.18)        // 範囲 = オレンジ
    private static let controlRGB = SkillRGB(r: 0.86, g: 0.32, b: 0.44)    // 減速・妨害・スタン・拘束 = ピンクがかった赤
    private static let mobilityRGB = SkillRGB(r: 0.58, g: 0.38, b: 0.86)   // 衝突・移動 = 紫
    private static let burstRGB = SkillRGB(r: 0.94, g: 0.36, b: 0.20)      // 爆発・処刑 = 赤みのオレンジ
    private static let healRGB = SkillRGB(r: 0.28, g: 0.76, b: 0.42)       // 回復 = 緑
    private static let shieldRGB = SkillRGB(r: 0.30, g: 0.55, b: 0.95)     // シールド = 青
    private static let unknownRGB = SkillRGB(r: 0.50, g: 0.54, b: 0.62)

    /// タグの色（この関数が色の唯一の対応表）。
    static func rgb(for key: String) -> SkillRGB {
        switch normalized(key) {
        case "buff": return buffRGB
        case "aoe": return aoeRGB
        case "slow", "disrupt", "stun", "control", "pull": return controlRGB
        case "clash", "mobility": return mobilityRGB
        case "burst", "execute": return burstRGB
        case "heal": return healRGB
        case "shield": return shieldRGB
        default: return unknownRGB
        }
    }

    static func name(for key: String) -> String {
        switch normalized(key) {
        case "buff": return L("バフ", "Buff")
        case "aoe": return L("範囲技", "AoE")
        case "slow": return L("減速", "Slow")
        case "clash": return L("衝突", "Clash")
        case "disrupt": return L("妨害", "Disrupt")
        case "burst": return L("バースト", "Burst")
        case "mobility": return L("移動", "Mobility")
        case "heal": return L("回復", "Heal")
        case "shield": return L("シールド", "Shield")
        case "control": return L("拘束", "Control")
        case "stun": return L("スタン", "Stun")
        case "pull": return L("引き寄せ", "Pull")
        case "execute": return L("処刑", "Execute")
        default: return key
        }
    }

    static func symbol(for key: String) -> String {
        switch normalized(key) {
        case "buff": return "arrow.up.circle.fill"
        case "aoe": return "circle.dashed"
        case "slow": return "tortoise.fill"
        case "clash": return "arrow.right.to.line"
        case "disrupt": return "exclamationmark.triangle.fill"
        case "burst": return "burst.fill"
        case "mobility": return "wind"
        case "heal": return "cross.circle.fill"
        case "shield": return "shield.fill"
        case "control": return "link"
        case "stun": return "star.circle.fill"
        case "pull": return "arrow.down.left.and.arrow.up.right"
        case "execute": return "scope"
        default: return "tag.fill"
        }
    }

    static func style(for key: String) -> SkillTagStyle {
        SkillTagStyle(key: key, name: name(for: key), symbol: symbol(for: key), rgb: rgb(for: key))
    }

    private static func normalized(_ key: String) -> String { key.lowercased() }

    // MARK: ヒーロー固有のタグ（統合点）

    /// 統合点: キット層の `HeroKits.tags(heroID:slot:)` が入ったら、ここだけを差し替える。
    /// 現在は常に nil（= このファイルの派生ルールを使う）。nil または空配列のときは派生ルールへ戻る。
    ///   差し替え後: `return HeroKits.hasKit(heroID) ? HeroKits.tags(heroID: heroID, slot: slot) : nil`
    static func kitTagOverride(heroID: String, slot: SkillSlot) -> [String]? {
        HeroKits.hasKit(heroID) ? HeroKits.tags(heroID: heroID, slot: slot) : nil
    }

    // MARK: 派生ルール

    /// スキルのタグ（最大 2 個、先頭が主タグ。アイコンの下の見出しに使う）。
    /// キット層の上書きがあればそれ、無ければ照準の形・CC・回復・シールドから派生する。
    /// `master` は呼び出し側の文脈を揃えるための引数（現在の派生では参照しない）。
    static func tags(for skill: SkillDef, hero: HeroDef, master: MasterData = .shared) -> [String] {
        _ = master
        if let override = kitTagOverride(heroID: hero.heroID, slot: skill.slot) {
            let cleaned = unique(override.map { $0.lowercased() })
            if !cleaned.isEmpty { return Array(cleaned.prefix(maxTagsPerSkill)) }
        }
        let targeting = SkillCatalog.targeting(for: skill, hero: hero)
        let n = SkillCatalog.numbers(for: skill, hero: hero, rank: 1, stats: Stats())
        return derive(slot: skill.slot, archetype: targeting.archetype, cc: n.cc, heal: n.heal, shield: n.shield,
                      missingHealthRatio: n.missingHealthRatio)
    }

    /// 形・CC・回復・シールドからタグを決める（純粋。ここを直接テストする）。
    /// 並びは「主タグ（形）→ CC → 副タグ」で、先頭 2 個だけを返す。
    static func derive(slot: SkillSlot, archetype: SkillArchetype, cc: CrowdControl, heal: Double, shield: Double,
                       missingHealthRatio: Double) -> [String] {
        if slot == .passive || archetype == .passive { return ["buff"] }
        var out: [String] = []
        func add(_ key: String) { if !out.contains(key) { out.append(key) } }

        // 主タグ（スキルの形）
        switch archetype {
        case .passive:
            add("buff")
        case .cone, .groundAoE, .selfAoE, .multiStrike:
            add("aoe")
        case .dashStrike, .leapSlam:
            // 押し出す突進は「衝突」、それ以外は「移動」
            add(cc == .knockback ? "clash" : "mobility")
        case .blinkEmpower:
            add("mobility")
        case .targetedBlink:
            add("mobility")
            if missingHealthRatio > 0 { add("execute") }
        case .lineSkillshot, .piercingLine:
            add("burst")
        case .teamHeal:
            add("heal")
            if shield > 0 { add("shield") }
        case .healZone:
            add("heal")
        }
        // CC
        switch cc {
        case .none: break
        case .slow: add("slow")
        case .stun: add("stun")
        case .knockback: add("disrupt")
        case .root: add("control")
        }
        // 副タグ
        switch archetype {
        case .piercingLine, .healZone: add("aoe")
        default: break
        }
        if heal > 0 { add("heal") }
        if shield > 0 { add("shield") }
        return Array(out.prefix(maxTagsPerSkill))
    }

    /// 並びを保ったまま重複を除く。
    static func unique(_ keys: [String]) -> [String] {
        var seen: [String] = []
        for k in keys where !k.isEmpty && !seen.contains(k) { seen.append(k) }
        return seen
    }

    /// アイコンの下の見出し（主タグの名前。タグが無ければ空）。
    static func caption(for tags: [String]) -> String {
        tags.first.map { name(for: $0) } ?? ""
    }

    /// ヒーローの「サブロール」表示（3 つのアクティブスキルのタグを数えて、多い順に最大 2 個。同数は先に出た順）。
    static func featureTags(hero: HeroDef, master: MasterData = .shared) -> [String] {
        var counts: [(key: String, count: Int)] = []
        for skill in master.skills(forHero: hero.heroID) where skill.slot != .passive {
            for key in tags(for: skill, hero: hero, master: master) {
                if let i = counts.firstIndex(where: { $0.key == key }) {
                    counts[i].count += 1
                } else {
                    counts.append((key: key, count: 1))
                }
            }
        }
        // 安定ソート（Swift の sort は安定とは限らないので、元の順を添字で補う）
        let ranked = counts.enumerated().sorted { a, b in
            a.element.count != b.element.count ? a.element.count > b.element.count : a.offset < b.offset
        }
        return ranked.prefix(maxTagsPerSkill).map { $0.element.key }
    }
}

// MARK: - 評価バー（生存能力・攻撃能力・コントロール効果・難易度）

struct HeroRatings: Equatable {
    /// いずれも 0...1。
    var survivability: Double
    var offense: Double
    var control: Double
    var difficulty: Double
}

/// ヒーロー 1 人分の生の評価値（全ヒーローと並べて 0...1 に直す前の値）。
struct HeroRawRatings: Equatable {
    var survivability: Double
    var offense: Double
    var control: Double
}

enum HeroRatingMath {
    /// 最低限見えるバーの割合（生存・攻撃。最小のヒーローでもバーが空にならない）。
    static let barFloor = 0.12

    /// CC の強さの重み（1 秒あたり）。
    static func ccWeight(_ cc: CrowdControl) -> Double {
        switch cc {
        case .none: return 0
        case .slow: return 0.35
        case .root: return 0.8
        case .knockback: return 0.9
        case .stun: return 1.0
        }
    }

    /// CC 1 つの強さ = 重み × 持続秒（持続が未設定の CC は 1 秒扱い）。
    static func ccStrength(_ cc: CrowdControl, duration: Double) -> Double {
        guard cc != .none else { return 0 }
        return ccWeight(cc) * (duration > 0 ? duration : 1)
    }

    /// キットがタグで示す CC（`numbers.cc` に現れない効果。引き寄せ・拘束など）の重み。
    static func tagControlWeight(_ key: String) -> Double {
        switch key.lowercased() {
        case "stun": return 1.0
        case "pull": return 0.7
        case "control": return 0.8
        case "disrupt": return 0.6
        case "slow": return 0.35
        default: return 0
        }
    }

    /// 全ヒーローの値の中での位置（最小 = barFloor、最大 = 1。全員同じなら 0.5）。
    static func normalized(_ v: Double, among values: [Double]) -> Double {
        guard let lo = values.min(), let hi = values.max(), hi - lo > 1e-9 else { return 0.5 }
        let t = min(1, max(0, (v - lo) / (hi - lo)))
        return barFloor + (1 - barFloor) * t
    }

    /// 最大値に対する割合（0 は 0 のまま。CC の無いヒーローのバーは空になる）。
    static func ratio(_ v: Double, max hi: Double) -> Double {
        guard hi > 1e-9 else { return 0 }
        return min(1, max(0, v / hi))
    }

    /// 難易度（1...5）→ 0.2...1。
    static func difficultyValue(_ d: Int) -> Double {
        Double(min(5, max(1, d))) / 5
    }

    /// ヒーロー 1 人分の生の評価値。最大レベルの能力値とランク 1 のスキル数値（キットのヒーローはキットの値）から求める。
    /// - 生存: 最大 HP × (100 + 防御と魔防の平均) / 100（被ダメージ軽減 100 / (100 + 防御) の逆数）
    /// - 攻撃: 通常攻撃の毎秒ダメージ + 各スキルの 1 回の合計ダメージ ÷ CD（1 秒未満は 1 秒）
    /// - コントロール: 各スキルの CC の強さの合計（アルティメットは 1.25 倍）
    static func raw(for hero: HeroDef, master: MasterData) -> HeroRawRatings {
        let st = HeroGrowth.baseStats(def: hero, level: Balance.maxLevel)
        let survivability = st.maxHP * (100 + (st.armor + st.magicResist) / 2) / 100
        var offense = st.attack * st.attackSpeed
        var control = 0.0
        for skill in master.skills(forHero: hero.heroID) where skill.slot != .passive {
            let n = SkillCatalog.numbers(for: skill, hero: hero, rank: 1, stats: st)
            offense += n.totalDamage / max(1, n.cooldown)
            var c = ccStrength(n.cc, duration: n.ccDuration)
            if n.cc == .none {
                // キットが CC をタグでだけ示す場合（引き寄せなど）
                c = SkillTags.tags(for: skill, hero: hero, master: master).map(tagControlWeight).max() ?? 0
            }
            control += c * (skill.slot == .ultimate ? 1.25 : 1)
        }
        return HeroRawRatings(survivability: survivability, offense: offense, control: control)
    }

    /// 生の評価値を、全ヒーローの値と並べて 0...1 にする（純粋。ここを直接テストする）。
    static func ratings(raw: HeroRawRatings, roster: [HeroRawRatings], difficulty: Int) -> HeroRatings {
        HeroRatings(survivability: normalized(raw.survivability, among: roster.map(\.survivability)),
                    offense: normalized(raw.offense, among: roster.map(\.offense)),
                    control: ratio(raw.control, max: roster.map(\.control).max() ?? 0),
                    difficulty: difficultyValue(difficulty))
    }

    /// マスターの全ヒーローと並べたときの、このヒーローの評価（4 項目とも 0...1）。
    static func ratings(for hero: HeroDef, master: MasterData) -> HeroRatings {
        ratings(raw: raw(for: hero, master: master),
                roster: master.heroes.map { raw(for: $0, master: master) },
                difficulty: hero.difficulty)
    }
}

// MARK: - レベル表（Lv.1 … Lv.N × CD・コスト・主な数値）

struct SkillLevelTable: Equatable {
    enum RowKind: Equatable {
        case cooldown
        case cost
        case figure(SkillMath.Figure)
    }

    struct Row: Equatable {
        var kind: RowKind
        var title: String
        /// ランク順の表示値（ranks と同じ長さ）。
        var values: [String]
    }

    var ranks: [Int]
    var rows: [Row]

    /// 「CD 時間」は常に出す。コストはランクで変わるときだけ行にし、変わらなければ 1 行目の説明（CD / 消費量）に出す。
    /// 主な数値の行はアーキタイプで決まる（ダメージ・追加ダメージ・回復・シールド。キットは値があるものだけ）。
    static func build(skill: SkillDef, hero: HeroDef) -> SkillLevelTable {
        let ranks = SkillMath.ranks(for: skill.slot)
        guard !ranks.isEmpty else { return SkillLevelTable(ranks: [], rows: []) }
        let archetype = SkillCatalog.targeting(for: skill, hero: hero).archetype
        let numbers = ranks.map { SkillMath.numbers(skill, hero: hero, rank: $0) }

        var rows: [Row] = []
        rows.append(Row(kind: .cooldown, title: L("CD時間", "Cooldown"),
                        values: ranks.map { SkillShowcaseText.fixed1(SkillMath.cooldown(skill, hero: hero, rank: $0)) }))
        let costs = ranks.map { SkillMath.cost(skill, hero: hero, rank: $0) }
        if costsVary(costs) {
            rows.append(Row(kind: .cost, title: SkillShowcaseText.costRowTitle(hero.resource),
                            values: costs.map { CollectionStyle.number($0, digits: 1) }))
        }
        for f in SkillMath.figures(skill, hero: hero, archetype: archetype) {
            rows.append(Row(kind: .figure(f), title: SkillMath.figureRowTitle(f),
                            values: numbers.map { SkillMath.figureValue(f, $0) }))
        }
        return SkillLevelTable(ranks: ranks, rows: rows)
    }

    /// コストがランクで変わるか（変わらなければ表に行を出さない）。
    static func costsVary(_ costs: [Double]) -> Bool {
        guard let first = costs.first else { return false }
        return costs.contains { abs($0 - first) > 1e-9 }
    }
}

// MARK: - 文字列

enum SkillShowcaseText {
    /// 小数 1 桁固定（CD の表示。7 → "7.0"）。
    static func fixed1(_ v: Double) -> String {
        String(format: "%.1f", v)
    }

    /// 「CD：7.0　マナ消費量：45」。
    static func statLine(cooldown: Double, cost: Double, resource: ResourceKind) -> String {
        let cd = fixed1(cooldown)
        let c = CollectionStyle.number(cost, digits: 1)
        let name = CollectionStyle.resourceName(resource)
        return L("CD：\(cd)　\(name)消費量：\(c)", "CD: \(cd)   \(name) Cost: \(c)")
    }

    static func costRowTitle(_ resource: ResourceKind) -> String {
        let name = CollectionStyle.resourceName(resource)
        return L("\(name)コスト", "\(name) Cost")
    }

    static func rankTitle(_ rank: Int) -> String { "Lv.\(rank)" }
}

extension SkillMath {
    /// ランク別のコスト。キットは numbers のコスト（ランクで変わる設計に追従）、それ以外は従来どおり一定。
    static func cost(_ skill: SkillDef, hero: HeroDef, rank: Int) -> Double {
        guard HeroKits.hasKit(hero.heroID) else { return cost(skill, resource: hero.resource) }
        return numbers(skill, hero: hero, rank: rank).cost
    }

    /// レベル表の行の見出し。
    static func figureRowTitle(_ f: Figure) -> String {
        switch f {
        case .damage: return L("基礎ダメージ", "Base Damage")
        case .bonusDamage: return L("追加ダメージ", "Bonus Damage")
        case .heal: return L("回復量", "Healing")
        case .shield: return L("シールド量", "Shield")
        }
    }
}

// MARK: - 説明文の強調

struct SkillTextSegment: Equatable {
    enum Role: Equatable {
        case plain
        case physical
        case magic
        case trueDamage
        case keyword
        case coefficient
        case heal
    }

    var text: String
    var role: Role
}

/// 説明文の中の語句を強調するために区切る（係数「(+70% …)」・ダメージの種類・CC などのキーワード・回復）。
enum SkillDescriptionStyler {
    private static let patterns: [(pattern: String, role: SkillTextSegment.Role)] = [
        // 係数: (+70% 攻撃力) / （+130%…）
        ("[（(]\\s*\\+?\\d+(?:\\.\\d+)?\\s*%[^）)]*[）)]", .coefficient),
        ("物理ダメージ|[Pp]hysical damage", .physical),
        ("魔法ダメージ|[Mm]agic(?:al)? damage", .magic),
        ("確定ダメージ|[Tt]rue damage", .trueDamage),
        ("回復|\\b[Hh]eal(?:s|ed|ing)?\\b", .heal),
        ("スタン|ノックバック|ノックアップ|移動不能|拘束|スロー|シールド|ブリンク|打ち上げ|沈黙|ステルス|無敵"
            + "|\\b[Ss]tun(?:s|ned)?\\b|\\b[Kk]nock(?:s|ed)? (?:back|up)\\b|\\b[Rr]oot(?:s|ed)?\\b"
            + "|\\b[Ss]low(?:s|ed)?\\b|\\b[Ss]hield(?:s|ed)?\\b|\\b[Bb]link(?:s)?\\b|\\b[Ss]tealth\\b", .keyword),
    ]

    private static let compiled: [(regex: NSRegularExpression, role: SkillTextSegment.Role)] = patterns.compactMap { p in
        (try? NSRegularExpression(pattern: p.pattern, options: [])).map { (regex: $0, role: p.role) }
    }

    /// 文字列を、強調する語句とそれ以外に区切る。重なったときは先頭が早いもの、同じなら長いものを採る。
    /// すべてのセグメントを連結すると元の文字列に戻る。
    static func segments(_ text: String) -> [SkillTextSegment] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var hits: [(range: NSRange, role: SkillTextSegment.Role)] = []
        for entry in compiled {
            for m in entry.regex.matches(in: text, options: [], range: whole) where m.range.length > 0 {
                hits.append((range: m.range, role: entry.role))
            }
        }
        hits.sort { a, b in
            a.range.location != b.range.location ? a.range.location < b.range.location : a.range.length > b.range.length
        }
        var out: [SkillTextSegment] = []
        var cursor = 0
        for h in hits where h.range.location >= cursor {
            if h.range.location > cursor {
                out.append(SkillTextSegment(text: ns.substring(with: NSRange(location: cursor, length: h.range.location - cursor)),
                                            role: .plain))
            }
            out.append(SkillTextSegment(text: ns.substring(with: h.range), role: h.role))
            cursor = h.range.location + h.range.length
        }
        if cursor < ns.length {
            out.append(SkillTextSegment(text: ns.substring(from: cursor), role: .plain))
        }
        return out
    }
}

// MARK: - 係数（「(+60% 攻撃力)」の行）

struct SkillCoefficient: Equatable {
    enum Kind: Equatable {
        case damageAttack
        case damagePower
        case healAttack
        case healPower
    }

    var kind: Kind
    /// 攻撃力・魔力 1 あたりの増分を % にした値。
    var percent: Double
    /// 例: 「+60% 攻撃力」。
    var text: String

    /// 表に出す数値の種類（figures）に合わせて、ダメージ・回復の係数を並べる（0 の係数は出さない）。
    static func parts(scaling: (damage: SkillMath.Scaling, heal: SkillMath.Scaling),
                      figures: [SkillMath.Figure]) -> [SkillCoefficient] {
        var out: [SkillCoefficient] = []
        let attackName = L("攻撃力", "ATK")
        let powerName = L("魔力", "Power")
        func pct(_ v: Double) -> Double { v * 100 }
        func label(_ p: Double, _ name: String) -> String { "+\(CollectionStyle.number(p, digits: 0))% \(name)" }
        if figures.contains(.damage) || figures.contains(.bonusDamage) {
            if scaling.damage.attack > 1e-9 {
                out.append(SkillCoefficient(kind: .damageAttack, percent: pct(scaling.damage.attack),
                                            text: label(pct(scaling.damage.attack), attackName)))
            }
            if scaling.damage.power > 1e-9 {
                out.append(SkillCoefficient(kind: .damagePower, percent: pct(scaling.damage.power),
                                            text: label(pct(scaling.damage.power), powerName)))
            }
        }
        if figures.contains(.heal) {
            if scaling.heal.attack > 1e-9 {
                out.append(SkillCoefficient(kind: .healAttack, percent: pct(scaling.heal.attack),
                                            text: label(pct(scaling.heal.attack), attackName)))
            }
            if scaling.heal.power > 1e-9 {
                out.append(SkillCoefficient(kind: .healPower, percent: pct(scaling.heal.power),
                                            text: label(pct(scaling.heal.power), powerName)))
            }
        }
        return out
    }
}

// MARK: - 選択

enum HeroSkillSelection {
    /// 開いたときに選んでおくスキル（スキル 1。無ければ先頭）。
    static func defaultSkill(_ skills: [SkillDef]) -> SkillDef? {
        skills.first { $0.slot == .skill1 } ?? skills.first
    }

    /// 選択中の ID が、このヒーローのスキルとして有効ならそれ、無効ならデフォルト。
    static func resolved(selectedID: String?, skills: [SkillDef]) -> SkillDef? {
        if let selectedID, let s = skills.first(where: { $0.skillID == selectedID }) { return s }
        return defaultSkill(skills)
    }
}
