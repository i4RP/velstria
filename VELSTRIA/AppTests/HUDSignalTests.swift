import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud（signals）。クイックシグナル: クールダウン・メッセージの件数上限と期限切れ・味方の返信の決定性、
// HUDModel 経由の送信（ピンの位置・返信の配達・シミュレーションを進めない・チュートリアルでは送らない）、
// シグナル列・キルフィード・チャットのメニュー・メッセージ欄の配置（4 端末 × 左右配置で、情報側の端・重なり無し・
// Safe Area 内・タップ領域 44pt 以上。メッセージ欄はスティックの待機位置の円より上）、ミニマップの顔アイコンの縮小、
// 送り主の短い名前（日英とも欄で切れない）。

final class HUDSignalTests: XCTestCase {
    private let allies = [
        HUDSignalAlly(id: 11, name: "A", pos: Vec2(1000, 1000), alive: true),
        HUDSignalAlly(id: 12, name: "B", pos: Vec2(5000, 5000), alive: true),
        HUDSignalAlly(id: 13, name: "C", pos: Vec2(5100, 5100), alive: false),
    ]

    // MARK: クールダウン

    func testCooldownBlocksRapidSends() {
        var b = HUDSignalBoard()
        XCTAssertTrue(b.send(.signal(.attack), sender: "You", at: Vec2(10, 10), allies: [], now: 100))
        XCTAssertFalse(b.send(.signal(.retreat), sender: "You", at: Vec2(10, 10), allies: [], now: 101.2), "2 秒以内は送れない")
        XCTAssertFalse(b.send(.chat(.thanks), sender: "You", at: nil, allies: [], now: 101.99), "定型文も同じクールダウン")
        XCTAssertEqual(b.messages.count, 1)
        XCTAssertEqual(b.pings.count, 1)
        XCTAssertTrue(b.send(.signal(.gather), sender: "You", at: Vec2(10, 10), allies: [], now: 102))
        XCTAssertEqual(b.messages.map(\.icon), [.signal(.attack), .signal(.gather)])
        XCTAssertEqual(b.sequence, 2, "断った送信は数えない")
    }

    // MARK: 件数上限と期限切れ

    func testMessagesAreCappedAndExpire() {
        // 2 秒ごとのシグナル 3 回 + 味方の返信 3 件 = 6 件 → 新しい 4 件だけ残る
        var b = HUDSignalBoard()
        for k in 0..<3 {
            let t = Double(k) * HUDSignalBoard.cooldown
            XCTAssertTrue(b.send(.signal(.attack), sender: "You", at: Vec2(1000, 1000), allies: allies, now: t))
            XCTAssertEqual(b.update(now: t + 1.5), 1)
        }
        XCTAssertEqual(b.messages.count, HUDSignalBoard.maxMessages)
        XCTAssertEqual(b.messages.map(\.isHuman), [true, false, true, false])
        XCTAssertEqual(b.messages.map(\.createdAt), [2, 3.5, 4, 5.5], "古いものから消える")
        // それぞれ 6 秒で消える
        b.update(now: 2 + HUDSignalBoard.messageLifetime - 0.01)
        XCTAssertEqual(b.messages.count, 4)
        b.update(now: 2 + HUDSignalBoard.messageLifetime)
        XCTAssertEqual(b.messages.count, 3)
        b.update(now: 5.5 + HUDSignalBoard.messageLifetime)
        XCTAssertTrue(b.messages.isEmpty)
        XCTAssertTrue(b.isIdle)

        // 定型文: 返信・ピン無し
        var chat = HUDSignalBoard()
        chat.send(.chat(.missing), sender: "You", at: Vec2(1000, 1000), allies: allies, now: 0)
        XCTAssertEqual(chat.messages.map(\.icon), [.chat(.missing)])
        XCTAssertTrue(chat.replies.isEmpty, "定型文には返信しない")
        XCTAssertTrue(chat.pings.isEmpty, "定型文はピン無し")
    }

