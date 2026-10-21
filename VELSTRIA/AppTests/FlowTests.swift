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
        XCTAssertNil(PlayerNameRules.validate("Abcdefghijk2"))
        XCTAssertEqual(PlayerNameRules.validate("1234567890123"), .tooLong)
        // 長さが収まっても、電話番号のような数字の並び（連絡先）は使えない（OnlineSafetyTests にフィルタの詳細）
        XCTAssertEqual(PlayerNameRules.validate("123456789012"), .inappropriate)
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
    /// 全員分の名簿（ロールがそろい、AI の選択の幅が広い）。ゲームの既定は master.heroes（H025〜H034）。
    private let roster = MasterData.shared.allHeroes

    func testTurnOrder() {
        let t = DraftEngine.turns
        XCTAssertEqual(t.count, 10, "BAN は無い（2026-10-12 に廃止）")
        XCTAssertEqual(t.map(\.slotLabel), ["B1", "R1", "R2", "B2", "B3", "R3", "R4", "B4", "B5", "R5"])
        XCTAssertEqual(t.indices.filter { t[$0].isPlayer }, [0])
    }

    /// プレイヤーのピック以外を AI に任せて最後まで進める。希望ヒーローが取られていたら自動選択。
    static func runDraft(seed: UInt64, playerPick: String, roster: [HeroDef]? = MasterData.shared.allHeroes) -> DraftEngine {
        var d = DraftEngine(seed: seed, roster: roster)
        while let turn = d.currentTurn {
            let choice = turn.isPlayer ? d.autoChoiceForPlayer(preferred: [playerPick]) : d.aiChoice()
            guard d.commit(choice) else {
                XCTFail("手番 \(d.turnIndex) の確定に失敗")
                break
            }
        }
        return d
    }

    func testFullDraftIsValidAndDeterministic() {
        let a = Self.runDraft(seed: 777, playerPick: "H003")
        let b = Self.runDraft(seed: 777, playerPick: "H003")
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.isComplete)
        let picked = a.pickedHeroIDs
        XCTAssertEqual(picked.count, 10)
        XCTAssertEqual(Set(picked).count, 10)
        for team in Team.players {
            XCTAssertEqual(Set(a.picks(for: team).map(\.position)), Set(LanePosition.allCases))
        }
        XCTAssertEqual(a.playerPick?.heroID, "H003", "プレイヤーは最初の手番（B1）なので必ず取れる")
        XCTAssertEqual(a.playerPick?.position, .carry)   // Ranger → ボット

        let others = (1...5).map { Self.runDraft(seed: 777 &+ UInt64($0) * 1000, playerPick: "H003").pickedHeroIDs }
        XCTAssertTrue(others.contains { $0 != a.pickedHeroIDs }, "シードが違えば AI の選択も変わる")
    }

    /// 所持の制限は無く、取られていないヒーローなら誰でも選べる。AI の手番ではプレイヤーは選べない。
    func testPlayerRestrictions() {
        var d = DraftEngine(seed: 1, roster: roster)
        XCTAssertTrue(d.canPlayerSelect("H020"))
        XCTAssertFalse(d.commit("H999"))
        XCTAssertFalse(d.commit(nil), "ピックは省略できない")
        XCTAssertTrue(d.commit("H020"))
        XCTAssertFalse(d.canPlayerSelect("H001"), "AI の手番")
        XCTAssertEqual(d.autoChoiceForPlayer(preferred: ["H001"]), nil)
    }

    /// MLBB と同じく自分の手番は試合ごとに変わり、レーンを選んでいれば青の各手番のレーンを先に決める。
    func testPlayerSlotAndLanePlan() {
        let slots = Set((0..<40).map { DraftEngine.playerSlot(seed: UInt64($0) &* 7919) })
        XCTAssertTrue(slots.isSubset(of: Set(0...4)))
        XCTAssertGreaterThan(slots.count, 1, "シードで手番が変わる")
        var d = DraftEngine(seed: 5, roster: roster, playerSlot: 2, playerLane: .jungle)
        XCTAssertEqual(d.turns.indices.filter { d.turns[$0].isPlayer }, [4], "B3 は全体の 5 番目の手番")
        XCTAssertEqual(d.plannedLane(blueIndex: 2), .jungle)
        XCTAssertEqual(Set((0..<5).compactMap { d.plannedLane(blueIndex: $0) }), Set(LanePosition.allCases))
        while let turn = d.currentTurn {
            let choice = turn.isPlayer ? d.autoChoiceForPlayer(preferred: []) : d.aiChoice()
            XCTAssertTrue(d.commit(choice))
        }
        XCTAssertEqual(d.playerPick?.position, .jungle, "希望のレーン")
        // 味方の AI は受け持つレーンに合うロールを選ぶ
        for (i, pick) in d.picks(for: .blue).enumerated() where i != 2 {
            XCTAssertEqual(pick.position, d.plannedLane(blueIndex: i))
            let role = try? XCTUnwrap(d.role(of: pick.heroID))
            XCTAssertTrue(MatchFactory.preferredRoles(for: pick.position).contains(role!), "\(pick.heroID) が \(pick.position) に合わない")
        }
        XCTAssertEqual(Set(d.picks(for: .red).map(\.position)), Set(LanePosition.allCases))
    }

    /// レーン交換: 味方がまだ選んでいなければ応じる。ヒーロー交換: 両方が選んだ後、自分のヒーローが味方のレーンに合えば応じる。
    func testSwapRequests() {
        var d = DraftEngine(seed: 11, roster: roster, playerSlot: 0, playerLane: .mid)
        XCTAssertTrue(d.allyAcceptsLaneSwap(blueIndex: 3), "選ぶ前の味方は応じる")
        let theirs = d.plannedLane(blueIndex: 3)
        XCTAssertTrue(d.requestLaneSwap(blueIndex: 3))
        XCTAssertEqual(d.plannedLane(blueIndex: 0), theirs)
        XCTAssertEqual(d.plannedLane(blueIndex: 3), .mid)
        XCTAssertFalse(d.requestLaneSwap(blueIndex: 0), "自分とは交換しない")
        while let turn = d.currentTurn {
            let choice = turn.isPlayer ? d.autoChoiceForPlayer(preferred: []) : d.aiChoice()
            XCTAssertTrue(d.commit(choice))
        }
        let blue = d.picks(for: .blue)
        for j in 1..<5 {
            let before = d
            if d.allyAcceptsHeroSwap(blueIndex: j) {
                XCTAssertTrue(d.requestHeroSwap(blueIndex: j))
                XCTAssertEqual(d.picks(for: .blue)[0].heroID, blue[j].heroID)
                XCTAssertEqual(d.picks(for: .blue)[j].heroID, blue[0].heroID)
                XCTAssertEqual(d.picks(for: .blue).map(\.position), blue.map(\.position), "レーンはそのまま")
                break
            } else {
                XCTAssertFalse(d.requestHeroSwap(blueIndex: j))
                XCTAssertEqual(d, before, "断られたら何も変わらない")
            }
        }
    }

    /// 時間切れの自動選択は、よく使うヒーローを優先する（得意ヒーロー 3 体の並び）。
    func testFavoritesForAutoPick() {
        var p = Profile()
        p.career.perHero = ["H027": HeroCareer(matches: 5, wins: 1), "H025": HeroCareer(matches: 9, wins: 3),
                            "H030": HeroCareer(matches: 5, wins: 4), "H099": HeroCareer(matches: 50, wins: 50)]
        let roster = MasterData.shared.heroes.map(\.heroID)
        XCTAssertEqual(DraftShowcase.favorites(p, roster: roster), ["H025", "H030", "H027"], "試合数 → 勝ち数の順、名簿外は除く")
        let ai = DraftShowcase.aiFavorites(seed: 3, index: 1, lane: .carry)
        XCTAssertEqual(ai.count, 3)
        XCTAssertEqual(Set(ai).count, 3)
        XCTAssertEqual(ai, DraftShowcase.aiFavorites(seed: 3, index: 1, lane: .carry), "決定的")
    }

    func testQuickChatPhrasesAreStable() {
        // オンラインでは番号だけを送るので、並びを変えない（足すときは末尾へ）
        XCTAssertEqual(QuickChat.phrases.first?.ja, "よろしく！")
        XCTAssertEqual(QuickChat.text(99), "")
        XCTAssertNotNil(QuickChat.aiReply(to: 1))
        XCTAssertNil(QuickChat.aiReply(to: 7), "了解には返事をしない")
    }

    func testPositionSwapWithAlly() {
        var d = Self.runDraft(seed: 99, playerPick: "H003")
        XCTAssertEqual(d.playerPick?.position, .carry)
        let allyAtMid = d.heroID(team: .blue, position: .mid)
        XCTAssertNotNil(allyAtMid)
        d.setPlayerPosition(.mid)
        XCTAssertEqual(d.playerPick?.position, .mid)
        XCTAssertEqual(d.heroID(team: .blue, position: .carry), allyAtMid)
        XCTAssertEqual(Set(d.picks(for: .blue).map(\.position)), Set(LanePosition.allCases))
    }

    func testApplyDraftToConfig() throws {
        let d = Self.runDraft(seed: 2024, playerPick: "H003")
        let hero = try XCTUnwrap(d.playerPick?.heroID)
        var config = MatchFactory.standardMatch(mode: .ranked, humanHeroID: hero, humanName: "Tester",
                                                humanPosition: d.playerPick?.position, seed: 2024)
        d.apply(to: &config)
        XCTAssertEqual(config.players.count, 10)
        XCTAssertEqual(Set(config.players.map(\.heroID)).count, 10)
        for slot in config.players {
            XCTAssertEqual(d.heroID(team: slot.team, position: slot.position), slot.heroID)
        }
        XCTAssertEqual(config.humanSlot?.heroID, hero)
    }

    /// ゲームの既定の名簿（H025〜H034 の 10 体）でちょうど 10 ピックが埋まる。
    func testActiveRosterFillsAllPicks() {
        let d = Self.runDraft(seed: 20261001, playerPick: "H027", roster: nil)
        XCTAssertTrue(d.isComplete)
        XCTAssertEqual(d.playerPick?.heroID, "H027")
        XCTAssertEqual(Set(d.pickedHeroIDs), Set(HeroRoster.activeHeroIDs))
    }
}

