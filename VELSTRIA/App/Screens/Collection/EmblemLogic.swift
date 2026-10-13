import SwiftUI
import VelstriaCore

// 担当: ui-collection。エンブレム（MLBB のエンブレム画面。旧 UI043 ルーンの置き換え）の表示と保存のロジック。
// データは VelstriaCore の EmblemCatalog（7 セット・天賦 8 / 8 / 10）。docs/EMBLEMS.md。
// 保存: Profile.emblemTalents（セットごとの天賦）・emblemSetProgress（解放・レベル）・heroEmblems（ヒーローごと）。
// 解放・強化・欠片・宝箱の操作は EmblemService（Services/EmblemService.swift）。

/// 一括設定のロール絞り込み（MLBB の一括設定のタブ: 全て / タンク / ファイター / アサシン / ハンター / メイジ。サポートを足す）。
enum EmblemHeroFilter: String, CaseIterable, Identifiable {
    case all, tank, fighter, assassin, marksman, mage, support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L("全て", "All")
        case .tank: return L("タンク", "Tank")
        case .fighter: return L("ファイター", "Fighter")
        case .assassin: return L("アサシン", "Assassin")
        case .marksman: return L("ハンター", "Marksman")
        case .mage: return L("メイジ", "Mage")
        case .support: return L("サポート", "Support")
        }
    }

    /// 対象のロール（全ては nil）。MLBB のロール: タンク = ヴァンガード、ファイター = デュエリスト、ハンター = レンジャー、メイジ = アルカニスト。
    var role: Role? {
        switch self {
        case .all: return nil
        case .tank: return .vanguard
        case .fighter: return .duelist
        case .assassin: return .assassin
        case .marksman: return .ranger
        case .mage: return .arcanist
        case .support: return .support
        }
    }

    func matches(_ hero: HeroDef) -> Bool { role.map { $0 == hero.role } ?? true }
}

enum EmblemMath {
    // MARK: 解放・レベル（EmblemService）

    /// セットの解放とレベル（保存が無ければ新規は通常共通だけ解放済みの Lv1、旧版から引き継いだプレイヤーは解放済みの Lv60）。
    static func progress(_ set: EmblemSetID, profile: Profile) -> EmblemSetProgress {
        EmblemService.progress(set, profile: profile)
    }

    static func isUnlocked(_ set: EmblemSetID, profile: Profile) -> Bool { progress(set, profile: profile).unlocked }

    static func level(_ set: EmblemSetID, profile: Profile) -> Int { progress(set, profile: profile).level }

    static func isMaxLevel(_ set: EmblemSetID, profile: Profile) -> Bool {
        level(set, profile: profile) >= EmblemCatalog.maxLevel
    }

    /// 段 tier の天賦を、このセットのレベルで付けられるか（1 段目 Lv10・2 段目 Lv15・コア Lv20。仮）。
    static func isTierUnlocked(_ tier: EmblemTier, set: EmblemSetID, profile: Profile) -> Bool {
        EmblemService.isTierUnlocked(tier, set: set, profile: profile)
    }

    // MARK: セットごとの天賦

    /// セットに付けている天賦（保存が無ければセットの既定）。レベルはプレイヤーのセットのレベル。
    static func page(_ set: EmblemSetID, profile: Profile) -> EmblemLoadout {
        var e = profile.emblemTalents[set.rawValue] ?? EmblemCatalog.defaultLoadout(set: set)
        if e.set != set || !e.isValid {
            e = EmblemCatalog.defaultLoadout(set: set)
        }
        e.level = level(set, profile: profile)
        return e
    }

    /// セットの天賦を付け替える（同じ段の枠へ入る。費用は無い）。解放していないセット・解放レベル未満の段は変えない。
    static func equip(_ talent: EmblemTalentID, set: EmblemSetID, profile: inout Profile) {
        guard isUnlocked(set, profile: profile), isTierUnlocked(talent.tier, set: set, profile: profile) else { return }
        var e = page(set, profile: profile).replacing(talent)
        e.level = EmblemCatalog.maxLevel
        profile.emblemTalents[set.rawValue] = e
    }

    /// エンブレム画面で開いているセット（保存値が壊れていれば通常共通）。
    static func selectedSet(_ profile: Profile) -> EmblemSetID {
        EmblemSetID(rawValue: profile.selectedEmblemSet) ?? .common
    }

    // MARK: ヒーローごと

