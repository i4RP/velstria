import XCTest
@testable import VelstriaCore

/// 装備の作り直し（Mobile Legends 準拠）で入った貫通・確定ダメージ・固有効果。
final class ItemEffectsTests: XCTestCase {
    private let spot = Vec2(6000, 6000)

    /// 攻撃側（blue）と受け側（red、防御・魔防 100 固定・HP 満タン）の 1v1。キットの補正は外す。
    private func duel(_ attackerItems: [String], victimItems: [String] = []) -> (EconomyFixture, Int, Int) {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0]
        let v = f.heroes(.red)[0]
        f.place(a, at: spot)
        f.place(v, at: spot + Vec2(150, 0))
        for i in [a, v] {
            f.s.units[i].hero!.kit = nil
            f.s.units[i].hero!.autoLevelSkills = false
            f.s.units[i].hero!.runes = []
        }
        f.s.units[a].hero!.items = attackerItems
        f.s.units[a].hero!.itemInvested = attackerItems.map { _ in 1000 }
        f.s.units[v].hero!.items = victimItems
        f.s.units[v].hero!.itemInvested = victimItems.map { _ in 1000 }
        StatCalculator.recompute(&f.s, a, f.ctx)
        StatCalculator.recompute(&f.s, v, f.ctx)
        f.s.units[v].stats.armor = 100
        f.s.units[v].stats.magicResist = 100
        f.s.units[v].stats.damageReduction = 0
        f.s.units[v].hp = f.s.units[v].stats.maxHP
        f.s.units[a].hp = f.s.units[a].stats.maxHP
        return (f, a, v)
    }

    @discardableResult
    private func hit(_ f: inout EconomyFixture, _ a: Int, _ v: Int, _ raw: Double, _ type: DamageType) -> Double {
        CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(a), targetIndex: v, amount: raw, type: type,
                                source: .skill(.skill1), isCrit: false, appliesOnHit: false)
    }

    // MARK: - 貫通

    func testWithoutPenetrationDefenseApplies() {
        var (f, a, v) = duel([])
        XCTAssertEqual(hit(&f, a, v, 1000, .physical),
                       1000 * CombatSystem.mitigationMultiplier(.physical, armor: 100, magicResist: 100), accuracy: 1e-6)
    }

    func testPhysicalPenetrationPercentIgnoresPartOfArmor() {
        var (f, a, v) = duel(["EQ061"])    // 物理貫通 40%
        XCTAssertEqual(hit(&f, a, v, 1000, .physical),
                       1000 * CombatSystem.mitigationMultiplier(.physical, armor: 60, magicResist: 100), accuracy: 1e-6)
        // 魔法ダメージは物理貫通の影響を受けない
        let magic = hit(&f, a, v, 1000, .magic)
        XCTAssertEqual(magic, 1000 * CombatSystem.mitigationMultiplier(.magic, armor: 100, magicResist: 100), accuracy: 1e-6)
    }

    func testPenetrationAppliesPercentThenFlat() {
        var (f, a, v) = duel(["EQ061", "EQ031"])    // 40% → 60、固定 15 → 45
        XCTAssertEqual(hit(&f, a, v, 1000, .physical),
                       1000 * CombatSystem.mitigationMultiplier(.physical, armor: 45, magicResist: 100), accuracy: 1e-6)
    }

    func testFlatPenetrationCannotGoBelowZero() {
        var (f, a, v) = duel(["EQ031", "EQ064"])    // 固定 15 + 15 = 30
        f.s.units[v].stats.armor = 20
        XCTAssertEqual(hit(&f, a, v, 1000, .physical),
                       1000 * CombatSystem.mitigationMultiplier(.physical, armor: 0, magicResist: 100), accuracy: 1e-6)
    }

    func testMagicPenetration() {
        var (f, a, v) = duel(["EQ044", "EQ020"])    // 割合 40% → 60、固定 12 → 48
        XCTAssertEqual(hit(&f, a, v, 1000, .magic),
                       1000 * CombatSystem.mitigationMultiplier(.magic, armor: 100, magicResist: 48), accuracy: 1e-6)
        XCTAssertEqual(hit(&f, a, v, 1000, .physical),
                       1000 * CombatSystem.mitigationMultiplier(.physical, armor: 100, magicResist: 48), accuracy: 1e-6)
    }

    func testTrueDamageIgnoresDefenseAndReduction() {
        var (f, a, v) = duel([])
        f.s.units[v].stats.damageReduction = 0.3
        XCTAssertEqual(hit(&f, a, v, 500, .trueDamage), 500 * CombatSystem.damageReductionMultiplier(0.3), accuracy: 1e-6)
        f.s.units[v].stats.damageReduction = 0
        XCTAssertEqual(hit(&f, a, v, 500, .trueDamage), 500, accuracy: 1e-6)
    }

    // MARK: - 確定ダメージの固有効果

    func testDivineJusticeAddsTrueDamageAndHealAfterASkill() {
        var (f, a, v) = duel(["EQ043"])
        let attack = f.s.units[a].stats.attack
        f.s.units[a].hp = f.s.units[a].stats.maxHP * 0.4
        let hp = f.s.units[v].hp
        // スキルを使っていなければ働かない
        ItemEffects.onBasicAttackLanded(&f.s, f.ctx, attacker: a, target: v, dealt: 0)
        XCTAssertEqual(f.s.units[v].hp, hp, accuracy: 1e-9)
        // スキル後の次の通常攻撃で、攻撃力の 60% の確定ダメージ + 回復
        ItemEffects.onSkillCast(&f.s, f.ctx, caster: a)
        let own = f.s.units[a].hp
        ItemEffects.onBasicAttackLanded(&f.s, f.ctx, attacker: a, target: v, dealt: 0)
        XCTAssertEqual(hp - f.s.units[v].hp, attack * 0.6, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[a].hp - own, 80 + attack * 0.4, accuracy: 1e-6)
        // 1 回で使い切る
        let after = f.s.units[v].hp
        ItemEffects.onBasicAttackLanded(&f.s, f.ctx, attacker: a, target: v, dealt: 0)
        XCTAssertEqual(f.s.units[v].hp, after, accuracy: 1e-9)
    }

    func testBreakoutDealsTrueDamageThenWaitsForCooldown() {
        var (f, a, v) = duel(["EQ054"])
        let level = Double(f.s.units[a].hero!.level)
        let hp = f.s.units[v].hp
        ItemEffects.onBasicAttackLanded(&f.s, f.ctx, attacker: a, target: v, dealt: 0)
        XCTAssertEqual(hp - f.s.units[v].hp, 50 + 1.5 * (level - 1), accuracy: 1e-6)
        XCTAssertNotNil(f.s.units[v].statuses.first { $0.kind == .slow && $0.tag == "item.breakout" })
        let after = f.s.units[v].hp
        ItemEffects.onBasicAttackLanded(&f.s, f.ctx, attacker: a, target: v, dealt: 0)
        XCTAssertEqual(f.s.units[v].hp, after, accuracy: 1e-9, "クールダウン中は働かない")
        f.s.time += 10
        ItemEffects.onBasicAttackLanded(&f.s, f.ctx, attacker: a, target: v, dealt: 0)
        XCTAssertLessThan(f.s.units[v].hp, after)
    }

    func testDespairBoostsDamageAgainstLowHealthTargets() {
        var (f, a, v) = duel(["EQ049"])
        let mit = CombatSystem.mitigationMultiplier(.physical, armor: 100, magicResist: 100)
        f.s.units[v].hp = f.s.units[v].stats.maxHP * 0.8
        XCTAssertEqual(hit(&f, a, v, 1000, .physical), 1000 * mit, accuracy: 1e-6)
        f.s.units[v].hp = f.s.units[v].stats.maxHP * 0.4
        XCTAssertEqual(hit(&f, a, v, 1000, .physical), 1000 * 1.25 * mit, accuracy: 1e-6)
    }

    func testImmortalSavesFromLethalDamageOnce() {
        var (f, a, v) = duel([], victimItems: ["EQ053"])
        f.s.units[v].hp = 10
        hit(&f, a, v, 100_000, .trueDamage)
        XCTAssertTrue(f.s.units[v].isAlive)
        XCTAssertGreaterThan(f.s.units[v].hp, 0)
        XCTAssertFalse(f.s.units[v].shields.isEmpty)
        // クールダウン中の 2 度目は倒れる
        f.s.units[v].shields.removeAll()
        f.s.units[v].hp = 10
        hit(&f, a, v, 100_000, .trueDamage)
        XCTAssertFalse(f.s.units[v].isAlive)
    }

    func testSameEffectFromTwoCopiesWorksOnce() {
        let (f, a, _) = duel(["EQ043", "EQ043"])
        let effects = ItemEffects.active(f.s.units[a], f.master)
        XCTAssertEqual(effects.filter { $0.kind == .divineJustice }.count, 1)
    }

    func testEveryEffectIdInTheMasterIsImplemented() {
        for it in MasterData.shared.items where !it.effectID.isEmpty {
            XCTAssertNotNil(ItemEffectKind(rawValue: it.effectID), "\(it.itemID): \(it.effectID)")
            XCTAssertFalse(it.effectValues.isEmpty, it.itemID)
        }
    }
}
