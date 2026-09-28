import Foundation
import VelstriaCore

// 担当: ui-collection。画面表示用の純粋な計算（DESIGN.md の式をそのまま表示に使う。AppTests で検証）。

// MARK: - スキル（DESIGN §5・§6）

enum SkillMath {
    /// ランク 1...最大ランク。
    static func ranks(for slot: SkillSlot) -> [Int] {
        slot == .passive ? [] : Array(1...slot.maxRank)
    }

    /// 基礎ダメージ（ランク補正込み）= base × (1 + 0.30 × (rank − 1))。
    static func damage(base: Double, rank: Int) -> Double {
        base * (1 + Balance.skillDamagePerRank * Double(max(0, rank - 1)))
    }

    /// CD（CD 短縮なし）= cooldown × (1 − 0.06 × (rank − 1))。
    static func cooldown(_ skill: SkillDef, rank: Int) -> Double {
        SkillSystem.cooldown(for: skill, rank: rank, cdr: 0)
    }

    /// 実効コスト（Energy は ×0.6）。
    static func cost(_ skill: SkillDef, resource: ResourceKind) -> Double {
        SkillSystem.cost(for: skill, resource: resource)
    }

    /// 攻撃力スケーリングの実効係数（総攻撃力 × scaling_attack × 0.6）。
    static func effectiveAttackScaling(_ skill: SkillDef) -> Double {
        skill.scalingAttack * Balance.skillAttackScalingFactor
    }

    /// CC の効果量と時間（Ult は強化版）。
    static func ccDetail(_ cc: CrowdControl, isUltimate: Bool) -> String {
        let s = CollectionStyle.seconds
        switch cc {
        case .none:
            return L("なし", "None")
        case .slow:
            let pct = (isUltimate ? Balance.ultSlowPct : Balance.slowPct) * 100
            let dur = isUltimate ? Balance.ultSlowDuration : Balance.slowDuration
            return L("移動速度 −\(CollectionStyle.percent(pct)) / \(s(dur))",
                     "−\(CollectionStyle.percent(pct)) move speed for \(s(dur))")
        case .root:
            let dur = isUltimate ? Balance.ultRootDuration : Balance.rootDuration
            return L("移動不可 \(s(dur))", "Rooted for \(s(dur))")
        case .stun:
            let dur = isUltimate ? Balance.ultStunDuration : Balance.stunDuration
            return L("行動不能 \(s(dur))", "Stunned for \(s(dur))")
        case .knockback:
            let dist = CollectionStyle.number(Balance.knockbackDistance, digits: 0)
            return L("\(dist) 押し出し + スタン \(s(Balance.knockbackStun))",
                     "Pushed \(dist) units + \(s(Balance.knockbackStun)) stun")
        }
    }

    /// ヒーロー固有のパッシブ係数 k = 1.0 + 0.02 × (番号 mod 5)。
    static func passiveCoefficient(heroNumber: Int) -> Double {
        1.0 + 0.02 * Double(heroNumber % 5)
    }

    /// ロール別パッシブの効果文（DESIGN §6）。
    static func passiveText(role: Role, heroNumber: Int) -> String {
        let k = passiveCoefficient(heroNumber: heroNumber)
        let n = { (v: Double) in CollectionStyle.number(v, digits: 2) }
        switch role {
        case .vanguard:
            return L("HP が 40% 未満になると最大 HP の \(n(15 * k))% のシールドを得る（CD 20 秒）。",
                     "Below 40% HP, gain a shield equal to \(n(15 * k))% max HP (20s cooldown).")
        case .duelist:
            return L("通常攻撃が命中する毎に攻撃速度 +\(n(6 * k))%（最大 5 スタック、3 秒持続）。",
                     "Each basic attack hit grants +\(n(6 * k))% attack speed (up to 5 stacks, 3s).")
        case .ranger:
            return L("4 発毎の通常攻撃が必ずクリティカルになり、\(n(1.75 * k)) 倍のダメージを与える。",
                     "Every 4th basic attack is a guaranteed critical dealing \(n(1.75 * k))× damage.")
        case .arcanist:
            return L("スキル命中時、他のスキルの CD を \(n(0.6 * k)) 秒短縮する（1 キャストにつき 1 回）。",
                     "Skill hits reduce your other cooldowns by \(n(0.6 * k))s (once per cast).")
        case .support:
            return L("スキル使用時、800 以内で HP 割合が最も低い味方を 40 + \(n(10 * k))×Lv 回復する。",
                     "Casting a skill heals the lowest-HP ally within 800 for 40 + \(n(10 * k))×Lv.")
        case .assassin:
            return L("草むら/ステルス解除後 3 秒以内の最初のダメージ +\(n(30 * k))%。キル/アシストで全スキルの CD −30%。",
                     "First damage within 3s of leaving brush/stealth deals +\(n(30 * k))%. Takedowns cut all cooldowns by 30%.")
        }
    }
}

