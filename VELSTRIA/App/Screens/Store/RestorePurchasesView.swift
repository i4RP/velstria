import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI051 購入の復元・購入履歴（台帳 purchaseLedger）。

@MainActor
enum PurchaseLedgerText {
    static func productName(_ productID: String) -> String {
        if productID == StoreKitService.premiumPassProductID {
            return L("スターパス プレミアム", "Star Pass Premium")
        }
        if let p = StoreKitService.gemProducts.first(where: { $0.productID == productID }) {
            return "AstralGem ×\((p.gems + p.bonusGems).formatted())"
        }
        return productID
    }

    /// 新しい順。
    static func sorted(_ ledger: [PurchaseRecord]) -> [PurchaseRecord] {
        ledger.sorted { $0.date != $1.date ? $0.date > $1.date : $0.transactionID > $1.transactionID }
    }
}

struct RestorePurchasesView: View {
    @Environment(AppModel.self) private var app
    @State private var restoring = false
    @State private var result: Bool?

    var body: some View {
        let ledger = PurchaseLedgerText.sorted(app.profile.purchaseLedger)
        ScreenScaffold(title: L("購入の復元", "Restore Purchases")) {
            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    restorePanel
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .frame(width: 290)
                VStack(alignment: .leading, spacing: 6) {
                    CollectionSectionTitle(title: L("購入履歴", "Purchase History"), symbol: "clock.arrow.circlepath",
                                           trailing: L("\(ledger.count) 件", "\(ledger.count) records"))
                    if ledger.isEmpty {
                        CollectionEmptyState(symbol: "doc.text.magnifyingglass",
                                             title: L("購入履歴はありません", "No purchases yet"),
                                             message: L("App Store での購入はここに記録されます。", "App Store purchases will be listed here."))
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(ledger) { record in
                                    ledgerRow(record)
                                }
                            }
                            .padding(.bottom, 12)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var restorePanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("購入の復元", "Restore"), systemImage: "arrow.clockwise.circle.fill")
                    .font(Theme.heading(15))
                    .foregroundStyle(Theme.textPrimary)
                Text(L("機種変更や再インストール後に、スターパス プレミアムなどの購入状態を App Store から再取得します。未付与の AstralGem の取引があれば、あわせて付与されます。",
                       "Re-fetches purchases such as Star Pass Premium from the App Store after changing devices or reinstalling. Any undelivered AstralGem transactions are delivered as well."))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("AstralGem（消耗型）の残高は「購入の復元」では戻りません。機種変更の際は「アカウント・データ」のバックアップで引き継いでください。",
                       "AstralGem balances (consumable) are not restored by Restore Purchases. When changing devices, carry them over with the backup in Account & Data."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    restore()
                } label: {
                    HStack(spacing: 8) {
                        if restoring {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(restoring ? L("復元中…", "Restoring…") : L("購入を復元", "Restore Purchases"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
                .frame(minHeight: 44)
                .disabled(restoring)
                .accessibilityIdentifier("restore_button")
                if let result {
                    Label(result ? L("購入情報を復元しました", "Purchases restored")
                                 : L("復元できませんでした。通信状況と Apple アカウントをご確認ください。",
                                     "Couldn't restore. Check your connection and Apple Account."),
                          systemImage: result ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(Theme.body(12))
                        .foregroundStyle(result ? Theme.success : Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                        .accessibilityIdentifier("restore_result")
                }
                if app.profile.pass.hasPremium {
                    Label(L("スターパス プレミアム: 有効", "Star Pass Premium: active"), systemImage: "crown.fill")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.gold)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: result)
    }

    private func restore() {
        guard !restoring else { return }
        app.haptics.tap()
        restoring = true
        result = nil
        Task { @MainActor in
            let ok = await app.storeKit.restore()
            restoring = false
            result = ok
            if ok { app.haptics.success() } else { app.haptics.warning() }
        }
    }

    private func ledgerRow(_ r: PurchaseRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.productID == StoreKitService.premiumPassProductID ? "crown.fill" : "diamond.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(r.revoked ? Theme.textSecondary : (r.productID == StoreKitService.premiumPassProductID ? Theme.gold : Theme.cyan))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                Text(PurchaseLedgerText.productName(r.productID))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(r.revoked)
                Text(r.date.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("¥\(r.priceJPY.formatted())")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                if r.revoked {
                    CollectionInfoTag(text: L("返金済み", "Refunded"), symbol: "arrow.uturn.left", color: Theme.danger)
                } else if r.gemsGranted > 0 {
                    Text(L("+\(r.gemsGranted.formatted()) Gem 付与", "+\(r.gemsGranted.formatted()) gems"))
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.success)
                } else {
                    Text(L("付与済み", "Delivered")).font(Theme.body(10)).foregroundStyle(Theme.success)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}
