import XCTest

// 担当: battle-hud（観戦）。観戦の HUD の通し UI テスト（AI 同士の観戦）:
// 観戦メニュー（視界・情報パネル）・情報パネルのタブ・一時停止と 10 秒戻る・コマ送り・
// 戦術マップを開いたままの再生操作（B23）と文言（B20）・シネマ表示と戻すボタン。

final class SpectatorHUDUITests: XCTestCase {
    static let battleStartTimeout: TimeInterval = 60

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-skipOnboarding", "-grant"] + args
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    @discardableResult
    private func tap(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10) -> XCUIElement {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "\(id) が表示されない")
        e.tap()
        return e
    }

    /// 観戦メニューのボタンは UI テスト用の早送りボタン（画面下中央）と重なるので上寄りを押す。
    private func openMenu(_ app: XCUIApplication) {
        let menu = element(app, "spectate_menu")
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertTrue(element(app, "spectate_menu_panel").waitForExistence(timeout: 5), "観戦メニューが開かない")
    }

    func testSpectatorMenuPanelsSeekTacticalMapAndCinematic() {
        let app = launch(["-battle", "spectate", "-language", "en"])
        // 読み込み中（ヒーローのモデルの準備でメインスレッドが重い）に UI を問い合わせると時間切れになるので、少し待ってから探す
        sleep(15)
        // 狭い画面（SE）は速度ボタンを観戦メニューに畳むので、どの端末にもある一時停止ボタンで待つ
        XCTAssertTrue(element(app, "spectate_pause").waitForExistence(timeout: Self.battleStartTimeout))
        XCTAssertTrue(element(app, "replay_progress").exists, "AI 同士の観戦もシークバーを出す")
        XCTAssertTrue(element(app, "spectate_score").exists)
        snap("spectate_dock")

        // 観戦メニュー: 視界をレッドに、ヒーロー詳細を開く
        openMenu(app)
        tap(app, "spectate_vision_red")
        XCTAssertTrue(element(app, "spectate_vision_red").isSelected)
        snap("spectate_menu")
        tap(app, "spectate_panel_hero")
        tap(app, "spectate_menu_close")
        XCTAssertTrue(element(app, "spectate_info_panel").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "spectate_hero_detail").waitForExistence(timeout: 5))
        snap("spectate_panel_hero")
        tap(app, "spectate_tab_gold")
        XCTAssertTrue(element(app, "spectate_gold_graph").waitForExistence(timeout: 5))
        snap("spectate_panel_gold")
        tap(app, "spectate_tab_events")
        snap("spectate_panel_events")
        tap(app, "spectate_panel_close")
        XCTAssertTrue(element(app, "spectate_info_panel").waitForNonExistence(timeout: 5))

        // 一時停止 → 10 秒戻る → コマ送り
        tap(app, "spectate_pause")
        XCTAssertTrue(element(app, "spectate_pause").isSelected, "一時停止中")
        tap(app, "spectate_back10")
        tap(app, "spectate_step")
        snap("spectate_paused")

        // 戦術マップを開いたまま再生できる（B23）。観戦の文言（B20）
        tap(app, "hud_minimap_expand")
        XCTAssertTrue(element(app, "hud_tactical_panel").waitForExistence(timeout: 5))
        let status = element(app, "hud_tactical_status")
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertNotEqual(status.label, "LIVE", "観戦で LIVE と出さない")
        let pause = element(app, "spectate_pause")
        XCTAssertTrue(pause.isHittable, "戦術マップを開いていても再生操作が押せる")
        pause.tap()
        XCTAssertFalse(element(app, "spectate_pause").isSelected)
        XCTAssertTrue(element(app, "hud_tactical_panel").exists, "再生操作でマップは閉じない")
        snap("spectate_tactical_map")
        tap(app, "hud_tactical_close")

        // シネマ表示: HUD を隠して戻すボタンだけ
        openMenu(app)
        tap(app, "spectate_cinematic")
        XCTAssertTrue(element(app, "spectate_cinematic_restore").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "spectate_pause").waitForNonExistence(timeout: 5))
        snap("spectate_cinematic")
        tap(app, "spectate_cinematic_restore")
        XCTAssertTrue(element(app, "spectate_pause").waitForExistence(timeout: 5))

        tap(app, "spectate_leave")
        tap(app, "leave_confirm")
        XCTAssertTrue(element(app, "spectate_pause").waitForNonExistence(timeout: 10))
    }
}
