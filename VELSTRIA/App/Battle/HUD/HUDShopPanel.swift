import SwiftUI
import VelstriaCore

// 担当: battle-hud。UI028 戦闘中ショップ（スライドイン）。
// おすすめの購入順（次の購入を強調）・カテゴリタブ・装備一覧（実コスト/購入不可理由）・詳細（能力値・パッシブ・素材）・
// 購入（.buyItem、失敗は .purchaseFailed をトーストで通知）・所持品の売却（.sellItem、売却額）。死亡中も使える。

struct HUDShopPanel: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let shop = model.shop
        let master = MasterData.shared
        VStack(spacing: 0) {
            header(shop)
            Divider().overlay(HUDStyle.rim)
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 8) {
                    if model.shopCategory == nil {
                        HUDShopRecommended(model: model, shop: shop)
                    }
                    HUDShopGrid(model: model, shop: shop,
                                items: model.shopCategory.map { HUDShopLogic.items(in: $0, master: master) }
                                    ?? HUDShopLogic.recommendedGridItems(shop.path, master: master))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                HUDShopDetail(model: model, shop: shop)
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
                                Text(line.label)
                                Spacer()
                                Text(line.value).monospacedDigit().foregroundStyle(Theme.success)
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            // マスターのパッシブ名は日本語のみなので英語表示では汎用名にする
                            Text(item.passiveName.isEmpty || Loc.isEnglish ? L("パッシブ", "Passive") : item.passiveName)
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.gold)
                            Text(ItemMath.passiveEffectText(item))
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 2)
                        let parts = ItemMath.components(item, master: master)
                        if !parts.isEmpty {
                            HStack(spacing: 4) {
                                Text(L("素材", "Components"))
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                                    Button {
                                        model.shopSelectedItemID = part.itemID
                                        model.shopSelectedSlot = nil
                                    } label: {
                                        ItemIconView(item: part, size: 26)
                                            .overlay(alignment: .topTrailing) {
                                                if shop.items.contains(part.itemID) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundStyle(Theme.success)
                                                        .background(Circle().fill(Color.black))
                                                }
                                            }
                                            .frame(width: 32, height: 32)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(MasterText.item(part))
                                }
                            }
                        }
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
                        Text(L("購入", "Buy"))
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
