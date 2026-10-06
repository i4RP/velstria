import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

/// 観戦の HUD: ヒーロー詳細の純粋なビルダー（プレイヤーの HUD と一致）、スコアボード（観戦者の列・タップで追従・持ち主の強調）、
/// 視界・自動カメラ・シネマ表示・パネル、一時停止中の追従の反映（B21）、試合時間で流れるキルフィード・告知（B22）、
/// 目標タイマー・出来事の一覧、戦術マップの文言（B20）、ゴールドの帯の幅（B19）。
@MainActor
final class HUDSpectatorTests: XCTestCase {
    private var retained: [AnyObject] = []

    override func tearDown() {
        retained.removeAll()
        super.tearDown()
    }

    private func start(_ launch: BattleLaunch) -> (BattleController, HUDModel) {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        retained.append(app)
        let c = BattleController(launch: launch)
        let m = HUDModel(controller: c)
        m.start(app: app, onFinish: { _ in })
        addTeardownBlock { @MainActor in m.stop() }
        return (c, m)
    }

    private func spectate(seed: UInt64 = 7) -> (BattleController, HUDModel) {
        start(BattleLaunch(config: MatchFactory.botMatch(seed: seed)))
    }

    private func run(_ c: BattleController, ticks: Int) {
        for _ in 0..<ticks where !c.isEnded { c.frame(dt: Balance.dt) }
    }

