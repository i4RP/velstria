import XCTest
@testable import VELSTRIA
import VelstriaCore

// 担当: ui-collection。コレクション画面の表示用計算（DESIGN §4・§6・§7・§8）の検証。

final class CollectionLogicTests: XCTestCase {
    let master = MasterData.shared

    override func setUp() {
        super.setUp()
        Loc.current = .ja
    }

    // MARK: スキル

    func testSkillDamageScalesThirtyPercentPerRank() {
        XCTAssertEqual(SkillMath.damage(base: 100, rank: 1), 100, accuracy: 1e-9)
        XCTAssertEqual(SkillMath.damage(base: 100, rank: 2), 130, accuracy: 1e-9)
        XCTAssertEqual(SkillMath.damage(base: 100, rank: 4), 190, accuracy: 1e-9)
    }

    func testSkillCooldownDropsSixPercentPerRank() throws {
        let skill = try XCTUnwrap(master.skill("SK001_2"))
        XCTAssertEqual(SkillMath.cooldown(skill, rank: 1), skill.cooldownSec, accuracy: 1e-9)
        XCTAssertEqual(SkillMath.cooldown(skill, rank: 3), skill.cooldownSec * 0.88, accuracy: 1e-9)
    }

    func testEnergyHeroesPaySixtyPercentCost() throws {
        let skill = try XCTUnwrap(master.skill(hero: "H002", slot: .skill1))
        XCTAssertEqual(master.hero("H002")?.resource, .energy)
        XCTAssertEqual(SkillMath.cost(skill, resource: .energy), skill.cost * 0.6, accuracy: 1e-9)
        XCTAssertEqual(SkillMath.cost(skill, resource: .mana), skill.cost, accuracy: 1e-9)
    }

    func testRankListsPerSlot() {
        XCTAssertEqual(SkillMath.ranks(for: .passive), [])
        XCTAssertEqual(SkillMath.ranks(for: .skill2), [1, 2, 3, 4])
        XCTAssertEqual(SkillMath.ranks(for: .ultimate), [1, 2, 3])
    }

    func testEffectiveAttackScalingAppliesGlobalFactor() throws {
        let skill = try XCTUnwrap(master.skill("SK001_2"))
        XCTAssertEqual(SkillMath.effectiveAttackScaling(skill), skill.scalingAttack * 0.6, accuracy: 1e-9)
    }

    func testPassiveCoefficientAndText() throws {
        XCTAssertEqual(SkillMath.passiveCoefficient(heroNumber: 5), 1.0, accuracy: 1e-9)
        XCTAssertEqual(SkillMath.passiveCoefficient(heroNumber: 7), 1.04, accuracy: 1e-9)
        // H007 ガルク（Vanguard）: 15% × 1.04 = 15.6%
        let garruk = try XCTUnwrap(master.hero("H007"))
        XCTAssertTrue(SkillMath.passiveText(role: garruk.role, heroNumber: garruk.number).contains("15.6"))
        for role in Role.allCases {
            XCTAssertFalse(SkillMath.passiveText(role: role, heroNumber: 1).isEmpty)
        }
    }

    func testCrowdControlDetailsUseBalanceValues() {
        XCTAssertTrue(SkillMath.ccDetail(.slow, isUltimate: false).contains("30%"))
        XCTAssertTrue(SkillMath.ccDetail(.slow, isUltimate: true).contains("45%"))
        XCTAssertTrue(SkillMath.ccDetail(.stun, isUltimate: true).contains("1.25"))
        XCTAssertTrue(SkillMath.ccDetail(.root, isUltimate: false).contains("1"))
        XCTAssertTrue(SkillMath.ccDetail(.knockback, isUltimate: false).contains("250"))
    }

    func testEveryArchetypeHasNameAndDescription() {
        let all: [SkillArchetype] = [.passive, .cone, .lineSkillshot, .piercingLine, .dashStrike, .blinkEmpower, .groundAoE,
                                     .selfAoE, .healZone, .leapSlam, .multiStrike, .teamHeal, .targetedBlink]
        for a in all {
            XCTAssertFalse(CollectionStyle.archetypeName(a).isEmpty)
            XCTAssertFalse(CollectionStyle.archetypeDescription(a).isEmpty)
        }
    }

    // MARK: 能力値

