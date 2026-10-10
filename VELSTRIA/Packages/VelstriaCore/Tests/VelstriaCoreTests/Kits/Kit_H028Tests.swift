import XCTest
@testable import VelstriaCore

/// H028 断空のザイル（Saber）のキット。仕様: docs/kits/Saber.md、実装対応表: 同ファイル末尾。
/// 敵は動かない通常のヒーロー（H001 / H003 ほか）。キットはテストごとに testOverride で有効にする（isReady の既定に依存しない）。
final class Kit_H028Tests: XCTestCase {
    typealias Tune = Kit_H028.Tune

    override func setUp() {
        super.setUp()
        HeroKits.testOverride = [Kit_H028(isReady: true)]
    }

    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    // MARK: - 土台

    /// ザイル（blue, 東向き）を置く。敵は別に addEnemy で足す。
    private func world(level: Int = 12, ranks: [Int]? = [1, 1, 1], noCooldowns: Bool = false) -> (SkillWorld, Int) {
        var w = SkillWorld(noCooldowns: noCooldowns)
        let k = w.addHero("H028", team: .blue, at: skillArena, level: level, ranks: ranks, facing: 0)
        return (w, k)
    }

    @discardableResult
    private func addEnemy(_ w: inout SkillWorld, dx: Double, dy: Double = 0, hero: String = "H001", level: Int = 12) -> Int {
        w.addHero(hero, team: .red, at: skillArena + Vec2(dx, dy), level: level, ranks: [1, 1, 1])
    }

    private func kit(_ w: SkillWorld, _ k: Int) -> KitState { w.s.units[k].hero!.kit! }

    private func baneTag(_ w: SkillWorld, _ k: Int) -> String { KitTags.mark("H028", Tune.baneMark, owner: w.id(k)) }

    private func stacks(_ w: SkillWorld, _ k: Int, _ e: Int) -> Int {
        Kit.markStacks(w.s, target: e, tag: baneTag(w, k))
    }

    /// 防御を削らない確定ダメージの命中（スキル由来 = 防御ダウンの層も積む）。
    private func poke(_ w: inout SkillWorld, _ k: Int, _ e: Int, slot: SkillSlot = .skill2, damage: Double = 10) {
        w.hit(k, e, SkillWorld.truePayload(damage, source: .skill(slot)))
    }

    /// 1 tick ずつ進め、tick の前の対象の防御と、その tick に対象へ入ったダメージを集める。
    private struct Hit {
        var time: Double
        var armor: Double
        var amount: Double
        var source: DamageSource
    }

    private func steps(_ w: inout SkillWorld, target: Int, ticks: Int) -> [Hit] {
        var out: [Hit] = []
        let tid = w.id(target)
        for _ in 0..<ticks {
            w.log.removeAll(keepingCapacity: true)
            let armor = w.s.units[target].stats.armor
            w.tick()
            for d in w.damageEvents where d.targetID == tid {
                out.append(Hit(time: w.s.time, armor: armor, amount: d.amount, source: d.source))
            }
        }
        return out
    }

    private func mitigation(_ armor: Double) -> Double { 100 / (100 + armor) }

    private func fullHP(_ w: inout SkillWorld, _ i: Int) { w.s.units[i].hp = w.s.units[i].stats.maxHP }

    private func attackVolleys(_ w: inout SkillWorld, target: Int, ticks: Int) -> [[DamageEvent]] {
        var out: [[DamageEvent]] = []
        let tid = w.id(target)
        for _ in 0..<ticks {
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            let hits = w.damageEvents.filter { $0.targetID == tid && $0.source == .basicAttack }
            if !hits.isEmpty { out.append(hits) }
        }
        return out
    }

    // MARK: - レジストリ・照準・数値

