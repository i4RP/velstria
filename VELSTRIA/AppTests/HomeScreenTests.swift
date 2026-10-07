import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

// 担当: home-chrome。ホーム画面の純粋ロジック（HomeLogic.swift）: 全対応端末で配置が収まること、
// 項目と識別子、ショーケースの巡回、書式、同梱フォントの登録。

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

    func testLayoutFitsEverySupportedDevice() {
        for d in Self.devices {
            let m = HomeMetrics(size: d.size, safeArea: d.inset)
            let screen = CGRect(origin: .zero, size: d.size)
            let content = CGRect(x: m.contentMinX, y: 0, width: m.contentMaxX - m.contentMinX, height: d.size.height)
            for (label, r) in [("left", m.leftRailRect), ("right", m.rightRailRect), ("center", m.centerRect),
                               ("tabs", m.tabsRect), ("start", m.startRect), ("handle", m.handleRect)] {
                XCTAssertTrue(screen.contains(r), "\(d.name): \(label) が画面外 \(r)")
                XCTAssertTrue(content.insetBy(dx: -0.5, dy: 0).contains(r), "\(d.name): \(label) がセーフエリアにはみ出す \(r)")
            }
            XCTAssertGreaterThanOrEqual(m.leftRailRect.width, HomeMetrics.minLeftRailWidth, d.name)
            XCTAssertGreaterThanOrEqual(m.rightRailRect.width, HomeMetrics.minRightRailWidth, d.name)
            XCTAssertGreaterThanOrEqual(m.centerRect.width, HomeMetrics.minCenterWidth, d.name)
            // 列どうしが重ならない（左 → 中央 → 取っ手 → 右）
            XCTAssertLessThanOrEqual(m.leftRailRect.maxX, m.centerRect.minX, d.name)
            XCTAssertLessThanOrEqual(m.centerRect.maxX, m.handleRect.minX, d.name)
            XCTAssertLessThanOrEqual(m.handleRect.maxX, m.rightRailRect.minX + 0.5, d.name)
            XCTAssertLessThanOrEqual(m.tabsRect.maxX, m.startRect.minX, d.name)
            // 縦: ヘッダーの下にレール、レールの下にフッター・START
            XCTAssertGreaterThanOrEqual(m.leftRailRect.minY, m.headerRect.maxY, d.name)
            XCTAssertLessThanOrEqual(m.leftRailRect.maxY, m.footerRect.minY, d.name)
            XCTAssertLessThanOrEqual(m.rightRailRect.maxY, m.firstWinChipRect.minY, d.name)
            XCTAssertLessThanOrEqual(m.firstWinChipRect.maxY, m.startRect.minY, d.name)
            // 左レールの中身（バナー 2 + リスト 3 + 間隔）が収まり、押せる大きさがある
            let leftNeeded = 2 * m.bannerHeight + 3 * m.listItemHeight + 4 * m.spacing
            XCTAssertLessThanOrEqual(leftNeeded, m.leftRailRect.height + 0.5, d.name)
            XCTAssertGreaterThanOrEqual(m.listItemHeight, HomeMetrics.minTapSize, d.name)
            XCTAssertGreaterThanOrEqual(m.modeSlotHeight - m.modeCardSpacing, HomeMetrics.minTapSize, d.name)
            XCTAssertGreaterThanOrEqual(m.socialRowHeight, HomeMetrics.minTapSize, d.name)
            XCTAssertGreaterThanOrEqual(m.footerBarHeight, HomeMetrics.minTapSize, d.name)
            XCTAssertGreaterThanOrEqual(m.startRect.height, 60, d.name)
            // 畳んだ右レールは画面外へ、取っ手は中身の右端に残る
            XCTAssertGreaterThanOrEqual(m.rightRailRect.minX + m.railCollapseOffset, d.size.width, d.name)
            XCTAssertEqual(m.handleRect.maxX + m.handleCollapseOffset, m.contentMaxX, accuracy: 0.5, d.name)
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

    func testModesKeepTheirDestinations() {
        XCTAssertEqual(HomeMode.ranked.action(difficulty: .normal), .match(.ranked))
        XCTAssertEqual(HomeMode.classic.action(difficulty: .hard), .match(.standard(.hard)))
        XCTAssertEqual(HomeMode.brawl.action(difficulty: .easy), .match(.brawl(.easy)))
        XCTAssertEqual(HomeMode.arcade.action(difficulty: .normal), .push(.arcade))
        XCTAssertEqual(HomeMode.rising.action(difficulty: .normal), .push(.rising))
        XCTAssertEqual(HomeMode.custom.action(difficulty: .normal), .push(.customSetup))
        XCTAssertEqual(HomeMode.magicChess.action(difficulty: .normal), .push(.magicChess))
        XCTAssertEqual(HomeMode.allCases.filter(\.startsMatch), [.ranked, .classic, .brawl])
    }

    func testSocialLinksFollowFeatureFlag() {
        XCTAssertEqual(HomeSocialLink.visible(lanMatch: true), [.online, .spectate, .replays])
        XCTAssertEqual(HomeSocialLink.visible(lanMatch: false), [.spectate, .replays])
    }

    func testEveryHomeEntryPointIsReachable() {
        // 旧ホームから行けた先がすべて新しいホーム（レール・タブ・ドロワー）から行けること
        var routes: [Route] = HomeQuickLink.allCases.map(\.route) + HomeSocialLink.allCases.map(\.route)
            + HomeTab.allCases.compactMap(\.route) + HomeMenuItem.allCases.map(\.route)
        routes += HomeMode.allCases.compactMap {
            if case .push(let r) = $0.action(difficulty: .normal) { return r } else { return nil }
        }
        routes += [.profile, .rankOverview, .currencyStore, .mail, .notices, .settings, .events, .starPass]
        for r in [Route.heroes, .items, .runes, .store, .records, .replays, .spectateSetup, .practiceSetup, .onlineLobby,
                  .settings, .missions, .events, .starPass, .arcade, .rising, .customSetup, .magicChess] {
            XCTAssertTrue(routes.contains(r), "\(r) へ行けない")
        }
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

    func testBackdropAspectFill() {
        let r = HomeBackdrop.aspectFillRect(image: CGSize(width: 1600, height: 900), in: CGSize(width: 874, height: 402))
        XCTAssertEqual(r.width, 874, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(r.height, 402)
        XCTAssertEqual(r.midY, 201, accuracy: 0.5)
    }
}
