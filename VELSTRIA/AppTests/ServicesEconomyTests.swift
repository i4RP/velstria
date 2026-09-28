import XCTest
@testable import VELSTRIA
import VelstriaCore

final class ServicesEconomyTests: XCTestCase {
    private let master = ServicesFixtures.master

    func testCatalogHelpers() {
        XCTAssertEqual(EconomyService.storeItems(ofType: .cosmetic).count, 72)
        XCTAssertEqual(EconomyService.storeItems(ofType: .heroUnlock).count, 24)
        XCTAssertEqual(EconomyService.storeItems(ofType: .bundle).count, 18)
        XCTAssertEqual(EconomyService.cosmetics(ofType: .heroSkin).count, 12)
        XCTAssertEqual(EconomyService.cosmetics(ofType: .avatarFrame).count, 12)
        XCTAssertEqual(EconomyService.storeItem(forCosmetic: "CO004")?.sku, "SKU004")
        XCTAssertEqual(EconomyService.storeItem(forHero: "H007")?.sku, "SKU079")
        XCTAssertEqual(EconomyService.gemPrice(ofCosmetic: "CO004"), 880)
        XCTAssertEqual(EconomyService.duplicateRefundGems(cosmeticID: "CO002"), 130)
    }

    func testHeroPriceMultiplierAndCoinPurchase() {
        let item = master.storeItem("SKU079")!
        XCTAssertEqual(EconomyService.price(of: item), 3011) // 12043 × 0.25 = 3010.75
        var p = Profile()
        p.starlightCoin = 3010
        XCTAssertFalse(EconomyService.canAfford(item, profile: p))
        XCTAssertEqual(EconomyService.purchase(sku: "SKU079", profile: &p, master: master), .insufficientFunds)
        XCTAssertEqual(p.starlightCoin, 3010)
        p.starlightCoin = 5000
        XCTAssertTrue(EconomyService.canAfford(item, profile: p))
        XCTAssertEqual(EconomyService.purchase(sku: "SKU079", profile: &p, master: master), .success(granted: ["H007"]))
        XCTAssertEqual(p.starlightCoin, 5000 - 3011)
        XCTAssertTrue(EconomyService.isOwned(heroID: "H007", profile: p))
        XCTAssertEqual(EconomyService.purchaseCount(sku: "SKU079", profile: p), 1)
        XCTAssertEqual(EconomyService.purchase(sku: "SKU079", profile: &p, master: master), .alreadyOwned)
        // 初期所持ヒーローは購入不可
        XCTAssertEqual(EconomyService.purchase(sku: "SKU073", profile: &p, master: master), .alreadyOwned)
    }

    func testGemSpendOrderFreeThenPaid() {
        var p = Profile()
        p.freeGem = 100
        p.paidGem = 200
        XCTAssertEqual(EconomyService.purchase(sku: "SKU001", profile: &p, master: master), .success(granted: ["CO001"]))
        XCTAssertEqual(p.freeGem, 0)
        XCTAssertEqual(p.paidGem, 180)
        XCTAssertFalse(EconomyService.spendGems(181, profile: &p))
        XCTAssertEqual(p.paidGem, 180)
        XCTAssertFalse(EconomyService.spendGems(-5, profile: &p))
        p.freeGem = 50
        XCTAssertTrue(EconomyService.spendGems(60, profile: &p))
        XCTAssertEqual(p.freeGem, 0)
        XCTAssertEqual(p.paidGem, 170)
    }

    func testCosmeticPurchaseLimitsAndOwnership() {
        var p = Profile()
        p.freeGem = 5000
        XCTAssertEqual(EconomyService.purchase(sku: "SKU002", profile: &p, master: master), .success(granted: ["CO002"]))
        XCTAssertEqual(EconomyService.purchase(sku: "SKU002", profile: &p, master: master), .alreadyOwned)
        // 購入回数が上限に達していれば（所持していなくても）購入不可
        var q = Profile()
        q.freeGem = 5000
        q.storePurchases = [StorePurchaseCount(sku: "SKU003", count: 1)]
        let item = master.storeItem("SKU003")!
        XCTAssertEqual(EconomyService.remainingPurchases(item, profile: q), 0)
        XCTAssertEqual(EconomyService.purchase(sku: "SKU003", profile: &q, master: master), .limitReached)
        XCTAssertEqual(q.freeGem, 5000)
        XCTAssertEqual(EconomyService.purchase(sku: "NOPE", profile: &q, master: master), .invalid)
    }

