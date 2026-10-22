import XCTest
@testable import VelstriaCore

/// エンブレムの解放・レベル・天賦の解放・宝箱・入手の見込み（Data/EmblemProgression.swift。docs/EMBLEMS.md「解放・レベル・入手」）。
final class EmblemProgressionTests: XCTestCase {
    private typealias P = EmblemProgression
    private typealias E = EmblemEconomy

    // MARK: - 強化の費用

    func testCostTableMatchesTheGuideTotalsAndBumpsAtKeyLevels() {
        XCTAssertEqual(P.upgradeCosts.count, 59, "Lv1→2 … 59→60")
        XCTAssertEqual(P.totalCost, 22_773)
        XCTAssertEqual(P.rangeTotals.map(\.total).reduce(0, +), 22_773)
        // 10 レベルごとの合計（第三者の攻略）
        for r in P.rangeTotals {
            let sum = (r.lo...r.hi).map { P.upgradeCost(from: $0 - 1)! }.reduce(0, +)
            XCTAssertEqual(sum, r.total, "Lv\(r.lo)〜\(r.hi)")
        }
        XCTAssertEqual(P.cumulativeCost(to: 60), 22_773)
        XCTAssertEqual(P.cumulativeCost(to: 30), 483 + 1210 + 2540)
        XCTAssertEqual(P.cumulativeCost(to: 1), 0)
        // 画面で確かめた 1 回の費用（26→27 アサシン・28→29 タンク・29→30 サポート）
        XCTAssertEqual(P.upgradeCost(from: 26), 227)
        XCTAssertEqual(P.upgradeCost(from: 28), 337)
        XCTAssertEqual(P.upgradeCost(from: 29), 488)
        XCTAssertNotEqual(P.upgradeCost(from: 42), 365, "42→43（通常共通）は範囲の合計と合わない（docs に記録）")
        XCTAssertNil(P.upgradeCost(from: 60), "MAX")
        XCTAssertNil(P.upgradeCost(from: 0))
        // キーレベルに上がる 1 回は前後より高い（Lv60 は前より 1.4 倍以上）
        for key in P.keyLevels {
            let c = P.upgradeCost(from: key - 1)!
            XCTAssertGreaterThan(Double(c), Double(P.upgradeCost(from: key - 2)!) * 1.4, "Lv\(key)")
            if let next = P.upgradeCost(from: key) { XCTAssertGreaterThan(c, next, "Lv\(key)") }
        }
        // 範囲の中（キーレベル以外）は増えていく
        for r in P.rangeTotals {
            let costs = (r.lo...r.hi).filter { !P.isKeyLevel($0) }.map { P.upgradeCost(from: $0 - 1)! }
            XCTAssertEqual(costs, costs.sorted(), "Lv\(r.lo)〜\(r.hi)")
            XCTAssertEqual(Set(costs).count, costs.count)
        }
        XCTAssertEqual(P.nextKeyLevel(after: 26), 30)
        XCTAssertEqual(P.nextKeyLevel(after: 30), 45)
        XCTAssertEqual(P.nextKeyLevel(after: 59), 60)
        XCTAssertNil(P.nextKeyLevel(after: 60))
    }

    func testUpgradeQuoteSpendsFragmentsBeforeDust() {
        // 画面の「10+217/227」
        let q = EmblemUpgradeQuote.make(cost: 227, fragments: 10, dust: 500)
        XCTAssertEqual(q, EmblemUpgradeQuote(needed: 227, fromFragments: 10, fromDust: 217))
        XCTAssertTrue(q.affordable)
        // 欠片が足りていればマジックダストは使わない
        XCTAssertEqual(EmblemUpgradeQuote.make(cost: 50, fragments: 80, dust: 999),
                       EmblemUpgradeQuote(needed: 50, fromFragments: 50, fromDust: 0))
        // 足りない（タンクの 145 / 337）
        let short = EmblemUpgradeQuote.make(cost: 337, fragments: 145, dust: 0)
        XCTAssertEqual(short.fromFragments + short.fromDust, 145)
        XCTAssertFalse(short.affordable)
        XCTAssertFalse(EmblemUpgradeQuote.make(cost: 488, fragments: 0, dust: 487).affordable)
        XCTAssertTrue(EmblemUpgradeQuote.make(cost: 488, fragments: 0, dust: 488).affordable)
        // 負の値は 0 とする
        XCTAssertEqual(EmblemUpgradeQuote.make(cost: 10, fragments: -5, dust: -1), EmblemUpgradeQuote(needed: 10, fromFragments: 0, fromDust: 0))
    }

