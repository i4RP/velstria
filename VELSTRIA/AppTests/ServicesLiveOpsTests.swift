import XCTest
@testable import VELSTRIA
import VelstriaCore

final class ServicesLiveOpsTests: XCTestCase {
    private let master = ServicesFixtures.master

    private func input(won: Bool = true, kills: Int = 3, assists: Int = 4, cs: Int = 50, towers: Int = 2,
                       damage: Double = 8000, role: Role? = .vanguard) -> MatchProgressInput {
        MatchProgressInput(won: won, kills: kills, deaths: 1, assists: assists, creepScore: cs, towersDestroyed: towers,
                           damageToHeroes: damage, role: role, heroID: "H001")
    }

    // MARK: デイリー / ウィークリー

    func testDailySelectionIsDeterministicAndOnePerGroup() {
        XCTAssertEqual(LiveOpsService.dailyMissionPool.count, 12)
        XCTAssertEqual(LiveOpsService.weeklyMissionPool.count, 4)
        let pool = LiveOpsService.dailyMissionPool.map(\.id)
        var distinct = Set<[String]>()
        for day in 1...28 {
            let key = String(format: "2026-10-%02d", day)
            let a = LiveOpsService.dailySelection(dayKey: key)
            XCTAssertEqual(a, LiveOpsService.dailySelection(dayKey: key))
            XCTAssertEqual(a.count, 3)
            for (group, id) in a.enumerated() {
                let index = pool.firstIndex(of: id)!
                XCTAssertEqual(index / 4, group, "グループ \(group) から選ばれる")
            }
            distinct.insert(a)
        }
        XCTAssertGreaterThan(distinct.count, 5, "日によって入れ替わる")
    }

    func testRefreshReplacesDailyEachDayAndWeeklyEachWeek() {
        var p = Profile()
        let wed = ServicesFixtures.date(2026, 10, 7)
        LiveOpsService.refreshMissions(profile: &p, now: wed)
        XCTAssertEqual(p.missions.dayKey, "2026-10-07")
        XCTAssertEqual(p.missions.daily.map(\.id), LiveOpsService.dailySelection(dayKey: "2026-10-07"))
        XCTAssertEqual(LiveOpsService.dailyMissions(profile: p).map(\.id), p.missions.daily.map(\.id))
        XCTAssertEqual(LiveOpsService.weeklyMissions(profile: p).map(\.id), ["W01", "W02", "W03", "W04"])
        LiveOpsService.recordMatch(input(), profile: &p, now: wed)
        XCTAssertEqual(p.missions.weekly.first { $0.id == "W01" }?.progress, 1)

        let thu = ServicesFixtures.date(2026, 10, 8)
        LiveOpsService.refreshMissions(profile: &p, now: thu)
        XCTAssertEqual(p.missions.dayKey, "2026-10-08")
        XCTAssertTrue(p.missions.daily.allSatisfy { $0.progress == 0 })
        XCTAssertEqual(p.missions.weekly.first { $0.id == "W01" }?.progress, 1, "同じ週は維持")

        let nextMonday = ServicesFixtures.date(2026, 10, 12)
        LiveOpsService.refreshMissions(profile: &p, now: nextMonday)
        XCTAssertEqual(p.missions.weeklyKey, "2026-W42")
        XCTAssertEqual(p.missions.weekly.first { $0.id == "W01" }?.progress, 0)

        // 端末時刻が戻っても入れ替えない
        let before = p.missions
        LiveOpsService.refreshMissions(profile: &p, now: wed)
        XCTAssertEqual(p.missions, before)
    }

