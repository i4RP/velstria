import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI047 通貨購入（AstralGem パック・年齢別上限・法定表示・復元導線）。

struct CurrencyStoreView: View {
    @Environment(AppModel.self) private var app
    @State private var purchasing: String?
    @State private var notice: CurrencyStoreNotice?
    @State private var receivedGems: Int?

    private let columns = [GridItem(.adaptive(minimum: 136), spacing: 10)]

    var body: some View {
        let remaining = app.storeKit.monthlyLimitRemaining(profile: app.profile)
        ScreenScaffold(title: L("AstralGem 購入", "Buy AstralGem")) {
            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !FeatureFlags.inAppPurchases {
                            Label(L("現在、アプリ内課金はご利用いただけません。", "In-app purchases are currently unavailable."),
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.danger)
                        }
                        if app.storeKit.isLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small).tint(Theme.cyan)
                                Text(L("App Store から価格を取得中…", "Loading prices from the App Store…"))
                                    .font(Theme.body(11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .accessibilityElement(children: .combine)
                            .transition(.opacity)
                        } else if FeatureFlags.inAppPurchases && app.storeKit.products.isEmpty {
                            // App Store の価格を取得できていない間は参考価格であることを明示する
                            Label(L("App Store の価格を取得できていないため、参考価格（税込）を表示しています。購入時は App Store の価格が適用されます。",
                                    "Couldn't load App Store prices; showing reference prices (tax incl.). The App Store price applies at purchase."),
                                  systemImage: "info.circle")
                                .font(Theme.body(10))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("currency_reference_prices")
                        }
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(Array(StoreKitService.gemProducts.enumerated()), id: \.element.productID) { i, product in
                                StoreGemPackCard(product: product, tierIndex: i,
                                            price: app.storeKit.displayPrice(for: product.productID),
                                            isPurchasing: purchasing == product.productID,
                                            isDisabled: purchasing != nil || !FeatureFlags.inAppPurchases,
                                            exceedsLimit: IAPResultText.exceedsLimit(priceJPY: product.referencePriceJPY, remaining: remaining)) {
                                    buy(product)
                                }
                            }
                        }
                        Text(L("購入した AstralGem は有償分として保持され、無償分の後に消費されます。価格は税込です。",
                               "Purchased AstralGem is kept as paid gems and is spent after free gems. Prices include tax."))
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                ScrollView {
                    sidePanel(remaining: remaining)
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .frame(width: 252)
            }
            .padding(.horizontal, 20)
        }
        .overlay {
            if let gems = receivedGems {
                GemPurchaseCompleteOverlay(gems: gems) { receivedGems = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: receivedGems)
        .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
               presenting: notice) { _ in
            Button("OK", role: .cancel) {}
        } message: { n in
            Text(n.body)
        }
    }

    private func buy(_ product: GemProduct) {
        guard purchasing == nil else { return }
        app.haptics.tap()
        purchasing = product.productID
        Task { @MainActor in
            let result = await app.storeKit.purchase(productID: product.productID)
            purchasing = nil
            handle(result)
        }
    }

    private func handle(_ result: IAPResult) {
        let remaining = app.storeKit.monthlyLimitRemaining(profile: app.profile)
        switch result {
        case .success(let gems):
            app.haptics.success()
            app.audio.play(.purchase)
            app.showToast(L("AstralGem ×\(gems.formatted()) を受け取りました", "Received \(gems.formatted()) AstralGem"))
            receivedGems = gems
        case .cancelled:
            return
        default:
            if case .pending = result { app.haptics.tap() } else { app.haptics.warning() }
            let bracket = app.profile.ageBracket ?? (remaining != nil ? .under13 : nil)
            if let m = IAPResultText.message(for: result, bracket: bracket, remaining: remaining) {
                notice = CurrencyStoreNotice(title: m.title, body: m.body)
            }
        }
    }

    // MARK: 右列

