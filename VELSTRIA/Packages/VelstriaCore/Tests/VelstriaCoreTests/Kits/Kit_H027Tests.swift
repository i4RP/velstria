import XCTest
@testable import VelstriaCore

/// H027 竜槍のジャルド（Zilong）のキット。仕様: docs/kits/Zilong.md、実装対応表: 同ファイル末尾。
/// 本物のキットなので testOverride は使わない（H027 は isReady）。敵は動かない通常のヒーロー（H001 / H003 ほか）。
final class Kit_H027Tests: XCTestCase {
    typealias Tune = Kit_H027.Tune

    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    // MARK: - 土台

    /// ジャルド（blue, 東向き）を置く。敵は別に addEnemy で足す。
    private func world(level: Int = 1, ranks: [Int]? = [1, 1, 1], noCooldowns: Bool = false) -> (SkillWorld, Int) {
        var w = SkillWorld(noCooldowns: noCooldowns)
        let k = w.addHero("H027", team: .blue, at: skillArena, level: level, ranks: ranks, facing: 0)
        return (w, k)
    }

    @discardableResult
    private func addEnemy(_ w: inout SkillWorld, dx: Double, dy: Double = 0, hero: String = "H001", level: Int = 12) -> Int {
        w.addHero(hero, team: .red, at: skillArena + Vec2(dx, dy), level: level, ranks: [1, 1, 1])
    }

    private func kit(_ w: SkillWorld, _ k: Int) -> KitState { w.s.units[k].hero!.kit! }

    private func fullHP(_ w: inout SkillWorld, _ i: Int) { w.s.units[i].hp = w.s.units[i].stats.maxHP }

    /// 1 tick ずつ進め、通常攻撃のダメージ（ターゲットへ）を「1 回の攻撃」ごとにまとめて返す。
    /// 三連突きは 0.133 秒おき（4 tick）に 3 発なので、まとまりの最初の命中から 9 tick 以内の命中は同じまとまりに入れる
    /// （通常の攻撃間隔は 15 tick 以上）。
    private func attackVolleys(_ w: inout SkillWorld, target: Int, ticks: Int) -> [[DamageEvent]] {
        var out: [[DamageEvent]] = []
        let tid = w.id(target)
        var start = -1000
        for n in 0..<ticks {
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            let hits = w.damageEvents.filter { $0.targetID == tid && $0.source == .basicAttack }
            guard !hits.isEmpty else { continue }
            if !out.isEmpty, n - start <= 9 {
                out[out.count - 1] += hits
            } else {
                out.append(hits)
                start = n
            }
        }
        return out
    }

    /// 通常攻撃の命中ごとに (tick の番号, ダメージ, 回復の合計) を返す。
    private func attackHits(_ w: inout SkillWorld, attacker k: Int, target: Int, ticks: Int)
        -> [(tick: Int, damage: DamageEvent, healed: Double)] {
        var out: [(tick: Int, damage: DamageEvent, healed: Double)] = []
        let tid = w.id(target)
        for n in 0..<ticks {
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            let healed = heals(w, of: k).reduce(0, +)
            for d in w.damageEvents where d.targetID == tid && d.source == .basicAttack {
                out.append((n, d, healed))
            }
        }
        return out
    }

    private func heals(_ w: SkillWorld, of i: Int) -> [Double] {
        let id = w.id(i)
        return w.log.compactMap { if case .heal(let t, _, let a) = $0, t == id { return a } else { return nil } }
    }

    // MARK: - レジストリ・照準・数値

