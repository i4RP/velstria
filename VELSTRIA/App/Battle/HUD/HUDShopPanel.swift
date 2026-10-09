import SwiftUI
import VelstriaCore

// 担当: battle-hud。UI028 戦闘中ショップ（スライドイン）。
// おすすめの購入順（次の購入を強調）・カテゴリタブ（攻撃/魔法/防御/移動 + ジャングル/ロームの祝福）・
// 装備一覧（実コスト/購入不可理由）・詳細（能力値・固有効果・2 段の合成ツリー）・
// 購入（.buyItem、失敗は .purchaseFailed をトーストで通知）・所持品の売却（.sellItem、売却額）・
// 靴への祝福の付与（.setGearOption）・効果中のポーション。死亡中も使える。

struct HUDShopPanel: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let shop = model.shop
        let master = MasterData.shared
        // ジャングル・ロームのタブは装備ではなく靴に付ける祝福を並べる
        let blessingTab = model.shopCategory.flatMap { GearInfo.isBlessingCategory($0) ? $0 : nil }
        VStack(spacing: 0) {
            header(shop)
            Divider().overlay(HUDStyle.rim)
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 8) {
                    if let c = blessingTab {
                        HUDShopBlessings(model: model, shop: shop, category: c)
                    } else {
                        if model.shopCategory == nil {
                            HUDShopRecommended(model: model, shop: shop)
                        }
                        HUDShopGrid(model: model, shop: shop,
                                    items: model.shopCategory.map { HUDShopLogic.items(in: $0, master: master) }
                                        ?? HUDShopLogic.recommendedGridItems(shop.path, master: master))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                Group {
                    // 所持品を選んでいる間は売却の詳細
                    if let c = blessingTab, model.shopSelectedSlot == nil,
                       let option = HUDShopLogic.focusedBlessing(category: c, selected: model.shopSelectedOption, shop: shop) {
                        HUDShopBlessingDetail(model: model, shop: shop, option: option)
                    } else {
                        HUDShopDetail(model: model, shop: shop)
                    }
                }
                .frame(width: min(250, layout.width * 0.3))
            }
            .padding(10)
            Divider().overlay(HUDStyle.rim)
            HUDShopInventory(model: model, shop: shop)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.20).opacity(0.97),
                                              Color(red: 0.03, green: 0.03, blue: 0.09).opacity(0.97)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shop_panel")
    }

    private func header(_ shop: HUDShopState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bag.fill").foregroundStyle(Theme.gold)
            Text(L("ショップ", "Shop"))
                .font(Theme.heading(17))
                .foregroundStyle(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    tab(nil, title: L("おすすめ", "Recommended"), symbol: "star.fill")
                    ForEach(ItemCategory.allCases, id: \.self) { c in
                        tab(c, title: CollectionStyle.categoryName(c), symbol: CollectionStyle.categorySymbol(c))
                    }
                }
                .padding(.horizontal, 4)
            }
            HStack(spacing: 4) {
                HUDCoin(size: 18)
                Text("\(shop.gold)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.gold)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.25), value: shop.gold)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(shop.gold) Gold")
            .accessibilityIdentifier("shop_gold")
            Button { model.closePanel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L("閉じる", "Close"))
            .accessibilityIdentifier("shop_close")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 48)
    }

    private func tab(_ c: ItemCategory?, title: String, symbol: String) -> some View {
        let selected = model.shopCategory == c
        let color = c.map { CollectionStyle.categoryColor($0) } ?? Theme.gold
        return Button {
            model.shopCategory = c
            // 祝福のタブでは祝福の詳細を出す（所持品の売却の選択は解く）
            if let c, GearInfo.isBlessingCategory(c) { model.shopSelectedSlot = nil }
            model.selectionFeedback()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(selected ? Color.black : color)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(selected ? color : Color.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(color.opacity(selected ? 0 : 0.5), lineWidth: 1))
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shop_tab_\(c?.rawValue.lowercased() ?? "recommended")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// おすすめの購入順（次の購入を強調）。
struct HUDShopRecommended: View {
    let model: HUDModel
    let shop: HUDShopState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("おすすめの購入順", "Recommended Build"))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
                Spacer()
                if let next = shop.next, let item = MasterData.shared.item(next) {
                    Text(L("次: \(MasterText.item(item))", "Next: \(MasterText.item(item))"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(shop.path) { step in
                        if step.id > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        pathTile(step)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func pathTile(_ step: HUDShopPathStep) -> some View {
        let selected = model.shopSelectedItemID == step.itemID && model.shopSelectedSlot == nil
        return Button {
            model.shopSelectedItemID = step.itemID
            model.shopSelectedSlot = nil
            model.selectionFeedback()
        } label: {
            ZStack(alignment: .topTrailing) {
                if let item = MasterData.shared.item(step.itemID) {
                    ItemIconView(item: item, size: 44)
                        .opacity(step.owned ? 0.55 : 1)
                }
                if step.owned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.success)
                        .background(Circle().fill(Color.black))
                        .offset(x: 4, y: -4)
                } else if step.isNext || step.isGoal {
                    Text(step.isNext ? L("次", "NEXT") : L("目標", "GOAL"))
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(step.isNext ? Theme.gold : Theme.cyan))
                        .offset(x: 6, y: -6)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.white : (step.isNext ? Theme.gold : Color.clear), lineWidth: selected ? 2 : 1.5))
            .shadow(color: step.isNext ? Theme.gold.opacity(0.7) : .clear, radius: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(MasterData.shared.item(step.itemID).map { MasterText.item($0) } ?? step.itemID)
        .accessibilityValue(step.owned ? L("所持済み", "Owned") : (step.isNext ? L("次のおすすめ", "Next recommended") : ""))
        .accessibilityIdentifier(step.isNext ? "shop_next" : "shop_path_\(step.id)")
    }
}

/// カテゴリの装備一覧。
struct HUDShopGrid: View {
    let model: HUDModel
    let shop: HUDShopState
    let items: [ItemDef]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 6)], spacing: 6) {
                ForEach(items) { item in
                    cell(item)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func cell(_ item: ItemDef) -> some View {
        let entry = shop.entry(item.itemID)
        let selected = model.shopSelectedItemID == item.itemID && model.shopSelectedSlot == nil
        let isNext = shop.next == item.itemID
        let affordable = entry?.canBuy ?? false
        return Button {
            model.shopSelectedItemID = item.itemID
            model.shopSelectedSlot = nil
            model.selectionFeedback()
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    ItemIconView(item: item, size: 40)
                    if (entry?.ownedCount ?? 0) > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.success)
                            .background(Circle().fill(Color.black))
                            .offset(x: 4, y: -4)
                    }
                }
                Text(MasterText.item(item))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 2) {
                    HUDCoin(size: 10)
                    Text("\(entry?.cost ?? Int(item.priceGold))")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(affordable ? Theme.gold : (entry?.failure == .notEnoughGold ? Theme.danger : .white.opacity(0.45)))
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.white : (isNext ? Theme.gold : Color.white.opacity(0.08)),
                              lineWidth: selected || isNext ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(MasterText.item(item))
        .accessibilityValue("\(entry?.cost ?? Int(item.priceGold)) Gold")
        .accessibilityIdentifier("shop_item_\(item.itemID)")
    }
}

/// 選択中の装備の詳細と購入ボタン（所持品を選んでいる場合は売却）。
struct HUDShopDetail: View {
    let model: HUDModel
    let shop: HUDShopState

    var body: some View {
        let master = MasterData.shared
        VStack(alignment: .leading, spacing: 6) {
            if let itemID = model.shopSelectedItemID, let item = master.item(itemID) {
                HStack(spacing: 8) {
                    ItemIconView(item: item, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MasterText.item(item))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text("\(CollectionStyle.categoryName(item.category)) · \(CollectionStyle.tierName(item.tier))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(CollectionStyle.categoryColor(item.category))
                    }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ItemMath.statLines(item)) { line in
                            HStack(spacing: 4) {
                                Image(systemName: line.symbol).font(.system(size: 9, weight: .bold)).frame(width: 12)
                                Text(line.label).lineLimit(1).minimumScaleFactor(0.7)
                                Spacer()
                                Text(line.value).monospacedDigit().foregroundStyle(Theme.success)
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                        }
                        let passive = ItemMath.passiveEffectText(item)
                        if !passive.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ItemMath.passiveName(item) ?? L("パッシブ", "Passive"))
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.gold)
                                Text(passive)
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 2)
                        }
                        if let note = ItemMath.consumableText(item) {
                            Text(note)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.cyan)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if item.isBoots {
                            // 靴にはジャングル・ロームの祝福を付けられる（ショップの祝福のタブ）
                            Text(shop.gearOption.map { L("祝福: \(GearInfo.name($0))", "Blessing: \(GearInfo.name($0))") }
                                 ?? L("ジャングル・ロームのタブから祝福を付けられます", "Add a blessing from the Jungle or Roam tab"))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.success)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HUDShopRecipeTree(model: model, shop: shop, item: item)
                    }
                }
                Spacer(minLength: 0)
                actionArea(item)
            } else {
                Text(L("装備を選んでください", "Select an item"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    @ViewBuilder
    private func actionArea(_ item: ItemDef) -> some View {
        if let slot = model.shopSelectedSlot, slot < shop.items.count, shop.items[slot] == item.itemID {
            let value = slot < shop.sellValues.count ? shop.sellValues[slot] : 0
            Button { model.sell(slot: slot) } label: {
                Label(L("売却 +\(value)", "Sell +\(value)"), systemImage: "cart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.danger))
            .accessibilityIdentifier("shop_sell")
        } else {
            let entry = shop.entry(item.itemID)
            let cost = entry?.cost ?? Int(item.priceGold)
            let discounted = cost < Int(item.priceGold)
            VStack(spacing: 4) {
                if let reason = HUDShopLogic.failureText(entry?.failure) {
                    Text(reason)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.danger)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if discounted {
                    Text(L("合成割引 −\(Int(item.priceGold) - cost)", "Combine discount −\(Int(item.priceGold) - cost)"))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.success)
                        .frame(maxWidth: .infinity)
                }
                Button { model.buy(item.itemID) } label: {
                    HStack(spacing: 5) {
                        Text(item.isConsumable ? L("購入して使う", "Buy & Use") : L("購入", "Buy"))
                        HUDCoin(size: 14)
                        Text("\(cost)").monospacedDigit()
                        if discounted {
                            Text("\(Int(item.priceGold))")
                                .strikethrough()
                                .font(.system(size: 11, weight: .bold))
                                .opacity(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(color: entry?.canBuy == true ? Theme.gold : Color.gray))
                .accessibilityIdentifier("shop_buy")
            }
        }
    }
}

/// 合成ツリー（素材 → 素材の素材の 2 段。価格と所持の印付き。タップでその装備を選ぶ）。
struct HUDShopRecipeTree: View {
    let model: HUDModel
    let shop: HUDShopState
    let item: ItemDef

    var body: some View {
        let tree = ItemMath.recipeTree(item, master: MasterData.shared)
        if !tree.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("素材", "Components"))
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                ForEach(tree) { node in
                    row(node.item, iconSize: 24, nested: false)
                    ForEach(node.children) { child in
                        row(child.item, iconSize: 18, nested: true)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func row(_ part: ItemDef, iconSize: CGFloat, nested: Bool) -> some View {
        let owned = shop.items.contains(part.itemID)
        return Button {
            model.shopSelectedItemID = part.itemID
            model.shopSelectedSlot = nil
            model.selectionFeedback()
        } label: {
            HStack(spacing: 4) {
                if nested {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.leading, 6)
                }
                ItemIconView(item: part, size: iconSize)
                Text(MasterText.item(part))
                    .font(.system(size: nested ? 9.5 : 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(nested ? 0.7 : 0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if owned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.success)
                }
                HUDCoin(size: 9)
                Text("\(Int(part.priceGold))")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.gold.opacity(nested ? 0.75 : 1))
            }
            .frame(minHeight: nested ? 24 : 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MasterText.item(part))
        .accessibilityValue("\(Int(part.priceGold)) Gold" + (owned ? L("、所持済み", ", owned") : ""))
    }
}

/// ジャングル・ロームのタブ: 靴に付ける祝福のカード（付けられるか・費用・付いている祝福の印）と進み具合。
struct HUDShopBlessings: View {
    let model: HUDModel
    let shop: HUDShopState
    let category: ItemCategory

    var body: some View {
        let cards = HUDShopLogic.blessings(in: category, shop: shop)
        let focused = HUDShopLogic.focusedBlessing(category: category, selected: model.shopSelectedOption, shop: shop)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: CollectionStyle.categorySymbol(category))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CollectionStyle.categoryColor(category))
                Text(HUDShopLogic.blessingProgressText(category, shop: shop) ?? "")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(L("靴に付ける（0 Gold・装備枠を使わない）", "Goes on your boots (0 Gold, no slot)"))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("shop_blessing_progress")
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 6)], spacing: 6) {
                    ForEach(cards) { card in
                        cardView(card, selected: card.option == focused)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func cardView(_ card: HUDBlessingCard, selected: Bool) -> some View {
        let color = CollectionStyle.categoryColor(card.option.category)
        let reason = HUDShopLogic.failureText(card.failure)
        let cost = HUDShopLogic.blessingCostText(card, master: .shared)
        return Button {
            model.shopSelectedOption = card.option
            model.shopSelectedSlot = nil
            model.selectionFeedback()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(0.22))
                    Image(systemName: GearInfo.symbol(card.option))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(color)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(GearInfo.name(card.option))
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if card.isCurrent {
                            Text(L("付与中", "ON"))
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.success))
                        }
                    }
                    Text(GearInfo.short(card.option))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let reason, !card.isCurrent {
                        Text(reason)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.danger)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !card.isCurrent {
                        HStack(spacing: 2) {
                            HUDCoin(size: 10)
                            Text(cost)
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.gold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.white : (card.isCurrent ? Theme.success : Color.white.opacity(0.08)),
                              lineWidth: selected || card.isCurrent ? 1.5 : 1))
            .opacity(reason == nil || card.isCurrent ? 1 : 0.7)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(GearInfo.name(card.option))
        .accessibilityValue(card.isCurrent ? L("付与中", "Attached") : (reason ?? "\(cost) Gold"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("shop_gear_\(card.option.rawValue)")
    }
}

/// 選んだ祝福の詳細（効果・ルール・進み具合）と「付与」「付け替え」ボタン（.setGearOption。靴が無ければ一緒に買う）。
struct HUDShopBlessingDetail: View {
    let model: HUDModel
    let shop: HUDShopState
    let option: GearOption

    var body: some View {
        let card = shop.blessing(option) ?? HUDBlessingCard(option: option, cost: 0, failure: nil, isCurrent: false)
        let color = CollectionStyle.categoryColor(option.category)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(0.22))
                    Image(systemName: GearInfo.symbol(option))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(color)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GearInfo.name(option))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(L("\(CollectionStyle.categoryName(option.category))の祝福", "\(CollectionStyle.categoryName(option.category)) blessing"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if let progress = HUDShopLogic.blessingProgressText(option.category, shop: shop) {
                        Text(progress)
                            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.success)
                    }
                    // 1 行目は祝福の効果、2 行目からはルール
                    ForEach(Array(GearInfo.details(option).enumerated()), id: \.offset) { k, line in
                        let lead = k == 0
                        Text(lead ? line : "・" + line)
                            .font(.system(size: lead ? 11 : 10, weight: lead ? Font.Weight.semibold : Font.Weight.medium,
                                          design: .rounded))
                            .foregroundStyle(.white.opacity(lead ? 0.9 : 0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                if let reason = HUDShopLogic.failureText(card.failure), !card.isCurrent {
                    Text(reason)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.danger)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if card.cost > 0 && !card.isCurrent {
                    Text(L("靴が無いので一緒に買います", "Boots will be bought with it"))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
                Button { model.setGearOption(option) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: card.isCurrent ? "checkmark" : GearInfo.symbol(option))
                        Text(HUDShopLogic.blessingActionTitle(card, current: shop.gearOption))
                        if card.cost > 0 && !card.isCurrent {
                            HUDCoin(size: 14)
                            Text("\(card.cost)").monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(color: card.canApply ? Theme.gold : Color.gray))
                .disabled(card.isCurrent)
                .accessibilityIdentifier("shop_gear_apply")
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

/// 所持品（選ぶと売却できる）。
struct HUDShopInventory: View {
    let model: HUDModel
    let shop: HUDShopState

    var body: some View {
        HStack(spacing: 8) {
            Text(L("所持品", "Inventory"))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 4) {
                ForEach(0..<Balance.itemSlots, id: \.self) { k in
                    let selected = model.shopSelectedSlot == k
                    Button {
                        guard k < shop.items.count else { return }
                        model.shopSelectedSlot = k
                        model.shopSelectedItemID = shop.items[k]
                        model.selectionFeedback()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.45))
                            if k < shop.items.count, let item = MasterData.shared.item(shop.items[k]) {
                                ItemIconView(item: item, size: 38)
                                    .overlay(alignment: .topTrailing) {
                                        // 靴に付いている祝福の印
                                        if item.isBoots, let option = shop.gearOption {
                                            Image(systemName: GearInfo.symbol(option))
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.black)
                                                .frame(width: 15, height: 15)
                                                .background(Circle().fill(CollectionStyle.categoryColor(option.category)))
                                                .offset(x: 4, y: -4)
                                        }
                                    }
                            } else {
                                Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(.white.opacity(0.2))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? Theme.danger : Color.white.opacity(0.15), lineWidth: selected ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HUDPressStyle())
                    .accessibilityLabel(k < shop.items.count ? (MasterData.shared.item(shop.items[k]).map { MasterText.item($0) } ?? "")
                                                             : L("空きスロット", "Empty slot"))
                    .accessibilityIdentifier("shop_slot_\(k + 1)")
                }
            }
            // 効果中のポーション（所持枠を使わない）と残り秒数
            if let potion = model.itemActives.potion, let item = MasterData.shared.item(potion.itemID) {
                HStack(spacing: 4) {
                    ItemIconView(item: item, size: 30)
                    Text(L("残り \(potion.remaining) 秒", "\(potion.remaining)s"))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.cyan)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .frame(height: 38)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(MasterText.item(item))
                .accessibilityValue(L("残り \(potion.remaining) 秒", "\(potion.remaining) seconds left"))
                .accessibilityIdentifier("shop_potion")
            }
            Spacer()
            if let slot = model.shopSelectedSlot, slot < shop.sellValues.count {
                Text(L("売却額 \(shop.sellValues[slot]) Gold（投資額の 60%）", "Sells for \(shop.sellValues[slot]) gold (60% of cost)"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(L("所持品を選ぶと売却できます", "Select an owned item to sell it"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
