import XCTest
@testable import VelstriaCore

/// エンブレム（MLBB の 7 セットと 3 段のタレント。Data/EmblemCatalog.swift / Systems/EmblemEffects.swift。docs/EMBLEMS.md）。
final class EmblemTests: XCTestCase {
    private let spot = Vec2(6000, 6000)
    private typealias K = Balance.Emblems

    // MARK: - データ

    func testCatalogHasSevenSetsAndEightEightTenTalentsInPickerOrder() {
        XCTAssertEqual(EmblemCatalog.sets.map(\.id), EmblemSetID.allCases)
        XCTAssertEqual(EmblemCatalog.sets.map(\.id.rawValue),
                       ["EM_COMMON", "EM_TANK", "EM_ASSASSIN", "EM_MAGE", "EM_FIGHTER", "EM_SUPPORT", "EM_MARKSMAN"])
        XCTAssertEqual(EmblemCatalog.talents.map(\.id), EmblemTalentID.allCases)
        XCTAssertEqual(Set(EmblemCatalog.talents.map(\.id.rawValue)).count, 26)
        XCTAssertTrue(EmblemCatalog.talents.allSatisfy { $0.id.rawValue.hasPrefix("TL_") })
        XCTAssertTrue(EmblemCatalog.sets.allSatisfy { $0.id.rawValue.hasPrefix("EM_") && $0.attributes.count == 3 })
        // ピッカーの並び（日本語クライアントのスクショ。左上から行ごと）
        XCTAssertEqual(EmblemCatalog.talents(tier: .tier1).map(\.id),
                       [.thrill, .swift, .vitality, .rupture, .inspire, .firmness, .agility, .fatal])
        XCTAssertEqual(EmblemCatalog.talents(tier: .tier2).map(\.id),
                       [.wildernessBlessing, .seasonedHunter, .tenacity, .masterAssassin, .bargainHunter,
                        .festivalOfBlood, .pullYourselfTogether, .weaponMaster])
        XCTAssertEqual(EmblemCatalog.talents(tier: .core).map(\.id),
                       [.impureRage, .quantumCharge, .warCry, .temporalReign, .concussiveBlast, .killingSpree,
                        .lethalIgnition, .braveSmite, .focusingMark, .weaknessFinder])
        // セットの既定のタレントは各段のもの
        for d in EmblemCatalog.sets {
            XCTAssertEqual(d.defaultTier1.tier, .tier1, d.id.rawValue)
            XCTAssertEqual(d.defaultTier2.tier, .tier2, d.id.rawValue)
            XCTAssertEqual(d.defaultCore.tier, .core, d.id.rawValue)
            XCTAssertTrue(EmblemCatalog.defaultLoadout(set: d.id).isValid)
        }
        // 1 段目は小見出しが無い（ピッカーの画面どおり）。2 段目・コアにはある
        for t in EmblemCatalog.talents {
            XCTAssertEqual(t.subtitleJa == nil, t.tier == .tier1, t.id.rawValue)
            XCTAssertFalse(t.descriptionJa.isEmpty)
            XCTAssertFalse(t.descriptionEn.isEmpty)
            XCTAssertFalse(t.params.isEmpty, t.id.rawValue)
            XCTAssertNil(t.unlockLevel, "天賦ごとの解放レベルは不明（段の解放レベル EmblemProgression.talentUnlockLevels を使う）")
        }
    }

    func testScreenshotValuesAndConfirmedNames() {
        func values(_ id: EmblemSetID) -> [String] {
            EmblemCatalog.set(id).attributes.map { "\($0.kind.nameJa) \($0.maxValue)\($0.kind.isPercent ? "%" : "")" }
        }
        // スクショ（Lv60）
        XCTAssertEqual(values(.common), ["混合回復 12.0", "HP 275.0", "適応攻撃 22.0"])
        XCTAssertEqual(values(.tank), ["HP 500.0", "混合防御 10.0", "HP回復 4.0"])
        // ハンターの 🔍（適応貫通は割合）
        XCTAssertEqual(values(.marksman), ["攻撃速度 15.0%", "適応攻撃 16.0", "適応貫通 10.0%"])
        // Fandom
        XCTAssertEqual(values(.assassin), ["適応貫通 14.0", "適応攻撃 10.0", "移動速度 3.0%"])
        XCTAssertEqual(values(.mage), ["魔法攻撃 30.0", "CD短縮 5.0%", "魔法貫通 8.0"])
        XCTAssertEqual(values(.fighter), ["混合吸収 10.0%", "適応攻撃 16.0", "混合防御 8.0"])
        XCTAssertEqual(values(.support), ["回復効果 12.0%", "CD短縮 10.0%", "移動速度 6.0%"])
        XCTAssertEqual(EmblemCatalog.set(.common).nameJa, "通常共通エンブレム")
        XCTAssertEqual(EmblemCatalog.set(.tank).nameJa, "オーダーエンブレム(タンク)")
        XCTAssertEqual(EmblemCatalog.set(.marksman).nameJa, "オーダーエンブレム(ハンター)")
        // 画面で確かめた天賦の名前
        let confirmed = EmblemCatalog.talents.filter(\.jaConfirmed).map { "\($0.id.rawValue)=\($0.nameJa)" }
        XCTAssertEqual(Set(confirmed), ["TL_VITALITY=活力", "TL_TENACITY=強靭", "TL_WEAKNESS_FINDER=弱点分析",
                                        "TL_FATAL=致命", "TL_WEAPON_MASTER=武器マスター", "TL_CONCUSSIVE_BLAST=強震撃",
                                        "TL_THRILL=衝撃", "TL_WILDERNESS_BLESSING=山野の主", "TL_IMPURE_RAGE=不純な怒り"])
        // コア属性はステータス欄の 1 つ目（通常共通 = 混合回復・タンク = HP・アサシン = 適応貫通・サポート = 回復効果は画面で確認）
        for d in EmblemCatalog.sets {
            XCTAssertEqual(d.attributes.map(\.isCore), [true, false, false], d.id.rawValue)
        }
        XCTAssertEqual(Set(EmblemCatalog.sets.filter(\.coreConfirmed).map(\.id)), [.common, .tank, .assassin, .support])
        XCTAssertEqual(EmblemCatalog.talent(.tenacity).subtitleJa, "低HP時防御力上昇")
        XCTAssertEqual(EmblemCatalog.talent(.weaknessFinder).subtitleJa, "通常攻撃で敵を減速")
        XCTAssertEqual(EmblemCatalog.talent(.vitality).descriptionJa, "最大HPが225上昇する。")
        // 用語説明（共通用語・ステータス説明）
        XCTAssertEqual(EmblemAttributeKind.hybridRegen.glossaryJa, "HP+MP回復。")
        XCTAssertEqual(EmblemAttributeKind.hybridDefense.glossaryJa, "物理+魔法防御。")
        XCTAssertTrue(EmblemAttributeKind.adaptiveAttack.glossaryJa?.hasPrefix("追加物理攻撃が追加魔法攻撃より高い場合") == true)
        XCTAssertNotNil(EmblemAttributeKind.adaptivePenetrationPct.glossaryEn)
        XCTAssertEqual(EmblemCatalog.talent(.tenacity).descriptionJa, "HPが50%未満の時、ダメージ軽減が5%上昇する。")
    }

