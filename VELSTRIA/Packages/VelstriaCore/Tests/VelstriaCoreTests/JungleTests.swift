import XCTest
@testable import VelstriaCore

/// MLBB の現行マップに合わせたジャングル（キャンプの種類・草むら・バフ。docs/DESIGN.md §2・§4、Balance.Jungle）。
final class JungleTests: XCTestCase {
    typealias Kit = WorldTestKit
    let map = MapDefinition.standard
    private let spot = Vec2(6000, 6000)

    // MARK: - マップ

    func testCampKindsMatchMLBBLayout() {
        for side in Team.players {
            let kinds = map.camps.filter { $0.side == side }.map(\.kind).sorted { $0.rawValue < $1.rawValue }
            XCTAssertEqual(kinds, [.blueSentinel, .redSentinel, .hornLizard, .emberBeetle, .magmaGolem], "\(side)")
        }
        let neutral = map.camps.filter { $0.side == .neutral }
        XCTAssertEqual(neutral.filter { $0.kind == .treasureCrab }.count, 2)
        XCTAssertEqual(neutral.filter { $0.kind == .mossWanderer }.count, 1)
        XCTAssertFalse(map.camps.contains { $0.kind == .small })
        // 宝殻蟹は左上・右下の川の端に点対称で 1 体ずつ
        let crabs = neutral.filter { $0.kind == .treasureCrab }.map(\.pos)
        XCTAssertEqual(crabs[1], crabs[0].mirrored)
        XCTAssertLessThan(crabs[0].x, 3000)
        XCTAssertGreaterThan(crabs[0].y, 8000)
        // 出現・再出現（Patch 2.1.88: 両陣地のキャンプは 0:25 に揃って出る）
        for c in map.camps where c.side != .neutral {
            XCTAssertEqual(c.firstSpawn, Balance.Jungle.campFirstSpawn)
            XCTAssertEqual(c.respawn, c.kind.isSentinel ? Balance.Jungle.buffRespawn : Balance.Jungle.creepRespawn)
        }
    }

    func testMultiRectBushIsOneBush() {
        let groups = Dictionary(grouping: map.brushes, by: \.bush)
        // 角の斜めの帯・宝殻蟹の右・中央の帯（片側 3 か所 × 2）
        XCTAssertEqual(groups.values.filter { $0.count > 1 }.count, 6)
        for (bush, rects) in groups {
            XCTAssertEqual(bush, rects.map(\.id).min())
            for r in rects { XCTAssertEqual(map.brushIndex(at: r.rect.center), bush, "rect \(r.id)") }
        }
    }

    func testUnitsInDifferentRectsOfSameBushSeeEachOther() {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.setTime(&s, 60)
        Kit.suppressWaves(&s)
        let rects = Dictionary(grouping: map.brushes, by: \.bush).values.first { $0.count == 4 }!.sorted { $0.id < $1.id }
        let a = rects[0].rect.center, b = rects[1].rect.center
        XCTAssertGreaterThan(a.distance(to: b), Balance.brushRevealRadius)
        let hider = Kit.addHero(&s, ctx, team: .red, pos: a)
        let scout = Kit.addHero(&s, ctx, team: .blue, pos: b)
        VisionSystem.update(&s, ctx)
        XCTAssertEqual(s.units[hider].brushIndex, s.units[scout].brushIndex)
        XCTAssertTrue(s.isVisible(hider, to: .blue))
    }

    // MARK: - 出現

