import XCTest
@testable import VelstriaCore

/// バトルスペル BS01–BS15（DESIGN §7）。
final class SpellSystemTests: XCTestCase {

    private func spellEvents(_ w: SkillWorld) -> [(EntityID, String, Vec2, Vec2)] {
        w.log.compactMap {
            if case .spellCast(let c, let id, let o, let t) = $0 { return (c, id, o, t) } else { return nil }
        }
    }

    func testMasterSpellsAllMapToKinds() {
        XCTAssertEqual(MasterData.shared.spells.map(\.spellID), BattleSpell.allCases.map(\.rawValue))
        for spell in BattleSpell.allCases {
            let t = SpellSystem.targeting(for: spell.rawValue)
            XCTAssertNotNil(t)
            XCTAssertEqual(t?.aim, spell.aim)
        }
        XCTAssertNil(SpellSystem.targeting(for: "BS99"))
    }

    // MARK: - BS01 瞬歩

    func testBlinkMovesFourHundredAndStopsBeforeObstacles() {
        var w = SkillWorld()
        let h = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS01", "BS03"])
        XCTAssertTrue(w.castSpell(h, 0, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.s.units[h].pos.x, skillArena.x + 400, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 90)
        let e = spellEvents(w).last!
        XCTAssertEqual(e.1, "BS01")
        XCTAssertEqual(e.2, skillArena)
        XCTAssertEqual(e.3.x, skillArena.x + 400, accuracy: 1e-6)
        XCTAssertFalse(w.castSpell(h, 0, .direction(Vec2(1, 0))), "CD 中")
        XCTAssertFalse(SpellSystem.canCast(w.s, w.ctx, heroIndex: h, spellIndex: 0))

        // 壁（x 4750..6000, y 1300..1700）の手前で止まる
        var o = SkillWorld()
        let start = Vec2(4500, 1500)
        XCTAssertTrue(o.ctx.nav.isWalkable(start, radius: Balance.heroRadius))
        let b = o.addHero("H001", team: .blue, at: start, spells: ["BS01", "BS03"])
        XCTAssertTrue(o.castSpell(b, 0, .point(start + Vec2(1000, 0))))
        XCTAssertGreaterThan(o.s.units[b].pos.x, start.x + 50)
        XCTAssertLessThan(o.s.units[b].pos.x, 4750 - Balance.heroRadius + 1)
        XCTAssertTrue(o.ctx.nav.isWalkable(o.s.units[b].pos, radius: Balance.heroRadius))
        // .none は向いている方向
        var f = SkillWorld()
        let c = f.addHero("H001", team: .blue, at: skillArena, spells: ["BS01", "BS03"], facing: Double.pi / 2)
        XCTAssertTrue(f.castSpell(c, 0))
        XCTAssertEqual(f.s.units[c].pos.y, skillArena.y + 400, accuracy: 1e-6)
    }

    func testDisabledHeroesCanOnlyCleanse() {
        var w = SkillWorld()
        let h = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS01", "BS02"])
        let e = w.addHero("H003", team: .red, at: skillArena + Vec2(300, 0))
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: w.id(e), targetIndex: h, cc: .stun, isUltimate: true,
                             from: w.s.units[e].pos)
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: w.id(e), targetIndex: h, cc: .slow, isUltimate: false,
                             from: w.s.units[e].pos)
        XCTAssertFalse(SpellSystem.canCast(w.s, w.ctx, heroIndex: h, spellIndex: 0))
        XCTAssertFalse(w.castSpell(h, 0, .direction(Vec2(1, 0))))
        XCTAssertTrue(SpellSystem.canCast(w.s, w.ctx, heroIndex: h, spellIndex: 1))
        XCTAssertTrue(w.castSpell(h, 1))
        XCTAssertFalse(w.s.units[h].has(.stun))
        XCTAssertFalse(w.s.units[h].has(.slow))
        XCTAssertTrue(w.s.units[h].has(.ccImmune))
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[1], 100)
        // CC 無効中は CC を受けない
        CombatSystem.applyCC(&w.s, w.ctx, sourceID: w.id(e), targetIndex: h, cc: .root, isUltimate: false,
                             from: w.s.units[e].pos)
        XCTAssertFalse(w.s.units[h].has(.root))
        w.run(seconds: 1.6)
        XCTAssertFalse(w.s.units[h].has(.ccImmune))
        // 沈黙ではスペルは封じられない
        CombatSystem.addStatus(&w.s, targetIndex: h, StatusEffect(kind: .silence, duration: 1))
        XCTAssertTrue(w.castSpell(h, 0, .direction(Vec2(0, 1))))
    }

    // MARK: - BS03 治癒波 / BS04 鉄壁 / BS06 加速陣

    func testHealWavesHealsSelfAndLowestAlly() {
        var w = SkillWorld()
        let h = w.addHero("H005", team: .blue, at: skillArena, spells: ["BS03", "BS01"])
        let low = w.addHero("H001", team: .blue, at: skillArena + Vec2(500, 0))
        let lower = w.addHero("H002", team: .blue, at: skillArena + Vec2(1200, 0))   // 800 の外
        let mid = w.addHero("H004", team: .blue, at: skillArena + Vec2(0, 500))
        w.s.units[h].hp = 1000
        w.s.units[low].hp = w.s.units[low].stats.maxHP * 0.3
        w.s.units[mid].hp = w.s.units[mid].stats.maxHP * 0.6
        w.s.units[lower].hp = 100
        let lowBefore = w.s.units[low].hp
        XCTAssertTrue(w.castSpell(h, 0))
        XCTAssertEqual(w.s.units[h].hp, 1000 + w.s.units[h].stats.maxHP * 0.15, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[low].hp, lowBefore + w.s.units[low].stats.maxHP * 0.15, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[mid].hp, w.s.units[mid].stats.maxHP * 0.6, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[lower].hp, 100)
        XCTAssertEqual(w.s.units[h].status(.speedBoost)?.magnitude, 0.2)
        XCTAssertEqual(w.s.units[low].status(.speedBoost)?.remaining, 2)
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 80)
    }

    func testBarrierAndGhost() {
        var w = SkillWorld()
        let h = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS04", "BS06"])
        let speed = w.s.units[h].stats.moveSpeed
        XCTAssertTrue(w.castSpell(h, 0))
        XCTAssertEqual(w.s.units[h].totalShield, w.s.units[h].stats.maxHP * 0.2, accuracy: 1e-6)
        XCTAssertTrue(w.castSpell(h, 1))
        w.tick()
        XCTAssertEqual(w.s.units[h].stats.moveSpeed, speed * 1.4, accuracy: 1e-6)
        w.run(seconds: 3)
        XCTAssertEqual(w.s.units[h].totalShield, 0, "鉄壁は 3 秒")
        XCTAssertGreaterThan(w.s.units[h].stats.moveSpeed, speed)
        w.run(seconds: 2)
        XCTAssertEqual(w.s.units[h].stats.moveSpeed, speed, accuracy: 1e-6, "加速陣は 5 秒")
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 75 - 5 - Balance.dt, accuracy: 0.05)
    }

    // MARK: - BS05 狩猟印

    func testSmiteHitsOnlyMinionsAndMonstersInRange() {
        var w = SkillWorld()
        let h = w.addHero("H006", team: .blue, at: skillArena, level: 5, spells: ["BS05", "BS01"])
        w.addHero("H001", team: .red, at: skillArena + Vec2(200, 0))
        // 敵ヒーローしか居なければ失敗（CD を消費しない）
        XCTAssertFalse(w.castSpell(h, 0))
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 0)
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(0, 300))
        let monster = w.addMonster(.campLarge, at: skillArena + Vec2(-400, 0))
        let farMonster = w.addMonster(.blueSentinel, at: skillArena + Vec2(0, -900))
        let hpBefore = w.s.units[monster].hp
        XCTAssertTrue(w.castSpell(h, 0))
        XCTAssertEqual(hpBefore - w.s.units[monster].hp, 600 + 40 * 5, accuracy: 1e-6, "モンスター優先・確定ダメージ")
        XCTAssertEqual(w.s.units[minion].hp, w.s.units[minion].stats.maxHP)
        XCTAssertEqual(w.s.units[farMonster].hp, w.s.units[farMonster].stats.maxHP)
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 45)
        // ユニット指定
        var u = SkillWorld()
        let h2 = u.addHero("H006", team: .blue, at: skillArena, level: 1, spells: ["BS05", "BS01"])
        let m2 = u.addMinion(.siege, team: .red, at: skillArena + Vec2(0, 300))
        u.addMonster(.campLarge, at: skillArena + Vec2(-400, 0))
        XCTAssertTrue(u.castSpell(h2, 0, .unit(u.id(m2))))
        XCTAssertEqual(u.damage(to: m2), 640, accuracy: 1e-6)
    }

    // MARK: - BS07 点火

    func testIgniteBurnsEnemyHeroAndCutsHealing() {
        var w = SkillWorld()
        let h = w.addHero("H006", team: .blue, at: skillArena, level: 4, spells: ["BS07", "BS01"])
        let t = w.addHero("H013", team: .red, at: skillArena + Vec2(500, 0))
        w.addHero("H001", team: .red, at: skillArena + Vec2(900, 0))
        XCTAssertTrue(w.castSpell(h, 0))
        XCTAssertTrue(w.s.units[t].has(.burn))
        w.tick()
        XCTAssertEqual(w.s.units[t].stats.healingReceivedMultiplier, 0.5, accuracy: 1e-9)
        w.run(seconds: 5.1)
        XCTAssertEqual(w.damage(to: t, from: .dot), 70 + 20 * 4, accuracy: 1e-6)
        XCTAssertFalse(w.s.units[t].has(.burn))
        // 射程外なら失敗
        var o = SkillWorld()
        let h2 = o.addHero("H006", team: .blue, at: skillArena, spells: ["BS07", "BS01"])
        let far = o.addHero("H013", team: .red, at: skillArena + Vec2(800, 0))
        XCTAssertFalse(o.castSpell(h2, 0, .unit(o.id(far))))
    }

    // MARK: - BS08 虚像

    func testStealthHidesFromEnemiesAndBreaksOnAttack() {
        var w = SkillWorld()
        w.autoReveal = false
        let h = w.addHero("H002", team: .blue, at: skillArena, spells: ["BS08", "BS01"])
        let watcher = w.addHero("H003", team: .red, at: skillArena + Vec2(600, 0))
        VisionSystem.update(&w.s, w.ctx)
        XCTAssertTrue(w.s.isVisible(h, to: .red))
        let speed = w.s.units[h].stats.moveSpeed
        XCTAssertTrue(w.castSpell(h, 0))
        w.tick(3)
        XCTAssertFalse(w.s.isVisible(h, to: .red), "ステルス")
        XCTAssertEqual(w.s.units[h].stats.moveSpeed, speed * 1.25, accuracy: 1e-6)
        // 通常攻撃の発射でステルスが解除される
        w.s.units[h].pos = skillArena + Vec2(400, 0)
        w.s.units[h].attackTargetID = w.id(watcher)
        w.run(seconds: 0.5)
        XCTAssertFalse(w.s.units[h].has(.stealth))
        w.tick(3)
        XCTAssertTrue(w.s.isVisible(h, to: .red))
        // 自然に 1.5 秒で切れる
        var n = SkillWorld()
        let h2 = n.addHero("H002", team: .blue, at: skillArena, spells: ["BS08", "BS01"])
        XCTAssertTrue(n.castSpell(h2, 0))
        n.run(seconds: 1.4)
        XCTAssertTrue(n.s.units[h2].has(.stealth))
        n.run(seconds: 0.2)
        XCTAssertFalse(n.s.units[h2].has(.stealth))
    }

    func testStealthBreaksOnSkillAndOffensiveSpellButNotOnBlink() {
        var w = SkillWorld()
        let h = w.addHero("H002", team: .blue, at: skillArena, spells: ["BS08", "BS01"])
        XCTAssertTrue(w.castSpell(h, 0))
        XCTAssertTrue(w.castSpell(h, 1, .direction(Vec2(1, 0))))
        XCTAssertTrue(w.s.units[h].has(.stealth), "瞬歩では解除しない")
        XCTAssertTrue(w.cast(h, .skill1, .direction(Vec2(1, 0))))
        XCTAssertFalse(w.s.units[h].has(.stealth))

        var e = SkillWorld()
        let h2 = e.addHero("H002", team: .blue, at: skillArena, spells: ["BS08", "BS10"])
        let t = e.addHero("H003", team: .red, at: skillArena + Vec2(300, 0))
        XCTAssertTrue(e.castSpell(h2, 0))
        XCTAssertTrue(e.castSpell(h2, 1, .unit(e.id(t))))
        XCTAssertFalse(e.s.units[h2].has(.stealth))
    }

    // MARK: - BS09 帰還門

    func testTeleportChannelsThenMovesToAllyTower() {
        var w = SkillWorld()
        let h = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS09", "BS01"])
        // 味方タワーが無く、泉の外を指定 → 失敗
        XCTAssertFalse(w.castSpell(h, 0, .point(skillArena + Vec2(2000, 0))))
        let towerPos = Vec2(1400, 4800)
        w.addTower(team: .blue, at: towerPos)
        XCTAssertTrue(w.castSpell(h, 0, .point(towerPos + Vec2(0, 200))))
        XCTAssertEqual(w.s.units[h].hero!.channel?.kind, .teleport)
        XCTAssertEqual(w.s.units[h].hero!.channel?.total, 3)
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 120)
        w.run(seconds: 2.9)
        XCTAssertEqual(w.s.units[h].pos, skillArena)
        w.run(seconds: 0.2)
        XCTAssertNil(w.s.units[h].hero!.channel)
        XCTAssertLessThan(w.s.units[h].pos.distance(to: towerPos), 400)
        XCTAssertTrue(w.log.contains { if case .channelCompleted(_, .teleport, _) = $0 { return true } else { return false } })
    }

    func testTeleportAutoTargetsOwnLaneFrontTowerAndIsInterruptedByDamage() {
        var w = SkillWorld()
        let h = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS09", "BS01"])   // Vanguard → top ポジション（EXP レーン）
        let e = w.addHero("H003", team: .red, at: skillArena + Vec2(300, 0))
        let spots = w.ctx.map.towers.filter { $0.team == .blue && !$0.isCore }
        for spot in spots { w.s.addUnit(UnitFactory.makeStructure(spot)) }
        let ownLane = w.ctx.map.lane(for: .top)!
        let topOuter = spots.first { $0.lane == ownLane && $0.tier == .outer }!.pos
        XCTAssertTrue(w.castSpell(h, 0))
        XCTAssertEqual(spellEvents(w).last!.3, topOuter)
        w.run(seconds: 1)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: h, amount: 10, type: .physical,
                                 source: .basicAttack)
        w.tick()
        XCTAssertNil(w.s.units[h].hero!.channel, "被ダメで中断")
        XCTAssertGreaterThan(w.s.units[h].hero!.spellCooldowns[0], 100, "CD は消費済み")
    }

    // MARK: - BS10 星鎖

    func testExhaustSlowsAndWeakensEnemyHero() {
        var w = SkillWorld()
        let h = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS10", "BS01"])
        let t = w.addHero("H003", team: .red, at: skillArena + Vec2(600, 0))
        let speed = w.s.units[t].stats.moveSpeed
        XCTAssertTrue(w.castSpell(h, 0))
        w.tick()
        XCTAssertEqual(w.s.units[t].stats.moveSpeed, speed * 0.6, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[t].stats.damageBonus, -0.3, accuracy: 1e-9)
        let dealt = CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(t), targetIndex: h, amount: 100,
                                             type: .trueDamage, source: .basicAttack)
        XCTAssertEqual(dealt, 70, accuracy: 1e-9)
        w.run(seconds: 2.5)
        XCTAssertEqual(w.s.units[t].stats.moveSpeed, speed, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 105 - 2.5 - Balance.dt, accuracy: 0.05)
        // 範囲外・ヒーロー以外は対象外
        var o = SkillWorld()
        let h2 = o.addHero("H001", team: .blue, at: skillArena, spells: ["BS10", "BS01"])
        o.addMinion(team: .red, at: skillArena + Vec2(200, 0))
        o.addHero("H003", team: .red, at: skillArena + Vec2(800, 0))
        XCTAssertFalse(o.castSpell(h2, 0))
    }

    // MARK: - 練習場・コマンド経由

    func testPracticeNoCooldownsAppliesToSpells() {
        var w = SkillWorld(noCooldowns: true)
        let h = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS04", "BS06"])
        XCTAssertTrue(w.castSpell(h, 0))
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 0)
        XCTAssertTrue(w.castSpell(h, 0))
    }

    func testInvalidSpellIndexOrDeadHeroFails() {
        var w = SkillWorld()
        let h = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS04", "BS06"])
        XCTAssertFalse(w.castSpell(h, 2))
        XCTAssertFalse(w.castSpell(h, -1))
        w.s.units[h].isAlive = false
        XCTAssertFalse(w.castSpell(h, 0))
        XCTAssertFalse(SpellSystem.canCast(w.s, w.ctx, heroIndex: h, spellIndex: 0))
    }

    // MARK: - BS11 処断

    func testExecuteDealsTrueDamageScalingWithMissingHP() {
        var w = SkillWorld()
        let h = w.addHero("H006", team: .blue, at: skillArena, level: 5, spells: ["BS11", "BS01"])
        let t = w.addHero("H013", team: .red, at: skillArena + Vec2(500, 0))
        w.s.units[t].hp = w.s.units[t].stats.maxHP * 0.4
        let missing = w.s.units[t].stats.maxHP - w.s.units[t].hp
        let hpBefore = w.s.units[t].hp
        XCTAssertTrue(w.castSpell(h, 0, .unit(w.id(t))))
        XCTAssertEqual(hpBefore - w.s.units[t].hp, 150 + 30 * 5 + 0.25 * missing, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 90)
        // 射程外・ミニオンのみなら失敗（CD を消費しない）
        var o = SkillWorld()
        let h2 = o.addHero("H006", team: .blue, at: skillArena, spells: ["BS11", "BS01"])
        let far = o.addHero("H013", team: .red, at: skillArena + Vec2(700, 0))
        o.addMinion(team: .red, at: skillArena + Vec2(200, 0))
        XCTAssertFalse(o.castSpell(h2, 0, .unit(o.id(far))))
        XCTAssertEqual(o.s.units[h2].hero!.spellCooldowns[0], 0)
    }

    // MARK: - BS12 鼓舞

    func testInspireBoostsAttackSpeedForFiveSeconds() {
        var w = SkillWorld()
        let h = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS12", "BS01"])
        let base = w.s.units[h].stats.attackSpeed
        XCTAssertTrue(w.castSpell(h, 0))
        w.tick()
        XCTAssertEqual(w.s.units[h].stats.attackSpeed, base * 1.5, accuracy: 1e-9)
        w.run(seconds: 5.1)
        XCTAssertEqual(w.s.units[h].stats.attackSpeed, base, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 75 - 5.1, accuracy: 0.1)
    }

    // MARK: - BS13 石化

    func testPetrifyStunsNearbyEnemyHeroesThenSlows() {
        var w = SkillWorld()
        let h = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS13", "BS01"])
        let near = w.addHero("H003", team: .red, at: skillArena + Vec2(300, 0))
        let far = w.addHero("H013", team: .red, at: skillArena + Vec2(800, 0))
        let ally = w.addHero("H002", team: .blue, at: skillArena + Vec2(0, 200))
        XCTAssertTrue(w.castSpell(h, 0))
        XCTAssertTrue(w.s.units[near].has(.stun))
        XCTAssertFalse(w.s.units[far].has(.stun))
        XCTAssertFalse(w.s.units[ally].has(.stun))
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 80)
        w.run(seconds: 0.9)
        XCTAssertFalse(w.s.units[near].has(.stun), "0.8 秒でスタンは切れる")
        XCTAssertEqual(w.s.units[near].status(.slow)?.magnitude ?? 0, 0.3, accuracy: 1e-9)
        w.run(seconds: 1.6)
        XCTAssertFalse(w.s.units[near].has(.slow))
        // CC 無効中は掛からない
        var c = SkillWorld()
        let h2 = c.addHero("H001", team: .blue, at: skillArena, spells: ["BS13", "BS01"])
        let t = c.addHero("H003", team: .red, at: skillArena + Vec2(300, 0))
        CombatSystem.addStatus(&c.s, targetIndex: t, StatusEffect(kind: .ccImmune, duration: 2))
        XCTAssertTrue(c.castSpell(h2, 0))
        XCTAssertFalse(c.s.units[t].has(.stun))
    }

    // MARK: - BS14 火炎弾

    func testFlameshotHitsFirstEnemyHeroWithKnockback() {
        var w = SkillWorld()
        let h = w.addHero("H006", team: .blue, at: skillArena, level: 3, spells: ["BS14", "BS01"])
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(200, 0))
        let t = w.addHero("H013", team: .red, at: skillArena + Vec2(400, 0))
        let second = w.addHero("H003", team: .red, at: skillArena + Vec2(560, 0))
        let startX = w.s.units[t].pos.x
        XCTAssertTrue(w.castSpell(h, 0, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.s.units[h].hero!.spellCooldowns[0], 55)
        w.run(seconds: 0.5)
        XCTAssertEqual(w.damage(to: t, from: .spell), w.mitigated(100 + 20 * 3, .magic, on: t), accuracy: 1e-6)
        XCTAssertEqual(w.damage(to: minion), 0, "ミニオンには当たらない")
        XCTAssertEqual(w.damage(to: second), 0, "貫通しない")
        XCTAssertGreaterThan(w.s.units[t].pos.x, startX + 100, "進行方向へ押し出される")
        // 外れても発動（CD 消費）
        var m = SkillWorld()
        let h2 = m.addHero("H006", team: .blue, at: skillArena, spells: ["BS14", "BS01"])
        XCTAssertTrue(m.castSpell(h2, 0, .direction(Vec2(0, 1))))
        XCTAssertEqual(m.s.units[h2].hero!.spellCooldowns[0], 55)
        // 射程（700）の外には届かない
        var f = SkillWorld()
        let h3 = f.addHero("H006", team: .blue, at: skillArena, spells: ["BS14", "BS01"])
        let out = f.addHero("H013", team: .red, at: skillArena + Vec2(900, 0))
        XCTAssertTrue(f.castSpell(h3, 0, .direction(Vec2(1, 0))))
        f.run(seconds: 1)
        XCTAssertEqual(f.damage(to: out), 0)
    }

    // MARK: - BS15 報復

    func testVengeanceReducesDamageAndReflectsToAttacker() {
        var w = SkillWorld()
        let h = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS15", "BS01"])
        let e = w.addHero("H003", team: .red, at: skillArena + Vec2(200, 0))
        XCTAssertTrue(w.castSpell(h, 0))
        w.tick()
        let attackerHP = w.s.units[e].hp
        let before = w.s.units[h].hp
        let dealt = CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: h, amount: 200,
                                             type: .physical, source: .spell)
        XCTAssertEqual(before - w.s.units[h].hp, dealt, accuracy: 1e-6)
        let expected = w.mitigated(200, .physical, on: h) * (1 - 0.30)
        XCTAssertEqual(dealt, expected, accuracy: 1e-6, "被ダメ −30%")
        XCTAssertEqual(attackerHP - w.s.units[e].hp, dealt * 0.35, accuracy: 1e-6, "35% を確定ダメージで反射")
        // 継続ダメージは反射しない
        let hp2 = w.s.units[e].hp
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: h, amount: 100, type: .trueDamage, source: .dot)
        XCTAssertEqual(w.s.units[e].hp, hp2, accuracy: 1e-9)
        // 5 秒で切れる
        w.run(seconds: 5.1)
        XCTAssertNil(w.s.units[h].statuses.first { $0.tag == Balance.Spells.vengeanceTag })
        let hp3 = w.s.units[e].hp
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: h, amount: 200, type: .physical, source: .spell)
        XCTAssertEqual(w.s.units[e].hp, hp3, accuracy: 1e-9)
    }

    func testVengeanceBetweenTwoHoldersDoesNotLoop() {
        var w = SkillWorld()
        let a = w.addHero("H001", team: .blue, at: skillArena, spells: ["BS15", "BS01"])
        let b = w.addHero("H003", team: .red, at: skillArena + Vec2(200, 0), spells: ["BS15", "BS01"])
        XCTAssertTrue(w.castSpell(a, 0))
        XCTAssertTrue(w.castSpell(b, 0))
        let hpB = w.s.units[b].hp
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(b), targetIndex: a, amount: 300, type: .physical, source: .spell)
        XCTAssertLessThan(w.s.units[b].hp, hpB)
        XCTAssertGreaterThan(w.s.units[b].hp, hpB - 300)
    }

    func testNewSpellsBreakStealthWhenOffensive() {
        for id in ["BS11", "BS13", "BS14"] {
            var w = SkillWorld()
            let h = w.addHero("H002", team: .blue, at: skillArena, spells: ["BS08", id])
            w.addHero("H003", team: .red, at: skillArena + Vec2(300, 0))
            XCTAssertTrue(w.castSpell(h, 0))
            XCTAssertTrue(w.s.units[h].has(.stealth))
            XCTAssertTrue(w.castSpell(h, 1, id == "BS14" ? .direction(Vec2(1, 0)) : .none), id)
            XCTAssertFalse(w.s.units[h].has(.stealth), "\(id) はステルスを解除する")
        }
        var w = SkillWorld()
        let h = w.addHero("H002", team: .blue, at: skillArena, spells: ["BS08", "BS15"])
        XCTAssertTrue(w.castSpell(h, 0))
        XCTAssertTrue(w.castSpell(h, 1))
        XCTAssertTrue(w.s.units[h].has(.stealth), "報復は解除しない")
    }
}