    func testRegistryAndTargetingPerSlot() throws {
        XCTAssertTrue(HeroKits.hasKit("H027"))
        XCTAssertFalse(HeroKits.hasKit("H001"))
        XCTAssertFalse(HeroKits.hasKit("H002"))
        let m = MasterData.shared
        let hero = try XCTUnwrap(m.hero("H027"))
        func target(_ slot: SkillSlot, stage: Int = 0) throws -> SkillTargeting {
            let skill = try XCTUnwrap(m.skill(hero: "H027", slot: slot))
            return HeroKits.targeting(for: skill, hero: hero, stage: stage)
        }
        let s1 = try target(.skill1)
        XCTAssertEqual(s1.aim, .unit)
        XCTAssertEqual(s1.shape, .lockOn)
        XCTAssertTrue(s1.requiresTarget)
        XCTAssertEqual(s1.reach, Tune.flipReach)
        XCTAssertFalse(s1.recastable, "Zilong に再使用は無い")
        let s2 = try target(.skill2)
        XCTAssertEqual(s2.archetype, .targetedBlink)
        XCTAssertEqual(s2.aim, .unit)
        XCTAssertEqual(s2.shape, .lockOn)
        XCTAssertTrue(s2.requiresTarget)
        XCTAssertEqual(s2.reach, Tune.strikeReach)
        let ult = try target(.ultimate)
        XCTAssertEqual(ult.archetype, .selfAoE)
        XCTAssertEqual(ult.aim, .none)
        XCTAssertEqual(ult.shape, .selfRing)
        XCTAssertFalse(ult.requiresTarget)
        let passive = try target(.passive)
        XCTAssertEqual(passive.archetype, .passive)
        // 段（再使用）は無い: どの段でも同じ
        for slot in [SkillSlot.skill1, .skill2, .ultimate] {
            XCTAssertEqual(try target(slot, stage: 1), try target(slot), "\(slot)")
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
        let hero = try XCTUnwrap(m.hero("H027"))
        let skill = try XCTUnwrap(m.skill(hero: "H027", slot: slot))
        let stats = w.s.units[k].stats
        let generic = SkillCatalog.genericNumbers(for: skill, hero: hero, rank: rank, stats: stats)
        let kitN = SkillCatalog.numbers(for: skill, hero: hero, rank: rank, stats: stats)
        return kitN.totalDamage / generic.totalDamage
    }

    /// 例外: スキル1 だけは下限 0.65。公式の表（250 → 350 = 1.4 倍）は汎用（+30%/ランク = 1.9 倍）より伸びが緩く、
    /// 三連突きと打ち上げで Lv1 の 1v1 が強く出るため換算を低くした（docs/kits/Zilong.md の「バランス」）。
    func testNumbersStayWithinDamageBudgetAndFollowCooldownFormula() throws {
        for level in [1, 6, 12] {
            for rank in 1...Balance.basicSkillMaxRank {
                for slot in [SkillSlot.skill1, .skill2] {
                    let r = try damageRatio(slot, level: level, rank: rank)
                    XCTAssertGreaterThanOrEqual(r, slot == .skill1 ? 0.65 : 0.8, "\(slot) Lv\(level) r\(rank)")
                    XCTAssertLessThanOrEqual(r, 1.3, "\(slot) Lv\(level) r\(rank)")
                }
            }
        }
        // 奥義はダメージを持たない（自己強化。ダメージの予算は無し: 理由は docs/kits/Zilong.md の対応表）
        let (w, k) = world()
        let n = w.numbers(k, .ultimate)
        XCTAssertEqual(n.damage, 0)
        XCTAssertEqual(n.cc, .none)
        // クールダウン = MLBB の秒数（ランクで線形）× 全体倍率 × (1 − CD 短縮)
        let cdr = w.s.units[k].stats.cooldownReduction
        func expected(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
            (a + (b - a) * Double(rank - 1) / Double(maxRank - 1)) * (1 - cdr) * Balance.Skills.cooldownScale
        }
        let hero = try XCTUnwrap(MasterData.shared.hero("H027"))
        for rank in 1...4 {
            let sk = try XCTUnwrap(MasterData.shared.skill(hero: "H027", slot: .skill1))
            let got = SkillCatalog.numbers(for: sk, hero: hero, rank: rank, stats: w.s.units[k].stats).cooldown
            XCTAssertEqual(got, expected(12, 9.5, rank: rank, maxRank: 4), accuracy: 1e-9)
            let sk2 = try XCTUnwrap(MasterData.shared.skill(hero: "H027", slot: .skill2))
            XCTAssertEqual(SkillCatalog.numbers(for: sk2, hero: hero, rank: rank, stats: w.s.units[k].stats).cooldown,
                           expected(12, 9, rank: rank, maxRank: 4), accuracy: 1e-9)
        }
        for rank in 1...3 {
            let sk = try XCTUnwrap(MasterData.shared.skill(hero: "H027", slot: .ultimate))
            XCTAssertEqual(SkillCatalog.numbers(for: sk, hero: hero, rank: rank, stats: w.s.units[k].stats).cooldown,
                           expected(35, 27, rank: rank, maxRank: 3), accuracy: 1e-9)
        }
        // ランクが上がるほど強く（ダメージ・防御ダウン）、CD は短く
        let sk2 = try XCTUnwrap(MasterData.shared.skill(hero: "H027", slot: .skill2))
        let r1 = SkillCatalog.numbers(for: sk2, hero: hero, rank: 1, stats: w.s.units[k].stats)
        let r4 = SkillCatalog.numbers(for: sk2, hero: hero, rank: 4, stats: w.s.units[k].stats)
        XCTAssertGreaterThan(r4.damage, r1.damage)
        XCTAssertLessThan(r4.cooldown, r1.cooldown)
        XCTAssertEqual(r1.extras.first?.value, 15)
        XCTAssertEqual(r4.extras.first?.value, 30)
    }

    func testOfficialTablesCostsAndTags() throws {
        let hero = try XCTUnwrap(MasterData.shared.hero("H027"))
        func skill(_ slot: SkillSlot) throws -> SkillDef { try XCTUnwrap(MasterData.shared.skill(hero: "H027", slot: slot)) }
        let (w, k) = world(level: 6)
        let st = w.s.units[k].stats
        // ダメージ: (公式の基礎（Lv1 → Lv6 をランクで線形補間）+ 係数 × 攻撃力 × 0.6) × スロット倍率 × 換算
        let atk = st.attack * Balance.skillAttackScalingFactor
        let s1 = Balance.Skills.damageScale(.skill1), s2 = Balance.Skills.damageScale(.skill2)
        for rank in 1...4 {
            let lv = 1 + Double(rank - 1) * 5 / 3
            XCTAssertEqual(SkillCatalog.numbers(for: try skill(.skill1), hero: hero, rank: rank, stats: st).damage,
                           (250 + (lv - 1) * 20 + 0.8 * atk) * s1 * Tune.flipScale, accuracy: 1e-6, "S1 r\(rank)")
            XCTAssertEqual(SkillCatalog.numbers(for: try skill(.skill2), hero: hero, rank: rank, stats: st).damage,
                           (250 + (lv - 1) * 40 + 0.6 * atk) * s2 * Tune.strikeScale, accuracy: 1e-6, "S2 r\(rank)")
        }
        // 最終ランク = 公式の最終レベル（350 / 450）
        XCTAssertEqual(Kit_H027.scaledBase(Tune.flipBase, slot: .skill1, scale: Tune.flipScale, rank: 4),
                       350 * s1 * Tune.flipScale, accuracy: 1e-9)
        XCTAssertEqual(Kit_H027.scaledBase(Tune.strikeBase, slot: .skill2, scale: Tune.strikeScale, rank: 4),
                       450 * s2 * Tune.strikeScale, accuracy: 1e-9)
        // パッシブ: ダメージは公式の 80 + 30% × 換算 0.6、回復 50 + 20% と HP 50% 未満の +30 は公式の値そのまま
        XCTAssertEqual(Tune.flurryScale, 0.6)
        XCTAssertEqual(Kit_H027.flurryHitDamage(attack: 200), (80 + 60) * 0.6, accuracy: 1e-9)
        XCTAssertEqual(Kit_H027.flurryHeal(attack: 200), 50 + 40, accuracy: 1e-9)
        XCTAssertEqual(Tune.executeFlat, 30)
        // マナ（公式: S1 80 → 105、S2 40、ULT 120 / 140 / 160）。Energy のヒーローなので × energyCostMultiplier
        XCTAssertEqual(hero.resource, .energy)
        let e = Balance.energyCostMultiplier
        for (rank, mp) in [(1, 80.0), (2, 88), (3, 97), (4, 105)] {
            XCTAssertEqual(SkillSystem.cost(for: try skill(.skill1), hero: hero, rank: rank), mp * e, accuracy: 1e-9)
            XCTAssertEqual(SkillSystem.cost(for: try skill(.skill2), hero: hero, rank: rank), 40 * e, accuracy: 1e-9)
            XCTAssertEqual(SkillCatalog.numbers(for: try skill(.skill1), hero: hero, rank: rank, stats: st).cost, mp * e,
                           accuracy: 1e-9)
        }
        for (rank, mp) in [(1, 120.0), (2, 140), (3, 160)] {
            XCTAssertEqual(SkillSystem.cost(for: try skill(.ultimate), hero: hero, rank: rank), mp * e, accuracy: 1e-9)
        }
        // 実際の消費もこの値
        var (v, j) = world()
        let target = addEnemy(&v, dx: 200)
        let before = v.s.units[j].resource
        XCTAssertTrue(v.cast(j, .skill1, .unit(v.id(target))))
        XCTAssertEqual(before - v.s.units[j].resource, 80 * e, accuracy: 1e-9)
        // タグ（公式: パッシブ = バフ・回復、S1 = CC・ダメージ、S2 = 移動（ブリンク）・デバフ、ULT = 加速・バフ）
        XCTAssertEqual(HeroKits.tags(heroID: "H027", slot: .passive), ["buff", "heal"])
        XCTAssertEqual(HeroKits.tags(heroID: "H027", slot: .skill1), ["control", "burst"])
        XCTAssertEqual(HeroKits.tags(heroID: "H027", slot: .skill2), ["mobility", "disrupt"])
        XCTAssertEqual(HeroKits.tags(heroID: "H027", slot: .ultimate), ["mobility", "buff"])
        for slot in SkillSlot.allCases {
            for tag in HeroKits.tags(heroID: "H027", slot: slot) { XCTAssertTrue(KitTag.all.contains(tag), tag) }
        }
        // 説明文は公式の構造（{基礎}(+{係数}%物理攻撃)）
        let n1 = SkillCatalog.numbers(for: try skill(.skill1), hero: hero, rank: 1, stats: st)
        let ja1 = try XCTUnwrap(HeroKits.text(heroID: "H027", slot: .skill1)).filled(
            english: false, numbers: n1, targeting: SkillCatalog.targeting(for: try skill(.skill1), hero: hero))
        let b1 = Int(try XCTUnwrap(n1.extras.first { $0.key == "base" }).value)
        let p1 = Int(try XCTUnwrap(n1.extras.first { $0.key == "atkPct" }).value)
        XCTAssertTrue(ja1.contains("\(b1)(+\(p1)%物理攻撃)の物理ダメージ"), ja1)
        let pn = SkillCatalog.numbers(for: try skill(.passive), hero: hero, rank: 1, stats: st)
        let jap = try XCTUnwrap(HeroKits.text(heroID: "H027", slot: .passive)).filled(
            english: false, numbers: pn, targeting: SkillCatalog.targeting(for: try skill(.passive), hero: hero))
        XCTAssertTrue(jap.contains("48(+18%物理攻撃)の通常攻撃ダメージ") && jap.contains("50(+20%物理攻撃)のHP"), jap)
        XCTAssertTrue(jap.contains("ダメージが30増加する"), jap)
    }

    func testTextFillsEverySlotWithSimNumbers() throws {
        let (w, k) = world(level: 6, ranks: [2, 2, 2])
        let hero = try XCTUnwrap(MasterData.shared.hero("H027"))
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H027", slot: slot), "\(slot)")
            let skill = try XCTUnwrap(MasterData.shared.skill(hero: "H027", slot: slot))
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
        let passiveSkill = try XCTUnwrap(MasterData.shared.skill(hero: "H027", slot: .passive))
        let pn = SkillCatalog.numbers(for: passiveSkill, hero: hero, rank: 1, stats: stats)
        let ja = try XCTUnwrap(HeroKits.text(heroID: "H027", slot: .passive)).filled(
            english: false, numbers: pn, targeting: SkillCatalog.targeting(for: passiveSkill, hero: hero))
        XCTAssertTrue(ja.contains("\(Int(Kit_H027.flurryHitDamage(attack: stats.attack).rounded()))"), ja)
        XCTAssertTrue(ja.contains("\(Int((50 + 0.2 * stats.attack).rounded()))"), ja)
        XCTAssertEqual(pn.hits, 3)
        let ultSkill = try XCTUnwrap(MasterData.shared.skill(hero: "H027", slot: .ultimate))
        let un = SkillCatalog.numbers(for: ultSkill, hero: hero, rank: 2, stats: stats)
        XCTAssertEqual(un.extras.map(\.value), [40, 45, 7.5, 2])
        // 文の整理: スキル2 のリセット条件・奥義は他の CC を防がない
        let s2Skill = try XCTUnwrap(MasterData.shared.skill(hero: "H027", slot: .skill2))
        let s2n = SkillCatalog.numbers(for: s2Skill, hero: hero, rank: 1, stats: stats)
        let s2ja = try XCTUnwrap(HeroKits.text(heroID: "H027", slot: .skill2)).filled(
            english: false, numbers: s2n, targeting: SkillCatalog.targeting(for: s2Skill, hero: hero))
        XCTAssertTrue(s2ja.contains("倒したとき、または"), s2ja)
        let ultja = try XCTUnwrap(HeroKits.text(heroID: "H027", slot: .ultimate)).filled(
            english: false, numbers: un, targeting: SkillCatalog.targeting(for: ultSkill, hero: hero))
        XCTAssertTrue(ultja.contains("スタン"), ultja)
        for slot in SkillSlot.allCases {
            let t = try XCTUnwrap(HeroKits.text(heroID: "H027", slot: slot))
            for banned in ["S1", "S2", "奥義", "Skill1", "Skill2"] {
                XCTAssertFalse(t.ja.contains(banned) || t.en.contains(banned), "\(slot): \(banned)")
            }
        }
    }

    // MARK: - パッシブ: 竜の三連突き

    func testFlurryTriggersOnTheFourthAttackThenRestartsCounting() throws {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 140)
        w.s.units[k].attackTargetID = w.id(e)
        let volleys = attackVolleys(&w, target: e, ticks: 240)
        XCTAssertGreaterThanOrEqual(volleys.count, 6)
        // 3 回は単発、4 回目が三連、その後また 3 回単発 → 三連
        XCTAssertEqual(volleys.prefix(8).map(\.count), [1, 1, 1, 3, 1, 1, 1, 3])
        let atk = w.s.units[k].stats.attack
        let flurryHit = Kit_H027.flurryHitDamage(attack: atk)
        for hit in volleys[0] { XCTAssertEqual(hit.amount, w.mitigated(atk, .physical, on: e), accuracy: 1e-6) }
        for hit in volleys[3] { XCTAssertEqual(hit.amount, w.mitigated(flurryHit, .physical, on: e), accuracy: 1e-6) }
        XCTAssertLessThanOrEqual(kit(w, k).jarldCharge, 3)
    }