// MARK: - 能力値（DESIGN §4）

enum HeroStatKind: CaseIterable, Identifiable {
    case hp, attack, defense, magicDefense, attackSpeed, moveSpeed, range
    var id: Self { self }

    var label: String {
        switch self {
        case .hp: return L("最大HP", "Max HP")
        case .attack: return L("攻撃力", "Attack")
        case .defense: return L("防御", "Armor")
        case .magicDefense: return L("魔防", "Magic Res.")
        case .attackSpeed: return L("攻撃速度", "Atk Speed")
        case .moveSpeed: return L("移動速度", "Move Speed")
        case .range: return L("射程", "Range")
        }
    }

    var symbol: String {
        switch self {
        case .hp: return "heart.fill"
        case .attack: return "bolt.fill"
        case .defense: return "shield.fill"
        case .magicDefense: return "sparkles"
        case .attackSpeed: return "timer"
        case .moveSpeed: return "hare.fill"
        case .range: return "scope"
        }
    }

    func value(_ st: Stats) -> Double {
        switch self {
        case .hp: return st.maxHP
        case .attack: return st.attack
        case .defense: return st.armor
        case .magicDefense: return st.magicResist
        case .attackSpeed: return st.attackSpeed
        case .moveSpeed: return st.moveSpeed
        case .range: return st.attackRange
        }
    }

    /// レベル毎の成長量（表示用）。成長しない項目は nil。
    func growth(_ def: HeroDef) -> Double? {
        switch self {
        case .hp: return def.hpGrowth
        case .attack: return def.attackGrowth
        case .defense: return def.defenseGrowth
        case .magicDefense: return def.magicDefenseGrowth
        case .attackSpeed:
            let base = def.isRanged ? Balance.rangedAttackSpeed : Balance.meleeAttackSpeed
            return base * Balance.attackSpeedPerLevel
        case .moveSpeed, .range: return nil
        }
    }

    var digits: Int { self == .attackSpeed ? 2 : 0 }
}

enum HeroStatMath {
    /// 全ヒーロー Lv 最大時の最大値（バーの正規化用）。
    static func maxValue(_ kind: HeroStatKind, master: MasterData) -> Double {
        let values = master.heroes.map { kind.value(HeroGrowth.baseStats(def: $0, level: Balance.maxLevel)) }
        return max(values.max() ?? 1, 1e-6)
    }
}

// MARK: - 装備（DESIGN §8）

struct ItemStatLine: Identifiable, Equatable {
    var id: String { label }
    var label: String
    var value: String
    var symbol: String
}

enum ItemMath {
    /// 非ゼロの能力値。
    static func statLines(_ item: ItemDef) -> [ItemStatLine] {
        var lines: [ItemStatLine] = []
        let n = { (v: Double) in CollectionStyle.number(v, digits: 1) }
        if item.attack != 0 { lines.append(.init(label: L("攻撃力", "Attack"), value: "+\(n(item.attack))", symbol: "bolt.fill")) }
        if item.abilityPower != 0 { lines.append(.init(label: L("魔力", "Power"), value: "+\(n(item.abilityPower))", symbol: "sparkles")) }
        if item.hp != 0 { lines.append(.init(label: L("最大HP", "Max HP"), value: "+\(n(item.hp))", symbol: "heart.fill")) }
        if item.armor != 0 { lines.append(.init(label: L("防御", "Armor"), value: "+\(n(item.armor))", symbol: "shield.fill")) }
        if item.magicResist != 0 { lines.append(.init(label: L("魔防", "Magic Res."), value: "+\(n(item.magicResist))", symbol: "shield.lefthalf.filled")) }
        if item.moveSpeed != 0 { lines.append(.init(label: L("移動速度", "Move Speed"), value: "+\(n(item.moveSpeed))", symbol: "hare.fill")) }
        if item.cooldownReductionPct != 0 {
            lines.append(.init(label: L("CD短縮", "Cooldown Red."), value: "+\(CollectionStyle.percent(item.cooldownReductionPct))", symbol: "timer"))
        }
        return lines
    }