    func testBundleMappingIsDeterministicAndCoversCatalog() {
        XCTAssertEqual(EconomyService.bundleContents("BUNDLE_01", master: master), ["CO001", "CO002", "CO003", "CO004"])
        XCTAssertEqual(EconomyService.bundleContents("BUNDLE_18", master: master), ["CO069", "CO070", "CO071", "CO072"])
        XCTAssertEqual(EconomyService.bundleContents("BUNDLE_00", master: master), [])
        XCTAssertEqual(EconomyService.bundleContents("CO001", master: master), [])
        var all: [String] = []
        for item in EconomyService.storeItems(ofType: .bundle) {
            let contents = EconomyService.bundleContents(item.grantID, master: master)
            XCTAssertEqual(contents.count, 4)
            XCTAssertEqual(Set(contents).count, 4, "バンドル内の重複なし")
            let rarities = Set(contents.compactMap { master.cosmetic($0)?.rarity })
            XCTAssertEqual(rarities.count, 4, "各レア度 1 個ずつ")
            all += contents
        }
        XCTAssertEqual(Set(all).count, 72)
    }

    func testBundlePurchaseRefundsDuplicates() {
        var p = Profile()
        p.freeGem = 2000
        p.ownedCosmeticIDs = ["CO002"]
        let item = master.storeItem("SKU097")!
        let preview = EconomyService.bundlePreview(item, profile: p)
        XCTAssertEqual(preview.newItems, ["CO001", "CO003", "CO004"])
        XCTAssertEqual(preview.duplicates, ["CO002"])
        XCTAssertEqual(preview.refundGems, 130)
        XCTAssertEqual(preview.totalValueGems, 120 + 260 + 520 + 880)
        XCTAssertFalse(EconomyService.isOwned(item, profile: p))
        XCTAssertEqual(EconomyService.purchase(sku: "SKU097", profile: &p, master: master),
                       .success(granted: ["CO001", "CO003", "CO004"]))
        XCTAssertEqual(p.freeGem, 2000 - 1331 + 130)
        XCTAssertEqual(p.ownedCosmeticIDs.sorted(), ["CO001", "CO002", "CO003", "CO004"])
        XCTAssertEqual(EconomyService.purchaseCount(sku: "SKU097", profile: p), 1)
        // 中身をすべて所持したら購入不可
        XCTAssertTrue(EconomyService.isOwned(item, profile: p))
        XCTAssertEqual(EconomyService.purchase(sku: "SKU097", profile: &p, master: master), .alreadyOwned)
    }

    func testEquipCosmetics() {
        var p = Profile()
        XCTAssertFalse(EconomyService.equip(cosmeticID: "CO001", profile: &p), "未所持は装備不可")
        p.ownedCosmeticIDs = ["CO001", "CO002", "CO004", "CO010", "CO016", "CO022", "CO028", "CO005"]
        XCTAssertTrue(EconomyService.equip(cosmeticID: "CO001", profile: &p))
        XCTAssertEqual(p.equippedSkins["H001"], "CO001")
        XCTAssertTrue(EconomyService.equip(cosmeticID: "CO002", profile: &p))
        XCTAssertEqual(p.equippedRecall, "CO002")
        XCTAssertTrue(EconomyService.equip(cosmeticID: "CO005", profile: &p))
        XCTAssertEqual(p.equippedAvatarFrame, "CO005")
        for id in ["CO004", "CO010", "CO016", "CO022", "CO028"] {
            XCTAssertTrue(EconomyService.equip(cosmeticID: id, profile: &p))
        }
        XCTAssertEqual(p.equippedEmotes, ["CO010", "CO016", "CO022", "CO028"])
        XCTAssertTrue(EconomyService.isEquipped(cosmeticID: "CO028", profile: p))
        EconomyService.unequip(cosmeticID: "CO028", profile: &p)
        XCTAssertFalse(EconomyService.isEquipped(cosmeticID: "CO028", profile: p))
        EconomyService.unequip(cosmeticID: "CO001", profile: &p)
        XCTAssertNil(p.equippedSkins["H001"])
    }
}
