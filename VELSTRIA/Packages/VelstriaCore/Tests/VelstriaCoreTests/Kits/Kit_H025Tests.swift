import XCTest
@testable import VelstriaCore

/// H025 月弦のルミナ（MLBB ミヤの Velstria 版）のキット。仕様: docs/kits/Miya.md、実装対応表: 同ファイル末尾。
/// キットは HeroKits.testOverride に有効な Kit_H025 を差して試す（本番の有効化とは独立。有効化後も同じ結果）。
final class Kit_H025Tests: XCTestCase {
    typealias T = LuminaTuning
    static let east = Vec2(1, 0)

    override func setUp() {
        super.setUp()
        HeroKits.testOverride = [Kit_H025(isReady: true)]
    }

    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    // MARK: - 土台

    @discardableResult
    private func addLumina(_ w: inout SkillWorld, ranks: [Int]? = [1, 1, 1], level: Int = 1,
                           at pos: Vec2 = skillArena) -> Int {
        w.addHero("H025", team: .blue, at: pos, level: level, ranks: ranks, facing: 0)
    }

    /// 敵（動かない通常のヒーロー）。長い試験で倒れないよう HP を大きくする。
    @discardableResult
    private func addFoe(_ w: inout SkillWorld, dx: Double, dy: Double = 0, hero: String = "H003", tank: Bool = true) -> Int {
        let e = w.addDummyEnemy(at: skillArena + Vec2(dx, dy), hero: hero)
        if tank { w.s.units[e].hp = 1e8 }
        return e
    }

    /// 敵のミニオン（動かない）。
    @discardableResult
    private func addMinion(_ w: inout SkillWorld, dx: Double, dy: Double) -> Int {
        w.addMinion(team: .red, at: skillArena + Vec2(dx, dy))
    }

    private var def: HeroDef { MasterData.shared.hero("H025")! }

    private func skill(_ slot: SkillSlot) -> SkillDef { MasterData.shared.skill(hero: "H025", slot: slot)! }

    private func events(_ w: SkillWorld, to e: Int, _ source: DamageSource) -> [DamageEvent] {
        w.damageEvents.filter { $0.targetID == w.id(e) && $0.source == source }
    }

    private func slowMagnitude(_ w: SkillWorld, _ e: Int) -> Double? {
        w.s.units[e].statuses.first { $0.kind == .slow && $0.tag == T.slowTag }?.magnitude
    }

    private func degrees(_ v: Vec2) -> Double { v.angle * 180 / Double.pi }

    // MARK: - レジストリ・照準・説明

