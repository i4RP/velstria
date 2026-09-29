import XCTest
@testable import VELSTRIA
import VelstriaCore

// 担当: ui-flow。フロー系ロジック（名前規則・オンボーディング再開・ドラフト・構成生成・通報メール・評価内訳）のテスト。

final class FlowNameAndOnboardingTests: XCTestCase {
    func testPlayerNameRules() {
        XCTAssertNil(PlayerNameRules.validate("  ab  "))
        XCTAssertEqual(PlayerNameRules.normalized("  ab  "), "ab")
        XCTAssertEqual(PlayerNameRules.validate("a"), .tooShort)
        XCTAssertEqual(PlayerNameRules.validate("   "), .tooShort)
        XCTAssertNil(PlayerNameRules.validate("123456789012"))
        XCTAssertEqual(PlayerNameRules.validate("1234567890123"), .tooLong)
        XCTAssertNil(PlayerNameRules.validate("星環の旅人"))
        XCTAssertEqual(PlayerNameRules.validate("ab\ncd"), .invalidCharacters)
        XCTAssertEqual(PlayerNameRules.validate("ab\u{0007}c"), .invalidCharacters)
        // 絵文字は 1 文字として数える
        XCTAssertNil(PlayerNameRules.validate("🌟🌟"))
    }

    func testNameSuggestionsAlwaysValid() {
        for seed in UInt64(0)..<300 {
            XCTAssertNil(PlayerNameRules.validate(PlayerNameRules.suggestion(seed: seed, english: false)))
            XCTAssertNil(PlayerNameRules.validate(PlayerNameRules.suggestion(seed: seed, english: true)))
        }
        XCTAssertEqual(PlayerNameRules.suggestion(seed: 42, english: true), PlayerNameRules.suggestion(seed: 42, english: true))
    }

    func testOnboardingResumesAtFirstIncompleteStep() {
        var p = Profile()
        XCTAssertEqual(OnboardingStep.firstPending(for: p), .age)
        p.ageBracket = .age16to19
        XCTAssertEqual(OnboardingStep.firstPending(for: p), .terms)
        p.acceptedTermsVersion = FeatureFlags.currentTermsVersion
        XCTAssertEqual(OnboardingStep.firstPending(for: p), .name)
        p.displayName = "Tester"
        XCTAssertEqual(OnboardingStep.firstPending(for: p), .prepare)
        p.firstResourcePrepared = true
        XCTAssertEqual(OnboardingStep.firstPending(for: p), .tutorial)
        // 規約改定時は規約から
        p.acceptedTermsVersion = FeatureFlags.currentTermsVersion - 1
        XCTAssertEqual(OnboardingStep.firstPending(for: p), .terms)
    }

    func testWarmUpDoesRealWork() {
        XCTAssertGreaterThan(FlowWarmUp.touchMasterData(.shared), 100)
        let ticks = FlowWarmUp.runSimulationWarmUp(seconds: 1.0)
        XCTAssertGreaterThanOrEqual(ticks, Int(Balance.tickRate))
        XCTAssertLessThanOrEqual(ticks, Int(Balance.tickRate) + 1)
    }
}

final class FlowDraftTests: XCTestCase {
    private let owned = ["H001", "H002", "H003", "H004", "H005", "H006"]

    func testTurnOrder() {
        let t = DraftEngine.turns
        XCTAssertEqual(t.count, 14)
        XCTAssertEqual(t.prefix(4).map(\.action), [.ban, .ban, .ban, .ban])
        XCTAssertEqual(t.prefix(4).map(\.team), [.blue, .red, .blue, .red])
        XCTAssertEqual(t.dropFirst(4).map(\.slotLabel), ["B1", "R1", "R2", "B2", "B3", "R3", "R4", "B4", "B5", "R5"])
        XCTAssertEqual(t.indices.filter { t[$0].isPlayer }, [0, 4])
    }