    func testLevelTableFallsBackToMaxValue() {
        let a = EmblemAttribute(.hp, 500)
        XCTAssertEqual(a.value(level: 60), 500)
        XCTAssertEqual(a.value(level: 1), 500, "表が無ければ Lv60 の値")
        let b = EmblemAttribute(.hp, 500, levelValues: [10, 20, 30])
        XCTAssertEqual(b.value(level: 2), 20)
        XCTAssertEqual(b.value(level: 60), 500, "表の外は Lv60 の値")
        XCTAssertTrue(EmblemCatalog.sets.allSatisfy { $0.attributes.allSatisfy { $0.levelValues?.count == 60 } },
                      "セットは仮のレベル別の表を持つ（EmblemProgression.levelValues）")
        XCTAssertEqual(EmblemCatalog.clampLevel(0), 1)
        XCTAssertEqual(EmblemCatalog.clampLevel(99), 60)
        XCTAssertFalse(EmblemLoadout(.common, .thrill, .tenacity, .impureRage, level: 61).isValid)
    }

    func testAnyCombinationIsAllowedButTiersMustMatch() {
        for set in EmblemSetID.allCases {
            for t1 in EmblemCatalog.talents(tier: .tier1) {
                XCTAssertTrue(EmblemLoadout(set, t1.id, .weaponMaster, .focusingMark).isValid)
            }
        }
        XCTAssertFalse(EmblemLoadout(.tank, .tenacity, .tenacity, .impureRage).isValid)
        XCTAssertFalse(EmblemLoadout(.tank, .vitality, .impureRage, .impureRage).isValid)
        XCTAssertFalse(EmblemLoadout(.tank, .vitality, .tenacity, .fatal).isValid)
        // 段の合わないタレントへの付け替えは同じ段の枠へ入る
        let e = EmblemCatalog.defaultLoadout(set: .tank).replacing(.weaknessFinder)
        XCTAssertEqual(e.core, .weaknessFinder)
        XCTAssertEqual(e.tier1, .vitality)
    }

    // MARK: - バトルプラン・ボット

    func testEveryBattlePlanCarriesTheScreenshotEmblem() {
        var n = 0
        for (heroID, plans) in ItemSystem.heroPlans {
            for (k, p) in plans.enumerated() {
                n += 1
                XCTAssertTrue(p.emblem.isValid, "\(heroID) \(k)")
                XCTAssertEqual(p.emblem.level, 60)
            }
        }
        XCTAssertEqual(n, 30)
        func e(_ h: String, _ k: Int) -> EmblemLoadout { ItemSystem.heroPlans[h]![k].emblem }
        XCTAssertEqual(e("H025", 0), EmblemLoadout(.marksman, .fatal, .masterAssassin, .quantumCharge))
        XCTAssertEqual(e("H026", 0), EmblemLoadout(.assassin, .rupture, .wildernessBlessing, .lethalIgnition))
        // 金の盾と上向きの矢印 = 武器マスター（エウドラ 3・ライラ 1 / 3・オーロラ 3）
        XCTAssertEqual(e("H026", 2).tier2, .weaponMaster)
        XCTAssertEqual(e("H030", 0), EmblemLoadout(.assassin, .fatal, .weaponMaster, .quantumCharge))
        XCTAssertEqual(e("H030", 2).tier2, .weaponMaster)
        XCTAssertEqual(e("H031", 2), EmblemLoadout(.common, .rupture, .weaponMaster, .lethalIgnition))
        XCTAssertEqual(e("H029", 0), EmblemLoadout(.tank, .firmness, .pullYourselfTogether, .concussiveBlast))
        XCTAssertEqual(e("H033", 1), EmblemLoadout(.assassin, .thrill, .seasonedHunter, .temporalReign))
        XCTAssertEqual(e("H032", 2), EmblemLoadout(.assassin, .rupture, .festivalOfBlood, .lethalIgnition))
    }

    func testBotsUseTheDefaultPlanEmblemOrTheRoleDefault() {
        // H025〜H034 は「有効」のプランのエンブレム
        for heroID in HeroRoster.activeHeroIDs {
            XCTAssertEqual(EmblemCatalog.botLoadout(heroID: heroID), ItemSystem.plan(heroID: heroID, chosen: nil)!.emblem, heroID)
        }
        XCTAssertEqual(EmblemCatalog.botLoadout(heroID: "H033")?.core, .temporalReign)    // 有効 = 2 つ目
        XCTAssertEqual(EmblemCatalog.botLoadout(heroID: "H025")?.tier2, .masterAssassin)  // 有効 = 3 つ目
        // ほかはロール別（ヴァンガード = タンク、デュエリスト = ファイター、アルカニスト = メイジ、レンジャー = ハンター）
        XCTAssertEqual(EmblemCatalog.botLoadout(heroID: "H001"), EmblemLoadout(.tank, .vitality, .tenacity, .concussiveBlast))
        XCTAssertEqual(EmblemCatalog.botLoadout(heroID: "H002"), EmblemLoadout(.fighter, .firmness, .festivalOfBlood, .braveSmite))
        XCTAssertEqual(EmblemCatalog.botLoadout(heroID: "H003"), EmblemLoadout(.marksman, .fatal, .weaponMaster, .weaknessFinder))
        XCTAssertEqual(EmblemCatalog.botLoadout(heroID: "H004"), EmblemLoadout(.mage, .inspire, .bargainHunter, .lethalIgnition))
        XCTAssertEqual(EmblemCatalog.botLoadout(heroID: "H005"), EmblemLoadout(.support, .agility, .pullYourselfTogether, .focusingMark))
        XCTAssertEqual(EmblemCatalog.botLoadout(heroID: "H006"), EmblemLoadout(.assassin, .rupture, .masterAssassin, .killingSpree))
        XCTAssertNil(EmblemCatalog.botLoadout(heroID: "H999"))

        let cfg = MatchFactory.botMatch(seed: 5)
        for p in cfg.players {
            XCTAssertEqual(p.emblem, EmblemCatalog.botLoadout(heroID: p.heroID), p.heroID)
            XCTAssertEqual(p.emblem?.level, 60)
        }
        let sim = Simulation(config: cfg)
        for i in sim.state.heroIndices {
            let h = sim.state.units[i].hero!
            XCTAssertEqual(h.emblem, EmblemCatalog.botLoadout(heroID: h.heroID))
        }
    }

