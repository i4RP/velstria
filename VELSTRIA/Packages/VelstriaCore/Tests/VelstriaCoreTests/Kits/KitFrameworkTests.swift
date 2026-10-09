import XCTest
@testable import VelstriaCore

/// キット層の枠組み（docs/SKILL_KITS.md の Phase 0）。本物のキットは無効なので、テスト専用の TestKit とプリミティブで確かめる。
/// 無効なキット（H025..H034 のスタブ）と、キットなしのヒーローが「これまでと同じ」であることも検査する。
final class KitFrameworkTests: KitTestCase {

    // MARK: - レジストリ・キットなしの不変性

    func testStubsAreRegisteredButNotReady() {
        HeroKits.testOverride = []
        XCTAssertEqual(HeroKits.all.map(\.heroID),
                       ["H025", "H026", "H027", "H028", "H029", "H030", "H031", "H032", "H033", "H034"])
        // 有効化されたキット（各ヒーローの担当が isReady を true にした分）は存在し、残りのスタブは存在しないのと同じ
        let ready = Set(HeroKits.all.filter(\.isReady).map(\.heroID))
        for hero in MasterData.shared.heroes {
            XCTAssertEqual(HeroKits.hasKit(hero.heroID), ready.contains(hero.heroID), hero.heroID)
        }
        // 無効なキットは存在しないのと同じ: ユニットに状態が付かない（有効なキットのヒーローには付く）
        let ctx = SkillWorld.standardContext
        for hero in ctx.master.heroes {
            let slot = PlayerSlot(team: .blue, heroID: hero.heroID, controller: .bot,
                                  position: MatchFactory.defaultPosition(for: hero.role), spells: ["BS01", "BS03"],
                                  displayName: hero.heroID)
            let unit = UnitFactory.makeHero(def: hero, slot: slot, pos: skillArena)
            XCTAssertEqual(unit.hero?.kit != nil, ready.contains(hero.heroID), hero.heroID)
        }
    }

    func testTestOverrideMakesHeroKitReadyAndAttachesState() {
        XCTAssertTrue(HeroKits.hasKit(KitTestCase.kitHero))
        XCTAssertFalse(HeroKits.hasKit("H001"))
        var w = SkillWorld()
        let k = w.addHero(KitTestCase.kitHero, team: .blue, at: skillArena)
        XCTAssertNotNil(w.s.units[k].hero?.kit, "makeHero は有効なキットのヒーローにだけ KitState を付ける")
        let plain = w.addHero("H001", team: .blue, at: skillArena + Vec2(0, 300))
        XCTAssertNil(w.s.units[plain].hero?.kit)
        XCTAssertNotNil(HeroKits.kit(of: w.s.units[k]))
        XCTAssertNil(HeroKits.kit(of: w.s.units[plain]))
    }

    func testKitlessTargetingAndNumbersEqualGeneric() {
        HeroKits.testOverride = []
        let m = MasterData.shared
        var stats = Stats()
        stats.attack = 120
        stats.abilityPower = 80
        // 有効なキットのヒーロー（Kit_H0xxTests が検査する）は除く
        for hero in m.heroes where !HeroKits.hasKit(hero.heroID) {
            for skill in m.skills(forHero: hero.heroID) {
                let g = SkillCatalog.genericTargeting(for: skill, hero: hero)
                XCTAssertEqual(SkillCatalog.targeting(for: skill, hero: hero), g, skill.skillID)
                XCTAssertEqual(HeroKits.targeting(for: skill, hero: hero, stage: 1), g, skill.skillID)
                for rank in 1...skill.slot.maxRank {
                    XCTAssertEqual(SkillCatalog.numbers(for: skill, hero: hero, rank: rank, stats: stats),
                                   SkillCatalog.genericNumbers(for: skill, hero: hero, rank: rank, stats: stats),
                                   skill.skillID)
                }
                // 追加フィールドは既定値のまま
                XCTAssertEqual(g.shape, .auto)
                XCTAssertEqual(g.halfAngle, 0)
                XCTAssertNil(g.reachOverride)
                XCTAssertFalse(g.requiresTarget)
                XCTAssertFalse(g.recastable)
            }
        }
    }

    func testReachOverrideReplacesArchetypeReach() {
        var t = SkillTargeting(archetype: .cone, aim: .direction, range: 400, radius: 400)
        XCTAssertEqual(t.reach, 400)
        t.reachOverride = 900
        XCTAssertEqual(t.reach, 900)
        let p = SkillTargeting(archetype: .passive, aim: .none, range: 0, radius: 0, reachOverride: 50)
        XCTAssertEqual(p.reach, 50, "reachOverride はアーキタイプより優先")
    }

    func testKitAwareCatalogAndActiveTargeting() throws {
        var w = SkillWorld()
        let k = w.addKitHero()
        let hero = try XCTUnwrap(w.ctx.master.hero(KitTestCase.kitHero))
        let skill = try XCTUnwrap(w.ctx.master.skill(hero: hero.heroID, slot: .skill1))
        let generic = SkillCatalog.genericTargeting(for: skill, hero: hero)
        // stage 0 はキットの記述（recastable だけ立つ）
        var expected0 = generic
        expected0.recastable = true
        XCTAssertEqual(SkillCatalog.targeting(for: skill, hero: hero), expected0)
        XCTAssertEqual(SkillCatalog.activeTargeting(w.s, caster: k, slot: .skill1, skill: skill, hero: hero), expected0)
        // 再使用の窓が開くと次の段の記述
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        let active = SkillCatalog.activeTargeting(w.s, caster: k, slot: .skill1, skill: skill, hero: hero)
        XCTAssertEqual(active.shape, .fan)
        XCTAssertEqual(active.halfAngle, 0.5)
        XCTAssertEqual(active.reach, 999)
        XCTAssertTrue(active.requiresTarget)
        // 数値: 汎用を土台に extras / stages / recastWindow
        let stats = w.s.units[k].stats
        let n = SkillCatalog.numbers(for: skill, hero: hero, rank: 1, stats: stats)
        let g = SkillCatalog.genericNumbers(for: skill, hero: hero, rank: 1, stats: stats)
        XCTAssertEqual(n.damage, g.damage)
        XCTAssertEqual(n.extras, [KitStat(key: "bonus", value: 12.5)])
        XCTAssertEqual(n.stages, 3)
        XCTAssertEqual(n.recastWindow, 3)
        XCTAssertEqual(HeroKits.numbers(for: skill, hero: hero, rank: 1, stats: stats, stage: 2).extras.first?.value, 14.5)
        // キットなしのヒーローの activeTargeting は汎用
        let plain = w.addHero("H001", team: .blue, at: skillArena + Vec2(0, 400))
        let h1 = try XCTUnwrap(w.ctx.master.hero("H001"))
        let s1 = try XCTUnwrap(w.ctx.master.skill(hero: "H001", slot: .skill1))
        XCTAssertEqual(SkillCatalog.activeTargeting(w.s, caster: plain, slot: .skill1, skill: s1, hero: h1),
                       SkillCatalog.genericTargeting(for: s1, hero: h1))
    }

    func testKitTextFillsPlaceholdersFromSimNumbers() throws {
        var n = SkillNumbers()
        n.damage = 123.4
        n.hits = 3
        n.shield = 80.6
        n.heal = 45
        n.cooldown = 6.5
        n.extras = [KitStat(key: "a", value: 1.5), KitStat(key: "b", value: 4)]
        let t = SkillTargeting(archetype: .cone, aim: .direction, range: 650, radius: 155.2)
        XCTAssertEqual(KitText.fill("{damage}/{total}/{hits}/{shield}/{heal}/{range}/{radius}/{cd}/{x0}/{x1}/{x2}",
                                    numbers: n, targeting: t), "123/370/3/81/45/650/155/6.5/1.5/4/0")
        let text = try XCTUnwrap(HeroKits.text(heroID: KitTestCase.kitHero, slot: .skill1))
        XCTAssertEqual(text.filled(english: false, numbers: n, targeting: t), "ダメージ123 範囲650 X1.5")
        XCTAssertEqual(text.filled(english: true, numbers: n, targeting: t), "Deals 123 in 650, x1.5")
        XCTAssertNil(HeroKits.text(heroID: KitTestCase.kitHero, slot: .skill2))
        XCTAssertNil(HeroKits.text(heroID: "H001", slot: .skill1))
    }

    // MARK: - コストの上書き・タグ

    /// コストとタグだけを上書きするキット（スキル1: ランク × 10 + 20 の Mana 基準（Energy のヒーローは × 0.6）/ スキル2: 実効値 33）。
    private struct CostKit: HeroKit {
        let heroID: String
        var isReady: Bool { true }

        func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
            switch slot {
            case .skill1: return HeroKits.resourceCost(20 + Double(rank) * 10, hero: hero)
            case .skill2: return 33
            default: return base
            }
        }

