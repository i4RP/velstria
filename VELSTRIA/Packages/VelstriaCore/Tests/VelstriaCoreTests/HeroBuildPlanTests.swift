import XCTest
@testable import VelstriaCore

/// 担当: 推奨ビルド（ロール別・ヒーロー別の具体的な装備 ID の列。Mobile Legends の定番構成）と、
/// H025〜H034 のバトルプラン（3 つずつ。「有効」のプランが推奨ビルド、人間は選んだプラン）。
final class HeroBuildPlanTests: XCTestCase {
    /// 推奨ビルドとして正しい形か: 6 個・重複なし・マスターにある・消耗品なし・靴は 1 足（Tier 2）・残りは完成品。
    /// 靴の位置は MLBB のバトルプランの購入順どおり（セイバーはハンターストライクの次に靴）なので先頭とは限らない。
    private func assertWellFormed(_ build: [String], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let m = MasterData.shared
        XCTAssertEqual(build.count, Balance.itemSlots, label, file: file, line: line)
        XCTAssertEqual(Set(build).count, build.count, "\(label) は重複なし", file: file, line: line)
        let items = build.compactMap { m.item($0) }
        XCTAssertEqual(items.count, build.count, "\(label) はマスターにある装備だけ", file: file, line: line)
        XCTAssertFalse(items.contains { $0.isConsumable }, "\(label) にポーションは入れない", file: file, line: line)
        XCTAssertEqual(items.filter(\.isBoots).count, 1, "\(label): 靴は 1 足", file: file, line: line)
        XCTAssertFalse(items.contains { $0.itemID == Balance.Gear.baseBootsID }, "\(label): 靴は Tier 2", file: file, line: line)
        XCTAssertTrue(items.filter { !$0.isBoots }.allSatisfy { $0.tier == 3 }, "\(label): 靴以外は完成品", file: file, line: line)
    }

    func testRoleBuildsAreWellFormed() {
        let m = MasterData.shared
        for role in Role.allCases {
            let build = ItemSystem.recommendedBuild(role: role, master: m)
            XCTAssertEqual(build, ItemSystem.roleBuilds[role], "\(role): マスターから落ちた ID は無い")
            assertWellFormed(build, "\(role)")
            XCTAssertEqual(build, ItemSystem.recommendedBuild(role: role, master: m), "決定論")
        }
    }

    func testEveryHeroHasAWellFormedBuild() throws {
        let m = MasterData.shared
        XCTAssertEqual(m.allHeroes.count, 34)
        for hero in m.allHeroes {
            let build = ItemSystem.recommendedBuild(heroID: hero.heroID, role: hero.role, master: m)
            assertWellFormed(build, hero.heroID)
            if let own = ItemSystem.heroBuilds[hero.heroID] {
                XCTAssertEqual(build, own, "\(hero.heroID) は固有のビルド")
            } else {
                XCTAssertEqual(build, ItemSystem.recommendedBuild(role: hero.role, master: m), "\(hero.heroID) はロール別")
            }
        }
        // 固有ビルドの鍵はすべて実在するヒーロー（ロールが合わない上書きは使われないので無意味）
        for (heroID, build) in ItemSystem.heroBuilds {
            XCTAssertNotNil(m.hero(heroID), heroID)
            XCTAssertTrue(build.allSatisfy { m.item($0) != nil }, heroID)
        }
    }

    func testBuildFallsBackToRoleWhenHeroHasNoOverrideOrRoleDiffers() throws {
        let m = MasterData.shared
        // 上書きの無いヒーローはロール別
        XCTAssertNil(ItemSystem.heroBuilds["H001"])
        XCTAssertEqual(ItemSystem.recommendedBuild(heroID: "H001", role: .vanguard, master: m),
                       ItemSystem.recommendedBuild(role: .vanguard, master: m))
        // 上書きのあるヒーローでも、ロールが食い違う（テストでの差し替え）ならロール別
        let hero = try XCTUnwrap(m.hero("H028"))
        XCTAssertEqual(hero.role, .assassin)
        XCTAssertNotNil(ItemSystem.heroBuilds["H028"])
        XCTAssertEqual(ItemSystem.recommendedBuild(heroID: "H028", role: .duelist, master: m),
                       ItemSystem.recommendedBuild(role: .duelist, master: m))
        // HeroData 経由も同じ
        let f = EconomyFixture.standard()
        var h = f.hero(f.human)
        h.heroID = "H028"
        h.role = .assassin
        XCTAssertEqual(ItemSystem.recommendedBuild(for: h, master: m), ItemSystem.heroBuilds["H028"])
        // 祝福は靴に付くので、狩猟印の有無で装備の並びは変わらない
        h.spells = [Balance.Economy.smiteSpellID, "BS01"]
        XCTAssertEqual(ItemSystem.recommendedBuild(for: h, master: m), ItemSystem.heroBuilds["H028"])
    }