    /// 一覧用の主要能力（最初の能力値）。
    static func primaryStat(_ item: ItemDef) -> ItemStatLine? {
        statLines(item).first
    }

    /// カテゴリ別の固有パッシブ効果（X = passive_text の %）。
    static func passiveEffectText(_ item: ItemDef) -> String {
        let x = item.passivePercent
        let p = { (v: Double) in CollectionStyle.percent(v) }
        switch item.category {
        case .attack:
            return L("通常攻撃のダメージ +\(p(x))", "Basic attack damage +\(p(x))")
        case .magic:
            return L("スキルダメージ +\(p(x))", "Skill damage +\(p(x))")
        case .defense:
            return L("受けるダメージ −\(p(x / 2))", "Damage taken −\(p(x / 2))")
        case .movement:
            return L("非戦闘時の移動速度 +\(p(x))", "Out-of-combat move speed +\(p(x))")
        case .utility:
            return L("回復・シールド量 +\(p(x))、Mana 回復 +\(p(x))", "Healing & shielding +\(p(x)), mana regen +\(p(x))")
        case .jungle:
            return L("モンスターへのダメージ +\(p(3 * x))、モンスター Gold +20%",
                     "Damage to monsters +\(p(3 * x)), monster gold +20%")
        }
    }

    /// 素材（build_from）。存在しない ID は除外、重複は保持。
    static func components(_ item: ItemDef, master: MasterData) -> [ItemDef] {
        item.buildFrom.compactMap { master.item($0) }
    }

    /// この装備を素材に含む上位装備（ID 昇順）。
    static func buildsInto(_ itemID: String, master: MasterData) -> [ItemDef] {
        master.items.filter { $0.buildFrom.contains(itemID) }
    }

    /// 素材をすべて所持している場合の合成コスト = max(price × 0.3, price − 素材価格合計)。
    static func combineCost(_ item: ItemDef, master: MasterData) -> Double {
        let parts = components(item, master: master).reduce(0) { $0 + $1.priceGold }
        guard parts > 0 else { return item.priceGold }
        return max(item.priceGold * Balance.minCombineCostRatio, item.priceGold - parts).rounded()
    }

    static func filtered(_ items: [ItemDef], category: ItemCategory?, tier: Int?) -> [ItemDef] {
        items.filter { (category == nil || $0.category == category) && (tier == nil || $0.tier == tier) }
    }
}

// MARK: - ビルド（DESIGN §8: 6 枠・移動系 1・ジャングル系 1）

enum BuildCheck: Equatable {
    case ok
    case full
    case duplicate
    case movementLimit
    case jungleLimit
    case unknown

    var message: String {
        switch self {
        case .ok: return ""
        case .full: return L("装備枠がいっぱいです（最大 6 個）", "All 6 slots are filled")
        case .duplicate: return L("同じ装備は 1 つまでです（固有パッシブは重複しません）", "Only one of each item (unique passives don't stack)")
        case .movementLimit: return L("移動系装備は 1 つまでです", "Only one Movement item allowed")
        case .jungleLimit: return L("ジャングル系装備は 1 つまでです", "Only one Jungle item allowed")
        case .unknown: return L("不明な装備です", "Unknown item")
        }
    }
}

enum BuildRules {
    static var slotCount: Int { Balance.itemSlots }

    /// 不明 ID・上限超過・制限違反を取り除く（順序は保持）。
    static func sanitized(_ build: [String], master: MasterData) -> [String] {
        var result: [String] = []
        for id in build where check(id, adding: result, replacing: nil, master: master) == .ok {
            result.append(id)
        }
        return result
    }

    /// build に itemID を追加（replacing 指定時はその位置を置換）できるか。
    static func check(_ itemID: String, adding build: [String], replacing index: Int?, master: MasterData) -> BuildCheck {
        guard let item = master.item(itemID) else { return .unknown }
        var others = build
        if let index, others.indices.contains(index) {
            others.remove(at: index)
        } else if build.count >= slotCount {
            return .full
        }
        if others.contains(itemID) { return .duplicate }
        let categories = others.compactMap { master.item($0)?.category }
        if item.category == .movement && categories.contains(.movement) { return .movementLimit }
        if item.category == .jungle && categories.contains(.jungle) { return .jungleLimit }
        return .ok
    }

