import XCTest
@testable import VelstriaCore

/// H026 紫電のエウリア（Eudora）のキット。仕様: docs/kits/Eudora.md、実装対応表: 同ファイル末尾。
/// 敵は動かない通常のヒーロー（H001 / H003 ほか）。エウリアは blue・東向き。
final class Kit_H026Tests: XCTestCase {
    typealias T = EuriaTuning
    static let east = Vec2(1, 0)

    /// キットは testOverride に差す（本番の有効化とは独立。有効化後も同じ結果）。
    override func setUp() {
        super.setUp()
        HeroKits.testOverride = [Kit_H026(isReady: true)]
    }

    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    // MARK: - 土台

    private func world(level: Int = 12, ranks: [Int]? = [1, 1, 1], noCooldowns: Bool = false) -> (SkillWorld, Int) {
        var w = SkillWorld(noCooldowns: noCooldowns)
        let k = w.addHero("H026", team: .blue, at: skillArena, level: level, ranks: ranks, facing: 0)
        return (w, k)
    }

    @discardableResult
    private func addEnemy(_ w: inout SkillWorld, dx: Double, dy: Double = 0, hero: String = "H001", level: Int = 12) -> Int {
        w.addHero(hero, team: .red, at: skillArena + Vec2(dx, dy), level: level, ranks: [1, 1, 1])
    }

    private func kit(_ w: SkillWorld, _ k: Int) -> KitState { w.s.units[k].hero!.kit! }

    private var def: HeroDef { MasterData.shared.hero("H026")! }

    private func skill(_ slot: SkillSlot) -> SkillDef { MasterData.shared.skill(hero: "H026", slot: slot)! }

    private func numbers(_ w: SkillWorld, _ k: Int, _ slot: SkillSlot) -> SkillNumbers {
        SkillCatalog.numbers(for: skill(slot), hero: def, rank: max(1, w.s.units[k].hero!.rank(slot)),
                             stats: w.s.units[k].stats)
    }

    private func markTag(_ w: SkillWorld, _ k: Int) -> String { KitTags.mark("H026", T.markName, owner: w.id(k)) }

    /// 超伝導を付ける（所有者 = エウリア）。
    private func mark(_ w: inout SkillWorld, owner k: Int, on e: Int, duration: Double = T.markDuration) {
        Kit.addMark(&w.s, target: e, ownerID: w.id(k), tag: markTag(w, k), maxStacks: 1, duration: duration)
    }

    private func marked(_ w: SkillWorld, owner k: Int, on e: Int) -> Bool {
        Kit.markStacks(w.s, target: e, tag: markTag(w, k)) > 0
    }

    private func events(_ w: SkillWorld, to e: Int, _ source: DamageSource) -> [DamageEvent] {
        w.damageEvents.filter { $0.targetID == w.id(e) && $0.source == source }
    }

    private func status(_ w: SkillWorld, _ e: Int, _ kind: StatusKind) -> StatusEffect? {
        w.s.units[e].statuses.first { $0.kind == kind }
    }

    private func zoneCreated(_ w: SkillWorld) -> [(visual: String, center: Vec2, radius: Double, delay: Double)] {
        w.log.compactMap {
            if case .zoneCreated(_, _, _, let visual, let center, let radius, let delay, _, _) = $0 {
                return (visual, center, radius, delay)
            }
            return nil
        }
    }

    // MARK: - レジストリ・照準・説明