    /// プレイヤーの BAN/ピック以外を AI に任せて最後まで進める。希望ヒーローが BAN されていたら自動選択。
    static func runDraft(seed: UInt64, owned: [String], playerBan: String?, playerPick: String) -> DraftEngine {
        var d = DraftEngine(seed: seed, ownedHeroIDs: owned)
        while let turn = d.currentTurn {
            let choice: String?
            if turn.isPlayer {
                choice = turn.action == .ban ? playerBan : d.autoChoiceForPlayer(preferred: [playerPick])
            } else {
                choice = d.aiChoice()
            }
            guard d.commit(choice) else {
                XCTFail("手番 \(d.turnIndex) の確定に失敗")
                break
            }
        }
        return d
    }

    private func runDraft(seed: UInt64, playerBan: String?, playerPick: String) -> DraftEngine {
        Self.runDraft(seed: seed, owned: owned, playerBan: playerBan, playerPick: playerPick)
    }

    /// 先頭 4 手の BAN で指定ヒーローが選ばれないシードを探す（テストの前提を固定する）。
    private func seed(avoidingBanOf hero: String, from start: UInt64) -> UInt64 {
        var s = start
        while Self.runDraft(seed: s, owned: owned, playerBan: nil, playerPick: hero).playerPick?.heroID != hero { s += 1 }
        return s
    }

    func testFullDraftIsValidAndDeterministic() {
        let s = seed(avoidingBanOf: "H003", from: 777)
        let a = runDraft(seed: s, playerBan: "H010", playerPick: "H003")
        let b = runDraft(seed: s, playerBan: "H010", playerPick: "H003")
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.isComplete)
        XCTAssertEqual(a.bannedHeroIDs.count, 4)
        XCTAssertTrue(a.bannedHeroIDs.contains("H010"))
        let picked = a.pickedHeroIDs
        XCTAssertEqual(picked.count, 10)
        XCTAssertEqual(Set(picked).count, 10)
        XCTAssertTrue(Set(picked).isDisjoint(with: Set(a.bannedHeroIDs)))
        for team in Team.players {
            XCTAssertEqual(Set(a.picks(for: team).map(\.position)), Set(LanePosition.allCases))
        }
        XCTAssertEqual(a.playerPick?.heroID, "H003")
        XCTAssertEqual(a.playerPick?.position, .carry)   // Ranger → ボット

