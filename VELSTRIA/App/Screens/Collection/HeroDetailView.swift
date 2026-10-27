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
        case .build: return L("戦闘準備", "Preparation")
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
    @State private var showsDetails = DebugLaunch.value(after: "-heroTab") != nil
    @State private var pendingSKU: String?
    @State private var showsBattleSkills = false
    /// スキルタブで開いているスキル（nil = スキル 1）。
    @State private var selectedSkillID: String?
    @State private var skillPreview: HeroSkillPreviewRequest?

    var body: some View {
        if let hero = app.master.hero(heroID) {
            let skills = app.master.skills(forHero: hero.heroID)
            let current = HeroSkillSelection.resolved(selectedID: selectedSkillID, skills: skills)
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.4)],
                                   startPoint: .leading, endPoint: .trailing).ignoresSafeArea()
                    VStack(spacing: 0) {
                        showcaseHeader
                        HStack(spacing: 0) {
                            showcaseInfo(hero, skills: skills)
                                .frame(width: geometry.size.width * 0.28)
                            HeroPreview3DView(heroID: hero.heroID, skinID: app.profile.equippedSkins[hero.heroID],
                                              allowsSkillPreview: true, skillPreview: skillPreview,
                                              isActive: !showsDetails)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay(alignment: .bottom) {
                                    Text(L("ドラッグして回転", "Drag to rotate"))
                                        .font(Theme.body(10)).foregroundStyle(.white.opacity(0.65))
                                        .padding(.bottom, 8).allowsHitTesting(false)
                                }
                            skinRail(hero, height: geometry.size.height)
                                .frame(width: geometry.size.width * 0.23)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                }
            }
            .background {
                GeometryReader { background in
                    Image("HomeBackdrop").resizable().scaledToFill()
                        .frame(width: background.size.width, height: background.size.height).clipped()
                }.ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsDetails) {
                VStack(spacing: 8) {
                    HStack {
                        Text(MasterText.hero(hero)).font(Theme.heading(18))
                        Spacer()
                        Button(L("閉じる", "Close")) { showsDetails = false }
                    }
                    tabBar
                    if tab == .skills, let skill = current {
                        SkillShowcasePanel(skill: skill, hero: hero).id(skill.skillID)
                        HStack {
                            ForEach(skills) { skill in
                                SkillIconButton(skill: skill, hero: hero, isSelected: current?.skillID == skill.skillID,
                                                identifier: "detail_skill_" + skill.skillID) {
                                    selectedSkillID = skill.skillID
                                }
                            }
                        }
                    } else {
                        ScrollView { tabContent(hero) }
                    }
                }
                .padding(16)
                .background(Theme.panel)
                .foregroundStyle(Theme.textPrimary)
                .sheet(isPresented: $showsBattleSkills) {
                    VStack(spacing: 10) {
                        HStack {
                            Text(L("バトルスキル", "Battle Skills")).font(Theme.heading(20))
                            Spacer()
                            Button(L("閉じる", "Close")) { showsBattleSkills = false }
                        }
                        BattleSkillPicker(current: SpellLoadoutRules.effective(heroID: heroID, profile: app.profile)[0]) { id in
                            app.profile.heroSpells[heroID] = [id, SpellLoadoutRules.fixedSpellID]
                            showsBattleSkills = false
                        }
                    }.padding(16).background(Theme.panel).foregroundStyle(Theme.textPrimary)
                }
            }
            .storePurchaseFlow(sku: $pendingSKU)
            .onChange(of: app.router.path.count) { _, _ in showsDetails = false }

        } else {
            ScreenScaffold(title: L("ヒーロー詳細", "Hero Details")) {
                EmptyStateView(symbol: "questionmark.circle", title: L("ヒーローが見つかりません", "Hero not found"))
            }
        }
    }

    private var showcaseHeader: some View {
        HStack {
            Button { app.router.pop() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.cyan)
                    .shadow(color: Theme.cyan.opacity(0.7), radius: 6)
                    .frame(width: 60, height: 44)
            }
            .accessibilityLabel(L("戻る", "Back"))
            .accessibilityIdentifier("nav_back")
            Spacer()
            CurrencyBadge(kind: .coin, amount: app.profile.starlightCoin)
            CurrencyBadge(kind: .gem, amount: app.profile.totalGem)
        }
        .padding(.horizontal, 20).padding(.top, 4)
    }

    private func openDetails(_ selection: HeroDetailTab) {
        tab = selection
        showsDetails = true
        app.haptics.tap()
    }

    private func showcaseInfo(_ hero: HeroDef, skills: [SkillDef]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Label(MasterText.hero(hero), systemImage: Theme.roleSymbol(hero.role))
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Rectangle().fill(Theme.cyan.opacity(0.4)).frame(height: 1)
                Text(MasterText.role(hero.role)).font(Theme.body(14))
                Text(SkillTags.featureTags(hero: hero, master: app.master).map { SkillTags.name(for: $0) }.joined(separator: " / "))
                    .font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                if !app.owns(heroID: hero.heroID), let item = StoreCatalog.unlockItem(heroID: hero.heroID, master: app.master) {
                    Button { pendingSKU = item.sku } label: {
                        HStack {
                            Text(L("解放", "Unlock"))
                            PriceTag(currency: item.currency, amount: EconomyService.price(of: item), size: 12)
                        }
                    }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("herodetail_unlock")
                }
                HeroRatingBars(ratings: HeroRatingMath.ratings(for: hero, master: app.master))
                    .frame(maxWidth: 210)
                Button {
                    let name = app.profile.displayName.isEmpty ? "Player" : app.profile.displayName
                    let config = MatchFactory.practiceMatch(humanHeroID: hero.heroID, humanName: name,
                                                            options: PracticeOptions(infiniteGold: true), seed: UInt64.random(in: 1...UInt64.max))
                    app.startBattle(BattleLaunch(config: config))
                } label: {
                    Label(L("練習場で試す", "Try in Practice"), systemImage: "figure.fencing")
                        .font(Theme.body(12)).frame(minHeight: 32)
                }
                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("herodetail_practice")
                HStack(spacing: 2) {
                    ForEach(skills) { skill in
                        SkillIconButton(skill: skill, hero: hero, isSelected: selectedSkillID == skill.skillID,
                                        identifier: "skill_" + skill.skillID) {
                            selectedSkillID = skill.skillID
                            skillPreview = HeroSkillPreviewRequest(skillID: skill.skillID)
                            app.haptics.tap()
                        }.frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 12) {
                    showcaseShortcut(.stats)
                    showcaseShortcut(.build)
                    showcaseShortcut(.overview)
                    showcaseShortcut(.skills)
                }
            }
            .padding(.top, 8).padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Theme.textPrimary)
    }

    private func showcaseShortcut(_ selection: HeroDetailTab) -> some View {
        Button { openDetails(selection) } label: {
            VStack(spacing: 3) {
                Image(systemName: selection == .skills ? "info.circle" : selection.symbol)
                    .font(.system(size: 17)).frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Theme.cyan.opacity(0.35)))
                Text(selection == .overview ? L("伝記", "Lore")
                     : (selection == .skills ? L("スキル説明", "Skill details") : selection.title))
                    .font(Theme.body(10)).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(selection == .skills ? "herodetail_skill_details" : "herodetail_quick_\(selection.rawValue)")
    }

    private func skinRail(_ hero: HeroDef, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("スキン", "Skins"))
                .font(Theme.heading(16)).foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity).padding(.bottom, 8)
                .background(alignment: .bottom) { Rectangle().fill(Theme.cyan.opacity(0.6)).frame(height: 1) }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    showcaseSkinCard(hero: hero, skin: nil, height: height)
                    ForEach(CosmeticInfo.skins(heroID: hero.heroID, master: app.master)) { skin in
                        showcaseSkinCard(hero: hero, skin: skin, height: height)
                    }
                }
                .padding(3)
            }
            .scrollIndicators(.hidden)
            .frame(height: max(150, height * 0.59))
            Spacer(minLength: 0)
        }.padding(.top, 24)
    }

    private func showcaseSkinCard(hero: HeroDef, skin: CosmeticDef?, height: CGFloat) -> some View {
        let equipped = app.profile.equippedSkins[hero.heroID] == skin?.cosmeticID
        let cardHeight = max(140, height * 0.56)
        return Button {
            app.haptics.tap()
            var profile = app.profile
            if let skin {
                if app.owns(cosmeticID: skin.cosmeticID) {
                    if CosmeticInfo.equip(skin, profile: &profile) { app.profile = profile }
                } else if let item = StoreCatalog.storeItem(forCosmetic: skin.cosmeticID, master: app.master) {
                    app.router.push(.productDetail(item.sku))
                }
            } else {
                CosmeticInfo.unequip(.heroSkin, heroID: hero.heroID, profile: &profile)
                app.profile = profile
            }
        } label: {
            ZStack(alignment: .bottom) {
                if let art = skin.flatMap({ PortraitArt.skin($0.cosmeticID) }) ?? PortraitArt.card(hero.heroID) ?? PortraitArt.hero(hero.heroID) {
                    Image(uiImage: art).resizable().scaledToFill()
                        .frame(width: cardHeight * 0.6, height: cardHeight).clipped()
                }
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                VStack(spacing: 4) {
                    Text(skin.map { MasterText.cosmetic($0) } ?? L("デフォルト", "Default"))
                        .font(Theme.body(12)).lineLimit(2)
                    if equipped {
                        Label(L("使用中", "Equipped"), systemImage: "checkmark.circle.fill")
                            .font(Theme.body(10)).foregroundStyle(Theme.cyan)
                    }
                }.foregroundStyle(.white).padding(10)
            }
            .frame(width: cardHeight * 0.6, height: cardHeight)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(equipped ? Theme.cyan : .white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("herodetail_skin_\(skin?.cosmeticID ?? "default")")
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
        case .skills: EmptyView()   // スキルは右パネル（SkillShowcasePanel）に出す
        case .skins: HeroSkinsSection(hero: hero)
        case .build: HeroBuildSection(hero: hero, onChangeBattleSkill: { showsBattleSkills = true })
        }
    }
}