    func testMissionClaimIsIdempotent() {
        var p = Profile()
        let now = ServicesFixtures.weekday
        LiveOpsService.refreshMissions(profile: &p, now: now)
        let dailyID = p.missions.daily[0].id
        XCTAssertNil(LiveOpsService.claimMission(id: dailyID, profile: &p, now: now), "未達成は受け取れない")
        // デイリーを確実に達成させる
        let def = LiveOpsService.missionDef(id: dailyID)!
        p.missions.daily[0].progress = def.target
        let coinsBefore = p.starlightCoin
        let rewards = LiveOpsService.claimMission(id: dailyID, profile: &p, now: now)
        XCTAssertNotNil(rewards)
        XCTAssertEqual(p.starlightCoin, coinsBefore + def.rewardCoins)
        XCTAssertEqual(p.pass.xp, def.rewardPassXP)
        XCTAssertTrue(p.missions.daily[0].claimed)
        XCTAssertNil(LiveOpsService.claimMission(id: dailyID, profile: &p, now: now), "二重受取なし")
        XCTAssertEqual(p.starlightCoin, coinsBefore + def.rewardCoins)
        XCTAssertNil(LiveOpsService.claimMission(id: "W01", profile: &p, now: now))
        XCTAssertNil(LiveOpsService.claimMission(id: "UNKNOWN", profile: &p, now: now))
    }

    func testProgressKindsAndCaps() {
        var p = Profile()
        let now = ServicesFixtures.weekday
        LiveOpsService.refreshMissions(profile: &p, now: now)
        for _ in 0..<20 { LiveOpsService.recordMatch(input(kills: 5, towers: 1), profile: &p, now: now) }
        XCTAssertEqual(LiveOpsService.missionProgress(id: "W01", profile: p)?.progress, 15, "目標で頭打ち")
        XCTAssertEqual(LiveOpsService.missionProgress(id: "W03", profile: p)?.progress, 40)
        XCTAssertEqual(LiveOpsService.missionProgress(id: "W04", profile: p)?.progress, 12)
        XCTAssertEqual(LiveOpsService.claimableMissionCount(profile: p, now: now) >= 4, true)
        let all = LiveOpsService.claimAllMissions(profile: &p, now: now)
        XCTAssertFalse(all.isEmpty)
        XCTAssertEqual(LiveOpsService.claimableMissionCount(profile: p, now: now), 0)
        // 受取済みは進捗しない
        let progressed = LiveOpsService.recordMatch(input(), profile: &p, now: now)
        XCTAssertFalse(progressed.contains("W01"))
    }

    func testUnclaimedCompletedMissionsAreMailedOnRollover() {
        var p = Profile()
        let now = ServicesFixtures.weekday
        LiveOpsService.refreshMissions(profile: &p, now: now)
        let def = LiveOpsService.missionDef(id: p.missions.daily[0].id)!
        p.missions.daily[0].progress = def.target
        LiveOpsService.refreshMissions(profile: &p, now: ServicesFixtures.date(2026, 10, 8))
        XCTAssertEqual(p.mail.count, 1)
        let coinsBefore = p.starlightCoin
        _ = LiveOpsService.claimMail(id: p.mail[0].id, profile: &p, now: ServicesFixtures.date(2026, 10, 8))
        XCTAssertEqual(p.starlightCoin, coinsBefore + def.rewardCoins)
    }

    // MARK: イベント

    func testEventsWindows() {
        let oct = ServicesFixtures.date(2026, 10, 15)
        XCTAssertTrue(LiveOpsService.activeEvents(now: oct).contains { $0.id == LiveOpsService.launchEventID })
        XCTAssertFalse(LiveOpsService.activeEvents(now: ServicesFixtures.date(2027, 1, 2)).contains { $0.id == LiveOpsService.launchEventID })
        XCTAssertFalse(LiveOpsService.activeEvents(now: ServicesFixtures.date(2026, 9, 30)).contains { $0.id == LiveOpsService.launchEventID })
        XCTAssertTrue(LiveOpsService.activeEvents(now: ServicesFixtures.date(2026, 12, 31, hour: 23)).contains { $0.id == LiveOpsService.launchEventID })
        XCTAssertEqual(LiveOpsService.eventMissions(eventID: LiveOpsService.launchEventID).count, 3)

        XCTAssertTrue(LiveOpsService.isWeekendBoostActive(now: ServicesFixtures.date(2026, 10, 3, hour: 0, minute: 1)))
        XCTAssertTrue(LiveOpsService.isWeekendBoostActive(now: ServicesFixtures.date(2026, 10, 4, hour: 23)))
        XCTAssertFalse(LiveOpsService.isWeekendBoostActive(now: ServicesFixtures.date(2026, 10, 5, hour: 0, minute: 1)))
        XCTAssertFalse(LiveOpsService.isWeekendBoostActive(now: ServicesFixtures.date(2026, 10, 2, hour: 23)))
        // 平日は次の週末を予告として返す
        let upcoming = LiveOpsService.events(now: ServicesFixtures.date(2026, 10, 7)).first { $0.id == LiveOpsService.weekendEventID }!
        XCTAssertEqual(LiveOpsService.dayKey(upcoming.start), "2026-10-10")
        XCTAssertEqual(LiveOpsService.dayKey(upcoming.end), "2026-10-12")
    }

