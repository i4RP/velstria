import XCTest
@testable import VELSTRIA
import VelstriaCore

// 担当: ui-liveops。ライブオプス画面の表示ロジック（時刻・ミッション・スターパス・リプレイ・観戦・練習・チュートリアル）。

final class LiveOpsScreensTests: XCTestCase {
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

    private func tokyoCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: 時刻

    func testCountdownFormatting() {
        XCTAssertEqual(LiveOpsClock.countdown(3_661), "01:01:01")
        XCTAssertEqual(LiveOpsClock.countdown(-5), "00:00:00")
        XCTAssertEqual(LiveOpsClock.countdown(59.9), "00:00:59")
        XCTAssertEqual(LiveOpsClock.countdown(2 * 86_400 + 3 * 3_600 + 5), "2日 3時間")
        Loc.current = .en
        XCTAssertEqual(LiveOpsClock.countdown(2 * 86_400 + 3 * 3_600 + 5), "2d 3h")
    }

    func testDailyResetIsNextLocalMidnight() {
        let cal = tokyoCalendar()
        let now = date(2026, 9, 28, 19, 30, calendar: cal)
        XCTAssertEqual(LiveOpsClock.nextDailyReset(after: now, calendar: cal), date(2026, 9, 29, 0, 0, calendar: cal))
        let justAfterMidnight = date(2026, 9, 29, 0, 1, calendar: cal)
        XCTAssertEqual(LiveOpsClock.nextDailyReset(after: justAfterMidnight, calendar: cal), date(2026, 9, 30, 0, 0, calendar: cal))
    }

    func testWeeklyResetIsNextMonday() {
        let cal = tokyoCalendar()
        // 2026-09-28 は月曜日
        let monday = date(2026, 9, 28, 19, 30, calendar: cal)
        XCTAssertEqual(LiveOpsClock.nextWeeklyReset(after: monday, calendar: cal), date(2026, 10, 5, 0, 0, calendar: cal))
        let sunday = date(2026, 10, 4, 23, 0, calendar: cal)
        XCTAssertEqual(LiveOpsClock.nextWeeklyReset(after: sunday, calendar: cal), date(2026, 10, 5, 0, 0, calendar: cal))
    }

    func testDurationAndSeasonFormatting() {
        XCTAssertEqual(LiveOpsFormat.duration(812), "13:32")
        XCTAssertEqual(LiveOpsFormat.duration(59.6), "1:00")
        XCTAssertEqual(StarPassTrack.seasonName("S1"), "シーズン 1")
        Loc.current = .en
        XCTAssertEqual(StarPassTrack.seasonName("S12"), "Season 12")
        XCTAssertEqual(StarPassTrack.seasonName("Launch"), "Launch")
    }

    // MARK: ミッション

    private func mission(_ id: String, target: Int, coins: Int = 100, xp: Int = 150) -> MissionDef {
        MissionDef(id: id, titleJa: "ミッション\(id)", titleEn: "Mission \(id)", kind: .playMatches, target: target,
                   rewardCoins: coins, rewardPassXP: xp)
    }

    func testMissionEntriesStatesAndDisplayOrder() {
        let defs = [mission("A", target: 3), mission("B", target: 5), mission("C", target: 1), mission("D", target: 2)]
        let progress = [MissionProgress(id: "A", progress: 1),
                        MissionProgress(id: "B", progress: 7),
                        MissionProgress(id: "C", progress: 1, claimed: true)]
        let entries = LiveOpsMissions.entries(defs, progress: progress)
        XCTAssertEqual(entries.map(\.state), [.inProgress, .claimable, .claimed, .inProgress])
        XCTAssertEqual(entries[1].fraction, 1, accuracy: 1e-9)
        XCTAssertEqual(entries[3].progress, 0)
        XCTAssertEqual(LiveOpsMissions.displayOrder(entries).map(\.id), ["B", "A", "D", "C"])
    }

    func testMissionRewardsSkipZeroAmounts() {
        let e = LiveOpsMissionEntry(def: mission("X", target: 1, coins: 0, xp: 200), progress: 0, claimed: false)
        XCTAssertEqual(e.rewards, [MailAttachment(kind: .passXP, amount: 200)])
        Loc.current = .en
        XCTAssertEqual(e.title, "Mission X")
    }

