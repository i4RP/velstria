import XCTest
@testable import VelstriaCore

/// タワー / ベース（MLBB 2.2.16。DESIGN §3・§4、docs/TOWER_BASE_MLBB.md）: 狙う順・連続命中・確定ダメージ・対ミニオン割合ダメージ・
/// 保護（エネルギーシールド・バックドア・インナーの保護・聖なる防御）・無敵の順序・ベースの回復。
final class WorldTowerTests: XCTestCase {
    typealias Kit = WorldTestKit
    typealias T = Balance.Tower

    /// Blue mid 外塔 (4656,4991) の前に敵を置いた状態（5:00。シールドは外す）。射程 530 + 塔の半径 110。
    func makeLaneFight() -> (SimState, SimContext, tower: Int) {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.setTime(&s, 300)
        Kit.suppressWaves(&s)
        let outer = Kit.structureIndex(s, team: .blue, lane: .mid, tier: .outer)
        // 外塔のエネルギーシールド（開始〜5:00）は専用のテストで確かめる。ここでは外した状態から始める
        s.units[outer].shields.removeAll()
        return (s, ctx, outer)
    }

    /// 外塔から敵側（右上）へ d だけ離れた点。
    func ahead(_ s: SimState, _ tower: Int, _ d: Double) -> Vec2 {
        s.units[tower].pos + Vec2(1, 1).normalized * d
    }

