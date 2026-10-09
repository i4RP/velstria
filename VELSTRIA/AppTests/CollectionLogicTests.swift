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
        let scale = Balance.Skills.cooldownScale
        XCTAssertEqual(SkillMath.cooldown(skill, rank: 1), skill.cooldownSec * scale, accuracy: 1e-9)
        XCTAssertEqual(SkillMath.cooldown(skill, rank: 3), skill.cooldownSec * 0.88 * scale, accuracy: 1e-9)
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

    // スキル詳細の数値はシミュレーション（SkillCatalog.numbers）と一致すること。

    func testSkillNumbersIncludeSlotMultiplier() throws {
        let skill = try XCTUnwrap(master.skill("SK001_2"))
        let hero = try XCTUnwrap(master.hero(skill.heroID))
        let scale = Balance.Skills.damageScale(.skill1)
        XCTAssertEqual(SkillMath.numbers(skill, hero: hero, rank: 1).damage, skill.baseDamage * scale, accuracy: 1e-9)
        XCTAssertEqual(SkillMath.numbers(skill, hero: hero, rank: 4).damage, skill.baseDamage * 1.9 * scale, accuracy: 1e-9)
        // 係数もスロット倍率込み（攻撃力は 0.6 の共通補正も掛かる）
        let s = SkillMath.scaling(skill, hero: hero)
        XCTAssertEqual(s.damage.attack, skill.scalingAttack * Balance.skillAttackScalingFactor * scale, accuracy: 1e-9)
        XCTAssertEqual(s.damage.power, skill.scalingPower * scale, accuracy: 1e-9)
    }

    func testSkillNumbersMatchSimulationForEverySkill() throws {
        var stats = Stats()
        stats.attack = 150
        stats.abilityPower = 80
        for skill in master.skills where skill.slot != .passive {
            let hero = try XCTUnwrap(master.hero(skill.heroID))
            let sim = SkillCatalog.numbers(for: skill, hero: hero, rank: 2, stats: stats)
            let base = SkillMath.numbers(skill, hero: hero, rank: 2)
            let s = SkillMath.scaling(skill, hero: hero)
            // 表の基礎値 + 表示係数 × 能力値 = シミュレーションの値
            XCTAssertEqual(base.damage + s.damage.attack * 150 + s.damage.power * 80, sim.damage, accuracy: 1e-6, skill.skillID)
            XCTAssertEqual(base.heal + s.heal.attack * 150 + s.heal.power * 80, sim.heal, accuracy: 1e-6, skill.skillID)
            XCTAssertEqual(base.hits, sim.hits, skill.skillID)
        }
    }

    func testSupportSkillsShowHealInsteadOfRawDamage() throws {
        // SK005_5 ヴォスの Ult（味方全体回復）: ダメージ 0、回復 = 基礎 × 2.4 × 1.2
        let ult = try XCTUnwrap(master.skill("SK005_5"))
        let voss = try XCTUnwrap(master.hero(ult.heroID))
        let t = SkillCatalog.targeting(for: ult, hero: voss)
        XCTAssertEqual(t.archetype, .teamHeal)
        XCTAssertEqual(SkillMath.figures(t.archetype), [.heal, .shield])
        let n = SkillMath.numbers(ult, hero: voss, rank: 1)
        XCTAssertEqual(n.damage, 0)
        XCTAssertEqual(n.heal, ult.baseDamage * Balance.Skills.healScale * Balance.Skills.teamHealRatio, accuracy: 1e-9)
        XCTAssertEqual(SkillMath.figureValue(.heal, n), "590")
    }

    func testMultiStrikeAndEmpowerUseArchetypeRatios() throws {
        // SK002_5 リラの Ult（連続斬り 45% × 3）、SK020_3 など遠隔 Skill2（強化攻撃 50%）
        let ult = try XCTUnwrap(master.skill("SK002_5"))
        let lyra = try XCTUnwrap(master.hero(ult.heroID))
        let n = SkillMath.numbers(ult, hero: lyra, rank: 1)
        XCTAssertEqual(n.hits, 3)
        XCTAssertEqual(n.damage, ult.baseDamage * Balance.Skills.damageScale(.ultimate) * 0.45, accuracy: 1e-9)
        XCTAssertTrue(SkillMath.figureValue(.damage, n).hasPrefix("3×"))
        let ranged = try XCTUnwrap(master.heroes.first { $0.isRanged })
        let blink = try XCTUnwrap(master.skill(hero: ranged.heroID, slot: .skill2))
        XCTAssertEqual(SkillMath.figures(SkillCatalog.targeting(for: blink, hero: ranged).archetype), [.bonusDamage])
        XCTAssertEqual(SkillMath.numbers(blink, hero: ranged, rank: 1).damage,
                       blink.baseDamage * Balance.Skills.damageScale(.skill2) * 0.5, accuracy: 1e-9)
    }

    func testSkillDescriptionsUseSimulationNumbers() throws {
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            for skill in master.skills where skill.slot != .passive {
                let hero = try XCTUnwrap(master.hero(skill.heroID))
                let n = SkillMath.numbers(skill, hero: hero, rank: 1)
                let text = SkillMath.description(skill, hero: hero)
                // キットのスキルの説明はキットの文（HeroKits.text）。数値の置き換えは testKitDescriptions で確認する
                if let kit = SkillMath.kitDescription(skill, hero: hero, english: lang == .en) {
                    XCTAssertEqual(text, kit, "\(lang) \(skill.skillID)")
                    continue
                }
                let main = n.damage > 0 ? n.damage : n.heal
                XCTAssertTrue(text.contains(CollectionStyle.number(main, digits: 0)), "\(lang) \(skill.skillID): \(text)")
                if n.heal > 0 {
                    XCTAssertTrue(text.contains(CollectionStyle.number(n.heal, digits: 0)), "\(lang) \(skill.skillID): \(text)")
                }
                // マスターの仮文（全スキル共通の「指定方向へ効果を発生し」）は使わない
                XCTAssertFalse(text.contains("指定方向へ効果を発生し"), "\(skill.skillID): \(text)")
                XCTAssertFalse(text.contains("  "), "\(skill.skillID): \(text)")
            }
        }
        Loc.current = .ja
        let mirea = try XCTUnwrap(master.hero("H004"))
        let zone = try XCTUnwrap(master.skill("SK004_5"))
        XCTAssertTrue(SkillMath.description(zone, hero: mirea).contains("指定地点"))
    }

    /// キット（ヒーロー固有スキル）のヒーローの説明文は HeroKits.text から。プレースホルダが残らず、日英で違い、
    /// キットの無いヒーローは従来の文のまま。
    func testKitDescriptionsComeFromTheKit() throws {
        let kitHeroes = master.heroes.map(\.heroID).filter { HeroKits.hasKit($0) }
        try XCTSkipIf(kitHeroes.isEmpty, "有効なキットが無い")
        defer { Loc.current = .ja }
        for id in kitHeroes {
            let hero = try XCTUnwrap(master.hero(id))
            for slot in SkillSlot.allCases {
                guard let skill = master.skill(hero: id, slot: slot), HeroKits.text(heroID: id, slot: slot) != nil else { continue }
                let ja = try XCTUnwrap(SkillMath.kitDescription(skill, hero: hero, english: false), "\(id) \(slot)")
                let en = try XCTUnwrap(SkillMath.kitDescription(skill, hero: hero, english: true), "\(id) \(slot)")
                for text in [ja, en] {
                    XCTAssertFalse(text.contains("{"), "\(id) \(slot): 置き換わっていない: \(text)")
                    XCTAssertFalse(text.isEmpty, "\(id) \(slot)")
                }
                XCTAssertNotEqual(ja, en, "\(id) \(slot)")
                Loc.current = .ja
                XCTAssertEqual(SkillMath.description(skill, hero: hero), ja, "\(id) \(slot): 説明はキットの日本語")
                Loc.current = .en
                XCTAssertEqual(SkillMath.description(skill, hero: hero), en, "\(id) \(slot): 説明はキットの英語")
            }
        }
        // キットの無いヒーローはキットの説明を持たない（従来の生成文）
        let plain = try XCTUnwrap(master.heroes.first { !HeroKits.hasKit($0.heroID) })
        let skill = try XCTUnwrap(master.skill(hero: plain.heroID, slot: .skill1))
        XCTAssertNil(SkillMath.kitDescription(skill, hero: plain, english: false))
    }

    /// H027（ジャルド。常に有効なキット）の説明は、sim の数値で埋めた文。
    func testKitDescriptionFillsSimulationNumbers() throws {
        let hero = try XCTUnwrap(master.hero("H027"))
        try XCTSkipUnless(HeroKits.hasKit("H027"))
        let s1 = try XCTUnwrap(master.skill(hero: "H027", slot: .skill1))
        let n = SkillMath.numbers(s1, hero: hero, rank: 1)
        let ja = try XCTUnwrap(SkillMath.kitDescription(s1, hero: hero, english: false))
        XCTAssertTrue(ja.contains(String(Int(n.damage.rounded()))), ja)
        XCTAssertTrue(ja.contains("跳ね上げ"), ja)
        let en = try XCTUnwrap(SkillMath.kitDescription(s1, hero: hero, english: true))
        XCTAssertTrue(en.contains("Spear"), en)
        // パッシブもキットの文（ロール別の汎用文ではない）
        let passive = try XCTUnwrap(master.skill(hero: "H027", slot: .passive))
        Loc.current = .ja
        XCTAssertNotEqual(SkillMath.description(passive, hero: hero), SkillMath.passiveText(role: hero.role, heroNumber: hero.number))
    }

    /// キットのヒーローの CD・ランク表の列は、キットの数値から。
    func testKitCooldownAndFiguresFollowKitNumbers() throws {
        try XCTSkipUnless(HeroKits.hasKit("H027"))
        let hero = try XCTUnwrap(master.hero("H027"))
        let ult = try XCTUnwrap(master.skill(hero: "H027", slot: .ultimate))
        XCTAssertEqual(SkillMath.cooldown(ult, hero: hero, rank: 1), SkillMath.numbers(ult, hero: hero, rank: 1).cooldown,
                       accuracy: 1e-9)
        // 奥義は自己強化（ダメージなし）: 0 の列を出さない
        let t = SkillCatalog.targeting(for: ult, hero: hero)
        XCTAssertEqual(SkillMath.figures(ult, hero: hero, archetype: t.archetype), [])
        // キットの無いヒーローは従来どおり
        let plain = try XCTUnwrap(master.heroes.first { !HeroKits.hasKit($0.heroID) })
        let sk = try XCTUnwrap(master.skill(hero: plain.heroID, slot: .skill1))
        XCTAssertEqual(SkillMath.cooldown(sk, hero: plain, rank: 2), SkillMath.cooldown(sk, rank: 2), accuracy: 1e-9)
        let pt = SkillCatalog.targeting(for: sk, hero: plain)
        XCTAssertEqual(SkillMath.figures(sk, hero: plain, archetype: pt.archetype), SkillMath.figures(pt.archetype))
    }

    func testShapeNames() {
        XCTAssertNil(SkillMath.shapeName(.auto))
        for shape in [AimShape.fan, .wideLine, .circleAtPoint, .selfRing, .lockOn, .dashToPoint] {
            XCTAssertFalse((SkillMath.shapeName(shape) ?? "").isEmpty, "\(shape)")
        }
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

    func testCombineCostSubtractsComponents() throws {
        // EQ125 レギオンソード = EQ133 + EQ133: 910 − (250 + 250) = 410
        let eq125 = try XCTUnwrap(master.item("EQ125"))
        XCTAssertEqual(ItemMath.combineCost(eq125, master: master), 410)
        // EQ403 スイフトブーツ = EQ408 + EQ132: 720 − (250 + 280) = 190（下限は価格 × Balance.minCombineCostRatio）
        let eq403 = try XCTUnwrap(master.item("EQ403"))
        XCTAssertEqual(ItemMath.combineCost(eq403, master: master), max(190, (720 * Balance.minCombineCostRatio).rounded()))
        // 素材なしは価格そのまま
        let eq133 = try XCTUnwrap(master.item("EQ133"))
        XCTAssertEqual(ItemMath.combineCost(eq133, master: master), eq133.priceGold)
    }

    func testBuildsIntoListsParentsInIDOrder() {
        let parents = ItemMath.buildsInto("EQ133", master: master)
        XCTAssertFalse(parents.isEmpty)
        XCTAssertTrue(parents.allSatisfy { $0.buildFrom.contains("EQ133") })
        XCTAssertEqual(parents.map(\.itemID), parents.map(\.itemID).sorted())
        XCTAssertTrue(ItemMath.buildsInto("EQ106", master: master).isEmpty)
    }

    func testDuplicateComponentsAreKept() throws {
        let eq125 = try XCTUnwrap(master.item("EQ125"))
        XCTAssertEqual(ItemMath.components(eq125, master: master).map(\.itemID), ["EQ133", "EQ133"])
    }

    func testRecipeTreeHasTwoLevels() throws {
        // EQ101 マジックガン = EQ122（= EQ133）+ EQ132 + EQ132
        let eq101 = try XCTUnwrap(master.item("EQ101"))
        let tree = ItemMath.recipeTree(eq101, master: master)
        XCTAssertEqual(tree.map(\.item.itemID), ["EQ122", "EQ132", "EQ132"])
        XCTAssertEqual(tree.map(\.id), [0, 1, 2], "同じ素材が並んでも識別できる")
        XCTAssertEqual(tree[0].children.map(\.item.itemID), ["EQ133"])
        XCTAssertTrue(tree[1].children.isEmpty)
        XCTAssertTrue(tree.allSatisfy { $0.children.allSatisfy { $0.children.isEmpty } }, "2 段まで")
        for item in master.items {
            let nodes = ItemMath.recipeTree(item, master: master)
            XCTAssertEqual(nodes.map(\.item.itemID), item.buildFrom, item.itemID)
            XCTAssertLessThanOrEqual(nodes.count, 4, item.itemID)
        }
    }

    func testPassiveEffectText() throws {
        // 装備ごとの固有効果文（マスターの passive_text。複数の固有効果は 1 行に 1 つ）をそのまま出す
        let eq101 = try XCTUnwrap(master.item("EQ101"))
        XCTAssertEqual(ItemMath.passiveEffectText(eq101), eq101.passiveText)
        XCTAssertEqual(ItemMath.passiveName(eq101), eq101.passiveName)
        // 固有効果の無い素材は空
        let eq133 = try XCTUnwrap(master.item("EQ133"))
        XCTAssertEqual(ItemMath.passiveEffectText(eq133), "")
        XCTAssertNil(ItemMath.passiveName(eq133))
        for item in master.items where !item.passiveText.isEmpty {
            XCTAssertFalse(ItemMath.passiveEffectText(item).isEmpty, item.itemID)
        }
    }

    func testCaptionPrefersTagThenStat() throws {
        let eq101 = try XCTUnwrap(master.item("EQ101"))
        XCTAssertEqual(ItemMath.tag(eq101), eq101.tagJa)
        XCTAssertEqual(ItemMath.caption(eq101), eq101.tagJa)
        // 短い説明の無い素材は主要能力
        let eq133 = try XCTUnwrap(master.item("EQ133"))
        XCTAssertNil(ItemMath.tag(eq133))
        XCTAssertEqual(ItemMath.caption(eq133), "攻撃力 +15")
        for item in master.items {
            XCTAssertFalse(ItemMath.caption(item).isEmpty, item.itemID)
        }
    }

    func testStatLinesSkipZeroValues() throws {
        let eq133 = try XCTUnwrap(master.item("EQ133"))
        XCTAssertEqual(ItemMath.statLines(eq133).count, 1)
        for item in master.items {
            let lines = ItemMath.statLines(item)
            XCTAssertFalse(lines.isEmpty, item.itemID)
            XCTAssertEqual(Set(lines.map(\.id)).count, lines.count, "\(item.itemID) の行が重複している")
        }
    }

    func testStatLinesIncludeNewAndUniqueStats() throws {
        func labels(_ id: String) throws -> [String] { try ItemMath.statLines(XCTUnwrap(master.item(id))).map(\.label) }
        // 固有の能力値は「（固有）」付きで最後に並ぶ（EQ105 ハンターストライク: 物理貫通 15）
        let eq105 = try XCTUnwrap(master.item("EQ105"))
        let hunter = ItemMath.statLines(eq105)
        XCTAssertEqual(hunter.last?.label, "物理貫通（固有）")
        XCTAssertEqual(hunter.last?.value, "+15")
        XCTAssertEqual(hunter.filter { $0.label.contains("（固有）") }.count, eq105.uniqueStats.count)
        XCTAssertTrue(try labels("EQ313").contains("クリティカルダメージ軽減（固有）"))
        // 総入れ替えで足した能力値
        XCTAssertTrue(try labels("EQ113").contains("適応攻撃"))
        XCTAssertTrue(try labels("EQ201").contains("最大MP"))
        XCTAssertTrue(try labels("EQ406").contains("コントロール時間短縮"))
        XCTAssertTrue(try labels("EQ402").contains("減速軽減"))
        XCTAssertTrue(try labels("EQ307").contains("受ける回復"))
        XCTAssertTrue(try labels("EQ325").contains("ダメージ軽減"))
        // 固有の能力値はすべて表示する（表に無いキーも落とさない）
        for item in master.items {
            let unique = ItemMath.statLines(item).filter { $0.label.hasSuffix("（固有）") }
            XCTAssertEqual(unique.count, item.uniqueStats.filter { $0.value != 0 }.count, item.itemID)
        }
    }

    func testConsumableText() throws {
        let potion = try XCTUnwrap(master.item("EQ134"))
        XCTAssertTrue(potion.isConsumable)
        XCTAssertTrue(ItemMath.consumableText(potion)?.contains("\(Int(potion.consumableSec)) 秒") == true)
        XCTAssertNil(ItemMath.consumableText(try XCTUnwrap(master.item("EQ101"))))
    }

    func testItemFilter() {
        XCTAssertEqual(master.items.count, 92)
        XCTAssertEqual(ItemMath.filtered(master.items, category: nil, tier: nil).count, 92)
        let attackT3 = ItemMath.filtered(master.items, category: .attack, tier: 3)
        XCTAssertFalse(attackT3.isEmpty)
        XCTAssertTrue(attackT3.allSatisfy { $0.isListed(in: .attack) && $0.tier == 3 })
        XCTAssertEqual(attackT3.map(\.itemID), attackT3.map(\.itemID).sorted(), "ID 順")
        // 別のタブにも並ぶ装備（ウィンタークラウンは攻撃と魔法）
        let magic = ItemMath.filtered(master.items, category: .magic, tier: nil).map(\.itemID)
        XCTAssertTrue(magic.contains("EQ113"))
        XCTAssertTrue(ItemMath.filtered(master.items, category: .attack, tier: nil).map(\.itemID).contains("EQ113"))
        // ジャングル・ロームは祝福のタブ（装備は無い）
        XCTAssertTrue(ItemMath.filtered(master.items, category: .jungle, tier: nil).isEmpty)
        XCTAssertTrue(ItemMath.filtered(master.items, category: .roam, tier: nil).isEmpty)
    }

    // MARK: 祝福

    func testGearInfoDescribesEveryBlessing() {
        XCTAssertTrue(GearInfo.isBlessingCategory(.jungle))
        XCTAssertTrue(GearInfo.isBlessingCategory(.roam))
        XCTAssertFalse(GearInfo.isBlessingCategory(.movement))
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            let names = GearOption.allCases.map(GearInfo.name)
            XCTAssertEqual(Set(names).count, names.count, "\(lang)")
            for o in GearOption.allCases {
                XCTAssertFalse(GearInfo.short(o).isEmpty)
                XCTAssertFalse(GearInfo.summary(o).isEmpty)
                XCTAssertEqual(GearInfo.details(o).first, GearInfo.summary(o))
                XCTAssertFalse(GearInfo.symbol(o).isEmpty)
            }
            XCTAssertFalse(GearInfo.rules(.jungle).isEmpty)
            XCTAssertFalse(GearInfo.rules(.roam).isEmpty)
            XCTAssertTrue(GearInfo.rules(.attack).isEmpty)
            XCTAssertEqual(GearInfo.commonRules.count, 2)
        }
        Loc.current = .ja
        // 数値は Balance.Gear から作る
        XCTAssertTrue(GearInfo.summary(.encourage).contains("+\(Int(Balance.Gear.encourageDefense))"))
        XCTAssertTrue(GearInfo.rules(.roam).joined().contains("2:00"))
    }

    func testBlessingProgressTexts() {
        let k = Balance.Gear.self
        XCTAssertEqual(GearInfo.jungleProgressText(3), "狩りとキル 3 / \(k.jungleBlessingUnlockCount)")
        XCTAssertTrue(GearInfo.jungleProgressText(k.jungleBlessingUnlockCount).contains("/ \(k.jungleSecondUnlockCount)"))
        XCTAssertFalse(GearInfo.jungleProgressText(k.jungleSecondUnlockCount).contains("/"))
        XCTAssertEqual(GearInfo.roamProgressText(640), "共栄ゴールド 640 / \(Int(k.blessingUnlockGold))")
        XCTAssertFalse(GearInfo.roamProgressText(Int(k.blessingUnlockGold)).contains("/"))
    }

    // MARK: ビルド

    func testBuildRulesEnforceLimits() {
        // EQ403 / EQ404 = 靴（移動）
        XCTAssertEqual(BuildRules.check("EQ404", adding: ["EQ403"], replacing: nil, master: master), .bootsLimit)
        XCTAssertEqual(BuildRules.check("EQ101", adding: ["EQ101"], replacing: nil, master: master), .duplicate)
        XCTAssertEqual(BuildRules.check("EQ999", adding: [], replacing: nil, master: master), .unknown)
        XCTAssertEqual(BuildRules.check("EQ001", adding: [], replacing: nil, master: master), .unknown, "旧装備は無い")
        // ポーションはビルドに入らない
        XCTAssertEqual(BuildRules.check("EQ134", adding: [], replacing: nil, master: master), .consumable)
        XCTAssertEqual(BuildRules.check("EQ325", adding: ["EQ101"], replacing: 0, master: master), .consumable)
        let full = ["EQ101", "EQ102", "EQ103", "EQ104", "EQ105", "EQ106"]
        XCTAssertEqual(BuildRules.check("EQ107", adding: full, replacing: nil, master: master), .full)
        // 置換なら満杯でも可、靴どうしの差し替えも可
        XCTAssertEqual(BuildRules.check("EQ107", adding: full, replacing: 0, master: master), .ok)
        XCTAssertEqual(BuildRules.check("EQ404", adding: ["EQ403"], replacing: 0, master: master), .ok)
        for c in [BuildCheck.full, .duplicate, .bootsLimit, .consumable, .unknown] {
            XCTAssertFalse(c.message.isEmpty)
        }
        XCTAssertNotNil(master.spell(BuildRules.smiteSpellID))
    }

    func testRecommendedBuildIsSanitizedAndWithinSlots() {
        for hero in master.heroes {
            let build = BuildRules.recommended(for: hero.heroID, master: master)
            XCTAssertEqual(build.count, BuildRules.slotCount, hero.heroID)
            XCTAssertEqual(BuildRules.sanitized(build, master: master), build)
            XCTAssertEqual(build.filter { master.item($0)?.isBoots == true }.count, 1, "\(hero.heroID) の靴は 1 足")
        }
        XCTAssertEqual(BuildRules.recommended(for: "H999", master: master), [])
    }

    func testSanitizedBuildDropsInvalidEntries() {
        let raw = ["EQ403", "EQ404", "BAD", "EQ101", "EQ101", "EQ134", "EQ001", "EQ102", "EQ103", "EQ104", "EQ105", "EQ106"]
        XCTAssertEqual(BuildRules.sanitized(raw, master: master), ["EQ403", "EQ101", "EQ102", "EQ103", "EQ104", "EQ105"])
    }

    func testBuildMoveSwapsNeighbours() {
        XCTAssertEqual(BuildRules.move(["A", "B", "C"], from: 1, by: -1), ["B", "A", "C"])
        XCTAssertEqual(BuildRules.move(["A", "B", "C"], from: 2, by: 1), ["A", "B", "C"])
    }

    func testCurrentBuildPrefersCustom() {
        var p = Profile()
        p.customBuilds["H003"] = ["EQ101", "EQ106"]
        XCTAssertEqual(BuildRules.current(for: "H003", profile: p, master: master), ["EQ101", "EQ106"])
        XCTAssertEqual(BuildRules.current(for: "H001", profile: p, master: master),
                       BuildRules.recommended(for: "H001", master: master))
        XCTAssertEqual(BuildRules.totalCost(["EQ101", "EQ106"], master: master), 2120 + 3010)
        // 旧装備の ID が残ったカスタムビルドは読み込み時に落とす
        p.customBuilds["H003"] = ["EQ061", "EQ101"]
        XCTAssertEqual(BuildRules.current(for: "H003", profile: p, master: master), ["EQ101"])
        p.customBuilds["H003"] = ["EQ061", "EQ043"]
        XCTAssertNil(BuildRules.custom(for: "H003", profile: p, master: master))
        XCTAssertEqual(BuildRules.current(for: "H003", profile: p, master: master),
                       BuildRules.recommended(for: "H003", master: master), "旧装備だけのビルドはおすすめに戻す")
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

    func testSpellAssignmentKeepsHealFixed() {
        // 1 枠目だけ変えられる。2 枠目は常に治癒波（BS03）
        XCTAssertEqual(SpellLoadoutRules.assigning("BS07", slot: 0, in: ["BS01", "BS03"]), ["BS07", "BS03"])
        XCTAssertEqual(SpellLoadoutRules.assigning("BS07", slot: 1, in: ["BS01", "BS03"]), ["BS01", "BS03"])
        XCTAssertEqual(SpellLoadoutRules.assigning("BS03", slot: 0, in: ["BS01", "BS03"]), ["BS01", "BS03"])
        XCTAssertEqual(SpellLoadoutRules.normalized([]), ["BS01", "BS03"])
        // 旧データ（治癒波が 1 枠目・重複・他スペルが 2 枠目）は治癒波を 2 枠目に寄せる
        XCTAssertEqual(SpellLoadoutRules.normalized(["BS03", "BS01"]), ["BS01", "BS03"])
        XCTAssertEqual(SpellLoadoutRules.normalized(["BS03", "BS03"]), ["BS01", "BS03"])
        XCTAssertEqual(SpellLoadoutRules.normalized(["BS07", "BS01"]), ["BS07", "BS03"])
        // 不明な ID は除外して既定で補う
        XCTAssertEqual(SpellLoadoutRules.normalized(["BS99", "BS07"]), ["BS07", "BS03"])
        XCTAssertEqual(SpellLoadoutRules.normalized(["", "BS02"]), ["BS02", "BS03"])
    }

    func testSmiteNameFollowsMasterSpellName() {
        XCTAssertEqual(BuildRules.smiteName(master: master), "狩猟印")
        XCTAssertEqual(BuildRules.smiteName(master: master), master.spell(BuildRules.smiteSpellID).map { MasterText.spell($0) })
    }

    func testEffectiveSpellsUseHeroOverride() {
        var p = Profile()
        p.defaultSpells = ["BS02", "BS04"]
        p.heroSpells["H006"] = ["BS05", "BS01"]
        XCTAssertEqual(SpellLoadoutRules.effective(heroID: nil, profile: p), ["BS02", "BS03"])
        XCTAssertEqual(SpellLoadoutRules.effective(heroID: "H001", profile: p), ["BS02", "BS03"])
        XCTAssertEqual(SpellLoadoutRules.effective(heroID: "H006", profile: p), ["BS05", "BS03"])
    }

    // MARK: エモート

    func testEmoteSlotsAreCompactAndCappedAtFour() {
        XCTAssertEqual(EmoteSlots.normalized([]), [])
        XCTAssertEqual(EmoteSlots.normalized(["A", "", "B", "A", "C", "D", "E"]), ["A", "B", "C", "D"])
        // 空き枠を指定すると最初の空き枠へ詰める
        XCTAssertEqual(EmoteSlots.assigning("A", slot: 2, in: []), ["A"])
        XCTAssertEqual(EmoteSlots.assigning("C", slot: 3, in: ["A", "B"]), ["A", "B", "C"])
        // 埋まった枠は置換、装備済みを別の枠へ置くと入れ替え
        XCTAssertEqual(EmoteSlots.assigning("X", slot: 1, in: ["A", "B", "C"]), ["A", "X", "C"])
        XCTAssertEqual(EmoteSlots.assigning("C", slot: 0, in: ["A", "B", "C"]), ["C", "B", "A"])
        XCTAssertEqual(EmoteSlots.assigning("B", slot: 3, in: ["A", "B"]), ["A", "B"])
        XCTAssertEqual(EmoteSlots.assigning("E", slot: 3, in: ["A", "B", "C", "D"]), ["A", "B", "C", "E"])
        XCTAssertEqual(EmoteSlots.assigning("E", slot: 4, in: ["A"]), ["A"])
        // 空ける（後ろは詰まる）
        XCTAssertEqual(EmoteSlots.clearing(slot: 0, in: ["A", "B"]), ["B"])
        XCTAssertEqual(EmoteSlots.clearing(slot: 3, in: ["A", "B"]), ["A", "B"])
        XCTAssertEqual(EmoteSlots.pruned(["A", "X", ""], owned: ["A"]), ["A"])
        XCTAssertEqual(EmoteSlots.emote(at: 1, in: ["A", "B"]), "B")
        XCTAssertNil(EmoteSlots.emote(at: 2, in: ["A", "B"]))
        XCTAssertEqual(EmoteSlots.firstEmptySlot(in: ["A", "B"]), 2)
        XCTAssertNil(EmoteSlots.firstEmptySlot(in: ["A", "B", "C", "D"]))
        // 旧形式（"" 埋め 4 要素）も読める
        XCTAssertEqual(EmoteSlots.normalized(["A", "", "", "B"]), ["A", "B"])
    }

    // MARK: ヒーロー一覧

    func testHeroListFilter() {
        let owned = ["H001", "H002", "H007"]
        XCTAssertEqual(HeroListFilter.heroes(master.heroes, role: nil, ownership: .all, owned: owned).count, 34)
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
        XCTAssertEqual(CollectionStyle.categoryName(.magic), "Magic")
        XCTAssertEqual(GearInfo.name(.flame), "Flame Hunt")
        // 装備の固有効果・短い説明は master_en.json の "<id>.desc" / "<id>.tag"（日本語が混ざらない）
        let eq101 = master.item("EQ101")!
        for text in [ItemMath.passiveEffectText(eq101), ItemMath.passiveName(eq101) ?? "", ItemMath.caption(eq101)] {
            XCTAssertFalse(text.isEmpty)
            XCTAssertNil(text.range(of: "[\\u3040-\\u30ff\\u3400-\\u9fff]", options: .regularExpression), text)
        }
        XCTAssertTrue(SpellInfo.of("BS01").effect.hasPrefix("Teleport"))
    }
}
