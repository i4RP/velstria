import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud。上部の HUD: ミニマップドック・ミニマップ横の縦列・味方列・スコア・情報側の列・キルフィードが
// iPhone 13 mini 〜 17 Pro Max の横画面（右手 / 左利き配置・観戦）で重ならず Safe Area 内に収まること、
// 攻撃ボタン 3 つ・スキル群・習得ボタン・照準のキャンセル領域・チュートリアルカードとも重ならないこと、
// 味方アイコンの読み上げ、電池・時刻の表示、K/D/A のアイコン、消音ボタンの表示（設定の音量 0 は消音の表示）。

@MainActor
final class HUDTopBarTests: XCTestCase {
    /// 横画面の論理サイズと Safe Area（左右 = Dynamic Island / ノッチ側、下 = ホームインジケータ）。
    private let devices: [(name: String, size: CGSize, side: CGFloat, bottom: CGFloat)] = [
        ("iPhone 13 mini", CGSize(width: 812, height: 375), 44, 21),
        ("iPhone 16e", CGSize(width: 844, height: 390), 47, 21),
        ("iPhone 17 Pro", CGSize(width: 874, height: 402), 62, 20),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440), 62, 20),
    ]

    private func layout(_ d: (name: String, size: CGSize, side: CGFloat, bottom: CGFloat), leftHanded: Bool) -> HUDLayout {
        HUDLayout(size: d.size, safe: EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side),
                  leftHanded: leftHanded)
    }

    /// キルフィードの占める範囲の目安（情報側、killFeedTop から最大 4 行・各行 ~26pt・幅 ~110pt）。
    /// 操作中は情報側の端にシグナル列の分（killFeedSideReserve）を空ける。
    private func killFeedFrame(_ l: HUDLayout, reserveSignals: Bool) -> CGRect {
        let reserve = reserveSignals ? l.killFeedSideReserve : 0
        let h = CGFloat(HUDModel.killFeedMax) * 26 + CGFloat(HUDModel.killFeedMax - 1) * 3
        let x = l.leftHanded ? l.leadingEdge + reserve : l.trailingEdge - reserve - 110
        return CGRect(x: x, y: l.killFeedTop, width: 110, height: h)
    }

    private func topFrames(_ l: HUDLayout, spectating: Bool) -> [(String, CGRect)] {
        var out: [(String, CGRect)] = [
            ("ミニマップドック", l.minimapDockFrame),
            ("スコア", l.scoreFrame),
            ("情報側", l.topInfoFrame(spectating: spectating)),
            ("キルフィード", killFeedFrame(l, reserveSignals: !spectating)),
        ]
        if !spectating {
            for (k, f) in l.utilityFrames.enumerated() { out.append((k == 0 ? "端末状態" : "縦列のボタン\(k)", f)) }
            out.append(("味方列", l.allyStripFrame))
        }
        return out
    }

    /// 戦闘の操作部品（右手配置は右、左利きは左）。習得ボタンはタップ領域（44pt）で見る。
    private func controls(_ l: HUDLayout) -> [(String, CGPoint, CGFloat)] {
        var out: [(String, CGPoint, CGFloat)] = AttackButtonSlot.allCases.map {
            ("攻撃\($0.rawValue)", l.attackCenter(for: $0), l.attackDiameter(for: $0) / 2)
        }
        for slot in SkillSlot.actives {
            out.append(("スキル\(slot.rawValue)", l.skillCenter(slot), (slot == .ultimate ? l.ultDiameter : l.skillDiameter) / 2))
            out.append(("習得\(slot.rawValue)", l.levelBadgeCenter(slot), max(l.levelBadgeDiameter, HUDLevelBadge.touchDiameter) / 2))
        }
        out.append(("スペル1", l.spellCenter(0), l.spellDiameter / 2))
        out.append(("スペル2", l.spellCenter(1), l.spellDiameter / 2))
        out.append(("帰還", l.recallCenter, l.recallDiameter / 2))
        return out
    }

    private func intersects(_ r: CGRect, center c: CGPoint, radius: CGFloat) -> Bool {
        let x = min(max(c.x, r.minX), r.maxX), y = min(max(c.y, r.minY), r.maxY)
        return hypot(c.x - x, c.y - y) < radius
    }

    func testTopFramesStayInsideSafeAreaWithoutOverlap() {
        for d in devices {
            for left in [false, true] {
                for spectating in [false, true] {
                    let l = layout(d, leftHanded: left)
                    let tag = "\(d.name) \(left ? "左利き" : "右手")\(spectating ? " 観戦" : "")"
                    let frames = topFrames(l, spectating: spectating)
                    for (name, f) in frames {
                        XCTAssertGreaterThanOrEqual(f.minX, d.side - 0.5, "\(tag) \(name) が左の Safe Area にかかる")
                        XCTAssertLessThanOrEqual(f.maxX, d.size.width - d.side + 0.5, "\(tag) \(name) が右の Safe Area にかかる")
                        XCTAssertGreaterThanOrEqual(f.minY, l.topEdge - 0.5, "\(tag) \(name) が上端を越える")
                        XCTAssertLessThan(f.maxY, l.joystickRest.y - l.joystickRadius, "\(tag) \(name) がスティックにかかる")
                        if name != "ミニマップドック" {
                            XCTAssertFalse(f.intersects(l.joystickZone), "\(tag) \(name) がスティックの受付領域にかかる")
                        }
                    }
                    for i in frames.indices {
                        for j in frames.indices where j > i {
                            let (an, a) = frames[i], (bn, b) = frames[j]
                            XCTAssertFalse(a.intersects(b), "\(tag) \(an) \(a) と \(bn) \(b) が重なる")
                        }
                    }
                    // 攻撃ボタン 3 つ・スキル群・習得ボタン・スペル・帰還とも重ならない（ミニマップ・キルフィードは担当外）
                    if !spectating {
                        for (name, f) in frames where name != "ミニマップドック" && name != "キルフィード" {
                            for (cn, c, r) in controls(l) {
                                XCTAssertFalse(intersects(f, center: c, radius: r), "\(tag) \(name) と \(cn) が重なる")
                            }
                        }
                    }
                }
            }
        }
    }

    func testUtilityColumnHugsTheInnerSideOfTheMinimapWith44ptTargets() {
        for d in devices {
            for left in [false, true] {
                let l = layout(d, leftHanded: left)
                let tag = "\(d.name) \(left ? "左利き" : "右手")"
                let column = l.utilityColumnFrame
                let map = l.minimapFrame
                // ミニマップの内側（画面中央側）にすぐ接し、ミニマップ（ドラッグ領域）とは重ならない
                if left {
                    XCTAssertGreaterThan(map.midX, d.size.width / 2, "\(tag) 左利きではミニマップが右上")
                    XCTAssertLessThanOrEqual(column.maxX, map.minX, tag)
                    XCTAssertLessThanOrEqual(map.minX - column.maxX, 4, "\(tag) ミニマップのすぐ左")
                } else {
                    XCTAssertGreaterThanOrEqual(column.minX, map.maxX, tag)
                    XCTAssertLessThanOrEqual(column.minX - map.maxX, 4, "\(tag) ミニマップのすぐ右")
                }
                XCTAssertFalse(column.intersects(l.minimapDockFrame), tag)
                XCTAssertGreaterThanOrEqual(l.utilityButtonSize, 30, tag)
                XCTAssertLessThanOrEqual(l.utilityButtonSize, 34, tag)
                for k in 0..<HUDLayout.utilityButtonCount {
                    let f = l.utilityButtonFrame(k)
                    XCTAssertGreaterThanOrEqual(f.width, 44, "\(tag) ボタン \(k)")
                    XCTAssertGreaterThanOrEqual(f.height, 44, "\(tag) ボタン \(k)")
                    XCTAssertFalse(f.intersects(l.utilityStatusFrame), "\(tag) ボタン \(k) と端末状態")
                    if k > 0 { XCTAssertFalse(f.intersects(l.utilityButtonFrame(k - 1)), "\(tag) ボタン \(k - 1)/\(k)") }
                }
                // 縦列はミニマップドック（地図 + 全体マップボタン）の高さに収まる（降参パネル・スティックの受付より上）
                XCTAssertLessThanOrEqual(column.maxY, l.minimapDockFrame.maxY, tag)
                // 照準のキャンセル領域と重ならない
                let c = l.cancelCenter, r = l.cancelRadius
                let cancel = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                for (name, f) in [("縦列", column), ("味方列", l.allyStripFrame), ("スコア", l.scoreFrame)] {
                    XCTAssertFalse(cancel.intersects(f), "\(tag) キャンセル領域と\(name)")
                }
                // チュートリアルカード（上部中央、幅 330、中心 topEdge + 96）は縦列にかからず、味方列・スコアの下にある
                let cardScale = min(l.scale, 1.1)
                let cardHalf = 330 * cardScale / 2
                let cardX = (d.size.width / 2 - cardHalf)...(d.size.width / 2 + cardHalf)
                XCTAssertFalse(cardX.overlaps(column.minX...column.maxX), "\(tag) チュートリアルカードと縦列")
                let cardTop = l.topEdge + 96 * cardScale - 44
                XCTAssertLessThan(l.allyStripFrame.maxY, cardTop, tag)
                XCTAssertLessThan(l.scoreFrame.maxY, cardTop, tag)
                XCTAssertGreaterThanOrEqual(l.topInfoFrame(spectating: false).height, 44)
            }
        }
    }

    func testScoreIsCenteredAndAllyStripSitsBetweenScoreAndColumn() {
        for d in devices {
            for left in [false, true] {
                let l = layout(d, leftHanded: left)
                let tag = "\(d.name) \(left ? "左利き" : "右手")"
                let strip = l.allyStripFrame, score = l.scoreFrame, column = l.utilityColumnFrame
                XCTAssertEqual(score.midX, d.size.width / 2, accuracy: 0.01, tag)
                XCTAssertLessThan(score.width, 120, "\(tag) 小型のスコア")
                XCTAssertLessThan(score.height, 36, "\(tag) 小型のスコア")
                // 味方列はスコアのミニマップ側（右手配置は左、左利きは右）で、縦列との間に収まる
                if left {
                    XCTAssertGreaterThanOrEqual(strip.minX, score.maxX, tag)
                    XCTAssertLessThanOrEqual(strip.maxX, column.minX, tag)
                    XCTAssertEqual(l.allyStripAlignment, .topLeading, "\(tag) 人数が少ない時はスコア側へ寄せる")
                } else {
                    XCTAssertLessThanOrEqual(strip.maxX, score.minX, tag)
                    XCTAssertGreaterThanOrEqual(strip.minX, column.maxX, tag)
                    XCTAssertEqual(l.allyStripAlignment, .topTrailing, "\(tag) 人数が少ない時はスコア側へ寄せる")
                }
                XCTAssertEqual(strip.midY, score.midY, accuracy: 1, "\(tag) 顔とスコアの高さ")
                XCTAssertEqual(strip.minY, l.topEdge, accuracy: 0.01, "\(tag) 顔は上端に沿う")
                XCTAssertGreaterThanOrEqual(l.allyFaceSize, 24, tag)
                XCTAssertLessThanOrEqual(l.allyFaceSize, 28, tag)
                XCTAssertGreaterThanOrEqual(strip.width, l.allyFaceSize * CGFloat(HUDLayout.allyStripMax) - 0.01, "\(tag) 4 人分")
                // 情報側の列は topInfoAlignment の側の Safe Area の端に寄せる
                for spectating in [false, true] {
                    let info = l.topInfoFrame(spectating: spectating)
                    if left {
                        XCTAssertEqual(l.topInfoAlignment, .topLeading)
                        XCTAssertEqual(info.minX, l.leadingEdge, accuracy: 0.01, tag)
                    } else {
                        XCTAssertEqual(l.topInfoAlignment, .topTrailing)
                        XCTAssertEqual(info.maxX, l.trailingEdge, accuracy: 0.01, tag)
                    }
                    XCTAssertLessThanOrEqual(info.maxY, l.killFeedTop, "\(tag) キルフィードより上")
                }
            }
        }
    }

    func testLeftHandedMirrorsTopLayout() {
        for d in devices {
            let r = layout(d, leftHanded: false), l = layout(d, leftHanded: true)
            let w = d.size.width
            XCTAssertEqual(r.allyFaceSize, l.allyFaceSize, d.name)
            XCTAssertEqual(r.allyStripFrame.midX, w - l.allyStripFrame.midX, accuracy: 0.01, d.name)
            XCTAssertEqual(r.utilityColumnX, w - l.utilityColumnX, accuracy: 0.01, d.name)
            XCTAssertEqual(r.topInfoFrame(spectating: false).midX, w - l.topInfoFrame(spectating: false).midX, accuracy: 0.01, d.name)
            XCTAssertEqual(r.scoreFrame, l.scoreFrame, d.name)
        }
    }

    // MARK: 味方アイコン

    private func ally(dead: Bool, hp: Double = 0.75, respawn: Int = 26, ult: Bool = false) -> HUDAllyStatus {
        HUDAllyStatus(id: 3, heroID: "H002", level: 5, hpRatio: hp, isDead: dead, respawn: respawn, ultReady: ult)
    }

    func testAllyAccessibilityText() {
        let saved = Loc.current
        defer { Loc.current = saved }
        Loc.current = .ja
        XCTAssertEqual(HUDAllyIcon.accessibilityStatus(ally(dead: true, respawn: 26)), "復活まで 26 秒")
        XCTAssertEqual(HUDAllyIcon.accessibilityStatus(ally(dead: false, hp: 0.75)), "HP 75%")
        XCTAssertEqual(HUDAllyIcon.accessibilityStatus(ally(dead: false, hp: 0.4, ult: true)), "HP 40%、必殺技 使用可能")
        Loc.current = .en
        XCTAssertEqual(HUDAllyIcon.accessibilityStatus(ally(dead: true, respawn: 10, ult: true)), "Respawns in 10 s",
                       "倒れている間は復活までの秒数だけ")
        let name = HUDAllyIcon.accessibilityName(ally(dead: false))
        XCTAssertFalse(name.isEmpty)
        XCTAssertNotEqual(name, "H002", "マスターのヒーロー名を読む")
        XCTAssertEqual(HUDAllyIcon.lowHPRatio, 0.3)
    }

    // MARK: 端末状態

    func testBatteryReading() {
        XCTAssertNil(HUDBatteryReading.make(level: -1, state: .unknown), "シミュレータ（-1）は電池を出さない")
        XCTAssertNil(HUDBatteryReading.make(level: 0.5, state: .unknown))
        let low = HUDBatteryReading.make(level: 0.15, state: .unplugged)
        XCTAssertEqual(low?.isLow, true)
        XCTAssertEqual(low?.charging, false)
        XCTAssertEqual(low?.percent, 15)
        let charging = HUDBatteryReading.make(level: 0.8, state: .charging)
        XCTAssertEqual(charging?.isLow, false)
        XCTAssertEqual(charging?.charging, true)
        XCTAssertEqual(HUDBatteryReading.make(level: 1, state: .full)?.charging, true)
        XCTAssertEqual(HUDBatteryReading.make(level: 0.2, state: .unplugged)?.isLow, false, "20% ちょうどは赤くしない")
    }

    func testClockTextIs24HourHHmm() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 9, minute: 5))!
        let night = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 27))!
        XCTAssertEqual(HUDDeviceStatusView.clockText(morning, calendar: cal), "09:05")
        XCTAssertEqual(HUDDeviceStatusView.clockText(night, calendar: cal), "23:27")

        let saved = Loc.current
        defer { Loc.current = saved }
        Loc.current = .ja
        XCTAssertEqual(HUDDeviceStatusView.accessibilityText(battery: nil, clock: "09:05"), "時刻 09:05")
        XCTAssertEqual(HUDDeviceStatusView.accessibilityText(battery: HUDBatteryReading(level: 0.42, charging: true), clock: "09:05"),
                       "電池 42%、充電中、時刻 09:05")
    }

    // MARK: アイコン

    func testSymbolsExist() {
        let names = [HUDPlayerStats.assistSymbol, HUDPlayerStats.creepSymbol, HUDScoreCapsule.towerSymbol,
                     "gearshape.fill", "list.bullet.rectangle.fill",
                     HUDUtilityColumnStyle.soundSymbol(muted: false), HUDUtilityColumnStyle.soundSymbol(muted: true),
                     HUDUtilityColumnStyle.zoomSymbol(boosted: false), HUDUtilityColumnStyle.zoomSymbol(boosted: true)]
        for n in names {
            XCTAssertNotNil(UIImage(systemName: n), "SF Symbol \(n) が無い")
        }
        XCTAssertNotEqual(HUDUtilityColumnStyle.soundSymbol(muted: false), HUDUtilityColumnStyle.soundSymbol(muted: true))
        XCTAssertNotEqual(HUDUtilityColumnStyle.zoomSymbol(boosted: false), HUDUtilityColumnStyle.zoomSymbol(boosted: true))
    }

    /// 消音ボタンは出音に合わせる: 設定の BGM・効果音がどちらも 0（既定値）の間は一時消音していなくても消音の表示で、
    /// 押しても一時消音は切り替えず、設定で音量を上げるよう案内する。
    func testSoundButtonFollowsActualOutput() {
        let saved = Loc.current
        Loc.current = .ja
        defer { Loc.current = saved }
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        app.profile.settings.bgmVolume = 0
        app.profile.settings.sfxVolume = 0
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001",
                                                                                          humanName: "T", seed: 9)))
        let m = HUDModel(controller: c)
        m.start(app: app) { _ in }
        defer { m.stop() }

        XCTAssertTrue(HUDModel.volumesSilent(m.settings))
        XCTAssertFalse(m.soundMuted)
        XCTAssertTrue(m.soundSilenced, "既定の設定では実際に無音なので消音の表示")
        m.toggleSound()
        XCTAssertFalse(m.soundMuted, "音量 0 の間は一時消音を切り替えない")
        XCTAssertFalse(app.audio.isTemporarilyMuted)
        XCTAssertEqual(m.toast?.text, "設定で音量を上げてください")
        XCTAssertTrue(m.soundSilenced)

        // 効果音だけでも上げれば通常の一時消音ボタン
        app.profile.settings.sfxVolume = 0.6
        m.syncSettings()
        XCTAssertFalse(m.soundSilenced)
        m.toggleSound()
        XCTAssertTrue(m.soundMuted)
        XCTAssertTrue(m.soundSilenced)
        XCTAssertTrue(app.audio.isTemporarilyMuted)
        m.toggleSound()
        XCTAssertFalse(m.soundMuted)
        XCTAssertFalse(app.audio.isTemporarilyMuted)

        // 一時消音中に設定を 0 へ戻してから押すと、一時消音を解いて案内する
        m.toggleSound()
        app.profile.settings.sfxVolume = 0
        m.syncSettings()
        m.toggleSound()
        XCTAssertFalse(m.soundMuted)
        XCTAssertFalse(app.audio.isTemporarilyMuted)
        XCTAssertTrue(m.soundSilenced)
    }

    func testPlayerStatsRedrawOnlyWhenTheirNumbersChange() {
        var a = HUDTopSnapshot()
        a.kills = 2; a.deaths = 1; a.assists = 3; a.creepScore = 40; a.seconds = 100
        var b = a
        b.seconds = 101
        b.blueKills = 5
        XCTAssertEqual(HUDPlayerStats(top: a, scale: 1), HUDPlayerStats(top: b, scale: 1), "試合時間・チームのキルでは描き直さない")
        for change in [\HUDTopSnapshot.kills, \.deaths, \.assists, \.creepScore] {
            var c = a
            c[keyPath: change] += 1
            XCTAssertNotEqual(HUDPlayerStats(top: a, scale: 1), HUDPlayerStats(top: c, scale: 1))
        }
        XCTAssertNotEqual(HUDScoreCapsule(top: a, colorblind: false, scale: 1), HUDScoreCapsule(top: b, colorblind: false, scale: 1))
    }

    func testSkullShapeHasEyeHoles() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let p = HUDSkull().path(in: rect)
        XCTAssertFalse(p.isEmpty)
        XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(p.boundingRect), "枠の中に収まる")
        XCTAssertTrue(p.contains(CGPoint(x: 50, y: 15)), "額は塗る")
        XCTAssertTrue(p.contains(CGPoint(x: 50, y: 90)), "顎は塗る")
        XCTAssertFalse(p.contains(CGPoint(x: 31, y: 44)), "左目は抜く")
        XCTAssertFalse(p.contains(CGPoint(x: 69, y: 44)), "右目は抜く")
        XCTAssertFalse(p.contains(CGPoint(x: 10, y: 92)), "顎の外側は塗らない")
    }
}