    func testExtraRewardsAreReadByFieldName() {
        struct WithExtras { var id = "EV"; var extraRewards = [MailAttachment(kind: .gem, amount: 50)] }
        struct WithoutExtras { var id = "D" }
        XCTAssertEqual(LiveOpsMissions.extraRewards(reflecting: WithExtras()), [MailAttachment(kind: .gem, amount: 50)])
        XCTAssertTrue(LiveOpsMissions.extraRewards(reflecting: WithoutExtras()).isEmpty)
        // 契約の MissionDef（追加報酬なし）は Coin / パス XP のみ
        let e = LiveOpsMissionEntry(def: mission("Y", target: 1, coins: 100, xp: 50), progress: 1, claimed: false)
        XCTAssertEqual(e.rewards, [MailAttachment(kind: .coin, amount: 100), MailAttachment(kind: .passXP, amount: 50)]
                       + LiveOpsMissions.extraRewards(e.def))
    }

    func testDayRolloverKeyComparison() {
        XCTAssertTrue(LiveOpsDayRollover.needsRefresh(lastLoginDayKey: "", today: "2026-09-29"))
        XCTAssertTrue(LiveOpsDayRollover.needsRefresh(lastLoginDayKey: "2026-09-28", today: "2026-09-29"))
        XCTAssertTrue(LiveOpsDayRollover.needsRefresh(lastLoginDayKey: "2026-12-31", today: "2027-01-01"))
        XCTAssertFalse(LiveOpsDayRollover.needsRefresh(lastLoginDayKey: "2026-09-29", today: "2026-09-29"))
        // 端末時刻が過去に戻った場合は処理しない
        XCTAssertFalse(LiveOpsDayRollover.needsRefresh(lastLoginDayKey: "2026-09-30", today: "2026-09-29"))
    }

