import XCTest
@testable import VelstriaCore

final class CombatStatusTests: XCTestCase {

    private func remaining(_ w: CombatWorld, _ t: Int, _ kind: StatusKind) -> Double? {
        w.s.units[t].statuses.filter { $0.kind == kind }.map(\.remaining).max()
    }

    func testCrowdControlDurationsFollowBalance() {
        var w = CombatWorld()
        let src = w.addHero(team: .blue, at: Vec2(1000, 1000))
        let a = w.addHero(team: .red, at: Vec2(1100, 1000))
        let b = w.addHero(team: .red, at: Vec2(1100, 1200))
        let from = w.s.units[src].pos
        let sid = w.id(src)

        CombatSystem.applyCC(&w.s, w.ctx, sourceID: sid, targetIndex: a, cc: .stun, isUltimate: false, from: from)
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: sid, targetIndex: b, cc: .stun, isUltimate: true, from: from)
        XCTAssertEqual(remaining(w, a, .stun), Balance.stunDuration)
        XCTAssertEqual(remaining(w, b, .stun), Balance.ultStunDuration)

        CombatSystem.applyCC(&w.s, w.ctx, sourceID: sid, targetIndex: a, cc: .root, isUltimate: false, from: from)
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: sid, targetIndex: b, cc: .root, isUltimate: true, from: from)
        XCTAssertEqual(remaining(w, a, .root), Balance.rootDuration)
        XCTAssertEqual(remaining(w, b, .root), Balance.ultRootDuration)

        CombatSystem.applyCC(&w.s, w.ctx, sourceID: sid, targetIndex: a, cc: .slow, isUltimate: false, from: from)
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: sid, targetIndex: b, cc: .slow, isUltimate: true, from: from)
        XCTAssertEqual(w.s.units[a].status(.slow)?.magnitude, Balance.slowPct)
        XCTAssertEqual(w.s.units[a].status(.slow)?.remaining, Balance.slowDuration)
        XCTAssertEqual(w.s.units[b].status(.slow)?.magnitude, Balance.ultSlowPct)
        XCTAssertEqual(w.s.units[b].status(.slow)?.remaining, Balance.ultSlowDuration)
        XCTAssertTrue(w.s.events.contains(.ccApplied(targetID: w.id(b), cc: .stun, duration: Balance.ultStunDuration)))
        XCTAssertFalse(w.s.units[a].canAct)
        XCTAssertFalse(w.s.units[a].canMove)

        // スタンは 0.75 秒で切れる
        w.tick(Int((Balance.stunDuration / Balance.dt).rounded(.up)))
        XCTAssertNil(remaining(w, a, .stun))
        XCTAssertNotNil(remaining(w, b, .stun))
    }

    func testCCImmunityAndStructuresBlockCrowdControl() {
        var w = CombatWorld()
        let src = w.addHero(team: .blue, at: Vec2(1000, 1000))
        let hero = w.addHero(team: .red, at: Vec2(1100, 1000))
        let tower = w.addUnit(.tower, team: .red, at: Vec2(1500, 1500), radius: 110)
        CombatSystem.addStatus(&w.s, targetIndex: hero, StatusEffect(kind: .ccImmune, duration: 1.5))

        for cc in [CrowdControl.stun, .root, .slow, .knockback] {
            CombatSystem.applyCC(&w.s, w.ctx, sourceID: w.id(src), targetIndex: hero, cc: cc, isUltimate: true,
                                 from: w.s.units[src].pos)
            CombatSystem.applyCC(&w.s, w.ctx, sourceID: w.id(src), targetIndex: tower, cc: cc, isUltimate: true,
                                 from: w.s.units[src].pos)
        }
        // 生の行動阻害ステータスも同様に防ぐ
        CombatSystem.addStatus(&w.s, targetIndex: hero, StatusEffect(kind: .stun, duration: 1))
        CombatSystem.addStatus(&w.s, targetIndex: tower, StatusEffect(kind: .burn, duration: 1, magnitude: 10))
        XCTAssertEqual(w.s.units[hero].statuses.map(\.kind), [.ccImmune])
        XCTAssertTrue(w.s.units[tower].statuses.isEmpty)
        XCTAssertNil(w.s.units[hero].displacement)
        XCTAssertNil(w.s.units[tower].displacement)
        // 浄化で外れない弱体（回復阻害）は CC 無効でも付与される
        CombatSystem.addStatus(&w.s, targetIndex: hero, StatusEffect(kind: .healReduction, duration: 1, magnitude: 0.5))
        XCTAssertTrue(w.s.units[hero].has(.healReduction))
    }

    func testKnockbackDisplacesThenStuns() {
        var w = CombatWorld()
        let src = w.addHero(team: .blue, at: Vec2(4900, 5000))
        let t = w.addHero(team: .red, at: Vec2(5000, 5000))
        w.s.units[t].windupRemaining = 0.2
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: w.id(src), targetIndex: t, cc: .knockback, isUltimate: false,
                             from: w.s.units[src].pos)

        XCTAssertEqual(w.s.units[t].displacement?.kind, .knockback)
        XCTAssertEqual(w.s.units[t].displacement?.to.x ?? 0, 5000 + Balance.knockbackDistance, accuracy: 1e-6)
        XCTAssertNil(w.s.units[t].windupRemaining, "ノックバックは前隙を取り消す")
        XCTAssertTrue(w.s.units[t].has(.airborne))
        XCTAssertTrue(w.s.events.contains(.ccApplied(targetID: w.id(t), cc: .knockback,
                                                     duration: Balance.knockbackTime + Balance.knockbackStun)))

        let pushTicks = Int((Balance.knockbackTime / Balance.dt).rounded(.up))
        w.tick(pushTicks)
        XCTAssertNil(w.s.units[t].displacement)
        XCTAssertEqual(w.s.units[t].pos.x, 5000 + Balance.knockbackDistance, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[t].pos.y, 5000, accuracy: 1e-6)
        XCTAssertFalse(w.s.units[t].canAct, "着地後も短いスタンが残る")

        w.tick(Int((Balance.knockbackStun / Balance.dt).rounded(.up)) + 1)
        XCTAssertTrue(w.s.units[t].canAct)
        XCTAssertTrue(w.s.units[t].canMove)
    }

    func testKnockbackStopsAtMapEdge() {
        var w = CombatWorld()
        let t = w.addHero(team: .red, at: Vec2(100, 6000))
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: nil, targetIndex: t, cc: .knockback, isUltimate: false,
                             from: Vec2(300, 6000))
        w.tick(20)
        XCTAssertGreaterThanOrEqual(w.s.units[t].pos.x, 0)
        XCTAssertLessThanOrEqual(w.s.units[t].pos.x, 100)
        XCTAssertNil(w.s.units[t].displacement)
    }

    func testSlowUsesStrongestOnlyAndBoostsAdd() {
        var st = CombatWorld.stats(moveSpeed: 300)
        let statuses = [
            StatusEffect(kind: .slow, duration: 2, magnitude: 0.30, tag: "a"),
            StatusEffect(kind: .slow, duration: 2, magnitude: 0.45, tag: "b"),
            StatusEffect(kind: .slow, duration: 2, magnitude: 0.10, tag: "c"),
            StatusEffect(kind: .speedBoost, duration: 2, magnitude: 0.20, tag: "x"),
            StatusEffect(kind: .speedBoost, duration: 2, magnitude: 0.10, tag: "y"),
        ]
        StatusModifiers.apply(statuses, to: &st)
        XCTAssertEqual(st.moveSpeed, 300 * 1.3 * 0.55, accuracy: 1e-9)

        // 実際の再計算経路（非ヒーロー）でも同じ
        var w = CombatWorld()
        let m = w.addUnit(.monster, team: .neutral, at: Vec2(3000, 3000), stats: CombatWorld.stats(moveSpeed: 300))
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: nil, targetIndex: m, cc: .slow, isUltimate: false, from: .zero)
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: nil, targetIndex: m, cc: .slow, isUltimate: true, from: .zero)
        StatCalculator.recompute(&w.s, m, w.ctx)
        XCTAssertEqual(w.s.units[m].stats.moveSpeed, 300 * (1 - Balance.ultSlowPct), accuracy: 1e-9)
        // 強いスロー（2.0s）が切れると弱いスローだけが残る
        w.tick(Int((Balance.slowDuration / Balance.dt).rounded(.up)))
        StatCalculator.recompute(&w.s, m, w.ctx)
        XCTAssertEqual(w.s.units[m].stats.moveSpeed, 300 * (1 - Balance.ultSlowPct), accuracy: 1e-9)
        w.tick(Int(((Balance.ultSlowDuration - Balance.slowDuration) / Balance.dt).rounded(.up)))
        StatCalculator.recompute(&w.s, m, w.ctx)
        XCTAssertEqual(w.s.units[m].stats.moveSpeed, 300, accuracy: 1e-9)
    }

    func testStatusWithSameTagRefreshesInsteadOfStacking() {
        var w = CombatWorld()
        let t = w.addHero(team: .red, at: Vec2(1000, 1000))
        CombatSystem.addStatus(&w.s, targetIndex: t, StatusEffect(kind: .damageBoost, duration: 2, magnitude: 0.1, tag: "q"))
        CombatSystem.addStatus(&w.s, targetIndex: t, StatusEffect(kind: .damageBoost, duration: 1, magnitude: 0.3, tag: "q"))
        CombatSystem.addStatus(&w.s, targetIndex: t, StatusEffect(kind: .damageBoost, duration: 1, magnitude: 0.2, tag: "r"))
        let q = w.s.units[t].statuses.filter { $0.tag == "q" }
        XCTAssertEqual(q.count, 1)
        XCTAssertEqual(q[0].remaining, 2)
        XCTAssertEqual(q[0].magnitude, 0.3)
        XCTAssertEqual(w.s.units[t].statuses.count, 2)
    }

    func testRedBuffBurnDealsExactTotalCreditedToSource() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(1000, 1000), stats: CombatWorld.stats(attack: 0))
        let v = w.addHero(team: .red, at: Vec2(1100, 1000), stats: CombatWorld.stats(hp: 5000))
        w.s.units[a].hero?.level = 5
        CombatSystem.addStatus(&w.s, targetIndex: a, StatusEffect(kind: .redBuff, duration: 90))

        let hit = HitPayload(damage: 0, damageType: .physical, source: .basicAttack, appliesOnHit: true)
        CombatSystem.applyHit(&w.s, w.ctx, sourceID: w.id(a), team: .blue, targetIndex: v, payload: hit,
                              from: w.s.units[a].pos)
        let burn = w.s.units[v].status(.burn)
        XCTAssertNotNil(burn)
        XCTAssertEqual(burn?.sourceID, w.id(a))
        XCTAssertEqual(w.s.units[v].status(.slow)?.magnitude, Balance.combatRedBuffSlowPct)
        XCTAssertEqual(w.s.units[v].status(.slow)?.remaining, Balance.combatRedBuffSlowDuration)

        w.tick(Int((Balance.combatRedBuffBurnDuration / Balance.dt).rounded()) + 2)
        let expected = Balance.combatRedBuffBurnBase + Balance.combatRedBuffBurnPerLevel * 5
        XCTAssertEqual(5000 - w.s.units[v].hp, expected, accuracy: 1e-6)
        XCTAssertFalse(w.s.units[v].has(.burn))
        let dots = w.damageEvents.filter { $0.source == .dot }
        XCTAssertEqual(dots.count, 6, "0.5 秒刻みで 6 回")
        XCTAssertTrue(dots.allSatisfy { $0.sourceID == w.id(a) && $0.damageType == .trueDamage })
        XCTAssertEqual(w.s.units[a].hero?.score.damageToHeroes ?? 0, expected, accuracy: 1e-6)
    }

    func testCleanseRemovesOnlyCleansableDebuffs() {
        var w = CombatWorld()
        let t = w.addHero(team: .blue, at: Vec2(1000, 1000))
        for kind in [StatusKind.stun, .root, .slow, .silence, .burn, .healReduction, .damageDealtReduction,
                     .speedBoost, .blueBuff] {
            CombatSystem.addStatus(&w.s, targetIndex: t, StatusEffect(kind: kind, duration: 3, magnitude: 0.1))
        }
        CombatSystem.cleanse(&w.s, targetIndex: t)
        XCTAssertEqual(w.s.units[t].statuses.map(\.kind), [.speedBoost, .blueBuff])
    }

    func testShieldsAndEmpoweredAttackExpire() {
        var w = CombatWorld()
        let t = w.addHero(team: .blue, at: Vec2(1000, 1000))
        CombatSystem.addShield(&w.s, w.ctx, sourceID: nil, targetIndex: t, amount: 100, duration: 1)
        w.s.units[t].hero?.empoweredAttack = EmpoweredAttack(bonusDamage: 50, damageType: .magic, remaining: 0.5)
        w.tick(14)
        XCTAssertNotNil(w.s.units[t].hero?.empoweredAttack)
        w.tick(1)
        XCTAssertNil(w.s.units[t].hero?.empoweredAttack)
        XCTAssertEqual(w.s.units[t].shields.count, 1)
        w.tick(15)
        XCTAssertTrue(w.s.units[t].shields.isEmpty)
    }

    func testObjectiveBuffsAndDebuffModifiers() {
        var st = CombatWorld.stats()
        st.resourceRegen = 3
        st.healingReceivedMultiplier = 1
        StatusModifiers.apply([
            StatusEffect(kind: .blueBuff, duration: 90),
            StatusEffect(kind: .wyrmBlessing, duration: 150),
            StatusEffect(kind: .colossusBlessing, duration: 180),
            StatusEffect(kind: .damageBoost, duration: 1, magnitude: 0.05),
            StatusEffect(kind: .damageDealtReduction, duration: 1, magnitude: 0.3, tag: "a"),
            StatusEffect(kind: .damageDealtReduction, duration: 1, magnitude: 0.2, tag: "b"),
            StatusEffect(kind: .healReduction, duration: 1, magnitude: 0.5, tag: "a"),
            StatusEffect(kind: .healReduction, duration: 1, magnitude: 0.4, tag: "b"),
            StatusEffect(kind: .damageReduction, duration: 1, magnitude: 0.25),
            StatusEffect(kind: .attackSpeedBoost, duration: 1, magnitude: 0.5),
        ], to: &st)
        XCTAssertEqual(st.cooldownReduction, 0.15, accuracy: 1e-9)
        XCTAssertEqual(st.resourceRegen, 8, accuracy: 1e-9)
        XCTAssertEqual(st.damageBonus, 0.10 + 0.15 + 0.05 - 0.3, accuracy: 1e-9)
        XCTAssertEqual(st.healingReceivedMultiplier, 0.5, accuracy: 1e-9)
        XCTAssertEqual(st.damageReduction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(st.attackSpeed, 1.5, accuracy: 1e-9)
    }

    func testStunCancelsEnemyChannel() {
        var w = CombatWorld()
        let src = w.addHero(team: .blue, at: Vec2(1000, 1000))
        let t = w.addHero(team: .red, at: Vec2(1100, 1000))
        w.s.units[t].hero?.channel = Channel(kind: .recall, duration: 6)
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: w.id(src), targetIndex: t, cc: .stun, isUltimate: false,
                             from: w.s.units[src].pos)
        XCTAssertNil(w.s.units[t].hero?.channel)
    }
}
