import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI057 インベントリ（通貨内訳・所持ヒーロー・種類別コスメ）。

enum InventoryTab: String, CaseIterable, Identifiable {
    case heroes, heroSkin, recall, spawn, killEffect, emote, avatarFrame
    var id: String { rawValue }

    var cosmeticType: CosmeticType? {
        switch self {
        case .heroes: return nil
        case .heroSkin: return .heroSkin
        case .recall: return .recall
        case .spawn: return .spawn
        case .killEffect: return .killEffect
        case .emote: return .emote
        case .avatarFrame: return .avatarFrame
        }
    }

    var title: String {
        cosmeticType.map(CollectionStyle.cosmeticTypeName) ?? L("ヒーロー", "Heroes")
    }

    var symbol: String {
        cosmeticType.map(CollectionStyle.cosmeticTypeSymbol) ?? "person.2.fill"
    }
}

struct InventoryView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: InventoryTab = .heroes

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        ScreenScaffold(title: L("インベントリ", "Inventory"), showsCurrencies: false) {
            VStack(spacing: 6) {
                currencyRow
                tabBar
                ScrollView {
                    content
                        .padding(.bottom, 12)
                        .id(tab)
                        .transition(.opacity)
                }
                .scrollIndicators(.hidden)
                .animation(.easeInOut(duration: 0.2), value: tab)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: 通貨

    private var currencyRow: some View {
        HStack(spacing: 8) {
            currencyCard(title: "StarlightCoin", symbol: "star.circle.fill", color: Theme.gold, amount: app.profile.starlightCoin,
                         note: L("プレイ報酬", "Play rewards"))
            currencyCard(title: L("AstralGem（無償）", "AstralGem (Free)"), symbol: "diamond.fill", color: Theme.cyan,
                         amount: app.profile.freeGem, note: L("報酬で獲得・先に消費", "From rewards, spent first"))
            currencyCard(title: L("AstralGem（有償）", "AstralGem (Paid)"), symbol: "diamond.fill",
                         color: Color(red: 0.72, green: 0.52, blue: 1.0), amount: app.profile.paidGem,
                         note: L("購入分", "Purchased"))
            currencyCard(title: L("Gem 合計", "Total Gems"), symbol: "sum", color: Theme.textPrimary, amount: app.profile.totalGem,
                         note: nil)
        }
    }

    private func currencyCard(title: String, symbol: String, color: Color, amount: Int, note: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.body(10)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                Text(amount.formatted()).font(Theme.mono(15)).foregroundStyle(Theme.textPrimary).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let note {
                    Text(note).font(Theme.body(9)).foregroundStyle(Theme.textSecondary.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: タブ

    private func counts(_ t: InventoryTab) -> (owned: Int, total: Int) {
        guard let type = t.cosmeticType else {
            return (app.master.heroes.filter { app.owns(heroID: $0.heroID) }.count, app.master.heroes.count)
        }
        let all = app.master.cosmetics.filter { $0.type == type }
        return (all.filter { app.owns(cosmeticID: $0.cosmeticID) }.count, all.count)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(InventoryTab.allCases) { t in
                        let c = counts(t)
                        CollectionFilterChip(title: "\(t.title) \(c.owned)/\(c.total)", symbol: t.symbol, color: Theme.cyan,
                                             isSelected: tab == t) { tab = t }
                            .accessibilityIdentifier("inventory_tab_\(t.rawValue)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            Button {
                app.router.push(tab == .emote ? .emotes : .cosmetics)
            } label: {
                Label(tab == .emote ? L("エモート設定", "Emotes") : L("装備変更", "Customize"), systemImage: "slider.horizontal.3")
                    .font(Theme.body(12))
                    .lineLimit(1)
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(minHeight: 44)
            .accessibilityIdentifier("inventory_customize")
        }
    }

    // MARK: 一覧

    @ViewBuilder
    private var content: some View {
        if let type = tab.cosmeticType {
            let owned = CosmeticInfo.owned(type, profile: app.profile, master: app.master)
            if owned.isEmpty {
                VStack(spacing: 8) {
                    CollectionEmptyState(symbol: CollectionStyle.cosmeticTypeSymbol(type),
                                         title: L("\(CollectionStyle.cosmeticTypeName(type))をまだ所持していません",
                                                  "You don't own any \(CollectionStyle.cosmeticTypeName(type)) yet"),
                                         message: L("ストアやイベント報酬で入手できます。", "Get them from the store or event rewards."))
                    Button {
                        app.router.push(type == .heroSkin ? .skinStore : .store)
                    } label: {
                        Label(L("ストアへ", "Go to Store"), systemImage: "bag.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("inventory_go_store")
                }
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(owned) { c in
                        cosmeticCell(c)
                    }
                }
            }
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(app.master.heroes.filter { app.owns(heroID: $0.heroID) }) { h in
                    heroCell(h)
                }
            }
        }
    }

    private func heroCell(_ h: HeroDef) -> some View {
        Button {
            app.router.push(.heroDetail(h.heroID))
        } label: {
            VStack(spacing: 4) {
                HeroPortraitView(heroID: h.heroID, size: 60)
                Text(MasterText.hero(h))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26)
                let skins = CosmeticInfo.skins(heroID: h.heroID, master: app.master)
                let ownedSkins = skins.filter { app.owns(cosmeticID: $0.cosmeticID) }.count
                Text(skins.isEmpty ? " " : L("スキン \(ownedSkins)/\(skins.count)", "Skins \(ownedSkins)/\(skins.count)"))
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel(MasterText.hero(h))
        .accessibilityIdentifier("inventory_hero_\(h.heroID)")
    }

    private func cosmeticCell(_ c: CosmeticDef) -> some View {
        let equipped = CosmeticInfo.isEquipped(c, profile: app.profile)
        return Button {
            if let item = StoreCatalog.storeItem(forCosmetic: c.cosmeticID, master: app.master) {
                app.router.push(.productDetail(item.sku))
            } else {
                app.router.push(c.type == .emote ? .emotes : .cosmetics)
            }
        } label: {
            VStack(spacing: 4) {
                CosmeticPreviewView(cosmetic: c, size: 66, animated: false)
                Text(MasterText.cosmetic(c))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26)
                if equipped {
                    Label(L("装備中", "Equipped"), systemImage: "checkmark.circle.fill")
                        .font(Theme.body(9))
                        .foregroundStyle(Theme.success)
                } else {
                    CollectionRarityTag(rarity: c.rarity).scaleEffect(0.85)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(equipped ? Theme.success.opacity(0.6) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel(MasterText.cosmetic(c) + (equipped ? L("（装備中）", " (equipped)") : ""))
        .accessibilityIdentifier("inventory_cosmetic_\(c.cosmeticID)")
    }
}