    /// 日本語クライアントの推奨: フランコ（H034）はラピッドブーツ（激励）。他のサポートは役割別（恩恵）、狩猟印は炎撃のまま。
    func testFrancoRoamBlessingFollowsTheJapaneseClient() {
        XCTAssertEqual(GearOption.defaultOption(for: .roam, role: .support, heroID: "H034"), .encourage)
        XCTAssertEqual(GearOption.defaultOption(for: .roam, role: .support, heroID: "H011"), .favor)
        XCTAssertEqual(GearOption.defaultOption(for: .jungle, role: .support, heroID: "H034"), .flame)
        XCTAssertEqual(ItemSystem.heroBuilds["H034"], ["EQ402", "EQ113", "EQ114", "EQ308", "EQ306", "EQ304"])
        XCTAssertEqual(ItemSystem.heroBuilds["H026"], ["EQ404", "EQ203", "EQ204", "EQ207", "EQ211", "EQ210"])
        XCTAssertEqual(ItemSystem.heroBuilds["H031"], ["EQ404", "EQ207", "EQ204", "EQ211", "EQ201", "EQ210"])
        XCTAssertEqual(ItemSystem.heroBuilds["H025"], ["EQ403", "EQ108", "EQ110", "EQ111", "EQ101", "EQ103"])
        // セイバー: 1 つ目はハンターストライク、靴（マジックブーツ）は 2 つ目
        XCTAssertEqual(ItemSystem.heroBuilds["H028"], ["EQ105", "EQ405", "EQ116", "EQ109", "EQ112", "EQ106"])
        XCTAssertEqual(ItemSystem.heroBuilds["H029"], ["EQ402", "EQ305", "EQ308", "EQ114", "EQ301", "EQ304"])
        XCTAssertEqual(ItemSystem.heroBuilds["H033"], ["EQ406", "EQ116", "EQ104", "EQ109", "EQ106", "EQ312"])
    }

    // MARK: - バトルプラン（1 ヒーロー 3 つ。docs/BUILD_PLANS.md）

    /// バトルプランのあるヒーロー（MLBB の元ヒーローを写した H025〜H034）。
    private static let planHeroes = (25...34).map { "H0\($0)" }

    func testEveryKitHeroHasThreeWellFormedPlans() {
        let m = MasterData.shared
        XCTAssertEqual(Set(ItemSystem.heroPlans.keys), Set(Self.planHeroes), "プランは H025〜H034 だけ")
        XCTAssertEqual(Set(ItemSystem.defaultPlanIndex.keys), Set(Self.planHeroes))
        for heroID in Self.planHeroes {
            XCTAssertNotNil(m.hero(heroID), heroID)
            let plans = ItemSystem.plans(forHero: heroID)
            XCTAssertEqual(plans.count, 3, "\(heroID) は 3 プラン")
            for (k, plan) in plans.enumerated() {
                let label = "\(heroID) プラン\(k + 1)「\(plan.name)」"
                assertWellFormed(plan.items, label)
                XCTAssertFalse(plan.name.isEmpty, label)
                XCTAssertFalse(plan.nameEN.isEmpty, label)
                XCTAssertTrue(plan.tags.count <= 2 && plan.tags.allSatisfy { !$0.isEmpty }, "\(label): タグは 0〜2 個")
                if let spell = plan.spellHint { XCTAssertFalse(spell.isEmpty, label) }
            }
            let k = ItemSystem.defaultPlanIndex[heroID]
            XCTAssertTrue(k.map { plans.indices.contains($0) } == true, "\(heroID) の「有効」の添字が範囲内")
        }
        // プランの無いヒーロー
        XCTAssertTrue(ItemSystem.plans(forHero: "H001").isEmpty)
        XCTAssertNil(ItemSystem.planIndex(heroID: "H001", chosen: 0))
        XCTAssertNil(ItemSystem.plan(heroID: "H001", chosen: nil))
    }