    private func sidePanel(remaining: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Panel(padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("AstralGem 残高", "AstralGem Balance")).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
                    balanceRow(L("有償", "Paid"), app.profile.paidGem, color: Color(red: 0.72, green: 0.52, blue: 1.0))
                    balanceRow(L("無償", "Free"), app.profile.freeGem, color: Theme.cyan)
                    Divider().overlay(Theme.panelStroke)
                    balanceRow(L("合計", "Total"), app.profile.totalGem, color: Theme.textPrimary)
                }
            }
            // 年齢区分が未設定でもサービス側が上限を適用している場合（最も厳しい区分扱い）は表示する
            if let bracket = app.profile.ageBracket ?? (remaining != nil ? .under13 : nil),
               let limit = bracket.monthlySpendLimitJPY {
                spendLimitPanel(bracket: bracket, limit: limit, remaining: remaining ?? limit)
            }
            StoreLegalDisclosure(title: L("資金決済法に基づく表示", "Payment Services Act Notice"),
                            rows: StoreLegalText.paymentServicesAct, id: "legal_payment_services")
            StoreLegalDisclosure(title: L("特定商取引法に基づく表記", "Specified Commercial Transactions Act"),
                            rows: StoreLegalText.commercialTransactions, id: "legal_commercial")
            Button {
                app.router.push(.restorePurchases)
            } label: {
                Label(L("購入の復元・購入履歴", "Restore Purchases & History"), systemImage: "arrow.clockwise")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.cyan)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("currency_restore")
            HStack(spacing: 0) {
                Link(destination: FeatureFlags.termsURL) {
                    Text(L("利用規約", "Terms of Use"))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("currency_terms")
                Link(destination: FeatureFlags.privacyPolicyURL) {
                    Text(L("プライバシーポリシー", "Privacy Policy"))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("currency_privacy")
            }
            .font(Theme.body(10))
            .underline()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private func balanceRow(_ label: String, _ amount: Int, color: Color) -> some View {
        HStack {
            Image(systemName: "diamond.fill").font(.system(size: 10)).foregroundStyle(color)
            Text(label).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(amount.formatted()).font(Theme.mono(13)).foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func spendLimitPanel(bracket: AgeBracket, limit: Int, remaining: Int) -> some View {
        let used = max(0, limit - remaining)
        return VStack(alignment: .leading, spacing: 5) {
            Label(L("月間購入上限", "Monthly Spending Limit"), systemImage: "person.badge.shield.checkmark.fill")
                .font(Theme.heading(12))
                .foregroundStyle(Theme.gold)
            Text(IAPResultText.monthlyLimitDescription(bracket) ?? "")
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(used), total: Double(max(1, limit)))
                .tint(remaining > 0 ? Theme.gold : Theme.danger)
            Text(L("今月の残り ¥\(remaining.formatted())", "Remaining this month ¥\(remaining.formatted())"))
                .font(Theme.mono(11))
                .foregroundStyle(remaining > 0 ? Theme.textPrimary : Theme.danger)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.gold.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("currency_spend_limit")
    }
}

struct CurrencyStoreNotice: Identifiable, Equatable {
    var id: String { title + body }
    let title: String
    let body: String
}

/// Gem パックのカード。
struct StoreGemPackCard: View {
    let product: GemProduct
    let tierIndex: Int
    let price: String
    let isPurchasing: Bool
    let isDisabled: Bool
    let exceedsLimit: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                StoreGemCluster(tier: tierIndex)
                    .frame(height: 46)
                    .padding(.top, 18)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: "diamond.fill").font(.system(size: 11)).foregroundStyle(Theme.cyan)
                    Text(product.gems.formatted())
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
                Group {
                    if product.bonusGems > 0 {
                        Text(L("+\(product.bonusGems.formatted()) ボーナス", "+\(product.bonusGems.formatted()) bonus"))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.gold))
                    } else {
                        Text(" ").font(.system(size: 10))
                    }
                }
                .frame(height: 16)
                // 付与される有償 Gem の合計（ボーナス分も有償として付与される。docs/legal の購入画面表示）
                Text(L("有償 Gem 計 \((product.gems + product.bonusGems).formatted()) 個",
                       "\((product.gems + product.bonusGems).formatted()) paid gems total"))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ZStack {
                    if isPurchasing {
                        ProgressView().tint(.black)
                    } else {
                        Text(price)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.85))
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Capsule().fill(LinearGradient(colors: [Theme.cyan, Theme.cyan.opacity(0.7)], startPoint: .top, endPoint: .bottom)))
                .padding(.horizontal, 10)
                if exceedsLimit {
                    Text(L("今月の上限を超えます", "Exceeds monthly limit"))
                        .font(Theme.body(9))
                        .foregroundStyle(Theme.danger)
                }
            }
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.cyan.opacity(0.08 + 0.03 * Double(tierIndex)), Theme.panel],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tierIndex >= 4 ? Theme.gold.opacity(0.6) : Theme.cyan.opacity(0.3), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                // 販売実績に基づかない「人気」表示は避け、推奨と単価の事実（最多ボーナス）のみを示す
                if tierIndex == 2 {
                    Text(L("おすすめ", "Recommended"))
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.danger))
                        .padding(6)
                } else if tierIndex == StoreKitService.gemProducts.count - 1 {
                    Text(L("お得", "Best Value"))
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.gold))
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .disabled(isDisabled)
        .opacity(isDisabled && !isPurchasing ? 0.6 : 1)
        .accessibilityLabel(L("AstralGem \(product.gems + product.bonusGems) 個、\(price)", "\(product.gems + product.bonusGems) AstralGem, \(price)"))
        .accessibilityIdentifier("gem_\(product.productID)")
    }
}