    func testStatBarsNormalizeAgainstMaxLevelMaximum() {
        for kind in HeroStatKind.allCases {
            let maxValue = HeroStatMath.maxValue(kind, master: master)
            for hero in master.heroes {
                let v = kind.value(HeroGrowth.baseStats(def: hero, level: Balance.maxLevel))
                XCTAssertLessThanOrEqual(v, maxValue + 1e-9, "\(kind) \(hero.heroID)")
            }
        }
        let alden = master.hero("H001")!
        XCTAssertEqual(HeroStatKind.hp.growth(alden), alden.hpGrowth)
        XCTAssertNil(HeroStatKind.moveSpeed.growth(alden))
    }

    // MARK: 装備

    func testCombineCostUsesThirtyPercentFloor() throws {
        // EQ019: 993 − (411 + 453) = 129 < 993 × 0.3 → 298
        let eq019 = try XCTUnwrap(master.item("EQ019"))
        XCTAssertEqual(ItemMath.combineCost(eq019, master: master), 298)
        // EQ061: 1277 − (315 + 453) = 509
        let eq061 = try XCTUnwrap(master.item("EQ061"))
        XCTAssertEqual(ItemMath.combineCost(eq061, master: master), 509)
        // 素材なしは価格そのまま
        let eq001 = try XCTUnwrap(master.item("EQ001"))
        XCTAssertEqual(ItemMath.combineCost(eq001, master: master), eq001.priceGold)
    }

    func testBuildsIntoListsParentsInIDOrder() {
        let parents = ItemMath.buildsInto("EQ009", master: master)
        XCTAssertFalse(parents.isEmpty)
        XCTAssertTrue(parents.allSatisfy { $0.buildFrom.contains("EQ009") })
        XCTAssertEqual(parents.map(\.itemID), parents.map(\.itemID).sorted())
        XCTAssertTrue(ItemMath.buildsInto("EQ061", master: master).isEmpty)
    }

    func testDuplicateComponentsAreKept() throws {
        let eq031 = try XCTUnwrap(master.item("EQ031"))
        XCTAssertEqual(ItemMath.components(eq031, master: master).map(\.itemID), ["EQ009", "EQ009"])
    }

    func testPassiveEffectTextPerCategory() throws {
        // Defense は X/2、Jungle は 3X
        let defense = try XCTUnwrap(master.item("EQ003"))
        XCTAssertEqual(defense.passivePercent, 8)
        XCTAssertTrue(ItemMath.passiveEffectText(defense).contains("4%"))
        let jungle = try XCTUnwrap(master.item("EQ006"))
        XCTAssertEqual(jungle.passivePercent, 11)
        XCTAssertTrue(ItemMath.passiveEffectText(jungle).contains("33%"))
        XCTAssertTrue(ItemMath.passiveEffectText(jungle).contains("20%"))
        for item in master.items {
            XCTAssertFalse(ItemMath.passiveEffectText(item).isEmpty)
        }
    }

    func testStatLinesSkipZeroValues() throws {
        let eq003 = try XCTUnwrap(master.item("EQ003"))
        XCTAssertEqual(ItemMath.statLines(eq003).count, 3)
        let eq006 = try XCTUnwrap(master.item("EQ006"))
        XCTAssertTrue(ItemMath.statLines(eq006).isEmpty)
    }

    func testItemFilter() {
        XCTAssertEqual(ItemMath.filtered(master.items, category: nil, tier: nil).count, 72)
        let attackT3 = ItemMath.filtered(master.items, category: .attack, tier: 3)
        XCTAssertFalse(attackT3.isEmpty)
        XCTAssertTrue(attackT3.allSatisfy { $0.category == .attack && $0.tier == 3 })
    }

    // MARK: ビルド

