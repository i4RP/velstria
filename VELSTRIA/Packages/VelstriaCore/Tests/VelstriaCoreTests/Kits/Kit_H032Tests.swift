import XCTest
@testable import VelstriaCore

/// H032 赤拳のディアス（Dyrroth）のキット。仕様: docs/kits/Dyrroth.md、実装対応表: 同ファイル末尾。
/// isReady になるまでは `HeroKits.testOverride` に差して試す（isReady 後も差しても同じ）。敵は動かない通常のヒーロー（H001 / H003 ほか）。
final class Kit_H032Tests: XCTestCase {
    typealias Tune = Kit_H032.Tune

    override func setUp() {
        super.setUp()
        HeroKits.testOverride = [Kit_H032(isReady: true)]
    }

    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    // MARK: - 土台

    /// ディアス（blue, 東向き）を置く。敵は別に addEnemy で足す。
    private func world(level: Int = 12, ranks: [Int]? = [1, 1, 1], noCooldowns: Bool = false) -> (SkillWorld, Int) {
        var w = SkillWorld(noCooldowns: noCooldowns)
        let k = w.addHero("H032", team: .blue, at: skillArena, level: level, ranks: ranks, facing: 0)
        return (w, k)
    }

    @discardableResult
    private func addEnemy(_ w: inout SkillWorld, dx: Double, dy: Double = 0, hero: String = "H001", level: Int = 12) -> Int {
        w.addHero(hero, team: .red, at: skillArena + Vec2(dx, dy), level: level, ranks: [1, 1, 1])
    }

    private func kit(_ w: SkillWorld, _ k: Int) -> KitState { w.s.units[k].hero!.kit! }

    private func setRage(_ w: inout SkillWorld, _ k: Int, _ v: Double) { w.s.units[k].hero!.kit!.diasRage = v }

    private let east = SkillTarget.direction(Vec2(1, 0))

    /// 1 tick ずつ進め、通常攻撃のダメージ（対象へ）を tick ごとにまとめて返す（命中の無い tick は含めない）。
    private func attackVolleys(_ w: inout SkillWorld, target: Int, ticks: Int, refill: Bool = true) -> [[DamageEvent]] {
        var out: [[DamageEvent]] = []
        let tid = w.id(target)
        for _ in 0..<ticks {
            if refill { w.s.units[target].hp = w.s.units[target].stats.maxHP }
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            let hits = w.damageEvents.filter { $0.targetID == tid && $0.source == .basicAttack }
            if !hits.isEmpty { out.append(hits) }
        }
        return out
    }

    private func heals(_ w: SkillWorld, of i: Int) -> [Double] {
        let id = w.id(i)
        return w.log.compactMap { if case .heal(let t, _, let a) = $0, t == id { return a } else { return nil } }
    }

    private func skillHits(_ w: SkillWorld, on e: Int, _ slot: SkillSlot) -> [DamageEvent] {
        w.damageEvents.filter { $0.targetID == w.id(e) && $0.source == .skill(slot) }
    }

    private func cooldown(_ w: SkillWorld, _ k: Int, _ slot: SkillSlot) -> Double { w.s.units[k].hero!.cooldown(slot) }

    // MARK: - レジストリ・照準・数値

    func testRegistryAndTargetingPerSlot() throws {
        XCTAssertTrue(HeroKits.hasKit("H032"))
        XCTAssertFalse(HeroKits.hasKit("H002"))
        let m = MasterData.shared
        let hero = try XCTUnwrap(m.hero("H032"))
        func target(_ slot: SkillSlot, stage: Int = 0) throws -> SkillTargeting {
            let skill = try XCTUnwrap(m.skill(hero: "H032", slot: slot))
            return HeroKits.targeting(for: skill, hero: hero, stage: stage)
        }
        let s1 = try target(.skill1)
        XCTAssertEqual(s1.archetype, .cone)
        XCTAssertEqual(s1.aim, .direction)
        XCTAssertEqual(s1.shape, .fan)
        XCTAssertEqual(s1.halfAngle, Tune.burstHalfAngle)
        XCTAssertEqual(s1.reach, Tune.burstReach)
        XCTAssertFalse(s1.recastable)
        let s2 = try target(.skill2)
        XCTAssertEqual(s2.archetype, .dashStrike)
        XCTAssertEqual(s2.aim, .direction)
        XCTAssertEqual(s2.shape, .dashToPoint)
        XCTAssertEqual(s2.range, Tune.dashRange)
        XCTAssertTrue(s2.recastable)
        XCTAssertFalse(s2.requiresTarget, "1 回目は敵が居なくても撃てる")
        let fatal = try target(.skill2, stage: 1)
        XCTAssertEqual(fatal.archetype, .targetedBlink)
        XCTAssertEqual(fatal.aim, .unit)
        XCTAssertEqual(fatal.shape, .lockOn)
        XCTAssertTrue(fatal.requiresTarget)
        XCTAssertTrue(fatal.recastable)
        XCTAssertEqual(fatal.reach, Tune.fatalReach)
        let ult = try target(.ultimate)
        XCTAssertEqual(ult.archetype, .piercingLine)
        XCTAssertEqual(ult.aim, .direction)
        XCTAssertEqual(ult.shape, .wideLine)
        XCTAssertEqual(ult.range, Tune.ultReach)
        XCTAssertEqual(ult.radius, Tune.ultHalfWidth)
        XCTAssertFalse(ult.requiresTarget)
        XCTAssertEqual(try target(.passive).archetype, .passive)
        // S1・奥義に段（再使用）は無い
        XCTAssertEqual(try target(.skill1, stage: 1), try target(.skill1))
        XCTAssertEqual(try target(.ultimate, stage: 1), try target(.ultimate))
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
        let hero = try XCTUnwrap(m.hero("H032"))
        let skill = try XCTUnwrap(m.skill(hero: "H032", slot: slot))
        let stats = w.s.units[k].stats
        return (HeroKits.numbers(for: skill, hero: hero, rank: rank, stats: stats, stage: stage),
                SkillCatalog.genericNumbers(for: skill, hero: hero, rank: rank, stats: stats))
    }

    /// 1 スロットの単体総ダメージは汎用の 0.8〜1.3 倍（アビス強化の版も含めて）。例外（docs/kits/Dyrroth.md の「バランス」）:
    /// - S1 の通常版は 0.40 以上、強化版は 0.75 以上。公式の減衰（2 発目以降 30%）と「1 発ごとに 140%」の強化（5 発）で、強化版の単体合計は
    ///   通常版の 1.925 倍になる。クールダウン短縮・円撃が上乗せされるので Lv12 の勝率で換算を決めた。
    /// - 奥義の基礎は 0.55 以上。失った HP の 20% が換算なしで乗る（下の testAbysmDamageGrowsWithTheTargetsLostHealth）。
    func testNumbersStayWithinDamageBudgetAndFollowCooldownFormula() throws {
        for level in [1, 6, 12] {
            for rank in 1...Balance.basicSkillMaxRank {
                // S1: 通常版（1 発目 + 30% × 2）と、アビス強化（140% + 42% × 4）
                let (s1, g1) = try numbers(.skill1, level: level, rank: rank)
                let r1 = s1.totalDamage / g1.totalDamage
                XCTAssertTrue((0.40...1.3).contains(r1), "S1 Lv\(level) r\(rank): \(r1)")
                let abyss1 = try XCTUnwrap(s1.extras.first { $0.key == "abyssTotal" }).value / g1.totalDamage
                XCTAssertTrue((0.75...1.3).contains(abyss1), "S1 abyss Lv\(level) r\(rank): \(abyss1)")
                XCTAssertEqual(abyss1 / r1, 1.4 * 2.2 / 1.6, accuracy: 1e-9)
                // S2: 1 回目 + 2 回目、アビス強化の 2 回目（追加物理攻撃 0 = 装備なしの値）
                let (dash, g2) = try numbers(.skill2, level: level, rank: rank)
                let (fatal, _) = try numbers(.skill2, level: level, rank: rank, stage: 1)
                let r2 = (dash.damage + fatal.damage) / g2.totalDamage
                XCTAssertTrue((0.8...1.3).contains(r2), "S2 Lv\(level) r\(rank): \(r2)")
                let lv = 1 + Double(rank - 1) * 5 / 3
                XCTAssertEqual(dash.damage / fatal.damage, (230 + (lv - 1) * 25) / (345 + (lv - 1) * 45), accuracy: 1e-9,
                               "公式の 1 回目 : 2 回目の表")
                let abyssFatal = try XCTUnwrap(dash.extras.first { $0.key == "abyssFatalDamage" }).value
                let abyss2 = (dash.damage + abyssFatal) / g2.totalDamage
                XCTAssertTrue((0.8...1.3).contains(abyss2), "S2 abyss Lv\(level) r\(rank): \(abyss2)")
            }
            // 奥義: 基礎ダメージ（失った HP の加算は含まない）
            for rank in 1...Balance.ultimateMaxRank {
                let (u, g) = try numbers(.ultimate, level: level, rank: rank)
                let r = u.totalDamage / g.totalDamage
                XCTAssertTrue((0.55...1.3).contains(r), "ult Lv\(level) r\(rank): \(r)")
            }
        }
        // クールダウン = MLBB の秒数（ランクで線形）× 全体倍率 × (1 − CD 短縮)
        let (w, k) = world()
        let cdr = w.s.units[k].stats.cooldownReduction
        func expected(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
            (a + (b - a) * Double(rank - 1) / Double(maxRank - 1)) * (1 - cdr) * Balance.Skills.cooldownScale
        }
        for rank in 1...4 {
            XCTAssertEqual(try numbers(.skill1, level: 12, rank: rank).kit.cooldown,
                           expected(6, 4, rank: rank, maxRank: 4), accuracy: 1e-9)
            XCTAssertEqual(try numbers(.skill2, level: 12, rank: rank).kit.cooldown,
                           expected(6, 6, rank: rank, maxRank: 4), accuracy: 1e-9)
        }
        for rank in 1...3 {
            XCTAssertEqual(try numbers(.ultimate, level: 12, rank: rank).kit.cooldown,
                           expected(36, 28, rank: rank, maxRank: 3), accuracy: 1e-9)
        }
        // ランクが上がるほど強く、CD は短く
        let a = try numbers(.skill1, level: 12, rank: 1).kit
        let b = try numbers(.skill1, level: 12, rank: 4).kit
        XCTAssertGreaterThan(b.damage, a.damage)
        XCTAssertLessThan(b.cooldown, a.cooldown)
        XCTAssertEqual(a.hits, 3)
        let u1 = try numbers(.ultimate, level: 12, rank: 1).kit
        let u3 = try numbers(.ultimate, level: 12, rank: 3).kit
        XCTAssertGreaterThan(u3.damage, u1.damage)
        // 窓・段
        let s2 = try numbers(.skill2, level: 12, rank: 1).kit
        XCTAssertEqual(s2.stages, 2)
        XCTAssertEqual(s2.recastWindow, Tune.recastWindow)
    }