    /// ヒーローに一括設定で付けたエンブレム（無ければ nil）。セットを解放していなければ無いものとする。
    static func custom(for heroID: String, profile: Profile) -> EmblemLoadout? {
        guard var e = profile.heroEmblems[heroID], isUnlocked(e.set, profile: profile) else { return nil }
        e.level = level(e.set, profile: profile)
        return e.isValid ? e : nil
    }

    /// 試合で使うエンブレム: 一括設定で付けたもの、無ければ選んだバトルプラン（未設定は「有効」）のエンブレム、
    /// プランの無いヒーローはロール別の既定。レベルはプレイヤーのセットのレベル。セットを解放していなければ通常共通。
    static func loadout(for heroID: String, profile: Profile, master: MasterData) -> EmblemLoadout? {
        if let e = custom(for: heroID, profile: profile) { return e }
        guard let def = master.hero(heroID) else { return nil }
        var e = EmblemCatalog.loadout(heroID: heroID, role: def.role, plan: profile.heroBuildPlans[heroID], master: master)
        if !isUnlocked(e.set, profile: profile) { return page(.common, profile: profile) }
        e.level = level(e.set, profile: profile)
        return e
    }

    /// 一括設定: セットの今の天賦を heroIDs に付ける。付けたヒーローの数を返す（解放していないセットは 0）。
    @discardableResult
    static func apply(set: EmblemSetID, to heroIDs: [String], profile: inout Profile) -> Int {
        guard isUnlocked(set, profile: profile) else { return 0 }
        var e = page(set, profile: profile)
        e.level = EmblemCatalog.maxLevel
        var n = 0
        for id in heroIDs where !id.isEmpty {
            profile.heroEmblems[id] = e
            n += 1
        }
        return n
    }

    /// ヒーローの一括設定を外す（バトルプランのエンブレムに戻る）。
    static func clearCustom(heroID: String, profile: inout Profile) {
        profile.heroEmblems[heroID] = nil
    }

    /// 一括設定の候補（持っているヒーロー、名簿の並び）。
    static func bulkCandidates(filter: EmblemHeroFilter, profile: Profile, master: MasterData) -> [HeroDef] {
        master.heroes.filter { profile.ownedHeroIDs.contains($0.heroID) && filter.matches($0) }
    }

    /// 一括設定のタブ（全て + 候補のいるロール。今の名簿にタンク（ヴァンガード）はいないので出さない）。
    static func bulkFilters(profile: Profile, master: MasterData) -> [EmblemHeroFilter] {
        EmblemHeroFilter.allCases.filter { $0 == .all || !bulkCandidates(filter: $0, profile: profile, master: master).isEmpty }
    }

    /// 一括設定を開いた時に選んでおくヒーロー（このセットと天賦がそのまま付いているヒーロー）。
    static func heroesUsing(_ e: EmblemLoadout, profile: Profile) -> Set<String> {
        var out = Set<String>()
        for (id, h) in profile.heroEmblems where h.set == e.set && h.tier1 == e.tier1 && h.tier2 == e.tier2 && h.core == e.core {
            out.insert(id)
        }
        return out
    }

    // MARK: 表示

    static func setName(_ set: EmblemSetID) -> String {
        let d = EmblemCatalog.set(set)
        return L(d.nameJa, d.nameEn)
    }

    /// セットの短い名前（報酬の「タンクの欠片」。画面のセット名の括弧の中）。
    static func shortSetName(_ set: EmblemSetID) -> String {
        switch set {
        case .common: return L("通常共通", "Common")
        case .tank: return L("タンク", "Tank")
        case .assassin: return L("アサシン", "Assassin")
        case .mage: return L("メイジ", "Mage")
        case .fighter: return L("ファイター", "Fighter")
        case .support: return L("サポート", "Support")
        case .marksman: return L("ハンター", "Marksman")
        }
    }

    static func talentName(_ t: EmblemTalentID) -> String {
        let d = EmblemCatalog.talent(t)
        return L(d.nameJa, d.nameEn)
    }

    static func talentSubtitle(_ t: EmblemTalentID) -> String? {
        let d = EmblemCatalog.talent(t)
        guard let ja = d.subtitleJa else { return nil }
        return L(ja, d.subtitleEn ?? ja)
    }

    static func talentDescription(_ t: EmblemTalentID) -> String {
        let d = EmblemCatalog.talent(t)
        return L(d.descriptionJa, d.descriptionEn)
    }

    static func attributeName(_ k: EmblemAttributeKind) -> String { L(k.nameJa, k.nameEn) }