@MainActor
final class FlowMatchModelTests: XCTestCase {
    private func profile() -> Profile {
        var p = Profile()
        p.displayName = "Tester"
        // 処刑（BS11）はアカウント Lv3 で解放（旧版の BS07 は選べなくなった）
        p.accountLevel = 30
        p.heroSpells["H003"] = ["BS11", "BS01"]
        return p
    }

    func testSpellEditing() {
        let m = MatchFlowModel(seed: 1)
        m.spells = ["BS01", "BS03"]
        m.setSpell("BS03", slot: 0)
        XCTAssertEqual(m.spells, ["BS01", "BS03"])
        m.setSpell("BS11", slot: 1)
        XCTAssertEqual(m.spells, ["BS01", "BS03"])
        m.setSpell("BS11", slot: 0)
        XCTAssertEqual(m.spells, ["BS11", "BS03"])
        XCTAssertEqual(MatchFlowModel.sanitizedSpells(["BS01", "BS01", "XX"], master: .shared), ["BS01", "BS03"])
        XCTAssertEqual(MatchFlowModel.sanitizedSpells(["BS03", "BS11"], master: .shared), ["BS11", "BS03"])
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
        XCTAssertEqual(m.spells, ["BS11", "BS03"])
        m.setPosition(.mid)
        let config = try XCTUnwrap(m.buildConfig(profile: p, master: .shared))
        XCTAssertEqual(config.mode, .standard)
        XCTAssertEqual(config.seed, 4242)
        let human = try XCTUnwrap(config.humanSlot)
        XCTAssertEqual(human.heroID, "H003")
        XCTAssertEqual(human.position, .mid)
        XCTAssertEqual(human.spells, ["BS11", "BS03"])
        XCTAssertEqual(human.displayName, "Tester")
        XCTAssertTrue(config.players.filter { $0.team == .red }.allSatisfy { $0.botDifficulty == .hard })
        XCTAssertTrue(config.players.filter { $0.team == .blue && $0.controller == .bot }.allSatisfy { $0.botDifficulty == .normal })
    }

