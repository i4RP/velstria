import XCTest

// 担当: 試合の外（ホーム・戦闘準備・ソーシャル）。触った画面の見た目を確かめるスクリーンショット（xcresult の添付）。
// 配信 CI（build-upload.yml）では iPhone 17 で、.github/workflows/outgame-shots.yml（outgame-* のタグ）では
// iPhone SE（667×375）と 17 Pro Max で流し、画像を成果物に出す。CI のシミュレータには粒子が写らない。

final class OutgameShotsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-skipOnboarding", "-grant", "-language", "ja"] + args
        app.launch()
        return app
    }

    /// 端末名つきで添付する（同じテストを複数の端末で流すため）。
    private func snap(_ name: String) {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "\(name)_\(device.replacingOccurrences(of: " ", with: "_"))"
        a.lifetime = .keepAlways
        add(a)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10) {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "\(id) が表示されない")
        e.tap()
    }

    func testHomeLobby() {
        let app = launch()
        XCTAssertTrue(element(app, "home_play").waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.5)
        snap("home")
        tap(app, "home_menu")
        XCTAssertTrue(element(app, "home_menu_close").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        snap("home_menu")
        tap(app, "home_menu_close")
        tap(app, "home_friends_toggle")
        Thread.sleep(forTimeInterval: 0.5)
        snap("home_friends_collapsed")
    }

    func testModeSelect() {
        let app = launch()
        tap(app, "home_play", timeout: 20)
        XCTAssertTrue(element(app, "flow_mode_standard").waitForExistence(timeout: 10))
        for id in ["flow_mode_ranked", "flow_mode_brawl", "flow_mode_rising", "flow_mode_magicChess",
                   "flow_mode_custom", "flow_mode_practice", "flow_mode_tutorial"] {
            XCTAssertTrue(element(app, id).exists, "\(id) が無い")
        }
        Thread.sleep(forTimeInterval: 1.0)
        snap("mode_select")
    }

    /// クラシック: レーン選択 → マッチング → マッチ成立 → ヒーロー選択（バトルスキルのポップアップ）→ 最終調整。
    func testClassicFlowScreens() {
        let app = launch()
        tap(app, "home_play", timeout: 20)
        tap(app, "flow_mode_standard")
        XCTAssertTrue(element(app, "flow_lane_start").waitForExistence(timeout: 10))
        tap(app, "flow_lane_4")
        Thread.sleep(forTimeInterval: 0.5)
        snap("lane_select")
        tap(app, "flow_lane_start")
        XCTAssertTrue(element(app, "flow_match_elapsed").waitForExistence(timeout: 5))
        snap("matching")
        XCTAssertTrue(element(app, "flow_match_accept").waitForExistence(timeout: 15))
        snap("match_found")
        tap(app, "flow_match_accept")
        XCTAssertTrue(element(app, "flow_next").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.8)
        snap("hero_select")
        tap(app, "flow_spell_0")
        XCTAssertTrue(element(app, "battle_skill_confirm").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        snap("battle_skill")
        tap(app, "flow_spell_close")
        tap(app, "flow_next")
        XCTAssertTrue(element(app, "flow_confirm").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        snap("final_adjust")
    }

    /// ランクのドラフト（自分の手番を 3 番目にして、味方の AI が先に選ぶ所も写す）。
    func testRankedDraftScreens() {
        let app = launch(["-flowSeed", "20261001", "-draftSlot", "3"])
        tap(app, "home_play", timeout: 20)
        tap(app, "flow_mode_ranked")
        tap(app, "flow_lane_start", timeout: 10)
        tap(app, "flow_match_accept", timeout: 15)
        XCTAssertTrue(element(app, "flow_lock").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)
        snap("draft_waiting")
        XCTAssertTrue(element(app, "flow_confirm").waitForExistence(timeout: 90))
        Thread.sleep(forTimeInterval: 0.8)
        snap("draft_adjust")
    }

    /// ランクの紋章（7 ティア）と通貨のアイコン（ベクターの自作。Common/CelestialArt.swift）。
    func testRankAndStoreArt() {
        let app = launch()
        tap(app, "home_rank", timeout: 20)
        XCTAssertTrue(element(app, "nav_back").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.8)
        snap("rank_overview")
        tap(app, "nav_back")
        tap(app, "home_currency_coin")
        XCTAssertTrue(element(app, "nav_back").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.8)
        snap("currency_store")
    }

    func testRecordsOpenReplays() {
        let app = launch()
        // 戦績はプロフィールから開く（採用案のロビーには入口を置かない）
        tap(app, "home_profile", timeout: 20)
        tap(app, "profile_records")
        XCTAssertTrue(element(app, "records_replays").waitForExistence(timeout: 10))
        snap("records")
        tap(app, "records_replays")
        Thread.sleep(forTimeInterval: 1.0)
        snap("replays")
    }
}