    // MARK: - 能力値のレベル別の表

    func testAttributeTablesPassThroughTheObservedPointsAndReachMaxAt60() {
        for d in EmblemCatalog.sets {
            for (k, a) in d.attributes.enumerated() {
                let t = a.levelValues ?? []
                XCTAssertEqual(t.count, 60, "\(d.id) \(a.kind)")
                XCTAssertEqual(a.value(level: 60), a.maxValue, "\(d.id) \(a.kind): Lv60 は最大")
                XCTAssertGreaterThan(a.value(level: 1), 0)
                XCTAssertLessThan(a.value(level: 1), a.maxValue * 0.2)
                for lv in 1..<60 {
                    XCTAssertLessThanOrEqual(a.value(level: lv), a.value(level: lv + 1), "\(d.id) \(a.kind) Lv\(lv)")
                }
                // 小数 2 桁（画面の表示どおり）
                XCTAssertTrue(t.allSatisfy { abs($0 * 100 - ($0 * 100).rounded()) < 1e-6 })
                XCTAssertEqual(a.isCore, k == 0)
            }
        }
        func v(_ set: EmblemSetID, _ k: Int, _ lv: Int) -> Double { EmblemCatalog.set(set).attributes[k].value(level: lv) }
        // アサシン Lv26: 適応貫通 3.80・適応攻撃 4.30・移動速度 1.20%、Lv27 の移動速度 1.30%
        XCTAssertEqual(v(.assassin, 0, 26), 3.80, accuracy: 0.01)
        XCTAssertEqual(v(.assassin, 1, 26), 4.30, accuracy: 0.01)
        XCTAssertEqual(v(.assassin, 2, 26), 1.20, accuracy: 0.01)
        XCTAssertEqual(v(.assassin, 2, 27), 1.30, accuracy: 0.01)
        // サポート Lv29: 回復効果 3.33%・CD短縮 4.72%・移動速度 2.82%、Lv30 の回復効果 4.75%
        XCTAssertEqual(v(.support, 0, 29), 3.33, accuracy: 0.01)
        XCTAssertEqual(v(.support, 0, 30), 4.75, accuracy: 0.01)
        XCTAssertEqual(v(.support, 1, 29), 4.72, accuracy: 0.01)
        XCTAssertEqual(v(.support, 2, 29), 2.82, accuracy: 0.01)
        // タンク Lv28: HP 140・混合防御 4.40・HP回復 1.74、Lv29 の HP回復 1.86
        XCTAssertEqual(v(.tank, 0, 28), 140, accuracy: 0.01)
        XCTAssertEqual(v(.tank, 1, 28), 4.40, accuracy: 0.01)
        XCTAssertEqual(v(.tank, 2, 28), 1.74, accuracy: 0.01)
        XCTAssertEqual(v(.tank, 2, 29), 1.86, accuracy: 0.01)
        // 通常共通 Lv42: 混合回復 4.40・HP 193・適応攻撃 14.70、Lv43 の適応攻撃 15.40
        XCTAssertEqual(v(.common, 0, 42), 4.40, accuracy: 0.01)
        XCTAssertEqual(v(.common, 1, 42), 193, accuracy: 0.01)
        XCTAssertEqual(v(.common, 2, 42), 14.70, accuracy: 0.01)
        XCTAssertEqual(v(.common, 2, 43), 15.40, accuracy: 0.01)
    }

    func testOneAttributeGrowsPerLevelAndTheCoreJumpsOnlyAtKeyLevels() {
        func changed(_ set: EmblemSetID, _ lv: Int) -> [Int] {
            EmblemCatalog.set(set).attributes.indices.filter {
                let a = EmblemCatalog.set(set).attributes[$0]
                return a.value(level: lv + 1) != a.value(level: lv)
            }
        }
        // 画面の予告（次のレベルで伸びるのは 1 つだけ）
        XCTAssertEqual(changed(.assassin, 26), [2], "Lv27 は移動速度だけ")
        XCTAssertEqual(changed(.tank, 28), [2], "Lv29 は HP回復だけ")
        XCTAssertEqual(changed(.support, 29), [0], "Lv30 は回復効果（コア）だけ")
        XCTAssertEqual(changed(.common, 42), [2], "Lv43 は適応攻撃だけ")
        for d in EmblemCatalog.sets {
            for lv in 1..<60 {
                let c = changed(d.id, lv)
                XCTAssertEqual(c.count, 1, "\(d.id) Lv\(lv)→\(lv + 1): \(c)")
                // コア属性はキーレベルに上がる時だけ伸び、キーレベルではコア属性だけが伸びる
                XCTAssertEqual(c.contains(0), P.isKeyLevel(lv + 1), "\(d.id) Lv\(lv + 1)")
            }
            // キーレベルで大きく伸びる（コア属性大幅アップ）
            let core = d.attributes[0]
            for key in P.keyLevels {
                XCTAssertGreaterThan(core.value(level: key) - core.value(level: key - 1), core.maxValue * 0.09, "\(d.id) Lv\(key)")
            }
        }
    }