// MARK: - 概要

private struct HeroOverviewSection: View {
    let hero: HeroDef
    @Environment(AppModel.self) private var app

    var body: some View {
        let damageType = app.master.skill(hero: hero.heroID, slot: .skill1)?.damageType ?? .physical
        VStack(alignment: .leading, spacing: 10) {
            // リソース・ダメージの種類・射程・難易度（左パネルからこちらへ移した基本情報）
            HStack(spacing: 5) {
                // 最大値は Lv1（怒り・リソースなしは量を持たないので名前だけ）
                CollectionInfoTag(text: hero.resource.usesPool
                                      ? "\(CollectionStyle.resourceName(hero.resource)) \(Int(hero.resourceMax))"
                                      : CollectionStyle.resourceName(hero.resource),
                                  symbol: CollectionStyle.resourceSymbol(hero.resource),
                                  color: CollectionStyle.resourceColor(hero.resource))
                CollectionInfoTag(text: CollectionStyle.damageTypeName(damageType),
                                  symbol: CollectionStyle.damageTypeSymbol(damageType),
                                  color: CollectionStyle.damageTypeColor(damageType))
                CollectionInfoTag(text: hero.isRanged ? L("遠隔", "Ranged") : L("近接", "Melee"),
                                  symbol: hero.isRanged ? "scope" : "figure.fencing", color: Theme.textSecondary)
                CollectionDifficultyStars(value: hero.difficulty, size: 10)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Panel(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(title: L("ストーリー", "Lore"), symbol: "quote.opening")
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
                SectionTitle(title: L("基本能力値", "Base Stats"), symbol: "chart.bar.fill",
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
                    Text(L("装備・エンブレム補正を除く", "Excludes items and emblems"))
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

// MARK: - スキン

private struct HeroSkinsSection: View {
    let hero: HeroDef
    @Environment(AppModel.self) private var app

    private let columns = [GridItem(.adaptive(minimum: 118, maximum: 150), spacing: 10)]

    var body: some View {
        let skins = CosmeticInfo.skins(heroID: hero.heroID, master: app.master)
        let equipped = app.profile.equippedSkins[hero.heroID]
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: L("スキン", "Skins"), symbol: "paintpalette.fill",
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
    var onChangeBattleSkill: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let build = BuildRules.current(for: hero.heroID, profile: app.profile, master: app.master)
        let skill = SpellLoadoutRules.effective(heroID: hero.heroID, profile: app.profile)[0]
        VStack(alignment: .leading, spacing: 10) {
            Panel(padding: 12) {
                HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("ビルド", "Build")).font(Theme.heading(14))
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                            ForEach(Array(build.enumerated()), id: \.offset) { _, id in
                                if let item = app.master.item(id) { ItemIconView(item: item, size: 30) }
                            }
                        }.frame(height: 52)
                    }.scrollIndicators(.hidden)
                    Button { app.router.push(.buildEditor(hero.heroID)) } label: {
                        Label(L("変更", "Change"), systemImage: "arrow.triangle.2.circlepath")
                    }.labelStyle(.iconOnly).buttonStyle(SecondaryButtonStyle()).accessibilityLabel(L("変更", "Change")).accessibilityIdentifier("herodetail_build_edit")
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("エンブレム", "Emblems")).font(Theme.heading(14))
                    if let emblem = EmblemMath.loadout(for: hero.heroID, profile: app.profile, master: app.master) {
                        VStack(spacing: 3) {
                            Image(systemName: EmblemStyle.setSymbol(emblem.set))
                                .font(.system(size: 28))
                                .foregroundStyle(EmblemStyle.color(emblem.set))
                            Text(EmblemMath.setName(emblem.set)).font(Theme.body(9)).lineLimit(1)
                        }
                        .frame(height: 52)
                    }
                    Button { app.router.push(.emblems) } label: {
                        Label(L("変更", "Change"), systemImage: "arrow.triangle.2.circlepath")
                    }.labelStyle(.iconOnly).buttonStyle(SecondaryButtonStyle()).accessibilityLabel(L("変更", "Change"))
                }.frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("バトルスキル", "Battle Skill")).font(Theme.heading(13)).lineLimit(1)
                    SpellIconView(spellID: skill, size: 48).frame(height: 52)
                    Button { onChangeBattleSkill() } label: {
                        Label(L("変更", "Change"), systemImage: "arrow.triangle.2.circlepath")
                    }.labelStyle(.iconOnly).buttonStyle(SecondaryButtonStyle()).accessibilityLabel(L("変更", "Change")).accessibilityIdentifier("herodetail_battle_skill_change")
                    Text(FlowText.spellName(skill)).font(Theme.body(11))
                }.frame(width: 90, alignment: .leading)
                }
            }
            if !BuildRules.plans(for: hero.heroID).isEmpty {
                HeroBattlePlanSection(hero: hero)
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

// MARK: - バトルプラン

/// MLBB の「バトルプラン」と同じく、3 つのプラン（名前・タグ・装備 6 個・バトルスキル）を並べ、
/// 使っているものに「有効」、ほかに「使う」を出す。選んだプランは Profile.heroBuildPlans に保存し、試合の構成へ渡る。
private struct HeroBattlePlanSection: View {
    let hero: HeroDef
    @Environment(AppModel.self) private var app

    var body: some View {
        let plans = BuildRules.plans(for: hero.heroID)
        let active = BuildRules.activePlanIndex(for: hero.heroID, profile: app.profile)
        let isCustom = BuildRules.custom(for: hero.heroID, profile: app.profile, master: app.master) != nil
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: L("バトルプラン", "Battle Plans"), symbol: "list.bullet.rectangle.fill",
                                       trailing: L("\(plans.count) 件", "\(plans.count) plans"))
                if isCustom {
                    Text(L("カスタムビルドを保存している間は、試合のおすすめ購入にカスタムビルドを使います。",
                           "While a custom build is saved, in-match recommendations use the custom build."))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(plans.enumerated()), id: \.offset) { k, plan in
                    planCard(plan, index: k, isActive: k == active)
                }
                customEmblemNote
            }
        }
    }

    /// エンブレム画面の一括設定で付けたエンブレムがあれば、試合ではプランのエンブレムの代わりにそれを使う。
    @ViewBuilder private var customEmblemNote: some View {
        if let custom = EmblemMath.custom(for: hero.heroID, profile: app.profile) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("一括設定のエンブレムを使います", "Using the emblem applied from the Emblems screen"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                    EmblemLoadoutBadge(emblem: custom, compact: true)
                }
                Spacer(minLength: 4)
                Button {
                    var p = app.profile
                    EmblemMath.clearCustom(heroID: hero.heroID, profile: &p)
                    app.profile = p
                    app.haptics.tap()
                } label: {
                    Text(L("プランに戻す", "Use Plan")).lineLimit(1)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("herodetail_emblem_clear")
            }
        }
    }

    private func planCard(_ plan: BuildPlan, index: Int, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(BuildRules.planName(plan))
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ForEach(plan.tags, id: \.self) { tag in
                    CollectionInfoTag(text: BuildRules.planTag(tag), color: Theme.cyan)
                }
                Spacer(minLength: 4)
                if isActive {
                    Label(L("有効", "Active"), systemImage: "checkmark.circle.fill")
                        .font(Theme.heading(13))
                        .foregroundStyle(Theme.success)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("herodetail_plan_\(index)_active")
                } else {
                    Button {
                        use(index, plan: plan)
                    } label: {
                        Text(L("使う", "Use")).lineLimit(1)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("herodetail_plan_\(index)_use")
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(plan.items.enumerated()), id: \.offset) { i, id in
                    if let item = app.master.item(id) {
                        ItemIconView(item: item, size: 36)
                            .accessibilityLabel("\(i + 1). \(MasterText.item(item))")
                    }
                }
                Spacer(minLength: 4)
                if let spell = plan.spellHint {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(L("バトルスキル", "Spell"))
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                        Text(BuildRules.planSpell(spell))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            // エンブレム（セット + 天賦 3 つ。画面のエンブレムの列）
            HStack(spacing: 6) {
                Text(L("エンブレム", "Emblem"))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                EmblemLoadoutBadge(emblem: plan.emblem)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("herodetail_plan_\(index)_emblem")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Theme.success.opacity(0.12) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? Theme.success.opacity(0.7) : Theme.panelStroke, lineWidth: isActive ? 1.5 : 1)
        )
    }

    private func use(_ index: Int, plan: BuildPlan) {
        var p = app.profile
        BuildRules.choosePlan(index, for: hero.heroID, profile: &p)
        app.profile = p
        app.haptics.tap()
        app.showToast(L("バトルプラン「\(plan.name)」を使います", "Using battle plan \"\(plan.nameEN)\""))
    }
}