        let others = (1...5).map { runDraft(seed: s &+ UInt64($0) * 1000, playerBan: "H010", playerPick: "H003").pickedHeroIDs }
        XCTAssertTrue(others.contains { $0 != a.pickedHeroIDs }, "シードが違えば AI の選択も変わる")
    }

    func testPlayerRestrictions() {
        var d = DraftEngine(seed: 1, ownedHeroIDs: owned)
        // BAN は未所持でも可能
        XCTAssertTrue(d.canPlayerSelect("H020"))
        XCTAssertFalse(d.commit("H999"))
        XCTAssertTrue(d.commit("H020"))
        // AI の手番ではプレイヤーは選べない
        XCTAssertFalse(d.canPlayerSelect("H001"))
        while let t = d.currentTurn, !t.isPlayer { d.commit(d.aiChoice()) }
        XCTAssertEqual(d.currentTurn?.action, .pick)
        XCTAssertFalse(d.canPlayerSelect("H020"), "BAN 済み")
        XCTAssertFalse(d.canPlayerSelect("H007"), "未所持")
        XCTAssertFalse(d.commit("H007"))
        let expected = ["H004", "H005", "H006", "H001"].first { d.canPlayerSelect($0) }
        XCTAssertEqual(d.autoChoiceForPlayer(preferred: ["H020"] + [expected].compactMap { $0 }), expected)
    }

    func testBanTimeoutSkips() {
        var d = DraftEngine(seed: 5, ownedHeroIDs: owned)
        XCTAssertNil(d.autoChoiceForPlayer(preferred: ["H001"]))
        XCTAssertTrue(d.commit(nil))
        XCTAssertEqual(d.bans(for: .blue), [nil])
        XCTAssertEqual(d.bannedHeroIDs, [])
    }

    func testPositionSwapWithAlly() {
        var d = runDraft(seed: seed(avoidingBanOf: "H003", from: 99), playerBan: nil, playerPick: "H003")
        XCTAssertEqual(d.playerPick?.position, .carry)
        let allyAtMid = d.heroID(team: .blue, position: .mid)
        XCTAssertNotNil(allyAtMid)
        d.setPlayerPosition(.mid)
        XCTAssertEqual(d.playerPick?.position, .mid)
        XCTAssertEqual(d.heroID(team: .blue, position: .carry), allyAtMid)
        XCTAssertEqual(Set(d.picks(for: .blue).map(\.position)), Set(LanePosition.allCases))
    }

    func testApplyDraftToConfig() throws {
        let d = runDraft(seed: 2024, playerBan: "H016", playerPick: "H003")
        let hero = try XCTUnwrap(d.playerPick?.heroID)
        var config = MatchFactory.standardMatch(mode: .ranked, humanHeroID: hero, humanName: "Tester",
                                                humanPosition: d.playerPick?.position, banned: d.bannedHeroIDs, seed: 2024)
        d.apply(to: &config)
        XCTAssertEqual(config.players.count, 10)
        XCTAssertEqual(Set(config.players.map(\.heroID)).count, 10)
        for slot in config.players {
            XCTAssertEqual(d.heroID(team: slot.team, position: slot.position), slot.heroID)
            XCTAssertFalse(d.bannedHeroIDs.contains(slot.heroID))
        }
        XCTAssertEqual(config.humanSlot?.heroID, hero)
    }
}

@MainActor
final class FlowMatchModelTests: XCTestCase {
    private func profile() -> Profile {
        var p = Profile()
        p.displayName = "Tester"
        p.heroSpells["H003"] = ["BS07", "BS01"]
        return p
    }

    func testSpellEditing() {
        let m = MatchFlowModel(seed: 1)
        m.spells = ["BS01", "BS03"]
        m.setSpell("BS03", slot: 0)
        XCTAssertEqual(m.spells, ["BS03", "BS01"])
        m.setSpell("BS07", slot: 1)
        XCTAssertEqual(m.spells, ["BS03", "BS07"])
        XCTAssertEqual(MatchFlowModel.sanitizedSpells(["BS01", "BS01", "XX"], master: .shared), ["BS01", "BS03"])
        XCTAssertEqual(MatchFlowModel.sanitizedSpells([], master: .shared), ["BS01", "BS03"])
    }

    func testStandardConfig() throws {
        let p = profile()
        let m = MatchFlowModel(seed: 4242)
        m.configure(profile: p, master: .shared)
        m.difficulty = .hard
        m.startStandard()
        m.selectHero("H003", profile: p, master: .shared)
        XCTAssertEqual(m.position, .carry)
        XCTAssertEqual(m.spells, ["BS07", "BS01"])
        m.setPosition(.mid)
        let config = try XCTUnwrap(m.buildConfig(profile: p, master: .shared))
        XCTAssertEqual(config.mode, .standard)
        XCTAssertEqual(config.seed, 4242)
        let human = try XCTUnwrap(config.humanSlot)
        XCTAssertEqual(human.heroID, "H003")
        XCTAssertEqual(human.position, .mid)
        XCTAssertEqual(human.spells, ["BS07", "BS01"])
        XCTAssertEqual(human.displayName, "Tester")
        XCTAssertTrue(config.players.filter { $0.team == .red }.allSatisfy { $0.botDifficulty == .hard })
        XCTAssertTrue(config.players.filter { $0.team == .blue && $0.controller == .bot }.allSatisfy { $0.botDifficulty == .normal })
    }

