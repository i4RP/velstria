import XCTest
@testable import VelstriaCore

final class CombatAttackTests: XCTestCase {

    private func releases(_ w: CombatWorld) -> Int {
        w.s.events.filter { if case .attackReleased = $0 { return true } else { return false } }.count
    }

    private func starts(_ w: CombatWorld) -> Int {
        w.s.events.filter { if case .attackStarted = $0 { return true } else { return false } }.count
    }

    func testMeleeAttackWindupAndCadenceMatchAttackSpeed() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000), stats: CombatWorld.stats(attackSpeed: 0.85))
        let t = w.addHero(team: .red, at: Vec2(5150, 5000), stats: CombatWorld.stats(hp: 1_000_000))
        w.s.units[a].attackTargetID = w.id(t)

        w.tick()
        XCTAssertEqual(starts(w), 1)
        let interval = 1 / 0.85
        XCTAssertEqual(w.s.units[a].windupRemaining ?? 0, interval * Balance.attackWindupRatio, accuracy: 1e-9)
        // 前隙が終わるまでは命中しない
        let windupTicks = Int((interval * Balance.attackWindupRatio / Balance.dt).rounded(.up))
        w.tick(windupTicks - 1)
        XCTAssertTrue(w.damageEvents.isEmpty)
        w.tick()
        XCTAssertEqual(w.damageEvents.count, 1)
        XCTAssertEqual(w.damageEvents[0].source, .basicAttack)
        XCTAssertEqual(w.s.units[a].hero?.basicAttackCount, 1)

        // 60 秒の命中数は攻撃速度どおり（端数の持ち越しで tick 丸めの誤差が蓄積しない）
        w.tick(1800 - windupTicks - 1)
        let expected = Int(((60 - interval * Balance.attackWindupRatio) / interval).rounded(.down)) + 1
        XCTAssertEqual(Double(releases(w)), Double(expected), accuracy: 1)
    }

    func testWindupCancelDoesNotConsumeAttack() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let t = w.addHero(team: .red, at: Vec2(5150, 5000))
        w.s.units[a].attackTargetID = w.id(t)
        w.tick(2)
        XCTAssertNotNil(w.s.units[a].windupRemaining)

        // 前隙中に射程外へ: 取り消し（攻撃は消費しない）→ 追跡
        w.s.units[t].pos = Vec2(5600, 5000)
        w.s.units[t].moveIntent = .none
        w.tick()
        XCTAssertNil(w.s.units[a].windupRemaining)
        XCTAssertEqual(w.s.units[a].attackCooldown, 0)
        XCTAssertTrue(w.damageEvents.isEmpty)
        if case .follow(let fid, _) = w.s.units[a].moveIntent {
            XCTAssertEqual(fid, w.id(t))
        } else {
            XCTFail("射程外の対象は追跡する")
        }

        // 戻ってくれば即座に前隙を開始できる
        w.s.units[t].pos = w.s.units[a].pos + Vec2(150, 0)
        w.tick()
        XCTAssertNotNil(w.s.units[a].windupRemaining)
        XCTAssertEqual(starts(w), 2)

        // 不可視化でも取り消し、対象は外れる
        w.s.units[t].visibleMask = Team.red.visionBit
        w.tick()
        XCTAssertNil(w.s.units[a].windupRemaining)
        XCTAssertNil(w.s.units[a].attackTargetID)
        XCTAssertEqual(w.s.units[a].attackCooldown, 0)
        XCTAssertTrue(w.damageEvents.isEmpty)
    }

    func testWalkingTargetWithinLeewayDoesNotCancelWindup() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let t = w.addHero(team: .red, at: Vec2(5150, 5000))
        w.s.units[a].attackTargetID = w.id(t)
        w.tick(2)
        XCTAssertNotNil(w.s.units[a].windupRemaining)
        // 歩いて逃げる程度（射程外 100）なら前隙は続き、攻撃は命中する
        let reach = 150 + 2 * Balance.heroRadius
        w.s.units[t].pos = w.s.units[a].pos + Vec2(reach + 100, 0)
        w.tick(12)
        XCTAssertEqual(w.damageEvents.map(\.targetID), [w.id(t)])
        XCTAssertEqual(starts(w), 1)
    }

    func testAttackCommandIntentResetDoesNotStallChase() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000), stats: CombatWorld.stats(moveSpeed: 300))
        let t = w.addHero(team: .red, at: Vec2(5000, 5000) + Vec2(1, 1).normalized * 800)
        w.s.units[a].attackTargetID = w.id(t)
        // 攻撃コマンド直後の状態（意図は .none）でも、同じ tick の移動で追跡する
        w.s.units[a].moveIntent = .none
        MovementSystem.update(&w.s, w.ctx)
        XCTAssertEqual(w.s.units[a].pos.distance(to: Vec2(5000, 5000)), 10, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[a].moveIntent,
                       .follow(targetID: w.id(t), range: 150 - Balance.combatFollowRangeMargin))

        // 射程内・対象なし・構造物は追跡しない
        let b = w.addHero(team: .blue, at: Vec2(6000, 6000))
        w.s.units[b].moveIntent = .none
        let tower = w.addUnit(.tower, team: .blue, at: Vec2(3000, 3000), radius: 110,
                              stats: CombatWorld.stats(range: 750))
        w.s.units[tower].attackTargetID = w.id(t)
        MovementSystem.update(&w.s, w.ctx)
        XCTAssertEqual(w.s.units[b].pos, Vec2(6000, 6000))
        XCTAssertEqual(w.s.units[b].moveIntent, .none)
        XCTAssertEqual(w.s.units[tower].moveIntent, .none)
    }

    func testStunDuringWindupCancelsWithoutConsuming() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let t = w.addHero(team: .red, at: Vec2(5150, 5000))
        w.s.units[a].attackTargetID = w.id(t)
        w.tick(2)
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: w.id(t), targetIndex: a, cc: .stun, isUltimate: false,
                             from: w.s.units[t].pos)
        XCTAssertNil(w.s.units[a].windupRemaining)
        w.tick(Int((Balance.stunDuration / Balance.dt).rounded(.up)) + 1)
        XCTAssertEqual(starts(w), 2, "スタン明けに攻撃を再開する")
        XCTAssertEqual(w.s.units[a].attackTargetID, w.id(t))
    }

    private func critSequence(seed: UInt64, attacks: Int) -> [Bool] {
        var w = CombatWorld(seed: seed)
        var st = CombatWorld.stats(attackSpeed: 2.5)
        st.critChance = 0.5
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000), stats: st)
        let t = w.addHero(team: .red, at: Vec2(5150, 5000), stats: CombatWorld.stats(hp: 1_000_000))
        w.s.units[a].attackTargetID = w.id(t)
        while w.damageEvents.count < attacks { w.tick() }
        return w.damageEvents.prefix(attacks).map(\.isCrit)
    }

    func testCritRollIsDeterministicBySeed() {
        let a = critSequence(seed: 42, attacks: 40)
        let b = critSequence(seed: 42, attacks: 40)
        let c = critSequence(seed: 4242, attacks: 40)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        let crits = a.filter { $0 }.count
        XCTAssertGreaterThan(crits, 8)
        XCTAssertLessThan(crits, 32)
    }

    func testCritMultiplierAndGuaranteedCrit() {
        var w = CombatWorld()
        var st = CombatWorld.stats(attack: 100)
        st.critChance = 1
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000), stats: st)
        let t = w.addHero(team: .red, at: Vec2(5150, 5000), stats: CombatWorld.stats(hp: 10_000))
        let rngBefore = w.s.rng
        CombatSystem.releaseAttack(&w.s, w.ctx, attacker: a, target: t)
        XCTAssertEqual(w.damageEvents.first?.amount ?? 0, 100 * Balance.critMultiplier, accuracy: 1e-9)
        XCTAssertEqual(w.damageEvents.first?.isCrit, true)
        XCTAssertEqual(w.s.rng, rngBefore, "確定クリティカルは乱数を消費しない")
    }

    func testRangedHeroFiresHomingProjectile() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000), ranged: true,
                          stats: CombatWorld.stats(attack: 80, range: 550))
        let t = w.addHero(team: .red, at: Vec2(5500, 5000), stats: CombatWorld.stats(hp: 5000))
        w.s.units[a].attackTargetID = w.id(t)
        let windupTicks = Int((Balance.attackWindupRatio / Balance.dt).rounded(.up)) + 1
        w.tick(windupTicks)
        XCTAssertEqual(w.s.projectiles.count, 1)
        XCTAssertEqual(w.s.projectiles.first?.visual, "basic_attack")
        XCTAssertEqual(w.s.projectiles.first?.speed, Balance.heroProjectileSpeed)
        XCTAssertTrue(w.s.events.contains(.attackReleased(sourceID: w.id(a), targetID: w.id(t), isRanged: true)))
        XCTAssertTrue(w.damageEvents.isEmpty)
        XCTAssertEqual(w.s.units[a].hero?.basicAttackCount, 0)

        w.tick(10)
        XCTAssertEqual(w.damageEvents.count, 1)
        XCTAssertEqual(w.damageEvents.first?.amount ?? 0, 80, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[a].hero?.basicAttackCount, 1, "命中時に数える")
        XCTAssertTrue(w.s.projectiles.allSatisfy(\.done))
    }

    func testMinionAndStructureProjectileSpeeds() {
        var w = CombatWorld()
        let m = w.addMinion(.ranged, team: .blue, at: Vec2(5000, 5000))
        let tower = w.addUnit(.tower, team: .blue, at: Vec2(5000, 5400), radius: 110,
                              stats: CombatWorld.stats(attack: 200, range: 750))
        let t = w.addMinion(.melee, team: .red, at: Vec2(5300, 5000))
        CombatSystem.releaseAttack(&w.s, w.ctx, attacker: m, target: t)
        CombatSystem.releaseAttack(&w.s, w.ctx, attacker: tower, target: t)
        XCTAssertEqual(w.s.projectiles.map(\.speed),
                       [Balance.combatMinionProjectileSpeed, Balance.combatStructureProjectileSpeed])
        XCTAssertEqual(w.s.projectiles.map(\.visual), ["basic_attack", "tower_shot"])
        XCTAssertEqual(w.s.projectiles[1].payload.damageType, .trueDamage, "対ミニオンのタワー弾は割合ダメージをそのまま削る")
    }

    func testEmpoweredAttackAddsBonusInstanceAndIsConsumed() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000), stats: CombatWorld.stats(attack: 100))
        let t = w.addHero(team: .red, at: Vec2(5150, 5000), stats: CombatWorld.stats(hp: 5000, armor: 100))
        w.s.units[a].hero?.empoweredAttack = EmpoweredAttack(bonusDamage: 80, damageType: .magic, cc: .stun)
        CombatSystem.releaseAttack(&w.s, w.ctx, attacker: a, target: t)

        XCTAssertEqual(w.damageEvents.map(\.amount), [50, 80])
        XCTAssertEqual(w.damageEvents.map(\.damageType), [.physical, .magic])
        XCTAssertNil(w.s.units[a].hero?.empoweredAttack)
        XCTAssertTrue(w.s.units[t].has(.stun))
        XCTAssertEqual(w.s.units[a].hero?.basicAttackCount, 1, "追加分は別の通常攻撃として数えない")

        // 遠隔は追加分を別の追尾弾で運ぶ
        var r = CombatWorld()
        let ra = r.addHero(team: .blue, at: Vec2(5000, 5000), ranged: true, stats: CombatWorld.stats(range: 550))
        let rt = r.addHero(team: .red, at: Vec2(5400, 5000), stats: CombatWorld.stats(hp: 5000))
        r.s.units[ra].hero?.empoweredAttack = EmpoweredAttack(bonusDamage: 60, damageType: .magic, visual: "fx_emp")
        CombatSystem.releaseAttack(&r.s, r.ctx, attacker: ra, target: rt)
        XCTAssertEqual(r.s.projectiles.map(\.visual), ["basic_attack", "fx_emp"])
        r.tick(15)
        XCTAssertEqual(r.damageEvents.map(\.amount), [100, 60])
        XCTAssertEqual(r.s.units[ra].hero?.basicAttackCount, 1)
    }

    func testChasesOutOfRangeTargetThenAttacks() {
        var w = CombatWorld()
        // 中央レーンの中心線上で追跡させる（障害物に依存しない）
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let t = w.addHero(team: .red, at: Vec2(5000, 5000) + Vec2(1, 1).normalized * 800,
                          stats: CombatWorld.stats(hp: 100_000))
        w.s.units[a].attackTargetID = w.id(t)
        w.tick()
        XCTAssertEqual(w.s.units[a].moveIntent,
                       .follow(targetID: w.id(t), range: 150 - Balance.combatFollowRangeMargin))
        w.tick(80)
        XCTAssertFalse(w.damageEvents.isEmpty)
        let reach = 150 + 2 * Balance.heroRadius
        XCTAssertLessThanOrEqual(w.s.units[a].pos.distance(to: w.s.units[t].pos), reach)
        XCTAssertEqual(w.s.units[a].facing, .pi / 4, accuracy: 1e-9)
    }

    func testStructuresNeverChase() {
        var w = CombatWorld()
        let tower = w.addUnit(.tower, team: .blue, at: Vec2(5000, 5000), radius: 110,
                              stats: CombatWorld.stats(range: 750, moveSpeed: 0))
        let t = w.addHero(team: .red, at: Vec2(6500, 5000))
        w.s.units[tower].attackTargetID = w.id(t)
        w.tick(30)
        XCTAssertEqual(w.s.units[tower].moveIntent, .none)
        XCTAssertEqual(w.s.units[tower].pos, Vec2(5000, 5000))
        XCTAssertEqual(starts(w), 0)
    }

    func testInRangeMinionStopsLaneWalkButMonsterKeepsItsOwnMovement() {
        var w = CombatWorld()
        let target = w.addHero(team: .blue, at: Vec2(5000, 5000), stats: CombatWorld.stats(hp: 100_000))
        let minion = w.addMinion(.melee, team: .red, at: Vec2(5100, 5100))
        let monster = w.addUnit(.monster, team: .neutral, at: Vec2(4900, 4950), radius: 60,
                                stats: CombatWorld.stats(range: 150, moveSpeed: 0))
        w.s.units[minion].attackTargetID = w.id(target)
        w.s.units[minion].moveIntent = .point(Vec2(3000, 3000))
        w.s.units[monster].attackTargetID = w.id(target)
        w.s.units[monster].moveIntent = .point(Vec2(3500, 3500))
        CombatSystem.updateAttacks(&w.s, w.ctx)
        XCTAssertEqual(w.s.units[minion].moveIntent, .none, "ミニオンは射程内でレーン行進を止めて殴る")
        XCTAssertNotNil(w.s.units[minion].windupRemaining)
        XCTAssertEqual(w.s.units[monster].moveIntent, .point(Vec2(3500, 3500)), "モンスターの移動は MonsterSystem が決める")
        XCTAssertNotNil(w.s.units[monster].windupRemaining)
    }

    func testHeroesFirstPicksLowestEffectiveHealthHero() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let heroA = w.addHero(team: .red, at: Vec2(5100, 5000), stats: CombatWorld.stats(hp: 1000))
        w.addHero(team: .red, at: Vec2(5300, 5000), stats: CombatWorld.stats(hp: 700, armor: 100))
        let heroC = w.addHero(team: .red, at: Vec2(5000, 5400), stats: CombatWorld.stats(hp: 800))
        let far = w.addHero(team: .red, at: Vec2(6000, 5000), stats: CombatWorld.stats(hp: 10))
        let minion = w.addUnit(.minion, team: .red, at: Vec2(5050, 5000))

        XCTAssertEqual(CombatSystem.selectTarget(&w.s, w.ctx, attacker: a, priority: .heroesFirst), heroC)
        // 見えない敵は選ばない
        w.s.units[heroC].visibleMask = Team.red.visionBit
        XCTAssertEqual(CombatSystem.selectTarget(&w.s, w.ctx, attacker: a, priority: .heroesFirst), heroA)
        // ヒーローがいなければ最も近いユニット
        for i in w.s.units.indices where w.s.units[i].kind == .hero && w.s.units[i].team == .red {
            w.s.units[i].isAlive = false
        }
        XCTAssertEqual(CombatSystem.selectTarget(&w.s, w.ctx, attacker: a, priority: .heroesFirst), minion)
        XCTAssertNotEqual(CombatSystem.selectTarget(&w.s, w.ctx, attacker: a, priority: .heroesFirst), far)
    }

    func testMinionsFirstPrefersLastHit() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000), stats: CombatWorld.stats(attack: 100))
        w.addUnit(.minion, team: .red, at: Vec2(5300, 5000), stats: CombatWorld.stats(hp: 90))
        let armored = w.addUnit(.minion, team: .red, at: Vec2(5200, 5000), stats: CombatWorld.stats(hp: 50, armor: 100))
        w.addUnit(.minion, team: .red, at: Vec2(5250, 5100), stats: CombatWorld.stats(hp: 51, armor: 100))
        w.addHero(team: .red, at: Vec2(5100, 5000), stats: CombatWorld.stats(hp: 10))
        // 1 発で倒せる候補のうち最も近いもの（防御込みで 50 ダメージ → HP 50 は倒せる、51 は倒せない）
        XCTAssertEqual(CombatSystem.selectTarget(&w.s, w.ctx, attacker: a, priority: .minionsFirst), armored)

        var v = CombatWorld()
        let b = v.addHero(team: .blue, at: Vec2(5000, 5000), stats: CombatWorld.stats(attack: 10))
        v.addUnit(.minion, team: .red, at: Vec2(5100, 5000), stats: CombatWorld.stats(hp: 500))
        let low = v.addUnit(.monster, team: .neutral, at: Vec2(5300, 5000), stats: CombatWorld.stats(hp: 300))
        XCTAssertEqual(CombatSystem.selectTarget(&v.s, v.ctx, attacker: b, priority: .minionsFirst), low)
    }

    func testStructuresFirstAndLowestHealth() {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let tower = w.addUnit(.tower, team: .red, at: Vec2(5400, 5000), radius: 110, stats: CombatWorld.stats(hp: 4000))
        w.addUnit(.minion, team: .red, at: Vec2(5100, 5000), stats: CombatWorld.stats(hp: 300))
        let weak = w.addHero(team: .red, at: Vec2(5000, 5200), stats: CombatWorld.stats(hp: 200))
        XCTAssertEqual(CombatSystem.selectTarget(&w.s, w.ctx, attacker: a, priority: .structuresFirst), tower)
        XCTAssertEqual(CombatSystem.selectTarget(&w.s, w.ctx, attacker: a, priority: .lowestHealth), weak)
        // シールドも HP として数える
        CombatSystem.addShield(&w.s, w.ctx, sourceID: nil, targetIndex: weak, amount: 500, duration: 5)
        XCTAssertNotEqual(CombatSystem.selectTarget(&w.s, w.ctx, attacker: a, priority: .lowestHealth), weak)
    }
}