    func testRegistryTargetingAndTextPerSlot() throws {
        XCTAssertTrue(HeroKits.hasKit("H025"))
        XCTAssertNotNil(HeroKits.kit(for: "H025"))
        // 本番のレジストリでも有効（テストの差し込み無しで引ける）
        XCTAssertTrue(Kit_H025().isReady)
        HeroKits.testOverride = []
        XCTAssertTrue(HeroKits.hasKit("H025"))
        HeroKits.testOverride = [Kit_H025(isReady: true)]

        let m = MasterData.shared
        // スキル1 月弦分矢: 自己強化（照準なし）。リングは通常攻撃の射程と同じ 550、撃てる距離の目安 (reach) は 600
        let t1 = SkillCatalog.targeting(for: skill(.skill1), hero: def)
        XCTAssertEqual(t1.archetype, .selfAoE)
        XCTAssertEqual(t1.aim, .none)
        XCTAssertEqual(t1.shape, .selfRing)
        XCTAssertEqual(t1.radius, T.selfRing)
        XCTAssertEqual(T.selfRing, def.attackRange, "照準リング = 通常攻撃の射程")
        XCTAssertEqual(t1.reach, T.s1Reach)
        XCTAssertFalse(t1.requiresTarget)
        XCTAssertFalse(t1.recastable)

        // S2 月蝕の矢: 射程 650 の地点指定の円
        let t2 = SkillCatalog.targeting(for: skill(.skill2), hero: def)
        XCTAssertEqual(t2.archetype, .groundAoE)
        XCTAssertEqual(t2.aim, .point)
        XCTAssertEqual(t2.range, 650)
        XCTAssertEqual(t2.radius, T.s2Radius)
        XCTAssertEqual(t2.shape, .circleAtPoint)
        XCTAssertEqual(t2.reach, 650 + T.s2Radius)

        // アルティメット 隠れ月光: 自己強化。リングは 550、撃てる距離の目安 (reach) は奥義の距離 770
        let t3 = SkillCatalog.targeting(for: skill(.ultimate), hero: def)
        XCTAssertEqual(t3.archetype, .selfAoE)
        XCTAssertEqual(t3.aim, .none)
        XCTAssertEqual(t3.shape, .selfRing)
        XCTAssertEqual(t3.radius, T.selfRing)
        XCTAssertEqual(t3.reach, 770)

        XCTAssertEqual(SkillCatalog.targeting(for: skill(.passive), hero: def).archetype, .passive)
        // 再使用の段は無い: どの段でも同じ
        for slot in SkillSlot.actives {
            XCTAssertEqual(HeroKits.targeting(for: skill(slot), hero: def, stage: 1),
                           HeroKits.targeting(for: skill(slot), hero: def, stage: 0), "\(slot)")
        }

        // 説明文: 4 スロットとも ja/en があり、テンプレートの語が全部埋まる。数値は sim の値と一致する
        let stats = HeroGrowth.baseStats(def: def, level: 6)
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H025", slot: slot), "\(slot)")
            let sk = m.skill(hero: "H025", slot: slot)!
            let n = SkillCatalog.numbers(for: sk, hero: def, rank: 1, stats: stats)
            let t = SkillCatalog.targeting(for: sk, hero: def)
            for english in [false, true] {
                let filled = text.filled(english: english, numbers: n, targeting: t)
                XCTAssertFalse(filled.contains("{"), "\(slot) \(english): \(filled)")
                XCTAssertFalse(filled.isEmpty)
            }
        }
        let n1 = SkillCatalog.numbers(for: skill(.skill1), hero: def, rank: 1, stats: stats)
        let ja1 = HeroKits.text(heroID: "H025", slot: .skill1)!.filled(english: false, numbers: n1, targeting: t1)
        XCTAssertTrue(ja1.contains("\(Int(n1.damage.rounded()))(+100%物理攻撃)の物理ダメージ"), ja1)
        XCTAssertTrue(ja1.contains("この効果は4秒間持続する"), ja1)
        let n2 = SkillCatalog.numbers(for: skill(.skill2), hero: def, rank: 1, stats: stats)
        let minorBase = try XCTUnwrap(n2.extras.first { $0.key == "minorBase" })
        let en2 = HeroKits.text(heroID: "H025", slot: .skill2)!.filled(english: true, numbers: n2, targeting: t2)
        XCTAssertTrue(en2.contains("\(Int(minorBase.value.rounded())) (+"), en2)
        XCTAssertTrue(en2.contains("\(T.s2Arrows) scattering"), en2)
        let ja3 = HeroKits.text(heroID: "H025", slot: .ultimate)!.filled(english: false, numbers: SkillCatalog.numbers(for: skill(.ultimate), hero: def, rank: 1, stats: stats), targeting: t3)
        XCTAssertTrue(ja3.contains("65%"))
        let pa = SkillCatalog.numbers(for: skill(.passive), hero: def, rank: 1, stats: stats)
        XCTAssertEqual(pa.damage, T.shadowFlat + T.shadowRatio * stats.attack, accuracy: 1e-9)
    }

    /// 説明文: UI の用語（スキル1 / スキル2 / アルティメット）と、マスターの名前（月弦分矢 / 月蝕の矢 / 隠れ月光）に沿う。
    /// 秒数は 0.35 を 0.3 / 0.4 に丸めない。
    func testTextWordingAndFractionalSeconds() throws {
        let stats = HeroGrowth.baseStats(def: def, level: 6)
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H025", slot: slot))
            let n = SkillCatalog.numbers(for: skill(slot), hero: def, rank: 1, stats: stats)
            let t = SkillCatalog.targeting(for: skill(slot), hero: def)
            let ja = text.filled(english: false, numbers: n, targeting: t)
            XCTAssertFalse(ja.contains("S1") || ja.contains("S2") || ja.contains("奥義"), "\(slot): \(ja)")
            XCTAssertFalse(ja.contains("月矢の連弾") || ja.contains("追って"), "\(slot): \(ja)")
            if slot == .passive {
                XCTAssertTrue(ja.contains("「月影」を召喚して対象を攻撃し"), ja)
                XCTAssertTrue(ja.contains("\(Int(T.shadowFlat))(+\(Int((T.shadowRatio * 100).rounded()))%物理攻撃)"), ja)
            }
            if slot == .skill2 {
                XCTAssertTrue(ja.contains("0.35秒"), ja)
                let en = text.filled(english: true, numbers: n, targeting: t)
                XCTAssertTrue(en.contains("0.35s"), en)
            }
            if slot == .ultimate { XCTAssertTrue(ja.contains("アルティメット以外のスキル"), ja) }
        }
        XCTAssertEqual(Kit_H025.seconds(0.35), "0.35")
        XCTAssertEqual(Kit_H025.seconds(4), "4")
        XCTAssertEqual(Kit_H025.seconds(1.2), "1.2")
        XCTAssertEqual(Kit_H025.seconds(0.5), "0.5")
    }

    // MARK: - 数値・ダメージ予算

    func testDamageDurationCooldownAndManaFollowTheOfficialTables() throws {
        // 公式の表を 4 ランク（rank r → Lv 1 + (r − 1) × 5 / 3）・アルティメットの 3 ランク（Lv そのまま）へ線形補間する
        for level in [1, 6, 12] {
            let stats = HeroGrowth.baseStats(def: def, level: level)
            let atk = stats.attack * Balance.skillAttackScalingFactor
            let cdr = 1 - min(0.4, stats.cooldownReduction)
            for slot in SkillSlot.actives {
                let sk = skill(slot)
                for rank in 1...slot.maxRank {
                    let lv = 1 + Double(rank - 1) * 5 / 3
                    let n = SkillCatalog.numbers(for: sk, hero: def, rank: rank, stats: stats)
                    XCTAssertEqual(n.resource, .mana)
                    XCTAssertEqual(SkillSystem.cost(for: sk, hero: def, rank: rank), n.cost, accuracy: 1e-9)
                    switch slot {
                    case .skill1:
                        // 主矢の追加ダメージ = 基礎 10 → 35（+100% 物理攻撃 = 通常攻撃そのもの）× スロット倍率 × 換算
                        XCTAssertEqual(n.damage, (10 + (lv - 1) * 5) * 4.0 * T.s1Scale, accuracy: 1e-9, "S1 r\(rank)")
                        XCTAssertEqual(Kit_H025.s1Duration(rank: rank), 4 + (lv - 1), accuracy: 1e-9, "持続 4 → 9 秒")
                        XCTAssertEqual(n.extras.first { $0.key == "duration" }?.value ?? 0, 4 + (lv - 1), accuracy: 1e-9)
                        XCTAssertEqual(n.cooldown, 11 * cdr, accuracy: 1e-9, "MLBB の CD 11 秒（全ランク固定）")
                        XCTAssertEqual(n.cost, 60 + (lv - 1) * 5, accuracy: 1e-9, "MP 60 → 85（日本語クライアント）")
                    case .skill2:
                        // 着弾 270 → 420（+45%）、小さな矢 40 → 105（+20%）。6 本すべてが 1 体に当たる最悪でも着弾の 3 倍未満
                        XCTAssertEqual(n.damage, (270 + (lv - 1) * 30 + 0.45 * atk) * 3.0 * T.s2Scale, accuracy: 1e-6,
                                       "S2 r\(rank)")
                        let minor = Kit_H025.minorDamage(rank: rank, stats: stats)
                        XCTAssertEqual(minor, (40 + (lv - 1) * 13 + 0.20 * atk) * 3.0 * T.s2Scale, accuracy: 1e-6)
                        XCTAssertEqual(try XCTUnwrap(n.extras.first { $0.key == "minorDamage" }).value, minor.rounded())
                        XCTAssertLessThan(minor * Double(T.s2Arrows), n.damage * 3)
                        XCTAssertEqual(n.cooldown, 8 * cdr, accuracy: 1e-9, "MLBB の CD 8 秒（全ランク固定）")
                        XCTAssertEqual(n.cost, 80 + (lv - 1) * 10, accuracy: 1e-9, "MP 80 → 130")
                        XCTAssertEqual(n.cc, .root)
                        XCTAssertEqual(n.ccDuration, 1.2)
                        XCTAssertEqual(n.delay, T.s2Delay)
                    case .ultimate:
                        // 奥義は直接ダメージを持たない（ミヤの Hidden Moonlight と同じ。価値は隠密と最大の段 = docs の対応表）
                        XCTAssertEqual(n.damage, 0)
                        XCTAssertEqual(n.cc, .none)
                        XCTAssertEqual(n.cooldown, [30.0, 25, 20][rank - 1] * cdr, accuracy: 1e-9, "CD 30 / 25 / 20 秒")
                        XCTAssertEqual(n.cost, [120.0, 145, 170][rank - 1], accuracy: 1e-9, "MP 120 / 145 / 170")
                    case .passive:
                        break
                    }
                }
            }
        }
        // 月影 = 公式（日本語クライアント）25(+20% 物理攻撃) の形を shadowScale 倍
        XCTAssertEqual(T.shadowFlat, 25 * T.shadowScale, accuracy: 1e-9)
        XCTAssertEqual(T.shadowRatio, 0.20 * T.shadowScale, accuracy: 1e-9)
        XCTAssertEqual(T.attackSpeedPerStack, 0.05)
        // ランクが上がると S1・S2 は強くなる
        let stats = HeroGrowth.baseStats(def: def, level: 6)
        for slot in [SkillSlot.skill1, .skill2] {
            let lo = SkillCatalog.numbers(for: skill(slot), hero: def, rank: 1, stats: stats)
            let hi = SkillCatalog.numbers(for: skill(slot), hero: def, rank: slot.maxRank, stats: stats)
            XCTAssertGreaterThan(hi.damage, lo.damage, "\(slot)")
        }
    }

    func testTagsFollowTheOfficialSkillTags() {
        // Fandom: Buff / Buff・AOE / CC・AOE / Conceal・Remove CC（隠密・解除は語彙に無いので バフ・移動）
        XCTAssertEqual(HeroKits.tags(heroID: "H025", slot: .passive), ["buff"])
        XCTAssertEqual(HeroKits.tags(heroID: "H025", slot: .skill1), ["buff", "aoe"])
        XCTAssertEqual(HeroKits.tags(heroID: "H025", slot: .skill2), ["disrupt", "aoe"])
        XCTAssertEqual(HeroKits.tags(heroID: "H025", slot: .ultimate), ["conceal", "cleanse"])
        for slot in SkillSlot.allCases {
            for tag in HeroKits.tags(heroID: "H025", slot: slot) { XCTAssertTrue(KitTag.all.contains(tag), tag) }
        }
    }

    // MARK: - パッシブ（月環の導き）

    func testBasicAttackHitsStackAttackSpeedAndFullStacksSummonTheShadow() throws {
        var w = SkillWorld()
        let k = addLumina(&w)
        let e = addFoe(&w, dx: 400)
        w.tick()
        let baseSpeed = w.s.units[k].stats.attackSpeed
        w.s.units[k].attackTargetID = w.id(e)
        let attack = w.s.units[k].stats.attack
        let shadow = w.mitigated(Kit_H025.shadowDamage(attack: attack), .physical, on: e)
        let primary = w.mitigated(attack, .physical, on: e)

        var lastStacks = 0
        var stackLog: [Int] = []
        for _ in 0..<(30 * 10) {
            w.tick()
            let st = w.kit(k).luminaStacks
            if st != lastStacks {
                stackLog.append(st)
                lastStacks = st
                // 攻撃速度は段 × 5%
                w.tick()
                XCTAssertEqual(w.s.units[k].stats.attackSpeed, baseSpeed * (1 + T.attackSpeedPerStack * Double(st)), accuracy: 1e-9)
            }
        }
        XCTAssertEqual(Array(stackLog.prefix(5)), [1, 2, 3, 4, 5], "命中ごとに 1 段")
        XCTAssertEqual(w.kit(k).luminaStacks, 5, "5 段が上限")
        let hits = events(w, to: e, .basicAttack)
        let shadows = hits.filter { abs($0.amount - shadow) < 0.01 }
        let primaries = hits.filter { abs($0.amount - primary) < 0.01 }
        XCTAssertEqual(shadows.count + primaries.count, hits.count, "通常攻撃の被ダメは主矢か月影のどちらか")
        XCTAssertGreaterThan(shadows.count, 0)
        // 発動回数は着弾した月影の数（飛行中の最後の 1 本だけ多いことがある）
        XCTAssertTrue((0...1).contains(w.kit(k).luminaShadows - shadows.count), "\(w.kit(k).luminaShadows) vs \(shadows.count)")
        // 月影は 5 段になってから: 最初の 5 回の主矢の間に月影は挟まらない
        let firstShadow = try XCTUnwrap(hits.firstIndex { abs($0.amount - shadow) < 0.01 })
        XCTAssertGreaterThanOrEqual(firstShadow, 5)
        // 5 段のあいだは主矢と月影が 1 対 1
        XCTAssertLessThanOrEqual(abs(primaries.count - 5 - shadows.count), 1)
        XCTAssertTrue(hits.allSatisfy { !$0.isCrit }, "ロールの確定会心は置き換わる")
        XCTAssertEqual(w.s.units[k].hero!.passive.value, 0)
    }

    func testShadowDamageFormulaAndTowersAreExcluded() throws {
        var w = SkillWorld()
        let k = addLumina(&w, level: 6)
        let e = addFoe(&w, dx: 400)
        let tower = w.addTower(team: .red, at: skillArena + Vec2(0, 500))
        w.tick()
        let attack = w.s.units[k].stats.attack
        XCTAssertEqual(Kit_H025.shadowDamage(attack: attack), T.shadowFlat + T.shadowRatio * attack, accuracy: 1e-9)
        let kit = try XCTUnwrap(HeroKits.kit(of: w.s.units[k]))
        w.s.units[k].hero!.kit!.luminaStacks = 5
        var plan = BasicAttackPlan(payload: HitPayload(damage: 100, damageType: .physical, source: .basicAttack), ranged: true)
        kit.shapeBasicAttack(&w.s, w.ctx, attacker: k, target: e, plan: &plan)
        XCTAssertEqual(plan.extras.count, 1)
        XCTAssertEqual(plan.extras[0].damage, T.shadowFlat + T.shadowRatio * attack, accuracy: 1e-9)
        XCTAssertFalse(plan.extras[0].isCrit)
        XCTAssertFalse(plan.extras[0].appliesOnHit, "月影は命中時効果（吸血・段の加算）を持たない")
        XCTAssertEqual(plan.extras[0].source, .basicAttack)
        XCTAssertEqual(plan.payload.damage, 100)
        // 4 段では出ない
        w.s.units[k].hero!.kit!.luminaStacks = 4
        var plan4 = BasicAttackPlan(payload: HitPayload(damage: 100, damageType: .physical, source: .basicAttack), ranged: true)
        kit.shapeBasicAttack(&w.s, w.ctx, attacker: k, target: e, plan: &plan4)
        XCTAssertTrue(plan4.extras.isEmpty)
        // 構造物には月影も月矢も働かない
        w.s.units[k].hero!.kit!.luminaStacks = 5
        w.s.units[k].hero!.kit!.luminaMoonArrow = 3
        w.s.units[k].hero!.kit!.luminaArrowBonus = 99
        var planT = BasicAttackPlan(payload: HitPayload(damage: 100, damageType: .physical, source: .basicAttack), ranged: true)
        kit.shapeBasicAttack(&w.s, w.ctx, attacker: k, target: tower, plan: &planT)
        XCTAssertTrue(planT.extras.isEmpty)
        XCTAssertEqual(planT.payload.damage, 100)
        XCTAssertEqual(w.s.projectiles.count, 0)
    }

    func testStacksExpireAfterFourSecondsWithoutHitAndRefreshOnHit() {
        var w = SkillWorld()
        let k = addLumina(&w)
        let e = addFoe(&w, dx: 400)
        w.s.units[k].attackTargetID = w.id(e)
        // 攻撃を続けて 2.5 秒、その後やめる。最後の命中（持続が 4 秒に戻った tick）から 4 秒で全段が消える（攻撃速度のステータスも）
        var lastRefresh = w.s.tick
        var previousTimer = w.kit(k).luminaStackTimer
        var sawStillStacked = false
        var sawCleared = false
        var stoppedAt = -1
        for step in 0..<(30 * 12) {
            if step == 75 {
                let before = w.kit(k).luminaStacks
                XCTAssertGreaterThanOrEqual(before, 2)
                XCTAssertLessThan(before, 5)
                let badge = HeroKits.badge(w.s.units[k].hero!, slot: .passive)
                XCTAssertEqual(badge?.kind, .stacks)
                XCTAssertEqual(badge?.value, before)
                XCTAssertEqual(badge?.maxValue, 5)
                w.s.units[k].attackTargetID = nil
                stoppedAt = w.s.tick
            }
            w.tick()
            let timer = w.kit(k).luminaStackTimer
            if timer > previousTimer { lastRefresh = w.s.tick }
            previousTimer = timer
            guard stoppedAt >= 0 else { continue }
            let age = Double(w.s.tick - lastRefresh) * Balance.dt
            if age < 3.8 {
                XCTAssertGreaterThan(w.kit(k).luminaStacks, 0, "age \(age)")
                XCTAssertTrue(w.s.units[k].has(.attackSpeedBoost))
                sawStillStacked = sawStillStacked || age > 3.0
            } else if age > 4.2 {
                XCTAssertEqual(w.kit(k).luminaStacks, 0, "age \(age)")
                XCTAssertFalse(w.s.units[k].has(.attackSpeedBoost))
                sawCleared = true
            }
        }
        XCTAssertTrue(sawStillStacked)
        XCTAssertTrue(sawCleared)
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive)?.value, 0)
        // 命中のたびに 4 秒に戻る
        w.s.units[k].attackTargetID = w.id(e)
        w.run(seconds: 1.5)
        let st = w.s.units[k].statuses.first { $0.tag == T.stackTag }
        XCTAssertNotNil(st)
        XCTAssertGreaterThan(w.kit(k).luminaStackTimer, 2.5)
    }

    func testStackStatusStaysSingleWhileHitsKeepComing() {
        // 段のステータスは 1 つだけ（毎命中で積み増さない）
        var w = SkillWorld()
        let k = addLumina(&w)
        let e = addFoe(&w, dx: 400)
        w.s.units[k].attackTargetID = w.id(e)
        w.run(seconds: 6)
        XCTAssertEqual(w.s.units[k].statuses.filter { $0.kind == .attackSpeedBoost && $0.tag == T.stackTag }.count, 1)
    }

    // MARK: - S1 月矢の連弾

    func testMoonArrowAddsBonusToTheMainArrowAndSplitsToTwoNearestEnemies() throws {
        var w = SkillWorld()
        let k = addLumina(&w)
        let main = addFoe(&w, dx: 400)
        let a = addFoe(&w, dx: 400, dy: 200, hero: "H004")      // 主矢の対象から 200
        let b = addFoe(&w, dx: 400, dy: -250, hero: "H005")     // 250
        let c = addFoe(&w, dx: 400, dy: 280, hero: "H006")      // 280（3 番目に近い: 副矢は 2 本だけ）
        let tooFar = addFoe(&w, dx: 400, dy: -330 - 300, hero: "H001")   // 範囲の外
        let n = w.numbers(k, .skill1)
        w.tick()
        XCTAssertTrue(w.cast(k, .skill1))
        XCTAssertEqual(w.castEvents.last?.slot, .skill1)
        XCTAssertEqual(w.castEvents.last?.archetype, .selfAoE)
        XCTAssertEqual(w.castEvents.last?.shape, .selfRing)
        XCTAssertEqual(w.castEvents.last?.duration, Kit_H025.s1Duration(rank: 1))
        XCTAssertEqual(w.kit(k).luminaMoonArrow, Kit_H025.s1Duration(rank: 1), accuracy: 1e-9)
        XCTAssertEqual(w.kit(k).luminaArrowBonus, n.damage, accuracy: 1e-9)
        w.s.units[k].attackTargetID = w.id(main)
        w.run(seconds: 1.0)
        let attack = w.s.units[k].stats.attack
        let mainHit = try XCTUnwrap(events(w, to: main, .basicAttack).first)
        XCTAssertEqual(mainHit.amount, w.mitigated(attack + n.damage, .physical, on: main), accuracy: 0.01,
                       "主矢 = 通常攻撃 + 追加ダメージ")
        let splashRaw = (attack + n.damage) * T.splashRatio
        for e in [a, b] {
            let hit = try XCTUnwrap(events(w, to: e, .basicAttack).first, "近い 2 体")
            XCTAssertEqual(hit.amount, w.mitigated(splashRaw, .physical, on: e), accuracy: 0.01, "主矢の 30%")
        }
        XCTAssertTrue(events(w, to: c, .basicAttack).isEmpty, "3 番目は撃たれない")
        XCTAssertTrue(events(w, to: tooFar, .basicAttack).isEmpty)
        // 主矢の対象には副矢は当たらない（1 回の通常攻撃で主矢 1 本）
        XCTAssertEqual(events(w, to: main, .basicAttack).count, 1)
        XCTAssertEqual(w.kit(k).luminaSplashArrows, 2)
        // 副矢は段を積まない（主矢の命中 1 回 = 1 段）
        XCTAssertEqual(w.kit(k).luminaStacks, 1)
    }

    func testMoonArrowCastEventCarriesTheRanksBuffDuration() {
        // 発動の合図（SkillCastEvent.duration）はランクの持続（4 → 9 秒）。App の演出はこれで効果の長さを決める
        for rank in 1...Balance.basicSkillMaxRank {
            var w = SkillWorld()
            let k = addLumina(&w, ranks: [rank, 1, 1], level: 12)
            w.tick()
            XCTAssertTrue(w.cast(k, .skill1), "r\(rank)")
            let cast = w.castEvents.last
            XCTAssertEqual(cast?.slot, .skill1)
            XCTAssertEqual(cast?.duration ?? 0, Kit_H025.s1Duration(rank: rank), accuracy: 1e-9, "r\(rank)")
            XCTAssertEqual(w.kit(k).luminaMoonArrow, Kit_H025.s1Duration(rank: rank), accuracy: 1e-9, "r\(rank)")
        }
        XCTAssertEqual(Kit_H025.s1Duration(rank: Balance.basicSkillMaxRank), 9, accuracy: 1e-9)
        // 奥義も持続を渡す（隠密 2 秒）
        var w = SkillWorld()
        let k = addLumina(&w, ranks: [1, 1, 1], level: 12)
        w.tick()
        XCTAssertTrue(w.cast(k, .ultimate))
        XCTAssertEqual(w.castEvents.last?.slot, .ultimate)
        XCTAssertEqual(w.castEvents.last?.duration ?? 0, T.ultDuration, accuracy: 1e-9)
    }

    func testMoonArrowSplashNeedsOthersInRangeAndSparesStructures() throws {
        var w = SkillWorld()
        let k = addLumina(&w)
        let main = addFoe(&w, dx: 600)
        // 主矢の対象から 280 だが、術者の射程（550 + 半径 + 余裕）の外
        let far = addFoe(&w, dx: 880, hero: "H004")
        let alone = addMinion(&w, dx: 30, dy: 900)    // 主矢から遠い
        w.tick()
        XCTAssertTrue(w.cast(k, .skill1))
        w.s.units[k].attackTargetID = w.id(main)
        w.run(seconds: 1.2)
        XCTAssertFalse(events(w, to: main, .basicAttack).isEmpty)
        XCTAssertTrue(events(w, to: far, .basicAttack).isEmpty, "射程の外へは飛ばない")
        XCTAssertTrue(events(w, to: alone, .basicAttack).isEmpty)
        XCTAssertEqual(w.kit(k).luminaSplashArrows, 0)

        // ミニオンにも副矢は飛ぶ
        var w2 = SkillWorld()
        let k2 = addLumina(&w2)
        let h = addFoe(&w2, dx: 400)
        let m1 = w2.addMinion(team: .red, at: skillArena + Vec2(450, 120))
        let m2 = w2.addMinion(team: .red, at: skillArena + Vec2(500, -100))
        XCTAssertTrue(w2.cast(k2, .skill1))
        w2.s.units[k2].attackTargetID = w2.id(h)
        w2.run(seconds: 1)
        XCTAssertFalse(events(w2, to: m1, .basicAttack).isEmpty)
        XCTAssertFalse(events(w2, to: m2, .basicAttack).isEmpty)

        // 主矢の対象が構造物なら何もしない（追加ダメージも副矢も）
        var w3 = SkillWorld()
        let k3 = addLumina(&w3)
        let tower = w3.addTower(team: .red, at: skillArena + Vec2(300, 0))
        _ = w3.addMinion(team: .red, at: skillArena + Vec2(330, 100))
        XCTAssertTrue(w3.cast(k3, .skill1))
        let kit = HeroKits.kit(of: w3.s.units[k3])!
        var plan = BasicAttackPlan(payload: HitPayload(damage: 100, damageType: .physical, source: .basicAttack), ranged: true)
        kit.shapeBasicAttack(&w3.s, w3.ctx, attacker: k3, target: tower, plan: &plan)
        XCTAssertEqual(plan.payload.damage, 100)
        XCTAssertEqual(w3.s.projectiles.count, 0)
    }

    func testMoonArrowSplashFollowsTheMainArrowIncludingCrit() throws {
        var w = SkillWorld()
        let k = addLumina(&w)
        let main = addFoe(&w, dx: 400)
        let a = addFoe(&w, dx: 400, dy: 200, hero: "H004")
        XCTAssertTrue(w.cast(k, .skill1))
        let bonus = w.kit(k).luminaArrowBonus
        let kit = try XCTUnwrap(HeroKits.kit(of: w.s.units[k]))
        // 主矢が会心（ダメージ 1000）のとき、追加ダメージを足した値の 30% が副矢になり、会心の表示も引き継ぐ
        var plan = BasicAttackPlan(payload: HitPayload(damage: 1000, damageType: .physical, source: .basicAttack,
                                                       isCrit: true, appliesOnHit: true), ranged: true)
        kit.shapeBasicAttack(&w.s, w.ctx, attacker: k, target: main, plan: &plan)
        XCTAssertEqual(plan.payload.damage, 1000 + bonus, accuracy: 1e-9)
        XCTAssertTrue(plan.payload.appliesOnHit)
        w.run(seconds: 1)
        let hit = try XCTUnwrap(events(w, to: a, .basicAttack).first)
        XCTAssertTrue(hit.isCrit)
        XCTAssertEqual(hit.amount, w.mitigated((1000 + bonus) * 0.3, .physical, on: a), accuracy: 0.01)
    }

    func testMoonArrowCannotBeRecastWhileActiveAndCooldownStartsOnCast() {
        var w = SkillWorld()
        let k = addLumina(&w)
        let n = w.numbers(k, .skill1)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .skill1))
        XCTAssertTrue(w.cast(k, .skill1))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), n.cooldown, accuracy: 1e-9)
        XCTAssertEqual(n.cooldown, 11, accuracy: 1e-9)
        let badge = HeroKits.badge(w.s.units[k].hero!, slot: .skill1)
        XCTAssertEqual(badge?.kind, .timer)
        XCTAssertEqual(badge?.total, Kit_H025.s1Duration(rank: 1))
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: k, slot: .skill1))
        w.run(seconds: 3.9)
        XCTAssertGreaterThan(w.kit(k).luminaMoonArrow, 0)
        XCTAssertFalse(w.cast(k, .skill1), "効果中は再使用できない")
        w.run(seconds: 0.2)
        XCTAssertEqual(w.kit(k).luminaMoonArrow, 0, accuracy: 1e-9)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .skill1))
        XCTAssertFalse(w.cast(k, .skill1), "効果が終わってもクールダウン中（残り約 6.9 秒）")
        w.run(seconds: 7.0)
        XCTAssertTrue(w.cast(k, .skill1))

        // 効果が切れたら通常攻撃は元に戻る
        var w2 = SkillWorld()
        let k2 = addLumina(&w2)
        let e = addFoe(&w2, dx: 400)
        XCTAssertTrue(w2.cast(k2, .skill1))
        w2.run(seconds: 4.2)
        w2.log.removeAll()
        w2.s.units[k2].attackTargetID = w2.id(e)
        w2.run(seconds: 0.8)
        let hit = events(w2, to: e, .basicAttack).first
        XCTAssertEqual(hit?.amount ?? 0, w2.mitigated(w2.s.units[k2].stats.attack, .physical, on: e), accuracy: 0.01)
    }

    // MARK: - S2 月蝕の矢

    func testEclipseLandsAfterDelayDamagesAndRootsButTheTargetCanStillAct() throws {
        var w = SkillWorld()
        let k = addLumina(&w)
        let hit = addFoe(&w, dx: 500, dy: 60)
        let edge = addFoe(&w, dx: 500, dy: 200, hero: "H004")     // 円の縁（170 + 半径 55 の内側）
        let out = addFoe(&w, dx: 500, dy: 260, hero: "H005")      // 円の外
        let n = w.numbers(k, .skill2)
        let target = skillArena + Vec2(500, 0)
        XCTAssertTrue(w.cast(k, .skill2, .point(target)))
        let cast = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(cast.archetype, .groundAoE)
        XCTAssertEqual(cast.shape, .circleAtPoint)
        XCTAssertEqual(cast.duration, T.s2Delay, accuracy: 1e-9)
        XCTAssertEqual(cast.count, 6)
        XCTAssertEqual(cast.halfAngle, Double.pi * 5 / 6, accuracy: 1e-9)
        XCTAssertEqual(cast.radius, T.s2Radius)
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k, code: T.Code.split), 1)
        w.run(seconds: 0.25)
        XCTAssertTrue(w.damageEvents.isEmpty, "着弾までは当たらない")
        XCTAssertTrue(w.s.projectiles.isEmpty)
        w.run(seconds: 0.25)
        for e in [hit, edge] {
            let evs = events(w, to: e, .skill(.skill2)).filter { abs($0.amount - w.mitigated(n.damage, .physical, on: e)) < 0.01 }
            XCTAssertEqual(evs.count, 1, "着弾の範囲に 1 度")
            let root = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .root })
            XCTAssertLessThanOrEqual(root.remaining, T.s2Root)
            XCTAssertGreaterThan(root.remaining, T.s2Root - 0.3)
            XCTAssertFalse(w.s.units[e].canMove, "移動不能")
            XCTAssertTrue(w.s.units[e].canAct, "攻撃とスキルは可能")
            XCTAssertTrue(w.s.units[e].canCast)
        }
        XCTAssertFalse(w.s.units[out].has(.root))
        // 1.2 秒で解ける
        w.run(seconds: 1.2)
        XCTAssertTrue(w.s.units[hit].canMove)
        XCTAssertFalse(w.s.units[hit].has(.root))
    }

    func testEclipseScattersSixArrowsEvenlyFromTheLandingPoint() throws {
        var w = SkillWorld()
        let k = addLumina(&w)
        let target = skillArena + Vec2(500, 0)
        XCTAssertTrue(w.cast(k, .skill2, .point(target)))
        var fired = false
        for _ in 0..<60 where !fired {
            w.tick()
            fired = Kit.scheduledCount(w.s, caster: k) == 0
        }
        XCTAssertTrue(fired)
        let arrows = w.s.projectiles.filter { $0.visual == skill(.skill2).effectID && !$0.done }
        XCTAssertEqual(arrows.count, 6)
        var angles: [Double] = []
        for p in arrows {
            XCTAssertEqual(p.pos.distance(to: target), 0, accuracy: 1e-6, "着弾点から")
            XCTAssertFalse(p.pierce, "最初に当たった敵まで")
            XCTAssertEqual(p.width, T.s2ArrowWidth)
            XCTAssertEqual(p.speed, T.s2ArrowSpeed)
            guard case .linear(let dir, let maxDistance) = p.motion else { return XCTFail("直線弾") }
            XCTAssertEqual(maxDistance, T.s2ArrowRange)
            XCTAssertEqual(dir.length, 1, accuracy: 1e-9)
            angles.append(degrees(dir))
        }
        // 発射方向（東）を中心に 60° おき: -150, -90, -30, 30, 90, 150
        for (got, want) in zip(angles, [-150.0, -90, -30, 30, 90, 150]) {
            XCTAssertEqual(got, want, accuracy: 1e-6)
        }
        // 撃つ向きが変われば散る向きもそれに従う（北向き = 90° 回転）
        var w2 = SkillWorld()
        let k2 = addLumina(&w2)
        XCTAssertTrue(w2.cast(k2, .skill2, .point(skillArena + Vec2(0, 500))))
        w2.run(seconds: 0.6)
        let north = w2.s.projectiles.filter { $0.visual == skill(.skill2).effectID }
        guard case .linear(let d0, _) = north[0].motion else { return XCTFail() }
        XCTAssertEqual(degrees(d0), -60, accuracy: 1e-6, "北 (90°) の -150°")
    }

    func testEachMinorArrowHitsOnlyTheFirstEnemyAndSlows() throws {
        var w = SkillWorld()
        let k = addLumina(&w)
        let n = w.numbers(k, .skill2)
        let minor = Kit_H025.minorDamage(rank: 1, stats: w.s.units[k].stats)
        let center = Vec2(500, 0)
        // +30° の矢の上: 近い敵と遠い敵（円の外。近い方だけに当たる）
        let ray = Vec2.fromAngle(30 * Double.pi / 180)
        let near = addFoe(&w, dx: center.x + ray.x * 300, dy: ray.y * 300)
        let far = addFoe(&w, dx: center.x + ray.x * 390, dy: ray.y * 390, hero: "H004")
        XCTAssertTrue(w.cast(k, .skill2, .point(skillArena + center)))
        w.run(seconds: 1.2)
        let nearEvs = events(w, to: near, .skill(.skill2))
        XCTAssertEqual(nearEvs.count, 1, "矢は 1 本だけ")
        XCTAssertEqual(nearEvs[0].amount, w.mitigated(minor, .physical, on: near), accuracy: 0.01)
        XCTAssertTrue(events(w, to: far, .skill(.skill2)).isEmpty, "最初の敵で止まる")
        XCTAssertEqual(slowMagnitude(w, near) ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertFalse(w.s.units[near].has(.root), "円の外は移動不能にならない")
        // スロウは 2 秒
        let slow = try XCTUnwrap(w.s.units[near].statuses.first { $0.tag == T.slowTag })
        XCTAssertLessThanOrEqual(slow.remaining, 2.0)
        XCTAssertGreaterThan(slow.remaining, 0.4)
        XCTAssertEqual(w.s.units[near].stats.moveSpeed,
                       HeroGrowth.baseStats(def: MasterData.shared.hero("H003")!, level: 1).moveSpeed * 0.7, accuracy: 1.0)
        w.run(seconds: 2)
        XCTAssertNil(slowMagnitude(w, near))
    }

    func testTargetInsideTheBlastTakesTheBlastAndTheArrowsThatPassThroughIt() throws {
        // 着弾点の 100 東に立つ敵: 円の中（移動不能）+ ±30° の 2 本が当たる（90° の矢は幅の外）
        var w = SkillWorld()
        let k = addLumina(&w)
        let n = w.numbers(k, .skill2)
        let minor = Kit_H025.minorDamage(rank: 1, stats: w.s.units[k].stats)
        let e = addFoe(&w, dx: 600)
        XCTAssertTrue(w.cast(k, .skill2, .point(skillArena + Vec2(500, 0))))
        w.run(seconds: 1.2)
        let evs = events(w, to: e, .skill(.skill2)).map(\.amount)
        let blast = w.mitigated(n.damage, .physical, on: e)
        let arrow = w.mitigated(minor, .physical, on: e)
        XCTAssertEqual(evs.count, 3, "\(evs)")
        XCTAssertEqual(evs.filter { abs($0 - blast) < 0.01 }.count, 1)
        XCTAssertEqual(evs.filter { abs($0 - arrow) < 0.01 }.count, 2)
        XCTAssertNotNil(slowMagnitude(w, e))
        XCTAssertTrue(w.s.units[e].has(.root), "円の中は移動不能（1.2 秒）")
    }

    func testEclipseEdgeCases() throws {
        // 射程 650 に丸める
        var w = SkillWorld()
        let k = addLumina(&w)
        XCTAssertTrue(w.cast(k, .skill2, .point(skillArena + Vec2(1500, 0))))
        XCTAssertEqual(w.castEvents.last?.target.x ?? 0, skillArena.x + 650, accuracy: 1e-6)

        // 味方・自分には当たらない
        var w2 = SkillWorld()
        let k2 = addLumina(&w2)
        let ally = w2.addHero("H001", team: .blue, at: skillArena + Vec2(450, 0), ranks: [1, 1, 1])
        XCTAssertTrue(w2.cast(k2, .skill2, .point(skillArena + Vec2(500, 0))))
        w2.run(seconds: 1.2)
        XCTAssertEqual(w2.damage(to: ally), 0)
        XCTAssertEqual(w2.damage(to: k2), 0)
        XCTAssertFalse(w2.s.units[ally].has(.slow))

        // 術者がスタンしても散る（矢はもう放たれている）。CC 無効の敵は移動不能にならないがダメージは受ける
        var w3 = SkillWorld()
        let k3 = addLumina(&w3)
        let immune = addFoe(&w3, dx: 500)
        w3.s.units[immune].statuses.append(StatusEffect(kind: .ccImmune, duration: 5))
        XCTAssertTrue(w3.cast(k3, .skill2, .point(skillArena + Vec2(500, 0))))
        w3.tick(3)
        CombatSystem.addStatus(&w3.s, targetIndex: k3, StatusEffect(kind: .stun, duration: 0.6))
        w3.run(seconds: 0.5)
        XCTAssertEqual(Kit.scheduledCount(w3.s, caster: k3), 0, "非中断のタイマーは発火済み")
        w3.run(seconds: 1)
        XCTAssertFalse(w3.s.units[immune].has(.root))
        XCTAssertGreaterThan(w3.damage(to: immune, from: .skill(.skill2)), 0)
        XCTAssertNil(slowMagnitude(w3, immune), "CC 無効にはスロウも入らない")

        // 死亡すると散らない（状態ごと消える）。着弾は止まらない
        var w4 = SkillWorld()
        let k4 = addLumina(&w4)
        let e = addFoe(&w4, dx: 500)
        XCTAssertTrue(w4.cast(k4, .skill2, .point(skillArena + Vec2(500, 0))))
        w4.tick(3)
        CombatSystem.applyDamage(&w4.s, w4.ctx, sourceID: w4.id(e), targetIndex: k4, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w4.s, w4.ctx)
        XCTAssertTrue(w4.s.units[k4].hero!.isDead)
        XCTAssertEqual(Kit.scheduledCount(w4.s, caster: k4), 0)
        w4.run(seconds: 1.2)
        XCTAssertTrue(w4.s.projectiles.filter { $0.visual == skill(.skill2).effectID }.isEmpty, "小さな矢は出ない")
    }

    // MARK: - 奥義 隠れ月光

    func testHiddenMoonlightCleansesConcealsAndSpeedsUp() throws {
        var w = SkillWorld()
        let k = addLumina(&w)
        w.tick()
        let baseSpeed = w.s.units[k].stats.moveSpeed
        // あらゆる弱体
        for st in [StatusEffect(kind: .slow, duration: 5, magnitude: 0.4),
                   StatusEffect(kind: .root, duration: 5),
                   StatusEffect(kind: .silence, duration: 5),
                   StatusEffect(kind: .burn, duration: 5, magnitude: 10),
                   StatusEffect(kind: .healReduction, duration: 5, magnitude: 0.4),
                   StatusEffect(kind: .armorShred, duration: 5, magnitude: 0.3),
                   StatusEffect(kind: .damageDealtReduction, duration: 5, magnitude: 0.2)] {
            w.s.units[k].statuses.append(st)
        }
        w.tick()
        // 沈黙中は撃てない → 先に解いてもらう代わりに沈黙以外を確認
        XCTAssertFalse(w.cast(k, .ultimate), "沈黙中は撃てない")
        w.s.units[k].statuses.removeAll { $0.kind == .silence }
        XCTAssertTrue(w.cast(k, .ultimate))
        let cast = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(cast.archetype, .selfAoE)
        XCTAssertEqual(cast.shape, .selfRing)
        XCTAssertEqual(cast.duration, T.ultDuration)
        for kind in [StatusKind.slow, .root, .silence, .burn, .healReduction, .armorShred, .damageDealtReduction] {
            XCTAssertFalse(w.s.units[k].has(kind), "\(kind)")
        }
        XCTAssertTrue(w.s.units[k].has(.stealth))
        XCTAssertTrue(w.kit(k).luminaHidden)
        XCTAssertEqual(w.kit(k).luminaHiddenRemaining, 2, accuracy: 1e-9)
        w.tick()
        XCTAssertEqual(w.s.units[k].stats.moveSpeed, baseSpeed * 1.65, accuracy: 1e-6)
        let badge = HeroKits.badge(w.s.units[k].hero!, slot: .ultimate)
        XCTAssertEqual(badge?.kind, .timer)
        XCTAssertEqual(badge?.total, 2)
        // 隠密中は攻撃されない（HP も減らない）が、無敵ではない
        XCTAssertFalse(w.s.units[k].has(.invulnerable))
    }

    func testHiddenMoonlightEndsByTimeAndGrantsFullStacks() {
        var w = SkillWorld()
        let k = addLumina(&w)
        w.tick()
        let baseSpeed = w.s.units[k].stats.moveSpeed
        XCTAssertTrue(w.cast(k, .ultimate))
        w.run(seconds: 1.8)
        XCTAssertTrue(w.s.units[k].has(.stealth))
        XCTAssertEqual(w.kit(k).luminaStacks, 0)
        w.run(seconds: 0.4)
        XCTAssertFalse(w.s.units[k].has(.stealth))
        XCTAssertFalse(w.s.units[k].has(.speedBoost), "加速も一緒に終わる")
        XCTAssertFalse(w.kit(k).luminaHidden)
        XCTAssertEqual(w.kit(k).luminaStacks, 5, "解けた瞬間に最大の段")
        let st = w.s.units[k].statuses.first { $0.kind == .attackSpeedBoost && $0.tag == T.stackTag }
        XCTAssertEqual(st?.magnitude ?? 0, T.attackSpeedPerStack * Double(T.maxStacks), accuracy: 1e-9)
        w.tick()
        XCTAssertEqual(w.s.units[k].stats.moveSpeed, baseSpeed, accuracy: 1e-6)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .ultimate))
        // 最大の段も 4 秒で切れる
        w.run(seconds: 4.2)
        XCTAssertEqual(w.kit(k).luminaStacks, 0)
        XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(.ultimate), 0)
        XCTAssertFalse(w.cast(k, .ultimate), "CD 中")
    }

    func testBasicAttackEndsStealthAndTheOpeningAttackCarriesTheShadow() throws {
        var w = SkillWorld()
        let k = addLumina(&w)
        let e = addFoe(&w, dx: 400)
        XCTAssertTrue(w.cast(k, .ultimate))
        w.run(seconds: 0.5)
        XCTAssertTrue(w.s.units[k].has(.stealth), "攻撃するまでは隠れている")
        w.log.removeAll()
        w.s.units[k].attackTargetID = w.id(e)
        w.run(seconds: 0.8)
        // 攻撃の発射で隠密が解け、その攻撃から最大の段（月影つき）
        XCTAssertFalse(w.s.units[k].has(.stealth))
        XCTAssertFalse(w.s.units[k].has(.speedBoost))
        XCTAssertFalse(w.kit(k).luminaHidden)
        let attack = w.s.units[k].stats.attack
        let evs = events(w, to: e, .basicAttack)
        XCTAssertEqual(evs.count, 2, "主矢 + 月影")
        XCTAssertTrue(evs.contains { abs($0.amount - w.mitigated(attack, .physical, on: e)) < 0.01 })
        XCTAssertTrue(evs.contains { abs($0.amount - w.mitigated(Kit_H025.shadowDamage(attack: attack), .physical, on: e)) < 0.01 })
        XCTAssertEqual(w.kit(k).luminaShadows, 1)
        XCTAssertGreaterThanOrEqual(w.kit(k).luminaStacks, 5)
    }

    func testNonUltimateSkillCastEndsStealthAndMoonArrowStartsWithFullStacks() {
        for slot in [SkillSlot.skill1, .skill2] {
            var w = SkillWorld()
            let k = addLumina(&w)
            _ = addFoe(&w, dx: 400)
            XCTAssertTrue(w.cast(k, .ultimate))
            w.run(seconds: 0.3)
            XCTAssertTrue(w.s.units[k].has(.stealth))
            XCTAssertTrue(w.cast(k, slot, .point(skillArena + Vec2(400, 0))), "\(slot)")
            XCTAssertFalse(w.s.units[k].has(.stealth), "\(slot)")
            XCTAssertFalse(w.kit(k).luminaHidden)
            XCTAssertEqual(w.kit(k).luminaStacks, 5, "\(slot)")
            XCTAssertFalse(w.s.units[k].has(.speedBoost), "\(slot)")
        }
        // 奥義を撃ち直す手段は無い（CD）ので「奥義の発動では解けない」は、発動の瞬間に隠密が付くことで確かめる
        var w = SkillWorld()
        let k = addLumina(&w)
        XCTAssertTrue(w.cast(k, .ultimate))
        XCTAssertTrue(w.s.units[k].has(.stealth))
    }

    func testStealthHidesFromFarEnemiesUntilTheyGetCloseOrAttackBreaksIt() {
        var w = SkillWorld()
        w.autoReveal = false
        let k = addLumina(&w)
        let seer = w.addHero("H003", team: .red, at: skillArena + Vec2(600, 0), ranks: [1, 1, 1])
        w.s.units[seer].hp = 1e8
        w.tick(Balance.visionUpdateEveryTicks * 2)
        XCTAssertTrue(w.s.isVisible(k, to: .red), "隠れる前は見える")
        XCTAssertTrue(w.cast(k, .ultimate))
        w.tick(Balance.visionUpdateEveryTicks * 2)
        XCTAssertFalse(w.s.isVisible(k, to: .red), "遠くの敵からは見えない")
        w.s.units[seer].pos = skillArena + Vec2(200, 0)
        w.tick(Balance.visionUpdateEveryTicks * 2)
        XCTAssertTrue(w.s.isVisible(k, to: .red), "近づかれれば見える（標準の看破）")
        // 攻撃すると隠密が解ける
        w.s.units[seer].pos = skillArena + Vec2(600, 0)
        w.tick(Balance.visionUpdateEveryTicks * 2)
        XCTAssertFalse(w.s.isVisible(k, to: .red))
        w.s.units[k].attackTargetID = w.id(seer)
        w.run(seconds: 1.0)
        XCTAssertTrue(w.s.isVisible(k, to: .red))
    }

    // MARK: - 端の場合

    func testNoTargetCastsStillSpendAndNothingBreaks() {
        var w = SkillWorld()
        let k = addLumina(&w)
        for slot in SkillSlot.actives {
            let before = w.s.units[k].resource
            XCTAssertTrue(w.cast(k, slot, .none), "\(slot)")
            XCTAssertLessThan(w.s.units[k].resource, before)
            XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(slot), 0)
        }
        w.run(seconds: 3)
        XCTAssertTrue(w.damageEvents.isEmpty)
        XCTAssertEqual(w.s.units[k].hp, w.s.units[k].stats.maxHP)
    }

    func testCostFollowsTheOfficialTableAndCCBlocksCasts() {
        var w = SkillWorld()
        let k = addLumina(&w)
        for (slot, mp) in [(SkillSlot.skill1, 60.0), (.skill2, 80), (.ultimate, 120)] {
            let n = w.numbers(k, slot)
            XCTAssertEqual(n.cost, mp, "公式のマナ（ランク 1）")
            let before = w.s.units[k].resource
            XCTAssertTrue(w.cast(k, slot, .point(skillArena + Vec2(400, 0))))
            XCTAssertEqual(before - w.s.units[k].resource, mp, accuracy: 1e-9, "\(slot)")
            XCTAssertEqual(w.s.units[k].hero!.cooldown(slot), n.cooldown, accuracy: 1e-9)
            XCTAssertFalse(w.cast(k, slot, .point(skillArena + Vec2(400, 0))), "CD 中")
        }
        // スタン・沈黙中は撃てない
        var w2 = SkillWorld()
        let k2 = addLumina(&w2)
        CombatSystem.addStatus(&w2.s, targetIndex: k2, StatusEffect(kind: .stun, duration: 0.5))
        for slot in SkillSlot.actives { XCTAssertFalse(w2.cast(k2, slot, .none), "\(slot)") }
        w2.run(seconds: 0.6)
        CombatSystem.addStatus(&w2.s, targetIndex: k2, StatusEffect(kind: .silence, duration: 0.5))
        for slot in SkillSlot.actives { XCTAssertFalse(w2.cast(k2, slot, .none), "\(slot)") }
        XCTAssertTrue(w2.damageEvents.isEmpty)
    }

    func testStunDoesNotEndHiddenMoonlightOrMoonArrow() {
        var w = SkillWorld()
        let k = addLumina(&w)
        XCTAssertTrue(w.cast(k, .ultimate))
        w.tick(5)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 0.4))
        w.tick(5)
        XCTAssertTrue(w.s.units[k].has(.stealth))
        XCTAssertTrue(w.kit(k).luminaHidden)
        w.run(seconds: 0.2)
        XCTAssertTrue(w.s.units[k].has(.stealth))
    }

    func testPracticeHasNoCooldownsOrCostsButMoonArrowStillCannotStack() {
        var p = SkillWorld(noCooldowns: true)
        let pk = addLumina(&p)
        let e = addFoe(&p, dx: 400)
        for slot in SkillSlot.actives {
            XCTAssertTrue(p.cast(pk, slot, .point(skillArena + Vec2(400, 0))), "\(slot)")
            XCTAssertEqual(p.s.units[pk].hero!.cooldown(slot), 0, "練習場は CD なし")
        }
        XCTAssertEqual(p.s.units[pk].resource, p.s.units[pk].stats.maxResource, accuracy: 1e-9, "コストも無し")
        XCTAssertFalse(p.cast(pk, .skill1), "月矢は効果中は撃ち直せない（練習場でも）")
        p.run(seconds: 4.2)
        XCTAssertTrue(p.cast(pk, .skill1))
        XCTAssertTrue(p.cast(pk, .ultimate))
        p.run(seconds: 1.0)
        XCTAssertGreaterThan(p.damage(to: e, from: .skill(.skill2)), 0)
    }

    func testDeathResetsEverythingAndRespawnStartsClean() {
        var w = SkillWorld()
        let k = addLumina(&w)
        let e = addFoe(&w, dx: 400)
        XCTAssertTrue(w.cast(k, .skill1))
        w.s.units[k].attackTargetID = w.id(e)
        w.run(seconds: 2)
        XCTAssertGreaterThan(w.kit(k).luminaStacks, 0)
        XCTAssertTrue(w.cast(k, .ultimate))
        XCTAssertTrue(w.kit(k).luminaHidden)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        let kit = w.kit(k)
        XCTAssertEqual(kit.luminaStacks, 0)
        XCTAssertFalse(kit.luminaHidden)
        XCTAssertEqual(kit.luminaMoonArrow, 0)
        XCTAssertEqual(kit.luminaArrowBonus, 0)
        XCTAssertEqual(kit.luminaHiddenRemaining, 0)
        XCTAssertEqual(kit.luminaShadows, 0)
        XCTAssertTrue(w.s.units[k].statuses.isEmpty)
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: k, slot: .skill2))
        w.run(seconds: 2)
        XCTAssertEqual(w.kit(k).luminaStacks, 0)
        XCTAssertFalse(w.kit(k).luminaHidden)
    }

    func testReplacementOfRoleCritPassiveAndAdjacentHeroesStayGeneric() {
        // 同じレンジャーの H003 はキットなし: 4 発目ごとに確定会心
        var w = SkillWorld()
        let other = w.addHero("H003", team: .blue, at: skillArena + Vec2(0, 900), ranks: [1, 1, 1], facing: 0)
        XCTAssertNil(w.s.units[other].hero?.kit)
        XCTAssertFalse(HeroKits.hasKit("H003"))
        let k = addLumina(&w)
        XCTAssertNotNil(w.s.units[k].hero?.kit)
        let e = addFoe(&w, dx: 400)
        w.s.units[k].attackTargetID = w.id(e)
        w.run(seconds: 8)
        XCTAssertTrue(events(w, to: e, .basicAttack).allSatisfy { !$0.isCrit })
    }

    // MARK: - 決定性

    private func script(_ w: inout SkillWorld, k: Int, step: Int) {
        switch step {
        case 0: w.cast(k, .ultimate)
        case 1: w.cast(k, .skill2, .point(skillArena + Vec2(500, 0)))
        case 2: w.cast(k, .skill1)
        case 3: w.s.units[k].attackTargetID = w.s.units.first { $0.team == .red && $0.kind == .hero }?.id
        default: break
        }
    }

    private func makeScriptWorld() -> (SkillWorld, Int) {
        var w = SkillWorld()
        let k = addLumina(&w, ranks: [2, 2, 2])
        w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        w.addDummyEnemy(at: skillArena + Vec2(470, 190), hero: "H004")
        w.addMinion(team: .red, at: skillArena + Vec2(540, -120))
        return (w, k)
    }

    private func runScript(_ w: inout SkillWorld, k: Int, from: Int, to: Int) {
        for step in from..<to {
            script(&w, k: k, step: step)
            w.run(seconds: 0.45)
        }
    }

    func testScriptedRunIsDeterministic() {
        var (a, ka) = makeScriptWorld()
        var (b, kb) = makeScriptWorld()
        runScript(&a, k: ka, from: 0, to: 14)
        runScript(&b, k: kb, from: 0, to: 14)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(a.s.units, b.s.units)
        XCTAssertEqual(a.log, b.log)
        XCTAssertGreaterThan(a.kit(ka).luminaShadows, 0, "台本が月影まで通っている")
        XCTAssertGreaterThan(a.kit(ka).luminaSplashArrows, 0, "台本が副矢まで通っている")
        XCTAssertFalse(a.damageEvents.filter { $0.source == .skill(.skill2) }.isEmpty)
    }

    func testJSONRoundTripMidUltimateAndMidEclipseResumesIdentically() throws {
        var (reference, kr) = makeScriptWorld()
        runScript(&reference, k: kr, from: 0, to: 14)

        // 途中（隠密と加速が生きている）/ 途中（月蝕の矢が着弾待ち）/ 途中（月矢と段が生きている）で保存して再開する
        for (stopStep, extraTicks) in [(0, 4), (1, 4), (2, 6)] {
            var (b, kb) = makeScriptWorld()
            runScript(&b, k: kb, from: 0, to: stopStep)
            script(&b, k: kb, step: stopStep)
            b.tick(extraTicks)
            switch stopStep {
            case 0: XCTAssertTrue(b.kit(kb).luminaHidden)
            case 1: XCTAssertEqual(Kit.scheduledCount(b.s, caster: kb, code: T.Code.split), 1, "着弾待ちの矢を保存する")
            default: XCTAssertGreaterThan(b.kit(kb).luminaMoonArrow, 0)
            }
            let data = try JSONEncoder().encode(b.s)
            var resumed = b
            resumed.s = try JSONDecoder().decode(SimState.self, from: data)
            XCTAssertEqual(resumed.s.units, b.s.units)
            XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
            b.run(seconds: 0.45 - Double(extraTicks) * Balance.dt)
            resumed.run(seconds: 0.45 - Double(extraTicks) * Balance.dt)
            runScript(&b, k: kb, from: stopStep + 1, to: 14)
            runScript(&resumed, k: kb, from: stopStep + 1, to: 14)
            XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash(), "step \(stopStep)")
            XCTAssertEqual(resumed.s.units, b.s.units)
            XCTAssertEqual(resumed.s.zones, b.s.zones)
            XCTAssertEqual(resumed.s.projectiles, b.s.projectiles)
            XCTAssertEqual(b.s.stateHash(), reference.s.stateHash(), "保存点 \(stopStep) でも元の実行と同じ")
        }
    }

    func testStateHashSeesLuminaRegisters() {
        var (a, ka) = makeScriptWorld()
        var (b, kb) = makeScriptWorld()
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        b.s.units[kb].hero!.kit!.luminaStacks = 3
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash())
        b.s.units[kb].hero!.kit!.luminaStacks = 0
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        a.s.units[ka].hero!.kit!.luminaMoonArrow = 2
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash())
    }

    func testOpeningAttackFromStealthWithMoonArrowCarriesEverything() throws {
        // 月矢の連弾 → 隠れ月光 → 攻撃: 隠密を抜けた最初の攻撃が、最大の段（月影）+ 月矢（主矢の追加ダメージ + 副矢）を全部のせる
        var w = SkillWorld()
        let k = addLumina(&w)
        let main = addFoe(&w, dx: 400)
        let side = addFoe(&w, dx: 400, dy: 200, hero: "H004")
        let n = w.numbers(k, .skill1)
        XCTAssertTrue(w.cast(k, .skill1))
        XCTAssertTrue(w.cast(k, .ultimate))
        XCTAssertGreaterThan(w.kit(k).luminaMoonArrow, 0, "奥義の発動では月矢は終わらない")
        w.run(seconds: 0.5)
        w.s.units[k].attackTargetID = w.id(main)
        w.log.removeAll()
        w.run(seconds: 0.8)
        let attack = w.s.units[k].stats.attack
        let evs = events(w, to: main, .basicAttack)
        XCTAssertEqual(evs.count, 2)
        XCTAssertTrue(evs.contains { abs($0.amount - w.mitigated(attack + n.damage, .physical, on: main)) < 0.01 }, "主矢")
        XCTAssertTrue(evs.contains { abs($0.amount - w.mitigated(Kit_H025.shadowDamage(attack: attack), .physical, on: main)) < 0.01 },
                      "月影")
        let sideHit = try XCTUnwrap(events(w, to: side, .basicAttack).first)
        XCTAssertEqual(sideHit.amount, w.mitigated((attack + n.damage) * T.splashRatio, .physical, on: side), accuracy: 0.01, "副矢")
        XCTAssertFalse(w.s.units[k].has(.stealth))
    }

    func testBotDecisionsForTheSelfBuffs() throws {
        var w = SkillWorld()
        let k = addLumina(&w)
        let near = addFoe(&w, dx: 500)
        let far = addFoe(&w, dx: 900, hero: "H004")
        w.tick()
        let kit = try XCTUnwrap(HeroKits.kit(of: w.s.units[k]))
        func decide(_ slot: SkillSlot, _ foe: Int, fighting: Bool) -> String {
            let tg = w.targeting(k, slot)
            switch kit.botCast(w.s, w.ctx, bot: k, slot: slot, targeting: tg, target: foe, fighting: fighting) {
            case .useDefault: return "default"
            case .skip: return "skip"
            case .cast(let t): return "cast \(t)"
            case .castNow(let t): return "castNow \(t)"
            }
        }
        XCTAssertEqual(decide(.skill1, near, fighting: true), "cast none")
        XCTAssertEqual(decide(.skill1, near, fighting: false), "skip", "交戦していなければ撃たない")
        XCTAssertEqual(decide(.skill1, far, fighting: true), "skip", "射程の外では撃たない")
        XCTAssertEqual(decide(.ultimate, near, fighting: true), "cast none")
        XCTAssertEqual(decide(.ultimate, far, fighting: true), "skip")
        XCTAssertEqual(decide(.skill2, near, fighting: true), "default", "月蝕の矢は汎用の予測射撃")
        // 低 HP の交戦中は、汎用の関門（倒せる / 2 体以上）を飛ばして隠れ月光を使う
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.3
        XCTAssertEqual(decide(.ultimate, near, fighting: true), "castNow none")
        XCTAssertEqual(decide(.ultimate, near, fighting: false), "skip")
        XCTAssertEqual(decide(.ultimate, far, fighting: true), "skip")
    }

    func testBotEscapeUsesHiddenMoonlightWhenHurtOrHobbledAndOnlyThen() throws {
        var w = SkillWorld()
        let k = addLumina(&w)
        _ = addFoe(&w, dx: 300)
        w.tick()
        let kit = try XCTUnwrap(HeroKits.kit(of: w.s.units[k]))
        func escape(_ slot: SkillSlot) -> String {
            let tg = w.targeting(k, slot)
            switch kit.botEscape(w.s, w.ctx, bot: k, slot: slot, targeting: tg, flee: Vec2(-1, 0), enemyDistance: 300) {
            case .useDefault: return "default"
            case .skip: return "skip"
            case .cast(let t): return "cast \(t)"
            case .castNow(let t): return "castNow \(t)"
            }
        }
        let maxHP = w.s.units[k].stats.maxHP
        w.s.units[k].hp = maxHP
        XCTAssertEqual(escape(.ultimate), "skip", "元気なら逃げない")
        w.s.units[k].hp = maxHP * 0.4
        XCTAssertEqual(escape(.ultimate), "castNow none", "低 HP なら隠れ月光で離脱")
        w.s.units[k].hp = maxHP * 0.6
        XCTAssertEqual(escape(.ultimate), "skip")
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .slow, duration: 2, magnitude: 0.3))
        XCTAssertEqual(escape(.ultimate), "castNow none", "足を止められて HP が減っているなら解除のために使う")
        w.s.units[k].hp = maxHP * 0.8
        XCTAssertEqual(escape(.ultimate), "skip")
        // スキル1・2 は逃走に使わない（既定のまま = 突進系ではないので撃たない）
        XCTAssertEqual(escape(.skill1), "default")
        XCTAssertEqual(escape(.skill2), "default")
        // 隠れている間は重ねて使わない
        w.s.units[k].hp = maxHP * 0.2
        w.s.units[k].hero!.kit!.luminaHidden = true
        XCTAssertEqual(escape(.ultimate), "skip")
    }

    // MARK: - 1v1 の勝率（ロール代表以外を含む全員との総当たり）

    /// 参考値の確認。静止した 1v1（kiting なし・開幕の CC を受ける）では立ち上がりの遅い射手は不利なので、
    /// 勝率が 35〜65% に収まることは求めない（他のレンジャー H003 は Lv6/12 で約 15〜20%）。支配的（70% 超）でないことだけを見る。
    func testRoundRobinWinRateIsReportedAndNotDominant() {
        let ids = MasterData.shared.heroes.map(\.heroID).filter { $0 != "H025" }
        for level in SkillBalanceTests.levels {
            var wins = 0.0
            for foe in ids {
                let r = SkillBalanceTests.duel("H025", foe, level: level)
                if r.winnerIsA == true { wins += 1 } else if r.winnerIsA == nil { wins += 0.5 }
            }
            let rate = wins / Double(ids.count)
            print(String(format: "H025 round-robin Lv%d: %.0f%% (%.1f/%d)", level, rate * 100, wins, ids.count))
            XCTAssertLessThan(rate, 0.7, "Lv\(level)")
        }
    }
    // MARK: - ボットの煙テスト

    /// 標準マップのボット戦で、青のレンジャー枠をルミナに置き換える。
    private func botConfig(seed: UInt64) -> MatchConfig {
        var cfg = MatchFactory.botMatch(seed: seed)
        let pos = MatchFactory.defaultPosition(for: .ranger)
        for j in cfg.players.indices where cfg.players[j].heroID == "H025" { cfg.players[j].heroID = "H003" }
        if let idx = cfg.players.firstIndex(where: { $0.team == .blue && $0.position == pos }) {
            cfg.players[idx].heroID = "H025"
            cfg.players[idx].displayName = "Lumina_AI"
        }
        return cfg
    }

    func testBotPlaysLuminaForThreeMinutesWithAllSlotsAndSaneState() throws {
        var casts: [SkillSlot: Int] = [:]
        var found = false
        var peakStacks = 0
        var sawHidden = false
        for seed in [UInt64(11), 12, 13, 14, 15] {
            let sim = Simulation(config: botConfig(seed: seed))
            guard let ri = sim.state.heroIndices.first(where: { sim.state.units[$0].hero?.heroID == "H025" }) else {
                continue
            }
            found = true
            let id = sim.state.units[ri].id
            XCTAssertNotNil(sim.state.units[ri].hero?.kit, "ボットのルミナにも KitState が付く")
            casts = [:]
            peakStacks = 0
            sawHidden = false
            while !sim.isEnded && sim.state.time < 180 {
                // 奥義は AI の判断が厳しく、ボットのレベルが試合の流れで遅れると 3 分間は習得すらしないので、
                // 110 秒にルミナの奥義を習得済みにしておく（レベル・ランクだけ。以降は AI のまま）
                if sim.state.tick == 3300, let i = sim.state.index(of: id), sim.state.units[i].hero?.rank(.ultimate) == 0 {
                    var st = sim.state
                    st.units[i].hero!.skillRanks[SkillSlot.ultimate.rawValue] = 1
                    sim.restore(from: st)
                }
                // 奥義は AI の判断が厳しいので、120 秒以降は 15 秒おきに自動照準で奥義・S2・S1 を撃たせ、状態遷移も通す
                // （S1 はクールダウンが MLBB の 11 秒になり、交戦の少ない序盤の 3 分では AI が一度も撃たない種がある）
                var commands: [HeroCommand] = []
                if sim.state.time >= 120, sim.state.tick % 450 == 0 {
                    commands.append(HeroCommand(heroID: id, command: .castSkill(slot: .ultimate, target: .none)))
                } else if sim.state.time >= 120, sim.state.tick % 450 == 300 {
                    commands.append(HeroCommand(heroID: id, command: .castSkill(slot: .skill1, target: .none)))
                } else if sim.state.time >= 120, sim.state.tick % 450 == 150 {
                    commands.append(HeroCommand(heroID: id, command: .castSkill(slot: .skill2, target: .none)))
                }
                for e in sim.step(commands: commands) {
                    if case .skillCast(let c) = e, c.casterID == id { casts[c.slot, default: 0] += 1 }
                }
                guard let i = sim.state.index(of: id) else { break }
                let u = sim.state.units[i]
                XCTAssertTrue(u.hp.isFinite && u.pos.x.isFinite && u.pos.y.isFinite && u.resource.isFinite)
                XCTAssertGreaterThanOrEqual(u.resource, 0)
                if let k = u.hero?.kit {
                    XCTAssertTrue(k.timers.allSatisfy { $0 >= 0 && $0.isFinite })
                    XCTAssertTrue(k.reals.allSatisfy { $0.isFinite })
                    XCTAssertLessThanOrEqual(k.scheduled.count, 2)
                    XCTAssertTrue(k.windows.allSatisfy { !$0.isOpen }, "再使用の窓は使わない")
                    XCTAssertNil(k.sweep)
                    XCTAssertTrue((0...T.maxStacks).contains(k.luminaStacks))
                    peakStacks = max(peakStacks, k.luminaStacks)
                    if k.luminaHidden {
                        sawHidden = true
                        XCTAssertTrue(u.has(.stealth), "隠れ月光の最中は隠密が付いている")
                    } else {
                        XCTAssertFalse(u.statuses.contains { $0.tag == T.hiddenTag || $0.tag == T.hiddenSpeedTag })
                    }
                    if k.luminaStacks > 0 {
                        XCTAssertTrue(u.statuses.contains { $0.kind == .attackSpeedBoost && $0.tag == T.stackTag })
                    }
                }
            }
            if casts[.skill1, default: 0] > 0, casts[.skill2, default: 0] > 0, casts[.ultimate, default: 0] > 0,
               peakStacks == T.maxStacks, sawHidden { break }
        }
        XCTAssertTrue(found)
        XCTAssertGreaterThan(casts[.skill1, default: 0], 0, "S1: \(casts)")
        XCTAssertGreaterThan(casts[.skill2, default: 0], 0, "S2: \(casts)")
        XCTAssertGreaterThan(casts[.ultimate, default: 0], 0, "奥義: \(casts)")
        XCTAssertEqual(peakStacks, T.maxStacks)
        XCTAssertTrue(sawHidden)
    }

    // MARK: - 1v1 の TTK（ロール代表との総当たり）

    func testDuelTimeToKillAgainstRoleRepresentativesStaysInBand() {
        var failures: [String] = []
        for level in SkillBalanceTests.levels {
            for foe in SkillBalanceTests.representatives {
                let r = SkillBalanceTests.duel("H025", foe, level: level)
                print(String(format: "H025 duel Lv%d vs %@: %.1f s winner=%@ hp=%.2f", level, foe, r.ttk, r.winnerIsA.map { $0 ? "H025" : foe } ?? "-", r.remainingHPRatio))
                if r.ttk < SkillBalanceTests.minTTK || r.ttk > SkillBalanceTests.maxTTK {
                    failures.append(String(format: "Lv%d H025 vs %@: %.2f s", level, foe, r.ttk))
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures)")
    }
}
