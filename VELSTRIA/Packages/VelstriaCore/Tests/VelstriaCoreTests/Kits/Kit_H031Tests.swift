import XCTest
@testable import VelstriaCore

/// H031 氷嵐のオーリア（MLBB オーロラの Velstria 版）のキット。docs/kits/Aurora.md の対応表と同じ並びで検査する。
/// キットは HeroKits.testOverride に有効な Kit_H031 を差して試す（本番の有効化とは独立。有効化後も同じ結果）。
final class Kit_H031Tests: XCTestCase {
    typealias T = OriaTuning
    static let east = Vec2(1, 0)

    override func setUp() {
        super.setUp()
        HeroKits.testOverride = [Kit_H031(isReady: true)]
    }

    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    // MARK: - 土台

    @discardableResult
    private func addOria(_ w: inout SkillWorld, ranks: [Int]? = [1, 1, 1], at pos: Vec2 = skillArena, level: Int = 1) -> Int {
        w.addHero("H031", team: .blue, at: pos, level: level, ranks: ranks, facing: 0)
    }

    private var def: HeroDef { MasterData.shared.hero("H031")! }

    private func skill(_ slot: SkillSlot) -> SkillDef { MasterData.shared.skill(hero: "H031", slot: slot)! }

    private func damageEvents(_ w: SkillWorld, to e: Int, _ source: DamageSource) -> [DamageEvent] {
        w.damageEvents.filter { $0.targetID == w.id(e) && $0.source == source }
    }

    private func status(_ w: SkillWorld, _ i: Int, _ kind: StatusKind, tag: String? = nil) -> StatusEffect? {
        w.s.units[i].statuses.first { $0.kind == kind && (tag == nil || $0.tag == tag) }
    }

    private func extra(_ n: SkillNumbers, _ key: String) -> Double {
        n.extras.first { $0.key == key }?.value ?? .nan
    }

