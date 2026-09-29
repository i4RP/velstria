import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI042 ビルド編集（6 枠・推奨から開始・並べ替え/削除・保存）。

struct BuildEditorView: View {
    let heroID: String
    @Environment(AppModel.self) private var app
    @State private var build: [String] = []
    @State private var loaded = false
    @State private var selectedSlot: Int?
    @State private var category: ItemCategory?
    @State private var warning: String?

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        ScreenScaffold(title: L("ビルド編集", "Build Editor")) {
            if let hero = app.master.hero(heroID) {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView {
                        editorPanel(hero)
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: 272)
                    catalog
                }
                .padding(.horizontal, 20)
                .onAppear(perform: load)
            } else {
                CollectionEmptyState(symbol: "questionmark.circle", title: L("ヒーローが見つかりません", "Hero not found"))
            }
        }
    }

    private var saved: [String] { BuildRules.current(for: heroID, profile: app.profile, master: app.master) }
    private var isDirty: Bool { loaded && build != saved }

    private func load() {
        guard !loaded else { return }
        build = saved
        loaded = true
    }

    // MARK: 左: 6 枠と操作

    private func editorPanel(_ hero: HeroDef) -> some View {
        let isCustom = app.profile.customBuilds[heroID] != nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HeroPortraitView(heroID: hero.heroID, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(MasterText.hero(hero)).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(isCustom ? L("カスタムビルド", "Custom build") : L("おすすめビルド", "Recommended build"))
                        .font(Theme.body(10))
                        .foregroundStyle(isCustom ? Theme.gold : Theme.textSecondary)
                }
                Spacer(minLength: 0)
                if isDirty {
                    CollectionInfoTag(text: L("未保存", "Unsaved"), symbol: "pencil", color: Theme.gold)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(62), spacing: 10), count: 3), spacing: 8) {
                ForEach(0..<BuildRules.slotCount, id: \.self) { i in
                    slotView(i)
                }
            }
            .frame(maxWidth: .infinity)
            selectionControls
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if BuildRules.lacksSmite(build, spells: SpellLoadoutRules.effective(heroID: heroID, profile: app.profile), master: app.master) {
                smiteNotice
            }
            HStack {
                Text(L("合計", "Total")).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                GoldPriceLabel(amount: BuildRules.totalCost(build, master: app.master), size: 13)
                Spacer()
                Text("\(build.count)/\(BuildRules.slotCount)").font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 8) {
                Button {
                    resetToRecommended()
                } label: {
                    Label(L("推奨に戻す", "Reset"), systemImage: "arrow.counterclockwise")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .accessibilityIdentifier("build_reset")
                Button {
                    save()
                } label: {
                    Label(L("保存", "Save"), systemImage: "checkmark")
                        .lineLimit(1)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(minHeight: 44)
                .disabled(!isDirty)
                .opacity(isDirty ? 1 : 0.5)
                .accessibilityIdentifier("build_save")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: warning)
    }

    /// ジャングル装備は狩猟印が無いと購入できないため、スペル設定へ誘導する。
    private var smiteNotice: some View {
        Button {
            app.haptics.tap()
            app.router.push(.spells)
        } label: {
            HStack(spacing: 6) {
                SpellIconView(spellID: BuildRules.smiteSpellID, size: 24)
                Text(L("ジャングル装備の購入には「狩猟印」が必要です。スペルを設定 ›",
                       "Jungle items require Smite. Set up spells ›"))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.gold)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.gold.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("build_smite_notice")
    }

    private func slotView(_ i: Int) -> some View {
        let item = i < build.count ? app.master.item(build[i]) : nil
        let selected = selectedSlot == i
        return Button {
            app.haptics.tap()
            withAnimation(.easeOut(duration: 0.15)) {
                selectedSlot = selected ? nil : (item == nil ? nil : i)
            }
            warning = nil
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selected ? Theme.gold : Theme.panelStroke,
                                    style: StrokeStyle(lineWidth: selected ? 2.5 : 1, dash: item == nil ? [4, 3] : []))
                    )
                if let item {
                    ItemIconView(item: item, size: 50)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text("\(i + 1)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(item == nil ? Theme.textSecondary : .black)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(item == nil ? Color.white.opacity(0.1) : Theme.gold))
                    .padding(3)
            }
            .frame(width: 62, height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.map { L("枠\(i + 1): \(MasterText.item($0))", "Slot \(i + 1): \(MasterText.item($0))") }
                            ?? L("枠\(i + 1): 空き", "Slot \(i + 1): empty"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("build_slot_\(i)")
    }

    @ViewBuilder
    private var selectionControls: some View {
        if let s = selectedSlot, s < build.count, let item = app.master.item(build[s]) {
            HStack(spacing: 6) {
                Text(MasterText.item(item))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                controlButton("chevron.left", label: L("前へ", "Move earlier"), id: "build_move_left", enabled: s > 0) { move(by: -1) }
                controlButton("chevron.right", label: L("後へ", "Move later"), id: "build_move_right", enabled: s < build.count - 1) { move(by: 1) }
                controlButton("trash.fill", label: L("外す", "Remove"), id: "build_remove", enabled: true, tint: Theme.danger) { remove() }
            }
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.gold.opacity(0.1)))
        } else {
            Text(build.count < BuildRules.slotCount
                 ? L("右の一覧から装備をタップして追加。枠をタップで並べ替え・削除。", "Tap an item to add it. Tap a slot to reorder or remove.")
                 : L("枠を選ぶと入れ替え・並べ替え・削除ができます。", "Select a slot to replace, reorder or remove."))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 44, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func controlButton(_ symbol: String, label: String, id: String, enabled: Bool, tint: Color = Theme.textPrimary,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint.opacity(enabled ? 1 : 0.3))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: 右: 装備カタログ

    private var catalog: some View {
        let items = ItemMath.filtered(app.master.items, category: category, tier: nil)
            .sorted { $0.tier != $1.tier ? $0.tier > $1.tier : $0.itemID < $1.itemID }
        return VStack(spacing: 2) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    CollectionFilterChip(title: L("すべて", "All"), symbol: "square.grid.2x2.fill", color: Theme.cyan,
                                         isSelected: category == nil) { category = nil }
                    ForEach(ItemCategory.allCases, id: \.self) { c in
                        CollectionFilterChip(title: CollectionStyle.categoryName(c), symbol: CollectionStyle.categorySymbol(c),
                                             color: CollectionStyle.categoryColor(c), isSelected: category == c, showsTitle: false) {
                            category = c
                        }
                        .accessibilityIdentifier("build_category_\(c.rawValue)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(items) { item in
                        catalogCell(item)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func catalogCell(_ item: ItemDef) -> some View {
        let inBuild = build.contains(item.itemID)
        return Button {
            add(item.itemID)
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    ItemIconView(item: item, size: 46)
                        .opacity(inBuild ? 0.45 : 1)
                    if inBuild {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.success)
                            .background(Circle().fill(Color.black))
                            .offset(x: 4, y: -4)
                    }
                }
                Text(MasterText.item(item))
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                GoldPriceLabel(amount: item.priceGold, size: 9)
            }
            .padding(5)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel("\(MasterText.item(item))\(inBuild ? L("（ビルド内）", " (in build)") : "")")
        .accessibilityIdentifier("build_item_\(item.itemID)")
    }

    // MARK: 操作

    private func add(_ itemID: String) {
        let replacing = selectedSlot.flatMap { $0 < build.count ? $0 : nil }
        let result = BuildRules.check(itemID, adding: build, replacing: replacing, master: app.master)
        guard result == .ok else {
            app.haptics.warning()
            warning = result.message
            return
        }
        warning = nil
        app.haptics.tap()
        withAnimation(.spring(duration: 0.3)) {
            if let replacing {
                build[replacing] = itemID
                selectedSlot = nil
            } else {
                build.append(itemID)
            }
        }
    }

    private func move(by offset: Int) {
        guard let s = selectedSlot else { return }
        withAnimation(.spring(duration: 0.25)) {
            build = BuildRules.move(build, from: s, by: offset)
            selectedSlot = s + offset
        }
    }

    private func remove() {
        guard let s = selectedSlot, s < build.count else { return }
        withAnimation(.spring(duration: 0.25)) {
            build.remove(at: s)
            selectedSlot = nil
        }
        warning = nil
    }

    private func save() {
        let clean = BuildRules.sanitized(build, master: app.master)
        if clean.isEmpty {
            app.profile.customBuilds[heroID] = nil
            app.showToast(L("カスタムビルドを削除しました", "Custom build cleared"))
        } else {
            app.profile.customBuilds[heroID] = clean
            app.showToast(L("ビルドを保存しました", "Build saved"))
        }
        build = saved
        selectedSlot = nil
        app.haptics.success()
    }

    private func resetToRecommended() {
        app.profile.customBuilds[heroID] = nil
        withAnimation(.spring(duration: 0.3)) {
            build = BuildRules.recommended(for: heroID, master: app.master)
            selectedSlot = nil
        }
        warning = nil
        app.showToast(L("おすすめビルドに戻しました", "Reset to recommended build"))
    }
}