    func testCrabletRespawnsEveryTwentySecondsThenCrabAtThreeMinutes() {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.suppressWaves(&s)
        let camp = ctx.map.camps.first { $0.kind == .treasureCrab }!
        func alive() -> [MonsterKind] {
            s.units.filter { $0.isAlive && $0.monster?.campID == camp.id }.map { $0.monster!.kind }
        }
        func killAll() {
            for i in s.units.indices where s.units[i].isAlive && s.units[i].monster?.campID == camp.id { Kit.kill(&s, i) }
            s.removeFinishedEntities()
        }
        Kit.setTime(&s, 41.9)
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(alive(), [])
        Kit.setTime(&s, 42)
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(alive(), [.crablet])
        // 子は倒されると 20 秒後に出直す
        Kit.setTime(&s, 60)
        killAll()
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(s.world.campRespawnAt[camp.id] ?? 0, 80, accuracy: 1e-6)
        Kit.setTime(&s, 80)
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(alive(), [.crablet])
        // 3:00 を越える分は 3:00 に親が出る
        Kit.setTime(&s, 170)
        killAll()
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(s.world.campRespawnAt[camp.id] ?? 0, Balance.Jungle.crabUpgradeTime, accuracy: 1e-6)
        Kit.setTime(&s, Balance.Jungle.crabUpgradeTime)
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(alive(), [.treasureCrab])
        // 親は 120 秒
        Kit.setTime(&s, 200)
        killAll()
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(s.world.campRespawnAt[camp.id] ?? 0, 320, accuracy: 1e-6)
    }

    func testLivingCrabletTurnsIntoCrabAtThreeMinutes() {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.suppressWaves(&s)
        let camp = ctx.map.camps.first { $0.kind == .treasureCrab }!
        Kit.setTime(&s, 42)
        SpawnSystem.update(&s, ctx)
        Kit.setTime(&s, Balance.Jungle.crabUpgradeTime)
        SpawnSystem.update(&s, ctx)
        let kinds = s.units.filter { $0.isAlive && $0.monster?.campID == camp.id }.map { $0.monster!.kind }
        XCTAssertEqual(kinds, [.treasureCrab])
        XCTAssertNil(s.world.campRespawnAt[camp.id])
    }

    func testEmberBeetleLeavesGrubThatExpiresWithoutReward() {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.setTime(&s, 30)
        Kit.suppressWaves(&s)
        SpawnSystem.update(&s, ctx)
        let camp = ctx.map.camps.first { $0.kind == .emberBeetle && $0.side == .blue }!
        let beetle = s.units.indices.first { s.units[$0].monster?.campID == camp.id }!
        let heroID = s.units[Kit.addHero(&s, ctx, team: .blue, pos: camp.pos + Vec2(0, -200))].id
        CombatSystem.applyDamage(&s, ctx, sourceID: heroID, targetIndex: beetle, amount: 99_999, type: .trueDamage,
                                 source: .basicAttack)
        DeathSystem.process(&s, ctx)
        s.removeFinishedEntities()
        let grubs = s.units.indices.filter { s.units[$0].isAlive && s.units[$0].monster?.kind == .emberGrub }
        XCTAssertEqual(grubs.count, 1)
        XCTAssertEqual(s.units[grubs[0]].monster?.campID, camp.id)
        // 幼体が残っている間は再出現の待ちに入らない
        SpawnSystem.update(&s, ctx)
        XCTAssertNil(s.world.campRespawnAt[camp.id])
        // 15 秒で報酬なしに消え、そこから 70 秒
        let gold = s.unit(heroID)!.hero!.gold
        Kit.setTime(&s, 30 + Balance.Jungle.grubLifetime)
        MonsterSystem.update(&s, ctx)
        XCTAssertFalse(s.units[grubs[0]].isAlive)
        DeathSystem.process(&s, ctx)
        s.removeFinishedEntities()
        SpawnSystem.update(&s, ctx)
        XCTAssertEqual(s.unit(heroID)!.hero!.gold, gold)
        XCTAssertEqual(s.world.campRespawnAt[camp.id] ?? 0, 30 + Balance.Jungle.grubLifetime + camp.respawn, accuracy: 1e-6)
    }

    // MARK: - モンスターの行動

