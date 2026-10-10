import XCTest
@testable import VelstriaCore

/// H030 星砲のライナ（MLBB ライラの Velstria 版）のキット。docs/kits/Layla.md の対応表と同じ並びで検査する。
/// キットは HeroKits.testOverride に有効な Kit_H030 を差して試す（本番の有効化とは独立。有効化後も同じ結果）。
final class Kit_H030Tests: XCTestCase {
    typealias T = RainaTuning
    static let east = Vec2(1, 0)

    override func setUp() {
        super.setUp()
        HeroKits.testOverride = [Kit_H030(isReady: true)]
    }

    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    // MARK: - 土台

    @discardableResult
    private func addRaina(_ w: inout SkillWorld, ranks: [Int]? = [1, 1, 1], at pos: Vec2 = skillArena) -> Int {
        w.addHero("H030", team: .blue, at: pos, ranks: ranks, facing: 0)
    }

    private func distanceMultiplier(_ d: Double) -> Double {
        1 + T.maxDistanceBonus * min(1, max(0, d / T.farDistance))
    }

    private var def: HeroDef { MasterData.shared.hero("H030")! }

    private func skill(_ slot: SkillSlot) -> SkillDef { MasterData.shared.skill(hero: "H030", slot: slot)! }

    /// 対象に刻印を付ける（所有者 = ライナ）。
    private func mark(_ w: inout SkillWorld, owner k: Int, on e: Int, duration: Double = T.markDuration) {
        Kit.addMark(&w.s, target: e, ownerID: w.id(k), tag: KitTags.mark("H030", T.markName, owner: w.id(k)),
                    maxStacks: 1, duration: duration)
    }

    private func markStacks(_ w: SkillWorld, owner k: Int, on e: Int) -> Int {
        Kit.markStacks(w.s, target: e, tag: KitTags.mark("H030", T.markName, owner: w.id(k)))
    }

    private func damageEvents(_ w: SkillWorld, to e: Int, _ source: DamageSource) -> [DamageEvent] {
        w.damageEvents.filter { $0.targetID == w.id(e) && $0.source == source }
    }

    // MARK: - レジストリ・照準