    func testRegistryAndTargetingPerSlot() throws {
        XCTAssertTrue(HeroKits.hasKit("H028"))
        XCTAssertFalse(HeroKits.hasKit("H001"))
        let m = MasterData.shared
        let hero = try XCTUnwrap(m.hero("H028"))
        func target(_ slot: SkillSlot, stage: Int = 0) throws -> SkillTargeting {
            let skill = try XCTUnwrap(m.skill(hero: "H028", slot: slot))
            return HeroKits.targeting(for: skill, hero: hero, stage: stage)
        }
        let s1 = try target(.skill1)
        XCTAssertEqual(s1.archetype, .selfAoE)
        XCTAssertEqual(s1.aim, .none)
        XCTAssertEqual(s1.shape, .selfRing)
        XCTAssertEqual(s1.radius, Tune.orbitRadius)
        XCTAssertFalse(s1.requiresTarget)
        let s2 = try target(.skill2)
        XCTAssertEqual(s2.archetype, .dashStrike)
        XCTAssertEqual(s2.aim, .direction)
        XCTAssertEqual(s2.shape, .dashToPoint)
        XCTAssertEqual(s2.range, Tune.dashRange)
        XCTAssertFalse(s2.requiresTarget)
        let ult = try target(.ultimate)
        XCTAssertEqual(ult.archetype, .targetedBlink)
        XCTAssertEqual(ult.aim, .unit)
        XCTAssertEqual(ult.shape, .lockOn)
        XCTAssertTrue(ult.requiresTarget)
        XCTAssertEqual(ult.reach, Tune.ultReach)
        XCTAssertEqual(try target(.passive).archetype, .passive)
        // 再使用（段）は無い: どの段でも同じ
        for slot in [SkillSlot.skill1, .skill2, .ultimate] {
            XCTAssertEqual(try target(slot, stage: 1), try target(slot), "\(slot)")
            XCTAssertFalse(try target(slot).recastable)
        }
        // 実ユニット: キット状態が付き、窓は閉じている
        let (w, k) = world()
        XCTAssertNotNil(w.s.units[k].hero?.kit)
        for slot in SkillSlot.allCases {
            XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: slot))
            XCTAssertEqual(HeroKits.activeStage(w.s.units[k].hero!, slot: slot), 0)
        }
    }

    /// 1 スロットの単体総ダメージは汎用の 0.8〜1.3 倍。
    private func damageRatio(_ slot: SkillSlot, level: Int, rank: Int) throws -> Double {
        let (w, k) = world(level: level)
        let m = MasterData.shared
        let hero = try XCTUnwrap(m.hero("H028"))
        let skill = try XCTUnwrap(m.skill(hero: "H028", slot: slot))
        let stats = w.s.units[k].stats
        let generic = SkillCatalog.genericNumbers(for: skill, hero: hero, rank: rank, stats: stats)
        let kitN = SkillCatalog.numbers(for: skill, hero: hero, rank: rank, stats: stats)
        var total = kitN.totalDamage
        // S1 は接触（9 回）+ 剣撃（5 秒で budgetStrikes 本の想定）、S2 は突進 + 強化通常攻撃の追加ダメージで数える
        if slot == .skill1 { total += generic.damage * Tune.strikeRatio * Double(Tune.budgetStrikes) }
        if slot == .skill2 { total += generic.damage * Tune.chargeBonusRatio }
        return total / generic.totalDamage
    }

    func testNumbersStayWithinDamageBudgetAndFollowCooldownFormula() throws {
        for level in [1, 6, 12] {
            for rank in 1...Balance.basicSkillMaxRank {
                for slot in [SkillSlot.skill1, .skill2] {
                    let r = try damageRatio(slot, level: level, rank: rank)
                    XCTAssertGreaterThanOrEqual(r, 0.8, "\(slot) Lv\(level) r\(rank)")
                    XCTAssertLessThanOrEqual(r, 1.3, "\(slot) Lv\(level) r\(rank)")
                }
            }
            for rank in 1...3 {
                let r = try damageRatio(.ultimate, level: level, rank: rank)
                XCTAssertGreaterThanOrEqual(r, 0.8, "ult Lv\(level) r\(rank)")
                XCTAssertLessThanOrEqual(r, 1.3, "ult Lv\(level) r\(rank)")
            }
        }
        // 数値の組み立て: S1 は 9 回の接触、S2 は 1 回の突進、奥義は 3 撃（重み 0.75 : 0.75 : 1.5）
        let (w, k) = world()
        let s1 = w.numbers(k, .skill1)
        XCTAssertEqual(s1.hits, Tune.pulseCount)
        XCTAssertEqual(s1.cc, .none)
        let s2 = w.numbers(k, .skill2)
        XCTAssertEqual(s2.hits, 1)
        XCTAssertEqual(s2.cc, .slow)
        XCTAssertEqual(s2.ccDuration, Tune.slowDuration)
        let ult = w.numbers(k, .ultimate)
        XCTAssertEqual(ult.hits, 3)
        XCTAssertEqual(ult.cc, .knockback)
        XCTAssertEqual(ult.ccDuration, Tune.airborne)
        XCTAssertTrue(ult.ccIsUltimate)
        XCTAssertEqual(ult.damage * Tune.ultWeights.reduce(0, +), ult.totalDamage, accuracy: 1e-9)
        XCTAssertEqual(w.numbers(k, .passive).damage, 0)
        // クールダウン = MLBB の秒数 × 全体倍率 × (1 − CD 短縮)。S1 は 10 秒一定、S2 は 7 秒一定、奥義は 44 / 40 / 36
        let cdr = w.s.units[k].stats.cooldownReduction
        func expected(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
            (a + (b - a) * Double(rank - 1) / Double(maxRank - 1)) * (1 - cdr) * Balance.Skills.cooldownScale
        }
        let hero = try XCTUnwrap(MasterData.shared.hero("H028"))
        for rank in 1...4 {
            let s1 = try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: .skill1))
            // S1 は MLBB の 10 秒そのまま（持続 5 秒なので剣の稼働率は約 50%）
            XCTAssertEqual(SkillCatalog.numbers(for: s1, hero: hero, rank: rank, stats: w.s.units[k].stats).cooldown,
                           expected(10, 10, rank: rank, maxRank: 4), accuracy: 1e-9)
            let s2 = try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: .skill2))
            XCTAssertEqual(SkillCatalog.numbers(for: s2, hero: hero, rank: rank, stats: w.s.units[k].stats).cooldown,
                           expected(7, 7, rank: rank, maxRank: 4), accuracy: 1e-9)
        }
        for rank in 1...3 {
            let u = try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: .ultimate))
            XCTAssertEqual(SkillCatalog.numbers(for: u, hero: hero, rank: rank, stats: w.s.units[k].stats).cooldown,
                           expected(44, 36, rank: rank, maxRank: 3), accuracy: 1e-9)
        }
        // ランクが上がるほど強く
        let sk = try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: .skill2))
        let r1 = SkillCatalog.numbers(for: sk, hero: hero, rank: 1, stats: w.s.units[k].stats)
        let r4 = SkillCatalog.numbers(for: sk, hero: hero, rank: 4, stats: w.s.units[k].stats)
        XCTAssertGreaterThan(r4.damage, r1.damage)
    }

    func testTextFillsEverySlotWithSimNumbers() throws {
        let (w, k) = world(level: 6, ranks: [2, 2, 2])
        let hero = try XCTUnwrap(MasterData.shared.hero("H028"))
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H028", slot: slot), "\(slot)")
            let skill = try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: slot))
            let n = SkillCatalog.numbers(for: skill, hero: hero, rank: max(1, w.s.units[k].hero!.rank(slot)),
                                         stats: w.s.units[k].stats)
            let t = SkillCatalog.targeting(for: skill, hero: hero)
            for english in [false, true] {
                let s = text.filled(english: english, numbers: n, targeting: t)
                XCTAssertFalse(s.contains("{"), "\(slot) en=\(english): \(s)")
                XCTAssertFalse(s.isEmpty)
            }
        }
        // 数値は sim と一致する
        let stats = w.s.units[k].stats
        let s1 = try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: .skill1))
        let n1 = SkillCatalog.numbers(for: s1, hero: hero, rank: 2, stats: stats)
        let ja1 = try XCTUnwrap(HeroKits.text(heroID: "H028", slot: .skill1)).filled(
            english: false, numbers: n1, targeting: SkillCatalog.targeting(for: s1, hero: hero))
        XCTAssertTrue(ja1.contains("\(Int(n1.damage.rounded()))ダメージ"), ja1)
        XCTAssertTrue(ja1.contains("最大\(Tune.pulseCount)回"), ja1)
        XCTAssertEqual(n1.extras.map(\.key), ["strikeDamage", "duration", "refund", "passPercent"])
        XCTAssertEqual(n1.extras[2].value, 1.0, accuracy: 1e-9)
        let p = try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: .passive))
        let pn = SkillCatalog.numbers(for: p, hero: hero, rank: 1, stats: stats)
        XCTAssertEqual(pn.extras.map(\.value), [3, 8, 5, 5])
        let u = try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: .ultimate))
        let un = SkillCatalog.numbers(for: u, hero: hero, rank: 2, stats: stats)
        XCTAssertEqual(un.extras[0].value, (un.damage * 0.75).rounded())
        XCTAssertEqual(un.extras[1].value, (un.damage * 1.5).rounded())
        XCTAssertEqual(un.extras[2].value, 1.2, accuracy: 1e-9)
    }

    /// 剣撃が主なダメージ源（接触より大きく）、強化通常攻撃の追加ダメージは突進の 3 割前後。
    /// S1 のクールダウンは全体倍率のまま（= 持続と同じ 5 秒）。秒数そのまま（約 50% の稼働率）にすると Lv1 の勝率が崩れる。
    func testSwordStrikesAreTheMainDamage() throws {
        XCTAssertGreaterThan(Tune.strikeRatio * Double(Tune.budgetStrikes), Tune.contactRatio)
        XCTAssertGreaterThanOrEqual(Tune.strikeRatio, 0.18)
        XCTAssertLessThanOrEqual(Tune.contactRatio, 0.6)
        XCTAssertGreaterThanOrEqual(Tune.chargeBonusRatio, 0.2)
        XCTAssertGreaterThanOrEqual(Tune.strikeGap, 0.3)
        XCTAssertEqual(Tune.chargeRefund, 1.0, "剣撃 1 本で突撃のクールダウンが MLBB と同じ 1 秒縮む")
        let (w, k) = world()
        XCTAssertEqual(w.numbers(k, .skill1).cooldown, 10 * (1 - w.s.units[k].stats.cooldownReduction), accuracy: 1e-9)
    }

    /// 説明文: UI の用語（スキル1 / スキル2 / アルティメットの言い方）と最終名、剣撃の言い方。
    func testTextsUseUITermsFinalNamesAndTheSwordStrikeTerm() throws {
        for slot in SkillSlot.allCases {
            let t = try XCTUnwrap(HeroKits.text(heroID: "H028", slot: slot))
            for banned in ["S1", "S2", "奥義", "追撃", "Skill1", "Skill2"] {
                XCTAssertFalse(t.ja.contains(banned) || t.en.contains(banned), "\(slot): \(banned)")
            }
        }
        let (w, k) = world()
        let hero = try XCTUnwrap(MasterData.shared.hero("H028"))
        func ja(_ slot: SkillSlot) throws -> String {
            let skill = try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: slot))
            let n = SkillCatalog.numbers(for: skill, hero: hero, rank: 1, stats: w.s.units[k].stats)
            return try XCTUnwrap(HeroKits.text(heroID: "H028", slot: slot)).filled(
                english: false, numbers: n, targeting: SkillCatalog.targeting(for: skill, hero: hero))
        }
        let s1 = try ja(.skill1)
        XCTAssertTrue(s1.contains("剣撃"), s1)
        XCTAssertTrue(s1.contains("断空突進"), s1)
        XCTAssertTrue(try ja(.skill2).contains("環剣"))
        XCTAssertTrue(try ja(.passive).contains("ミニオンには積まれない"))
    }

    // MARK: - パッシブ: 空断の理

    func testBaneStacksUpToFiveAndShredsArmorPerLevel() {
        for level in [1, 8, 15] {
            var (w, k) = world(level: level)
            let e = addEnemy(&w, dx: 400)
            let armor0 = w.s.units[e].stats.armor
            let flat = 3 + 5 * Double(level - 1) / 14
            XCTAssertEqual(Kit_H028.baneFlat(level: level), flat, accuracy: 1e-9)
            for n in 1...7 {
                poke(&w, k, e)
                let st = min(5, n)
                XCTAssertEqual(stacks(w, k, e), st, "Lv\(level) hit \(n)")
                // 同じ tick のうちに防御へ反映される
                XCTAssertEqual(w.s.units[e].stats.armor, armor0 - Double(st) * flat, accuracy: 1e-6, "Lv\(level) hit \(n)")
            }
        }
        // 最大レベルで 1 層 8、5 層で 40
        var (w, k) = world(level: 15)
        let e = addEnemy(&w, dx: 400)
        let armor0 = w.s.units[e].stats.armor
        for _ in 0..<5 { poke(&w, k, e) }
        XCTAssertEqual(armor0 - w.s.units[e].stats.armor, 40, accuracy: 1e-6)
    }

    /// パッシブのバッジ: 直近に積んだ敵の層の数。時間が切れる・その敵が倒れると消える（演出のパッシブの合図が出る土台）。
    func testPassiveBadgeShowsTheLatestTargetsStacksAndClearsWhenTheyExpireOrDie() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 200)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
        poke(&w, k, e)
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive), KitBadge(kind: .stacks, value: 1, maxValue: 5))
        poke(&w, k, e)
        poke(&w, k, e)
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive)?.value, 3)
        for _ in 0..<8 { poke(&w, k, e) }
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive)?.value, 5, "最大 5 層")
        // 別の敵に積めば、その敵の層の数に変わる
        let other = addEnemy(&w, dx: 200, dy: 100, hero: "H003")
        poke(&w, k, other)
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive)?.value, 1)
        // 5 秒で消える
        w.run(seconds: Tune.baneDuration + 0.3)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
        // 倒れたら消える
        poke(&w, k, e)
        XCTAssertNotNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
        w.s.units[e].isAlive = false
        w.tick()
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
    }

    func testBaneDurationRefreshesOnEveryHitAndExpiresTogether() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 400)
        let armor0 = w.s.units[e].stats.armor
        let flat = Kit_H028.baneFlat(level: 12)
        poke(&w, k, e)
        w.run(seconds: 3)
        poke(&w, k, e)
        XCTAssertEqual(stacks(w, k, e), 2)
        // 最初の層から 5 秒経っても、持続は 2 発目で戻っている
        w.run(seconds: 4.5)
        XCTAssertEqual(stacks(w, k, e), 2, "2 発目から 4.5 秒")
        XCTAssertEqual(w.s.units[e].stats.armor, armor0 - 2 * flat, accuracy: 1e-6)
        w.run(seconds: 0.7)
        XCTAssertEqual(stacks(w, k, e), 0, "2 発目から 5 秒で消える")
        XCTAssertFalse(w.s.units[e].statuses.contains { $0.kind == .armorShred })
        XCTAssertEqual(w.s.units[e].stats.armor, armor0, accuracy: 1e-6)
    }

    func testBaneIsAppliedByBasicAttacksAndSkillsButNotByCrowdControlOnlyHits() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 140)
        // ダメージ 0 の命中（CC のみ）は層にならない
        w.hit(k, e, HitPayload(damage: 0, damageType: .physical, source: .skill(.skill2), skillID: "t"))
        XCTAssertEqual(stacks(w, k, e), 0)
        // 通常攻撃
        w.s.units[k].attackTargetID = w.id(e)
        let volleys = attackVolleys(&w, target: e, ticks: 60)
        XCTAssertGreaterThanOrEqual(volleys.count, 1)
        XCTAssertEqual(stacks(w, k, e), min(5, volleys.count))
        // 2 発目以降の通常攻撃は前の層の分だけ防御が下がった状態で当たる
        if volleys.count >= 2 {
            let atk = w.s.units[k].stats.attack
            let flat = Kit_H028.baneFlat(level: 12)
            let armor0 = w.s.units[e].baseStats.armor
            let second = volleys[1][0].amount
            XCTAssertEqual(second, atk * 100 / (100 + armor0 - flat), accuracy: 1e-3)
        }
    }

    func testBaneOnlyAffectsHeroesMonstersAndDummies() {
        var (w, k) = world()
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(300, 0))
        let monster = w.addMonster(.campLarge, at: skillArena + Vec2(300, 200))
        let tower = w.addTower(team: .red, at: skillArena + Vec2(300, -300))
        let hero = addEnemy(&w, dx: 300, dy: 400)
        for t in [minion, monster, tower, hero] {
            poke(&w, k, t)
        }
        XCTAssertEqual(stacks(w, k, minion), 0, "ミニオンは対象外")
        XCTAssertEqual(stacks(w, k, tower), 0, "構造物は対象外")
        XCTAssertEqual(stacks(w, k, monster), 1)
        XCTAssertEqual(stacks(w, k, hero), 1)
        XCTAssertFalse(w.s.units[minion].statuses.contains { $0.kind == .armorShred })
    }

    func testBaneConvertsAgainstArmorBeforeOtherShredAndNeverPassesNinetyPercent() throws {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 400)
        let armor0 = w.s.units[e].stats.armor
        // 別の防御ダウン 40% がある相手: 換算は「ダウン前の防御」に対して行う（割合の最大が効く）
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .armorShred, duration: 10, magnitude: 0.4,
                                                                    tag: "other"))
        w.tick()
        poke(&w, k, e)
        let bane = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .armorShred && $0.tag == Tune.baneTag })
        XCTAssertEqual(bane.magnitude, Kit_H028.baneFlat(level: 12) / armor0, accuracy: 1e-9)
        // 防御がほぼ無い相手でも割合は 0.9 を超えない
        var (w2, k2) = world(level: 15)
        let e2 = addEnemy(&w2, dx: 400)
        w2.s.units[e2].baseStats.armor = 6
        StatCalculator.recompute(&w2.s, e2, w2.ctx)
        for _ in 0..<5 { poke(&w2, k2, e2) }
        let b2 = try XCTUnwrap(w2.s.units[e2].statuses.first { $0.tag == Tune.baneTag })
        XCTAssertLessThanOrEqual(b2.magnitude, Tune.baneMaxRatio + 1e-9)
        XCTAssertGreaterThanOrEqual(w2.s.units[e2].stats.armor, 0)
    }

    func testGenericAssassinPassiveIsReplaced() {
        // 汎用アサシンのパッシブ（キル/アシストで全 CD −30%）は無い
        var (w, k) = world()
        let e = addEnemy(&w, dx: 400)
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill1.rawValue] = 20
        w.s.units[k].hero!.skillCooldowns[SkillSlot.ultimate.rawValue] = 30
        w.s.units[e].hp = 1
        poke(&w, k, e, slot: .skill2, damage: 100)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertFalse(w.s.units[e].isAlive)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), 20, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), 30, accuracy: 1e-9)
    }

    // MARK: - S1: 周回する剣

    func testSwordsPulseNineTimesEveryHalfSecondAndStopAfterFiveSeconds() throws {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 150)
        let n = w.numbers(k, .skill1)
        let before = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .skill1))
        XCTAssertLessThan(w.s.units[k].resource, before, "コストを消費")
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), n.cooldown, accuracy: 1e-9)
        XCTAssertEqual(kit(w, k).zailSwordsRemaining, Tune.swordsDuration, accuracy: 1e-9)
        XCTAssertEqual(kit(w, k).zailPulseDamage, n.damage, accuracy: 1e-9)
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.slot, .skill1)
        XCTAssertEqual(ev.shape, .selfRing)
        XCTAssertEqual(ev.duration, Tune.swordsDuration)
        XCTAssertEqual(ev.count, Tune.swordCount)
        XCTAssertTrue(w.damageEvents.isEmpty, "発動の瞬間にはダメージが無い")
        let hits = steps(&w, target: e, ticks: 180).filter { $0.source == .skill(.skill1) }
        XCTAssertEqual(hits.count, Tune.pulseCount)
        for (i, h) in hits.enumerated() {
            XCTAssertEqual(h.time, 1 + Tune.pulseInterval * Double(i + 1), accuracy: 0.07, "pulse \(i)")
            XCTAssertEqual(h.amount, n.damage * mitigation(h.armor), accuracy: 1e-6, "pulse \(i)")
        }
        // 接触の防御ダウンが層になる
        XCTAssertEqual(stacks(w, k, e), 5)
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k), 0)
        XCTAssertEqual(kit(w, k).zailSwordsRemaining, 0)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .skill1))
        // もう当たらない
        XCTAssertTrue(steps(&w, target: e, ticks: 60).isEmpty)
    }

    func testSwordsOnlyTouchEnemiesInsideTheOrbitAndHitMinionsToo() {
        var (w, k) = world()
        let inside = addEnemy(&w, dx: Tune.orbitRadius + 50)
        let outside = addEnemy(&w, dx: -(Tune.orbitRadius + 80), hero: "H003")
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(0, 200))
        let ally = w.addHero("H001", team: .blue, at: skillArena + Vec2(0, -100), level: 12, ranks: [1, 1, 1])
        XCTAssertTrue(w.cast(k, .skill1))
        w.run(seconds: 0.7)
        XCTAssertGreaterThan(w.damage(to: inside), 0)
        XCTAssertEqual(w.damage(to: outside), 0)
        XCTAssertGreaterThan(w.damage(to: minion), 0)
        XCTAssertEqual(w.damage(to: ally), 0)
        // 周回半径の外から一歩入れば、次の接触で当たる
        w.s.units[outside].pos = w.s.units[k].pos + Vec2(-(Tune.orbitRadius - 20), 0)
        w.run(seconds: 0.6)
        XCTAssertGreaterThan(w.damage(to: outside), 0)
    }

    func testSwordsKeepOrbitingThroughStunAndDoNotStopWhenCasterIsHit() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 150)
        XCTAssertTrue(w.cast(k, .skill1))
        w.run(seconds: 0.7)
        let first = w.damage(to: e)
        XCTAssertGreaterThan(first, 0)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1.5))
        w.run(seconds: 1.5)
        XCTAssertGreaterThan(w.damage(to: e), first, "スタン中も剣は回る")
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k), Tune.pulseCount - 4 + 0, "9 回のうち 4 回が済んだ")
    }

    func testRecastingSwordsRestartsInsteadOfDoublingThePulses() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 150)
        XCTAssertTrue(w.cast(k, .skill1))
        w.run(seconds: 1.2)
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill1.rawValue] = 0
        XCTAssertTrue(w.cast(k, .skill1))
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k, code: 1), Tune.pulseCount)
        let hits = steps(&w, target: e, ticks: 180).filter { $0.source == .skill(.skill1) }
        XCTAssertEqual(hits.count, Tune.pulseCount, "作り直したぶんだけ")
    }

    func testSwordsCastWithoutAnyEnemyAndShowBadge() throws {
        var (w, k) = world()
        XCTAssertTrue(w.cast(k, .skill1), "敵が居なくても撃てる")
        w.tick(3)
        let badge = try XCTUnwrap(HeroKits.badge(w.s.units[k].hero!, slot: .skill1))
        XCTAssertEqual(badge.kind, .timer)
        XCTAssertEqual(badge.total, Tune.swordsDuration)
        XCTAssertLessThan(badge.remaining, Tune.swordsDuration)
    }

    // MARK: - S1: 剣撃

    func testSwordStrikeFliesAfterADamagingHitDealsDamageAndRefundsCharge() throws {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 200)
        XCTAssertTrue(w.cast(k, .skill1))
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = 3
        poke(&w, k, e)
        XCTAssertEqual(stacks(w, k, e), 1)
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k, code: 2), 1, "剣が 1 本飛ぶ")
        XCTAssertEqual(kit(w, k).zailSwordStrikes, 1)
        let expected = w.mitigated(kit(w, k).zailStrikeDamage, .physical, on: e)
        let hits = steps(&w, target: e, ticks: 8).filter { $0.source == .skill(.skill1) }
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].amount, expected, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 3 - Tune.chargeRefund - 8 * Balance.dt, accuracy: 1e-6,
                       "剣撃 1 本で S2 のクールダウンが短縮")
        XCTAssertEqual(stacks(w, k, e), 2, "剣撃もダメージなので防御ダウンの層になる")
        // 剣撃のダメージは S1 のダメージ × strikeRatio
        let generic = try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: .skill1))
        let hero = try XCTUnwrap(MasterData.shared.hero("H028"))
        let g = SkillCatalog.genericNumbers(for: generic, hero: hero, rank: 1, stats: w.s.units[k].stats).damage
        XCTAssertEqual(kit(w, k).zailStrikeDamage, g * Tune.strikeRatio, accuracy: 1e-6)
    }

    func testSwordStrikeTriggersFromRealBasicAttacksAndNotWithoutSwords() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 140)
        w.s.units[k].attackTargetID = w.id(e)
        _ = attackVolleys(&w, target: e, ticks: 90)
        XCTAssertEqual(kit(w, k).zailSwordStrikes, 0, "剣が無ければ飛ばない")
        XCTAssertEqual(w.damage(to: e, from: .skill(.skill1)), 0)

        var (w2, k2) = world()
        let e2 = addEnemy(&w2, dx: 140)
        XCTAssertTrue(w2.cast(k2, .skill1))
        w2.s.units[k2].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = 3
        w2.s.units[k2].attackTargetID = w2.id(e2)
        let volleys = attackVolleys(&w2, target: e2, ticks: 60)
        XCTAssertGreaterThanOrEqual(volleys.count, 1)
        XCTAssertGreaterThanOrEqual(kit(w2, k2).zailSwordStrikes, 1, "通常攻撃で剣が飛ぶ")
        XCTAssertLessThan(w2.s.units[k2].hero!.cooldown(.skill2), 3 - Tune.chargeRefund + 1e-9)
    }

    func testSwordStrikesAreSpacedByTheMinimumGapAndNeverChain() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 200)
        let other = addEnemy(&w, dx: 200, dy: 90, hero: "H003")
        XCTAssertTrue(w.cast(k, .skill1))
        // 同じ tick の複数ヒットは 1 本
        poke(&w, k, e)
        poke(&w, k, other)
        poke(&w, k, e)
        XCTAssertEqual(kit(w, k).zailSwordStrikes, 1)
        // 間隔を空ければ次が飛ぶ
        w.run(seconds: Tune.strikeGap + 0.1)
        poke(&w, k, e)
        XCTAssertEqual(kit(w, k).zailSwordStrikes, 2)
        // 剣撃・接触（S1 のダメージ）自体は剣を呼ばない: 5 秒そのまま放置しても累計は増えない
        let before = kit(w, k).zailSwordStrikes
        w.run(seconds: 5.5)
        XCTAssertEqual(kit(w, k).zailSwordStrikes, before)
        // 剣が戻ったあとは飛ばない
        poke(&w, k, e)
        XCTAssertEqual(kit(w, k).zailSwordStrikes, before)
    }

    func testSwordStrikePassesThroughOthersForHalfDamageAndRefundsOnce() {
        var (w, k) = world()
        let main = addEnemy(&w, dx: 200)
        let behind = addEnemy(&w, dx: 330, dy: 20, hero: "H003")
        let aside = addEnemy(&w, dx: 200, dy: 260, hero: "H004")
        XCTAssertTrue(w.cast(k, .skill1))
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = 3
        poke(&w, k, main)
        let strike = kit(w, k).zailStrikeDamage
        let mainArmor = w.s.units[main].stats.armor
        let behindArmor = w.s.units[behind].stats.armor
        w.log.removeAll()
        w.run(seconds: 0.2)
        let mainHit = w.damageEvents.first { $0.targetID == w.id(main) && $0.source == .skill(.skill1) }
        let behindHit = w.damageEvents.first { $0.targetID == w.id(behind) && $0.source == .skill(.skill1) }
        XCTAssertEqual(mainHit?.amount ?? 0, strike * mitigation(mainArmor), accuracy: 1e-6)
        XCTAssertEqual(behindHit?.amount ?? 0, strike * Tune.strikePassRatio * mitigation(behindArmor), accuracy: 1e-6,
                       "貫通した敵には 50%")
        XCTAssertNil(w.damageEvents.first { $0.targetID == w.id(aside) }, "軌道の外には当たらない")
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 3 - Tune.chargeRefund - 6 * Balance.dt, accuracy: 1e-6,
                       "クールダウン短縮は 1 本につき 1 回（貫通した敵の分は無い）")
    }

    func testSwordStrikeMissesWhenTargetDiesOrLeavesBeforeItLands() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 200)
        XCTAssertTrue(w.cast(k, .skill1))
        poke(&w, k, e)
        w.s.units[e].pos = w.s.units[k].pos + Vec2(900, 0)
        w.log.removeAll()
        w.run(seconds: 0.2)
        XCTAssertEqual(w.damage(to: e, from: .skill(.skill1)), 0, "遠くへ行った")

        var (w2, k2) = world()
        let e2 = addEnemy(&w2, dx: 200)
        XCTAssertTrue(w2.cast(k2, .skill1))
        poke(&w2, k2, e2)
        w2.s.units[e2].isAlive = false
        w2.run(seconds: 0.2)
        XCTAssertEqual(w2.damage(to: e2, from: .skill(.skill1)), 0)
    }

    func testStructuresDoNotSendSwords() {
        var (w, k) = world()
        let tower = w.addTower(team: .red, at: skillArena + Vec2(300, 0))
        XCTAssertTrue(w.cast(k, .skill1))
        poke(&w, k, tower)
        XCTAssertEqual(kit(w, k).zailSwordStrikes, 0)
    }

    // MARK: - S2: 突進

    func testChargeHitsEveryEnemyOnTheLineOnceAndStopsAtFullRange() throws {
        var (w, k) = world()
        let a = addEnemy(&w, dx: 150)
        let b = addEnemy(&w, dx: 300, dy: 20, hero: "H003")
        let off = addEnemy(&w, dx: 250, dy: 300, hero: "H004")
        let n = w.numbers(k, .skill2)
        let armorA = w.s.units[a].stats.armor
        let before = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .skill2, .direction(Vec2(1, 0))))
        XCTAssertLessThan(w.s.units[k].resource, before)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), n.cooldown, accuracy: 1e-9)
        XCTAssertNotNil(kit(w, k).sweep)
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.slot, .skill2)
        XCTAssertEqual(ev.shape, .dashToPoint)
        XCTAssertEqual(w.damage(to: a), 0, "到着前にまとめて当たらない: 経路に沿って 1 度ずつ")
        w.run(seconds: 0.5)
        XCTAssertEqual(w.damageEvents.filter { $0.targetID == w.id(a) && $0.source == .skill(.skill2) }.count, 1)
        XCTAssertEqual(w.damageEvents.filter { $0.targetID == w.id(b) && $0.source == .skill(.skill2) }.count, 1)
        XCTAssertEqual(w.damage(to: off), 0)
        XCTAssertEqual(w.damage(to: a, from: .skill(.skill2)), n.damage * mitigation(armorA), accuracy: 1e-6)
        XCTAssertEqual(w.s.units[k].pos.x, skillArena.x + Tune.dashRange, accuracy: 3)
        XCTAssertNil(kit(w, k).sweep)
        // 通り道の敵には防御ダウンの層
        XCTAssertEqual(stacks(w, k, a), 1)
        XCTAssertEqual(stacks(w, k, b), 1)
        XCTAssertEqual(stacks(w, k, off), 0)
    }

    func testChargeAimedAtAUnitStopsAtItsEdge() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 260)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        w.run(seconds: 0.5)
        XCTAssertGreaterThan(w.damage(to: e, from: .skill(.skill2)), 0)
        let gap = w.s.units[k].radius + w.s.units[e].radius
        XCTAssertEqual(w.s.units[k].pos.distance(to: w.s.units[e].pos), gap + 5, accuracy: 6)
    }

    func testChargeEnhancesTheNextBasicAttackWithBonusDamageAndSlowThenExpires() throws {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 300)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        XCTAssertEqual(kit(w, k).zailChargeWindow, 0, "到着するまでは強化されない")
        w.run(seconds: 0.4)
        // 突進は約 0.2 秒で着くので、0.4 秒後の残りは 4 秒より少し短い
        XCTAssertGreaterThan(kit(w, k).zailChargeWindow, Tune.enhanceWindow - 0.6)
        XCTAssertLessThanOrEqual(kit(w, k).zailChargeWindow, Tune.enhanceWindow)
        let badge = try XCTUnwrap(HeroKits.badge(w.s.units[k].hero!, slot: .skill2))
        XCTAssertEqual(badge.kind, .timer)
        XCTAssertEqual(badge.total, Tune.enhanceWindow)
        let atk = w.s.units[k].stats.attack
        let bonus = kit(w, k).zailChargeBonus
        XCTAssertGreaterThan(bonus, 0)
        let armor = w.s.units[e].stats.armor
        w.s.units[k].attackTargetID = w.id(e)
        let volleys = attackVolleys(&w, target: e, ticks: 90)
        XCTAssertGreaterThanOrEqual(volleys.count, 2)
        // 1 発目: 強化（追加ダメージ + 鈍足）。防御ダウンはこの 1 撃より前に積んだ 1 層（突進）まで
        XCTAssertEqual(volleys[0][0].amount, (atk + bonus) * mitigation(armor), accuracy: 1e-6)
        XCTAssertEqual(volleys[1][0].amount, atk * mitigation(armor - Kit_H028.baneFlat(level: 12)), accuracy: 1e-3,
                       "2 発目は強化されない（防御は 1 発目の分だけ下がっている）")
        XCTAssertEqual(kit(w, k).zailChargeWindow, 0)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .skill2))

        // 鈍足 60% を 1 秒
        var (w2, k2) = world()
        let e2 = addEnemy(&w2, dx: 140)
        w2.s.units[k2].hero!.kit!.zailChargeWindow = Tune.enhanceWindow
        w2.s.units[k2].hero!.kit!.zailChargeBonus = 100
        w2.s.units[k2].attackTargetID = w2.id(e2)
        for _ in 0..<60 {
            w2.tick()
            if w2.s.units[e2].has(.slow) { break }
        }
        let slow = try XCTUnwrap(w2.s.units[e2].statuses.first { $0.kind == .slow })
        XCTAssertEqual(slow.magnitude, Tune.slowAmount, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(slow.remaining, Tune.slowDuration)
        XCTAssertGreaterThan(slow.remaining, Tune.slowDuration - 0.2)
        w2.run(seconds: 1.2)
        XCTAssertFalse(w2.s.units[e2].has(.slow))

        // 時間切れ: 4 秒撃たなければ強化は消え、通常の攻撃
        var (w3, k3) = world()
        let e3 = addEnemy(&w3, dx: 300)
        XCTAssertTrue(w3.cast(k3, .skill2, .unit(w3.id(e3))))
        // 突進で積んだ防御ダウン（5 秒）も切れるまで待つ
        w3.run(seconds: Tune.enhanceWindow + 1.6)
        XCTAssertEqual(kit(w3, k3).zailChargeWindow, 0)
        let armor3 = w3.s.units[e3].stats.armor
        let atk3 = w3.s.units[k3].stats.attack
        w3.s.units[k3].attackTargetID = w3.id(e3)
        let v3 = attackVolleys(&w3, target: e3, ticks: 60)
        XCTAssertEqual(v3.first?[0].amount ?? 0, atk3 * mitigation(armor3), accuracy: 1e-3)
        XCTAssertFalse(w3.s.units[e3].has(.slow))
    }

    func testChargeIsCancelledByHardCrowdControlMidDashAndGivesNoEnhancement() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 340)
        XCTAssertTrue(w.cast(k, .skill2, .direction(Vec2(1, 0))))
        w.tick(2)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        w.run(seconds: 0.6)
        XCTAssertNil(kit(w, k).sweep)
        XCTAssertEqual(kit(w, k).zailChargeWindow, 0)
        XCTAssertLessThan(w.s.units[k].pos.x, skillArena.x + Tune.dashRange - 100)
        XCTAssertEqual(w.damage(to: e), 0)
        XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(.skill2), 1, "クールダウンは戻らない")
    }

    func testChargeNeedsResourceAndActionableCaster() {
        var (w, k) = world()
        addEnemy(&w, dx: 300)
        w.s.units[k].resource = 0
        XCTAssertFalse(w.cast(k, .skill2, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 0)
        w.s.units[k].resource = w.s.units[k].stats.maxResource
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        XCTAssertFalse(w.cast(k, .skill2, .direction(Vec2(1, 0))))
        XCTAssertFalse(w.cast(k, .skill1))
        XCTAssertFalse(w.cast(k, .ultimate))
    }

    // MARK: - 奥義: 三連断空

    private func ultWorld(rank: Int = 1, enemyDX: Double = 400, hero: String = "H001") -> (SkillWorld, Int, Int) {
        var (w, k) = world(ranks: [1, 1, rank])
        let e = addEnemy(&w, dx: enemyDX, hero: hero)
        return (w, k, e)
    }

    func testUltimateRejectsMinionsFarHeroesAndKeepsResources() {
        var (w, k) = world()
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(200, 0))
        let far = addEnemy(&w, dx: Tune.ultReach + 200)
        let before = w.s.units[k].resource
        XCTAssertFalse(w.cast(k, .ultimate, .unit(w.id(minion))), "ミニオンは対象外")
        XCTAssertFalse(w.cast(k, .ultimate, .unit(w.id(far))))
        XCTAssertFalse(w.cast(k, .ultimate))
        XCTAssertEqual(w.s.units[k].resource, before)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), 0)
        // 射程の縁（対象の縁まで）は届く
        w.s.units[far].pos = w.s.units[k].pos + Vec2(Tune.ultReach + w.s.units[far].radius - 1, 0)
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(far))))
        XCTAssertEqual(kit(w, k).zailUltPhase, 1)
    }

    func testUltimateDashesLiftsAndStrikesThreeTimesWithWeightedDamage() throws {
        var (w, k, e) = ultWorld(rank: 2)
        let n = w.numbers(k, .ultimate)
        let before = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        XCTAssertLessThan(w.s.units[k].resource, before)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), n.cooldown, accuracy: 1e-9)
        XCTAssertEqual(kit(w, k).zailUltPhase, 1)
        XCTAssertNotNil(kit(w, k).sweep)
        XCTAssertEqual(kit(w, k).zailUltTargetID, w.id(e))
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.slot, .ultimate)
        XCTAssertEqual(ev.shape, .lockOn)
        XCTAssertEqual(ev.targetUnitID, w.id(e))
        XCTAssertEqual(ev.count, 3)
        XCTAssertEqual(w.damage(to: e), 0, "突進の途中で当たらない")
        XCTAssertFalse(w.s.units[e].has(.airborne))
        // 到着まで進める
        var arrival = 0.0
        var all: [Hit] = []
        for _ in 0..<12 {
            all += steps(&w, target: e, ticks: 1)
            if kit(w, k).zailUltPhase == 2 {
                arrival = w.s.time
                break
            }
        }
        XCTAssertEqual(kit(w, k).zailUltPhase, 2, "到着して三連撃に入る")
        // 打ち上げ 1.2 秒・術者は動けない
        let air = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .airborne })
        XCTAssertEqual(air.remaining, Tune.airborne, accuracy: 1e-9)
        XCTAssertFalse(w.s.units[e].canAct)
        XCTAssertTrue(w.s.units[k].has(.root))
        XCTAssertTrue(w.s.units[k].statuses.contains { $0.kind == .channeling })
        XCTAssertNil(kit(w, k).sweep)
        // 突進は対象の縁で止まる
        let gap = w.s.units[k].radius + w.s.units[e].radius
        XCTAssertEqual(w.s.units[k].pos.distance(to: w.s.units[e].pos), gap + Tune.ultGap, accuracy: 6)
        // 三連撃
        all += steps(&w, target: e, ticks: 45)
        let strikes = all.filter { $0.source == .skill(.ultimate) }
        XCTAssertEqual(strikes.count, 3)
        XCTAssertEqual(strikes[0].time - arrival, Tune.ultFirstDelay, accuracy: 0.07)
        XCTAssertEqual(strikes[1].time - strikes[0].time, Tune.ultInterval, accuracy: 0.07)
        XCTAssertEqual(strikes[2].time - strikes[1].time, Tune.ultInterval, accuracy: 0.07)
        for (i, h) in strikes.enumerated() {
            XCTAssertEqual(h.amount, n.damage * Tune.ultWeights[i] * mitigation(h.armor), accuracy: 1e-6, "strike \(i)")
        }
        XCTAssertEqual(Tune.ultWeights, [0.75, 0.75, 1.5], "120 : 120 : 240")
        XCTAssertGreaterThan(strikes[2].amount / mitigation(strikes[2].armor),
                             2 * strikes[0].amount / mitigation(strikes[0].armor) - 1e-6)
        // 終わったら元通り
        XCTAssertEqual(kit(w, k).zailUltPhase, 0)
        XCTAssertEqual(kit(w, k).zailUltTargetID, 0)
        XCTAssertFalse(w.s.units[k].has(.root))
        XCTAssertFalse(w.s.units[k].statuses.contains { $0.kind == .channeling })
        XCTAssertEqual(kit(w, k).zailUltStrikes, 3)
        XCTAssertEqual(stacks(w, k, e), 3, "3 撃で防御ダウンが 3 層")
        // 打ち上げは 1.2 秒で終わる
        w.run(seconds: 0.6)
        XCTAssertFalse(w.s.units[e].has(.airborne))
    }

    func testUltimateSecondStrikeBenefitsFromTheStackedDefenseShred() {
        var (w, k, e) = ultWorld()
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        let armor0 = w.s.units[e].stats.armor
        let hits = steps(&w, target: e, ticks: 60).filter { $0.source == .skill(.ultimate) }
        XCTAssertEqual(hits.count, 3)
        let flat = Kit_H028.baneFlat(level: 12)
        XCTAssertEqual(hits[0].armor, armor0, accuracy: 1e-6)
        XCTAssertEqual(hits[1].armor, armor0 - flat, accuracy: 1e-6)
        XCTAssertEqual(hits[2].armor, armor0 - 2 * flat, accuracy: 1e-6)
    }

    func testUltimateFirstTwoStrikesSendSwordsButTheThirdDoesNot() {
        var (w, k, e) = ultWorld()
        XCTAssertTrue(w.cast(k, .skill1))
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = 5
        // 接触ダメージの 0.5 秒刻みと区別するため、剣撃の数は累計で見る
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        // S1 を撃った直後の S1 は canStart で撃てない（奥義の突進中）
        XCTAssertFalse(w.cast(k, .skill1))
        w.run(seconds: 2.5)
        XCTAssertEqual(kit(w, k).zailUltStrikes, 3)
        XCTAssertEqual(kit(w, k).zailSwordStrikes, 2, "1・2 撃目のみ")
        XCTAssertLessThan(w.s.units[k].hero!.cooldown(.skill2), 5 - 2 * Tune.chargeRefund + 1e-9)
    }

    func testUltimateStunInterruptsRemainingStrikesButTheTargetStaysAirborne() throws {
        var (w, k, e) = ultWorld()
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        // 1 撃目が入るまで進める
        var struck = false
        for _ in 0..<60 where !struck {
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            struck = w.damageEvents.contains { $0.source == .skill(.ultimate) }
        }
        XCTAssertTrue(struck)
        XCTAssertEqual(kit(w, k).zailUltStrikes, 1)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        w.tick(2)
        XCTAssertEqual(kit(w, k).zailUltPhase, 0, "中断で畳む")
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k, code: 5), 0)
        XCTAssertFalse(w.s.units[k].has(.root))
        XCTAssertFalse(w.s.units[k].statuses.contains { $0.kind == .channeling })
        let air = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .airborne }, "対象の打ち上げは残る")
        XCTAssertGreaterThan(air.remaining, 0)
        w.log.removeAll()
        w.run(seconds: 1.5)
        XCTAssertEqual(w.damage(to: e, from: .skill(.ultimate)), 0, "残りの 2 撃は出ない")
        XCTAssertEqual(kit(w, k).zailUltStrikes, 1)
        XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(.ultimate), 5, "クールダウンは戻らない")
        // 解けたらまた撃てる（クールダウン明け）
        w.s.units[k].hero!.skillCooldowns[SkillSlot.ultimate.rawValue] = 0
        w.s.units[k].resource = w.s.units[k].stats.maxResource
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
    }

    func testUltimateStunDuringTheDashMakesItWhiff() {
        var (w, k, e) = ultWorld(enemyDX: 480)
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        w.tick(2)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        w.run(seconds: 1)
        XCTAssertEqual(kit(w, k).zailUltPhase, 0)
        XCTAssertNil(kit(w, k).sweep)
        XCTAssertFalse(w.s.units[e].has(.airborne))
        XCTAssertEqual(w.damage(to: e), 0)
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k), 0)
        XCTAssertFalse(w.s.units[k].has(.root))
    }

    func testUltimateWhenTheTargetDiesMidSequenceStopsAndCleansUp() {
        var (w, k, e) = ultWorld()
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        var struck = false
        for _ in 0..<60 where !struck {
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            struck = w.damageEvents.contains { $0.source == .skill(.ultimate) }
        }
        XCTAssertTrue(struck)
        w.s.units[e].hp = 1
        poke(&w, k, e, slot: .skill2, damage: 100)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertFalse(w.s.units[e].isAlive)
        w.run(seconds: 1.5)
        XCTAssertEqual(kit(w, k).zailUltPhase, 0)
        XCTAssertEqual(kit(w, k).zailUltStrikes, 1, "死んだ相手へは続きの撃を出さない")
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k), 0)
        XCTAssertFalse(w.s.units[k].has(.root))
        XCTAssertNil(w.s.units[k].attackTargetID)
    }

    func testUltimateTargetEscapingOrDyingDuringTheDashWhiffsCleanly() {
        // 突進中に対象が遠くへ移った
        var (w, k, e) = ultWorld(enemyDX: 480)
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        w.tick(2)
        w.s.units[e].pos = w.s.units[e].pos + Vec2(900, 0)
        w.run(seconds: 0.5)
        XCTAssertEqual(kit(w, k).zailUltPhase, 0)
        XCTAssertFalse(w.s.units[e].has(.airborne))
        XCTAssertEqual(w.damage(to: e), 0)
        XCTAssertFalse(w.s.units[k].has(.root))
        // 突進中に対象が倒れた
        var (w2, k2, e2) = ultWorld(enemyDX: 480)
        XCTAssertTrue(w2.cast(k2, .ultimate, .unit(w2.id(e2))))
        w2.tick(2)
        w2.s.units[e2].isAlive = false
        w2.run(seconds: 0.5)
        XCTAssertEqual(kit(w2, k2).zailUltPhase, 0)
        XCTAssertEqual(Kit.scheduledCount(w2.s, caster: k2), 0)
    }

    func testUltimateOnCCImmuneTargetStillStrikesWithoutLifting() {
        var (w, k, e) = ultWorld()
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .ccImmune, duration: 10))
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        w.run(seconds: 2)
        XCTAssertFalse(w.s.units[e].statuses.contains { $0.kind == .airborne })
        XCTAssertEqual(kit(w, k).zailUltStrikes, 3)
        XCTAssertGreaterThan(w.damage(to: e, from: .skill(.ultimate)), 0)
    }

    func testCasterCannotStartOtherSkillsOrAttackDuringTheUltimate() {
        var (w, k, e) = ultWorld()
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        XCTAssertFalse(w.cast(k, .skill1), "突進中")
        XCTAssertFalse(w.cast(k, .skill2, .direction(Vec2(1, 0))))
        for _ in 0..<12 where kit(w, k).zailUltPhase != 2 { w.tick() }
        XCTAssertEqual(kit(w, k).zailUltPhase, 2)
        w.s.units[k].attackTargetID = w.id(e)
        w.tick()
        XCTAssertNil(w.s.units[k].attackTargetID, "三連撃の間は通常攻撃を始めない")
        XCTAssertFalse(w.cast(k, .skill1), "三連撃中")
        w.run(seconds: 1.5)
        XCTAssertEqual(kit(w, k).zailUltPhase, 0)
        w.s.units[k].resource = w.s.units[k].stats.maxResource
        XCTAssertTrue(w.cast(k, .skill1), "終われば撃てる")
    }

    func testUltimateCooldownByRankAndPracticeNoCooldowns() {
        for rank in 1...3 {
            var (w, k, e) = ultWorld(rank: rank)
            let n = w.numbers(k, .ultimate)
            XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
            XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), n.cooldown, accuracy: 1e-9)
        }
        var (w, k) = world(noCooldowns: true)
        let e = addEnemy(&w, dx: 300)
        XCTAssertTrue(w.cast(k, .skill2, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 0)
        w.run(seconds: 0.4)
        XCTAssertTrue(w.cast(k, .skill1))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), 0)
        // 剣撃の短縮も練習場では 0 のまま
        poke(&w, k, e)
        w.run(seconds: 0.3)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 0)
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), 0)
    }

    // MARK: - 死亡・割り込み

    func testDeathResetsEverythingIncludingSwordsAndUltimateState() {
        var (w, k, e) = ultWorld()
        XCTAssertTrue(w.cast(k, .skill1))
        w.run(seconds: 0.4)
        w.s.units[k].resource = w.s.units[k].stats.maxResource
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        for _ in 0..<12 where kit(w, k).zailUltPhase != 2 { w.tick() }
        XCTAssertEqual(kit(w, k).zailUltPhase, 2)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        XCTAssertEqual(kit(w, k), KitState())
        XCTAssertTrue(w.s.units[k].statuses.isEmpty)
        w.log.removeAll()
        w.run(seconds: 3)
        XCTAssertEqual(kit(w, k), KitState(), "死亡中は更新しない")
        XCTAssertEqual(w.damage(to: e, from: .skill(.skill1)), 0, "剣はもう回らない")
        XCTAssertEqual(w.damage(to: e, from: .skill(.ultimate)), 0)
    }

    func testStunnedHeroKeepsTheChargeWindowTicking() {
        var (w, k) = world()
        w.s.units[k].hero!.kit!.zailChargeWindow = 2
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        w.run(seconds: 1)
        XCTAssertEqual(kit(w, k).zailChargeWindow, 1, accuracy: 0.1)
    }

    // MARK: - 決定性

    private func script(_ w: inout SkillWorld, k: Int, e1: Int, e2: Int, m: Int, step: Int) {
        switch step {
        case 0: w.cast(k, .skill1)
        case 1: w.cast(k, .skill2, .unit(w.id(e1)))
        case 2: w.s.units[k].attackTargetID = w.id(e1)
        case 3: w.cast(k, .ultimate, .unit(w.id(e1)))
        case 4: w.cast(k, .skill2, .direction(Vec2(1, 0.3)))
        case 5: w.s.units[k].attackTargetID = w.id(e2)
        case 6: w.cast(k, .skill1)
        default: break
        }
    }

    private func makeScriptWorld() -> (SkillWorld, Int, Int, Int, Int) {
        var w = SkillWorld()
        let k = w.addHero("H028", team: .blue, at: skillArena, level: 12, ranks: [2, 2, 2], facing: 0)
        let e1 = w.addHero("H001", team: .red, at: skillArena + Vec2(380, 0), level: 12)
        let e2 = w.addHero("H004", team: .red, at: skillArena + Vec2(330, 160), level: 12)
        let m = w.addMinion(team: .red, at: skillArena + Vec2(200, -100))
        return (w, k, e1, e2, m)
    }

    private func run(_ w: inout SkillWorld, _ k: Int, _ e1: Int, _ e2: Int, _ m: Int, from: Int, to: Int) {
        for step in from..<to {
            script(&w, k: k, e1: e1, e2: e2, m: m, step: step)
            w.run(seconds: 0.9)
            // クールダウンとリソースを戻して台本が全スロットを通る
            if step % 2 == 1 {
                for slot in [SkillSlot.skill1, .skill2, .ultimate] {
                    w.s.units[k].hero!.skillCooldowns[slot.rawValue] = 0
                }
                w.s.units[k].resource = w.s.units[k].stats.maxResource
            }
        }
    }

    func testScriptedRunIsDeterministicAndExercisesTheKit() {
        var (a, ka, a1, a2, am) = makeScriptWorld()
        var (b, kb, b1, b2, bm) = makeScriptWorld()
        run(&a, ka, a1, a2, am, from: 0, to: 9)
        run(&b, kb, b1, b2, bm, from: 0, to: 9)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(a.s.units, b.s.units)
        XCTAssertEqual(a.log, b.log)
        let skillHits = a.damageEvents.filter { $0.source.isSkill }
        XCTAssertGreaterThanOrEqual(skillHits.count, 6, "台本が実際にスキルを撃っている")
        XCTAssertTrue(a.damageEvents.contains { $0.source == .skill(.ultimate) })
        XCTAssertTrue(a.damageEvents.contains { $0.source == .skill(.skill2) })
        XCTAssertTrue(a.damageEvents.contains { $0.source == .skill(.skill1) })
    }

    func testJSONRoundTripMidUltimateAndMidSwordsResumesIdentically() throws {
        var (a, ka, a1, a2, am) = makeScriptWorld()
        run(&a, ka, a1, a2, am, from: 0, to: 9)

        var (b, kb, b1, b2, bm) = makeScriptWorld()
        run(&b, kb, b1, b2, bm, from: 0, to: 3)    // 剣が回っている
        b.cast(kb, .ultimate, .unit(b.id(b1)))
        for _ in 0..<14 where kit(b, kb).zailUltPhase != 2 { b.tick() }
        b.tick(4)                                    // 三連撃の途中（予約が残っている）
        XCTAssertEqual(kit(b, kb).zailUltPhase, 2)
        XCTAssertGreaterThan(Kit.scheduledCount(b.s, caster: kb), 0)
        XCTAssertGreaterThan(kit(b, kb).zailSwordsRemaining, 0)
        let data = try JSONEncoder().encode(b.s)
        var resumed = b
        resumed.s = try JSONDecoder().decode(SimState.self, from: data)
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        b.run(seconds: 1.5)
        resumed.run(seconds: 1.5)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        run(&b, kb, b1, b2, bm, from: 4, to: 9)
        run(&resumed, kb, b1, b2, bm, from: 4, to: 9)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.damageEvents.count, b.damageEvents.count)
    }

    // MARK: - ボットの判断

    private func decisionName(_ d: BotKitDecision) -> String {
        switch d {
        case .useDefault: return "default"
        case .cast: return "cast"
        case .castNow: return "castNow"
        case .skip: return "skip"
        }
    }

    /// 奥義: 射程内の敵ヒーローが傷ついていれば関門を待たず今撃つ。満タンなら汎用の関門（cast）。剣の有無では決めない。
    func testBotUltimateCastsNowOnAWoundedHeroInReachAndNeverDependsOnSwords() throws {
        var (w, k) = world()
        let hero = addEnemy(&w, dx: 300)
        let t = HeroKits.targeting(for: try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: .ultimate)),
                                   hero: try XCTUnwrap(MasterData.shared.hero("H028")), stage: 0)
        func ask(_ target: Int, fighting: Bool = true) -> String {
            decisionName(HeroKits.botCast(w.s, w.ctx, bot: k, slot: .ultimate, targeting: t, target: target, fighting: fighting))
        }
        // 剣が回っていない満タンの敵ヒーロー: 汎用の関門に任せる（以前は HP < 80% か剣が必要で、撃てないことがあった）
        XCTAssertEqual(ask(hero), "cast")
        XCTAssertTrue(w.cast(k, .skill1), "剣が回っていても決定は変わらない")
        XCTAssertEqual(ask(hero), "cast")
        w.s.units[hero].hp = w.s.units[hero].stats.maxHP * (Tune.botExecuteRatio - 0.05)
        XCTAssertEqual(ask(hero), "castNow")
        w.s.units[hero].hp = w.s.units[hero].stats.maxHP * (Tune.botExecuteRatio + 0.1)
        XCTAssertEqual(ask(hero), "cast")
        // 射程の外・交戦中でない・ミニオン
        w.s.units[hero].hp = w.s.units[hero].stats.maxHP * 0.3
        XCTAssertEqual(ask(hero, fighting: false), "skip")
        let m = w.addMinion(team: .red, at: skillArena + Vec2(200, 0))
        XCTAssertEqual(ask(m), "skip")
        w.s.units[hero].pos = skillArena + Vec2(Tune.ultReach + 120, 0)
        XCTAssertEqual(ask(hero), "skip")
        // 突進 S2 は従来どおり（交戦中・届くとき）
        let t2 = HeroKits.targeting(for: try XCTUnwrap(MasterData.shared.skill(hero: "H028", slot: .skill2)),
                                    hero: try XCTUnwrap(MasterData.shared.hero("H028")), stage: 0)
        w.s.units[hero].pos = skillArena + Vec2(300, 0)
        XCTAssertEqual(decisionName(HeroKits.botCast(w.s, w.ctx, bot: k, slot: .skill2, targeting: t2, target: hero,
                                                     fighting: true)), "cast")
    }

    // MARK: - ボットの煙テスト

    /// ザイルをボットにして通常の 10 人戦を回す。S1 / S2 / 奥義のすべてを撃ち、状態が壊れない。
    /// ボットの奥義は「倒せる・2 人以上を巻き込める」ときだけなので、撃つまで種を変えて回す（最大 8 試合）。
    func testBotSmokeCastsEverySlotAndStateStaysBounded() throws {
        var casts: [SkillSlot: Int] = [:]
        var maxStacks = 0
        var strikes = 0
        var ultStrikes = 0
        var played = 0
        for seed in UInt64(41)..<UInt64(49) {
            played += 1
            var cfg = MatchFactory.botMatch(seed: seed)
            let idx = try XCTUnwrap(cfg.players.firstIndex { $0.team == .blue && $0.position == .jungle })
            if let other = cfg.players.firstIndex(where: { $0.heroID == "H028" }), other != idx {
                cfg.players[other].heroID = cfg.players[idx].heroID
            }
            cfg.players[idx].heroID = "H028"
            let sim = Simulation(config: cfg)
            let hero = try XCTUnwrap(sim.state.heroIndices.first { sim.state.units[$0].hero?.heroID == "H028" })
            let heroID = sim.state.units[hero].id
            XCTAssertNotNil(sim.state.units[hero].hero?.kit)
            while !sim.isEnded && sim.state.time < 1500 {
                let events = sim.step()
                for e in events {
                    if case .skillCast(let c) = e, c.casterID == heroID { casts[c.slot, default: 0] += 1 }
                }
                let i = sim.state.index(of: heroID)!
                let u = sim.state.units[i]
                let k = u.hero!.kit!
                strikes = max(strikes, k.zailSwordStrikes)
                ultStrikes = max(ultStrikes, k.zailUltStrikes)
                XCTAssertTrue(u.hp.isFinite && u.pos.x.isFinite && u.pos.y.isFinite && u.resource.isFinite)
                XCTAssertTrue(k.reals.allSatisfy { $0.isFinite })
                XCTAssertTrue(k.timers.allSatisfy { $0.isFinite && $0 >= 0 })
                XCTAssertLessThanOrEqual(k.scheduled.count, 16)
                XCTAssertLessThanOrEqual(u.statuses.count, 24)
                XCTAssertTrue((0...2).contains(k.zailUltPhase))
                for j in sim.state.units.indices where sim.state.units[j].team != u.team {
                    for st in sim.state.units[j].statuses where st.kind == .mark && st.tag.hasPrefix("kit.H028.bane.") {
                        maxStacks = max(maxStacks, Int(st.magnitude.rounded()))
                    }
                }
                // 全スロットを撃ち、三連撃が当たるまで進める
                if casts[.skill1, default: 0] > 0, casts[.skill2, default: 0] > 0, casts[.ultimate, default: 0] > 0,
                   ultStrikes > 0, sim.state.time > 150 { break }
            }
            if casts[.ultimate, default: 0] > 0, ultStrikes > 0 { break }
        }
        XCTAssertGreaterThan(casts[.skill1, default: 0], 0, "S1: \(casts)")
        XCTAssertGreaterThan(casts[.skill2, default: 0], 0, "S2: \(casts)")
        XCTAssertGreaterThan(casts[.ultimate, default: 0], 0, "奥義: \(casts) (試合 \(played))")
        XCTAssertGreaterThan(ultStrikes, 0, "奥義の三連撃が当たった")
        XCTAssertGreaterThanOrEqual(maxStacks, 1)
        XCTAssertLessThanOrEqual(maxStacks, 5)
        print("H028 bot smoke: \(casts) strikes \(strikes) ultStrikes \(ultStrikes) stacks \(maxStacks) matches \(played)")
    }

    // MARK: - 1v1 の TTK（H001–H006 相手、Lv 1 / 6 / 12）

    func testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives() {
        var failures: [String] = []
        var wins = 0
        var total = 0
        var table = "H028 TTK\n"
        for level in SkillBalanceTests.levels {
            for foe in SkillBalanceTests.representatives {
                let r = SkillBalanceTests.duel("H028", foe, level: level)
                total += 1
                if r.winnerIsA == true { wins += 1 }
                table += String(format: "Lv%d vs %@: %.1f s %@\n", level, foe, r.ttk,
                                r.winnerIsA.map { $0 ? "win" : "lose" } ?? "draw")
                if r.ttk < SkillBalanceTests.minTTK || r.ttk > SkillBalanceTests.maxTTK {
                    failures.append(String(format: "Lv%d %@: %.2f s", level, foe, r.ttk))
                }
            }
        }
        print(table + "wins \(wins)/\(total)")
        XCTAssertTrue(failures.isEmpty, "TTK が範囲外: \(failures)")
        XCTAssertGreaterThanOrEqual(wins, total / 4, "弱すぎる: \(wins)/\(total)")
    }

    /// 全員総当たりの勝率を、汎用アサシン（H006 / H012 / H018 / H024）と同じ測り方で並べる。Release のみ（数百の決闘）。
    func testRoundRobinWinRateStaysNearTheGenericAssassins() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter Kit_H028Tests")
        #else
        let ids = MasterData.shared.heroes.map(\.heroID)
        var table = "round-robin win rate (全員総当たり、決着のみ)\n"
        var rates: [String: [Int: Double]] = [:]
        for hero in ["H028", "H006", "H012", "H018", "H024"] {
            for level in SkillBalanceTests.levels {
                var wins = 0, decided = 0
                for foe in ids where foe != hero {
                    let r = SkillBalanceTests.duel(hero, foe, level: level)
                    if let win = r.winnerIsA {
                        decided += 1
                        if win { wins += 1 }
                    }
                }
                rates[hero, default: [:]][level] = decided > 0 ? Double(wins) / Double(decided) : 0
            }
            let row = SkillBalanceTests.levels.map { String(format: "Lv%d %.0f%%", $0, 100 * (rates[hero]?[$0] ?? 0)) }
            table += "\(hero): " + row.joined(separator: "  ") + "\n"
        }
        print(table)
        for level in SkillBalanceTests.levels {
            let zail = rates["H028"]?[level] ?? 0
            XCTAssertGreaterThan(zail, 0.15, "弱すぎる Lv\(level): \(zail)")
            XCTAssertLessThan(zail, 0.85, "強すぎる Lv\(level): \(zail)")
        }
        #endif
    }
}
