import SwiftUI
import VelstriaCore

// 担当: ui-collection。ゲーム内通貨の購入フロー: UI049 購入確認 → UI050 購入完了（失敗時はアラート）。
// 使い方: `.storePurchaseFlow(sku: $pendingSKU)` を画面ルートに付け、pendingSKU をセットすると確認を表示する。

/// 画面全体を覆うモーダルの土台（暗幕 + 中央パネル）。
struct StoreModalContainer<Content: View>: View {
    var maxWidth: CGFloat = 560
    var onDismiss: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onDismiss?() }
                .accessibilityHidden(true)
            content()
                .padding(16)
                .frame(maxWidth: maxWidth)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.13, blue: 0.27), Color(red: 0.07, green: 0.07, blue: 0.16)],
                                             startPoint: .top, endPoint: .bottom))
                )
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.gold.opacity(0.45), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 20)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
        }
    }
}

/// UI049 購入確認。残高の前後と、Gem の場合は無償/有償の消費内訳を表示する。
struct PurchaseConfirmSheet: View {
    let item: StoreItemDef
    let onConfirm: () -> Void
    let onCancel: () -> Void
    /// 残高不足時に通貨購入へ誘導する（Gem のみ）。
    let onGetCurrency: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let profile = app.profile
        let price = EconomyService.price(of: item)
        let before = StoreCatalog.balance(item.currency, profile: profile)
        let after = before - price
        let insufficient = after < 0
        StoreModalContainer(onDismiss: onCancel) {
            HStack(alignment: .center, spacing: 18) {
                StoreItemPreview(item: item, size: 120, animated: true)
                    .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("購入確認", "Confirm Purchase"))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.gold)
                    Text(MasterText.storeItem(item))
                        .font(Theme.heading(17))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        CollectionInfoTag(text: StoreCatalog.typeLabel(item, master: app.master),
                                          symbol: StoreCatalog.typeSymbol(item, master: app.master), color: Theme.cyan)
                        if let r = StoreCatalog.rarity(of: item, master: app.master) { CollectionRarityTag(rarity: r) }
                    }
                    balanceRows(price: price, before: before, after: after, insufficient: insufficient)
                    if item.currency == .astralGem && !insufficient {
                        let split = StoreCatalog.gemSplit(cost: price, profile: profile)
                        Text(L("無償 Gem から優先して消費します（無償 \(split.free.formatted())・有償 \(split.paid.formatted())）",
                               "Free gems are spent first (free \(split.free.formatted()), paid \(split.paid.formatted()))"))
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if insufficient {
                        Label(L("残高が不足しています", "Not enough balance"), systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.danger)
                    }
                    buttons(insufficient: insufficient)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func balanceRows(price: Int, before: Int, after: Int, insufficient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L("価格", "Price")).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                Spacer()
                PriceTag(currency: item.currency, amount: price, size: 15)
            }
            HStack(spacing: 6) {
                Text(L("残高", "Balance")).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                Spacer()
                PriceTag(currency: item.currency, amount: before, size: 13)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textSecondary)
                if insufficient {
                    // 残高不足時は購入後残高ではなく不足額を示す
                    Text(L("\((-after).formatted()) 不足", "\((-after).formatted()) short"))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.danger)
                } else {
                    PriceTag(currency: item.currency, amount: after, size: 13)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3)))
    }

    @ViewBuilder
    private func buttons(insufficient: Bool) -> some View {
        HStack(spacing: 10) {
            Button(L("キャンセル", "Cancel"), action: onCancel)
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .accessibilityIdentifier("purchase_cancel")
            if insufficient {
                if item.currency == .astralGem {
                    Button(action: onGetCurrency) {
                        Label(L("Gem を購入", "Get Gems"), systemImage: "diamond.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("purchase_get_currency")
                } else {
                    Text(L("Coin はバトル報酬で獲得できます", "Earn Coin by playing matches"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Button(action: onConfirm) {
                    Label(L("購入する", "Buy"), systemImage: "cart.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(minHeight: 44)
                .accessibilityIdentifier("purchase_confirm")
            }
        }
        .padding(.top, 2)
    }
}

/// 購入完了の内容。
struct StorePurchaseCompletion: Identifiable, Equatable {
    let id = UUID()
    let item: StoreItemDef
    let granted: [String]
}

/// UI050 購入完了（祝賀演出）。
struct PurchaseCompleteOverlay: View {
    let completion: StorePurchaseCompletion
    let onClose: () -> Void
    @Environment(AppModel.self) private var app
    @State private var appeared = false

    var body: some View {
        let equipTarget = equipCandidate
        ZStack {
            Color.black.opacity(0.84).ignoresSafeArea()
            StoreCelebrationBurst(color: rarityColor)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 10) {
                Text(L("購入完了！", "Purchased!"))
                    .font(Theme.title(26))
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.gold], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Theme.gold.opacity(0.6), radius: 8)
                grantedPreviews
                    .scaleEffect(appeared ? 1 : 0.4)
                    .opacity(appeared ? 1 : 0)
                Text(grantedNames)
                    .font(Theme.heading(15))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    if let c = equipTarget {
                        Button {
                            var p = app.profile
                            if CosmeticInfo.equip(c, profile: &p) {
                                app.profile = p
                                app.showToast(L("装備しました", "Equipped"))
                            } else {
                                app.showToast(L("エモート枠がいっぱいです", "Emote slots are full"))
                            }
                            onClose()
                        } label: {
                            Label(L("装備する", "Equip"), systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("purchase_equip")
                    }
                    Button(L("閉じる", "Close"), action: onClose)
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("purchase_done")
                }
            }
            .storeCelebrationCard(color: rarityColor, appeared: appeared)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.1)) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var rarityColor: Color {
        StoreCatalog.rarity(of: completion.item, master: app.master).map(Theme.rarityColor) ?? Theme.gold
    }

    /// 単品コスメなら装備ボタンを出す。
    private var equipCandidate: CosmeticDef? {
        guard completion.item.type == .cosmetic, let c = app.master.cosmetic(completion.item.grantID),
              !CosmeticInfo.isEquipped(c, profile: app.profile) else { return nil }
        return c
    }

    private var grantedNames: String {
        let names = completion.granted.compactMap { id -> String? in
            if let c = app.master.cosmetic(id) { return MasterText.cosmetic(c) }
            if let h = app.master.hero(id) { return MasterText.hero(h) }
            return nil
        }
        return names.isEmpty ? MasterText.storeItem(completion.item) : names.prefix(4).joined(separator: " / ")
    }

    @ViewBuilder
    private var grantedPreviews: some View {
        let cosmetics = completion.granted.compactMap { app.master.cosmetic($0) }
        if completion.item.type == .bundle, cosmetics.count > 1 {
            HStack(spacing: 10) {
                ForEach(cosmetics.prefix(5), id: \.cosmeticID) { c in
                    CosmeticPreviewView(cosmetic: c, size: 76)
                }
            }
        } else {
            StoreItemPreview(item: completion.item, size: 130, animated: true)
                .frame(height: 150)
        }
    }
}

extension View {
    /// 購入完了演出の中央カード（背景の画面と重なっても読めるよう不透明に近い板に載せる）。
    func storeCelebrationCard(color: Color, appeared: Bool) -> some View {
        self
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(RadialGradient(colors: [color.opacity(0.28), Color(red: 0.06, green: 0.06, blue: 0.15).opacity(0.94)],
                                         center: .center, startRadius: 10, endRadius: 260))
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(color.opacity(0.6), lineWidth: 1.5))
            .shadow(color: color.opacity(0.35), radius: 24)
            .scaleEffect(appeared ? 1 : 0.92)
            .padding(12)
    }
}

/// 放射光と紙吹雪の祝賀演出。
struct StoreCelebrationBurst: View {
    var color: Color = Theme.gold
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let e = reduceMotion ? 1.2 : tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height * 0.45)
                let R = max(size.width, size.height)
                // 回転する放射光
                let rays = 16
                for i in 0..<rays {
                    let a = e * 0.25 + Double(i) * 2 * .pi / Double(rays)
                    var p = Path()
                    p.move(to: c)
                    p.addLine(to: CGPoint(x: c.x + cos(a - 0.06) * R, y: c.y + sin(a - 0.06) * R))
                    p.addLine(to: CGPoint(x: c.x + cos(a + 0.06) * R, y: c.y + sin(a + 0.06) * R))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(color.opacity(i % 2 == 0 ? 0.10 : 0.05)))
                }
                // 最初の衝撃波
                if e < 1.2 {
                    let r = R * 0.5 * e
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(.white.opacity(max(0, 1 - e / 1.2))), lineWidth: 3)
                }
                // 紙吹雪（放物線で落下）
                let palette: [Color] = [color, Theme.cyan, .white, Theme.gold, Color(red: 1, green: 0.5, blue: 0.7)]
                for i in 0..<70 {
                    let a = CosmeticPainter.hash(i, 21) * 2 * .pi
                    let speed = 220 + CosmeticPainter.hash(i, 22) * 380
                    let life = e.truncatingRemainder(dividingBy: 3.2)
                    let x = c.x + cos(a) * speed * life
                    let y = c.y + sin(a) * speed * life * 0.7 + 180 * life * life
                    guard y < size.height + 20 else { continue }
                    let w = 4 + CosmeticPainter.hash(i, 23) * 5
                    var piece = ctx
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(life * (3 + CosmeticPainter.hash(i, 24) * 6)))
                    piece.fill(Path(CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2)),
                               with: .color(palette[i % palette.count].opacity(max(0, 1 - life / 3.2))))
                }
            }
        }
    }
}