    func testRegistryAndTargetingPerSlot() throws {
        XCTAssertTrue(HeroKits.hasKit("H026"))
        // 本番のレジストリでも有効（テストの差し込み無しで引ける）
        XCTAssertTrue(Kit_H026().isReady)
        HeroKits.testOverride = []
        XCTAssertTrue(HeroKits.hasKit("H026"))
        HeroKits.testOverride = [Kit_H026(isReady: true)]
        XCTAssertNotNil(HeroKits.kit(for: "H026"))
        let s1 = SkillCatalog.targeting(for: skill(.skill1), hero: def)
        XCTAssertEqual(s1.archetype, .cone)
        XCTAssertEqual(s1.aim, .direction)
        XCTAssertEqual(s1.shape, .fan)
        XCTAssertEqual(s1.halfAngle, T.s1HalfAngle)
        XCTAssertEqual(s1.range, 650)
        XCTAssertEqual(s1.reach, 650)
        XCTAssertFalse(s1.requiresTarget)
        let s2 = SkillCatalog.targeting(for: skill(.skill2), hero: def)
        XCTAssertEqual(s2.archetype, .lineSkillshot, "ブリンク強化ではなく対象指定の雷球")
        XCTAssertEqual(s2.aim, .unit)
        XCTAssertEqual(s2.shape, .lockOn)
        XCTAssertEqual(s2.range, 650)
        XCTAssertEqual(s2.reach, 650)
        XCTAssertTrue(s2.requiresTarget)
        let ult = SkillCatalog.targeting(for: skill(.ultimate), hero: def)
        XCTAssertEqual(ult.archetype, .groundAoE)
        XCTAssertEqual(ult.aim, .point)
        XCTAssertEqual(ult.shape, .circleAtPoint)
        XCTAssertEqual(ult.range, 770)
        XCTAssertEqual(ult.radius, T.ultOuterRadius)
        XCTAssertEqual(SkillCatalog.targeting(for: skill(.passive), hero: def).archetype, .passive)
        // 再使用の段は無い
        for slot in SkillSlot.allCases {
            XCTAssertEqual(HeroKits.targeting(for: skill(slot), hero: def, stage: 1),
                           HeroKits.targeting(for: skill(slot), hero: def, stage: 0), "\(slot)")
        }
        // 実ユニット: キット状態が付く。再使用の窓は無い
        let (w, k) = world()
        XCTAssertNotNil(w.s.units[k].hero?.kit)
        for slot in SkillSlot.allCases { XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: slot)) }
        // 汎用の遠隔ヒーロー（レンジャー H003）は影響を受けない
        XCTAssertFalse(HeroKits.hasKit("H003"))
    }

    func testTextFillsEverySlotWithSimNumbers() throws {
        let (w, k) = world(level: 6, ranks: [2, 2, 2])
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H026", slot: slot), "\(slot)")
            let n = numbers(w, k, slot)
            let t = SkillCatalog.targeting(for: skill(slot), hero: def)
            for english in [false, true] {
                let s = text.filled(english: english, numbers: n, targeting: t)
                XCTAssertFalse(s.contains("{"), "\(slot) en=\(english): \(s)")
                XCTAssertFalse(s.isEmpty)
            }
        }
        func ja(_ slot: SkillSlot) -> String {
            HeroKits.text(heroID: "H026", slot: slot)!.filled(english: false, numbers: numbers(w, k, slot),
                                                               targeting: SkillCatalog.targeting(for: skill(slot), hero: def))
        }
        let n1 = numbers(w, k, .skill1)
        XCTAssertTrue(ja(.skill1).contains("\(Int(n1.damage.rounded()))の魔法ダメージ"), ja(.skill1))
        XCTAssertTrue(ja(.skill1).contains("40%"), ja(.skill1))
        XCTAssertTrue(ja(.skill1).contains("0.8秒") || ja(.skill1).contains("縮む"), ja(.skill1))
        let n2 = numbers(w, k, .skill2)
        XCTAssertTrue(ja(.skill2).contains("\(Int(n2.damage.rounded()))の魔法ダメージ"), ja(.skill2))
        XCTAssertTrue(ja(.skill2).contains("1秒のスタン") || ja(.skill2).contains("1秒"), ja(.skill2))
        let nu = numbers(w, k, .ultimate)
        XCTAssertTrue(ja(.ultimate).contains("\(Int(nu.damage.rounded()))"), ja(.ultimate))
        XCTAssertTrue(ja(.ultimate).contains("0.8秒後"), ja(.ultimate))
        XCTAssertTrue(ja(.ultimate).contains("770"), ja(.ultimate))
        XCTAssertTrue(ja(.passive).contains("5秒"), ja(.passive))
    }

    // MARK: - 数値・ダメージ予算

    func testNumbersStayWithinDamageBudgetAndFollowCooldownFormula() {
        for level in [1, 6, 12] {
            let stats = HeroGrowth.baseStats(def: def, level: level)
            for rank in 1...Balance.basicSkillMaxRank {
                // S1: 鎖が結ばれたときの合計（2 撃 + 継続ダメージ 4 回）が汎用 S1 の 0.8〜1.3 倍
                let g1 = SkillCatalog.genericNumbers(for: skill(.skill1), hero: def, rank: rank, stats: stats)
                let n1 = SkillCatalog.numbers(for: skill(.skill1), hero: def, rank: rank, stats: stats)
                let total1 = n1.damage * Double(n1.hits) + n1.damage * T.dotRatio * Double(T.dotCount)
                XCTAssertEqual(n1.hits, 2)
                XCTAssertGreaterThanOrEqual(total1 / g1.damage, 0.8, "S1 Lv\(level) r\(rank)")
                XCTAssertLessThanOrEqual(total1 / g1.damage, 1.3, "S1 Lv\(level) r\(rank)")
                // S2: 汎用の遠隔 S2 は「ブリンク + 強化攻撃」で半分になっているので、元のスキル値を基準にする
                let g2 = SkillCatalog.genericNumbers(for: skill(.skill2), hero: def, rank: rank, stats: stats)
                let n2 = SkillCatalog.numbers(for: skill(.skill2), hero: def, rank: rank, stats: stats)
                let ratio2 = n2.damage / (g2.damage / Balance.Skills.empowerRatio)
                XCTAssertGreaterThanOrEqual(ratio2, 0.8, "S2 Lv\(level) r\(rank)")
                XCTAssertLessThanOrEqual(ratio2, 1.3, "S2 Lv\(level) r\(rank)")
            }
            for rank in 1...SkillSlot.ultimate.maxRank {
                // 奥義: 中心 + 雷の炸裂（印済みの単体）が汎用の 0.8〜1.3 倍。中心だけでも 0.8 倍以上
                let g = SkillCatalog.genericNumbers(for: skill(.ultimate), hero: def, rank: rank, stats: stats)
                let n = SkillCatalog.numbers(for: skill(.ultimate), hero: def, rank: rank, stats: stats)
                XCTAssertGreaterThanOrEqual(n.damage / g.damage, 0.8, "ULT center Lv\(level) r\(rank)")
                let marked = (n.damage + n.damage * T.burstRatio) / g.damage
                XCTAssertLessThanOrEqual(marked, 1.3, "ULT marked Lv\(level) r\(rank)")
                XCTAssertGreaterThanOrEqual(marked, 0.8)
                XCTAssertEqual(n.delay, T.ultDelay)
                XCTAssertEqual(n.cc, .none, "調査どおり奥義に CC は無い")
            }
        }
        // ランクで強くなる
        let stats = HeroGrowth.baseStats(def: def, level: 6)
        for slot in SkillSlot.actives {
            let lo = SkillCatalog.numbers(for: skill(slot), hero: def, rank: 1, stats: stats)
            let hi = SkillCatalog.numbers(for: skill(slot), hero: def, rank: slot.maxRank, stats: stats)
            XCTAssertGreaterThan(hi.damage, lo.damage, "\(slot)")
            XCTAssertLessThan(hi.cooldown, lo.cooldown, "\(slot)")
            // コストはマスターのまま（SkillSystem が定義から引く）
            XCTAssertEqual(hi.cost, lo.cost)
            XCTAssertEqual(hi.resource, .mana)
        }
        // クールダウン = MLBB の秒数（ランクで線形）× 全体倍率 × (1 − CD 短縮)
        let cdr = stats.cooldownReduction
        func cd(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
            (a + (b - a) * Double(rank - 1) / Double(maxRank - 1)) * (1 - cdr) * Balance.Skills.cooldownScale
        }
        for rank in 1...4 {
            XCTAssertEqual(SkillCatalog.numbers(for: skill(.skill1), hero: def, rank: rank, stats: stats).cooldown,
                           cd(7, 5, rank: rank, maxRank: 4), accuracy: 1e-9)
            XCTAssertEqual(SkillCatalog.numbers(for: skill(.skill2), hero: def, rank: rank, stats: stats).cooldown,
                           cd(11, 8.5, rank: rank, maxRank: 4), accuracy: 1e-9)
        }
        for rank in 1...3 {
            XCTAssertEqual(SkillCatalog.numbers(for: skill(.ultimate), hero: def, rank: rank, stats: stats).cooldown,
                           cd(32, 26, rank: rank, maxRank: 3), accuracy: 1e-9)
        }
        // S2: スタン 1 秒・魔防ダウン 10 → 25（固定値）・1.8 秒
        let n2 = SkillCatalog.numbers(for: skill(.skill2), hero: def, rank: 1, stats: stats)
        XCTAssertEqual(n2.cc, .stun)
        XCTAssertEqual(n2.ccDuration, 1.0)
        XCTAssertEqual(n2.extras.map(\.value), [10, 1.8, T.splashRadius, 1.0])
        XCTAssertEqual(SkillCatalog.numbers(for: skill(.skill2), hero: def, rank: 4, stats: stats).extras[0].value, 25)
        // S1 の鎖: 1 秒・+40%・1.5 秒 × クールダウン倍率の短縮
        let n1 = SkillCatalog.numbers(for: skill(.skill1), hero: def, rank: 1, stats: stats)
        XCTAssertEqual(n1.extras[0].value, 1.0)
        XCTAssertEqual(n1.extras[1].value, 40)
        XCTAssertEqual(n1.extras[2].value, 1.5 * Balance.Skills.cooldownScale, accuracy: 1e-9)
        XCTAssertEqual(SkillCatalog.numbers(for: skill(.passive), hero: def, rank: 1, stats: stats).extras.map(\.value), [5])
    }

    // MARK: - パッシブ: 超伝導

    func testEverySkillMarksHeroesAndMonstersButNotMinionsAndTheMarkExpires() {
        var (w, k) = world(noCooldowns: true)
        let hero1 = addEnemy(&w, dx: 300)
        let hero2 = addEnemy(&w, dx: 300, dy: 120, hero: "H003")
        let hero3 = addEnemy(&w, dx: 300, dy: -120, hero: "H004")
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(250, 0))
        // S1: 扇に入った敵（ミニオンを除く）
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertTrue(marked(w, owner: k, on: hero1))
        XCTAssertTrue(marked(w, owner: k, on: hero2))
        XCTAssertTrue(marked(w, owner: k, on: hero3))
        XCTAssertFalse(marked(w, owner: k, on: minion), "ミニオンには付かない")
        XCTAssertFalse(w.s.units[minion].statuses.contains { $0.kind == .mark })
        // 印の持続は 5 秒
        let st = w.s.units[hero1].statuses.first { $0.kind == .mark }!
        XCTAssertEqual(st.remaining, T.markDuration, accuracy: 1e-9)
        XCTAssertEqual(st.magnitude, 1)
        w.run(seconds: 4.8)
        XCTAssertTrue(marked(w, owner: k, on: hero1))
        w.run(seconds: 0.4)
        XCTAssertFalse(marked(w, owner: k, on: hero1))
        // S2 / 奥義も印を付ける
        var (w2, k2) = world(noCooldowns: true)
        let a = addEnemy(&w2, dx: 400)
        let b = addEnemy(&w2, dx: 400, dy: 100, hero: "H003")
        XCTAssertTrue(w2.cast(k2, .skill2, .unit(w2.id(a))))
        w2.run(seconds: 0.5)
        XCTAssertTrue(marked(w2, owner: k2, on: a))
        XCTAssertFalse(marked(w2, owner: k2, on: b), "印の無い S2 は広がらない")
        XCTAssertTrue(w2.cast(k2, .ultimate, .point(skillArena + Vec2(400, 100))))
        w2.run(seconds: 1.0)
        XCTAssertTrue(marked(w2, owner: k2, on: b))
        // 別のエウリアの印は区別される（所有者ごと）
        XCTAssertNotEqual(KitTags.mark("H026", T.markName, owner: 1), KitTags.mark("H026", T.markName, owner: 2))
    }

    func testMonstersAreMarkedToo() {
        var (w, k) = world()
        let monster = w.addMonster(.campSmall, at: skillArena + Vec2(250, 0))
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertTrue(marked(w, owner: k, on: monster))
    }

    func testTheMarkItselfDoesNotAddDamageAndTheGenericArcanistRefundIsGone() throws {
        // 印済みでも S2 の主対象へのダメージは同じ
        var (w, k) = world()
        let a = addEnemy(&w, dx: 400)
        let n2 = numbers(w, k, .skill2)
        let expected = w.mitigated(n2.damage, .magic, on: a)
        mark(&w, owner: k, on: a)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(a))))
        w.run(seconds: 0.6)
        XCTAssertEqual(events(w, to: a, .skill(.skill2)).first?.amount ?? 0, expected, accuracy: 1e-6)
        // 汎用アルカニストのパッシブ（スキル命中で他スキルの CD −0.6 秒）は走らない
        var (w2, k2) = world()
        let e = addEnemy(&w2, dx: 300)
        let cd2 = numbers(w2, k2, .skill2).cooldown
        w2.s.units[k2].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = cd2
        XCTAssertTrue(w2.cast(k2, .skill1, .direction(Self.east)))
        XCTAssertGreaterThan(w2.damage(to: e), 0)
        XCTAssertEqual(w2.s.units[k2].hero!.cooldown(.skill2), cd2, accuracy: 1e-9)
    }

    // MARK: - S1: Euria式・一閃

    func testForkedLightningHitsAFanInFrontWithinRange() {
        var (w, k) = world()
        let inside = addEnemy(&w, dx: 400)
        let edge = addEnemy(&w, dx: 500, dy: 500 * tan(T.s1HalfAngle) - 20, hero: "H003")
        let wide = addEnemy(&w, dx: 500, dy: 500 * tan(T.s1HalfAngle) + 120, hero: "H004")
        let farEnd = addEnemy(&w, dx: 650 + 30, dy: 0, hero: "H005")
        let tooFar = addEnemy(&w, dx: 650 + 80, dy: 0, hero: "H006")
        let behind = addEnemy(&w, dx: -300, hero: "H002")
        let n = numbers(w, k, .skill1)
        let mana = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertLessThan(w.s.units[k].resource, mana, "コストを消費")
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), n.cooldown, accuracy: 1e-9)
        let ev = w.castEvents.last!
        XCTAssertEqual(ev.slot, .skill1)
        XCTAssertEqual(ev.shape, .fan)
        XCTAssertEqual(ev.halfAngle, T.s1HalfAngle)
        XCTAssertEqual(ev.archetype, .cone)
        // 即時に当たる
        for e in [inside, edge, farEnd] {
            let hits = events(w, to: e, .skill(.skill1))
            XCTAssertEqual(hits.count, 1, "\(e)")
            XCTAssertEqual(hits[0].amount, w.mitigated(n.damage, .magic, on: e), accuracy: 1e-6)
        }
        XCTAssertEqual(w.damage(to: wide), 0, "扇の外")
        XCTAssertEqual(w.damage(to: tooFar), 0, "射程外")
        XCTAssertEqual(w.damage(to: behind), 0, "背後")
        // 未印の敵には鎖は結ばれない
        XCTAssertEqual(kit(w, k).euriaChains, 0)
        XCTAssertNil(status(w, k, .speedBoost))
        XCTAssertTrue(kit(w, k).scheduled.isEmpty)
    }

    func testForkedLightningDoublesAgainstMinionsAndSkipsMarking() {
        var (w, k) = world()
        let m = w.addMinion(team: .red, at: skillArena + Vec2(300, 0))
        let e = addEnemy(&w, dx: 300, dy: 80)
        w.s.units[m].hp = 1e6
        let n = numbers(w, k, .skill1)
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(events(w, to: m, .skill(.skill1)).first?.amount ?? 0, w.mitigated(n.damage * 2, .magic, on: m) * Balance.Skills.minionDamageMultiplier,
                       accuracy: 1e-6, "ミニオンには 200%（さらにミニオンへのスキル倍率）")
        XCTAssertEqual(events(w, to: e, .skill(.skill1)).first?.amount ?? 0, w.mitigated(n.damage, .magic, on: e),
                       accuracy: 1e-6)
        // S2 はミニオンにも倍にならない
        var (w2, k2) = world()
        let m2 = w2.addMinion(team: .red, at: skillArena + Vec2(300, 0))
        w2.s.units[m2].hp = 1e6
        let n2 = numbers(w2, k2, .skill2)
        XCTAssertTrue(w2.cast(k2, .skill2, .unit(w2.id(m2))))
        w2.run(seconds: 0.5)
        XCTAssertEqual(events(w2, to: m2, .skill(.skill2)).first?.amount ?? 0, w2.mitigated(n2.damage, .magic, on: m2) * Balance.Skills.minionDamageMultiplier,
                       accuracy: 1e-6)
    }

    func testChainOnAMarkedTargetGivesSpeedDamageOverTimeFinalHitAndCooldownRefund() throws {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 400)
        let n = numbers(w, k, .skill1)
        mark(&w, owner: k, on: e)
        let speed = w.s.units[k].stats.moveSpeed
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(kit(w, k).euriaChains, 1)
        XCTAssertEqual(kit(w, k).scheduled.count, T.dotCount + 1)
        let boost = try XCTUnwrap(status(w, k, .speedBoost))
        XCTAssertEqual(boost.magnitude, 0.4, accuracy: 1e-9)
        XCTAssertEqual(boost.remaining, 1.0, accuracy: 1e-9)
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .skill1)?.kind, .timer)
        XCTAssertEqual(w.damageEvents.count, 1, "初撃のみ")
        w.tick(1)
        XCTAssertEqual(w.s.units[k].stats.moveSpeed, speed * 1.4, accuracy: 1e-6, "鎖の間 +40%")
        // 継続ダメージは 0.2 秒ごとに 4 回、1 秒で終わりの一撃
        let dot = w.mitigated(n.damage * T.dotRatio, .magic, on: e)
        w.run(seconds: 0.25)
        XCTAssertEqual(events(w, to: e, .skill(.skill1)).count, 2)
        w.run(seconds: 0.6)
        XCTAssertEqual(events(w, to: e, .skill(.skill1)).count, 5)
        XCTAssertEqual(kit(w, k).euriaChainEnds, 0)
        let cdBefore = w.s.units[k].hero!.cooldown(.skill1)
        w.run(seconds: 0.2)
        let hits = events(w, to: e, .skill(.skill1))
        XCTAssertEqual(hits.count, 6)
        XCTAssertEqual(hits[0].amount, w.mitigated(n.damage, .magic, on: e), accuracy: 1e-6)
        for h in hits[1...4] { XCTAssertEqual(h.amount, dot, accuracy: 1e-6) }
        XCTAssertEqual(hits[5].amount, w.mitigated(n.damage, .magic, on: e), accuracy: 1e-6, "終わりの一撃は初撃と同じ")
        XCTAssertEqual(kit(w, k).euriaChainEnds, 1)
        // 終わりの一撃が当たると S1 のクールダウンが縮む
        let cdAfter = w.s.units[k].hero!.cooldown(.skill1)
        XCTAssertLessThan(cdAfter, cdBefore - T.chainRefund + 0.01)
        XCTAssertEqual(cdAfter, max(0, n.cooldown - 1.1 - T.chainRefund), accuracy: 0.04)
        // 鎖が終わると加速も終わる
        XCTAssertNil(status(w, k, .speedBoost))
        XCTAssertEqual(kit(w, k).euriaChainRemaining, 0)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .skill1))
        XCTAssertTrue(kit(w, k).scheduled.isEmpty)
    }

    func testChainIsBrokenWhenTheTargetDiesLeavesRangeOrTheCasterIsStunned() throws {
        func chain(_ prepare: (inout SkillWorld, Int, Int) -> Void) -> (SkillWorld, Int, Int) {
            var (w, k) = world()
            let e = addEnemy(&w, dx: 400)
            mark(&w, owner: k, on: e)
            XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
            w.run(seconds: 0.1)
            prepare(&w, k, e)
            w.run(seconds: 1.4)
            return (w, k, e)
        }
        let n = numbers(world().0, world().1, .skill1)
        // 対象が離れすぎた
        var (w, k, e) = chain { w, _, e in w.s.units[e].pos = skillArena + Vec2(1500, 0) }
        XCTAssertEqual(events(w, to: e, .skill(.skill1)).count, 1, "初撃のみ")
        XCTAssertNil(status(w, k, .speedBoost))
        XCTAssertEqual(kit(w, k).euriaChainEnds, 0)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), max(0, n.cooldown - 1.5), accuracy: 0.04, "クールダウンは縮まない")
        XCTAssertTrue(kit(w, k).scheduled.isEmpty)
        // 対象が倒れた（継続ダメージで）
        (w, k, e) = chain { w, _, e in w.s.units[e].hp = 1 }
        XCTAssertFalse(w.s.units[e].isAlive)
        XCTAssertEqual(kit(w, k).euriaChainEnds, 0)
        XCTAssertNil(status(w, k, .speedBoost))
        XCTAssertTrue(kit(w, k).scheduled.isEmpty)
        // 術者がスタンされた: 鎖は取り消し（それまでの継続ダメージは残る）
        (w, k, e) = chain { w, k, _ in CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 0.5)) }
        XCTAssertEqual(events(w, to: e, .skill(.skill1)).count, 1, "スタンまでに継続ダメージは入っていない（0.2 秒前）")
        XCTAssertNil(status(w, k, .speedBoost), "加速も終わる")
        XCTAssertEqual(kit(w, k).euriaChainRemaining, 0)
        XCTAssertEqual(kit(w, k).euriaChainEnds, 0)
        XCTAssertTrue(kit(w, k).scheduled.isEmpty)
        // 対象が対象不可になった
        (w, k, e) = chain { w, _, e in
            CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .untargetable, duration: 5))
        }
        XCTAssertEqual(kit(w, k).euriaChainEnds, 0)
        XCTAssertTrue(kit(w, k).scheduled.isEmpty)
    }

    func testChainOnTwoMarkedTargetsAndRecastRestartsTheSameChain() {
        var (w, k) = world(noCooldowns: true)
        let a = addEnemy(&w, dx: 400)
        let b = addEnemy(&w, dx: 400, dy: 100, hero: "H003")
        mark(&w, owner: k, on: a)
        mark(&w, owner: k, on: b)
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(kit(w, k).euriaChains, 2)
        XCTAssertEqual(kit(w, k).scheduled.count, 2 * (T.dotCount + 1))
        w.run(seconds: 1.1)
        XCTAssertEqual(kit(w, k).euriaChainEnds, 2)
        XCTAssertEqual(events(w, to: a, .skill(.skill1)).count, 6)
        XCTAssertEqual(events(w, to: b, .skill(.skill1)).count, 6)
        XCTAssertNil(status(w, k, .speedBoost))
        // 前の鎖から 3 秒以内（印が残っていても）は、同じ相手に鎖を結び直さない（鎖が無限に繋がらない）
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(kit(w, k).scheduled.count, 0, "ロックアウト中は新しい鎖なし")
        XCTAssertEqual(kit(w, k).euriaChains, 2)
        // 3 秒たてば再び結べる（予約は対象ごとに 1 組 = 張り直しでも増えない）
        w.run(seconds: T.chainLockout)
        mark(&w, owner: k, on: a)
        mark(&w, owner: k, on: b)
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(kit(w, k).euriaChains, 4)
        XCTAssertEqual(kit(w, k).scheduled.count, 2 * (T.dotCount + 1))
        w.run(seconds: 0.3)
        // 再び鎖の途中で当てても、ロックアウト中なので張り直しにならない（予約は増えない。0.3 秒で継続ダメージが 1 回ずつ進んだ分だけ減っている）
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(kit(w, k).scheduled.count, 2 * T.dotCount)
        XCTAssertEqual(kit(w, k).euriaChains, 4)
    }

    /// 印は消費しない。鎖のロックアウトは「同じ相手」だけで、別の相手には結べる。
    func testChainLockoutIsPerTargetAndTheMarkIsNeverConsumed() {
        var (w, k) = world(noCooldowns: true)
        let a = addEnemy(&w, dx: 400)
        let b = addEnemy(&w, dx: 400, dy: 100, hero: "H003")
        mark(&w, owner: k, on: a)
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(kit(w, k).euriaChains, 1)
        XCTAssertEqual(kit(w, k).euriaChainLockout(for: w.id(a)), T.chainLockout, accuracy: 0.05)
        XCTAssertEqual(kit(w, k).euriaChainLockout(for: w.id(b)), 0, "b にはまだ鎖が無い")
        XCTAssertTrue(marked(w, owner: k, on: a), "印は消費されない")
        w.run(seconds: 1.2)
        XCTAssertTrue(marked(w, owner: k, on: a))
        // 別の相手（b は最初の S1 で印が付いている）にはすぐ結べる
        XCTAssertTrue(marked(w, owner: k, on: b))
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(kit(w, k).euriaChains, 2, "a はロックアウト中、b は新しい鎖")
        XCTAssertGreaterThan(kit(w, k).euriaChainLockout(for: w.id(b)), 0)
        // ロックアウトは自動で明ける
        w.run(seconds: T.chainLockout + 0.1)
        XCTAssertEqual(kit(w, k).euriaChainLockout(for: w.id(a)), 0)
        XCTAssertEqual(kit(w, k).euriaChainLockout(for: w.id(b)), 0)
        mark(&w, owner: k, on: a)
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(kit(w, k).euriaChains, 4, "a と b の両方に結び直す")
    }

    func testChainEndRefundRespectsPracticeNoCooldowns() {
        var (w, k) = world(noCooldowns: true)
        let e = addEnemy(&w, dx: 400)
        mark(&w, owner: k, on: e)
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), 0)
        w.run(seconds: 1.2)
        XCTAssertEqual(kit(w, k).euriaChainEnds, 1)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), 0)
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)), "練習場は CD なし")
    }

    // MARK: - S2: 星環シフト（Ball Lightning）

    func testOrbFliesToTheTargetThenDealsDamageStunAndMagicShred() throws {
        var (w, k) = world()
        let a = addEnemy(&w, dx: 500)
        let n = numbers(w, k, .skill2)
        let before = w.mitigated(n.damage, .magic, on: a)
        let resist = w.s.units[a].stats.magicResist
        let mana = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(a))))
        XCTAssertLessThan(w.s.units[k].resource, mana)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), n.cooldown, accuracy: 1e-9)
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.shape, .lockOn)
        XCTAssertEqual(ev.slot, .skill2)
        XCTAssertEqual(ev.targetUnitID, w.id(a))
        XCTAssertEqual(w.damage(to: a), 0, "雷球が届くまでダメージは無い")
        XCTAssertEqual(w.s.projectiles.count, 1)
        w.run(seconds: 0.4)
        let hits = events(w, to: a, .skill(.skill2))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].amount, before, accuracy: 1e-6)
        let stun = try XCTUnwrap(status(w, a, .stun))
        XCTAssertLessThanOrEqual(stun.remaining, 1.0)
        XCTAssertGreaterThan(stun.remaining, 0.6)
        XCTAssertFalse(w.s.units[a].canAct)
        // 魔防ダウン（固定値 10）1.8 秒
        let shred = try XCTUnwrap(status(w, a, .magicShred))
        XCTAssertEqual(shred.magnitude, 10, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(shred.remaining, 1.8)
        XCTAssertEqual(w.s.units[a].stats.magicResist, resist - 10, accuracy: 1e-9)
        // スタン 1 秒で解け、魔防ダウンは 1.8 秒で解ける
        w.run(seconds: 0.9)
        XCTAssertTrue(w.s.units[a].canAct)
        XCTAssertNotNil(status(w, a, .magicShred))
        w.run(seconds: 1.0)
        XCTAssertNil(status(w, a, .magicShred))
        XCTAssertEqual(w.s.units[a].stats.magicResist, resist, accuracy: 1e-9)
    }

    func testOrbShredGrowsWithRankAndDoesNotDropResistBelowZero() throws {
        var (w, k) = world(ranks: [1, 4, 1])
        let a = addEnemy(&w, dx: 400)
        w.s.units[a].stats.magicResist = 5
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(a))))
        w.run(seconds: 0.5)
        let shred = try XCTUnwrap(status(w, a, .magicShred))
        XCTAssertEqual(shred.magnitude, 25, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(w.s.units[a].stats.magicResist, 0)
    }

    func testOrbRequiresATargetInReachAndPicksTheNearestHeroWhenAimedAtNothing() {
        var (w, k) = world()
        let mana = w.s.units[k].resource
        XCTAssertFalse(w.cast(k, .skill2, .direction(Self.east)), "敵が居なければ拒否")
        XCTAssertEqual(w.s.units[k].resource, mana, "コストを消費しない")
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 0)
        let far = addEnemy(&w, dx: 650 + 80)
        XCTAssertFalse(w.cast(k, .skill2, .unit(w.id(far))), "射程外")
        XCTAssertEqual(w.s.units[k].resource, mana)
        let weak = addEnemy(&w, dx: 500, dy: 60, hero: "H003")
        let near = addEnemy(&w, dx: 200, dy: -60, hero: "H004")
        w.s.units[weak].hp = 100
        XCTAssertTrue(w.cast(k, .skill2, .none), "自動照準は HP の低い敵ヒーロー")
        XCTAssertEqual(w.castEvents.last?.targetUnitID, w.id(weak))
        _ = near
        // 指定したユニットを優先する
        var (w2, k2) = world()
        let x = addEnemy(&w2, dx: 300)
        let y = addEnemy(&w2, dx: 200, dy: 100, hero: "H003")
        XCTAssertTrue(w2.cast(k2, .skill2, .unit(w2.id(x))))
        XCTAssertEqual(w2.castEvents.last?.targetUnitID, w2.id(x))
        _ = y
        // 対象不可の敵は選べない
        var (w3, k3) = world()
        let u = addEnemy(&w3, dx: 300)
        CombatSystem.addStatus(&w3.s, targetIndex: u, StatusEffect(kind: .untargetable, duration: 5))
        XCTAssertFalse(w3.cast(k3, .skill2, .unit(w3.id(u))))
    }

    func testMarkedTargetSpreadsDamageStunAndShredToNearbyEnemiesOnly() throws {
        var (w, k) = world()
        let a = addEnemy(&w, dx: 450)
        let b = addEnemy(&w, dx: 450, dy: 150, hero: "H003")
        let c = addEnemy(&w, dx: 450, dy: -T.splashRadius + 20, hero: "H004")
        let far = addEnemy(&w, dx: 450, dy: 400, hero: "H005")
        let m = w.addMinion(team: .red, at: skillArena + Vec2(450 + 180, 0))
        w.s.units[m].hp = 1e6
        mark(&w, owner: k, on: a)
        let n = numbers(w, k, .skill2)
        let expected = [a, b, c, m].map { w.mitigated(n.damage, .magic, on: $0) * ($0 == m ? Balance.Skills.minionDamageMultiplier : 1) }
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(a))))
        w.run(seconds: 0.5)
        XCTAssertEqual(kit(w, k).euriaSplashes, 1)
        for (idx, e) in [a, b, c, m].enumerated() {
            let hits = events(w, to: e, .skill(.skill2))
            XCTAssertEqual(hits.count, 1, "\(e)")
            XCTAssertEqual(hits[0].amount, expected[idx], accuracy: 1e-6, "\(e)")
            if e == m {
                // ミニオンにはダメージだけ（スタン・魔防ダウンは広がらない）
                XCTAssertNil(status(w, e, .stun), "ミニオンはスタンしない")
                XCTAssertNil(status(w, e, .magicShred), "ミニオンは魔防ダウンしない")
            } else {
                XCTAssertNotNil(status(w, e, .stun), "\(e)")
                XCTAssertEqual(status(w, e, .magicShred)?.magnitude ?? 0, 10, accuracy: 1e-9, "\(e)")
            }
        }
        XCTAssertEqual(w.damage(to: far), 0, "範囲外")
        // 広がった先にも印が付く（ミニオンを除く）
        XCTAssertTrue(marked(w, owner: k, on: b))
        XCTAssertTrue(marked(w, owner: k, on: c))
        XCTAssertFalse(marked(w, owner: k, on: m))
        XCTAssertFalse(marked(w, owner: k, on: far))
    }

    func testCCImmuneTargetStillTakesDamageButIsNotStunned() {
        var (w, k) = world()
        let a = addEnemy(&w, dx: 400)
        CombatSystem.addStatus(&w.s, targetIndex: a, StatusEffect(kind: .ccImmune, duration: 10))
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(a))))
        w.run(seconds: 0.6)
        XCTAssertGreaterThan(w.damage(to: a), 0)
        XCTAssertNil(status(w, a, .stun))
    }

    func testOrbFizzlesIfTheTargetBecomesUntargetableOrDiesInFlight() {
        var (w, k) = world()
        let a = addEnemy(&w, dx: 600)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(a))))
        w.tick(2)
        CombatSystem.addStatus(&w.s, targetIndex: a, StatusEffect(kind: .untargetable, duration: 5))
        w.run(seconds: 0.6)
        XCTAssertEqual(w.damage(to: a), 0)
        XCTAssertFalse(marked(w, owner: k, on: a))
    }

    // MARK: - 奥義: 九天雷鳴（Thunder's Wrath）

    func testThunderTelegraphsThenStrikesCenterHeavierThanTheOuterRing() throws {
        var (w, k) = world()
        let impact = skillArena + Vec2(600, 0)
        let center = addEnemy(&w, dx: 600 + 100)
        let ring = addEnemy(&w, dx: 600, dy: 220, hero: "H003")
        let outside = addEnemy(&w, dx: 600, dy: 440, hero: "H004")
        let n = numbers(w, k, .ultimate)
        let mana = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .ultimate, .point(impact)))
        XCTAssertLessThan(w.s.units[k].resource, mana)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), n.cooldown, accuracy: 1e-9)
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.archetype, .groundAoE)
        XCTAssertEqual(ev.shape, .circleAtPoint)
        XCTAssertEqual(ev.duration, T.ultDelay)
        XCTAssertEqual(ev.target.x, impact.x, accuracy: 1e-6)
        // 予告のゾーン（0.8 秒）
        let zone = try XCTUnwrap(zoneCreated(w).first)
        XCTAssertEqual(zone.delay, T.ultDelay, accuracy: 1e-9)
        XCTAssertEqual(zone.radius, T.ultOuterRadius)
        XCTAssertEqual(zone.center.x, impact.x, accuracy: 1e-6)
        XCTAssertEqual(zone.visual, skill(.ultimate).effectID)
        w.run(seconds: 0.7)
        XCTAssertTrue(w.damageEvents.isEmpty, "予告の間はダメージ無し")
        w.run(seconds: 0.2)
        let c = events(w, to: center, .skill(.ultimate))
        let r = events(w, to: ring, .skill(.ultimate))
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(c[0].amount, w.mitigated(n.damage, .magic, on: center), accuracy: 1e-6)
        XCTAssertEqual(r[0].amount, w.mitigated(n.damage * T.ultOuterRatio, .magic, on: ring), accuracy: 1e-6,
                       "外側は中心の半分")
        XCTAssertEqual(w.damage(to: outside), 0)
        // 奥義に CC は無い
        XCTAssertNil(status(w, center, .stun))
        XCTAssertTrue(w.s.units[center].canAct)
    }

    func testThunderCenterBoundaryAndRangeClamp() {
        var (w, k) = world()
        let impact = skillArena + Vec2(600, 0)
        let inner = addEnemy(&w, dx: 600 + T.ultCenterRadius - 5)
        let justOut = addEnemy(&w, dx: 600, dy: T.ultCenterRadius + 10, hero: "H003")
        let n = numbers(w, k, .ultimate)
        XCTAssertTrue(w.cast(k, .ultimate, .point(impact)))
        w.run(seconds: 1.0)
        XCTAssertEqual(events(w, to: inner, .skill(.ultimate)).first?.amount ?? 0,
                       w.mitigated(n.damage, .magic, on: inner), accuracy: 1e-6)
        XCTAssertEqual(events(w, to: justOut, .skill(.ultimate)).first?.amount ?? 0,
                       w.mitigated(n.damage * T.ultOuterRatio, .magic, on: justOut), accuracy: 1e-6)
        // 射程 770 を超える地点は射程の端に丸められる
        var (w2, k2) = world()
        XCTAssertTrue(w2.cast(k2, .ultimate, .point(skillArena + Vec2(1500, 0))))
        XCTAssertEqual(w2.castEvents.last!.target.x, skillArena.x + 770, accuracy: 1e-6)
        XCTAssertEqual(zoneCreated(w2).first?.center.x ?? 0, skillArena.x + 770, accuracy: 1e-6, "敵が居なくても撃てる")
    }

    func testThunderburstTriggersOnMarkedTargetsOnlyAfterADelayAndHitsNearbyEnemies() throws {
        var (w, k) = world()
        let impact = skillArena + Vec2(600, 0)
        let markedHero = addEnemy(&w, dx: 600 + 60)
        let neighbor = addEnemy(&w, dx: 600 + 60, dy: 150, hero: "H003")
        let unmarkedFar = addEnemy(&w, dx: 600 + 60, dy: -300, hero: "H004")
        mark(&w, owner: k, on: markedHero)
        let n = numbers(w, k, .ultimate)
        let burst = n.damage * T.burstRatio
        XCTAssertTrue(w.cast(k, .ultimate, .point(impact)))
        w.run(seconds: 0.9)
        XCTAssertEqual(kit(w, k).euriaBursts, 1, "印済みの敵 1 体につき 1 回")
        // 炸裂の予告（少し遅れる）
        let zones = zoneCreated(w)
        XCTAssertEqual(zones.count, 2)
        XCTAssertEqual(zones[1].delay, T.burstDelay, accuracy: 1e-9)
        XCTAssertEqual(zones[1].radius, T.burstRadius)
        XCTAssertEqual(zones[1].visual, skill(.passive).effectID, "大雷とは別の演出")
        XCTAssertEqual(events(w, to: markedHero, .skill(.ultimate)).count, 1)
        w.run(seconds: 0.5)
        let hits = events(w, to: markedHero, .skill(.ultimate))
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[1].amount, w.mitigated(burst, .magic, on: markedHero), accuracy: 1e-6)
        // 近くの敵も巻き込む（炸裂は対象を中心にした範囲）
        let nh = events(w, to: neighbor, .skill(.ultimate))
        XCTAssertEqual(nh.count, 2)
        XCTAssertEqual(nh[1].amount, w.mitigated(burst, .magic, on: neighbor), accuracy: 1e-6)
        // 遠い（印の無い）敵は大雷のみ（外側 or 圏外）
        XCTAssertLessThanOrEqual(events(w, to: unmarkedFar, .skill(.ultimate)).count, 1)
        // 大雷で印が付いた近くの敵は、次の奥義で炸裂の対象になる
        XCTAssertTrue(marked(w, owner: k, on: neighbor))
        // 印の無い敵だけなら炸裂しない
        var (w2, k2) = world()
        let e = addEnemy(&w2, dx: 600)
        XCTAssertTrue(w2.cast(k2, .ultimate, .point(skillArena + Vec2(600, 0))))
        w2.run(seconds: 2.0)
        XCTAssertEqual(kit(w2, k2).euriaBursts, 0)
        XCTAssertEqual(events(w2, to: e, .skill(.ultimate)).count, 1)
        XCTAssertTrue(marked(w2, owner: k2, on: e))
    }

    func testMultipleMarkedTargetsEachCauseTheirOwnOverlappingBurst() {
        var (w, k) = world()
        let a = addEnemy(&w, dx: 600)
        let b = addEnemy(&w, dx: 600, dy: 120, hero: "H003")
        mark(&w, owner: k, on: a)
        mark(&w, owner: k, on: b)
        let n = numbers(w, k, .ultimate)
        XCTAssertTrue(w.cast(k, .ultimate, .point(skillArena + Vec2(600, 0))))
        w.run(seconds: 1.7)
        XCTAssertEqual(kit(w, k).euriaBursts, 2)
        // 互いに炸裂の範囲内: 大雷 1 回 + 炸裂 2 回
        for e in [a, b] {
            let hits = events(w, to: e, .skill(.ultimate))
            XCTAssertEqual(hits.count, 3, "\(e)")
            XCTAssertEqual(hits[1].amount, w.mitigated(n.damage * T.burstRatio, .magic, on: e), accuracy: 1e-6)
            XCTAssertEqual(hits[2].amount, w.mitigated(n.damage * T.burstRatio, .magic, on: e), accuracy: 1e-6)
        }
    }

    func testBurstFollowsTheTargetAndFizzlesIfItDies() {
        var (w, k) = world()
        let a = addEnemy(&w, dx: 600)
        let bystander = addEnemy(&w, dx: 600, dy: 150, hero: "H003")
        mark(&w, owner: k, on: a)
        XCTAssertTrue(w.cast(k, .ultimate, .point(skillArena + Vec2(600, 0))))
        w.run(seconds: 1.0)
        // 炸裂までに対象が動く: 炸裂は対象に付いていく（置き去りの敵は巻き込まれない）
        w.s.units[a].pos = w.s.units[a].pos + Vec2(0, -500)
        w.run(seconds: 0.6)
        XCTAssertEqual(events(w, to: a, .skill(.ultimate)).count, 2)
        XCTAssertEqual(events(w, to: bystander, .skill(.ultimate)).count, 1, "炸裂は対象に付いていった")
        // 炸裂の前に対象が倒れたら不発
        var (w2, k2) = world()
        let b = addEnemy(&w2, dx: 600)
        let c = addEnemy(&w2, dx: 600, dy: 100, hero: "H003")
        mark(&w2, owner: k2, on: b)
        XCTAssertTrue(w2.cast(k2, .ultimate, .point(skillArena + Vec2(600, 0))))
        w2.run(seconds: 1.0)
        XCTAssertEqual(kit(w2, k2).euriaBursts, 1)
        CombatSystem.applyDamage(&w2.s, w2.ctx, sourceID: w2.id(k2), targetIndex: b, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        w2.run(seconds: 0.8)
        XCTAssertEqual(events(w2, to: c, .skill(.ultimate)).count, 1, "炸裂は不発")
    }

    func testThunderStillLandsAfterTheCasterIsStunnedAndNothingHappensWhenStunnedBeforeCasting() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 600)
        XCTAssertTrue(w.cast(k, .ultimate, .point(skillArena + Vec2(600, 0))))
        w.tick(3)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1.5))
        w.run(seconds: 1.0)
        XCTAssertGreaterThan(w.damage(to: e), 0, "すでに呼んだ雷は落ちる")
        // スタン中は撃てない
        var (w2, k2) = world()
        CombatSystem.addStatus(&w2.s, targetIndex: k2, StatusEffect(kind: .stun, duration: 1.0))
        for slot in SkillSlot.actives { XCTAssertFalse(w2.cast(k2, slot, .none), "\(slot)") }
        XCTAssertEqual(w2.s.units[k2].hero!.cooldown(.ultimate), 0)
    }

    // MARK: - 端の場合

    func testDeathResetsTheKitAndCancelsTheChain() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 400)
        mark(&w, owner: k, on: e)
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        w.run(seconds: 0.3)
        XCTAssertGreaterThan(kit(w, k).scheduled.count, 0)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        XCTAssertEqual(kit(w, k), KitState())
        XCTAssertTrue(w.s.units[k].statuses.isEmpty)
        let hits = events(w, to: e, .skill(.skill1)).count
        w.run(seconds: 1.5)
        XCTAssertEqual(events(w, to: e, .skill(.skill1)).count, hits, "死亡後は鎖が動かない")
        XCTAssertEqual(kit(w, k), KitState())
    }

    func testPracticeNoCooldownsKeepsEverySlotAtZero() {
        var (w, k) = world(noCooldowns: true)
        let e = addEnemy(&w, dx: 300)
        for slot in SkillSlot.actives {
            XCTAssertTrue(w.cast(k, slot, .unit(w.id(e))), "\(slot)")
            XCTAssertEqual(w.s.units[k].hero!.cooldown(slot), 0, "\(slot)")
        }
    }

    func testManaAndCooldownAreChargedFromMasterAndSlotCooldownForEverySlot() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 300)
        for slot in SkillSlot.actives {
            w.s.units[k].resource = w.s.units[k].stats.maxResource
            let before = w.s.units[k].resource
            XCTAssertTrue(w.cast(k, slot, .unit(w.id(e))), "\(slot)")
            XCTAssertEqual(before - w.s.units[k].resource, SkillSystem.cost(for: skill(slot), resource: .mana),
                           accuracy: 1e-9)
            XCTAssertEqual(w.s.units[k].hero!.cooldown(slot), numbers(w, k, slot).cooldown, accuracy: 1e-9)
            XCTAssertFalse(w.cast(k, slot, .unit(w.id(e))), "再使用の窓は無い（CD 中は撃てない）")
        }
    }

    // MARK: - 決定性

    private func script(_ w: inout SkillWorld, k: Int, e1: Int, e2: Int, step: Int) {
        switch step {
        case 0: w.cast(k, .skill1, .direction(Vec2(1, 0)))
        case 1: w.cast(k, .skill1, .direction(Vec2(1, 0)))
        case 2: w.cast(k, .skill2, .unit(w.id(e1)))
        case 3: w.cast(k, .ultimate, .point(skillArena + Vec2(300, 40)))
        case 4: w.s.units[k].attackTargetID = w.id(e1)
        case 5: w.cast(k, .skill1, .unit(w.id(e2)))
        case 6: w.cast(k, .skill2, .unit(w.id(e2)))
        case 7: w.s.units[e1].attackTargetID = w.id(k)
        default: break
        }
    }

    private func makeScriptWorld() -> (SkillWorld, Int, Int, Int) {
        var w = SkillWorld(noCooldowns: true)
        let k = w.addHero("H026", team: .blue, at: skillArena, level: 12, ranks: [2, 2, 2], facing: 0)
        let e1 = w.addHero("H001", team: .red, at: skillArena + Vec2(320, 0), level: 12)
        let e2 = w.addHero("H004", team: .red, at: skillArena + Vec2(300, 140), level: 12)
        _ = w.addMinion(team: .red, at: skillArena + Vec2(250, -100))
        return (w, k, e1, e2)
    }

    private func run(_ w: inout SkillWorld, _ k: Int, _ e1: Int, _ e2: Int, from: Int, to: Int, seconds: Double = 1.1) {
        for step in from..<to {
            script(&w, k: k, e1: e1, e2: e2, step: step)
            w.run(seconds: seconds)
        }
    }

    func testScriptedRunIsDeterministicAndExercisesTheKit() {
        var (a, ka, a1, a2) = makeScriptWorld()
        var (b, kb, b1, b2) = makeScriptWorld()
        run(&a, ka, a1, a2, from: 0, to: 9)
        run(&b, kb, b1, b2, from: 0, to: 9)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(a.s.units, b.s.units)
        XCTAssertEqual(a.log, b.log)
        XCTAssertTrue(a.damageEvents.contains { $0.source == .skill(.ultimate) })
        XCTAssertTrue(a.damageEvents.contains { $0.source == .skill(.skill2) })
        XCTAssertTrue(a.damageEvents.contains { $0.source == .skill(.skill1) })
        let k = a.s.units[ka].hero!.kit!
        XCTAssertGreaterThan(k.euriaChains, 0, "台本が鎖を結んでいる")
        XCTAssertGreaterThan(k.euriaBursts, 0, "台本が炸裂を起こしている")
        XCTAssertGreaterThan(k.euriaSplashes, 0, "台本が広がりを起こしている")
    }

    /// 途中（鎖の最中 / 雷球の飛行中 / 大雷の予告中 / 炸裂の予告中）でシリアライズして再開しても同じ。
    func testJSONRoundTripMidChainMidOrbMidThunderAndMidBurstResumesIdentically() throws {
        func check(_ prepare: (inout SkillWorld, Int, Int, Int) -> Void, _ name: String) throws {
            var (b, kb, b1, b2) = makeScriptWorld()
            prepare(&b, kb, b1, b2)
            let data = try JSONEncoder().encode(b.s)
            var resumed = b
            resumed.s = try JSONDecoder().decode(SimState.self, from: data)
            XCTAssertEqual(resumed.s.units, b.s.units, name)
            XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash(), name)
            b.run(seconds: 0.7)
            resumed.run(seconds: 0.7)
            XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash(), name)
            run(&b, kb, b1, b2, from: 4, to: 9)
            run(&resumed, kb, b1, b2, from: 4, to: 9)
            XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash(), name)
            XCTAssertEqual(resumed.s.units, b.s.units, name)
            XCTAssertEqual(resumed.damageEvents.count, b.damageEvents.count, name)
        }
        try check({ w, k, e1, _ in
            mark(&w, owner: k, on: e1)
            w.cast(k, .skill1, .direction(Vec2(1, 0)))
            w.tick(8)
            XCTAssertFalse(w.s.units[k].hero!.kit!.scheduled.isEmpty)
        }, "mid chain")
        try check({ w, k, e1, _ in
            w.cast(k, .skill2, .unit(w.id(e1)))
            w.tick(3)
            XCTAssertFalse(w.s.projectiles.isEmpty)
        }, "mid orb")
        try check({ w, k, _, _ in
            w.cast(k, .ultimate, .point(skillArena + Vec2(300, 40)))
            w.tick(12)
            XCTAssertFalse(w.s.zones.isEmpty)
        }, "mid thunder telegraph")
        try check({ w, k, e1, _ in
            mark(&w, owner: k, on: e1)
            w.cast(k, .ultimate, .point(skillArena + Vec2(300, 40)))
            w.run(seconds: 1.0)
            XCTAssertTrue(w.s.zones.contains { !$0.done && $0.followsTargetID != nil })
        }, "mid burst telegraph")
    }

    // MARK: - ボットの煙テスト

    func testTextUsesUITermsAndMasterNames() throws {
        let (w, k) = world(level: 6, ranks: [2, 2, 2])
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H026", slot: slot))
            let ja = text.filled(english: false, numbers: numbers(w, k, slot),
                                 targeting: SkillCatalog.targeting(for: skill(slot), hero: def))
            XCTAssertFalse(ja.contains("S1") || ja.contains("S2") || ja.contains("奥義"), "\(slot): \(ja)")
            XCTAssertFalse(ja.contains("星環シフト") || ja.contains("Euria式"), "\(slot): \(ja)")
            if slot == .passive {
                XCTAssertTrue(ja.contains("分岐雷") && ja.contains("雷球") && ja.contains("九天雷鳴"), ja)
                XCTAssertTrue(ja.contains("スキル1") && ja.contains("スキル2") && ja.contains("アルティメット"), ja)
            }
            if slot == .skill1 { XCTAssertTrue(ja.contains("3秒に1回"), ja) }
            if slot == .skill2 { XCTAssertTrue(ja.contains("ミニオンにはダメージのみ"), ja) }
        }
    }

    // MARK: - ボットの順序（印を付けてから重い技）

    private func decide(_ w: SkillWorld, _ k: Int, _ slot: SkillSlot, target: Int) throws -> String {
        let kit = try XCTUnwrap(HeroKits.kit(of: w.s.units[k]))
        let tg = SkillCatalog.activeTargeting(w.s, caster: k, slot: slot, skill: skill(slot), hero: def)
        switch kit.botCast(w.s, w.ctx, bot: k, slot: slot, targeting: tg, target: target, fighting: true) {
        case .useDefault: return "default"
        case .skip: return "skip"
        case .cast(let t): return "cast \(t)"
        case .castNow(let t): return "castNow \(t)"
        }
    }

    func testBotWaitsForTheMarkOnlyWhileForkedBoltIsReallyCastable() throws {
        var (w, k) = world(level: 12, ranks: [2, 2, 2])
        let a = addEnemy(&w, dx: 500)
        w.tick()
        // S1 が撃てる（CD 明け・マナあり・扇の射程内）: 印が無ければ アルティメット を見送る
        XCTAssertEqual(try decide(w, k, .ultimate, target: a), "skip")
        XCTAssertEqual(try decide(w, k, .skill2, target: a), "default", "近くに別のヒーローが居なければ S2 を先に撃ってよい（S2 が印を付ける）")
        // 近くに別のヒーローが居ると、S2 は印を付けてから（広がる）
        let b = addEnemy(&w, dx: 500, dy: 150, hero: "H003")
        w.tick()
        XCTAssertEqual(try decide(w, k, .skill2, target: a), "skip")
        // 印済みなら両方撃つ
        mark(&w, owner: k, on: a)
        XCTAssertEqual(try decide(w, k, .ultimate, target: a), "default")
        XCTAssertEqual(try decide(w, k, .skill2, target: a), "default")
        w.s.units[a].statuses.removeAll { $0.kind == .mark }
        // S1 が CD 中: 待たずに撃つ
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(try decide(w, k, .ultimate, target: a), "default", "S1 が CD 中は待たない")
        XCTAssertEqual(try decide(w, k, .skill2, target: a), "default")
        _ = b
    }

    func testBotDoesNotWaitForForkedBoltWhenItCannotFireAtThisTarget() throws {
        // 扇（射程 650）の外: S1 は撃てないので、アルティメット（770）を待たせない
        var (w, k) = world(level: 12, ranks: [2, 2, 2])
        let far = addEnemy(&w, dx: 730)
        w.tick()
        XCTAssertEqual(try decide(w, k, .ultimate, target: far), "default", "S1 の射程外")
        // マナ不足: S1 のコストに足りない
        var (w2, k2) = world(level: 12, ranks: [2, 2, 2])
        let near = addEnemy(&w2, dx: 400)
        w2.tick()
        XCTAssertEqual(try decide(w2, k2, .ultimate, target: near), "skip")
        w2.s.units[k2].resource = 1
        XCTAssertEqual(try decide(w2, k2, .ultimate, target: near), "default", "マナが無いなら待たない")
        // 沈黙: S1 が撃てない
        var (w3, k3) = world(level: 12, ranks: [2, 2, 2])
        let near3 = addEnemy(&w3, dx: 400)
        w3.tick()
        CombatSystem.addStatus(&w3.s, targetIndex: k3, StatusEffect(kind: .silence, duration: 5))
        XCTAssertEqual(try decide(w3, k3, .ultimate, target: near3), "default")
        _ = (w2, w3)
    }

    /// エウリアをボット（ミッド）にして通常の 10 人戦を回す。S1 / S2 / 奥義をすべて撃ち、鎖・広がり・炸裂が起き、状態が壊れない。
    func testBotSmokeCastsEverySlotAndStateStaysBounded() throws {
        var cfg = MatchFactory.botMatch(seed: 31)
        let idx = try XCTUnwrap(cfg.players.firstIndex { $0.team == .blue && $0.position == .mid })
        if let other = cfg.players.firstIndex(where: { $0.heroID == "H026" }), other != idx {
            cfg.players[other].heroID = cfg.players[idx].heroID
        }
        cfg.players[idx].heroID = "H026"
        let sim = Simulation(config: cfg)
        let hero = try XCTUnwrap(sim.state.heroIndices.first { sim.state.units[$0].hero?.heroID == "H026" })
        let heroID = sim.state.units[hero].id
        XCTAssertNotNil(sim.state.units[hero].hero?.kit)
        var casts: [SkillSlot: Int] = [:]
        var chains = 0, ends = 0, bursts = 0, splashes = 0
        while !sim.isEnded && sim.state.time < 1500 {
            let events = sim.step()
            for e in events {
                if case .skillCast(let c) = e, c.casterID == heroID { casts[c.slot, default: 0] += 1 }
            }
            let i = sim.state.index(of: heroID)!
            let u = sim.state.units[i]
            let k = u.hero!.kit!
            chains = max(chains, k.euriaChains)
            ends = max(ends, k.euriaChainEnds)
            bursts = max(bursts, k.euriaBursts)
            splashes = max(splashes, k.euriaSplashes)
            XCTAssertTrue(u.hp.isFinite && u.pos.x.isFinite && u.pos.y.isFinite && u.resource.isFinite)
            XCTAssertTrue(k.reals.allSatisfy { $0.isFinite })
            XCTAssertTrue(k.timers.allSatisfy { $0.isFinite && $0 >= 0 })
            XCTAssertLessThanOrEqual(k.scheduled.count, 24)
            XCTAssertLessThanOrEqual(u.statuses.count, 24)
            if k.scheduled.isEmpty { XCTAssertFalse(u.statuses.contains { $0.tag == T.chainSpeedTag }) }
            if casts[.skill1, default: 0] > 0, casts[.skill2, default: 0] > 0, casts[.ultimate, default: 0] > 0,
               chains > 0, bursts > 0, splashes > 0, sim.state.time > 130 { break }
        }
        XCTAssertGreaterThan(casts[.skill1, default: 0], 0, "S1: \(casts)")
        XCTAssertGreaterThan(casts[.skill2, default: 0], 0, "S2: \(casts)")
        XCTAssertGreaterThan(casts[.ultimate, default: 0], 0, "奥義: \(casts)")
        XCTAssertGreaterThan(chains, 0, "鎖: \(casts)")
        print("H026 bot smoke: \(casts) chains \(chains) ends \(ends) bursts \(bursts) splashes \(splashes) until \(sim.state.time) s")
    }

    // MARK: - 1v1 の TTK（H001–H006 相手、Lv 1 / 6 / 12）と総当たりの勝率

    func testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives() {
        var failures: [String] = []
        var wins = 0
        var total = 0
        var table = "H026 TTK\n"
        for level in SkillBalanceTests.levels {
            for foe in SkillBalanceTests.representatives {
                let r = SkillBalanceTests.duel("H026", foe, level: level)
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
        XCTAssertGreaterThanOrEqual(wins, total / 5, "弱すぎる: \(wins)/\(total)")
    }

    /// 全ヒーローとの総当たり（Lv 6 / 12）での勝率。極端に強くも弱くもない（目安 35〜65%）。
    func testRoundRobinWinRateAgainstTheWholeRosterIsNotExtreme() {
        let ids = MasterData.shared.heroes.map(\.heroID).filter { $0 != "H026" }
        var report = "H026 round robin\n"
        for level in [6, 12] {
            var score = 0.0
            for foe in ids {
                let r = SkillBalanceTests.duel("H026", foe, level: level)
                if r.winnerIsA == true { score += 1 } else if r.winnerIsA == nil { score += 0.5 }
            }
            let rate = score / Double(ids.count)
            report += String(format: "Lv%d: %.1f%% (%.1f/%d)\n", level, rate * 100, score, ids.count)
            XCTAssertGreaterThanOrEqual(rate, 0.25, "Lv\(level) 弱すぎる")
            XCTAssertLessThanOrEqual(rate, 0.75, "Lv\(level) 強すぎる")
        }
        print(report)
    }
}
