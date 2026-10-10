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

    /// 紅焔バフ（MLBB の溶岩の魂）: 敵ヒーローに当たると 3 秒に 1 回、確定ダメージ（50 + 物攻 × 割合 + 対象の最大 HP × 割合）と
    /// スロー 1 秒。ヴァンガード（前衛）は物攻 20%・最大 HP 0.3%・スロー 60%・貫通 5%。ヒーロー以外には出ない。
    func testRedBuffStrikeHitsHeroesEveryThreeSeconds() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(1000, 1000), stats: CombatWorld.stats(attack: 100))
        let v = w.addHero(team: .red, at: Vec2(1100, 1000), stats: CombatWorld.stats(hp: 5000))
        let m = w.addUnit(.monster, team: .neutral, at: Vec2(900, 1000), stats: CombatWorld.stats(hp: 5000))
        CombatSystem.addStatus(&w.s, targetIndex: a, JungleBuffs.redBuff(for: w.s.units[a], sourceID: w.id(m)))
        XCTAssertEqual(w.s.units[a].status(.redBuff)?.magnitude ?? 0, Balance.Jungle.redFrontPenetration)
        XCTAssertEqual(w.s.units[a].status(.redBuff)?.remaining ?? 0, 75)

        let hit = HitPayload(damage: 10, damageType: .trueDamage, source: .basicAttack, appliesOnHit: true)
        func strike(_ t: Int) {
            CombatSystem.applyHit(&w.s, w.ctx, sourceID: w.id(a), team: .blue, targetIndex: t, payload: hit,
                                  from: w.s.units[a].pos)
        }
        let bonus = 50 + 100 * 0.20 + 5000 * 0.003
        strike(v)
        XCTAssertEqual(5000 - w.s.units[v].hp, 10 + bonus, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[v].status(.slow)?.magnitude ?? 0, 0.60, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[v].status(.slow)?.remaining ?? 0, 1, accuracy: 1e-9)
        XCTAssertTrue(w.damageEvents.contains { $0.sourceID == w.id(a) && $0.damageType == .trueDamage && $0.source == .passive })
        // 3 秒以内は出ない
        strike(v)
        XCTAssertEqual(5000 - w.s.units[v].hp, 20 + bonus, accuracy: 1e-6)
        w.tick(Int((Balance.Jungle.redStrikeCooldown / Balance.dt).rounded()) + 1)
        // モンスターには出ない
        strike(m)
        XCTAssertEqual(5000 - w.s.units[m].hp, 10, accuracy: 1e-6)
        // 3 秒経てば再び出る
        let before = w.s.units[v].hp
        strike(v)
        XCTAssertEqual(before - w.s.units[v].hp, 10 + bonus, accuracy: 1e-6)
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
        // 蒼晶バフは CD −10% のみ（消費の軽減は JungleBuffs）、竜の加護は能力値を直接変えない（シールドと攻撃力は JungleBuffs）
        XCTAssertEqual(st.cooldownReduction, 0.10, accuracy: 1e-9)
        XCTAssertEqual(st.resourceRegen, 3, accuracy: 1e-9)
        XCTAssertEqual(st.damageBonus, 0.15 + 0.05 - 0.3, accuracy: 1e-9)
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