    /// 能力値の用語説明（日本語クライアントの文。無い能力値は nil）。
    static func attributeGlossary(_ k: EmblemAttributeKind) -> String? {
        guard let ja = k.glossaryJa else { return nil }
        return L(ja, k.glossaryEn ?? ja)
    }

    /// 「+12.00」「+3.00%」（画面と同じく小数 2 桁）。
    static func valueText(_ v: Double, percent: Bool) -> String {
        "+" + String(format: "%.2f", v) + (percent ? "%" : "")
    }

    /// セットの能力値の表示（level の値）。
    static func attributeValue(_ a: EmblemAttribute, level: Int) -> String {
        valueText(a.value(level: level), percent: a.kind.isPercent)
    }

    /// 🔍「エンブレムステータス：現在/最大レベル」の行（「+140.00 / 500.00」）。
    static func currentMaxText(_ a: EmblemAttribute, level: Int) -> String {
        let suffix = a.kind.isPercent ? "%" : ""
        return attributeValue(a, level: level) + " / " + String(format: "%.2f", a.maxValue) + suffix
    }

    /// 天賦の段の呼び名（画面: 通常天賦 / コア天賦）。
    static func tierLabel(_ tier: EmblemTier) -> String {
        tier == .core ? L("コア天賦", "Core Talent") : L("通常天賦", "Standard Talent")
    }

    // MARK: 強化・解放の表示

    /// 段 tier の解放の文（「Lv10で解放」）。
    static func tierLockText(_ tier: EmblemTier) -> String {
        let lv = EmblemProgression.unlockLevel(tier)
        return L("Lv\(lv)で解放", "Unlocks at Lv\(lv)")
    }

    /// コア属性の呼び名（画面の「コア属性大幅アップ 最大HP」。HP は「最大HP」と出る）。
    static func coreAttributeName(_ k: EmblemAttributeKind) -> String {
        k == .hp ? L("最大HP", "Max HP") : attributeName(k)
    }

    /// 次のキーレベルの行（「Lv30 コア属性大幅アップ 適応貫通」。最大なら nil）。
    static func nextKeyLevelText(_ set: EmblemSetID, level: Int) -> String? {
        guard let key = EmblemProgression.nextKeyLevel(after: level) else { return nil }
        let def = EmblemCatalog.set(set)
        guard let core = def.attributes.first(where: \.isCore) ?? def.attributes.first else { return nil }
        let name = coreAttributeName(core.kind)
        return L("Lv\(key) コア属性大幅アップ \(name)", "Lv\(key): Core stat boost — \(name)")
    }

    /// 強化の費用の行（画面の「10+217/227」= 使う欠片 + 使うマジックダスト / 必要な量。通常共通は欠片が無いので「217/227」）。
    static func costText(_ q: EmblemUpgradeQuote, set: EmblemSetID) -> String {
        set == .common ? "\(q.fromDust)/\(q.needed)" : "\(q.fromFragments)+\(q.fromDust)/\(q.needed)"
    }

    /// 次のレベルで変わる能力値の値（「+1.30%」。変わらない・最大なら nil）。ステータス欄の「+1.20% → +1.30%」。
    static func nextValueText(_ a: EmblemAttribute, level: Int) -> String? {
        guard level < EmblemCatalog.maxLevel else { return nil }
        let next = a.value(level: level + 1)
        guard next != a.value(level: level) else { return nil }
        return valueText(next, percent: a.kind.isPercent)
    }

    /// マジックダストの量の表示（「1,234」）。
    static func amountText(_ n: Int) -> String { n.formatted() }

    /// 1 行の要約（「通常共通エンブレム · 衝撃 / 山野の主 / 不純な怒り」）。
    static func summary(_ e: EmblemLoadout) -> String {
        setName(e.set) + " · " + e.talents.map { talentName($0) }.joined(separator: " / ")
    }
}

/// エンブレムの色と記号（SF Symbols。MLBB の絵は使わない）。色は MLBB のタブの色。
enum EmblemStyle {
    static func color(_ set: EmblemSetID) -> Color {
        switch set {
        case .common: return Color(red: 0.56, green: 0.68, blue: 0.82)    // 灰青
        case .tank: return Color(red: 0.96, green: 0.56, blue: 0.30)      // 橙
        case .assassin: return Color(red: 0.78, green: 0.50, blue: 0.92)  // 紫
        case .mage: return Color(red: 0.38, green: 0.70, blue: 0.96)      // 青
        case .fighter: return Color(red: 0.98, green: 0.38, blue: 0.42)   // 赤
        case .support: return Color(red: 0.40, green: 0.80, blue: 0.52)   // 緑
        case .marksman: return Color(red: 0.88, green: 0.74, blue: 0.40)  // 金
        }
    }

