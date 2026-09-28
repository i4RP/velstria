import XCTest
@testable import VELSTRIA
import VelstriaCore

final class ServicesStoreKitTests: XCTestCase {
    private let purchaseDate = ServicesFixtures.date(2026, 10, 7)

    private func grant(_ id: UInt64, _ product: String, price: Int = 800, revoked: Date? = nil,
                       _ p: inout Profile) -> LedgerGrantResult {
        StoreKitService.applyTransaction(transactionID: id, productID: product, priceJPY: price,
                                         purchaseDate: purchaseDate, revocationDate: revoked, to: &p)
    }

    func testGemGrantIsIdempotentByTransactionID() {
        var p = Profile()
        XCTAssertEqual(grant(1001, "com.velstria.game.gem.300", &p), .grantedGems(330))
        XCTAssertEqual(p.paidGem, 330)
        XCTAssertEqual(p.freeGem, 0)
        XCTAssertEqual(p.purchaseLedger.count, 1)
        XCTAssertEqual(p.purchaseLedger[0].gemsGranted, 330)
        XCTAssertEqual(p.monthlySpendJPY["2026-10"], 800)
        // 再配信（Transaction.updates / unfinished）でも二重付与しない
        XCTAssertEqual(grant(1001, "com.velstria.game.gem.300", &p), .alreadyProcessed)
        XCTAssertEqual(p.paidGem, 330)
        XCTAssertEqual(p.purchaseLedger.count, 1)
        XCTAssertEqual(p.monthlySpendJPY["2026-10"], 800)
        // 別トランザクションは付与
        XCTAssertEqual(grant(1002, "com.velstria.game.gem.60", price: 160, &p), .grantedGems(60))
        XCTAssertEqual(p.paidGem, 390)
        XCTAssertEqual(p.monthlySpendJPY["2026-10"], 960)
        XCTAssertEqual(grant(1003, "com.example.other", &p), .unknownProduct)
        XCTAssertEqual(p.purchaseLedger.count, 2)
    }

    func testAllGemProductsIncludeBonus() {
        for product in StoreKitService.gemProducts {
            var p = Profile()
            XCTAssertEqual(grant(7, product.productID, price: product.referencePriceJPY, &p),
                           .grantedGems(product.gems + product.bonusGems))
        }
        XCTAssertEqual(StoreKitService.allProductIDs.count, 7)
    }

    func testPremiumPassGrantAndRestore() {
        var p = Profile()
        XCTAssertEqual(grant(2001, StoreKitService.premiumPassProductID, price: 980, &p), .grantedPremiumPass)
        XCTAssertTrue(p.pass.hasPremium)
        XCTAssertEqual(p.paidGem, 0)
        XCTAssertEqual(grant(2001, StoreKitService.premiumPassProductID, price: 980, &p), .alreadyProcessed)
        // インポート等で hasPremium が落ちていても権利から復元
        p.pass.hasPremium = false
        StoreKitService.restorePremium(transactionID: 2001, priceJPY: 980, purchaseDate: purchaseDate, to: &p)
        XCTAssertTrue(p.pass.hasPremium)
        XCTAssertEqual(p.purchaseLedger.count, 1)
        // 別端末からの復元（台帳なし）
        var q = Profile()
        StoreKitService.restorePremium(transactionID: 2001, priceJPY: 980, purchaseDate: purchaseDate, to: &q)
        XCTAssertTrue(q.pass.hasPremium)
        XCTAssertEqual(q.purchaseLedger.count, 1)
        StoreKitService.restorePremium(transactionID: 2001, priceJPY: 980, purchaseDate: purchaseDate, to: &q)
        XCTAssertEqual(q.purchaseLedger.count, 1)
    }

    func testRevocationRemovesUnspentPaidGems() {
        var p = Profile()
        _ = grant(3001, "com.velstria.game.gem.980", price: 2500, &p) // 1090
        XCTAssertTrue(EconomyService.spendGems(1000, profile: &p))
        XCTAssertEqual(p.paidGem, 90)
        XCTAssertEqual(grant(3001, "com.velstria.game.gem.980", revoked: Date(), &p), .revoked(removedGems: 90))
        XCTAssertEqual(p.paidGem, 0)
        XCTAssertTrue(p.purchaseLedger[0].revoked)
        XCTAssertEqual(grant(3001, "com.velstria.game.gem.980", revoked: Date(), &p), .alreadyRevoked)
        XCTAssertEqual(grant(3001, "com.velstria.game.gem.980", &p), .alreadyRevoked)
        XCTAssertEqual(p.paidGem, 0)

        // 無償 Gem は回収しない
        var q = Profile()
        q.freeGem = 500
        _ = grant(3002, "com.velstria.game.gem.300", &q)
        XCTAssertEqual(grant(3002, "com.velstria.game.gem.300", revoked: Date(), &q), .revoked(removedGems: 330))
        XCTAssertEqual(q.freeGem, 500)

        // 付与前に取り消されたトランザクションは後から届いても付与しない
        var r = Profile()
        XCTAssertEqual(grant(3003, "com.velstria.game.gem.60", revoked: Date(), &r), .revoked(removedGems: 0))
        XCTAssertEqual(grant(3003, "com.velstria.game.gem.60", &r), .alreadyRevoked)
        XCTAssertEqual(r.paidGem, 0)

        // プレミアムの取り消し
        var s = Profile()
        _ = grant(3004, StoreKitService.premiumPassProductID, price: 980, &s)
        XCTAssertEqual(grant(3004, StoreKitService.premiumPassProductID, revoked: Date(), &s), .revoked(removedGems: 0))
        XCTAssertFalse(s.pass.hasPremium)
    }