/// 購入失敗の種類。
enum StorePurchaseFailure: Identifiable, Equatable {
    case insufficient(Currency)
    case owned
    case limit
    case invalid

    var id: String {
        switch self {
        case .insufficient(let c): return "insufficient_\(c.rawValue)"
        case .owned: return "owned"
        case .limit: return "limit"
        case .invalid: return "invalid"
        }
    }

    var title: String {
        switch self {
        case .insufficient: return L("残高不足", "Not Enough Balance")
        case .owned: return L("所持済み", "Already Owned")
        case .limit: return L("購入上限", "Purchase Limit")
        case .invalid: return L("購入できません", "Unavailable")
        }
    }

    var message: String {
        switch self {
        case .insufficient(.astralGem): return L("AstralGem が不足しています。Gem を購入しますか？", "You don't have enough AstralGem. Get more gems?")
        case .insufficient(.starlightCoin): return L("StarlightCoin が不足しています。バトルやミッションの報酬で獲得できます。", "Not enough StarlightCoin. Earn more from matches and missions.")
        case .owned: return L("この商品は既に所持しています。", "You already own this item.")
        case .limit: return L("この商品の購入上限に達しています。", "You've reached the purchase limit for this item.")
        case .invalid: return L("この商品は現在購入できません。", "This item is currently unavailable.")
        }
    }
}