    func testBuildRulesEnforceLimits() {
        // EQ004 / EQ010 = Movement, EQ006 / EQ012 = Jungle
        XCTAssertEqual(BuildRules.check("EQ010", adding: ["EQ004"], replacing: nil, master: master), .movementLimit)
        XCTAssertEqual(BuildRules.check("EQ012", adding: ["EQ006"], replacing: nil, master: master), .jungleLimit)
        XCTAssertEqual(BuildRules.check("EQ001", adding: ["EQ001"], replacing: nil, master: master), .duplicate)
        XCTAssertEqual(BuildRules.check("EQ999", adding: [], replacing: nil, master: master), .unknown)
        let full = ["EQ001", "EQ002", "EQ003", "EQ005", "EQ007", "EQ008"]
        XCTAssertEqual(BuildRules.check("EQ009", adding: full, replacing: nil, master: master), .full)
        // 置換なら満杯でも可、同じ移動系の差し替えも可
        XCTAssertEqual(BuildRules.check("EQ009", adding: full, replacing: 0, master: master), .ok)
        XCTAssertEqual(BuildRules.check("EQ010", adding: ["EQ004"], replacing: 0, master: master), .ok)
    }

    func testSanitizedBuildDropsInvalidEntries() {
        let raw = ["EQ004", "EQ010", "BAD", "EQ001", "EQ001", "EQ006", "EQ012", "EQ002", "EQ003", "EQ005", "EQ007"]
        XCTAssertEqual(BuildRules.sanitized(raw, master: master), ["EQ004", "EQ001", "EQ006", "EQ002", "EQ003", "EQ005"])
    }

    func testBuildMoveSwapsNeighbours() {
        XCTAssertEqual(BuildRules.move(["A", "B", "C"], from: 1, by: -1), ["B", "A", "C"])
        XCTAssertEqual(BuildRules.move(["A", "B", "C"], from: 2, by: 1), ["A", "B", "C"])
    }

    func testCurrentBuildPrefersCustom() {
        var p = Profile()
        p.customBuilds["H003"] = ["EQ061", "EQ043"]
        XCTAssertEqual(BuildRules.current(for: "H003", profile: p, master: master), ["EQ061", "EQ043"])
        XCTAssertEqual(BuildRules.current(for: "H001", profile: p, master: master),
                       BuildRules.recommended(for: "H001", master: master))
        XCTAssertEqual(BuildRules.totalCost(["EQ061", "EQ043"], master: master), 1277 + 1331)
    }

    // MARK: ルーン

    func testDefaultRunePageSelectsOneRunePerTierFromPath() {
        for path in RunePath.allCases {
            let page = RuneMath.defaultPage(name: "P", path: path, master: master)
            XCTAssertEqual(page.runeIDs.count, 3)
            for (i, id) in page.runeIDs.enumerated() {
                let rune = master.rune(id)
                XCTAssertEqual(rune?.path, path)
                XCTAssertEqual(rune?.tier, i + 1)
            }
        }
    }

    func testNormalizedRunePageRepairsMismatches() {
        let page = RunePage(name: "   とても長いルーンページの名前ですよ   ", primaryPath: .arcana, runeIDs: ["RN01", "RN12"])
        let fixed = RuneMath.normalized(page, master: master)
        XCTAssertEqual(fixed.runeIDs, ["RN02", "RN12", "RN22"])
        XCTAssertLessThanOrEqual(fixed.name.count, RuneMath.maxNameLength)
        XCTAssertFalse(fixed.name.hasPrefix(" "))
        let switched = RuneMath.changingPath(fixed, to: .harmony, master: master)
        XCTAssertEqual(switched.primaryPath, .harmony)
        XCTAssertTrue(switched.runeIDs.allSatisfy { master.rune($0)?.path == .harmony })
    }

    func testRuneBonusFollowsPathRules() {
        // Valor: RN01 3% + RN11 6% + RN21 2% = 攻撃力 +11%
        let valor = RunePage(name: "V", primaryPath: .valor, runeIDs: ["RN01", "RN11", "RN21"])
        XCTAssertEqual(RuneMath.bonus(for: valor, master: master).attackPct, 11, accuracy: 1e-9)
        // Arcana: 魔力 +X、スキルダメ +X/2
        let arcana = RuneMath.bonus(path: .arcana, percent: 8)
        XCTAssertEqual(arcana.abilityPowerPct, 8)
        XCTAssertEqual(arcana.skillDamagePct, 4)
        // Resolve: HP と防御 +X
        let resolve = RuneMath.bonus(path: .resolve, percent: 5)
        XCTAssertEqual(resolve.maxHPPct, 5)
        XCTAssertEqual(resolve.defensesPct, 5)
        // Cunning: 移動 X/2・CD X/2
        let cunning = RuneMath.bonus(path: .cunning, percent: 6)
        XCTAssertEqual(cunning.moveSpeedPct, 3)
        XCTAssertEqual(cunning.cooldownReductionPct, 3)
        // Harmony: 回復 3X・回復量 X
        let harmony = RuneMath.bonus(path: .harmony, percent: 4)
        XCTAssertEqual(harmony.regenPct, 12)
        XCTAssertEqual(harmony.healingPct, 4)
        XCTAssertEqual(harmony.lines.count, 2)
    }

