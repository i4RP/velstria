import XCTest
@testable import VELSTRIA
import VelstriaCore

// 担当: ui-collection。ヒーロー詳細・スキル詳細（左: ヒーロー情報 / 右: スキル詳細）の表示用の純粋な計算の検証。
// タグ（種類・派生ルール・色）、評価バー、レベル表、説明文の強調、係数、選択。

final class SkillShowcaseTests: XCTestCase {
    let master = MasterData.shared

    override func setUp() {
        super.setUp()
        Loc.current = .ja
    }

    private func skill(_ hero: String, _ slot: SkillSlot) throws -> SkillDef {
        try XCTUnwrap(master.skill(hero: hero, slot: slot))
    }

    // MARK: タグ（色の対応表）

    func testTagColorsFollowTheSingleMapping() {
        let buff = SkillTags.rgb(for: "buff")
        let aoe = SkillTags.rgb(for: "aoe")
        let control = SkillTags.rgb(for: "slow")
        let mobility = SkillTags.rgb(for: "clash")
        XCTAssertEqual(SkillTags.rgb(for: "disrupt"), control)
        XCTAssertEqual(SkillTags.rgb(for: "stun"), control)
        XCTAssertEqual(SkillTags.rgb(for: "control"), control)
        XCTAssertEqual(SkillTags.rgb(for: "pull"), control)
        XCTAssertEqual(SkillTags.rgb(for: "mobility"), mobility)
        XCTAssertEqual(SkillTags.rgb(for: "execute"), SkillTags.rgb(for: "burst"))
        // 7 系統（バフ・範囲・妨害系・衝突/移動・バースト・回復・シールド）はそれぞれ別の色
        let distinct = [buff, aoe, control, mobility, SkillTags.rgb(for: "burst"), SkillTags.rgb(for: "heal"),
                        SkillTags.rgb(for: "shield")]
        for i in distinct.indices {
            for j in distinct.indices where i < j { XCTAssertNotEqual(distinct[i], distinct[j], "\(i) \(j)") }
        }
        // 大文字小文字は区別しない
        XCTAssertEqual(SkillTags.rgb(for: "AOE"), aoe)
    }

    func testTagColorHues() {
        // バフ = ティール（緑と青が赤より強い）、範囲 = オレンジ、妨害系 = 赤みが強い、衝突 = 紫（青が緑より強い）、回復 = 緑、シールド = 青
        let buff = SkillTags.rgb(for: "buff")
        XCTAssertGreaterThan(buff.g, buff.r)
        XCTAssertGreaterThan(buff.b, buff.r)
        let aoe = SkillTags.rgb(for: "aoe")
        XCTAssertGreaterThan(aoe.r, aoe.g)
        XCTAssertGreaterThan(aoe.g, aoe.b)
        let control = SkillTags.rgb(for: "slow")
        XCTAssertGreaterThan(control.r, control.g)
        XCTAssertGreaterThan(control.r, 0.7)
        let clash = SkillTags.rgb(for: "clash")
        XCTAssertGreaterThan(clash.b, clash.g)
        XCTAssertGreaterThan(clash.r, clash.g)
        let heal = SkillTags.rgb(for: "heal")
        XCTAssertGreaterThan(heal.g, heal.r)
        XCTAssertGreaterThan(heal.g, heal.b)
        let shield = SkillTags.rgb(for: "shield")
        XCTAssertGreaterThan(shield.b, shield.r)
        XCTAssertGreaterThan(shield.b, shield.g)
        for c in [buff, aoe, control, clash, heal, shield] {
            for v in [c.r, c.g, c.b] { XCTAssertTrue((0...1).contains(v)) }
        }
    }

    func testTagNamesAndUnknownKey() {
        XCTAssertEqual(SkillTags.name(for: "buff"), "バフ")
        XCTAssertEqual(SkillTags.name(for: "aoe"), "範囲技")
        XCTAssertEqual(SkillTags.name(for: "slow"), "減速")
        XCTAssertEqual(SkillTags.name(for: "clash"), "衝突")
        XCTAssertEqual(SkillTags.name(for: "disrupt"), "妨害")
        Loc.current = .en
        XCTAssertEqual(SkillTags.name(for: "aoe"), "AoE")
        XCTAssertEqual(SkillTags.name(for: "disrupt"), "Disrupt")
        Loc.current = .ja
        // 知らないキーは名前をそのまま出し、灰色
        let unknown = SkillTags.style(for: "mystery")
        XCTAssertEqual(unknown.name, "mystery")
        XCTAssertEqual(unknown.rgb, SkillTags.rgb(for: "also-unknown"))
        // 既知のキーは全部、灰色でも空の名前でもない
        for key in SkillTags.knownKeys {
            let s = SkillTags.style(for: key)
            XCTAssertFalse(s.name.isEmpty, key)
            XCTAssertFalse(s.symbol.isEmpty, key)
            XCTAssertNotEqual(s.rgb, unknown.rgb, key)
            XCTAssertEqual(s.name == key, false, key)
        }
    }

