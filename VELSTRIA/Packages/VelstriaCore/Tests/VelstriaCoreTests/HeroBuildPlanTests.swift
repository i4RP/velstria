import XCTest
@testable import VelstriaCore

/// 担当: ヒーロー別の推奨ビルド（Mobile Legends の定番ビルドに寄せた上書き）。
final class HeroBuildPlanTests: XCTestCase {
    func testHeroBuildsFollowTheirPlanAndAreComplete() throws {
        let m = MasterData.shared
        XCTAssertFalse(ItemSystem.heroBuildPlans.isEmpty)
        for (heroID, plan) in ItemSystem.heroBuildPlans.sorted(by: { $0.key < $1.key }) {
            let hero = try XCTUnwrap(m.hero(heroID), heroID)
            let build = ItemSystem.recommendedBuild(heroID: heroID, role: hero.role, master: m)
            XCTAssertEqual(plan.count, 6, heroID)
            XCTAssertEqual(build.count, 6, heroID)
            XCTAssertEqual(Set(build).count, 6, "\(heroID) は重複なし")
            XCTAssertEqual(build.compactMap { m.item($0)?.category }, plan, "\(heroID) はカテゴリの順どおり")
            XCTAssertTrue(build.allSatisfy { m.item($0)?.tier == 3 }, "\(heroID) は完成品")
            XCTAssertLessThanOrEqual(plan.filter { $0 == .movement }.count, 1, "\(heroID): 靴は 1 つまで")
            XCTAssertEqual(build, ItemSystem.recommendedBuild(heroID: heroID, role: hero.role, master: m), "決定論")
        }
    }

    func testPlanFallsBackToRoleWhenHeroHasNoOverrideOrRoleDiffers() throws {
        let m = MasterData.shared
        // 上書きの無いヒーローはロール別
        XCTAssertNil(ItemSystem.heroBuildPlans["H001"])
        XCTAssertEqual(ItemSystem.buildPlan(heroID: "H001", role: .vanguard, master: m), ItemSystem.buildPlan(role: .vanguard))
        // 上書きのあるヒーローでも、ロールが食い違う（テストでの差し替え）ならロール別
        let hero = try XCTUnwrap(m.hero("H028"))
        XCTAssertEqual(hero.role, .assassin)
        XCTAssertEqual(ItemSystem.buildPlan(heroID: "H028", role: .duelist, master: m), ItemSystem.buildPlan(role: .duelist))
    }
}
