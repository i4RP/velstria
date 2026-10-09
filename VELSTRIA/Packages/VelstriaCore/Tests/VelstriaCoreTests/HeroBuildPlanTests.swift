import XCTest
@testable import VelstriaCore

/// 担当: 推奨ビルド（ロール別・ヒーロー別の具体的な装備 ID の列。Mobile Legends の定番構成）。
final class HeroBuildPlanTests: XCTestCase {
    /// 推奨ビルドとして正しい形か: 6 個・重複なし・マスターにある・消耗品なし・靴は先頭の 1 足だけ・残りは完成品。
    private func assertWellFormed(_ build: [String], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let m = MasterData.shared
        XCTAssertEqual(build.count, Balance.itemSlots, label, file: file, line: line)
        XCTAssertEqual(Set(build).count, build.count, "\(label) は重複なし", file: file, line: line)
        let items = build.compactMap { m.item($0) }
        XCTAssertEqual(items.count, build.count, "\(label) はマスターにある装備だけ", file: file, line: line)
        XCTAssertFalse(items.contains { $0.isConsumable }, "\(label) にポーションは入れない", file: file, line: line)
        XCTAssertEqual(items.filter(\.isBoots).count, 1, "\(label): 靴は 1 足", file: file, line: line)
        XCTAssertEqual(items.first?.isBoots, true, "\(label): 靴から買う", file: file, line: line)
        XCTAssertNotEqual(items.first?.itemID, Balance.Gear.baseBootsID, "\(label): 靴は Tier 2", file: file, line: line)
        XCTAssertTrue(items.dropFirst().allSatisfy { $0.tier == 3 }, "\(label): 靴以外は完成品", file: file, line: line)
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
        XCTAssertEqual(m.heroes.count, 34)
        for hero in m.heroes {
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
}