    func testMonthlyLimitByAgeBracket() {
        let now = ServicesFixtures.date(2026, 10, 20)
        var p = Profile()
        XCTAssertEqual(StoreKitService.remainingMonthlyAllowance(profile: p, now: now), 5000, "未設定は最も厳しい区分")
        p.ageBracket = .age13to15
        p.monthlySpendJPY["2026-10"] = 4500
        p.monthlySpendJPY["2026-09"] = 5000
        XCTAssertEqual(StoreKitService.remainingMonthlyAllowance(profile: p, now: now), 500)
        XCTAssertTrue(StoreKitService.isWithinMonthlyLimit(priceJPY: 160, profile: p, now: now))
        XCTAssertFalse(StoreKitService.isWithinMonthlyLimit(priceJPY: 800, profile: p, now: now))
        p.ageBracket = .age16to19
        XCTAssertEqual(StoreKitService.remainingMonthlyAllowance(profile: p, now: now), 5500)
        p.ageBracket = .adult
        XCTAssertNil(StoreKitService.remainingMonthlyAllowance(profile: p, now: now))
        XCTAssertTrue(StoreKitService.isWithinMonthlyLimit(priceJPY: 1_000_000, profile: p, now: now))
        // 翌月はリセット
        p.ageBracket = .under13
        XCTAssertEqual(StoreKitService.remainingMonthlyAllowance(profile: p, now: ServicesFixtures.date(2026, 11, 1)), 5000)
        // 上限を超えた記録があっても負にならない
        p.monthlySpendJPY["2026-10"] = 9000
        XCTAssertEqual(StoreKitService.remainingMonthlyAllowance(profile: p, now: now), 0)
    }

    func testReferencePrices() {
        XCTAssertEqual(StoreKitService.referencePriceJPY(productID: StoreKitService.premiumPassProductID), 980)
        XCTAssertEqual(StoreKitService.referencePriceJPY(productID: "com.velstria.game.gem.6480"), 15800)
        XCTAssertEqual(StoreKitService.referencePriceJPY(productID: "unknown"), 0)
    }

    /// StoreKit 構成ファイル（Velstria.storekit）の構造と商品定義がコードの定義と一致すること。
    /// （ヘッドレスの xcodebuild では SKTestSession が構成を適用しないため、JSON として検証する）
    func testStoreKitConfigurationMatchesProductDefinitions() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../App/Resources/Velstria.storekit").standardizedFileURL
        let url = FileManager.default.fileExists(atPath: source.path)
            ? source : Bundle.main.url(forResource: "Velstria", withExtension: "storekit")
        guard let url else { throw XCTSkip("Velstria.storekit が見つからない") }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let version = try XCTUnwrap(root["version"] as? [String: Any])
        XCTAssertEqual(version["major"] as? Int, 4)
        XCTAssertNotNil(root["identifier"] as? String)
        let settings = try XCTUnwrap(root["settings"] as? [String: Any])
        XCTAssertEqual(settings["_storefront"] as? String, "JPN")
        XCTAssertEqual((root["subscriptionGroups"] as? [Any])?.count, 0)
        let products = try XCTUnwrap(root["products"] as? [[String: Any]])
        XCTAssertEqual(products.count, 7)
        XCTAssertEqual(Set(products.compactMap { $0["internalID"] as? String }).count, 7, "internalID は一意")
        func product(_ id: String) throws -> [String: Any] {
            try XCTUnwrap(products.first { $0["productID"] as? String == id }, id)
        }
        for gem in StoreKitService.gemProducts {
            let p = try product(gem.productID)
            XCTAssertEqual(p["type"] as? String, "Consumable")
            XCTAssertEqual(p["displayPrice"] as? String, String(gem.referencePriceJPY))
            let locales = (p["localizations"] as? [[String: Any]])?.compactMap { $0["locale"] as? String }
            XCTAssertEqual(Set(locales ?? []), ["ja", "en_US"])
        }
        let pass = try product(StoreKitService.premiumPassProductID)
        XCTAssertEqual(pass["type"] as? String, "NonConsumable")
        XCTAssertEqual(pass["displayPrice"] as? String, String(StoreKitService.premiumPassReferencePriceJPY))
        XCTAssertEqual(pass["familyShareable"] as? Bool, false)
    }
}
