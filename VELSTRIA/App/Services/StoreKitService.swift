import Foundation
import StoreKit
import VelstriaCore

// 担当: app-services（最小実装。StoreKit 2 の商品取得・購入・検証・冪等付与・finish・未完了/返金監視・
// 復元・年齢別月間上限を実装すること）

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

@Observable
@MainActor
final class StoreKitService {
    static let gemProducts: [GemProduct] = [
        GemProduct(productID: "com.velstria.game.gem.60", gems: 60, bonusGems: 0, referencePriceJPY: 160),
        GemProduct(productID: "com.velstria.game.gem.300", gems: 300, bonusGems: 30, referencePriceJPY: 800),
        GemProduct(productID: "com.velstria.game.gem.980", gems: 980, bonusGems: 110, referencePriceJPY: 2500),
        GemProduct(productID: "com.velstria.game.gem.1980", gems: 1980, bonusGems: 260, referencePriceJPY: 4900),
        GemProduct(productID: "com.velstria.game.gem.3280", gems: 3280, bonusGems: 600, referencePriceJPY: 8000),
        GemProduct(productID: "com.velstria.game.gem.6480", gems: 6480, bonusGems: 1600, referencePriceJPY: 15800),
    ]
    static let premiumPassProductID = "com.velstria.game.pass.premium"

    /// 取得済み StoreKit 商品（productID → Product）。
    var products: [String: Product] = [:]
    var isLoading = false
    var lastError: String?

    @ObservationIgnored private weak var app: AppModel?

    init() {}

    func attach(to app: AppModel) {
        self.app = app
    }

    /// 商品取得とトランザクション監視の開始。
    func start() async {
    }

    func purchase(productID: String) async -> IAPResult {
        .failed("not implemented")
    }

    func restore() async -> Bool {
        false
    }
}
