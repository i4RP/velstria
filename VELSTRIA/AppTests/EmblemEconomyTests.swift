import XCTest
@testable import VELSTRIA
import VelstriaCore

/// エンブレムの解放・強化・欠片・無料の宝箱・入手（Services/EmblemService.swift。docs/EMBLEMS.md「解放・レベル・入手」）。
/// 数値の表そのもの（費用・能力値・天賦の解放レベル・宝箱の時計・1 週間の見込み）は VelstriaCore の EmblemProgressionTests。
final class EmblemEconomyTests: XCTestCase {
    private var dirs: [URL] = []

    override func setUp() {
        super.setUp()
        Loc.current = .ja
    }

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        dirs = []
        super.tearDown()
    }

    private func persistence() -> PersistenceService {
        let s = ServicesFixtures.tempPersistence()
        dirs.append(s.directory)
        return s
    }

    // MARK: - 新規と旧版

    func testNewProfileStartsWithOnlyCommonAtLevelOne() {
        let p = Profile()
        XCTAssertFalse(p.emblemGrandfathered)
        XCTAssertEqual(p.magicDust, 0)
        XCTAssertTrue(p.emblemFragments.isEmpty)
        for set in EmblemSetID.allCases {
            XCTAssertEqual(EmblemService.isUnlocked(set, profile: p), set == .common, "\(set)")
            XCTAssertEqual(EmblemService.level(set, profile: p), 1)
        }
        XCTAssertNil(EmblemService.upgradeQuote(.tank, profile: p), "未解放は強化できない")
        XCTAssertEqual(EmblemService.upgradeQuote(.common, profile: p), EmblemUpgradeQuote(needed: 30, fromFragments: 0, fromDust: 0))
        XCTAssertFalse(EmblemService.canImprove(.common, profile: p))
        // 試合: 「有効」のプランのセット（H027 = アサシン）が未解放なので通常共通の Lv1。Lv1 は天賦がどれも働かない
        let e = EmblemMath.loadout(for: "H027", profile: p, master: .shared)
        XCTAssertEqual(e?.set, .common)
        XCTAssertEqual(e?.level, 1)
        XCTAssertNil(e?.activeTier1)
        XCTAssertNil(e?.activeTier2)
        XCTAssertNil(e?.activeCore)
    }

    func testOldProfilesKeepEverySetUnlockedAtTheirLevel() throws {
        let s = persistence()
        var p = Profile()
        p.displayName = "Tester"
        p.emblemSetProgress[EmblemSetID.mage.rawValue] = EmblemSetProgress(unlocked: true, level: 37)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        // schemaVersion 3（解放・レベルより前）の保存: 新しいキーは無い
        object["schemaVersion"] = 3
        for key in ["magicDust", "emblemFragments", "emblemChest", "emblemGrandfathered"] { object.removeValue(forKey: key) }
        let v3 = try s.decodeProfile(JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(v3.emblemGrandfathered)
        XCTAssertEqual(v3.schemaVersion, PersistenceService.currentSchemaVersion)
        for set in EmblemSetID.allCases {
            XCTAssertTrue(EmblemService.isUnlocked(set, profile: v3), "\(set)")
            XCTAssertEqual(EmblemService.level(set, profile: v3), set == .mage ? 37 : 60, "保存されていたレベルは残す \(set)")
            XCTAssertEqual(v3.emblemSetProgress[set.rawValue]?.unlocked, true, "移行で全セットを書き込む")
        }
        XCTAssertEqual(v3.magicDust, 0)
        XCTAssertEqual(v3.emblemChest, EmblemChestState())
        // 試合のエンブレムも今までどおり（H027 の「有効」のプラン = アサシン Lv60）
        XCTAssertEqual(EmblemMath.loadout(for: "H027", profile: v3, master: .shared), ItemSystem.plan(heroID: "H027", chosen: nil)?.emblem)
        // もっと古い版（v1）も同じ
        object["schemaVersion"] = 1
        let v1 = try s.decodeProfile(JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(v1.emblemGrandfathered)
        XCTAssertTrue(EmblemService.isUnlocked(.marksman, profile: v1))
        // 今の版の新規の保存は旧版扱いにならない
        let fresh = try s.decodeProfile(JSONEncoder().encode(Profile()))
        XCTAssertFalse(fresh.emblemGrandfathered)
        XCTAssertFalse(EmblemService.isUnlocked(.tank, profile: fresh))
        XCTAssertEqual(EmblemService.level(.common, profile: fresh), 1)
    }

    func testSanitizeDropsBrokenEmblemWallets() {
        var p = Profile()
        p.magicDust = -5
        p.emblemFragments = [EmblemSetID.common.rawValue: 10, "EM_BOGUS": 3, EmblemSetID.tank.rawValue: -2,
                             EmblemSetID.mage.rawValue: 7]
        p.emblemSetProgress[EmblemSetID.common.rawValue] = EmblemSetProgress(unlocked: false, level: 4)
        p.emblemChest.charges = 9
        PersistenceService.sanitize(&p)
        XCTAssertEqual(p.magicDust, 0)
        XCTAssertEqual(p.emblemFragments, [EmblemSetID.mage.rawValue: 7])
        XCTAssertEqual(p.emblemSetProgress[EmblemSetID.common.rawValue], EmblemSetProgress(unlocked: true, level: 4),
                       "通常共通はいつでも解放済み")
        XCTAssertEqual(p.emblemChest.charges, EmblemEconomy.chestMaxCharges)
    }

    // MARK: - 解放・強化

    func testUnlockCostsDustAndStartsAtLevelOne() {
        var p = Profile()
        XCTAssertFalse(EmblemService.canUnlock(.tank, profile: p))
        XCTAssertFalse(EmblemService.unlock(.tank, profile: &p), "魔法の粉が足りない")
        p.magicDust = EmblemEconomy.unlockCost + 20
        XCTAssertTrue(EmblemService.canImprove(.tank, profile: p), "タブの上向きの矢印")
        XCTAssertTrue(EmblemService.unlock(.tank, profile: &p))
        XCTAssertEqual(p.magicDust, 20)
        XCTAssertEqual(EmblemService.progress(.tank, profile: p), EmblemSetProgress(unlocked: true, level: 1))
        XCTAssertFalse(EmblemService.unlock(.tank, profile: &p), "解放済み")
        XCTAssertFalse(EmblemService.unlock(.common, profile: &p), "通常共通は最初から")
        XCTAssertEqual(p.magicDust, 20)
    }

    func testUpgradeSpendsFragmentsBeforeDust() {
        var p = Profile()
        p.emblemSetProgress[EmblemSetID.assassin.rawValue] = EmblemSetProgress(unlocked: true, level: 26)
        p.emblemFragments[EmblemSetID.assassin.rawValue] = 10
        p.magicDust = 300
        // 画面の「10+217/227」（アサシン 26→27）
        let q = EmblemService.upgradeQuote(.assassin, profile: p)
        XCTAssertEqual(q, EmblemUpgradeQuote(needed: 227, fromFragments: 10, fromDust: 217))
        XCTAssertEqual(q.map { EmblemMath.costText($0, set: .assassin) }, "10+217/227")
        XCTAssertTrue(EmblemService.upgrade(.assassin, profile: &p))
        XCTAssertEqual(EmblemService.level(.assassin, profile: p), 27)
        XCTAssertEqual(EmblemService.fragments(.assassin, profile: p), 0)
        XCTAssertNil(p.emblemFragments[EmblemSetID.assassin.rawValue], "使い切った欠片は消す")
        XCTAssertEqual(p.magicDust, 83)
        // 欠片だけで足りれば魔法の粉は使わない（27→28 = 280）
        p.emblemFragments[EmblemSetID.assassin.rawValue] = 500
        XCTAssertTrue(EmblemService.upgrade(.assassin, profile: &p))
        XCTAssertEqual(EmblemService.fragments(.assassin, profile: p), 220)
        XCTAssertEqual(p.magicDust, 83)
        // 足りなければ何も減らない（28→29 = 337 > 100 + 83）
        p.emblemFragments[EmblemSetID.assassin.rawValue] = 100
        XCTAssertFalse(EmblemService.canUpgrade(.assassin, profile: p))
        XCTAssertFalse(EmblemService.upgrade(.assassin, profile: &p))
        XCTAssertEqual(EmblemService.level(.assassin, profile: p), 28)
        XCTAssertEqual(EmblemService.fragments(.assassin, profile: p), 100)
        XCTAssertEqual(p.magicDust, 83)
        XCTAssertEqual(EmblemService.upgradeQuote(.assassin, profile: p).map { EmblemMath.costText($0, set: .assassin) }, "100+83/337")
        // 通常共通は魔法の粉だけ（表示も「粉/必要」）
        p.magicDust = 30
        XCTAssertEqual(EmblemService.upgradeQuote(.common, profile: p).map { EmblemMath.costText($0, set: .common) }, "30/30")
        XCTAssertTrue(EmblemService.upgrade(.common, profile: &p))
        XCTAssertEqual(EmblemService.level(.common, profile: p), 2)
        XCTAssertEqual(p.magicDust, 0)
    }

    func testMaxLevelHasNoUpgradeAndFragmentsTurnIntoDust() {
        var p = Profile()
        p.emblemSetProgress[EmblemSetID.tank.rawValue] = EmblemSetProgress(unlocked: true, level: 59)
        p.emblemFragments[EmblemSetID.tank.rawValue] = 2000
        XCTAssertTrue(EmblemService.upgrade(.tank, profile: &p), "59→60 = 1583 を欠片で払う")
        XCTAssertTrue(EmblemService.isMaxLevel(.tank, profile: p))
        XCTAssertEqual(p.magicDust, 2000 - 1583, "最大になったら残りの欠片は魔法の粉に")
        XCTAssertEqual(EmblemService.fragments(.tank, profile: p), 0)
        XCTAssertNil(EmblemService.upgradeQuote(.tank, profile: p), "MAX")
        XCTAssertFalse(EmblemService.upgrade(.tank, profile: &p))
        XCTAssertFalse(EmblemService.canImprove(.tank, profile: p))
        XCTAssertNil(EmblemMath.nextKeyLevelText(.tank, level: 60))
        // 最大のセットの欠片は受け取った時に魔法の粉に
        let before = p.magicDust
        let got = LiveOpsService.grantResolved(EmblemService.fragmentAttachment(40, set: .tank), to: &p)
        XCTAssertEqual(got, EmblemService.dustAttachment(40))
        XCTAssertEqual(p.magicDust, before + 40)
        XCTAssertEqual(EmblemService.fragments(.tank, profile: p), 0)
        // 通常共通の欠片も魔法の粉（通常共通は欠片を使わない）
        XCTAssertEqual(LiveOpsService.grantResolved(EmblemService.fragmentAttachment(5, set: .common), to: &p).kind, .magicDust)
        // ほかのセットは欠片のまま（未解放でも貯められる）
        let frag = LiveOpsService.grantResolved(EmblemService.fragmentAttachment(15, set: .mage), to: &p)
        XCTAssertEqual(frag, EmblemService.fragmentAttachment(15, set: .mage))
        XCTAssertEqual(EmblemService.fragments(.mage, profile: p), 15)
        // 知らないセットの欠片は何もしない
        let dust = p.magicDust
        let bogus = LiveOpsService.grantResolved(MailAttachment(kind: .emblemFragment, amount: 9, refID: "EM_BOGUS"), to: &p)
        XCTAssertEqual(bogus.amount, 0)
        XCTAssertEqual(p.magicDust, dust)
        // 旧版から引き継いだプレイヤーは全部最大なので、欠片はすべて魔法の粉
        var old = Profile()
        EmblemService.grandfather(&old)
        XCTAssertEqual(LiveOpsService.grantResolved(EmblemService.fragmentAttachment(10, set: .support), to: &old).kind, .magicDust)
        XCTAssertEqual(old.magicDust, 10)
    }

    // MARK: - 天賦の解放と表示

    func testTalentTiersLockBelowTheirLevel() {
        var p = Profile()
        p.emblemSetProgress[EmblemSetID.tank.rawValue] = EmblemSetProgress(unlocked: true, level: 12)
        XCTAssertTrue(EmblemMath.isTierUnlocked(.tier1, set: .tank, profile: p))
        XCTAssertFalse(EmblemMath.isTierUnlocked(.tier2, set: .tank, profile: p))
        XCTAssertFalse(EmblemMath.isTierUnlocked(.core, set: .tank, profile: p))
        XCTAssertEqual(EmblemMath.tierLockText(.tier1), "Lv10で解放")
        XCTAssertEqual(EmblemMath.tierLockText(.tier2), "Lv15で解放")
        XCTAssertEqual(EmblemMath.tierLockText(.core), "Lv20で解放")
        // 解放した段は付け替えられ（費用は無い）、未解放の段は変わらない
        let dust = p.magicDust
        EmblemMath.equip(.fatal, set: .tank, profile: &p)
        EmblemMath.equip(.weaponMaster, set: .tank, profile: &p)
        EmblemMath.equip(.weaknessFinder, set: .tank, profile: &p)
        let page = EmblemMath.page(.tank, profile: p)
        XCTAssertEqual(page, EmblemLoadout(.tank, .fatal, .tenacity, .concussiveBlast, level: 12))
        XCTAssertEqual(p.magicDust, dust)
        // 試合: 解放した段だけ働く
        XCTAssertEqual(page.activeTier1, .fatal)
        XCTAssertNil(page.activeTier2)
        XCTAssertNil(page.activeCore)
    }

    func testUpgradeTexts() {
        // 次のキーレベル（「Lv30 コア属性大幅アップ 最大HP」。HP は「最大HP」）
        XCTAssertEqual(EmblemMath.nextKeyLevelText(.tank, level: 28), "Lv30 コア属性大幅アップ 最大HP")
        XCTAssertEqual(EmblemMath.nextKeyLevelText(.assassin, level: 26), "Lv30 コア属性大幅アップ 適応貫通")
        XCTAssertEqual(EmblemMath.nextKeyLevelText(.common, level: 42), "Lv45 コア属性大幅アップ 混合回復")
        XCTAssertEqual(EmblemMath.nextKeyLevelText(.support, level: 30), "Lv45 コア属性大幅アップ 回復効果")
        // 次のレベルで変わる値（アサシン Lv26 → 27 は移動速度だけ +1.20% → +1.30%）
        let a = EmblemCatalog.set(.assassin).attributes
        XCTAssertEqual(EmblemMath.attributeValue(a[2], level: 26), "+1.20%")
        XCTAssertEqual(EmblemMath.nextValueText(a[2], level: 26), "+1.30%")
        XCTAssertNil(EmblemMath.nextValueText(a[0], level: 26))
        XCTAssertNil(EmblemMath.nextValueText(a[1], level: 26))
        XCTAssertNil(EmblemMath.nextValueText(a[2], level: 60), "MAX")
        XCTAssertEqual(EmblemMath.currentMaxText(EmblemCatalog.set(.tank).attributes[0], level: 28), "+140.00 / 500.00")
        XCTAssertEqual(EmblemMath.shortSetName(.marksman), "ハンター")
        Loc.current = .en
        XCTAssertEqual(EmblemMath.tierLockText(.core), "Unlocks at Lv20")
        XCTAssertEqual(EmblemMath.nextKeyLevelText(.tank, level: 28), "Lv30: Core stat boost — Max HP")
        Loc.current = .ja
    }

    // MARK: - 試合

    func testHumanLoadoutCarriesThePlayerLevelWhileBotsStayAtSixty() {
        var p = Profile()
        p.emblemSetProgress[EmblemSetID.assassin.rawValue] = EmblemSetProgress(unlocked: true, level: 26)
        let e = EmblemMath.loadout(for: "H027", profile: p, master: .shared)
        XCTAssertEqual(e?.set, .assassin)
        XCTAssertEqual(e?.level, 26)
        let cfg = MatchFactory.standardMatch(humanHeroID: "H027", humanName: "P", humanEmblem: e, seed: 1)
        XCTAssertEqual(cfg.humanSlot?.emblem?.level, 26)
        XCTAssertTrue(cfg.players.filter { $0.controller == .bot }.allSatisfy { $0.emblem?.level == 60 })
        // 一括設定で付けた 1 式も今のレベルで使う
        EmblemMath.apply(set: .assassin, to: ["H030"], profile: &p)
        XCTAssertEqual(EmblemMath.custom(for: "H030", profile: p)?.level, 26)
        p.emblemSetProgress[EmblemSetID.assassin.rawValue]?.level = 31
        XCTAssertEqual(EmblemMath.loadout(for: "H030", profile: p, master: .shared)?.level, 31)
    }

    func testMatchRewardGrantsDustScaledByDuration() {
        var p = Profile()
        let win = RewardService.apply(outcome: ServicesFixtures.outcome(won: true, minutes: 15), to: &p, master: .shared,
                                      persistence: persistence(), now: ServicesFixtures.weekday)
        XCTAssertEqual(win.magicDust, EmblemEconomy.matchDustWin)
        XCTAssertEqual(p.magicDust, EmblemEconomy.matchDustWin)
        let loss = RewardService.apply(outcome: ServicesFixtures.outcome(won: false, minutes: 15), to: &p, master: .shared,
                                       persistence: persistence(), now: ServicesFixtures.weekday)
        XCTAssertEqual(loss.magicDust, EmblemEconomy.matchDustLoss)
        // 短い試合は Coin と同じ時間係数（下限 0.3）
        let short = RewardService.apply(outcome: ServicesFixtures.outcome(won: true, minutes: 2), to: &p, master: .shared,
                                        persistence: persistence(), now: ServicesFixtures.weekday)
        XCTAssertEqual(short.magicDust, 5)
        XCTAssertEqual(p.magicDust, EmblemEconomy.matchDustWin + EmblemEconomy.matchDustLoss + 5)
        // 報酬の対象外（練習場）は無し
        let practice = RewardService.apply(outcome: ServicesFixtures.outcome(mode: .practice), to: &p, master: .shared,
                                           persistence: persistence(), now: ServicesFixtures.weekday)
        XCTAssertEqual(practice.magicDust, 0)
    }

    // MARK: - 無料のエンブレム宝箱

    func testChestOpensThenWaitsFourHoursAndStoresTwo() {
        var p = Profile()
        let t0 = ServicesFixtures.weekday
        EmblemService.refreshChest(profile: &p, now: t0)
        XCTAssertEqual(EmblemService.chestCharges(p, now: t0), 1, "新規は 1 回分")
        XCTAssertEqual(EmblemService.chestSecondsUntilNext(p, now: t0), 4 * 3600)
        XCTAssertEqual(HomeBadges.emblemChest(p, now: t0), 1)
        XCTAssertEqual(HomeTab.emblems.badge(profile: p, now: t0), 1, "フッターのエンブレムのタブ")
        XCTAssertEqual(HomeTab.heroes.badge(profile: p, now: t0), 0)
        let first = EmblemService.openChest(profile: &p, now: t0)
        XCTAssertEqual(first, [EmblemService.dustAttachment(EmblemEconomy.chestDust),
                               EmblemService.fragmentAttachment(EmblemEconomy.chestFragments, set: .tank)])
        XCTAssertEqual(p.magicDust, EmblemEconomy.chestDust)
        XCTAssertEqual(EmblemService.fragments(.tank, profile: p), EmblemEconomy.chestFragments)
        XCTAssertNil(EmblemService.openChest(profile: &p, now: t0.addingTimeInterval(60)), "4 時間待つ")
        XCTAssertEqual(EmblemService.chestSecondsUntilNext(p, now: t0.addingTimeInterval(60)).map(EmblemService.countdownText), "3:59:00")
        XCTAssertEqual(HomeTab.emblems.badge(profile: p, now: t0.addingTimeInterval(60)), 0)
        // 9 時間たつと 2 回分（それ以上は貯まらない）。欠片のセットは巡回（タンク → アサシン → メイジ）
        let later = t0.addingTimeInterval(9 * 3600)
        XCTAssertEqual(EmblemService.chestCharges(p, now: later), 2)
        XCTAssertEqual(EmblemService.chestCharges(p, now: later.addingTimeInterval(48 * 3600)), 2)
        XCTAssertNotNil(EmblemService.openChest(profile: &p, now: later))
        XCTAssertNotNil(EmblemService.openChest(profile: &p, now: later))
        XCTAssertNil(EmblemService.openChest(profile: &p, now: later))
        XCTAssertEqual(EmblemService.fragments(.assassin, profile: p), EmblemEconomy.chestFragments)
        XCTAssertEqual(EmblemService.fragments(.mage, profile: p), EmblemEconomy.chestFragments)
        XCTAssertEqual(p.emblemChest.opened, 3)
        // 同じ時刻・同じ状態なら同じ結果（確率は無い）
        var a = p, b = p
        let t = later.addingTimeInterval(4 * 3600)
        XCTAssertEqual(EmblemService.openChest(profile: &a, now: t), EmblemService.openChest(profile: &b, now: t))
        XCTAssertEqual(a, b)
        XCTAssertEqual(EmblemService.countdownText(59), "0:59")
    }

    // MARK: - 添付と入手

    func testMailKindsRoundTripAndMerge() throws {
        let list = [EmblemService.dustAttachment(30), EmblemService.fragmentAttachment(15, set: .tank)]
        let mail = MailItem(date: Date(timeIntervalSince1970: 1_800_000_000), title: "T", body: "B", attachments: list)
        XCTAssertEqual(try JSONDecoder().decode(MailItem.self, from: JSONEncoder().encode(mail)), mail)
        let json = String(decoding: try JSONEncoder().encode(list), as: UTF8.self)
        XCTAssertTrue(json.contains("\"magicDust\"") && json.contains("\"emblemFragment\"") && json.contains("\"EM_TANK\""), json)
        // 旧版の種類はそのまま読める
        let old = try JSONDecoder().decode(MailAttachment.self, from: Data(#"{"kind":"coin","amount":100}"#.utf8))
        XCTAssertEqual(old, MailAttachment(kind: .coin, amount: 100))
        // まとめ: 魔法の粉は合算、欠片は同じセットだけ合算
        let more = list + [EmblemService.dustAttachment(20), EmblemService.fragmentAttachment(5, set: .tank),
                           EmblemService.fragmentAttachment(7, set: .mage)]
        let merged = LiveOpsService.mergeAttachments(more)
        XCTAssertEqual(merged, [EmblemService.dustAttachment(50), EmblemService.fragmentAttachment(20, set: .tank),
                                EmblemService.fragmentAttachment(7, set: .mage)])
        XCTAssertEqual(RewardClaimText.merged(more), merged)
        // 表示
        XCTAssertEqual(RewardClaimText.name(EmblemService.dustAttachment(30)), "魔法の粉 ×30")
        XCTAssertEqual(RewardClaimText.shortName(EmblemService.fragmentAttachment(15, set: .tank)), "タンクの欠片")
        XCTAssertEqual(RewardClaimText.chipText(EmblemService.fragmentAttachment(15, set: .tank)), "15")
        XCTAssertEqual(LiveOpsService.describe(EmblemService.fragmentAttachment(15, set: .marksman)), "ハンターの欠片 ×15")
        XCTAssertEqual(FlowText.attachmentTitle(EmblemService.dustAttachment(30), master: .shared), "30 魔法の粉")
    }

    func testMissionsPassAndWelcomeMailGrantDustAndFragments() {
        typealias E = EmblemEconomy
        // デイリー: 参加・戦闘・タワーは魔法の粉、ロールでプレイはそのロールのセットの欠片
        XCTAssertEqual(LiveOpsService.missionDef(id: "D01")?.extraRewards, [EmblemService.dustAttachment(E.dailyParticipationDust)])
        XCTAssertEqual(LiveOpsService.missionDef(id: "D05")?.extraRewards, [EmblemService.dustAttachment(E.dailyCombatDust)])
        XCTAssertEqual(LiveOpsService.missionDef(id: "D09")?.extraRewards, [EmblemService.dustAttachment(E.dailyObjectiveDust)])
        XCTAssertEqual(LiveOpsService.missionDef(id: "D10")?.extraRewards, [EmblemService.fragmentAttachment(E.dailyRoleFragments, set: .tank)])
        XCTAssertEqual(LiveOpsService.missionDef(id: "D11")?.extraRewards.first?.refID, EmblemSetID.marksman.rawValue)
        XCTAssertEqual(LiveOpsService.missionDef(id: "D12")?.extraRewards.first?.refID, EmblemSetID.support.rawValue)
        XCTAssertTrue(LiveOpsService.dailyMissionPool.allSatisfy { !$0.extraRewards.isEmpty })
        // ウィークリー: W02 は 6 つのセットの欠片のまとめ、ほかは魔法の粉
        let w02 = LiveOpsService.missionDef(id: "W02")?.extraRewards ?? []
        XCTAssertEqual(Set(w02.compactMap(\.refID)), Set(E.chestRotation.map(\.rawValue)))
        XCTAssertTrue(w02.allSatisfy { $0.kind == .emblemFragment && $0.amount == E.weeklyFragmentsPerSet })
        XCTAssertEqual(LiveOpsService.missionDef(id: "W01")?.extraRewards, [EmblemService.dustAttachment(E.weeklyPlayDust)])
        // 受け取ると所持に入る（デイリーの 1 枠目は参加のミッション）
        var p = Profile()
        let now = ServicesFixtures.weekday
        LiveOpsService.refreshMissions(profile: &p, now: now)
        let id = p.missions.daily[0].id
        p.missions.daily[0].progress = LiveOpsService.missionDef(id: id)!.target
        XCTAssertNotNil(LiveOpsService.claimMission(id: id, profile: &p, now: now))
        XCTAssertEqual(p.magicDust, E.dailyParticipationDust)
        // スターパスの無料トラック（3・8・13・18・23・28 段階）
        let pass = LiveOpsService.passRewards()
        XCTAssertEqual(pass.filter { $0.free?.kind == .magicDust }.map(\.level), E.passDustLevels)
        XCTAssertTrue(pass.filter { $0.free?.kind == .magicDust }.allSatisfy { $0.free?.amount == E.passDust })
        // ウェルカムメール: セットを 1 つ解放できる魔法の粉。起動で宝箱の時計も数え始める
        var fresh = Profile()
        LiveOpsService.onLaunch(profile: &fresh, master: .shared, now: now)
        let welcome = fresh.mail.first { $0.attachments.contains { $0.kind == .magicDust } }
        XCTAssertEqual(welcome?.attachments.first { $0.kind == .magicDust }?.amount, E.starterDust)
        XCTAssertEqual(fresh.emblemChest.anchor, now)
        _ = LiveOpsService.claimAllMail(profile: &fresh, now: now)
        XCTAssertEqual(fresh.magicDust, E.starterDust)
        XCTAssertTrue(EmblemService.canUnlock(.assassin, profile: fresh))
    }
}