    func testRankedConfigUsesDraftAndRankDifficulty() throws {
        var p = profile()
        p.rank.tier = .legend
        let m = MatchFlowModel(seed: 9)
        m.configure(profile: p, master: .shared)
        m.startRanked(profile: p)
        var d = try XCTUnwrap(m.draft)
        while let t = d.currentTurn {
            let choice = t.isPlayer ? d.autoChoiceForPlayer(preferred: ["H027"]) : d.aiChoice()
            guard d.commit(choice) else { return XCTFail("ドラフトが進まない") }
        }
        m.draft = d
        let hero = try XCTUnwrap(d.playerPick?.heroID)
        m.selectHero(hero, profile: p, master: .shared)
        let config = try XCTUnwrap(m.buildConfig(profile: p, master: .shared))
        XCTAssertEqual(config.mode, .ranked)
        let diffs = RankService.botDifficulty(for: p.rank)
        XCTAssertTrue(config.players.filter { $0.team == .red }.allSatisfy { $0.botDifficulty == diffs.enemy })
        for slot in config.players {
            XCTAssertEqual(d.heroID(team: slot.team, position: slot.position), slot.heroID)
        }
    }

    func testSkinMustBeOwnedAndMatchHero() throws {
        var p = profile()
        let skin = try XCTUnwrap(MasterData.shared.allCosmetics.first { $0.type == .heroSkin && $0.heroID == "H001" })
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
        XCTAssertEqual(m.heroID, HeroRoster.defaultHeroID, "未所持の前回ヒーローは使わず所持の先頭")
        p.lastPickedHeroID = "H027"
        p.preferredDifficulty = .hard
        let m2 = MatchFlowModel(seed: 1)
        m2.configure(profile: p, master: .shared)
        XCTAssertEqual(m2.heroID, "H027")
        XCTAssertEqual(m2.difficulty, .hard)
    }

