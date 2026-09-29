import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI046 スキンストア（ヒーロー別フィルタ・プレビュー・価格/所持）。

struct SkinStoreView: View {
    @Environment(AppModel.self) private var app
    @State private var heroID: String?
    @State private var hideOwned = false

    private let columns = [GridItem(.adaptive(minimum: 136), spacing: 10)]

    var body: some View {
        let all = StoreCatalog.items(in: .skins, master: app.master)
        let heroes = skinHeroes(all)
        let items = all.filter { item in
            guard let c = app.master.cosmetic(item.grantID) else { return false }
            if let heroID, c.heroID != heroID { return false }
            if hideOwned && EconomyService.isOwned(item, profile: app.profile) { return false }
            return true
        }
        ScreenScaffold(title: L("スキンストア", "Skin Store")) {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            CollectionFilterChip(title: L("全ヒーロー", "All Heroes"), symbol: "person.2.fill",
                                                 color: StoreCategory.skins.color, isSelected: heroID == nil) { heroID = nil }
                                .accessibilityIdentifier("skins_hero_all")
                            ForEach(heroes) { h in
                                heroChip(h)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    CollectionFilterChip(title: L("未所持のみ", "Unowned only"), symbol: "line.3.horizontal.decrease.circle",
                                         color: Theme.cyan, isSelected: hideOwned) { hideOwned.toggle() }
                        .accessibilityIdentifier("skins_hide_owned")
                }
                ScrollView {
                    if items.isEmpty {
                        CollectionEmptyState(symbol: "paintpalette", title: L("表示できるスキンがありません", "No skins to show"),
                                             message: hideOwned ? L("すべて所持しています", "You own them all") : nil)
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(items) { item in
                                StoreProductCard(item: item, previewSize: 96)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
                .scrollIndicators(.hidden)
                .animation(.easeInOut(duration: 0.2), value: heroID)
                .animation(.easeInOut(duration: 0.2), value: hideOwned)
            }
            .padding(.horizontal, 20)
        }
    }

    /// スキンが存在するヒーロー（ID 昇順）。
    private func skinHeroes(_ items: [StoreItemDef]) -> [HeroDef] {
        let ids = items.compactMap { app.master.cosmetic($0.grantID)?.heroID }
        return app.master.heroes.filter { ids.contains($0.heroID) }
    }

    private func heroChip(_ h: HeroDef) -> some View {
        let selected = heroID == h.heroID
        return Button {
            app.haptics.tap()
            heroID = selected ? nil : h.heroID
        } label: {
            HStack(spacing: 6) {
                HeroPortraitView(heroID: h.heroID, size: 26, showsRole: false)
                Text(MasterText.hero(h))
                    .font(Theme.body(12))
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(height: 34)
            .background(Capsule().fill(selected ? AnyShapeStyle(StoreCategory.skins.color) : AnyShapeStyle(Color.white.opacity(0.08))))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MasterText.hero(h))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("skins_hero_\(h.heroID)")
    }
}
