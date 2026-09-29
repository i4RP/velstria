import Foundation
import StoreKit
import VelstriaCore

// 担当: app-services
// StoreKit 2（DESIGN §13）:
// - start(): Transaction.updates の監視開始（アプリ起動直後）→ 商品取得 → 未完了トランザクション処理 → 権利の再確認
// - 購入: 機能フラグ → 年齢区分の月間上限 → product.purchase() → 検証済みのみ付与 → 保存 → finish()
// - 付与は Transaction.id で冪等（profile.purchaseLedger）。Gem は gems + bonusGems を有償 Gem へ。
// - スターパス プレミアムは非消耗型。currentEntitlements から復元する。
// - 返金・取り消し（revocationDate あり）は台帳を revoked にし、未消費の有償 Gem を付与数まで回収する。
// 付与ロジック（applyTransaction）は StoreKit 型に依存しない static 関数としてテスト可能にしている。

struct GemProduct: Identifiable, Equatable {
    var id: String { productID }
    var productID: String
    var gems: Int
    var bonusGems: Int
    var referencePriceJPY: Int
}

enum IAPResult: Equatable {
    case success(gems: Int)
    case pending
    case cancelled
    case limitExceeded
    case failed(String)
}

/// トランザクションを台帳へ反映した結果。
enum LedgerGrantResult: Equatable {
    /// 有償 Gem を付与した。
    case grantedGems(Int)
    case grantedPremiumPass
    /// 同じ Transaction.id を処理済み（何もしない）。
    case alreadyProcessed
    /// 返金・取り消しを反映した（回収した有償 Gem 数）。
    case revoked(removedGems: Int)
    /// 取り消し済みの記録がある（何もしない）。
    case alreadyRevoked
    /// このアプリの商品ではない。
    case unknownProduct
}

@Observable
@MainActor
final class StoreKitService {
    nonisolated static let gemProducts: [GemProduct] = [
        GemProduct(productID: "com.velstria.game.gem.60", gems: 60, bonusGems: 0, referencePriceJPY: 160),
        GemProduct(productID: "com.velstria.game.gem.300", gems: 300, bonusGems: 30, referencePriceJPY: 800),
        GemProduct(productID: "com.velstria.game.gem.980", gems: 980, bonusGems: 110, referencePriceJPY: 2500),
        GemProduct(productID: "com.velstria.game.gem.1980", gems: 1980, bonusGems: 260, referencePriceJPY: 4900),
        GemProduct(productID: "com.velstria.game.gem.3280", gems: 3280, bonusGems: 600, referencePriceJPY: 8000),
        GemProduct(productID: "com.velstria.game.gem.6480", gems: 6480, bonusGems: 1600, referencePriceJPY: 15800),
    ]
    nonisolated static let premiumPassProductID = "com.velstria.game.pass.premium"
    nonisolated static let premiumPassReferencePriceJPY = 980

    nonisolated static var allProductIDs: [String] { gemProducts.map(\.productID) + [premiumPassProductID] }

    /// 取得済み StoreKit 商品（productID → Product）。
    var products: [String: Product] = [:]
    var isLoading = false
    var lastError: String?
    /// 購入処理中の productID（UI のボタン無効化用）。
    var purchasingProductID: String?
    /// 復元処理中。
    var isRestoring = false

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init() {}

    func attach(to app: AppModel) {
        self.app = app
    }

    /// 商品取得とトランザクション監視の開始（複数回呼んでも 1 回だけ実行）。
    func start() async {
        guard !started else { return }
        started = true
        listenForTransactionUpdates()
        await loadProducts()
        await processUnfinishedTransactions()
        await refreshEntitlements()
    }