    static func totalCost(_ build: [String], master: MasterData) -> Double {
        build.compactMap { master.item($0)?.priceGold }.reduce(0, +)
    }

    /// 推奨ビルド（ロール別。未提供なら空）。
    static func recommended(for heroID: String, master: MasterData) -> [String] {
        guard let role = master.hero(heroID)?.role else { return [] }
        return sanitized(ItemSystem.recommendedBuild(role: role, master: master), master: master)
    }

    /// 表示・編集の初期値: カスタムビルド優先、無ければ推奨。
    static func current(for heroID: String, profile: Profile, master: MasterData) -> [String] {
        if let custom = profile.customBuilds[heroID] {
            return sanitized(custom, master: master)
        }
        return recommended(for: heroID, master: master)
    }

    static func move(_ build: [String], from: Int, by offset: Int) -> [String] {
        let to = from + offset
        guard build.indices.contains(from), build.indices.contains(to) else { return build }
        var b = build
        b.swapAt(from, to)
        return b
    }
}

// MARK: - ルーン（DESIGN §8: メインパス 1 + 各 Tier 1 個）

struct RuneBonus: Equatable {
    var attackPct: Double = 0
    var abilityPowerPct: Double = 0
    var skillDamagePct: Double = 0
    var maxHPPct: Double = 0
    var defensesPct: Double = 0
    var moveSpeedPct: Double = 0
    var cooldownReductionPct: Double = 0
    var regenPct: Double = 0
    var healingPct: Double = 0

    /// 表示用の行（0 は除外）。
    var lines: [ItemStatLine] {
        var out: [ItemStatLine] = []
        let p = { (v: Double) in "+" + CollectionStyle.percent(v) }
        if attackPct > 0 { out.append(.init(label: L("攻撃力", "Attack"), value: p(attackPct), symbol: "bolt.fill")) }
        if abilityPowerPct > 0 { out.append(.init(label: L("魔力", "Power"), value: p(abilityPowerPct), symbol: "sparkles")) }
        if skillDamagePct > 0 { out.append(.init(label: L("スキルダメージ", "Skill Damage"), value: p(skillDamagePct), symbol: "wand.and.stars")) }
        if maxHPPct > 0 { out.append(.init(label: L("最大HP", "Max HP"), value: p(maxHPPct), symbol: "heart.fill")) }
        if defensesPct > 0 { out.append(.init(label: L("防御・魔防", "Armor & MR"), value: p(defensesPct), symbol: "shield.fill")) }
        if moveSpeedPct > 0 { out.append(.init(label: L("移動速度", "Move Speed"), value: p(moveSpeedPct), symbol: "hare.fill")) }
        if cooldownReductionPct > 0 { out.append(.init(label: L("CD短縮", "Cooldown Red."), value: p(cooldownReductionPct), symbol: "timer")) }
        if regenPct > 0 { out.append(.init(label: L("HP/Mana 回復", "HP/Mana Regen"), value: p(regenPct), symbol: "arrow.clockwise")) }
        if healingPct > 0 { out.append(.init(label: L("回復量", "Healing"), value: p(healingPct), symbol: "cross.circle.fill")) }
        return out
    }
}

enum RuneMath {
    static let maxPages = 5
    static let tiers = [1, 2, 3]
    static let maxNameLength = 16

    /// パス・Tier のルーン（ID 昇順）。
    static func runes(path: RunePath, tier: Int, master: MasterData) -> [RuneDef] {
        master.runes.filter { $0.path == path && $0.tier == tier }
    }

    static func defaultPageName(index: Int) -> String {
        L("ページ\(index + 1)", "Page \(index + 1)")
    }

    /// 各 Tier の先頭ルーンを選んだ既定ページ。
    static func defaultPage(name: String, path: RunePath = .valor, master: MasterData) -> RunePage {
        RunePage(name: name, primaryPath: path,
                 runeIDs: tiers.map { runes(path: path, tier: $0, master: master).first?.runeID ?? "" })
    }

    /// パスと Tier が一致しないルーンを既定値に置き換え、3 枠に揃える。
    static func normalized(_ page: RunePage, master: MasterData) -> RunePage {
        var p = page
        p.runeIDs = tiers.enumerated().map { i, tier in
            let options = runes(path: page.primaryPath, tier: tier, master: master)
            let current = i < page.runeIDs.count ? page.runeIDs[i] : ""
            if options.contains(where: { $0.runeID == current }) { return current }
            return options.first?.runeID ?? ""
        }
        let trimmed = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.name = String(trimmed.prefix(maxNameLength))
        return p
    }