    private func waitForSeek(_ c: BattleController, timeout: TimeInterval = 60) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while c.seekingToTick != nil && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// 人間の試合を少し進めて、その記録をリプレイとして起動する。
    private func replay(ticks: Int = 90, team: Team = .red) -> (BattleController, HUDModel, ReplayData) {
        let live = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P",
                                                                                                humanTeam: team, seed: 5)))
        run(live, ticks: ticks)
        let data = live.makeOutcome(abandoned: true).replay!
        let (c, m) = start(BattleLaunch(config: data.config, replay: data))
        return (c, m, data)
    }

    // MARK: ヒーロー詳細のビルダー

    func testHeroBuilderMatchesThePlayerHUD() {
        let (c, m) = start(BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "P", seed: 11)))
        c.send(.setAutoLevel(enabled: true))
        run(c, ticks: 240)
        m.refresh()
        guard let hi = c.humanIndex,
              let b = HUDModel.buildHeroPanel(c.state, c.ctx, index: hi) else { return XCTFail("自分のヒーロー") }
        XCTAssertEqual(b.hero, m.hero, "抜き出した純粋なビルダーはプレイヤーの HUD と同じ値を作る")
        XCTAssertEqual(b.vitals, m.vitals)
        XCTAssertEqual(b.skills, m.skills)
        XCTAssertEqual(b.spells, m.spells)
        XCTAssertTrue(b.skills.contains { $0.slot == .ultimate })
        XCTAssertNil(HUDModel.buildHeroPanel(c.state, c.ctx, index: c.state.units.count + 5), "範囲外は nil")
    }

    func testHeroCardForAnyHeroIncludesStats() {
        let (c, _) = spectate()
        run(c, ticks: 450)
        let s = c.state
        guard let red = s.heroIndices(team: .red).last, let h = s.units[red].hero,
              let card = HUDModel.buildHeroCard(s, c.ctx, index: red, ownerID: nil) else { return XCTFail() }
        XCTAssertEqual(card.id, s.units[red].id)
        XCTAssertEqual(card.team, .red)
        XCTAssertEqual(card.panel.hero.heroID, h.heroID)
        XCTAssertEqual(card.panel.hero.items, h.items)
        XCTAssertEqual(card.kills, h.score.kills)
        XCTAssertEqual(card.creepScore, h.score.creepScore)
        XCTAssertEqual(card.netWorth, Int((h.gold + h.itemInvested.reduce(0, +)).rounded()))
        XCTAssertEqual(card.damageDealt, Int(h.score.damageToHeroes.rounded()))
        XCTAssertEqual(card.panel.skills.map(\.slot), SkillSlot.actives, "必殺技まで 4 枠")
        XCTAssertTrue(card.panel.skills.allSatisfy { !$0.canLevel }, "観戦者は習得操作をしない")
        XCTAssertFalse(card.isOwner)
    }

    // MARK: スナップショット（ゴールド差・必殺技・持ち主）

    func testSpectateSnapshotGoldDiffAndOwner() {
        let (c, m, _) = replay()
        run(c, ticks: 60)
        m.refresh()
        let s = c.state
        let diff = EconomyRewards.teamGoldEarned(s, team: .blue) - EconomyRewards.teamGoldEarned(s, team: .red)
        XCTAssertEqual(m.spectate.goldDiff, Int((diff / 100).rounded()) * 100)
        XCTAssertEqual(m.spectate.heroes.count, 10)
        let owners = m.spectate.heroes.filter(\.isOwner)
        XCTAssertEqual(owners.map(\.id), [c.ownerHeroID!], "リプレイの持ち主だけを強調（B16）")
        // ミニマップでも持ち主を「自分」として描く
        XCTAssertEqual(m.minimap.heroes.filter(\.isHuman).count, 1)
        // スコアボードも
        m.openPanel(.scoreboard)
        let rows = m.scoreboard.blue + m.scoreboard.red
        XCTAssertEqual(rows.filter(\.isHuman).map(\.id), [c.ownerHeroID!])
    }

    func testScoreboardSpectatorColumnsAndTapToFollow() {
        let (c, m) = spectate()
        run(c, ticks: 120)
        m.refresh()
        m.openPanel(.scoreboard)
        let rows = m.scoreboard.blue + m.scoreboard.red
        XCTAssertEqual(rows.count, 10)
        XCTAssertTrue(rows.allSatisfy { $0.netWorth > 0 }, "観戦者には装備の価値を見せる")
        XCTAssertEqual(rows.filter(\.isFocus).count, 1, "追従中の行を示す")
        let red = m.scoreboard.red[2].id
        m.scoreboardRowTapped(red)
        XCTAssertEqual(c.cameraMode, .followUnit(red))
        XCTAssertNil(m.panel, "タップで追従したらスコアボードを閉じる")

        // プレイヤーには相手の所持 Gold を見せない
        let (_, p) = start(BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 3)))
        p.openPanel(.scoreboard)
        XCTAssertTrue((p.scoreboard.blue + p.scoreboard.red).allSatisfy { $0.netWorth == 0 && $0.damage == 0 })
        let before = p.controller.cameraMode
        p.scoreboardRowTapped(p.scoreboard.red[0].id)
        XCTAssertEqual(p.controller.cameraMode, before, "プレイヤーはスコアボードから追従しない")
    }

    // MARK: 視界・自動カメラ・シネマ表示・パネル

    func testVisionDirectorCinematicAndPanels() {
        let (c, m) = spectate()
        m.setSpectatorVision(.red)
        XCTAssertEqual(c.viewerTeam, .red)
        XCTAssertEqual(m.minimap.viewerTeam, .red, "一時停止中でもミニマップの霧を作り直す")
        m.setSpectatorVision(nil)
        XCTAssertNil(c.viewerTeam)

        let director = c.spectatorDirectorEnabled
        m.toggleSpectatorDirector()
        XCTAssertEqual(c.spectatorDirectorEnabled, !director)

        m.toggleSpectatorDrawer()
        XCTAssertTrue(m.spectator.isDrawerOpen)
        m.setTacticalMap(open: true)
        m.setCinematic(true)
        XCTAssertTrue(m.spectator.isCinematic)
        XCTAssertFalse(m.spectator.isDrawerOpen, "シネマ表示は観戦メニューを閉じる")
        XCTAssertFalse(m.isTacticalMapOpen, "シネマ表示は戦術マップを閉じる")
        m.setCinematic(false)
        XCTAssertFalse(m.spectator.isCinematic)

        run(c, ticks: 30)
        m.refresh()
        m.toggleSpectatorPanel(.hero)
        XCTAssertEqual(m.spectator.panel, .hero)
        XCTAssertEqual(m.spectator.heroCard?.id, m.spectator.focusID, "追従中のヒーローの詳細")
        m.toggleSpectatorPanel(.gold)
        XCTAssertEqual(m.spectator.panel, .gold)
        XCTAssertFalse(m.spectator.graph.points.isEmpty)
        m.toggleSpectatorPanel(.gold)
        XCTAssertNil(m.spectator.panel)

        // プレイヤーには効かない
        let (pc, p) = start(BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 3)))
        p.setSpectatorVision(.red)
        XCTAssertEqual(pc.viewerTeam, .blue)
        p.setCinematic(true)
        XCTAssertFalse(p.spectator.isCinematic)
    }

    func testSelectingTheFocusedHeroTogglesDetails() {
        let (c, m) = spectate()
        m.refresh()
        let blue = m.spectate.heroes[1].id
        m.spectatorSelectHero(blue)
        XCTAssertEqual(c.cameraMode, .followUnit(blue))
        m.refresh()
        XCTAssertNil(m.spectator.panel)
        m.spectatorSelectHero(blue)
        XCTAssertEqual(m.spectator.panel, .hero, "追従中をもう一度タップで詳細")
        XCTAssertEqual(m.spectator.heroCard?.id, blue)
    }

    // MARK: B21 一時停止中の追従

    func testFollowWhilePausedUpdatesFocusImmediately() {
        let (c, m) = spectate()
        run(c, ticks: 30)
        m.refresh()
        m.toggleSpectatorPause()
        XCTAssertTrue(c.isPaused)
        let target = m.spectate.heroes.last!
        m.follow(target.id)
        // HUDTicker が controller.cameraMode の変化で呼ぶ
        m.cameraModeChanged()
        XCTAssertEqual(m.spectator.focusID, target.id)
        XCTAssertEqual(m.minimap.heroes.first(where: \.isFocus)?.heroID, target.heroID, "注目の輪がすぐ移る")
        // 自動カメラが追従先を変えても同じ
        let other = m.spectate.heroes.first!
        c.cameraMode = .followUnit(other.id)
        m.cameraModeChanged()
        XCTAssertEqual(m.spectator.focusID, other.id)
        XCTAssertEqual(m.minimap.heroes.first(where: \.isFocus)?.heroID, other.heroID)
        // 自由カメラ → 追従に戻る
        m.minimapDragged(to: Vec2(4000, 4000))
        m.cameraModeChanged()
        XCTAssertTrue(m.spectator.isFreeCamera)
        m.refollowLastHero()
        XCTAssertEqual(c.cameraMode, .followUnit(other.id))
    }

    /// 自由カメラの移動（ドラッグ・パン）は指の動きのたびに cameraMode が変わる。一時停止中でも、注目の対象・
    /// 自由カメラかどうか・視界が変わった時だけ HUD を作り直す。
    func testFreeCameraDragWhilePausedRefreshesOnlyOnFocusChange() {
        let (c, m) = spectate()
        run(c, ticks: 30)
        m.refresh()
        m.toggleSpectatorPause()
        m.minimapDragged(to: Vec2(4000, 4000))
        m.cameraModeChanged()
        XCTAssertTrue(m.spectator.isFreeCamera)
        let version = m.minimapVersion
        for k in 1...20 {
            m.minimapDragged(to: Vec2(4000 + Double(k) * 10, 4000))
            m.cameraModeChanged()
        }
        XCTAssertEqual(m.minimapVersion, version, "自由カメラの移動だけでは HUD 全体を作り直さない")
        let id = m.spectate.heroes[3].id
        m.follow(id)
        m.cameraModeChanged()
        XCTAssertFalse(m.spectator.isFreeCamera)
        XCTAssertEqual(m.spectator.focusID, id)
        XCTAssertGreaterThan(m.minimapVersion, version, "追従先が変われば作り直す")
        // 視界の切り替え（HUDTicker が spectatorVision の変化でも呼ぶ）
        let before = m.minimapVersion
        c.spectatorVision = .blue
        m.cameraModeChanged()
        XCTAssertGreaterThan(m.minimapVersion, before)
        XCTAssertEqual(m.minimap.viewerTeam, .blue)
    }

    // MARK: B23 観戦者の一時停止で戦術マップを閉じない

    func testSpectatorPauseKeepsTheTacticalMapOpen() {
        let (c, m) = spectate()
        run(c, ticks: 30)
        m.refresh()
        m.setTacticalMap(open: true)
        XCTAssertTrue(m.isTacticalMapOpen)
        m.toggleSpectatorPause()
        XCTAssertTrue(c.isPaused)
        // BattleHUDView が controller.isPaused の変化で呼ぶ
        m.externallyPaused()
        XCTAssertTrue(m.isTacticalMapOpen, "ドックの一時停止で戦術マップを閉じない（B23）")
        XCTAssertNil(m.panel, "ドックの一時停止でポーズメニューを開かない")
        m.spectatorStep()
        m.externallyPaused()
        XCTAssertTrue(m.isTacticalMapOpen, "コマ送りでも閉じない")

        // 外部（バックグラウンド移行）の一時停止は従来どおり: マップを閉じてポーズメニューを開く
        m.toggleSpectatorPause()
        XCTAssertFalse(c.isPaused)
        c.isPaused = true
        m.externallyPaused()
        XCTAssertFalse(m.isTacticalMapOpen)
        XCTAssertEqual(m.panel, .pause)
    }

    func testAdjacentHeroCyclesAndSkipsDead() {
        func hero(_ id: EntityID, dead: Bool = false) -> HUDSpectateHero {
            HUDSpectateHero(id: id, heroID: "H001", team: id < 5 ? .blue : .red, level: 1, hpRatio: 1, isDead: dead, respawn: 0)
        }
        let heroes = (0..<10).map { hero(EntityID($0), dead: $0 == 3) }
        XCTAssertEqual(HUDSpectatorState.adjacentHero(from: 2, step: 1, heroes: heroes), 4, "倒れているヒーローは飛ばす")
        XCTAssertEqual(HUDSpectatorState.adjacentHero(from: 9, step: 1, heroes: heroes), 0, "最後の次は最初")
        XCTAssertEqual(HUDSpectatorState.adjacentHero(from: 0, step: -1, heroes: heroes), 9)
        XCTAssertEqual(HUDSpectatorState.adjacentHero(from: nil, step: 1, heroes: heroes), 0)
        let allDead = (0..<3).map { hero(EntityID($0), dead: true) }
        XCTAssertEqual(HUDSpectatorState.adjacentHero(from: 0, step: 1, heroes: allDead), 1, "全員倒れていれば順に")
        XCTAssertNil(HUDSpectatorState.adjacentHero(from: 0, step: 1, heroes: []))

        let (c, m) = spectate()
        m.refresh()
        let first = m.spectate.heroes[0].id
        m.follow(first)
        m.refresh()
        m.followAdjacentHero(1)
        XCTAssertEqual(c.cameraMode, .followUnit(m.spectate.heroes[1].id))
    }

    // MARK: B22 試合時間で流れるキルフィード・告知

    func testKillFeedExpiresOnGameTime() {
        let e = HUDKillFeedEntry(id: 1, killerHeroID: nil, killerTeam: nil, victimHeroID: "H001", victimTeam: .blue,
                                 assists: 0, involvesHuman: false, createdAt: 100, gameTime: 10)
        XCTAssertFalse(HUDModel.feedEntryExpired(e, wall: 101, game: 30), "早送りでも最短の実時間は読める")
        XCTAssertTrue(HUDModel.feedEntryExpired(e, wall: 103, game: 18), "早送りでは試合時間で早く消える")
        XCTAssertFalse(HUDModel.feedEntryExpired(e, wall: 200, game: 15), "一時停止中（試合時間が進まない）は残る")
        XCTAssertTrue(HUDModel.feedEntryExpired(e, wall: 100.5, game: 5), "巻き戻した先より後の項目は消す")

        let (c, m) = spectate()
        let s = c.state
        let blue = s.heroIndices(team: .blue).map { s.units[$0].id }
        let red = s.heroIndices(team: .red).map { s.units[$0].id }
        for k in 0..<8 {
            m.handle([.heroKilled(HeroKillEvent(victimID: red[k % 5], killerID: blue[k % 5], assistIDs: [], bounty: 300,
                                                 isFirstBlood: k == 0, multiKill: 1, killerStreak: 1, isShutdown: false))])
        }
        XCTAssertEqual(m.killFeed.count, m.killFeedLimit)
        XCTAssertEqual(m.killFeedLimit, HUDModel.killFeedMax + 1, "観戦者は少し多め")
        XCTAssertEqual(m.killFeed.last?.gameTime, s.time)
    }

    func testBannerExpiryUsesGameTime() {
        let d = HUDModel.bannerDuration
        XCTAssertFalse(HUDModel.bannerExpired(wall: 0.5, game: 4, duration: d), "8× でも最短の実時間は出す")
        XCTAssertTrue(HUDModel.bannerExpired(wall: 1.2, game: 9.6, duration: d), "早送りでは早く次へ")
        XCTAssertFalse(HUDModel.bannerExpired(wall: 2.0, game: 2.0, duration: d))
        XCTAssertTrue(HUDModel.bannerExpired(wall: 2.5, game: 2.5, duration: d), "通常速度は従来どおり約 2.4 秒")
        XCTAssertFalse(HUDModel.bannerExpired(wall: 4, game: 0, duration: d), "一時停止中はしばらく残る")
        XCTAssertTrue(HUDModel.bannerExpired(wall: d * 3, game: 0, duration: d), "止まったままでも出しっぱなしにしない")
        XCTAssertTrue(HUDModel.bannerExpired(wall: 0.1, game: -3, duration: d), "巻き戻したら消す")
    }

    // MARK: 目標タイマー・出来事の一覧

    func testObjectiveTimers() {
        let (c, _) = spectate()
        var s = c.state
        let camps: [HUDMinimapBuffer.Camp] = [
            .init(pos: .zero, alive: true, isBoss: true, kind: .astralWyrm, respawnRemaining: nil),
            .init(pos: .zero, alive: false, isBoss: true, kind: .ancientColossus, respawnRemaining: 65.2),
            .init(pos: .zero, alive: false, isBoss: false, kind: .small, respawnRemaining: 12),
        ]
        let blue = s.heroIndices(team: .blue)[0]
        s.units[blue].statuses.append(StatusEffect(kind: .wyrmBlessing, duration: 90))
        s.units[blue].statuses[s.units[blue].statuses.count - 1].remaining = 29.4
        let timers = HUDSpectatorState.objectives(camps: camps, state: s)
        XCTAssertEqual(timers, [
            HUDObjectiveTimer(kind: .wyrm, team: nil, seconds: nil),
            HUDObjectiveTimer(kind: .colossus, team: nil, seconds: 66),
            HUDObjectiveTimer(kind: .wyrmBlessing, team: .blue, seconds: 30),
        ])
        let unknown: [HUDMinimapBuffer.Camp] = [.init(pos: .zero, alive: false, isBoss: true, kind: .astralWyrm, respawnRemaining: nil)]
        XCTAssertTrue(HUDSpectatorState.objectives(camps: unknown, state: c.state).isEmpty, "出現時刻が分からない物は出さない")
    }

    func testEventLogNewestFirstWithFocus() {
        let (c, _) = spectate()
        let s = c.state
        let killer = s.units[s.heroIndices(team: .blue)[0]].id
        let victim = s.units[s.heroIndices(team: .red)[0]].id
        let t = ReplayTimeline(events: [
            TimelineEvent(tick: 300, kind: .kill(victimID: victim, killerID: killer, assistIDs: [7], killerTeam: .blue,
                                                 isFirstBlood: true, multiKill: 2, isShutdown: false), pos: Vec2(100, 200)),
            TimelineEvent(tick: 600, kind: .structure(team: .red, kind: .tower, lane: .mid, tier: .outer, killerID: nil), pos: nil),
            TimelineEvent(tick: 900, kind: .objective(kind: .astralWyrm, team: .red, killerID: victim), pos: nil),
            TimelineEvent(tick: 950, kind: .ace(team: .red), pos: nil),
        ], coveredTick: 1000)
        let log = HUDSpectatorState.eventLog(from: t, state: s)
        XCTAssertEqual(log.map(\.tick), [950, 900, 600, 300], "新しい順")
        XCTAssertTrue(log.allSatisfy { !$0.title.isEmpty })
        let kill = log.last!
        XCTAssertEqual(kill.focusID, killer)
        XCTAssertEqual(kill.team, .blue)
        XCTAssertNotNil(kill.leftHeroID)
        XCTAssertNotNil(kill.rightHeroID)
        XCTAssertNotNil(kill.subtitle, "ファーストブラッド・ダブルキル・アシスト")
        XCTAssertEqual(log[2].team, .blue, "タワーを失ったのはレッド → 有利はブルー")
        XCTAssertEqual(log[1].focusID, victim)
    }

    func testJumpToEventSeeksWhenSeekable() async {
        let (c, m) = spectate()
        run(c, ticks: 400)
        let e = HUDEventLogEntry(id: 0, tick: 300, title: "x", symbol: "bolt.fill", team: .blue, weight: 0.5)
        m.jumpToEvent(e)
        XCTAssertEqual(c.seekingToTick, 210, "出来事の 3 秒前から")
        await waitForSeek(c)
        XCTAssertEqual(c.state.tick, 210)
    }

    // MARK: B20 戦術マップの文言

    func testTacticalMapWordingForSpectators() {
        let saved = Loc.current
        defer { Loc.current = saved }
        Loc.current = .en
        typealias T = HUDTacticalMapText
        XCTAssertEqual(T.status(isSpectating: false, isReplay: false, isLiveWatcher: false, paused: false), .live)
        XCTAssertEqual(T.status(isSpectating: true, isReplay: true, isLiveWatcher: false, paused: false), .replay)
        XCTAssertEqual(T.status(isSpectating: true, isReplay: false, isLiveWatcher: false, paused: false), .spectating)
        XCTAssertEqual(T.status(isSpectating: true, isReplay: false, isLiveWatcher: true, paused: false), .liveWatch)
        XCTAssertEqual(T.status(isSpectating: true, isReplay: true, isLiveWatcher: false, paused: true), .paused)
        XCTAssertEqual(T.label(.replay), "REPLAY", "リプレイで LIVE と出さない")
        XCTAssertFalse(T.showsLastSeen(viewerTeam: nil), "全体視界の観戦には「最後に見えた位置」は無い")
        XCTAssertTrue(T.showsLastSeen(viewerTeam: .blue))
        XCTAssertNotEqual(T.subtitle(isSpectating: true, isReplay: false), T.subtitle(isSpectating: false, isReplay: false))
        XCTAssertEqual(T.focusLegend(isSpectating: true, hasOwner: false), "Followed hero")
    }

    // MARK: B19 ゴールドの帯の幅

    func testScorePillFitsBetweenMinimapAndPanel() {
        let (c, m) = spectate()
        run(c, ticks: 30)
        m.refresh()
        let host = UIHostingController(rootView: HUDSpectateScore(model: m).environment(AppModel(persistence: ServicesFixtures.tempPersistence())))
        let size = host.sizeThatFits(in: CGSize(width: 1000, height: 100))
        XCTAssertGreaterThan(size.width, 100)
        for (w, h, side, bottom) in [(667.0, 375.0, 0.0, 0.0), (812.0, 375.0, 44.0, 21.0), (874.0, 402.0, 62.0, 20.0)] {
            let base = HUDLayout(size: CGSize(width: w, height: h), safe: EdgeInsets(top: 0, leading: side, bottom: bottom, trailing: side),
                                 leftHanded: false)
            let l = HUDSpectatorLayout(base: base, seekable: true)
            XCTAssertLessThan(size.width + 12, l.topCenterWidth(panelOpen: true), "\(w)×\(h) パネルを開いた時のゴールドの帯")
        }
    }
}
