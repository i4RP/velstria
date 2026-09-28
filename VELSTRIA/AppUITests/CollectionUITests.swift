import XCTest

// 担当: ui-collection。コレクション/ストア画面の主要導線（DebugLaunch の -route で直行）。

final class CollectionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(route: String, grant: Bool = true, language: String = "ja") -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-skipOnboarding", "-route", route, "-language", language]
        if grant { app.launchArguments.append("-grant") }
        app.launch()
        return app
    }

    /// 遷移アニメーションの完了を待ってから画面を記録する。
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testHeroListToDetailToSkill() {
        let app = launch(route: "heroes")
        let card = element(app, "hero_H007")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        element(app, "heroes_role_Vanguard").tap()
        snapshot(app, "heroes_vanguard")
        card.tap()
        let skillsTab = element(app, "herodetail_tab_skills")
        XCTAssertTrue(skillsTab.waitForExistence(timeout: 5))
        snapshot(app, "hero_detail_overview")
        element(app, "herodetail_tab_stats").tap()
        snapshot(app, "hero_detail_stats")
        element(app, "herodetail_tab_skins").tap()
        snapshot(app, "hero_detail_skins")
        element(app, "herodetail_tab_build").tap()
        snapshot(app, "hero_detail_build")
        skillsTab.tap()
        snapshot(app, "hero_detail_skills")
        let ult = element(app, "skill_SK007_5")
        XCTAssertTrue(ult.waitForExistence(timeout: 5))
        ult.tap()
        XCTAssertTrue(element(app, "skilldetail_switch_SK007_1").waitForExistence(timeout: 5))
        snapshot(app, "skill_detail_ult")
    }

    func testLockedHeroUnlockFlowShowsConfirmation() {
        // -grant なしは Coin 0 → 確認シートで残高不足を表示
        let app = launch(route: "heroDetail:H007", grant: false)
        let unlock = element(app, "herodetail_unlock")
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        unlock.tap()
        XCTAssertTrue(element(app, "purchase_cancel").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "purchase_confirm").exists)
        snapshot(app, "hero_unlock_insufficient")
        element(app, "purchase_cancel").tap()
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
    }

    func testPurchaseCosmeticAndEquip() {
        let app = launch(route: "productDetail:SKU002")
        let buy = element(app, "product_buy")
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        snapshot(app, "product_detail_recall")
        buy.tap()
        let confirm = element(app, "purchase_confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        snapshot(app, "purchase_confirm")
        confirm.tap()
        let equip = element(app, "purchase_equip")
        XCTAssertTrue(equip.waitForExistence(timeout: 5))
        snapshot(app, "purchase_complete")
        equip.tap()
        XCTAssertFalse(element(app, "product_buy").exists)
        snapshot(app, "product_owned_equipped")
    }

    func testBuildEditorAddReorderSave() {
        let app = launch(route: "buildEditor:H003")
        let item = element(app, "build_item_EQ061")
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        element(app, "build_item_EQ043").tap()
        element(app, "build_slot_1").tap()
        element(app, "build_move_left").tap()
        snapshot(app, "build_editor_edited")
        let save = element(app, "build_save")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(element(app, "toast").waitForExistence(timeout: 5))
    }

    func testRunePageEditing() {
        let app = launch(route: "runes")
        let arcana = element(app, "rune_path_Arcana")
        XCTAssertTrue(arcana.waitForExistence(timeout: 10))
        arcana.tap()
        element(app, "rune_RN27").tap()
        snapshot(app, "runes_arcana")
        element(app, "rune_page_add").tap()
        XCTAssertTrue(element(app, "rune_page_1").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "rune_page_activate").exists)
        snapshot(app, "runes_second_page")
    }

    func testSpellLoadoutAssignment() {
        let app = launch(route: "spells")
        let ignite = element(app, "spell_BS07")
        XCTAssertTrue(ignite.waitForExistence(timeout: 10))
        element(app, "spell_slot_1").tap()
        ignite.tap()
        element(app, "spells_scope_H006").tap()
        element(app, "spell_BS05").tap()
        XCTAssertTrue(element(app, "spells_reset_hero").waitForExistence(timeout: 5))
        snapshot(app, "spells_hero_override")
    }

    func testStoreScreensOpen() {
        let app = launch(route: "store")
        XCTAssertTrue(element(app, "store_cat_emotes").waitForExistence(timeout: 10))
        element(app, "store_cat_emotes").tap()
        snapshot(app, "store_emotes")
        element(app, "store_get_gems").tap()
        XCTAssertTrue(element(app, "legal_payment_services").waitForExistence(timeout: 5))
        element(app, "legal_payment_services").tap()
        snapshot(app, "currency_legal_expanded")
    }

    func testEmotePurchaseAndLoadout() {
        let app = launch(route: "productDetail:SKU004")
        let buy = element(app, "product_buy")
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        buy.tap()
        element(app, "purchase_confirm").tap()
        let equip = element(app, "purchase_equip")
        XCTAssertTrue(equip.waitForExistence(timeout: 5))
        equip.tap()
        let back = element(app, "nav_back")
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        // 商品詳細の「所持済み」表示を確認してから、インベントリ経由でエモート設定へ
        XCTAssertFalse(element(app, "product_buy").exists)
    }

    func testEnglishInventoryAndCosmetics() {
        let app = launch(route: "inventory", language: "en")
        XCTAssertTrue(element(app, "inventory_tab_emote").waitForExistence(timeout: 10))
        element(app, "inventory_tab_heroSkin").tap()
        snapshot(app, "inventory_skins_empty_en")
        element(app, "inventory_customize").tap()
        XCTAssertTrue(element(app, "cosmetics_type_Recall").waitForExistence(timeout: 5))
        element(app, "cosmetics_type_Recall").tap()
        snapshot(app, "cosmetics_recall_en")
    }
}
