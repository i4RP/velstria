import XCTest
@testable import VELSTRIA
import VelstriaCore

final class HUDAttackTests: XCTestCase {
    private var savedLanguage: AppLanguage = .ja

    override func setUp() {
        super.setUp()
        savedLanguage = Loc.current
    }

    override func tearDown() {
        Loc.current = savedLanguage
        super.tearDown()
    }

    @MainActor
    private func fixture() -> (app: AppModel, model: HUDModel) {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let config = MatchFactory.practiceMatch(humanHeroID: "H001", humanName: "Tester",
                                                options: PracticeOptions(), seed: 17)
        let controller = BattleController(launch: BattleLaunch(config: config))
        let model = HUDModel(controller: controller)
        model.start(app: app, onFinish: { _ in })
        return (app, model)
    }

    @MainActor
    private func recordedPriorities(_ model: HUDModel) -> [TargetPriority] {
        model.controller.frame(dt: Balance.dt)
        return (model.controller.recorder?.frames ?? []).flatMap(\.commands).compactMap {
            switch $0.command {
            case .attackNearest(let priority): return priority
            case .attackNearestWith(let priority, _, _): return priority
            default: return nil
            }
        }
    }

    @MainActor
    private func waitForAttacks(_ count: Int, model: HUDModel) async throws -> [TargetPriority] {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            let priorities = recordedPriorities(model)
            if priorities.count >= count { return priorities }
            try await Task.sleep(for: .milliseconds(20))
        }
        return recordedPriorities(model)
    }

    @MainActor
    func testDefaultButtonsSendTowerHeroAndMinionPriorities() {
        let f = fixture()
        defer { f.model.stop() }

        for button in [AttackButtonSlot.top, .center, .bottom] {
            f.model.attackPressed(button: button)
            f.model.attackReleased(button: button)
        }

        XCTAssertEqual(recordedPriorities(f.model), [.structuresFirst, .lowestHealth, .minionsFirst])
        XCTAssertFalse(f.model.attackHeld)
    }

    /// 中央ボタンだけがヒーローロック・アクティブモンスターの判別の設定を持って発動する。
    @MainActor
    func testOnlyTheCenterButtonCarriesHeroLockAndActiveMonsterSettings() {
        let f = fixture()
        defer { f.model.stop() }
        f.app.profile.settings.heroLock = false
        f.app.profile.settings.activeMonsterDetection = true

        for button in [AttackButtonSlot.top, .center, .bottom] {
            f.model.attackPressed(button: button)
            f.model.attackReleased(button: button)
        }
        f.model.controller.frame(dt: Balance.dt)
        let commands = (f.model.controller.recorder?.frames ?? []).flatMap(\.commands).map(\.command).filter {
            switch $0 {
            case .attackNearest, .attackNearestWith: return true
            default: return false
            }
        }
        XCTAssertEqual(commands, [
            .attackNearest(priority: .structuresFirst),
            .attackNearestWith(priority: .lowestHealth, heroLock: false, activeMonsterOnly: true),
            .attackNearest(priority: .minionsFirst),
        ])
    }

    @MainActor
    func testButtonsReadTheirOwnUpdatedSettingsOnPress() {
        let f = fixture()
        defer { f.model.stop() }
        // Changes made after the HUD starts must apply without waiting for a refresh.
        f.app.profile.settings.topAttackPriority = .minionsFirst
        f.app.profile.settings.attackPriority = .lowestHealth
        f.app.profile.settings.bottomAttackPriority = .structuresFirst

        f.model.attackPressed(button: .top)
        f.model.attackReleased(button: .top)
        f.model.attackPressed()
        f.model.attackReleased()
        f.model.attackPressed(button: .bottom)
        f.model.attackReleased(button: .bottom)

        XCTAssertEqual(recordedPriorities(f.model), [.minionsFirst, .lowestHealth, .structuresFirst])
    }

    @MainActor
    func testHeldButtonRepeatsItsConfiguredPriority() async throws {
        let f = fixture()
        defer { f.model.stop() }
        f.app.profile.settings.bottomAttackPriority = .lowestHealth

        f.model.attackPressed(button: .bottom)
        let priorities = try await waitForAttacks(3, model: f.model)

        XCTAssertGreaterThanOrEqual(priorities.count, 3)
        XCTAssertTrue(priorities.allSatisfy { $0 == .lowestHealth })
        XCTAssertTrue(f.model.attackHeld)
    }

    @MainActor
    func testReleasingPreviousButtonDoesNotCancelNewHold() async throws {
        let f = fixture()
        defer { f.model.stop() }

        f.model.attackPressed(button: .top)
        f.model.attackPressed(button: .bottom)
        f.model.attackReleased(button: .top)
        XCTAssertTrue(f.model.attackHeld)

        let priorities = try await waitForAttacks(3, model: f.model)
        XCTAssertGreaterThanOrEqual(priorities.count, 3)
        XCTAssertEqual(priorities.first, .structuresFirst)
        XCTAssertTrue(priorities.dropFirst().allSatisfy { $0 == .minionsFirst })

        f.model.attackReleased(button: .bottom)
        XCTAssertFalse(f.model.attackHeld)
        let releasedCount = recordedPriorities(f.model).count
        try await Task.sleep(for: HUDModel.attackRepeatInterval + .milliseconds(100))
        XCTAssertEqual(recordedPriorities(f.model).count, releasedCount)
    }

    @MainActor
    func testStoppingHUDCancelsHeldButtonAndRepeats() async throws {
        let f = fixture()
        defer { f.model.stop() }

        f.model.attackPressed(button: .top)
        let priorities = try await waitForAttacks(2, model: f.model)
        XCTAssertGreaterThanOrEqual(priorities.count, 2)
        f.model.stop()

        XCTAssertFalse(f.model.attackHeld)
        let stoppedCount = recordedPriorities(f.model).count
        try await Task.sleep(for: HUDModel.attackRepeatInterval + .milliseconds(100))
        XCTAssertEqual(recordedPriorities(f.model).count, stoppedCount)
    }

    @MainActor
    func testClosingTacticalMapRestoresAllAttackButtonCommands() {
        let f = fixture()
        defer { f.model.stop() }

        f.model.setTacticalMap(open: true)
        for button in AttackButtonSlot.allCases {
            f.model.attackPressed(button: button)
            f.model.attackReleased(button: button)
        }
        XCTAssertTrue(recordedPriorities(f.model).isEmpty)

        f.model.setTacticalMap(open: false)
        for button in AttackButtonSlot.allCases {
            f.model.attackPressed(button: button)
            f.model.attackReleased(button: button)
        }
        XCTAssertEqual(recordedPriorities(f.model), [.structuresFirst, .heroesFirst, .minionsFirst])
    }

    @MainActor
    func testExternalPauseClearsHoldBeforeResuming() async throws {
        let f = fixture()
        defer { f.model.stop() }

        f.model.attackPressed(button: .bottom)
        XCTAssertEqual(recordedPriorities(f.model), [.minionsFirst])
        f.model.controller.isPaused = true
        f.model.externallyPaused()
        XCTAssertFalse(f.model.attackHeld)
        f.model.resume()

        try await Task.sleep(for: HUDModel.attackRepeatInterval + .milliseconds(100))
        XCTAssertEqual(recordedPriorities(f.model), [.minionsFirst])

        f.model.attackPressed(button: .center)
        f.model.attackReleased(button: .center)
        XCTAssertEqual(recordedPriorities(f.model), [.minionsFirst, .heroesFirst])
    }
}
