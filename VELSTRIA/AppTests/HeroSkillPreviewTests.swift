import XCTest
@testable import VELSTRIA
import VelstriaCore

@MainActor
final class HeroSkillPreviewTests: XCTestCase {
    private let master = MasterData.shared

    func testEachSkillPlaysMotionAndFXThenReturnsToIdle() throws {
        let driver = HeroStageDriver()
        var config = HeroStageConfig(slots: [HeroStageSlot(heroID: "H033")], pedestal: true,
                                     allowsSkillPreview: true)
        driver.apply(config)
        let model = try XCTUnwrap(driver.models.first)
        let playback = try XCTUnwrap(driver.skillPlayback)
        for skill in master.skills(forHero: "H033") {
            config.skillPreview = HeroSkillPreviewRequest(skillID: skill.skillID)
            driver.apply(config)
            XCTAssertTrue(driver.models.first?.root === model.root, "タップでモデルを作り直さない")
            XCTAssertEqual(model.state, skill.slot == .passive ? .attack : .cast(skill.slot))
            for _ in 0..<12 { driver.tick(1 / 60) }
            XCTAssertGreaterThan(playback.player.activeCount, 0, skill.skillID)
            for _ in 0..<250 { driver.tick(1 / 60) }
            XCTAssertEqual(model.state, .idle, skill.skillID)
            XCTAssertFalse(playback.isPlaying)
            XCTAssertEqual(playback.player.activeCount, 0)
            XCTAssertEqual(playback.player.pendingCount, 0)
        }
    }

    func testRepeatedTapsRestartButViewUpdatesDoNotReplay() throws {
        let driver = HeroStageDriver()
        let skill = try XCTUnwrap(master.skill(hero: "H033", slot: .skill2))
        var config = HeroStageConfig(slots: [HeroStageSlot(heroID: "H033")], allowsSkillPreview: true)
        driver.apply(config)
        let playback = try XCTUnwrap(driver.skillPlayback)
        // 連打しても古い予約は残らず、現在のスキルだけになる。
        for _ in 0..<20 {
            config.skillPreview = HeroSkillPreviewRequest(skillID: skill.skillID)
            driver.apply(config)
            driver.tick(1 / 60)
            XCTAssertEqual(driver.models.first?.state, .cast(.skill2))
            XCTAssertTrue(playback.isPlaying)
            XCTAssertLessThanOrEqual(playback.player.pendingCount, BattleWorkBudget.pendingCues)
        }
        for _ in 0..<250 { driver.tick(1 / 60) }
        driver.apply(config)
        XCTAssertFalse(playback.isPlaying, "レイアウト更新で再発動しない")
        config.skillPreview = HeroSkillPreviewRequest(skillID: skill.skillID)
        driver.apply(config)
        XCTAssertTrue(playback.isPlaying, "同じボタンをもう一度押すと再生する")
    }

    func testLeavingPreviewCancelsFXAndOtherScreensDoNotPreloadSkills() throws {
        let driver = HeroStageDriver()
        var config = HeroStageConfig(slots: [HeroStageSlot(heroID: "H033")])
        driver.apply(config)
        XCTAssertNil(driver.skillPlayback)
        config.allowsSkillPreview = true
        config.skillPreview = HeroSkillPreviewRequest(skillID: try XCTUnwrap(master.skill(hero: "H033", slot: .skill1)).skillID)
        driver.apply(config)
        let playback = try XCTUnwrap(driver.skillPlayback)
        XCTAssertTrue(playback.isPlaying)
        driver.isActive = false
        XCTAssertFalse(playback.isPlaying)
        XCTAssertFalse(playback.player.root.isEnabled)
        XCTAssertEqual(playback.player.activeCount, 0)
        XCTAssertEqual(playback.player.pendingCount, 0)
        driver.isActive = true
        driver.apply(config)
        driver.tick(1 / 60)
        XCTAssertFalse(playback.isPlaying, "画面へ戻っただけでは再発動しない")
    }
}
