import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI043 ルーン（最大 5 ページ・メインパス + 各 Tier 1 個・使用ページ選択）。

struct RunePageView: View {
    @Environment(AppModel.self) private var app
    @State private var editing = 0
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScreenScaffold(title: L("ルーン", "Runes")) {
            VStack(spacing: 6) {
                pageBar
                if app.profile.runePages.indices.contains(editing) {
                    let page = app.profile.runePages[editing]
                    HStack(alignment: .top, spacing: 10) {
                        pathPicker(page)
                            .frame(width: 148)
                        ScrollView {
                            tierRows(page)
                        }
                        .scrollIndicators(.hidden)
                        ScrollView {
                            summary(page)
                        }
                        .scrollIndicators(.hidden)
                        .frame(width: 208)
                    }
                    .id(page.id)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .animation(.easeInOut(duration: 0.2), value: editing)
        }
        .onAppear(perform: prepare)
        .confirmationDialog(L("このページを削除しますか？", "Delete this page?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("削除", "Delete"), role: .destructive) { deletePage() }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        }
    }

    /// 初回は既定ページを作成し、全ページを正規化する。
    private func prepare() {
        var p = app.profile
        if p.runePages.isEmpty {
            p.runePages = [RuneMath.defaultPage(name: RuneMath.defaultPageName(index: 0), master: app.master)]
            p.selectedRunePage = 0
        }
        p.runePages = p.runePages.prefix(RuneMath.maxPages).map { RuneMath.normalized($0, master: app.master) }
        for i in p.runePages.indices where p.runePages[i].name.isEmpty {
            p.runePages[i].name = RuneMath.defaultPageName(index: i)
        }
        if !p.runePages.indices.contains(p.selectedRunePage) { p.selectedRunePage = 0 }
        if p != app.profile { app.profile = p }
        editing = p.selectedRunePage
    }

    private func update(_ change: (inout RunePage) -> Void) {
        guard app.profile.runePages.indices.contains(editing) else { return }
        var page = app.profile.runePages[editing]
        change(&page)
        app.profile.runePages[editing] = page
    }

    // MARK: ページ切替

    private var pageBar: some View {
        let pages = app.profile.runePages
        return HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                        pageTab(i, page: page, active: app.profile.selectedRunePage == i)
                    }
                    if pages.count < RuneMath.maxPages {
                        Button {
                            addPage()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.cyan)
                                .frame(width: 44, height: 36)
                                .background(RoundedRectangle(cornerRadius: 10).stroke(Theme.cyan.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("ページを追加", "Add page"))
                        .accessibilityIdentifier("rune_page_add")
                    }
                }
            }
            .scrollIndicators(.hidden)
            Text("\(pages.count)/\(RuneMath.maxPages)")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
            if app.profile.selectedRunePage == editing {
                Label(L("使用中", "Active"), systemImage: "checkmark.seal.fill")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.success)
                    .frame(minHeight: 44)
            } else {
                Button {
                    app.profile.selectedRunePage = editing
                    app.haptics.success()
                    app.showToast(L("このページを使用します", "Page set as active"))
                } label: {
                    Label(L("使用する", "Use Page"), systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(minHeight: 44)
                .accessibilityIdentifier("rune_page_activate")
            }
        }
    }

    private func pageTab(_ i: Int, page: RunePage, active: Bool) -> some View {
        let selected = editing == i
        let color = CollectionStyle.runePathColor(page.primaryPath)
        return Button {
            // ページを切り替える前に編集中ページの空の名前を戻す
            restoreEmptyName()
            nameFocused = false
            editing = i
            app.haptics.tap()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: CollectionStyle.runePathSymbol(page.primaryPath))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(selected ? Color.black.opacity(0.8) : color)
                Text(page.name)
                    .font(Theme.body(12))
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? Color.black.opacity(0.7) : Theme.success)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? AnyShapeStyle(color) : AnyShapeStyle(Color.white.opacity(0.07))))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(selected ? 0 : 0.4), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(page.name)\(active ? L("（使用中）", " (active)") : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("rune_page_\(i)")
    }

    // MARK: パス選択

    private func pathPicker(_ page: RunePage) -> some View {
        ScrollView {
            VStack(spacing: 5) {
                ForEach(RunePath.allCases, id: \.self) { path in
                    let selected = page.primaryPath == path
                    let color = CollectionStyle.runePathColor(path)
                    Button {
                        guard !selected else { return }
                        app.haptics.tap()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            update { $0 = RuneMath.changingPath($0, to: path, master: app.master) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            RuneIconView(path: path, tier: 3, size: 28, dimmed: !selected)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(CollectionStyle.runePathName(path))
                                    .font(Theme.heading(13))
                                    .foregroundStyle(selected ? color : Theme.textPrimary)
                                Text(CollectionStyle.runePathTagline(path))
                                    .font(Theme.body(9))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 7)
                        .frame(minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? color.opacity(0.18) : Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? color : Color.clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("rune_path_\(path.rawValue)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Tier 別ルーン

    private func tierRows(_ page: RunePage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(RuneMath.tiers.enumerated()), id: \.offset) { index, tier in
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("ティア \(tier)", "Tier \(tier)"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 8) {
                        ForEach(RuneMath.runes(path: page.primaryPath, tier: tier, master: app.master)) { rune in
                            runeOption(rune, selected: index < page.runeIDs.count && page.runeIDs[index] == rune.runeID, slot: index)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func runeOption(_ rune: RuneDef, selected: Bool, slot: Int) -> some View {
        let color = CollectionStyle.runePathColor(rune.path)
        return Button {
            guard !selected else { return }
            app.haptics.tap()
            withAnimation(.easeOut(duration: 0.15)) {
                update { page in
                    page = RuneMath.normalized(page, master: app.master)
                    page.runeIDs[slot] = rune.runeID
                }
            }
        } label: {
            HStack(spacing: 7) {
                RuneIconView(path: rune.path, tier: rune.tier, size: 34, dimmed: !selected)
                    .scaleEffect(selected ? 1.05 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MasterText.rune(rune))
                        .font(Theme.heading(12))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(RuneMath.effectText(rune))
                        .font(Theme.body(10))
                        .foregroundStyle(selected ? color : Theme.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? color.opacity(0.16) : Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? color : Theme.panelStroke.opacity(0.5), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(MasterText.rune(rune))、\(RuneMath.effectText(rune))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("rune_\(rune.runeID)")
    }

    // MARK: 名前・合計

    private func summary(_ page: RunePage) -> some View {
        let bonus = RuneMath.bonus(for: page, master: app.master)
        let color = CollectionStyle.runePathColor(page.primaryPath)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pencil").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textSecondary)
                TextField(L("ページ名", "Page name"), text: Binding(
                    get: { app.profile.runePages.indices.contains(editing) ? app.profile.runePages[editing].name : "" },
                    set: { v in update { $0.name = String(v.prefix(RuneMath.maxNameLength)) } }))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit(restoreEmptyName)
                    // 確定せずにフォーカスが外れた場合も空の名前を残さない
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { restoreEmptyName() }
                    }
                    .accessibilityIdentifier("rune_page_name")
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3)))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: CollectionStyle.runePathSymbol(page.primaryPath)).foregroundStyle(color)
                    Text(L("効果の合計", "Total Bonus")).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
                }
                ForEach(bonus.lines) { line in
                    HStack {
                        Image(systemName: line.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(color).frame(width: 14)
                        Text(line.label).font(Theme.body(12)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer()
                        Text(line.value).font(Theme.mono(12)).foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if bonus.lines.isEmpty {
                    Text(L("ルーンを選択してください", "Select runes")).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.4), lineWidth: 1))
            if app.profile.runePages.count > 1 {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(L("ページを削除", "Delete Page"), systemImage: "trash")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rune_page_delete")
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: 操作

    private func restoreEmptyName() {
        update { page in
            if page.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                page.name = RuneMath.defaultPageName(index: editing)
            }
        }
    }

    private func addPage() {
        guard app.profile.runePages.count < RuneMath.maxPages else { return }
        restoreEmptyName()
        let index = app.profile.runePages.count
        let path = RunePath.allCases[index % RunePath.allCases.count]
        app.profile.runePages.append(RuneMath.defaultPage(name: RuneMath.defaultPageName(index: index), path: path, master: app.master))
        editing = index
        app.haptics.tap()
    }

    private func deletePage() {
        var p = app.profile
        guard p.runePages.count > 1, p.runePages.indices.contains(editing) else { return }
        p.runePages.remove(at: editing)
        if p.selectedRunePage == editing {
            p.selectedRunePage = 0
        } else if p.selectedRunePage > editing {
            p.selectedRunePage -= 1
        }
        app.profile = p
        editing = min(editing, p.runePages.count - 1)
    }
}