        func text(slot: SkillSlot) -> KitText? {
            slot == .skill1 ? KitText(ja: "a", en: "b", tags: [KitTag.aoe, KitTag.slow]) : nil
        }
    }

    func testKitCostOverrideIsPerRankAndUsedByNumbersValidationAndPractice() throws {
        // H002 は Energy のヒーロー（汎用のコストは × 0.6）
        HeroKits.testOverride = [CostKit(heroID: "H002")]
        let hero = try XCTUnwrap(MasterData.shared.hero("H002"))
        XCTAssertEqual(hero.resource, .energy)
        func skill(_ slot: SkillSlot) throws -> SkillDef { try XCTUnwrap(MasterData.shared.skill(hero: "H002", slot: slot)) }
        let mult = Balance.energyCostMultiplier
        // 汎用の関数はキットを含まない
        XCTAssertEqual(SkillSystem.cost(for: try skill(.skill1), resource: .energy), try skill(.skill1).cost * mult)
        // ランク込み: スキル1 は Mana 基準の素の値に Energy の倍率（resourceCost）、スキル2 は実効値のまま、ほかは汎用
        XCTAssertEqual(SkillSystem.cost(for: try skill(.skill1), hero: hero, rank: 1), 30 * mult, accuracy: 1e-9)
        XCTAssertEqual(SkillSystem.cost(for: try skill(.skill1), hero: hero, rank: 3), 50 * mult, accuracy: 1e-9)
        XCTAssertEqual(SkillSystem.cost(for: try skill(.skill1), hero: hero, rank: 99), 60 * mult, accuracy: 1e-9, "最大ランクに丸める")
        XCTAssertEqual(SkillSystem.cost(for: try skill(.skill1), hero: hero, rank: 0), 30 * mult, accuracy: 1e-9, "1 に丸める")
        XCTAssertEqual(SkillSystem.cost(for: try skill(.skill2), hero: hero, rank: 2), 33)
        XCTAssertEqual(SkillSystem.cost(for: try skill(.ultimate), hero: hero, rank: 1),
                       try skill(.ultimate).cost * mult, accuracy: 1e-9)
        // numbers の cost も同じ値（HUD・ツールチップ）
        var w = SkillWorld()
        let k = w.addHero("H002", team: .blue, at: skillArena, level: 12, ranks: [2, 1, 1], facing: 0)
        let stats = w.s.units[k].stats
        XCTAssertEqual(SkillCatalog.numbers(for: try skill(.skill1), hero: hero, rank: 2, stats: stats).cost, 40 * mult,
                       accuracy: 1e-9)
        XCTAssertEqual(SkillCatalog.numbers(for: try skill(.skill2), hero: hero, rank: 1, stats: stats).cost, 33)
        XCTAssertEqual(SkillCatalog.genericNumbers(for: try skill(.skill2), hero: hero, rank: 1, stats: stats).cost,
                       try skill(.skill2).cost * mult, accuracy: 1e-9)
        // 検証: 足りなければ撃てず、ちょうどなら撃てて、その値だけ消費する（ランク 2 のスキル1 = 40 × 0.6）
        let need = 40 * mult
        w.s.units[k].resource = need - 0.5
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: k, slot: .skill1))
        XCTAssertFalse(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        w.s.units[k].resource = need
        XCTAssertTrue(SkillSystem.canCast(w.s, w.ctx, heroIndex: k, slot: .skill1))
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.s.units[k].resource, 0, accuracy: 1e-9)
        w.s.units[k].resource = 100
        XCTAssertTrue(w.cast(k, .skill2, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.s.units[k].resource, 67, accuracy: 1e-9)
        // 練習場の CD なしはコストも 0
        var free = SkillWorld(noCooldowns: true)
        let f = free.addHero("H002", team: .blue, at: skillArena, level: 12, ranks: [2, 1, 1], facing: 0)
        free.s.units[f].resource = 100
        XCTAssertTrue(free.cast(f, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(free.s.units[f].resource, 100, accuracy: 1e-9)
    }

    func testKitlessCostEqualsGenericForEverySkillAndRank() throws {
        HeroKits.testOverride = []
        for hero in MasterData.shared.heroes where !HeroKits.hasKit(hero.heroID) {
            for skill in MasterData.shared.skills(forHero: hero.heroID) {
                for rank in 0...5 {
                    XCTAssertEqual(SkillSystem.cost(for: skill, hero: hero, rank: rank),
                                   SkillSystem.cost(for: skill, resource: hero.resource), "\(hero.heroID) \(skill.slot)")
                }
            }
        }
    }

    func testTagsComeFromTheKitTextAndDefaultToEmpty() {
        HeroKits.testOverride = [CostKit(heroID: "H002")]
        XCTAssertEqual(KitText(ja: "a", en: "b").tags, [])
        XCTAssertEqual(HeroKits.tags(heroID: "H002", slot: .skill1), ["aoe", "slow"])
        XCTAssertEqual(HeroKits.tags(heroID: "H002", slot: .skill2), [], "text が無いスロットは空")
        XCTAssertEqual(HeroKits.tags(heroID: "H001", slot: .skill1), [], "キットが無いヒーローは空")
        XCTAssertEqual(KitTag.all, ["buff", "aoe", "slow", "clash", "disrupt", "burst", "mobility", "heal", "shield",
                                    "control", "stun", "pull", "execute"])
        // 既存のテキストの検証に影響しない（テンプレートの埋め込みは tags と無関係）
        let text = KitText(ja: "x{damage}", en: "y", tags: [KitTag.buff])
        var n = SkillNumbers()
        n.damage = 5
        XCTAssertEqual(text.filled(english: false, numbers: n, targeting: SkillTargeting(archetype: .passive, aim: .none,
                                                                                          range: 0, radius: 0)), "x5")
    }


    func testRecastWindowRoutesWithoutCooldownOrCostAndCloses() throws {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill1))
        XCTAssertEqual(HeroKits.activeStage(w.s.units[k].hero!, slot: .skill1), 0)

        // 初回: コストと CD を必ず消費し、窓が開く
        let resourceBefore = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        let afterFirst = w.s.units[k].resource
        XCTAssertLessThan(afterFirst, resourceBefore, "初回はコストを消費する")
        let cd = w.s.units[k].hero!.cooldown(.skill1)
        XCTAssertGreaterThan(cd, 0, "初回は CD を消費する（ボットの命中判定が CD で見る）")
        XCTAssertEqual(w.kit(k).ints[0], 1)
        let info = try XCTUnwrap(HeroKits.recast(w.s.units[k].hero!, slot: .skill1))
        XCTAssertEqual(info.stage, 1)
        XCTAssertEqual(info.total, 3)
        XCTAssertEqual(info.charges, 2)
        XCTAssertEqual(HeroKits.activeStage(w.s.units[k].hero!, slot: .skill1), 1)
        XCTAssertEqual(w.castEvents.last?.stage, 0)

        // 再使用: CD が残っていてもコスト 0 で撃てる。リソースが空でも撃てる（canCast も真）
        w.tick(3)
        w.s.units[k].resource = 0
        XCTAssertTrue(SkillSystem.canCast(w.s, w.ctx, heroIndex: k, slot: .skill1))
        XCTAssertTrue(w.cast(k, .skill1, .point(w.s.units[e].pos)))
        XCTAssertEqual(w.s.units[k].resource, 0, accuracy: 1e-9, "再使用はコスト無し")
        XCTAssertEqual(w.kit(k).ints[1], 1)
        XCTAssertEqual(w.kit(k).ints[2], 1, "最初の再使用は stage 1")
        XCTAssertEqual(w.castEvents.last?.stage, 1)
        XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(.skill1), 0)
        XCTAssertEqual(HeroKits.recast(w.s.units[k].hero!, slot: .skill1)?.stage, 2, "次の段へ進む")
        XCTAssertEqual(HeroKits.recast(w.s.units[k].hero!, slot: .skill1)?.charges, 1)

        // 2 回目の再使用で charges が尽き、窓が閉じて cooldownOnClose が適用される
        XCTAssertTrue(w.cast(k, .skill1, .none))
        XCTAssertEqual(w.kit(k).ints[1], 2)
        XCTAssertEqual(w.kit(k).ints[2], 2)
        XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill1))
        XCTAssertEqual(w.kit(k).ints[6], 1, "onWindowClosed")
        XCTAssertEqual(w.kit(k).ints[7], 0, "時間切れではない")
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), 7, accuracy: 1e-9)
        // 閉じた後は通常の発動（CD とコスト）に戻る
        w.s.units[k].resource = w.s.units[k].stats.maxResource
        XCTAssertFalse(w.cast(k, .skill1, .none), "CD 中は撃てない")
        XCTAssertEqual(w.kit(k).ints[0], 1)
    }

    func testRecastWindowExpiresAndAppliesCooldownOnClose() {
        var w = SkillWorld()
        let k = w.addKitHero()
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        w.run(seconds: 2.5)
        XCTAssertNotNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill1), "3 秒の窓はまだ開いている")
        let remaining = HeroKits.recast(w.s.units[k].hero!, slot: .skill1)?.remaining ?? 0
        XCTAssertEqual(remaining, 0.5, accuracy: 0.1)
        w.run(seconds: 0.6)
        XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill1))
        XCTAssertEqual(w.kit(k).ints[6], 1)
        XCTAssertEqual(w.kit(k).ints[7], 1, "時間切れで閉じた")
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), 7, accuracy: 0.2, "閉じた時点で 7 秒（その後の数 tick 分だけ減っている）")
        XCTAssertEqual(w.kit(k).ints[1], 0, "再使用しなかった")
    }

    func testRecastFailsWithoutAimKeepsWindowAndCastingWhileStunnedFails() {
        var w = SkillWorld()
        let k = w.addKitHero()
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        // 行動不能なら再使用もできない（窓はそのまま）
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 0.2))
        XCTAssertFalse(w.cast(k, .skill1, .none))
        XCTAssertNotNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill1))
        XCTAssertEqual(w.kit(k).ints[1], 0)
    }

    func testRequiresTargetRecastNeedsAnEnemyInReach() {
        var w = SkillWorld()
        let k = w.addKitHero()
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        // 段 1 の照準は requiresTarget: 射程内に敵が居なければ再使用できず、窓はそのまま
        XCTAssertFalse(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.kit(k).ints[1], 0)
        XCTAssertNotNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill1))
        // 居れば照準点が対象でなくても、その敵に向けて撃つ
        let e = w.addDummyEnemy(at: skillArena + Vec2(0, 600))
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.kit(k).ints[1], 1)
        XCTAssertEqual(w.castEvents.last?.targetUnitID, nil, "TestKit は unit を渡さない")
        XCTAssertEqual(w.s.units[k].facing, Double.pi / 2, accuracy: 1e-9, "対象の方を向く")
        XCTAssertTrue(w.s.isTargetableEnemy(e, of: .blue))
    }

    func testCooldownOnCloseRespectsPracticeNoCooldowns() {
        var w = SkillWorld(noCooldowns: true)
        let k = w.addKitHero()
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        w.run(seconds: 3.2)
        XCTAssertEqual(w.kit(k).ints[6], 1)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), 0, "練習場の noCooldowns を尊重")
    }

    func testRefundAndSetCooldown() {
        var w = SkillWorld()
        let k = w.addKitHero()
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = 10
        Kit.refundCooldown(&w.s, w.ctx, caster: k, slot: .skill2, seconds: 4)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 6, accuracy: 1e-9)
        Kit.refundCooldown(&w.s, w.ctx, caster: k, slot: .skill2, seconds: 100)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 0)
        Kit.setCooldown(&w.s, w.ctx, caster: k, slot: .ultimate, seconds: 33)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), 33)
    }

    func testCanStartGatesFirstCastOnly() {
        var w = SkillWorld()
        let k = w.addKitHero()
        w.addDummyEnemy(at: skillArena + Vec2(300, 0))   // 再使用（stage 1）は射程内の対象が必要
        w.s.units[k].hero!.kit!.form = 9
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: k, slot: .skill1))
        XCTAssertFalse(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.kit(k).ints[0], 0)
        // 窓が開いている再使用では canStart は見ない
        w.s.units[k].hero!.kit!.form = 0
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        w.s.units[k].hero!.kit!.form = 9
        XCTAssertTrue(w.cast(k, .skill1, .none))
        XCTAssertEqual(w.kit(k).ints[1], 1)
    }

    func testBadgeAndCastEventFields() throws {
        var w = SkillWorld()
        let k = w.addKitHero()
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        let badge = try XCTUnwrap(HeroKits.badge(w.s.units[k].hero!, slot: .skill1))
        XCTAssertEqual(badge, KitBadge(kind: .stacks, value: 1, maxValue: 5))
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .skill2))
        let e = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(e.shape, .fan)
        XCTAssertEqual(e.halfAngle, 0.5)
        XCTAssertEqual(e.duration, 3)
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e.stage, 0)
        // 汎用の発動イベントは追加フィールドが既定値
        let plain = w.addHero("H001", team: .blue, at: skillArena + Vec2(0, 500))
        XCTAssertTrue(w.cast(plain, .skill1, .direction(Vec2(1, 0))))
        let g = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(g.stage, 0)
        XCTAssertEqual(g.shape, .auto)
        XCTAssertEqual(g.halfAngle, 0)
        XCTAssertEqual(g.duration, 0)
        XCTAssertEqual(g.count, 0)
    }

    // MARK: - 遅延・連撃

    func testScheduledTimersFireInInsertionOrderAndZeroFiresSameTick() {
        var w = SkillWorld()
        let k = w.addKitHero()
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 1, after: 0.1)
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 2, after: 0)
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 3, after: 0.1)
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k), 3)
        w.tick()
        XCTAssertEqual(w.kit(k).ints[4], 2, "remaining 0 は同 tick に発火")
        w.tick()
        XCTAssertEqual(w.kit(k).ints[4], 2)
        w.tick()
        XCTAssertEqual(w.kit(k).ints[4], 213, "0.1 秒（3 tick）後。同時刻のタイマーは挿入順")
        XCTAssertEqual(w.kit(k).ints[3], 3)
        XCTAssertTrue(w.kit(k).scheduled.isEmpty)
    }

    func testStrikeSequenceFiresCountTimesWithIndices() {
        var w = SkillWorld()
        let k = w.addKitHero()
        XCTAssertTrue(w.cast(k, .ultimate))
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k, code: 5), 3)
        XCTAssertEqual(w.kit(k).scheduled.map(\.index), [0, 1, 2])
        w.run(seconds: 0.05)
        XCTAssertEqual(w.kit(k).ints[3], 0)
        w.run(seconds: 0.1)
        XCTAssertEqual(w.kit(k).ints[3], 1, "0.1 秒後に 1 発目")
        w.run(seconds: 0.5)
        XCTAssertEqual(w.kit(k).ints[3], 3)
        XCTAssertEqual(w.kit(k).ints[4], 555)
    }

    func testHardCCInterruptsOnlyInterruptibleTimers() {
        var w = SkillWorld()
        let k = w.addKitHero()
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 1, after: 0.5)
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 2, after: 0.5, interruptible: false)
        w.tick(2)
        XCTAssertEqual(w.kit(k).reals[0], 0)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 0.3))
        w.tick()
        XCTAssertEqual(w.kit(k).reals[0], 1, "onInterrupted")
        XCTAssertEqual(w.kit(k).scheduled.map(\.code), [2])
        w.run(seconds: 1)
        XCTAssertEqual(w.kit(k).ints[4], 2, "取り消されなかった方だけ発火")
        // 取り消すものが無ければ onInterrupted も呼ばれない
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 0.3))
        w.tick(3)
        XCTAssertEqual(w.kit(k).reals[0], 1)
    }

    func testSuppressAndKnockUpAlsoInterrupt() {
        for kind in [StatusKind.suppress, .airborne] {
            var w = SkillWorld()
            let k = w.addKitHero()
            Kit.schedule(&w.s, caster: k, slot: .skill1, code: 1, after: 1)
            w.s.units[k].statuses.append(StatusEffect(kind: kind, duration: 0.3))
            w.tick()
            XCTAssertTrue(w.kit(k).scheduled.isEmpty, "\(kind)")
            XCTAssertEqual(w.kit(k).reals[0], 1, "\(kind)")
        }
    }

    func testCancelScheduledByCodeAndSlot() {
        var w = SkillWorld()
        let k = w.addKitHero()
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 1, after: 1)
        Kit.schedule(&w.s, caster: k, slot: .skill2, code: 1, after: 1)
        Kit.schedule(&w.s, caster: k, slot: .skill2, code: 2, after: 1)
        Kit.cancelScheduled(&w.s, caster: k, slot: .skill2, code: 1)
        XCTAssertEqual(w.kit(k).scheduled.map(\.code), [1, 2])
        Kit.cancelScheduled(&w.s, caster: k, code: 2)
        XCTAssertEqual(w.kit(k).scheduled.count, 1)
        Kit.cancelScheduled(&w.s, caster: k)
        XCTAssertTrue(w.kit(k).scheduled.isEmpty)
    }

    func testKitTimersCountDownToZeroAndUpdateRuns() {
        var w = SkillWorld()
        let k = w.addKitHero()
        w.s.units[k].hero!.kit!.timers[2] = 0.1
        w.tick()
        XCTAssertEqual(w.kit(k).timers[2], 0.1 - Balance.dt, accuracy: 1e-9)
        w.tick(5)
        XCTAssertEqual(w.kit(k).timers[2], 0)
        XCTAssertEqual(w.kit(k).reals[4], 6, "HeroKit.update は毎 tick 呼ばれる")
    }

    // MARK: - 経路ヒット突進

    func testSweepingDashHitsEachEnemyOnPathOnce() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let a = w.addDummyEnemy(at: skillArena + Vec2(250, 0))
        let b = w.addDummyEnemy(at: skillArena + Vec2(450, 0), hero: "H004")
        let off = w.addDummyEnemy(at: skillArena + Vec2(400, 300), hero: "H005")
        let beyond = w.addDummyEnemy(at: skillArena + Vec2(900, 0), hero: "H006")
        XCTAssertTrue(w.cast(k, .skill2, .direction(Vec2(1, 0))))
        XCTAssertNotNil(w.kit(k).sweep)
        w.run(seconds: 0.6)
        for target in [a, b] {
            let events = w.damageEvents.filter { $0.targetID == w.id(target) }
            XCTAssertEqual(events.count, 1, "経路上の敵に 1 度ずつ")
            XCTAssertGreaterThan(events[0].amount, 0)
        }
        XCTAssertEqual(w.damage(to: off), 0)
        XCTAssertEqual(w.damage(to: beyond), 0)
        XCTAssertNil(w.kit(k).sweep, "着地で外れる")
        XCTAssertEqual(w.kit(k).ints[5], 1, "着地で arriveCode の onTimer")
        XCTAssertEqual(w.s.units[k].pos.x, skillArena.x + 600, accuracy: 1)
    }

    func testSweepIsCancelledByHardCCMidDash() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let near = w.addDummyEnemy(at: skillArena + Vec2(250, 0))
        let far = w.addDummyEnemy(at: skillArena + Vec2(450, 0), hero: "H004")
        XCTAssertTrue(w.cast(k, .skill2, .direction(Vec2(1, 0))))
        w.tick(3)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        w.run(seconds: 0.6)
        XCTAssertNil(w.kit(k).sweep)
        XCTAssertEqual(w.kit(k).reals[0], 1)
        XCTAssertEqual(w.kit(k).ints[5], 0, "着地しない")
        XCTAssertEqual(w.damageEvents.filter { $0.targetID == w.id(near) }.count, 1)
        XCTAssertEqual(w.damage(to: far), 0)
        XCTAssertLessThan(w.s.units[k].pos.x, skillArena.x + 600 - 100, "突進は途中で止まる")
    }

    func testSweepOnlyDamagesEnemiesAndHeroesOnlyFilter() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let ally = w.addHero("H001", team: .blue, at: skillArena + Vec2(250, 0))
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(400, 0))
        XCTAssertTrue(w.cast(k, .skill2, .direction(Vec2(1, 0))))
        w.run(seconds: 0.6)
        XCTAssertEqual(w.damage(to: ally), 0)
        XCTAssertGreaterThan(w.damage(to: minion), 0, "ミニオンにも当たる（heroesOnly でない）")
    }

    // MARK: - 引き寄せ・押し出し・打ち上げ

    func testPullStopsAtGapAndDoesNotOvershoot() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(800, 0))
        XCTAssertTrue(Kit.pull(&w.s, w.ctx, target: e, toward: w.s.units[k].pos, distance: 2000, duration: 0.3, gap: 150))
        XCTAssertNotNil(w.s.units[e].displacement)
        XCTAssertEqual(w.s.units[e].displacement?.kind, .knockback)
        w.run(seconds: 0.6)
        XCTAssertEqual(w.s.units[e].pos.distance(to: w.s.units[k].pos), 150, accuracy: 1)
        // 短い引き寄せは距離だけ
        let e2 = w.addDummyEnemy(at: skillArena + Vec2(0, 900), hero: "H004")
        XCTAssertTrue(Kit.pull(&w.s, w.ctx, target: e2, toward: w.s.units[k].pos, distance: 200, duration: 0.2))
        w.run(seconds: 0.5)
        XCTAssertEqual(w.s.units[e2].pos.distance(to: w.s.units[k].pos), 700, accuracy: 1)
        // すでに gap 以内なら動かさない
        XCTAssertFalse(Kit.pull(&w.s, w.ctx, target: e, toward: w.s.units[k].pos, distance: 500, duration: 0.2, gap: 400))
    }

    func testPushAwayAndDisplacementImmunity() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        XCTAssertTrue(Kit.pushAway(&w.s, w.ctx, target: e, from: w.s.units[k].pos, distance: 250, duration: 0.3))
        w.run(seconds: 0.6)
        XCTAssertEqual(w.s.units[e].pos.x, skillArena.x + 550, accuracy: 1)
        // CC 無効・構造物・無敵には効かない
        let immune = w.addDummyEnemy(at: skillArena + Vec2(0, 300), hero: "H004")
        CombatSystem.addStatus(&w.s, targetIndex: immune, StatusEffect(kind: .ccImmune, duration: 5))
        XCTAssertFalse(Kit.pushAway(&w.s, w.ctx, target: immune, from: w.s.units[k].pos, distance: 400, duration: 0.3))
        let tower = w.addTower(team: .red, at: skillArena + Vec2(-400, 0))
        XCTAssertFalse(Kit.pull(&w.s, w.ctx, target: tower, toward: w.s.units[k].pos, distance: 300, duration: 0.3))
    }

    func testKnockUpAppliesAirborneAndRespectsCCImmunity() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        Kit.knockUp(&w.s, target: e, duration: 0.8, sourceID: w.id(k))
        XCTAssertTrue(w.s.units[e].has(.airborne))
        XCTAssertFalse(w.s.units[e].canAct)
        XCTAssertFalse(w.s.units[e].canMove)
        w.run(seconds: 1)
        XCTAssertFalse(w.s.units[e].has(.airborne))
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .ccImmune, duration: 5))
        Kit.knockUp(&w.s, target: e, duration: 0.8, sourceID: w.id(k))
        XCTAssertFalse(w.s.units[e].has(.airborne))
    }

    // MARK: - 扇状の弾

    func testFanSpawnsEvenAnglesInOrderWithoutRandomness() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let rngBefore = w.s.rng
        let ids = Kit.fan(&w.s, caster: k, direction: Vec2(1, 0), count: 5, halfAngle: 0.4, speed: 1000, range: 800,
                          width: 30, payload: SkillWorld.truePayload(), visual: "fan_test")
        XCTAssertEqual(ids.count, 5)
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(w.s.projectiles.count, 5)
        var angles: [Double] = []
        for p in w.s.projectiles {
            guard case .linear(let dir, let maxDistance) = p.motion else { return XCTFail("linear") }
            angles.append(dir.angle)
            XCTAssertEqual(maxDistance, 800)
            XCTAssertEqual(p.payload.originPos, w.s.units[k].pos, "距離スケーリングの起点")
            XCTAssertEqual(p.team, .blue)
        }
        for (a, e) in zip(angles, [-0.4, -0.2, 0, 0.2, 0.4]) { XCTAssertEqual(a, e, accuracy: 1e-9) }
        XCTAssertEqual(w.s.rng, rngBefore, "乱数は使わない")
        XCTAssertEqual(Kit.fan(&w.s, caster: k, direction: Vec2(0, 1), count: 1, halfAngle: 1, speed: 1000, range: 100,
                               width: 10, payload: SkillWorld.truePayload(), visual: "x").count, 1)
        guard case .linear(let single, _) = w.s.projectiles.last!.motion else { return XCTFail("linear") }
        XCTAssertEqual(single.angle, Double.pi / 2, accuracy: 1e-9, "1 発なら中心のみ")
        XCTAssertTrue(Kit.fan(&w.s, caster: k, direction: Vec2(1, 0), count: 0, halfAngle: 1, speed: 1, range: 1,
                              width: 1, payload: SkillWorld.truePayload(), visual: "x").isEmpty)
    }

    // MARK: - マーク

    func testMarksStackRefreshConsumeAndOwnerSeparation() {
        var w = SkillWorld()
        let a = w.addKitHero()
        let b = w.addKitHero(at: skillArena + Vec2(0, 400))
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        let tagA = KitTags.mark("H002", "brand", owner: w.id(a))
        let tagB = KitTags.mark("H002", "brand", owner: w.id(b))
        XCTAssertNotEqual(tagA, tagB)
        XCTAssertEqual(Kit.addMark(&w.s, target: e, ownerID: w.id(a), tag: tagA, maxStacks: 3, duration: 4), 1)
        XCTAssertEqual(Kit.addMark(&w.s, target: e, ownerID: w.id(a), tag: tagA, stacks: 1, maxStacks: 3, duration: 4), 2)
        XCTAssertEqual(Kit.addMark(&w.s, target: e, ownerID: w.id(b), tag: tagB, maxStacks: 3, duration: 4), 1)
        XCTAssertEqual(Kit.markStacks(w.s, target: e, tag: tagA), 2)
        XCTAssertEqual(Kit.markStacks(w.s, target: e, tag: tagB), 1, "所有者ごとに別")
        XCTAssertEqual(w.s.units[e].statuses.filter { $0.kind == .mark }.count, 2)
        // 上限
        XCTAssertEqual(Kit.addMark(&w.s, target: e, ownerID: w.id(a), tag: tagA, stacks: 5, maxStacks: 3, duration: 4), 3)
        // 持続は積むたびに戻る
        w.run(seconds: 3)
        XCTAssertEqual(w.s.units[e].statuses.first { $0.tag == tagA }?.remaining ?? 0, 1, accuracy: 0.1)
        Kit.addMark(&w.s, target: e, ownerID: w.id(a), tag: tagA, maxStacks: 3, duration: 4)
        w.run(seconds: 2)
        XCTAssertEqual(Kit.markStacks(w.s, target: e, tag: tagA), 3, "更新されたので残っている")
        XCTAssertEqual(Kit.markStacks(w.s, target: e, tag: tagB), 0, "更新しなかった方は切れた")
        // 消費
        XCTAssertEqual(Kit.consumeMarks(&w.s, target: e, tag: tagA), 3)
        XCTAssertEqual(Kit.markStacks(w.s, target: e, tag: tagA), 0)
        XCTAssertEqual(Kit.consumeMarks(&w.s, target: e, tag: tagA), 0)
        // 死んでいる相手には積まない
        w.s.units[e].isAlive = false
        XCTAssertEqual(Kit.addMark(&w.s, target: e, ownerID: w.id(a), tag: tagA, maxStacks: 3, duration: 4), 0)
    }

    func testMarkIsNeitherHarmfulNorBeneficialAndNotCleansable() {
        XCTAssertFalse(StatusKind.mark.combatIsHarmful)
        XCTAssertFalse(StatusKind.mark.combatIsBeneficial)
        XCTAssertFalse(StatusKind.mark.isCleansable)
        XCTAssertFalse(StatusKind.mark.preventsActions)
    }

    // MARK: - HitEffect / DamageScaling

    func testHitEffectAddMarkAndMarkScalingConsume() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        let tag = KitTags.mark("H002", "brand", owner: w.id(k))
        var stacker = SkillWorld.truePayload(10)
        stacker.effects = [.addMark(name: "brand", stacks: 1, maxStacks: 3, duration: 5)]
        for _ in 0..<4 { w.hit(k, e, stacker) }
        XCTAssertEqual(Kit.markStacks(w.s, target: e, tag: tag), 3, "上限 3")

        w.s.units[e].hp = w.s.units[e].stats.maxHP
        let base = w.hit(k, e, SkillWorld.truePayload(100))
        var scaled = SkillWorld.truePayload(100)
        scaled.scaling = .marks(name: "brand", perStack: 0.2, consume: true)
        w.s.units[e].hp = w.s.units[e].stats.maxHP
        let boosted = w.hit(k, e, scaled)
        XCTAssertEqual(boosted / base, 1.6, accuracy: 1e-9, "1 + 0.2 × 3")
        XCTAssertEqual(Kit.markStacks(w.s, target: e, tag: tag), 0, "ヒット後に消費")
        w.s.units[e].hp = w.s.units[e].stats.maxHP
        XCTAssertEqual(w.hit(k, e, scaled) / base, 1.0, accuracy: 1e-9, "マークが無ければ補正なし")
    }

    func testDamageScalingMissingHealthMaxHealthAndDistance() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        let maxHP = w.s.units[e].stats.maxHP
        func fresh() { w.s.units[e].hp = maxHP }

        fresh()
        let base = w.hit(k, e, SkillWorld.truePayload(100))

        // 失った HP: 倍率 = 1 + maxBonus × (1 − HP 割合)
        var missing = SkillWorld.truePayload(100)
        missing.scaling = .missingHealth(maxBonus: 1.0)
        fresh()
        XCTAssertEqual(w.hit(k, e, missing) / base, 1.0, accuracy: 1e-9, "満タンなら補正なし")
        w.s.units[e].hp = maxHP * 0.5
        XCTAssertEqual(w.hit(k, e, missing) / base, 1.5, accuracy: 1e-9)

        // 最大 HP の割合を加算
        var maxH = SkillWorld.truePayload(100)
        maxH.scaling = .maxHealth(ratio: 0.1)
        fresh()
        XCTAssertEqual(w.hit(k, e, maxH) / base, (100 + maxHP * 0.1) / 100, accuracy: 1e-9)

        // 距離: originPos からの距離で minMult..maxMult
        var dist = SkillWorld.truePayload(100)
        dist.scaling = .distance(near: 200, far: 800, minMult: 0.5, maxMult: 1.5)
        for (d, mult) in [(100.0, 0.5), (200.0, 0.5), (500.0, 1.0), (800.0, 1.5), (1500.0, 1.5)] {
            dist.originPos = w.s.units[e].pos - Vec2(d, 0)
            fresh()
            XCTAssertEqual(w.hit(k, e, dist) / base, mult, accuracy: 1e-9, "d=\(d)")
        }
        // originPos が無ければ所有者の位置（300）
        dist.originPos = nil
        fresh()
        XCTAssertEqual(w.hit(k, e, dist) / base, 0.5 + 1.0 * (300 - 200) / 600, accuracy: 1e-9)
        // 補正はダメージが 0 の命中には効かない
        var noDamage = missing
        noDamage.damage = 0
        w.s.units[e].hp = maxHP * 0.5
        XCTAssertEqual(w.hit(k, e, noDamage), 0)
    }

    func testHitEffectsKnockUpPullPushHealAndRefund() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(800, 0))
        // 打ち上げ
        var up = SkillWorld.truePayload(10)
        up.effects = [.knockUp(duration: 0.8)]
        w.hit(k, e, up)
        XCTAssertTrue(w.s.units[e].has(.airborne))
        w.run(seconds: 1)
        // 引き寄せ（所有者の位置へ、端同士の隙間 20）
        var pull = SkillWorld.truePayload(10)
        pull.effects = [.pullToOwner(distance: 2000, duration: 0.3, gap: 20)]
        w.hit(k, e, pull)
        w.run(seconds: 0.6)
        let touching = w.s.units[k].radius + w.s.units[e].radius
        XCTAssertEqual(w.s.units[e].pos.distance(to: w.s.units[k].pos), touching + 20, accuracy: 1)
        // 押し出し（所有者から遠ざかる）
        var push = SkillWorld.truePayload(10)
        push.effects = [.pushAway(distance: 300, duration: 0.2)]
        let before = w.s.units[e].pos.distance(to: w.s.units[k].pos)
        w.hit(k, e, push)
        w.run(seconds: 0.5)
        XCTAssertEqual(w.s.units[e].pos.distance(to: w.s.units[k].pos), before + 300, accuracy: 1)
        // 回復（flat + 与えたダメージ × ratio）とクールダウン短縮
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.5
        w.s.units[k].hero!.skillCooldowns[SkillSlot.skill2.rawValue] = 8
        var heal = SkillWorld.truePayload(100)
        heal.effects = [.healOwner(flat: 20, ratioOfDealt: 0.5), .refundCooldown(slot: .skill2, seconds: 3)]
        w.s.units[e].hp = w.s.units[e].stats.maxHP
        let hpBefore = w.s.units[k].hp
        let dealt = w.hit(k, e, heal)
        let healed = w.s.units[k].hp - hpBefore
        let power = 1 + w.s.units[k].stats.healShieldPower
        XCTAssertEqual(healed, (20 + dealt * 0.5) * power * w.s.units[k].stats.healingReceivedMultiplier, accuracy: 1e-6)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 5, accuracy: 1e-9)
    }

    func testKitEventCallsOnHitWithDealtDamage() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        var p = SkillWorld.truePayload(100)
        p.kitEvent = 7
        let dealt = w.hit(k, e, p)
        XCTAssertEqual(w.kit(k).reals[2], 7)
        XCTAssertEqual(w.kit(k).reals[1], dealt, accuracy: 1e-9)
        // kitEvent 0 は呼ばれない
        w.hit(k, e, SkillWorld.truePayload(100))
        XCTAssertEqual(w.kit(k).reals[1], dealt, accuracy: 1e-9)
    }

    // MARK: - ステルス・対象不可・suppress

    func testPersistentStealthSurvivesCastsAndAttacksButNormalStealthDoesNot() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        Kit.setPersistentStealth(&w.s, caster: k, duration: 10)
        w.s.units[k].statuses.append(StatusEffect(kind: .stealth, duration: 10, tag: "other"))
        XCTAssertEqual(w.s.units[k].statuses.filter { $0.kind == .stealth }.count, 2)
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.s.units[k].statuses.filter { $0.kind == .stealth }.map(\.tag), [KitTags.persistentStealth])
        // 通常攻撃の発射でも解除されない
        w.s.units[k].attackTargetID = w.id(e)
        w.run(seconds: 1.5)
        XCTAssertGreaterThan(w.damage(to: e, from: .basicAttack), 0)
        XCTAssertTrue(w.s.units[k].has(.stealth))
        Kit.clearPersistentStealth(&w.s, caster: k)
        XCTAssertFalse(w.s.units[k].has(.stealth))
    }

    func testUntargetableExcludedFromSingleTargetingButNotFromAreas() {
        var w = SkillWorld()
        let caster = w.addHero("H001", team: .blue, at: skillArena, facing: 0)
        let e = w.addDummyEnemy(at: skillArena + Vec2(150, 0))
        let other = w.addDummyEnemy(at: skillArena + Vec2(250, 0), hero: "H004")
        XCTAssertTrue(w.s.isTargetableEnemy(e, of: .blue))
        Kit.setUntargetable(&w.s, target: e, duration: 5)
        XCTAssertTrue(w.s.units[e].has(.untargetable))
        XCTAssertFalse(w.s.isTargetableEnemy(e, of: .blue))
        XCTAssertTrue(w.s.isTargetableEnemy(e, of: .red) == false, "自陣営の敵ではない")
        XCTAssertTrue(w.s.isTargetableEnemy(other, of: .blue))
        // 自動照準・攻撃ボタンの対象選択から外れる
        XCTAssertEqual(SkillAiming.bestEnemyHero(w.s, caster: caster, reach: 600), other)
        XCTAssertEqual(SkillAiming.nearestEnemy(w.s, caster: caster, reach: 600), other)
        XCTAssertFalse(SkillAiming.isAimable(w.s, caster: caster, e))
        XCTAssertEqual(CombatSystem.selectTarget(&w.s, w.ctx, attacker: caster, priority: .heroesFirst), other)
        XCTAssertFalse(w.s.enemies(of: .blue, near: skillArena, radius: 400).contains(e))
        // 索敵用の要約でも外れる
        let cand = WorldTargeting.candidates(w.s).first { $0.index == e }
        XCTAssertEqual(cand?.untargetable, true)
        XCTAssertEqual(cand?.isTargetableEnemy(of: .blue), false)
        // 範囲（扇）は当たる
        w.cast(caster, .skill1, .direction(Vec2(1, 0)))
        w.run(seconds: 0.5)
        XCTAssertGreaterThan(w.damage(to: e), 0, "範囲・直線には当たる")
        // 時間切れで戻る
        w.run(seconds: 5)
        XCTAssertTrue(w.s.isTargetableEnemy(e, of: .blue))
    }

    func testHomingProjectileFizzlesWhenTargetBecomesUntargetable() {
        var w = SkillWorld()
        let k = w.addHero("H003", team: .blue, at: skillArena)
        let e = w.addDummyEnemy(at: skillArena + Vec2(900, 0))
        ProjectileSystem.spawn(&w.s, ownerIndex: k, motion: .homing(targetID: w.id(e)), speed: 600,
                               payload: SkillWorld.truePayload(100), visual: "t")
        w.tick(2)
        XCTAssertFalse(w.s.projectiles[0].done)
        Kit.setUntargetable(&w.s, target: e, duration: 5)
        w.tick()
        XCTAssertTrue(w.s.projectiles[0].done)
        w.run(seconds: 2)
        XCTAssertEqual(w.damage(to: e), 0)
    }

    func testAttackTargetIsDroppedWhenTargetBecomesUntargetable() {
        var w = SkillWorld()
        let k = w.addHero("H001", team: .blue, at: skillArena)
        let e = w.addDummyEnemy(at: skillArena + Vec2(100, 0))
        w.s.units[k].attackTargetID = w.id(e)
        Kit.setUntargetable(&w.s, target: e, duration: 5)
        w.tick(2)
        XCTAssertNil(w.s.units[k].attackTargetID)
    }

    func testSuppressIgnoresCCImmunityAndIsNotCleansable() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .ccImmune, duration: 5))
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .stun, duration: 2))
        XCTAssertFalse(w.s.units[e].has(.stun), "通常の CC は CC 無効に防がれる")
        Kit.suppress(&w.s, target: e, duration: 2, sourceID: w.id(k))
        XCTAssertTrue(w.s.units[e].has(.suppress), "suppress は CC 無効を無視する")
        XCTAssertFalse(w.s.units[e].canAct)
        XCTAssertFalse(w.s.units[e].canCast)
        XCTAssertFalse(w.s.units[e].canMove)
        CombatSystem.cleanse(&w.s, targetIndex: e)
        XCTAssertTrue(w.s.units[e].has(.suppress), "解除不可")
        // 無敵・構造物には効かない
        let inv = w.addDummyEnemy(at: skillArena + Vec2(0, 300), hero: "H004")
        CombatSystem.addStatus(&w.s, targetIndex: inv, StatusEffect(kind: .invulnerable, duration: 3))
        Kit.suppress(&w.s, target: inv, duration: 2, sourceID: w.id(k))
        XCTAssertFalse(w.s.units[inv].has(.suppress))
        let tower = w.addTower(team: .red, at: skillArena + Vec2(-500, 0))
        Kit.suppress(&w.s, target: tower, duration: 2, sourceID: w.id(k))
        XCTAssertFalse(w.s.units[tower].has(.suppress))
        // 持続後に解ける
        w.run(seconds: 2.1)
        XCTAssertFalse(w.s.units[e].has(.suppress))
        XCTAssertTrue(w.s.units[e].canAct)
    }

    func testNewStatusKindsAreAppendedAndClassified() {
        // 既存の raw 値は変わらず、新しい case は末尾
        XCTAssertEqual(StatusKind.colossusBlessing.rawValue, 19)
        let added: [StatusKind] = [.mark, .lifestealBoost, .spellVampBoost, .attackRangeBoost, .armorShred,
                                   .untargetable, .suppress, .channeling]
        XCTAssertEqual(added.map(\.rawValue), Array(20...27))
        XCTAssertTrue(StatusKind.suppress.preventsMovement)
        XCTAssertTrue(StatusKind.suppress.preventsActions)
        XCTAssertTrue(StatusKind.suppress.combatIsHarmful)
        XCTAssertFalse(StatusKind.suppress.combatIsCrowdControl, "CC 無効に防がれない")
        XCTAssertFalse(StatusKind.suppress.isCleansable)
        XCTAssertTrue(StatusKind.armorShred.combatIsHarmful)
        for k in [StatusKind.lifestealBoost, .spellVampBoost, .attackRangeBoost, .untargetable, .channeling] {
            XCTAssertTrue(k.combatIsBeneficial, "\(k)")
            XCTAssertFalse(k.preventsActions, "\(k)")
        }
    }

    func testStatusModifiersApplyLifestealRangeAndArmorShred() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let base = w.s.units[k].stats
        Kit.grantLifesteal(&w.s, target: k, ratio: 0.2, duration: 5, tag: "a")
        Kit.grantSpellVamp(&w.s, target: k, ratio: 0.15, duration: 5, tag: "b")
        Kit.grantAttackRange(&w.s, target: k, amount: 120, duration: 5, tag: "c")
        StatCalculator.recompute(&w.s, k, w.ctx)
        let boosted = w.s.units[k].stats
        XCTAssertEqual(boosted.lifesteal, base.lifesteal + 0.2, accuracy: 1e-9)
        XCTAssertEqual(boosted.spellVamp, base.spellVamp + 0.15, accuracy: 1e-9)
        XCTAssertEqual(boosted.attackRange, base.attackRange + 120, accuracy: 1e-9)
        // 別の tag は加算、同じ tag は大きい方
        Kit.grantLifesteal(&w.s, target: k, ratio: 0.1, duration: 5, tag: "a2")
        StatCalculator.recompute(&w.s, k, w.ctx)
        XCTAssertEqual(w.s.units[k].stats.lifesteal, base.lifesteal + 0.3, accuracy: 1e-9)

        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        StatCalculator.recompute(&w.s, e, w.ctx)
        let armor = w.s.units[e].stats.armor
        Kit.shredArmor(&w.s, target: e, ratio: 0.3, duration: 5, sourceID: w.id(k), tag: "s1")
        Kit.shredArmor(&w.s, target: e, ratio: 0.2, duration: 5, sourceID: w.id(k), tag: "s2")
        StatCalculator.recompute(&w.s, e, w.ctx)
        XCTAssertEqual(w.s.units[e].stats.armor, armor * 0.7, accuracy: 1e-9, "大きい方のみ")
        w.run(seconds: 5.1)
        XCTAssertEqual(w.s.units[e].stats.armor, armor, accuracy: 1e-9)
    }

    func testShieldHelperUsesKitTag() {
        var w = SkillWorld()
        let k = w.addKitHero()
        Kit.shield(&w.s, w.ctx, caster: k, target: k, amount: 100, duration: 3, name: "guard")
        Kit.shield(&w.s, w.ctx, caster: k, target: k, amount: 50, duration: 3, name: "guard")
        XCTAssertEqual(w.s.units[k].shields.count, 1, "同じ tag は置き換え")
        XCTAssertEqual(w.s.units[k].shields.first?.tag, KitTags.shield("H002", "guard"))
    }

    // MARK: - パッシブの差し替え・通常攻撃の整形

    func testKitReplacesRolePassiveWhileKitlessDuelistKeepsIt() {
        var w = SkillWorld()
        let kitHero = w.addKitHero()
        let plain = w.addHero(KitTestCase.kitHero, team: .blue, at: skillArena + Vec2(0, 1000))
        w.s.units[plain].hero!.kit = nil   // 同じヒーローでもキット状態が無ければ従来のパッシブ（hot path の guard）
        let t1 = w.addDummyEnemy(at: skillArena + Vec2(200, 0), hero: "H013")
        let t2 = w.addDummyEnemy(at: skillArena + Vec2(200, 1000), hero: "H013")
        w.s.units[kitHero].attackTargetID = w.id(t1)
        w.s.units[plain].attackTargetID = w.id(t2)
        w.run(seconds: 1.5)
        XCTAssertGreaterThan(w.s.units[plain].hero!.passive.stacks, 0, "キットなしはデュエリストの攻撃速度スタック")
        XCTAssertGreaterThan(w.kit(kitHero).reals[3], 0, "キットの onBasicAttackHit が呼ばれる")
        XCTAssertEqual(w.s.units[kitHero].hero!.passive.stacks, 0, "ロールのパッシブは置き換わる")
        XCTAssertFalse(w.s.units[kitHero].statuses.contains { $0.tag == Balance.Skills.duelistPassiveTag })
        XCTAssertTrue(w.s.units[plain].statuses.contains { $0.tag == Balance.Skills.duelistPassiveTag })
    }

    func testKitPassiveHooksDispatch() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        let attackerBase = w.hit(k, e, SkillWorld.truePayload(100))
        // 与ダメ補正
        w.s.units[k].hero!.kit!.form = 1
        w.s.units[e].hp = w.s.units[e].stats.maxHP
        XCTAssertEqual(w.hit(k, e, SkillWorld.truePayload(100)) / attackerBase, 1.5, accuracy: 1e-9)
        XCTAssertGreaterThan(w.kit(k).reals[5], 0, "onSkillHit")
        // 被ダメ補正（防御・軽減の後）と onDamageTaken
        w.s.units[k].hero!.kit!.form = 0
        w.s.units[e].hero!.kit = KitState()
        w.s.units[e].hero!.kit!.form = 2
        // e のヒーローには TestKit が無いので dispatch されない（kit の有無はヒーロー ID で決まる）
        XCTAssertNil(HeroKits.kit(of: w.s.units[e]))
        w.s.units[e].hero!.kit = nil
        let victim = w.addKitHero(team: .red, at: skillArena + Vec2(0, 700))
        let fullHP = w.s.units[victim].stats.maxHP
        w.s.units[victim].hp = fullHP
        let normal = w.hit(k, victim, SkillWorld.truePayload(100))
        w.s.units[victim].hp = fullHP
        w.s.units[victim].hero!.kit!.form = 2
        let halved = w.hit(k, victim, SkillWorld.truePayload(100))
        XCTAssertEqual(halved / normal, 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan(w.kit(victim).reals[6], 0, "onDamageTaken")
        // 発動の完了
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(w.kit(k).reals[7], 1, "onSkillCast")
    }

    func testShapeBasicAttackAddsExtraHit() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(150, 0), hero: "H013")
        w.s.units[k].attackTargetID = w.id(e)
        w.run(seconds: 1)
        let plain = w.damageEvents.filter { $0.targetID == w.id(e) && $0.source == .basicAttack }
        XCTAssertFalse(plain.isEmpty)
        XCTAssertTrue(plain.allSatisfy { $0.damageType == .physical })

        var w2 = SkillWorld()
        let k2 = w2.addKitHero()
        w2.s.units[k2].hero!.kit!.form = 3
        let e2 = w2.addDummyEnemy(at: skillArena + Vec2(150, 0), hero: "H013")
        w2.s.units[k2].attackTargetID = w2.id(e2)
        w2.run(seconds: 1)
        let extra = w2.damageEvents.filter { $0.targetID == w2.id(e2) && $0.damageType == .trueDamage }
        XCTAssertFalse(extra.isEmpty, "追加ヒット")
        XCTAssertEqual(extra.count, w2.damageEvents.filter { $0.targetID == w2.id(e2) && $0.damageType == .physical }.count)
    }

    func testBotCastHookOnlyForKitHeroes() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let plain = w.addHero("H001", team: .blue, at: skillArena + Vec2(0, 500))
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        let t = SkillTargeting(archetype: .cone, aim: .direction, range: 400, radius: 400)
        func name(_ d: BotKitDecision) -> String {
            switch d {
            case .useDefault: return "default"
            case .cast: return "cast"
            case .castNow: return "castNow"
            case .skip: return "skip"
            }
        }
        XCTAssertEqual(name(HeroKits.botCast(w.s, w.ctx, bot: k, slot: .skill1, targeting: t, target: e, fighting: true)), "skip")
        XCTAssertEqual(name(HeroKits.botCast(w.s, w.ctx, bot: k, slot: .ultimate, targeting: t, target: e, fighting: true)), "cast")
        XCTAssertEqual(name(HeroKits.botCast(w.s, w.ctx, bot: k, slot: .skill2, targeting: t, target: e, fighting: true)), "default")
        XCTAssertEqual(name(HeroKits.botCast(w.s, w.ctx, bot: plain, slot: .skill1, targeting: t, target: e, fighting: true)), "default")
    }

    // MARK: - ゾーンの追従

    func testZoneFollowsTargetAndEndsWhenTargetDies() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        let zoneID = ZoneSystem.spawn(&w.s, ownerIndex: k, center: w.s.units[e].pos, radius: 80, delay: 1.0,
                                      followsTargetID: w.id(e), payload: SkillWorld.truePayload(30), visual: "z")
        w.s.units[e].pos = skillArena + Vec2(400, 600)
        w.tick()
        XCTAssertEqual(w.s.zones.first { $0.id == zoneID }?.center, w.s.units[e].pos)
        w.s.units[e].pos = skillArena + Vec2(800, 100)
        w.run(seconds: 1.1)
        XCTAssertGreaterThan(w.damage(to: e), 0, "追従した先で発動する")

        // 対象が死ぬとゾーンは終わる
        let e2 = w.addDummyEnemy(at: skillArena + Vec2(0, 600), hero: "H004")
        let z2 = ZoneSystem.spawn(&w.s, ownerIndex: k, center: w.s.units[e2].pos, radius: 80, delay: 1.0,
                                  followsTargetID: w.id(e2), payload: SkillWorld.truePayload(30), visual: "z")
        w.s.units[e2].isAlive = false
        w.tick()
        XCTAssertEqual(w.s.zones.first { $0.id == z2 }?.done, true)
        XCTAssertEqual(w.damage(to: e2), 0)
    }

    // MARK: - 死亡

    func testDeathResetsKitStateExceptWhatOnDeathKeeps() {
        var w = SkillWorld()
        let k = w.addKitHero()
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        w.s.units[k].hero!.kit!.ints[3] = 9
        w.s.units[k].hero!.kit!.form = 2
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 1, after: 5)
        KitRuntime.heroDied(&w.s, w.ctx, hero: k)
        let kit = w.kit(k)
        XCTAssertEqual(kit.ints[0], 1, "onDeath が残したもの")
        XCTAssertEqual(kit.ints[3], 0)
        XCTAssertEqual(kit.form, 0)
        XCTAssertTrue(kit.scheduled.isEmpty)
        XCTAssertFalse(kit.windows[SkillSlot.skill1.rawValue].isOpen)
        XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill1))
    }

    func testRealDeathThroughDeathSystemResetsKit() {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 1, after: 5)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        XCTAssertTrue(w.kit(k).scheduled.isEmpty)
        XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: .skill1))
        // 死亡中は更新しない（タイマーが積まれても発火しない）
        w.run(seconds: 1)
        XCTAssertEqual(w.kit(k).ints[3], 0)
    }

    // MARK: - 決定性・ハッシュ

    /// 再使用・突進・連撃・マーク・通常攻撃を混ぜた台本。
    private func script(_ w: inout SkillWorld, k: Int, e1: Int, e2: Int, step: Int) {
        switch step {
        case 0: w.cast(k, .skill1, .direction(Vec2(1, 0)))
        case 1: w.cast(k, .skill1, .point(w.s.units[e1].pos))
        case 2: w.cast(k, .skill2, .direction(Vec2(1, 0)))
        case 3:
            w.cast(k, .ultimate)
            var p = SkillWorld.truePayload(40)
            p.effects = [.addMark(name: "brand", stacks: 1, maxStacks: 4, duration: 6)]
            p.scaling = .missingHealth(maxBonus: 0.5)
            w.hit(k, e2, p)
        case 4: w.s.units[k].attackTargetID = w.id(e1)
        default: break
        }
    }

    private func runScript(_ w: inout SkillWorld, k: Int, e1: Int, e2: Int, from: Int, to: Int) {
        for step in from..<to {
            script(&w, k: k, e1: e1, e2: e2, step: step)
            w.run(seconds: 0.4)
        }
    }

    private func makeScriptWorld() -> (SkillWorld, Int, Int, Int) {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e1 = w.addDummyEnemy(at: skillArena + Vec2(350, 0))
        let e2 = w.addDummyEnemy(at: skillArena + Vec2(300, 200), hero: "H004")
        return (w, k, e1, e2)
    }

    func testScriptedRunIsDeterministic() {
        var (a, ka, a1, a2) = makeScriptWorld()
        var (b, kb, b1, b2) = makeScriptWorld()
        runScript(&a, k: ka, e1: a1, e2: a2, from: 0, to: 8)
        runScript(&b, k: kb, e1: b1, e2: b2, from: 0, to: 8)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(a.s.units, b.s.units)
        XCTAssertEqual(a.log, b.log)
        XCTAssertGreaterThan(a.kit(ka).ints[0] + a.kit(ka).ints[1] + a.kit(ka).ints[3], 3, "台本が実際にキットを動かしている")
    }

    func testJSONRoundTripMidWindowResumesIdentically() throws {
        var (a, ka, a1, a2) = makeScriptWorld()
        runScript(&a, k: ka, e1: a1, e2: a2, from: 0, to: 8)

        var (b, kb, b1, b2) = makeScriptWorld()
        runScript(&b, k: kb, e1: b1, e2: b2, from: 0, to: 2)   // 再使用の窓・タイマーが生きている途中
        XCTAssertTrue(b.kit(kb).windows.contains { $0.isOpen } || !b.kit(kb).scheduled.isEmpty || b.kit(kb).sweep != nil)
        let data = try JSONEncoder().encode(b.s)
        var resumed = b
        resumed.s = try JSONDecoder().decode(SimState.self, from: data)
        XCTAssertEqual(resumed.s.units, b.s.units, "往復で状態が変わらない")
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        runScript(&resumed, k: kb, e1: b1, e2: b2, from: 2, to: 8)

        XCTAssertEqual(resumed.s.stateHash(), a.s.stateHash())
        XCTAssertEqual(resumed.s.units, a.s.units)
        XCTAssertEqual(resumed.s.zones, a.s.zones)
        XCTAssertEqual(resumed.s.projectiles, a.s.projectiles)
    }

    func testKitMidSweepSurvivesJSONRoundTrip() throws {
        var w = SkillWorld()
        let k = w.addKitHero()
        let e = w.addDummyEnemy(at: skillArena + Vec2(450, 0))
        XCTAssertTrue(w.cast(k, .skill2, .direction(Vec2(1, 0))))
        w.tick(3)
        XCTAssertNotNil(w.kit(k).sweep)
        var copy = w
        copy.s = try JSONDecoder().decode(SimState.self, from: JSONEncoder().encode(w.s))
        w.run(seconds: 0.6)
        copy.run(seconds: 0.6)
        XCTAssertEqual(w.s.units, copy.s.units)
        XCTAssertEqual(w.damageEvents.filter { $0.targetID == w.id(e) }.count, 1)
        XCTAssertEqual(copy.damageEvents.filter { $0.targetID == copy.id(e) }.count, 1)
        XCTAssertEqual(copy.kit(k).ints[5], 1)
    }

    func testStateHashMixesKitRegistersWindowsAndKitStatuses() {
        var (a, ka, _, _) = makeScriptWorld()
        var (b, kb, _, _) = makeScriptWorld()
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        b.s.units[kb].hero!.kit!.ints[3] = 1
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash(), "レジスタ")
        b.s.units[kb].hero!.kit!.ints[3] = 0
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        b.s.units[kb].hero!.kit!.form = 1
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash(), "形態")
        b.s.units[kb].hero!.kit!.form = 0
        Kit.openRecast(&b.s, caster: kb, slot: .skill1, duration: 3)
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash(), "窓の段")
        Kit.openRecast(&a.s, caster: ka, slot: .skill1, duration: 3)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        Kit.schedule(&b.s, caster: kb, slot: .skill1, code: 1, after: 1)
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash(), "予約数")
        Kit.cancelScheduled(&b.s, caster: kb)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        // 敵側のマーク（status の kind / tag / magnitude）
        let e = b.s.units.firstIndex { $0.team == .red }!
        let tag = KitTags.mark("H002", "brand", owner: b.id(kb))
        Kit.addMark(&b.s, target: e, ownerID: b.id(kb), tag: tag, maxStacks: 3, duration: 5)
        let h1 = b.s.stateHash()
        XCTAssertNotEqual(a.s.stateHash(), h1)
        Kit.addMark(&b.s, target: e, ownerID: b.id(kb), tag: tag, maxStacks: 3, duration: 5)
        XCTAssertNotEqual(b.s.stateHash(), h1, "スタック数")
    }

    // MARK: - キットなしのヒーローは不変（hot path）

    /// キットなしの 3 体（H001 / H003 / H005 vs 敵 H004）で全スキルと通常攻撃を回す。
    /// nilKits = true なら、makeHero が付けた KitState（差し込み中のみ）を外して「キット無し」にする。
    private func kitlessBrawl(nilKits: Bool = false) -> SkillWorld {
        var w = SkillWorld()
        let a = w.addHero("H001", team: .blue, at: skillArena, facing: 0)
        let b = w.addHero("H003", team: .blue, at: skillArena + Vec2(-300, 200), facing: 0)
        let c = w.addHero("H005", team: .blue, at: skillArena + Vec2(-300, -200), facing: 0)
        let e = w.addHero("H004", team: .red, at: skillArena + Vec2(500, 0), facing: Double.pi)
        if nilKits { for i in [a, b, c, e] { w.s.units[i].hero!.kit = nil } }
        w.addMinion(team: .red, at: skillArena + Vec2(450, 80))
        w.s.units[a].attackTargetID = w.id(e)
        for (round, slot) in [SkillSlot.skill1, .skill2, .ultimate, .skill1, .skill2].enumerated() {
            for h in [a, b, c] { w.cast(h, slot, .point(w.s.units[e].pos)) }
            w.s.units[b].attackTargetID = w.id(e)
            w.run(seconds: 1.2 + Double(round) * 0.1)
        }
        return w
    }

    func testKitlessBrawlIsDeterministicAndHasNoKitState() {
        HeroKits.testOverride = []
        let a = kitlessBrawl()
        let b = kitlessBrawl()
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(a.s.units, b.s.units)
        XCTAssertEqual(a.log, b.log)
        XCTAssertTrue(a.s.units.allSatisfy { $0.hero?.kit == nil })
        XCTAssertFalse(a.damageEvents.isEmpty, "戦闘が実際に起きている")
        XCTAssertTrue(a.damageEvents.contains { $0.source.isSkill })
    }

    /// 同じ ID のキットがレジストリに差してあっても、hero.kit が nil のユニットはレジストリを引かず従来どおり動く。
    func testUnitsWithoutKitStateIgnoreRegistryEntriesForTheirHeroID() {
        HeroKits.testOverride = []
        let baseline = kitlessBrawl()
        HeroKits.testOverride = [TestKit(heroID: "H001"), TestKit(heroID: "H003"), TestKit(heroID: "H005"),
                                 TestKit(heroID: "H004")]
        let viaRegistry = kitlessBrawl(nilKits: true)
        XCTAssertTrue(viaRegistry.s.units.allSatisfy { HeroKits.kit(of: $0) == nil })
        HeroKits.testOverride = []
        XCTAssertEqual(baseline.s.stateHash(), viaRegistry.s.stateHash())
        XCTAssertEqual(baseline.s.units, viaRegistry.s.units)
        XCTAssertEqual(baseline.log, viaRegistry.log)
    }

    func testRealMatchHasNoKitStateAndStaysDeterministic() {
        HeroKits.testOverride = []
        func run() -> Simulation {
            let sim = Simulation(config: MatchFactory.botMatch(seed: 99))
            var events: [SimEvent] = []
            SkillDeterminismTests.run(sim, until: 30, events: &events)
            return sim
        }
        let a = run()
        let b = run()
        XCTAssertEqual(a.state.stateHash(), b.state.stateHash())
        XCTAssertEqual(a.state.units, b.state.units)
        // 有効なキットのヒーロー（Kit_H0xxTests が検査する）だけに KitState が付く
        XCTAssertTrue(a.state.units.allSatisfy { ($0.hero?.kit != nil) == HeroKits.hasKit($0.hero?.heroID ?? "") })
        XCTAssertGreaterThan(a.state.tick, 0)
    }
}