    /// 致命傷（HP・シールドを超える確定ダメージ）。
    private func fatal(_ w: inout SkillWorld, _ k: Int, from e: Int, source: DamageSource = .spell) {
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                 source: source)
        w.flushEvents()
    }

    // MARK: - レジストリ・照準

    func testRegistryTargetingAndTextPerSlot() throws {
        XCTAssertTrue(HeroKits.hasKit("H031"))
        XCTAssertNotNil(HeroKits.kit(for: "H031"))
        // 本番のレジストリでも有効（テストの差し込み無しで引ける）
        XCTAssertTrue(Kit_H031().isReady)
        HeroKits.testOverride = []
        XCTAssertTrue(HeroKits.hasKit("H031"))
        HeroKits.testOverride = [Kit_H031(isReady: true)]

        let t1 = SkillCatalog.targeting(for: skill(.skill1), hero: def)
        XCTAssertEqual(t1.archetype, .groundAoE)
        XCTAssertEqual(t1.aim, .point)
        XCTAssertEqual(t1.range, 650)
        XCTAssertEqual(t1.radius, T.s1Radius)
        XCTAssertEqual(t1.shape, .circleAtPoint)
        XCTAssertEqual(t1.reach, 650 + T.s1Radius)

        let t2 = SkillCatalog.targeting(for: skill(.skill2), hero: def)
        XCTAssertEqual(t2.archetype, .cone)
        XCTAssertEqual(t2.aim, .direction)
        XCTAssertEqual(t2.range, 650)
        XCTAssertEqual(t2.radius, 650)
        XCTAssertEqual(t2.shape, .fan)
        XCTAssertEqual(t2.halfAngle, T.s2HalfAngle, accuracy: 1e-12)
        XCTAssertEqual(t2.reach, 650)

        let t3 = SkillCatalog.targeting(for: skill(.ultimate), hero: def)
        XCTAssertEqual(t3.archetype, .piercingLine)
        XCTAssertEqual(t3.aim, .direction)
        XCTAssertEqual(t3.range, 770, "遠隔の奥義の射程の目安（≈ 100 × MLBB の 7.7 マス）")
        XCTAssertEqual(t3.radius, T.ultGlacierRadius, "照準の帯の半幅 = 氷河の半径（砕けて凍らせる範囲）")
        XCTAssertEqual(t3.shape, .wideLine)
        XCTAssertNotEqual(T.ultPathWidth, T.ultGlacierRadius, "氷の道の当たり幅は照準の帯とは別")

        XCTAssertEqual(SkillCatalog.targeting(for: skill(.passive), hero: def).archetype, .passive)

        // 説明文: 4 スロットとも ja/en があり、テンプレートの語が全部埋まる
        let stats = HeroGrowth.baseStats(def: def, level: 6)
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H031", slot: slot), "\(slot)")
            let sk = skill(slot)
            let n = SkillCatalog.numbers(for: sk, hero: def, rank: 1, stats: stats)
            let t = SkillCatalog.targeting(for: sk, hero: def)
            for english in [false, true] {
                let filled = text.filled(english: english, numbers: n, targeting: t)
                XCTAssertFalse(filled.contains("{"), "\(slot) \(english): \(filled)")
                XCTAssertFalse(filled.isEmpty)
            }
        }
        // 数値は sim の値と一致する
        let n1 = SkillCatalog.numbers(for: skill(.skill1), hero: def, rank: 1, stats: stats)
        let ja1 = HeroKits.text(heroID: "H031", slot: .skill1)!.filled(english: false, numbers: n1, targeting: t1)
        XCTAssertTrue(ja1.contains("\(Int(n1.damage.rounded()))ダメージ"), ja1)
        XCTAssertTrue(ja1.contains("\(Int(extra(n1, "hailDamage").rounded()))ダメージ"), ja1)
        let n3 = SkillCatalog.numbers(for: skill(.ultimate), hero: def, rank: 1, stats: stats)
        let en3 = HeroKits.text(heroID: "H031", slot: .ultimate)!.filled(english: true, numbers: n3, targeting: t3)
        XCTAssertTrue(en3.contains("\(Int(extra(n3, "shatterDamage").rounded())) damage"), en3)
        let np = SkillCatalog.numbers(for: skill(.passive), hero: def, rank: 1, stats: stats)
        let jap = HeroKits.text(heroID: "H031", slot: .passive)!.filled(english: false, numbers: np, targeting: t1)
        XCTAssertTrue(jap.contains("1.5秒") && jap.contains("30%") && jap.contains("150秒"), jap)
        XCTAssertTrue(jap.contains("氷の誇り") && jap.contains("レベル1で0%"), jap)
        let enp = HeroKits.text(heroID: "H031", slot: .passive)!.filled(english: true, numbers: np, targeting: t1)
        XCTAssertTrue(enp.contains("Pride of Ice") && enp.contains("0% at level 1"), enp)
        // 用語: スキル1 / スキル2 / アルティメットの略称は使わない
        for slot in SkillSlot.allCases {
            let n = SkillCatalog.numbers(for: skill(slot), hero: def, rank: 1, stats: stats)
            let ja = HeroKits.text(heroID: "H031", slot: slot)!.filled(english: false, numbers: n, targeting: t1)
            XCTAssertFalse(ja.contains("S1") || ja.contains("S2") || ja.contains("奥義"), "\(slot): \(ja)")
        }
    }

    // MARK: - 数値・ダメージ予算

    func testSingleTargetDamageStaysNearGenericBudget() throws {
        for level in [1, 6, 12] {
            let stats = HeroGrowth.baseStats(def: def, level: level)
            for slot in SkillSlot.actives {
                let sk = skill(slot)
                for rank in 1...slot.maxRank {
                    let base = SkillCatalog.genericNumbers(for: sk, hero: def, rank: rank, stats: stats)
                    let n = SkillCatalog.numbers(for: sk, hero: def, rank: rank, stats: stats)
                    var reference = base.damage * Double(base.hits)
                    var total = n.damage * Double(n.hits)
                    switch slot {
                    case .skill1:
                        total += extra(n, "hailDamage") * Double(T.s1Hails)
                    case .skill2:
                        // 汎用の遠隔 S2 は「ブリンク + 強化攻撃」で半分になっているので、元のスキル値を基準にする
                        reference = base.damage / Balance.Skills.empowerRatio
                        total += extra(n, "patchTotal")
                    default:
                        total += extra(n, "shatterDamage")
                    }
                    let ratio = total / reference
                    XCTAssertGreaterThanOrEqual(ratio, 0.8, "\(slot) rank \(rank) Lv\(level)")
                    XCTAssertLessThanOrEqual(ratio, 1.3, "\(slot) rank \(rank) Lv\(level)")
                    // コストは汎用のまま（SkillSystem が定義から引く）
                    XCTAssertEqual(n.cost, base.cost)
                    XCTAssertEqual(n.resource, .mana)
                    XCTAssertEqual(n.damageType, .magic)
                }
            }
        }
        // ランクが上がると強くなり、S1 と奥義は CD が短くなる（S2 は 13 秒固定）
        let stats = HeroGrowth.baseStats(def: def, level: 6)
        for slot in SkillSlot.actives {
            let lo = SkillCatalog.numbers(for: skill(slot), hero: def, rank: 1, stats: stats)
            let hi = SkillCatalog.numbers(for: skill(slot), hero: def, rank: slot.maxRank, stats: stats)
            XCTAssertGreaterThan(hi.damage, lo.damage, "\(slot)")
            if slot == .skill2 {
                XCTAssertEqual(hi.cooldown, lo.cooldown, accuracy: 1e-9)
            } else {
                XCTAssertLessThan(hi.cooldown, lo.cooldown, "\(slot)")
            }
        }
        // CD は MLBB の秒数 × 調整係数
        let lo1 = SkillCatalog.numbers(for: skill(.skill1), hero: def, rank: 1, stats: Stats())
        XCTAssertEqual(lo1.cooldown, 6.5 * Balance.Skills.cooldownScale, accuracy: 1e-9)
        let lo2 = SkillCatalog.numbers(for: skill(.skill2), hero: def, rank: 1, stats: Stats())
        XCTAssertEqual(lo2.cooldown, 13.0 * Balance.Skills.cooldownScale, accuracy: 1e-9)
        // CC: S1 鈍足 40% / 1 秒、S2 凍結 1 秒、奥義 凍結（魔力で延びる）
        let n1 = SkillCatalog.numbers(for: skill(.skill1), hero: def, rank: 1, stats: stats)
        XCTAssertEqual(n1.cc, .slow)
        XCTAssertEqual(n1.ccDuration, 1.0)
        XCTAssertEqual(extra(n1, "slow"), 40)
        let n2 = SkillCatalog.numbers(for: skill(.skill2), hero: def, rank: 1, stats: stats)
        XCTAssertEqual(n2.cc, .stun)
        XCTAssertEqual(n2.ccDuration, 1.0)
        let n3 = SkillCatalog.numbers(for: skill(.ultimate), hero: def, rank: 1, stats: stats)
        XCTAssertEqual(n3.cc, .stun)
        XCTAssertEqual(extra(n3, "slow"), 80)
        XCTAssertEqual(extra(n3, "slowDuration"), 1.2, accuracy: 1e-12)
    }

    func testUltimateFreezeGrowsWithAbilityPowerUpToTheCap() {
        XCTAssertEqual(Kit_H031.glacierFreeze(abilityPower: 0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(Kit_H031.glacierFreeze(abilityPower: 100), 1.2, accuracy: 1e-12)
        XCTAssertEqual(Kit_H031.glacierFreeze(abilityPower: 250), 1.5, accuracy: 1e-12)
        XCTAssertEqual(Kit_H031.glacierFreeze(abilityPower: 300), 1.6, accuracy: 1e-12)
        XCTAssertEqual(Kit_H031.glacierFreeze(abilityPower: 9999), 1.6, accuracy: 1e-12, "上限 +0.6 秒")
        XCTAssertEqual(Kit_H031.glacierFreeze(abilityPower: -50), 1.0, accuracy: 1e-12)
        var st = Stats()
        st.abilityPower = 200
        let n = SkillCatalog.numbers(for: skill(.ultimate), hero: def, rank: 2, stats: st)
        XCTAssertEqual(n.ccDuration, 1.4, accuracy: 1e-12)
        XCTAssertEqual(extra(n, "freeze"), 1.4, accuracy: 1e-12)
    }

    // MARK: - S1 氷塊と雹

    func testHailMeteorLandsAfterDelayWithSlowThenFiveHailstones() throws {
        var w = SkillWorld()
        let k = addOria(&w)
        let center = skillArena + Vec2(500, 0)
        let e = w.addDummyEnemy(at: center)
        let n = w.numbers(k, .skill1)
        let hail = Kit_H031.hailDamage(n)
        XCTAssertTrue(w.cast(k, .skill1, .point(center)))
        XCTAssertEqual(w.castEvents.last?.archetype, .groundAoE)
        XCTAssertEqual(w.castEvents.last?.shape, .circleAtPoint)
        XCTAssertEqual(w.castEvents.last?.count, T.s1Hails)

        w.run(seconds: 0.4)
        XCTAssertTrue(w.damageEvents.isEmpty, "氷塊の着弾前は無傷")
        w.run(seconds: 0.2)   // 0.6 秒
        let meteor = damageEvents(w, to: e, .skill(.skill1))
        XCTAssertEqual(meteor.count, 1)
        XCTAssertEqual(meteor[0].amount, w.mitigated(n.damage, .magic, on: e), accuracy: 1e-6)
        let slow = try XCTUnwrap(status(w, e, .slow, tag: T.s1SlowTag))
        XCTAssertEqual(slow.magnitude, 0.40, accuracy: 1e-12)
        XCTAssertGreaterThan(slow.remaining, 0.85)
        XCTAssertLessThanOrEqual(slow.remaining, 1.0)
        // 雹は氷塊のあとに、中心のまわり（氷塊の半径の 0.9 / 1.2 倍）へ降る: 中心に立つ相手には当たらない
        w.run(seconds: 1.0)
        let all = damageEvents(w, to: e, .skill(.skill1))
        XCTAssertEqual(all.count, 1, "氷塊の中心に立つ相手には雹が当たらない（氷塊だけ）")
        XCTAssertEqual(w.damage(to: e), w.mitigated(n.damage, .magic, on: e), accuracy: 1e-5)

        // 雹の落ちる位置に立つ相手: 氷塊 + その雹（向き east から 72° ずつ、偶数番は内側 0.9、奇数番は外側 1.2）
        var v = SkillWorld()
        let k2 = addOria(&v)
        let spot = center + Vec2(T.s1Radius * T.hailRingInner, 0)   // k = 0 の雹の中心
        let e2 = v.addDummyEnemy(at: spot)
        XCTAssertTrue(v.cast(k2, .skill1, .point(center)))
        v.run(seconds: 2)
        let hits = damageEvents(v, to: e2, .skill(.skill1))
        XCTAssertEqual(hits.count, 2, "氷塊 + 雹 1 発")
        XCTAssertEqual(hits[1].amount, v.mitigated(hail, .magic, on: e2), accuracy: 1e-6)
        XCTAssertEqual(v.damage(to: e2), v.mitigated(n.damage + hail, .magic, on: e2), accuracy: 1e-5)
    }

    func testHailScatterGeometry() {
        // 雹は氷塊の半径の 0.9 / 1.2 倍の輪の上、5 つが 72° ずつ
        XCTAssertEqual(T.hailRingInner, 0.9)
        XCTAssertEqual(T.hailRingOuter, 1.2)
        var w = SkillWorld()
        let k = addOria(&w)
        let center = skillArena + Vec2(500, 0)
        XCTAssertTrue(w.cast(k, .skill1, .point(center)))
        w.tick()
        let hailZones = w.log.compactMap { e -> Vec2? in
            if case .zoneCreated(_, _, _, let visual, let c, _, _, _, _) = e, visual == Kit_H031.passiveVisual(w.ctx) { return c }
            return nil
        }
        XCTAssertEqual(hailZones.count, T.s1Hails)
        for (idx, c) in hailZones.enumerated() {
            let ring = T.s1Radius * (idx % 2 == 0 ? T.hailRingInner : T.hailRingOuter)
            XCTAssertEqual(c.distance(to: center), ring, accuracy: 1e-6, "雹 \(idx)")
            XCTAssertGreaterThan(c.distance(to: center), T.hailRadius, "中心は雹の半径の外 = 中心に立つ相手に当たらない")
        }
    }

    func testPrideHealGrowsWithLevel() throws {
        XCTAssertEqual(Kit_H031.prideHealRatio(level: 1), T.prideHealLv1, accuracy: 1e-12)
        XCTAssertEqual(Kit_H031.prideHealRatio(level: T.prideHealFullLevel), T.prideHealRatio, accuracy: 1e-12)
        XCTAssertEqual(Kit_H031.prideHealRatio(level: 15), T.prideHealRatio, accuracy: 1e-12, "最大レベルでも 30%")
        XCTAssertEqual(Kit_H031.prideHealRatio(level: 6), T.prideHealLv1 + (T.prideHealRatio - T.prideHealLv1) * 5 / 11,
                       accuracy: 1e-12)
        XCTAssertLessThan(Kit_H031.prideHealRatio(level: 1), Kit_H031.prideHealRatio(level: 6))
        XCTAssertLessThan(Kit_H031.prideHealRatio(level: 6), Kit_H031.prideHealRatio(level: 12))
        // 実際の回復量: Lv1 は無敵の猶予だけ、Lv12 は 30%
        for (level, expect) in [(1, T.prideHealLv1), (12, T.prideHealRatio)] {
            var w = SkillWorld()
            let k = addOria(&w, level: level)
            let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
            let maxHP = w.s.units[k].stats.maxHP
            fatal(&w, k, from: e)
            w.run(seconds: 1.6)
            XCTAssertEqual(w.s.units[k].hp, 1 + maxHP * expect, accuracy: maxHP * 0.012, "Lv\(level)")
            XCTAssertTrue(w.s.units[k].isAlive)
        }
    }

    func testHailSlowCutsMovementSpeedByForty() {
        var w = SkillWorld()
        let k = addOria(&w)
        let center = skillArena + Vec2(500, 0)
        let e = w.addDummyEnemy(at: center)
        let before = w.s.units[e].stats.moveSpeed
        XCTAssertTrue(w.cast(k, .skill1, .point(center)))
        w.run(seconds: 0.6)
        XCTAssertEqual(w.s.units[e].stats.moveSpeed, before * 0.6, accuracy: 1e-6)
        w.run(seconds: 1.2)
        XCTAssertNil(status(w, e, .slow, tag: T.s1SlowTag), "1 秒で解ける")
        XCTAssertEqual(w.s.units[e].stats.moveSpeed, before, accuracy: 1e-6)
    }

    func testHailGeometryOnlyHitsInsideTheLandingCircle() {
        var w = SkillWorld()
        let k = addOria(&w)
        let center = skillArena + Vec2(500, 0)
        let inside = w.addDummyEnemy(at: center + Vec2(0, 120))
        let edge = w.addDummyEnemy(at: center + Vec2(215, 0), hero: "H004")
        let outside = w.addDummyEnemy(at: center + Vec2(0, -400), hero: "H005")
        XCTAssertTrue(w.cast(k, .skill1, .point(center)))
        w.run(seconds: 2)
        XCTAssertEqual(damageEvents(w, to: inside, .skill(.skill1)).first.map { $0.amount },
                       w.mitigated(w.numbers(k, .skill1).damage, .magic, on: inside))
        XCTAssertGreaterThanOrEqual(damageEvents(w, to: edge, .skill(.skill1)).count, 1, "縁にも氷塊は届く")
        XCTAssertLessThan(damageEvents(w, to: edge, .skill(.skill1)).count, 1 + T.s1Hails, "縁の相手は雹を全部は受けない")
        XCTAssertEqual(w.damage(to: outside), 0)
        XCTAssertNil(status(w, outside, .slow))
    }

    func testHailAimClampsToRangeAndAutoAimsAtNearbyEnemy() {
        var w = SkillWorld()
        let k = addOria(&w)
        let far = w.addDummyEnemy(at: skillArena + Vec2(1100, 0))
        XCTAssertTrue(w.cast(k, .skill1, .point(skillArena + Vec2(2000, 0))))
        // 射程 650 に丸められるので 1100 先は氷塊の円（650 + 170 + 55 = 875）も、雹の輪（650 + 204 + 85 + 55 ≒ 995）も外
        w.run(seconds: 2)
        XCTAssertEqual(w.damage(to: far), 0)
        XCTAssertEqual(w.castEvents.last?.target.x ?? 0, skillArena.x + 650, accuracy: 1e-6)

        var v = SkillWorld()
        let k2 = addOria(&v)
        let e = v.addDummyEnemy(at: skillArena + Vec2(450, 100))
        XCTAssertTrue(v.cast(k2, .skill1, .none), "自動照準")
        v.run(seconds: 2)
        XCTAssertGreaterThan(v.damage(to: e, from: .skill(.skill1)), 0)
    }

    // MARK: - S2 霜風

    func testBreezeConeHitsAfterDelayAndFreezesOnlyEnemiesFarEnough() throws {
        var w = SkillWorld()
        let k = addOria(&w)
        let far = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        let near = w.addDummyEnemy(at: skillArena + Vec2(120, 0), hero: "H004")
        let side = w.addDummyEnemy(at: skillArena + Vec2(400, 420), hero: "H005")
        let n = w.numbers(k, .skill2)
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        XCTAssertEqual(w.castEvents.last?.archetype, .cone)
        XCTAssertEqual(w.castEvents.last?.shape, .fan)
        XCTAssertEqual(w.castEvents.last?.halfAngle ?? 0, T.s2HalfAngle, accuracy: 1e-12)

        w.run(seconds: 0.2)
        XCTAssertTrue(w.damageEvents.isEmpty, "霜風が広がるまでの遅れがある")
        XCTAssertNil(status(w, far, .stun))
        w.run(seconds: 0.2)   // 0.4 秒
        let hit = damageEvents(w, to: far, .skill(.skill2))
        XCTAssertGreaterThanOrEqual(hit.count, 1)
        XCTAssertEqual(hit[0].amount, w.mitigated(n.damage, .magic, on: far), accuracy: 1e-6)
        let freeze = try XCTUnwrap(status(w, far, .stun, tag: T.freezeTag), "離れた敵は凍結")
        XCTAssertGreaterThan(freeze.remaining, 0.85)
        XCTAssertLessThanOrEqual(freeze.remaining, 1.0)
        XCTAssertFalse(w.s.units[far].canAct)
        // 近すぎる敵はダメージのみ
        XCTAssertGreaterThanOrEqual(damageEvents(w, to: near, .skill(.skill2)).count, 1)
        XCTAssertEqual(damageEvents(w, to: near, .skill(.skill2))[0].amount, w.mitigated(n.damage, .magic, on: near), accuracy: 1e-6)
        XCTAssertNil(status(w, near, .stun), "近距離は凍らない（パッチ 1.8.56）")
        // 扇の外
        XCTAssertEqual(w.damage(to: side), 0)
        // 凍結は 1 秒で解ける
        w.run(seconds: 1.0)
        XCTAssertNil(status(w, far, .stun, tag: T.freezeTag))
        XCTAssertTrue(w.s.units[far].canAct)
        // CC の通知（凍結）
        XCTAssertTrue(w.log.contains { if case .ccApplied(let id, .stun, _) = $0 { return id == w.id(far) } else { return false } })
    }

    func testBreezeFreezeBoundaryAndRangeEdge() {
        var w = SkillWorld()
        let k = addOria(&w)
        // 境界: 距離 200 未満は凍らず、200 以上は凍る（同じ方向に並べず、扇の中で上下に分ける）
        let below = w.addDummyEnemy(at: skillArena + Vec2(190, 30))
        let above = w.addDummyEnemy(at: skillArena + Vec2(201, -30), hero: "H004")
        // 射程の端（650 + 対象半径 55）
        let edgeIn = w.addDummyEnemy(at: skillArena + Vec2(690, 0), hero: "H005")
        let edgeOut = w.addDummyEnemy(at: skillArena + Vec2(740, 200), hero: "H006")
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 0.4)
        XCTAssertGreaterThan(w.damage(to: below), 0)
        XCTAssertNil(status(w, below, .stun))
        XCTAssertNotNil(status(w, above, .stun, tag: T.freezeTag))
        XCTAssertGreaterThan(w.damage(to: edgeIn, from: .skill(.skill2)), 0)
        XCTAssertNotNil(status(w, edgeIn, .stun))
        XCTAssertEqual(w.damage(to: edgeOut), 0)
    }

    func testBreezePatchAtTheFarEndDealsItsTotalInFourTicks() {
        var w = SkillWorld()
        let k = addOria(&w)
        // 扇の外（射程 650 + 55 の先）だが凍った地面（中心 540・半径 190 + 55）には入る
        let patchOnly = w.addDummyEnemy(at: skillArena + Vec2(730, 0))
        let n = w.numbers(k, .skill2)
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 3)
        let ticks = damageEvents(w, to: patchOnly, .skill(.skill2))
        XCTAssertEqual(ticks.count, T.s2PatchTicks)
        let total = Kit_H031.patchTotal(n)
        for d in ticks { XCTAssertEqual(d.amount, w.mitigated(total / Double(T.s2PatchTicks), .magic, on: patchOnly), accuracy: 1e-6) }
        XCTAssertNil(status(w, patchOnly, .stun), "扇の外は凍らない")
        // 凍った地面の持続は 1.8 秒（0.3 秒の遅れのあと）
        XCTAssertTrue(w.s.zones.allSatisfy { $0.done })

        // 扇の中の凍結した敵は、霜風 + 地面の合計を受ける
        var v = SkillWorld()
        let k2 = addOria(&v)
        let e = v.addDummyEnemy(at: skillArena + Vec2(450, 0))
        let n2 = v.numbers(k2, .skill2)
        XCTAssertTrue(v.cast(k2, .skill2, .direction(Self.east)))
        v.run(seconds: 3)
        XCTAssertEqual(v.damage(to: e), v.mitigated(n2.damage + Kit_H031.patchTotal(n2), .magic, on: e), accuracy: 1e-5)
    }

    func testBreezeFreezeStopsAttacksAndCasts() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(450, 0), hero: "H004")
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 0.4)
        XCTAssertTrue(w.s.units[e].has(.stun))
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: e, slot: .skill1), "凍結中は撃てない")
    }

    // MARK: - 奥義

    func testUltimatePathSlowsThenGlacierShattersAndFreezes() throws {
        var w = SkillWorld()
        let k = addOria(&w)
        let onPath = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        let sideInArea = w.addDummyEnemy(at: skillArena + Vec2(450, 250), hero: "H004")
        let farSide = w.addDummyEnemy(at: skillArena + Vec2(450, 520), hero: "H005")
        let behind = w.addDummyEnemy(at: skillArena + Vec2(-250, 0), hero: "H006")
        let n = w.numbers(k, .ultimate)
        let shatter = Kit_H031.shatterDamage(n)
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        XCTAssertEqual(w.castEvents.last?.archetype, .piercingLine)
        XCTAssertEqual(w.castEvents.last?.shape, .wideLine)
        XCTAssertEqual(w.castEvents.last?.duration ?? 0, T.ultGlacierDelay, accuracy: 1e-12)

        // 氷の道: 小さなダメージと 80% の鈍足
        w.run(seconds: 0.4)
        let path = damageEvents(w, to: onPath, .skill(.ultimate))
        XCTAssertEqual(path.count, 1)
        XCTAssertEqual(path[0].amount, w.mitigated(n.damage, .magic, on: onPath), accuracy: 1e-6)
        let slow = try XCTUnwrap(status(w, onPath, .slow, tag: T.pathSlowTag))
        XCTAssertEqual(slow.magnitude, 0.8, accuracy: 1e-12)
        XCTAssertGreaterThan(slow.remaining, 0.8)
        XCTAssertEqual(w.damage(to: sideInArea), 0, "道の外（幅 120 + 55 の外）は鈍足も無い")
        XCTAssertNil(status(w, sideInArea, .slow))

        // 砕ける前
        w.run(seconds: 0.7)   // 1.1 秒
        XCTAssertEqual(damageEvents(w, to: onPath, .skill(.ultimate)).count, 1)
        XCTAssertNil(status(w, onPath, .stun))
        // 砕ける（1.2 秒）
        w.run(seconds: 0.2)   // 1.3 秒
        for e in [onPath, sideInArea] {
            let hits = damageEvents(w, to: e, .skill(.ultimate))
            XCTAssertEqual(hits.last?.amount ?? 0, w.mitigated(shatter, .magic, on: e), accuracy: 1e-6)
            let freeze = try XCTUnwrap(status(w, e, .stun, tag: T.freezeTag))
            XCTAssertGreaterThan(freeze.remaining, 0.85)
            XCTAssertLessThanOrEqual(freeze.remaining, 1.0)
            XCTAssertFalse(w.s.units[e].canAct)
        }
        XCTAssertEqual(w.damage(to: farSide), 0)
        XCTAssertEqual(w.damage(to: behind), 0)
        // 1 秒後に解ける
        w.run(seconds: 1.2)
        XCTAssertTrue(w.s.units[onPath].canAct)
        XCTAssertTrue(w.s.units[sideInArea].canAct)
        // 道 + 砕け
        XCTAssertEqual(w.damage(to: onPath), w.mitigated(n.damage + shatter, .magic, on: onPath), accuracy: 1e-5)
    }

    func testUltimateFreezeIsLongerWithAbilityPowerAtCast() throws {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        w.s.units[k].stats.abilityPower = 250
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.s.units[k].stats.abilityPower = 0   // 砕けるまでに魔力が変わっても、撃った時点の値
        w.run(seconds: 1.3)
        let freeze = try XCTUnwrap(status(w, e, .stun, tag: T.freezeTag))
        XCTAssertGreaterThan(freeze.remaining, 1.35)
        XCTAssertLessThanOrEqual(freeze.remaining, 1.5)
    }

    func testUltimateDoesNotFreezeCCImmuneOrInvulnerableTargets() {
        var w = SkillWorld()
        let k = addOria(&w)
        let immune = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        let guarded = w.addDummyEnemy(at: skillArena + Vec2(450, 150), hero: "H004")
        CombatSystem.addStatus(&w.s, targetIndex: immune, StatusEffect(kind: .ccImmune, duration: 5))
        CombatSystem.addStatus(&w.s, targetIndex: guarded, StatusEffect(kind: .invulnerable, duration: 5))
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.run(seconds: 1.4)
        XCTAssertNil(status(w, immune, .stun))
        XCTAssertNil(status(w, immune, .slow))
        XCTAssertGreaterThan(w.damage(to: immune), 0, "ダメージは入る")
        XCTAssertEqual(w.damage(to: guarded), 0)
        XCTAssertNil(status(w, guarded, .stun))
    }

    func testUltimateOnlyReachesEnemiesNotAllies() {
        var w = SkillWorld()
        let k = addOria(&w)
        let ally = w.addHero("H004", team: .blue, at: skillArena + Vec2(300, 0))
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.run(seconds: 1.4)
        XCTAssertEqual(w.damage(to: ally), 0)
        XCTAssertGreaterThan(w.damage(to: e), 0)
    }

    // MARK: - パッシブ（氷の誇り）

    func testFatalDamageIsNegatedAndFreezesTheOwnerInvulnerably() throws {
        var w = SkillWorld()
        let k = addOria(&w, level: 12)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        let maxHP = w.s.units[k].stats.maxHP
        fatal(&w, k, from: e)
        XCTAssertTrue(w.s.units[k].isAlive)
        XCTAssertEqual(w.s.units[k].hp, 1, accuracy: 1e-9)
        XCTAssertTrue(w.s.pendingDeaths.isEmpty)
        XCTAssertEqual(w.kit(k).oriaSaves, 1)
        XCTAssertEqual(w.kit(k).oriaPrideCooldown, 150, accuracy: 1e-9)
        XCTAssertTrue(w.s.units[k].has(.invulnerable))
        XCTAssertTrue(w.s.units[k].has(.suppress))
        XCTAssertFalse(w.s.units[k].canAct, "凍結中は行動できない")
        XCTAssertTrue(w.damageEvents.filter { $0.targetID == w.id(k) }.isEmpty, "無効にしたダメージは通らない")
        // 凍結中の追加ダメージも通らない
        fatal(&w, k, from: e)
        XCTAssertEqual(w.s.units[k].hp, 1, accuracy: 1e-9)
        XCTAssertFalse(w.cast(k, .skill1, .direction(Self.east)), "凍結中は撃てない")
        // 凍結の弱体は（無敵なので）新たに付かない
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 2, sourceID: w.id(e)))
        XCTAssertNil(status(w, k, .stun))

        // 1.5 秒かけて最大 HP の 30% を回復する（自然回復の分だけ多少の誤差）
        w.run(seconds: 0.75)
        let half = w.s.units[k].hp
        XCTAssertEqual(half - 1, maxHP * 0.30 * 0.5, accuracy: maxHP * 0.01)
        XCTAssertGreaterThan(w.kit(k).oriaFreezeLeft, 0)
        w.run(seconds: 0.85)
        XCTAssertEqual(w.s.units[k].hp, 1 + maxHP * 0.30, accuracy: maxHP * 0.01)
        XCTAssertEqual(w.kit(k).oriaHealTicks, 0)
        XCTAssertFalse(w.s.units[k].has(.invulnerable), "1.5 秒で解ける")
        XCTAssertFalse(w.s.units[k].has(.suppress))
        XCTAssertTrue(w.s.units[k].canAct)
        XCTAssertEqual(w.kit(k).oriaFreezeLeft, 0)
        // 回復は 30% で止まる（以降は自然回復だけ）
        let afterFreeze = w.s.units[k].hp
        w.run(seconds: 1)
        XCTAssertLessThan(w.s.units[k].hp - afterFreeze, maxHP * 0.02)
    }

    func testPrideDoesNotTriggerOnSurvivableHitsAndCountsShieldsAsHealth() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        let hp = w.s.units[k].hp
        // 倒れない量
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: hp - 1, type: .trueDamage, source: .spell)
        XCTAssertEqual(w.kit(k).oriaSaves, 0)
        XCTAssertGreaterThan(w.s.units[k].hp, 0)
        XCTAssertEqual(w.kit(k).oriaPrideCooldown, 0)
        // シールドで受けきれる量は致命傷ではない
        CombatSystem.addShield(&w.s, w.ctx, sourceID: w.id(k), targetIndex: k, amount: 500, duration: 5)
        let remaining = w.s.units[k].hp
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: remaining + 400, type: .trueDamage, source: .spell)
        XCTAssertEqual(w.kit(k).oriaSaves, 0)
        XCTAssertTrue(w.s.units[k].isAlive)
        // シールドを超える致命傷は無効（シールドは失う）
        CombatSystem.addShield(&w.s, w.ctx, sourceID: w.id(k), targetIndex: k, amount: 300, duration: 5)
        let hp2 = w.s.units[k].hp
        let cover = w.s.units[k].totalShield
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: hp2 + cover + 1, type: .trueDamage, source: .spell)
        XCTAssertEqual(w.kit(k).oriaSaves, 1)
        XCTAssertTrue(w.s.units[k].shields.isEmpty)
        XCTAssertEqual(w.s.units[k].hp, 1, accuracy: 1e-9)
    }

    func testPrideIsOnA150SecondCooldownAndSecondFatalBlowKills() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        fatal(&w, k, from: e)
        w.run(seconds: 2)   // 凍結が解ける
        XCTAssertTrue(w.s.units[k].canAct)
        XCTAssertEqual(w.kit(k).oriaPrideCooldown, 148, accuracy: 0.1)
        // クールダウン中の致命傷では倒れる
        fatal(&w, k, from: e)
        XCTAssertFalse(w.s.units[k].isAlive)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertEqual(w.kit(k).oriaSaves, 0, "死亡で全リセット")
        XCTAssertEqual(w.kit(k).oriaPrideCooldown, 148, accuracy: 0.1, "再発動までの残りは死亡しても残る")
        XCTAssertTrue(w.s.units[k].hero!.isDead)

        // 150 秒後には再び働く
        var v = SkillWorld()
        let k2 = addOria(&v)
        let e2 = v.addDummyEnemy(at: skillArena + Vec2(400, 0))
        fatal(&v, k2, from: e2)
        v.run(seconds: 151)
        XCTAssertEqual(v.kit(k2).oriaPrideCooldown, 0, accuracy: 1e-9)
        v.s.units[k2].hp = v.s.units[k2].stats.maxHP
        fatal(&v, k2, from: e2)
        XCTAssertTrue(v.s.units[k2].isAlive)
        XCTAssertEqual(v.kit(k2).oriaSaves, 2)
    }

    func testPrideTriggersBeforeTheImmortalItem() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        w.s.units[k].hero!.items = ["EQ053"]
        w.s.units[k].hero!.itemInvested = [1000]
        StatCalculator.recompute(&w.s, k, w.ctx)
        w.s.units[k].hp = w.s.units[k].stats.maxHP
        XCTAssertTrue(w.s.units[k].hero!.itemRuntime.ready(.immortal, at: w.s.time))
        fatal(&w, k, from: e)
        XCTAssertEqual(w.kit(k).oriaSaves, 1)
        XCTAssertTrue(w.s.units[k].hero!.itemRuntime.ready(.immortal, at: w.s.time), "氷の誇りが先に働き、装備は残る")
        XCTAssertEqual(w.s.units[k].hp, 1, accuracy: 1e-9)
        // 氷の誇りが再使用待ちなら、装備が働く
        w.run(seconds: 2)
        w.s.units[k].hp = 5
        fatal(&w, k, from: e)
        XCTAssertTrue(w.s.units[k].isAlive)
        XCTAssertFalse(w.s.units[k].hero!.itemRuntime.ready(.immortal, at: w.s.time))
        XCTAssertEqual(w.kit(k).oriaSaves, 1)
    }

    func testPrideNeverFiresForEnemiesWithoutTheKitAndReplacesTheGenericArcanistPassive() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(450, 0), hero: "H004")
        XCTAssertNil(w.s.units[e].hero?.kit)
        // 汎用アルカニストの「スキル命中で他スキルの CD −0.6 秒」は無い
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        let cdAfterCast = w.s.units[k].hero!.cooldown(.skill2)
        XCTAssertTrue(w.cast(k, .skill1, .point(skillArena + Vec2(450, 0))))
        w.run(seconds: 0.6)
        XCTAssertGreaterThan(w.damage(to: e, from: .skill(.skill1)), 0)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), cdAfterCast - 0.6, accuracy: 0.1,
                       "経過した時間だけ減る（命中による短縮は無い）")
        // 敵側は致命傷で普通に倒れる
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(k), targetIndex: e, amount: 1e9, type: .trueDamage, source: .spell)
        XCTAssertFalse(w.s.units[e].isAlive)
    }

    func testPrideBadgeShowsFreezeThenCooldownThenReady() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        var b = HeroKits.badge(w.s.units[k].hero!, slot: .passive)
        XCTAssertEqual(b?.kind, .stacks)
        XCTAssertEqual(b?.value, 1)
        fatal(&w, k, from: e)
        b = HeroKits.badge(w.s.units[k].hero!, slot: .passive)
        XCTAssertEqual(b?.kind, .timer)
        XCTAssertEqual(b?.total, 1.5)
        w.run(seconds: 2)
        b = HeroKits.badge(w.s.units[k].hero!, slot: .passive)
        XCTAssertEqual(b?.kind, .timer)
        XCTAssertEqual(b?.total, 150)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .skill1))
    }

    // MARK: - 端の場合

    func testNoTargetCastsStillSpendButNothingBreaks() {
        var w = SkillWorld()
        let k = addOria(&w)
        for slot in SkillSlot.actives {
            let before = w.s.units[k].resource
            XCTAssertTrue(w.cast(k, slot, .none), "\(slot)")
            XCTAssertLessThan(w.s.units[k].resource, before)
            XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(slot), 0)
        }
        w.run(seconds: 3)
        XCTAssertTrue(w.damageEvents.isEmpty)
        XCTAssertTrue(w.s.projectiles.allSatisfy { $0.done })
    }

    func testCastBlockedWhileStunnedAndSilencedAndPracticeHasNoCooldowns() {
        var w = SkillWorld()
        let k = addOria(&w)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 0.5))
        for slot in SkillSlot.actives { XCTAssertFalse(w.cast(k, slot, .none), "\(slot)") }
        w.run(seconds: 0.6)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .silence, duration: 0.5))
        for slot in SkillSlot.actives { XCTAssertFalse(w.cast(k, slot, .none), "\(slot)") }
        XCTAssertTrue(w.damageEvents.isEmpty)

        var p = SkillWorld(noCooldowns: true)
        let pk = addOria(&p)
        let e = p.addDummyEnemy(at: skillArena + Vec2(400, 0))
        for slot in SkillSlot.actives {
            XCTAssertTrue(p.cast(pk, slot, .direction(Self.east)), "\(slot)")
            XCTAssertEqual(p.s.units[pk].hero!.cooldown(slot), 0, "練習場は CD なし")
        }
        XCTAssertEqual(p.s.units[pk].resource, p.s.units[pk].stats.maxResource, accuracy: 1e-9, "コストも無し")
        p.run(seconds: 2)
        XCTAssertGreaterThan(p.damage(to: e), 0)
        // 練習場では氷の誇りも再発動待ちにならない
        let e2 = p.addDummyEnemy(at: skillArena + Vec2(0, 400), hero: "H004")
        fatal(&p, pk, from: e2)
        XCTAssertEqual(p.kit(pk).oriaSaves, 1)
        XCTAssertEqual(p.kit(pk).oriaPrideCooldown, 0)
        p.run(seconds: 2)
        fatal(&p, pk, from: e2)
        XCTAssertEqual(p.kit(pk).oriaSaves, 2)
        XCTAssertTrue(p.s.units[pk].isAlive)
    }

    func testStunAfterCastDoesNotCancelTheFallingIceAndFrostPatch() {
        var w = SkillWorld()
        let k = addOria(&w)
        // 氷塊の中心から雹の輪（0.9 倍）の位置 = k = 0 の雹が降る場所に立つ
        let center = skillArena + Vec2(450, 0)
        let e = w.addDummyEnemy(at: center + Vec2(T.s1Radius * T.hailRingInner, 0))
        XCTAssertTrue(w.cast(k, .skill1, .point(center)))
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.tick(2)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1.5))
        w.run(seconds: 2.5)
        let s1 = damageEvents(w, to: e, .skill(.skill1))
        XCTAssertEqual(s1.count, 2, "撃った氷塊と雹はスタンでは消えない（氷塊 + 立っている場所に降る雹 1 発）")
        XCTAssertFalse(damageEvents(w, to: e, .skill(.skill2)).isEmpty)
        XCTAssertFalse(damageEvents(w, to: e, .skill(.ultimate)).isEmpty)
    }

    func testDeathAfterCastLetsTheGlacierShatterButResetsTheKit() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(450, 0))
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.tick(2)
        let origin = w.kit(k).oriaBreezeOrigin
        w.s.units[k].hero!.kit!.oriaPrideCooldown = 40   // 氷の誇りは待機中
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage, source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        XCTAssertEqual(w.kit(k).oriaSaves, 0)
        XCTAssertEqual(w.kit(k).oriaPrideCooldown, 40, "再発動までの残りは残る")
        XCTAssertEqual(w.kit(k).oriaBreezeOrigin, origin, "遅れて当たる霜風の起点は残る（凍結の判定が壊れない）")
        w.run(seconds: 1.3)
        // 撃った後の氷は術者が倒れても残る（霜風の凍結も、氷河の砕けも）
        XCTAssertFalse(damageEvents(w, to: e, .skill(.skill2)).isEmpty)
        XCTAssertFalse(damageEvents(w, to: e, .skill(.ultimate)).isEmpty)
        XCTAssertNotNil(status(w, e, .stun, tag: T.freezeTag), "氷河の凍結")
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: k, slot: .skill1))
        XCTAssertFalse(w.cast(k, .skill1, .direction(Self.east)), "死亡中は撃てない")
    }

    func testDeathDuringSelfFreezeCannotHappenBecauseOfInvulnerability() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        fatal(&w, k, from: e)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage, source: .fountain)
        XCTAssertTrue(w.s.units[k].isAlive)
        w.run(seconds: 1.0)
        XCTAssertTrue(w.s.units[k].isAlive)
    }

    func testManaCostAndCooldownFollowTheMasterCostAndKitCooldown() {
        var w = SkillWorld()
        let k = addOria(&w)
        for slot in SkillSlot.actives {
            let sk = skill(slot)
            let n = w.numbers(k, slot)
            let before = w.s.units[k].resource
            XCTAssertTrue(w.cast(k, slot, .direction(Self.east)))
            XCTAssertEqual(before - w.s.units[k].resource, sk.cost, accuracy: 1e-9, "コストはマスターデータのまま")
            XCTAssertEqual(w.s.units[k].hero!.cooldown(slot), n.cooldown, accuracy: 1e-9)
            XCTAssertFalse(w.cast(k, slot, .direction(Self.east)), "CD 中")
        }
    }

    // MARK: - 決定性

    private func script(_ w: inout SkillWorld, k: Int, step: Int) {
        switch step {
        case 0: w.cast(k, .skill1, .point(skillArena + Vec2(500, 0)))
        case 1: w.cast(k, .skill2, .direction(Self.east))
        case 2: w.cast(k, .ultimate, .direction(Self.east))
        case 3: w.s.units[k].attackTargetID = w.s.units.first { $0.team == .red && $0.kind == .hero }?.id
        case 5:
            // 氷の誇りを一度働かせる
            if let e = w.s.units.firstIndex(where: { $0.team == .red && $0.kind == .hero }) {
                CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                         source: .spell)
            }
        default: break
        }
    }

    private func makeScriptWorld() -> (SkillWorld, Int) {
        var w = SkillWorld()
        let k = addOria(&w, ranks: [2, 2, 2])
        w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        w.addDummyEnemy(at: skillArena + Vec2(520, 150), hero: "H004")
        w.addMinion(team: .red, at: skillArena + Vec2(700, 40))
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
        runScript(&a, k: ka, from: 0, to: 12)
        runScript(&b, k: kb, from: 0, to: 12)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(a.s.units, b.s.units)
        XCTAssertEqual(a.log, b.log)
        XCTAssertEqual(a.kit(ka).oriaSaves, 1, "台本が氷の誇りまで通っている")
        for slot in SkillSlot.actives {
            XCTAssertFalse(a.damageEvents.filter { $0.source == .skill(slot) }.isEmpty, "\(slot)")
        }
    }

    func testJSONRoundTripMidUltimateAndMidFreezeResumesIdentically() throws {
        var (a, ka) = makeScriptWorld()
        runScript(&a, k: ka, from: 0, to: 12)

        var (b, kb) = makeScriptWorld()
        runScript(&b, k: kb, from: 0, to: 3)
        // 途中（氷の道は飛翔中・氷河は育成中・霜の地面も生きている）: 奥義を撃った直後
        script(&b, k: kb, step: 2)
        b.tick(4)
        XCTAssertTrue(b.s.zones.contains { !$0.done && !$0.triggered }, "氷河の予告中にシリアライズする")
        let data = try JSONEncoder().encode(b.s)
        var resumed = b
        resumed.s = try JSONDecoder().decode(SimState.self, from: data)
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.s.zones, b.s.zones)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        b.run(seconds: 0.45 - 4 * Balance.dt)
        resumed.run(seconds: 0.45 - 4 * Balance.dt)
        runScript(&b, k: kb, from: 3, to: 12)
        runScript(&resumed, k: kb, from: 3, to: 12)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.s.zones, b.s.zones)
        XCTAssertEqual(resumed.s.projectiles, b.s.projectiles)
        XCTAssertEqual(resumed.log.count, b.log.count)
        _ = a.s

        // 凍結中（回復の tick が残っている）でも同じ
        var c = SkillWorld()
        let kc = addOria(&c)
        let ec = c.addDummyEnemy(at: skillArena + Vec2(400, 0))
        fatal(&c, kc, from: ec)
        c.tick(10)
        XCTAssertGreaterThan(c.kit(kc).oriaHealTicks, 0)
        var d = c
        d.s = try JSONDecoder().decode(SimState.self, from: try JSONEncoder().encode(c.s))
        XCTAssertEqual(d.s.stateHash(), c.s.stateHash())
        c.run(seconds: 2)
        d.run(seconds: 2)
        XCTAssertEqual(d.s.stateHash(), c.s.stateHash())
        XCTAssertEqual(d.s.units[kc].hp, c.s.units[kc].hp)
    }

    func testStateHashSeesPrideAndBreezeState() {
        var (a, ka) = makeScriptWorld()
        var (b, kb) = makeScriptWorld()
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        b.s.units[kb].hero!.kit!.oriaPrideCooldown = 10
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash())
        b.s.units[kb].hero!.kit!.oriaPrideCooldown = 0
        a.s.units[ka].hero!.kit!.oriaBreezeOrigin = Vec2(1, 2)
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash())
    }

    // MARK: - ボットの煙テスト

    /// 標準マップのボット戦で、青のアルカニスト枠をオーリアに置き換える。
    private func botConfig(seed: UInt64) -> MatchConfig {
        var cfg = MatchFactory.botMatch(seed: seed)
        let pos = MatchFactory.defaultPosition(for: .arcanist)
        for j in cfg.players.indices where cfg.players[j].heroID == "H031" { cfg.players[j].heroID = "H004" }
        if let idx = cfg.players.firstIndex(where: { $0.team == .blue && $0.position == pos }) {
            cfg.players[idx].heroID = "H031"
            cfg.players[idx].displayName = "Oria_AI"
        }
        return cfg
    }

    func testBotPlaysOriaForThreeMinutesWithAllSlotsAndSaneState() throws {
        var casts: [SkillSlot: Int] = [:]
        var skillDamage: [SkillSlot: Double] = [:]
        var found = false
        var pride = 0
        for seed in [UInt64(11), 12, 13, 14, 15] {
            let sim = Simulation(config: botConfig(seed: seed))
            guard let oi = sim.state.heroIndices.first(where: { sim.state.units[$0].hero?.heroID == "H031" }) else {
                continue
            }
            found = true
            let oriaID = sim.state.units[oi].id
            XCTAssertNotNil(sim.state.units[oi].hero?.kit, "ボットのオーリアにも KitState が付く")
            casts = [:]
            skillDamage = [:]
            pride = 0
            while !sim.isEnded && sim.state.time < 240 {
                // 奥義は「倒せる / 2 体以上を巻き込む」ときだけ撃つ AI で、試合の流れ次第では出ない。
                // 120 秒以降は 20 秒おきに自動照準で S2・奥義を撃たせ、霜風・氷河の状態遷移も通す（S1 は AI の判断のまま）
                var commands: [HeroCommand] = []
                if sim.state.time >= 120, sim.state.tick % 600 == 0 {
                    commands.append(HeroCommand(heroID: oriaID, command: .castSkill(slot: .ultimate, target: .none)))
                } else if sim.state.time >= 120, sim.state.tick % 600 == 300 {
                    commands.append(HeroCommand(heroID: oriaID, command: .castSkill(slot: .skill2, target: .none)))
                }
                for e in sim.step(commands: commands) {
                    switch e {
                    case .skillCast(let c) where c.casterID == oriaID:
                        casts[c.slot, default: 0] += 1
                    case .damage(let d) where d.sourceID == oriaID:
                        if case .skill(let slot) = d.source { skillDamage[slot, default: 0] += d.amount }
                    default:
                        break
                    }
                }
                guard let i = sim.state.index(of: oriaID) else { break }
                let u = sim.state.units[i]
                XCTAssertTrue(u.hp.isFinite && u.pos.x.isFinite && u.pos.y.isFinite && u.resource.isFinite)
                XCTAssertGreaterThanOrEqual(u.resource, 0)
                if let k = u.hero?.kit {
                    XCTAssertTrue(k.timers.allSatisfy { $0 >= 0 && $0.isFinite })
                    XCTAssertTrue(k.reals.allSatisfy { $0.isFinite })
                    XCTAssertTrue(k.windows.allSatisfy { !$0.isOpen }, "再使用の窓は使わない")
                    XCTAssertTrue(k.scheduled.isEmpty, "遅延タイマーは使わない")
                    XCTAssertNil(k.sweep)
                    pride = max(pride, k.oriaSaves)
                }
            }
            if casts[.skill1, default: 0] > 0, casts[.skill2, default: 0] > 0, casts[.ultimate, default: 0] > 0 { break }
        }
        XCTAssertTrue(found)
        XCTAssertGreaterThan(casts[.skill1, default: 0], 0, "S1: \(casts)")
        XCTAssertGreaterThan(casts[.skill2, default: 0], 0, "S2: \(casts)")
        XCTAssertGreaterThan(casts[.ultimate, default: 0], 0, "奥義: \(casts)")
        XCTAssertGreaterThan(skillDamage[.skill1, default: 0], 0)
        XCTAssertGreaterThan(skillDamage[.skill2, default: 0], 0)
        print("H031 bot smoke: casts \(casts) skillDamage \(skillDamage) pride \(pride)")
    }

    // MARK: - 1v1 の TTK（ロール代表との総当たり）

    func testDuelTimeToKillAgainstRoleRepresentativesStaysInBand() {
        var failures: [String] = []
        for level in SkillBalanceTests.levels {
            for foe in SkillBalanceTests.representatives {
                let r = SkillBalanceTests.duel("H031", foe, level: level)
                print(String(format: "H031 duel Lv%d vs %@: %.1f s winner=%@ hp=%.2f", level, foe, r.ttk, r.winnerIsA.map { $0 ? "H031" : foe } ?? "-", r.remainingHPRatio))
                if r.ttk < SkillBalanceTests.minTTK || r.ttk > SkillBalanceTests.maxTTK {
                    failures.append(String(format: "Lv%d H031 vs %@: %.2f s", level, foe, r.ttk))
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures)")
    }

    /// 診断: 全 34 ヒーローとの 1v1 の勝率（H031 と、汎用のアルカニスト H004/H010/H016/H022 を同じ場で比べる）。Release のみ。
    func testRoundRobinWinRateNextToGenericArcanists() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter Kit_H031Tests/testRoundRobin")
        #else
        let ids = MasterData.shared.heroes.map(\.heroID)
        for level in SkillBalanceTests.levels {
            var line = "Lv\(level) win rate:"
            for hero in ["H031", "H004", "H010", "H016", "H022"] {
                var wins = 0.0, games = 0.0
                for foe in ids where foe != hero {
                    // 先手・後手の偏りを避けるため、双方向で戦わせる
                    let r1 = SkillBalanceTests.duel(hero, foe, level: level)
                    let r2 = SkillBalanceTests.duel(foe, hero, level: level)
                    wins += (r1.winnerIsA == true ? 1 : 0) + (r2.winnerIsA == false ? 1 : 0)
                    games += 2
                }
                line += String(format: " %@ %.1f%%", hero, wins / games * 100)
            }
            print(line)
        }
        #endif
    }
}
