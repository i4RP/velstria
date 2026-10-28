import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI045 ストアホーム（注目バンドル・カテゴリ・カテゴリ別商品）。

struct StoreHomeView: View {
    @Environment(AppModel.self) private var app
    /// インライン表示中のカテゴリ（スキン・Gem は専用画面へ遷移）。
    @State private var category: StoreCategory = .effects
    @State private var effectFilter: CosmeticType?

    var body: some View {
        ScreenScaffold(title: L("ストア", "Store")) {
            ScrollViewReader { proxy in
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        CurrencyBadge(kind: .coin, amount: app.profile.starlightCoin)
                        CurrencyBadge(kind: .gem, amount: app.profile.totalGem)
                        Spacer(minLength: 0)
                        Button { app.router.push(.inventory) } label: { Image(systemName: "shippingbox") }
                            .accessibilityLabel(L("所持品", "Inventory"))
                            .accessibilityIdentifier("store_inventory")
                        Button { app.router.push(.restorePurchases) } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel(L("購入を復元", "Restore purchases"))
                            .accessibilityIdentifier("store_restore")
                    }
                    .font(Theme.body(14)).foregroundStyle(Theme.cyan)
                    .frame(minHeight: 32)
                    categoryTiles(proxy: proxy)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            categorySection.id("category_section")
                            SectionTitle(title: L("注目バンドル", "Featured bundles"), symbol: "sparkles")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 12) {
                                ForEach(StoreCatalog.featuredBundles(master: app.master, day: StoreCatalog.dayNumber(Date()))) { item in
                                    StoreProductCard(item: item)
                                }
                            }
                            .accessibilityIdentifier("store_featured")
                        }
                        .padding(.top, 6)
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private func categoryTiles(proxy: ScrollViewProxy) -> some View {
        // 商品の無いカテゴリ（今はスキン）は出さず、出すタイルで 1 行を埋める
        let categories = StoreCatalog.homeCategories(master: app.master)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories) { c in
                    CollectionFilterChip(title: c.title, symbol: c.symbol, color: Theme.cyan,
                                         isSelected: c == category && c != .skins && c != .gems) {
                        app.haptics.tap()
                        switch c {
                        case .skins: app.router.push(.skinStore)
                        case .gems: app.router.push(.currencyStore)
                        default:
                            category = c
                            effectFilter = nil
                            proxy.scrollTo("category_section", anchor: .top)
                        }
                    }
                    .accessibilityIdentifier("store_cat_\(c.rawValue)")
                }
            }
        }
    }

    private var categorySection: some View {
        let all = StoreCatalog.items(in: category, master: app.master)
        let items = all.filter { item in
            guard let effectFilter else { return true }
            return app.master.cosmetic(item.grantID)?.type == effectFilter
        }
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: category.title, symbol: category.symbol,
                                   trailing: L("\(items.count) 件", "\(items.count) items"))
            if category == .effects {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                    CollectionFilterChip(title: L("すべて", "All"), color: Theme.cyan, isSelected: effectFilter == nil) { effectFilter = nil }
                        .accessibilityIdentifier("store_effect_all")
                    ForEach(category.cosmeticTypes, id: \.self) { t in
                        CollectionFilterChip(title: CollectionStyle.cosmeticTypeName(t), symbol: CollectionStyle.cosmeticTypeSymbol(t),
                                             color: category.color, isSelected: effectFilter == t) { effectFilter = t }
                            .accessibilityIdentifier("store_effect_\(t.rawValue)")
                    }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
                ForEach(items) { item in
                    StoreProductCard(item: item)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: effectFilter)
    }
}

/// 商品カード（プレビュー・名前・レアリティ・価格/所持）。
struct StoreProductCard: View {
    let item: StoreItemDef
    var previewSize: CGFloat = 80
    @Environment(AppModel.self) private var app

    var body: some View {
        let owned = EconomyService.isOwned(item, profile: app.profile)
        let unavailable = StoreCatalog.isUnavailable(item, profile: app.profile)
        let rarity = StoreCatalog.rarity(of: item, master: app.master)
        let tint = rarity.map(Theme.rarityColor) ?? Theme.cyan
        Button {
            app.haptics.tap()
            app.router.push(.productDetail(item.sku))
        } label: {
            VStack(spacing: 5) {
                StoreItemPreview(item: item, size: previewSize, animated: false)
                    .frame(height: previewSize + 4)
                    .padding(.top, 16)
                Text(MasterText.storeItem(item))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28)
                HStack(spacing: 4) {
                    Image(systemName: StoreCatalog.typeSymbol(item, master: app.master)).font(.system(size: 9))
                    Text(StoreCatalog.typeLabel(item, master: app.master)).font(Theme.body(9)).lineLimit(1)
                }
                .foregroundStyle(tint)
                Group {
                    if owned {
                        Label(L("所持済み", "Owned"), systemImage: "checkmark.circle.fill")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.success)
                    } else if unavailable {
                        Text(L("上限到達", "Limit reached")).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                    } else {
                        PriceTag(currency: item.currency, amount: EconomyService.price(of: item), size: 12,
                                 insufficient: !StoreCatalog.canAfford(item, profile: app.profile))
                    }
                }
                .frame(height: 18)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, minHeight: 206, alignment: .top)
            .worldShellCard(selected: owned)
            .opacity(unavailable && !owned ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel("\(MasterText.storeItem(item))、\(owned ? L("所持済み", "Owned") : "\(EconomyService.price(of: item)) \(CollectionStyle.currencyName(item.currency))")")
        .accessibilityIdentifier("product_\(item.sku)")
    }
}