    func testTextFillsEverySlotWithSimNumbers() throws {
        let (w, k) = world(level: 6, ranks: [2, 2, 2])
        let hero = try XCTUnwrap(MasterData.shared.hero("H032"))
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H032", slot: slot), "\(slot)")
            let skill = try XCTUnwrap(MasterData.shared.skill(hero: "H032", slot: slot))
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
        let s1 = try XCTUnwrap(MasterData.shared.skill(hero: "H032", slot: .skill1))
        let n1 = SkillCatalog.numbers(for: s1, hero: hero, rank: 2, stats: stats)
        let ja1 = try XCTUnwrap(HeroKits.text(heroID: "H032", slot: .skill1)).filled(
            english: false, numbers: n1, targeting: SkillCatalog.targeting(for: s1, hero: hero))
        XCTAssertTrue(ja1.contains("\(Int(n1.totalDamage.rounded()))"), ja1)
        XCTAssertTrue(ja1.contains("\(Int(try XCTUnwrap(n1.extras.first { $0.key == "abyssTotal" }).value.rounded()))"), ja1)
        let sp = try XCTUnwrap(MasterData.shared.skill(hero: "H032", slot: .passive))
        let pn = SkillCatalog.numbers(for: sp, hero: hero, rank: 1, stats: stats)
        XCTAssertEqual(pn.extras.map(\.value), [2, 5, 150, 180])
        let ult = try XCTUnwrap(MasterData.shared.skill(hero: "H032", slot: .ultimate))
        let un = SkillCatalog.numbers(for: ult, hero: hero, rank: 2, stats: stats)
        XCTAssertEqual(un.extras.count, 7)
        for (a, b) in zip(un.extras.map { $0.value }, [20, 0.5, 55, 0.8]) { XCTAssertEqual(a, b, accuracy: 1e-9) }
    }

    func testOfficialTablesCostsAndTags() throws {
        let m = MasterData.shared
        let hero = try XCTUnwrap(m.hero("H032"))
        func skill(_ slot: SkillSlot) throws -> SkillDef { try XCTUnwrap(m.skill(hero: "H032", slot: slot)) }
        let (w, k) = world(level: 6)
        let st = w.s.units[k].stats
        let atk = st.attack * Balance.skillAttackScalingFactor
        let s1 = Balance.Skills.damageScale(.skill1), s2 = Balance.Skills.damageScale(.skill2)
        let su = Balance.Skills.damageScale(.ultimate)
        for rank in 1...4 {
            let lv = 1 + Double(rank - 1) * 5 / 3
            // S1: 1 発目 = (240 → 520 + 60% 物理攻撃 × 0.6) × スロット倍率 × 換算
            XCTAssertEqual(Kit_H032.burstDamage(rank: rank, stats: st), (240 + (lv - 1) * 56 + 0.6 * atk) * s1 * Tune.burstScale,
                           accuracy: 1e-6, "S1 r\(rank)")
            // S2: 追加物理攻撃が 0（装備なし）なら基礎だけ
            let dash = HeroKits.numbers(for: try skill(.skill2), hero: hero, rank: rank, stats: st, stage: 0)
            let fatal = HeroKits.numbers(for: try skill(.skill2), hero: hero, rank: rank, stats: st, stage: 1)
            XCTAssertEqual(dash.damage, (230 + (lv - 1) * 25) * s2 * Tune.spectreScale, accuracy: 1e-6, "S2 r\(rank)")
            XCTAssertEqual(fatal.damage, (345 + (lv - 1) * 45) * s2 * Tune.spectreScale, accuracy: 1e-6, "S2 再使用 r\(rank)")
        }
        for (rank, b, cap) in [(1, 650.0, 1500.0), (2, 950, 2000), (3, 1250, 2500)] {
            let n = HeroKits.numbers(for: try skill(.ultimate), hero: hero, rank: rank, stats: st)
            XCTAssertEqual(n.damage, b * su * Tune.ultScale, accuracy: 1e-6)
            XCTAssertEqual(Kit_H032.ultNonHeroCap(rank: rank), cap * su * Tune.ultScale, accuracy: 1e-6)
        }
        XCTAssertEqual(Tune.ultLostHealth, 0.20)
        XCTAssertEqual(Tune.burstMinionFactor, 0.75)
        XCTAssertEqual(Tune.fatalSlowAbyss, 0.9)
        XCTAssertEqual(Tune.fatalSlowDuration, 1.0)
        // 追加物理攻撃（物理攻撃 − レベルの基礎値）だけで伸びる: 装備で +100 なら 1 回目に 0.6 × 100 × 0.6 × 倍率 × 換算
        var (v, j) = world(level: 6)
        let e = addEnemy(&v, dx: 200)
        v.s.units[j].stats.attack += 100
        XCTAssertEqual(Kit_H032.extraAttack(v.s.units[j]), 100, accuracy: 1e-9)
        XCTAssertTrue(v.cast(j, .skill2, east))
        let expected = (230 * s2 * Tune.spectreScale) + 0.6 * 100 * Balance.skillAttackScalingFactor * s2 * Tune.spectreScale
        XCTAssertEqual(kit(v, j).diasDashDamage, expected, accuracy: 1e-6)
        _ = e
        // コスト: 公式どおり無し
        for slot in SkillSlot.actives {
            for rank in 1...slot.maxRank {
                XCTAssertEqual(SkillSystem.cost(for: try skill(slot), hero: hero, rank: rank), 0, "\(slot) r\(rank)")
                XCTAssertEqual(HeroKits.numbers(for: try skill(slot), hero: hero, rank: rank, stats: st).cost, 0)
            }
        }
        // タグ（公式: パッシブ = バフ・回復、S1 = 範囲技・減速、S2 = 移動・ダメージ、ULT = バースト・減速）
        XCTAssertEqual(HeroKits.tags(heroID: "H032", slot: .passive), ["buff", "heal"])
        XCTAssertEqual(HeroKits.tags(heroID: "H032", slot: .skill1), ["aoe", "slow"])
        XCTAssertEqual(HeroKits.tags(heroID: "H032", slot: .skill2), ["mobility", "burst"])
        XCTAssertEqual(HeroKits.tags(heroID: "H032", slot: .ultimate), ["burst", "slow"])
        for slot in SkillSlot.allCases {
            for tag in HeroKits.tags(heroID: "H032", slot: slot) { XCTAssertTrue(KitTag.all.contains(tag), tag) }
        }
        // 説明文は公式の構造
        let n2 = HeroKits.numbers(for: try skill(.skill2), hero: hero, rank: 1, stats: st)
        let ja2 = try XCTUnwrap(HeroKits.text(heroID: "H032", slot: .skill2)).filled(
            english: false, numbers: n2, targeting: SkillCatalog.targeting(for: try skill(.skill2), hero: hero))
        XCTAssertTrue(ja2.contains("%追加物理攻撃)の物理ダメージを与えてわずかにノックバックさせる"), ja2)
        XCTAssertTrue(ja2.contains("再発動：3秒以内に") && ja2.contains("物理防御を4秒間40%低下させる"), ja2)
        XCTAssertTrue(ja2.contains("さらに1秒間90%減速させて、物理防御を4秒間60%低下させる"), ja2)
        let nu = HeroKits.numbers(for: try skill(.ultimate), hero: hero, rank: 1, stats: st)
        let jau = try XCTUnwrap(HeroKits.text(heroID: "H032", slot: .ultimate)).filled(
            english: false, numbers: nu, targeting: SkillCatalog.targeting(for: try skill(.ultimate), hero: hero))
        XCTAssertTrue(jau.contains("対象の失ったHPの20%の物理ダメージ") && jau.contains("制圧によってのみ中断される"), jau)
    }

    // MARK: - パッシブ: レイジ

    func testRageGainsOverTimeByLevelAndCapsAtMax() {
        // MLBB と同じ毎秒 2%（Lv1）〜 5%（最大レベル）
        for (level, perSecond) in [(1, 2.0), (15, 5.0)] {
            var (w, k) = world(level: level)
            XCTAssertEqual(kit(w, k).diasRage, 0, "開始時は 0")
            w.run(seconds: 5)
            XCTAssertEqual(kit(w, k).diasRage, perSecond * 5, accuracy: 0.2, "Lv\(level)")
        }
        XCTAssertEqual(Kit_H032.rageRate(level: 1), 2, accuracy: 1e-9)
        XCTAssertEqual(Kit_H032.rageRate(level: Balance.maxLevel), 5, accuracy: 1e-9)
        XCTAssertGreaterThan(Kit_H032.rageRate(level: 8), Kit_H032.rageRate(level: 7))
        var (w, k) = world()
        setRage(&w, k, 99.9)
        w.run(seconds: 2)
        XCTAssertEqual(kit(w, k).diasRage, Tune.rageMax, "上限 100")
    }

