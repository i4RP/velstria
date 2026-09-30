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

    func testSkinMustBeOwnedAndMatchHero() throws {
        var p = profile()
        let skin = try XCTUnwrap(MasterData.shared.cosmetics.first { $0.type == .heroSkin && $0.heroID == "H001" })
        p.equippedSkins["H001"] = skin.cosmeticID
        let m = MatchFlowModel(seed: 1)
        m.selectHero("H001", profile: p, master: .shared)
        XCTAssertNil(m.skinID, "未所持のスキンは装備しない")
        p.ownedCosmeticIDs = [skin.cosmeticID]
        m.selectHero("H001", profile: p, master: .shared)
        XCTAssertEqual(m.skinID, skin.cosmeticID)
        m.startStandard()
        let config = m.buildConfig(profile: p, master: .shared)
        XCTAssertEqual(config?.humanSlot?.skinID, skin.cosmeticID)
        // 別ヒーローへ切り替えると、そのヒーローの保存値（未設定）に戻る
        m.selectHero("H003", profile: p, master: .shared)
        XCTAssertNil(m.skinID)
    }

    func testConfigureStartsFromLastPickedOwnedHero() {
        var p = profile()
        p.lastPickedHeroID = "H020"
        let m = MatchFlowModel(seed: 1)
        m.configure(profile: p, master: .shared)
        XCTAssertEqual(m.heroID, "H001", "未所持の前回ヒーローは使わず所持の先頭")
        p.lastPickedHeroID = "H004"
        p.preferredDifficulty = .hard
        let m2 = MatchFlowModel(seed: 1)
        m2.configure(profile: p, master: .shared)
        XCTAssertEqual(m2.heroID, "H004")
        XCTAssertEqual(m2.difficulty, .hard)
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
        let enc = ReportMail.encode(raw)
        XCTAssertFalse(enc.contains(where: { " &=+?\n#".contains($0) }))
        XCTAssertEqual(enc.removingPercentEncoding, raw)
        let url = try XCTUnwrap(ReportMail.url(to: "support@velstria.example", subject: "件名 & test", body: raw))
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
        let body = ReportMail.body(category: .bug, message: "hello", summary: summary,
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
        XCTAssertEqual(FlowText.compactNumber(9_876), 9_876.formatted())
        XCTAssertEqual(FlowText.compactNumber(12_345), "12.3k")
        XCTAssertEqual(FlowText.compactNumber(1_000_000), "1.0M")
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

// MARK: - レビュー修正の回帰テスト

final class FlowReviewFixTests: XCTestCase {
    /// 所持ヒーローが 1 体だけでも、BAN でピック候補が無くならずドラフトが最後まで進む。
    func testDraftNeverStrandsPlayerWithSingleOwnedHero() {
        for seed in UInt64(0)..<40 {
            var d = DraftEngine(seed: seed, ownedHeroIDs: ["H003"])
            // プレイヤー自身も最後の所持ヒーローは BAN できない
            XCTAssertFalse(d.canPlayerSelect("H003"))
            XCTAssertTrue(d.canPlayerSelect("H004"))
            XCTAssertFalse(d.commit("H003"))
            XCTAssertTrue(d.commit(nil))
            while let t = d.currentTurn {
                let choice = t.isPlayer ? d.autoChoiceForPlayer(preferred: ["H003"]) : d.aiChoice()
                guard d.commit(choice) else { return XCTFail("seed \(seed): 手番 \(d.turnIndex) で停止") }
            }
            XCTAssertFalse(d.bannedHeroIDs.contains("H003"), "seed \(seed)")
            XCTAssertEqual(d.playerPick?.heroID, "H003", "seed \(seed)")
        }
    }

    /// 所持ヒーローが無い（壊れた復元データ）場合も、空いているヒーローでピックでき、ドラフトが止まらない。
    func testDraftFallsBackWhenNoOwnedHeroIsAvailable() {
        var d = DraftEngine(seed: 7, ownedHeroIDs: [])
        while let t = d.currentTurn {
            let choice = t.isPlayer ? (t.action == .ban ? nil : d.autoChoiceForPlayer(preferred: [])) : d.aiChoice()
            guard d.commit(choice) else { return XCTFail("手番 \(d.turnIndex) で停止") }
        }
        XCTAssertTrue(d.isComplete)
        XCTAssertNotNil(d.playerPick)
        XCTAssertEqual(Set(d.pickedHeroIDs).count, 10)
    }

    /// UI テスト（FlowUITests.testRankedDraft）が前提にするシードの AI BAN。
    func testUITestDraftSeedKeepsH003Available() throws {
        let seed = try XCTUnwrap(UInt64(FlowUITestsSeed.draft))
        var d = DraftEngine(seed: seed, ownedHeroIDs: Profile().ownedHeroIDs)
        XCTAssertTrue(d.commit("H010"))
        while let t = d.currentTurn, t.action == .ban { XCTAssertTrue(d.commit(d.aiChoice())) }
        XCTAssertFalse(d.bannedHeroIDs.contains("H003"))
        XCTAssertTrue(d.canPlayerSelect("H003"))
    }

    func testBackupRestoreKeepsDevicePurchaseRecordsAndAge() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var current = Profile()
        current.displayName = "NewPhone"
        current.ageBracket = .age13to15
        current.acceptedTermsVersion = 3
        current.onboardingCompleted = true
        current.firstResourcePrepared = true
        current.monthlySpendJPY = ["2027-01": 4_000, "2027-02": 800]
        current.purchaseLedger = [
            PurchaseRecord(transactionID: 2, productID: "gem.300", gemsGranted: 330, priceJPY: 800, date: t0.addingTimeInterval(60)),
            PurchaseRecord(transactionID: 3, productID: "gem.60", gemsGranted: 60, priceJPY: 160, date: t0.addingTimeInterval(120), revoked: true),
        ]
        var backup = Profile()
        backup.displayName = "OldPhone"
        backup.ageBracket = .adult
        backup.acceptedTermsVersion = 1
        backup.onboardingCompleted = true
        backup.firstResourcePrepared = false
        backup.starlightCoin = 12_345
        backup.monthlySpendJPY = ["2027-01": 160, "2026-12": 2_500]
        backup.purchaseLedger = [
            PurchaseRecord(transactionID: 1, productID: "gem.980", gemsGranted: 1090, priceJPY: 2500, date: t0),
            PurchaseRecord(transactionID: 3, productID: "gem.60", gemsGranted: 60, priceJPY: 160, date: t0.addingTimeInterval(120)),
        ]

        let merged = BackupRestore.merged(imported: backup, current: current)
        // 復元したいデータはバックアップのもの
        XCTAssertEqual(merged.displayName, "OldPhone")
        XCTAssertEqual(merged.starlightCoin, 12_345)
        XCTAssertEqual(merged.playerID, backup.playerID)
        // 年齢区分・課金の記録は巻き戻さない
        XCTAssertEqual(merged.ageBracket, .age13to15)
        XCTAssertEqual(merged.monthlySpendJPY, ["2027-01": 4_000, "2027-02": 800, "2026-12": 2_500])
        XCTAssertEqual(merged.purchaseLedger.map(\.transactionID), [1, 2, 3])
        XCTAssertEqual(merged.purchaseLedger.last?.revoked, true)
        // 同意済みの規約は戻さない・初回準備は端末の値
        XCTAssertEqual(merged.acceptedTermsVersion, 3)
        XCTAssertTrue(merged.firstResourcePrepared)
        XCTAssertTrue(merged.onboardingCompleted)

        // 名前が壊れたバックアップは現在の名前を使う
        backup.displayName = " "
        XCTAssertEqual(BackupRestore.merged(imported: backup, current: current).displayName, "NewPhone")
    }

    /// バックアップの JSON を書き換えても、課金台帳で裏付けられない有償 Gem・プレミアムは付かない。
    func testBackupRestoreCapsPaidItemsToPurchaseLedger() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let gem980 = "com.bitcoinpay.velstria.gem.980"   // 980 + 110 = 1,090 個
        let gem60 = "com.bitcoinpay.velstria.gem.60"
        let current = Profile()

        // 正規のバックアップ（購入 1,090 個のうち 90 個使用）はそのまま戻る
        var legit = Profile()
        legit.paidGem = 1_000
        legit.purchaseLedger = [PurchaseRecord(transactionID: 10, productID: gem980, gemsGranted: 1_090, priceJPY: 2500, date: t0)]
        XCTAssertEqual(BackupRestore.merged(imported: legit, current: current).paidGem, 1_000)

        // 残高だけ書き換えたもの → 台帳の付与合計まで
        var edited = legit
        edited.paidGem = 999_999
        edited.pass.hasPremium = true
        let merged = BackupRestore.merged(imported: edited, current: current)
        XCTAssertEqual(merged.paidGem, 1_090)
        XCTAssertFalse(merged.pass.hasPremium, "台帳にプレミアムの購入が無い")

        // 付与数の書き換え・未知の商品・同じ取引の重複は数えない
        var forged = Profile()
        forged.paidGem = 50_000
        forged.purchaseLedger = [
            PurchaseRecord(transactionID: 20, productID: gem60, gemsGranted: 99_999, priceJPY: 160, date: t0),
            PurchaseRecord(transactionID: 21, productID: "com.example.fake", gemsGranted: 5_000, priceJPY: 0, date: t0),
            PurchaseRecord(transactionID: 22, productID: gem60, gemsGranted: 60, priceJPY: 160, date: t0),
            PurchaseRecord(transactionID: 22, productID: gem60, gemsGranted: 60, priceJPY: 160, date: t0),
        ]
        // gem.60 の取引 20 は 60 個 × 最大数量 10 まで、取引 22 は重複を 1 回だけ
        XCTAssertEqual(BackupRestore.merged(imported: forged, current: current).paidGem, 660)

        // この端末で取り消し（返金）済みの取引の分は戻らない
        var refundedHere = Profile()
        refundedHere.purchaseLedger = [PurchaseRecord(transactionID: 10, productID: gem980, gemsGranted: 0, priceJPY: 0, date: t0, revoked: true)]
        XCTAssertEqual(BackupRestore.merged(imported: legit, current: refundedHere).paidGem, 0)

        // プレミアムは台帳（バックアップ側・この端末側のどちらか）に有効な購入があれば引き継ぐ
        var premium = Profile()
        premium.pass.hasPremium = true
        premium.purchaseLedger = [PurchaseRecord(transactionID: 30, productID: StoreKitService.premiumPassProductID,
                                                 gemsGranted: 0, priceJPY: 980, date: t0)]
        XCTAssertTrue(BackupRestore.merged(imported: premium, current: current).pass.hasPremium)
        XCTAssertTrue(BackupRestore.merged(imported: Profile(), current: premium).pass.hasPremium)
        var premiumRefunded = premium
        premiumRefunded.purchaseLedger[0].revoked = true
        XCTAssertFalse(BackupRestore.merged(imported: premium, current: premiumRefunded).pass.hasPremium)
    }

    func testDateFormattingFollowsLanguage() {
        let saved = Loc.current
        defer { Loc.current = saved }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .current
        let d = utc.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 7, minute: 5))!
        Loc.current = .ja
        XCTAssertEqual(FlowText.date(d), "2026/09/29 07:05")
        XCTAssertEqual(FlowText.date(d, time: false), "2026/09/29")
        Loc.current = .en
        XCTAssertEqual(FlowText.date(d), "Sep 29, 2026 07:05")
        XCTAssertEqual(FlowText.date(d, time: false), "Sep 29, 2026")
        Loc.current = .ja
        XCTAssertEqual(FlowText.date(d, time: false), "2026/09/29", "言語を戻すと書式も戻る")
    }
}

/// UI テストと共有するシード（UI テストのターゲットはアプリ本体を import できないため文字列で持つ）。
enum FlowUITestsSeed {
    static let draft = "20261001"
}
