import SwiftUI
import VelstriaCore

// 担当: ui-collection。エンブレム（MLBB のエンブレム画面を写したもの。旧 UI043 ルーンの置き換え。docs/EMBLEMS.md）。
// 上に 7 つのセットのタブ（記号 + Lv）、左にセット名とリング（右上 = 1 段目・左 = 2 段目・下 = コアの天賦）、右にステータス。
// 天賦の枠を押すとその段の天賦の一覧（装備中に ✓）と、名前・橙の小見出し・説明・「装備」/「装備中」。
// 左上の 🔍 はエンブレムステータス（現在/最大レベル）と天賦の説明、右下のボタンは一括設定（ヒーローを選んで付ける）。
// 天賦は組み換え自由（どのセットにもどの天賦でも付けられる。段は合わせる）。

struct EmblemView: View {
    @Environment(AppModel.self) private var app
    /// 天賦を選んでいる段（nil = ステータスを表示）。
    @State private var pickingTier: EmblemTier?
    /// 一覧で選んで説明を見ている天賦。
    @State private var preview: EmblemTalentID?
    @State private var showsBulk = false
    @State private var showsDetail = false

    private var current: EmblemSetID { EmblemMath.selectedSet(app.profile) }

    var body: some View {
        let set = current
        let page = EmblemMath.page(set, profile: app.profile)
        let unlocked = EmblemMath.isUnlocked(set, profile: app.profile)
        ScreenScaffold(title: L("エンブレム", "Emblems")) {
            VStack(spacing: 8) {
                setTabs
                HStack(alignment: .top, spacing: 12) {
                    ringPanel(set: set, page: page, unlocked: unlocked)
                        .frame(width: 330)
                    if let tier = pickingTier, unlocked {
                        pickerPanel(tier: tier, page: page)
                    } else {
                        statusPanel(set: set, page: page)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .animation(.easeInOut(duration: 0.2), value: pickingTier)
        }
        .sheet(isPresented: $showsBulk) {
            EmblemBulkApplySheet(set: set).environment(app)
        }
        .sheet(isPresented: $showsDetail) {
            EmblemDetailSheet(page: page).environment(app)
        }
    }

    // MARK: セットのタブ

    private var setTabs: some View {
        HStack(spacing: 6) {
            ForEach(EmblemSetID.allCases, id: \.self) { set in
                setTab(set)
            }
        }
    }

    private func setTab(_ set: EmblemSetID) -> some View {
        let selected = current == set
        let color = EmblemStyle.color(set)
        let unlocked = EmblemMath.isUnlocked(set, profile: app.profile)
        let level = EmblemMath.level(set, profile: app.profile)
        return Button {
            guard !selected else { return }
            app.haptics.tap()
            app.profile.selectedEmblemSet = set.rawValue
            pickingTier = nil
            preview = nil
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(color.opacity(selected ? 0.35 : 0.18))
                    Circle().stroke(color.opacity(selected ? 1 : 0.5), lineWidth: 1.2)
                    Image(systemName: unlocked ? EmblemStyle.setSymbol(set) : "lock.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(unlocked ? color : Theme.textSecondary)
                }
                .frame(width: 32, height: 32)
                Text(unlocked ? "Lv\(level)" : L("未解放", "Locked"))
                    .font(Theme.mono(12))
                    .foregroundStyle(unlocked ? Theme.success : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? color.opacity(0.16) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? color : Theme.panelStroke.opacity(0.6), lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(EmblemMath.setName(set)) \(unlocked ? "Lv\(level)" : L("未解放", "Locked"))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("emblem_tab_\(set.rawValue)")
    }

    // MARK: リング（セット名・天賦 3 枠・🔍・MAX・一括設定）

    private func ringPanel(set: EmblemSetID, page: EmblemLoadout, unlocked: Bool) -> some View {
        let color = EmblemStyle.color(set)
        let maxed = EmblemMath.isMaxLevel(set, profile: app.profile)
        return Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lv\(page.level)")
                            .font(Theme.title(24))
                            .foregroundStyle(Theme.gold)
                        Text(EmblemMath.setName(set))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 4)
                    Button {
                        app.haptics.tap()
                        showsDetail = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.cyan)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("エンブレムステータス", "Emblem Details"))
                    .accessibilityIdentifier("emblem_detail")
                }
                ZStack {
                    Circle()
                        .stroke(LinearGradient(colors: [color.opacity(0.9), Theme.cyan.opacity(0.5)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                        .frame(width: 170, height: 170)
                    Circle()
                        .fill(RadialGradient(colors: [color.opacity(0.25), .clear], center: .center, startRadius: 4, endRadius: 85))
                        .frame(width: 160, height: 160)
                    Image(systemName: unlocked ? EmblemStyle.setSymbol(set) : "lock.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(color.opacity(0.35))
                    slot(.tier1, page: page, unlocked: unlocked).offset(x: 62, y: -62)
                    slot(.tier2, page: page, unlocked: unlocked).offset(x: -86, y: 0)
                    slot(.core, page: page, unlocked: unlocked).offset(x: 30, y: 82)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                HStack {
                    Spacer()
                    Text(unlocked ? (maxed ? "MAX" : "Lv\(page.level) / \(EmblemCatalog.maxLevel)") : L("未解放", "Locked"))
                        .font(Theme.heading(15))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("emblem_level_state")
                    Spacer()
                    Button {
                        app.haptics.tap()
                        showsBulk = true
                    } label: {
                        Image(systemName: "person.2.badge.gearshape.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(color.opacity(0.35)))
                            .overlay(Circle().stroke(color, lineWidth: 1.2))
                    }
                    .buttonStyle(.plain)
                    .disabled(!unlocked)
                    .accessibilityLabel(L("一括設定", "Apply to Heroes"))
                    .accessibilityIdentifier("emblem_bulk")
                }
            }
        }
    }

    /// 天賦の枠（押すとその段の一覧。右下に入れ替えの印）。
    private func slot(_ tier: EmblemTier, page: EmblemLoadout, unlocked: Bool) -> some View {
        let id = page.talent(tier)
        let selected = pickingTier == tier
        let color = EmblemStyle.talentColor(id)
        let size: CGFloat = tier == .core ? 70 : 60
        return Button {
            guard unlocked else { return }
            app.haptics.tap()
            if selected {
                pickingTier = nil
                preview = nil
            } else {
                pickingTier = tier
                preview = id
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(Color.black.opacity(0.55))
                    Circle().stroke(selected ? Theme.gold : color.opacity(0.7), lineWidth: selected ? 3 : 2)
                    Image(systemName: EmblemStyle.talentSymbol(id))
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(color)
                }
                .frame(width: size, height: size)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Theme.cyan.opacity(0.6)))
                    .offset(x: 2, y: 2)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(EmblemMath.tierLabel(tier))：\(EmblemMath.talentName(id))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("emblem_slot_\(tier.rawValue)")
    }

    // MARK: ステータス

    private func statusPanel(set: EmblemSetID, page: EmblemLoadout) -> some View {
        let def = EmblemCatalog.set(set)
        let color = EmblemStyle.color(set)
        return Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                CollectionSectionTitle(title: L("ステータス", "Stats"), symbol: "chart.bar.fill")
                ForEach(Array(def.attributes.enumerated()), id: \.offset) { _, a in
                    HStack(spacing: 10) {
                        Image(systemName: EmblemStyle.attributeSymbol(a.kind))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(color)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(EmblemMath.attributeName(a.kind))
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textPrimary)
                            Text(EmblemMath.attributeValue(a, level: page.level))
                                .font(Theme.mono(14))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
                CollectionSectionTitle(title: L("天賦", "Talents"), symbol: "sparkles")
                ForEach(EmblemTier.allCases, id: \.self) { tier in
                    let id = page.talent(tier)
                    HStack(spacing: 8) {
                        Image(systemName: EmblemStyle.talentSymbol(id))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(EmblemStyle.talentColor(id))
                            .frame(width: 22)
                        Text("\(EmblemMath.tierLabel(tier))：\(EmblemMath.talentName(id))")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 天賦の一覧

    private func pickerPanel(tier: EmblemTier, page: EmblemLoadout) -> some View {
        let options = EmblemCatalog.talents(tier: tier)
        let shown = preview.flatMap { $0.tier == tier ? $0 : nil } ?? page.talent(tier)
        let columns = Array(repeating: GridItem(.fixed(58), spacing: 10), count: 3)
        return Panel(padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(options) { t in
                            talentOption(t.id, equipped: page.talent(tier) == t.id, shown: shown == t.id)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.hidden)
                .frame(width: 210)
                talentDetail(shown, equipped: page.talent(tier) == shown)
            }
        }
    }

    private func talentOption(_ id: EmblemTalentID, equipped: Bool, shown: Bool) -> some View {
        let color = EmblemStyle.talentColor(id)
        return Button {
            app.haptics.selection()
            preview = id
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(Color.black.opacity(0.5))
                    Circle().stroke(shown ? Theme.gold : color.opacity(0.45), lineWidth: shown ? 2.5 : 1.2)
                    Image(systemName: EmblemStyle.talentSymbol(id))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(color)
                }
                .frame(width: 54, height: 54)
                if equipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.success)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
            }
            .frame(minWidth: 54, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(EmblemMath.talentName(id))\(equipped ? L("（装備中）", " (equipped)") : "")")
        .accessibilityAddTraits(shown ? .isSelected : [])
        .accessibilityIdentifier("emblem_talent_\(id.rawValue)")
    }

    private func talentDetail(_ id: EmblemTalentID, equipped: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(EmblemMath.talentName(id))
                    .font(Theme.heading(16))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 4)
                Button {
                    app.haptics.tap()
                    pickingTier = nil
                    preview = nil
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("戻る", "Back"))
                .accessibilityIdentifier("emblem_picker_back")
            }
            Rectangle().fill(Theme.panelStroke).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let sub = EmblemMath.talentSubtitle(id) {
                        Text(sub)
                            .font(Theme.body(13))
                            .foregroundStyle(Color(red: 1.0, green: 0.68, blue: 0.30))
                    }
                    Text(EmblemMath.talentDescription(id))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            Rectangle().fill(Theme.panelStroke).frame(height: 1)
            HStack {
                Spacer()
                if equipped {
                    Text(L("装備中", "Equipped"))
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("emblem_equipped")
                } else {
                    Button {
                        equip(id)
                    } label: {
                        Text(L("装備", "Equip"))
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
                    .accessibilityIdentifier("emblem_equip")
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func equip(_ id: EmblemTalentID) {
        var p = app.profile
        EmblemMath.equip(id, set: current, profile: &p)
        app.profile = p
        app.haptics.success()
    }
}

// MARK: - 一括設定

/// MLBB の「一括設定」: ロールのタブと全選択で、このセットと天賦を付けるヒーローを選ぶ。
struct EmblemBulkApplySheet: View {
    let set: EmblemSetID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var filter: EmblemHeroFilter = .all
    @State private var selected: Set<String> = []
    @State private var prepared = false

    var body: some View {
        let heroes = EmblemMath.bulkCandidates(filter: filter, profile: app.profile, master: app.master)
        let columns = [GridItem(.adaptive(minimum: 72, maximum: 90), spacing: 10)]
        return ZStack {
            StarfieldBackground()
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    Text(L("一括設定", "Apply to Heroes"))
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    FlowCloseButton(identifier: "emblem_bulk_close") { dismiss() }
                }
                HStack(spacing: 6) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(EmblemMath.bulkFilters(profile: app.profile, master: app.master)) { f in
                                CollectionFilterChip(title: f.title, isSelected: filter == f) {
                                    app.haptics.tap()
                                    filter = f
                                }
                                .accessibilityIdentifier("emblem_bulk_filter_\(f.rawValue)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    Button {
                        app.haptics.tap()
                        let ids = Set(heroes.map(\.heroID))
                        if ids.isSubset(of: selected) {
                            selected.subtract(ids)
                        } else {
                            selected.formUnion(ids)
                        }
                    } label: {
                        Label(L("全選択", "Select All"), systemImage: "checkmark.square")
                            .lineLimit(1)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("emblem_bulk_all")
                }
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(heroes) { h in
                            heroCell(h)
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.hidden)
                Text(L("エンブレムを適用するヒーローを選んでください", "Choose the heroes to apply this emblem to"))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    apply()
                } label: {
                    Text("OK").frame(minWidth: 120)
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("emblem_bulk_ok")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !prepared else { return }
            prepared = true
            selected = EmblemMath.heroesUsing(EmblemMath.page(set, profile: app.profile), profile: app.profile)
        }
    }

    private func heroCell(_ h: HeroDef) -> some View {
        let on = selected.contains(h.heroID)
        return Button {
            app.haptics.selection()
            if on { selected.remove(h.heroID) } else { selected.insert(h.heroID) }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                HeroPortraitView(heroID: h.heroID, size: 64, showsRole: false)
                    .opacity(on ? 1 : 0.75)
                    .overlay(Circle().stroke(on ? Theme.gold : Color.clear, lineWidth: 2.5))
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.success)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
            }
            .frame(minWidth: 64, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MasterText.hero(h))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("emblem_bulk_hero_\(h.heroID)")
    }

    private func apply() {
        var p = app.profile
        let n = EmblemMath.apply(set: set, to: selected.sorted(), profile: &p)
        app.profile = p
        app.haptics.success()
        app.showToast(L("\(n) 体のヒーローにエンブレムを適用しました", "Applied the emblem to \(n) heroes"))
        dismiss()
    }
}

// MARK: - 🔍 エンブレムステータス

/// 🔍 の画面: 「エンブレムステータス：現在/最大レベル」（セットの 3 つの能力値）と「エンブレム天賦：」（付けている 3 つの説明）。
struct EmblemDetailSheet: View {
    let page: EmblemLoadout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let def = EmblemCatalog.set(page.set)
        let color = EmblemStyle.color(page.set)
        return ZStack {
            StarfieldBackground()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: EmblemStyle.setSymbol(page.set)).foregroundStyle(color)
                    Text("\(EmblemMath.setName(page.set))  Lv\(page.level)")
                        .font(Theme.title(18))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    FlowCloseButton(identifier: "emblem_detail_close") { dismiss() }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("エンブレムステータス：現在/最大レベル", "Emblem stats: current / max level"))
                            .font(Theme.heading(14))
                            .foregroundStyle(Theme.gold)
                        ForEach(Array(def.attributes.enumerated()), id: \.offset) { _, a in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(EmblemMath.attributeName(a.kind))
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text(EmblemMath.currentMaxText(a, level: page.level))
                                        .font(Theme.mono(13))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                // 用語説明（混合・適応の意味。日本語クライアントの文）
                                if let g = EmblemMath.attributeGlossary(a.kind) {
                                    Text(g)
                                        .font(Theme.body(10))
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text(L("エンブレム天賦：", "Emblem talents:"))
                            .font(Theme.heading(14))
                            .foregroundStyle(Theme.gold)
                            .padding(.top, 4)
                        ForEach(EmblemTier.allCases, id: \.self) { tier in
                            let id = page.talent(tier)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(EmblemMath.tierLabel(tier))：\(EmblemMath.talentName(id))")
                                    .font(Theme.heading(13))
                                    .foregroundStyle(EmblemStyle.talentColor(id))
                                Text(EmblemMath.talentDescription(id))
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .preferredColorScheme(.dark)
    }
}

/// エンブレム 1 式の小さな表示（セットの記号 + 天賦 3 つの記号と名前）。ヒーロー詳細のバトルプラン・出撃準備で使う。
struct EmblemLoadoutBadge: View {
    let emblem: EmblemLoadout
    var compact = false

    var body: some View {
        let color = EmblemStyle.color(emblem.set)
        HStack(spacing: 6) {
            Image(systemName: EmblemStyle.setSymbol(emblem.set))
                .font(.system(size: compact ? 11 : 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
                .background(Circle().fill(color.opacity(0.18)))
                .overlay(Circle().stroke(color.opacity(0.7), lineWidth: 1))
            ForEach(emblem.talents, id: \.self) { t in
                HStack(spacing: 3) {
                    Image(systemName: EmblemStyle.talentSymbol(t))
                        .font(.system(size: compact ? 9 : 11, weight: .bold))
                        .foregroundStyle(EmblemStyle.talentColor(t))
                    Text(EmblemMath.talentName(t))
                        .font(Theme.body(compact ? 9 : 11))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EmblemMath.summary(emblem))
    }
}
