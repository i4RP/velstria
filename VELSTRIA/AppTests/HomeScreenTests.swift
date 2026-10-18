import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

// 担当: home-chrome。ホーム画面の純粋ロジック（HomeLogic.swift）: 参照デザインのロビーが全対応端末で
// 縦横同じ倍率のままセーフエリアに収まること、識別子、ショーケースの巡回、書式、同梱フォントの登録。

final class HomeScreenTests: XCTestCase {
    private var savedLanguage: AppLanguage = .ja

    override func setUp() {
        super.setUp()
        savedLanguage = Loc.current
        Loc.current = .ja
    }

    override func tearDown() {
        Loc.current = savedLanguage
        super.tearDown()
    }

    /// 対応端末（横画面）の画面サイズとセーフエリア。
    private static let devices: [(name: String, size: CGSize, inset: EdgeInsets)] = [
        ("iPhone SE 3", CGSize(width: 667, height: 375), EdgeInsets()),
        ("iPhone 16e", CGSize(width: 844, height: 390), EdgeInsets(top: 0, leading: 47, bottom: 21, trailing: 47)),
        ("iPhone 17", CGSize(width: 874, height: 402), EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440), EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)),
    ]

    func testLobbyKeepsAspectAndFitsSafeArea() {
        for d in Self.devices {
            let l = HomeLayout(size: d.size, safeArea: d.inset)
            let screen = CGRect(origin: .zero, size: d.size)
            // 縦横同じ倍率（板の縦横比のまま）
            XCTAssertEqual(l.boardRect.width / l.boardRect.height, HomeLayout.board.width / HomeLayout.board.height,
                           accuracy: 0.001, d.name)
            XCTAssertEqual(l.boardRect.width, HomeLayout.board.width * l.scale, accuracy: 0.01, d.name)
            // 板はセーフエリアの内側（Dynamic Island・角丸・ホームインジケータを避ける）で、どちらかの辺に接する
            XCTAssertTrue(l.safeRect.insetBy(dx: -0.5, dy: -0.5).contains(l.boardRect), "\(d.name): 板がはみ出す \(l.boardRect)")
            XCTAssertTrue(abs(l.boardRect.width - l.safeRect.width) < 0.5 || abs(l.boardRect.height - l.safeRect.height) < 0.5,
                          "\(d.name): 余白が大きすぎる")
            for slot in HomeLobbySlot.all {
                let r = l.screenRect(slot.rect)
                XCTAssertTrue(screen.contains(r), "\(d.name): \(slot.name) が画面外 \(r)")
                XCTAssertTrue(l.safeRect.insetBy(dx: -0.5, dy: -0.5).contains(r), "\(d.name): \(slot.name) がセーフエリアにはみ出す \(r)")
            }
            // フッターの帯は画面の左端と下端まで
            XCTAssertEqual(l.footerBandRect.minX, 0, d.name)
            XCTAssertEqual(l.footerBandRect.maxY, d.size.height, accuracy: 0.01, d.name)
        }
    }

    func testPlayButtonClearsDynamicIslandOnProMax() {
        // 以前は縦横別の倍率でセーフエリアを見ず、17 Pro Max で対戦開始ボタンが右へ約 38pt はみ出していた
        let l = HomeLayout(size: CGSize(width: 956, height: 440), safeArea: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62))
        XCTAssertLessThanOrEqual(l.screenRect(HomeLobbySlot.play).maxX, 956 - 62 + 0.5)
        XCTAssertGreaterThanOrEqual(l.screenRect(HomeLobbySlot.profile).minX, 62 - 0.5)
    }

    func testSlotsStayOnBoardAndDoNotOverlap() {
        let board = CGRect(origin: .zero, size: HomeLayout.board)
        for slot in HomeLobbySlot.all {
            XCTAssertTrue(board.contains(slot.rect), "\(slot.name) が板の外 \(slot.rect)")
        }
        // 下段の押せる部品どうし（タブ・エンブレム・ランク・対戦開始）は重ならない
        let bottom = [HomeLobbySlot.footerTabs, HomeLobbySlot.emblems, HomeLobbySlot.rank, HomeLobbySlot.play]
        for i in bottom.indices {
            for j in bottom.indices where j > i {
                XCTAssertFalse(bottom[i].intersects(bottom[j]), "下段の部品 \(i) と \(j) が重なる")
            }
        }
    }

    func testIdentifiersAreUniqueAndKeepLegacyOnes() {
        let all = HomeIdentifiers.all
        XCTAssertEqual(all.count, Set(all).count, "識別子が重複している")
        // 既存の UI テストが使う識別子
        for id in ["home_play", "home_profile", "home_mail", "home_notices", "home_records", "home_rank"] {
            XCTAssertTrue(all.contains(id), id)
        }
    }

    func testMenuDoesNotDuplicateLobbyEntries() {
        // ロビーに入口がある画面と、モード選択（VS AI & カスタム）にある画面はドロワーに置かない
        let routes = HomeMenuItem.allCases.map(\.route)
        for r in [Route.achievements, .ranking, .support, .cosmetics, .practiceSetup, .tutorialMenu] {
            XCTAssertFalse(routes.contains(r), "\(r) がドロワーとほかの入口で重複")
        }
        XCTAssertEqual(Set(routes).count, routes.count)
    }

    func testShowcaseCycling() {
        let master = ["H001", "H002", "H003", "H004"]
        let roster = HomeShowcaseLogic.roster(owned: ["H004", "H002", "H009"], masterOrder: master)
        XCTAssertEqual(roster, ["H002", "H004"], "所持ヒーローをマスター順に（マスターに無い ID は除く）")
        XCTAssertEqual(HomeShowcaseLogic.neighbor(of: "H002", in: roster, step: 1), "H004")
        XCTAssertEqual(HomeShowcaseLogic.neighbor(of: "H004", in: roster, step: 1), "H002", "末尾の次は先頭")
        XCTAssertEqual(HomeShowcaseLogic.neighbor(of: "H002", in: roster, step: -1), "H004", "先頭の前は末尾")
        XCTAssertEqual(HomeShowcaseLogic.neighbor(of: "H001", in: roster, step: 1), "H002", "巡回対象外からは先頭へ")
        XCTAssertEqual(HomeShowcaseLogic.neighbor(of: "H001", in: roster, step: -1), "H004", "巡回対象外からは末尾へ")
        XCTAssertEqual(HomeShowcaseLogic.neighbor(of: "H001", in: [], step: 1), "H001")
        XCTAssertEqual(HomeShowcaseLogic.initialHero(lastPicked: "H003", avatar: "H001", isKnown: { $0 == "H003" }), "H003")
        XCTAssertEqual(HomeShowcaseLogic.initialHero(lastPicked: "H099", avatar: "H001", isKnown: { $0 == "H003" }), "H001")
        XCTAssertEqual(HomeShowcaseLogic.initialHero(lastPicked: nil, avatar: "H001", isKnown: { _ in true }), "H001")
    }

    func testCurrencyFormat() {
        XCTAssertEqual(HomeFormat.currency(0), "0")
        XCTAssertEqual(HomeFormat.currency(-5), "0")
        XCTAssertEqual(HomeFormat.currency(1234), "1,234")
        XCTAssertEqual(HomeFormat.currency(100_000), "100,000")
        XCTAssertEqual(HomeFormat.currency(100_000, compact: true), "100K")
        XCTAssertEqual(HomeFormat.currency(1_299_999), "1.2M", "切り捨て（多く見せない）")
        XCTAssertEqual(HomeFormat.currency(2_000_000), "2M")
        XCTAssertEqual(HomeFormat.currency(345_000_000), "345M")
        XCTAssertEqual(HomeFormat.currency(1_500_000_000), "1.5B")
    }

    func testRemainingFormat() {
        XCTAssertEqual(HomeFormat.remaining(3 * 86_400 + 5 * 3_600 + 120), "残り 3日 5時間")
        XCTAssertEqual(HomeFormat.remaining(2 * 3_600 + 30 * 60), "残り 2時間 30分")
        XCTAssertEqual(HomeFormat.remaining(20), "残り 1分")
        XCTAssertEqual(HomeFormat.remaining(-10), "残り 1分")
        XCTAssertEqual(HomeFormat.remaining(.infinity), "残り 1分")
        Loc.current = .en
        XCTAssertEqual(HomeFormat.remaining(90 * 60), "1h 30m left")
    }

    func testBundledFontsAreRegistered() {
        XCTAssertEqual(HomeFont.unresolvedFaces, [], "Info.plist の UIAppFonts とフォントの同梱を確認")
    }
}