    // MARK: タグの派生ルール

    func testDerivedTagsFromShapeAndCC() {
        typealias T = SkillTags
        XCTAssertEqual(T.derive(slot: .passive, archetype: .passive, cc: .none, heal: 0, shield: 0, missingHealthRatio: 0), ["buff"])
        XCTAssertEqual(T.derive(slot: .skill1, archetype: .cone, cc: .none, heal: 0, shield: 0, missingHealthRatio: 0), ["aoe"])
        XCTAssertEqual(T.derive(slot: .skill1, archetype: .cone, cc: .slow, heal: 0, shield: 0, missingHealthRatio: 0), ["aoe", "slow"])
        XCTAssertEqual(T.derive(slot: .skill2, archetype: .dashStrike, cc: .none, heal: 0, shield: 0, missingHealthRatio: 0), ["mobility"])
        XCTAssertEqual(T.derive(slot: .skill2, archetype: .dashStrike, cc: .knockback, heal: 0, shield: 0, missingHealthRatio: 0),
                       ["clash", "disrupt"])
        XCTAssertEqual(T.derive(slot: .ultimate, archetype: .leapSlam, cc: .stun, heal: 0, shield: 0, missingHealthRatio: 0),
                       ["mobility", "stun"])
        XCTAssertEqual(T.derive(slot: .skill1, archetype: .lineSkillshot, cc: .root, heal: 0, shield: 0, missingHealthRatio: 0),
                       ["burst", "control"])
        XCTAssertEqual(T.derive(slot: .ultimate, archetype: .piercingLine, cc: .none, heal: 0, shield: 0, missingHealthRatio: 0),
                       ["burst", "aoe"])
        XCTAssertEqual(T.derive(slot: .skill2, archetype: .blinkEmpower, cc: .slow, heal: 0, shield: 0, missingHealthRatio: 0),
                       ["mobility", "slow"])
        XCTAssertEqual(T.derive(slot: .ultimate, archetype: .multiStrike, cc: .stun, heal: 0, shield: 0, missingHealthRatio: 0),
                       ["aoe", "stun"])
        XCTAssertEqual(T.derive(slot: .skill1, archetype: .groundAoE, cc: .none, heal: 0, shield: 0, missingHealthRatio: 0), ["aoe"])
    }

    func testDerivedTagsForHealingAndExecute() {
        typealias T = SkillTags
        // 対象指定ブリンクは移動 + 処刑（CC があっても 2 個まで）
        XCTAssertEqual(T.derive(slot: .ultimate, archetype: .targetedBlink, cc: .stun, heal: 0, shield: 0, missingHealthRatio: 0.3),
                       ["mobility", "execute"])
        XCTAssertEqual(T.derive(slot: .ultimate, archetype: .targetedBlink, cc: .stun, heal: 0, shield: 0, missingHealthRatio: 0),
                       ["mobility", "stun"])
        // 味方全体回復は回復 + シールド
        XCTAssertEqual(T.derive(slot: .ultimate, archetype: .teamHeal, cc: .stun, heal: 500, shield: 200, missingHealthRatio: 0),
                       ["heal", "shield"])
        XCTAssertEqual(T.derive(slot: .ultimate, archetype: .teamHeal, cc: .none, heal: 500, shield: 0, missingHealthRatio: 0), ["heal"])
        // 回復ゾーンは回復 + CC（CC が無ければ範囲）
        XCTAssertEqual(T.derive(slot: .skill2, archetype: .healZone, cc: .slow, heal: 100, shield: 0, missingHealthRatio: 0),
                       ["heal", "slow"])
        XCTAssertEqual(T.derive(slot: .skill2, archetype: .healZone, cc: .none, heal: 100, shield: 0, missingHealthRatio: 0),
                       ["heal", "aoe"])
        // 自己シールド付きの範囲
        XCTAssertEqual(T.derive(slot: .skill1, archetype: .selfAoE, cc: .none, heal: 0, shield: 90, missingHealthRatio: 0),
                       ["aoe", "shield"])
        XCTAssertEqual(T.derive(slot: .skill1, archetype: .selfAoE, cc: .slow, heal: 0, shield: 90, missingHealthRatio: 0),
                       ["aoe", "slow"])
    }