    func testEventMissionProgressAndClaim() {
        var p = Profile()
        let now = ServicesFixtures.date(2026, 10, 15)
        for _ in 0..<10 { LiveOpsService.recordMatch(input(kills: 3), profile: &p, now: now) }
        XCTAssertEqual(LiveOpsService.missionProgress(id: "EV01", profile: p)?.progress, 10)
        XCTAssertEqual(LiveOpsService.missionProgress(id: "EV03", profile: p)?.progress, 30)
        let gemsBefore = p.freeGem
        XCTAssertNotNil(LiveOpsService.claimMission(id: "EV01", profile: &p, now: now))
        XCTAssertEqual(p.freeGem, gemsBefore + 50)
        XCTAssertNil(LiveOpsService.claimMission(id: "EV01", profile: &p, now: now))
        XCTAssertNotNil(LiveOpsService.claimMission(id: "EV03", profile: &p, now: now))
        XCTAssertTrue(p.ownedCosmeticIDs.contains("CO023"))
        // イベント外の期間は進まない・受け取れない
        var q = Profile()
        let after = ServicesFixtures.date(2027, 2, 1)
        LiveOpsService.recordMatch(input(), profile: &q, now: after)
        XCTAssertEqual(LiveOpsService.missionProgress(id: "EV01", profile: q)?.progress, 0)
        // イベント進捗は実績の件数に数えない
        XCTAssertEqual(LiveOpsService.unlockedAchievementCount(profile: p), LiveOpsService.achievements.filter {
            p.achievements[$0.id]?.unlockedAt != nil
        }.count)
    }

    // MARK: スターパス

    func testPassRewardsTable() {
        let rewards = LiveOpsService.passRewards()
        XCTAssertEqual(rewards.count, 30)
        XCTAssertEqual(rewards.map(\.level), Array(1...30))
        XCTAssertTrue(rewards.allSatisfy { $0.free != nil && $0.premium != nil })
        let cosmetics = rewards.flatMap { [$0.free, $0.premium] }.compactMap { $0 }.filter { $0.kind == .cosmetic }
        XCTAssertEqual(cosmetics.count, 9)
        XCTAssertEqual(Set(cosmetics.compactMap(\.refID)).count, 9)
        XCTAssertTrue(cosmetics.allSatisfy { master.cosmetic($0.refID ?? "") != nil })
        XCTAssertEqual(LiveOpsService.passLevel(xp: 999), 0)
        XCTAssertEqual(LiveOpsService.passLevel(xp: 1000), 1)
        XCTAssertEqual(LiveOpsService.passLevel(xp: 99_999), 30)
        XCTAssertEqual(LiveOpsService.passXPInLevel(xp: 2500), 500)
    }