    /// 商品情報を取得する（失敗時は lastError を設定し、表示は参考価格にフォールバック）。
    /// 取得中に呼ばれた場合は進行中の取得の完了を待つ（起動直後の購入操作で「取得できない」にならないように）。
    func loadProducts() async {
        if let inFlight = loadTask {
            await inFlight.value
            return
        }
        let task = Task { await self.fetchProducts() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func fetchProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await Product.products(for: Self.allProductIDs)
            var map: [String: Product] = [:]
            for p in list { map[p.id] = p }
            products = map
            if list.isEmpty {
                lastError = L("商品情報を取得できませんでした。", "Could not load products.")
            } else {
                lastError = nil
            }
        } catch {
            lastError = L("商品情報を取得できませんでした。通信環境をご確認ください。",
                          "Could not load products. Please check your connection.")
        }
    }

    private func listenForTransactionUpdates() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                _ = await self.handle(result)
            }
        }
    }

    /// 前回起動時までに完了していないトランザクション（付与前にアプリが終了した等）を処理する。
    func processUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            _ = await handle(result)
        }
    }

    /// 検証結果を処理する。検証済みのみ付与して finish。未検証は付与も finish もしない。
    @discardableResult
    private func handle(_ result: VerificationResult<Transaction>) async -> LedgerGrantResult? {
        switch result {
        case .verified(let transaction):
            guard let outcome = applyVerified(transaction) else { return nil }
            await transaction.finish()
            return outcome
        case .unverified:
            lastError = L("購入の検証に失敗しました。", "Purchase verification failed.")
            return nil
        }
    }

    /// AppModel のプロフィールへ反映し、finish の前に確実に保存する。
    private func applyVerified(_ transaction: Transaction) -> LedgerGrantResult? {
        guard let app else { return nil }
        var profile = app.profile
        let outcome = Self.applyTransaction(
            transactionID: transaction.id, productID: transaction.productID,
            priceJPY: Self.priceJPY(of: transaction), quantity: transaction.purchasedQuantity,
            purchaseDate: transaction.purchaseDate, revocationDate: transaction.revocationDate, to: &profile)
        if profile != app.profile {
            app.profile = profile
            app.persistence.saveNow(profile)
        }
        return outcome
    }

    // MARK: - 購入

    func purchase(productID: String) async -> IAPResult {
        guard FeatureFlags.inAppPurchases else {
            return .failed(L("現在購入はご利用いただけません。", "Purchases are currently unavailable."))
        }
        guard let app else { return .failed(L("購入を開始できませんでした。", "Could not start the purchase.")) }
        guard purchasingProductID == nil else {
            return .failed(L("他の購入を処理中です。", "Another purchase is in progress."))
        }
        if productID == Self.premiumPassProductID && app.profile.pass.hasPremium {
            return .failed(L("スターパス プレミアムは購入済みです。", "You already own the Star Pass Premium."))
        }
        // 以降は await を挟むため、連打で購入が二重に始まらないよう先に処理中にする
        purchasingProductID = productID
        defer { purchasingProductID = nil }
        if products[productID] == nil { await loadProducts() }
        guard let product = products[productID] else {
            return .failed(L("商品情報を取得できませんでした。", "Could not load the product."))
        }

        // 年齢区分による月間上限（日本のストアフロントなら実価格、それ以外は参考価格で判定）
        let price = await limitCheckPriceJPY(for: product)
        if !Self.isWithinMonthlyLimit(priceJPY: price, profile: app.profile, now: Date()) {
            return .limitExceeded
        }

        var options: Set<Product.PurchaseOption> = []
        if let token = UUID(uuidString: app.profile.playerID) {
            options.insert(.appAccountToken(token))
        }
        do {
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    let outcome = applyVerified(transaction)
                    guard let outcome else {
                        return .failed(L("購入内容を反映できませんでした。再起動後に自動で反映されます。",
                                         "Could not apply the purchase. It will be applied after restarting the app."))
                    }
                    await transaction.finish()
                    switch outcome {
                    case .grantedGems(let gems): return .success(gems: gems)
                    case .grantedPremiumPass: return .success(gems: 0)
                    case .alreadyProcessed:
                        // 監視タスク側で先に付与済み
                        let granted = app.profile.purchaseLedger.first { $0.transactionID == transaction.id }?.gemsGranted
                        return .success(gems: granted ?? 0)
                    case .revoked, .alreadyRevoked:
                        return .failed(L("この購入は取り消されています。", "This purchase has been revoked."))
                    case .unknownProduct:
                        return .failed(L("不明な商品です。", "Unknown product."))
                    }
                case .unverified:
                    lastError = L("購入の検証に失敗しました。", "Purchase verification failed.")
                    return .failed(L("購入の検証に失敗しました。", "Purchase verification failed."))
                }
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed(L("購入を完了できませんでした。", "The purchase could not be completed."))
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func purchasePremiumPass() async -> IAPResult {
        await purchase(productID: Self.premiumPassProductID)
    }

    /// App Store と同期し、スターパス プレミアムなどの権利を復元する。
    func restore() async -> Bool {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            lastError = L("購入の復元に失敗しました。", "Could not restore purchases.")
            return false
        }
        await processUnfinishedTransactions()
        await refreshEntitlements()
        lastError = nil
        return true
    }

    /// 現在の権利（非消耗型）を確認し、スターパス プレミアムを復元する。
    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.premiumPassProductID,
                  transaction.revocationDate == nil,
                  let app else { continue }
            var profile = app.profile
            Self.restorePremium(transactionID: transaction.id, priceJPY: Self.priceJPY(of: transaction),
                                purchaseDate: transaction.purchaseDate, to: &profile)
            if profile != app.profile {
                app.profile = profile
                app.persistence.saveNow(profile)
            }
        }
    }

    // MARK: - 表示・上限

    /// 表示価格（StoreKit 取得済みならローカライズ価格、未取得なら参考価格）。
    func displayPrice(for productID: String) -> String {
        if let p = products[productID] { return p.displayPrice }
        return "¥\(Self.referencePriceJPY(productID: productID).formatted())"
    }

    /// 年齢区分による今月の残り購入可能額（円）。nil = 上限なし。
    func monthlyLimitRemaining(profile: Profile, now: Date = Date()) -> Int? {
        Self.remainingMonthlyAllowance(profile: profile, now: now)
    }

    /// 年齢区分が未設定の場合は最も厳しい区分（15 歳以下）として扱う。
    nonisolated static func remainingMonthlyAllowance(profile: Profile, now: Date) -> Int? {
        guard let limit = (profile.ageBracket ?? .under13).monthlySpendLimitJPY else { return nil }
        let spent = profile.monthlySpendJPY[LiveOpsService.monthKey(now)] ?? 0
        return max(0, limit - spent)
    }

    nonisolated static func isWithinMonthlyLimit(priceJPY: Int, profile: Profile, now: Date) -> Bool {
        guard let remaining = remainingMonthlyAllowance(profile: profile, now: now) else { return true }
        return priceJPY <= remaining
    }

    nonisolated static func gemProduct(_ productID: String) -> GemProduct? {
        gemProducts.first { $0.productID == productID }
    }

    nonisolated static func referencePriceJPY(productID: String) -> Int {
        if productID == premiumPassProductID { return premiumPassReferencePriceJPY }
        return gemProduct(productID)?.referencePriceJPY ?? 0
    }

    /// 上限判定に使う価格: 日本のストアフロントかつ JPY 表示なら実価格、それ以外は参考価格。
    private func limitCheckPriceJPY(for product: Product) async -> Int {
        let storefront = await Storefront.current
        if storefront?.countryCode == "JPN", product.priceFormatStyle.currencyCode == "JPY" {
            return NSDecimalNumber(decimal: product.price).intValue
        }
        return Self.referencePriceJPY(productID: product.id)
    }

    /// 台帳に記録する価格（円）。JPY 決済なら実価格、それ以外は参考価格。
    nonisolated private static func priceJPY(of transaction: Transaction) -> Int {
        if let price = transaction.price, transaction.currency?.identifier == "JPY" {
            return NSDecimalNumber(decimal: price).intValue
        }
        return referencePriceJPY(productID: transaction.productID) * max(1, transaction.purchasedQuantity)
    }

    // MARK: - 付与（StoreKit 非依存・冪等）

    /// 検証済みトランザクションをプロフィールへ反映する。同じ transactionID は二度付与しない。
    nonisolated static func applyTransaction(transactionID: UInt64, productID: String, priceJPY: Int, quantity: Int = 1,
                                 purchaseDate: Date, revocationDate: Date?,
                                 to profile: inout Profile) -> LedgerGrantResult {
        let isPremium = productID == premiumPassProductID
        let gemProduct = gemProduct(productID)
        guard isPremium || gemProduct != nil else { return .unknownProduct }

        if revocationDate != nil {
            return revoke(transactionID: transactionID, productID: productID, purchaseDate: purchaseDate, to: &profile)
        }
        if let existing = profile.purchaseLedger.first(where: { $0.transactionID == transactionID }) {
            return existing.revoked ? .alreadyRevoked : .alreadyProcessed
        }
        let monthKey = LiveOpsService.monthKey(purchaseDate)
        profile.monthlySpendJPY[monthKey, default: 0] += max(0, priceJPY)
        if isPremium {
            profile.pass.hasPremium = true
            profile.purchaseLedger.append(PurchaseRecord(transactionID: transactionID, productID: productID,
                                                         gemsGranted: 0, priceJPY: priceJPY, date: purchaseDate))
            return .grantedPremiumPass
        }
        let gems = (gemProduct!.gems + gemProduct!.bonusGems) * max(1, quantity)
        profile.paidGem += gems
        profile.purchaseLedger.append(PurchaseRecord(transactionID: transactionID, productID: productID,
                                                     gemsGranted: gems, priceJPY: priceJPY, date: purchaseDate))
        return .grantedGems(gems)
    }

    /// 返金・取り消し。未消費の有償 Gem を付与数まで回収する（消費済み分は回収しない）。
    nonisolated private static func revoke(transactionID: UInt64, productID: String, purchaseDate: Date,
                               to profile: inout Profile) -> LedgerGrantResult {
        guard let i = profile.purchaseLedger.firstIndex(where: { $0.transactionID == transactionID }) else {
            // 付与前に取り消された: 以後の再配信で付与しないよう取り消し済みとして記録する
            profile.purchaseLedger.append(PurchaseRecord(transactionID: transactionID, productID: productID,
                                                         gemsGranted: 0, priceJPY: 0, date: purchaseDate, revoked: true))
            return .revoked(removedGems: 0)
        }
        guard !profile.purchaseLedger[i].revoked else { return .alreadyRevoked }
        profile.purchaseLedger[i].revoked = true
        if productID == premiumPassProductID {
            let stillOwned = profile.purchaseLedger.contains {
                $0.productID == premiumPassProductID && !$0.revoked
            }
            if !stillOwned { profile.pass.hasPremium = false }
            return .revoked(removedGems: 0)
        }
        let removed = min(profile.paidGem, profile.purchaseLedger[i].gemsGranted)
        profile.paidGem -= removed
        return .revoked(removedGems: removed)
    }

    /// 権利の復元（台帳に無ければ記録を追加。月間課金額は購入月に計上）。
    nonisolated static func restorePremium(transactionID: UInt64, priceJPY: Int, purchaseDate: Date, to profile: inout Profile) {
        if let existing = profile.purchaseLedger.first(where: { $0.transactionID == transactionID }) {
            if !existing.revoked { profile.pass.hasPremium = true }
            return
        }
        _ = applyTransaction(transactionID: transactionID, productID: premiumPassProductID, priceJPY: priceJPY,
                             purchaseDate: purchaseDate, revocationDate: nil, to: &profile)
    }
}