    func testRageBadgeAndAbyssReadyFlag() {
        var (w, k) = world()
        setRage(&w, k, 49)
        let hero = w.s.units[k].hero!
        // パッシブのバッジは 50 ごとに 1 段（0〜2）: 演出はバッジが増えた瞬間にだけ出るので、毎秒のレイジでは増えない
        XCTAssertEqual(HeroKits.badge(hero, slot: .passive), KitBadge(kind: .stacks, value: 0, maxValue: 2))
        XCTAssertNil(HeroKits.badge(hero, slot: .skill1))
        setRage(&w, k, 50)
        let ready = w.s.units[k].hero!
        XCTAssertEqual(HeroKits.badge(ready, slot: .passive), KitBadge(kind: .stacks, value: 1, maxValue: 2))
        XCTAssertEqual(HeroKits.badge(ready, slot: .skill1)?.kind, .form)
        XCTAssertEqual(HeroKits.badge(ready, slot: .skill2)?.kind, .form)
        XCTAssertNil(HeroKits.badge(ready, slot: .ultimate))
        setRage(&w, k, 99.9)
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive)?.value, 1)
        setRage(&w, k, 100)
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive), KitBadge(kind: .stacks, value: 2, maxValue: 2))
    }

    /// レイジが 0 → 100 まで毎 tick 増える間に、パッシブのバッジが変わるのは 50 と 100 の 2 回だけ（演出のスパム防止）。
    func testPassiveBadgeChangesOnlyAtThresholdsWhileRageBuilds() {
        var (w, k) = world(level: 12)
        var values: [Int] = [HeroKits.badge(w.s.units[k].hero!, slot: .passive)!.value]
        for _ in 0..<(30 * 40) {
            w.tick()
            let v = HeroKits.badge(w.s.units[k].hero!, slot: .passive)!.value
            if v != values.last { values.append(v) }
            if kit(w, k).diasRage >= Tune.rageMax { break }
        }
        XCTAssertEqual(values, [0, 1, 2])
        // 使って 50 を消費すると 1 つ減る
        XCTAssertGreaterThanOrEqual(kit(w, k).diasRage, Tune.rageMax)
        let e = addEnemy(&w, dx: 200)
        XCTAssertTrue(w.cast(k, .skill1, east))
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive)?.value, 1)
        _ = e
    }

    // MARK: - パッシブ: 円撃（Circle Strike）

    func testCircleStrikeOnEverySecondAttackWithLevelScaledDamage() {
        for (level, ratio) in [(1, 1.5), (15, 1.8)] {
            var (w, k) = world(level: level)
            let e = addEnemy(&w, dx: 140)
            w.s.units[k].attackTargetID = w.id(e)
            let volleys = attackVolleys(&w, target: e, ticks: 400)
            XCTAssertGreaterThanOrEqual(volleys.count, 6)
            let atk = w.s.units[k].stats.attack
            for (n, v) in volleys.prefix(6).enumerated() {
                XCTAssertEqual(v.count, 1)
                let expected = n % 2 == 0 ? atk : atk * ratio
                XCTAssertEqual(v[0].amount, w.mitigated(expected, .physical, on: e), accuracy: 1e-6, "Lv\(level) 攻撃 \(n + 1)")
            }
            XCTAssertEqual(Kit_H032.circleRatio(level: level), ratio, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(kit(w, k).diasCircles, 3)
        }
    }

    func testCircleStrikeHitsEveryEnemyAroundButOnlyOnTheCircleSwing() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 140)
        let near = addEnemy(&w, dx: -60, dy: 110, hero: "H003")          // 円の内側
        let far = addEnemy(&w, dx: 0, dy: 330, hero: "H004")             // 円の外側
        let m = w.addMinion(team: .red, at: skillArena + Vec2(20, -120))
        w.s.units[k].attackTargetID = w.id(e)
        let atk = w.s.units[k].stats.attack
        let ratio = Kit_H032.circleRatio(level: 12)
        // 1 回目: 周りには当たらない
        w.log.removeAll()
        var first: [DamageEvent] = []
        for _ in 0..<60 {
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            first = w.damageEvents.filter { $0.source == .basicAttack }
            if !first.isEmpty { break }
        }
        XCTAssertEqual(first.map(\.targetID), [w.id(e)])
        // 2 回目: 円撃。周りの敵ヒーロー・ミニオンにも同じ生ダメージ
        var second: [DamageEvent] = []
        for _ in 0..<60 {
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            second = w.damageEvents.filter { $0.source == .basicAttack }
            if !second.isEmpty { break }
        }
        let byTarget = Dictionary(uniqueKeysWithValues: second.map { ($0.targetID, $0.amount) })
        XCTAssertEqual(Set(byTarget.keys), [w.id(e), w.id(near), w.id(m)], "遠い敵には当たらない")
        XCTAssertNil(byTarget[w.id(far)])
        XCTAssertEqual(byTarget[w.id(e)]!, w.mitigated(atk * ratio, .physical, on: e), accuracy: 1e-6)
        XCTAssertEqual(byTarget[w.id(near)]!, w.mitigated(atk * ratio, .physical, on: near), accuracy: 1e-6)
        XCTAssertEqual(byTarget[w.id(m)]!, w.mitigated(atk * ratio, .physical, on: m), accuracy: 1e-6)
    }

    func testCircleStrikeHealsMaxHealthFractionAndHalvesAgainstMinionsAndTowers() {
        // 敵ヒーロー: 最大 HP の割合（Lv1 は 1.4%、最大レベルは 2%。公式の 7〜10% の 0.2 倍 = 伸び方は公式と同じ）
        XCTAssertEqual(Kit_H032.circleHealRatio(level: 1), 0.07 * 0.2, accuracy: 1e-9)
        XCTAssertEqual(Kit_H032.circleHealRatio(level: Balance.maxLevel), 0.10 * 0.2, accuracy: 1e-9)
        var (w, k) = world()
        let e = addEnemy(&w, dx: 140)
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.3
        w.s.units[k].hero!.kit!.diasSwings = 1
        w.s.units[k].attackTargetID = w.id(e)
        var healed: [Double] = []
        for _ in 0..<60 {
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            if w.damageEvents.contains(where: { $0.source == .basicAttack }) {
                healed = heals(w, of: k)
                break
            }
        }
        let st = w.s.units[k].stats
        let mult = (1 + st.healShieldPower) * st.healingReceivedMultiplier
        XCTAssertEqual(healed.count, 1)
        XCTAssertEqual(healed.first ?? 0, st.maxHP * Kit_H032.circleHealRatio(level: 12) * mult, accuracy: 1e-6)

        // ミニオンだけが相手: 半分
        var (w2, k2) = world()
        let m = w2.addMinion(team: .red, at: skillArena + Vec2(140, 0))
        w2.s.units[k2].hp = w2.s.units[k2].stats.maxHP * 0.3
        w2.s.units[k2].hero!.kit!.diasSwings = 1
        w2.s.units[k2].attackTargetID = w2.id(m)
        var healed2: [Double] = []
        for _ in 0..<60 {
            w2.log.removeAll(keepingCapacity: true)
            w2.tick()
            if w2.damageEvents.contains(where: { $0.source == .basicAttack }) {
                healed2 = heals(w2, of: k2)
                break
            }
        }
        let st2 = w2.s.units[k2].stats
        XCTAssertEqual(healed2.first ?? 0,
                       st2.maxHP * Kit_H032.circleHealRatio(level: 12) * Tune.circleHealNonHero
                           * (1 + st2.healShieldPower) * st2.healingReceivedMultiplier, accuracy: 1e-6)

        // ミニオンが主対象でも、周りに敵ヒーローが居れば全量
        var (w3, k3) = world()
        let m3 = w3.addMinion(team: .red, at: skillArena + Vec2(140, 0))
        addEnemy(&w3, dx: 0, dy: 120)
        w3.s.units[k3].hp = w3.s.units[k3].stats.maxHP * 0.3
        w3.s.units[k3].hero!.kit!.diasSwings = 1
        w3.s.units[k3].attackTargetID = w3.id(m3)
        var healed3: [Double] = []
        for _ in 0..<60 {
            w3.log.removeAll(keepingCapacity: true)
            w3.tick()
            if w3.damageEvents.contains(where: { $0.source == .basicAttack }) {
                healed3 = heals(w3, of: k3)
                break
            }
        }
        XCTAssertEqual(healed3.first ?? 0, healed.first ?? -1, accuracy: 1e-6)
    }

    func testCircleStrikeOnTowerStillCountsAndNeverHitsStructuresAround() {
        var (w, k) = world()
        let t = w.addTower(team: .red, at: skillArena + Vec2(150, 0))
        let t2 = w.addTower(team: .red, at: skillArena + Vec2(0, 150))
        for u in [t, t2] { w.s.units[u].visibleMask = Team.blue.visionBit | Team.red.visionBit }
        w.s.units[k].hero!.kit!.diasSwings = 1
        w.s.units[k].attackTargetID = w.id(t)
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.3
        w.run(seconds: 2)
        XCTAssertGreaterThanOrEqual(kit(w, k).diasCircles, 1)
        XCTAssertEqual(w.damage(to: t2), 0, "周りのタワーには当たらない（円撃は構造物を巻き込まない）")
    }

    /// 公式: 円撃は攻撃エフェクト（装備の命中時効果）を発動しない。通常の攻撃では働き、円撃の主対象では働かない
    /// （HitPayload.skipsItemOnHit）。吸血は円撃の主対象にも乗る（Fandom の注記）。
    func testCircleStrikeDoesNotTriggerItemOnHitEffectsButKeepsLifesteal() {
        var (w, k) = world()
        w.s.units[k].hero!.items = ["EQ119"]   // ラスティサイズ: 命中時に 80 の物理（.item）+ 減速
        let e = addEnemy(&w, dx: 140)
        w.s.units[k].attackTargetID = w.id(e)
        var itemHits: [Int] = []
        for _ in 0..<400 where itemHits.count < 4 {
            w.s.units[e].hp = w.s.units[e].stats.maxHP
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            let tid = w.id(e)
            guard w.damageEvents.contains(where: { $0.targetID == tid && $0.source == .basicAttack }) else { continue }
            itemHits.append(w.damageEvents.filter { $0.targetID == tid && $0.source == .item }.count)
        }
        XCTAssertEqual(itemHits, [1, 0, 1, 0], "円撃（2 回に 1 回）は装備の命中時効果を発動しない")
        XCTAssertEqual(kit(w, k).diasCircles, 2)

        // 吸血は円撃の主対象にも乗る（skipsItemOnHit は装備の命中時効果だけを外す）: 吸血 +50% の有無で、円撃の回復が与えたダメージの 50% だけ違う
        func circle(lifesteal: Double) -> (heal: Double, dealt: Double) {
            var (g, d) = world()
            g.s.units[d].hero!.kit!.diasSwings = 1
            let v = addEnemy(&g, dx: 140)
            g.s.units[d].hp = g.s.units[d].stats.maxHP * 0.3
            if lifesteal > 0 {
                CombatSystem.addStatus(&g.s, targetIndex: d, StatusEffect(kind: .lifestealBoost, duration: 10, magnitude: lifesteal,
                                                                          sourceID: g.id(d), tag: "test.lifesteal"))
            }
            g.s.units[d].attackTargetID = g.id(v)
            for _ in 0..<60 {
                g.log.removeAll(keepingCapacity: true)
                g.tick()
                let hits = g.damageEvents.filter { $0.targetID == g.id(v) && $0.source == .basicAttack }
                if !hits.isEmpty {
                    XCTAssertEqual(kit(g, d).diasCircles, 1)
                    return (heals(g, of: d).reduce(0, +), hits.map(\.amount).reduce(0, +))
                }
            }
            XCTFail("円撃が出ない")
            return (0, 0)
        }
        let plain = circle(lifesteal: 0)
        let vamp = circle(lifesteal: 0.5)
        XCTAssertGreaterThan(vamp.dealt, 0)
        XCTAssertEqual(vamp.heal - plain.heal, vamp.dealt * 0.5, accuracy: 1e-6, "円撃の主対象への吸血")
    }

    // MARK: - パッシブ: クールダウン短縮

    func testHeroDamageShortensSkillCooldownsButMinionDamageDoesNot() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 140)
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill1.rawValue] = 3
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = 3
        w.s.units[k].hero!.skillCooldowns[SkillSlot.ultimate.rawValue] = 20
        w.s.units[k].attackTargetID = w.id(e)
        var ticks = 0
        for _ in 0..<60 {
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            ticks += 1
            if w.damageEvents.contains(where: { $0.source == .basicAttack }) { break }
        }
        let dt = Balance.dt
        XCTAssertEqual(cooldown(w, k, .skill1), 3 - Double(ticks) * dt - Tune.cooldownRefund, accuracy: 1e-6)
        XCTAssertEqual(cooldown(w, k, .skill2), 3 - Double(ticks) * dt - Tune.cooldownRefund, accuracy: 1e-6)
        XCTAssertEqual(cooldown(w, k, .ultimate), 20 - Double(ticks) * dt, accuracy: 1e-6, "奥義は縮まない")

        var (w2, k2) = world()
        let m = w2.addMinion(team: .red, at: skillArena + Vec2(140, 0))
        w2.s.units[k2].hero!.skillCooldowns[SkillSlot.skill1.rawValue] = 3
        w2.s.units[k2].attackTargetID = w2.id(m)
        var t2 = 0
        for _ in 0..<60 {
            w2.log.removeAll(keepingCapacity: true)
            w2.tick()
            t2 += 1
            if w2.damageEvents.contains(where: { $0.source == .basicAttack }) { break }
        }
        XCTAssertEqual(cooldown(w2, k2, .skill1), 3 - Double(t2) * dt, accuracy: 1e-6)
    }

    func testSkillHitsShortenCooldownsOncePerCast() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 200)
        XCTAssertTrue(w.cast(k, .skill1, east))
        let cd1 = cooldown(w, k, .skill1)
        let cd2 = cooldown(w, k, .skill2)
        XCTAssertEqual(cd2, 0)
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = 5
        w.run(seconds: 0.7)       // 3 発とも当たる
        XCTAssertEqual(skillHits(w, on: e, .skill1).count, 3)
        let elapsed = (0.7 * Balance.tickRate).rounded(.up) * Balance.dt
        XCTAssertEqual(cooldown(w, k, .skill1), max(0, cd1 - elapsed - Tune.skillCooldownRefund), accuracy: 1e-6,
                       "3 発当たっても 1 回だけ縮む")
        XCTAssertEqual(cooldown(w, k, .skill2), 5 - elapsed - Tune.skillCooldownRefund, accuracy: 1e-6)
        // ミニオンだけに当たった発動では縮まない
        var (w2, k2) = world()
        let m = w2.addMinion(team: .red, at: skillArena + Vec2(200, 0))
        XCTAssertTrue(w2.cast(k2, .skill1, east))
        let before = cooldown(w2, k2, .skill1)
        w2.run(seconds: 0.7)
        XCTAssertEqual(skillHits(w2, on: m, .skill1).count, 3)
        XCTAssertEqual(cooldown(w2, k2, .skill1), max(0, before - elapsed), accuracy: 1e-6)
    }

    // MARK: - S1: 爆裂連撃

    func testBurstStrikeReleasesThreeDecayingBurstsSlowsAndSpendsNoRage() throws {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 200)
        let n = w.numbers(k, .skill1)
        let energy = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .skill1, east))
        XCTAssertEqual(energy - w.s.units[k].resource, 0, accuracy: 1e-9, "公式どおりコスト無し")
        XCTAssertEqual(cooldown(w, k, .skill1), n.cooldown, accuracy: 1e-9)
        XCTAssertEqual(w.damage(to: e), 0, "撃った tick にはまだ当たらない")
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.shape, .fan)
        XCTAssertEqual(ev.count, 3)
        XCTAssertEqual(ev.range, Tune.burstReach)
        XCTAssertEqual(kit(w, k).scheduled.count, 3)
        w.run(seconds: 0.7)
        let hits = skillHits(w, on: e, .skill1)
        XCTAssertEqual(hits.count, 3)
        // 公式の減衰: 1 発目 100%、2・3 発目 30%（damage は単体に 3 発当たったときの平均 = 合計 ÷ 3）
        let first = Kit_H032.burstDamage(rank: 1, stats: w.s.units[k].stats)
        XCTAssertEqual(n.damage * 3, first * 1.6, accuracy: 1e-6)
        for (i, h) in hits.enumerated() {
            XCTAssertEqual(h.amount, w.mitigated(first * [1.0, 0.3, 0.3][i], .physical, on: e), accuracy: 1e-6, "\(i + 1) 発目")
        }
        XCTAssertGreaterThan(hits[0].amount, hits[1].amount)
        XCTAssertEqual(hits[1].amount, hits[2].amount, accuracy: 1e-6)
        let slow = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .slow })
        XCTAssertEqual(slow.magnitude, 0.25, accuracy: 1e-9)
        XCTAssertEqual(kit(w, k).diasAbyssUses, 0)
        // 1.5 秒で解ける
        w.run(seconds: 1.6)
        XCTAssertFalse(w.s.units[e].statuses.contains { $0.kind == .slow })
    }

    func testBurstStrikeIsRestrictedToTheConeAndMinionsTakeLess() {
        var (w, k) = world()
        let front = addEnemy(&w, dx: 250)
        let side = addEnemy(&w, dx: 0, dy: 250, hero: "H003")      // 真横: 扇の外
        let behind = addEnemy(&w, dx: -200, hero: "H004")
        let far = addEnemy(&w, dx: 520, hero: "H005")               // 射程の外
        let m = w.addMinion(team: .red, at: skillArena + Vec2(200, 40))
        XCTAssertTrue(w.cast(k, .skill1, east))
        w.run(seconds: 0.7)
        XCTAssertEqual(skillHits(w, on: front, .skill1).count, 3)
        XCTAssertEqual(skillHits(w, on: side, .skill1).count, 0)
        XCTAssertEqual(skillHits(w, on: behind, .skill1).count, 0)
        XCTAssertEqual(skillHits(w, on: far, .skill1).count, 0)
        let minionHits = skillHits(w, on: m, .skill1)
        XCTAssertEqual(minionHits.count, 3)
        let heroRaw = skillHits(w, on: front, .skill1).map { $0.amount / (100 / (100 + w.s.units[front].stats.armor)) }
        for (i, h) in minionHits.enumerated() {
            XCTAssertEqual(h.amount, w.mitigated(heroRaw[i] * Tune.burstMinionFactor, .physical, on: m) * Balance.Skills.minionDamageMultiplier,
                           accuracy: 1e-6)
        }
    }

    func testAbyssBurstNeedsHalfRageSpendsItAndHitsFiveTimesFartherAndHarder() throws {
        // 49: 通常版
        var (w, k) = world()
        let e = addEnemy(&w, dx: 420)       // 通常の扇の外・強化の扇の内
        setRage(&w, k, 49)
        XCTAssertTrue(w.cast(k, .skill1, east))
        XCTAssertEqual(w.castEvents.last?.count, 3)
        XCTAssertEqual(kit(w, k).diasRage, 49, accuracy: 1e-9)
        w.run(seconds: 0.7)
        XCTAssertEqual(skillHits(w, on: e, .skill1).count, 0, "通常版は届かない")

        // 50: アビス強化
        var (w2, k2) = world()
        let e2 = addEnemy(&w2, dx: 420)
        let n = w2.numbers(k2, .skill1)
        setRage(&w2, k2, 60)
        XCTAssertTrue(w2.cast(k2, .skill1, east))
        XCTAssertEqual(kit(w2, k2).diasRage, 10, accuracy: 1e-9, "50 消費")
        XCTAssertEqual(kit(w2, k2).diasAbyssUses, 1)
        let ev = try XCTUnwrap(w2.castEvents.last)
        XCTAssertEqual(ev.count, 5)
        XCTAssertEqual(ev.range, Tune.burstReachAbyss)
        XCTAssertEqual(kit(w2, k2).scheduled.count, 5)
        w2.run(seconds: 0.9)
        let hits = skillHits(w2, on: e2, .skill1)
        XCTAssertEqual(hits.count, 5)
        // 公式: 1 発ごとに元のダメージの 140%（減衰の表 {140%, 42%, 42%, 42%, 42%}）
        let first = n.damage * 3 / 1.6
        for (i, h) in hits.enumerated() {
            XCTAssertEqual(h.amount, w2.mitigated(first * [1.4, 0.42, 0.42, 0.42, 0.42][i], .physical, on: e2), accuracy: 1e-6)
        }
        let abyssTotal = try XCTUnwrap(n.extras.first { $0.key == "abyssTotal" }).value
        XCTAssertEqual(abyssTotal, first * 3.08, accuracy: 1e-6)
        XCTAssertEqual(hits.reduce(0) { $0 + $1.amount }, w2.mitigated(abyssTotal, .physical, on: e2), accuracy: 1e-6)
        let slow = try XCTUnwrap(w2.s.units[e2].statuses.first { $0.kind == .slow })
        XCTAssertEqual(slow.magnitude, 0.5, accuracy: 1e-9, "鈍足は倍")

        // ちょうど 50 でも強化（境界）
        var (w3, k3) = world()
        setRage(&w3, k3, 50)
        XCTAssertTrue(w3.cast(k3, .skill1, east))
        XCTAssertEqual(w3.castEvents.last?.count, 5)
        XCTAssertEqual(kit(w3, k3).diasRage, 0, accuracy: 1e-9)
    }

    func testStunCancelsRemainingBurstsButAfterTheFirstBurstTheFirstStays() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 200)
        XCTAssertTrue(w.cast(k, .skill1, east))
        w.tick(1)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        w.run(seconds: 0.8)
        XCTAssertEqual(skillHits(w, on: e, .skill1).count, 0)
        XCTAssertTrue(kit(w, k).scheduled.isEmpty)
        XCTAssertGreaterThan(cooldown(w, k, .skill1), 0, "クールダウンは戻らない")

        var (w2, k2) = world()
        let e2 = addEnemy(&w2, dx: 200)
        XCTAssertTrue(w2.cast(k2, .skill1, east))
        w2.tick(4)                                  // 1 発目（0.1 秒）は出た
        CombatSystem.addStatus(&w2.s, targetIndex: k2, StatusEffect(kind: .stun, duration: 1))
        w2.run(seconds: 0.8)
        XCTAssertEqual(skillHits(w2, on: e2, .skill1).count, 1)
    }

    // MARK: - S2: 亡霊の歩み

    func testSpectreStepDashesToMaxDistanceWithoutEnemiesAndOpensTheWindow() {
        var (w, k) = world()
        let n = w.numbers(k, .skill2)
        let energy = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .skill2, east))
        XCTAssertEqual(energy - w.s.units[k].resource, 0, accuracy: 1e-9, "公式どおりコスト無し")
        XCTAssertEqual(cooldown(w, k, .skill2), n.cooldown, accuracy: 1e-9, "最初の発動で CD を消費する")
        XCTAssertNotNil(kit(w, k).sweep)
        let info = HeroKits.recast(w.s.units[k].hero!, slot: .skill2)
        XCTAssertEqual(info?.stage, 1)
        XCTAssertEqual(info?.total, Tune.recastWindow)
        XCTAssertEqual(HeroKits.activeStage(w.s.units[k].hero!, slot: .skill2), 1)
        XCTAssertEqual(w.castEvents.last?.shape, .dashToPoint)
        w.run(seconds: 0.4)
        XCTAssertNil(kit(w, k).sweep)
        XCTAssertEqual(w.s.units[k].pos.x, skillArena.x + Tune.dashRange, accuracy: 1)
        XCTAssertEqual(w.damageEvents.count, 0)
    }

    func testSpectreStepStopsAtTheFirstEnemyHitsOnlyItAndPushesItBack() throws {
        var (w, k) = world()
        let m = w.addMinion(team: .red, at: skillArena + Vec2(250, 0))
        let behind = addEnemy(&w, dx: 330)                      // 手前のミニオンで止まるので届かない
        let n = w.numbers(k, .skill2)
        let mx0 = w.s.units[m].pos.x
        XCTAssertTrue(w.cast(k, .skill2, east))
        XCTAssertEqual(kit(w, k).diasDashTargetID, w.id(m))
        w.run(seconds: 0.6)
        let hits = skillHits(w, on: m, .skill2)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].amount, w.mitigated(n.damage, .physical, on: m) * Balance.Skills.minionDamageMultiplier, accuracy: 1e-6)
        XCTAssertEqual(skillHits(w, on: behind, .skill2).count, 0)
        // ミニオンの縁で止まる（中心間 = 半径の和 + 少し）
        let gap = w.s.units[k].radius + w.s.units[m].radius
        XCTAssertEqual(w.s.units[m].pos.x - w.s.units[k].pos.x, gap + 5 + Tune.pushDistance, accuracy: 6)
        XCTAssertEqual(w.s.units[m].pos.x - mx0, Tune.pushDistance, accuracy: 1, "わずかに押し出される")
        XCTAssertEqual(w.s.units[m].pos.y, skillArena.y, accuracy: 1)
    }

    func testSpectreStepStopsAtAHeroAndPushesItWithoutHittingOthersOnTheWay() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 320)
        let side = addEnemy(&w, dx: 150, dy: 250, hero: "H003")    // 進路の幅の外
        let n = w.numbers(k, .skill2)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        w.run(seconds: 0.6)
        let hits = skillHits(w, on: e, .skill2)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].amount, w.mitigated(n.damage, .physical, on: e), accuracy: 1e-6)
        XCTAssertEqual(skillHits(w, on: side, .skill2).count, 0)
        XCTAssertLessThan(w.s.units[k].pos.x, skillArena.x + Tune.dashRange)
    }

    func testSpectreStepOnACCImmuneTargetDamagesButDoesNotPush() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 300)
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .ccImmune, duration: 5))
        XCTAssertTrue(w.cast(k, .skill2, east))
        let x0 = w.s.units[e].pos.x
        w.run(seconds: 0.6)
        XCTAssertEqual(skillHits(w, on: e, .skill2).count, 1)
        XCTAssertEqual(w.s.units[e].pos.x, x0, accuracy: 1e-6)
    }

    func testStunMidDashCancelsTheDashAndTheStrikeButKeepsTheWindowAndCooldown() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 400)
        XCTAssertTrue(w.cast(k, .skill2, east))
        w.tick(2)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        w.run(seconds: 0.6)
        XCTAssertNil(kit(w, k).sweep)
        XCTAssertEqual(kit(w, k).diasDashTargetID, 0)
        XCTAssertEqual(skillHits(w, on: e, .skill2).count, 0)
        XCTAssertLessThan(w.s.units[k].pos.x, skillArena.x + 300)
        XCTAssertGreaterThan(cooldown(w, k, .skill2), 0)
    }

    func testStrikeMissesWhenTheTargetDiesOrEscapesDuringTheDash() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 380)
        XCTAssertTrue(w.cast(k, .skill2, east))
        w.tick(2)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(k), targetIndex: e, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        w.run(seconds: 0.5)
        XCTAssertEqual(skillHits(w, on: e, .skill2).count, 0)
        XCTAssertEqual(kit(w, k).diasDashTargetID, 0)

        var (w2, k2) = world()
        let e2 = addEnemy(&w2, dx: 380)
        XCTAssertTrue(w2.cast(k2, .skill2, east))
        w2.tick(2)
        w2.s.units[e2].pos = skillArena + Vec2(380, 900)        // ブリンクなどで離脱
        w2.run(seconds: 0.5)
        XCTAssertEqual(skillHits(w2, on: e2, .skill2).count, 0)
    }

    // MARK: - S2: 致命の一撃（再使用）

    /// 敵ヒーローを突進で止めて押し出し、窓の中にいる状態にする。
    private func startFatalWorld(rage: Double = 0, dx: Double = 320) -> (SkillWorld, Int, Int) {
        var (w, k) = world()
        let e = addEnemy(&w, dx: dx)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        w.run(seconds: 0.5)
        setRage(&w, k, rage)
        return (w, k, e)
    }

    func testFatalStrikeLeapsAtTheHeroDealsDamageAndShredsArmorForFourSeconds() throws {
        var (w, k, e) = startFatalWorld()
        XCTAssertNotNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill2))
        let fatal = HeroKits.numbers(for: MasterData.shared.skill(hero: "H032", slot: .skill2)!,
                                     hero: MasterData.shared.hero("H032")!, rank: 1, stats: w.s.units[k].stats, stage: 1)
        let armor0 = w.s.units[e].stats.armor
        let energy = w.s.units[k].resource
        let cd = cooldown(w, k, .skill2)
        w.log.removeAll()
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))), "2 回目は CD・コストを使わない")
        XCTAssertEqual(w.s.units[k].resource, energy, accuracy: 1e-9)
        XCTAssertEqual(cooldown(w, k, .skill2), cd, accuracy: 1e-9)
        XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill2), "1 回の再使用で窓は閉じる")
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.stage, 1)
        XCTAssertEqual(ev.shape, .lockOn)
        XCTAssertEqual(ev.count, 1)
        XCTAssertEqual(skillHits(w, on: e, .skill2).count, 0, "到着するまでダメージは無い")
        w.run(seconds: 0.5)
        let hits = skillHits(w, on: e, .skill2)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].amount, fatal.damage * 100 / (100 + armor0), accuracy: 1e-6,
                       "防御ダウンはこの 1 撃には掛からない")
        let shred = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .armorShred })
        XCTAssertEqual(shred.magnitude, 0.4, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[e].stats.armor, armor0 * 0.6, accuracy: 1e-6)
        XCTAssertFalse(w.s.units[e].statuses.contains { $0.kind == .slow })
        XCTAssertEqual(w.s.units[k].pos.distance(to: w.s.units[e].pos),
                       w.s.units[k].radius + w.s.units[e].radius + 5, accuracy: 6)
        // 4 秒で戻る
        w.run(seconds: 3.4)
        XCTAssertEqual(w.s.units[e].stats.armor, armor0 * 0.6, accuracy: 1e-6, "まだ 4 秒たっていない")
        w.run(seconds: 0.6)
        XCTAssertFalse(w.s.units[e].statuses.contains { $0.kind == .armorShred })
        XCTAssertEqual(w.s.units[e].stats.armor, armor0, accuracy: 1e-6)
    }

    func testAbyssFatalStrikeSpendsRageReachesFartherAndAddsSlowAndDeeperShred() throws {
        // 遠い敵（350 を超え 500 以内）: レイジが足りなければ届かない
        var (w, k) = world()
        let e = addEnemy(&w, dx: 120)
        XCTAssertTrue(w.cast(k, .skill2, east))
        w.run(seconds: 0.4)
        // 敵を 450 先へ（術者の位置 + 450）
        w.s.units[e].pos = w.s.units[k].pos + Vec2(450, 0)
        setRage(&w, k, 49)
        XCTAssertFalse(w.cast(k, .skill2, .unit(w.id(e))), "49 では 350 まで")
        XCTAssertNotNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill2), "拒否されても窓は残る")
        XCTAssertEqual(kit(w, k).diasRage, 49, accuracy: 1e-9)
        setRage(&w, k, 50)
        let fatal = HeroKits.numbers(for: MasterData.shared.skill(hero: "H032", slot: .skill2)!,
                                     hero: MasterData.shared.hero("H032")!, rank: 1, stats: w.s.units[k].stats, stage: 1)
        let armor0 = w.s.units[e].stats.armor
        w.log.removeAll()
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        XCTAssertEqual(kit(w, k).diasRage, 0, accuracy: 1e-9)
        XCTAssertEqual(w.castEvents.last?.count, 2, "アビス強化の印")
        w.run(seconds: 0.5)
        let hits = skillHits(w, on: e, .skill2)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].amount, fatal.damage * Tune.abyssFatalMultiplier * 100 / (100 + armor0), accuracy: 1e-6)
        let shred = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .armorShred })
        XCTAssertEqual(shred.magnitude, 0.6, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[e].stats.armor, armor0 * 0.4, accuracy: 1e-6)
        let slow = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .slow })
        XCTAssertEqual(slow.magnitude, Tune.fatalSlowAbyss, accuracy: 1e-9)
    }

    func testFatalStrikeOnlyTargetsHeroesAndRefusesWithoutOne() {
        var (w, k) = world()
        let m = w.addMinion(team: .red, at: skillArena + Vec2(150, 0))
        XCTAssertTrue(w.cast(k, .skill2, east))
        w.run(seconds: 0.5)
        // 周りはミニオンだけ: 拒否、窓・レイジはそのまま
        setRage(&w, k, 80)
        XCTAssertFalse(w.cast(k, .skill2, .unit(w.id(m))))
        XCTAssertFalse(w.cast(k, .skill2, .none))
        XCTAssertNotNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill2))
        XCTAssertEqual(kit(w, k).diasRage, 80, accuracy: 1e-9)
        XCTAssertEqual(skillHits(w, on: m, .skill2).count, 1, "ミニオンには 1 回目の突進で当たっただけ")
        // 敵ヒーローが射程に入れば、ミニオンを指定しても敵ヒーローに飛ぶ
        let e = addEnemy(&w, dx: 0, dy: 250)
        w.s.units[e].pos = w.s.units[k].pos + Vec2(0, 250)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(m))))
        XCTAssertEqual(kit(w, k).diasDashTargetID, w.id(e))
    }

    func testRecastWindowExpiresAfterThreeSeconds() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 420)
        XCTAssertTrue(w.cast(k, .skill2, east))
        w.run(seconds: 2.5)
        XCTAssertNotNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill2))
        w.run(seconds: 0.6)
        XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill2))
        _ = e
    }

    func testStunMidFatalDashRefundsTheSpentRageAndCancelsTheStrike() {
        var (w, k, e) = startFatalWorld(rage: 80, dx: 300)
        w.s.units[e].pos = w.s.units[k].pos + Vec2(340, 0)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        XCTAssertEqual(kit(w, k).diasRage, 30, accuracy: 1e-9)
        w.tick(2)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        w.run(seconds: 0.5)
        XCTAssertEqual(skillHits(w, on: e, .skill2).filter { $0.amount > 0 }.count, 1, "1 回目の突進の分だけ")
        XCTAssertGreaterThanOrEqual(kit(w, k).diasRage, 80)
        XCTAssertEqual(kit(w, k).diasDashAbyss, 0)
        XCTAssertEqual(kit(w, k).diasDashTargetID, 0)
        XCTAssertFalse(w.s.units[e].statuses.contains { $0.kind == .armorShred })
    }

    func testFatalStrikeMissesIfTheTargetDiesOnTheWay() {
        var (w, k, e) = startFatalWorld(rage: 0, dx: 300)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        w.tick(1)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(k), targetIndex: e, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        w.run(seconds: 0.5)
        XCTAssertEqual(skillHits(w, on: e, .skill2).count, 1, "1 回目の分だけ")
        XCTAssertEqual(kit(w, k).diasDashTargetID, 0)
    }

    // MARK: - 奥義: 奈落の一撃

    private func ultRaw(_ w: SkillWorld, _ k: Int, _ e: Int) -> Double {
        let lost = max(0, w.s.units[e].stats.maxHP - max(0, w.s.units[e].hp))
        return w.numbers(k, .ultimate).damage + lost * Tune.ultLostHealth
    }

    /// 倒れずに全ダメージを受け止める大きなシールド（ダメージイベントの量 = 吸収 + HP 減少）。
    private func shieldUp(_ w: inout SkillWorld, _ i: Int) {
        CombatSystem.addShield(&w.s, w.ctx, sourceID: nil, targetIndex: i, amount: 1_000_000, duration: 100, tag: "test")
    }

    /// 自然回復ぶん（溜めの 0.5 秒で数 HP）の誤差。
    private let regenSlack = 2.0

    func testAbysmStrikeChargesRootedThenHitsTheLineWithLostHealthDamageAndSlow() throws {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 380)
        w.s.units[e].hp = w.s.units[e].stats.maxHP * 0.5
        shieldUp(&w, e)
        let raw = ultRaw(w, k, e)
        let n = w.numbers(k, .ultimate)
        XCTAssertTrue(w.cast(k, .ultimate, east))
        XCTAssertEqual(cooldown(w, k, .ultimate), n.cooldown, accuracy: 1e-9)
        XCTAssertEqual(kit(w, k).diasUltCharging, 1)
        XCTAssertTrue(w.s.units[k].has(.root))
        XCTAssertTrue(w.s.units[k].has(.channeling))
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.shape, .wideLine)
        XCTAssertEqual(ev.duration, Tune.ultCharge)
        w.run(seconds: 0.4)
        XCTAssertEqual(skillHits(w, on: e, .ultimate).count, 0, "溜めの間は当たらない")
        // 溜めの間はほかのスキルを始められず、攻撃もしない
        XCTAssertFalse(w.cast(k, .skill1, east))
        w.s.units[k].attackTargetID = w.id(e)
        w.tick()
        XCTAssertNil(w.s.units[k].attackTargetID)
        w.run(seconds: 0.3)
        let hits = skillHits(w, on: e, .ultimate)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].amount, w.mitigated(raw, .physical, on: e), accuracy: regenSlack)
        XCTAssertEqual(kit(w, k).diasUltCharging, 0)
        XCTAssertFalse(w.s.units[k].has(.root))
        XCTAssertFalse(w.s.units[k].has(.channeling))
        let slow = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .slow })
        XCTAssertEqual(slow.magnitude, 0.55, accuracy: 1e-9)
        XCTAssertEqual(slow.duration, 0.8, accuracy: 1e-9)
    }

    func testAbysmDamageGrowsWithTheTargetsLostHealth() {
        var amounts: [Double] = []
        var raws: [Double] = []
        for hpFraction in [1.0, 0.75, 0.5, 0.25, 0.05] {
            var (w, k) = world()
            let e = addEnemy(&w, dx: 300)
            w.s.units[e].hp = w.s.units[e].stats.maxHP * hpFraction
            shieldUp(&w, e)
            let raw = ultRaw(w, k, e)
            XCTAssertTrue(w.cast(k, .ultimate, east))
            w.run(seconds: 0.7)
            let hits = skillHits(w, on: e, .ultimate)
            XCTAssertEqual(hits.count, 1, "HP \(hpFraction)")
            let lost = w.s.units[e].stats.maxHP * (1 - hpFraction)
            XCTAssertEqual(raw, w.numbers(k, .ultimate).damage + lost * 0.20, accuracy: 1e-6, "公式: 失った HP の 20%")
            XCTAssertEqual(hits[0].amount, w.mitigated(raw, .physical, on: e), accuracy: regenSlack, "HP \(hpFraction)")
            amounts.append(hits[0].amount)
            raws.append(raw)
        }
        for i in 1..<amounts.count { XCTAssertGreaterThan(amounts[i], amounts[i - 1]) }
        // 満タンの相手には予算内（汎用の 0.8〜1.3 倍）、HP が少ない相手には予算を超える（意図: 失った HP の割合の追加ダメージ）
        let (w, k) = world()
        let generic = SkillCatalog.genericNumbers(
            for: MasterData.shared.skill(hero: "H032", slot: .ultimate)!, hero: MasterData.shared.hero("H032")!, rank: 1,
            stats: w.s.units[k].stats).totalDamage
        XCTAssertLessThanOrEqual(raws[0] / generic, 1.3)
        XCTAssertGreaterThan(raws[4], raws[0] * 2, "HP 5% の相手へは基礎の 2 倍を超える（失った HP の 20% の追加）")
    }

    func testAbysmHitsEveryEnemyOnTheLineButNotOutsideItAndCapsNonHeroDamage() {
        var (w, k) = world()
        let near = addEnemy(&w, dx: 200)
        let far = addEnemy(&w, dx: 640, dy: 40, hero: "H003")         // 線の終わりの丸い端の内側
        let off = addEnemy(&w, dx: 300, dy: 260, hero: "H004")         // 線の外（半幅 140 + 半径）
        let beyond = addEnemy(&w, dx: 950, hero: "H005")
        let behind = addEnemy(&w, dx: -260, hero: "H006")              // 線の始点の丸い端（半幅 + 半径）より後ろ
        let m = w.addMinion(team: .red, at: skillArena + Vec2(250, -60))
        w.s.units[m].hp = w.s.units[m].stats.maxHP * 0.2
        shieldUp(&w, m)
        let flat = w.numbers(k, .ultimate).damage
        let lostM = w.s.units[m].stats.maxHP * 0.8
        XCTAssertTrue(w.cast(k, .ultimate, east))
        w.run(seconds: 0.8)
        XCTAssertEqual(skillHits(w, on: near, .ultimate).count, 1)
        XCTAssertEqual(skillHits(w, on: far, .ultimate).count, 1)
        XCTAssertEqual(skillHits(w, on: off, .ultimate).count, 0)
        XCTAssertEqual(skillHits(w, on: beyond, .ultimate).count, 0)
        XCTAssertEqual(skillHits(w, on: behind, .ultimate).count, 0)
        // ミニオンにも失った HP の 20% が乗る（公式）。ヒーロー以外への合計は上限（1500 / 2000 / 2500 の換算）まで
        let mh = skillHits(w, on: m, .ultimate)
        XCTAssertEqual(mh.count, 1)
        let rawM = min(flat + lostM * Tune.ultLostHealth, Kit_H032.ultNonHeroCap(rank: 1))
        XCTAssertEqual(mh[0].amount, w.mitigated(rawM, .physical, on: m) * Balance.Skills.minionDamageMultiplier, accuracy: regenSlack)
        // 大きなモンスター: 失った HP が大きくても上限で止まる。ヒーローには上限が無い
        let cap = Kit_H032.ultNonHeroCap(rank: 1)
        XCTAssertEqual(Kit_H032.ultHitDamage(flat: flat, lostHealth: 100_000, isHero: false, cap: cap), cap, accuracy: 1e-9)
        XCTAssertEqual(Kit_H032.ultHitDamage(flat: flat, lostHealth: 100_000, isHero: true, cap: cap), flat + 20_000, accuracy: 1e-9)
        XCTAssertEqual(Kit_H032.ultHitDamage(flat: flat, lostHealth: 100, isHero: false, cap: cap), flat + 20, accuracy: 1e-9)
    }

    func testStunDuringTheChargeDoesNotStopTheStrikeButSuppressionDoes() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 300)
        XCTAssertTrue(w.cast(k, .ultimate, east))
        w.tick(3)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .airborne, duration: 0.3))
        w.run(seconds: 0.8)
        XCTAssertEqual(skillHits(w, on: e, .ultimate).count, 1, "スタン・打ち上げでは止まらない")

        var (w2, k2) = world()
        let e2 = addEnemy(&w2, dx: 300)
        XCTAssertTrue(w2.cast(k2, .ultimate, east))
        w2.tick(3)
        Kit.suppress(&w2.s, target: k2, duration: 1, sourceID: w2.id(e2))
        w2.tick(1)
        XCTAssertEqual(kit(w2, k2).diasUltCharging, 0)
        XCTAssertTrue(kit(w2, k2).scheduled.isEmpty)
        XCTAssertFalse(w2.s.units[k2].has(.root))
        w2.run(seconds: 1.0)
        XCTAssertEqual(skillHits(w2, on: e2, .ultimate).count, 0, "制圧された奥義は不発")
        XCTAssertGreaterThan(cooldown(w2, k2, .ultimate), 0, "クールダウンは戻らない")
    }

    /// 射程 650・半幅 140: 420 を超えて届くが、650 + 半径の外・半幅の外には当たらない。
    func testAbysmStrikeReachesSixHundredFiftyWithHalfWidthOneForty() throws {
        XCTAssertEqual(Tune.ultReach, 650)
        XCTAssertEqual(Tune.ultHalfWidth, 140)
        let r = Balance.heroRadius
        var (w, k) = world()
        let inside = addEnemy(&w, dx: 600, dy: 0)
        let wide = addEnemy(&w, dx: 300, dy: 140 + r - 6, hero: "H003")       // 半幅の縁
        let outsideWide = addEnemy(&w, dx: 300, dy: 140 + r + 40, hero: "H004")
        let tip = addEnemy(&w, dx: 650 + r - 6, dy: 0, hero: "H005")          // 先端の縁
        let past = addEnemy(&w, dx: 650 + r + 60, dy: 0, hero: "H006")
        for e in [inside, wide, outsideWide, tip, past] { shieldUp(&w, e) }
        XCTAssertTrue(w.cast(k, .ultimate, east))
        w.run(seconds: 0.8)
        XCTAssertEqual(skillHits(w, on: inside, .ultimate).count, 1)
        XCTAssertEqual(skillHits(w, on: wide, .ultimate).count, 1)
        XCTAssertEqual(skillHits(w, on: outsideWide, .ultimate).count, 0)
        XCTAssertEqual(skillHits(w, on: tip, .ultimate).count, 1)
        XCTAssertEqual(skillHits(w, on: past, .ultimate).count, 0)
        // 照準の寸法（AimLayer の帯・FX の線の長さ）は同じ値
        let t = HeroKits.targeting(for: try XCTUnwrap(MasterData.shared.skill(hero: "H032", slot: .ultimate)),
                                   hero: try XCTUnwrap(MasterData.shared.hero("H032")), stage: 0)
        XCTAssertEqual(t.range, 650)
        XCTAssertEqual(t.radius, 140)
    }

    // MARK: - ボット

    private func botTargeting(_ slot: SkillSlot) throws -> SkillTargeting {
        HeroKits.targeting(for: try XCTUnwrap(MasterData.shared.skill(hero: "H032", slot: slot)),
                           hero: try XCTUnwrap(MasterData.shared.hero("H032")), stage: 0)
    }

    /// 奥義: 交戦中の敵ヒーローが射程の手前に居れば関門を待たずに撃ち、溜めの間の動きを読んだ向きにする。
    func testBotUltimateCastsNowAtAnEnemyHeroAndLeadsItsMovement() throws {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 400)
        let t = try botTargeting(.ultimate)
        func ask(_ target: Int, fighting: Bool = true) -> BotKitDecision {
            HeroKits.botCast(w.s, w.ctx, bot: k, slot: .ultimate, targeting: t, target: target, fighting: fighting)
        }
        // 止まっている相手: 真正面（東）
        guard case .castNow(.direction(let d0)) = ask(e) else { return XCTFail("castNow を期待") }
        XCTAssertEqual(d0.x, 1, accuracy: 1e-6)
        XCTAssertEqual(d0.y, 0, accuracy: 1e-6)
        // 北へ動いている相手: 溜めの間の分だけ北寄りへ（真正面よりも y が大きい）
        w.s.units[e].prevPos = w.s.units[e].pos - Vec2(0, 8)
        guard case .castNow(.direction(let d1)) = ask(e) else { return XCTFail("castNow を期待") }
        XCTAssertGreaterThan(d1.y, 0.15)
        // 読みの長さは敵の移動速度の 0.5 秒分まで（異常に大きい移動でも射線は暴れない）
        w.s.units[e].prevPos = w.s.units[e].pos - Vec2(0, 500)
        guard case .castNow(.direction(let d2)) = ask(e) else { return XCTFail("castNow を期待") }
        let maxLead = w.s.units[e].stats.moveSpeed * Tune.ultCharge
        XCTAssertEqual(d2.y, maxLead / Vec2(400, maxLead).length, accuracy: 0.05)
        // 交戦中でない・遠い・ミニオンは従来どおり
        func isDefault(_ d: BotKitDecision) -> Bool { if case .useDefault = d { return true } else { return false } }
        XCTAssertTrue(isDefault(ask(e, fighting: false)))
        w.s.units[e].pos = skillArena + Vec2(Tune.ultBotReach + 40, 0)
        w.s.units[e].prevPos = w.s.units[e].pos
        XCTAssertTrue(isDefault(ask(e)))
        let m = w.addMinion(team: .red, at: skillArena + Vec2(300, 0))
        XCTAssertTrue(isDefault(ask(m)))
        // 溜めている最中は新たに撃たない
        w.s.units[e].pos = skillArena + Vec2(400, 0)
        XCTAssertTrue(w.cast(k, .ultimate, east))
        XCTAssertTrue(isDefault(ask(e)))
        // 奥義以外は既定
        for slot in [SkillSlot.skill1, .skill2] {
            XCTAssertTrue(isDefault(HeroKits.botCast(w.s, w.ctx, bot: k, slot: slot, targeting: try botTargeting(slot),
                                                     target: e, fighting: true)))
        }
    }

    /// ミニオン・ジャングルへは紅蓮の踏込（S2 の 1 回目）だけ。HP が低い・敵タワーの射程なら使わない。
    func testBotFarmAllowsOnlySkill2AndKeepsItSafe() throws {
        var (w, k) = world()
        let t2 = try botTargeting(.skill2)
        let center = skillArena + Vec2(250, 0)
        func farm(_ slot: SkillSlot) throws -> Bool {
            HeroKits.botFarm(w.s, w.ctx, bot: k, slot: slot, targeting: try botTargeting(slot), center: center, count: 3)
        }
        XCTAssertTrue(try farm(.skill2))
        XCTAssertFalse(try farm(.skill1))
        XCTAssertFalse(try farm(.ultimate))
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.4
        XCTAssertFalse(try farm(.skill2))
        w.s.units[k].hp = w.s.units[k].stats.maxHP
        _ = w.addTower(team: .red, at: center + Vec2(300, 0))
        XCTAssertFalse(try farm(.skill2))
        _ = t2
    }

    /// 説明文: パッシブはクールダウン短縮の秒数（通常攻撃・円撃 0.3 秒 / スキル 0.05 秒）を、UI の用語で書く。
    func testPassiveTextStatesBothRefundsAndUsesUITerms() throws {
        let (w, k) = world()
        let hero = try XCTUnwrap(MasterData.shared.hero("H032"))
        let sp = try XCTUnwrap(MasterData.shared.skill(hero: "H032", slot: .passive))
        let pn = SkillCatalog.numbers(for: sp, hero: hero, rank: 1, stats: w.s.units[k].stats)
        let ja = try XCTUnwrap(HeroKits.text(heroID: "H032", slot: .passive)).filled(
            english: false, numbers: pn, targeting: SkillCatalog.targeting(for: sp, hero: hero))
        XCTAssertTrue(ja.contains("\(String(format: "%g", Tune.cooldownRefund))秒"), ja)
        XCTAssertTrue(ja.contains("\(String(format: "%g", Tune.skillCooldownRefund))秒"), ja)
        XCTAssertTrue(ja.contains("円撃を含む"), ja)
        for slot in SkillSlot.allCases {
            let t = try XCTUnwrap(HeroKits.text(heroID: "H032", slot: slot))
            for banned in ["S1", "S2", "奥義", "Skill1", "Skill2"] {
                XCTAssertFalse(t.ja.contains(banned) || t.en.contains(banned), "\(slot): \(banned)")
            }
        }
        // 奥義の説明の射程は sim の 650
        let ult = try XCTUnwrap(MasterData.shared.skill(hero: "H032", slot: .ultimate))
        let un = SkillCatalog.numbers(for: ult, hero: hero, rank: 1, stats: w.s.units[k].stats)
        let uja = try XCTUnwrap(HeroKits.text(heroID: "H032", slot: .ultimate)).filled(
            english: false, numbers: un, targeting: SkillCatalog.targeting(for: ult, hero: hero))
        XCTAssertTrue(uja.contains("650"), uja)
    }

    func testAbysmUsesTheDirectionLockedAtCastTime() {
        var (w, k) = world()
        let north = addEnemy(&w, dx: 0, dy: 300)
        let east1 = addEnemy(&w, dx: 300, dy: 0, hero: "H003")
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Vec2(0, 1))))
        w.run(seconds: 0.8)
        XCTAssertEqual(skillHits(w, on: north, .ultimate).count, 1)
        XCTAssertEqual(skillHits(w, on: east1, .ultimate).count, 0)
    }

    // MARK: - 死亡・練習場・状態

    func testDeathResetsEverythingIncludingRageAndAChargingUltimate() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 300)
        setRage(&w, k, 90)
        w.s.units[k].hero!.kit!.diasSwings = 1
        XCTAssertTrue(w.cast(k, .ultimate, east))
        w.tick(3)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        XCTAssertEqual(kit(w, k), KitState())
        XCTAssertTrue(w.s.units[k].statuses.isEmpty)
        w.run(seconds: 1)
        XCTAssertEqual(kit(w, k), KitState(), "死亡中は更新しない")
        XCTAssertEqual(skillHits(w, on: e, .ultimate).count, 0)
    }

    func testPracticeNoCooldownsKeepsCooldownsAtZeroAndTheKitStillWorks() {
        var (w, k) = world(noCooldowns: true)
        let e = addEnemy(&w, dx: 300)
        let energy = w.s.units[k].resource
        for slot in [SkillSlot.skill1, .skill2, .ultimate] {
            XCTAssertTrue(w.cast(k, slot, east), "\(slot)")
            XCTAssertEqual(cooldown(w, k, slot), 0, "\(slot)")
            w.run(seconds: 0.8)
        }
        XCTAssertEqual(w.s.units[k].resource, energy, accuracy: 1e-9, "コスト 0")
        XCTAssertGreaterThan(skillHits(w, on: e, .skill1).count, 0)
        XCTAssertGreaterThan(skillHits(w, on: e, .ultimate).count, 0)
        // 短縮は 0 のまま
        w.s.units[k].attackTargetID = w.id(e)
        w.run(seconds: 2)
        XCTAssertEqual(cooldown(w, k, .skill1), 0)
        XCTAssertEqual(cooldown(w, k, .skill2), 0)
    }

    func testTargetDyingMidBurstSequenceAndMidUltimateIsHarmless() {
        var (w, k) = world()
        let e = addEnemy(&w, dx: 200)
        XCTAssertTrue(w.cast(k, .skill1, east))
        w.tick(2)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(k), targetIndex: e, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        w.run(seconds: 0.7)
        XCTAssertEqual(skillHits(w, on: e, .skill1).count, 0)
        XCTAssertTrue(kit(w, k).scheduled.isEmpty)
        XCTAssertTrue(w.cast(k, .ultimate, east))
        w.run(seconds: 0.8)
        XCTAssertEqual(kit(w, k).diasUltCharging, 0)
    }

    func testStateStaysBoundedAndFinite() {
        var (w, k) = world()
        addEnemy(&w, dx: 200)
        w.run(seconds: 120)
        let st = kit(w, k)
        XCTAssertEqual(st.diasRage, Tune.rageMax)
        XCTAssertTrue(st.reals.allSatisfy { $0.isFinite })
        XCTAssertTrue(st.timers.allSatisfy { $0.isFinite && $0 >= 0 })
    }

    // MARK: - 決定性

    private func script(_ w: inout SkillWorld, k: Int, e1: Int, e2: Int, m: Int, step: Int) {
        switch step {
        case 0:
            w.s.units[k].hero!.kit!.diasRage = 60
            w.cast(k, .skill1, .direction(Vec2(1, 0)))
        case 1: w.cast(k, .skill2, .unit(w.id(e1)))
        case 2: w.cast(k, .skill2, .unit(w.id(e1)))
        case 3: w.s.units[k].attackTargetID = w.id(e1)
        case 4: w.cast(k, .ultimate, .direction(Vec2(1, 0)))
        case 5: w.s.units[k].attackTargetID = w.id(e2)
        case 6: w.cast(k, .skill1, .unit(w.id(m)))
        case 7:
            w.s.units[k].hero!.kit!.diasRage = 100
            w.cast(k, .skill2, .unit(w.id(e2)))
        case 8: w.cast(k, .skill2, .unit(w.id(e2)))
        default: break
        }
    }

    private func makeScriptWorld() -> (SkillWorld, Int, Int, Int, Int) {
        var w = SkillWorld()
        let k = w.addHero("H032", team: .blue, at: skillArena, level: 12, ranks: [2, 2, 2], facing: 0)
        let e1 = w.addHero("H001", team: .red, at: skillArena + Vec2(380, 0), level: 12)
        let e2 = w.addHero("H004", team: .red, at: skillArena + Vec2(330, 160), level: 12)
        let m = w.addMinion(team: .red, at: skillArena + Vec2(200, -100))
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
        let skillHits = a.damageEvents.filter { $0.source.isSkill }
        XCTAssertGreaterThanOrEqual(skillHits.count, 6, "台本が実際にスキルを撃っている")
        XCTAssertTrue(a.damageEvents.contains { $0.source == .basicAttack })
        XCTAssertTrue(a.damageEvents.contains { $0.source == .skill(.ultimate) })
        XCTAssertGreaterThanOrEqual(kit(a, ka).diasAbyssUses, 1)
        XCTAssertGreaterThanOrEqual(kit(a, ka).diasCircles, 1)
    }

    func testJSONRoundTripMidDashAndMidUltimateResumesIdentically() throws {
        var (a, ka, a1, a2, am) = makeScriptWorld()
        run(&a, ka, a1, a2, am, from: 0, to: 10)

        // 突進の途中
        var (b, kb, b1, b2, bm) = makeScriptWorld()
        run(&b, kb, b1, b2, bm, from: 0, to: 1)
        // 台本の最初のスキル（扇）はミニオンを倒せなくなった（ミニオンへのスキル倍率）。生き残ったミニオンが進路を塞ぐと
        // 突進がすぐ止まるので、進路の外へ出す（検証したいのは突進の途中の保存と再開）
        b.s.units[bm].pos = skillArena + Vec2(0, 900)
        b.cast(kb, .skill2, .unit(b.id(b1)))
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
        run(&b, kb, b1, b2, bm, from: 2, to: 10)
        run(&resumed, kb, b1, b2, bm, from: 2, to: 10)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.damageEvents.count, b.damageEvents.count)

        // 奥義の溜めの途中
        var (c, kc, c1, c2, cm) = makeScriptWorld()
        run(&c, kc, c1, c2, cm, from: 0, to: 4)
        c.cast(kc, .ultimate, .direction(Vec2(1, 0)))
        c.tick(3)
        XCTAssertEqual(kit(c, kc).diasUltCharging, 1)
        XCTAssertEqual(kit(c, kc).scheduled.count, 1)
        let data2 = try JSONEncoder().encode(c.s)
        var resumed2 = c
        resumed2.s = try JSONDecoder().decode(SimState.self, from: data2)
        XCTAssertEqual(resumed2.s.stateHash(), c.s.stateHash())
        c.run(seconds: 0.7)
        resumed2.run(seconds: 0.7)
        XCTAssertEqual(resumed2.s.stateHash(), c.s.stateHash())
        XCTAssertEqual(resumed2.damageEvents.filter { $0.source == .skill(.ultimate) }.count,
                       c.damageEvents.filter { $0.source == .skill(.ultimate) }.count)
        run(&c, kc, c1, c2, cm, from: 5, to: 10)
        run(&resumed2, kc, c1, c2, cm, from: 5, to: 10)
        XCTAssertEqual(resumed2.s.stateHash(), c.s.stateHash())
        XCTAssertEqual(resumed2.s.units, c.s.units)
    }

    // MARK: - ボットの煙テスト

    /// ディアスをボットにして通常の 10 人戦を回す。S1 / S2（1・2 回目）/ 奥義のすべてを撃ち、状態が壊れない。
    func testBotSmokeCastsEverySlotAndStateStaysBounded() throws {
        var cfg = MatchFactory.botMatch(seed: 31)
        let idx = try XCTUnwrap(cfg.players.firstIndex { $0.team == .blue && $0.position == .top })
        if let other = cfg.players.firstIndex(where: { $0.heroID == "H032" }), other != idx {
            cfg.players[other].heroID = cfg.players[idx].heroID
        }
        cfg.players[idx].heroID = "H032"
        let sim = Simulation(config: cfg)
        let hero = try XCTUnwrap(sim.state.heroIndices.first { sim.state.units[$0].hero?.heroID == "H032" })
        let heroID = sim.state.units[hero].id
        XCTAssertNotNil(sim.state.units[hero].hero?.kit)
        var casts: [SkillSlot: Int] = [:]
        var fatalCasts = 0
        var abyssCasts = 0
        var circles = 0
        var maxRage = 0.0
        while !sim.isEnded && sim.state.time < 1500 {
            let events = sim.step()
            for e in events {
                if case .skillCast(let c) = e, c.casterID == heroID {
                    casts[c.slot, default: 0] += 1
                    if c.slot == .skill2 && c.stage == 1 { fatalCasts += 1 }
                    if c.slot == .skill1 && c.count == Tune.burstCountAbyss { abyssCasts += 1 }
                }
            }
            let i = sim.state.index(of: heroID)!
            let u = sim.state.units[i]
            let k = u.hero!.kit!
            circles = max(circles, k.diasCircles)
            maxRage = max(maxRage, k.diasRage)
            XCTAssertTrue(u.hp.isFinite && u.pos.x.isFinite && u.pos.y.isFinite && u.resource.isFinite)
            XCTAssertTrue(k.reals.allSatisfy { $0.isFinite })
            XCTAssertTrue(k.timers.allSatisfy { $0.isFinite && $0 >= 0 })
            XCTAssertGreaterThanOrEqual(k.diasRage, 0)
            XCTAssertLessThanOrEqual(k.diasRage, Tune.rageMax)
            XCTAssertLessThanOrEqual(k.scheduled.count, 8)
            XCTAssertLessThanOrEqual(u.statuses.count, 24)
            if casts[.skill1, default: 0] > 0, casts[.skill2, default: 0] > 0, casts[.ultimate, default: 0] > 0,
               fatalCasts > 0, sim.state.time > 130 { break }
        }
        XCTAssertGreaterThan(casts[.skill1, default: 0], 0, "S1: \(casts)")
        XCTAssertGreaterThan(casts[.skill2, default: 0], 0, "S2: \(casts)")
        XCTAssertGreaterThan(casts[.ultimate, default: 0], 0, "奥義: \(casts)")
        XCTAssertGreaterThan(fatalCasts, 0, "S2 の 2 回目")
        XCTAssertGreaterThanOrEqual(circles, 1)
        print("H032 bot smoke: \(casts), fatal \(fatalCasts), abyss S1 \(abyssCasts), circles \(circles), max rage \(maxRage) until \(sim.state.time) s")
    }

    // MARK: - 1v1 の TTK（H001–H006 相手、Lv 1 / 6 / 12）

    func testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives() {
        var failures: [String] = []
        var wins = 0
        var total = 0
        var table = "H032 TTK\n"
        for level in SkillBalanceTests.levels {
            for foe in SkillBalanceTests.representatives {
                let r = SkillBalanceTests.duel("H032", foe, level: level)
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

    /// 全 34 ヒーローとの 1v1 の勝率を Lv 1/6/12 で出し、汎用の Duelist（H002/H008/H014/H020）・ジャルド（H027）と同じ方法で並べる。
    func testRoundRobinWinRatesStayNearTheGenericDuelists() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter Kit_H032Tests")
        #else
        let ids = MasterData.shared.heroes.map(\.heroID)
        let subjects = ["H032", "H002", "H008", "H014", "H020", "H027"]
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
        // 同じ近傍: 汎用 Duelist の幅 ±20pt に収まり、支配的でも無力でもない
        for level in SkillBalanceTests.levels {
            let generic = ["H002", "H008", "H014", "H020"].compactMap { rates[$0]?[level] }
            let dias = try XCTUnwrap(rates["H032"]?[level])
            XCTAssertGreaterThan(dias, (generic.min() ?? 0) - 20, "Lv\(level) 弱すぎる")
            XCTAssertLessThan(dias, (generic.max() ?? 100) + 20, "Lv\(level) 強すぎる")
        }
        #endif
    }
}