    func testHumanGetsTheGivenEmblemOrTheChosenPlanEmblem() {
        // 渡されなければ選んだバトルプランのエンブレム
        let plan2 = MatchFactory.standardMatch(humanHeroID: "H027", humanName: "P", humanBuildPlan: 2, seed: 42)
        XCTAssertEqual(plan2.humanSlot?.emblem, ItemSystem.heroPlans["H027"]![2].emblem)
        let none = MatchFactory.standardMatch(humanHeroID: "H027", humanName: "P", seed: 42)
        XCTAssertEqual(none.humanSlot?.emblem, ItemSystem.plan(heroID: "H027", chosen: nil)!.emblem)
        // 保存したエンブレム（レベル込み）はそのまま
        let mine = EmblemLoadout(.support, .vitality, .bargainHunter, .warCry, level: 60)
        for cfg in [MatchFactory.standardMatch(humanHeroID: "H030", humanName: "P", humanEmblem: mine, seed: 1),
                    MatchFactory.brawlMatch(humanHeroID: "H030", humanName: "P", humanEmblem: mine, seed: 1),
                    MatchFactory.customMatch(humanHeroID: "H030", humanEmblem: mine, seed: 1),
                    MatchFactory.practiceMatch(humanHeroID: "H030", humanName: "P", options: PracticeOptions(),
                                               humanEmblem: mine, seed: 1),
                    MatchFactory.onlineMatch(humans: [OnlineHumanSlot(team: .blue, position: .carry, heroID: "H030",
                                                                      displayName: "P", emblem: mine)], seed: 1)] {
            XCTAssertEqual(cfg.humanSlot?.emblem, mine, "\(cfg.mode)")
        }
        // オンラインでエンブレムを送らない旧版のロビーは選んだプランのエンブレム
        let old = MatchFactory.onlineMatch(humans: [OnlineHumanSlot(team: .blue, position: .mid, heroID: "H031",
                                                                    displayName: "P", buildPlan: 1)], seed: 1)
        XCTAssertEqual(old.humanSlot?.emblem, ItemSystem.heroPlans["H031"]![1].emblem)
    }

    // MARK: - 古いデータ

