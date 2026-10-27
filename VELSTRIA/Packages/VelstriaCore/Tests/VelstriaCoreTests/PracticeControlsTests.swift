import XCTest
@testable import VelstriaCore

final class PracticeControlsTests: XCTestCase {
    private func fixture(infiniteGold: Bool = true, tutorial: Bool = false) -> EconomyFixture {
        EconomyFixture(config: MatchFactory.practiceMatch(
            humanHeroID: "H025", humanName: "Practice",
            options: PracticeOptions(infiniteGold: infiniteGold, spawnMinions: false, spawnDummies: false),
            tutorial: tutorial, seed: 17))
    }

    private func send(_ command: PlayerCommand, to f: inout EconomyFixture, heroIndex: Int? = nil) {
        let input = HeroCommand(heroID: f.id(heroIndex ?? f.human), command: command)
        CommandSystem.apply([input], &f.s, f.ctx)
    }

    func testLevelCanBeRaisedLoweredAndSkillsReallocatedWithinLimits() {
        var f = fixture()
        let i = f.human
        let initialHP = f.s.units[i].stats.maxHP
        send(.levelSkill(slot: .ultimate), to: &f)
        send(.practice(.setLevel(Int.max)), to: &f)
        XCTAssertEqual(f.hero(i).level, Balance.maxLevel)
        XCTAssertEqual(f.hero(i).rank(.ultimate), 1, "Raising preserves chosen ranks")
        XCTAssertEqual(f.hero(i).skillPoints, Balance.maxLevel - 1)
        XCTAssertGreaterThan(f.s.units[i].stats.maxHP, initialHP)
        send(.practice(.learnSkills), to: &f)
        XCTAssertEqual(f.hero(i).skillRanks, [1, 6, 6, 3])
        XCTAssertEqual(f.hero(i).skillPoints, 0)
        send(.practice(.resetSkills), to: &f)
        XCTAssertEqual(f.hero(i).skillRanks, [1, 0, 0, 0])
        XCTAssertEqual(f.hero(i).skillPoints, Balance.maxLevel)
        send(.practice(.learnSkills), to: &f)
        send(.practice(.setLevel(Int.min)), to: &f)
        XCTAssertEqual(f.hero(i).level, 1)
        XCTAssertEqual(f.hero(i).xp, 0)
        XCTAssertEqual(f.hero(i).skillRanks, [1, 0, 0, 0])
        XCTAssertEqual(f.hero(i).skillPoints, 1)
        XCTAssertEqual(f.s.units[i].stats.maxHP, initialHP, accuracy: 0.001)
        send(.levelSkill(slot: .skill2), to: &f)
        XCTAssertEqual(f.hero(i).rank(.skill2), 1)
    }

    func testRepeatedPurchaseClearAndReplacementPreservesSixSlots() {
        var f = fixture()
        let i = f.human
        let initialStats = f.s.units[i].stats
        for _ in 0..<3 {
            for _ in 0..<Balance.itemSlots { send(.buyItem(itemID: "EQ106"), to: &f) }
            XCTAssertEqual(f.hero(i).items.count, Balance.itemSlots)
            send(.buyItem(itemID: "EQ106"), to: &f)
            XCTAssertEqual(f.hero(i).items.count, Balance.itemSlots)
            XCTAssertEqual(f.hero(i).gold, Balance.Economy.practiceGold)
            send(.sellItem(slotIndex: 2), to: &f)
            send(.buyItem(itemID: "EQ401"), to: &f)
            XCTAssertTrue(f.hero(i).items.contains("EQ401"))
            send(.practice(.clearItems), to: &f)
            XCTAssertTrue(f.hero(i).items.isEmpty)
            XCTAssertTrue(f.hero(i).itemInvested.isEmpty)
            XCTAssertEqual(f.s.units[i].stats, initialStats)
        }
        var finite = fixture(infiniteGold: false)
        finite.s.units[finite.human].hero!.gold = 0
        send(.practice(.refillGold), to: &finite)
        XCTAssertEqual(finite.hero(finite.human).gold, Balance.Economy.practiceGold)
        XCTAssertEqual(finite.hero(finite.human).score.goldEarned, 0)
    }

    func testPracticeCommandsHaveNoEffectOutsidePracticeOrOnOtherHeroes() {
        let commands: [PracticeCommand] = [.setLevel(15), .resetSkills, .learnSkills, .clearItems, .refillGold]
        for config in [EconomyFixture.standard().ctx.config, fixture(tutorial: true).ctx.config] {
            var f = EconomyFixture(config: config)
            let i = f.human
            f.s.units[i].hero!.items = ["EQ106"]
            f.s.units[i].hero!.skillRanks = [1, 1, 0, 0]
            f.s.units[i].hero!.skillPoints = 0
            let before = f.s.units[i]
            for command in commands { send(.practice(command), to: &f) }
            XCTAssertEqual(f.s.units[i], before)
        }
        var config = fixture().ctx.config
        config.players.append(PlayerSlot(team: .red, heroID: "H026", controller: .bot, position: .mid, displayName: "Bot"))
        var f = EconomyFixture(config: config)
        let other = f.heroes(.red)[0]
        let before = f.s.units[other]
        for command in commands { send(.practice(command), to: &f, heroIndex: other) }
        XCTAssertEqual(f.s.units[other], before)
    }
}