    func testFlurryHealsPerHitAndDoesNotChargeItself() throws {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 140)
        w.s.units[k].hero!.kit!.jarldCharge = 3
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.5
        w.s.units[k].attackTargetID = w.id(e)
        var healed: [Double] = []
        var volley: [DamageEvent] = []
        for _ in 0..<60 {
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            volley += w.damageEvents.filter { $0.source == .basicAttack }
            healed += heals(w, of: k)
            if volley.count >= 3 { break }
        }
        XCTAssertEqual(volley.count, 3, "三連突き")
        XCTAssertEqual(healed.count, 3, "命中ごとに回復")
        let st = w.s.units[k].stats
        let expected = (50 + 0.2 * st.attack) * (1 + st.healShieldPower) * st.healingReceivedMultiplier
        for h in healed { XCTAssertEqual(h, expected, accuracy: 1e-6) }
        XCTAssertEqual(kit(w, k).jarldCharge, 0, "三連突きの命中は竜気にならない")
        XCTAssertEqual(kit(w, k).jarldFlurryHitsLeft, 0)
        // 通常の攻撃は回復しない
        w.log.removeAll()
        let normal = attackVolleys(&w, target: e, ticks: 60)
        XCTAssertEqual(normal.first?.count, 1)
    }

    func testFlurryExtendsAttackRangeWhileChargedAndDropsAfterFiring() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 900)    // 殴れない遠さ
        let base = w.s.units[k].stats.attackRange
        w.s.units[k].hero!.kit!.jarldCharge = 3
        w.tick(3)
        XCTAssertEqual(w.s.units[k].stats.attackRange, base + Tune.flurryRangeBonus, accuracy: 1e-9)
        // 射程が伸びた分だけ遠くから三連突きが届く: 通常の射程の外・伸びた射程の内
        let reach = base + Tune.flurryRangeBonus + w.s.units[k].radius + w.s.units[e].radius
        w.s.units[e].pos = w.s.units[k].pos + Vec2(reach - 5, 0)
        w.s.units[k].attackTargetID = w.id(e)
        let volleys = attackVolleys(&w, target: e, ticks: 45)
        XCTAssertEqual(volleys.first?.count, 3, "伸びた射程から三連突き")
        w.tick(2)
        XCTAssertEqual(w.s.units[k].stats.attackRange, base, accuracy: 1e-9, "撃ったら元に戻る")
        XCTAssertFalse(w.s.units[k].statuses.contains { $0.kind == .attackRangeBoost })
    }

    func testSkillHitsChargeTheFlurryButCrowdControlOnlyHitsDoNot() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 200)
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        XCTAssertEqual(kit(w, k).jarldCharge, 1, "スキルのダメージも竜気になる")
        // ダメージ 0 の命中（CC のみ）は数えない
        w.hit(k, e, HitPayload(damage: 0, damageType: .physical, source: .skill(.skill1), skillID: "t"))
        XCTAssertEqual(kit(w, k).jarldCharge, 1)
        // 奥義（ダメージ無し）は数えない
        XCTAssertTrue(w.cast(k, .ultimate))
        XCTAssertEqual(kit(w, k).jarldCharge, 1)
        // 竜気は 3（奥義中は 2）で頭打ち
        w.hit(k, e, SkillWorld.truePayload(10))
        w.hit(k, e, SkillWorld.truePayload(10))
        w.hit(k, e, SkillWorld.truePayload(10))
        XCTAssertEqual(kit(w, k).jarldCharge, Tune.chargeUlt)
    }

    /// 三連突きの 3 発は同じ tick に重ならず、4 tick（約 0.133 秒）おきに当たる。1 発目は通常攻撃と同じ tick。
    func testFlurryHitsLandOnSeparateTicksAboutAFlurryGapApart() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 140)
        w.s.units[k].hero!.kit!.jarldCharge = 3
        w.s.units[k].attackTargetID = w.id(e)
        let hits = attackHits(&w, attacker: k, target: e, ticks: 60).prefix(3)
        XCTAssertEqual(hits.count, 3)
        let ticks = hits.map(\.tick)
        XCTAssertEqual(Set(ticks).count, 3, "3 発が同じ tick に重ならない: \(ticks)")
        // 予約は撃った tick を 1 回目に数えて減るので、実際に当たるのは ceil(gap / dt) - 1 tick 後
        let gap = Int((Tune.flurryGap / Balance.dt).rounded(.up)) - 1
        XCTAssertEqual(ticks[1] - ticks[0], gap, "2 発目は 1 発目の約 0.13 秒後")
        XCTAssertEqual(ticks[2] - ticks[1], gap)
        XCTAssertGreaterThan(Double(gap) * Balance.dt, 0.12, "被弾演出の間引き（0.12 秒）に潰されない")
        // 予約は撃った時点で 2 つ入り、当たり切ると空になる
        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 140)
        w2.s.units[k2].hero!.kit!.jarldCharge = 3
        w2.s.units[k2].attackTargetID = w2.id(e2)
        for _ in 0..<60 {
            w2.tick()
            if !w2.damageEvents.filter({ $0.source == .basicAttack }).isEmpty { break }
        }
        XCTAssertEqual(Kit.scheduledCount(w2.s, caster: k2, code: 2), 2)
        w2.run(seconds: 0.5)
        XCTAssertEqual(Kit.scheduledCount(w2.s, caster: k2), 0)
        XCTAssertEqual(kit(w2, k2).jarldCharge, 0, "三連突きの命中は竜気にならない")
        XCTAssertEqual(kit(w2, k2).jarldFlurryHitsLeft, 0)
    }

    /// ヒーロー以外（ミニオン）が相手なら、三連突きの回復は 1 発ごとに半分。
    func testFlurryHealIsHalvedAgainstNonHeroTargets() throws {
        var (w, k) = world(level: 12)
        let m = w.addMinion(team: .red, at: skillArena + Vec2(120, 0))
        w.s.units[m].baseStats.maxHP = 1e6
        StatCalculator.recompute(&w.s, m, w.ctx)
        w.s.units[m].hp = 1e6
        w.s.units[k].hero!.kit!.jarldCharge = 3
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.2
        w.s.units[k].attackTargetID = w.id(m)
        var healed: [Double] = []
        var count = 0
        for _ in 0..<60 {
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            healed += heals(w, of: k)
            count += w.damageEvents.filter { $0.source == .basicAttack }.count
            if count >= 3 { break }
        }
        XCTAssertEqual(count, 3)
        XCTAssertEqual(healed.count, 3)
        let st = w.s.units[k].stats
        let full = (50 + 0.2 * st.attack) * (1 + st.healShieldPower) * st.healingReceivedMultiplier
        for h in healed { XCTAssertEqual(h, full * Tune.flurryHealNonHero, accuracy: 1e-6) }
        // 説明文にも書いてある
        let ja = try XCTUnwrap(HeroKits.text(heroID: "H027", slot: .passive)).filled(
            english: false, numbers: w.numbers(k, .passive), targeting: SkillCatalog.targeting(
                for: try XCTUnwrap(MasterData.shared.skill(hero: "H027", slot: .passive)),
                hero: try XCTUnwrap(MasterData.shared.hero("H027"))))
        XCTAssertTrue(ja.contains("ヒーロー以外"), ja)
        XCTAssertFalse(ja.contains("{"), ja)
    }

    /// 1 発目のあとで対象が倒れた・射程の外へ出たら、残りは出ない。
    func testFlurryRemainingHitsDropWhenTheTargetDiesOrLeavesRange() {
        func run(_ mutate: (inout SkillWorld, Int) -> Void) -> Int {
            var (w, k) = world(level: 12)
            let e = addEnemy(&w, dx: 140)
            w.s.units[k].hero!.kit!.jarldCharge = 3
            w.s.units[k].attackTargetID = w.id(e)
            var count = 0
            var mutated = false
            var sinceFirst = 0
            // 1 発目から 0.5 秒だけ数える（その先は次の通常攻撃）
            for _ in 0..<80 {
                w.log.removeAll(keepingCapacity: true)
                w.tick()
                if count >= 1 { sinceFirst += 1 }
                if sinceFirst <= 15 {
                    count += w.damageEvents.filter { $0.source == .basicAttack && $0.targetID == w.id(e) }.count
                }
                if count >= 1, !mutated {
                    mutated = true
                    mutate(&w, e)
                }
            }
            return count
        }
        XCTAssertEqual(run { _, _ in }, 3, "何もしなければ 3 発")
        XCTAssertEqual(run { w, e in w.s.units[e].hp = 1 }, 2, "2 発目で倒れたら 3 発目は出ない")
        XCTAssertEqual(run { w, e in w.s.units[e].isAlive = false }, 1, "倒れたら残りは出ない")
        XCTAssertEqual(run { w, e in w.s.units[e].pos = w.s.units[e].pos + Vec2(700, 0) }, 1, "射程の外なら出ない")
        XCTAssertEqual(run { w, e in CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .untargetable, duration: 5)) },
                       1, "対象不可なら出ない")
    }

    /// 「HP 50% 未満で +30」は 1 発ごとに、当たる瞬間の対象の HP で決める。
    func testExecuteBonusIsEvaluatedPerFlurryHit() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 140)
        let atk = w.s.units[k].stats.attack
        let base = Kit_H027.flurryHitDamage(attack: atk)
        let first = w.mitigated(base, .physical, on: e)
        // 1 発目の前は 50% より少し上、1 発目のあとで 50% を割る
        w.s.units[e].hp = w.s.units[e].stats.maxHP * 0.5 + first * 0.5
        w.s.units[k].hero!.kit!.jarldCharge = 3
        w.s.units[k].attackTargetID = w.id(e)
        let hits = attackHits(&w, attacker: k, target: e, ticks: 60).prefix(3).map(\.damage.amount)
        XCTAssertEqual(hits.count, 3)
        XCTAssertEqual(hits[0], first, accuracy: 1e-6, "1 発目は HP 50% 以上なので +30 が無い")
        XCTAssertEqual(hits[1], w.mitigated(base + 30, .physical, on: e), accuracy: 1e-6, "2 発目は割ったあとなので +30")
        XCTAssertEqual(hits[2], hits[1], accuracy: 1e-6)
    }

    func testUltimateLowersFlurryThresholdToTwo() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 140)
        w.s.units[k].hero!.kit!.jarldCharge = 2
        w.s.units[k].attackTargetID = w.id(e)
        // 奥義なし: 2 では三連にならない
        XCTAssertEqual(attackVolleys(&w, target: e, ticks: 20).first?.count, 1)

        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 140)
        XCTAssertTrue(w2.cast(k2, .ultimate))
        w2.s.units[k2].hero!.kit!.jarldCharge = 2
        w2.s.units[k2].attackTargetID = w2.id(e2)
        // 三連突きが当たり終わった時点（次の通常攻撃の前）で止めて、竜気が 0 に戻っていることを見る
        var landed = 0
        for _ in 0..<60 where landed < 3 {
            w2.log.removeAll(keepingCapacity: true)
            w2.tick()
            landed += w2.damageEvents.filter { $0.source == .basicAttack && $0.targetID == w2.id(e2) }.count
        }
        XCTAssertEqual(landed, 3, "奥義中は 2 回で三連突き")
        XCTAssertEqual(kit(w2, k2).jarldCharge, 0)
    }

    func testExecuteBonusAddsFlatDamageBelowHalfHealth() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 140)
        let atk = w.s.units[k].stats.attack
        w.s.units[e].hp = w.s.units[e].stats.maxHP * 0.4
        w.s.units[k].attackTargetID = w.id(e)
        let low = attackVolleys(&w, target: e, ticks: 20)
        XCTAssertEqual(low.first?.first?.amount ?? 0, w.mitigated(atk + 30, .physical, on: e), accuracy: 1e-6)
        // 半分以上なら無し
        fullHP(&w, e)
        w.s.units[e].hp = w.s.units[e].stats.maxHP * 0.6
        let high = attackVolleys(&w, target: e, ticks: 40)
        XCTAssertEqual(high.first?.first?.amount ?? 0, w.mitigated(atk, .physical, on: e), accuracy: 1e-6)
        // 三連突きの 1 撃ごとに +30
        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 140)
        w2.s.units[k2].hero!.kit!.jarldCharge = 3
        w2.s.units[e2].hp = w2.s.units[e2].stats.maxHP * 0.4
        w2.s.units[k2].attackTargetID = w2.id(e2)
        let flurry = attackVolleys(&w2, target: e2, ticks: 45)
        let hit = Kit_H027.flurryHitDamage(attack: w2.s.units[k2].stats.attack) + 30
        XCTAssertEqual(flurry.first?.map(\.amount) ?? [], Array(repeating: w2.mitigated(hit, .physical, on: e2), count: 3))
    }

    // MARK: - S1: 槍の跳ね上げ

    func testFlipDealsDamageLiftsAndThrowsTargetBehind() throws {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 220)
        let n = w.numbers(k, .skill1)
        let before = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        XCTAssertLessThan(w.s.units[k].resource, before, "コストを消費")
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), n.cooldown, accuracy: 1e-9)
        let hits = w.damageEvents.filter { $0.targetID == w.id(e) }
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].amount, w.mitigated(n.damage, .physical, on: e), accuracy: 1e-6)
        XCTAssertEqual(hits[0].source, .skill(.skill1))
        let air = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .airborne })
        XCTAssertEqual(air.remaining, Tune.flipAirborne, accuracy: 1e-9)
        XCTAssertFalse(w.s.units[e].canAct)
        XCTAssertFalse(w.s.units[e].canMove)
        // 発動イベント
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.slot, .skill1)
        XCTAssertEqual(ev.shape, .lockOn)
        XCTAssertEqual(ev.targetUnitID, w.id(e))
        XCTAssertEqual(ev.duration, Tune.flipAirborne)
        // 術者の頭上を越えて背後に着地する
        w.run(seconds: 0.4)
        XCTAssertFalse(w.s.units[e].canAct, "宙に浮いている間は行動できない")
        w.run(seconds: 0.6)
        XCTAssertFalse(w.s.units[e].has(.airborne))
        XCTAssertEqual(w.s.units[e].pos.x, w.s.units[k].pos.x - Tune.flipLandingGap, accuracy: 3)
        XCTAssertEqual(w.s.units[e].pos.y, w.s.units[k].pos.y, accuracy: 3)
        XCTAssertTrue(w.s.units[e].canAct)
    }

    func testFlipRejectedWithoutTargetInReachAndKeepsResources() {
        var (w, k) = world()
        let far = addEnemy(&w, dx: 600)
        let before = w.s.units[k].resource
        XCTAssertFalse(w.cast(k, .skill1, .unit(w.id(far))))
        XCTAssertFalse(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        XCTAssertFalse(w.cast(k, .skill1))
        XCTAssertEqual(w.s.units[k].resource, before)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), 0)
        XCTAssertEqual(w.damage(to: far), 0)
        // ちょうど射程の縁（対象の縁まで 300）は届く
        let edge = Tune.flipReach + w.s.units[far].radius - 1
        w.s.units[far].pos = w.s.units[k].pos + Vec2(edge, 0)
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(far))))
    }

    func testFlipAutoTargetPrefersHeroesThenLowestHealthAndRespectsPointAndDirection() {
        var (w, k) = world(level: 12)
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(120, 0))
        let tank = addEnemy(&w, dx: 0, dy: 200, hero: "H001")
        let squishy = addEnemy(&w, dx: 0, dy: -200, hero: "H003")
        w.s.units[squishy].hp = w.s.units[squishy].stats.maxHP * 0.5
        // 自動: ヒーローのうち HP + シールドが最小
        XCTAssertEqual(Kit_H027.pickTarget(w.s, caster: k, reach: Tune.flipReach, target: .none), squishy)
        // 方向: 向きに近い敵（ミニオンが東にいるが、ヒーローを優先しない: 角度の最小が先）
        XCTAssertEqual(Kit_H027.pickTarget(w.s, caster: k, reach: Tune.flipReach, target: .direction(Vec2(0, 1))), tank)
        // 地点: その地点に近い敵
        XCTAssertEqual(Kit_H027.pickTarget(w.s, caster: k, reach: Tune.flipReach,
                                           target: .point(w.s.units[tank].pos)), tank)
        // 指定ユニット（ミニオン）はそのまま
        XCTAssertEqual(Kit_H027.pickTarget(w.s, caster: k, reach: Tune.flipReach, target: .unit(w.id(minion))), minion)
        // ヒーローが居なければ最寄りのミニオン
        w.s.units[tank].isAlive = false
        w.s.units[squishy].isAlive = false
        XCTAssertEqual(Kit_H027.pickTarget(w.s, caster: k, reach: Tune.flipReach, target: .none), minion)
        // 無敵の相手は選べない
        CombatSystem.addStatus(&w.s, targetIndex: minion, StatusEffect(kind: .invulnerable, duration: 5))
        XCTAssertNil(Kit_H027.pickTarget(w.s, caster: k, reach: Tune.flipReach, target: .none))
    }

    func testFlipOnCCImmuneTargetDamagesButDoesNotLiftOrMove() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 220)
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .ccImmune, duration: 5))
        let at = w.s.units[e].pos
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        XCTAssertGreaterThan(w.damage(to: e), 0)
        XCTAssertFalse(w.s.units[e].has(.airborne))
        w.run(seconds: 1)
        XCTAssertEqual(w.s.units[e].pos, at)
    }

    func testFlipExecuteFlatBelowHalfHealth() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 220)
        let n = w.numbers(k, .skill1)
        w.s.units[e].hp = w.s.units[e].stats.maxHP * 0.45
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        XCTAssertEqual(w.damage(to: e), w.mitigated(n.damage + 30, .physical, on: e), accuracy: 1e-6)
    }

    // MARK: - S2: 竜牙の踏み込み

    func testStrikeDashesHitsOnceOnArrivalShredsArmorThenAttacks() throws {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 400)
        w.s.units[e].hp = w.s.units[e].stats.maxHP
        let armor0 = w.s.units[e].stats.armor
        let n = w.numbers(k, .skill2)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), n.cooldown, accuracy: 1e-9)
        XCTAssertEqual(w.damage(to: e), 0, "到着するまでダメージは無い")
        XCTAssertNotNil(kit(w, k).sweep)
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.shape, .lockOn)
        XCTAssertEqual(ev.targetUnitID, w.id(e))
        w.run(seconds: 0.4)
        let hits = w.damageEvents.filter { $0.targetID == w.id(e) && $0.source == .skill(.skill2) }
        XCTAssertEqual(hits.count, 1, "到着した tick に 1 度だけ")
        XCTAssertEqual(hits[0].amount, n.damage * 100 / (100 + armor0), accuracy: 1e-6,
                       "防御ダウンはこの 1 撃には掛からない（掛かる前の防御で軽減）")
        XCTAssertNil(kit(w, k).sweep)
        // 対象の縁で止まる
        let gap = w.s.units[k].radius + w.s.units[e].radius
        XCTAssertEqual(w.s.units[k].pos.distance(to: w.s.units[e].pos), gap + 5, accuracy: 6)
        // 防御ダウン: 固定値 15（ランク 1）を 2 秒
        let shred = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .armorShred })
        XCTAssertEqual(shred.magnitude, 15 / armor0, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[e].stats.armor, armor0 - 15, accuracy: 1e-6)
        // そのまま通常攻撃に移る
        XCTAssertEqual(w.s.units[k].attackTargetID, w.id(e))
        w.run(seconds: 0.6)
        XCTAssertGreaterThan(w.damage(to: e, from: .basicAttack), 0, "踏み込み後の通常攻撃")
        // 2 秒で戻る
        w.run(seconds: 1.5)
        XCTAssertFalse(w.s.units[e].statuses.contains { $0.kind == .armorShred })
        XCTAssertEqual(w.s.units[e].stats.armor, armor0, accuracy: 1e-6)
    }

    func testStrikeShredScalesWithRankAndNeverExceedsArmor() {
        var (w, k) = world(level: 12, ranks: [1, 4, 1])
        let e = addEnemy(&w, dx: 300)
        let armor0 = w.s.units[e].stats.armor
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        w.run(seconds: 0.4)
        XCTAssertEqual(w.s.units[e].stats.armor, armor0 - 30, accuracy: 1e-6)
        // 防御が固定値より低い相手でも 0 未満にならない（割合は 0.9 まで）
        var (w2, k2) = world(level: 12, ranks: [1, 4, 1])
        let e2 = addEnemy(&w2, dx: 300)
        w2.s.units[e2].baseStats.armor = 5
        StatCalculator.recompute(&w2.s, e2, w2.ctx)
        XCTAssertTrue(w2.cast(k2, .skill2, .unit(w2.id(e2))))
        w2.run(seconds: 0.4)
        XCTAssertGreaterThanOrEqual(w2.s.units[e2].stats.armor, 0)
    }

    func testStrikeIsCancelledByHardCrowdControlMidDash() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 440)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        w.tick(2)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        w.run(seconds: 0.6)
        XCTAssertNil(kit(w, k).sweep)
        XCTAssertEqual(w.damage(to: e), 0, "突進が止まったので踏み込みの一撃は無い")
        XCTAssertLessThan(w.s.units[k].pos.x, skillArena.x + 440 - 150)
        XCTAssertEqual(kit(w, k).jarldDashTargetID, 0)
        XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(.skill2), 0, "クールダウンは戻らない")
    }

    func testStrikeMissesWhenTargetEscapesOrDiesDuringDash() {
        // 突進中に対象が遠くへ移った（ブリンクなど）
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 440)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        w.tick(2)
        w.s.units[e].pos = w.s.units[e].pos + Vec2(900, 0)
        w.run(seconds: 0.5)
        XCTAssertEqual(w.damage(to: e), 0)
        // 突進中に対象が倒れた
        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 440)
        XCTAssertTrue(w2.cast(k2, .skill2, .unit(w2.id(e2))))
        w2.tick(2)
        w2.s.units[e2].isAlive = false
        w2.run(seconds: 0.5)
        XCTAssertEqual(w2.damage(to: e2), 0)
        XCTAssertNil(w2.s.units[k2].attackTargetID)
    }

    func testStrikeNeedsTargetInReachAndEnoughResource() {
        var (w, k) = world(level: 12)
        let far = addEnemy(&w, dx: 700)
        XCTAssertFalse(w.cast(k, .skill2, .unit(w.id(far))))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 0)
        let near = addEnemy(&w, dx: 300, dy: 100, hero: "H003")
        // リソース不足は失敗（再使用は無いので、常に初回の条件）
        w.s.units[k].resource = 0
        XCTAssertFalse(w.cast(k, .skill2, .unit(w.id(near))))
        w.s.units[k].resource = w.s.units[k].stats.maxResource
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(near))))
        // 行動不能では撃てない
        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 300)
        CombatSystem.addStatus(&w2.s, targetIndex: k2, StatusEffect(kind: .stun, duration: 1))
        XCTAssertFalse(w2.cast(k2, .skill2, .unit(w2.id(e2))))
        XCTAssertFalse(w2.cast(k2, .skill1, .unit(w2.id(e2))))
    }

    func testStrikeCooldownResetsOnKill() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 400)
        w.s.units[e].hp = 1
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(.skill2), 1, "初回は必ずクールダウンを消費")
        w.run(seconds: 0.4)
        XCTAssertFalse(w.s.units[e].isAlive)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 0, accuracy: 1e-9, "倒したのでリセット")
        // 倒せなかったときは戻らない
        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 400)
        XCTAssertTrue(w2.cast(k2, .skill2, .unit(w2.id(e2))))
        w2.run(seconds: 0.4)
        XCTAssertGreaterThan(w2.s.units[k2].hero!.cooldown(.skill2), 1)
    }

    func testStrikeResetsWhenDamagedMinionDiesWithinHalfASecond() {
        func scenario(waitBeforeKill: Double, viaBasicAttack: Bool = false) -> Double {
            var (w, k) = world(level: 12)
            let helper = addEnemy(&w, dx: 0, dy: 800)
            let m = w.addMinion(team: .red, at: skillArena + Vec2(120, 0))
            w.s.units[k].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = 60
            if viaBasicAttack {
                // 実際の通常攻撃が当たった tick から数える
                w.s.units[k].attackTargetID = w.id(m)
                for _ in 0..<90 {
                    w.tick()
                    if w.damage(to: m, from: .basicAttack) > 0 { break }
                }
            } else {
                w.hit(k, m, SkillWorld.truePayload(10))
            }
            w.run(seconds: waitBeforeKill)
            // 他人が止めを刺す
            CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(helper), targetIndex: m, amount: 1e6,
                                     type: .trueDamage, source: .spell)
            w.tick(2)
            return w.s.units[k].hero!.cooldown(.skill2)
        }
        XCTAssertEqual(scenario(waitBeforeKill: 0.2), 0, accuracy: 1e-9, "0.5 秒以内に倒れた")
        XCTAssertEqual(scenario(waitBeforeKill: 0.2, viaBasicAttack: true), 0, accuracy: 1e-9, "通常攻撃でも同じ")
        XCTAssertGreaterThan(scenario(waitBeforeKill: 0.8), 3, "窓を過ぎたら戻らない")
        XCTAssertGreaterThan(scenario(waitBeforeKill: 0.8, viaBasicAttack: true), 3)
    }

    func testPracticeNoCooldownsKeepsCooldownsAtZeroAndStillWorks() {
        var (w, k) = world(level: 12, noCooldowns: true)
        let e = addEnemy(&w, dx: 300)
        XCTAssertTrue(w.cast(k, .skill2, .unit(w.id(e))))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 0)
        w.run(seconds: 0.4)
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), 0)
        XCTAssertTrue(w.cast(k, .ultimate))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), 0)
    }

    // MARK: - 奥義: 至高の武人

    func testUltimateGivesSpeedAttackSpeedAndNoDamage() throws {
        var (w, k) = world(level: 12)
        var (ref, rk) = world(level: 12)    // 比較用（奥義を使わない同じヒーロー）
        ref.tick(2)
        let baseMS = ref.s.units[rk].stats.moveSpeed
        let baseAS = ref.s.units[rk].stats.attackSpeed
        let n = w.numbers(k, .ultimate)
        let before = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .ultimate), "敵が居なくても撃てる")
        XCTAssertLessThan(w.s.units[k].resource, before)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), n.cooldown, accuracy: 1e-9)
        XCTAssertTrue(w.damageEvents.isEmpty, "ダメージを持たない")
        w.tick(2)
        XCTAssertEqual(w.s.units[k].stats.moveSpeed, baseMS * 1.4, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[k].stats.attackSpeed, baseAS * 1.35, accuracy: 1e-6)
        XCTAssertEqual(kit(w, k).jarldUltRemaining, Tune.ultDuration, accuracy: 0.1)
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.shape, .selfRing)
        XCTAssertEqual(ev.duration, Tune.ultDuration)
        XCTAssertEqual(ev.count, 2)
        let badge = try XCTUnwrap(HeroKits.badge(w.s.units[k].hero!, slot: .ultimate))
        XCTAssertEqual(badge.kind, .timer)
        XCTAssertEqual(badge.total, Tune.ultDuration)
        let pb = try XCTUnwrap(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
        XCTAssertEqual(pb, KitBadge(kind: .stacks, value: 0, maxValue: 2))
        // 7.5 秒で終わる
        w.run(seconds: 7.6)
        XCTAssertFalse(w.s.units[k].statuses.contains { $0.kind == .speedBoost || $0.kind == .attackSpeedBoost })
        XCTAssertEqual(w.s.units[k].stats.moveSpeed, baseMS, accuracy: 1e-6)
        XCTAssertEqual(kit(w, k).jarldUltRemaining, 0)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .ultimate))
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive)?.maxValue, 3)
    }

    func testUltimateAttackSpeedByRank() {
        for (rank, expected) in [(1, 0.35), (2, 0.45), (3, 0.55)] {
            var (w, k) = world(level: 12, ranks: [1, 1, rank])
            var (ref, rk) = world(level: 12)
            ref.tick(2)
            XCTAssertTrue(w.cast(k, .ultimate))
            w.tick(2)
            XCTAssertEqual(w.s.units[k].stats.attackSpeed, ref.s.units[rk].stats.attackSpeed * (1 + expected),
                           accuracy: 1e-6, "rank \(rank)")
        }
    }

    func testUltimateRemovesSlowsAndGrantsSlowImmunityButNotOtherCC() {
        var (w, k) = world(level: 12)
        let slow = StatusEffect(kind: .slow, duration: 5, magnitude: 0.5)
        CombatSystem.addStatus(&w.s, targetIndex: k, slow)
        w.tick()
        XCTAssertTrue(w.s.units[k].has(.slow))
        XCTAssertTrue(w.cast(k, .ultimate))
        XCTAssertFalse(w.s.units[k].has(.slow), "発動で解除")
        // 奥義中に新しく掛かったスロウも無効
        CombatSystem.addStatus(&w.s, targetIndex: k, slow)
        w.tick(2)
        XCTAssertFalse(w.s.units[k].has(.slow))
        let ms = w.s.units[k].stats.moveSpeed
        var (ref, rk) = world(level: 12)
        ref.tick(2)
        XCTAssertEqual(ms, ref.s.units[rk].stats.moveSpeed * 1.4, accuracy: 1e-6)
        // スタンなど他の CC には無効化が働かない（スロウ無効のみ）
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .root, duration: 1))
        w.tick()
        XCTAssertTrue(w.s.units[k].has(.root))
        // 切れたらスロウは再び効く
        w.run(seconds: 8)
        CombatSystem.addStatus(&w.s, targetIndex: k, slow)
        w.tick(2)
        XCTAssertTrue(w.s.units[k].has(.slow))
    }

    // MARK: - 死亡・割り込み

    func testDeathResetsEverythingIncludingChargeUltAndRangeBoost() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 300)
        XCTAssertTrue(w.cast(k, .ultimate))
        w.s.units[k].hero!.kit!.jarldCharge = 2
        w.tick(3)
        XCTAssertTrue(w.s.units[k].statuses.contains { $0.kind == .attackRangeBoost })
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        XCTAssertEqual(kit(w, k), KitState())
        XCTAssertTrue(w.s.units[k].statuses.isEmpty)
        w.run(seconds: 1)
        XCTAssertEqual(kit(w, k), KitState(), "死亡中は更新しない")
    }

    func testStunnedHeroCannotBeginAnyAttackOrSkillAndFlurryIsNotWasted() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 140)
        w.s.units[k].hero!.kit!.jarldCharge = 3
        w.s.units[k].attackTargetID = w.id(e)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        let during = attackVolleys(&w, target: e, ticks: 20)
        XCTAssertTrue(during.isEmpty)
        XCTAssertEqual(kit(w, k).jarldCharge, 3, "スタン中に竜気は消えない")
        let after = attackVolleys(&w, target: e, ticks: 80)
        XCTAssertEqual(after.first?.count, 3, "解けたら三連突き")
    }

    // MARK: - 決定性

    private func script(_ w: inout SkillWorld, k: Int, e1: Int, e2: Int, m: Int, step: Int) {
        switch step {
        case 0: w.cast(k, .ultimate)
        case 1: w.cast(k, .skill2, .unit(w.id(e1)))
        case 2: w.s.units[k].attackTargetID = w.id(e1)
        case 3: w.cast(k, .skill1, .unit(w.id(e1)))
        case 4: w.cast(k, .skill2, .unit(w.id(e2)))
        case 5: w.s.units[k].attackTargetID = w.id(e2)
        case 6: w.cast(k, .skill1, .unit(w.id(m)))
        default: break
        }
    }

    private func makeScriptWorld() -> (SkillWorld, Int, Int, Int, Int) {
        var w = SkillWorld()
        let k = w.addHero("H027", team: .blue, at: skillArena, level: 12, ranks: [2, 2, 2], facing: 0)
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
        run(&a, ka, a1, a2, am, from: 0, to: 9)
        run(&b, kb, b1, b2, bm, from: 0, to: 9)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(a.s.units, b.s.units)
        XCTAssertEqual(a.log, b.log)
        let skillHits = a.damageEvents.filter { $0.source.isSkill }
        XCTAssertGreaterThanOrEqual(skillHits.count, 2, "台本が実際にスキルを撃っている")
        XCTAssertTrue(a.damageEvents.contains { $0.source == .basicAttack })
    }

    func testJSONRoundTripMidDashAndMidUltimateResumesIdentically() throws {
        var (a, ka, a1, a2, am) = makeScriptWorld()
        run(&a, ka, a1, a2, am, from: 0, to: 9)

        var (b, kb, b1, b2, bm) = makeScriptWorld()
        run(&b, kb, b1, b2, bm, from: 0, to: 1)    // 奥義の途中
        b.cast(kb, .skill2, .unit(b.id(b1)))
        b.tick(2)                                   // 突進の途中
        XCTAssertNotNil(kit(b, kb).sweep)
        XCTAssertGreaterThan(kit(b, kb).jarldUltRemaining, 0)
        let data = try JSONEncoder().encode(b.s)
        var resumed = b
        resumed.s = try JSONDecoder().decode(SimState.self, from: data)
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        // 続きは同じ台本（step 1 の S2 はすでに撃ってあるので、残りの時間だけ進めてから step 2 以降）
        b.run(seconds: 0.7)
        resumed.run(seconds: 0.7)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        run(&b, kb, b1, b2, bm, from: 2, to: 9)
        run(&resumed, kb, b1, b2, bm, from: 2, to: 9)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.damageEvents.count, b.damageEvents.count)
    }

    // MARK: - ボットの判断

    private func botTargeting(_ slot: SkillSlot) throws -> SkillTargeting {
        let hero = try XCTUnwrap(MasterData.shared.hero("H027"))
        return HeroKits.targeting(for: try XCTUnwrap(MasterData.shared.skill(hero: "H027", slot: slot)), hero: hero, stage: 0)
    }

    private func decision(_ d: BotKitDecision) -> String {
        switch d {
        case .useDefault: return "default"
        case .cast: return "cast"
        case .castNow: return "castNow"
        case .skip: return "skip"
        }
    }

    /// 奥義: 交戦中の敵ヒーローに届くなら関門を待たずに今撃つ。強化中・敵が遠い・ミニオン相手は従来どおり。
    func testBotUltimateCastsNowOnAnEnemyHeroInReach() throws {
        var (w, k) = world(level: 12)
        let hero = addEnemy(&w, dx: 300)
        let far = addEnemy(&w, dx: 650, dy: 0, hero: "H003")
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(200, 0))
        let t = try botTargeting(.ultimate)
        func ask(_ target: Int, fighting: Bool = true) -> String {
            decision(HeroKits.botCast(w.s, w.ctx, bot: k, slot: .ultimate, targeting: t, target: target, fighting: fighting))
        }
        XCTAssertEqual(ask(hero), "castNow")
        XCTAssertEqual(ask(hero, fighting: false), "skip")
        XCTAssertEqual(ask(far), "cast", "届かない敵ヒーローは従来どおり（汎用の関門を通る）")
        XCTAssertEqual(ask(minion), "cast", "ミニオンは関門を待つ")
        w.s.units[far].pos = skillArena + Vec2(1200, 0)
        XCTAssertEqual(ask(far), "skip")
        // 強化中は撃たない
        XCTAssertTrue(w.cast(k, .ultimate))
        XCTAssertEqual(ask(hero), "skip")
    }

    /// ミニオン・ジャングルへの竜牙突き（S2）: 許すのは S2 だけ。HP が低い・敵タワーの射程なら許さない。
    func testBotFarmAllowsOnlySkill2AndKeepsItSafe() throws {
        var (w, k) = world(level: 12)
        let t2 = try botTargeting(.skill2)
        let t1 = try botTargeting(.skill1)
        let center = skillArena + Vec2(250, 0)
        XCTAssertTrue(HeroKits.botFarm(w.s, w.ctx, bot: k, slot: .skill2, targeting: t2, center: center, count: 3))
        XCTAssertFalse(HeroKits.botFarm(w.s, w.ctx, bot: k, slot: .skill1, targeting: t1, center: center, count: 3))
        XCTAssertFalse(HeroKits.botFarm(w.s, w.ctx, bot: k, slot: .ultimate, targeting: t2, center: center, count: 3))
        // HP が半分を切ると使わない
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.4
        XCTAssertFalse(HeroKits.botFarm(w.s, w.ctx, bot: k, slot: .skill2, targeting: t2, center: center, count: 3))
        w.s.units[k].hp = w.s.units[k].stats.maxHP
        // 敵のタワーの射程には飛び込まない
        _ = w.addTower(team: .red, at: center + Vec2(300, 0))
        XCTAssertFalse(HeroKits.botFarm(w.s, w.ctx, bot: k, slot: .skill2, targeting: t2, center: center, count: 3))
    }

    // MARK: - ボットの煙テスト

    /// ジャルドをボットにして通常の 10 人戦を回す。S1 / S2 / 奥義のすべてを撃ち、状態が壊れない。
    func testBotSmokeCastsEverySlotAndStateStaysBounded() throws {
        var cfg = MatchFactory.botMatch(seed: 31)
        let idx = try XCTUnwrap(cfg.players.firstIndex { $0.team == .blue && $0.position == .top })
        if let other = cfg.players.firstIndex(where: { $0.heroID == "H027" }), other != idx {
            cfg.players[other].heroID = cfg.players[idx].heroID
        }
        cfg.players[idx].heroID = "H027"
        let sim = Simulation(config: cfg)
        let hero = try XCTUnwrap(sim.state.heroIndices.first { sim.state.units[$0].hero?.heroID == "H027" })
        let heroID = sim.state.units[hero].id
        XCTAssertNotNil(sim.state.units[hero].hero?.kit)
        var casts: [SkillSlot: Int] = [:]
        var maxCharge = 0
        while !sim.isEnded && sim.state.time < 1500 {
            let events = sim.step()
            for e in events {
                if case .skillCast(let c) = e, c.casterID == heroID { casts[c.slot, default: 0] += 1 }
            }
            let i = sim.state.index(of: heroID)!
            let u = sim.state.units[i]
            let k = u.hero!.kit!
            maxCharge = max(maxCharge, k.jarldCharge)
            XCTAssertTrue(u.hp.isFinite && u.pos.x.isFinite && u.pos.y.isFinite && u.resource.isFinite)
            XCTAssertLessThanOrEqual(k.jarldCharge, 3)
            XCTAssertTrue(k.reals.allSatisfy { $0.isFinite })
            XCTAssertTrue(k.timers.allSatisfy { $0.isFinite && $0 >= 0 })
            XCTAssertLessThanOrEqual(k.scheduled.count, 4)
            XCTAssertLessThanOrEqual(u.statuses.count, 24)
            if casts[.skill1, default: 0] > 0, casts[.skill2, default: 0] > 0, casts[.ultimate, default: 0] > 0,
               sim.state.time > 130 { break }
        }
        XCTAssertGreaterThan(casts[.skill1, default: 0], 0, "S1: \(casts)")
        XCTAssertGreaterThan(casts[.skill2, default: 0], 0, "S2: \(casts)")
        XCTAssertGreaterThan(casts[.ultimate, default: 0], 0, "奥義: \(casts)")
        XCTAssertGreaterThanOrEqual(maxCharge, 1)
        print("H027 bot smoke: \(casts) until \(sim.state.time) s")
    }

    // MARK: - 1v1 の TTK（H001–H006 相手、Lv 1 / 6 / 12）

    func testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives() {
        var failures: [String] = []
        var wins = 0
        var total = 0
        var table = "H027 TTK\n"
        for level in SkillBalanceTests.levels {
            for foe in SkillBalanceTests.representatives {
                let r = SkillBalanceTests.duel("H027", foe, level: level)
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
        // 勝敗はロール代表の並びで偏る（この総当たりは H001/H002 が 6 割以上勝つ）ので、弱すぎないことだけ見る
        XCTAssertGreaterThanOrEqual(wins, total / 4, "弱すぎる: \(wins)/\(total)")
    }
}