    /// パス変更（ルーンは新パスの既定に置換）。
    static func changingPath(_ page: RunePage, to path: RunePath, master: MasterData) -> RunePage {
        var p = page
        p.primaryPath = path
        p.runeIDs = []
        return normalized(p, master: master)
    }

    /// 1 個分の効果（X = effect の %）。
    static func bonus(path: RunePath, percent x: Double) -> RuneBonus {
        var b = RuneBonus()
        switch path {
        case .valor:
            b.attackPct = x
        case .arcana:
            b.abilityPowerPct = x
            b.skillDamagePct = x / 2
        case .resolve:
            b.maxHPPct = x
            b.defensesPct = x
        case .cunning:
            b.moveSpeedPct = x / 2
            b.cooldownReductionPct = x / 2
        case .harmony:
            b.regenPct = 3 * x
            b.healingPct = x
        }
        return b
    }

    /// ページ全体の合計。
    static func bonus(for page: RunePage, master: MasterData) -> RuneBonus {
        var total = RuneBonus()
        for id in page.runeIDs {
            guard let r = master.rune(id) else { continue }
            let b = bonus(path: r.path, percent: r.percent)
            total.attackPct += b.attackPct
            total.abilityPowerPct += b.abilityPowerPct
            total.skillDamagePct += b.skillDamagePct
            total.maxHPPct += b.maxHPPct
            total.defensesPct += b.defensesPct
            total.moveSpeedPct += b.moveSpeedPct
            total.cooldownReductionPct += b.cooldownReductionPct
            total.regenPct += b.regenPct
            total.healingPct += b.healingPct
        }
        return total
    }

    /// ルーン 1 個の効果文。
    static func effectText(_ rune: RuneDef) -> String {
        bonus(path: rune.path, percent: rune.percent).lines.map { "\($0.label) \($0.value)" }
            .joined(separator: L("・", ", "))
    }
}

// MARK: - スペル（2 枠・既定 + ヒーロー別）

enum SpellLoadoutRules {
    static let slotCount = 2

    /// slot に spellID を入れる。もう一方の枠に同じスペルがあれば入れ替える。
    static func assigning(_ spellID: String, slot: Int, in current: [String]) -> [String] {
        var s = normalized(current)
        guard (0..<slotCount).contains(slot) else { return s }
        if let other = s.firstIndex(of: spellID), other != slot {
            s[other] = s[slot]
        }
        s[slot] = spellID
        return s
    }

    /// 2 枠に揃える（不足は既定 BS01/BS03 で補完、重複は解消）。
    static func normalized(_ spells: [String]) -> [String] {
        let fallback = ["BS01", "BS03", "BS04"]
        var out: [String] = []
        for id in spells + fallback where !out.contains(id) && !id.isEmpty {
            out.append(id)
            if out.count == slotCount { break }
        }
        return out
    }

    /// ヒーローの実効スペル（上書きが無ければ既定）。
    static func effective(heroID: String?, profile: Profile) -> [String] {
        if let heroID, let override = profile.heroSpells[heroID] { return normalized(override) }
        return normalized(profile.defaultSpells)
    }
}

// MARK: - エモート（4 枠。空き枠は ""）

enum EmoteSlots {
    static let count = 4

    /// 常に 4 要素（空き枠は ""）。
    static func normalized(_ ids: [String]) -> [String] {
        var out = Array(ids.prefix(count))
        while out.count < count { out.append("") }
        return out
    }

    /// slot に emoteID を装備。別枠に同じものがあればそこは入れ替える。
    static func assigning(_ emoteID: String, slot: Int, in current: [String]) -> [String] {
        var s = normalized(current)
        guard (0..<count).contains(slot) else { return s }
        if let other = s.firstIndex(of: emoteID), other != slot {
            s[other] = s[slot]
        }
        s[slot] = emoteID
        return s
    }

    static func clearing(slot: Int, in current: [String]) -> [String] {
        var s = normalized(current)
        guard (0..<count).contains(slot) else { return s }
        s[slot] = ""
        return s
    }

    /// 所持していない ID を空き枠にする。
    static func pruned(_ ids: [String], owned: [String]) -> [String] {
        normalized(ids).map { owned.contains($0) ? $0 : "" }
    }
}
