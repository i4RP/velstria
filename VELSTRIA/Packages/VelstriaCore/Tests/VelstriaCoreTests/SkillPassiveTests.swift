import XCTest
@testable import VelstriaCore

/// ロール別パッシブ（DESIGN §6）。k = 1.0 + 0.02 × (番号 mod 5)。
final class SkillPassiveTests: XCTestCase {

    func testPassiveCoefficient() {
        XCTAssertEqual(SkillCatalog.passiveCoefficient(heroNumber: 5), 1.0)
        XCTAssertEqual(SkillCatalog.passiveCoefficient(heroNumber: 1), 1.02, accuracy: 1e-12)
        XCTAssertEqual(SkillCatalog.passiveCoefficient(heroNumber: 24), 1.08, accuracy: 1e-12)
    }

    // MARK: - Vanguard

    func testVanguardLowHealthShieldWithCooldown() {
        var w = SkillWorld()
        let v = w.addHero("H001", team: .blue, at: skillArena)   // k = 1.02
        let e = w.addHero("H003", team: .red, at: skillArena + Vec2(300, 0))
        let maxHP = w.s.units[v].stats.maxHP
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: v, amount: maxHP * 0.5,
                                 type: .trueDamage, source: .spell)
        XCTAssertEqual(w.s.units[v].totalShield, 0, "50% では発動しない")
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: v, amount: maxHP * 0.15,
                                 type: .trueDamage, source: .spell)
        XCTAssertEqual(w.s.units[v].totalShield, maxHP * 0.15 * 1.02, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[v].hero!.passive.cooldown, 20)
        // CD 中は再発動しない
        w.run(seconds: 5)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: v, amount: 100,
                                 type: .trueDamage, source: .spell)
        XCTAssertEqual(w.s.units[v].totalShield, 0, "シールドは 4 秒で切れ、CD 中は張り直さない")
        w.run(seconds: 15.1)
        XCTAssertEqual(w.s.units[v].hero!.passive.cooldown, 0)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: v, amount: 10,
                                 type: .trueDamage, source: .spell)
        XCTAssertGreaterThan(w.s.units[v].totalShield, 0)
    }

    // MARK: - Duelist

    func testDuelistAttackSpeedStacksCapAndExpire() {
        var w = SkillWorld()
        let d = w.addHero("H002", team: .blue, at: skillArena)   // k = 1.04
        let t = w.addHero("H013", team: .red, at: skillArena + Vec2(200, 0))
        let baseAS = w.s.units[d].stats.attackSpeed
        w.s.units[d].attackTargetID = w.id(t)
        w.run(seconds: 1.3)
        XCTAssertEqual(w.s.units[d].hero!.passive.stacks, 1)
        XCTAssertEqual(w.s.units[d].stats.attackSpeed, baseAS * (1 + 0.06 * 1.04), accuracy: 1e-9)
        w.run(seconds: 8)
        XCTAssertEqual(w.s.units[d].hero!.passive.stacks, 5, "最大 5 スタック")
        let buff = w.s.units[d].statuses.first { $0.tag == Balance.Skills.duelistPassiveTag }
        XCTAssertEqual(buff?.magnitude ?? 0, 0.06 * 1.04 * 5, accuracy: 1e-9)
        // 攻撃をやめると 3 秒で切れてスタックが戻る
        w.s.units[d].attackTargetID = nil
        w.run(seconds: 3.1)
        XCTAssertEqual(w.s.units[d].hero!.passive.stacks, 0)
        XCTAssertFalse(w.s.units[d].statuses.contains { $0.tag == Balance.Skills.duelistPassiveTag })
    }

    // MARK: - Ranger

    func testRangerEveryFourthAttackCritsWithCoefficient() {
        var w = SkillWorld()
        let r = w.addHero("H003", team: .blue, at: skillArena)   // k = 1.06
        let t = w.addHero("H013", team: .red, at: skillArena + Vec2(400, 0))
        let attack = w.s.units[r].stats.attack
        w.s.units[r].attackTargetID = w.id(t)
        w.run(seconds: 10.5)
        let hits = w.damageEvents.filter { $0.targetID == w.id(t) && $0.source == .basicAttack }
        XCTAssertGreaterThanOrEqual(hits.count, 8)
        for (n, h) in hits.enumerated() {
            XCTAssertEqual(h.isCrit, n % 4 == 3, "\(n + 1) 発目")
            let mult = h.isCrit ? 1.75 * 1.06 : 1
            XCTAssertEqual(h.amount, w.mitigated(attack * mult, .physical, on: t), accuracy: 1e-6)
        }
        XCTAssertEqual(w.s.units[r].stats.critMultiplier, Balance.critMultiplier, "倍率は次 tick の再計算で戻る")
    }

    // MARK: - Arcanist

    func testArcanistSkillHitRefundsOtherCooldownsOncePerCast() {
        var w = SkillWorld()
        let a = w.addHero("H004", team: .blue, at: skillArena)   // k = 1.08, Skill3 groundAoE
        let center = skillArena + Vec2(400, 0)
        w.addHero("H013", team: .red, at: center)
        w.addMinion(team: .red, at: center + Vec2(0, 60))
        w.s.units[a].hero!.skillCooldowns[SkillSlot.skill1.rawValue] = 5
        w.s.units[a].hero!.skillCooldowns[SkillSlot.ultimate.rawValue] = 20
        XCTAssertTrue(w.cast(a, .skill3, .point(center)))
        let s3 = w.s.units[a].hero!.cooldown(.skill3)
        w.run(seconds: 0.6)
        let elapsed = 0.6 + Balance.dt / 2
        // 2 体に命中しても 1 回だけ
        XCTAssertEqual(w.s.units[a].hero!.cooldown(.skill1), 5 - elapsed - 0.6 * 1.08, accuracy: 0.04)
        XCTAssertEqual(w.s.units[a].hero!.cooldown(.ultimate), 20 - elapsed - 0.6 * 1.08, accuracy: 0.04)
        XCTAssertEqual(w.s.units[a].hero!.cooldown(.skill3), s3 - elapsed, accuracy: 0.04, "自身の CD は短縮しない")
        // 外れた場合は短縮しない
        var m = SkillWorld()
        let a2 = m.addHero("H004", team: .blue, at: skillArena)
        m.s.units[a2].hero!.skillCooldowns[SkillSlot.skill3.rawValue] = 5
        XCTAssertTrue(m.cast(a2, .skill1, .direction(Vec2(1, 0))))
        m.run(seconds: 1)
        XCTAssertEqual(m.s.units[a2].hero!.cooldown(.skill3), 4, accuracy: 0.04)
    }

    // MARK: - Support

    func testSupportHealsLowestAllyOnCast() {
        var w = SkillWorld()
        let s = w.addHero("H005", team: .blue, at: skillArena, level: 3)   // k = 1.0
        let hurt = w.addHero("H001", team: .blue, at: skillArena + Vec2(600, 0))
        let hurter = w.addHero("H002", team: .blue, at: skillArena + Vec2(1000, 0))
        w.s.units[hurt].hp = w.s.units[hurt].stats.maxHP * 0.5
        w.s.units[hurter].hp = w.s.units[hurter].stats.maxHP * 0.2   // 800 の外
        let before = w.s.units[hurt].hp
        XCTAssertTrue(w.cast(s, .skill1, .direction(Vec2(0, 1))))
        XCTAssertEqual(w.s.units[hurt].hp, before + 40 + 10 * 3, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[hurter].hp, w.s.units[hurter].stats.maxHP * 0.2, accuracy: 1e-9)
        XCTAssertGreaterThan(w.s.units[s].hero!.score.healingDone, 0)
    }

    // MARK: - Assassin

    func testAssassinAmbushAfterLeavingBrushBoostsFirstHeroDamage() {
        var w = SkillWorld()
        let a = w.addHero("H006", team: .blue, at: skillArena)   // k = 1.02
        let t = w.addHero("H013", team: .red, at: skillArena + Vec2(200, 0))
        func hit() -> Double {
            CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a), targetIndex: t, amount: 100, type: .trueDamage,
                                     source: .basicAttack)
        }
        XCTAssertEqual(hit(), 100, accuracy: 1e-9, "隠れていなければ補正なし")
        w.s.units[a].brushIndex = 0
        w.tick()
        w.s.units[a].brushIndex = nil
        w.run(seconds: 2)
        // ミニオンへのダメージでは消費しない
        let m = w.addMinion(team: .red, at: skillArena + Vec2(0, 200))
        XCTAssertEqual(CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(a), targetIndex: m, amount: 50,
                                                type: .trueDamage, source: .basicAttack), 50, accuracy: 1e-9)
        XCTAssertEqual(hit(), 100 * (1 + 0.30 * 1.02), accuracy: 1e-9)
        XCTAssertEqual(hit(), 100, accuracy: 1e-9, "最初の 1 回だけ")
        // 3 秒を過ぎると無効
        w.s.units[a].brushIndex = 0
        w.tick()
        w.s.units[a].brushIndex = nil
        w.run(seconds: 3.1)
        XCTAssertEqual(hit(), 100, accuracy: 1e-9)
    }

    func testAssassinAmbushFromStealth() {
        var w = SkillWorld()
        let a = w.addHero("H006", team: .blue, at: skillArena)
        let t = w.addHero("H013", team: .red, at: skillArena + Vec2(200, 0))
        CombatSystem.addStatus(&w.s, targetIndex: a, StatusEffect(kind: .stealth, duration: 1))
        w.tick()
        // ステルス中の攻撃（スキル発動でステルス解除 → 奇襲）
        let n = w.numbers(a, .skill1)
        XCTAssertTrue(w.cast(a, .skill1, .unit(w.id(t))))
        XCTAssertFalse(w.s.units[a].has(.stealth), "スキル発動でステルス解除")
        XCTAssertEqual(w.damage(to: t), w.mitigated(n.damage * (1 + 0.30 * 1.02), .physical, on: t), accuracy: 1e-6)
    }

    func testAssassinTakedownRefundsCooldowns() {
        var w = SkillWorld()
        let a = w.addHero("H006", team: .blue, at: skillArena, level: 6)
        let victim = w.addHero("H003", team: .red, at: skillArena + Vec2(200, 0))
        w.s.units[a].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = 6
        w.s.units[a].hero!.skillCooldowns[SkillSlot.ultimate.rawValue] = 10
        w.s.units[victim].hp = 50
        let s1Before = SkillSystem.cooldown(for: w.ctx.master.skill(hero: "H006", slot: .skill1)!, rank: 1,
                                            cdr: w.s.units[a].stats.cooldownReduction)
        XCTAssertTrue(w.cast(a, .skill1, .unit(w.id(victim))))
        XCTAssertFalse(w.s.units[victim].isAlive)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertEqual(w.s.units[a].hero!.score.kills, 1)
        XCTAssertEqual(w.s.units[a].hero!.cooldown(.skill2), 6 * 0.7, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[a].hero!.cooldown(.ultimate), 10 * 0.7, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[a].hero!.cooldown(.skill1), s1Before * 0.7, accuracy: 1e-9)
    }

    func testPassivesOnlyApplyToTheirRole() {
        var w = SkillWorld()
        let duelist = w.addHero("H002", team: .blue, at: skillArena)
        let ranger = w.addHero("H003", team: .blue, at: skillArena + Vec2(0, 100))
        // デュエリストに 4 発目の確定クリティカルは無い / レンジャーに攻撃速度スタックは無い
        w.s.units[duelist].hero!.basicAttackCount = 3
        XCTAssertNil(PassiveHooks.forceCrit(&w.s, w.ctx, attacker: duelist))
        PassiveHooks.onBasicAttackHit(&w.s, w.ctx, attacker: ranger, target: duelist, damage: 10)
        XCTAssertFalse(w.s.units[ranger].statuses.contains { $0.kind == .attackSpeedBoost })
        w.s.units[ranger].hero!.basicAttackCount = 3
        XCTAssertEqual(PassiveHooks.forceCrit(&w.s, w.ctx, attacker: ranger), true)
        XCTAssertNil(PassiveHooks.forceCrit(&w.s, w.ctx, attacker: ranger), "同じ命中数で 2 度出さない")
        // 非ヒーロー（ミニオン）は何もしない
        let m = w.addMinion(team: .red, at: skillArena + Vec2(300, 0))
        XCTAssertEqual(PassiveHooks.outgoingDamageBonus(&w.s, w.ctx, attacker: m, target: duelist, source: .minion), 0)
        XCTAssertNil(PassiveHooks.forceCrit(&w.s, w.ctx, attacker: m))
    }
}