    func testEmblemFromBulkApplyOrBattlePlan() {
        var p = profile()
        // 全セット解放済みの Lv60（旧版から引き継いだプレイヤー）。新規のプレイヤーは EmblemEconomyTests
        EmblemService.grandfather(&p)
        p.lastPickedHeroID = "H027"
        let m = MatchFlowModel(seed: 1)
        m.configure(profile: p, master: .shared)
        // 一括設定が無ければ「有効」のバトルプランのエンブレム（Lv60）
        XCTAssertEqual(m.emblem(profile: p, master: .shared), ItemSystem.plan(heroID: "H027", chosen: nil)?.emblem)
        let tank = EmblemCatalog.defaultLoadout(set: .tank)
        EmblemMath.apply(set: .tank, to: ["H027"], profile: &p)
        XCTAssertEqual(m.emblem(profile: p, master: .shared), tank)
        XCTAssertEqual(m.buildConfig(profile: p, master: .shared)?.humanSlot?.emblem, tank)
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
        // 赤い点は受け取っていない添付のあるメールだけ（未読でも添付が無ければ付かない。MLBB 2.2.16）
        XCTAssertEqual(HomeBadges.mail(p, now: now), 1)
        XCTAssertEqual(HomeBadges.claimableMail(p, now: now), 1)
        p.mail[0].read = true
        XCTAssertEqual(HomeBadges.mail(p, now: now), 1, "既読でも受け取るまで付く")
        p.mail[0].claimed = true
        XCTAssertEqual(HomeBadges.mail(p, now: now), 0)
        p.mail.append(MailItem(date: now, title: "d", body: ""))
        XCTAssertEqual(HomeBadges.mail(p, now: now), 0, "添付の無い未読には付かない")
        // スターパス: 到達した段の未受取の報酬
        XCTAssertEqual(HomeBadges.starPass(p), 0)
        LiveOpsService.addPassXP(LiveOpsService.passXPPerLevel * 2, to: &p)
        XCTAssertGreaterThan(HomeBadges.starPass(p), 0)
        p.lastFirstWinDayKey = LiveOpsService.dayKey(now)
        XCTAssertFalse(HomeBadges.firstWinAvailable(p, now: now))
        XCTAssertTrue(HomeBadges.firstWinAvailable(p, now: now.addingTimeInterval(86_400)))
    }
}