struct StorePurchaseFlowModifier: ViewModifier {
    @Binding var sku: String?
    @Environment(AppModel.self) private var app
    @State private var completion: StorePurchaseCompletion?
    @State private var failure: StorePurchaseFailure?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let sku, let item = app.master.storeItem(sku) {
                    PurchaseConfirmSheet(item: item,
                                         onConfirm: { confirm(item) },
                                         onCancel: { self.sku = nil },
                                         onGetCurrency: {
                                             self.sku = nil
                                             app.router.push(.currencyStore)
                                         })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .overlay {
                if let completion {
                    PurchaseCompleteOverlay(completion: completion) { self.completion = nil }
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: sku)
            .animation(.easeOut(duration: 0.25), value: completion)
            .alert(failure?.title ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                   presenting: failure) { f in
                if case .insufficient(.astralGem) = f {
                    Button(L("Gem を購入", "Get Gems")) { app.router.push(.currencyStore) }
                    Button(L("閉じる", "Close"), role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { f in
                Text(f.message)
            }
    }

    private func confirm(_ item: StoreItemDef) {
        var p = app.profile
        let result = EconomyService.purchase(sku: item.sku, profile: &p, master: app.master)
        sku = nil
        switch result {
        case .success(let granted):
            app.profile = p
            app.haptics.success()
            app.audio.play(.purchase)
            completion = StorePurchaseCompletion(item: item, granted: granted)
        case .insufficientFunds:
            app.haptics.warning()
            failure = .insufficient(item.currency)
        case .alreadyOwned:
            failure = .owned
        case .limitReached:
            failure = .limit
        case .invalid:
            failure = .invalid
        }
    }
}

extension View {
    /// ゲーム内通貨の購入フロー（確認 → 完了 / エラー）を付ける。
    func storePurchaseFlow(sku: Binding<String?>) -> some View {
        modifier(StorePurchaseFlowModifier(sku: sku))
    }
}
