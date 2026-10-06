import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

/// 統合レビューの UI 指摘の回帰テスト: 終わった後の右上ボタン・戦術マップ、退出の確認、観戦メニューと戦術マップの排他、
/// VoiceOver のモーダル、倒れている間の表示の重なり（降参投票・告知）、観戦席の待機の表示、読み上げの区切り。
@MainActor
final class SpectatorUIFixTests: XCTestCase {
    private var savedLanguage: AppLanguage = .ja

    override func setUp() {
        super.setUp()
        savedLanguage = Loc.current
    }

    override func tearDown() {
        Loc.current = savedLanguage
        super.tearDown()
    }

    private let devices: [(name: String, size: CGSize, side: CGFloat, bottom: CGFloat)] = [
        ("iPhone SE", CGSize(width: 667, height: 375), 0, 0),
        ("iPhone 13 mini", CGSize(width: 812, height: 375), 44, 21),
        ("iPhone 16e", CGSize(width: 844, height: 390), 47, 21),
        ("iPhone 17 Pro", CGSize(width: 874, height: 402), 62, 20),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440), 62, 20),
    ]

    private func layouts() -> [(tag: String, layout: HUDLayout)] {
        devices.flatMap { d in
            [false, true].map { left in
                ("\(d.name) \(left ? "左利き" : "右手")",
                 HUDLayout(size: d.size, safe: EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side), leftHanded: left))
            }
        }
    }

    private func model(_ config: MatchConfig) -> (HUDModel, AppModel) {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let m = HUDModel(controller: BattleController(launch: BattleLaunch(config: config)))
        m.start(app: app, onFinish: { _ in })
        return (m, app)
    }

    // MARK: 終わった後

    func testSeekableSpectatorCanOpenPanelsAndMapAfterTheEnd() {
        let (m, _) = model(MatchFactory.botMatch(seed: 3))
        defer { m.stop() }
        XCTAssertTrue(m.allowsPanelsAfterEnd)
        m.debugEnd(winner: .blue)
        XCTAssertNotNil(m.endPhase)
        XCTAssertTrue(HUDSpectatorEndCardRule.isVisible(m), "終わったらカードを出す")
        m.openPanel(.scoreboard)
        XCTAssertEqual(m.panel, .scoreboard, "終わった後もスコアボードを開ける")
        XCTAssertFalse(HUDSpectatorEndCardRule.isVisible(m), "パネルの間はカードを隠す（カードの下に開かない）")
        m.closePanel()
        XCTAssertTrue(HUDSpectatorEndCardRule.isVisible(m))
        m.setTacticalMap(open: true)
        XCTAssertTrue(m.isTacticalMapOpen, "終わった後も戦術マップを開ける")
        XCTAssertFalse(HUDSpectatorEndCardRule.isVisible(m))
        m.setTacticalMap(open: false)
        m.requestLeave()
        XCTAssertEqual(m.panel, .pause)
        XCTAssertTrue(m.confirmingLeave)
    }

    func testPlayerAfterTheEndKeepsPanelsClosedAndNoStaleLeaveConfirmation() {
        let (m, _) = model(MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 3))
        defer { m.stop() }
        XCTAssertFalse(m.allowsPanelsAfterEnd)
        m.debugEnd(winner: .blue)
        m.openPanel(.scoreboard)
        XCTAssertNil(m.panel, "プレイヤーは終了演出の間パネルを開かない（従来どおり）")
        m.requestLeave()
        XCTAssertNil(m.panel)
        XCTAssertFalse(m.confirmingLeave, "開けなかった時に退出の確認だけ残さない")
    }

    // MARK: 観戦メニューと戦術マップ

    func testSpectatorDrawerAndTacticalMapAreExclusive() {
        let (m, _) = model(MatchFactory.botMatch(seed: 4))
        defer { m.stop() }
        m.setTacticalMap(open: true)
        XCTAssertTrue(m.isTacticalMapOpen)
        m.toggleSpectatorDrawer()
        XCTAssertTrue(m.spectator.isDrawerOpen)
        XCTAssertFalse(m.isTacticalMapOpen, "マップの上から開いた引き出しは、マップを閉じて見せる")
        m.setTacticalMap(open: true)
        XCTAssertTrue(m.isTacticalMapOpen)
        XCTAssertFalse(m.spectator.isDrawerOpen, "マップを開いたら見えない引き出しを残さない")
    }

    func testTacticalMapIsModalOnlyForPlayers() {
        XCTAssertTrue(HUDTacticalMapText.isModal(isSpectating: false))
        XCTAssertFalse(HUDTacticalMapText.isModal(isSpectating: true), "観戦者はマップの上のドックも VoiceOver で辿れる")
    }

    // MARK: 倒れている間の重なり

    func testDeathAllyStripAvoidsTheSurrenderVoteCard() {
        for (tag, l) in layouts() {
            let vote = HUDSurrenderMetrics.frame(l)
            let strip = HUDDeathMetrics.stripFrame(l, allies: 4, avoiding: vote)
            XCTAssertFalse(strip.intersects(vote), "\(tag): 味方の一覧が降参投票のカードに隠れる")
            XCTAssertGreaterThanOrEqual(strip.minX, l.leadingEdge - 0.5, "\(tag): 左の Safe Area")
            XCTAssertLessThanOrEqual(strip.maxX, l.trailingEdge + 0.5, "\(tag): 右の Safe Area")
            XCTAssertFalse(strip.intersects(l.minimapDockFrame), "\(tag): ミニマップと重なる")
            // 投票が無ければ従来の位置
            XCTAssertEqual(HUDDeathMetrics.stripFrame(l, allies: 4, avoiding: nil), HUDDeathMetrics.stripFrame(l, allies: 4))
        }
    }

    func testPlayerBannerMovesBelowTheDeathCard() {
        for (tag, l) in layouts() {
            XCTAssertEqual(HUDRootMetrics.playerBannerCenterY(l, heroDead: false), l.height * 0.27, "\(tag): 生きている間は従来の位置")
            let cardBottom = HUDDeathMetrics.cardCenter(l).y + HUDDeathMetrics.cardHeight / 2
            let bannerTop = HUDRootMetrics.playerBannerCenterY(l, heroDead: true) - HUDRootMetrics.bannerHalfHeight(l)
            XCTAssertGreaterThanOrEqual(bannerTop, cardBottom, "\(tag): 告知が復活までのカードを隠す")
            XCTAssertLessThan(bannerTop, l.height / 2, "\(tag): 告知は画面の上半分に収まる")
        }
    }

    // MARK: 観戦席の待機

    func testSpectatorWaitingPillSitsBetweenTheTopBandsAndTheDock() {
        for (tag, l) in layouts() {
            let sl = HUDSpectatorLayout(base: l, seekable: false)
            let top = OnlineBattleOverlay.spectatorWaitingTop(l)
            XCTAssertGreaterThanOrEqual(top, sl.objectivesBottom, "\(tag): 上部の帯（スコア・ゴールド・目標）と重なる")
            XCTAssertLessThanOrEqual(top + OnlineBattleOverlay.spectatorWaitingMaxHeight, sl.dockTop, "\(tag): ドックと重なる")
            XCTAssertLessThanOrEqual(OnlineBattleOverlay.spectatorWaitingMaxWidth(l), l.width, "\(tag)")
        }
    }

    // MARK: 読み上げ

    func testAccessibilityLabelsUseTheLanguagesSeparator() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        Loc.current = .en
        let row = ReplayLibrary.rowAccessibilityLabel(title: "Kael", mode: .ranked, date: date, unplayable: true)
        XCTAssertFalse(row.contains("、"), row)
        XCTAssertTrue(row.contains(", "), row)
        XCTAssertFalse(ReplayLibrary.modeFilterAccessibilityLabel(.spectate).contains("、"))
        XCTAssertFalse(SpectateSetup.slotAccessibilityLabel(team: .blue, position: .mid, heroName: "Kael", pinned: true).contains("、"))
        Loc.current = .ja
        let ja = ReplayLibrary.rowAccessibilityLabel(title: "Kael", mode: .ranked, date: date, unplayable: false)
        XCTAssertTrue(ja.contains("、"), ja)
        XCTAssertEqual(ReplayLibrary.modeFilterAccessibilityLabel(nil), "モードで絞り込む")
    }
}
