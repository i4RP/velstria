import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 内部ビルドの演出チェック（FXCheck）: 試合の設定と撃ち手の表。
@MainActor
final class FXCheckTests: XCTestCase {
    /// 練習場（クールダウン無し・ミニオン無し・Lv4・スキル自動習得）に敵の Bot の英雄を 1 体足す。人間は自分 1 人。
    func testConfigIsPracticeWithAnEnemyBotHero() {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let config = FXCheckSession.config(heroID: "H027", app: app)
        XCTAssertEqual(config.mode, .practice)
        XCTAssertEqual(config.practice?.noCooldowns, true)
        XCTAssertEqual(config.practice?.spawnMinions, false)
        XCTAssertEqual(config.practice?.startLevel, 4)
        let humans = config.players.filter { $0.controller == .human }
        XCTAssertEqual(humans.map(\.heroID), ["H027"])
        XCTAssertEqual(humans.first?.autoLevelSkills, true)
        let foes = config.players.filter { $0.team != humans.first?.team }
        XCTAssertEqual(foes.count, 1)
        XCTAssertEqual(foes.first?.controller, .bot)
        XCTAssertNotEqual(foes.first?.heroID, "H027")
        XCTAssertNotEqual(FXCheckSession.config(heroID: "H029", app: app).players.last?.heroID, "H029", "自分と同じヒーローを敵にしない")
    }

    /// 英雄にだけ撃てるスキル・再使用の段の表が 10 体の中にあり、比較撮影（FXCapture）と同じ値を使う。
    func testHeroOnlyAndRecastTablesNameKnownHeroes() {
        let master = MasterData.shared
        for id in Array(FXCheckDriver.heroOnly.keys) + Array(FXCheckDriver.recasts.keys) {
            XCTAssertNotNil(master.hero(id), id)
            XCTAssertTrue(FXCheckSession.defaultHeroes.contains(id), id)
        }
        XCTAssertEqual(FXCapture.recasts, FXCheckDriver.recasts)
        XCTAssertEqual(FXCapture.standoff, FXCheckDriver.standoff)
    }
}
