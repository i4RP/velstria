import XCTest
@testable import VelstriaCore

/// Gold/EXP レーンの割当と序盤のミニオン報酬補正（参照仕様 §3.1）。
final class LaneRoleTests: XCTestCase {
    private let spot = Vec2(6000, 6000)

    func testExpLaneIsTheSideLaneNearestTheFirstBoss() {
        let map = MapDefinition.standard
        // 最初のボス（星喰竜 2:00）は (8300, 3700)。bot レーンの方が近い。
        XCTAssertEqual(map.expLane, .bot)
        XCTAssertEqual(map.goldLane, .top)
    }

    func testPositionsFollowTheLaneRoles() {
        let map = MapDefinition.standard
        XCTAssertEqual(map.lane(for: .top), map.expLane)
        XCTAssertEqual(map.lane(for: .carry), map.goldLane)
        XCTAssertEqual(map.lane(for: .support), map.goldLane)
        XCTAssertEqual(map.lane(for: .mid), .mid)
        XCTAssertNil(map.lane(for: .jungle))
    }

    func testSingleLaneMapKeepsTheLegacyAssignment() {
        let map = MapDefinition.brawl
        XCTAssertNil(map.expLane)
        XCTAssertNil(map.goldLane)
        XCTAssertEqual(map.lane(for: .top), .top)
        XCTAssertEqual(map.lane(for: .carry), .bot)
    }

    func testGoldLaneMinionGivesMoreGoldEarly() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0]
        f.place(a, at: spot)
        let goldLane = f.ctx.map.goldLane!
        f.s.time = 100
        let gold0 = f.hero(a).gold
        let m = f.addMinion(.melee, team: .red, at: spot, lane: goldLane)
        f.kill(m, by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold0, Balance.Economy.minionGold(.melee, at: 100) * (1 + Balance.Economy.goldLaneGoldBonus),
                       accuracy: 1e-9)
        // XP は補正なし
        XCTAssertEqual(f.hero(a).xp, 60, accuracy: 1e-9)
    }

    func testExpLaneMinionGivesMoreXPEarly() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0]
        f.place(a, at: spot)
        f.s.time = 100
        let gold0 = f.hero(a).gold
        let m = f.addMinion(.melee, team: .red, at: spot, lane: f.ctx.map.expLane!)
        f.kill(m, by: f.id(a))
        XCTAssertEqual(f.hero(a).xp, 60 * (1 + Balance.Economy.expLaneXPBonus), accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).gold - gold0, Balance.Economy.minionGold(.melee, at: 100), accuracy: 1e-9)
    }

    func testLaneBonusEndsAndMidIsUnaffected() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0]
        f.place(a, at: spot)
        // 補正終了後
        f.s.time = Balance.Economy.laneBonusEnd
        var gold0 = f.hero(a).gold
        f.kill(f.addMinion(.melee, team: .red, at: spot, lane: f.ctx.map.goldLane!), by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold0, Balance.Economy.minionGold(.melee, at: Balance.Economy.laneBonusEnd), accuracy: 1e-9)
        // 序盤でも中央レーンは補正なし
        f.s.time = 100
        gold0 = f.hero(a).gold
        f.kill(f.addMinion(.melee, team: .red, at: spot, lane: .mid), by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold0, Balance.Economy.minionGold(.melee, at: 100), accuracy: 1e-9)
    }
}