// MARK: - レビュー修正の回帰テスト

final class FlowReviewFixTests: XCTestCase {
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

/// レーン選択（MLBB 2.2.16: 2〜5 本。必要なレーンは 1 本で確定。フレックスプロ）とモード選択のタイル。
final class FlowLaneAndModeTests: XCTestCase {
    func testLaneSelectionNeedsTwoLanesUnlessNeededOrFlex() {
        let needed = LanePosition.support
        XCTAssertTrue(LaneSelectRules.canConfirm(lanes: [], flex: true, needed: needed), "フレックスプロ")
        XCTAssertFalse(LaneSelectRules.canConfirm(lanes: [], flex: false, needed: needed))
        XCTAssertFalse(LaneSelectRules.canConfirm(lanes: [.mid], flex: false, needed: needed))
        XCTAssertTrue(LaneSelectRules.canConfirm(lanes: [.support], flex: false, needed: needed), "必要なレーンは 1 本で確定")
        XCTAssertTrue(LaneSelectRules.canConfirm(lanes: [.mid, .top], flex: false, needed: needed))
        XCTAssertEqual(LaneSelectRules.order, [.top, .jungle, .mid, .support, .carry], "MLBB の並び（Exp・ジャングル・ミドル・ローム・ゴールド）")
        XCTAssertTrue(LaneSelectRules.order.contains(LaneSelectRules.neededLane(seed: 12_345)))
    }

    func testLaneChoicesRoundTripAndFallBackToFlex() {
        XCTAssertEqual(LaneSelectRules.encode(lanes: [.mid, .top], flex: false), "2,0")
        XCTAssertEqual(LaneSelectRules.decode("2,0").lanes, [.mid, .top])
        XCTAssertFalse(LaneSelectRules.decode("2,0").flex)
        XCTAssertTrue(LaneSelectRules.decode("flex").flex)
        XCTAssertTrue(LaneSelectRules.decode("").flex)
        XCTAssertTrue(LaneSelectRules.decode("x,9").flex, "読めない値はフレックスプロ")
        XCTAssertEqual(LaneSelectRules.decode("1,1,3").lanes, [.jungle, .carry], "重複は 1 つに")
    }

    func testModeTilesFollowTheJapaneseClient() {
        let saved = Loc.current
        defer { Loc.current = saved }
        Loc.current = .ja
        XCTAssertEqual(MatchModeCategory.allCases.map(\.title),
                       ["ランキング", "マッチング", "乱闘", "アーケード", "マジックチェス", "ライジング", "AI対戦とカスタム"])
        XCTAssertEqual(MatchModeCategory.playTitle("ranked"), "ランキング")
        XCTAssertNil(MatchModeCategory.playTitle(nil))
        XCTAssertNil(MatchModeCategory.playTitle("bogus"))
        XCTAssertEqual(Set(MatchModeCategory.allCases.map(\.identifier)).count, MatchModeCategory.allCases.count)
        XCTAssertEqual(ModeTileLayout.mythicNext(36), 50)
        XCTAssertEqual(ModeTileLayout.mythicNext(0), 25)
        XCTAssertNil(ModeTileLayout.mythicNext(100))
        // 菱形は重ならない（中心の L1 距離 ≥ 半径の和）
        let tiles = MatchModeCategory.allCases
        for (i, a) in tiles.enumerated() {
            for b in tiles[(i + 1)...] {
                let d = abs(a.spot.center.x - b.spot.center.x) + abs(a.spot.center.y - b.spot.center.y)
                XCTAssertGreaterThanOrEqual(d, a.spot.radius + b.spot.radius, "\(a) と \(b) が重なる")
            }
        }
    }
}

/// UI テストと共有するシード（UI テストのターゲットはアプリ本体を import できないため文字列で持つ）。
enum FlowUITestsSeed {
    static let draft = "20261001"
}