    func testEmblemValuesAtALevelReachTheStats() {
        // タンク Lv28 の HP 140・混合防御 4.40・HP回復 1.74（天賦は致命 / 熟練ハンター = 能力値に入らない組み合わせ）
        var base = Stats()
        base.maxHP = 2000; base.armor = 20; base.magicResist = 20; base.hpRegen = 5; base.moveSpeed = 250; base.attackSpeed = 1
        var st = base
        ItemStats.apply(items: [], emblem: EmblemLoadout(.tank, .fatal, .seasonedHunter, .warCry, level: 28), to: &st, master: .shared)
        XCTAssertEqual(st.maxHP - base.maxHP, 140, accuracy: 1e-9)
        XCTAssertEqual(st.armor - base.armor, 4.40, accuracy: 1e-9)
        XCTAssertEqual(st.hpRegen - base.hpRegen, 1.74, accuracy: 1e-9)
    }

    // MARK: - 天賦の解放

    func testTalentTiersUnlockAtTenFifteenTwenty() {
        XCTAssertEqual(P.unlockLevel(.tier1), 10)
        XCTAssertEqual(P.unlockLevel(.tier2), 15)
        XCTAssertEqual(P.unlockLevel(.core), 20)
        XCTAssertFalse(P.allTalentsUnlocked)
        XCTAssertTrue(EmblemCatalog.talents.allSatisfy { P.unlockLevel(talent: $0.id) == P.unlockLevel($0.tier) })
        func active(_ lv: Int) -> [EmblemTalentID?] {
            let e = EmblemLoadout(.tank, .vitality, .tenacity, .concussiveBlast, level: lv)
            return [e.activeTier1, e.activeTier2, e.activeCore]
        }
        XCTAssertEqual(active(1), [nil, nil, nil])
        XCTAssertEqual(active(9), [nil, nil, nil])
        XCTAssertEqual(active(10), [.vitality, nil, nil])
        XCTAssertEqual(active(14), [.vitality, nil, nil])
        XCTAssertEqual(active(15), [.vitality, .tenacity, nil])
        XCTAssertEqual(active(20), [.vitality, .tenacity, .concussiveBlast])
        XCTAssertEqual(active(60), [.vitality, .tenacity, .concussiveBlast])
        XCTAssertTrue(P.isTierUnlocked(.core, level: 20))
        XCTAssertFalse(P.isTierUnlocked(.core, level: 19))
    }

    func testLockedTiersDoNothingInTheMatch() {
        func hero(_ e: EmblemLoadout) -> HeroData {
            let def = MasterData.shared.hero("H030")!
            return HeroData(heroID: def.heroID, role: def.role, isRanged: def.isRanged, resourceKind: def.resource,
                            controller: .human, position: .mid, displayName: "P", botDifficulty: .normal,
                            spells: ["BS01", "BS03"], emblem: e, skinID: nil)
        }
        // 2 段目（掘り出し上手・立て直し）は Lv15 から
        XCTAssertEqual(EmblemEffects.purchasePriceMultiplier(hero(EmblemLoadout(.mage, .inspire, .bargainHunter, .lethalIgnition, level: 14))), 1)
        XCTAssertEqual(EmblemEffects.purchasePriceMultiplier(hero(EmblemLoadout(.mage, .inspire, .bargainHunter, .lethalIgnition, level: 15))), 0.95)
        XCTAssertEqual(EmblemEffects.spellCooldownMultiplier(hero(EmblemLoadout(.support, .agility, .pullYourselfTogether, .focusingMark, level: 10))), 1)
        XCTAssertEqual(EmblemEffects.spellCooldownMultiplier(hero(EmblemLoadout(.support, .agility, .pullYourselfTogether, .focusingMark, level: 15))), 0.88, accuracy: 1e-9)
        // コア（時の支配）は Lv20 から
        var h = hero(EmblemLoadout(.assassin, .thrill, .seasonedHunter, .temporalReign, level: 19))
        h.emblemRuntime.until = 100
        XCTAssertEqual(EmblemEffects.skillCooldownRate(h, slot: SkillSlot.skill1.rawValue, time: 1), 1)
        h.emblem?.level = 20
        XCTAssertEqual(EmblemEffects.skillCooldownRate(h, slot: SkillSlot.skill1.rawValue, time: 1), 1.5)
        // 1 段目（活力）は Lv10 から
        var base = Stats()
        base.maxHP = 2000; base.moveSpeed = 250; base.attackSpeed = 1
        var lv9 = base, lv10 = base
        ItemStats.apply(items: [], emblem: EmblemLoadout(.mage, .vitality, .seasonedHunter, .warCry, level: 9), to: &lv9, master: .shared)
        ItemStats.apply(items: [], emblem: EmblemLoadout(.mage, .vitality, .seasonedHunter, .warCry, level: 10), to: &lv10, master: .shared)
        XCTAssertEqual(lv10.maxHP - lv9.maxHP, 225, accuracy: 1e-9)
    }