    func testPassClaimRules() {
        var p = Profile()
        XCTAssertNil(LiveOpsService.claimPass(level: 1, premium: false, profile: &p), "未到達")
        LiveOpsService.addPassXP(5000, to: &p)
        XCTAssertEqual(LiveOpsService.claimablePassRewardCount(profile: p), 5)
        XCTAssertNil(LiveOpsService.claimPass(level: 6, premium: false, profile: &p))
        XCTAssertNil(LiveOpsService.claimPass(level: 0, premium: false, profile: &p))
        XCTAssertNil(LiveOpsService.claimPass(level: 31, premium: false, profile: &p))
        let r1 = LiveOpsService.claimPass(level: 1, premium: false, profile: &p)
        XCTAssertEqual(r1, MailAttachment(kind: .coin, amount: 110))
        XCTAssertEqual(p.starlightCoin, 110)
        XCTAssertNil(LiveOpsService.claimPass(level: 1, premium: false, profile: &p), "二重受取なし")
        XCTAssertNil(LiveOpsService.claimPass(level: 1, premium: true, profile: &p), "プレミアム未購入")
        p.pass.hasPremium = true
        XCTAssertEqual(LiveOpsService.claimablePassRewardCount(profile: p), 4 + 5)
        XCTAssertNotNil(LiveOpsService.claimPass(level: 1, premium: true, profile: &p))
        XCTAssertNil(LiveOpsService.claimPass(level: 1, premium: true, profile: &p))
        let rest = LiveOpsService.claimAllPass(profile: &p)
        XCTAssertEqual(rest.count, 8)
        XCTAssertEqual(p.pass.claimedFree.sorted(), [1, 2, 3, 4, 5])
        XCTAssertEqual(p.pass.claimedPremium.sorted(), [1, 2, 3, 4, 5])
        XCTAssertTrue(p.ownedCosmeticIDs.contains("CO003"), "プレミアム 5 段階目のコスメ")
        LiveOpsService.addPassXP(1_000_000, to: &p)
        XCTAssertEqual(p.pass.xp, 30_000)
    }

    // MARK: ログイン・メール

    func testWelcomeAndLoginBonusCycle() {
        var p = Profile()
        let day1 = ServicesFixtures.date(2026, 10, 1, hour: 8)
        LiveOpsService.onLaunch(profile: &p, master: master, now: day1)
        XCTAssertEqual(p.totalLoginDays, 1)
        XCTAssertEqual(p.loginStreak, 1)
        XCTAssertEqual(p.mail.count, 2)
        let welcome = p.mail.first { $0.attachments.contains { $0.kind == .cosmetic } && $0.expiresAt == nil }!
        XCTAssertEqual(welcome.attachments.first { $0.kind == .coin }?.amount, 500)
        XCTAssertEqual(welcome.attachments.first { $0.kind == .gem }?.amount, 100)
        let frameID = welcome.attachments.first { $0.kind == .cosmetic }?.refID
        XCTAssertEqual(frameID.flatMap { master.cosmetic($0)?.type }, .avatarFrame)
        XCTAssertEqual(p.mail[0].attachments, [MailAttachment(kind: .coin, amount: 100)], "1 日目")

        // 同じ日の再起動では増えない
        LiveOpsService.onLaunch(profile: &p, master: master, now: day1.addingTimeInterval(3600))
        XCTAssertEqual(p.mail.count, 2)
        XCTAssertEqual(p.totalLoginDays, 1)

        let expected = LiveOpsService.loginBonusCalendar()
        XCTAssertEqual(expected.count, 7)
        for day in 2...7 {
            LiveOpsService.onLaunch(profile: &p, master: master, now: ServicesFixtures.date(2026, 10, day, hour: 8))
            if day < 7 { XCTAssertEqual(p.mail[0].attachments, [expected[day - 1]], "\(day) 日目") }
        }
        XCTAssertEqual(p.loginStreak, 7)
        let day7 = p.mail[0].attachments[0]
        XCTAssertEqual(day7.kind, .cosmetic)
        XCTAssertEqual(day7.refID.flatMap { master.cosmetic($0)?.rarity }, .epic)

        // 1 日空けると連続ログインはリセット、周期は累計日数で進む
        LiveOpsService.onLaunch(profile: &p, master: master, now: ServicesFixtures.date(2026, 10, 9, hour: 8))
        XCTAssertEqual(p.loginStreak, 1)
        XCTAssertEqual(p.totalLoginDays, 8)
        XCTAssertEqual(p.mail[0].attachments, [expected[0]])
        XCTAssertEqual(LiveOpsService.loginBonusDayIndex(profile: p), 0)

        // 端末時刻を戻しても再付与しない
        let count = p.mail.count
        LiveOpsService.onLaunch(profile: &p, master: master, now: ServicesFixtures.date(2026, 10, 5, hour: 8))
        XCTAssertEqual(p.mail.count, count)
    }