    func testPrefersNearestMinionOverCloserHero() {
        var (s, ctx, tower) = makeLaneFight()
        let hero = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, tower, 250))
        let far = Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, tower, 600))
        let near = Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, tower, 450))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[near].id)
        _ = (hero, far)
    }

    func testTargetsHeroWhenNoMinionAndDummyCountsAsHero() {
        var (s, ctx, tower) = makeLaneFight()
        let hero = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, tower, 500))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[hero].id)

        var (s2, ctx2, tower2) = makeLaneFight()
        let dummy = s2.addUnit(UnitFactory.makeDummy(team: .red, pos: ahead(s2, tower2, 450)))
        VisionSystem.update(&s2, ctx2)
        TowerSystem.update(&s2, ctx2)
        XCTAssertEqual(s2.units[tower2].attackTargetID, dummy)
    }

    func testOutOfRangeIsIgnoredAndTargetDropsWhenLeaving() {
        var (s, ctx, tower) = makeLaneFight()
        let m = Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, tower, 600))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[m].id)
        s.units[m].pos = ahead(s, tower, 700) // 700 > 530 + 110 + 36
        TowerSystem.update(&s, ctx)
        XCTAssertNil(s.units[tower].attackTargetID)
    }

    func testKeepsCurrentTargetUntilItLeaves() {
        var (s, ctx, tower) = makeLaneFight()
        let hero = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, tower, 500))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[hero].id)
        // ミニオンが入ってきてもヒーローを撃ち続ける
        Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, tower, 400))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[hero].id)
    }

    func testHeroAttackingAlliedHeroTakesPriority() {
        var (s, ctx, tower) = makeLaneFight()
        let minion = Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, tower, 400))
        let enemy = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, tower, 600))
        let ally = Kit.addHero(&s, ctx, team: .blue, pos: ahead(s, tower, 200))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[minion].id)

        // 敵ヒーローが味方ヒーローを攻撃 → 即座に切り替え
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[enemy].id, targetIndex: ally, amount: 50,
                                 type: .physical, source: .basicAttack)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[enemy].id)

        // 2 秒経過後も射程内に居る限り維持
        Kit.setTime(&s, s.time + 2.5)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[enemy].id)

        // 味方がタワーの射程より十分外で攻撃された場合は対象外（射程の少し外 = 150 までは数える）
        var (s2, ctx2, tower2) = makeLaneFight()
        let m2 = Kit.addMinion(&s2, ctx2, team: .red, pos: ahead(s2, tower2, 400))
        let e2 = Kit.addHero(&s2, ctx2, team: .red, pos: ahead(s2, tower2, 600))
        let far = Kit.addHero(&s2, ctx2, team: .blue, pos: ahead(s2, tower2, 1300))
        VisionSystem.update(&s2, ctx2)
        CombatSystem.applyDamage(&s2, ctx2, sourceID: s2.units[e2].id, targetIndex: far, amount: 50,
                                 type: .physical, source: .basicAttack)
        TowerSystem.update(&s2, ctx2)
        XCTAssertEqual(s2.units[tower2].attackTargetID, s2.units[m2].id)
        s2.units[far].pos = ahead(s2, tower2, -780) // 射程 + 半径 + 150 の内側（塔の後ろ）
        CombatSystem.applyDamage(&s2, ctx2, sourceID: s2.units[e2].id, targetIndex: far, amount: 50,
                                 type: .physical, source: .basicAttack)
        TowerSystem.update(&s2, ctx2)
        XCTAssertEqual(s2.units[tower2].attackTargetID, s2.units[e2].id)
    }

    /// MLBB: ヒーローを撃っている間は、ほかの敵ヒーローが味方を攻撃しても対象を替えない。
    func testKeepsShootingAHeroEvenWhenAnotherHeroAttacksAnAlly() {
        var (s, ctx, tower) = makeLaneFight()
        let first = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, tower, 450))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[first].id)
        let other = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, tower, 550))
        let ally = Kit.addHero(&s, ctx, team: .blue, pos: ahead(s, tower, 100))
        VisionSystem.update(&s, ctx)
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[other].id, targetIndex: ally, amount: 50,
                                 type: .physical, source: .basicAttack)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[first].id)
    }

    /// 召喚されたロード（チームに付いた古環の巨像）は、ミニオンより先に狙われる。ミニオンも敵のロードをヒーローと同じ順で狙う。
    func testSummonedLordIsTargetedBeforeMinions() {
        var (s, ctx, tower) = makeLaneFight()
        let minion = Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, tower, 400))
        var lord = UnitFactory.makeMonster(kind: .ancientColossus, campID: -1, pos: ahead(s, tower, 600))
        lord.team = .red
        lord.minion = MinionData(type: .siege, lane: .mid, spawnTime: s.time)
        let lordID = s.addUnit(lord)
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, lordID)
        _ = minion
        // 青のミニオンは、近くの赤のミニオンより赤のロードを先に狙う（ヒーローと同じ扱い）
        let blueMinion = Kit.addMinion(&s, ctx, team: .blue, pos: ahead(s, tower, 300))
        VisionSystem.update(&s, ctx)
        MinionSystem.update(&s, ctx)
        XCTAssertEqual(s.units[blueMinion].attackTargetID, lordID)
        // 中立のモンスターは狙わない
        XCTAssertFalse(MinionSystem.isAttackableKind(.monster, team: .neutral))
        XCTAssertTrue(TowerSystem.isSummonedLord(s.units[s.index(of: lordID)!]))
    }

    /// MLBB: 同じヒーローに続けて当てると 1 発ごとに攻撃の +75%（20 発目で 4880 になり止まる）。最初の 1 発は −10%。
    /// 2 秒当てなければ戻る。ミニオンを撃っても、2 秒以内に同じヒーローへ戻れば続く。
    func testRampOnConsecutiveHeroHits() {
        var (s, ctx, tower) = makeLaneFight()
        let a = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, tower, 450))
        let b = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, tower, 550))
        let base = s.units[tower].stats.attack
        XCTAssertEqual(base, 320)
        var expected = [288.0]
        for n in 1..<22 { expected.append(320 + 240 * Double(min(n, 19))) }
        XCTAssertEqual(expected[19], 4880)
        for e in expected {
            XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: a), e, accuracy: 1e-9)
            Kit.setTime(&s, s.time + 1)
        }
        // 2 秒以上当てなければ戻る
        Kit.setTime(&s, s.time + 2.5)
        XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: a), 288, accuracy: 1e-9)
        Kit.setTime(&s, s.time + 1)
        // ミニオンを挟んでも 2 秒以内なら続く
        let m = Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, tower, 400))
        _ = TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: m)
        Kit.setTime(&s, s.time + 1)
        XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: a), 560, accuracy: 1e-9)
        // 別のヒーローは 1 発目から
        Kit.setTime(&s, s.time + 1)
        XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: b), 288, accuracy: 1e-9)
    }

    /// 塔の弾は確定ダメージ（防御・被ダメ軽減を無視）。
    func testTowerShotsAreTrueDamage() {
        var (s, ctx, tower) = makeLaneFight()
        let hero = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, tower, 450))
        s.units[hero].statuses.append(StatusEffect(kind: .damageReduction, duration: 10, magnitude: 0.3))
        s.units[hero].statuses.append(StatusEffect(kind: .flatArmorMod, duration: 10, magnitude: 200))
        StatCalculator.recompute(&s, hero, ctx)
        s.units[hero].hp = s.units[hero].stats.maxHP
        let before = s.units[hero].hp
        CombatSystem.releaseAttack(&s, ctx, attacker: tower, target: hero)
        guard let shot = s.projectiles.last else { return XCTFail("tower must fire a projectile") }
        XCTAssertEqual(shot.payload.damageType, .trueDamage)
        XCTAssertEqual(shot.payload.damage, 288, accuracy: 1e-9)
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[tower].id, team: .blue, targetIndex: hero, payload: shot.payload,
                              from: s.units[tower].pos)
        XCTAssertEqual(before - s.units[hero].hp, 288, accuracy: 1e-6)
    }

    /// タワー → ミニオンの 1 発は確定ダメージとして適用される（CombatSystem の契約）。
    func shootMinion(_ s: inout SimState, _ ctx: SimContext, tower: Int, minion m: Int) {
        let dmg = TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: m)
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[tower].id, targetIndex: m, amount: dmg,
                                 type: .trueDamage, source: .tower)
    }

    func testMinionDamageIsPercentOfMaxHP() {
        var (s, ctx, tower) = makeLaneFight()
        for (type, pct) in [(MinionType.melee, 0.45), (.ranged, 0.70), (.siege, 0.14)] {
            let m = Kit.addMinion(&s, ctx, type: type, team: .red, pos: ahead(s, tower, 400))
            let maxHP = s.units[m].stats.maxHP
            shootMinion(&s, ctx, tower: tower, minion: m)
            XCTAssertEqual(maxHP - s.units[m].hp, pct * maxHP, accuracy: 1e-6, "\(type)")
        }
        // 攻城ミニオンは防御 40 だが、割合ダメージは防御の影響を受けない
        let siege = Kit.addMinion(&s, ctx, type: .siege, team: .red, pos: ahead(s, tower, 400))
        XCTAssertEqual(s.units[siege].stats.armor, 40)
        XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: tower, targetIndex: siege),
                       0.14 * s.units[siege].stats.maxHP, accuracy: 1e-9)
        // 近接 3 発・遠隔 2 発・攻城 8 発で倒れる
        for (type, shots) in [(MinionType.melee, 3), (.ranged, 2), (.siege, 8)] {
            let m = Kit.addMinion(&s, ctx, type: type, team: .red, pos: ahead(s, tower, 400))
            var n = 0
            while s.units[m].isAlive {
                shootMinion(&s, ctx, tower: tower, minion: m)
                n += 1
            }
            XCTAssertEqual(n, shots, "\(type)")
        }
    }

    func testMinionPercentDamageCancelsBonusesAndReductions() {
        var (s, ctx, tower) = makeLaneFight()
        // 強化ミニオン（HP ×1.5）+ 被ダメ軽減 20%、タワーに与ダメ +10% が付いていても 1 発 45%
        let m = Kit.addMinion(&s, ctx, type: .melee, team: .red, pos: ahead(s, tower, 400))
        s.units[m].baseStats.maxHP *= 1.5
        s.units[m].statuses.append(StatusEffect(kind: .damageReduction, duration: 5, magnitude: 0.2))
        s.units[tower].statuses.append(StatusEffect(kind: .damageBoost, duration: 5, magnitude: 0.1))
        StatCalculator.recompute(&s, m, ctx)
        StatCalculator.recompute(&s, tower, ctx)
        s.units[m].hp = s.units[m].stats.maxHP
        let maxHP = s.units[m].stats.maxHP
        shootMinion(&s, ctx, tower: tower, minion: m)
        XCTAssertEqual(maxHP - s.units[m].hp, 0.45 * maxHP, accuracy: 1e-6)
    }

    func testRetargetCancelsWindup() {
        var (s, ctx, tower) = makeLaneFight()
        let minion = Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, tower, 400))
        let enemy = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, tower, 600))
        let ally = Kit.addHero(&s, ctx, team: .blue, pos: ahead(s, tower, 200))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[minion].id)
        s.units[tower].windupRemaining = 0.1
        // 同じ対象のままなら前隙は続く
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].windupRemaining, 0.1)
        // 救援で対象が変わると前隙は取り消され、新しい対象へ撃ち直す
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[enemy].id, targetIndex: ally, amount: 50,
                                 type: .physical, source: .basicAttack)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].attackTargetID, s.units[enemy].id)
        XCTAssertNil(s.units[tower].windupRemaining)
    }

    /// アウタータワーは最初のミニオンが出てから 15 秒間（0:26 まで）攻撃せず、無敵。
    func testOuterTowersSleepForFifteenSecondsAfterTheFirstWave() {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.suppressWaves(&s)
        let outer = Kit.structureIndex(s, team: .blue, lane: .mid, tier: .outer)
        Kit.setTime(&s, T.outerWakeTime - 1)
        let hero = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, outer, 450))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertNil(s.units[outer].attackTargetID)
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: outer))
        XCTAssertTrue(WorldTargeting.structureInvulnerability(s)[outer])
        Kit.setTime(&s, T.outerWakeTime + 0.1)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[outer].attackTargetID, s.units[hero].id)
        XCTAssertFalse(TowerSystem.isInvulnerable(s, ctx, index: outer))
        XCTAssertEqual(T.outerWakeTime, 26, accuracy: 1e-9)
    }

    /// 外塔のエネルギーシールドがある間は被ダメ −30%。シールドが無い（期限切れ・削り切り）と通常に戻る。
    func testOuterTowerShieldReducesDamageWhileItLasts() {
        var (s, ctx, outer) = makeLaneFight()
        let inner = Kit.structureIndex(s, team: .blue, lane: .mid, tier: .inner)
        let siege = Kit.addMinion(&s, ctx, type: .siege, team: .red, pos: ahead(s, outer, 400))
        XCTAssertFalse(TowerSystem.hasTurretShield(s.units[outer]))
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: nil), 1.0, accuracy: 1e-9)
        s.units[outer].shields.append(Shield(amount: T.shieldAmount, duration: T.shieldDuration, tag: TowerSystem.shieldTag))
        XCTAssertTrue(TowerSystem.hasTurretShield(s.units[outer]))
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: nil), 0.7, accuracy: 1e-9)
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: siege), 0.7 * 1.5, accuracy: 1e-9)
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: inner, sourceIndex: siege), 1.5, accuracy: 1e-9)
        // 期限切れ（5:00）
        s.units[outer].shields[0].remaining = 0
        XCTAssertFalse(TowerSystem.hasTurretShield(s.units[outer]))
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: siege), 1.5, accuracy: 1e-9)
    }

    /// シールドを削ったヒーローは、削ったダメージ 10 につき 1 Gold（1 本 360 Gold まで）。HP は減らない。
    func testHeroDamagingTheOuterShieldEarnsGold() {
        var (s, ctx, outer) = makeLaneFight()
        let hero = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, outer, 450))
        Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, outer, 400))   // 護衛ミニオン（バックドアの保護を外す）
        s.units[outer].shields.append(Shield(amount: T.shieldAmount, duration: T.shieldDuration, tag: TowerSystem.shieldTag))
        let hpBefore = s.units[outer].hp
        let shieldBefore = s.units[outer].totalShield
        let goldBefore = s.units[hero].hero!.gold
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: outer, amount: 1000,
                                 type: .trueDamage, source: .basicAttack)
        // 確定ダメージ 1000 × シールドの軽減 0.7 = 700 がシールドに吸われ、HP は減らない
        XCTAssertEqual(s.units[outer].hp, hpBefore, accuracy: 1e-9)
        XCTAssertEqual(shieldBefore - s.units[outer].totalShield, 700, accuracy: 1e-6)
        XCTAssertEqual(s.units[hero].hero!.gold - goldBefore, 70, accuracy: 1e-6)
        // 残り 4300 を削り切っても、1 本の合計は 360 Gold まで
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: outer, amount: 10_000,
                                 type: .trueDamage, source: .basicAttack)
        XCTAssertFalse(TowerSystem.hasTurretShield(s.units[outer]))
        XCTAssertEqual(s.units[hero].hero!.gold - goldBefore, 360, accuracy: 1e-6)
    }

    /// ミニオンがシールドに与えるダメージは 1 発 75 で固定。
    func testMinionsDealAFixedSeventyFiveToTheShield() {
        var (s, ctx, outer) = makeLaneFight()
        let siege = Kit.addMinion(&s, ctx, type: .siege, team: .red, pos: ahead(s, outer, 400))
        s.units[outer].shields.append(Shield(amount: T.shieldAmount, duration: T.shieldDuration, tag: TowerSystem.shieldTag))
        let hpBefore = s.units[outer].hp
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[siege].id, targetIndex: outer, amount: 400,
                                 type: .physical, source: .minion)
        XCTAssertEqual(T.shieldAmount - s.units[outer].totalShield, 75, accuracy: 1e-6)
        XCTAssertEqual(s.units[outer].hp, hpBefore, accuracy: 1e-9)
    }

    /// シールドがある間、近くの味方ヒーローの被ダメ −15%（確定ダメージには効かない）。
    func testShieldProtectsNearbyAlliedHeroes() {
        var (s, ctx, outer) = makeLaneFight()
        Kit.setTime(&s, 200)
        let ally = Kit.addHero(&s, ctx, team: .blue, pos: ahead(s, outer, 300))
        let enemy = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, outer, 900))
        s.units[ally].statuses.removeAll()
        StatCalculator.recompute(&s, ally, ctx)
        func hit() -> Double {
            s.units[ally].hp = s.units[ally].stats.maxHP
            let before = s.units[ally].hp
            CombatSystem.applyDamage(&s, ctx, sourceID: s.units[enemy].id, targetIndex: ally, amount: 300,
                                     type: .trueDamage, source: .skill(.skill1))
            let trueHit = before - s.units[ally].hp
            s.units[ally].hp = s.units[ally].stats.maxHP
            CombatSystem.applyDamage(&s, ctx, sourceID: s.units[enemy].id, targetIndex: ally, amount: 300,
                                     type: .magic, source: .skill(.skill1))
            return (before - s.units[ally].hp) / max(1e-9, trueHit)
        }
        let unshielded = hit()
        s.units[outer].shields.append(Shield(amount: T.shieldAmount, duration: T.shieldDuration, tag: TowerSystem.shieldTag))
        XCTAssertTrue(TowerSystem.shieldGuardsHero(s, heroIndex: ally))
        XCTAssertEqual(hit() / unshielded, 0.85, accuracy: 1e-6)
        // 射程の外では守られない
        s.units[ally].pos = ahead(s, outer, 1200)
        XCTAssertFalse(TowerSystem.shieldGuardsHero(s, heroIndex: ally))
    }

    func testOnlyOuterTowersStartWithTheEnergyShield() {
        let (s, _) = Kit.makeState(Kit.emptyConfig())
        for u in s.units where u.isStructure {
            XCTAssertEqual(TowerSystem.hasTurretShield(u), u.kind == .tower && u.tower?.tier == .outer, "only outer towers carry the energy shield")
        }
    }

    /// バックドアの保護: 射程内に攻める側のミニオンがいなければ、ミニオン以外からの被ダメ −50%。ミニオンからベースへは −50%。
    func testBackdoorProtection() {
        var (s, ctx, outer) = makeLaneFight()
        let hero = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, outer, 500))
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: hero), 0.5, accuracy: 1e-9)
        // 塔の射程内に攻撃側のミニオンが居れば解除
        let m = Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, outer, 400))
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: hero), 1.0, accuracy: 1e-9)
        // 射程外のミニオンや防衛側のミニオンでは解除されない
        s.units[m].pos = ahead(s, outer, 800)
        Kit.addMinion(&s, ctx, team: .blue, pos: ahead(s, outer, 200))
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: hero), 0.5, accuracy: 1e-9)
        // 外塔のシールドと重なる
        s.units[outer].shields.append(Shield(amount: 100, duration: 100, tag: TowerSystem.shieldTag))
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: outer, sourceIndex: hero), 0.5 * 0.7, accuracy: 1e-9)
        s.units[outer].shields.removeAll()
        // 実ダメージにも反映される（防御 20: MLBB の式 120 / 140）
        let before = s.units[outer].hp
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: outer, amount: 180,
                                 type: .physical, source: .basicAttack)
        XCTAssertEqual(before - s.units[outer].hp, 180 * 0.5 * 120 / 140, accuracy: 1e-6)
        // ミニオンからベースへのダメージは −50%（ミニオンはベースの射程内に居るのでバックドアの保護は無い）
        let core = Kit.structureIndex(s, team: .red, lane: nil, tier: .base, core: true)
        let blueMinion = Kit.addMinion(&s, ctx, team: .blue, pos: s.units[core].pos + Vec2(-400, -400))
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: core, sourceIndex: blueMinion), 0.5, accuracy: 1e-9)
    }

    /// ヒーローの通常攻撃は塔に 物攻 100% + 魔攻 100%（MLBB 1.8.08）。
    func testHeroBasicAttackOnTowersAddsMagicPower() {
        var (s, ctx, outer) = makeLaneFight()
        let hero = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, outer, 300))
        Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, outer, 400))   // 護衛ミニオン
        s.units[hero].statuses.append(StatusEffect(kind: .flatPowerMod, duration: 10, magnitude: 100))
        StatCalculator.recompute(&s, hero, ctx)
        let st = s.units[hero].stats
        XCTAssertGreaterThan(st.abilityPower, 0)
        let expected = (st.attack + st.abilityPower) * max(0, 1 + st.damageBonus + st.basicAttackDamageBonus) * 120 / 140
        XCTAssertEqual(CombatSystem.estimateBasicAttackDamage(s, ctx, attacker: hero, target: outer),
                       (st.attack + st.abilityPower) * max(0, 1 + st.damageBonus + st.basicAttackDamageBonus) * 120 / 140,
                       accuracy: 1e-6)
        _ = expected
    }

    /// インナーの保護: 同じレーンのアウターが 8:00 までに壊れたら、1 分間 被ダメ −50%。8:00 を過ぎてからは付かない。
    func testInnerTurretIsGuardedAfterAnEarlyOuterLoss() {
        var (s, ctx, outer) = makeLaneFight()
        let inner = Kit.structureIndex(s, team: .blue, lane: .mid, tier: .inner)
        let topOuter = Kit.structureIndex(s, team: .blue, lane: .top, tier: .outer)
        let topInner = Kit.structureIndex(s, team: .blue, lane: .top, tier: .inner)
        Kit.kill(&s, outer)
        TowerSystem.onTowerDestroyed(&s, victimIndex: outer)
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: inner, sourceIndex: nil), 0.5, accuracy: 1e-9)
        Kit.setTime(&s, 300 + 59)
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: inner, sourceIndex: nil), 0.5, accuracy: 1e-9)
        Kit.setTime(&s, 300 + 61)
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: inner, sourceIndex: nil), 1.0, accuracy: 1e-9)
        // 8:00 より後に落ちたアウターでは付かない
        Kit.setTime(&s, 8 * 60 + 1)
        Kit.kill(&s, topOuter)
        TowerSystem.onTowerDestroyed(&s, victimIndex: topOuter)
        XCTAssertEqual(TowerSystem.damageTakenMultiplier(s, ctx, structureIndex: topInner, sourceIndex: nil), 1.0, accuracy: 1e-9)
    }

    /// ベースタワーの聖なる防御: 同じレーンのインナーが 12:00 までに壊れたら、次に射程に入る敵ミニオンの波に最大 HP の 80%。
    /// 射程内の敵ミニオン・敵ヒーローを押し返す。1 度きりで、12:00 を過ぎたら発動しない。
    func testHolyDefenseHitsTheNextWaveBeforeTwelveMinutes() {
        var (s, ctx, outer) = makeLaneFight()
        let inner = Kit.structureIndex(s, team: .blue, lane: .mid, tier: .inner)
        let base = Kit.structureIndex(s, team: .blue, lane: .mid, tier: .base)
        Kit.kill(&s, outer)
        Kit.setTime(&s, 600)
        Kit.kill(&s, inner)
        TowerSystem.onTowerDestroyed(&s, victimIndex: inner)
        XCTAssertEqual(s.units[base].tower?.holyDefenseArmed, true)
        // 射程の外の波は発動させない
        let far = Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, base, 800))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[base].tower?.holyDefenseArmed, true)
        // 射程に入ると発動: 波（射程の少し外まで）の敵ミニオンに最大 HP の 80%、射程内の敵は押し返される
        let near = Kit.addMinion(&s, ctx, team: .red, pos: ahead(s, base, 500))
        let hero = Kit.addHero(&s, ctx, team: .red, pos: ahead(s, base, 450))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertNil(s.units[base].tower?.holyDefenseArmed)
        for m in [near, far] {
            XCTAssertEqual(s.units[m].stats.maxHP - s.units[m].hp, 0.8 * s.units[m].stats.maxHP, accuracy: 1e-6)
        }
        XCTAssertNotNil(s.units[near].displacement)
        XCTAssertNotNil(s.units[hero].displacement)
        XCTAssertNil(s.units[far].displacement)

        // 12:00 を過ぎると待機していても発動しない
        var (s2, ctx2, outer2) = makeLaneFight()
        let inner2 = Kit.structureIndex(s2, team: .blue, lane: .mid, tier: .inner)
        let base2 = Kit.structureIndex(s2, team: .blue, lane: .mid, tier: .base)
        Kit.kill(&s2, outer2)
        Kit.setTime(&s2, 700)
        Kit.kill(&s2, inner2)
        TowerSystem.onTowerDestroyed(&s2, victimIndex: inner2)
        Kit.setTime(&s2, 12 * 60 + 1)
        let late = Kit.addMinion(&s2, ctx2, team: .red, pos: ahead(s2, base2, 500))
        VisionSystem.update(&s2, ctx2)
        TowerSystem.update(&s2, ctx2)
        XCTAssertEqual(s2.units[late].hp, s2.units[late].stats.maxHP, accuracy: 1e-9)
        XCTAssertNil(s2.units[base2].tower?.holyDefenseArmed)
        // 12:00 より後に落ちたインナーでは待機しない
        var (s3, _, outer3) = makeLaneFight()
        let inner3 = Kit.structureIndex(s3, team: .blue, lane: .mid, tier: .inner)
        let base3 = Kit.structureIndex(s3, team: .blue, lane: .mid, tier: .base)
        Kit.kill(&s3, outer3)
        Kit.setTime(&s3, 12 * 60 + 5)
        Kit.kill(&s3, inner3)
        TowerSystem.onTowerDestroyed(&s3, victimIndex: inner3)
        XCTAssertNil(s3.units[base3].tower?.holyDefenseArmed)
    }

    /// ベースは 5 秒ごとに 165 回復する。
    func testCoreRegeneratesEveryFiveSeconds() {
        var (s, ctx, _) = makeLaneFight()
        let core = Kit.structureIndex(s, team: .red, lane: nil, tier: .base, core: true)
        s.units[core].hp = 5000
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[core].hp, 5000, accuracy: 1e-9)
        Kit.setTime(&s, s.time + 4.9)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[core].hp, 5000, accuracy: 1e-9)
        Kit.setTime(&s, s.time + 0.2)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[core].hp, 5165, accuracy: 1e-9)
        Kit.setTime(&s, s.time + 5)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[core].hp, 5330, accuracy: 1e-9)
    }

    func testInvulnerabilityOrder() {
        var (s, ctx, _) = makeLaneFight()
        func idx(_ lane: Lane, _ tier: TowerTier) -> Int { Kit.structureIndex(s, team: .blue, lane: lane, tier: tier) }
        let core = Kit.structureIndex(s, team: .blue, lane: nil, tier: .base, core: true)
        XCTAssertFalse(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .outer)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .inner)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .base)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: core))
        XCTAssertEqual(CombatSystem.applyDamage(&s, ctx, sourceID: nil, targetIndex: idx(.top, .inner), amount: 500,
                                                type: .trueDamage, source: .spell), 0)

        Kit.kill(&s, idx(.top, .outer))
        XCTAssertFalse(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .inner)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .base)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: idx(.mid, .inner)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: core))

        Kit.kill(&s, idx(.top, .inner))
        XCTAssertFalse(TowerSystem.isInvulnerable(s, ctx, index: idx(.top, .base)))
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: core))

        Kit.kill(&s, idx(.top, .base))
        XCTAssertFalse(TowerSystem.isInvulnerable(s, ctx, index: core))
        XCTAssertGreaterThan(CombatSystem.applyDamage(&s, ctx, sourceID: nil, targetIndex: core, amount: 500,
                                                      type: .trueDamage, source: .spell), 0)
        // 他レーンの内塔・基部塔は引き続き前段の外塔が守る
        XCTAssertTrue(TowerSystem.isInvulnerable(s, ctx, index: idx(.bot, .base)))
        // 前計算版（ミニオンの索敵用）と一致
        let table = WorldTargeting.structureInvulnerability(s)
        for i in s.units.indices where s.units[i].isStructure {
            XCTAssertEqual(table[i], TowerSystem.isInvulnerable(s, ctx, index: i))
        }
    }

    func testCoreAttacksLikeTower() {
        var (s, ctx, _) = makeLaneFight()
        let core = Kit.structureIndex(s, team: .red, lane: nil, tier: .base, core: true)
        // ベースの射程 530 + 半径 250
        let m = Kit.addMinion(&s, ctx, team: .blue, pos: s.units[core].pos + Vec2(-500, -500))
        VisionSystem.update(&s, ctx)
        TowerSystem.update(&s, ctx)
        XCTAssertEqual(s.units[core].attackTargetID, s.units[m].id)
        XCTAssertEqual(TowerSystem.attackDamage(&s, ctx, towerIndex: core, targetIndex: m),
                       0.45 * s.units[m].stats.maxHP, accuracy: 1e-6)
    }

    func testTowerKillsMinionsInSimulation() {
        var (s, ctx, tower) = makeLaneFight()
        let m = Kit.addMinion(&s, ctx, type: .ranged, team: .red, pos: ahead(s, tower, 500))
        s.units[m].minion?.waypointIndex = 2
        VisionSystem.update(&s, ctx)
        let sim = Simulation(snapshot: s)
        var hits = 0
        for _ in 0..<90 {
            for e in sim.step() {
                if case .damage(let d) = e, d.sourceID == s.units[tower].id { hits += 1 }
            }
        }
        XCTAssertNil(sim.state.unit(s.units[m].id), "ranged minion should die in 2 tower shots")
        XCTAssertEqual(hits, 2)
    }
}
