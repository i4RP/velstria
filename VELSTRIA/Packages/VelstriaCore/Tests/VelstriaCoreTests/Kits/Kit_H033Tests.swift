import XCTest
@testable import VelstriaCore

/// H033 紅牙のヴァルド（Alucard）のキット。仕様: docs/kits/Alucard.md、実装対応表: 同ファイル末尾。
/// isReady になるまでは `HeroKits.testOverride` に差して試す（isReady 後も差しても同じ）。敵は動かない通常のヒーロー（H001 / H003 ほか）。
final class Kit_H033Tests: XCTestCase {
    typealias Tune = Kit_H033.Tune

    override func setUp() {
        super.setUp()
        HeroKits.testOverride = [Kit_H033(isReady: true)]
    }

    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    // MARK: - 土台

    /// ヴァルド（blue, 東向き）を置く。敵は別に addEnemy で足す。
    private func world(level: Int = 12, ranks: [Int]? = [1, 1, 1], noCooldowns: Bool = false) -> (SkillWorld, Int) {
        var w = SkillWorld(noCooldowns: noCooldowns)
        let k = w.addHero("H033", team: .blue, at: skillArena, level: level, ranks: ranks, facing: 0)
        return (w, k)
    }

    @discardableResult
    private func addEnemy(_ w: inout SkillWorld, dx: Double, dy: Double = 0, hero: String = "H001", level: Int = 12) -> Int {
        w.addHero(hero, team: .red, at: skillArena + Vec2(dx, dy), level: level, ranks: [1, 1, 1])
    }

    private func kit(_ w: SkillWorld, _ k: Int) -> KitState { w.s.units[k].hero!.kit! }

    private let east = SkillTarget.direction(Vec2(1, 0))

    private func at(_ dx: Double, _ dy: Double = 0) -> SkillTarget { .point(skillArena + Vec2(dx, dy)) }

    private func heals(_ w: SkillWorld, of i: Int) -> [Double] {
        let id = w.id(i)
        return w.log.compactMap { if case .heal(let t, _, let a) = $0, t == id { return a } else { return nil } }
    }

    private func skillHits(_ w: SkillWorld, on e: Int, _ slot: SkillSlot) -> [DamageEvent] {
        w.damageEvents.filter { $0.targetID == w.id(e) && $0.source == .skill(slot) }
    }

    private func basicHits(_ w: SkillWorld, on e: Int) -> [DamageEvent] {
        w.damageEvents.filter { $0.targetID == w.id(e) && $0.source == .basicAttack }
    }

    private func cooldown(_ w: SkillWorld, _ k: Int, _ slot: SkillSlot) -> Double { w.s.units[k].hero!.cooldown(slot) }

    private func status(_ w: SkillWorld, _ i: Int, _ kind: StatusKind, tag: String? = nil) -> StatusEffect? {
        w.s.units[i].statuses.first { $0.kind == kind && (tag == nil || $0.tag == tag) }
    }

    /// 敵を倒す（死亡処理まで）。
    private func kill(_ w: inout SkillWorld, _ victim: Int, by killer: Int) {
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(killer), targetIndex: victim, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
    }

    // MARK: - レジストリ・照準・数値