    func testOldConfigsWithRunesDecodeAndUnknownEmblemValuesFallBack() throws {
        let slot = PlayerSlot(team: .blue, heroID: "H025", controller: .human, position: .carry, displayName: "P",
                              buildPlan: 1)
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(slot)) as? [String: Any])
        obj.removeValue(forKey: "emblem")
        obj["runes"] = ["RN01", "RN12", "RN23"]
        let old = try JSONDecoder().decode(PlayerSlot.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.emblem, "旧版の runes は読まない")
        XCTAssertEqual(old.buildPlan, 1)

        // 旧版の試合構成（runes を持つ）も読める
        var cfgObj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(MatchFactory.botMatch(seed: 2)))
            as? [String: Any])
        cfgObj["simVersion"] = 16
        cfgObj["players"] = (cfgObj["players"] as? [[String: Any]])?.map { p -> [String: Any] in
            var p = p
            p.removeValue(forKey: "emblem")
            p["runes"] = [String]()
            return p
        }
        let oldCfg = try JSONDecoder().decode(MatchConfig.self, from: JSONSerialization.data(withJSONObject: cfgObj))
        XCTAssertEqual(oldCfg.simVersion, 16)
        XCTAssertTrue(oldCfg.players.allSatisfy { $0.emblem == nil })

        // 知らないセット・段の違うタレント・レベル無し
        let bad = #"{"set":"EM_BOGUS","tier1":"TL_IMPURE_RAGE","tier2":"TL_TENACITY","core":"TL_NOPE"}"#
        let e = try JSONDecoder().decode(EmblemLoadout.self, from: Data(bad.utf8))
        XCTAssertEqual(e, EmblemLoadout(.common, .thrill, .tenacity, .impureRage, level: 60))
        let lv = try JSONDecoder().decode(EmblemLoadout.self, from: Data(#"{"set":"EM_TANK","level":250}"#.utf8))
        XCTAssertEqual(lv, EmblemCatalog.defaultLoadout(set: .tank))
        // 往復
        let mine = EmblemLoadout(.mage, .inspire, .weaponMaster, .temporalReign, level: 37)
        XCTAssertEqual(try JSONDecoder().decode(EmblemLoadout.self, from: JSONEncoder().encode(mine)), mine)
        let text = String(decoding: try JSONEncoder().encode(mine), as: UTF8.self)
        XCTAssertTrue(text.contains("\"EM_MAGE\"") && text.contains("\"TL_TEMPORAL_REIGN\""), text)
    }

    // MARK: - セットの能力値

    /// 能力値だけを計算する（装備なし。hero を渡すと MP・適応の向き・スタックが入る）。
    private func stats(_ e: EmblemLoadout?, items: [String] = [], heroID: String = "H002", takedowns: Int = 0,
                       base: Stats? = nil) -> Stats {
        var st = base ?? {
            var s = Stats()
            s.attack = 100; s.abilityPower = 0; s.maxHP = 2000; s.armor = 20; s.magicResist = 20
            s.moveSpeed = 250; s.attackSpeed = 1; s.hpRegen = 5; s.resourceRegen = 3
            return s
        }()
        let def = MasterData.shared.hero(heroID)!
        var h = HeroData(heroID: heroID, role: def.role, isRanged: def.isRanged, resourceKind: def.resource,
                         controller: .bot, position: .mid, displayName: "T", botDifficulty: .normal,
                         spells: ["BS01", "BS03"], emblem: e, skinID: nil)
        h.emblemRuntime.takedowns = takedowns
        ItemStats.apply(items: items, emblem: e, to: &st, master: .shared, hero: h)
        // 攻撃速度（基礎 + 追加 × 比率）と移動速度（基礎 × (100% + 加速 − 減速)）を確定する。マップ縮尺・逓減は見ない（isHero: false）
        StatCalculator.finalize(&st, isHero: false)
        return st
    }

    func testEverySetAttributeAppliesToStats() {
        let none = stats(nil)
        func d(_ set: EmblemSetID, heroID: String = "H002") -> (Stats, Stats) {
            // 能力値だけのタレント（1 段目・2 段目）が入らない組み合わせ: 1 段目は致命（クリティカル）、2 段目は熟練ハンター
            (stats(EmblemLoadout(set, .fatal, .seasonedHunter, .warCry), heroID: heroID), stats(nil, heroID: heroID))
        }
        // 通常共通（Mana のヒーロー H004 は MP 回復も、Energy の H002 は HP 回復だけ）
        var (s, b) = d(.common, heroID: "H004")
        XCTAssertEqual(s.hpRegen - b.hpRegen, 12, accuracy: 1e-9)
        XCTAssertEqual(s.resourceRegen - b.resourceRegen, 12, accuracy: 1e-9)
        XCTAssertEqual(s.maxHP - b.maxHP, 275, accuracy: 1e-9)
        XCTAssertEqual(s.abilityPower - b.abilityPower, 22, accuracy: 1e-9, "魔法のヒーローは適応攻撃が魔法攻撃に")
        (s, b) = d(.common)
        XCTAssertEqual(s.resourceRegen, b.resourceRegen, accuracy: 1e-9, "Energy のヒーローに MP 回復は無い")
        XCTAssertEqual(s.attack - b.attack, 22, accuracy: 1e-9)
        // タンク
        (s, b) = d(.tank)
        XCTAssertEqual(s.maxHP - b.maxHP, 500, accuracy: 1e-9)
        XCTAssertEqual(s.armor - b.armor, 10, accuracy: 1e-9)
        XCTAssertEqual(s.magicResist - b.magicResist, 10, accuracy: 1e-9)
        XCTAssertEqual(s.hpRegen - b.hpRegen, 4, accuracy: 1e-9)
        // アサシン（物理のヒーローは物理貫通）
        (s, b) = d(.assassin)
        XCTAssertEqual(s.armorPenFlat - b.armorPenFlat, 14, accuracy: 1e-9)
        XCTAssertEqual(s.magicPenFlat, b.magicPenFlat, accuracy: 1e-9)
        XCTAssertEqual(s.attack - b.attack, 10, accuracy: 1e-9)
        XCTAssertEqual(s.moveSpeed, b.moveSpeed * 1.03, accuracy: 1e-9)
        // メイジ
        (s, b) = d(.mage)
        XCTAssertEqual(s.abilityPower - b.abilityPower, 30, accuracy: 1e-9)
        XCTAssertEqual(s.cooldownReduction - b.cooldownReduction, 0.05, accuracy: 1e-9)
        XCTAssertEqual(s.magicPenFlat - b.magicPenFlat, 8, accuracy: 1e-9)
        // ファイター
        (s, b) = d(.fighter)
        XCTAssertEqual(s.lifesteal - b.lifesteal, 0.10, accuracy: 1e-9)
        XCTAssertEqual(s.spellVamp - b.spellVamp, 0.10, accuracy: 1e-9)
        XCTAssertEqual(s.attack - b.attack, 16, accuracy: 1e-9)
        XCTAssertEqual(s.armor - b.armor, 8, accuracy: 1e-9)
        // サポート
        (s, b) = d(.support)
        XCTAssertEqual(s.healShieldPower - b.healShieldPower, 0.12, accuracy: 1e-9)
        XCTAssertEqual(s.cooldownReduction - b.cooldownReduction, 0.10, accuracy: 1e-9)
        XCTAssertEqual(s.moveSpeed, b.moveSpeed * 1.06, accuracy: 1e-9)
        // ハンター（適応貫通は割合）
        (s, b) = d(.marksman)
        // 攻撃速度 +15% は追加の攻撃速度 +0.15 回/秒（MLBB: 基礎 + 追加 × 比率）
        XCTAssertEqual(s.attackSpeed, b.attackSpeed + 0.15, accuracy: 1e-9)
        XCTAssertEqual(s.attack - b.attack, 16, accuracy: 1e-9)
        XCTAssertEqual(s.armorPenPct - b.armorPenPct, 0.10, accuracy: 1e-9)
        XCTAssertEqual(s.magicPenPct, b.magicPenPct, accuracy: 1e-9)
        // エンブレム無しは何も変わらない
        XCTAssertEqual(none, stats(nil))
    }

    func testAdaptiveAttackAndPenetrationFollowExtraStats() {
        let rupture = EmblemLoadout(.common, .rupture, .seasonedHunter, .warCry)
        // 物理のヒーロー・装備なし: 物理
        var s = stats(rupture, heroID: "H002")
        XCTAssertEqual(s.attack, 122, accuracy: 1e-9)
        XCTAssertEqual(s.armorPenFlat, 5, accuracy: 1e-9)
        // 魔法のヒーロー・装備なし（追加はどちらも 0）: ヒーローの主なダメージの種類 = 魔法。
        // 物理攻撃の合計（素の 100）と魔法攻撃の合計（0）で比べると物理になってしまう（比べるのは「追加」同士）
        s = stats(rupture, heroID: "H004")
        XCTAssertEqual(s.abilityPower, 22, accuracy: 1e-9)
        XCTAssertEqual(s.magicPenFlat, 5, accuracy: 1e-9)
        // 物理のヒーローでも、追加の魔法攻撃が多ければ魔法（ジーニアスワンド: 魔法攻撃 +75）
        s = stats(rupture, items: ["EQ203"], heroID: "H002")
        XCTAssertEqual(s.attack, 100, accuracy: 1e-9)
        XCTAssertGreaterThan(s.abilityPower, 22 + 50)
        XCTAssertEqual(s.magicPenFlat - stats(nil, items: ["EQ203"], heroID: "H002").magicPenFlat, 5, accuracy: 1e-9)
        // メイジのセットの魔法攻撃 30 は追加の魔法攻撃として数える（物理のヒーローでも適応は魔法へ）
        s = stats(EmblemLoadout(.mage, .rupture, .seasonedHunter, .warCry), heroID: "H002")
        XCTAssertEqual(s.attack, 100, accuracy: 1e-9)
        XCTAssertEqual(s.magicPenFlat, 8 + 5, accuracy: 1e-9)
    }

    func testAdaptiveDamageComparesExtraStatsOnly() {
        // 適応ダメージ（不純な怒り・致死の発火）の向き: 追加の物理攻撃と魔法攻撃を比べ、同じならヒーローのダメージタイプ
        var (f, a, _) = duel(nil, attacker: "H004")
        XCTAssertGreaterThan(f.s.units[a].stats.attack, f.s.units[a].stats.abilityPower, "前提: 合計は物理攻撃の方が多い")
        XCTAssertTrue(ItemEffects.adaptiveIsMagic(f.s.units[a], f.master), "追加はどちらも 0 → 魔法のヒーローは魔法")
        var (g, b, _) = duel(nil, attacker: "H002")
        XCTAssertFalse(ItemEffects.adaptiveIsMagic(g.s.units[b], g.master))
        g.s.units[b].hero!.items = ["EQ203"]
        StatCalculator.recompute(&g.s, b, g.ctx)
        XCTAssertTrue(ItemEffects.adaptiveIsMagic(g.s.units[b], g.master), "追加の魔法攻撃が多ければ物理のヒーローでも魔法")
        f.s.units[a].hero!.items = ["EQ133"]
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertFalse(ItemEffects.adaptiveIsMagic(f.s.units[a], f.master), "追加の物理攻撃が多ければ魔法のヒーローでも物理")
    }

    func testTierOneTalents() {
        let base = stats(EmblemLoadout(.tank, .fatal, .seasonedHunter, .warCry))
        func with(_ t: EmblemTalentID, heroID: String = "H002") -> Stats {
            stats(EmblemLoadout(.tank, t, .seasonedHunter, .warCry), heroID: heroID)
        }
        // 致命: クリティカル率 +5%・クリティカルダメージ +5%
        let noCrit = stats(EmblemLoadout(.tank, .vitality, .seasonedHunter, .warCry))
        XCTAssertEqual(base.critChance - noCrit.critChance, 0.05, accuracy: 1e-9)
        XCTAssertEqual(base.critMultiplier - noCrit.critMultiplier, 0.05, accuracy: 1e-9)
        XCTAssertEqual(with(.thrill).attack - noCrit.attack, 16, accuracy: 1e-9)
        XCTAssertEqual(with(.swift).attackSpeed, noCrit.attackSpeed + 0.10, accuracy: 1e-9)
        XCTAssertEqual(with(.vitality).maxHP - base.maxHP, 225, accuracy: 1e-9)
        XCTAssertEqual(with(.rupture).armorPenFlat - base.armorPenFlat, 5, accuracy: 1e-9)
        XCTAssertEqual(with(.inspire).cooldownReduction - base.cooldownReduction, 0.05, accuracy: 1e-9)
        XCTAssertEqual(with(.inspire).resourceRegen, base.resourceRegen, accuracy: 1e-9, "Energy に MP 回復は無い")
        XCTAssertEqual(with(.inspire, heroID: "H004").resourceRegen
                       - stats(EmblemLoadout(.tank, .fatal, .seasonedHunter, .warCry), heroID: "H004").resourceRegen,
                       2, accuracy: 1e-9)
        XCTAssertEqual(with(.firmness).armor - base.armor, 8, accuracy: 1e-9)
        XCTAssertEqual(with(.firmness).magicResist - base.magicResist, 8, accuracy: 1e-9)
        XCTAssertEqual(with(.agility).moveSpeed, noCrit.moveSpeed * 1.04, accuracy: 1e-9)
    }

    func testWeaponMasterAndFestivalOfBlood() {
        // 武器マスター: 装備・エンブレムで得た物理攻撃 +8%（ダガー +15、通常共通の適応攻撃 +22、高揚 +16）
        let plain = stats(EmblemLoadout(.common, .thrill, .seasonedHunter, .warCry), items: ["EQ133"])
        let wm = stats(EmblemLoadout(.common, .thrill, .weaponMaster, .warCry), items: ["EQ133"])
        let extra = plain.attack - 100
        XCTAssertEqual(wm.attack, 100 + extra * 1.08, accuracy: 1e-9)
        // 血の祭典: スキル吸収 6% + キル・アシストごとに 0.5%（12 スタックまで）
        let fob = EmblemLoadout(.tank, .vitality, .festivalOfBlood, .warCry)
        XCTAssertEqual(stats(fob).spellVamp, 0.06, accuracy: 1e-9)
        XCTAssertEqual(stats(fob, takedowns: 4).spellVamp, 0.08, accuracy: 1e-9)
        XCTAssertEqual(stats(fob, takedowns: 40).spellVamp, 0.12, accuracy: 1e-9)
    }

    // MARK: - 1v1 の試合状態

    /// blue の a（attacker）と red の v。キット・自動習得を外し、v は防御・軽減 0、最大 HP 20000。
    private func duel(_ e: EmblemLoadout?, attacker: String = "H002", victim: String = "H008",
                      extraBlue: String? = nil, extraRed: String? = nil) -> (EconomyFixture, Int, Int) {
        var players = [
            PlayerSlot(team: .blue, heroID: attacker, controller: .human, position: .mid, emblem: e, displayName: "A",
                       autoLevelSkills: false),
            PlayerSlot(team: .red, heroID: victim, controller: .human, position: .mid, displayName: "V",
                       autoLevelSkills: false),
        ]
        if let extraBlue {
            players.append(PlayerSlot(team: .blue, heroID: extraBlue, controller: .bot, position: .top, displayName: "B",
                                      autoLevelSkills: false))
        }
        if let extraRed {
            players.append(PlayerSlot(team: .red, heroID: extraRed, controller: .bot, position: .top, displayName: "R",
                                      autoLevelSkills: false))
        }
        var f = EconomyFixture(config: MatchConfig(mode: .standard, seed: 1, players: players))
        let a = f.heroes(.blue)[0], v = f.heroes(.red)[0]
        f.place(a, at: spot)
        f.place(v, at: spot + Vec2(150, 0))
        for i in f.s.heroIndices {
            f.s.units[i].hero!.kit = nil
            StatCalculator.recompute(&f.s, i, f.ctx)
            f.s.units[i].hp = f.s.units[i].stats.maxHP
            if i != a { bare(&f, i) }
        }
        for i in f.s.heroIndices where i != a && i != v { f.place(i, at: spot + Vec2(0, 3000)) }
        f.s.events.removeAll()
        return (f, a, v)
    }

    private func bare(_ f: inout EconomyFixture, _ i: Int, hp: Double = 20_000) {
        f.s.units[i].stats.armor = 0
        f.s.units[i].stats.magicResist = 0
        f.s.units[i].stats.damageReduction = 0
        f.s.units[i].stats.maxHP = hp
        f.s.units[i].hp = hp
    }

    @discardableResult
    private func hit(_ f: inout EconomyFixture, _ from: Int, _ to: Int, _ raw: Double, _ type: DamageType = .physical,
                     _ source: DamageSource = .skill(.skill1)) -> Double {
        CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(from), targetIndex: to, amount: raw, type: type,
                                source: source, isCrit: false, appliesOnHit: source == .basicAttack)
    }

    private func advance(_ f: inout EconomyFixture, _ seconds: Double) {
        for _ in 0..<Int((seconds * Balance.tickRate).rounded()) {
            f.s.tick += 1
            f.s.time = Double(f.s.tick) * Balance.dt
        }
    }

    /// エンブレムの追加ダメージ（DamageSource.item）の合計。
    private func extraDamage(_ f: EconomyFixture, to i: Int) -> Double {
        f.s.events.reduce(0) {
            if case .damage(let d) = $1, d.targetID == f.id(i), d.source == .item { return $0 + d.amount }
            return $0
        }
    }

    private func status(_ f: EconomyFixture, _ i: Int, _ tag: String) -> StatusEffect? {
        f.s.units[i].statuses.first { $0.tag == tag }
    }

    // MARK: - 2 段目

    func testTenacityBelowHalfHP() {
        var (f, a, _) = duel(EmblemLoadout(.tank, .vitality, .tenacity, .warCry))
        StatCalculator.recompute(&f.s, a, f.ctx)
        let full = f.s.units[a].stats.damageReduction
        f.s.units[a].hp = f.s.units[a].stats.maxHP * 0.49
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.damageReduction - full, 0.05, accuracy: 1e-9)
    }

    func testWildernessBlessingOnlyInJungleAndRiverAndHalvedInCombat() {
        let map = MapDefinition.standard
        XCTAssertFalse(map.isInWilderness(map.fountain(.blue)))
        XCTAssertFalse(map.isInWilderness(map.core(.red)))
        XCTAssertFalse(map.isInWilderness(map.towers.first { $0.lane == .top && $0.tier == .outer }!.pos))
        XCTAssertTrue(map.isInWilderness(Vec2(map.size / 2, map.size / 2) + Vec2(600, -600)), "川")
        for c in map.camps where c.side != .neutral {
            XCTAssertTrue(map.isInWilderness(c.pos), "camp \(c.id) \(c.kind)")
        }
        let camp = map.camps.first { $0.side == .blue }!.pos
        var (f, a, _) = duel(EmblemLoadout(.common, .thrill, .wildernessBlessing, .warCry))
        f.place(a, at: map.towers.first { $0.lane == .top && $0.tier == .outer && $0.team == .blue }!.pos)
        StatCalculator.recompute(&f.s, a, f.ctx)
        let lane = f.s.units[a].stats.moveSpeed
        f.place(a, at: camp)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.moveSpeed, lane * 1.10, accuracy: 1e-6)
        f.s.units[a].lastCombatTime = f.s.time
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.moveSpeed, lane * 1.05, accuracy: 1e-6)
    }

    func testSeasonedHunterAndMasterAssassinDamageBonus() {
        var (f, a, v) = duel(EmblemLoadout(.assassin, .rupture, .seasonedHunter, .warCry))
        let boss = f.addMonster(.astralWyrm, at: spot + Vec2(200, 0))
        let creep = f.addMonster(.hornLizard, at: spot + Vec2(250, 0))
        XCTAssertEqual(EmblemEffects.outgoingDamageBonus(f.s, f.ctx, attacker: a, target: boss, source: .basicAttack), 0.15, accuracy: 1e-9)
        XCTAssertEqual(EmblemEffects.outgoingDamageBonus(f.s, f.ctx, attacker: a, target: creep, source: .skill(.skill1)), 0.075, accuracy: 1e-9)
        XCTAssertEqual(EmblemEffects.outgoingDamageBonus(f.s, f.ctx, attacker: a, target: boss, source: .spell), 0, "狩猟印には効かない")
        XCTAssertEqual(EmblemEffects.outgoingDamageBonus(f.s, f.ctx, attacker: a, target: v, source: .basicAttack), 0)

        var (g, b, w) = duel(EmblemLoadout(.assassin, .rupture, .masterAssassin, .warCry), extraRed: "H006")
        XCTAssertEqual(EmblemEffects.outgoingDamageBonus(g.s, g.ctx, attacker: b, target: w, source: .basicAttack), 0.07, accuracy: 1e-9)
        // MLBB: 固定貫通は防御を 0 より下まで下げる（−60 まで）。貫通の分だけ防御を持たせて実効防御を 0 にし、倍率だけを見る
        g.s.units[w].stats.armor = g.s.units[b].stats.armorPenFlat
        XCTAssertEqual(g.s.units[b].stats.armorPenPct, 0, accuracy: 1e-12)
        XCTAssertEqual(hit(&g, b, w, 1000), 1070, accuracy: 1e-6)
        // もう 1 体の敵ヒーローが近くに来たら効かない
        let other = g.heroes(.red).first { $0 != w }!
        g.place(other, at: g.s.units[b].pos + Vec2(-300, 0))
        XCTAssertEqual(EmblemEffects.outgoingDamageBonus(g.s, g.ctx, attacker: b, target: w, source: .basicAttack), 0)
    }

    func testBargainHunterBuysAtNinetyFivePercent() {
        var (f, a, _) = duel(EmblemLoadout(.mage, .inspire, .bargainHunter, .lethalIgnition))
        f.s.units[a].hero!.gold = 10_000
        let item = f.master.item("EQ203")!
        let q = ItemSystem.quote(f.hero(a), itemID: "EQ203", ctx: f.ctx)
        XCTAssertEqual(q.cost, (item.priceGold * 0.95).rounded())
        f.s.units[a].hero!.emblem = nil
        XCTAssertEqual(ItemSystem.quote(f.hero(a), itemID: "EQ203", ctx: f.ctx).cost, item.priceGold)
    }

    func testPullYourselfTogetherShortensSpellAndItemActiveCooldowns() {
        var (f, a, _) = duel(EmblemLoadout(.support, .agility, .pullYourselfTogether, .focusingMark))
        f.s.units[a].hero!.spells = ["BS06", "BS12"]
        XCTAssertTrue(SpellSystem.cast(&f.s, f.ctx, heroIndex: a, spellIndex: 0, target: .none))
        let cd = f.master.spell("BS06")!.cooldownSec
        XCTAssertEqual(f.hero(a).spellCooldowns[0], cd * 0.88, accuracy: 1e-9)
        // キル・アシスト 3 回で 15%（8 スタックまで）
        f.s.units[a].hero!.emblemRuntime.takedowns = 3
        XCTAssertTrue(SpellSystem.cast(&f.s, f.ctx, heroIndex: a, spellIndex: 1, target: .none))
        XCTAssertEqual(f.hero(a).spellCooldowns[1], f.master.spell("BS12")!.cooldownSec * 0.85, accuracy: 1e-9)
        f.s.units[a].hero!.emblemRuntime.takedowns = 30
        XCTAssertEqual(EmblemEffects.spellCooldownMultiplier(f.hero(a)), 0.80, accuracy: 1e-9)
        // 装備のアクティブ（ナチュラルウィンド）
        f.s.units[a].hero!.items = ["EQ117"]
        let info = ItemEffects.activeInfo(f.hero(a), time: f.s.time, master: f.master)!
        ItemEffects.useActive(&f.s, f.ctx, heroIndex: a)
        XCTAssertEqual(f.hero(a).itemRuntime.readyTime(info.kind) - f.s.time, info.cooldown * 0.80, accuracy: 1e-9)
    }

    // MARK: - コア

    func testImpureRageAddsMaxHPDamageCappedOnNonHeroesAndRestores() {
        var (f, a, v) = duel(EmblemLoadout(.common, .thrill, .wildernessBlessing, .impureRage))
        f.s.units[a].hp = f.s.units[a].stats.maxHP * 0.5
        let hp0 = f.s.units[a].hp
        hit(&f, a, v, 100)
        XCTAssertEqual(extraDamage(f, to: v), 20_000 * 0.04, accuracy: 1e-6)
        // H002 は Energy なので HP を 1% 回復
        XCTAssertEqual(f.s.units[a].hp - hp0, f.s.units[a].stats.maxHP * 0.01, accuracy: 1e-6)
        // CD 5 秒
        f.s.events.removeAll()
        hit(&f, a, v, 100)
        XCTAssertEqual(extraDamage(f, to: v), 0)
        advance(&f, 5)
        // ヒーロー以外は最大 120
        let m = f.addMinion(.melee, team: .red, at: spot + Vec2(100, 0))
        f.s.units[m].stats.maxHP = 50_000
        f.s.units[m].hp = 50_000
        f.s.events.removeAll()
        hit(&f, a, m, 100)
        XCTAssertEqual(extraDamage(f, to: m), 120, accuracy: 1e-6)
        // 通常攻撃では働かない
        advance(&f, 5)
        f.s.events.removeAll()
        hit(&f, a, v, 100, .physical, .basicAttack)
        XCTAssertEqual(extraDamage(f, to: v), 0)

        // Mana のヒーロー（H004）は MP 2% を回復
        var (g, b, w) = duel(EmblemLoadout(.common, .thrill, .wildernessBlessing, .impureRage), attacker: "H004")
        g.s.units[b].resource = 0
        hit(&g, b, w, 100, .magic)
        XCTAssertEqual(g.s.units[b].resource, g.s.units[b].stats.maxResource * 0.02, accuracy: 1e-6)
        XCTAssertTrue(g.s.events.contains {
            if case .damage(let d) = $0, d.source == .item { return d.damageType == .magic }
            return false
        }, "魔法のヒーローの適応ダメージは魔法")
    }

    func testQuantumChargeOnBasicAttack() {
        var (f, a, v) = duel(EmblemLoadout(.marksman, .fatal, .masterAssassin, .quantumCharge))
        f.s.units[a].hp = 500
        hit(&f, a, v, 100, .physical, .skill(.skill1))
        XCTAssertNil(status(f, a, "emblem.quantumCharge"), "スキルでは働かない")
        hit(&f, a, v, 100, .physical, .basicAttack)
        XCTAssertEqual(status(f, a, "emblem.quantumCharge")?.magnitude ?? 0, 0.30, accuracy: 1e-9)
        XCTAssertEqual(status(f, a, "emblem.quantumCharge")?.remaining ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[a].hp, 500 + 75, accuracy: 1e-6, "Lv1 は 75")
        XCTAssertEqual(EmblemEffects.byLevel(15, 75, 180), 180, accuracy: 1e-9)
        XCTAssertEqual(EmblemEffects.byLevel(8, 162, 750), 162 + 42 * 7, accuracy: 1e-9)
        // CD 10 秒
        let hp1 = f.s.units[a].hp
        advance(&f, 9)
        hit(&f, a, v, 100, .physical, .basicAttack)
        XCTAssertEqual(f.s.units[a].hp, hp1, accuracy: 1e-6)
    }

    func testWarCryAfterThreeSeparateHits() {
        var (f, a, v) = duel(EmblemLoadout(.fighter, .thrill, .festivalOfBlood, .warCry))
        hit(&f, a, v, 50, .physical, .basicAttack)
        advance(&f, 0.5)
        // 同じスキルの何度ものダメージは 1 回
        hit(&f, a, v, 50, .physical, .skill(.skill2))
        hit(&f, a, v, 50, .physical, .skill(.skill2))
        XCTAssertNil(status(f, a, "emblem.warCry"))
        advance(&f, 0.5)
        hit(&f, a, v, 50, .physical, .basicAttack)
        let st = status(f, a, "emblem.warCry")
        XCTAssertEqual(st?.kind, .damageBoost)
        XCTAssertEqual(st?.magnitude ?? 0, 0.08, accuracy: 1e-9)
        XCTAssertEqual(st?.remaining ?? 0, 6, accuracy: 1e-9)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.damageBonus, 0.08, accuracy: 1e-9)
    }

    func testTemporalReignAcceleratesOtherCooldownsAfterTheUltimate() {
        var (f, a, v) = duel(EmblemLoadout(.assassin, .thrill, .seasonedHunter, .temporalReign))
        f.s.units[a].hero!.skillCooldowns = [0, 10, 10, 10]
        PassiveHooks.onSkillCast(&f.s, f.ctx, caster: a, slot: .ultimate)
        for _ in 0..<30 {
            f.s.tick += 1
            f.s.time = Double(f.s.tick) * Balance.dt
            SkillSystem.update(&f.s, f.ctx)
        }
        XCTAssertEqual(f.hero(a).skillCooldowns[1], 10 - 1.5, accuracy: 1e-6)
        XCTAssertEqual(f.hero(a).skillCooldowns[2], 10 - 1.5, accuracy: 1e-6)
        XCTAssertEqual(f.hero(a).skillCooldowns[3], 10 - 1, accuracy: 1e-6, "必殺技自身は速くならない")
        // 窓は 4 秒。キル・アシストで 2 秒延びる
        XCTAssertEqual(f.hero(a).emblemRuntime.until - f.s.time, 3, accuracy: 1e-6)
        _ = v
        EmblemEffects.onKillOrAssist(&f.s, hero: a)
        XCTAssertEqual(f.hero(a).emblemRuntime.until - f.s.time, 5, accuracy: 1e-6)
        // CD 20 秒の間は次の必殺技で開かない
        let until = f.hero(a).emblemRuntime.until
        advance(&f, 6)
        PassiveHooks.onSkillCast(&f.s, f.ctx, caster: a, slot: .ultimate)
        XCTAssertEqual(f.hero(a).emblemRuntime.until, until)
    }

    func testConcussiveBlastAfterBasicAttack() {
        var (f, a, v) = duel(EmblemLoadout(.tank, .vitality, .tenacity, .concussiveBlast))
        let near = f.addMinion(.melee, team: .red, at: f.s.units[v].pos + Vec2(0, 100))
        f.s.units[near].stats.maxHP = 5000
        f.s.units[near].hp = 5000
        let expected = 100 + 0.07 * f.s.units[a].stats.maxHP
        CombatSystem.basicAttackLanded(&f.s, f.ctx, attacker: a, target: v, dealt: 0)
        XCTAssertEqual(extraDamage(f, to: v), expected, accuracy: 1e-6)
        XCTAssertGreaterThan(extraDamage(f, to: near), 0, "周りの敵にも")
        f.s.events.removeAll()
        CombatSystem.basicAttackLanded(&f.s, f.ctx, attacker: a, target: v, dealt: 0)
        XCTAssertEqual(extraDamage(f, to: v), 0, "CD 15 秒")
    }

    func testKillingSpreeHealsAndResetsOnKill() {
        var (f, a, v) = duel(EmblemLoadout(.assassin, .rupture, .masterAssassin, .killingSpree))
        let mx = f.s.units[a].stats.maxHP
        f.s.units[a].hp = mx * 0.5
        hit(&f, a, v, 100)
        XCTAssertEqual(f.s.units[a].hp, mx * 0.5, accuracy: 1e-6, "敵の HP が 30% 以上なら働かない")
        f.s.units[v].hp = 20_000 * 0.25
        hit(&f, a, v, 100)
        XCTAssertEqual(f.s.units[a].hp, mx * 0.5 + mx * 0.5 * 0.15, accuracy: 1e-6)
        XCTAssertEqual(status(f, a, "emblem.killingSpree")?.magnitude ?? 0, 0.2, accuracy: 1e-9)
        XCTAssertGreaterThan(f.hero(a).emblemRuntime.readyAt, f.s.time + 29)
        // 敵ヒーローを倒すと CD がリセット
        f.s.units[v].hero!.recentDamagers = [DamageRecord(sourceID: f.id(a), time: f.s.time)]
        f.kill(v, by: f.id(a))
        XCTAssertEqual(f.hero(a).emblemRuntime.readyAt, 0)
        XCTAssertEqual(f.hero(a).emblemRuntime.takedowns, 1)
    }

    func testLethalIgnitionAfterThreeBigHitsWithinFiveSeconds() {
        var (f, a, v) = duel(EmblemLoadout(.mage, .rupture, .bargainHunter, .lethalIgnition), attacker: "H004")
        // MLBB: 固定の魔法貫通は魔防を 0 より下まで下げる（−60 まで）。貫通の分だけ魔防を持たせて実効魔防を 0 にする
        f.s.units[v].stats.magicResist = f.s.units[a].stats.magicPenFlat
        XCTAssertEqual(f.s.units[a].stats.magicPenPct, 0, accuracy: 1e-12)
        // 最大 HP 20000 の 7% = 1400 を超えるダメージ
        hit(&f, a, v, 1300, .magic)
        advance(&f, 1)
        hit(&f, a, v, 1500, .magic)
        advance(&f, 1)
        hit(&f, a, v, 1500, .magic)
        XCTAssertEqual(extraDamage(f, to: v), 0, "大きなダメージは 2 回だけ")
        advance(&f, 1)
        hit(&f, a, v, 1500, .magic)
        XCTAssertEqual(extraDamage(f, to: v), 162, accuracy: 1e-6, "Lv1 は 162")
        f.s.events.removeAll()
        for _ in 0..<3 { advance(&f, 1); hit(&f, a, v, 1500, .magic) }
        XCTAssertEqual(extraDamage(f, to: v), 0, "CD 15 秒")
    }

    func testBraveSmiteHealsOnSkillDamageToHeroes() {
        var (f, a, v) = duel(EmblemLoadout(.fighter, .firmness, .festivalOfBlood, .braveSmite))
        let mx = f.s.units[a].stats.maxHP
        f.s.units[a].hp = mx * 0.5
        // 吸収（ファイターの混合吸収 10%、スキルは血の祭典 6% も）の分を除いて比べる
        hit(&f, a, v, 100, .physical, .basicAttack)
        XCTAssertEqual(f.s.units[a].hp, mx * 0.5 + 100 * f.s.units[a].stats.lifesteal, accuracy: 1e-6, "通常攻撃では働かない")
        let hp0 = f.s.units[a].hp
        hit(&f, a, v, 100)
        XCTAssertEqual(f.s.units[a].stats.spellVamp, 0.16, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[a].hp, hp0 + mx * 0.05 + 100 * 0.16, accuracy: 1e-6)
        // CD 6 秒
        let hp1 = f.s.units[a].hp
        hit(&f, a, v, 100)
        XCTAssertEqual(f.s.units[a].hp, hp1 + 100 * 0.16, accuracy: 1e-6)
    }

    func testFocusingMarkBoostsAlliesAgainstTheMarkedHero() {
        var (f, a, v) = duel(EmblemLoadout(.support, .agility, .pullYourselfTogether, .focusingMark), extraBlue: "H014")
        let b = f.heroes(.blue).first { $0 != a }!
        f.place(b, at: f.s.units[v].pos + Vec2(-100, 0))
        XCTAssertEqual(hit(&f, b, v, 1000), 1000, accuracy: 1e-6)
        hit(&f, a, v, 10)
        XCTAssertEqual(hit(&f, b, v, 1000), 1060, accuracy: 1e-6)
        XCTAssertEqual(status(f, b, EmblemEffects.focusTag)?.magnitude ?? 0, 0.10, accuracy: 1e-9)
        advance(&f, 3.1)
        XCTAssertEqual(hit(&f, b, v, 1000), 1000, accuracy: 1e-6, "3 秒で切れる")
    }

    func testWeaknessFinderSlowsAndCooldownShrinksPerAttack() {
        var (f, a, v) = duel(EmblemLoadout(.marksman, .fatal, .weaponMaster, .weaknessFinder))
        CombatSystem.basicAttackLanded(&f.s, f.ctx, attacker: a, target: v, dealt: 0)
        let slow = f.s.units[v].statuses.first { $0.kind == .slow && $0.tag == "emblem.weaknessFinder" }
        let atk = f.s.units[v].statuses.first { $0.kind == .attackSpeedBoost && $0.tag == "emblem.weaknessFinder" }
        XCTAssertEqual(slow?.magnitude ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(atk?.magnitude ?? 0, -0.3, accuracy: 1e-9)
        XCTAssertEqual(slow?.remaining ?? 0, 1, accuracy: 1e-9)
        let t0 = f.s.time
        XCTAssertEqual(f.hero(a).emblemRuntime.readyAt, t0 + 10, accuracy: 1e-9)
        // 通常攻撃 1 回で 1 秒縮む（最短 3 秒）
        for _ in 0..<3 { CombatSystem.basicAttackLanded(&f.s, f.ctx, attacker: a, target: v, dealt: 0) }
        XCTAssertEqual(f.hero(a).emblemRuntime.readyAt, t0 + 7, accuracy: 1e-9)
        for _ in 0..<10 { CombatSystem.basicAttackLanded(&f.s, f.ctx, attacker: a, target: v, dealt: 0) }
        XCTAssertEqual(f.hero(a).emblemRuntime.readyAt, t0 + 3, accuracy: 1e-9)
    }

    // MARK: - 決定論

    func testBotMatchWithEmblemsIsDeterministic() {
        let a = Simulation(config: MatchFactory.botMatch(difficulty: .hard, seed: 77))
        let b = Simulation(config: MatchFactory.botMatch(difficulty: .hard, seed: 77))
        a.runHeadless(maxTime: 150)
        b.runHeadless(maxTime: 150)
        XCTAssertEqual(a.state.stateHash(), b.state.stateHash())
        XCTAssertEqual(a.state.rng, b.state.rng)
        for i in a.state.heroIndices {
            XCTAssertEqual(a.state.units[i].hero?.emblemRuntime, b.state.units[i].hero?.emblemRuntime)
            XCTAssertNotNil(a.state.units[i].hero?.emblem)
        }
    }
}
