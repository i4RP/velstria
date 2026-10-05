import XCTest
@testable import VelstriaCore

/// 乱闘（単レーン・ジャングル無し・経済加速）の検証。
final class BrawlTests: XCTestCase {
    func testBrawlMapIsValid() {
        let m = MapDefinition.brawl
        XCTAssertTrue(m.validationIssues().isEmpty, "検証エラー: \(m.validationIssues())")
        XCTAssertEqual(m.lanes, [.mid])
        XCTAssertTrue(m.camps.isEmpty, "乱闘はジャングル無し")
        XCTAssertEqual(m.lanePaths.count, 3, "インデックス安全のため lanePaths は 3 要素")
        XCTAssertTrue(m.towers.contains { $0.isCore && $0.team == .blue })
        XCTAssertTrue(m.towers.contains { $0.isCore && $0.team == .red })
        XCTAssertEqual(m.towers.filter { !$0.isCore && $0.lane == .mid && $0.team == .blue }.count, 3)
        XCTAssertEqual(m.towers.filter { !$0.isCore && $0.lane == .mid && $0.team == .red }.count, 3)
        // top / bot には塔が無い
        XCTAssertTrue(m.towers.filter { $0.lane == .top || $0.lane == .bot }.isEmpty)
    }

    func testMapResolver() {
        XCTAssertEqual(MapDefinition.map(for: .brawl), MapDefinition.brawl)
        XCTAssertEqual(MapDefinition.map(for: .standard), MapDefinition.standard)
        XCTAssertEqual(MapDefinition.map(for: .ranked), MapDefinition.standard)
        XCTAssertEqual(MapDefinition.map(for: .custom), MapDefinition.standard)
    }

    func testStandardMapUnchanged() {
        // 既存モードのマップ・レーンは従来どおり。
        XCTAssertEqual(MapDefinition.standard.lanes, [.top, .mid, .bot])
        XCTAssertTrue(MapDefinition.standard.validationIssues().isEmpty)
    }

    func testBrawlMatchComposition() {
        let cfg = MatchFactory.brawlMatch(humanHeroID: "H001", humanName: "T", seed: 7)
        XCTAssertEqual(cfg.mode, .brawl)
        XCTAssertEqual(cfg.players.count, 10)
        XCTAssertEqual(cfg.players.filter { $0.team == .blue }.count, 5)
        XCTAssertEqual(cfg.players.filter { $0.team == .red }.count, 5)
        XCTAssertEqual(cfg.players.filter { $0.controller == .human }.count, 1)
        XCTAssertFalse(cfg.players.contains { $0.spells.contains("BS05") }, "乱闘は狩猟印を付けない")
        XCTAssertEqual(cfg.maxDuration, 15 * 60, accuracy: 1)
    }

    func testBrawlRandomHeroWhenUnspecified() {
        let a = MatchFactory.brawlMatch(humanName: "T", seed: 123)
        XCTAssertNotNil(a.humanSlot)
        XCTAssertFalse(a.humanSlot!.heroID.isEmpty)
    }

    func testEconomyScales() {
        XCTAssertEqual(Balance.Economy.goldScale(.brawl), 2.0)
        XCTAssertEqual(Balance.Economy.goldScale(.standard), 1.0)
        XCTAssertEqual(Balance.Economy.xpScale(.brawl), 2.0)
        XCTAssertEqual(Balance.Economy.xpScale(.standard), 1.0)
    }

    func testBrawlSimIsDeterministic() {
        let cfg = MatchFactory.brawlMatch(humanHeroID: "H002", humanName: "T", seed: 42)
        let map = MapDefinition.map(for: cfg.mode)
        let a = Simulation(config: cfg, map: map)
        let b = Simulation(config: cfg, map: map)
        for _ in 0..<300 { a.step(commands: []); b.step(commands: []) }
        XCTAssertEqual(a.state.stateHash(), b.state.stateHash())
    }

    func testBrawlSpawnsMinionsOnlyOnMid() {
        let cfg = MatchFactory.brawlMatch(humanHeroID: "H002", humanName: "T", seed: 9)
        let sim = Simulation(config: cfg, map: MapDefinition.brawl)
        // 最初のウェーブが湧くまで進める。
        var ticks = 0
        while ticks < 70 * 30, !sim.isEnded,
              !sim.state.units.contains(where: { $0.kind == .minion }) {
            sim.step(commands: [])
            ticks += 1
        }
        let minions = sim.state.units.filter { $0.kind == .minion }
        XCTAssertFalse(minions.isEmpty, "乱闘でもミニオンは湧く")
        let lanes = Set(minions.compactMap { $0.minion?.lane })
        XCTAssertEqual(lanes, [.mid], "乱闘のミニオンは mid のみ")
    }
}
