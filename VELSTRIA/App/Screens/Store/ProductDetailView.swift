import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI048 商品詳細 → UI049 購入確認 → UI050 購入完了。

struct ProductDetailView: View {
    let sku: String
    @Environment(AppModel.self) private var app
    @State private var pendingSKU: String?

    var body: some View {
        ScreenScaffold(title: L("商品詳細", "Product")) {
            if let item = app.master.storeItem(sku) {
                HStack(alignment: .top, spacing: 16) {
                    showcase(item)
                        .frame(width: 280)
                    ScrollView {
                        info(item)
                            .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, 20)
            } else {
                CollectionEmptyState(symbol: "questionmark.circle", title: L("商品が見つかりません", "Product not found"))
            }
        }
        .storePurchaseFlow(sku: $pendingSKU)
    }

    private func showcase(_ item: StoreItemDef) -> some View {
        let tint = StoreCatalog.rarity(of: item, master: app.master).map(Theme.rarityColor) ?? Theme.cyan
        return ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(RadialGradient(colors: [tint.opacity(0.35), Theme.panel], center: .center, startRadius: 10, endRadius: 220))
            Canvas { ctx, size in
                // 台座
                let c = CGPoint(x: size.width / 2, y: size.height * 0.84)
                for k in 0..<3 {
                    let w = 180.0 - Double(k) * 40
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - w * 0.09, width: w, height: w * 0.18)),
                               with: .color(tint.opacity(0.5 - 0.12 * Double(k))), lineWidth: 1.5)
                }
            }
            StoreItemPreview(item: item, size: 160, animated: true)
                .offset(y: -10)
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.5), lineWidth: 1))
        .frame(maxHeight: .infinity)
        .padding(.bottom, 12)
    }

    private func info(_ item: StoreItemDef) -> some View {
        let owned = EconomyService.isOwned(item, profile: app.profile)
        let unavailable = StoreCatalog.isUnavailable(item, profile: app.profile)
        let cosmetic = StoreCatalog.cosmetic(for: item, master: app.master)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                CollectionInfoTag(text: StoreCatalog.typeLabel(item, master: app.master),
                                  symbol: StoreCatalog.typeSymbol(item, master: app.master), color: Theme.cyan)
                if let r = StoreCatalog.rarity(of: item, master: app.master) { CollectionRarityTag(rarity: r) }
            }
            Text(MasterText.storeItem(item))
                .font(Theme.title(22))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(MasterText.description(id: item.sku,
                                        ja: Self.description(item, master: app.master, lang: Loc.isEnglish ? .en : .ja)))
                .font(Theme.body(13))
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            if item.type == .heroUnlock, let hero = app.master.hero(item.grantID) {
                heroInfo(hero)
            }
            if item.type == .bundle {
                bundleContents(item)
            }
            if item.type != .heroUnlock {
                noticeRow(symbol: "shield.checkered", text: L("戦闘能力には影響しません（見た目のみ）", "Cosmetic only — no effect on combat power"))
            }
            if item.purchaseLimit > 1 {
                noticeRow(symbol: "number.circle",
                          text: L("購入回数 \(StoreCatalog.purchaseCount(sku: item.sku, profile: app.profile))/\(item.purchaseLimit)",
                                  "Purchased \(StoreCatalog.purchaseCount(sku: item.sku, profile: app.profile))/\(item.purchaseLimit)"))
            }
            Divider().overlay(Theme.panelStroke)
            purchaseRow(item, owned: owned, unavailable: unavailable, cosmetic: cosmetic)
            policyBlock(item)
        }
    }

    /// 購入条件（重複・返金・上限）。
    private func policyBlock(_ item: StoreItemDef) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(StoreCatalog.policyRows(item)) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 84, alignment: .leading)
                    Text(row.value)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }

    private func heroInfo(_ hero: HeroDef) -> some View {
        Button {
            app.router.push(.heroDetail(hero.heroID))
        } label: {
            HStack(spacing: 10) {
                HeroPortraitView(heroID: hero.heroID, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        CollectionRoleTag(role: hero.role)
                        CollectionDifficultyStars(value: hero.difficulty, size: 9)
                    }
                    Text(L("ヒーロー詳細を見る", "View hero details"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.cyan)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
            }
            .padding(8)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("product_hero_link")
    }

    @ViewBuilder
    private func bundleContents(_ item: StoreItemDef) -> some View {
        let contents = EconomyService.bundleContents(item.grantID, master: app.master).compactMap { app.master.cosmetic($0) }
        if !contents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                CollectionSectionTitle(title: L("セット内容", "Includes"), symbol: "gift.fill", trailing: L("\(contents.count) 点", "\(contents.count) items"))
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(contents) { c in
                            VStack(spacing: 3) {
                                CosmeticPreviewView(cosmetic: c, size: 58, animated: false)
                                Text(MasterText.cosmetic(c))
                                    .font(Theme.body(9))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 70)
                                if app.owns(cosmeticID: c.cosmeticID) {
                                    Text(L("所持", "Owned")).font(Theme.body(9)).foregroundStyle(Theme.success)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func noticeRow(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(Theme.body(11))
            .foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder
    private func purchaseRow(_ item: StoreItemDef, owned: Bool, unavailable: Bool, cosmetic: CosmeticDef?) -> some View {
        let price = EconomyService.price(of: item)
        let affordable = StoreCatalog.canAfford(item, profile: app.profile)
        HStack(spacing: 12) {
            if owned {
                Label(L("所持済み", "Owned"), systemImage: "checkmark.seal.fill")
                    .font(Theme.heading(15))
                    .foregroundStyle(Theme.success)
                Spacer()
                if let cosmetic {
                    if CosmeticInfo.isEquipped(cosmetic, profile: app.profile) {
                        Label(L("装備中", "Equipped"), systemImage: "checkmark.circle.fill")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Button {
                            equip(cosmetic)
                        } label: {
                            Label(L("装備する", "Equip"), systemImage: "checkmark.circle")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("product_equip")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("価格", "Price")).font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
                    PriceTag(currency: item.currency, amount: price, size: 20)
                    if !affordable && !unavailable {
                        Text(L("残高不足", "Not enough balance")).font(Theme.body(10)).foregroundStyle(Theme.danger)
                    }
                }
                Spacer()
                if unavailable {
                    Text(L("購入上限に達しています", "Purchase limit reached"))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Button {
                        app.haptics.tap()
                        pendingSKU = item.sku
                    } label: {
                        Label(item.type == .heroUnlock ? L("解放する", "Unlock") : L("購入する", "Buy"), systemImage: "cart.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("product_buy")
                }
            }
        }
    }

    private func equip(_ c: CosmeticDef) {
        var p = app.profile
        if CosmeticInfo.equip(c, profile: &p) {
            app.profile = p
            app.haptics.success()
            app.showToast(L("装備しました", "Equipped"))
        } else {
            app.haptics.warning()
            app.showToast(L("エモート枠がいっぱいです。エモート設定で入れ替えてください", "Emote slots are full. Swap one in Emotes"))
            app.router.push(.emotes)
        }
    }

    enum DescriptionLanguage { case ja, en }

    /// 種類別の説明文（マスターに説明が無いため生成する）。
    static func description(_ item: StoreItemDef, master: MasterData, lang: DescriptionLanguage) -> String {
        let ja = lang == .ja
        switch item.type {
        case .heroUnlock:
            let name = master.hero(item.grantID).map { ja ? $0.displayNameJa : $0.codeName } ?? item.grantID
            return ja ? "\(name)を解放し、すべてのモードで使用できるようにします。"
                      : "Unlocks \(name) for use in every mode."
        case .bundle:
            return ja ? "複数のコスメをまとめた星環バンドルです。所持済みのコスメは重複して付与されず、商品設定に従って通貨で補填されます。"
                      : "A Star Ring bundle containing multiple cosmetics. Cosmetics you already own aren't granted twice; they're compensated with currency per the product settings."
        case .cosmetic:
            guard let c = master.cosmetic(item.grantID) else { return "" }
            switch c.type {
            case .heroSkin:
                let name = master.hero(c.heroID).map { ja ? $0.displayNameJa : $0.codeName } ?? c.heroID
                return ja ? "\(name)の外見を変更するスキンです。能力値やスキル性能は変わりません。"
                          : "A skin that changes how \(name) looks. Stats and abilities are unchanged."
            case .recall:
                return ja ? "帰還中の演出を変更します。" : "Changes your recall animation."
            case .spawn:
                return ja ? "試合開始時と復活時の出現演出を変更します。" : "Changes your spawn effect at match start and on respawn."
            case .killEffect:
                return ja ? "敵ヒーローを倒した時の演出を変更します。" : "Changes the effect shown when you defeat an enemy hero."
            case .emote:
                return ja ? "戦闘中に表示できるエモートです。エモート設定で 4 枠のいずれかに装備します。"
                          : "An emote you can show during matches. Equip it to one of 4 slots in Emotes."
            case .avatarFrame:
                return ja ? "プロフィールやロード画面のアイコンを飾るフレームです。" : "A frame that decorates your icon on your profile and loading screen."
            }
        }
    }
}