    func testHumanUsesTheirLevelWhileBotsStayAtSixty() {
        let low = EmblemLoadout(.tank, .vitality, .tenacity, .concussiveBlast, level: 1)
        let full = EmblemLoadout(.tank, .vitality, .tenacity, .concussiveBlast, level: 60)
        func human(_ cfg: MatchConfig) -> (Simulation, Int) {
            let sim = Simulation(config: cfg)
            let i = sim.state.heroIndices.first { sim.state.units[$0].hero?.controller == .human }!
            return (sim, i)
        }
        let (a, i) = human(MatchFactory.standardMatch(humanHeroID: "H030", humanName: "P", humanEmblem: low, seed: 3))
        let (b, j) = human(MatchFactory.standardMatch(humanHeroID: "H030", humanName: "P", humanEmblem: full, seed: 3))
        XCTAssertEqual(a.state.units[i].hero?.emblem?.level, 1)
        XCTAssertEqual(b.state.units[j].hero?.emblem?.level, 60)
        // Lv1: HP 75（コアの帯 0 = 15%）・活力は働かない。Lv60: HP 500 + 活力 225
        let tankLv1 = EmblemCatalog.set(.tank).attributes[0].value(level: 1)
        XCTAssertEqual(tankLv1, 75, accuracy: 1e-9)
        XCTAssertEqual(b.state.units[j].stats.maxHP - a.state.units[i].stats.maxHP, (500 + 225) - tankLv1, accuracy: 1e-6)
        for s in [a, b] {
            for k in s.state.heroIndices where s.state.units[k].hero?.controller == .bot {
                XCTAssertEqual(s.state.units[k].hero?.emblem?.level, 60)
            }
        }
        // 構成の往復でもレベルは残る（キーが無ければ 60）
        let cfg = MatchFactory.standardMatch(humanHeroID: "H030", humanName: "P", humanEmblem: low, seed: 3)
        let back = try? JSONDecoder().decode(MatchConfig.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back?.humanSlot?.emblem?.level, 1)
    }

    // MARK: - 無料のエンブレム宝箱

