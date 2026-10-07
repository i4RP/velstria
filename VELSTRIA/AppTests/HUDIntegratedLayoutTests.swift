import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud（統合）。デス画面アップグレードの 4 担当の部品どうしの重なり:
// 上部（スコア・味方列・ミニマップ横の縦列・情報列）、シグナル（列・メッセージ・クイックチャットのメニュー・キルフィード）、
// デス画面（復活カウントのエンブレム）、操作ラベル（スキルの種別タグ）を、4 端末 × 左右配置で突き合わせる。
// 各担当のテストは自分の部品と main の操作部品（攻撃 3 つ・スキル格子・ミニマップドック等）との重なりを見ている。
// 統合側の表示の譲り合い: 告知バナー（死亡中はチュートリアルでもエンブレムより上）、レベルアップ表示とキルフィード
// （2 件以上の時は隠す・隠れている間は寿命を進めない）、メッセージの欄と移動スティックの待機位置の円。

@MainActor
final class HUDIntegratedLayoutTests: XCTestCase {
    /// HUDLayoutTests と同じ端末（横画面の論理サイズと Safe Area）。
    private let devices: [(name: String, size: CGSize, side: CGFloat, bottom: CGFloat)] = [
        ("iPhone 13 mini", CGSize(width: 812, height: 375), 44, 21),
        ("iPhone 16e", CGSize(width: 844, height: 390), 47, 21),
        ("iPhone 17 Pro", CGSize(width: 874, height: 402), 62, 20),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440), 62, 20),
    ]

    private var savedLanguage: AppLanguage = .ja

    override func setUp() {
        super.setUp()
        savedLanguage = Loc.current
    }

    override func tearDown() {
        Loc.current = savedLanguage
        super.tearDown()
    }

    private func layouts() -> [(tag: String, l: HUDLayout)] {
        devices.flatMap { d in
            [false, true].map { left in
                ("\(d.name) \(left ? "左利き" : "右手")",
                 HUDLayout(size: d.size, safe: EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side),
                           leftHanded: left))
            }
        }
    }

    private func rect(_ c: CGPoint, _ s: CGSize) -> CGRect {
        CGRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height)
    }

    // MARK: 各担当の部品

    /// 上部（top 担当）: スコア・味方列・情報列（成績 + スコアボード）・縦列（端末状態・設定・消音・ズーム）。
    private func topRects(_ l: HUDLayout) -> [(String, CGRect)] {
        [("スコア", l.scoreFrame), ("味方列", l.allyStripFrame), ("情報列", l.topInfoFrame(spectating: false))]
            + l.utilityFrames.enumerated().map { ("縦列\($0.offset)", $0.element) }
    }

    /// キルフィード（BattleHUDView と同じく情報側の端から killFeedSideReserve だけ内側。最大 4 行の見積もり）。
    private func killFeedRect(_ l: HUDLayout) -> CGRect {
        let size = HUDLayout.killFeedEstimate
        let x = l.leftHanded ? l.leadingEdge + l.killFeedSideReserve : l.trailingEdge - l.killFeedSideReserve - size.width
        return CGRect(x: x, y: l.killFeedTop, width: size.width, height: size.height)
    }

    /// シグナル（signals 担当）: 列の各ボタンのタップ領域・メッセージの欄・キルフィード。
    private func signalRects(_ l: HUDLayout) -> [(String, CGRect)] {
        HUDSignalSlot.allCases.map { ("シグナル \($0)", l.signalSlotFrame($0)) }
            + [("メッセージ", l.signalMessageFrame), ("キルフィード", killFeedRect(l))]
    }

    /// デス画面（death 担当）: 復活カウントのエンブレム（「デス情報を見る」を含むタップ領域）。
    private func emblemRect(_ l: HUDLayout) -> CGRect {
        rect(l.deathEmblemCenter, l.deathEmblemSize)
    }

    /// 操作ラベル（controls 担当）: 各スキルの種別タグ（日英の全タグのうち最も幅の広いもの）。
    private func tagRects(_ l: HUDLayout) -> [(String, CGRect)] {
        var out: [(String, CGRect)] = []
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            let fs = l.controlLabelFontSize
            let wide = HUDSkillTag.allCases.filter { $0 != .passive }
                .map { HUDControlLabel.estimatedSize($0.label, fontSize: fs) }
                .max { $0.width < $1.width }!
            for slot in SkillSlot.actives {
                out.append(("タグ \(slot) \(lang)", rect(l.skillLabelCenter(slot, size: wide), wide)))
            }
        }
        Loc.current = savedLanguage
        return out
    }

    /// 告知バナー（BattleHUDView と同じ HUDRootMetrics.bannerCenterY・bannerHeight）の帯。
    private func bannerBand(_ l: HUDLayout, tutorial: Bool = false, dead: Bool = true) -> ClosedRange<CGFloat> {
        let h = HUDRootMetrics.bannerHeight(l)
        let y = HUDRootMetrics.bannerCenterY(l, tutorial: tutorial, dead: dead)
        return (y - h / 2)...(y + h / 2)
    }

    /// 画面中央のレベルアップ表示（BattleHUDView: 画面高さの 36%。「レベルアップ」18pt + 数字 30pt、幅は英語の
    /// 「LEVEL UP」・日本語の「レベルアップ」に余裕を見て 124pt）。
    private func levelUpRect(_ l: HUDLayout) -> CGRect {
        rect(CGPoint(x: l.width / 2, y: l.height * 0.36), CGSize(width: 124, height: 58))
    }

    // MARK: テスト

    func testOwnersDoNotOverlapEachOther() {
        for (tag, l) in layouts() {
            let groups: [(owner: String, rects: [(String, CGRect)])] = [
                ("top", topRects(l)),
                ("signals", signalRects(l)),
                ("death", [("エンブレム", emblemRect(l))]),
                ("controls", tagRects(l)),
            ]
            for i in groups.indices {
                for j in groups.indices where j > i {
                    for a in groups[i].rects {
                        for b in groups[j].rects {
                            XCTAssertFalse(a.1.intersects(b.1),
                                           "\(tag): \(a.0)（\(groups[i].owner)）と \(b.0)（\(groups[j].owner)）が重なる")
                        }
                    }
                }
            }
        }
    }

    /// クイックチャットのメニュー（開いている間だけ。キルフィードの上に重ねる）は上部とエンブレムにかからない。
    func testChatMenuClearsTopAndEmblem() {
        for (tag, l) in layouts() {
            let menu = l.signalChatMenuFrame
            for (name, r) in topRects(l) {
                XCTAssertFalse(menu.intersects(r), "\(tag): メニューと\(name)")
            }
            XCTAssertFalse(menu.intersects(emblemRect(l)), "\(tag): メニューとエンブレム")
        }
    }

    /// 告知バナーはエンブレムより上、上部の情報列・スコアより下に出る（死亡中に両方見える）。
    /// チュートリアル（通常は上の指示カードを避けて画面高さの 46%）でも、死亡中はエンブレムの上端より上に収める。
    func testBannerBandSitsBetweenTopAndEmblem() {
        for (tag, l) in layouts() {
            for tutorial in [false, true] {
                let t = "\(tag)\(tutorial ? " チュートリアル" : "")"
                let band = bannerBand(l, tutorial: tutorial)
                XCTAssertLessThan(band.upperBound, emblemRect(l).minY, "\(t): バナーとエンブレム")
                XCTAssertGreaterThan(band.lowerBound, l.scoreFrame.maxY, "\(t): バナーとスコア")
                XCTAssertGreaterThan(band.lowerBound, l.allyStripFrame.maxY, "\(t): バナーと味方列")
            }
            // 通常の試合は死亡中も同じ高さ（27%）、生きている間のチュートリアルは 46% のまま
            // 通常の試合は死亡中も 27%、エンブレムが高い端末（13 mini）ではその上端に収まる分だけ上
            XCTAssertLessThanOrEqual(HUDRootMetrics.bannerCenterY(l, tutorial: false, dead: true), l.height * 0.27 + 1e-6, tag)
            XCTAssertEqual(HUDRootMetrics.bannerCenterY(l, tutorial: false, dead: false), l.height * 0.27, accuracy: 1e-6, tag)
            XCTAssertEqual(HUDRootMetrics.bannerCenterY(l, tutorial: true, dead: false), l.height * 0.46, accuracy: 1e-6, tag)
        }
    }

    /// キルフィードの 1 行目はレベルアップ表示にかからない（2 行目以降は重なりうるので、2 件以上の時は表示中だけ隠す）。
    func testLevelUpClearsTheFirstKillFeedRow() {
        for (tag, l) in layouts() {
            let feed = killFeedRect(l)
            let firstRow = CGRect(x: feed.minX, y: feed.minY, width: feed.width, height: 26)
            XCTAssertFalse(firstRow.intersects(levelUpRect(l)), "\(tag): レベルアップとキルフィードの 1 行目")
        }
    }

    /// メッセージの欄（入る行数だけ）は移動スティックの待機位置の円にかからない。
    func testMessagesClearTheJoystickRest() {
        for (tag, l) in layouts() {
            let f = l.signalMessageFrame
            let c = l.joystickRest
            let x = min(max(c.x, f.minX), f.maxX)
            let y = min(max(c.y, f.minY), f.maxY)
            XCTAssertGreaterThanOrEqual(hypot(c.x - x, c.y - y), l.joystickRadius + 2, "\(tag): メッセージとスティックの円")
            XCTAssertGreaterThanOrEqual(l.signalMessageRows, 1, tag)
            XCTAssertLessThanOrEqual(l.signalMessageRows, HUDSignalBoard.maxMessages, tag)
        }
    }

    // MARK: キルフィードの譲り合い（HUDModel）

    private func killEvent(_ victim: EntityID, by killer: EntityID) -> SimEvent {
        .heroKilled(HeroKillEvent(victimID: victim, killerID: killer, assistIDs: [], bounty: 300,
                                  isFirstBlood: false, multiKill: 1, killerStreak: 1, isShutdown: false))
    }

    /// 内側へ寄せたキルフィードは、告知バナーの間と、2 件以上ある時のレベルアップ表示の間だけ隠れる。
    func testKillFeedYieldsToBannerAndLevelUp() throws {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H003",
                                                                                          humanName: "T", seed: 5)))
        let m = HUDModel(controller: c)
        let s = c.state
        let me = try XCTUnwrap(c.humanHeroID)
        let blue = s.heroIndices(team: .blue).map { s.units[$0].id }
        let red = s.heroIndices(team: .red).map { s.units[$0].id }
        XCTAssertTrue(m.killFeedReservesSignals)

        m.handle([killEvent(red[0], by: blue[0])])
        XCTAssertFalse(m.killFeedYieldsToCenter)
        m.handle([.levelUp(heroID: me, level: 2)])
        XCTAssertTrue(m.levelUpShowing)
        XCTAssertFalse(m.killFeedYieldsToCenter, "1 件だけならレベルアップ表示と重ならない")
        m.handle([killEvent(red[1], by: blue[1])])
        XCTAssertTrue(m.killFeedYieldsToCenter, "2 件以上は 2 行目がレベルアップ表示と重なる")

        let m2 = HUDModel(controller: c)
        m2.handle([.announcement(.firstBlood(killerID: blue[0], victimID: red[0]))])
        XCTAssertNotNil(m2.banner)
        XCTAssertTrue(m2.killFeedYieldsToCenter)

        // チュートリアルはシグナル列が無いのでキルフィードは端のまま（隠さない）
        let tc = BattleController(launch: BattleLaunch(config: MatchFactory.practiceMatch(
            humanHeroID: "H001", humanName: "T", options: PracticeOptions(), tutorial: true, seed: 5)))
        XCTAssertFalse(HUDModel(controller: tc).killFeedReservesSignals)
    }

    /// 隠れていた間は寿命に数えない（バナーが続いても、キルが一度も見えずに消えない）。
    func testKillFeedAgeSkipsHiddenTime() {
        let e = HUDKillFeedEntry(id: 1, killerHeroID: "H001", killerTeam: .blue, victimHeroID: "H002", victimTeam: .red,
                                 assists: 0, involvesHuman: false, createdAt: 100, gameTime: 10,
                                 heldBase: 2, heldGameBase: 2)
        // 作ってから 9 秒（試合時間も 9 秒）隠れていなければ期限切れ
        XCTAssertTrue(HUDModel.feedEntryExpired(e, wall: 109, game: 19, heldWall: 2, heldGame: 2))
        // そのうち 6 秒隠れていた: 見えていたのは 3 秒なので残る
        XCTAssertFalse(HUDModel.feedEntryExpired(e, wall: 109, game: 19, heldWall: 8, heldGame: 8))
        XCTAssertFalse(HUDModel.feedEntryExpired(e, wall: 109, game: 19, heldWall: 8, heldGame: 8), "実時間・試合時間の両方で数える")
        // 隠れていた分を引いても、見えた時間が寿命を超えれば消える
        XCTAssertTrue(HUDModel.feedEntryExpired(e, wall: 125, game: 35, heldWall: 8, heldGame: 8))
    }
}
