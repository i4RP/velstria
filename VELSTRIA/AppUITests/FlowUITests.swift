import XCTest

// 担当: ui-flow。オンボーディング → ホーム → 対戦フロー（通常戦・ランク戦ドラフト）→ ロード → リザルトの通し UI テスト。
// 各ステップのスクリーンショットを添付（xcresult から書き出して見た目の確認に使う）。

final class FlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"] + args
        app.launch()
        return app
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func tap(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10) -> XCUIElement {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "\(id) が表示されない")
        e.tap()
        return e
    }

    func testOnboardingReachesHome() {
        runOnboarding(language: "ja")
    }

    func testOnboardingEnglish() {
        runOnboarding(language: "en")
    }

    private func runOnboarding(language: String) {
        let app = launch(["-language", language])
        XCTAssertTrue(element(app, "onb_start").waitForExistence(timeout: 15))
        snap("onb_01_splash_\(language)")
        tap(app, "onb_start")

        XCTAssertTrue(element(app, "onb_age_2").waitForExistence(timeout: 5))
        tap(app, "onb_age_2")
        snap("onb_02_age_\(language)")
        tap(app, "onb_age_next")

        XCTAssertTrue(element(app, "onb_terms_accept").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "onb_terms_next").isEnabled, "同意前は進めない")
        tap(app, "onb_terms_accept")
        snap("onb_03_terms_\(language)")
        tap(app, "onb_terms_next")

        let field = element(app, "onb_name_field")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("P")
        XCTAssertFalse(element(app, "onb_name_next").isEnabled, "1 文字では進めない")
        field.typeText("ilot")
        snap("onb_04_name_\(language)")
        tap(app, "onb_name_next")

        XCTAssertTrue(element(app, "onb_prepare_progress").waitForExistence(timeout: 5))
        snap("onb_05_prepare_\(language)")

        XCTAssertTrue(element(app, "onb_tutorial_skip").waitForExistence(timeout: 30))
        snap("onb_06_tutorial_\(language)")
        tap(app, "onb_tutorial_skip")

        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 10))
        snap("home_\(language)")
    }

    func testHomeMetaScreens() {
        let app = launch(["-skipOnboarding", "-grant", "-language", "ja"])
        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 15))
        // 採用案のロビー: お知らせは ≡ のメニュー、戦績・アカウントはプロフィールの左のメニューから（同じ画面の中で切り替えるので 1 回戻る）
        let paths: [(ids: [String], name: String, backs: Int)] = [
            (["home_profile"], "profile", 1), (["home_mail"], "mail", 1), (["home_menu", "home_menu_notices"], "notices", 1),
            (["home_profile", "profile_records"], "records", 1), (["home_profile", "profile_account"], "account", 1), (["home_rank"], "rank", 1),
        ]
        for (ids, name, backs) in paths {
            for id in ids { tap(app, id) }
            XCTAssertTrue(element(app, "nav_back").waitForExistence(timeout: 5), "\(name) に戻るボタンがない")
            snap("meta_\(name)")
            for _ in 0..<backs { tap(app, "nav_back") }
            XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 5))
        }
    }

    func testStandardMatchFlowToResult() {
        let app = launch(["-skipOnboarding", "-grant", "-language", "ja"])
        tap(app, "home_play", timeout: 15)
        XCTAssertTrue(element(app, "flow_mode_standard").waitForExistence(timeout: 5))
        tap(app, "flow_difficulty_2")
        snap("flow_01_mode")
        tap(app, "flow_mode_standard")

        // レーン選択 → マッチング →「マッチ成立」で入場（MLBB の手順。AI 戦なので待ちは数秒）
        XCTAssertTrue(element(app, "flow_lane_start").waitForExistence(timeout: 5))
        // MLBB と同じく 2 本以上（必要なレーンだけなら 1 本）
        tap(app, "flow_lane_3")
        tap(app, "flow_lane_1")
        snap("flow_01b_lane")
        tap(app, "flow_lane_start")
        tap(app, "flow_match_accept", timeout: 15)

        tap(app, "flow_hero_H027", timeout: 20)
        snap("flow_02_hero")
        tap(app, "flow_spell_0")
        // バトルスキルの選択（BattleSkillPicker）。新規のアカウント Lv1 で装備できるのは瞬歩（BS01）だけ
        XCTAssertTrue(element(app, "spell_BS01").waitForExistence(timeout: 5))
        snap("flow_03_spells")
        tap(app, "spell_BS01")
        tap(app, "battle_skill_confirm")
        tap(app, "flow_next")

        // 決定の後は 25 秒の最終調整（準備完了ですぐ始める）
        XCTAssertTrue(element(app, "flow_confirm").waitForExistence(timeout: 5))
        snap("flow_04_adjust")
        tap(app, "flow_confirm")

        XCTAssertTrue(element(app, "loading_progress").waitForExistence(timeout: 10))
        snap("flow_05_loading")

        // 試合を最後まで早送りすると CI のシミュレータでは 15 分を超えるので、一時停止 → 退出（敗北）でリザルトへ進む
        sleep(15)
        tap(app, "hud_pause", timeout: 120)
        tap(app, "pause_leave")
        tap(app, "leave_confirm")
        XCTAssertTrue(element(app, "result_close").waitForExistence(timeout: 60))
        sleep(2)
        snap("result_01_table")
        tap(app, "result_tab_eval")
        snap("result_02_eval")
        tap(app, "result_tab_rewards")
        sleep(3)
        snap("result_03_rewards")
        tap(app, "result_report")
        XCTAssertTrue(element(app, "report_send").waitForExistence(timeout: 5))
        snap("result_04_report")
        tap(app, "report_close")

        // もう一度: リザルトを閉じた後、同じモードのレーン選択から（MLBB と同じくマッチングからやり直す）
        tap(app, "result_again", timeout: 5)
        XCTAssertTrue(element(app, "flow_lane_start").waitForExistence(timeout: 10), "対戦フローが開き直されない")
        snap("result_05_again")
        tap(app, "flow_back")
        tap(app, "flow_close")
        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 10))
    }

    /// ドラフトの AI 選択を固定するシード。
    static let draftSeed = "20261001"

    func testRankedDraft() {
        // 自分の手番は試合ごとに変わる。テストは -draftSlot 1 で B1（最初の手番）に固定する
        let app = launch(["-skipOnboarding", "-language", "ja", "-flowSeed", Self.draftSeed, "-draftSlot", "1"])
        tap(app, "home_play", timeout: 15)
        tap(app, "flow_mode_ranked")
        tap(app, "flow_lane_2", timeout: 5)
        tap(app, "flow_lane_4")
        snap("draft_00_lane")
        tap(app, "flow_lane_start")
        tap(app, "flow_match_accept", timeout: 15)

        // BAN は無く、最初からプレイヤーのピック（B1）
        XCTAssertTrue(element(app, "flow_lock").waitForExistence(timeout: 20))
        tap(app, "flow_hero_H027")
        snap("draft_02_pick")
        tap(app, "flow_lock")

        // 全員のピックの後は 25 秒の最終調整（戦闘準備のタブ）
        XCTAssertTrue(element(app, "flow_confirm").waitForExistence(timeout: 40))
        snap("draft_03_adjust")
    }

    /// 観戦（AI 同士）のリザルト: 観戦用の見出しで、報酬なし・「もう一度」なし。
    func testSpectateResult() {
        let app = launch(["-skipOnboarding", "-language", "en", "-battle", "spectate"])
        XCTAssertTrue(element(app, "loading_progress").waitForExistence(timeout: 10))
        tap(app, "battle_stub_simulate", timeout: 20)
        XCTAssertTrue(element(app, "result_close").waitForExistence(timeout: 900))
        XCTAssertTrue(element(app, "result_banner").exists)
        XCTAssertFalse(element(app, "result_again").exists, "観戦では「もう一度」を出さない")
        sleep(2)
        snap("result_spectate_en")
        tap(app, "result_tab_rewards")
        snap("result_spectate_rewards_en")
        tap(app, "result_close")
        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 10))
    }

    /// 練習場のリザルト（1 人）: 評価タブと報酬対象外の表示。
    func testPracticeResult() {
        let app = launch(["-skipOnboarding", "-language", "ja", "-battle", "practice"])
        XCTAssertTrue(element(app, "loading_progress").waitForExistence(timeout: 10))
        snap("loading_practice")
        tap(app, "battle_stub_simulate", timeout: 20)
        XCTAssertTrue(element(app, "result_close").waitForExistence(timeout: 900))
        XCTAssertFalse(element(app, "result_again").exists)
        tap(app, "result_tab_eval")
        sleep(1)
        snap("result_practice_eval")
        tap(app, "result_close")
        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 10))
    }

    func testEnglishScreens() {
        let app = launch(["-skipOnboarding", "-grant", "-language", "en"])
        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 15))
        snap("en_home")
        tap(app, "home_play")
        XCTAssertTrue(element(app, "flow_mode_standard").waitForExistence(timeout: 5))
        snap("en_mode")
        tap(app, "flow_mode_standard")
        XCTAssertTrue(element(app, "flow_lane_start").waitForExistence(timeout: 5))
        snap("en_lane")
        tap(app, "flow_back")
        tap(app, "flow_close")
        tap(app, "home_profile", timeout: 5)
        XCTAssertTrue(element(app, "nav_back").waitForExistence(timeout: 5))
        snap("en_profile")
    }
}