    func testRegistryAndTargetingPerSlot() throws {
        XCTAssertTrue(HeroKits.hasKit("H033"))
        XCTAssertFalse(HeroKits.hasKit("H006"))
        let m = MasterData.shared
        let hero = try XCTUnwrap(m.hero("H033"))
        func target(_ slot: SkillSlot, stage: Int = 0) throws -> SkillTargeting {
            let skill = try XCTUnwrap(m.skill(hero: "H033", slot: slot))
            return HeroKits.targeting(for: skill, hero: hero, stage: stage)
        }
        let s1 = try target(.skill1)
        XCTAssertEqual(s1.archetype, .leapSlam)
        XCTAssertEqual(s1.aim, .point)
        XCTAssertEqual(s1.shape, .circleAtPoint)
        XCTAssertEqual(s1.range, Tune.s1Range)
        XCTAssertEqual(s1.radius, Tune.s1Radius)
        XCTAssertEqual(s1.reach, Tune.s1Range + Tune.s1Radius)
        XCTAssertFalse(s1.recastable)
        XCTAssertFalse(s1.requiresTarget, "敵が居なくても撃てる")
        let s2 = try target(.skill2)
        XCTAssertEqual(s2.archetype, .selfAoE)
        XCTAssertEqual(s2.aim, .none)
        XCTAssertEqual(s2.shape, .selfRing)
        XCTAssertEqual(s2.reach, Tune.s2Radius)
        let ult = try target(.ultimate)
        XCTAssertEqual(ult.archetype, .groundAoE)
        XCTAssertEqual(ult.aim, .point)
        XCTAssertEqual(ult.shape, .circleAtPoint)
        XCTAssertEqual(ult.range, Tune.ultCastRange)
        XCTAssertEqual(ult.radius, Tune.absorbRadius)
        XCTAssertTrue(ult.recastable)
        let wave = try target(.ultimate, stage: 1)
        XCTAssertEqual(wave.archetype, .piercingLine)
        XCTAssertEqual(wave.aim, .direction)
        XCTAssertEqual(wave.shape, .wideLine)
        XCTAssertEqual(wave.range, Tune.waveRange)
        XCTAssertEqual(wave.radius, Tune.waveHalfWidth)
        XCTAssertFalse(wave.requiresTarget)
        XCTAssertEqual(try target(.passive).archetype, .passive)
        // S1・S2 に段（再使用）は無い
        XCTAssertEqual(try target(.skill1, stage: 1), try target(.skill1))
        XCTAssertEqual(try target(.skill2, stage: 1), try target(.skill2))
        // 実ユニット: キット状態が付き、窓は閉じている
        let (w, k) = world()
        XCTAssertNotNil(w.s.units[k].hero?.kit)
        for slot in SkillSlot.allCases {
            XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: slot))
            XCTAssertEqual(HeroKits.activeStage(w.s.units[k].hero!, slot: slot), 0)
        }
    }

    private func numbers(_ slot: SkillSlot, level: Int, rank: Int, stage: Int = 0) throws -> (kit: SkillNumbers, generic: SkillNumbers) {
        let (w, k) = world(level: level)
        let m = MasterData.shared
        let hero = try XCTUnwrap(m.hero("H033"))
        let skill = try XCTUnwrap(m.skill(hero: "H033", slot: slot))
        let stats = w.s.units[k].stats
        return (HeroKits.numbers(for: skill, hero: hero, rank: rank, stats: stats, stage: stage),
                SkillCatalog.genericNumbers(for: skill, hero: hero, rank: rank, stats: stats))
    }

    /// 1 スロットの単体総ダメージは汎用の 0.8〜1.3 倍（奥義は衝撃波のダメージ）。
    /// 例外: S1 はランクが上がるほど倍率を下げる（0.88 → 0.64）ので、ランク 2 以降は 0.8 を割る。序盤（Lv1〜3 はスキル1 だけ）を
    /// 強くして、ランクが上がってスキル2・アルティメット（クールダウン半減・追撃）が揃ったあとの火力と 3 秒の瞬間火力を抑えるため
    /// （docs/kits/Alucard.md の「バランス」）。
    func testNumbersStayWithinDamageBudgetAndFollowCooldownFormula() throws {
        for level in [1, 6, 12] {
            for rank in 1...Balance.basicSkillMaxRank {
                for slot in [SkillSlot.skill1, .skill2] {
                    let (n, g) = try numbers(slot, level: level, rank: rank)
                    let r = n.totalDamage / g.totalDamage
                    let floor = slot == .skill1 ? 0.6 : 0.8
                    XCTAssertTrue((floor...1.3).contains(r), "\(slot) Lv\(level) r\(rank): \(r)")
                }
            }
            for rank in 1...Balance.ultimateMaxRank {
                for stage in [0, 1] {
                    let (u, g) = try numbers(.ultimate, level: level, rank: rank, stage: stage)
                    let r = u.totalDamage / g.totalDamage
                    XCTAssertTrue((0.8...1.3).contains(r), "ult stage\(stage) Lv\(level) r\(rank): \(r)")
                }
            }
        }
        // クールダウン = MLBB の秒数（ランクで線形）× 全体倍率 × (1 − CD 短縮)
        let (w, k) = world()
        let cdr = w.s.units[k].stats.cooldownReduction
        func expected(_ a: Double, _ b: Double, rank: Int, maxRank: Int, scale: Double = Balance.Skills.cooldownScale) -> Double {
            (a + (b - a) * Double(rank - 1) / Double(maxRank - 1)) * (1 - cdr) * scale
        }
        for rank in 1...4 {
            XCTAssertEqual(try numbers(.skill1, level: 12, rank: rank).kit.cooldown,
                           expected(8.5, 6.5, rank: rank, maxRank: 4, scale: Kit_H033.s1CooldownScale(rank: rank)),
                           accuracy: 1e-9)
            XCTAssertEqual(try numbers(.skill2, level: 12, rank: rank).kit.cooldown,
                           expected(6, 4, rank: rank, maxRank: 4, scale: Tune.s2CooldownScale), accuracy: 1e-9)
        }
        for rank in 1...3 {
            // MLBB の 40 / 35 / 30 秒
            XCTAssertEqual(try numbers(.ultimate, level: 12, rank: rank).kit.cooldown,
                           expected(40, 30, rank: rank, maxRank: 3), accuracy: 1e-9)
        }
        // ランクが上がるほど強く、CD は短く
        let a = try numbers(.skill1, level: 12, rank: 1).kit
        let b = try numbers(.skill1, level: 12, rank: 4).kit
        XCTAssertGreaterThan(b.damage, a.damage)
        XCTAssertLessThan(b.cooldown, a.cooldown)
        XCTAssertEqual(a.cc, .slow)
        XCTAssertEqual(a.ccDuration, Tune.s1SlowDuration)
        let s2 = try numbers(.skill2, level: 12, rank: 1).kit
        XCTAssertEqual(s2.cc, .none)
        let u1 = try numbers(.ultimate, level: 12, rank: 1).kit
        let u3 = try numbers(.ultimate, level: 12, rank: 3).kit
        XCTAssertGreaterThan(u3.damage, u1.damage)
        // 窓・段・吸収の鈍足
        XCTAssertEqual(u1.stages, 2)
        XCTAssertEqual(u1.recastWindow, Tune.ultWindow)
        XCTAssertEqual(u1.cc, .slow)
        XCTAssertEqual(u1.ccDuration, Tune.absorbDuration)
        XCTAssertEqual(try numbers(.ultimate, level: 12, rank: 1, stage: 1).kit.cc, .none)
        // 吸血は奥義ランクで 10 / 20 / 30%
        for (rank, want) in [(1, 10.0), (2, 20.0), (3, 30.0)] {
            let n = try numbers(.ultimate, level: 12, rank: rank).kit
            XCTAssertEqual(try XCTUnwrap(n.extras.first { $0.key == "lifesteal" }).value, want, accuracy: 1e-9)
        }
    }

    func testTextFillsEverySlotWithSimNumbers() throws {
        let (w, k) = world(level: 6, ranks: [2, 2, 2])
        let hero = try XCTUnwrap(MasterData.shared.hero("H033"))
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H033", slot: slot), "\(slot)")
            let skill = try XCTUnwrap(MasterData.shared.skill(hero: "H033", slot: slot))
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
        for slot in [SkillSlot.skill1, .skill2, .ultimate] {
            let skill = try XCTUnwrap(MasterData.shared.skill(hero: "H033", slot: slot))
            let n = SkillCatalog.numbers(for: skill, hero: hero, rank: 2, stats: stats)
            for english in [false, true] {
                let s = try XCTUnwrap(HeroKits.text(heroID: "H033", slot: slot)).filled(
                    english: english, numbers: n, targeting: SkillCatalog.targeting(for: skill, hero: hero))
                XCTAssertTrue(s.contains("\(Int(n.damage.rounded()))"), "\(slot): \(s)")
            }
        }
        let sp = try XCTUnwrap(MasterData.shared.skill(hero: "H033", slot: .passive))
        let pn = SkillCatalog.numbers(for: sp, hero: hero, rank: 1, stats: stats)
        XCTAssertEqual(pn.extras.map(\.value), [140, 5, 300, 30])
        let ult = try XCTUnwrap(MasterData.shared.skill(hero: "H033", slot: .ultimate))
        let un = SkillCatalog.numbers(for: ult, hero: hero, rank: 2, stats: stats)
        XCTAssertEqual(un.extras.map(\.value), [30, 10, Tune.hasteDuration, 20])
        let s1 = try XCTUnwrap(MasterData.shared.skill(hero: "H033", slot: .skill1))
        XCTAssertEqual(SkillCatalog.numbers(for: s1, hero: hero, rank: 2, stats: stats).extras.map(\.value), [40, 2])
        // 説明文の半径・射程は照準情報から
        let ja = try XCTUnwrap(HeroKits.text(heroID: "H033", slot: .ultimate)).filled(
            english: false, numbers: un, targeting: SkillCatalog.targeting(for: ult, hero: hero))
        XCTAssertTrue(ja.contains("\(Int(Tune.ultCastRange))") && ja.contains("\(Int(Tune.absorbRadius))"), ja)
    }

    /// S1 のダメージ倍率はランクが上がるほど下がるが、ダメージの絶対値はランクで増える（汎用の +30%/ランクが勝つ）。
    func testGroundsplitterDamageRatioFallsWithRankButDamageStillGrows() throws {
        XCTAssertEqual(Tune.s1Ratios.count, 4)
        XCTAssertGreaterThan(Tune.s1Ratios[0], Tune.s1Ratios[3])
        XCTAssertEqual(Kit_H033.s1Ratio(rank: 0), Tune.s1Ratios[0])
        XCTAssertEqual(Kit_H033.s1Ratio(rank: 9), Tune.s1Ratios[3])
        var last = 0.0
        for rank in 1...4 {
            let (n, g) = try numbers(.skill1, level: 12, rank: rank)
            XCTAssertEqual(n.damage / g.damage, Tune.s1Ratios[rank - 1], accuracy: 1e-9)
            XCTAssertGreaterThan(n.damage, last, "ランク \(rank) で S1 のダメージが減る")
            last = n.damage
        }
    }

    /// S1 のクールダウンの倍率はランク別（序盤はスキル1 しか無いので短い）。ランクが上がってもクールダウンは延びない。
    func testGroundsplitterCooldownScaleDependsOnRankAndNeverGrowsWithRank() throws {
        XCTAssertEqual(Tune.s1CooldownScales.count, 4)
        XCTAssertLessThan(Kit_H033.s1CooldownScale(rank: 1), Kit_H033.s1CooldownScale(rank: 4))
        XCTAssertEqual(Kit_H033.s1CooldownScale(rank: 0), Kit_H033.s1CooldownScale(rank: 1), "未習得は 1 と同じ（下限）")
        XCTAssertEqual(Kit_H033.s1CooldownScale(rank: 9), Kit_H033.s1CooldownScale(rank: 4), "上限")
        var last = Double.infinity
        for rank in 1...4 {
            let cd = try numbers(.skill1, level: 12, rank: rank).kit.cooldown
            XCTAssertLessThanOrEqual(cd, last + 1e-9, "ランク \(rank) でクールダウンが延びる")
            last = cd
        }
    }

    // MARK: - パッシブ: 追撃

    func testEverySkillCastArmsPursuitAndExtendsAttackRange() {
        var (w, k) = world(ranks: [1, 1, 1])
        let base = w.s.units[k].stats.attackRange
        XCTAssertEqual(kit(w, k).valdPursuit, 0)
        for slot in [SkillSlot.skill1, .skill2, .ultimate] {
            w.s.units[k].hero!.kit!.valdPursuit = 0
            w.s.units[k].statuses.removeAll()
            w.s.units[k].hero!.skillCooldowns = [0, 0, 0, 0]
            w.tick(2)
            XCTAssertTrue(w.cast(k, slot, east), "\(slot)")
            XCTAssertEqual(kit(w, k).valdPursuit, Tune.pursuitWindow, "\(slot)")
            let range = status(w, k, .attackRangeBoost, tag: Tune.pursuitRangeTag)
            XCTAssertEqual(range?.magnitude, Tune.pursuitRangeBonus, "\(slot)")
            w.tick(2)
            XCTAssertEqual(w.s.units[k].stats.attackRange, base + Tune.pursuitRangeBonus, accuracy: 1e-9, "\(slot)")
            w.run(seconds: 0.8)
        }
        // 窓は時間で閉じ、射程も戻る
        w.run(seconds: Tune.pursuitWindow + 0.5)
        XCTAssertEqual(kit(w, k).valdPursuit, 0)
        XCTAssertNil(status(w, k, .attackRangeBoost, tag: Tune.pursuitRangeTag))
        XCTAssertEqual(w.s.units[k].stats.attackRange, base, accuracy: 1e-9)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive), "窓が閉じればバッジも消える")
    }

    func testPursuitBadgeShowsTheRemainingWindow() {
        var (w, k) = world()
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
        XCTAssertTrue(w.cast(k, .skill2))
        let b = HeroKits.badge(w.s.units[k].hero!, slot: .passive)
        XCTAssertEqual(b?.kind, .timer)
        XCTAssertEqual(b?.total, Tune.pursuitWindow)
        XCTAssertEqual(b?.remaining ?? 0, Tune.pursuitWindow, accuracy: 1e-9)
    }

    /// 基準: 敵に隣接して通常攻撃 1 回のダメージ（追撃なし）。
    private func plainAttackDamage(enemy: String = "H001") -> Double {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 120, hero: enemy)
        w.s.units[k].attackTargetID = w.id(e)
        for _ in 0..<60 {
            w.tick()
            if let hit = basicHits(w, on: e).first { return hit.amount }
        }
        return 0
    }

    func testPursuitDashesFromFarAndDealsOnePointFourTimesAndIsSpentOnce() {
        let plain = plainAttackDamage()
        XCTAssertGreaterThan(plain, 0)
        var (w, k) = world()
        let e = addEnemy(&w, dx: 480)
        // S2 は敵に届かない（半径 250）→ 追撃の準備だけ
        XCTAssertTrue(w.cast(k, .skill2))
        XCTAssertEqual(skillHits(w, on: e, .skill2).count, 0)
        w.s.units[k].attackTargetID = w.id(e)
        let startX = w.s.units[k].pos.x
        var first: DamageEvent?
        var second: DamageEvent?
        for _ in 0..<150 {
            w.tick()
            let hits = basicHits(w, on: e)
            if first == nil { first = hits.first }
            if hits.count >= 2 { second = hits[1]; break }
        }
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.amount ?? 0, plain * Tune.pursuitRatio, accuracy: 1e-6, "攻撃力の 140%")
        XCTAssertEqual(second?.amount ?? 0, plain, accuracy: 1e-6, "追撃は 1 回で使い切る")
        XCTAssertEqual(kit(w, k).valdPursuit, 0)
        XCTAssertEqual(kit(w, k).valdPursuits, 1)
        XCTAssertNil(status(w, k, .attackRangeBoost, tag: Tune.pursuitRangeTag))
        // 敵の目の前まで踏み込んだ（元の距離 480 → 半径の和 + 余裕）
        let gap = w.s.units[k].pos.distance(to: w.s.units[e].pos)
        XCTAssertLessThan(w.s.units[k].pos.x, w.s.units[e].pos.x)
        XCTAssertGreaterThan(w.s.units[k].pos.x, startX + 200)
        XCTAssertLessThanOrEqual(gap, w.s.units[k].radius + w.s.units[e].radius + 150 + 1)
    }

    func testPursuitEmitsADashDisplacementAndStartsBeyondMeleeRange() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 430)
        XCTAssertTrue(w.cast(k, .skill2))
        w.s.units[k].attackTargetID = w.id(e)
        w.log.removeAll()
        var dashed = false
        var hitAt: Double?
        for _ in 0..<120 {
            w.tick()
            if w.log.contains(where: { if case .displaced(let id, let kind, _, _, _) = $0 { return id == w.id(k) && kind == .dash } else { return false } }) {
                dashed = true
            }
            if hitAt == nil, !basicHits(w, on: e).isEmpty { hitAt = w.s.time }
            if hitAt != nil { break }
            w.log.removeAll(keepingCapacity: true)
        }
        XCTAssertTrue(dashed, "追撃は踏み込み（dash）を伴う")
        XCTAssertNotNil(hitAt)
    }

    func testPursuitExpiresUnusedAndTheNextAttackIsPlain() {
        let plain = plainAttackDamage()
        var (w, k) = world()
        let e = addEnemy(&w, dx: 120)
        XCTAssertTrue(w.cast(k, .skill2))
        // 敵は S2 の円の中。ダメージを受けて回復し直す
        w.run(seconds: Tune.pursuitWindow + 0.3)
        XCTAssertEqual(kit(w, k).valdPursuit, 0)
        w.s.units[e].hp = w.s.units[e].stats.maxHP
        w.s.units[k].attackTargetID = w.id(e)
        w.log.removeAll()
        for _ in 0..<60 {
            w.tick()
            if let h = basicHits(w, on: e).first {
                XCTAssertEqual(h.amount, plain, accuracy: 1e-6)
                return
            }
        }
        XCTFail("通常攻撃が当たらない")
    }

    func testPursuitOnAMinionAlsoGetsTheBonusButOnAStructureIsSpentWithoutIt() {
        // ミニオン: 通常攻撃の 1.4 倍
        var (w, k) = world()
        let m = w.addMinion(team: .red, at: skillArena + Vec2(300, 0))
        XCTAssertTrue(w.cast(k, .skill2))
        var plan = BasicAttackPlan(payload: HitPayload(damage: 100, damageType: .physical, source: .basicAttack,
                                                       appliesOnHit: true), ranged: false)
        Kit_H033(isReady: true).shapeBasicAttack(&w.s, w.ctx, attacker: k, target: m, plan: &plan)
        XCTAssertEqual(plan.payload.damage, 100 * Tune.pursuitRatio, accuracy: 1e-9)
        XCTAssertEqual(kit(w, k).valdPursuit, 0)
        // 通常攻撃（準備なし）は変えない
        var plain = BasicAttackPlan(payload: HitPayload(damage: 100, damageType: .physical, source: .basicAttack), ranged: false)
        Kit_H033(isReady: true).shapeBasicAttack(&w.s, w.ctx, attacker: k, target: m, plan: &plain)
        XCTAssertEqual(plain.payload.damage, 100)
        // 構造物: 準備と射程の延長は消えるが、威力も踏み込みも乗らない
        let t = w.addTower(team: .red, at: skillArena + Vec2(400, 0))
        w.s.units[k].displacement = nil // 追撃の踏み込みを止める
        w.tick(2)
        w.s.units[k].hero!.skillCooldowns = [0, 0, 0, 0]
        XCTAssertTrue(w.cast(k, .skill2))
        w.s.units[k].displacement = nil
        var towerPlan = BasicAttackPlan(payload: HitPayload(damage: 100, damageType: .physical, source: .basicAttack), ranged: false)
        Kit_H033(isReady: true).shapeBasicAttack(&w.s, w.ctx, attacker: k, target: t, plan: &towerPlan)
        XCTAssertEqual(towerPlan.payload.damage, 100)
        XCTAssertEqual(kit(w, k).valdPursuit, 0)
        XCTAssertNil(w.s.units[k].displacement)
        XCTAssertNil(status(w, k, .attackRangeBoost, tag: Tune.pursuitRangeTag))
    }

    func testPursuitDoesNotDashWhileRootedButStillHitsHarder() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 300)
        XCTAssertTrue(w.cast(k, .skill2))
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .root, duration: 2, sourceID: w.id(e), tag: "t"))
        var plan = BasicAttackPlan(payload: HitPayload(damage: 100, damageType: .physical, source: .basicAttack), ranged: false)
        Kit_H033(isReady: true).shapeBasicAttack(&w.s, w.ctx, attacker: k, target: e, plan: &plan)
        XCTAssertEqual(plan.payload.damage, 140, accuracy: 1e-9)
        XCTAssertNil(w.s.units[k].displacement)
    }

    func testPursuitCritKeepsTheCritMultiplier() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 300)
        XCTAssertTrue(w.cast(k, .skill2))
        // 会心の攻撃（攻撃力 × 倍率）に 1.4 倍が掛かる
        var plan = BasicAttackPlan(payload: HitPayload(damage: 250, damageType: .physical, source: .basicAttack, isCrit: true),
                                   ranged: false)
        Kit_H033(isReady: true).shapeBasicAttack(&w.s, w.ctx, attacker: k, target: e, plan: &plan)
        XCTAssertEqual(plan.payload.damage, 350, accuracy: 1e-9)
        XCTAssertTrue(plan.payload.isCrit)
    }

    // MARK: - 複合吸血（奥義のパッシブ）

    func testHybridLifestealFollowsTheUltimateRank() {
        for (rank, want) in [(0, 0.0), (1, 0.10), (2, 0.20), (3, 0.30)] {
            var (w, k) = world(ranks: [1, 1, rank])
            w.tick(3)
            XCTAssertEqual(w.s.units[k].stats.lifesteal, want, accuracy: 1e-9, "rank \(rank)")
            XCTAssertEqual(w.s.units[k].stats.spellVamp, want * Tune.spellVampFactor, accuracy: 1e-9, "rank \(rank)")
            if rank == 0 {
                XCTAssertNil(status(w, k, .lifestealBoost))
                XCTAssertNil(status(w, k, .spellVampBoost))
            }
        }
        // ランクが上がれば大きさだけ更新する（重ならない）
        var (w, k) = world(ranks: [1, 1, 1])
        w.tick(3)
        w.s.units[k].hero!.skillRanks[SkillSlot.ultimate.rawValue] = 3
        w.tick(3)
        XCTAssertEqual(w.s.units[k].stats.lifesteal, 0.30, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[k].statuses.filter { $0.kind == .lifestealBoost }.count, 1)
        // 無期限
        w.run(seconds: 60)
        XCTAssertEqual(w.s.units[k].stats.lifesteal, 0.30, accuracy: 1e-9)
    }

    func testBasicAttackHealsByTheLifestealRatio() {
        var (w, k) = world(ranks: [1, 1, 3])
        let e = addEnemy(&w, dx: 120)
        w.tick(3)
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.5
        w.s.units[k].attackTargetID = w.id(e)
        w.log.removeAll()
        for _ in 0..<60 {
            w.tick()
            if let hit = basicHits(w, on: e).first {
                let healed = heals(w, of: k)
                XCTAssertEqual(healed.count, 1)
                XCTAssertEqual(healed.first ?? 0, hit.amount * 0.30, accuracy: 1e-6)
                return
            }
        }
        XCTFail("通常攻撃が当たらない")
    }

    func testSkillDamageHealsBySpellVampOncePerTarget() {
        var (w, k) = world(ranks: [1, 1, 2])
        let e1 = addEnemy(&w, dx: 100)
        let e2 = addEnemy(&w, dx: -100, hero: "H004")
        w.tick(3)
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.4
        w.log.removeAll()
        XCTAssertTrue(w.cast(k, .skill2))
        let d1 = skillHits(w, on: e1, .skill2).reduce(0) { $0 + $1.amount }
        let d2 = skillHits(w, on: e2, .skill2).reduce(0) { $0 + $1.amount }
        XCTAssertGreaterThan(d1, 0)
        XCTAssertGreaterThan(d2, 0)
        let healed = heals(w, of: k)
        XCTAssertEqual(healed.count, 2)
        XCTAssertEqual(healed.reduce(0, +), (d1 + d2) * 0.20 * Tune.spellVampFactor, accuracy: 1e-6)
    }

    func testNoLifestealBeforeTheUltimateIsLearned() {
        var (w, k) = world(ranks: [1, 1, 0])
        let e = addEnemy(&w, dx: 100)
        w.tick(3)
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.5
        w.log.removeAll()
        XCTAssertTrue(w.cast(k, .skill2))
        XCTAssertGreaterThan(skillHits(w, on: e, .skill2).count, 0)
        XCTAssertTrue(heals(w, of: k).isEmpty)
    }

    // MARK: - S1 地割り

    func testGroundsplitterRollsToThePointSlamsAndSlows() throws {
        var (w, k) = world()
        let hit = addEnemy(&w, dx: 400)
        let miss = addEnemy(&w, dx: 700, hero: "H003")
        let n = w.numbers(k, .skill1)
        XCTAssertTrue(w.cast(k, .skill1, at(300)))
        XCTAssertNotNil(kit(w, k).sweep)
        XCTAssertEqual(skillHits(w, on: hit, .skill1).count, 0, "着地するまでは当たらない")
        w.run(seconds: 0.6)
        XCTAssertEqual(w.s.units[k].pos.x, skillArena.x + 300, accuracy: 1)
        XCTAssertNil(kit(w, k).sweep)
        let hits = skillHits(w, on: hit, .skill1)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.amount ?? 0, w.mitigated(n.damage, .physical, on: hit), accuracy: 1e-6)
        XCTAssertEqual(skillHits(w, on: miss, .skill1).count, 0)
        XCTAssertEqual(kit(w, k).valdSlams, 1)
        let slow = try XCTUnwrap(status(w, hit, .slow, tag: Tune.s1SlowTag))
        XCTAssertEqual(slow.magnitude, 0.40, accuracy: 1e-9)
        XCTAssertGreaterThan(slow.remaining, 1.0)
        XCTAssertLessThanOrEqual(slow.remaining, 2.0)
        XCTAssertNil(status(w, miss, .slow))
        // 2 秒で鈍足が切れる
        w.run(seconds: 2.0)
        XCTAssertNil(status(w, hit, .slow, tag: Tune.s1SlowTag))
        XCTAssertEqual(cooldown(w, k, .skill1), n.cooldown - 2.6, accuracy: 0.1)
    }

    func testGroundsplitterDoesNotHitEnemiesOnThePathButOutsideTheSlam() {
        var (w, k) = world()
        let onPath = addEnemy(&w, dx: 100, dy: 0)
        XCTAssertTrue(w.cast(k, .skill1, at(350)))
        w.run(seconds: 0.6)
        // 経路の敵（落下点から 250 離れている: 半径 190 + 敵の半径 55 = 245 より外）には当たらない
        XCTAssertEqual(skillHits(w, on: onPath, .skill1).count, 0)
        XCTAssertEqual(w.s.units[k].pos.x, skillArena.x + 350, accuracy: 1)
    }

    func testGroundsplitterOnAUnitStopsAtItsEdgeAndHitsIt() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 250)
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        w.run(seconds: 0.6)
        let gap = w.s.units[e].pos.x - w.s.units[k].pos.x
        XCTAssertEqual(gap, w.s.units[k].radius + w.s.units[e].radius + Tune.s1Gap, accuracy: 1)
        XCTAssertEqual(skillHits(w, on: e, .skill1).count, 1)
    }

    func testGroundsplitterIsCappedAtItsRangeAndWorksWithNoTarget() {
        var (w, k) = world()
        XCTAssertTrue(w.cast(k, .skill1, at(1200)))
        w.run(seconds: 0.6)
        XCTAssertEqual(w.s.units[k].pos.x, skillArena.x + Tune.s1Range, accuracy: 1)
        // 対象も地点も無い: 向き（東）へ最大距離
        var (w2, k2) = world()
        XCTAssertTrue(w2.cast(k2, .skill1))
        w2.run(seconds: 0.6)
        XCTAssertEqual(w2.s.units[k2].pos.x, skillArena.x + Tune.s1Range, accuracy: 1)
        XCTAssertEqual(w2.damageEvents.count, 0)
    }

    func testGroundsplitterHitsMinionsAndMonstersToo() {
        var (w, k) = world()
        let m = w.addMinion(team: .red, at: skillArena + Vec2(300, 60))
        let mon = w.addMonster(.campSmall, at: skillArena + Vec2(300, -80))
        XCTAssertTrue(w.cast(k, .skill1, at(300)))
        w.run(seconds: 0.6)
        XCTAssertEqual(skillHits(w, on: m, .skill1).count, 1)
        XCTAssertEqual(skillHits(w, on: mon, .skill1).count, 1)
    }

    func testStunMidRollCancelsTheSlamButKeepsTheCooldown() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 350)
        XCTAssertTrue(w.cast(k, .skill1, at(330)))
        w.tick(2)
        XCTAssertNotNil(kit(w, k).sweep)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1.0, sourceID: w.id(e), tag: "t"))
        w.run(seconds: 0.8)
        XCTAssertNil(kit(w, k).sweep)
        XCTAssertEqual(skillHits(w, on: e, .skill1).count, 0)
        XCTAssertEqual(kit(w, k).valdSlams, 0)
        XCTAssertEqual(kit(w, k).valdSlamDamage, 0)
        XCTAssertLessThan(w.s.units[k].pos.x, skillArena.x + 330 - 20, "転がりは止められた")
        XCTAssertGreaterThan(cooldown(w, k, .skill1), 0)
    }

    func testRootBlocksTheRollButNotTheSpin() {
        var (w, k) = world()
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .root, duration: 2, sourceID: w.id(k), tag: "t"))
        XCTAssertFalse(w.cast(k, .skill1, at(300)), "ルート中は転がれない")
        XCTAssertEqual(cooldown(w, k, .skill1), 0)
        XCTAssertTrue(w.cast(k, .skill2), "旋回斬は動かないので撃てる")
    }

    // MARK: - S2 旋回斬

    func testWhirlingSmashHitsEveryoneAroundInstantlyAndOnlyThere() throws {
        var (w, k) = world()
        let e1 = addEnemy(&w, dx: 150)
        let e2 = addEnemy(&w, dx: -120, dy: 100, hero: "H004")
        let far = addEnemy(&w, dx: 420, hero: "H003")
        let m = w.addMinion(team: .red, at: skillArena + Vec2(0, -150))
        let n = w.numbers(k, .skill2)
        XCTAssertTrue(w.cast(k, .skill2))
        // 発動した tick のうちに当たる（照準なし）
        for e in [e1, e2] {
            let hits = skillHits(w, on: e, .skill2)
            XCTAssertEqual(hits.count, 1)
            XCTAssertEqual(hits.first?.amount ?? 0, w.mitigated(n.damage, .physical, on: e), accuracy: 1e-6)
            XCTAssertNil(status(w, e, .slow), "旋回斬に CC は無い")
        }
        XCTAssertEqual(skillHits(w, on: m, .skill2).count, 1)
        XCTAssertEqual(skillHits(w, on: far, .skill2).count, 0)
        XCTAssertEqual(w.s.units[k].pos, skillArena, "その場から動かない")
        XCTAssertEqual(cooldown(w, k, .skill2), n.cooldown, accuracy: 1e-9)
        // 味方には当たらない
        let ally = w.addHero("H002", team: .blue, at: skillArena + Vec2(50, 50), level: 12, ranks: [1, 1, 1])
        w.s.units[k].hero!.skillCooldowns = [0, 0, 0, 0]
        w.log.removeAll()
        XCTAssertTrue(w.cast(k, .skill2))
        XCTAssertTrue(w.damageEvents.allSatisfy { $0.targetID != w.id(ally) })
    }

    func testWhirlingSmashWithNobodyAroundStillCasts() {
        var (w, k) = world()
        XCTAssertTrue(w.cast(k, .skill2))
        XCTAssertEqual(w.damageEvents.count, 0)
        XCTAssertEqual(kit(w, k).valdPursuit, Tune.pursuitWindow)
    }

    /// 説明文: UI の用語（スキル1 / スキル2 / アルティメット）で、奥義の文は 吸収 / 半減 / 衝撃波 / 吸血 に分けてある。
    func testTextsUseUITermsAndTheUltimateTextIsSplitIntoParts() throws {
        for slot in SkillSlot.allCases {
            let t = try XCTUnwrap(HeroKits.text(heroID: "H033", slot: slot))
            for banned in ["S1", "S2", "奥義", "Skill1", "Skill2"] {
                XCTAssertFalse(t.ja.contains(banned) || t.en.contains(banned), "\(slot): \(banned)")
            }
        }
        let (w, k) = world()
        let hero = try XCTUnwrap(MasterData.shared.hero("H033"))
        let ult = try XCTUnwrap(MasterData.shared.skill(hero: "H033", slot: .ultimate))
        let n = SkillCatalog.numbers(for: ult, hero: hero, rank: 1, stats: w.s.units[k].stats)
        let ja = try XCTUnwrap(HeroKits.text(heroID: "H033", slot: .ultimate)).filled(
            english: false, numbers: n, targeting: SkillCatalog.targeting(for: ult, hero: hero))
        for part in ["吸収:", "半減:", "衝撃波:", "吸血:", "スキル1とスキル2"] { XCTAssertTrue(ja.contains(part), "\(part): \(ja)") }
        let sp = try XCTUnwrap(MasterData.shared.skill(hero: "H033", slot: .passive))
        let pja = try XCTUnwrap(HeroKits.text(heroID: "H033", slot: .passive)).filled(
            english: false, numbers: SkillCatalog.numbers(for: sp, hero: hero, rank: 1, stats: w.s.units[k].stats),
            targeting: SkillCatalog.targeting(for: sp, hero: hero))
        XCTAssertTrue(pja.contains("アルティメット"), pja)
        // スキルの吸血は通常攻撃の 1/3（範囲スキルが大勢に当たったときの回復が過大にならない）
        XCTAssertEqual(Tune.spellVampFactor, 0.33, accuracy: 1e-9)
        XCTAssertTrue(pja.contains("33%"), pja)
    }

    // MARK: - 奥義 1 回目: 吸収

    func testAbsorbDealsNoDamageButSlowsAndShredsEverythingInTheCircle() throws {
        var (w, k) = world()
        let e1 = addEnemy(&w, dx: 300)
        let m = w.addMinion(team: .red, at: skillArena + Vec2(300, 150))
        let out = addEnemy(&w, dx: 300, dy: 400, hero: "H003")
        let armor = w.s.units[e1].stats.armor
        let magic = w.s.units[e1].stats.magicResist
        XCTAssertTrue(w.cast(k, .ultimate, at(300)))
        XCTAssertTrue(w.damageEvents.isEmpty, "吸収そのものにダメージは無い")
        w.tick(2)
        for u in [e1, m] {
            let slow = try XCTUnwrap(status(w, u, .slow, tag: Tune.absorbSlowTag), "\(u)")
            XCTAssertEqual(slow.magnitude, 0.30, accuracy: 1e-9)
            XCTAssertNotNil(status(w, u, .armorShred))
            XCTAssertNotNil(status(w, u, .magicShred))
        }
        XCTAssertNil(status(w, out, .slow))
        XCTAssertNil(status(w, out, .armorShred))
        // 防御・魔防が 10 下がる
        XCTAssertEqual(w.s.units[e1].stats.armor, armor - 10, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[e1].stats.magicResist, magic - 10, accuracy: 1e-6)
        // 4 秒で元に戻る
        w.run(seconds: Tune.absorbDuration)
        XCTAssertNil(status(w, e1, .slow, tag: Tune.absorbSlowTag))
        XCTAssertEqual(w.s.units[e1].stats.armor, armor, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[e1].stats.magicResist, magic, accuracy: 1e-6)
    }

    func testAbsorbGivesDefensePerEnemyHeroOnlyAndHalvesOtherCooldowns() throws {
        var (w, k) = world()
        addEnemy(&w, dx: 250)
        addEnemy(&w, dx: 350, dy: 100, hero: "H004")
        addEnemy(&w, dx: 300, dy: -100, hero: "H003")
        w.addMinion(team: .red, at: skillArena + Vec2(300, 0))
        addEnemy(&w, dx: 300, dy: 500, hero: "H005")
        XCTAssertTrue(w.cast(k, .ultimate, at(300)))
        XCTAssertEqual(kit(w, k).valdAbsorbHeroes, 3, "ミニオンと円の外の敵ヒーローは数えない")
        XCTAssertEqual(kit(w, k).valdAbsorbs, 1)
        let dr = try XCTUnwrap(status(w, k, .damageReduction, tag: Tune.hasteTag))
        XCTAssertEqual(dr.magnitude, Tune.defensePerHero * 3, accuracy: 1e-9)
        XCTAssertEqual(dr.remaining, Tune.hasteDuration, accuracy: 1e-9)
        w.tick(2)
        XCTAssertEqual(w.s.units[k].stats.damageReduction, Tune.defensePerHero * 3, accuracy: 1e-9)
        // 敵ヒーローが居なければ防御は得ない（クールダウン半減は得る）
        var (w2, k2) = world()
        XCTAssertTrue(w2.cast(k2, .ultimate, at(300)))
        XCTAssertNil(status(w2, k2, .damageReduction, tag: Tune.hasteTag))
        XCTAssertEqual(kit(w2, k2).valdHaste, Tune.hasteDuration)
    }

    func testAbsorbDoesNotCountOrAffectInvulnerableHeroes() {
        var (w, k) = world()
        let shielded = addEnemy(&w, dx: 250)
        let normal = addEnemy(&w, dx: 350, dy: 100, hero: "H004")
        CombatSystem.addStatus(&w.s, targetIndex: shielded, StatusEffect(kind: .invulnerable, duration: 5, sourceID: w.id(shielded), tag: "t"))
        XCTAssertTrue(w.cast(k, .ultimate, at(300)))
        XCTAssertEqual(kit(w, k).valdAbsorbHeroes, 1)
        XCTAssertNil(status(w, shielded, .slow))
        XCTAssertNotNil(status(w, normal, .slow, tag: Tune.absorbSlowTag))
        XCTAssertEqual(status(w, k, .damageReduction, tag: Tune.hasteTag)?.magnitude ?? 0, Tune.defensePerHero, accuracy: 1e-9)
    }

    func testOtherSkillCooldownsTickTwiceAsFastForTheHasteDurationAndTheUltimateDoesNot() {
        var (w, k) = world()
        let n = w.numbers(k, .ultimate)
        XCTAssertTrue(w.cast(k, .ultimate, at(300)))
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill1.rawValue] = 20
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = 20
        let haste = Tune.hasteDuration
        w.run(seconds: 3)
        XCTAssertEqual(cooldown(w, k, .skill1), 20 - 6, accuracy: 0.15)
        XCTAssertEqual(cooldown(w, k, .skill2), 20 - 6, accuracy: 0.15)
        XCTAssertEqual(cooldown(w, k, .ultimate), n.cooldown - 3, accuracy: 0.15, "奥義自身は半減しない")
        // 半減の秒数を過ぎたら通常の速さ（合計 haste + 1 秒: haste 秒が 2 倍 + 1 秒が等倍）
        w.run(seconds: haste + 1 - 3)
        XCTAssertEqual(cooldown(w, k, .skill1), 20 - (2 * haste + 1), accuracy: 0.2)
        XCTAssertEqual(kit(w, k).valdHaste, 0)
        w.run(seconds: 1)
        XCTAssertEqual(cooldown(w, k, .skill1), 20 - (2 * haste + 2), accuracy: 0.2, "半減が終われば等倍")
    }

    func testAbsorbOpensTheSixSecondWindowAndSpendsTheCooldownUpFront() {
        var (w, k) = world()
        let n = w.numbers(k, .ultimate)
        XCTAssertTrue(w.cast(k, .ultimate, at(300)))
        XCTAssertEqual(cooldown(w, k, .ultimate), n.cooldown, accuracy: 1e-9, "最初の発動で CD を消費する")
        let info = HeroKits.recast(w.s.units[k].hero!, slot: .ultimate)
        XCTAssertEqual(info?.stage, 1)
        XCTAssertEqual(info?.total, Tune.ultWindow)
        XCTAssertEqual(info?.charges, 1)
        XCTAssertEqual(HeroKits.activeStage(w.s.units[k].hero!, slot: .ultimate), 1)
        // 窓の間は CD・コストを見ない（CD が残っていても撃てる）。時間で閉じる
        w.run(seconds: Tune.ultWindow + 0.2)
        XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: .ultimate))
        XCTAssertGreaterThan(cooldown(w, k, .ultimate), 0)
        XCTAssertFalse(w.cast(k, .ultimate, east), "窓が閉じれば CD 中は撃てない")
        // 発動の通知: 吸収は段 0、地点の円
        var (w2, k2) = world()
        w2.cast(k2, .ultimate, at(300))
        let ev = w2.castEvents.last
        XCTAssertEqual(ev?.stage, 0)
        XCTAssertEqual(ev?.shape, .circleAtPoint)
        XCTAssertEqual(ev?.target.x ?? 0, skillArena.x + 300, accuracy: 1e-6)
    }

    func testAbsorbWithNoTargetStillWorksAndCenterIsCappedAtTheCastRange() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 850)
        // 射程 450 に丸められた中心（+450）から半径 300 → +750 まで。敵は +850（半径 55 を足しても円の外）
        XCTAssertTrue(w.cast(k, .ultimate, at(1500)))
        XCTAssertNil(status(w, e, .slow))
        XCTAssertEqual(w.castEvents.last?.target.x ?? 0, skillArena.x + Tune.ultCastRange, accuracy: 1e-6)
        var (w2, k2) = world()
        XCTAssertTrue(w2.cast(k2, .ultimate))
        XCTAssertEqual(kit(w2, k2).valdAbsorbHeroes, 0)
    }

    // MARK: - 奥義 2 回目: 衝撃波

    /// 吸収は誰にも当てず（西へ）、窓だけ開く。
    private func openWindow(_ w: inout SkillWorld, _ k: Int) {
        XCTAssertTrue(w.cast(k, .ultimate, at(-400)))
        w.log.removeAll()
    }

    func testShockwavePiercesEverythingOnTheLineAndOnlyThere() throws {
        var (w, k) = world()
        let e1 = addEnemy(&w, dx: 300)
        let e2 = addEnemy(&w, dx: 700, hero: "H004")
        let m = w.addMinion(team: .red, at: skillArena + Vec2(500, 40))
        let off = addEnemy(&w, dx: 300, dy: 300, hero: "H003")
        let beyond = addEnemy(&w, dx: 1100, hero: "H005")
        openWindow(&w, k)
        let n = HeroKits.numbers(for: try XCTUnwrap(MasterData.shared.skill(hero: "H033", slot: .ultimate)),
                                 hero: try XCTUnwrap(MasterData.shared.hero("H033")), rank: 1, stats: w.s.units[k].stats, stage: 1)
        XCTAssertTrue(w.cast(k, .ultimate, east))
        XCTAssertEqual(w.s.projectiles.count, 1)
        XCTAssertTrue(w.s.projectiles[0].pierce)
        XCTAssertEqual(w.s.projectiles[0].width, Tune.waveHalfWidth)
        XCTAssertEqual(w.castEvents.last?.stage, 1)
        XCTAssertEqual(w.castEvents.last?.shape, .wideLine)
        w.run(seconds: 1.0)
        for e in [e1, e2] {
            let hits = skillHits(w, on: e, .ultimate)
            XCTAssertEqual(hits.count, 1, "\(e)")
            XCTAssertEqual(hits.first?.amount ?? 0, w.mitigated(n.damage, .physical, on: e), accuracy: 1e-6)
        }
        XCTAssertEqual(skillHits(w, on: m, .ultimate).count, 1)
        XCTAssertEqual(skillHits(w, on: off, .ultimate).count, 0)
        XCTAssertEqual(skillHits(w, on: beyond, .ultimate).count, 0, "長さ \(Tune.waveRange) の外")
        XCTAssertEqual(kit(w, k).valdWaves, 1)
    }

    func testShockwaveClosesTheWindowWithoutTouchingTheCooldownAndNeedsNoCost() {
        var (w, k) = world()
        openWindow(&w, k)
        let cdBefore = cooldown(w, k, .ultimate)
        w.s.units[k].resource = 0
        w.tick(5)
        let cdAfterTicks = cooldown(w, k, .ultimate)
        let energyBefore = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .ultimate, east), "窓の間はコストを見ない")
        XCTAssertEqual(cooldown(w, k, .ultimate), cdAfterTicks, accuracy: 1e-9, "再使用で CD は変わらない")
        XCTAssertLessThan(cdAfterTicks, cdBefore)
        XCTAssertEqual(w.s.units[k].resource, energyBefore, accuracy: 1e-9, "コストも消費しない")
        XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: .ultimate))
        XCTAssertFalse(w.cast(k, .ultimate, east), "1 回きり")
    }

    func testShockwaveDirectionFollowsAUnitTargetAndWorksWithNoEnemy() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 400, dy: 400, hero: "H004")
        openWindow(&w, k)
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        let dir = w.s.projectiles[0].motion
        if case .linear(let d, let maxD) = dir {
            XCTAssertEqual(d.x, d.y, accuracy: 1e-6)
            XCTAssertEqual(maxD, Tune.waveRange)
        } else {
            XCTFail("直線弾")
        }
        w.run(seconds: 1.0)
        XCTAssertEqual(skillHits(w, on: e, .ultimate).count, 1)
        // 敵が居ない: 向き（東）へそのまま撃つ
        var (w2, k2) = world()
        openWindow(&w2, k2)
        XCTAssertTrue(w2.cast(k2, .ultimate))
        w2.run(seconds: 1.5)
        XCTAssertTrue(w2.s.projectiles.allSatisfy(\.done), "波は端まで届いて消える")
        XCTAssertTrue(w2.damageEvents.isEmpty)
    }

    func testShockwaveHealsBySpellVampPerTargetAndRearmsPursuit() {
        var (w, k) = world(ranks: [1, 1, 1])
        let e1 = addEnemy(&w, dx: 300)
        let e2 = addEnemy(&w, dx: 600, hero: "H004")
        openWindow(&w, k)
        w.run(seconds: Tune.pursuitWindow + 0.3)
        XCTAssertEqual(kit(w, k).valdPursuit, 0)
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.3
        w.log.removeAll()
        XCTAssertTrue(w.cast(k, .ultimate, east))
        XCTAssertEqual(kit(w, k).valdPursuit, Tune.pursuitWindow, "衝撃波もスキルの発動")
        w.run(seconds: 1.0)
        let dealt = skillHits(w, on: e1, .ultimate).reduce(0) { $0 + $1.amount }
            + skillHits(w, on: e2, .ultimate).reduce(0) { $0 + $1.amount }
        XCTAssertGreaterThan(dealt, 0)
        let healed = heals(w, of: k)
        XCTAssertEqual(healed.count, 2)
        XCTAssertEqual(healed.reduce(0, +), dealt * 0.10 * Tune.spellVampFactor, accuracy: 1e-6)
    }

    func testStunDuringTheWindowBlocksTheShockwaveButNotTheWindowOrTheHaste() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 300)
        openWindow(&w, k)
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill1.rawValue] = 10
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1.5, sourceID: w.id(e), tag: "t"))
        XCTAssertFalse(w.cast(k, .ultimate, east), "スタン中は撃てない")
        XCTAssertNotNil(HeroKits.recast(w.s.units[k].hero!, slot: .ultimate), "窓は残る")
        w.run(seconds: 1.6)
        // スタンの間もクールダウンは 2 倍の速さで進む
        XCTAssertLessThan(cooldown(w, k, .skill1), 10 - 2.5)
        XCTAssertTrue(w.cast(k, .ultimate, east), "スタンが明ければ窓の中で撃てる")
        w.run(seconds: 1.0)
        XCTAssertEqual(skillHits(w, on: e, .ultimate).count, 1)
    }

    func testWindowCanBeUsedOnTheLastTickBeforeItExpires() {
        var (w, k) = world()
        openWindow(&w, k)
        w.run(seconds: Tune.ultWindow - 0.2)
        XCTAssertNotNil(HeroKits.recast(w.s.units[k].hero!, slot: .ultimate))
        XCTAssertTrue(w.cast(k, .ultimate, east))
        XCTAssertEqual(w.s.projectiles.count, 1)
    }

    // MARK: - 死亡・練習場・状態

    func testDeathResetsEverythingIncludingTheWindowPursuitAndHaste() {
        var (w, k) = world(ranks: [1, 1, 3])
        let e = addEnemy(&w, dx: 300)
        XCTAssertTrue(w.cast(k, .ultimate, at(300)))
        XCTAssertTrue(w.cast(k, .skill2))
        w.tick(3)
        XCTAssertNotNil(HeroKits.recast(w.s.units[k].hero!, slot: .ultimate))
        kill(&w, k, by: e)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        XCTAssertEqual(kit(w, k), KitState())
        XCTAssertTrue(w.s.units[k].statuses.isEmpty)
        w.run(seconds: 1)
        XCTAssertEqual(kit(w, k), KitState(), "死亡中は更新しない")
        XCTAssertTrue(w.s.projectiles.isEmpty)
    }

    func testDyingMidRollLeavesNothingBehind() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 350)
        XCTAssertTrue(w.cast(k, .skill1, at(330)))
        w.tick(2)
        kill(&w, k, by: e)
        w.run(seconds: 1)
        XCTAssertEqual(skillHits(w, on: e, .skill1).count, 0)
        XCTAssertEqual(kit(w, k), KitState())
    }

    func testTargetDyingMidRollOrMidWindowIsHarmless() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 250)
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        w.tick(2)
        kill(&w, e, by: k)
        w.run(seconds: 0.6)
        XCTAssertEqual(skillHits(w, on: e, .skill1).count, 0)
        XCTAssertNil(kit(w, k).sweep)
        // 窓の途中で敵が全員倒れていても撃てる
        openWindow(&w, k)
        XCTAssertTrue(w.cast(k, .ultimate, east))
        w.run(seconds: 1.5)
        XCTAssertTrue(w.s.projectiles.allSatisfy(\.done))
    }

    func testPracticeNoCooldownsKeepsCooldownsAtZeroAndTheKitStillWorks() {
        var (w, k) = world(noCooldowns: true)
        let e = addEnemy(&w, dx: 200)
        let energy = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .skill2))
        XCTAssertEqual(cooldown(w, k, .skill2), 0)
        XCTAssertTrue(w.cast(k, .ultimate, at(200)))
        XCTAssertEqual(cooldown(w, k, .ultimate), 0)
        XCTAssertNotNil(status(w, e, .slow, tag: Tune.absorbSlowTag))
        XCTAssertTrue(w.cast(k, .ultimate, east), "窓は練習場でも開く")
        w.run(seconds: 1)
        XCTAssertGreaterThan(skillHits(w, on: e, .ultimate).count, 0)
        XCTAssertTrue(w.cast(k, .skill1, at(150)))
        w.run(seconds: 0.8)
        XCTAssertEqual(w.s.units[k].resource, energy, accuracy: 1e-9, "コスト 0")
        for slot in [SkillSlot.skill1, .skill2, .ultimate] { XCTAssertEqual(cooldown(w, k, slot), 0) }
        // 半減の補助はクールダウンを負にしない
        XCTAssertTrue(w.s.units[k].hero!.skillCooldowns.allSatisfy { $0 >= 0 })
    }

    func testStateStaysBoundedAndFinite() {
        var (w, k) = world()
        addEnemy(&w, dx: 200)
        w.run(seconds: 120)
        let st = kit(w, k)
        XCTAssertTrue(st.reals.allSatisfy { $0.isFinite })
        XCTAssertTrue(st.timers.allSatisfy { $0.isFinite && $0 >= 0 })
        XCTAssertLessThanOrEqual(w.s.units[k].statuses.count, 4)
    }

    // MARK: - 決定性

    private func script(_ w: inout SkillWorld, k: Int, e1: Int, e2: Int, m: Int, step: Int) {
        switch step {
        case 0: w.cast(k, .skill1, .point(skillArena + Vec2(300, 0)))
        case 1: w.cast(k, .ultimate, .point(w.s.units[e1].pos))
        case 2: w.cast(k, .ultimate, .direction(Vec2(1, 0)))
        case 3: w.s.units[k].attackTargetID = w.id(e1)
        case 4: w.cast(k, .skill2)
        case 5: w.s.units[k].attackTargetID = w.id(e2)
        case 6: w.cast(k, .skill1, .unit(w.id(m)))
        case 7: w.cast(k, .skill2)
        case 8: w.s.units[k].attackTargetID = w.id(e1)
        default: break
        }
    }

    private func makeScriptWorld() -> (SkillWorld, Int, Int, Int, Int) {
        var w = SkillWorld()
        let k = w.addHero("H033", team: .blue, at: skillArena, level: 12, ranks: [2, 2, 2], facing: 0)
        let e1 = w.addHero("H001", team: .red, at: skillArena + Vec2(380, 0), level: 12)
        let e2 = w.addHero("H004", team: .red, at: skillArena + Vec2(330, 160), level: 12)
        let m = w.addMinion(team: .red, at: skillArena + Vec2(200, -100))
        // 吸血が働くよう、最初から傷ついている
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.5
        return (w, k, e1, e2, m)
    }

    private func run(_ w: inout SkillWorld, _ k: Int, _ e1: Int, _ e2: Int, _ m: Int, from: Int, to: Int) {
        for step in from..<to {
            script(&w, k: k, e1: e1, e2: e2, m: m, step: step)
            w.run(seconds: 0.7)
        }
    }

    func testScriptedRunIsDeterministicAndExercisesTheKit() {
        var (a, ka, a1, a2, am) = makeScriptWorld()
        var (b, kb, b1, b2, bm) = makeScriptWorld()
        run(&a, ka, a1, a2, am, from: 0, to: 10)
        run(&b, kb, b1, b2, bm, from: 0, to: 10)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(a.s.units, b.s.units)
        XCTAssertEqual(a.log, b.log)
        XCTAssertGreaterThanOrEqual(a.damageEvents.filter { $0.source.isSkill }.count, 6, "台本が実際にスキルを撃っている")
        XCTAssertTrue(a.damageEvents.contains { $0.source == .basicAttack })
        XCTAssertTrue(a.damageEvents.contains { $0.source == .skill(.ultimate) })
        XCTAssertGreaterThanOrEqual(kit(a, ka).valdPursuits, 1)
        XCTAssertGreaterThanOrEqual(kit(a, ka).valdWaves, 1)
        XCTAssertGreaterThanOrEqual(kit(a, ka).valdSlams, 1)
        XCTAssertTrue(a.log.contains { if case .heal = $0 { return true } else { return false } }, "吸血が働いている")
    }

    func testJSONRoundTripMidRollAndMidWindowResumesIdentically() throws {
        var (a, ka, a1, a2, am) = makeScriptWorld()
        run(&a, ka, a1, a2, am, from: 0, to: 10)

        // 転がりの途中
        var (b, kb, b1, b2, bm) = makeScriptWorld()
        b.cast(kb, .skill1, .point(skillArena + Vec2(300, 0)))
        b.tick(2)
        XCTAssertNotNil(kit(b, kb).sweep)
        let data = try JSONEncoder().encode(b.s)
        var resumed = b
        resumed.s = try JSONDecoder().decode(SimState.self, from: data)
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        b.run(seconds: 0.7)
        resumed.run(seconds: 0.7)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        run(&b, kb, b1, b2, bm, from: 1, to: 10)
        run(&resumed, kb, b1, b2, bm, from: 1, to: 10)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.damageEvents.count, b.damageEvents.count)

        // 奥義の窓の途中（クールダウン半減・防御・追撃の準備が動いている）
        var (c, kc, c1, c2, cm) = makeScriptWorld()
        run(&c, kc, c1, c2, cm, from: 0, to: 2)
        c.tick(5)
        XCTAssertNotNil(HeroKits.recast(c.s.units[kc].hero!, slot: .ultimate))
        XCTAssertGreaterThan(kit(c, kc).valdHaste, 0)
        let data2 = try JSONEncoder().encode(c.s)
        var resumed2 = c
        resumed2.s = try JSONDecoder().decode(SimState.self, from: data2)
        XCTAssertEqual(resumed2.s.stateHash(), c.s.stateHash())
        c.run(seconds: 0.7)
        resumed2.run(seconds: 0.7)
        XCTAssertEqual(resumed2.s.stateHash(), c.s.stateHash())
        run(&c, kc, c1, c2, cm, from: 2, to: 10)
        run(&resumed2, kc, c1, c2, cm, from: 2, to: 10)
        XCTAssertEqual(resumed2.s.stateHash(), c.s.stateHash())
        XCTAssertEqual(resumed2.s.units, c.s.units)
        XCTAssertEqual(resumed2.damageEvents.filter { $0.source == .skill(.ultimate) }.count,
                       c.damageEvents.filter { $0.source == .skill(.ultimate) }.count)
    }

    // MARK: - ボットの判断（共有のボット処理を実際に通す）

    /// ボット視点の場面（KitSharedTests の Scene と同じ作り）: ヴァルドが青の mid で、赤の mid の倒せない敵と向き合う。
    private struct BotScene {
        var f: BotFixture
        let me: Int
        let foe: Int
        var agent: BotAgent
        var mem: BotHeroMemory
        let sighting: BotSighting

        init(ranks: [Int] = [1, 1, 1, 1]) {
            var cfg = MatchFactory.botMatch(difficulty: .hard, seed: 5)
            let idx = cfg.players.firstIndex { $0.team == .blue && $0.position == .mid }!
            if let other = cfg.players.firstIndex(where: { $0.heroID == "H033" }), other != idx {
                cfg.players[other].heroID = cfg.players[idx].heroID
            }
            cfg.players[idx].heroID = "H033"
            var fx = BotFixture(config: cfg, time: 600)
            fx.parkAllHeroes()
            let m = fx.hero(.blue, .mid)
            let e = fx.hero(.red, .mid)
            fx.place(m, at: Vec2(6000, 6000))
            fx.place(e, at: Vec2(6300, 6000))
            fx.s.units[m].hero!.level = 12
            fx.s.units[m].hero!.skillRanks = ranks
            fx.s.units[m].hero!.skillCooldowns = Array(repeating: 0, count: fx.s.units[m].hero!.skillCooldowns.count)
            fx.s.units[m].resource = fx.s.units[m].stats.maxResource
            // 倒せない敵
            fx.s.units[e].stats.maxHP = 1_000_000
            fx.s.units[e].hp = 1_000_000
            let def = fx.ctx.master.hero("H033")!
            let sight = BotSighting(index: e, id: fx.s.units[e].id, pos: Vec2(6300, 6000), velocity: .zero,
                                    distance: 300, visible: true)
            var ag = BotAgent(i: m, slot: fx.slot(of: m), id: fx.s.units[m].id, team: .blue, profile: .of(.hard),
                              difficulty: .hard, pos: Vec2(6000, 6000), level: 12, role: def.role, position: .mid,
                              isRanged: def.isRanged, skillsWork: true)
            ag.enemies = [sight]
            me = m
            foe = e
            sighting = sight
            agent = ag
            mem = fx.memory(m)
            f = fx
        }

        mutating func castSkills() -> [PlayerCommand] {
            agent.commands = []
            mem.lastSkillTime = -100
            BotCombat.castSkills(&f.s, f.ctx, &agent, &mem, target: sighting, fighting: true)
            return agent.commands
        }

        mutating func farm(minions: Int = 3) -> [PlayerCommand] {
            var targets: [Int] = []
            for k in 0..<minions {
                targets.append(f.addMinion(.melee, team: .red, lane: .mid, at: Vec2(6250 + Double(k) * 20, 6000)))
            }
            agent.commands = []
            mem.lastSkillTime = -100
            BotCombat.castFarmSkills(&f.s, f.ctx, &agent, &mem, targets: targets, minCluster: 1)
            return agent.commands
        }
    }

    private static func slots(_ cmds: [PlayerCommand]) -> [SkillSlot] {
        cmds.compactMap { if case .castSkill(let slot, _) = $0 { return slot } else { return nil } }
    }

    /// 衝撃波（アルティメットの 2 回目）は、汎用の関門（倒せる・2 体以上）に関係なく撃つ。吸収（1 回目）は関門を通ったときだけ。
    func testBotRecastsTheShockwaveEvenWhenTheGateWouldBlockTheAbsorb() {
        var sc = BotScene()
        XCTAssertFalse(Self.slots(sc.castSkills()).contains(.ultimate), "倒せない 1 体への吸収は関門で止まる")
        // 吸収のあと（クールダウン中）で再使用の窓が開いている
        sc.f.s.units[sc.me].hero!.skillCooldowns[SkillSlot.ultimate.rawValue] = 30
        Kit.openRecast(&sc.f.s, caster: sc.me, slot: .ultimate, duration: Tune.ultWindow, stage: 1, charges: 1)
        XCTAssertTrue(HeroKits.isRecasting(sc.f.s, sc.me, .ultimate))
        let cmds = sc.castSkills()
        XCTAssertEqual(Self.slots(cmds).first, .ultimate, "\(cmds)")
        if case .castSkill(_, let target) = cmds.first {
            XCTAssertEqual(target, .unit(sc.f.s.units[sc.foe].id), "衝撃波は敵へ向ける")
        }
        // 窓が無ければ、クールダウン中の奥義は撃てない
        var closed = BotScene()
        closed.f.s.units[closed.me].hero!.skillCooldowns[SkillSlot.ultimate.rawValue] = 30
        XCTAssertFalse(Self.slots(closed.castSkills()).contains(.ultimate))
    }

    /// ファーム: Lv1〜3 の序盤（スキル1 だけ）でもミニオンの集団へ裂地撃（S1）を撃つ。HP が低いと撃たない。
    func testBotFarmsMinionsWithGroundsplitterAndStaysSafe() {
        var sc = BotScene(ranks: [1, 1, 0, 0])
        XCTAssertEqual(Self.slots(sc.farm()), [.skill1])
        var weak = BotScene(ranks: [1, 1, 0, 0])
        weak.f.s.units[weak.me].hp = weak.f.s.units[weak.me].stats.maxHP * 0.3
        XCTAssertTrue(Self.slots(weak.farm()).isEmpty, "HP が低いときは転がり込まない")
    }

    func testBotFarmDecisionAllowsOnlySkill1AndAvoidsEnemyTowers() throws {
        var (w, k) = world()
        let hero = try XCTUnwrap(MasterData.shared.hero("H033"))
        func tg(_ slot: SkillSlot) throws -> SkillTargeting {
            HeroKits.targeting(for: try XCTUnwrap(MasterData.shared.skill(hero: "H033", slot: slot)), hero: hero, stage: 0)
        }
        let center = skillArena + Vec2(250, 0)
        func farm(_ slot: SkillSlot) throws -> Bool {
            HeroKits.botFarm(w.s, w.ctx, bot: k, slot: slot, targeting: try tg(slot), center: center, count: 3)
        }
        XCTAssertTrue(try farm(.skill1))
        XCTAssertFalse(try farm(.skill2))
        XCTAssertFalse(try farm(.ultimate))
        _ = w.addTower(team: .red, at: center + Vec2(400, 0))
        XCTAssertFalse(try farm(.skill1), "敵のタワーの射程には転がり込まない")
    }

    // MARK: - ボットの煙テスト

    /// ヴァルドをボットにして通常の 10 人戦を回す。S1 / S2 / 奥義（吸収・衝撃波）のすべてを撃ち、追撃が起き、状態が壊れない。
    /// 奥義は汎用の関門（倒せる・2 体以上）を通ったときだけ撃つので、撃つまで種を変えて回す（最大 6 試合）。
    func testBotSmokeCastsEverySlotAndStateStaysBounded() throws {
        var casts: [SkillSlot: Int] = [:]
        var waves = 0
        var absorbs = 0
        var pursuits = 0
        var heroesCaught = 0
        var played = 0
        var lastTime = 0.0
        for seed in UInt64(33)..<UInt64(39) where absorbs == 0 || waves == 0 || pursuits == 0 || casts[.skill1, default: 0] == 0
            || casts[.skill2, default: 0] == 0 {
            played += 1
            var cfg = MatchFactory.botMatch(seed: seed)
            let idx = try XCTUnwrap(cfg.players.firstIndex { $0.team == .blue && $0.position == .jungle })
            if let other = cfg.players.firstIndex(where: { $0.heroID == "H033" }), other != idx {
                cfg.players[other].heroID = cfg.players[idx].heroID
            }
            cfg.players[idx].heroID = "H033"
            let sim = Simulation(config: cfg)
            let hero = try XCTUnwrap(sim.state.heroIndices.first { sim.state.units[$0].hero?.heroID == "H033" })
            let heroID = sim.state.units[hero].id
            XCTAssertNotNil(sim.state.units[hero].hero?.kit)
            lastTime = try runSmokeMatch(sim, heroID: heroID, casts: &casts, waves: &waves, absorbs: &absorbs,
                                         pursuits: &pursuits, heroesCaught: &heroesCaught)
        }
        XCTAssertGreaterThan(casts[.skill1, default: 0], 0, "S1: \(casts)")
        XCTAssertGreaterThan(casts[.skill2, default: 0], 0, "S2: \(casts)")
        XCTAssertGreaterThan(absorbs, 0, "奥義の吸収: \(casts) (試合 \(played))")
        XCTAssertGreaterThan(waves, 0, "奥義の衝撃波: \(casts) (試合 \(played))")
        XCTAssertGreaterThan(pursuits, 0, "追撃")
        print("H033 bot smoke: \(casts), absorbs \(absorbs), waves \(waves), pursuits \(pursuits), max heroes caught \(heroesCaught), matches \(played), last until \(lastTime) s")
    }

    /// 1 試合を回して、ヴァルドの発動を数え、状態が壊れていないことを見る（条件がそろったら 130 秒以降に打ち切る）。
    private func runSmokeMatch(_ sim: Simulation, heroID: EntityID, casts: inout [SkillSlot: Int], waves: inout Int,
                               absorbs: inout Int, pursuits: inout Int, heroesCaught: inout Int) throws -> Double {
        while !sim.isEnded && sim.state.time < 1800 {
            let events = sim.step()
            for e in events {
                if case .skillCast(let c) = e, c.casterID == heroID {
                    casts[c.slot, default: 0] += 1
                    if c.slot == .ultimate && c.stage == 1 { waves += 1 }
                    if c.slot == .ultimate && c.stage == 0 { absorbs += 1 }
                }
            }
            let i = sim.state.index(of: heroID)!
            let u = sim.state.units[i]
            let k = u.hero!.kit!
            pursuits = max(pursuits, k.valdPursuits)
            heroesCaught = max(heroesCaught, k.valdAbsorbHeroes)
            XCTAssertTrue(u.hp.isFinite && u.pos.x.isFinite && u.pos.y.isFinite && u.resource.isFinite)
            XCTAssertTrue(k.reals.allSatisfy { $0.isFinite })
            XCTAssertTrue(k.timers.allSatisfy { $0.isFinite && $0 >= 0 })
            XCTAssertLessThanOrEqual(k.scheduled.count, 4)
            XCTAssertLessThanOrEqual(u.statuses.count, 24)
            if casts[.skill1, default: 0] > 0, casts[.skill2, default: 0] > 0, absorbs > 0, waves > 0, pursuits > 0,
               sim.state.time > 130 { break }
        }
        return sim.state.time
    }

    // MARK: - 1v1 の TTK（H001–H006 相手、Lv 1 / 6 / 12）

    func testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives() {
        var failures: [String] = []
        var wins = 0
        var total = 0
        var table = "H033 TTK\n"
        for level in SkillBalanceTests.levels {
            for foe in SkillBalanceTests.representatives {
                let r = SkillBalanceTests.duel("H033", foe, level: level)
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

    // MARK: - 総当たりの勝率（レポート用。Release のみ）

    /// 全ヒーローとの 1v1 の勝率を Lv 1/6/12 で出し、汎用のアサシン（H006/H012/H018/H024）と同じ方法で並べる。
    func testRoundRobinWinRatesStayNearTheGenericAssassins() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter Kit_H033Tests")
        #else
        let ids = MasterData.shared.heroes.map(\.heroID)
        let subjects = ["H033", "H006", "H012", "H018", "H024", "H028"]
        var rates: [String: [Int: Double]] = [:]
        var table = "round robin win rate (%) vs all heroes, draws = half\n"
        for subject in subjects {
            var line = subject
            for level in SkillBalanceTests.levels {
                var points = 0.0
                var games = 0
                for foe in ids where foe != subject {
                    let r = SkillBalanceTests.duel(subject, foe, level: level)
                    games += 1
                    switch r.winnerIsA {
                    case .some(true): points += 1
                    case .some(false): break
                    case .none: points += 0.5
                    }
                }
                let rate = points / Double(max(1, games)) * 100
                rates[subject, default: [:]][level] = rate
                line += String(format: "  Lv%d %.0f%%", level, rate)
            }
            table += line + "\n"
        }
        print(table)
        // 同じ近傍: 汎用アサシンの幅 ±20pt に収まり、支配的でも無力でもない
        for level in SkillBalanceTests.levels {
            let generic = ["H006", "H012", "H018", "H024"].compactMap { rates[$0]?[level] }
            let vald = try XCTUnwrap(rates["H033"]?[level])
            XCTAssertGreaterThan(vald, (generic.min() ?? 0) - 20, "Lv\(level) 弱すぎる")
            XCTAssertLessThan(vald, (generic.max() ?? 100) + 20, "Lv\(level) 強すぎる")
        }
        #endif
    }
}
