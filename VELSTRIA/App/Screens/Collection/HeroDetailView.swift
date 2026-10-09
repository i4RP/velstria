import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI038 ヒーロー詳細（ショーケース + 概要/能力値/スキル/スキン/ビルド）。

enum HeroDetailTab: String, CaseIterable, Identifiable {
    case overview, stats, skills, skins, build
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("概要", "Overview")
        case .stats: return L("能力値", "Stats")
        case .skills: return L("スキル", "Skills")
        case .skins: return L("スキン", "Skins")
        case .build: return L("ビルド", "Build")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "book.fill"
        case .stats: return "chart.bar.fill"
        case .skills: return "wand.and.stars"
        case .skins: return "paintpalette.fill"
        case .build: return "shippingbox.fill"
        }
    }
}

struct HeroDetailView: View {
    let heroID: String
    @Environment(AppModel.self) private var app
    // 出荷ビルドでは DebugLaunch.args が空なので常に .overview。-heroTab <skills 等> はストア用スクリーンショットの撮影用。
    @State private var tab: HeroDetailTab = DebugLaunch.value(after: "-heroTab").flatMap(HeroDetailTab.init(rawValue:)) ?? .overview
    @State private var pendingSKU: String?

    var body: some View {
        if let hero = app.master.hero(heroID) {
            ScreenScaffold(title: L("ヒーロー詳細", "Hero Details")) {
                HStack(alignment: .top, spacing: 14) {
                    HeroShowcasePanel(hero: hero, pendingSKU: $pendingSKU)
                        .frame(width: 236)
                    VStack(spacing: 6) {
                        tabBar
                        ScrollView {
                            tabContent(hero)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 12)
                                .id(tab)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
            }
            .storePurchaseFlow(sku: $pendingSKU)
        } else {
            ScreenScaffold(title: L("ヒーロー詳細", "Hero Details")) {
                CollectionEmptyState(symbol: "questionmark.circle", title: L("ヒーローが見つかりません", "Hero not found"))
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(HeroDetailTab.allCases) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { tab = t }
                    app.haptics.tap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: t.symbol).font(.system(size: 11, weight: .bold))
                        Text(t.title).font(Theme.body(13)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(tab == t ? Color.black.opacity(0.85) : Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(tab == t ? AnyShapeStyle(LinearGradient(colors: [Theme.gold, Theme.gold.opacity(0.75)],
                                                                          startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(Color.white.opacity(0.06)))
                    )
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
                .accessibilityIdentifier("herodetail_tab_\(t.rawValue)")
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ hero: HeroDef) -> some View {
        switch tab {
        case .overview: HeroOverviewSection(hero: hero)
        case .stats: HeroStatsSection(hero: hero)
        case .skills: HeroSkillsSection(hero: hero)
        case .skins: HeroSkinsSection(hero: hero)
        case .build: HeroBuildSection(hero: hero)
        }
    }
}

// MARK: - ショーケース（左列）

private struct HeroShowcasePanel: View {
    let hero: HeroDef
    @Binding var pendingSKU: String?
    @Environment(AppModel.self) private var app

    /// パネルの高さに合わせたポートレートの大きさ（下の情報・ボタンが収まる範囲で最大化）。
    static func portraitSize(panelHeight h: CGFloat, locked: Bool) -> CGFloat {
        let reserved: CGFloat = locked ? 244 : 190
        return min(108, max(70, (h - reserved) / 1.58))
    }

    var body: some View {
        GeometryReader { geo in
            content(portrait: Self.portraitSize(panelHeight: geo.size.height, locked: !app.owns(heroID: hero.heroID)))
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Theme.roleColor(hero.role).opacity(0.18), Theme.panel],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.roleColor(hero.role).opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func content(portrait: CGFloat) -> some View {
        let owned = app.owns(heroID: hero.heroID)
        let damageType = app.master.skill(hero: hero.heroID, slot: .skill1)?.damageType ?? .physical
        return ScrollView {
            VStack(spacing: 7) {
                // 装備中のスキンで表示する 3D プレビュー（横ドラッグで回転）。高さは従来の 2D 肖像と同じ枠。
                HeroPreview3DView(heroID: hero.heroID, skinID: app.profile.equippedSkins[hero.heroID])
                    .frame(maxWidth: .infinity)
                    .frame(height: portrait * 1.54)
                Text(MasterText.hero(hero))
                    .font(Theme.heading(17))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 8) {
                    CollectionRoleTag(role: hero.role)
                    CollectionDifficultyStars(value: hero.difficulty, size: 10)
                }
                HStack(spacing: 5) {
                    CollectionInfoTag(text: "\(CollectionStyle.resourceName(hero.resource)) \(Int(hero.resourceMax))",
                                      symbol: CollectionStyle.resourceSymbol(hero.resource),
                                      color: CollectionStyle.resourceColor(hero.resource))
                    CollectionInfoTag(text: CollectionStyle.damageTypeName(damageType),
                                      symbol: CollectionStyle.damageTypeSymbol(damageType),
                                      color: CollectionStyle.damageTypeColor(damageType))
                    CollectionInfoTag(text: hero.isRanged ? L("遠隔", "Ranged") : L("近接", "Melee"),
                                      symbol: hero.isRanged ? "scope" : "figure.fencing", color: Theme.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                if owned {
                    Label(L("所持済み", "Owned"), systemImage: "checkmark.seal.fill")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.success)
                } else if let item = StoreCatalog.unlockItem(heroID: hero.heroID, master: app.master) {
                    Button {
                        app.haptics.tap()
                        pendingSKU = item.sku
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.open.fill")
                            Text(L("解放", "Unlock"))
                            Image(systemName: CollectionStyle.currencySymbol(item.currency))
                                .font(.system(size: 12, weight: .bold))
                            Text(EconomyService.price(of: item).formatted())
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("herodetail_unlock")
                }
                Button {
                    startPractice()
                } label: {
                    Label(L("練習場で試す", "Try in Practice"), systemImage: "figure.fencing")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .accessibilityIdentifier("herodetail_practice")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func startPractice() {
        app.haptics.impact()
        let name = app.profile.displayName.isEmpty ? "Player" : app.profile.displayName
        let config = MatchFactory.practiceMatch(humanHeroID: hero.heroID, humanName: name, options: PracticeOptions(),
                                                seed: UInt64.random(in: 1...UInt64.max))
        app.startBattle(BattleLaunch(config: config))
    }
}

// MARK: - 概要

private struct HeroOverviewSection: View {
    let hero: HeroDef

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Panel(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    CollectionSectionTitle(title: L("ストーリー", "Lore"), symbol: "quote.opening")
                    Text(MasterText.name(id: "\(hero.heroID).lore", ja: hero.lore))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            traitRow(title: L("強み", "Strengths"), symbol: "hand.thumbsup.fill", color: Theme.success,
                     text: MasterText.name(id: "\(hero.heroID).strengths", ja: hero.strengths))
            traitRow(title: L("弱み", "Weaknesses"), symbol: "exclamationmark.triangle.fill", color: Theme.danger,
                     text: MasterText.name(id: "\(hero.heroID).weaknesses", ja: hero.weaknesses))
            traitRow(title: L("対策", "Counterplay"), symbol: "lightbulb.fill", color: Theme.cyan,
                     text: MasterText.name(id: "\(hero.heroID).counterplay", ja: hero.counterplay))
        }
    }

    private func traitRow(title: String, symbol: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.heading(13)).foregroundStyle(color)
                Text(text)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 能力値

private struct HeroStatsSection: View {
    let hero: HeroDef
    @Environment(AppModel.self) private var app

    var body: some View {
        let lv1 = HeroGrowth.baseStats(def: hero, level: 1)
        let lvMax = HeroGrowth.baseStats(def: hero, level: Balance.maxLevel)
        let color = Theme.roleColor(hero.role)
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                CollectionSectionTitle(title: L("基本能力値", "Base Stats"), symbol: "chart.bar.fill",
                                       trailing: "Lv1 → Lv\(Balance.maxLevel)")
                ForEach(HeroStatKind.allCases) { kind in
                    let growth = kind.growth(hero).map { "+\(CollectionStyle.number($0, digits: kind.digits == 0 ? 2 : 3))/Lv" }
                    CollectionStatBar(label: kind.label, symbol: kind.symbol,
                                   lv1: kind.value(lv1), lvMax: kind.value(lvMax),
                                   maxValue: HeroStatMath.maxValue(kind, master: app.master),
                                   growth: growth, color: color, digits: kind.digits)
                }
                HStack(spacing: 12) {
                    legend(color: color, text: "Lv1")
                    legend(color: color.opacity(0.35), text: "Lv\(Balance.maxLevel)")
                    Spacer()
                    Text(L("装備・ルーン補正を除く", "Excludes items and runes"))
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 16, height: 6)
            Text(text).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - スキル

private struct HeroSkillsSection: View {
    let hero: HeroDef
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 7) {
            ForEach(app.master.skills(forHero: hero.heroID)) { skill in
                CollectionSkillCard(skill: skill, hero: hero)
            }
        }
    }
}

/// スキルカード（枠・名前・CD・コスト・CC）。
struct CollectionSkillCard: View {
    let skill: SkillDef
    let hero: HeroDef
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.haptics.tap()
            app.router.push(.skillDetail(skill.skillID))
        } label: {
            HStack(spacing: 10) {
                CollectionSkillSlotBadge(slot: skill.slot, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(MasterText.skill(skill))
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(CollectionStyle.slotName(skill.slot))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 4)
                if skill.slot != .passive {
                    metric(symbol: "timer", text: CollectionStyle.seconds(SkillMath.cooldown(skill, hero: hero, rank: 1)))
                    metric(symbol: CollectionStyle.resourceSymbol(hero.resource),
                           text: CollectionStyle.number(SkillMath.cost(skill, resource: hero.resource), digits: 0),
                           color: CollectionStyle.resourceColor(hero.resource))
                    // キットのスキルはキットの CC（マスターの汎用値ではなく numbers の cc）
                    let cc = HeroKits.hasKit(hero.heroID) ? SkillMath.numbers(skill, hero: hero, rank: 1).cc : skill.cc
                    if cc != .none {
                        CollectionInfoTag(text: CollectionStyle.ccName(cc), symbol: CollectionStyle.ccSymbol(cc),
                                          color: CollectionStyle.ccColor(cc))
                    }
                } else {
                    CollectionInfoTag(text: L("常時", "Always on"), symbol: "infinity", color: Theme.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [CollectionStyle.slotColor(skill.slot).opacity(0.12), Color.white.opacity(0.04)],
                                         startPoint: .leading, endPoint: .trailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityIdentifier("skill_\(skill.skillID)")
    }

    private func metric(symbol: String, text: String, color: Color = Theme.textSecondary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Text(text).font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
        }
        .fixedSize()
    }
}

// MARK: - スキン

private struct HeroSkinsSection: View {
    let hero: HeroDef
    @Environment(AppModel.self) private var app

    private let columns = [GridItem(.adaptive(minimum: 118, maximum: 150), spacing: 10)]

    var body: some View {
        let skins = CosmeticInfo.skins(heroID: hero.heroID, master: app.master)
        let equipped = app.profile.equippedSkins[hero.heroID]
        VStack(alignment: .leading, spacing: 8) {
            CollectionSectionTitle(title: L("スキン", "Skins"), symbol: "paintpalette.fill",
                                   trailing: L("\(skins.count + 1) 種", "\(skins.count + 1) total"))
            LazyVGrid(columns: columns, spacing: 10) {
                defaultSkinCard(equipped: equipped == nil)
                ForEach(skins) { skin in
                    skinCard(skin, equipped: equipped == skin.cosmeticID)
                }
            }
            if skins.isEmpty {
                // 未発表の有料コンテンツを予告しない（審査ガイドライン 2.1 / 2.3）
                Text(L("このヒーローはデフォルトスキンのみです。", "This hero has the default skin only."))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func defaultSkinCard(equipped: Bool) -> some View {
        Button {
            var p = app.profile
            CosmeticInfo.unequip(.heroSkin, heroID: hero.heroID, profile: &p)
            app.profile = p
            app.haptics.tap()
        } label: {
            skinCardBody(preview: AnyView(HeroPortraitView(heroID: hero.heroID, size: 78)),
                         name: L("デフォルト", "Default"), rarity: nil, status: equipped ? .equipped : .owned)
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityIdentifier("herodetail_skin_default")
    }

    private func skinCard(_ skin: CosmeticDef, equipped: Bool) -> some View {
        let owned = app.owns(cosmeticID: skin.cosmeticID)
        let item = StoreCatalog.storeItem(forCosmetic: skin.cosmeticID, master: app.master)
        let status: SkinCardStatus = equipped ? .equipped : (owned ? .owned : .forSale(item))
        return Button {
            app.haptics.tap()
            if let item { app.router.push(.productDetail(item.sku)) }
        } label: {
            skinCardBody(preview: AnyView(CosmeticPreviewView(cosmetic: skin, size: 78, animated: false)),
                         name: MasterText.cosmetic(skin), rarity: skin.rarity, status: status)
        }
        .buttonStyle(CollectionPressStyle())
        .disabled(item == nil)
        .accessibilityIdentifier("herodetail_skin_\(skin.cosmeticID)")
    }

    private enum SkinCardStatus {
        case equipped, owned
        case forSale(StoreItemDef?)
    }

    private func skinCardBody(preview: AnyView, name: String, rarity: Rarity?, status: SkinCardStatus) -> some View {
        VStack(spacing: 5) {
            preview.padding(.top, 6)
            Text(name)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28)
            if let rarity { CollectionRarityTag(rarity: rarity) } else { CollectionInfoTag(text: L("標準", "Base"), color: Theme.textSecondary) }
            Group {
                switch status {
                case .equipped:
                    Label(L("装備中", "Equipped"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                case .owned:
                    Label(L("所持", "Owned"), systemImage: "checkmark").foregroundStyle(Theme.textSecondary)
                case .forSale(let item):
                    if let item {
                        PriceTag(currency: item.currency, amount: EconomyService.price(of: item), size: 12)
                    } else {
                        Text(L("未販売", "Not for sale")).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .font(Theme.body(11))
            .frame(height: 18)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isEquipped(status) ? Theme.success.opacity(0.7) : Theme.panelStroke, lineWidth: isEquipped(status) ? 1.5 : 1)
        )
    }

    private func isEquipped(_ s: SkinCardStatus) -> Bool {
        if case .equipped = s { return true }
        return false
    }
}

// MARK: - ビルド

private struct HeroBuildSection: View {
    let hero: HeroDef
    @Environment(AppModel.self) private var app

    var body: some View {
        let isCustom = BuildRules.custom(for: hero.heroID, profile: app.profile, master: app.master) != nil
        let build = BuildRules.current(for: hero.heroID, profile: app.profile, master: app.master)
        let recommended = BuildRules.recommended(for: hero.heroID, master: app.master)
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                CollectionSectionTitle(title: isCustom ? L("カスタムビルド", "Custom Build") : L("おすすめビルド", "Recommended Build"),
                                       symbol: isCustom ? "person.fill" : "star.fill",
                                       trailing: build.isEmpty ? nil : totalLabel(build))
                if build.isEmpty {
                    CollectionEmptyState(symbol: "shippingbox",
                                         title: L("ビルドが未設定です", "No build yet"),
                                         message: L("ビルド編集で購入順を決めておくと、戦闘中のおすすめ購入に反映されます。",
                                                    "Set up a purchase order in the build editor to use it as in-match recommendations."))
                } else {
                    buildRow(build, iconSize: 50)
                }
                // カスタム使用中でも、ロール別のおすすめを参考として並べる
                if isCustom && !recommended.isEmpty && recommended != build {
                    CollectionSectionTitle(title: L("おすすめビルド（\(MasterText.role(hero.role))）", "Recommended (\(MasterText.role(hero.role)))"),
                                           symbol: "star.fill", trailing: totalLabel(recommended))
                    buildRow(recommended, iconSize: 40)
                }
                Button {
                    app.haptics.tap()
                    app.router.push(.buildEditor(hero.heroID))
                } label: {
                    Label(L("ビルド編集", "Edit Build"), systemImage: "square.and.pencil")
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(minHeight: 44)
                .accessibilityIdentifier("herodetail_build_edit")
            }
        }
    }

    private func totalLabel(_ build: [String]) -> String {
        L("合計", "Total") + " \(Int(BuildRules.totalCost(build, master: app.master)).formatted())G"
    }

    private func buildRow(_ build: [String], iconSize: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(build.enumerated()), id: \.offset) { i, id in
                    if let item = app.master.item(id) {
                        buildStep(index: i, item: item, iconSize: iconSize)
                    }
                }
            }
            // 番号バッジのはみ出し分
            .padding(.top, 4)
            .padding(.leading, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func buildStep(index: Int, item: ItemDef, iconSize: CGFloat) -> some View {
        Button {
            app.haptics.tap()
            app.router.push(.itemDetail(item.itemID))
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    ItemIconView(item: item, size: iconSize)
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Theme.gold))
                        .offset(x: -4, y: -4)
                }
                Text(MasterText.item(item))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 66, height: 26)
                GoldPriceLabel(amount: item.priceGold, size: 10)
            }
            .frame(minWidth: 66, minHeight: 44)
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel("\(index + 1). \(MasterText.item(item))")
        .accessibilityIdentifier("herodetail_build_\(index)_\(item.itemID)")
    }
}