    func testRankedConfigUsesDraftAndRankDifficulty() throws {
        var p = profile()
        p.rank.tier = .azureCrystal
        let m = MatchFlowModel(seed: 9)
        m.configure(profile: p, master: .shared)
        m.startRanked(profile: p)
        var d = try XCTUnwrap(m.draft)
        while let t = d.currentTurn {
            let choice = t.isPlayer ? (t.action == .ban ? "H012" : d.autoChoiceForPlayer(preferred: ["H001"])) : d.aiChoice()
            guard d.commit(choice) else { return XCTFail("ドラフトが進まない") }
        }
        m.draft = d
        let hero = try XCTUnwrap(d.playerPick?.heroID)
        m.selectHero(hero, profile: p, master: .shared)
        let config = try XCTUnwrap(m.buildConfig(profile: p, master: .shared))
        XCTAssertEqual(config.mode, .ranked)
        XCTAssertFalse(config.players.map(\.heroID).contains("H012"))
        let diffs = RankService.botDifficulty(for: p.rank)
        XCTAssertTrue(config.players.filter { $0.team == .red }.allSatisfy { $0.botDifficulty == diffs.enemy })
        for slot in config.players {
            XCTAssertEqual(d.heroID(team: slot.team, position: slot.position), slot.heroID)
        }
    }

    func testRuneIDsFromSelectedPage() {
        var p = profile()
        p.runePages = [RunePage(name: "A", primaryPath: .valor, runeIDs: ["RN01", "", "RN11"])]
        let m = MatchFlowModel(seed: 1)
        m.configure(profile: p, master: .shared)
        XCTAssertEqual(m.runeIDs(profile: p), ["RN01", "RN11"])
        m.runePageIndex = nil
        XCTAssertEqual(m.runeIDs(profile: p), [])
    }
}

final class FlowResultTests: XCTestCase {
    private func player(k: Int, d: Int, a: Int) -> PlayerSummary {
        var s = HeroScore()
        s.kills = k
        s.deaths = d
        s.assists = a
        s.damageToHeroes = 12_000
        s.towerDamage = 3_000
        s.healingDone = 4_000
        s.minionKills = 100
        s.monsterKills = 20
        return PlayerSummary(entityID: 1, team: .blue, heroID: "H003", displayName: "Tester", isHuman: true, position: .carry,
                             level: 12, items: [], score: s, mvpScore: 0, grade: "A", isMVP: true)
    }

    func testMVPBreakdownMatchesDesignFormula() {
        let b = MVPBreakdown.make(player(k: 5, d: 2, a: 7), won: true)
        // (5×3 + 7×2 − 2×1.5) + 12000/1000 + 3000/1500 + 4000/2000 + 120/20 + 3
        XCTAssertEqual(b.total, 51, accuracy: 0.0001)
        XCTAssertEqual(MVPBreakdown.make(player(k: 5, d: 2, a: 7), won: false).total, 48, accuracy: 0.0001)
    }

    func testAdviceIsBoundedAndNonEmpty() {
        let tips = MVPBreakdown.advice(player(k: 0, d: 9, a: 1), durationMinutes: 15)
        XCTAssertFalse(tips.isEmpty)
        XCTAssertLessThanOrEqual(tips.count, 3)
    }

