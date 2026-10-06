import XCTest

// 担当: ui-liveops（観戦: リプレイ一覧・観戦の準備・リザルトからの続き）。
// -sampleReplays で見本のリプレイを入れ、一覧 → 詳細 → 再生、観戦の設定・ヒーロー指定、観戦のリザルトの続きの操作を通す。
// 各ステップのスクリーンショットを添付する（見た目の確認用）。

final class ReplayLibraryUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private static let battleStartTimeout: TimeInterval = 150

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-skipOnboarding", "-grant"] + args
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

    /// 一覧（お気に入り・別バージョン・絞り込み）→ 詳細 → 再生 → 途中で止めたリザルト（もう一度再生）。
    func testReplayListDetailAndPlayback() {
        let app = launch(["-sampleReplays", "-route", "replays", "-language", "en"])
        XCTAssertTrue(element(app, "replay_row_0").waitForExistence(timeout: 15))
        XCTAssertTrue(element(app, "replays_storage").waitForExistence(timeout: 10), "使用容量が出ない")
        XCTAssertTrue(element(app, "replay_incompatible_3").exists, "別バージョンのリプレイは開く前に分かる")
        snap("replays_list_en")
        tap(app, "replays_filter_favorites")
        XCTAssertTrue(element(app, "replay_row_0").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "replay_row_1").exists, "お気に入りは 1 件")
        snap("replays_favorites_en")
        tap(app, "replays_filter_all")

        tap(app, "replay_row_0")
        XCTAssertTrue(element(app, "replay_detail_play").waitForExistence(timeout: 10))
        sleep(1)
        snap("replay_detail_en")
        tap(app, "replay_detail_play")
        XCTAssertTrue(element(app, "spectate_pause").waitForExistence(timeout: Self.battleStartTimeout), "リプレイが始まらない")
        snap("replay_playback_en")
        tap(app, "spectate_leave")
        tap(app, "leave_confirm")
        XCTAssertTrue(element(app, "result_replay_again").waitForExistence(timeout: 20))
        XCTAssertFalse(element(app, "result_watch_next").exists, "リプレイの後は次の観戦を出さない")
        snap("replay_result_en")
        tap(app, "result_close")
        XCTAssertTrue(element(app, "replay_row_0").waitForExistence(timeout: 10), "閉じると一覧へ戻る")
    }

    /// 観戦の準備: 設定（速度・視界・自動カメラ・最大時間）と観戦の記録、ヒーローの指定。
    func testSpectateSetupSettingsAndPicks() {
        let app = launch(["-route", "spectateSetup", "-language", "en"])
        XCTAssertTrue(element(app, "spectate_start").waitForExistence(timeout: 15))
        tap(app, "spectate_map_brawl")
        snap("spectate_setup_brawl_en")
        tap(app, "spectate_settings")
        XCTAssertTrue(element(app, "spectate_watch_record").waitForExistence(timeout: 5))
        tap(app, "spectate_pref_speed_2")
        XCTAssertTrue(element(app, "spectate_pref_speed_2").isSelected)
        snap("spectate_settings_en")
        tap(app, "spectate_settings_close")

        tap(app, "spectate_roster")
        tap(app, "spectate_slot_red_2")
        tap(app, "spectate_hero_H001")
        sleep(1)
        snap("spectate_roster_en")
        tap(app, "spectate_roster_close")
        XCTAssertTrue(element(app, "spectate_start").waitForExistence(timeout: 5))
        snap("spectate_setup_picked_en")
    }

    /// AI 同士の観戦のリザルト: リプレイを見る・同じシード・次の観戦。報酬タブは報酬なし。
    func testSpectateResultFollowUps() {
        let app = launch(["-battle", "spectate", "-language", "en"])
        // 読み込み中はアクセシビリティの問い合わせが詰まりやすいので、観戦の操作が出るまで待ってから押す
        XCTAssertTrue(element(app, "spectate_pause").waitForExistence(timeout: Self.battleStartTimeout), "観戦が始まらない")
        sleep(2)
        tap(app, "spectate_leave")
        tap(app, "leave_confirm")
        XCTAssertTrue(element(app, "result_close").waitForExistence(timeout: 20))
        XCTAssertTrue(element(app, "result_watch_replay").exists)
        XCTAssertTrue(element(app, "result_same_seed").exists)
        XCTAssertTrue(element(app, "result_watch_next").exists)
        XCTAssertFalse(element(app, "result_again").exists, "観戦では「もう一度」を出さない")
        snap("spectate_result_followups_en")
        tap(app, "result_watch_replay")
        XCTAssertTrue(element(app, "spectate_pause").waitForExistence(timeout: Self.battleStartTimeout), "リプレイが始まらない")
        snap("spectate_result_replay_en")
    }
}
