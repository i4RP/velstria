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

    /// 3D プレビューの見た目が一定時間で変わる（自動回転・待機モーションが動いている）か。
    private func previewIsAnimating(_ preview: XCUIElement) -> Bool {
        let first = preview.screenshot().pngRepresentation
        Thread.sleep(forTimeInterval: 1.5)
        let second = preview.screenshot().pngRepresentation
        return first != second
    }

    func testHeroPreviewKeepsAnimatingAfterPushAndPop() {
        let app = launch(route: "heroDetail:H001")
        let preview = element(app, "hero_preview_3d")
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(previewIsAnimating(preview), "詳細を開いた直後に 3D プレビューが動いていない")
        element(app, "herodetail_tab_skills").tap()
        let skill = element(app, "skill_SK001_2")
        XCTAssertTrue(skill.waitForExistence(timeout: 5))
        skill.tap()
        XCTAssertTrue(element(app, "skilldetail_switch_SK001_1").waitForExistence(timeout: 5))
        element(app, "nav_back").tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.0)
        snapshot(app, "hero_detail_preview_after_pop")
        XCTAssertTrue(previewIsAnimating(preview), "スキル詳細から戻った後に 3D プレビューが止まっている")
    }

    func testSkillDetailShowsSimulationHealForTeamHeal() {
        // SK005_5 ヴォスの Ult（味方全体回復）: 実戦の回復量 205 × 2.4 × 1.2 = 590 を表と説明に出す
        let app = launch(route: "skillDetail:SK005_5", language: "en")
        let description = element(app, "skilldetail_description")
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        XCTAssertTrue(description.label.contains("590 HP"), description.label)
        // ランク 1 の回復量（表）
        XCTAssertTrue(app.staticTexts["590"].exists)
        app.scrollViews.containing(.any, identifier: "skilldetail_description").firstMatch.swipeUp(velocity: .slow)
        snapshot(app, "skill_detail_team_heal_scaling")
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

    func testBuildEditorSmiteNoticeLinksToSpells() {
        // 既定スペル（瞬歩・治癒波）のままジャングル装備を入れると、狩猟印の案内からスペル設定へ進める
        let app = launch(route: "buildEditor:H006")
        let jungle = element(app, "build_category_Jungle")
        XCTAssertTrue(jungle.waitForExistence(timeout: 10))
        jungle.tap()
        element(app, "build_item_EQ006").tap()
        let notice = element(app, "build_smite_notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        snapshot(app, "build_editor_smite_notice")
        notice.tap()
        XCTAssertTrue(element(app, "spell_BS05").waitForExistence(timeout: 5))
    }

    func testEnglishPurchaseConfirmSheet() {
        let app = launch(route: "productDetail:SKU001", language: "en")
        let buy = element(app, "product_buy")
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        buy.tap()
        XCTAssertTrue(element(app, "purchase_confirm").waitForExistence(timeout: 5))
        snapshot(app, "purchase_confirm_en")
        element(app, "purchase_cancel").tap()
        XCTAssertTrue(buy.waitForExistence(timeout: 5))
    }

    func testRunePageNameIsRestoredWhenCleared() {
        let app = launch(route: "runes")
        let field = element(app, "rune_page_name")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        XCTAssertNotEqual(field.value as? String, "ページ1", "名前が消去されていない")
        // 空のままページを追加して切り替えても、元のページ名は既定名に戻る
        element(app, "rune_page_add").tap()
        let first = element(app, "rune_page_0")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.hasPrefix("ページ1"), first.label)
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
        // 商品詳細は「所持済み」表示になり、エモート設定へ進める
        let slotsLink = element(app, "product_emote_slots")
        XCTAssertTrue(slotsLink.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "product_buy").exists)
        slotsLink.tap()
        // 装備したエモート（CO004）は枠 1 に入り、一覧に表示される
        let slot0 = element(app, "emote_slot_0")
        XCTAssertTrue(slot0.waitForExistence(timeout: 5))
        XCTAssertTrue(slot0.label.contains("潮祈のエモート I"), slot0.label)
        XCTAssertTrue(element(app, "emote_CO004").exists)
        XCTAssertTrue(element(app, "emote_clear").exists)
        snapshot(app, "emote_loadout_equipped")
        element(app, "emote_clear").tap()
        XCTAssertFalse(element(app, "emote_clear").waitForExistence(timeout: 1))
        XCTAssertFalse(element(app, "emote_slot_0").label.contains("潮祈のエモート I"))
        element(app, "emote_CO004").tap()
        XCTAssertTrue(element(app, "emote_slot_0").label.contains("潮祈のエモート I"))
        snapshot(app, "emote_loadout_reassigned")
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