    func testHeroBuildIsTheActivePlan() {
        let m = MasterData.shared
        XCTAssertEqual(Set(ItemSystem.heroBuilds.keys), Set(ItemSystem.heroPlans.keys))
        for heroID in Self.planHeroes {
            let plans = ItemSystem.plans(forHero: heroID)
            guard let k = ItemSystem.defaultPlanIndex[heroID], plans.indices.contains(k),
                  let role = m.hero(heroID)?.role else {
                XCTFail(heroID)
                continue
            }
            XCTAssertEqual(ItemSystem.heroBuilds[heroID], plans[k].items, "\(heroID): 推奨ビルド = 「有効」のプラン")
            XCTAssertEqual(ItemSystem.planIndex(heroID: heroID, chosen: nil), k)
            XCTAssertEqual(ItemSystem.recommendedBuild(heroID: heroID, role: role, master: m), plans[k].items)
        }
        // 日本語クライアントで「有効」だったプラン（ジャルド = 爆発力、ライナ = 攻撃速度＆クリティカル率、ディアス = 爆発力）
        XCTAssertEqual(ItemSystem.plan(heroID: "H027", chosen: nil)?.name, "爆発力")
        XCTAssertEqual(ItemSystem.heroBuilds["H027"], ["EQ402", "EQ108", "EQ119", "EQ102", "EQ101", "EQ110"])
        XCTAssertEqual(ItemSystem.plan(heroID: "H030", chosen: nil)?.name, "攻撃速度＆クリティカル率")
        XCTAssertEqual(ItemSystem.heroBuilds["H030"], ["EQ407", "EQ108", "EQ110", "EQ111", "EQ101", "EQ103"])
        XCTAssertEqual(ItemSystem.plan(heroID: "H032", chosen: nil)?.name, "爆発力")
        XCTAssertEqual(ItemSystem.heroBuilds["H032"], ["EQ406", "EQ105", "EQ116", "EQ302", "EQ301", "EQ308"])
        XCTAssertEqual(ItemSystem.plan(heroID: "H025", chosen: nil)?.name, "ヒット＆アウェイ")
        XCTAssertEqual(ItemSystem.plan(heroID: "H033", chosen: nil)?.name, "DPS")
    }

    func testChosenPlanOverridesTheActivePlan() throws {
        let m = MasterData.shared
        let plans = ItemSystem.plans(forHero: "H027")
        let role = try XCTUnwrap(m.hero("H027")?.role)
        for k in plans.indices {
            XCTAssertEqual(ItemSystem.planIndex(heroID: "H027", chosen: k), k)
            XCTAssertEqual(ItemSystem.recommendedBuild(heroID: "H027", role: role, master: m, plan: k), plans[k].items)
        }
        // 範囲外・負の添字は「有効」のプラン
        for bad in [-1, 3, 99] {
            XCTAssertEqual(ItemSystem.planIndex(heroID: "H027", chosen: bad), 1, "\(bad)")
        }
        // ロールが食い違う時は選んだプランでもロール別
        XCTAssertEqual(ItemSystem.recommendedBuild(heroID: "H027", role: .support, master: m, plan: 0),
                       ItemSystem.recommendedBuild(role: .support, master: m))
        // プランの無いヒーローは選んでもロール別
        XCTAssertEqual(ItemSystem.recommendedBuild(heroID: "H001", role: .vanguard, master: m, plan: 2),
                       ItemSystem.recommendedBuild(role: .vanguard, master: m))
        // HeroData 経由: buildPlan が推奨ビルドとおすすめ購入を決める
        let f = EconomyFixture.standard()
        var h = f.hero(f.human)
        h.heroID = "H027"
        h.role = role
        h.items = []
        h.buildPlan = nil
        XCTAssertEqual(ItemSystem.recommendedBuild(for: h, master: m), plans[1].items)
        h.buildPlan = 0
        XCTAssertEqual(ItemSystem.recommendedBuild(for: h, master: m), plans[0].items)
        h.buildPlan = 7
        XCTAssertEqual(ItemSystem.recommendedBuild(for: h, master: m), plans[1].items)
    }