    func testTagsForEverySkillAreValid() {
        for hero in master.heroes {
            for skill in master.skills(forHero: hero.heroID) {
                let tags = SkillTags.tags(for: skill, hero: hero, master: master)
                XCTAssertFalse(tags.isEmpty, skill.skillID)
                XCTAssertLessThanOrEqual(tags.count, SkillTags.maxTagsPerSkill, skill.skillID)
                XCTAssertEqual(Set(tags).count, tags.count, skill.skillID)
                for key in tags { XCTAssertTrue(SkillTags.knownKeys.contains(key), "\(skill.skillID) \(key)") }
                if skill.slot == .passive { XCTAssertEqual(tags, ["buff"], skill.skillID) }
            }
            let feature = SkillTags.featureTags(hero: hero, master: master)
            XCTAssertFalse(feature.isEmpty, hero.heroID)
            XCTAssertLessThanOrEqual(feature.count, SkillTags.maxTagsPerSkill)
        }
    }

    func testTagCaptionUsesPrimaryTag() {
        XCTAssertEqual(SkillTags.caption(for: ["slow", "aoe"]), "減速")
        XCTAssertEqual(SkillTags.caption(for: []), "")
        XCTAssertEqual(SkillTags.unique(["aoe", "slow", "aoe", ""]), ["aoe", "slow"])
    }

    // MARK: 評価バー

    func testCCStrength() {
        XCTAssertEqual(HeroRatingMath.ccStrength(.none, duration: 3), 0)
        XCTAssertEqual(HeroRatingMath.ccStrength(.stun, duration: 2), 2, accuracy: 1e-9)
        // 持続が未設定の CC は 1 秒扱い
        XCTAssertEqual(HeroRatingMath.ccStrength(.stun, duration: 0), 1, accuracy: 1e-9)
        // 同じ持続なら スタン > 拘束 > 減速
        XCTAssertGreaterThan(HeroRatingMath.ccStrength(.stun, duration: 1), HeroRatingMath.ccStrength(.root, duration: 1))
        XCTAssertGreaterThan(HeroRatingMath.ccStrength(.root, duration: 1), HeroRatingMath.ccStrength(.slow, duration: 1))
        // 長いほど強い
        XCTAssertGreaterThan(HeroRatingMath.ccStrength(.slow, duration: 3), HeroRatingMath.ccStrength(.slow, duration: 1))
    }