    /// セットのタブの記号（盾と剣・橙の盾・手裏剣・杖・剣・十字・弓）。
    static func setSymbol(_ set: EmblemSetID) -> String {
        switch set {
        case .common: return "shield.fill"
        case .tank: return "shield.checkered"
        case .assassin: return "staroflife.fill"
        case .mage: return "wand.and.stars"
        case .fighter: return "figure.fencing"
        case .support: return "cross.fill"
        case .marksman: return "scope"
        }
    }

    /// 天賦の記号（ピッカーのアイコンに似たもの）。
    static func talentSymbol(_ t: EmblemTalentID) -> String {
        switch t {
        case .thrill: return "xmark"                         // 交差した刃
        case .swift: return "wind"                           // 爪痕
        case .vitality: return "heart.fill"                  // ハート
        case .rupture: return "arrow.up.right.circle.fill"   // 矢の付いた円
        case .inspire: return "arrow.triangle.2.circlepath"  // 回る矢
        case .firmness: return "shield.lefthalf.filled"      // 二重の菱形
        case .agility: return "shoeprints.fill"              // 靴
        case .fatal: return "burst.fill"                     // 手裏剣
        case .wildernessBlessing: return "water.waves"       // 水を踏む靴
        case .seasonedHunter: return "pawprint.fill"         // 角の兜
        case .tenacity: return "shield.fill"                 // H の盾
        case .masterAssassin: return "scope"                 // 照準
        case .bargainHunter: return "ticket.fill"            // $ の券
        case .festivalOfBlood: return "drop.fill"            // 血の滴
        case .pullYourselfTogether: return "hourglass"       // 砂時計
        case .weaponMaster: return "arrow.up.circle.fill"    // 金の盾と上向きの矢印
        case .impureRage: return "flame.fill"                // 炎
        case .quantumCharge: return "bolt.fill"              // 門
        case .warCry: return "megaphone.fill"                // 角
        case .temporalReign: return "clock.arrow.circlepath" // 立方体の時計
        case .concussiveBlast: return "dot.radiowaves.left.and.right" // 橙の衝撃
        case .killingSpree: return "tornado"                 // 紫の渦
        case .lethalIgnition: return "flame.circle.fill"     // 青い斧
        case .braveSmite: return "cross.circle.fill"         // 赤い剣
        case .focusingMark: return "target"                  // 緑の矢
        case .weaknessFinder: return "tortoise.fill"         // 金の紋章
        }
    }

    /// ステータス欄の能力値の記号。
    static func attributeSymbol(_ k: EmblemAttributeKind) -> String {
        switch k {
        case .hybridRegen: return "arrow.clockwise.heart.fill"
        case .hp: return "heart.fill"
        case .adaptiveAttack: return "bolt.fill"
        case .hybridDefense: return "shield.lefthalf.filled"
        case .hpRegen: return "cross.case.fill"
        case .adaptivePenetration, .adaptivePenetrationPct: return "arrow.up.right.circle.fill"
        case .movementSpeedPct: return "shoeprints.fill"
        case .magicPower: return "sparkles"
        case .cooldownReductionPct: return "hourglass"
        case .magicPenetration: return "sparkle"
        case .hybridLifestealPct: return "drop.fill"
        case .healingEffectPct: return "plus.circle.fill"
        case .attackSpeedPct: return "speedometer"
        }
    }

    /// 天賦の色（コアはセットの色に依らず金、通常天賦は白に近い青）。
    static func talentColor(_ t: EmblemTalentID) -> Color {
        t.tier == .core ? Theme.gold : Color(red: 0.70, green: 0.84, blue: 1.0)
    }

    /// マジックダストの記号と色（紫の粒）。
    static let dustSymbol = "sparkles"
    static let dustColor = Color(red: 0.78, green: 0.62, blue: 1.0)
    /// 無料のエンブレム宝箱の記号。
    static let chestSymbol = "gift.fill"
    /// 「コア属性大幅アップ」の橙（ピッカーの小見出しと同じ）。
    static let keyLevelColor = Color(red: 1.0, green: 0.68, blue: 0.30)
}
