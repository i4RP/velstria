import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI040 装備一覧（攻撃・魔法・防御・移動 + Tier フィルタ）と、
// ジャングル・ロームのタブ（装備ではなく靴に付ける祝福の一覧と説明）。

struct ItemListView: View {
    @Environment(AppModel.self) private var app
    @State private var category: ItemCategory?
    @State private var tier: Int?

    private let columns = [GridItem(.adaptive(minimum: 176), spacing: 8)]
    private let blessingColumns = [GridItem(.adaptive(minimum: 250), spacing: 8)]

    var body: some View {
        // ジャングル・ロームのタブは祝福を並べる（Tier は無い）
        let blessingTab = category.flatMap { GearInfo.isBlessingCategory($0) ? $0 : nil }
        let items = blessingTab == nil ? ItemMath.filtered(app.master.items, category: category, tier: tier) : []
        let options = blessingTab.map { GearOption.options(for: $0) } ?? []
        ScreenScaffold(title: L("装備", "Items")) {
            HStack(alignment: .top, spacing: 12) {
                ItemCategoryRail(selection: $category)
                    .frame(width: 128)
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        Text(category.map(CollectionStyle.categoryName) ?? L("すべての装備", "All Items"))
                            .font(Theme.heading(15))
                            .foregroundStyle(Theme.textPrimary)
                        Text(blessingTab == nil ? L("\(items.count) 件", "\(items.count) items")
                                                : L("祝福 \(options.count) 種", "\(options.count) blessings"))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        if blessingTab == nil {
                            ItemTierPicker(tier: $tier)
                        }
                    }
                    .frame(minHeight: 32)
                    ScrollView {
                        if let c = blessingTab {
                            VStack(spacing: 8) {
                                LazyVGrid(columns: blessingColumns, spacing: 8) {
                                    ForEach(options, id: \.self) { option in
                                        BlessingInfoCard(option: option)
                                    }
                                }
                                BlessingRulesPanel(category: c)
                            }
                            .padding(.bottom, 12)
                        } else if items.isEmpty {
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
                    // 短い説明（「攻撃範囲増加」など。無ければ主要能力）
                    Text(ItemMath.caption(item))
                        .font(Theme.body(11))
                        .foregroundStyle(CollectionStyle.categoryColor(item.category))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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

/// 図鑑のジャングル・ロームのタブ: 祝福 1 つの名前・短い効果・効果の全文。
struct BlessingInfoCard: View {
    let option: GearOption

    var body: some View {
        let color = CollectionStyle.categoryColor(option.category)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(color.opacity(0.22))
                    Image(systemName: GearInfo.symbol(option))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(color)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GearInfo.name(option))
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(GearInfo.short(option))
                        .font(Theme.body(11))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            Text(GearInfo.summary(option))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blessing_\(option.rawValue)")
    }
}

/// 図鑑のジャングル・ロームのタブ: 祝福の種類ごとのルールと、付け方の決まり。
struct BlessingRulesPanel: View {
    let category: ItemCategory

    var body: some View {
        let color = CollectionStyle.categoryColor(category)
        VStack(alignment: .leading, spacing: 5) {
            CollectionSectionTitle(title: L("\(CollectionStyle.categoryName(category))の祝福のルール",
                                            "\(CollectionStyle.categoryName(category)) blessing rules"),
                                   symbol: CollectionStyle.categorySymbol(category))
            ForEach(Array((GearInfo.rules(category) + GearInfo.commonRules).enumerated()), id: \.offset) { _, rule in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(color).frame(width: 5, height: 5).padding(.top, 6)
                    Text(rule)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.25)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blessing_rules")
    }
}