    func testPingsExpireAndAreCapped() {
        var b = HUDSignalBoard()
        for k in 0..<6 {
            b.send(.signal(.gather), sender: "You", at: Vec2(Double(k), 0), allies: [], now: Double(k) * 2)
        }
        XCTAssertEqual(b.pings.count, HUDSignalBoard.maxPings)
        XCTAssertEqual(b.pings.last?.pos, Vec2(5, 0))
        b.update(now: 10)
        XCTAssertEqual(b.pings.map(\.createdAt), [8, 10], "2.4 秒より古いピンは消える")
        b.update(now: 10 + HUDSignalBoard.pingLifetime)
        XCTAssertTrue(b.pings.isEmpty)
        // 地点が無ければピン無し（メッセージは出る）
        var none = HUDSignalBoard()
        none.send(.signal(.retreat), sender: "You", at: nil, allies: [], now: 0)
        XCTAssertTrue(none.pings.isEmpty)
        XCTAssertEqual(none.messages.count, 1)
    }

    // MARK: 味方の返信

    func testReplierIsNearestLivingAllyAndDeterministic() {
        // ピンに最も近い生存中の味方（倒れている C は近くても選ばない）
        XCTAssertEqual(HUDSignalBoard.replier(allies, near: Vec2(5200, 5200))?.id, 12)
        XCTAssertEqual(HUDSignalBoard.replier(allies, near: Vec2(900, 900))?.id, 11)
        // 同じ距離なら ID の小さい方、ピンが無ければ ID の小さい方
        let tied = [HUDSignalAlly(id: 22, name: "X", pos: Vec2(0, 100), alive: true),
                    HUDSignalAlly(id: 21, name: "Y", pos: Vec2(0, -100), alive: true)]
        XCTAssertEqual(HUDSignalBoard.replier(tied, near: .zero)?.id, 21)
        XCTAssertEqual(HUDSignalBoard.replier(tied.reversed(), near: .zero)?.id, 21, "並び順に依らない")
        XCTAssertEqual(HUDSignalBoard.replier(allies, near: nil)?.id, 11)
        XCTAssertNil(HUDSignalBoard.replier([allies[2]], near: .zero), "生存中の味方がいなければ返信なし")
        XCTAssertNil(HUDSignalBoard.replier([], near: .zero))

        // 同じ入力なら同じ返信（文言・間合いも同じ）
        func run() -> HUDSignalBoard {
            var b = HUDSignalBoard()
            b.send(.signal(.attack), sender: "You", at: Vec2(5200, 5200), allies: allies, now: 50)
            b.send(.signal(.retreat), sender: "You", at: Vec2(900, 900), allies: allies, now: 52)
            b.update(now: 53.5)
            return b
        }
        let a = run(), b = run()
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.messages.filter { !$0.isHuman }.map(\.sender), ["B", "A"])
        for seq in 1...6 {
            let d = HUDSignalBoard.replyDelay(sequence: seq)
            XCTAssertGreaterThanOrEqual(d, 0.8)
            XCTAssertLessThanOrEqual(d, 1.2, "1 秒前後")
            for kind in HUDSignalKind.allCases {
                XCTAssertEqual(HUDSignalBoard.replyText(kind, sequence: seq), HUDSignalBoard.replyText(kind, sequence: seq + 2))
                XCTAssertFalse(HUDSignalBoard.replyText(kind, sequence: seq).isEmpty)
            }
        }
    }

    func testReplyArrivesAboutOneSecondLater() {
        var b = HUDSignalBoard()
        b.send(.signal(.gather), sender: "You", at: Vec2(1000, 1000), allies: allies, now: 10)
        XCTAssertEqual(b.replies.count, 1)
        let due = 10 + HUDSignalBoard.replyDelay(sequence: 1)
        XCTAssertEqual(b.update(now: due - 0.01), 0)
        XCTAssertEqual(b.messages.count, 1)
        XCTAssertEqual(b.update(now: due), 1)
        XCTAssertEqual(b.messages.count, 2)
        let reply = b.messages[1]
        XCTAssertFalse(reply.isHuman)
        XCTAssertEqual(reply.sender, "A")
        XCTAssertEqual(reply.icon, .reply(.gather))
        XCTAssertEqual(reply.createdAt, due, "届いた時刻から 6 秒表示")
        XCTAssertTrue(b.replies.isEmpty)
    }

    // MARK: HUDModel 経由

    @MainActor
    func testSendThroughModelPingsCameraCenterAndBotReplies() {
        let saved = Loc.current
        defer { Loc.current = saved }
        Loc.current = .en
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "T", seed: 3)))
        let m = HUDModel(controller: c)
        let center = m.signals
        let tick = c.state.tick
        let state = c.state
        center.send(.signal(.attack), model: m, now: 100)
        XCTAssertEqual(center.messages.map(\.sender), ["You"])
        XCTAssertEqual(center.messages.first?.text, "Attack!")
        XCTAssertTrue(center.coolingDown)
        XCTAssertEqual(m.minimap.pings.count, 1)
        XCTAssertEqual(m.minimap.pings.first?.pos, m.cameraCenter(c.state), "ピンはカメラの注視点")
        XCTAssertEqual(m.minimap.pings.first?.kind, .attack)
        XCTAssertEqual(m.minimap.pingClock, 100)

        center.send(.signal(.retreat), model: m, now: 100.5)
        XCTAssertEqual(center.messages.count, 1, "クールダウン中は送らない")

        // 約 1 秒後に味方ボットの 1 人が返信する（表示だけ。シミュレーションは進めず、状態も変えない）
        center.refresh(model: m, now: 100 + HUDSignalBoard.replyDelay(sequence: 1))
        XCTAssertEqual(center.messages.count, 2)
        let allyNames = HUDSignalCenter.allies(m).map(\.name)
        XCTAssertEqual(allyNames.count, 4, "自分以外の味方 4 人")
        XCTAssertTrue(allyNames.contains(center.messages[1].sender))
        XCTAssertEqual(c.state.tick, tick)
        XCTAssertEqual(c.state.units.map(\.pos), state.units.map(\.pos))

        center.refresh(model: m, now: 102.1)
        XCTAssertFalse(center.coolingDown)
        center.refresh(model: m, now: 100 + HUDSignalBoard.pingLifetime)
        XCTAssertTrue(m.minimap.pings.isEmpty, "期限切れのピンはミニマップからも消える")
        center.refresh(model: m, now: 120)
        XCTAssertTrue(center.messages.isEmpty)

        center.send(.chat(.missing), model: m, now: 130)
        center.stop()
        XCTAssertTrue(center.messages.isEmpty)
        XCTAssertTrue(center.board.isIdle)
    }

    /// 送り主の名前: 二つ名を外した短い名前（「Mirea, Tidecaller」→「Mirea」、「城門の誓衛アルデン」→「アルデン」）。
    /// 最も長い名前と最も長い文言の組み合わせでも、メッセージの欄で名前・文言とも「…」で切れない。
    @MainActor
    func testSenderNamesFitTheMessageArea() {
        let saved = Loc.current
        defer { Loc.current = saved }
        let heroes = MasterData.shared.heroes
        XCTAssertFalse(heroes.isEmpty)
        let alden = MasterData.shared.hero("H001")!, mirea = MasterData.shared.hero("H004")!

        // 行の中身: 記号（行の高さ − 3）+ 間隔 4 × 2 + 左右の余白 1.5 + 8 と、送り主・文言の 2 つの文字（縮小の下限 0.7 倍）
        func width(_ text: String, size: CGFloat) -> CGFloat {
            let base = UIFont.systemFont(ofSize: size, weight: .bold)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
            return ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        /// HStack の割り振り（同じ優先度: 伸び縮みの小さい方から残りを等分）で、どちらも 0.7 倍までの縮小で切れずに収まるか。
        func fits(_ sender: String, _ text: String, _ l: HUDLayout) -> Bool {
            let h = l.signalMessageRowHeight
            let avail = l.signalMessageFrame.width - ((h - 3) + 4 * 2 + 1.5 + 8)
            let a = width(sender, size: h * 0.66), b = width(text, size: h * 0.66)
            let (small, large) = a <= b ? (a, b) : (b, a)
            guard small * 0.7 <= avail / 2 else { return false }
            return large * 0.7 <= avail - min(small, avail / 2)
        }
        let replies = { HUDSignalKind.allCases.flatMap { k in [1, 2].map { HUDSignalBoard.replyText(k, sequence: $0) } } }
        let own = { HUDSignalKind.allCases.map(\.text) + HUDQuickChat.allCases.map(\.text) }

        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            XCTAssertEqual(HUDSignalCenter.senderName(alden), lang == .en ? "Alden" : "アルデン")
            XCTAssertEqual(HUDSignalCenter.senderName(mirea), lang == .en ? "Mirea" : "ミレア")
            for h in heroes {
                let name = HUDSignalCenter.senderName(h)
                XCTAssertFalse(name.isEmpty, h.heroID)
                XCTAssertFalse(name.contains(","), "\(h.heroID): \(name)")
                XCTAssertTrue(MasterText.hero(h).contains(name), "\(h.heroID): 正式名の一部")
            }
            let lines = heroes.flatMap { h in replies().map { (HUDSignalCenter.senderName(h), $0) } }
                + own().map { (L("あなた", "You"), $0) }
            for (tag, _, l) in layouts() {
                for (sender, text) in lines {
                    XCTAssertTrue(fits(sender, text, l), "\(tag) \(lang): 「\(sender) \(text)」が欄で切れる")
                }
            }
        }
        // 確認: 正式名のままだと切れる（英語の二つ名・日本語の長い名前）
        Loc.current = .en
        XCTAssertTrue(layouts().contains { !fits(MasterText.hero(mirea), "Coming!", $0.l) })
        Loc.current = .ja
        XCTAssertTrue(layouts().contains { !fits(MasterText.hero(alden), "了解、下がる！", $0.l) })
    }

    @MainActor
    func testChatMenuClosesForPanelsAndTutorialSendsNothing() {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "T", seed: 9)))
        let m = HUDModel(controller: c)
        m.start(app: app) { _ in }
        defer { m.stop() }
        let center = m.signals
        center.toggleChatMenu(model: m)
        XCTAssertTrue(center.chatMenuOpen)
        center.send(.chat(.thanks), model: m, now: 10)
        XCTAssertFalse(center.chatMenuOpen, "送信でメニューを閉じる")
        center.toggleChatMenu(model: m)
        m.openPanel(.scoreboard)
        center.refresh(model: m, now: 11)
        XCTAssertFalse(center.chatMenuOpen, "パネルを開いたら閉じる")
        m.closePanel()
        center.toggleExpanded(model: m)
        XCTAssertFalse(center.isExpanded)
        center.toggleExpanded(model: m)
        XCTAssertTrue(center.isExpanded)

        // 全体マップを開いている間は送れない
        m.setTacticalMap(open: true)
        center.send(.signal(.gather), model: m, now: 20)
        XCTAssertEqual(center.messages.count, 1)
        m.setTacticalMap(open: false)

        // チュートリアルではシグナルを出さない
        let tc = BattleController(launch: BattleLaunch(config: MatchFactory.practiceMatch(
            humanHeroID: "H001", humanName: "T", options: PracticeOptions(), tutorial: true, seed: 5)))
        let tm = HUDModel(controller: tc)
        XCTAssertTrue(tm.isTutorial)
        tm.signals.send(.signal(.attack), model: tm, now: 5)
        tm.signals.toggleChatMenu(model: tm)
        XCTAssertTrue(tm.signals.messages.isEmpty)
        XCTAssertTrue(tm.minimap.pings.isEmpty)
        XCTAssertFalse(tm.signals.chatMenuOpen)
    }

    // MARK: ミニマップの顔アイコン

    @MainActor
    func testMinimapFaceThumbnailsAreSmallAndCached() throws {
        let src = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 640)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 640))
        }
        let thumb = HUDMinimapFaces.thumbnail(src)
        XCTAssertEqual(thumb.size, CGSize(width: HUDMinimapFaces.pixelSize, height: HUDMinimapFaces.pixelSize))
        XCTAssertEqual(thumb.scale, 1)
        // 縦長・横長の元画像でも正方形
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 500)).image { _ in }
        XCTAssertEqual(HUDMinimapFaces.thumbnail(tall).size.width, HUDMinimapFaces.thumbnail(tall).size.height)

        XCTAssertNotNil(PortraitArt.hero("H001"), "描き下ろしのポートレートがある")
        XCTAssertNotNil(HUDMinimapFaces.face("H001"))
        XCTAssertNil(HUDMinimapFaces.face("NO_SUCH_HERO"), "アートの無いヒーローは色面 + 頭文字")
        let dots = [HUDMinimapBuffer.Dot(pos: .zero, team: .blue, kind: .hero, hue: 0, isHuman: true, isFocus: false,
                                         alpha: 1, heroID: "H001"),
                    HUDMinimapBuffer.Dot(pos: .zero, team: .red, kind: .hero, hue: 0, isHuman: false, isFocus: false,
                                         alpha: 0.4, heroID: "H001"),
                    HUDMinimapBuffer.Dot(pos: .zero, team: .red, kind: .hero, hue: 0, isHuman: false, isFocus: false,
                                         alpha: 1, heroID: nil)]
        XCTAssertEqual(Array(HUDMinimapFaces.faces(for: dots).keys), ["H001"])
        // 顔の大きさ: ミニマップ（138〜172pt）で直径 13pt 以上、全体マップではそれより大きい
        for size in [CGFloat(138), 152.8, 172] {
            let r = HUDMinimapFaces.radius(mapSize: size, expanded: false)
            XCTAssertGreaterThanOrEqual(r * 2, 13)
            XCTAssertLessThan(r * 2, size * 0.12)
        }
        XCTAssertGreaterThan(HUDMinimapFaces.radius(mapSize: 288, expanded: true), HUDMinimapFaces.radius(mapSize: 172, expanded: false))
    }

    // MARK: 配置

    private let devices: [(name: String, size: CGSize, side: CGFloat, bottom: CGFloat)] = [
        ("iPhone 13 mini", CGSize(width: 812, height: 375), 44, 21),
        ("iPhone 16e", CGSize(width: 844, height: 390), 47, 21),
        ("iPhone 17 Pro", CGSize(width: 874, height: 402), 62, 20),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440), 62, 20),
    ]

    private struct Disc {
        var name: String
        var center: CGPoint
        var radius: CGFloat
    }

    /// 操作部品（攻撃ボタン 3 つ・スキル・必殺技・スペル・帰還）とスティックの土台。
    private func controls(_ l: HUDLayout) -> [Disc] {
        var out = AttackButtonSlot.allCases.map {
            Disc(name: "attack_\($0.rawValue)", center: l.attackCenter(for: $0), radius: l.attackDiameter(for: $0) / 2)
        }
        for slot in SkillSlot.actives {
            out.append(Disc(name: "skill\(slot.rawValue)", center: l.skillCenter(slot),
                            radius: (slot == .ultimate ? l.ultDiameter : l.skillDiameter) / 2))
        }
        out.append(Disc(name: "spell0", center: l.spellCenter(0), radius: l.spellDiameter / 2))
        out.append(Disc(name: "spell1", center: l.spellCenter(1), radius: l.spellDiameter / 2))
        out.append(Disc(name: "recall", center: l.recallCenter, radius: l.recallDiameter / 2))
        // 移動スティックの待機位置の円（浮動スティックでも触っていない時はここに描く）
        out.append(Disc(name: "joystick", center: l.joystickRest, radius: l.joystickRadius))
        return out
    }

    /// 習得バッジのタップ領域（スキルポイントがある時だけ出る 44pt の正方形）。
    @MainActor
    private func badges(_ l: HUDLayout) -> [(name: String, rect: CGRect)] {
        let half = HUDLevelBadge.touchDiameter / 2
        return SkillSlot.actives.map { slot in
            let c = l.levelBadgeCenter(slot)
            return ("level\(slot.rawValue)", CGRect(x: c.x - half, y: c.y - half, width: half * 2, height: half * 2))
        }
    }

    private func hits(_ r: CGRect, _ d: Disc, margin: CGFloat = 2) -> Bool {
        let dx = max(r.minX - d.center.x, 0, d.center.x - r.maxX)
        let dy = max(r.minY - d.center.y, 0, d.center.y - r.maxY)
        return dx * dx + dy * dy < (d.radius + margin) * (d.radius + margin)
    }

    /// キルフィード（最大 4 行・1 行 26pt + 行間 3、幅は 2 桁アシストの行で約 96pt）の占める範囲。
    /// BattleHUDView と同じく情報側の端から killFeedSideReserve だけ内側に寄せる。
    private func killFeedFrame(_ l: HUDLayout) -> CGRect {
        let size = HUDLayout.killFeedEstimate
        let x = l.leftHanded ? l.leadingEdge + l.killFeedSideReserve : l.trailingEdge - l.killFeedSideReserve - size.width
        return CGRect(x: x, y: l.killFeedTop, width: size.width, height: size.height)
    }

    /// 情報側の上の列（K/D/A・スコアボード・ポーズ。高さ 44）の帯。
    private func topInfoBand(_ l: HUDLayout) -> CGRect {
        CGRect(x: l.leadingEdge, y: l.topEdge, width: l.trailingEdge - l.leadingEdge, height: l.topButtonSize)
    }

    /// ヒーローパネルと上の状態アイコン列・おすすめ購入ボタン。
    private func heroPanelFrame(_ l: HUDLayout) -> CGRect {
        let h = HUDRootMetrics.heroPanelHeight(l) + 46
        return CGRect(x: l.heroPanelCenterX - l.heroPanelWidth / 2, y: l.bottomEdge - h, width: l.heroPanelWidth, height: h)
    }

    private func layouts() -> [(tag: String, side: CGFloat, l: HUDLayout)] {
        devices.flatMap { d in
            [false, true].map { left in
                ("\(d.name) \(left ? "左利き" : "右手")", d.side,
                 HUDLayout(size: d.size, safe: EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side),
                           leftHanded: left))
            }
        }
    }

    @MainActor
    func testSignalTraySitsOnTheInfoSideWithoutOverlap() {
        XCTAssertEqual(HUDLevelBadge.touchDiameter, 44, "signalLevelBadgeRects と同じ大きさ")
        for (tag, side, l) in layouts() {
            let slots = HUDSignalSlot.allCases.map { (slot: $0, frame: l.signalSlotFrame($0)) }
            let tray = l.signalTrayFrame
            // 情報側の端（右手配置 = 右、左利き = 左。ミニマップの反対側）
            if l.leftHanded {
                XCTAssertEqual(l.signalSlotFrame(.toggle).minX, l.leadingEdge, accuracy: 0.5, "\(tag) 折りたたみボタンは左端")
                XCTAssertLessThan(tray.midX, l.width / 2)
            } else {
                XCTAssertEqual(l.signalSlotFrame(.toggle).maxX, l.trailingEdge, accuracy: 0.5, "\(tag) 折りたたみボタンは右端")
                XCTAssertGreaterThan(tray.midX, l.width / 2)
            }
            XCTAssertEqual(tray.midX > l.width / 2, l.topInfoAlignment == .topTrailing, "\(tag) 情報列と同じ側")
            XCTAssertFalse(tray.intersects(l.minimapDockFrame), "\(tag) シグナル列とミニマップ")
            XCTAssertFalse(tray.intersects(topInfoBand(l)), "\(tag) シグナル列と情報列")
            XCTAssertFalse(tray.intersects(killFeedFrame(l)), "\(tag) シグナル列とキルフィード")
            for s in slots {
                XCTAssertGreaterThanOrEqual(s.frame.width, 44, "\(tag) \(s.slot) のタップ領域")
                XCTAssertGreaterThanOrEqual(s.frame.height, 44, "\(tag) \(s.slot) のタップ領域")
                XCTAssertGreaterThanOrEqual(s.frame.minX, side - 0.5, "\(tag) \(s.slot) が左の Safe Area にかかる")
                XCTAssertLessThanOrEqual(s.frame.maxX, l.width - side + 0.5, "\(tag) \(s.slot) が右の Safe Area にかかる")
                XCTAssertLessThanOrEqual(s.frame.maxY, l.bottomEdge)
                for c in controls(l) {
                    XCTAssertFalse(hits(s.frame, c), "\(tag) \(s.slot) と \(c.name) が重なる")
                }
                for b in badges(l) {
                    XCTAssertFalse(s.frame.insetBy(dx: -2, dy: -2).intersects(b.rect), "\(tag) \(s.slot) と \(b.name) のタップ領域")
                }
            }
            for i in slots.indices {
                for j in slots.indices where j > i {
                    XCTAssertFalse(slots[i].frame.intersects(slots[j].frame), "\(tag) \(slots[i].slot) と \(slots[j].slot)")
                }
            }
            XCTAssertGreaterThanOrEqual(l.signalButtonSize, 30)
            XCTAssertLessThanOrEqual(l.signalButtonSize, l.signalHitSize)
            // 主な端末（16e 以上）は 1 行
            if l.width >= 844 { XCTAssertEqual(l.signalTrayColumns, HUDSignalSlot.allCases.count, tag) }

            // チャットのメニュー: Safe Area 内、列の下、端にそろえる
            let menu = l.signalChatMenuFrame
            XCTAssertGreaterThanOrEqual(menu.minX, side, tag)
            XCTAssertLessThanOrEqual(menu.maxX, l.width - side, tag)
            XCTAssertGreaterThanOrEqual(menu.minY, tray.maxY, tag)
            XCTAssertLessThanOrEqual(menu.maxY, l.bottomEdge, tag)
            XCTAssertFalse(menu.intersects(l.minimapDockFrame), "\(tag) メニューとミニマップ")
            XCTAssertGreaterThanOrEqual(HUDLayout.signalChatItemSize.height, 44)
        }
    }

    @MainActor
    func testKillFeedStaysClearOfSignalsAndControls() {
        for (tag, side, l) in layouts() {
            let feed = killFeedFrame(l)
            XCTAssertGreaterThanOrEqual(feed.minX, side, tag)
            XCTAssertLessThanOrEqual(feed.maxX, l.width - side, tag)
            XCTAssertGreaterThanOrEqual(feed.minY, l.topEdge + l.topButtonSize, "\(tag) キルフィードと情報列・スコア")
            XCTAssertFalse(feed.intersects(l.signalTrayFrame), "\(tag) キルフィードとシグナル列")
            XCTAssertFalse(feed.intersects(l.minimapDockFrame), "\(tag) キルフィードとミニマップ")
            XCTAssertFalse(feed.intersects(l.signalMessageFrame), "\(tag) キルフィードとメッセージ")
            for c in controls(l) {
                XCTAssertFalse(hits(feed, c), "\(tag) キルフィードと \(c.name) が重なる")
            }
            for b in badges(l) {
                XCTAssertFalse(feed.intersects(b.rect), "\(tag) キルフィードと \(b.name)")
            }
            // 情報側の半分に収まる（スコアの下、情報側寄り）
            XCTAssertEqual(feed.midX > l.width / 2, !l.leftHanded, tag)
            XCTAssertGreaterThanOrEqual(l.killFeedSideReserve, l.signalTrayFrame.width + 6)
        }
    }

    @MainActor
    func testMessageAreaSitsBelowTheMinimapAndAvoidsControls() {
        for (tag, side, l) in layouts() {
            let f = l.signalMessageFrame
            let dock = l.minimapDockFrame
            XCTAssertGreaterThanOrEqual(f.minX, side - 0.5, tag)
            XCTAssertLessThanOrEqual(f.maxX, l.width - side + 0.5, tag)
            XCTAssertGreaterThan(f.minY, dock.maxY, "\(tag) ミニマップ（と全体マップのボタン）の下")
            XCTAssertEqual(l.leftHanded ? f.maxX : f.minX, l.leftHanded ? dock.maxX : dock.minX, accuracy: 0.5,
                           "\(tag) ミニマップの側の端にそろえる")
            XCTAssertGreaterThanOrEqual(f.width, 120, "\(tag) 1 行に送り主と文言が入る幅")
            // 行数はスティックの待機位置の円の上端までに入る分（最低 1 行、最大 4 行）
            let rows = CGFloat(l.signalMessageRows)
            XCTAssertGreaterThanOrEqual(rows, 1, tag)
            XCTAssertLessThanOrEqual(Int(rows), HUDSignalBoard.maxMessages, tag)
            XCTAssertEqual(f.height, rows * l.signalMessageRowHeight + (rows - 1) * l.signalMessageSpacing, accuracy: 0.01,
                           "\(tag) \(Int(rows)) 行分")
            XCTAssertLessThanOrEqual(f.maxY, l.joystickRest.y - l.joystickRadius - 2 + 0.01, "\(tag) スティックの円の上")
            XCTAssertLessThan(f.maxY, l.bottomEdge, tag)
            XCTAssertFalse(f.intersects(l.signalTrayFrame), "\(tag) メッセージとシグナル列")
            XCTAssertFalse(f.intersects(l.signalChatMenuFrame), "\(tag) メッセージとメニュー")
            XCTAssertFalse(f.intersects(heroPanelFrame(l)), "\(tag) メッセージとヒーローパネル")
            for c in controls(l) {
                XCTAssertFalse(hits(f, c), "\(tag) メッセージと \(c.name) が重なる")
            }
            // 詠唱バー（幅 210・ヒーローパネルの上）と重ならない
            let barY = l.bottomEdge - HUDRootMetrics.heroPanelHeight(l) - 60 * min(l.scale, 1.08)
            let bar = CGRect(x: l.heroPanelCenterX - 105, y: barY - 12, width: 210, height: 24)
            XCTAssertFalse(f.intersects(bar), "\(tag) メッセージと詠唱バー")
        }
    }
}