    func testRegistryTargetingAndTextPerSlot() throws {
        XCTAssertTrue(HeroKits.hasKit("H030"))
        XCTAssertNotNil(HeroKits.kit(for: "H030"))
        // 本番のレジストリでも有効（テストの差し込み無しで引ける）
        XCTAssertTrue(Kit_H030().isReady)
        HeroKits.testOverride = []
        XCTAssertTrue(HeroKits.hasKit("H030"))
        HeroKits.testOverride = [Kit_H030(isReady: true)]

        let m = MasterData.shared
        let t1 = SkillCatalog.targeting(for: skill(.skill1), hero: def)
        XCTAssertEqual(t1.archetype, .lineSkillshot)
        XCTAssertEqual(t1.aim, .direction)
        XCTAssertEqual(t1.range, 650)
        XCTAssertEqual(t1.reach, 650)
        XCTAssertEqual(t1.shape, .auto)

        let t2 = SkillCatalog.targeting(for: skill(.skill2), hero: def)
        XCTAssertEqual(t2.archetype, .lineSkillshot, "ブリンク強化ではなく爆発する弾")
        XCTAssertEqual(t2.aim, .direction)
        XCTAssertEqual(t2.range, 650)
        XCTAssertEqual(t2.radius, T.s2Width)
        XCTAssertEqual(t2.reach, 650)

        let t3 = SkillCatalog.targeting(for: skill(.ultimate), hero: def)
        XCTAssertEqual(t3.archetype, .piercingLine)
        XCTAssertEqual(t3.aim, .direction)
        XCTAssertEqual(t3.range, 2000)
        XCTAssertEqual(t3.radius, skill(.ultimate).radius)
        XCTAssertEqual(t3.shape, .wideLine)
        XCTAssertEqual(t3.reach, 2000)

        XCTAssertEqual(SkillCatalog.targeting(for: skill(.passive), hero: def).archetype, .passive)

        // 説明文: 4 スロットとも ja/en があり、テンプレートの語が全部埋まる
        let stats = HeroGrowth.baseStats(def: def, level: 6)
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H030", slot: slot), "\(slot)")
            let sk = m.skill(hero: "H030", slot: slot)!
            let n = SkillCatalog.numbers(for: sk, hero: def, rank: 1, stats: stats)
            let t = SkillCatalog.targeting(for: sk, hero: def)
            for english in [false, true] {
                let filled = text.filled(english: english, numbers: n, targeting: t)
                XCTAssertFalse(filled.contains("{"), "\(slot) \(english): \(filled)")
                XCTAssertFalse(filled.isEmpty)
            }
        }
        // 数値は sim の値と一致する（公式の文の構造: {base}(+{atkPct}%物理攻撃)）
        let n1 = SkillCatalog.numbers(for: skill(.skill1), hero: def, rank: 1, stats: stats)
        let base1 = try XCTUnwrap(n1.extras.first { $0.key == "base" }).value
        let pct1 = try XCTUnwrap(n1.extras.first { $0.key == "atkPct" }).value
        XCTAssertTrue(HeroKits.text(heroID: "H030", slot: .skill1)!
            .filled(english: false, numbers: n1, targeting: t1).contains("\(Int(base1))(+\(Int(pct1))%物理攻撃)の物理ダメージ"))
        let n2 = SkillCatalog.numbers(for: skill(.skill2), hero: def, rank: 1, stats: stats)
        let detBase = try XCTUnwrap(n2.extras.first { $0.key == "detBase" })
        XCTAssertTrue(HeroKits.text(heroID: "H030", slot: .skill2)!
            .filled(english: true, numbers: n2, targeting: t2).contains("\(Int(detBase.value)) (+"))
        let nu = SkillCatalog.numbers(for: skill(.ultimate), hero: def, rank: 1, stats: stats)
        let ju = HeroKits.text(heroID: "H030", slot: .ultimate)!.filled(english: false, numbers: nu, targeting: t3)
        XCTAssertTrue(ju.contains("パッシブ：") && ju.contains("最大180"), ju)
    }

    func testTagsFollowTheOfficialSkillTags() {
        // 日本語クライアント: バフ / 爆発力・バフ / 範囲技・妨害 / 爆発力・バフ（Fandom の S2「AoE・Slowed」とは違う）
        XCTAssertEqual(HeroKits.tags(heroID: "H030", slot: .passive), ["buff"])
        XCTAssertEqual(HeroKits.tags(heroID: "H030", slot: .skill1), ["burst", "buff"])
        XCTAssertEqual(HeroKits.tags(heroID: "H030", slot: .skill2), ["aoe", "disrupt"])
        XCTAssertEqual(HeroKits.tags(heroID: "H030", slot: .ultimate), ["burst", "buff"])
        for slot in SkillSlot.allCases {
            for tag in HeroKits.tags(heroID: "H030", slot: slot) { XCTAssertTrue(KitTag.all.contains(tag), tag) }
        }
    }

    // MARK: - 数値（公式の表）

    func testDamageCooldownAndManaFollowTheOfficialTables() throws {
        // 公式のダメージ: (基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率 × 換算。基礎は Lv1 → Lv6 をランクで線形補間
        // （スキル1・2 は 4 ランク = rank r → Lv 1 + (r − 1) × 5 / 3。アルティメットの 3 ランクは公式の Lv そのまま）
        for level in [1, 6, 12] {
            let stats = HeroGrowth.baseStats(def: def, level: level)
            let atk = stats.attack * Balance.skillAttackScalingFactor
            let cdr = 1 - min(0.4, stats.cooldownReduction)
            for rank in 1...4 {
                let lv = 1 + Double(rank - 1) * 5 / 3
                let n1 = SkillCatalog.numbers(for: skill(.skill1), hero: def, rank: rank, stats: stats)
                XCTAssertEqual(n1.damage, (200 + (lv - 1) * 40 + 0.8 * atk) * 4.0 * T.s1Scale, accuracy: 1e-6, "S1 r\(rank)")
                XCTAssertEqual(n1.cooldown, (6.0 - (lv - 1) * 0.4) * cdr, accuracy: 1e-9, "S1 CD r\(rank)")
                XCTAssertEqual(n1.cost, 35 + (lv - 1) * 5, accuracy: 1e-9, "S1 MP r\(rank)（日本語クライアント 35 → 60）")
                let n2 = SkillCatalog.numbers(for: skill(.skill2), hero: def, rank: rank, stats: stats)
                XCTAssertEqual(n2.damage, (170 + (lv - 1) * 30 + 0.65 * atk) * 3.0 * T.s2Scale, accuracy: 1e-6, "S2 r\(rank)")
                let det = try XCTUnwrap(n2.extras.first { $0.key == "detonation" }).value
                XCTAssertEqual(det, (100 + (lv - 1) * 20 + 0.35 * atk) * 3.0 * T.s2Scale, accuracy: 1e-6, "刻印 r\(rank)")
                XCTAssertEqual(n2.cooldown, (7.5 - (lv - 1) * 0.2) * cdr, accuracy: 1e-9, "S2 CD r\(rank)")
                XCTAssertEqual(n2.cost, 70, accuracy: 1e-9, "S2 MP r\(rank)（日本語クライアント 70 一定）")
                XCTAssertEqual(SkillSystem.cost(for: skill(.skill2), hero: def, rank: rank), n2.cost, accuracy: 1e-9)
                XCTAssertEqual(n1.resource, .mana)
            }
            for (rank, b, cd, mp) in [(1, 500.0, 37.0, 130.0), (2, 650, 32, 150), (3, 800, 27, 170)] {
                let n = SkillCatalog.numbers(for: skill(.ultimate), hero: def, rank: rank, stats: stats)
                XCTAssertEqual(n.damage, (b + 1.5 * atk) * 2.6 * T.ultScale, accuracy: 1e-6, "ULT r\(rank)")
                XCTAssertEqual(n.cooldown, cd * cdr, accuracy: 1e-9, "ULT CD r\(rank)")
                XCTAssertEqual(n.cost, mp, accuracy: 1e-9, "ULT MP r\(rank)")
            }
            // 1 スロットの火力は汎用の値から大きく外れない（ダメージの絶対値は Velstria の尺度）
            for slot in SkillSlot.actives {
                for rank in 1...slot.maxRank {
                    let base = SkillCatalog.genericNumbers(for: skill(slot), hero: def, rank: rank, stats: stats)
                    let n = SkillCatalog.numbers(for: skill(slot), hero: def, rank: rank, stats: stats)
                    // 汎用の遠隔 S2 は「ブリンク + 強化攻撃」で半分になっているので、元のスキル値を基準にする
                    let reference = slot == .skill2 ? base.damage / Balance.Skills.empowerRatio : base.damage
                    var total = n.damage
                    if slot == .skill2 { total += try XCTUnwrap(n.extras.first { $0.key == "detonation" }).value }
                    XCTAssertGreaterThanOrEqual(total / reference, 0.7, "\(slot) rank \(rank) Lv\(level)")
                    XCTAssertLessThanOrEqual(total / reference, 1.4, "\(slot) rank \(rank) Lv\(level)")
                }
            }
        }
        // 説明文の {base}・{atkPct} は sim の式に換算した値
        let st = HeroGrowth.baseStats(def: def, level: 1)
        let n1 = SkillCatalog.numbers(for: skill(.skill1), hero: def, rank: 4, stats: st)
        XCTAssertEqual(n1.extras.first { $0.key == "base" }?.value, (400 * 4.0 * T.s1Scale).rounded())
        XCTAssertEqual(n1.extras.first { $0.key == "atkPct" }?.value, (0.8 * 0.6 * 4.0 * T.s1Scale * 100).rounded())
        XCTAssertEqual(SkillCatalog.numbers(for: skill(.passive), hero: def, rank: 1, stats: st).cost, 0)
        // ランクが上がると強くなる
        let stats = HeroGrowth.baseStats(def: def, level: 6)
        for slot in SkillSlot.actives {
            let lo = SkillCatalog.numbers(for: skill(slot), hero: def, rank: 1, stats: stats)
            let hi = SkillCatalog.numbers(for: skill(slot), hero: def, rank: slot.maxRank, stats: stats)
            XCTAssertGreaterThan(hi.damage, lo.damage, "\(slot)")
        }
        // S2 の CC は刻印の弾けのスタン（爆発の減速は無い = 日本語クライアント）
        let n2 = SkillCatalog.numbers(for: skill(.skill2), hero: def, rank: 1, stats: stats)
        XCTAssertEqual(n2.cc, .stun)
        XCTAssertEqual(n2.ccDuration, T.markStun)
        XCTAssertNil(n2.extras.first { $0.key == "slow" })
    }

    // MARK: - パッシブ（遠星の照準）

    func testBasicAttackDamageGrowsWithDistanceUpToTheCap() {
        for d in [100.0, 300, 500] {
            var w = SkillWorld()
            let k = addRaina(&w)
            let e = w.addDummyEnemy(at: skillArena + Vec2(d, 0))
            w.s.units[k].attackTargetID = w.id(e)
            w.run(seconds: 2.5)
            let events = damageEvents(w, to: e, .basicAttack)
            XCTAssertGreaterThanOrEqual(events.count, 2, "d=\(d)")
            let expected = w.mitigated(w.s.units[k].stats.attack * distanceMultiplier(d), .physical, on: e)
            for ev in events {
                XCTAssertEqual(ev.amount, expected, accuracy: 0.01, "d=\(d)")
                XCTAssertFalse(ev.isCrit)
            }
        }
    }

    func testPassiveScalingIsPlainDistanceCapAndIgnoresTowers() throws {
        XCTAssertEqual(T.distanceScaling, .distance(near: 0, far: 600, minMult: 1, maxMult: 1.15), "公式: 6 マスで最大 115%")
        var w = SkillWorld()
        let k = addRaina(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        let tower = w.addTower(team: .red, at: skillArena + Vec2(0, 500))
        let kit = try XCTUnwrap(HeroKits.kit(of: w.s.units[k]))
        var plan = BasicAttackPlan(payload: HitPayload(damage: 100, damageType: .physical, source: .basicAttack),
                                   ranged: true)
        kit.shapeBasicAttack(&w.s, w.ctx, attacker: k, target: e, plan: &plan)
        XCTAssertEqual(plan.payload.scaling, T.distanceScaling)
        XCTAssertEqual(plan.payload.originPos, w.s.units[k].pos)
        XCTAssertTrue(plan.extras.isEmpty)
        var towerPlan = BasicAttackPlan(payload: HitPayload(damage: 100, damageType: .physical, source: .basicAttack),
                                        ranged: true)
        kit.shapeBasicAttack(&w.s, w.ctx, attacker: k, target: tower, plan: &towerPlan)
        XCTAssertNil(towerPlan.payload.scaling, "タワーには効かない")
        XCTAssertNil(towerPlan.payload.originPos)

        // 実際の通常攻撃でもタワーは補正なし: 距離の違うタワー 2 つで 1 発あたりが同じ
        var w2 = SkillWorld()
        let k2 = addRaina(&w2)
        w2.s.tick = 5000   // 序盤保護を外す
        w2.s.time = Double(w2.s.tick) * Balance.dt
        let near = w2.addTower(team: .red, at: skillArena + Vec2(250, 0))
        w2.tick()
        w2.s.units[k2].attackTargetID = w2.id(near)
        w2.run(seconds: 2)
        let near1 = damageEvents(w2, to: near, .basicAttack).first?.amount ?? 0
        var w3 = SkillWorld()
        let k3 = addRaina(&w3)
        w3.s.tick = 5000
        w3.s.time = Double(w3.s.tick) * Balance.dt
        let far = w3.addTower(team: .red, at: skillArena + Vec2(500, 0))
        w3.tick()
        w3.s.units[k3].attackTargetID = w3.id(far)
        w3.run(seconds: 2)
        let far1 = damageEvents(w3, to: far, .basicAttack).first?.amount ?? 0
        XCTAssertGreaterThan(near1, 0)
        XCTAssertEqual(near1, far1, accuracy: 1e-6, "タワーへの通常攻撃は距離補正を受けない")
    }

    func testPassiveReplacesRangerCritPassive() {
        var w = SkillWorld()
        let k = addRaina(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        w.s.units[k].attackTargetID = w.id(e)
        w.run(seconds: 8)
        let events = damageEvents(w, to: e, .basicAttack)
        XCTAssertGreaterThanOrEqual(events.count, 6)
        XCTAssertTrue(events.allSatisfy { !$0.isCrit }, "ロールの「4 発毎の確定会心」は置き換わる")
        XCTAssertEqual(w.s.units[k].hero!.passive.stacks, 0)
        XCTAssertGreaterThanOrEqual(w.s.units[k].hero!.basicAttackCount, 6)
    }

    func testSkillsGetDistanceBonusAndCapAtFarDistance() {
        // S1: 距離ごとの倍率
        for d in [150.0, 385, 640] {
            var w = SkillWorld()
            let k = addRaina(&w)
            let e = w.addDummyEnemy(at: skillArena + Vec2(d, 0))
            let n = w.numbers(k, .skill1)
            XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
            w.run(seconds: 1)
            let evs = damageEvents(w, to: e, .skill(.skill1))
            XCTAssertEqual(evs.count, 1, "d=\(d)")
            XCTAssertEqual(evs.first?.amount ?? 0, w.mitigated(n.damage * distanceMultiplier(d), .physical, on: e),
                           accuracy: 0.01, "d=\(d)")
        }
        // 奥義: 頭打ち（600 以上は +15%）
        for d in [600.0, 1200, 1900] {
            var w = SkillWorld()
            let k = addRaina(&w)
            let e = w.addDummyEnemy(at: skillArena + Vec2(d, 0))
            let n = w.numbers(k, .ultimate)
            XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
            w.run(seconds: 1.5)
            let evs = damageEvents(w, to: e, .skill(.ultimate))
            XCTAssertEqual(evs.count, 1, "d=\(d)")
            XCTAssertEqual(evs.first?.amount ?? 0, w.mitigated(n.damage * 1.15, .physical, on: e), accuracy: 0.01,
                           "d=\(d)")
        }
        XCTAssertEqual(distanceMultiplier(0), 1)
        XCTAssertEqual(distanceMultiplier(300), 1.075, accuracy: 1e-9, "公式: 6 マス（600）で最大 115%")
        XCTAssertEqual(distanceMultiplier(600), 1.15, accuracy: 1e-9)
    }

    func testCriticalHitsAlsoGetTheDistanceBonus() throws {
        // 公式: スキル1 は「クリティカル可能」、パッシブの除外は「タワー」だけ = 会心の通常攻撃・スキル1 にも距離の補正が乗る
        var w = SkillWorld()
        let k = addRaina(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        let kit = try XCTUnwrap(HeroKits.kit(of: w.s.units[k]))
        var plan = BasicAttackPlan(payload: HitPayload(damage: 100, damageType: .physical, source: .basicAttack, isCrit: true),
                                   ranged: true)
        kit.shapeBasicAttack(&w.s, w.ctx, attacker: k, target: e, plan: &plan)
        XCTAssertEqual(plan.payload.scaling, T.distanceScaling, "会心の通常攻撃にも距離の補正")
        // 会心率 100% のスキル1（480 = +12%）: 会心の倍率 × 距離の補正。合図も出る
        var w2 = SkillWorld()
        let k2 = addRaina(&w2)
        let e2 = w2.addDummyEnemy(at: skillArena + Vec2(480, 0))
        w2.s.units[k2].stats.critChance = 1
        let n = w2.numbers(k2, .skill1)
        XCTAssertTrue(w2.cast(k2, .skill1, .direction(Self.east)))
        w2.run(seconds: 1)
        let ev = try XCTUnwrap(damageEvents(w2, to: e2, .skill(.skill1)).first)
        XCTAssertTrue(ev.isCrit)
        let crit = max(1, w2.s.units[k2].stats.critMultiplier)
        XCTAssertEqual(ev.amount, w2.mitigated(n.damage * crit * distanceMultiplier(480), .physical, on: e2), accuracy: 0.01)
        XCTAssertEqual(HeroKits.badge(w2.s.units[k2].hero!, slot: .passive)?.value, 12)
    }

    // MARK: - パッシブのバッジ（遠距離命中の合図）

    func testPassiveBadgeFlashesWhenABasicAttackLandsFarOnAnEnemyHero() throws {
        XCTAssertEqual(Kit_H030.distanceBonus(0), 0)
        XCTAssertEqual(Kit_H030.distanceBonus(T.farDistance * 2), T.maxDistanceBonus, accuracy: 1e-12)
        XCTAssertEqual(1 + Kit_H030.distanceBonus(385), distanceMultiplier(385), accuracy: 1e-12, "ダメージの補正と同じ式")
        // 近い（300 = +7.5%）: 当たっても合図は出ない
        do {
            var w = SkillWorld()
            let k = addRaina(&w)
            let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
            w.s.units[k].attackTargetID = w.id(e)
            w.run(seconds: 2.5)
            XCTAssertGreaterThanOrEqual(damageEvents(w, to: e, .basicAttack).count, 2)
            XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
        }
        // 基本射程の端の近く（520 = +13%）: 最初の命中からタイマー。value = その命中の補正（%）
        var w = SkillWorld()
        let k = addRaina(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(520, 0))
        w.s.units[k].attackTargetID = w.id(e)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
        var ticks = 0
        while damageEvents(w, to: e, .basicAttack).isEmpty && ticks < Int(3 * Balance.tickRate) {
            XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive), "当たる前は出ない")
            w.tick()
            ticks += 1
        }
        XCTAssertFalse(damageEvents(w, to: e, .basicAttack).isEmpty)
        let badge = try XCTUnwrap(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
        XCTAssertEqual(badge.kind, .timer)
        XCTAssertEqual(badge.total, T.farHitFlash)
        XCTAssertGreaterThan(badge.remaining, T.farHitFlash - 0.1)
        XCTAssertEqual(badge.value, Int((Kit_H030.distanceBonus(520) * 100).rounded()))
        XCTAssertEqual(badge.value, 13)
        XCTAssertEqual(badge.maxValue, 15)
        // 撃ち続けている間は点いたまま（命中のたびに付け直す）
        w.run(seconds: 3)
        XCTAssertGreaterThanOrEqual(damageEvents(w, to: e, .basicAttack).count, 3)
        XCTAssertNotNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
        // 撃つのをやめると 1.5 秒で消える
        w.s.units[k].attackTargetID = nil
        w.run(seconds: T.farHitFlash + 0.6)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
    }

    func testPassiveBadgeIgnoresMinionsAndCountsFarSkillHits() throws {
        // ミニオンは遠くても数えない
        do {
            var w = SkillWorld()
            let k = addRaina(&w)
            let m = w.addMinion(team: .red, at: skillArena + Vec2(540, 0))
            w.s.units[m].stats.maxHP = 1e6
            w.s.units[m].hp = 1e6
            w.s.units[k].attackTargetID = w.id(m)
            w.run(seconds: 2.5)
            XCTAssertFalse(damageEvents(w, to: m, .basicAttack).isEmpty)
            XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
        }
        // S1（480 = +12%）・奥義（1200 = 頭打ちの 15%）の遠い命中も合図になる。起点は撃った位置
        for (slot, d, pct) in [(SkillSlot.skill1, 480.0, 12), (.ultimate, 1200, 15)] {
            var w = SkillWorld()
            let k = addRaina(&w)
            let e = w.addDummyEnemy(at: skillArena + Vec2(d, 0))
            XCTAssertTrue(w.cast(k, slot, .direction(Self.east)))
            w.run(seconds: 1.0)
            XCTAssertEqual(damageEvents(w, to: e, .skill(slot)).count, 1, "\(slot)")
            let badge = try XCTUnwrap(HeroKits.badge(w.s.units[k].hero!, slot: .passive), "\(slot)")
            XCTAssertEqual(badge.value, pct, "\(slot)")
        }
        // S2 の爆発（星環弾は撃った位置が起点。近い 200 = +5% では出ない）
        do {
            var w = SkillWorld()
            let k = addRaina(&w)
            let e = w.addDummyEnemy(at: skillArena + Vec2(200, 0))
            XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
            w.run(seconds: 1.0)
            XCTAssertEqual(damageEvents(w, to: e, .skill(.skill2)).count, 1)
            XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .passive))
        }
        do {
            var w = SkillWorld()
            let k = addRaina(&w)
            let e = w.addDummyEnemy(at: skillArena + Vec2(600, 0))
            XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
            w.run(seconds: 1.0)
            XCTAssertEqual(damageEvents(w, to: e, .skill(.skill2)).count, 1)
            XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive)?.value, 15)
        }
    }

    func testUltimateRankPermanentlyExtendsAttackRange() {
        var w = SkillWorld()
        let k = addRaina(&w, ranks: [1, 1, 1])
        let base = def.attackRange
        w.tick()
        w.tick()
        XCTAssertEqual(w.s.units[k].stats.attackRange, base + 60, accuracy: 1e-9)
        w.s.units[k].hero!.skillRanks[SkillSlot.ultimate.rawValue] = 3
        w.tick(2)
        XCTAssertEqual(w.s.units[k].stats.attackRange, base + 180, accuracy: 1e-9)
        // ステータスは 1 つだけ（毎 tick 積み増さない）
        XCTAssertEqual(w.s.units[k].statuses.filter { $0.tag == T.ultRangeTag }.count, 1)
        w.s.units[k].hero!.skillRanks[SkillSlot.ultimate.rawValue] = 0
        w.tick(2)
        XCTAssertEqual(w.s.units[k].stats.attackRange, base, accuracy: 1e-9)
        XCTAssertTrue(w.s.units[k].statuses.filter { $0.tag == T.ultRangeTag }.isEmpty)
        // 死亡で消え、復活後に戻る
        w.s.units[k].hero!.skillRanks[SkillSlot.ultimate.rawValue] = 2
        w.tick(2)
        XCTAssertEqual(w.s.units[k].stats.attackRange, base + 120, accuracy: 1e-9)
    }

    // MARK: - S1 マレフィック・ボム

    func testBombHitsOnlyTheFirstEnemyInTheLine() {
        var w = SkillWorld()
        let k = addRaina(&w)
        let front = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        let back = w.addDummyEnemy(at: skillArena + Vec2(500, 0), hero: "H004")
        let off = w.addDummyEnemy(at: skillArena + Vec2(300, 400), hero: "H005")
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        XCTAssertEqual(w.castEvents.last?.archetype, .lineSkillshot)
        XCTAssertEqual(w.castEvents.last?.slot, .skill1)
        w.run(seconds: 1)
        XCTAssertGreaterThan(w.damage(to: front, from: .skill(.skill1)), 0)
        XCTAssertEqual(w.damage(to: back), 0)
        XCTAssertEqual(w.damage(to: off), 0)
        // 射程外には届かない
        var w2 = SkillWorld()
        let k2 = addRaina(&w2)
        let far = w2.addDummyEnemy(at: skillArena + Vec2(950, 0))
        XCTAssertTrue(w2.cast(k2, .skill1, .direction(Self.east)))
        w2.run(seconds: 1.5)
        XCTAssertEqual(w2.damage(to: far), 0)
        XCTAssertEqual(w2.s.units[k2].statuses.filter { $0.tag == T.s1RangeTag }.count, 0, "外れたら延長なし")
        XCTAssertFalse(w2.s.units[k2].has(.speedBoost))
    }

    func testBombCanCrit() {
        var w = SkillWorld()
        let k = addRaina(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        w.s.units[k].stats.critChance = 1
        let n = w.numbers(k, .skill1)
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        w.run(seconds: 1)
        let ev = damageEvents(w, to: e, .skill(.skill1))
        XCTAssertEqual(ev.count, 1)
        XCTAssertTrue(ev[0].isCrit)
        let crit = w.s.units[k].stats.critMultiplier
        XCTAssertEqual(ev[0].amount, w.mitigated(n.damage * crit * distanceMultiplier(400), .physical, on: e),
                       accuracy: 0.01)

        // 確率 0 なら乱数を引かず、会心にならない
        var w2 = SkillWorld()
        let k2 = addRaina(&w2)
        let e2 = w2.addDummyEnemy(at: skillArena + Vec2(400, 0))
        let rng = w2.s.rng
        XCTAssertTrue(w2.cast(k2, .skill1, .direction(Self.east)))
        XCTAssertEqual(w2.s.rng, rng)
        w2.run(seconds: 1)
        XCTAssertFalse(damageEvents(w2, to: e2, .skill(.skill1))[0].isCrit)
    }

    func testBombHitExtendsRangeByUltimateRankAndGrantsDecayingSpeed() throws {
        let base = def.attackRange
        for (ultRank, expectedBuff) in zip([1, 2, 3], [140.0, 120, 100]) {
            var w = SkillWorld()
            let k = addRaina(&w, ranks: [1, 1, ultRank])
            _ = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
            w.tick(2)
            XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .skill1))
            XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
            w.run(seconds: 0.5)
            let st = try XCTUnwrap(w.s.units[k].statuses.first { $0.tag == T.s1RangeTag })
            XCTAssertEqual(st.magnitude, expectedBuff, "奥義ランク \(ultRank)")
            XCTAssertEqual(w.s.units[k].stats.attackRange, base + 60 * Double(ultRank) + expectedBuff, accuracy: 1e-9)
            let badge = try XCTUnwrap(HeroKits.badge(w.s.units[k].hero!, slot: .skill1))
            XCTAssertEqual(badge.kind, .timer)
            XCTAssertEqual(badge.total, T.s1RangeBuffDuration)
            XCTAssertGreaterThan(badge.remaining, 2)
            // 3 秒で切れる（常時の延長だけが残る）
            w.run(seconds: 3)
            XCTAssertEqual(w.s.units[k].stats.attackRange, base + 60 * Double(ultRank), accuracy: 1e-9)
            XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .skill1))
        }
        // 奥義 0 ランクは最大の +160
        var w = SkillWorld()
        let k = addRaina(&w, ranks: [1, 1, 0])
        _ = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        w.run(seconds: 0.5)
        XCTAssertEqual(w.s.units[k].statuses.first { $0.tag == T.s1RangeTag }?.magnitude, 160)
    }

    func testBombSpeedBoostDecaysAndDoublesOnEnemyHero() throws {
        // 敵ヒーロー: 2.4 秒（最初の 1.2 秒は 60% のまま、その後 0 へ）
        var w = SkillWorld()
        let k = addRaina(&w)
        _ = w.addDummyEnemy(at: skillArena + Vec2(200, 0))
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        w.run(seconds: 0.3)
        let hero0 = try XCTUnwrap(w.s.units[k].statuses.first { $0.tag == T.rushTag })
        XCTAssertGreaterThan(hero0.remaining, 2.0)
        XCTAssertLessThanOrEqual(hero0.duration, T.rushHeroDuration + 1e-9)
        XCTAssertEqual(hero0.magnitude, 0.6, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[k].stats.moveSpeed,
                       HeroGrowth.baseStats(def: def, level: 1).moveSpeed * 1.6, accuracy: 1.0)
        w.run(seconds: 1.5)   // 残り ≈ 0.6 秒 → 0.3
        let mid = try XCTUnwrap(w.s.units[k].statuses.first { $0.tag == T.rushTag })
        XCTAssertEqual(mid.magnitude, 0.6 * mid.remaining / T.rushDuration, accuracy: 0.03)
        XCTAssertLessThan(mid.magnitude, 0.6)
        w.run(seconds: 1)
        XCTAssertFalse(w.s.units[k].has(.speedBoost))

        // ミニオン: 1.2 秒で 60% → 0
        var w2 = SkillWorld()
        let k2 = addRaina(&w2)
        _ = w2.addMinion(team: .red, at: skillArena + Vec2(200, 0))
        XCTAssertTrue(w2.cast(k2, .skill1, .direction(Self.east)))
        w2.run(seconds: 0.4)
        let minion = try XCTUnwrap(w2.s.units[k2].statuses.first { $0.tag == T.rushTag })
        XCTAssertLessThanOrEqual(minion.duration, T.rushDuration + 1e-9)
        XCTAssertEqual(minion.magnitude, 0.6 * minion.remaining / T.rushDuration, accuracy: 0.03)
        XCTAssertLessThan(minion.magnitude, 0.5)
        w2.run(seconds: 1)
        XCTAssertFalse(w2.s.units[k2].has(.speedBoost))
    }

    // MARK: - S2 ヴォイド・プロジェクタイル

    func testOrbBurstsOnFirstEnemyAndMarksEveryoneInTheBlast() throws {
        var w = SkillWorld()
        let k = addRaina(&w)
        let a = w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        let b = w.addDummyEnemy(at: skillArena + Vec2(500, 150), hero: "H004")
        let c = w.addDummyEnemy(at: skillArena + Vec2(500, 400), hero: "H005")
        let behind = w.addDummyEnemy(at: skillArena + Vec2(560, 0), hero: "H006")
        let n = w.numbers(k, .skill2)
        w.tick()
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        XCTAssertEqual(w.castEvents.last?.slot, .skill2)
        XCTAssertEqual(w.castEvents.last?.range ?? 0, 650 + 60, "奥義ランクの延長ぶん遠くへ届く")
        w.run(seconds: 1)
        let radius = skill(.skill2).radius
        for e in [a, b, behind] {
            let evs = damageEvents(w, to: e, .skill(.skill2))
            XCTAssertEqual(evs.count, 1, "爆発の中の敵に 1 度ずつ")
            let d = w.s.units[e].pos.distance(to: skillArena)
            XCTAssertEqual(evs[0].amount, w.mitigated(n.damage * distanceMultiplier(d), .physical, on: e), accuracy: 0.01)
            XCTAssertEqual(markStacks(w, owner: k, on: e), 1)
            XCTAssertLessThanOrEqual(w.s.units[e].pos.distance(to: w.s.units[a].pos), radius + w.s.units[e].radius)
        }
        XCTAssertEqual(w.damage(to: c), 0, "爆発の外")
        XCTAssertEqual(markStacks(w, owner: k, on: c), 0)
        for e in [a, b, behind, c] {
            XCTAssertFalse(w.s.units[e].has(.slow), "爆発に減速は無い（日本語クライアント）")
        }
        // 刻印は 3 秒で消える
        w.run(seconds: 3.1)
        XCTAssertEqual(markStacks(w, owner: k, on: a), 0)
        XCTAssertEqual(w.kit(k).rainaDetonations, 0, "S2 自身の命中では弾けない")
    }

    func testOrbRangeGrowsWithUltimateRankAndBombBuffAndBurstsOnMinionsFirst() {
        // 1000 先: 常時延長だけ（650 + 60）では届かず（射程の端 710 の爆発も半径 190 の外）、S1 の一時延長（+140）が乗ると届く
        var w = SkillWorld()
        let k = addRaina(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(1000, 0))
        w.tick()
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        XCTAssertEqual(w.castEvents.last?.range ?? 0, 710, accuracy: 1e-9)
        w.run(seconds: 1.5)
        XCTAssertEqual(w.damage(to: e), 0)

        var w2 = SkillWorld()
        let k2 = addRaina(&w2)
        let e2 = w2.addDummyEnemy(at: skillArena + Vec2(800, 0))
        w2.tick()
        Kit.grantAttackRange(&w2.s, target: k2, amount: 140, duration: 3, tag: T.s1RangeTag)
        XCTAssertTrue(w2.cast(k2, .skill2, .direction(Self.east)))
        XCTAssertEqual(w2.castEvents.last?.range ?? 0, 850, accuracy: 1e-9)
        w2.run(seconds: 1.5)
        XCTAssertGreaterThan(w2.damage(to: e2, from: .skill(.skill2)), 0)

        // 最初に当たるのはミニオンでも爆発する（奥の敵は爆発の中なら巻き込む）
        var w3 = SkillWorld()
        let k3 = addRaina(&w3)
        let minion = w3.addMinion(team: .red, at: skillArena + Vec2(350, 0))
        let hero = w3.addDummyEnemy(at: skillArena + Vec2(480, 0))
        XCTAssertTrue(w3.cast(k3, .skill2, .direction(Self.east)))
        w3.run(seconds: 1)
        XCTAssertGreaterThan(w3.damage(to: minion, from: .skill(.skill2)), 0)
        XCTAssertGreaterThan(w3.damage(to: hero, from: .skill(.skill2)), 0, "爆発の半径内")
        XCTAssertEqual(markStacks(w3, owner: k3, on: hero), 1)
    }

    func testOrbExplodesAtMaxRangeWhenNothingIsHit() throws {
        // 射程の端（650 + 60）の少し脇に敵: 弾は当たらず飛び去るが、端で爆発して巻き込む
        var w = SkillWorld()
        let k = addRaina(&w)
        let edge = skillArena + Vec2(710, 0)
        let near = w.addDummyEnemy(at: edge + Vec2(0, 150))
        let far = w.addDummyEnemy(at: edge + Vec2(0, 400), hero: "H004")
        let n = w.numbers(k, .skill2)
        w.tick()
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k, code: T.Code.orbEnd), 1)
        w.run(seconds: 1.2)
        let evs = damageEvents(w, to: near, .skill(.skill2))
        XCTAssertEqual(evs.count, 1, "射程の端の爆発に 1 度だけ")
        XCTAssertEqual(evs[0].amount, w.mitigated(n.damage * distanceMultiplier(w.s.units[near].pos.distance(to: skillArena)), .physical, on: near), accuracy: 0.01)
        XCTAssertEqual(markStacks(w, owner: k, on: near), 1, "刻印も付く")
        XCTAssertFalse(w.s.units[near].has(.slow))
        XCTAssertEqual(w.damage(to: far), 0, "爆発の外")
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k, code: T.Code.orbEnd), 0, "予約は使い切る")
        // 誰も居なくても何も壊れない
        var w2 = SkillWorld()
        let k2 = addRaina(&w2)
        XCTAssertTrue(w2.cast(k2, .skill2, .direction(Self.east)))
        w2.run(seconds: 1.5)
        XCTAssertTrue(w2.damageEvents.isEmpty)
        XCTAssertEqual(Kit.scheduledCount(w2.s, caster: k2), 0)
    }

    func testOrbThatHitsSomethingDoesNotExplodeAgainAtTheEnd() {
        var w = SkillWorld()
        let k = addRaina(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        // 端の爆発の位置（710）にも別の敵: 先に当たった爆発（300 の位置）の外
        let atEdge = w.addDummyEnemy(at: skillArena + Vec2(710, 100), hero: "H004")
        w.tick()
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 1.5)
        XCTAssertEqual(damageEvents(w, to: e, .skill(.skill2)).count, 1)
        XCTAssertEqual(w.damage(to: atEdge), 0, "命中で消えた弾は端で再び爆発しない")
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k, code: T.Code.orbEnd), 0)
    }

    func testOrbEndExplosionSurvivesTheCastersStun() {
        // 発動後にスタンされても、放たれた弾は飛んで端で爆発する
        var w = SkillWorld()
        let k = addRaina(&w)
        let near = w.addDummyEnemy(at: skillArena + Vec2(710, 150))
        w.tick()
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.tick(2)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 0.5))
        w.run(seconds: 1.2)
        XCTAssertGreaterThan(w.damage(to: near, from: .skill(.skill2)), 0)
    }

    func testBeamReachesEverywhereAlongTheLineAtHighSpeedWithoutTunneling() {
        // 速さ 7000（1 tick ≒ 233）でも、線上のどの距離の敵にも 1 度ずつ当たる（掃引判定）
        XCTAssertEqual(T.ultBeamSpeed, 7000)
        XCTAssertEqual(T.ultWindup, 0.2)
        var w = SkillWorld()
        let k = addRaina(&w)
        var es: [Int] = []
        for (n, d) in [130.0, 233, 466, 777, 1111, 1500, 1990].enumerated() {
            es.append(w.addDummyEnemy(at: skillArena + Vec2(d, 0), hero: ["H003", "H004", "H005", "H006", "H007", "H008", "H009"][n]))
        }
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.run(seconds: T.ultWindup + 2000 / T.ultBeamSpeed + 0.15)
        for e in es { XCTAssertEqual(damageEvents(w, to: e, .skill(.ultimate)).count, 1) }
        // 溜めが短く、ビームが速いので、遠くの敵にも 0.5 秒以内に届く
        XCTAssertLessThan(T.ultWindup + 2000 / T.ultBeamSpeed, 0.5)
    }

    // MARK: - ボット

    func testBotUltimateAimLeadsAMovingTargetByWindupPlusFlightTime() throws {
        var w = SkillWorld()
        let k = addRaina(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(700, 0))
        var blue = BotTeamIntel(team: .blue)
        blue.enemyIDs = [w.id(e)]
        blue.velocity = [Vec2(0, 300)]
        blue.visibleSince = [0]
        blue.lastSeenPos = [w.s.units[e].pos]
        blue.lastSeenTime = [0]
        blue.lastSeenTick = [0]
        blue.awayUntil = [-999]
        w.s.bots.teams = [blue, BotTeamIntel(team: .red)]
        let kit = try XCTUnwrap(HeroKits.kit(of: w.s.units[k]))
        let tg = HeroKits.targeting(for: skill(.ultimate), hero: def, stage: 0)
        guard case .cast(.direction(let d)) = kit.botCast(w.s, w.ctx, bot: k, slot: .ultimate, targeting: tg, target: e,
                                                          fighting: true) else {
            return XCTFail("ビームは先読みして撃つ")
        }
        XCTAssertGreaterThan(d.y, 0.02, "動く先（+y）へ先読み")
        XCTAssertEqual(d.length, 1, accuracy: 1e-9)
        // 先読みは 溜め + 距離 ÷ 速さ（約 0.3 秒）× 精度。汎用の見積もり（約 0.54 秒）よりずっと小さい
        let travel = T.ultWindup + 700 / T.ultBeamSpeed
        let lead = 300 * travel * BotProfile.of(.normal).accuracy
        XCTAssertEqual(d.y / d.x, lead / 700, accuracy: 0.003)
        // 観測が無ければ（速度 0）まっすぐ
        w.s.bots.teams[0].velocity = [.zero]
        guard case .cast(.direction(let d0)) = kit.botCast(w.s, w.ctx, bot: k, slot: .ultimate, targeting: tg, target: e,
                                                           fighting: true) else { return XCTFail() }
        XCTAssertEqual(d0.y, 0, accuracy: 1e-9)
        // 射程の外は撃たない。他のスロットは汎用のまま
        w.s.units[e].pos = skillArena + Vec2(2600, 0)
        guard case .skip = kit.botCast(w.s, w.ctx, bot: k, slot: .ultimate, targeting: tg, target: e, fighting: true) else {
            return XCTFail("射程外は見送り")
        }
        guard case .useDefault = kit.botCast(w.s, w.ctx, bot: k, slot: .skill2, targeting: tg, target: e, fighting: true)
        else { return XCTFail() }
    }

    func testTextUsesUITermsMasterNamesAndExplainsDistance() throws {
        let stats = HeroGrowth.baseStats(def: def, level: 6)
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H030", slot: slot))
            let n = SkillCatalog.numbers(for: skill(slot), hero: def, rank: 1, stats: stats)
            let t = SkillCatalog.targeting(for: skill(slot), hero: def)
            let ja = text.filled(english: false, numbers: n, targeting: t)
            XCTAssertFalse(ja.contains("S1") || ja.contains("S2") || ja.contains("奥義"), "\(slot): \(ja)")
            XCTAssertFalse(ja.contains("星環シフト") || ja.contains("星環弾"), "\(slot): \(ja)")
            if slot == .passive {
                XCTAssertTrue(ja.contains("基本射程"), ja)
                XCTAssertTrue(ja.contains("550"), ja)
                XCTAssertTrue(ja.contains("1.1倍"), ja)
                // 日本語クライアントの文: 「最小100%、6離れると最大115%」「タワーには適用されない」
                XCTAssertTrue(ja.contains("最小100%"), ja)
                XCTAssertTrue(ja.contains("最大115%まで増加"), ja)
                XCTAssertTrue(ja.contains("タワーには適用されない"), ja)
            }
            if slot == .skill1 {
                XCTAssertTrue(ja.contains("アルティメット"), ja)
                XCTAssertTrue(ja.contains("（クリティカル可能）"), ja)
            }
            if slot == .skill2 {
                XCTAssertTrue(ja.contains("射程の端で爆発"), ja)
                XCTAssertTrue(ja.contains("刻印の付いた敵を攻撃すると"), ja)
                XCTAssertFalse(ja.contains("低下"), "減速は無い: \(ja)")
            }
            if slot == .ultimate { XCTAssertTrue(ja.hasPrefix("パッシブ："), ja) }
        }
    }

    // MARK: - 刻印の炸裂（スタン 0.25 秒）

    /// 刻印した A（正面）と B（脇）。
    private func markedPair() -> (SkillWorld, k: Int, a: Int, b: Int) {
        var w = SkillWorld()
        let k = addRaina(&w)
        let a = w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        let b = w.addDummyEnemy(at: skillArena + Vec2(500, 230), hero: "H004")   // ビーム・S1 の幅の外、炸裂の半径の中
        mark(&w, owner: k, on: a)
        mark(&w, owner: k, on: b)
        return (w, k, a, b)
    }

    func testBasicAttackOnMarkedEnemyPopsTheMarkStunsAndDamagesNearby() throws {
        var w = SkillWorld()
        let k = addRaina(&w)
        let a = w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        let b = w.addDummyEnemy(at: skillArena + Vec2(500, 150), hero: "H004")
        let c = w.addDummyEnemy(at: skillArena + Vec2(500, 420), hero: "H005")
        let n = w.numbers(k, .skill2)
        let det = try XCTUnwrap(n.extras.first { $0.key == "detonation" }).value
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 0.6)
        XCTAssertEqual(markStacks(w, owner: k, on: a), 1)
        XCTAssertEqual(markStacks(w, owner: k, on: b), 1)
        w.s.units[k].attackTargetID = w.id(a)
        // 通常攻撃が当たる → 刻印が弾ける
        var popped = false
        for _ in 0..<90 where !popped {
            w.tick()
            popped = w.kit(k).rainaDetonations > 0
        }
        XCTAssertTrue(popped)
        XCTAssertEqual(markStacks(w, owner: k, on: a), 0, "弾けた刻印は消える")
        XCTAssertEqual(markStacks(w, owner: k, on: b), 1, "他の敵の刻印はそのまま")
        w.tick(2)
        // 炸裂: 周囲（A・B）に物理ダメージ + 0.25 秒のスタン。外の C は無傷
        for e in [a, b] {
            let evs = damageEvents(w, to: e, .skill(.skill2))
            XCTAssertEqual(evs.count, 2, "爆発 + 炸裂")
            let d = w.s.units[e].pos.distance(to: skillArena)
            XCTAssertEqual(evs[1].amount, w.mitigated(det * distanceMultiplier(d), .physical, on: e), accuracy: 0.01)
            let stun = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .stun })
            XCTAssertLessThanOrEqual(stun.remaining, T.markStun + 1e-9)
            XCTAssertGreaterThan(stun.remaining, 0)
            XCTAssertFalse(w.s.units[e].canAct)
        }
        XCTAssertEqual(w.damage(to: c), 0)
        XCTAssertFalse(w.s.units[c].has(.stun))
        w.tick(10)
        XCTAssertTrue(w.s.units[a].canAct, "0.25 秒で解ける")
        // 刻印が無ければ二度目の攻撃では弾けない（連続スタンにならない）
        w.run(seconds: 2)
        XCTAssertEqual(w.kit(k).rainaDetonations, 1)
        XCTAssertEqual(w.zoneCount(visual: skill(.skill2).effectID), 1, "炸裂のゾーンは 1 回だけ")
    }

    func testBombAndUltimateAlsoPopTheMark() {
        // S1
        var (w, k, a, b) = markedPair()
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        w.run(seconds: 1)
        XCTAssertEqual(w.kit(k).rainaDetonations, 1)
        XCTAssertEqual(markStacks(w, owner: k, on: a), 0)
        XCTAssertEqual(damageEvents(w, to: b, .skill(.skill2)).count, 1, "B は炸裂を受けた")
        XCTAssertGreaterThan(damageEvents(w, to: a, .skill(.skill1)).count, 0)

        // 奥義: ビーム上の刻印ごとに炸裂する
        var (w2, k2, a2, b2) = markedPair()
        XCTAssertTrue(w2.cast(k2, .ultimate, .direction(Self.east)))
        w2.run(seconds: 1.5)
        XCTAssertEqual(markStacks(w2, owner: k2, on: a2), 0)
        XCTAssertEqual(w2.kit(k2).rainaDetonations, 1, "ビームに当たったのは A だけ（B は脇）")
        XCTAssertEqual(damageEvents(w2, to: b2, .skill(.skill2)).count, 1)
        // 同じビーム上に刻印が 2 つなら 2 回
        var w3 = SkillWorld()
        let k3 = addRaina(&w3)
        let e1 = w3.addDummyEnemy(at: skillArena + Vec2(400, 0))
        let e2 = w3.addDummyEnemy(at: skillArena + Vec2(1200, 0), hero: "H004")
        mark(&w3, owner: k3, on: e1)
        mark(&w3, owner: k3, on: e2)
        XCTAssertTrue(w3.cast(k3, .ultimate, .direction(Self.east)))
        w3.run(seconds: 1.5)
        XCTAssertEqual(w3.kit(k3).rainaDetonations, 2)
        _ = (w.s, w2.s, b)
    }

    func testOrbNeverPopsAMarkItself() {
        // 刻印中の敵へ S2: 爆発して刻印を更新するだけ（炸裂もスタンも無い）
        var (w, k, a, b) = markedPair()
        w.run(seconds: 1.5)   // 刻印の残りを減らす
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 0.8)
        XCTAssertEqual(w.kit(k).rainaDetonations, 0)
        XCTAssertEqual(markStacks(w, owner: k, on: a), 1)
        XCTAssertEqual(markStacks(w, owner: k, on: b), 1)
        XCTAssertFalse(w.s.units[b].has(.stun))
        XCTAssertGreaterThan(w.s.units[a].statuses.first { $0.kind == .mark }?.remaining ?? 0, 2.0, "持続は 3 秒に戻る")
    }

    func testOnlyOwnMarksPopAndExpiredMarksDoNot() {
        var w = SkillWorld()
        let k = addRaina(&w)
        let other = w.addHero("H030", team: .blue, at: skillArena + Vec2(0, -600), ranks: [1, 1, 1], facing: 0)
        let a = w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        let b = w.addDummyEnemy(at: skillArena + Vec2(500, 150), hero: "H004")
        mark(&w, owner: other, on: a)   // 別のライナの刻印では弾けない
        XCTAssertTrue(w.cast(k, .skill1, .direction(Self.east)))
        w.run(seconds: 1)
        XCTAssertEqual(w.kit(k).rainaDetonations, 0)
        XCTAssertEqual(markStacks(w, owner: other, on: a), 1)
        XCTAssertFalse(w.s.units[b].has(.stun))

        // 期限切れ
        var w2 = SkillWorld()
        let k2 = addRaina(&w2)
        let a2 = w2.addDummyEnemy(at: skillArena + Vec2(500, 0))
        mark(&w2, owner: k2, on: a2, duration: 0.5)
        w2.run(seconds: 0.7)
        XCTAssertEqual(markStacks(w2, owner: k2, on: a2), 0)
        w2.s.units[k2].attackTargetID = w2.id(a2)
        w2.run(seconds: 1.5)
        XCTAssertEqual(w2.kit(k2).rainaDetonations, 0)
    }

    // MARK: - 奥義 デストラクション・ラッシュ

    func testUltimateChargesThenPiercesEveryEnemyInTheLine() throws {
        var w = SkillWorld()
        let k = addRaina(&w)
        let e1 = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        let e2 = w.addDummyEnemy(at: skillArena + Vec2(900, 0), hero: "H004")
        let e3 = w.addDummyEnemy(at: skillArena + Vec2(1600, 0), hero: "H005")
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(1200, 0))
        let off = w.addDummyEnemy(at: skillArena + Vec2(900, 330), hero: "H006")
        let past = w.addDummyEnemy(at: skillArena + Vec2(2300, 0), hero: "H001")
        let n = w.numbers(k, .ultimate)
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        let cast = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(cast.archetype, .piercingLine)
        XCTAssertEqual(cast.shape, .wideLine)
        XCTAssertEqual(cast.duration, T.ultWindup)
        XCTAssertEqual(cast.range, 2000)
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k, code: T.Code.beam), 1)
        w.run(seconds: 0.1)
        XCTAssertTrue(w.damageEvents.isEmpty, "溜めの間は当たらない")
        w.run(seconds: 1.2)
        for (e, d) in [(e1, 400.0), (e2, 900), (e3, 1600)] {
            let evs = damageEvents(w, to: e, .skill(.ultimate))
            XCTAssertEqual(evs.count, 1, "貫通して 1 度ずつ")
            XCTAssertEqual(evs[0].amount, w.mitigated(n.damage * distanceMultiplier(d), .physical, on: e), accuracy: 0.01)
        }
        XCTAssertEqual(damageEvents(w, to: minion, .skill(.ultimate)).count, 1, "ミニオンにも当たる")
        XCTAssertEqual(w.damage(to: off), 0)
        XCTAssertEqual(w.damage(to: past), 0, "射程 2000 の外")
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k), 0)
        // 減速・スタンなどの CC は無い
        for e in [e1, e2, e3] {
            XCTAssertFalse(w.s.units[e].has(.stun))
            XCTAssertFalse(w.s.units[e].has(.slow))
            XCTAssertNil(w.s.units[e].displacement)
        }
    }

    func testBeamKeepsTheDirectionFixedAtCast() {
        var w = SkillWorld()
        let k = addRaina(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(600, 0))
        let other = w.addDummyEnemy(at: skillArena + Vec2(0, 600), hero: "H004")
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.s.units[k].facing = Double.pi / 2   // 溜め中に向きを変えても、ビームは発動時の向き
        w.run(seconds: 1.5)
        XCTAssertGreaterThan(w.damage(to: e), 0)
        XCTAssertEqual(w.damage(to: other), 0)
    }

    func testHardCCDuringChargeCancelsTheBeam() {
        var w = SkillWorld()
        let k = addRaina(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(600, 0))
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.tick(3)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 0.8))
        w.run(seconds: 2)
        XCTAssertEqual(w.damage(to: e), 0, "スタンで溜めが途切れる")
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k), 0)
        XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(.ultimate), 0, "消費したクールダウンは戻らない")
        XCTAssertTrue(w.s.projectiles.isEmpty)
    }

    func testDeathDuringChargeCancelsTheBeamAndResetsKit() {
        var w = SkillWorld()
        let k = addRaina(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(600, 0))
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        mark(&w, owner: k, on: e)
        w.tick(2)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k), 0)
        w.run(seconds: 1.5)
        XCTAssertEqual(damageEvents(w, to: e, .skill(.ultimate)).count, 0)
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: k, slot: .skill1))
        XCTAssertFalse(w.cast(k, .skill1, .direction(Self.east)), "死亡中は撃てない")
        XCTAssertEqual(w.kit(k).rainaDetonations, 0)
        XCTAssertEqual(w.kit(k).rainaRangeBuff, 0)
    }

    // MARK: - 端の場合

    func testNoTargetCastsStillSpendButNothingBreaks() {
        var w = SkillWorld()
        let k = addRaina(&w)
        for slot in SkillSlot.actives {
            let before = w.s.units[k].resource
            XCTAssertTrue(w.cast(k, slot, .none), "\(slot)")
            XCTAssertLessThan(w.s.units[k].resource, before)
            XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(slot), 0)
        }
        w.run(seconds: 3)
        XCTAssertTrue(w.damageEvents.isEmpty)
        XCTAssertFalse(w.s.units[k].has(.speedBoost))
        XCTAssertEqual(w.kit(k).rainaDetonations, 0)
        XCTAssertTrue(w.s.projectiles.allSatisfy { $0.done } || w.s.projectiles.isEmpty)
        // 自動照準（敵ヒーローが射程内にいれば向く）
        let e = w.addDummyEnemy(at: skillArena + Vec2(0, 500))
        w.run(seconds: 12)
        XCTAssertTrue(w.cast(k, .skill1, .none))
        w.run(seconds: 1)
        XCTAssertGreaterThan(w.damage(to: e, from: .skill(.skill1)), 0)
    }

    func testCastBlockedWhileStunnedAndSilencedAndPracticeHasNoCooldowns() {
        var w = SkillWorld()
        let k = addRaina(&w)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 0.5))
        for slot in SkillSlot.actives { XCTAssertFalse(w.cast(k, slot, .none), "\(slot)") }
        w.run(seconds: 0.6)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .silence, duration: 0.5))
        for slot in SkillSlot.actives { XCTAssertFalse(w.cast(k, slot, .none), "\(slot)") }
        XCTAssertTrue(w.damageEvents.isEmpty)

        var p = SkillWorld(noCooldowns: true)
        let pk = addRaina(&p)
        let e = p.addDummyEnemy(at: skillArena + Vec2(400, 0))
        for slot in SkillSlot.actives {
            XCTAssertTrue(p.cast(pk, slot, .direction(Self.east)), "\(slot)")
            XCTAssertEqual(p.s.units[pk].hero!.cooldown(slot), 0, "練習場は CD なし")
        }
        XCTAssertEqual(p.s.units[pk].resource, p.s.units[pk].stats.maxResource, accuracy: 1e-9, "コストも無し")
        p.run(seconds: 1.5)
        XCTAssertGreaterThan(p.damage(to: e), 0)
    }

    func testManaCostFollowsTheOfficialTableAndCooldownStartsOnCast() {
        var w = SkillWorld()
        let k = addRaina(&w)
        for (slot, mp) in [(SkillSlot.skill1, 35.0), (.skill2, 70), (.ultimate, 130)] {
            let n = w.numbers(k, slot)
            XCTAssertEqual(n.cost, mp, "公式のマナ（ランク 1）")
            XCTAssertNotEqual(skill(slot).cost, mp, "マスターのコストではない")
            let before = w.s.units[k].resource
            XCTAssertTrue(w.cast(k, slot, .direction(Self.east)))
            XCTAssertEqual(before - w.s.units[k].resource, mp, accuracy: 1e-9)
            XCTAssertEqual(w.s.units[k].hero!.cooldown(slot), n.cooldown, accuracy: 1e-9)
            XCTAssertFalse(w.cast(k, slot, .direction(Self.east)), "CD 中")
        }
    }

    // MARK: - 決定性

    private func script(_ w: inout SkillWorld, k: Int, step: Int) {
        switch step {
        case 0: w.cast(k, .skill2, .direction(Self.east))
        case 1: w.s.units[k].attackTargetID = w.s.units.first { $0.team == .red && $0.kind == .hero }?.id
        case 2: w.cast(k, .skill1, .direction(Self.east))
        case 3: w.cast(k, .ultimate, .direction(Self.east))
        default: break
        }
    }

    private func makeScriptWorld() -> (SkillWorld, Int) {
        var w = SkillWorld()
        let k = addRaina(&w, ranks: [2, 2, 2])
        w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        w.addDummyEnemy(at: skillArena + Vec2(520, 150), hero: "H004")
        w.addMinion(team: .red, at: skillArena + Vec2(900, 40))
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
        XCTAssertGreaterThan(a.kit(ka).rainaDetonations, 0, "台本が刻印の炸裂まで通っている")
        XCTAssertFalse(a.damageEvents.filter { $0.source == .skill(.ultimate) }.isEmpty)
    }

    func testJSONRoundTripMidFightResumesIdentically() throws {
        var (a, ka) = makeScriptWorld()
        runScript(&a, k: ka, from: 0, to: 12)

        var (b, kb) = makeScriptWorld()
        runScript(&b, k: kb, from: 0, to: 3)
        // 途中（刻印・射程延長・加速・溜めが生きている）: 奥義を撃った直後
        script(&b, k: kb, step: 3)
        b.tick(4)
        XCTAssertFalse(b.kit(kb).scheduled.isEmpty, "溜め中にシリアライズする")
        XCTAssertTrue(b.s.units[kb].statuses.contains { $0.tag == T.ultRangeTag })
        let data = try JSONEncoder().encode(b.s)
        var resumed = b
        resumed.s = try JSONDecoder().decode(SimState.self, from: data)
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        b.run(seconds: 0.45 - 4 * Balance.dt)
        resumed.run(seconds: 0.45 - 4 * Balance.dt)
        runScript(&b, k: kb, from: 4, to: 12)
        runScript(&resumed, k: kb, from: 4, to: 12)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.s.zones, b.s.zones)
        XCTAssertEqual(resumed.s.projectiles, b.s.projectiles)
        XCTAssertEqual(resumed.log.count, b.log.count)
        _ = a.s
    }

    func testStateHashSeesMarksAndRaina() {
        var (a, ka) = makeScriptWorld()
        var (b, kb) = makeScriptWorld()
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        let e = b.s.units.firstIndex { $0.team == .red && $0.kind == .hero }!
        mark(&b, owner: kb, on: e)
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash())
        a.s.units[ka].hero!.kit!.rainaDetonations = 1
        b.s.units[kb].statuses.removeAll { $0.kind == .mark }
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash())
    }

    // MARK: - ボットの煙テスト

    /// 標準マップの ボット戦で、青のレンジャー枠をライナに置き換える。
    private func botConfig(seed: UInt64) -> MatchConfig {
        var cfg = MatchFactory.botMatch(seed: seed)
        let pos = MatchFactory.defaultPosition(for: .ranger)
        for j in cfg.players.indices where cfg.players[j].heroID == "H030" { cfg.players[j].heroID = "H003" }
        if let idx = cfg.players.firstIndex(where: { $0.team == .blue && $0.position == pos }) {
            cfg.players[idx].heroID = "H030"
            cfg.players[idx].displayName = "Raina_AI"
        }
        return cfg
    }

    func testBotPlaysRainaForTwoMinutesWithAllSlotsAndSaneState() throws {
        var casts: [SkillSlot: Int] = [:]
        var skillDamage: [SkillSlot: Double] = [:]
        var found = false
        for seed in [UInt64(11), 12, 13, 14, 15] {
            let sim = Simulation(config: botConfig(seed: seed))
            guard let ri = sim.state.heroIndices.first(where: { sim.state.units[$0].hero?.heroID == "H030" }) else {
                continue
            }
            found = true
            let rainaID = sim.state.units[ri].id
            XCTAssertNotNil(sim.state.units[ri].hero?.kit, "ボットのライナにも KitState が付く")
            casts = [:]
            skillDamage = [:]
            var peakRange = 0.0
            while !sim.isEnded && sim.state.time < 180 {
                // 奥義は「倒せる / 2 体以上を巻き込む」ときだけ撃つ AI で、試合の流れ次第では 3 分間に S2 も出ない。
                // 120 秒以降は 15 秒おきに自動照準で S2・奥義を撃たせ、溜め・爆発・ビームの状態遷移も通す（S1 は AI の判断のまま）
                var commands: [HeroCommand] = []
                if sim.state.time >= 120, sim.state.tick % 450 == 0 {
                    commands.append(HeroCommand(heroID: rainaID, command: .castSkill(slot: .ultimate, target: .none)))
                } else if sim.state.time >= 120, sim.state.tick % 450 == 150 {
                    commands.append(HeroCommand(heroID: rainaID, command: .castSkill(slot: .skill2, target: .none)))
                }
                for e in sim.step(commands: commands) {
                    switch e {
                    case .skillCast(let c) where c.casterID == rainaID:
                        casts[c.slot, default: 0] += 1
                    case .damage(let d) where d.sourceID == rainaID:
                        if case .skill(let slot) = d.source { skillDamage[slot, default: 0] += d.amount }
                    default:
                        break
                    }
                }
                guard let i = sim.state.index(of: rainaID) else { break }
                let u = sim.state.units[i]
                XCTAssertTrue(u.hp.isFinite && u.pos.x.isFinite && u.pos.y.isFinite && u.resource.isFinite)
                XCTAssertGreaterThanOrEqual(u.resource, 0)
                peakRange = max(peakRange, u.stats.attackRange)
                if let k = u.hero?.kit {
                    XCTAssertTrue(k.timers.allSatisfy { $0 >= 0 && $0.isFinite })
                    XCTAssertTrue(k.reals.allSatisfy { $0.isFinite })
                    XCTAssertLessThanOrEqual(k.scheduled.count, 2)
                    XCTAssertTrue(k.windows.allSatisfy { !$0.isOpen }, "再使用の窓は使わない")
                    XCTAssertNil(k.sweep)
                }
                for st in u.statuses where st.kind == .speedBoost {
                    XCTAssertTrue(st.magnitude >= 0 && st.magnitude <= T.rushSpeed + 1e-9)
                }
            }
            XCTAssertGreaterThan(peakRange, def.attackRange, "射程延長が実際に効いている")
            if casts[.skill1, default: 0] > 0, casts[.skill2, default: 0] > 0, casts[.ultimate, default: 0] > 0 { break }
        }
        XCTAssertTrue(found)
        XCTAssertGreaterThan(casts[.skill1, default: 0], 0, "S1: \(casts)")
        XCTAssertGreaterThan(casts[.skill2, default: 0], 0, "S2: \(casts)")
        XCTAssertGreaterThan(casts[.ultimate, default: 0], 0, "奥義: \(casts)")
        XCTAssertGreaterThan(skillDamage[.skill1, default: 0], 0)
        XCTAssertGreaterThan(skillDamage[.skill2, default: 0], 0)
    }

    // MARK: - 1v1 の TTK（ロール代表との総当たり）

    func testDuelTimeToKillAgainstRoleRepresentativesStaysInBand() {
        var failures: [String] = []
        for level in SkillBalanceTests.levels {
            for foe in SkillBalanceTests.representatives {
                let r = SkillBalanceTests.duel("H030", foe, level: level)
                print(String(format: "H030 duel Lv%d vs %@: %.1f s winner=%@ hp=%.2f", level, foe, r.ttk, r.winnerIsA.map { $0 ? "H030" : foe } ?? "-", r.remainingHPRatio))
                if r.ttk < SkillBalanceTests.minTTK || r.ttk > SkillBalanceTests.maxTTK {
                    failures.append(String(format: "Lv%d H030 vs %@: %.2f s", level, foe, r.ttk))
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures)")
    }
}

private extension SkillWorld {
    /// 指定の演出 ID（visual）で作られたゾーンの数。
    func zoneCount(visual: String) -> Int {
        log.filter { if case .zoneCreated(_, _, _, let v, _, _, _, _, _) = $0 { return v == visual } else { return false } }.count
    }
}
