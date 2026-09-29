import XCTest
@testable import VELSTRIA
import VelstriaCore

// 担当: ui-collection。ストア・コスメ画面の分類/装備/表示ロジックの検証。

@MainActor
final class CollectionStoreLogicTests: XCTestCase {
    let master = MasterData.shared

    override func setUp() {
        super.setUp()
        Loc.current = .ja
    }

    func testCategoryContents() {
        XCTAssertEqual(StoreCatalog.items(in: .skins, master: master).count, 12)
        XCTAssertEqual(StoreCatalog.items(in: .effects, master: master).count, 36)
        XCTAssertEqual(StoreCatalog.items(in: .emotes, master: master).count, 12)
        XCTAssertEqual(StoreCatalog.items(in: .frames, master: master).count, 12)
        XCTAssertEqual(StoreCatalog.items(in: .heroes, master: master).count, 24)
        XCTAssertTrue(StoreCatalog.items(in: .gems, master: master).isEmpty)
        XCTAssertEqual(StoreCatalog.bundles(master: master).count, 18)
        for c in StoreCategory.allCases {
            XCTAssertFalse(c.title.isEmpty)
            XCTAssertFalse(c.subtitle.isEmpty)
        }
    }

    func testFeaturedBundlesRotateDaily() {
        let day0 = StoreCatalog.featuredBundles(master: master, day: 0, count: 5)
        XCTAssertEqual(day0.map(\.sku), ["SKU097", "SKU098", "SKU099", "SKU100", "SKU101"])
        let day17 = StoreCatalog.featuredBundles(master: master, day: 17, count: 3)
        XCTAssertEqual(day17.map(\.sku), ["SKU114", "SKU097", "SKU098"])
        XCTAssertEqual(StoreCatalog.featuredBundles(master: master, day: -1, count: 1).map(\.sku), ["SKU114"])
        XCTAssertEqual(StoreCatalog.featuredBundles(master: master, day: 18, count: 5), day0)
    }

    func testLookupHelpers() {
        XCTAssertEqual(StoreCatalog.storeItem(forCosmetic: "CO001", master: master)?.sku, "SKU001")
        XCTAssertEqual(StoreCatalog.unlockItem(heroID: "H007", master: master)?.sku, "SKU079")
        XCTAssertNil(StoreCatalog.unlockItem(heroID: "H999", master: master))
        XCTAssertEqual(StoreCatalog.cosmetic(for: master.storeItem("SKU004")!, master: master)?.type, .emote)
        XCTAssertNil(StoreCatalog.cosmetic(for: master.storeItem("SKU079")!, master: master))
    }

    func testGemSplitSpendsFreeFirst() {
        var p = Profile()
        p.freeGem = 50
        p.paidGem = 100
        let split = StoreCatalog.gemSplit(cost: 120, profile: p)
        XCTAssertEqual(split.free, 50)
        XCTAssertEqual(split.paid, 70)
        let small = StoreCatalog.gemSplit(cost: 30, profile: p)
        XCTAssertEqual(small.free, 30)
        XCTAssertEqual(small.paid, 0)
    }

    func testAvailabilityAndAffordability() throws {
        var p = Profile()
        let skin = try XCTUnwrap(master.storeItem("SKU001"))
        XCTAssertFalse(StoreCatalog.isUnavailable(skin, profile: p))
        XCTAssertFalse(StoreCatalog.canAfford(skin, profile: p))
        p.freeGem = EconomyService.price(of: skin)
        XCTAssertTrue(StoreCatalog.canAfford(skin, profile: p))
        p.ownedCosmeticIDs.append("CO001")
        XCTAssertTrue(StoreCatalog.isUnavailable(skin, profile: p))

        let bundle = try XCTUnwrap(master.storeItem("SKU097"))
        p.storePurchases = [StorePurchaseCount(sku: "SKU097", count: bundle.purchaseLimit)]
        XCTAssertEqual(StoreCatalog.purchaseCount(sku: "SKU097", profile: p), bundle.purchaseLimit)
        XCTAssertTrue(StoreCatalog.isUnavailable(bundle, profile: p))

        let unlock = try XCTUnwrap(master.storeItem("SKU079"))
        XCTAssertEqual(StoreCatalog.balance(unlock.currency, profile: p), p.starlightCoin)
        XCTAssertNil(StoreCatalog.rarity(of: unlock, master: master))
        XCTAssertEqual(StoreCatalog.rarity(of: skin, master: master), .common)
    }

