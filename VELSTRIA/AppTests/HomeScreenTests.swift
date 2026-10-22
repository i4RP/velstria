import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

// 担当: home-chrome。ホーム画面の純粋ロジック（HomeLogic.swift）: 採用案（Celestial Saber）のロビーが全対応端末で
// 縦横同じ倍率のままセーフエリアに収まること、ドロワーと識別子、左のカード・フレンド欄の表示、書式、同梱フォントの登録。

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
        }
    }

    func testPlayButtonClearsDynamicIslandOnProMax() {
        let l = HomeLayout(size: CGSize(width: 956, height: 440), safeArea: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62))
        XCTAssertLessThanOrEqual(l.screenRect(HomeLobbySlot.play).maxX, 956 - 62 + 0.5)
        XCTAssertGreaterThanOrEqual(l.screenRect(HomeLobbySlot.profile).minX, 62 - 0.5)
    }

    func testSlotsStayOnBoardAndDoNotOverlap() {
        let board = CGRect(origin: .zero, size: HomeLayout.board)
        for slot in HomeLobbySlot.all {
            XCTAssertTrue(board.contains(slot.rect), "\(slot.name) が板の外 \(slot.rect)")
        }
        // 押せる部品どうしは重ならない（中央のキービジュアルは背景の扱いなので除く）
        let parts = HomeLobbySlot.all.filter { $0.name != "keyVisual" }
        for i in parts.indices {
            for j in parts.indices where j > i {
                XCTAssertFalse(parts[i].rect.intersects(parts[j].rect), "\(parts[i].name) と \(parts[j].name) が重なる")
            }
        }
    }

    func testIdentifiersAreUniqueAndKeepLegacyOnes() {
        let all = HomeIdentifiers.all
        XCTAssertEqual(all.count, Set(all).count, "識別子が重複している")
        // 既存の UI テストが使う識別子
        for id in ["home_play", "home_profile", "home_mail", "home_rank", "home_menu", "home_menu_notices"] {
            XCTAssertTrue(all.contains(id), id)
        }
    }

    func testEveryScreenHasOneEntryAndMenuHoldsOnlyTheRest() {
        // 採用案のロビーに入口の無い画面（お知らせ・ランキング・観戦・バトルスキル）はドロワーから
        let routes = HomeMenuItem.allCases.map(\.route)
        for r in [Route.notices, .ranking, .spectateSetup, .spells] {
            XCTAssertTrue(routes.contains(r), "\(r) へ行けない")
        }
        // ほかに入口がある画面はドロワーに置かない
        for r in [Route.achievements, .records, .support, .cosmetics, .practiceSetup, .tutorialMenu, .patchNotes] {
            XCTAssertFalse(routes.contains(r), "\(r) がドロワーとほかの入口で重複")
        }
        XCTAssertEqual(Set(routes).count, routes.count)
    }

    func testPassCardProgress() {
        let start = HomePassProgress(xp: 0)
        XCTAssertEqual(start.label, "Lv.0/\(LiveOpsService.passMaxLevel)")
        XCTAssertEqual(start.fraction, 0)
        let mid = HomePassProgress(xp: LiveOpsService.passXPPerLevel * 3 + LiveOpsService.passXPPerLevel / 4)
        XCTAssertEqual(mid.level, 3)
        XCTAssertEqual(mid.fraction, 0.25, accuracy: 0.001)
        let max = HomePassProgress(xp: LiveOpsService.passXPPerLevel * (LiveOpsService.passMaxLevel + 5))
        XCTAssertEqual(max.level, LiveOpsService.passMaxLevel)
        XCTAssertEqual(max.fraction, 1)
    }

    func testFriendStatusAndInvite() {
        XCTAssertEqual(HomeFriendStatus.of(online: false, inMyTeam: false), .offline)
        XCTAssertEqual(HomeFriendStatus.of(online: false, inMyTeam: true), .offline)
        XCTAssertEqual(HomeFriendStatus.of(online: true, inMyTeam: false), .online)
        XCTAssertEqual(HomeFriendStatus.of(online: true, inMyTeam: true), .inTeam)
        XCTAssertTrue(HomeFriendStatus.online.canInvite)
        for s in [HomeFriendStatus.offline, .inTeam, .inMatch, .practicing] {
            XCTAssertFalse(s.canInvite, "\(s) は招待できない")
        }
        XCTAssertEqual(HomeFriendStatus.inTeam.title, "チーム中")
        XCTAssertEqual(HomeFriendStatus.practicing.title, "練習中")
    }

    /// MLBB のフレンドの状態: ランキングルーム中・マッチング中・試合中（「ランキング1分」）・集計中・ライブ観戦・Offline。
    func testFriendActivityBecomesMLBBStatus() {
        let saved = Loc.current
        defer { Loc.current = saved }
        Loc.current = .ja
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func status(_ a: FriendActivity?, online: Bool = true) -> HomeFriendStatus {
            HomeFriendStatus.of(online: online, inMyTeam: false, activity: a, now: now)
        }
        XCTAssertEqual(status(nil).title, "オンライン")
        XCTAssertEqual(status(FriendActivity(.room, mode: "ranked")).title, "ランキングルーム中")
        XCTAssertEqual(status(FriendActivity(.matching, mode: "ranked")).title, "マッチング中")
        XCTAssertEqual(status(FriendActivity(.match, mode: "ranked", since: now.addingTimeInterval(-90))).title, "ランキング1分")
        XCTAssertEqual(status(FriendActivity(.match, mode: "classic", since: now.addingTimeInterval(-600))).title, "マッチング10分")
        XCTAssertEqual(status(FriendActivity(.tally)).title, "集計中")
        XCTAssertEqual(status(FriendActivity(.watch)).title, "ライブ観戦")
        XCTAssertEqual(status(FriendActivity(.watch)).tone, .watching)
        XCTAssertEqual(status(FriendActivity(.match, mode: "ranked")).tone, .busy)
        XCTAssertEqual(status(FriendActivity(.room, mode: "ranked"), online: false), .offline, "オフラインなら状態は見ない")
        XCTAssertEqual(HomeFriendStatus.offline.title, "Offline")
        XCTAssertFalse(status(FriendActivity(.matching)).canInvite, "マッチング中は招待できない")
        XCTAssertEqual(FriendActivityMode.mode(FriendActivityMode.code(.magicChess)), .magicChess)
        // 中継の応答（status は在席の相手だけ）・自分の状態の送り方
        XCTAssertEqual(InboxServerMessage.decode(#"{"t":"presence","online":["ABCDEFGH"],"status":{"ABCDEFGH":{"s":"match","m":"ranked","at":5},"WXYZ6789":{"s":"room"}}}"#),
                       .presence(online: ["ABCDEFGH"], activity: ["ABCDEFGH": FriendActivity(.match, mode: "ranked", since: Date(timeIntervalSince1970: 0.005))]))
        let sent = InboxClientMessage.status(FriendActivity(.room, mode: "ranked")).flatMap { $0.data(using: .utf8) }
        let json = sent.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        XCTAssertEqual(json["t"] as? String, "status")
        XCTAssertEqual(json["s"] as? String, "room")
        XCTAssertEqual(json["m"] as? String, "ranked")
        XCTAssertNil(json["at"])
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