    // MARK: スペル

    func testSpellInfoCoversAllMasterSpells() {
        XCTAssertEqual(SpellInfo.all.count, master.spells.count)
        for spell in master.spells {
            let info = SpellInfo.of(spell.spellID)
            XCTAssertEqual(info.id, spell.spellID)
            XCTAssertFalse(info.effectJa.isEmpty)
            XCTAssertFalse(info.effectEn.isEmpty)
        }
        XCTAssertNotNil(SpellInfo.of("BS05").tip)
    }

    func testSpellAssignmentSwapsDuplicates() {
        XCTAssertEqual(SpellLoadoutRules.assigning("BS03", slot: 0, in: ["BS01", "BS03"]), ["BS03", "BS01"])
        XCTAssertEqual(SpellLoadoutRules.assigning("BS07", slot: 1, in: ["BS01", "BS03"]), ["BS01", "BS07"])
        XCTAssertEqual(SpellLoadoutRules.normalized(["BS03", "BS03"]), ["BS03", "BS01"])
        XCTAssertEqual(SpellLoadoutRules.normalized([]), ["BS01", "BS03"])
    }

    func testEffectiveSpellsUseHeroOverride() {
        var p = Profile()
        p.defaultSpells = ["BS02", "BS04"]
        p.heroSpells["H006"] = ["BS05", "BS01"]
        XCTAssertEqual(SpellLoadoutRules.effective(heroID: nil, profile: p), ["BS02", "BS04"])
        XCTAssertEqual(SpellLoadoutRules.effective(heroID: "H001", profile: p), ["BS02", "BS04"])
        XCTAssertEqual(SpellLoadoutRules.effective(heroID: "H006", profile: p), ["BS05", "BS01"])
    }

    // MARK: エモート

    func testEmoteSlotsAreAlwaysFour() {
        XCTAssertEqual(EmoteSlots.normalized([]), ["", "", "", ""])
        XCTAssertEqual(EmoteSlots.normalized(["A", "B", "C", "D", "E"]), ["A", "B", "C", "D"])
        XCTAssertEqual(EmoteSlots.assigning("A", slot: 2, in: []), ["", "", "A", ""])
        XCTAssertEqual(EmoteSlots.assigning("A", slot: 0, in: ["B", "", "A", ""]), ["A", "", "B", ""])
        XCTAssertEqual(EmoteSlots.clearing(slot: 0, in: ["A", "B"]), ["", "B", "", ""])
        XCTAssertEqual(EmoteSlots.pruned(["A", "X"], owned: ["A"]), ["A", "", "", ""])
    }

    // MARK: ヒーロー一覧

    func testHeroListFilter() {
        let owned = ["H001", "H002", "H007"]
        XCTAssertEqual(HeroListFilter.heroes(master.heroes, role: nil, ownership: .all, owned: owned).count, 24)
        XCTAssertEqual(HeroListFilter.heroes(master.heroes, role: nil, ownership: .owned, owned: owned).map(\.heroID), owned)
        XCTAssertEqual(HeroListFilter.heroes(master.heroes, role: .vanguard, ownership: .owned, owned: owned).map(\.heroID),
                       ["H001", "H007"])
        XCTAssertEqual(HeroListFilter.heroes(master.heroes, role: .vanguard, ownership: .locked, owned: owned).map(\.heroID),
                       ["H013", "H019"])
    }

    func testEnglishStringsSwitchWithLanguage() {
        Loc.current = .en
        defer { Loc.current = .ja }
        XCTAssertEqual(CollectionStyle.categoryName(.jungle), "Jungle")
        XCTAssertTrue(ItemMath.passiveEffectText(master.item("EQ001")!).hasPrefix("Basic attack"))
        XCTAssertTrue(SpellInfo.of("BS01").effect.hasPrefix("Teleport"))
    }
}