    func testCosmeticVariantsAndOrdinals() throws {
        XCTAssertEqual(CosmeticInfo.variant(of: try XCTUnwrap(master.cosmetic("CO001"))), 0)
        XCTAssertEqual(CosmeticInfo.variant(of: try XCTUnwrap(master.cosmetic("CO025"))), 1)
        XCTAssertEqual(CosmeticInfo.variant(of: try XCTUnwrap(master.cosmetic("CO072"))), 2)
        XCTAssertEqual(CosmeticInfo.ordinal(of: try XCTUnwrap(master.cosmetic("CO004")), master: master), 0)
        XCTAssertEqual(CosmeticInfo.ordinal(of: try XCTUnwrap(master.cosmetic("CO010")), master: master), 1)
        // エモートの記号は種類内で重複しない
        let emotes = master.cosmetics.filter { $0.type == .emote }
        let symbols = emotes.map { CosmeticInfo.emoteSymbol($0, master: master) }
        XCTAssertEqual(Set(symbols).count, emotes.count)
        XCTAssertEqual(CosmeticInfo.skins(heroID: "H001", master: master).map(\.cosmeticID), ["CO001", "CO025", "CO049"])
        XCTAssertTrue(CosmeticInfo.skins(heroID: "H002", master: master).isEmpty)
    }

    func testEquipAndUnequipEachType() throws {
        var p = Profile()
        let skin = try XCTUnwrap(master.cosmetic("CO007"))
        XCTAssertFalse(CosmeticInfo.equip(skin, profile: &p), "未所持は装備できない")
        p.ownedCosmeticIDs = ["CO007", "CO002", "CO003", "CO005", "CO006"]
        XCTAssertTrue(CosmeticInfo.equip(skin, profile: &p))
        XCTAssertEqual(p.equippedSkins["H007"], "CO007")
        XCTAssertTrue(CosmeticInfo.isEquipped(skin, profile: p))
        for id in ["CO002", "CO003", "CO005", "CO006"] {
            let c = try XCTUnwrap(master.cosmetic(id))
            XCTAssertTrue(CosmeticInfo.equip(c, profile: &p))
            XCTAssertTrue(CosmeticInfo.isEquipped(c, profile: p))
            XCTAssertEqual(CosmeticInfo.equippedID(c.type, profile: p), id)
        }
        XCTAssertEqual(p.equippedRecall, "CO002")
        XCTAssertEqual(p.equippedSpawn, "CO003")
        XCTAssertEqual(p.equippedAvatarFrame, "CO005")
        XCTAssertEqual(p.equippedKillEffect, "CO006")
        CosmeticInfo.unequip(.heroSkin, heroID: "H007", profile: &p)
        CosmeticInfo.unequip(.recall, profile: &p)
        XCTAssertNil(p.equippedSkins["H007"])
        XCTAssertNil(p.equippedRecall)
    }

    func testEquipEmoteFillsFirstEmptySlot() throws {
        var p = Profile()
        let ids = ["CO004", "CO010", "CO016", "CO022", "CO028"]
        p.ownedCosmeticIDs = ids
        for id in ids.prefix(4) {
            XCTAssertTrue(CosmeticInfo.equip(try XCTUnwrap(master.cosmetic(id)), profile: &p))
        }
        XCTAssertEqual(p.equippedEmotes, ["CO004", "CO010", "CO016", "CO022"])
        // 既に装備済みは成功扱い、満杯なら失敗
        XCTAssertTrue(CosmeticInfo.equip(try XCTUnwrap(master.cosmetic("CO010")), profile: &p))
        XCTAssertFalse(CosmeticInfo.equip(try XCTUnwrap(master.cosmetic("CO028")), profile: &p))
        XCTAssertEqual(p.equippedEmotes.count, 4)
        // 外すと空き枠ができ、次の装備は末尾へ入る
        CosmeticInfo.unequip(.emote, profile: &p)
        XCTAssertEqual(p.equippedEmotes, [])
        XCTAssertTrue(CosmeticInfo.equip(try XCTUnwrap(master.cosmetic("CO028")), profile: &p))
        XCTAssertEqual(p.equippedEmotes, ["CO028"])
    }