    func testDay7FallsBackToGemsWhenOwned() {
        var p = Profile()
        p.totalLoginDays = 7
        let cosmetic = LiveOpsService.loginBonusCalendar(profile: p)[6]
        XCTAssertEqual(cosmetic.kind, .cosmetic)
        p.ownedCosmeticIDs = [cosmetic.refID!]
        XCTAssertEqual(LiveOpsService.loginBonusCalendar(profile: p)[6], MailAttachment(kind: .gem, amount: 100))
    }

    func testMailClaimIsIdempotentAndExpires() {
        var p = Profile()
        let now = ServicesFixtures.weekday
        LiveOpsService.sendMail(to: &p, title: "A", body: "a", attachments: [MailAttachment(kind: .coin, amount: 100)], now: now)
        LiveOpsService.sendMail(to: &p, title: "B", body: "b", attachments: [MailAttachment(kind: .gem, amount: 10)], now: now,
                                expiresAt: now.addingTimeInterval(60))
        let first = LiveOpsService.claimMail(id: p.mail[1].id, profile: &p, now: now)
        XCTAssertEqual(first, [MailAttachment(kind: .coin, amount: 100)])
        XCTAssertEqual(LiveOpsService.claimMail(id: p.mail[1].id, profile: &p, now: now), [])
        XCTAssertEqual(p.starlightCoin, 100)
        // 期限切れは受け取れない
        XCTAssertEqual(LiveOpsService.claimAllMail(profile: &p, now: now.addingTimeInterval(120)), [])
        XCTAssertEqual(p.freeGem, 0)
        LiveOpsService.pruneMail(profile: &p, now: now.addingTimeInterval(120))
        XCTAssertEqual(p.mail.count, 1)
        // 上限
        for i in 0..<120 {
            LiveOpsService.sendMail(to: &p, title: "\(i)", body: "", attachments: [], now: now)
        }
        XCTAssertEqual(p.mail.count, LiveOpsService.maxMailCount)
    }

    func testGrantEveryAttachmentKind() {
        var p = Profile()
        LiveOpsService.grant(MailAttachment(kind: .coin, amount: 10), to: &p)
        LiveOpsService.grant(MailAttachment(kind: .gem, amount: 5), to: &p)
        LiveOpsService.grant(MailAttachment(kind: .passXP, amount: 1500), to: &p)
        LiveOpsService.grant(MailAttachment(kind: .cosmetic, amount: 1, refID: "CO002"), to: &p)
        LiveOpsService.grant(MailAttachment(kind: .hero, amount: 1, refID: "H010"), to: &p)
        XCTAssertEqual(p.starlightCoin, 10)
        XCTAssertEqual(p.freeGem, 5)
        XCTAssertEqual(p.paidGem, 0, "報酬の Gem は無償")
        XCTAssertEqual(p.pass.xp, 1500)
        XCTAssertTrue(p.ownedCosmeticIDs.contains("CO002"))
        XCTAssertTrue(p.ownedHeroIDs.contains("H010"))
        // 重複は通貨に変換
        let dupCosmetic = LiveOpsService.grantResolved(MailAttachment(kind: .cosmetic, amount: 1, refID: "CO002"), to: &p)
        XCTAssertEqual(dupCosmetic, MailAttachment(kind: .gem, amount: 130))
        XCTAssertEqual(p.freeGem, 135)
        XCTAssertEqual(p.ownedCosmeticIDs.filter { $0 == "CO002" }.count, 1)
        let dupHero = LiveOpsService.grantResolved(MailAttachment(kind: .hero, amount: 1, refID: "H010"), to: &p)
        XCTAssertEqual(dupHero.kind, .coin)
        XCTAssertGreaterThan(dupHero.amount, 0)
        XCTAssertEqual(p.ownedHeroIDs.filter { $0 == "H010" }.count, 1)
        // 不正な参照は何もしない
        let before = p
        LiveOpsService.grant(MailAttachment(kind: .cosmetic, amount: 1, refID: "CO999"), to: &p)
        LiveOpsService.grant(MailAttachment(kind: .coin, amount: -50), to: &p)
        XCTAssertEqual(p, before)
    }