/// パック段階に応じて増える宝石の山。
struct StoreGemCluster: View {
    let tier: Int

    var body: some View {
        Canvas { ctx, size in
            let count = 1 + tier * 2
            let c = CGPoint(x: size.width / 2, y: size.height * 0.62)
            var gem = ctx.resolve(Image(systemName: "diamond.fill"))
            gem.shading = .linearGradient(Gradient(colors: [.white, Theme.cyan, Color(red: 0.4, green: 0.5, blue: 1.0)]),
                                          startPoint: .zero, endPoint: CGPoint(x: 0, y: 30))
            // 後ろ → 前の順に重ねる
            for i in (0..<count).reversed() {
                let row = i == 0 ? 0 : (i + 1) / 2
                let side: Double = i == 0 ? 0 : (i % 2 == 0 ? 1 : -1)
                let s = max(14, 30 - Double(row) * 3)
                let x = c.x + side * Double(row) * 8.5
                let y = c.y - Double(row) * 4 + (i == 0 ? 0 : 3)
                ctx.draw(gem, in: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s))
            }
            if tier >= 4 {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 34, y: c.y + 8, width: 68, height: 8)), with: .color(Theme.gold.opacity(0.3)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// 展開式の法定表示。
struct StoreLegalDisclosure: View {
    let title: String
    let rows: [StoreLegalText.Row]
    let id: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "doc.text.fill").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    Text(title).font(Theme.body(12)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? L("展開", "Expanded") : L("折りたたみ", "Collapsed"))
            .accessibilityIdentifier(id)
            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label).font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
                            Text(row.value).font(Theme.body(11)).foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
}

/// Gem 購入完了の演出。
struct GemPurchaseCompleteOverlay: View {
    let gems: Int
    let onClose: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.84).ignoresSafeArea()
            StoreCelebrationBurst(color: Theme.cyan).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 10) {
                Text(L("購入完了！", "Purchased!"))
                    .font(Theme.title(26))
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.cyan], startPoint: .top, endPoint: .bottom))
                StoreGemCluster(tier: 5)
                    .frame(width: 160, height: 80)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)
                Text(L("AstralGem ×\(gems.formatted()) を受け取りました", "Received \(gems.formatted()) AstralGem"))
                    .font(Theme.heading(16))
                    .foregroundStyle(Theme.textPrimary)
                Button(L("閉じる", "Close"), action: onClose)
                    .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("gem_purchase_done")
            }
            .storeCelebrationCard(color: Theme.cyan, appeared: appeared)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