    /// 人間が選んだプランは試合の構成 → HeroData に入り、その人間だけの推奨ビルドになる（AI は「有効」のプラン）。
    func testChosenPlanReachesOnlyTheHumanInAMatch() throws {
        let m = MasterData.shared
        let config = MatchFactory.standardMatch(humanHeroID: "H027", humanName: "P", humanBuildPlan: 2, seed: 42)
        let human = try XCTUnwrap(config.humanSlot)
        XCTAssertEqual(human.buildPlan, 2)
        XCTAssertTrue(config.players.filter { $0.controller == .bot }.allSatisfy { $0.buildPlan == nil }, "AI は選ばない")
        XCTAssertNil(MatchFactory.standardMatch(humanHeroID: "H027", humanName: "P", seed: 42).humanSlot?.buildPlan)
        let sim = Simulation(config: config)
        var humans = 0
        for u in sim.state.units {
            guard let h = u.hero else { continue }
            if h.controller == .human {
                humans += 1
                XCTAssertEqual(h.buildPlan, 2)
                XCTAssertEqual(ItemSystem.recommendedBuild(for: h, master: m), ItemSystem.plans(forHero: "H027")[2].items)
            } else {
                XCTAssertNil(h.buildPlan, h.heroID)
                XCTAssertEqual(ItemSystem.recommendedBuild(for: h, master: m),
                               ItemSystem.recommendedBuild(heroID: h.heroID, role: h.role, master: m), h.heroID)
                if let own = ItemSystem.heroBuilds[h.heroID] {
                    XCTAssertEqual(ItemSystem.recommendedBuild(for: h, master: m), own, "\(h.heroID) の AI は「有効」のプラン")
                }
            }
        }
        XCTAssertEqual(humans, 1)
        // 乱闘・カスタム・練習場・オンラインの構成も同じ値を人間の枠へ入れる
        XCTAssertEqual(MatchFactory.brawlMatch(humanHeroID: "H030", humanName: "P", humanBuildPlan: 1, seed: 3).humanSlot?.buildPlan, 1)
        XCTAssertEqual(MatchFactory.customMatch(humanHeroID: "H030", humanBuildPlan: 1, seed: 3).humanSlot?.buildPlan, 1)
        XCTAssertEqual(MatchFactory.practiceMatch(humanHeroID: "H030", humanName: "P", options: PracticeOptions(),
                                                  humanBuildPlan: 0, seed: 3).humanSlot?.buildPlan, 0)
        let online = MatchFactory.onlineMatch(humans: [OnlineHumanSlot(team: .blue, position: .mid, heroID: "H031",
                                                                        displayName: "P", buildPlan: 2)], seed: 5)
        XCTAssertEqual(online.players.first { $0.controller == .human }?.buildPlan, 2)
        XCTAssertTrue(online.players.filter { $0.controller == .bot }.allSatisfy { $0.buildPlan == nil })
    }

    /// 後から足した buildPlan は任意の値: 旧版の構成（キーが無い）は nil として読み、値があれば往復で保つ。
    func testBuildPlanIsOptionalInSavedConfigs() throws {
        let slot = PlayerSlot(team: .blue, heroID: "H025", controller: .human, position: .carry, displayName: "P")
        let old = try JSONEncoder().encode(slot)
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("buildPlan"), "nil は書かない（旧版と同じ形）")
        XCTAssertNil(try JSONDecoder().decode(PlayerSlot.self, from: old).buildPlan)
        var chosen = slot
        chosen.buildPlan = 1
        let data = try JSONEncoder().encode(chosen)
        XCTAssertEqual(try JSONDecoder().decode(PlayerSlot.self, from: data).buildPlan, 1)
        let onlineOld = try JSONEncoder().encode(OnlineHumanSlot(team: .red, position: .top, heroID: "H029", displayName: "Q"))
        XCTAssertNil(try JSONDecoder().decode(OnlineHumanSlot.self, from: onlineOld).buildPlan)
    }
}