    @MainActor
    func testDayRolloverRunsDailyRefreshOncePerDay() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LiveOpsRollover-\(UUID().uuidString)", isDirectory: true)
        let app = AppModel(persistence: PersistenceService(directory: dir))
        let now = Date()
        app.profile.lastLoginDayKey = "2000-01-01"
        XCTAssertTrue(LiveOpsDayRollover.refreshIfNeeded(app: app, now: now))
        XCTAssertEqual(app.profile.lastLoginDayKey, LiveOpsService.dayKey(now))
        XCTAssertFalse(LiveOpsDayRollover.refreshIfNeeded(app: app, now: now))
    }

    func testEventPhaseBoundaries() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let event = EventDef(id: "E", titleJa: "イベント", titleEn: "Event", detailJa: "", detailEn: "",
                             start: start, end: start.addingTimeInterval(3_600), missionIDs: [])
        XCTAssertEqual(LiveOpsEventPhase.of(event, now: start.addingTimeInterval(-1)), .upcoming)
        XCTAssertEqual(LiveOpsEventPhase.of(event, now: start), .active)
        XCTAssertEqual(LiveOpsEventPhase.of(event, now: start.addingTimeInterval(3_599)), .active)
        XCTAssertEqual(LiveOpsEventPhase.of(event, now: start.addingTimeInterval(3_600)), .ended)
    }

    // MARK: スターパス

    private func passRewards() -> [PassReward] {
        (1...10).map { lv in
            PassReward(level: lv, free: MailAttachment(kind: .coin, amount: 100 * lv),
                       premium: lv == 4 ? nil : MailAttachment(kind: .gem, amount: 50))
        }
    }

    func testStarPassCellStates() {
        var p = Profile()
        p.pass.xp = 7 * LiveOpsService.passXPPerLevel + 400
        p.pass.claimedFree = [1, 2, 3, 4, 5]
        let r = passRewards()
        XCTAssertEqual(StarPassTrack.level(p), 7)
        XCTAssertEqual(StarPassTrack.state(r[4], premium: false, profile: p), .claimed)
        XCTAssertEqual(StarPassTrack.state(r[5], premium: false, profile: p), .claimable)
        XCTAssertEqual(StarPassTrack.state(r[7], premium: false, profile: p), .locked)
        XCTAssertEqual(StarPassTrack.state(r[5], premium: true, profile: p), .premiumLocked)
        XCTAssertEqual(StarPassTrack.state(r[7], premium: true, profile: p), .locked)
        XCTAssertEqual(StarPassTrack.state(r[3], premium: true, profile: p), .none)
        p.pass.hasPremium = true
        p.pass.claimedPremium = [1]
        XCTAssertEqual(StarPassTrack.state(r[0], premium: true, profile: p), .claimed)
        XCTAssertEqual(StarPassTrack.state(r[5], premium: true, profile: p), .claimable)
    }

    func testStarPassClaimableSlotsAndFocus() {
        var p = Profile()
        p.pass.xp = 3 * LiveOpsService.passXPPerLevel
        p.pass.claimedFree = [1]
        let r = passRewards()
        XCTAssertEqual(StarPassTrack.claimableSlots(r, profile: p),
                       [StarPassSlot(level: 2, premium: false), StarPassSlot(level: 3, premium: false)])
        XCTAssertEqual(StarPassTrack.focusLevel(r, profile: p), 2)
        p.pass.hasPremium = true
        XCTAssertEqual(StarPassTrack.claimableSlots(r, profile: p).count, 2 + 3)
        p.pass.claimedFree = [1, 2, 3]
        p.pass.claimedPremium = [1, 2, 3]
        XCTAssertTrue(StarPassTrack.claimableSlots(r, profile: p).isEmpty)
        XCTAssertEqual(StarPassTrack.focusLevel(r, profile: p), 4)
    }

    func testStarPassLevelProgress() {
        let per = LiveOpsService.passXPPerLevel
        let mid = StarPassTrack.levelProgress(xp: 7 * per + 400)
        XCTAssertEqual(mid.current, 400)
        XCTAssertEqual(mid.needed, per)
        let maxed = StarPassTrack.levelProgress(xp: (LiveOpsService.passMaxLevel + 5) * per)
        XCTAssertEqual(maxed.current, maxed.needed)
    }

    // MARK: 報酬表示

    func testRewardMergeSumsAmountsAndDedupesItems() {
        let merged = RewardClaimText.merged([
            MailAttachment(kind: .coin, amount: 100),
            MailAttachment(kind: .passXP, amount: 150),
            MailAttachment(kind: .coin, amount: 50),
            MailAttachment(kind: .cosmetic, amount: 1, refID: "CO001"),
            MailAttachment(kind: .cosmetic, amount: 1, refID: "CO001"),
            MailAttachment(kind: .hero, amount: 1, refID: "H010"),
        ])
        XCTAssertEqual(merged, [
            MailAttachment(kind: .coin, amount: 150),
            MailAttachment(kind: .passXP, amount: 150),
            MailAttachment(kind: .cosmetic, amount: 1, refID: "CO001"),
            MailAttachment(kind: .hero, amount: 1, refID: "H010"),
        ])
        // 付与できなかった報酬の代替（数量 0）は表示しない
        XCTAssertTrue(RewardClaimText.merged([MailAttachment(kind: .gem, amount: 0)]).isEmpty)
        XCTAssertEqual(RewardClaimText.merged([MailAttachment(kind: .gem, amount: 0), MailAttachment(kind: .gem, amount: 30)]),
                       [MailAttachment(kind: .gem, amount: 30)])
    }

    func testRewardNamesAreLocalized() {
        let coin = MailAttachment(kind: .coin, amount: 1_200)
        XCTAssertTrue(RewardClaimText.name(coin).contains("コイン"))
        XCTAssertEqual(RewardClaimText.chipText(MailAttachment(kind: .passXP, amount: 300)), "300 XP")
        let hero = MailAttachment(kind: .hero, amount: 1, refID: "H001")
        XCTAssertTrue(RewardClaimText.name(hero).contains(MasterData.shared.hero("H001")!.displayNameJa))
        Loc.current = .en
        XCTAssertTrue(RewardClaimText.name(coin).hasPrefix("Starlight Coin"))
        if let skin = MasterData.shared.cosmetics.first(where: { $0.type == .heroSkin }) {
            XCTAssertEqual(RewardClaimText.chipText(MailAttachment(kind: .cosmetic, amount: 1, refID: skin.cosmeticID)), "Skin")
        }
    }

    // MARK: リプレイ

    private func tempPersistence() -> PersistenceService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LiveOpsTests-\(UUID().uuidString)", isDirectory: true)
        return PersistenceService(directory: dir)
    }

    func testReplayLaunchLoadsSavedReplay() throws {
        let persistence = tempPersistence()
        let config = MatchFactory.standardMatch(humanHeroID: "H001", humanName: "T", seed: 42)
        let data = ReplayRecorder(config: config).finish(summary: nil)
        let meta = try XCTUnwrap(persistence.saveReplay(data, heroID: "H001", won: true, date: Date()))
        switch ReplayLibrary.launch(for: meta, persistence: persistence) {
        case .success(let launch):
            XCTAssertEqual(launch.config, config)
            XCTAssertEqual(launch.replay, data)
            XCTAssertTrue(launch.isSpectating)
        case .failure(let e):
            XCTFail("unexpected \(e)")
        }
    }

    func testReplayLaunchReportsMissingAndIncompatible() throws {
        let persistence = tempPersistence()
        let missing = ReplayMeta(date: Date(), fileName: "none.vreplay", mode: .standard, heroID: "H001", won: nil, duration: 60)
        XCTAssertEqual(ReplayLibrary.launch(for: missing, persistence: persistence).liveOpsFailure, .missing)

        var data = ReplayRecorder(config: MatchFactory.botMatch(seed: 7)).finish(summary: nil)
        data.config.simVersion = MatchConfig.currentSimVersion + 1
        let meta = ReplayMeta(date: Date(), fileName: "old.vreplay", mode: .spectate, heroID: nil, won: nil, duration: 60)
        try JSONEncoder().encode(data).write(to: persistence.replaysDirectory.appendingPathComponent(meta.fileName))
        XCTAssertEqual(ReplayLibrary.launch(for: meta, persistence: persistence).liveOpsFailure, .incompatible)
    }

    func testReplayRemoveClearsMatchReferencesAndSortsNewestFirst() {
        let old = ReplayMeta(date: Date(timeIntervalSince1970: 100), fileName: "a", mode: .standard, heroID: "H001", won: true, duration: 600)
        let new = ReplayMeta(date: Date(timeIntervalSince1970: 200), fileName: "b", mode: .ranked, heroID: "H002", won: false, duration: 700)
        var p = Profile()
        p.replays = [old, new]
        p.matchHistory = [MatchRecord(date: old.date, mode: .standard, difficulty: .normal, won: true, duration: 600, heroID: "H001",
                                      kills: 3, deaths: 1, assists: 5, creepScore: 80, gold: 7000, damageToHeroes: 9000,
                                      grade: "A", isMVP: false, items: [], replayID: old.id)]
        XCTAssertEqual(ReplayLibrary.sorted(p.replays).map(\.id), [new.id, old.id])
        XCTAssertEqual(ReplayLibrary.record(for: old, in: p)?.kills, 3)
        ReplayLibrary.remove(old, from: &p)
        XCTAssertEqual(p.replays.map(\.id), [new.id])
        XCTAssertNil(p.matchHistory[0].replayID)
        XCTAssertNil(ReplayLibrary.record(for: old, in: p))
    }

    // MARK: 観戦・練習・チュートリアル

    func testSpectateConfigIsDeterministicAllBots() {
        let a = SpectateSetup.config(difficulty: .hard, seed: 99)
        let b = SpectateSetup.config(difficulty: .hard, seed: 99)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.mode, .spectate)
        XCTAssertEqual(a.players.count, 10)
        XCTAssertTrue(a.players.allSatisfy { $0.controller == .bot && $0.botDifficulty == .hard })
        let blue = SpectateSetup.roster(a, team: .blue)
        XCTAssertEqual(blue.map(\.position), LanePosition.allCases)
        XCTAssertEqual(Set(a.players.map(\.heroID)).count, 10)
        XCTAssertEqual(SpectateSetup.seedLabel(0xABCD), "#0000ABCD")
        XCTAssertGreaterThan(SpectateSetup.newSeed(), 0)
    }

    func testPracticeConfigAppliesOptionsAndLoadout() {
        var p = Profile()
        p.displayName = "Nova"
        p.heroSpells["H013"] = ["BS02", "BS07"]
        p.runePages = [RunePage(name: "A", primaryPath: .valor, runeIDs: [MasterData.shared.runes[0].runeID, "", "INVALID"])]
        p.selectedRunePage = 0
        p.equippedSkins["H013"] = "CO_NOT_OWNED"
        p.settings.autoLevelSkills = false
        let options = PracticeOptions(infiniteGold: true, noCooldowns: true, spawnMinions: false, spawnDummies: true, startLevel: 40)
        let config = PracticeSetup.config(heroID: "H013", options: options, profile: p, seed: 5)
        XCTAssertEqual(config.mode, .practice)
        XCTAssertEqual(config.practice?.startLevel, Balance.maxLevel)
        XCTAssertEqual(config.practice?.infiniteGold, true)
        XCTAssertEqual(config.practice?.spawnMinions, false)
        let human = config.humanSlot
        XCTAssertEqual(human?.heroID, "H013")
        XCTAssertEqual(human?.displayName, "Nova")
        XCTAssertEqual(human?.spells, ["BS02", "BS07"])
        XCTAssertEqual(human?.runes, [MasterData.shared.runes[0].runeID])
        XCTAssertNil(human?.skinID)
        XCTAssertEqual(human?.autoLevelSkills, false)
    }

    func testPracticeIgnoresInvalidSpellsAndPicksDefaultHero() {
        var p = Profile()
        p.heroSpells["H001"] = ["BS01", "BS01"]
        XCTAssertNil(PracticeSetup.spells(heroID: "H001", profile: p))
        XCTAssertEqual(PracticeSetup.defaultHeroID(profile: p), "H001")
        p.lastPickedHeroID = "H020"
        XCTAssertEqual(PracticeSetup.defaultHeroID(profile: p), "H020")
        p.lastPickedHeroID = "HXXX"
        XCTAssertEqual(PracticeSetup.defaultHeroID(profile: p), "H001")
        let config = PracticeSetup.config(heroID: "H001", options: PracticeOptions(startLevel: 0), profile: p, seed: 1)
        XCTAssertEqual(config.practice?.startLevel, 1)
        XCTAssertEqual(config.humanSlot?.spells.count, 2)
    }

    func testTutorialConfigAndCatalog() {
        let config = TutorialCatalog.config(playerName: "P")
        XCTAssertEqual(config.mode, .tutorial)
        XCTAssertEqual(config.players.count, 1)
        XCTAssertEqual(config.humanSlot?.heroID, TutorialCatalog.heroID)
        XCTAssertEqual(TutorialCatalog.chapters.map(\.titleJa), ["移動と攻撃", "スキルとレベル", "装備購入", "タワーとオブジェクト", "帰還とスペル"])
        XCTAssertEqual(Set(TutorialCatalog.tips.map(\.id)).count, TutorialCatalog.tips.count)
        for c in TutorialTip.Category.allCases {
            XCTAssertFalse(TutorialCatalog.tips.filter { $0.category == c }.isEmpty, "\(c) にヒントが無い")
        }
        for chapter in TutorialCatalog.chapters {
            XCTAssertEqual(chapter.pointsJa.count, chapter.pointsEn.count)
            XCTAssertFalse(chapter.detailEn.isEmpty)
        }
        for tip in TutorialCatalog.tips {
            XCTAssertFalse(tip.bodyJa.isEmpty)
            XCTAssertFalse(tip.bodyEn.isEmpty)
        }
        // DESIGN §7: 帰還は 6 秒詠唱で、移動・攻撃・被ダメで中断
        let recall = TutorialCatalog.chapters.last?.pointsJa.first ?? ""
        XCTAssertTrue(recall.contains("6 秒") && recall.contains("移動") && recall.contains("攻撃") && recall.contains("被ダメージ"))
        // DESIGN §4: 裏取り保護は「タワー射程内に（攻撃側の）ミニオンがいない時」
        XCTAssertTrue(TutorialCatalog.tips.first { $0.id == "laning_tower" }?.bodyJa.contains("味方ミニオン") == true)
    }
}

private extension Result {
    var liveOpsFailure: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