    func testNormalizedRatingRange() {
        let values = [10.0, 20, 30]
        XCTAssertEqual(HeroRatingMath.normalized(10, among: values), HeroRatingMath.barFloor, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.normalized(30, among: values), 1, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.normalized(20, among: values), HeroRatingMath.barFloor + (1 - HeroRatingMath.barFloor) * 0.5,
                       accuracy: 1e-9)
        // 範囲外は丸める。全員同じ値なら中央
        XCTAssertEqual(HeroRatingMath.normalized(99, among: values), 1, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.normalized(5, among: [7, 7, 7]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.normalized(5, among: []), 0.5, accuracy: 1e-9)
    }

    func testRatioAndDifficulty() {
        XCTAssertEqual(HeroRatingMath.ratio(5, max: 10), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.ratio(0, max: 10), 0, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.ratio(20, max: 10), 1, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.ratio(3, max: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.difficultyValue(1), 0.2, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.difficultyValue(3), 0.6, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.difficultyValue(5), 1, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.difficultyValue(9), 1, accuracy: 1e-9)
        XCTAssertEqual(HeroRatingMath.difficultyValue(0), 0.2, accuracy: 1e-9)
    }

    func testRatingsFromSyntheticRoster() {
        let tank = HeroRawRatings(survivability: 9000, offense: 100, control: 4)
        let mage = HeroRawRatings(survivability: 4000, offense: 300, control: 0)
        let mid = HeroRawRatings(survivability: 6500, offense: 200, control: 2)
        let roster = [tank, mage, mid]
        let t = HeroRatingMath.ratings(raw: tank, roster: roster, difficulty: 2)
        let m = HeroRatingMath.ratings(raw: mage, roster: roster, difficulty: 5)
        XCTAssertEqual(t.survivability, 1, accuracy: 1e-9)
        XCTAssertEqual(m.survivability, HeroRatingMath.barFloor, accuracy: 1e-9)
        XCTAssertGreaterThan(t.survivability, m.survivability)
        XCTAssertGreaterThan(m.offense, t.offense)
        XCTAssertEqual(t.control, 1, accuracy: 1e-9)
        XCTAssertEqual(m.control, 0, accuracy: 1e-9)
        XCTAssertEqual(t.difficulty, 0.4, accuracy: 1e-9)
        XCTAssertEqual(m.difficulty, 1, accuracy: 1e-9)
    }

    func testRatingsForEveryHeroAreInUnitRange() {
        var bestSurvivability = -Double.infinity
        var bestHero = ""
        for hero in master.heroes {
            let r = HeroRatingMath.ratings(for: hero, master: master)
            for v in [r.survivability, r.offense, r.control, r.difficulty] {
                XCTAssertTrue((0...1).contains(v), "\(hero.heroID) \(v)")
            }
            XCTAssertEqual(r.difficulty, Double(hero.difficulty) / 5, accuracy: 1e-9, hero.heroID)
            let raw = HeroRatingMath.raw(for: hero, master: master)
            XCTAssertGreaterThan(raw.survivability, 0, hero.heroID)
            XCTAssertGreaterThan(raw.offense, 0, hero.heroID)
            XCTAssertGreaterThanOrEqual(raw.control, 0, hero.heroID)
            if raw.survivability > bestSurvivability {
                bestSurvivability = raw.survivability
                bestHero = hero.heroID
            }
        }
        // 全員の中で最も硬いヒーローの生存能力は 1
        let best = master.hero(bestHero).map { HeroRatingMath.ratings(for: $0, master: master) }
        XCTAssertEqual(best?.survivability ?? 0, 1, accuracy: 1e-9)
        // 誰かには CC がある（コントロール効果の最大は 1）
        let controls = master.heroes.map { HeroRatingMath.ratings(for: $0, master: master).control }
        XCTAssertEqual(controls.max() ?? 0, 1, accuracy: 1e-9)
    }

    // MARK: レベル表

    func testLevelTableForBasicSkill() throws {
        let hero = try XCTUnwrap(master.hero("H001"))
        let skill = try self.skill("H001", .skill1)
        let table = SkillLevelTable.build(skill: skill, hero: hero)
        XCTAssertEqual(table.ranks, [1, 2, 3, 4])
        XCTAssertEqual(table.rows.first?.kind, .cooldown)
        XCTAssertEqual(table.rows.first?.title, "CD時間")
        for row in table.rows { XCTAssertEqual(row.values.count, 4, row.title) }
        // CD は SkillMath と同じ値（小数 1 桁）で、ランクが上がるほど短い
        let cd1 = SkillMath.cooldown(skill, hero: hero, rank: 1)
        XCTAssertEqual(table.rows[0].values[0], SkillShowcaseText.fixed1(cd1))
        XCTAssertLessThan(SkillMath.cooldown(skill, hero: hero, rank: 4), cd1)
        // 汎用スキルのコストはランクで変わらない → 行を出さない
        XCTAssertFalse(table.rows.contains { $0.kind == .cost })
        // 主な数値の行（ダメージ）
        let damageRow = try XCTUnwrap(table.rows.first { $0.kind == .figure(.damage) })
        XCTAssertEqual(damageRow.title, "基礎ダメージ")
        XCTAssertEqual(damageRow.values[0], SkillMath.figureValue(.damage, SkillMath.numbers(skill, hero: hero, rank: 1)))
        XCTAssertEqual(damageRow.values[3], SkillMath.figureValue(.damage, SkillMath.numbers(skill, hero: hero, rank: 4)))
    }

    func testLevelTableUltimateHasThreeColumnsAndPassiveHasNone() throws {
        let hero = try XCTUnwrap(master.hero("H001"))
        let ult = SkillLevelTable.build(skill: try skill("H001", .ultimate), hero: hero)
        XCTAssertEqual(ult.ranks, [1, 2, 3])
        for row in ult.rows { XCTAssertEqual(row.values.count, 3, row.title) }
        let passive = SkillLevelTable.build(skill: try skill("H001", .passive), hero: hero)
        XCTAssertTrue(passive.ranks.isEmpty)
        XCTAssertTrue(passive.rows.isEmpty)
    }

    func testLevelTableHealingUltimateListsHealAndShield() throws {
        // 味方全体回復（サポートのアルティメット）は回復量とシールド量の行を持つ
        let support = try XCTUnwrap(master.heroes.first { $0.role == .support && !HeroKits.hasKit($0.heroID) })
        let ult = try skill(support.heroID, .ultimate)
        let table = SkillLevelTable.build(skill: ult, hero: support)
        XCTAssertTrue(table.rows.contains { $0.kind == .figure(.heal) })
        XCTAssertTrue(table.rows.contains { $0.kind == .figure(.shield) })
        XCTAssertEqual(table.rows.first { $0.kind == .figure(.heal) }?.title, "回復量")
    }

    func testCostsVaryAndPerRankCost() throws {
        XCTAssertFalse(SkillLevelTable.costsVary([]))
        XCTAssertFalse(SkillLevelTable.costsVary([40, 40, 40]))
        XCTAssertTrue(SkillLevelTable.costsVary([40, 45, 50]))
        // キットの無いヒーローのコストはこれまでどおり一定
        for hero in master.heroes where !HeroKits.hasKit(hero.heroID) {
            for skill in master.skills(forHero: hero.heroID) where skill.slot != .passive {
                for rank in SkillMath.ranks(for: skill.slot) {
                    XCTAssertEqual(SkillMath.cost(skill, hero: hero, rank: rank), SkillMath.cost(skill, resource: hero.resource),
                                   accuracy: 1e-9, skill.skillID)
                }
            }
        }
    }

    func testLevelTableColumnsMatchForEverySkill() {
        for hero in master.heroes {
            for skill in master.skills(forHero: hero.heroID) {
                let table = SkillLevelTable.build(skill: skill, hero: hero)
                XCTAssertEqual(table.ranks, SkillMath.ranks(for: skill.slot), skill.skillID)
                if skill.slot == .passive {
                    XCTAssertTrue(table.rows.isEmpty, skill.skillID)
                } else {
                    XCTAssertEqual(table.rows.first?.kind, .cooldown, skill.skillID)
                    for row in table.rows { XCTAssertEqual(row.values.count, table.ranks.count, "\(skill.skillID) \(row.title)") }
                }
            }
        }
    }

    // MARK: 文字列

    func testStatLine() {
        XCTAssertEqual(SkillShowcaseText.fixed1(7), "7.0")
        XCTAssertEqual(SkillShowcaseText.fixed1(6.44), "6.4")
        XCTAssertEqual(SkillShowcaseText.statLine(cooldown: 7, cost: 45, resource: .mana), "CD：7.0　マナ消費量：45")
        XCTAssertEqual(SkillShowcaseText.statLine(cooldown: 55, cost: 16.2, resource: .energy), "CD：55.0　エナジー消費量：16.2")
        XCTAssertEqual(SkillShowcaseText.costRowTitle(.mana), "マナコスト")
        XCTAssertEqual(SkillShowcaseText.rankTitle(3), "Lv.3")
        Loc.current = .en
        XCTAssertEqual(SkillShowcaseText.statLine(cooldown: 7, cost: 45, resource: .mana), "CD: 7.0   Mana Cost: 45")
        Loc.current = .ja
    }

    // MARK: 説明文の強調

    private func joined(_ segs: [SkillTextSegment]) -> String { segs.map(\.text).joined() }

    func testStylerKeepsTheText() {
        let samples = [
            "前方 90° の扇形を斬りつけ、命中した敵に基礎 170 の魔法ダメージを与え、ノックバックさせる。",
            "Fires a skillshot. The first enemy hit takes 170 base magic damage and is slowed.",
            "ハンマーで地面を叩き、270 (+70% 攻撃力) の物理ダメージを与え、スタンさせる。",
            "",
            "ただの文章",
        ]
        for s in samples { XCTAssertEqual(joined(SkillDescriptionStyler.segments(s)), s) }
        XCTAssertTrue(SkillDescriptionStyler.segments("").isEmpty)
        XCTAssertEqual(SkillDescriptionStyler.segments("ただの文章"), [SkillTextSegment(text: "ただの文章", role: .plain)])
    }

    func testStylerRolesJapanese() {
        let segs = SkillDescriptionStyler.segments("270 (+70% 攻撃力)の物理ダメージを与え、スタンさせる。HP を回復する。")
        func roles(_ r: SkillTextSegment.Role) -> [String] { segs.filter { $0.role == r }.map(\.text) }
        XCTAssertEqual(roles(.coefficient), ["(+70% 攻撃力)"])
        XCTAssertEqual(roles(.physical), ["物理ダメージ"])
        XCTAssertEqual(roles(.keyword), ["スタン"])
        XCTAssertEqual(roles(.heal), ["回復"])
        let magic = SkillDescriptionStyler.segments("基礎 100 の魔法ダメージと確定ダメージ")
        XCTAssertEqual(magic.filter { $0.role == .magic }.map(\.text), ["魔法ダメージ"])
        XCTAssertEqual(magic.filter { $0.role == .trueDamage }.map(\.text), ["確定ダメージ"])
        // 全角のかっこの係数
        let full = SkillDescriptionStyler.segments("600（+130% 攻撃力）のダメージ")
        XCTAssertEqual(full.filter { $0.role == .coefficient }.map(\.text), ["（+130% 攻撃力）"])
    }

    func testStylerRolesEnglish() {
        let segs = SkillDescriptionStyler.segments("Enemies take 270 physical damage and are stunned. Allies heal 100 HP.")
        func roles(_ r: SkillTextSegment.Role) -> [String] { segs.filter { $0.role == r }.map(\.text) }
        XCTAssertEqual(roles(.physical), ["physical damage"])
        XCTAssertEqual(roles(.keyword), ["stunned"])
        XCTAssertEqual(roles(.heal), ["heal"])
    }

    // MARK: 係数

    func testCoefficientParts() {
        typealias S = SkillMath.Scaling
        let zero = S(attack: 0, power: 0)
        let atk = SkillCoefficient.parts(scaling: (damage: S(attack: 0.6, power: 0), heal: zero), figures: [.damage])
        XCTAssertEqual(atk.map(\.kind), [.damageAttack])
        XCTAssertEqual(atk.first?.percent ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(atk.first?.text, "+60% 攻撃力")
        let both = SkillCoefficient.parts(scaling: (damage: S(attack: 0.5, power: 0.8), heal: zero), figures: [.damage])
        XCTAssertEqual(both.map(\.kind), [.damageAttack, .damagePower])
        XCTAssertEqual(both.last?.text, "+80% 魔力")
        // 回復は heal の係数、ダメージの行が無ければダメージの係数は出さない
        let heal = SkillCoefficient.parts(scaling: (damage: S(attack: 0.5, power: 0.5), heal: S(attack: 0, power: 0.4)), figures: [.heal])
        XCTAssertEqual(heal.map(\.kind), [.healPower])
        XCTAssertEqual(heal.first?.text, "+40% 魔力")
        XCTAssertTrue(SkillCoefficient.parts(scaling: (damage: zero, heal: zero), figures: [.damage, .heal]).isEmpty)
        XCTAssertTrue(SkillCoefficient.parts(scaling: (damage: S(attack: 1, power: 1), heal: zero), figures: []).isEmpty)
        Loc.current = .en
        XCTAssertEqual(SkillCoefficient.parts(scaling: (damage: S(attack: 0.6, power: 0), heal: zero), figures: [.damage]).first?.text,
                       "+60% ATK")
        Loc.current = .ja
    }

    // MARK: 選択

    func testDefaultSkillSelection() throws {
        let skills = master.skills(forHero: "H001")
        XCTAssertEqual(HeroSkillSelection.defaultSkill(skills)?.slot, .skill1)
        XCTAssertNil(HeroSkillSelection.defaultSkill([]))
        let ult = try skill("H001", .ultimate)
        XCTAssertEqual(HeroSkillSelection.resolved(selectedID: ult.skillID, skills: skills)?.skillID, ult.skillID)
        // 別のヒーローのスキル・存在しない ID・nil は既定へ
        let other = try skill("H002", .skill2)
        XCTAssertEqual(HeroSkillSelection.resolved(selectedID: other.skillID, skills: skills)?.slot, .skill1)
        XCTAssertEqual(HeroSkillSelection.resolved(selectedID: "nope", skills: skills)?.slot, .skill1)
        XCTAssertEqual(HeroSkillSelection.resolved(selectedID: nil, skills: skills)?.slot, .skill1)
    }
}