    func testHornLizardHardensBelowHalfHP() {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.setTime(&s, 30)
        Kit.suppressWaves(&s)
        SpawnSystem.update(&s, ctx)
        let lizard = s.units.indices.first { s.units[$0].monster?.kind == .hornLizard }!
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: s.units[lizard].pos + Vec2(0, -300))
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: lizard,
                                 amount: s.units[lizard].stats.maxHP * 0.4, type: .trueDamage, source: .basicAttack)
        MonsterSystem.update(&s, ctx)
        XCTAssertFalse(s.units[lizard].has(.damageReduction), "半分までは硬くならない")
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: lizard,
                                 amount: s.units[lizard].stats.maxHP * 0.2, type: .trueDamage, source: .basicAttack)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[lizard].status(.damageReduction)?.magnitude ?? 0, Balance.Jungle.lizardHardenReduction)
        StatCalculator.recompute(&s, lizard, ctx)
        XCTAssertEqual(s.units[lizard].stats.damageReduction, Balance.Jungle.lizardHardenReduction, accuracy: 1e-9)
        // 全回復で解ける
        s.units[lizard].hp = s.units[lizard].stats.maxHP
        MonsterSystem.update(&s, ctx)
        XCTAssertFalse(s.units[lizard].has(.damageReduction))
    }

    func testMossWandererNeverFightsBackAndHealsWhenLeftAlone() {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.setTime(&s, 45)
        Kit.suppressWaves(&s)
        SpawnSystem.update(&s, ctx)
        let w = s.units.indices.first { s.units[$0].monster?.kind == .mossWanderer }!
        XCTAssertEqual(s.units[w].stats.attack, 0)
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: s.units[w].pos + Vec2(0, -200))
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: w, amount: 100, type: .physical,
                                 source: .basicAttack)
        MonsterSystem.update(&s, ctx)
        XCTAssertNil(s.units[w].attackTargetID)
        XCTAssertLessThan(s.units[w].hp, s.units[w].stats.maxHP)
        Kit.setTime(&s, 45 + MonsterSystem.passiveResetDelay + 0.1)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[w].hp, s.units[w].stats.maxHP)
    }

    // MARK: - バフ

    func testPurpleBuffCutsSkillCostsAndHealsOnKill() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let blue = f.heroes(.blue)
        let mana = blue.first { f.hero($0).resourceKind == .mana }!
        let energy = blue.first { f.hero($0).resourceKind == .energy }!
        XCTAssertEqual(JungleBuffs.skillCostMultiplier(f.s.units[mana]), 1)
        for i in [mana, energy] {
            CombatSystem.addStatus(&f.s, targetIndex: i, StatusEffect(kind: .blueBuff, duration: 75, tag: "sentinel"))
        }
        XCTAssertEqual(JungleBuffs.skillCostMultiplier(f.s.units[mana]), 0.4, accuracy: 1e-9)
        XCTAssertEqual(JungleBuffs.skillCostMultiplier(f.s.units[energy]), 0.75, accuracy: 1e-9)
        StatCalculator.recompute(&f.s, mana, f.ctx)
        XCTAssertEqual(f.s.units[mana].stats.cooldownReduction, Balance.Jungle.purpleCooldownReduction, accuracy: 1e-9)
        // 敵を倒すと回復: ミニオン 3% / モンスター 12%
        let maxHP = f.s.units[mana].stats.maxHP
        f.s.units[mana].hp = maxHP * 0.5
        f.kill(f.addMinion(.melee, team: .red, at: spot), by: f.id(mana))
        XCTAssertEqual(f.s.units[mana].hp, maxHP * 0.53, accuracy: 1e-6)
        f.kill(f.addMonster(.campLarge, at: spot), by: f.id(mana))
        XCTAssertEqual(f.s.units[mana].hp, maxHP * 0.65, accuracy: 1e-6)
    }

    func testJungleCreepGivesHealingBuffAndLevelTwo() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue).first { f.hero($0).resourceKind == .mana }!
        f.place(a, at: spot)
        let st = f.s.units[a].stats
        f.s.units[a].hp = st.maxHP - 500
        f.s.units[a].resource = 0
        f.kill(f.addMonster(.hornLizard, at: spot), by: f.id(a))
        // 1 体で Lv2（Patch 2.1.88）
        XCTAssertEqual(f.hero(a).level, 2)
        // XP（Lv2 で最大 HP が上がり、HP は割合を保つ）の後に 350 回復する
        let after = f.s.units[a]
        XCTAssertEqual(after.stats.maxHP - after.hp, 500 * after.stats.maxHP / st.maxHP - Balance.Jungle.healingBuffHP,
                       accuracy: 1e-6)
        XCTAssertEqual(after.resource, st.maxResource * Balance.Jungle.healingBuffManaPct, accuracy: 1e-6)
    }

    func testCrabGivesGoldOverTime() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0]
        f.place(a, at: spot)
        let gold = f.hero(a).gold
        f.kill(f.addMonster(.treasureCrab, at: spot), by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold, Balance.Economy.monsterGold(.treasureCrab))
        XCTAssertEqual(f.s.units[a].status(.goldBuff)?.magnitude ?? 0, 60.0 / 18, accuracy: 1e-9)
        let g0 = f.hero(a).gold
        for _ in 0..<(Int((18 / Balance.dt).rounded()) + 5) {
            JungleBuffs.update(&f.s, f.ctx)
            StatusSystem.update(&f.s, f.ctx)
        }
        XCTAssertFalse(f.s.units[a].has(.goldBuff))
        XCTAssertEqual(f.hero(a).gold - g0, 60, accuracy: 0.5)
    }

    func testMossWandererGrantsMossGrassAndAllyGold() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let blue = f.heroes(.blue)
        let a = blue[0]
        let b = blue.first { $0 != a && f.hero($0).resourceKind == .mana }!
        let river = Vec2(6000, 6000)
        XCTAssertTrue(f.ctx.map.isInRiver(river))
        f.place(a, at: river)
        f.place(b, at: river + Vec2(300, 0))
        let gb = f.hero(b).gold
        f.kill(f.addMonster(.mossWanderer, at: river), by: f.id(a))
        XCTAssertEqual(f.s.units[a].status(.mossGrass)?.remaining ?? 0, Balance.Jungle.mossGrassDuration)
        XCTAssertEqual(f.hero(b).gold - gb, Balance.Jungle.wandererAllyGold)
        // 川では移動速度 +15%
        StatCalculator.recompute(&f.s, a, f.ctx)
        let inRiver = f.s.units[a].stats.moveSpeed
        f.place(a, at: Vec2(3000, 3000))
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(inRiver / f.s.units[a].stats.moveSpeed, 1 + Balance.Jungle.mossGrassRiverSpeed, accuracy: 1e-9)
        // 近くの味方の Mana を毎秒 1%
        f.place(a, at: river)
        f.s.units[b].resource = 0
        for _ in 0..<Int(Balance.tickRate) { JungleBuffs.update(&f.s, f.ctx) }
        XCTAssertEqual(f.s.units[b].resource, f.s.units[b].stats.maxResource * 0.01, accuracy: 1e-6)
    }

    func testWyrmBlessingShieldRegeneratesAndGrantsAttack() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        StatCalculator.recompute(&f.s, a, f.ctx)
        let baseAttack = f.s.units[a].stats.attack
        f.kill(f.addMonster(.astralWyrm, at: Vec2(8300, 3700)), by: f.id(a))
        let level = Double(f.hero(a).level)
        func shield() -> Double { f.s.units[a].shields.first { $0.tag == JungleBuffs.wyrmShieldTag }?.amount ?? 0 }
        let full = shield()
        XCTAssertEqual(full, 400 + 40 * level, accuracy: 1e-9)
        // シールドがある間は攻撃力 +（20 + 2×Lv）（装備なし = 物理）
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attack - baseAttack, 20 + 2 * level, accuracy: 1e-6)
        // 削られて 5 秒経たなければ張り直さない
        let k = f.s.units[a].shields.firstIndex { $0.tag == JungleBuffs.wyrmShieldTag }!
        f.s.units[a].shields[k].amount = 10
        f.s.units[a].lastDamagedTime = f.s.time
        JungleBuffs.update(&f.s, f.ctx)
        XCTAssertEqual(shield(), 10)
        f.s.time += Balance.Jungle.wyrmShieldRegenDelay
        JungleBuffs.update(&f.s, f.ctx)
        XCTAssertEqual(shield(), full, accuracy: 1e-9)
        // 割れて消えても張り直す
        f.s.units[a].shields.removeAll()
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attack, baseAttack, accuracy: 1e-6)
        f.s.units[a].lastDamagedTime = f.s.time - Balance.Jungle.wyrmShieldRegenDelay
        JungleBuffs.update(&f.s, f.ctx)
        XCTAssertEqual(shield(), full, accuracy: 1e-9)
    }
}