    func testChestAccumulatesEveryFourHoursUpToTwoCharges() {
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let h: TimeInterval = 3600
        var c = EmblemChestState()
        XCTAssertEqual(c.charges, 1, "新しいプレイヤーは 1 回分を持って始める")
        c = c.refreshed(now: t0)
        XCTAssertEqual(c.anchor, t0, "初めて見た時から数える")
        XCTAssertEqual(c.nextChargeAt(now: t0), t0.addingTimeInterval(4 * h))
        XCTAssertEqual(c.refreshed(now: t0.addingTimeInterval(4 * h - 1)).charges, 1)
        XCTAssertEqual(c.refreshed(now: t0.addingTimeInterval(4 * h)).charges, 2)
        XCTAssertEqual(c.refreshed(now: t0.addingTimeInterval(100 * h)).charges, 2, "2 回分まで")
        XCTAssertNil(c.nextChargeAt(now: t0.addingTimeInterval(5 * h)), "満タンの間は数えない")
        // 満タンから開けると、開けた時から数え直す
        let r1 = c.open(now: t0.addingTimeInterval(5 * h))
        XCTAssertEqual(r1, EmblemChestReward(dust: E.chestDust, fragmentSet: .tank, fragments: E.chestFragments))
        XCTAssertEqual(c.charges, 1)
        XCTAssertEqual(c.nextChargeAt(now: t0.addingTimeInterval(5 * h)), t0.addingTimeInterval(9 * h))
        let r2 = c.open(now: t0.addingTimeInterval(6 * h))
        XCTAssertEqual(r2?.fragmentSet, .assassin, "欠片のセットは巡回する")
        XCTAssertEqual(c.charges, 0)
        XCTAssertNil(c.open(now: t0.addingTimeInterval(6 * h)), "貯まっていない")
        XCTAssertEqual(c.opened, 2)
        // 満タンでない時は途中の時間を持ち越す（5h から数えて 9h・13h）
        XCTAssertEqual(c.refreshed(now: t0.addingTimeInterval(9 * h)).charges, 1)
        let later = c.refreshed(now: t0.addingTimeInterval(11 * h))
        XCTAssertEqual(later.charges, 1)
        XCTAssertEqual(later.nextChargeAt(now: t0.addingTimeInterval(11 * h)), t0.addingTimeInterval(13 * h))
        // 同じ時刻なら同じ結果
        XCTAssertEqual(c.refreshed(now: t0.addingTimeInterval(11 * h)), later)
        // 時計を戻したら増やさず、その時から数え直す
        let back = c.refreshed(now: t0)
        XCTAssertEqual(back.charges, 0)
        XCTAssertEqual(back.anchor, t0)
        // 巡回は 6 つのセット（通常共通は無い）
        XCTAssertEqual((0..<6).map { E.chestReward(opened: $0).fragmentSet }, E.chestRotation)
        XCTAssertEqual(E.chestReward(opened: 6).fragmentSet, .tank)
        XCTAssertFalse(E.chestRotation.contains(.common))
    }

    func testChestStateDecodesOldOrBrokenData() throws {
        let t = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let s = EmblemChestState(charges: 2, anchor: t, opened: 7)
        XCTAssertEqual(try JSONDecoder().decode(EmblemChestState.self, from: JSONEncoder().encode(s)), s)
        XCTAssertEqual(try JSONDecoder().decode(EmblemChestState.self, from: Data("{}".utf8)), EmblemChestState())
        let bad = try JSONDecoder().decode(EmblemChestState.self, from: Data(#"{"charges":9,"opened":-3}"#.utf8))
        XCTAssertEqual(bad.charges, E.chestMaxCharges)
        XCTAssertEqual(bad.opened, 0)
    }

    // MARK: - 入手の見込み

    func testNormalPlayMaxesOneSetInThreeToFiveMonths() {
        XCTAssertEqual(E.matchDust(won: true, durationFactor: 1), 15)
        XCTAssertEqual(E.matchDust(won: false, durationFactor: 1), 8)
        XCTAssertEqual(E.matchDust(won: true, durationFactor: 0.3), 5)
        XCTAssertEqual(E.matchDust(won: true, durationFactor: .nan), 0)
        XCTAssertEqual(E.starterDust, E.unlockCost, "最初のマジックダストでセットを 1 つ解放できる")

        let normal = E.weeklyIncome()
        XCTAssertEqual(normal.dust, 1302, accuracy: 1e-9, "docs/EMBLEMS.md の計算")
        XCTAssertEqual(normal.fragments[.assassin] ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(normal.fragments[.tank] ?? 0, 76.25, accuracy: 1e-9)
        XCTAssertNil(normal.fragments[.common])
        // 1 か月 ≒ 4.35 週。3〜5 か月 = 13〜21.7 週
        for set in EmblemSetID.allCases {
            let weeks = E.weeksToMax(set, income: normal)
            XCTAssertGreaterThan(weeks, 13, "\(set)")
            XCTAssertLessThan(weeks, 21.7, "\(set)")
        }
        // 少なめ（1 日 2 試合・宝箱 2 回）は長く、多め（1 日 8 試合・宝箱 4 回）は短い
        let light = E.weeklyIncome(matchesPerDay: 2, chestOpensPerDay: 2)
        let heavy = E.weeklyIncome(matchesPerDay: 8, chestOpensPerDay: 4)
        XCTAssertGreaterThan(E.weeksToMax(.assassin, income: light), E.weeksToMax(.assassin, income: normal))
        XCTAssertLessThan(E.weeksToMax(.assassin, income: heavy), E.weeksToMax(.assassin, income: normal))
        XCTAssertGreaterThan(E.weeksToMax(.assassin, income: heavy), 8, "多めでも 2 か月はかかる")
    }
}
