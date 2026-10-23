import XCTest

// 担当: ui-collection。コレクション/ストア画面の主要導線（DebugLaunch の -route で直行）。

final class CollectionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(route: String, grant: Bool = true, language: String = "ja", extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-skipOnboarding", "-route", route, "-language", language]
        if grant { app.launchArguments.append("-grant") }
        app.launchArguments += extra
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
        let card = element(app, "hero_H029")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        element(app, "heroes_role_Support").tap()
        snapshot(app, "heroes_support")
        card.tap()
        XCTAssertTrue(element(app, "hero_preview_3d").waitForExistence(timeout: 10))
        snapshot(app, "hero_detail_overview")
        element(app, "herodetail_quick_stats").tap()
        snapshot(app, "hero_detail_stats")
        element(app, "herodetail_tab_skins").tap()
        snapshot(app, "hero_detail_skins")
        element(app, "herodetail_tab_build").tap()
        snapshot(app, "hero_detail_build")
        element(app, "herodetail_tab_skills").tap()
        snapshot(app, "hero_detail_skills")
        // 説明シート内のスキルアイコン列は説明・レベル表を切り替える。
        let ult = element(app, "detail_skill_SK029_5")
        XCTAssertTrue(ult.waitForExistence(timeout: 5))
        ult.tap()
        XCTAssertTrue(element(app, "skilldetail_description").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "skilldetail_rank_3").waitForExistence(timeout: 5))
        snapshot(app, "skill_detail_ult")
        // ライトモードではレベル表を畳み、フルモードで戻る
        element(app, "skilldetail_mode_light").tap()
        XCTAssertFalse(element(app, "skilldetail_rank_3").waitForExistence(timeout: 1))
        element(app, "skilldetail_mode_full").tap()
        XCTAssertTrue(element(app, "skilldetail_rank_3").waitForExistence(timeout: 5))
    }

    /// 全画面のスキル詳細（route 直行）でも、左のアイコン列で同じヒーローの別スキルへ切り替えられる。
    func testSkillDetailRouteSwitchesSkillFromIconRow() {
        let app = launch(route: "skillDetail:SK001_2")
        XCTAssertTrue(element(app, "skilldetail_switch_SK001_5").waitForExistence(timeout: 10))
        element(app, "skilldetail_switch_SK001_5").tap()
        XCTAssertTrue(element(app, "skilldetail_rank_3").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "skilldetail_rank_4").exists)
        snapshot(app, "skill_detail_route_ult")
    }

    /// 3D プレビューの見た目が一定時間で変わる（自動回転・待機モーションが動いている）か。
    private func previewIsAnimating(_ preview: XCUIElement) -> Bool {
        let first = preview.screenshot().pngRepresentation
        Thread.sleep(forTimeInterval: 1.5)
        let second = preview.screenshot().pngRepresentation
        return first != second
    }

    func testHeroPreviewKeepsAnimatingAfterSkillSelection() {
        let app = launch(route: "heroDetail:H033")
        let preview = element(app, "hero_preview_3d")
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "herodetail_quick_stats").isHittable)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(previewIsAnimating(preview), "詳細を開いた直後に 3D プレビューが動いていない")
        for id in ["SK033_1", "SK033_2", "SK033_3", "SK033_5", "SK033_5"] {
            let skill = element(app, "skill_" + id)
            XCTAssertTrue(skill.waitForExistence(timeout: 5))
            skill.tap()
            if id == "SK033_2" {
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "hero_skill_preview_effect"
                shot.lifetime = .keepAlways
                add(shot)
            }
            XCTAssertTrue(skill.isSelected)
            XCTAssertFalse(element(app, "skilldetail_description").exists, "再生で説明シートを開かない")
        }
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.0)
        snapshot(app, "hero_detail_preview_after_skill")
        XCTAssertTrue(previewIsAnimating(preview), "スキルを選んだ後に 3D プレビューが止まっている")
        element(app, "herodetail_skill_details").tap()
        XCTAssertTrue(element(app, "skilldetail_description").waitForExistence(timeout: 5))
        app.buttons["閉じる"].firstMatch.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(previewIsAnimating(preview), "説明を閉じた後に待機モーションが再開しない")
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
        let item = element(app, "build_item_EQ102")
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        element(app, "build_item_EQ103").tap()
        element(app, "build_slot_1").tap()
        element(app, "build_move_left").tap()
        snapshot(app, "build_editor_edited")
        let save = element(app, "build_save")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(element(app, "toast").waitForExistence(timeout: 5))
    }

    func testBuildEditorKeepsOnePairOfBoots() {
        // 祝福（ジャングル・ローム）は試合中に靴へ付けるので、ビルド編集のカテゴリには無い。靴は 1 足まで
        let app = launch(route: "buildEditor:H006")
        let movement = element(app, "build_category_Movement")
        XCTAssertTrue(movement.waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "build_category_Jungle").exists)
        XCTAssertFalse(element(app, "build_category_Roam").exists)
        // 1 枠空けてから、別の靴を足そうとすると断られる
        element(app, "build_slot_5").tap()
        element(app, "build_remove").tap()
        movement.tap()
        element(app, "build_item_EQ401").tap()
        XCTAssertTrue(element(app, "build_warning").waitForExistence(timeout: 5))
        snapshot(app, "build_editor_boots_limit")
    }

    func testItemListShowsBlessingTabs() {
        let app = launch(route: "items")
        let magic = element(app, "items_category_Magic")
        XCTAssertTrue(magic.waitForExistence(timeout: 10))
        magic.tap()
        XCTAssertTrue(element(app, "item_EQ113").waitForExistence(timeout: 5), "攻撃のウィンタークラウンは魔法のタブにも並ぶ")
        element(app, "items_category_Jungle").tap()
        XCTAssertTrue(element(app, "blessing_flame").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "blessing_rules").exists)
        snapshot(app, "items_jungle_blessings")
        element(app, "items_category_Roam").tap()
        XCTAssertTrue(element(app, "blessing_conceal").waitForExistence(timeout: 5))
    }

    func testItemDetailShowsTwoLevelRecipe() {
        // マジックガン = レイシハンマー（= ダガー）+ ナイフ + ナイフ
        let app = launch(route: "itemDetail:EQ101")
        XCTAssertTrue(element(app, "itemtree_EQ122").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "itemtree_EQ133").exists, "素材の素材も並ぶ")
        snapshot(app, "item_detail_recipe")
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

    /// エンブレム: タブでセットを切り替え、天賦の枠から別の天賦を装備し、一括設定でヒーローに付ける。
    func testEmblemTalentPickAndBulkApply() {
        let app = launch(route: "emblems")
        let tank = element(app, "emblem_tab_EM_TANK")
        XCTAssertTrue(tank.waitForExistence(timeout: 10))
        // 横画面の iPhone で中身が高すぎると「戻る」の行が画面の外へ押し出されていた
        XCTAssertTrue(element(app, "nav_back").isHittable, "エンブレム画面に戻るボタンが見えない")
        XCTAssertTrue(element(app, "emblem_bulk").isHittable, "一括設定が画面の外にある")
        tank.tap()
        element(app, "emblem_slot_3").tap()
        let finder = element(app, "emblem_talent_TL_WEAKNESS_FINDER")
        XCTAssertTrue(finder.waitForExistence(timeout: 5))
        finder.tap()
        let equip = element(app, "emblem_equip")
        XCTAssertTrue(equip.waitForExistence(timeout: 5))
        equip.tap()
        XCTAssertTrue(element(app, "emblem_equipped").waitForExistence(timeout: 5), "装備すると「装備中」になる")
        snapshot(app, "emblem_picker_core")
        element(app, "emblem_picker_back").tap()
        element(app, "emblem_detail").tap()
        XCTAssertTrue(element(app, "emblem_detail_close").waitForExistence(timeout: 5))
        snapshot(app, "emblem_detail")
        element(app, "emblem_detail_close").tap()
        element(app, "emblem_bulk").tap()
        let all = element(app, "emblem_bulk_all")
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        element(app, "emblem_bulk_filter_support").tap()
        all.tap()
        snapshot(app, "emblem_bulk")
        element(app, "emblem_bulk_ok").tap()
        XCTAssertTrue(tank.waitForExistence(timeout: 5))
    }

    /// エンブレムの宝箱・解放・強化（新規のプレイヤー: -emblemFresh = 通常共通だけ Lv1、マジックダスト 2,000、宝箱 1 回分）。
    func testEmblemChestUnlockAndUpgradeForANewPlayer() {
        let app = launch(route: "emblems", extra: ["-emblemFresh"])
        let chest = element(app, "emblem_chest")
        XCTAssertTrue(chest.waitForExistence(timeout: 10))
        snapshot(app, "emblem_fresh_common")
        chest.tap()
        let ok = element(app, "reward_claim_ok")
        XCTAssertTrue(ok.waitForExistence(timeout: 5), "宝箱の中身の受取ポップアップ")
        snapshot(app, "emblem_chest_reward")
        ok.tap()
        element(app, "emblem_tab_EM_ASSASSIN").tap()
        let unlock = element(app, "emblem_unlock")
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "未解放のセットは「解放」")
        snapshot(app, "emblem_locked")
        unlock.tap()
        let upgrade = element(app, "emblem_upgrade")
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5), "解放すると Lv1 から強化できる")
        XCTAssertTrue(element(app, "emblem_upgrade_cost").exists)
        upgrade.tap()
        XCTAssertTrue(element(app, "emblem_next_key").waitForExistence(timeout: 5))
        snapshot(app, "emblem_upgraded")
    }

    func testSpellLoadoutAssignment() {
        let app = launch(route: "spells")
        // バトルスキルは 1 枠（BattleSkillPicker）。新規のアカウント Lv1 では瞬歩（BS01）だけ装備できる
        let blink = element(app, "spell_BS01")
        XCTAssertTrue(blink.waitForExistence(timeout: 10))
        element(app, "spell_BS05").tap()
        XCTAssertFalse(element(app, "battle_skill_confirm").isEnabled, "未解放のスキルは装備できない")
        snapshot(app, "spells_locked")
        blink.tap()
        let confirm = element(app, "battle_skill_confirm")
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        snapshot(app, "spells_equipped")
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
        // スキンは出しているヒーローの分が無い間はタブを出さない（空のスキンストアへ案内しない）
        XCTAssertFalse(element(app, "inventory_tab_heroSkin").exists)
        element(app, "inventory_tab_recall").tap()
        snapshot(app, "inventory_recall_empty_en")
        element(app, "inventory_customize").tap()
        XCTAssertTrue(element(app, "cosmetics_type_Recall").waitForExistence(timeout: 5))
        element(app, "cosmetics_type_Recall").tap()
        snapshot(app, "cosmetics_recall_en")
    }
}