    func testSupportMailEncoding() throws {
        let raw = "a b&c=d+e?\n日本語 #1"
        let enc = SupportMail.encode(raw)
        XCTAssertFalse(enc.contains(where: { " &=+?\n#".contains($0) }))
        XCTAssertEqual(enc.removingPercentEncoding, raw)
        let url = try XCTUnwrap(SupportMail.url(to: "support@velstria.example", subject: "件名 & test", body: raw))
        XCTAssertEqual(url.scheme, "mailto")
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.path, "support@velstria.example")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "subject" }?.value, "件名 & test")
        XCTAssertEqual(comps.queryItems?.first { $0.name == "body" }?.value, raw)
    }

    func testSupportBodyExcludesPersonalData() {
        let config = MatchFactory.standardMatch(humanHeroID: "H003", humanName: "SecretName", seed: 31)
        let summary = MatchSummary(mode: .standard, seed: 31, winner: .blue, endReason: .coreDestroyed, duration: 754,
                                   humanTeam: .blue, players: [player(k: 1, d: 1, a: 1)], teamKills: [10, 5], towersDestroyed: [6, 2])
        let body = SupportMail.body(category: .bug, message: "hello", summary: summary,
                                    launch: BattleLaunch(config: config), systemVersion: "26.0")
        XCTAssertTrue(body.contains("Seed: 31"))
        XCTAssertTrue(body.contains("12:34"))
        XCTAssertTrue(body.contains("hello"))
        XCTAssertFalse(body.contains("SecretName"))
        XCTAssertFalse(body.contains("Tester"))
    }

    func testFormatting() {
        XCTAssertEqual(FlowText.duration(754), "12:34")
        XCTAssertEqual(FlowText.duration(-3), "0:00")
        XCTAssertEqual(FlowText.duration(.nan), "0:00")
        XCTAssertEqual(FlowText.kda(1, 2, 3), "1 / 2 / 3")
        XCTAssertLessThan(FlowAccountXP.required(forLevel: 1), FlowAccountXP.required(forLevel: 10))
    }

    func testAccountXPBeforeIsReconstructed() {
        // レベルアップなし: 200 → 320
        XCTAssertEqual(FlowAccountXP.xpBefore(levelBefore: 3, levelAfter: 3, xpAfter: 320, gained: 120), 200)
        // Lv1 で 450 XP（必要 500）+120 → Lv2・70 XP
        let need1 = FlowAccountXP.required(forLevel: 1)
        XCTAssertEqual(FlowAccountXP.xpBefore(levelBefore: 1, levelAfter: 2, xpAfter: 450 + 120 - need1, gained: 120), 450)
        // 範囲外は丸める
        XCTAssertEqual(FlowAccountXP.xpBefore(levelBefore: 5, levelAfter: 5, xpAfter: 10, gained: 120), 0)
        XCTAssertLessThanOrEqual(FlowAccountXP.xpBefore(levelBefore: 1, levelAfter: 4, xpAfter: 99_999, gained: 1),
                                 FlowAccountXP.required(forLevel: 1))
    }

    func testLoadingProgressCurve() {
        var last = -1.0
        for i in 0...200 {
            let x = Double(i) / 200
            let v = LoadingScreenView.stalledProgress(x, stall: 0.45)
            XCTAssertGreaterThanOrEqual(v, last)
            XCTAssertLessThanOrEqual(v, 1)
            last = v
        }
        XCTAssertEqual(LoadingScreenView.stalledProgress(1, stall: 0.45), 1, accuracy: 1e-9)
    }

    func testHomeBadges() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var p = Profile()
        p.mail = [
            MailItem(date: now, title: "a", body: "", attachments: [MailAttachment(kind: .coin, amount: 100)]),
            MailItem(date: now, title: "b", body: "", read: true),
            MailItem(date: now, title: "c", body: "", attachments: [MailAttachment(kind: .gem, amount: 5)],
                     expiresAt: now.addingTimeInterval(-60)),
        ]
        XCTAssertEqual(HomeBadges.unreadMail(p, now: now), 1)
        XCTAssertEqual(HomeBadges.claimableMail(p, now: now), 1)
        p.lastFirstWinDayKey = LiveOpsService.dayKey(now)
        XCTAssertFalse(HomeBadges.firstWinAvailable(p, now: now))
        XCTAssertTrue(HomeBadges.firstWinAvailable(p, now: now.addingTimeInterval(86_400)))
    }
}
