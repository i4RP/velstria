import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud。スキル長押しの説明カード（HUDLayout.skillTipFrame）と攻撃ボタンの絵柄:
// カードの枠が他の HUD 部品（シグナル列・クイックチャットのメニュー・ミニマップ・縦列・スコア・味方列・ヒーローパネル・
// 操作部品の円・習得バッジ・スティック・降参投票）に重ならず Safe Area に収まること（4 端末 × 左右配置）、
// キルフィードだけは説明を出している間は隠すこと、中央の攻撃ボタンが剣で優先対象を小さな記号で示すこと、
// 必殺・枠番号のバッジがボタンの円の内側に収まること。

@MainActor
final class HUDSkillTipTests: XCTestCase {
    /// HUDIntegratedLayoutTests と同じ端末（横画面の論理サイズと Safe Area）。
    private let devices: [(name: String, size: CGSize, side: CGFloat, bottom: CGFloat)] = [
        ("iPhone 13 mini", CGSize(width: 812, height: 375), 44, 21),
        ("iPhone 16e", CGSize(width: 844, height: 390), 47, 21),
        ("iPhone 17 Pro", CGSize(width: 874, height: 402), 62, 20),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440), 62, 20),
    ]

    private func layouts() -> [(tag: String, l: HUDLayout)] {
        devices.flatMap { d in
            [false, true].map { left in
                ("\(d.name) \(left ? "左利き" : "右手")",
                 HUDLayout(size: d.size, safe: EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side),
                           leftHanded: left))
            }
        }
    }

    /// 円と矩形が重ならない（円の中心から矩形までの距離が半径以上）。
    private func clears(_ r: CGRect, center: CGPoint, radius: CGFloat) -> Bool {
        let x = min(max(center.x, r.minX), r.maxX)
        let y = min(max(center.y, r.minY), r.maxY)
        return hypot(center.x - x, center.y - y) >= radius
    }

    /// キルフィード（BattleHUDView と同じく情報側の端から killFeedSideReserve だけ内側。最大 4 行の見積もり）。
    private func killFeedRect(_ l: HUDLayout) -> CGRect {
        let size = HUDLayout.killFeedEstimate
        let x = l.leftHanded ? l.leadingEdge + l.killFeedSideReserve : l.trailingEdge - l.killFeedSideReserve - size.width
        return CGRect(x: x, y: l.killFeedTop, width: size.width, height: size.height)
    }

    // MARK: 説明カードの枠

    /// 読める大きさがあり、Safe Area に収まり、クラスタ（スキル）の側に寄っている。
    func testTipFrameIsReadableAndInsideSafeArea() {
        for (tag, l) in layouts() {
            let f = l.skillTipFrame
            XCTAssertGreaterThanOrEqual(f.width, 200, "\(tag): カードの幅が足りない")
            XCTAssertLessThanOrEqual(f.width, l.skillTipMaxWidth + 1e-6, tag)
            XCTAssertGreaterThanOrEqual(f.height, 120, "\(tag): カードの高さが足りない")
            XCTAssertGreaterThanOrEqual(f.minX, l.leadingEdge, "\(tag): 左の Safe Area にかかる")
            XCTAssertLessThanOrEqual(f.maxX, l.trailingEdge, "\(tag): 右の Safe Area にかかる")
            XCTAssertGreaterThanOrEqual(f.minY, l.topEdge, "\(tag): 上の Safe Area にかかる")
            XCTAssertLessThanOrEqual(f.maxY, l.bottomEdge, "\(tag): ホームインジケータにかかる")
            // 縦列（ミニマップの内側）の外側・攻撃ボタンの列の画面中央側
            if l.leftHanded {
                XCTAssertLessThanOrEqual(f.maxX, l.utilityColumnFrame.minX - HUDLayout.skillTipGap + 1e-6, tag)
                XCTAssertGreaterThan(f.minX, l.attackCenter.x, "\(tag): 攻撃ボタンの列より中央側")
            } else {
                XCTAssertGreaterThanOrEqual(f.minX, l.utilityColumnFrame.maxX + HUDLayout.skillTipGap - 1e-6, tag)
                XCTAssertLessThan(f.maxX, l.attackCenter.x, "\(tag): 攻撃ボタンの列より中央側")
            }
            // 文字は 11pt 以上、説明文は 6 行以上入る
            XCTAssertGreaterThanOrEqual(l.skillTipBodyFontSize, 11, tag)
            XCTAssertGreaterThanOrEqual(l.skillTipTitleFontSize, 13, tag)
            XCTAssertGreaterThanOrEqual(l.skillTipBodyLineLimit, 6, "\(tag): 説明文の行数")
        }
    }

    /// 他の HUD 部品（隠さないもの全部）に重ならない。
    func testTipFrameDoesNotOverlapOtherHUDParts() {
        for (tag, l) in layouts() {
            let f = l.skillTipFrame
            var rects: [(String, CGRect)] = [
                ("シグナル列", l.signalTrayFrame),
                ("クイックチャットのメニュー", l.signalChatMenuFrame),
                ("メッセージの欄", l.signalMessageFrame),
                ("ミニマップ", l.minimapDockFrame),
                ("スコア", l.scoreFrame),
                ("味方列", l.allyStripFrame),
                ("情報列", l.topInfoFrame(spectating: false)),
                ("降参投票", HUDSurrenderMetrics.frame(l)),
                ("ヒーローパネル", CGRect(x: l.heroPanelCenterX - l.heroPanelWidth / 2,
                                          y: l.bottomEdge - HUDRootMetrics.heroPanelHeight(l),
                                          width: l.heroPanelWidth, height: HUDRootMetrics.heroPanelHeight(l))),
            ]
            rects += HUDSignalSlot.allCases.map { ("シグナル \($0)", l.signalSlotFrame($0)) }
            rects += l.utilityFrames.enumerated().map { ("縦列\($0.offset)", $0.element) }
            rects += l.signalLevelBadgeRects.enumerated().map { ("習得バッジ\($0.offset)", $0.element) }
            for (name, r) in rects {
                XCTAssertFalse(f.intersects(r), "\(tag): カードと\(name)が重なる")
            }
            for (k, d) in l.signalControlDiscs.enumerated() {
                XCTAssertTrue(clears(f, center: d.center, radius: d.radius), "\(tag): カードと操作部品の円 \(k)が重なる")
            }
            XCTAssertTrue(clears(f, center: l.joystickRest, radius: l.joystickRadius), "\(tag): カードとスティックが重なる")
        }
    }

    /// キルフィードは同じ空きに出うるので、カードを出している間は隠す（それ以外は今までどおり）。
    func testKillFeedIsHiddenWhileTipIsShown() {
        XCTAssertTrue(HUDKillFeedRule.isHidden(aiming: false, tipShown: true, covered: false, yieldsToCenter: false))
        XCTAssertTrue(HUDKillFeedRule.isHidden(aiming: true, tipShown: false, covered: false, yieldsToCenter: false))
        XCTAssertTrue(HUDKillFeedRule.isHidden(aiming: false, tipShown: false, covered: true, yieldsToCenter: false))
        XCTAssertTrue(HUDKillFeedRule.isHidden(aiming: false, tipShown: false, covered: false, yieldsToCenter: true))
        XCTAssertFalse(HUDKillFeedRule.isHidden(aiming: false, tipShown: false, covered: false, yieldsToCenter: false))
        // 重なりうる端末でも、重なるのは隠れるキルフィードだけ（上のテストで他の部品とは重ならないことを確認済み）
        for (tag, l) in layouts() {
            let overlapsFeed = l.skillTipFrame.intersects(killFeedRect(l))
            if overlapsFeed {
                XCTAssertTrue(HUDKillFeedRule.isHidden(aiming: false, tipShown: true, covered: false, yieldsToCenter: false), tag)
            }
        }
    }

    // MARK: 攻撃ボタンの絵柄

    func testCenterAttackButtonIsASwordAndShowsNonDefaultPriorityAsBadge() {
        for p in SettingsText.allPriorities {
            XCTAssertEqual(HUDAttackIcon.main(slot: .center, priority: p), .swords, "中央は優先対象に関わらず剣: \(p)")
        }
        // 既定（実質低 HP）は記号を出さない。ほかの選択肢は小さな記号で示す
        XCTAssertNil(HUDAttackIcon.badge(slot: .center, priority: GameSettings().attackPriority))
        XCTAssertEqual(GameSettings().attackPriority, .lowestHealth)
        XCTAssertEqual(HUDAttackIcon.badge(slot: .center, priority: .lowestHealthPercent), "percent")
        XCTAssertEqual(HUDAttackIcon.badge(slot: .center, priority: .nearest), "location.fill")
        // 上下のボタンは記号を持たない
        for slot in [AttackButtonSlot.top, .bottom] {
            for p in SettingsText.allPriorities {
                XCTAssertNil(HUDAttackIcon.badge(slot: slot, priority: p), "\(slot) \(p)")
            }
        }
    }

    func testTopAndBottomAttackButtonsShowTowerAndMinionIcons() {
        XCTAssertEqual(HUDAttackIcon.main(slot: .top, priority: .structuresFirst), .tower)
        XCTAssertEqual(HUDAttackIcon.main(slot: .bottom, priority: .minionsFirst),
                       .symbol(SettingsText.attackPrioritySymbol(.minionsFirst)))
        XCTAssertEqual(HUDAttackIcon.main(slot: .bottom, priority: .structuresFirst), .tower, "タワーはどのボタンでも同じ絵柄")
        XCTAssertEqual(SettingsText.attackPrioritySymbol(.minionsFirst), "pawprint.fill")
        // 既定の割り当て: 上 = タワー、下 = ミニオン・モンスター
        let s = GameSettings()
        XCTAssertEqual(HUDAttackIcon.main(slot: .top, priority: s.attackPriority(for: .top)), .tower)
        XCTAssertEqual(HUDAttackIcon.main(slot: .bottom, priority: s.attackPriority(for: .bottom)), .symbol("pawprint.fill"))
    }

    /// タワーの形は枠の内側に描かれ、ある程度の大きさがある。
    func testTowerShapeStaysInsideItsRect() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 100)
        let box = HUDTowerShape().path(in: rect).boundingRect
        XCTAssertGreaterThanOrEqual(box.minX, rect.minX)
        XCTAssertGreaterThanOrEqual(box.minY, rect.minY)
        XCTAssertLessThanOrEqual(box.maxX, rect.maxX)
        XCTAssertLessThanOrEqual(box.maxY, rect.maxY)
        XCTAssertGreaterThan(box.width, 60)
        XCTAssertGreaterThan(box.height, 80)
    }

    // MARK: 必殺・枠番号のバッジ

    /// バッジ（必殺 / ULT / 枠番号）はボタンの円の内側に収まる（円の外へはみ出さない）。
    /// カプセルは両端が半円: 端の円の中心 (±(幅/2 − 高さ/2), 縦位置) から高さ/2 まで。
    func testSkillBadgeStaysInsideTheButtonDisc() {
        for (tag, l) in layouts() {
            for slot in SkillSlot.actives {
                let d = slot == .ultimate ? l.ultDiameter : l.skillDiameter
                // 文字は全角 2 文字（必殺）か英大文字 3 文字（ULT）。余裕を見て 2.4em
                let font = d * HUDSkillButton.badgeFontRatio
                let width = font * 2.4 + d * 0.09 * 2
                let height = font * 1.2 + 5
                let capCenterX = width / 2 - height / 2
                let capCenterY = d * HUDSkillButton.badgeOffsetRatio
                let farthest = hypot(capCenterX, capCenterY) + height / 2
                XCTAssertLessThanOrEqual(farthest, d / 2, "\(tag) \(slot): バッジがボタンの円からはみ出す")
            }
        }
    }
}
