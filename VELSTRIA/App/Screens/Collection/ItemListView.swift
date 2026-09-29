import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI040 装備一覧（カテゴリ 6 種 + Tier フィルタ）。

struct ItemListView: View {
    @Environment(AppModel.self) private var app
    @State private var category: ItemCategory?
    @State private var tier: Int?

    private let columns = [GridItem(.adaptive(minimum: 176), spacing: 8)]

    var body: some View {
        let items = ItemMath.filtered(app.master.items, category: category, tier: tier)
        ScreenScaffold(title: L("装備", "Items")) {
            HStack(alignment: .top, spacing: 12) {
                ItemCategoryRail(selection: $category)
                    .frame(width: 128)
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        Text(category.map(CollectionStyle.categoryName) ?? L("すべての装備", "All Items"))
                            .font(Theme.heading(15))
                            .foregroundStyle(Theme.textPrimary)
                        Text(L("\(items.count) 件", "\(items.count) items"))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        ItemTierPicker(tier: $tier)
                    }
                    ScrollView {
                        if items.isEmpty {
                            CollectionEmptyState(symbol: "shippingbox", title: L("該当する装備がありません", "No items match"))
                        } else {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(items) { item in
                                    ItemListCell(item: item)
                                }
                            }
                            .padding(.bottom, 12)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .animation(.easeInOut(duration: 0.2), value: category)
                    .animation(.easeInOut(duration: 0.2), value: tier)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

/// 左側のカテゴリ切替（縦並び）。
struct ItemCategoryRail: View {
    @Binding var selection: ItemCategory?
    var includesAll = true

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                if includesAll {
                    railButton(title: L("すべて", "All"), symbol: "square.grid.2x2.fill", color: Theme.cyan,
                               selected: selection == nil, id: "all") { selection = nil }
                }
                ForEach(ItemCategory.allCases, id: \.self) { c in
                    railButton(title: CollectionStyle.categoryName(c), symbol: CollectionStyle.categorySymbol(c),
                               color: CollectionStyle.categoryColor(c), selected: selection == c, id: c.rawValue) {
                        selection = c
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func railButton(title: String, symbol: String, color: Color, selected: Bool, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? Color.black.opacity(0.85) : color)
                    .frame(width: 18)
                Text(title)
                    .font(Theme.body(13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? AnyShapeStyle(color) : AnyShapeStyle(Color.white.opacity(0.06)))
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(color.opacity(selected ? 0 : 0.3), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("items_category_\(id)")
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// Tier フィルタ。
struct ItemTierPicker: View {
    @Binding var tier: Int?

    var body: some View {
        Picker(L("ティア", "Tier"), selection: $tier) {
            Text(L("全Tier", "All")).tag(Int?.none)
            ForEach([1, 2, 3], id: \.self) { t in
                Text("T\(t)").tag(Int?.some(t))
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .accessibilityIdentifier("items_tier_filter")
    }
}

/// 一覧セル。
struct ItemListCell: View {
    let item: ItemDef
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.haptics.tap()
            app.router.push(.itemDetail(item.itemID))
        } label: {
            HStack(spacing: 9) {
                ItemIconView(item: item, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(MasterText.item(item))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let stat = ItemMath.primaryStat(item) {
                        Text("\(stat.label) \(stat.value)")
                            .font(Theme.body(11))
                            .foregroundStyle(CollectionStyle.categoryColor(item.category))
                            .lineLimit(1)
                    } else {
                        Text(ItemMath.passiveEffectText(item))
                            .font(Theme.body(11))
                            .foregroundStyle(CollectionStyle.categoryColor(item.category))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    HStack(spacing: 6) {
                        GoldPriceLabel(amount: item.priceGold, size: 11)
                        Text("T\(item.tier)")
                            .font(Theme.mono(10))
                            .foregroundStyle(CollectionStyle.tierColor(item.tier))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(minHeight: 62)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CollectionStyle.tierColor(item.tier).opacity(item.tier >= 3 ? 0.5 : 0.2), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel("\(MasterText.item(item))、\(CollectionStyle.categoryName(item.category))、\(Int(item.priceGold)) G")
        .accessibilityIdentifier("item_\(item.itemID)")
    }
}