    func testIAPMessages() {
        XCTAssertNil(IAPResultText.message(for: .cancelled, bracket: .adult, remaining: nil))
        let success = IAPResultText.message(for: .success(gems: 330), bracket: .adult, remaining: nil)
        XCTAssertEqual(success?.isError, false)
        XCTAssertTrue(success?.body.contains("330") == true)
        let limit = IAPResultText.message(for: .limitExceeded, bracket: .age13to15, remaining: 1200)
        XCTAssertEqual(limit?.isError, true)
        XCTAssertTrue(limit?.body.contains("5,000") == true)
        XCTAssertTrue(limit?.body.contains("1,200") == true)
        XCTAssertTrue(IAPResultText.monthlyLimitDescription(.age16to19)?.contains("10,000") == true)
        XCTAssertNil(IAPResultText.monthlyLimitDescription(.adult))
        XCTAssertNil(IAPResultText.monthlyLimitDescription(nil))
        XCTAssertNotNil(IAPResultText.message(for: .pending, bracket: nil, remaining: nil))
        XCTAssertEqual(IAPResultText.message(for: .failed("x"), bracket: nil, remaining: nil)?.isError, true)
        XCTAssertTrue(IAPResultText.exceedsLimit(priceJPY: 2500, remaining: 2000))
        XCTAssertFalse(IAPResultText.exceedsLimit(priceJPY: 2500, remaining: nil))
    }

    func testLegalNoticesArePresentInBothLanguages() {
        XCTAssertTrue(StoreLegalText.paymentServicesAct.contains { $0.value.contains("有効期限はありません") })
        XCTAssertTrue(StoreLegalText.commercialTransactions.contains { $0.label == "返品・キャンセル" })
        // docs/legal と同じ表示事項（苦情窓口・残高確認・端末内保存の注意・販売数量の制限）
        let psa = StoreLegalText.paymentServicesAct
        XCTAssertTrue(psa.contains { $0.label == "苦情・相談窓口" && $0.value.contains(FeatureFlags.supportEmail) })
        XCTAssertTrue(psa.contains { $0.label == "残高の確認方法" })
        XCTAssertTrue(psa.contains { $0.value.contains("端末内に保存") })
        XCTAssertTrue(psa.contains { $0.value == FeatureFlags.termsURL.absoluteString })
        XCTAssertTrue(StoreLegalText.monthlyLimitSummary.contains("5,000"))
        XCTAssertTrue(StoreLegalText.monthlyLimitSummary.contains("10,000"))
        XCTAssertTrue(StoreLegalText.commercialTransactions.contains { $0.value == StoreLegalText.monthlyLimitSummary })
        XCTAssertTrue(psa.contains { $0.value == StoreLegalText.issuerName })
        XCTAssertEqual(Set(psa.map(\.id)).count, psa.count)
        Loc.current = .en
        defer { Loc.current = .ja }
        XCTAssertTrue(StoreLegalText.paymentServicesAct.contains { $0.value.contains("No expiration") })
        XCTAssertEqual(Set(StoreLegalText.commercialTransactions.map(\.id)).count, StoreLegalText.commercialTransactions.count)
    }

    func testProductDescriptionsExistForEveryStoreItem() {
        for item in master.store {
            XCTAssertFalse(ProductDetailView.description(item, master: master, lang: .ja).isEmpty, item.sku)
            XCTAssertFalse(ProductDetailView.description(item, master: master, lang: .en).isEmpty, item.sku)
            XCTAssertFalse(StoreCatalog.typeLabel(item, master: master).isEmpty)
        }
    }

