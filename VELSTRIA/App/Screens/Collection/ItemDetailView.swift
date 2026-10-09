import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI041 装備詳細（能力値・固有パッシブ・合成ツリー）。

struct ItemDetailView: View {
    let itemID: String
    @Environment(AppModel.self) private var app

    var body: some View {
        ScreenScaffold(title: L("装備詳細", "Item Details")) {
            if let item = app.master.item(itemID) {
                HStack(alignment: .top, spacing: 14) {
                    ScrollView {
                        ItemSummaryPanel(item: item)
                            .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: 300)
                    ScrollView {
                        ItemBuildTreePanel(item: item)
                            .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, 20)
            } else {
                CollectionEmptyState(symbol: "questionmark.circle", title: L("装備が見つかりません", "Item not found"))
            }
        }
    }
}

private struct ItemSummaryPanel: View {
    let item: ItemDef
    @Environment(AppModel.self) private var app

    var body: some View {
        let color = CollectionStyle.categoryColor(item.category)
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ItemIconView(item: item, size: 70)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(MasterText.item(item))
                            .font(Theme.heading(17))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        HStack(spacing: 5) {
                            CollectionInfoTag(text: CollectionStyle.categoryName(item.category),
                                              symbol: CollectionStyle.categorySymbol(item.category), color: color)
                            CollectionInfoTag(text: CollectionStyle.tierName(item.tier), symbol: "diamond.fill",
                                              color: CollectionStyle.tierColor(item.tier))
                        }
                        if let tag = ItemMath.tag(item) {
                            Text(tag)
                                .font(Theme.body(11))
                                .foregroundStyle(color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                HStack(spacing: 14) {
                    priceBlock(title: L("合計価格", "Total"), amount: item.priceGold)
                    if !item.buildFrom.isEmpty {
                        priceBlock(title: L("合成コスト", "Combine"), amount: ItemMath.combineCost(item, master: app.master))
                    }
                    Spacer(minLength: 0)
                }
                let stats = ItemMath.statLines(item)
                if !stats.isEmpty {
                    VStack(spacing: 5) {
                        ForEach(stats) { line in
                            HStack {
                                Image(systemName: line.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(color).frame(width: 16)
                                Text(line.label).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(line.value).font(Theme.mono(13)).foregroundStyle(Theme.textPrimary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25)))
                }
                VStack(alignment: .leading, spacing: 4) {
                    let passive = ItemMath.passiveEffectText(item)
                    if !passive.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkle").foregroundStyle(Theme.gold)
                            Text(L("固有パッシブ", "Unique Passive"))
                                .font(Theme.body(11))
                                .foregroundStyle(Theme.gold)
                        }
                        if let name = ItemMath.passiveName(item) {
                            Text(name)
                                .font(Theme.heading(13))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(passive)
                            .font(Theme.body(13))
                            .foregroundStyle(color)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("同名の固有パッシブは重複しません。", "Unique passives with the same name do not stack."))
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if !item.alsoIn.isEmpty {
                        let tabs = item.alsoIn.map(CollectionStyle.categoryName).joined(separator: L("・", ", "))
                        Label(L("\(tabs)のタブにも並びます", "Also listed under \(tabs)"), systemImage: "square.grid.2x2")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let note = ItemMath.consumableText(item) {
                        Label(note, systemImage: "flask.fill")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.cyan)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if item.isBoots {
                        Label(L("靴は 1 足まで。試合中にショップのジャングル・ロームのタブから、靴に祝福を付けられます",
                                "One pair of boots only. During a match, add a blessing to your boots from the shop's Jungle or Roam tab"),
                              systemImage: "shoeprints.fill")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func priceBlock(title: String, amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
            GoldPriceLabel(amount: amount, size: 15)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 合成ツリー（上位装備 → この装備 → 素材 → 素材の素材）。
private struct ItemBuildTreePanel: View {
    let item: ItemDef
    @Environment(AppModel.self) private var app

    /// 素材の列の幅と間隔。素材 3 個までは 3×104 + 2×14 = 340pt、4 個は 4×88 + 3×8 = 376pt に収める
    /// （右の列は画面幅 − 一覧 300 − 余白。収まらない画面では横にスクロールする）。
    private func columns(_ count: Int) -> (width: CGFloat, spacing: CGFloat) {
        count >= 4 ? (88, 8) : (104, 14)
    }

    var body: some View {
        let tree = ItemMath.recipeTree(item, master: app.master)
        let parents = ItemMath.buildsInto(item.itemID, master: app.master)
        Panel(padding: 12) {
            VStack(spacing: 8) {
                CollectionSectionTitle(title: L("合成ツリー", "Build Path"), symbol: "point.3.connected.trianglepath.dotted")
                // 上位装備
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("この装備から作れる装備（\(parents.count)）", "Builds into (\(parents.count))"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                    if parents.isEmpty {
                        Text(L("最上位の装備です", "This is a final item"))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary.opacity(0.8))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(parents) { p in
                                    ItemTreeNode(item: p, compact: true)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                if !parents.isEmpty {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                // この装備
                VStack(spacing: 3) {
                    ItemIconView(item: item, size: 54)
                        .shadow(color: CollectionStyle.categoryColor(item.category).opacity(0.6), radius: 8)
                    Text(MasterText.item(item))
                        .font(Theme.heading(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    GoldPriceLabel(amount: item.priceGold, size: 11)
                }
                // 素材（2 段: 素材の下にその素材）
                if tree.isEmpty {
                    Text(L("基本装備（素材なし）", "Basic item (no components)"))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                } else {
                    ViewThatFits(in: .horizontal) {
                        componentRows(tree)
                        ScrollView(.horizontal) {
                            componentRows(tree)
                        }
                        .scrollIndicators(.hidden)
                    }
                    let partsTotal = tree.reduce(0) { $0 + $1.item.priceGold }
                    HStack(spacing: 6) {
                        Text(L("素材合計", "Components")).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                        GoldPriceLabel(amount: partsTotal, size: 11)
                        Text("+").foregroundStyle(Theme.textSecondary)
                        Text(L("合成", "Combine")).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                        GoldPriceLabel(amount: ItemMath.combineCost(item, master: app.master), size: 11)
                    }
                    .padding(.top, 2)
                    Text(combineRuleText)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 合成コストの決まり（下限の割合は Balance.minCombineCostRatio。0 なら価格 − 持っている素材の価格）。
    private var combineRuleText: String {
        let floor = Int((Balance.minCombineCostRatio * 100).rounded())
        if floor > 0 {
            return L("合成コスト = max(価格×\(floor)%, 価格 − 持っている素材の価格)。素材の素材を持っていればその分も引かれる",
                     "Combine cost = max(\(floor)% of price, price − owned components), including components of components")
        }
        return L("合成コスト = 価格 − 持っている素材の価格（素材の素材を持っていればその分も引かれる）",
                 "Combine cost = price − owned components (components of components count too)")
    }

    /// 素材の列（接続線 → 素材 → その素材）。
    private func componentRows(_ tree: [ItemRecipeNode]) -> some View {
        let (width, spacing) = columns(tree.count)
        return VStack(spacing: 0) {
            ItemTreeConnector(count: tree.count, childWidth: width, spacing: spacing)
                .stroke(Theme.gold.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: CGFloat(tree.count) * width + CGFloat(tree.count - 1) * spacing, height: 22)
            HStack(alignment: .top, spacing: spacing) {
                ForEach(tree) { node in
                    VStack(spacing: 4) {
                        ItemTreeNode(item: node.item, compact: false, textWidth: width - 10)
                        if !node.children.isEmpty {
                            Rectangle()
                                .fill(Theme.gold.opacity(0.45))
                                .frame(width: 1.5, height: 8)
                            VStack(spacing: 3) {
                                ForEach(node.children) { child in
                                    ItemTreeLeaf(item: child.item)
                                }
                            }
                        }
                    }
                    .frame(width: width)
                }
            }
        }
    }
}

/// 合成ツリーの 2 段目（素材の素材）。小さなアイコンと価格（タップでその装備の詳細へ）。
private struct ItemTreeLeaf: View {
    let item: ItemDef
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.haptics.tap()
            app.router.push(.itemDetail(item.itemID))
        } label: {
            HStack(spacing: 4) {
                ItemIconView(item: item, size: 28)
                GoldPriceLabel(amount: item.priceGold, size: 9)
            }
            .padding(.horizontal, 4)
            .frame(minWidth: 44, minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel(MasterText.item(item))
        .accessibilityValue("\(Int(item.priceGold)) G")
        .accessibilityIdentifier("itemtree_\(item.itemID)")
    }
}

/// ツリーの 1 ノード（タップでその装備の詳細へ）。
private struct ItemTreeNode: View {
    let item: ItemDef
    let compact: Bool
    /// 名前の幅（素材 4 個の列は狭い）。nil なら compact で決まる。
    var textWidth: CGFloat?
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.haptics.tap()
            app.router.push(.itemDetail(item.itemID))
        } label: {
            VStack(spacing: 3) {
                ItemIconView(item: item, size: compact ? 38 : 46)
                Text(MasterText.item(item))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(compact ? 1 : 2)
                    .multilineTextAlignment(.center)
                    .frame(width: textWidth ?? (compact ? 78 : 96))
                GoldPriceLabel(amount: item.priceGold, size: 10)
            }
            .padding(5)
            .frame(minWidth: 44, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel(MasterText.item(item))
        .accessibilityIdentifier("itemtree_\(item.itemID)")
    }
}

/// 親 1 → 子 n の括弧型の接続線。
struct ItemTreeConnector: Shape {
    let count: Int
    let childWidth: CGFloat
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.height / 2
        p.move(to: CGPoint(x: rect.midX, y: 0))
        p.addLine(to: CGPoint(x: rect.midX, y: midY))
        guard count > 0 else { return p }
        let centers = (0..<count).map { CGFloat($0) * (childWidth + spacing) + childWidth / 2 }
        if let first = centers.first, let last = centers.last, count > 1 {
            p.move(to: CGPoint(x: first, y: midY))
            p.addLine(to: CGPoint(x: last, y: midY))
        }
        for x in centers {
            p.move(to: CGPoint(x: x, y: midY))
            p.addLine(to: CGPoint(x: x, y: rect.height))
        }
        return p
    }
}
