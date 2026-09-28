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
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            StoreFeaturedCarousel()
                                .frame(height: 188)
                            StoreWalletPanel()
                                .frame(width: 200, height: 188)
                        }
                        categoryTiles(proxy: proxy)
                        categorySection
                            .id("category_section")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func categoryTiles(proxy: ScrollViewProxy) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(StoreCategory.allCases) { c in
                StoreCategoryTile(category: c, selected: c == category && c != .skins && c != .gems,
                                  count: StoreCatalog.items(in: c, master: app.master).count) {
                    app.haptics.tap()
                    switch c {
                    case .skins: app.router.push(.skinStore)
                    case .gems: app.router.push(.currencyStore)
                    default:
                        withAnimation(.easeInOut(duration: 0.25)) {
                            category = c
                            effectFilter = nil
                        }
                        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("category_section", anchor: .top) }
                    }
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
            CollectionSectionTitle(title: category.title, symbol: category.symbol,
                                   trailing: L("\(items.count) 件", "\(items.count) items"))
            if category == .effects {
                HStack(spacing: 6) {
                    CollectionFilterChip(title: L("すべて", "All"), color: category.color, isSelected: effectFilter == nil) { effectFilter = nil }
                    ForEach(category.cosmeticTypes, id: \.self) { t in
                        CollectionFilterChip(title: CollectionStyle.cosmeticTypeName(t), symbol: CollectionStyle.cosmeticTypeSymbol(t),
                                             color: category.color, isSelected: effectFilter == t) { effectFilter = t }
                            .accessibilityIdentifier("store_effect_\(t.rawValue)")
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                ForEach(items) { item in
                    StoreProductCard(item: item)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: effectFilter)
    }
}

// MARK: - 注目バンドル

struct StoreFeaturedCarousel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    var body: some View {
        let featured = StoreCatalog.featuredBundles(master: app.master, day: StoreCatalog.dayNumber(Date()))
        TabView(selection: $page) {
            ForEach(Array(featured.enumerated()), id: \.element.sku) { i, item in
                StoreFeaturedBanner(item: item)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.gold.opacity(0.35), lineWidth: 1))
        .task(id: featured.count) {
            // 5 秒毎に自動送り
            guard !reduceMotion, featured.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.5)) { page = (page + 1) % featured.count }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("store_featured")
    }
}

struct StoreFeaturedBanner: View {
    let item: StoreItemDef
    @Environment(AppModel.self) private var app

    var body: some View {
        let n = Int(item.grantID.suffix(2)) ?? 1
        let hue = (0.08 + 0.137 * Double(n)).truncatingRemainder(dividingBy: 1)
        let count = StoreCatalog.purchaseCount(sku: item.sku, profile: app.profile)
        let contents = EconomyService.bundleContents(item.grantID, master: app.master)
        Button {
            app.haptics.tap()
            app.router.push(.productDetail(item.sku))
        } label: {
            ZStack {
                LinearGradient(colors: [Color(hue: hue, saturation: 0.7, brightness: 0.45), Color(red: 0.06, green: 0.05, blue: 0.16)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Canvas { ctx, size in
                    // 背景の星環
                    let c = CGPoint(x: size.width * 0.78, y: size.height * 0.5)
                    for k in 1...4 {
                        let r = Double(k) * 34
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 1.4, y: c.y - r * 0.5, width: r * 2.8, height: r)),
                                   with: .color(.white.opacity(0.06)), lineWidth: 1)
                    }
                }
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                            Text(L("注目", "FEATURED"))
                        }
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.gold)
                        Text(MasterText.storeItem(item))
                            .font(Theme.title(22))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(contents.isEmpty ? L("限定コスメのセット", "A set of limited cosmetics")
                                              : L("コスメ \(contents.count) 点のセット", "\(contents.count) cosmetics"))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                        HStack(spacing: 10) {
                            PriceTag(currency: item.currency, amount: EconomyService.price(of: item), size: 16)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.black.opacity(0.4)))
                            if item.purchaseLimit > 1 {
                                Text(L("購入 \(count)/\(item.purchaseLimit)", "Bought \(count)/\(item.purchaseLimit)"))
                                    .font(Theme.body(11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    BundlePreviewView(item: item, size: 120, animated: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 26)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel(L("注目: ", "Featured: ") + MasterText.storeItem(item))
        .accessibilityIdentifier("store_featured_\(item.sku)")
    }
}

// MARK: - 財布

struct StoreWalletPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            walletRow(symbol: "star.circle.fill", color: Theme.gold, label: "Coin", amount: app.profile.starlightCoin)
            walletRow(symbol: "diamond.fill", color: Theme.cyan, label: L("無償 Gem", "Free Gem"), amount: app.profile.freeGem)
            walletRow(symbol: "diamond.fill", color: Color(red: 0.72, green: 0.52, blue: 1.0), label: L("有償 Gem", "Paid Gem"),
                      amount: app.profile.paidGem)
            Spacer(minLength: 0)
            Button {
                app.haptics.tap()
                app.router.push(.currencyStore)
            } label: {
                Label(L("Gem を購入", "Get Gems"), systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
            .frame(minHeight: 44)
            .accessibilityIdentifier("store_get_gems")
            HStack(spacing: 0) {
                smallLink(L("所持品", "Inventory"), symbol: "shippingbox.fill", id: "store_inventory") { app.router.push(.inventory) }
                smallLink(L("復元", "Restore"), symbol: "arrow.clockwise", id: "store_restore") { app.router.push(.restorePurchases) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
    }

    private func walletRow(symbol: String, color: Color, label: String, amount: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(color).frame(width: 16)
            Text(label).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(amount.formatted()).font(Theme.mono(13)).foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func smallLink(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.body(11))
                .foregroundStyle(Theme.cyan)
                .frame(maxWidth: .infinity, minHeight: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

// MARK: - カテゴリタイル・商品カード

struct StoreCategoryTile: View {
    let category: StoreCategory
    let selected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        let navigates = category == .skins || category == .gems
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(category.color.opacity(0.18)).frame(width: 36, height: 36)
                    Image(systemName: category.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(category.color)
                }
                Text(category.title)
                    .font(Theme.heading(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(category.subtitle)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [category.color.opacity(selected ? 0.35 : 0.14), Theme.panel],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? category.color : category.color.opacity(0.3), lineWidth: selected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if navigates {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(category.color)
                        .padding(7)
                } else if count > 0 {
                    Text("\(count)")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(7)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("store_cat_\(category.rawValue)")
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
                    .padding(.top, 6)
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
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.14), Theme.panel], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(owned ? 0.7 : 0.35), lineWidth: 1))
            .opacity(unavailable && !owned ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel("\(MasterText.storeItem(item))、\(owned ? L("所持済み", "Owned") : "\(EconomyService.price(of: item)) \(CollectionStyle.currencyName(item.currency))")")
        .accessibilityIdentifier("product_\(item.sku)")
    }
}