    // MARK: 実績・お知らせ

    func testAchievementsEvaluationAndClaim() {
        XCTAssertTrue((22...30).contains(LiveOpsService.achievements.count))
        XCTAssertEqual(Set(LiveOpsService.achievements.map(\.id)).count, LiveOpsService.achievements.count)
        var p = Profile()
        let now = ServicesFixtures.weekday
        XCTAssertTrue(LiveOpsService.evaluateAchievements(profile: &p, master: master, now: now).isEmpty)
        p.career.wins = 10
        p.career.matches = 12
        p.career.perHero["H001"] = HeroCareer(matches: 5)
        p.career.perHero["H002"] = HeroCareer(matches: 1)
        let unlocked = LiveOpsService.evaluateAchievements(profile: &p, master: master, now: now)
        XCTAssertTrue(unlocked.contains("ACH_FIRST_WIN"))
        XCTAssertTrue(unlocked.contains("ACH_WINS_10"))
        XCTAssertTrue(unlocked.contains("ACH_MATCHES_10"))
        let h1Role = master.hero("H001")!.role
        XCTAssertTrue(unlocked.contains("ACH_ROLE_\(h1Role.rawValue.uppercased())"))
        XCTAssertFalse(unlocked.contains("ACH_WINS_50"))
        XCTAssertEqual(p.achievements["ACH_WINS_50"]?.progress, 10)
        XCTAssertTrue(LiveOpsService.evaluateAchievements(profile: &p, master: master, now: now).isEmpty, "再評価で重複解除しない")
        XCTAssertEqual(LiveOpsService.claimAchievement(id: "ACH_WINS_10", profile: &p, now: now), 30)
        XCTAssertEqual(p.freeGem, 30)
        XCTAssertNil(LiveOpsService.claimAchievement(id: "ACH_WINS_10", profile: &p, now: now))
        XCTAssertNil(LiveOpsService.claimAchievement(id: "ACH_WINS_50", profile: &p, now: now))
        XCTAssertEqual(p.freeGem, 30)
    }

    func testNoticesAreBilingual() {
        let notices = LiveOpsService.notices
        XCTAssertEqual(notices.count, 4)
        XCTAssertEqual(Set(notices.map(\.id)).count, 4)
        for n in notices {
            XCTAssertFalse(n.titleJa.isEmpty)
            XCTAssertFalse(n.titleEn.isEmpty)
            XCTAssertFalse(n.bodyJa.isEmpty)
            XCTAssertFalse(n.bodyEn.isEmpty)
        }
        var p = Profile()
        XCTAssertEqual(LiveOpsService.unreadNoticeCount(profile: p), 4)
        LiveOpsService.markNoticeRead(id: "NT001", profile: &p)
        LiveOpsService.markNoticeRead(id: "NT001", profile: &p)
        XCTAssertEqual(LiveOpsService.unreadNoticeCount(profile: p), 3)
        for m in LiveOpsService.dailyMissionPool + LiveOpsService.weeklyMissionPool + LiveOpsService.eventMissionPool {
            XCTAssertFalse(m.titleJa.isEmpty)
            XCTAssertFalse(m.titleEn.isEmpty)
        }
    }
}