    func testPolicyRowsFollowLanguage() throws {
        let skin = try XCTUnwrap(master.storeItem("SKU001"))
        let ja = StoreCatalog.policyRows(skin)
        XCTAssertEqual(ja.count, 3)
        XCTAssertTrue(ja.contains { $0.value == skin.refundPolicy })
        XCTAssertTrue(ja.contains { $0.value.contains("1 回まで") })
        let bundle = try XCTUnwrap(master.storeItem("SKU097"))
        XCTAssertTrue(StoreCatalog.policyRows(bundle).contains { $0.value.contains("5 回まで") })
        Loc.current = .en
        defer { Loc.current = .ja }
        let en = StoreCatalog.policyRows(skin)
        XCTAssertEqual(en.count, 3)
        XCTAssertFalse(en.contains { $0.value == skin.refundPolicy })
        XCTAssertTrue(en.contains { $0.label == "Refunds" })
    }

    func testDuplicateRuleIsResolvedPerProductType() throws {
        // マスターの「購入不可または同価値通貨へ変換」をそのまま出さず、種別ごとの確定ルールを表示する
        let skin = try XCTUnwrap(master.storeItem("SKU001"))
        let unlock = try XCTUnwrap(master.storeItem("SKU079"))
        let bundle = try XCTUnwrap(master.storeItem("SKU097"))
        for item in [skin, unlock, bundle] {
            let row = try XCTUnwrap(StoreCatalog.policyRows(item).first { $0.label == "重複時の扱い" })
            XCTAssertEqual(row.value, StoreCatalog.duplicateRule(item))
            XCTAssertNotEqual(row.value, item.duplicatePolicy)
            XCTAssertFalse(row.value.contains("同価値"))
        }
        XCTAssertTrue(StoreCatalog.duplicateRule(skin).contains("購入できません"))
        XCTAssertTrue(StoreCatalog.duplicateRule(bundle).contains("無償 AstralGem"))
        Loc.current = .en
        defer { Loc.current = .ja }
        XCTAssertTrue(StoreCatalog.duplicateRule(unlock).hasPrefix("Can't be purchased"))
    }

    func testOwnedBundleContentsListsOnlyOwnedCosmeticsInsideBundles() throws {
        let bundle = try XCTUnwrap(master.storeItem("SKU097"))
        let contents = EconomyService.bundleContents(bundle.grantID, master: master)
        var p = Profile()
        XCTAssertEqual(StoreCatalog.ownedBundleContents(bundle, profile: p, master: master), [])
        p.ownedCosmeticIDs = Array(contents.prefix(1)) + ["CO999"]
        XCTAssertEqual(StoreCatalog.ownedBundleContents(bundle, profile: p, master: master), Array(contents.prefix(1)))
        // バンドル以外は常に空
        p.ownedCosmeticIDs = ["CO001"]
        XCTAssertEqual(StoreCatalog.ownedBundleContents(try XCTUnwrap(master.storeItem("SKU001")), profile: p, master: master), [])
    }

    func testProductDescriptionUsesHeroNames() throws {
        let unlock = try XCTUnwrap(master.storeItem("SKU079"))
        XCTAssertTrue(ProductDetailView.description(unlock, master: master, lang: .ja).hasPrefix("岩脈のガルク"))
        XCTAssertTrue(ProductDetailView.description(unlock, master: master, lang: .en).contains("Garruk"))
        let bundle = try XCTUnwrap(master.storeItem("SKU097"))
        XCTAssertFalse(ProductDetailView.description(bundle, master: master, lang: .ja).contains("同価値"))
    }

    func testLedgerSortingAndNames() {
        let old = PurchaseRecord(transactionID: 1, productID: "com.velstria.game.gem.300", gemsGranted: 330, priceJPY: 800,
                                 date: Date(timeIntervalSince1970: 1_000))
        let new = PurchaseRecord(transactionID: 2, productID: StoreKitService.premiumPassProductID, gemsGranted: 0, priceJPY: 980,
                                 date: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(PurchaseLedgerText.sorted([old, new]).map(\.transactionID), [2, 1])
        XCTAssertEqual(PurchaseLedgerText.productName("com.velstria.game.gem.300"), "AstralGem ×330")
        XCTAssertEqual(PurchaseLedgerText.productName("unknown.id"), "unknown.id")
    }

    func testPurchaseFailureMessages() {
        let all: [StorePurchaseFailure] = [.insufficient(.astralGem), .insufficient(.starlightCoin), .owned, .limit, .invalid]
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        for f in all {
            XCTAssertFalse(f.title.isEmpty)
            XCTAssertFalse(f.message.isEmpty)
        }
    }
}
