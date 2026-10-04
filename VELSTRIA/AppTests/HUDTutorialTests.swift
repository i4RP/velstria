import XCTest
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud。チュートリアル進行（TutorialDirector）の状態遷移を合成イベントで確認する。

final class HUDTutorialTests: XCTestCase {
    private let me: EntityID = 40
    private let enemy: EntityID = 41
    private let dummies: [EntityID] = [50, 51, 52]

    private func hit(_ source: EntityID?, _ target: EntityID, _ kind: DamageSource = .basicAttack) -> SimEvent {
        .damage(DamageEvent(sourceID: source, targetID: target, amount: 50, absorbed: 0, damageType: .physical,
                            source: kind, isCrit: false, pos: .zero))
    }

    private func cast(_ slot: SkillSlot, by caster: EntityID) -> SimEvent {
        .skillCast(SkillCastEvent(casterID: caster, heroID: "H002", slot: slot, skillID: "SK002_2", effectID: "",
                                  archetype: .cone, origin: .zero, target: .zero, range: 300, radius: 100))
    }

    private func midOuterDestroyed(team: Team = .red) -> SimEvent {
        .structureDestroyed(unitID: 9, kind: .tower, team: team, lane: .mid, tier: .outer, killerID: nil)
    }

    /// 移動手順を終わらせる。
    private func walk(_ t: inout TutorialDirector) {
        var p = Vec2(700, 700)
        t.observe(heroPosition: p, alive: true, skill1Rank: 0)
        for _ in 0..<7 {
            p = p + Vec2(100, 0)
            t.observe(heroPosition: p, alive: true, skill1Rank: 0)
        }
    }

    func testFullSequence() {
        var t = TutorialDirector()
        XCTAssertEqual(t.step, .move)
        XCTAssertEqual(t.highlight, .joystick)

        walk(&t)
        XCTAssertEqual(t.step, .attackDummy)
        XCTAssertEqual(t.highlight, .attack)

        // 人形以外・通常攻撃以外・他人の攻撃は数えない
        t.handle(hit(me, enemy), humanID: me, dummyIDs: dummies)
        t.handle(hit(me, dummies[0], .skill(.skill1)), humanID: me, dummyIDs: dummies)
        t.handle(hit(enemy, dummies[0]), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.dummyHits, 0)
        t.handle(hit(me, dummies[0]), humanID: me, dummyIDs: dummies)
        t.handle(hit(me, dummies[1]), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .attackDummy)
        XCTAssertEqual(t.progressText, "2/3")
        t.handle(hit(me, dummies[2]), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .learnSkill)
        XCTAssertEqual(t.highlight, .levelSkill1)

        // 別スロットの習得では進まない
        t.handle(.skillLeveled(heroID: me, slot: .skill2, rank: 1), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .learnSkill)
        t.handle(.skillLeveled(heroID: me, slot: .skill1, rank: 1), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .castSkill)
        XCTAssertEqual(t.highlight, .skill1)

        t.handle(cast(.skill1, by: enemy), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .castSkill)
        t.handle(cast(.skill1, by: me), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .openShop)
        XCTAssertEqual(t.highlight, .shop)

        t.noteShopOpened()
        XCTAssertEqual(t.step, .buyItem)
        t.handle(.itemPurchased(heroID: enemy, itemID: "EQ001"), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .buyItem)
        t.handle(.itemPurchased(heroID: me, itemID: "EQ001"), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .destroyTower)
        XCTAssertNotNil(t.objective(map: .standard, dummySpots: []))

        // 自軍の塔・別レーンは対象外
        t.handle(midOuterDestroyed(team: .blue), humanID: me, dummyIDs: dummies)
        t.handle(.structureDestroyed(unitID: 9, kind: .tower, team: .red, lane: .top, tier: .outer, killerID: nil),
                 humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .destroyTower)
        t.handle(midOuterDestroyed(), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .recall)
        XCTAssertEqual(t.highlight, .recall)

        t.handle(.channelCanceled(heroID: me, kind: .recall), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .recall)
        t.handle(.channelCompleted(heroID: me, kind: .recall, destination: .zero), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .complete)
        XCTAssertTrue(t.isComplete)
        XCTAssertNil(t.highlight)
        XCTAssertNil(t.stepNumber)
        XCTAssertFalse(t.rewardNote.isEmpty)
    }

    func testTeleportJumpsAndDeathDoNotCountAsWalking() {
        var t = TutorialDirector()
        t.observe(heroPosition: Vec2(700, 700), alive: true, skill1Rank: 0)
        t.observe(heroPosition: Vec2(4000, 4000), alive: true, skill1Rank: 0)
        XCTAssertEqual(t.moved, 0, "転移は移動に数えない")
        t.observe(heroPosition: Vec2(4200, 4000), alive: true, skill1Rank: 0)
        XCTAssertEqual(t.moved, 200, accuracy: 1e-9)
        t.observe(heroPosition: Vec2(4200, 4000), alive: false, skill1Rank: 0)
        t.observe(heroPosition: Vec2(4300, 4000), alive: true, skill1Rank: 0)
        XCTAssertEqual(t.moved, 200, accuracy: 1e-9, "死亡から復活の位置変化は数えない")
        XCTAssertEqual(t.progress ?? 0, 200 / 600, accuracy: 1e-9)
    }

    func testAlreadyLearnedSkillSkipsLearnStep() {
        var t = TutorialDirector()
        walk(&t)
        for d in dummies { t.handle(hit(me, d), humanID: me, dummyIDs: dummies) }
        XCTAssertEqual(t.step, .learnSkill)
        t.observe(heroPosition: Vec2(1500, 700), alive: true, skill1Rank: 1)
        XCTAssertEqual(t.step, .castSkill)
    }

    func testCastCommandAdvancesWhenSkillWasCastable() {
        var t = TutorialDirector()
        walk(&t)
        for d in dummies { t.handle(hit(me, d), humanID: me, dummyIDs: dummies) }
        t.handle(.skillLeveled(heroID: me, slot: .skill1, rank: 1), humanID: me, dummyIDs: dummies)
        t.noteSkillCommand(slot: .skill2, castable: true)
        t.noteSkillCommand(slot: .skill1, castable: false)
        XCTAssertEqual(t.step, .castSkill)
        t.noteSkillCommand(slot: .skill1, castable: true)
        XCTAssertEqual(t.step, .openShop)
    }

    func testQuickBuyDuringShopStepSkipsToTower() {
        var t = TutorialDirector()
        walk(&t)
        for d in dummies { t.handle(hit(me, d), humanID: me, dummyIDs: dummies) }
        t.handle(.skillLeveled(heroID: me, slot: .skill1, rank: 1), humanID: me, dummyIDs: dummies)
        t.handle(cast(.skill1, by: me), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .openShop)
        t.handle(.itemPurchased(heroID: me, itemID: "EQ005"), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .destroyTower)
    }

    func testTowerDestroyedEarlyIsRemembered() {
        var t = TutorialDirector()
        t.handle(midOuterDestroyed(), humanID: me, dummyIDs: dummies)
        XCTAssertTrue(t.targetTowerDestroyed)
        walk(&t)
        for d in dummies { t.handle(hit(me, d), humanID: me, dummyIDs: dummies) }
        t.handle(.skillLeveled(heroID: me, slot: .skill1, rank: 1), humanID: me, dummyIDs: dummies)
        t.handle(cast(.skill1, by: me), humanID: me, dummyIDs: dummies)
        t.noteShopOpened()
        t.handle(.itemPurchased(heroID: me, itemID: "EQ001"), humanID: me, dummyIDs: dummies)
        XCTAssertEqual(t.step, .recall, "先に塔を壊していれば塔の手順は飛ばす")
    }

    @MainActor
    func testHUDRemovesDummiesWhenPurchaseAdvancesToTower() throws {
        let saved = Loc.current
        defer { Loc.current = saved }
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        // 通常購入・おすすめ購入・塔を先に壊した場合のいずれも人形を退場させる。
        for (openShop, towerDestroyed) in [(true, false), (false, false), (true, true)] {
            let config = MatchFactory.practiceMatch(humanHeroID: "H001", humanName: "T",
                                                     options: PracticeOptions(), tutorial: true, seed: 5)
            let controller = BattleController(launch: BattleLaunch(config: config))
            let model = HUDModel(controller: controller)
            model.start(app: app) { _ in }
            defer { model.stop() }
            let humanID = try XCTUnwrap(controller.humanHeroID)
            let dummyIDs = controller.state.world.dummyIDs.compactMap { $0 }
            XCTAssertEqual(dummyIDs.count, 3)

            var t = TutorialDirector()
            walk(&t)
            for id in dummyIDs { t.handle(hit(humanID, id), humanID: humanID, dummyIDs: dummyIDs) }
            t.handle(.skillLeveled(heroID: humanID, slot: .skill1, rank: 1), humanID: humanID, dummyIDs: dummyIDs)
            t.noteSkillCommand(slot: .skill1, castable: true)
            if openShop { t.noteShopOpened() }
            if towerDestroyed { t.handle(midOuterDestroyed(), humanID: humanID, dummyIDs: dummyIDs) }
            model.debugSetTutorial(t)

            model.handle([.purchaseFailed(heroID: humanID, itemID: "EQ001", reason: PurchaseFailure.notEnoughGold.rawValue)])
            controller.frame(dt: Balance.dt)
            XCTAssertEqual(controller.state.units.filter { $0.kind == .dummy }.count, 3)

            model.handle([.itemPurchased(heroID: humanID, itemID: "EQ001")])
            XCTAssertEqual(model.tutorial?.step, towerDestroyed ? .recall : .destroyTower)
            controller.frame(dt: Balance.dt)
            XCTAssertFalse(controller.state.units.contains { $0.kind == .dummy })
            XCTAssertTrue(controller.state.world.dummySpots.isEmpty)
        }
    }

    func testTextsExistInBothLanguages() {
        let saved = Loc.current
        defer { Loc.current = saved }
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            var t = TutorialDirector()
            var seen: [String] = []
            for _ in TutorialStep.allCases {
                XCTAssertFalse(t.title.isEmpty)
                XCTAssertFalse(t.instruction.isEmpty)
                seen.append(t.title)
                // 次の手順へ（テスト用に各条件を満たす）
                switch t.step {
                case .move: walk(&t)
                case .attackDummy: for d in dummies { t.handle(hit(me, d), humanID: me, dummyIDs: dummies) }
                case .learnSkill: t.handle(.skillLeveled(heroID: me, slot: .skill1, rank: 1), humanID: me, dummyIDs: dummies)
                case .castSkill: t.handle(cast(.skill1, by: me), humanID: me, dummyIDs: dummies)
                case .openShop: t.noteShopOpened()
                case .buyItem: t.handle(.itemPurchased(heroID: me, itemID: "EQ001"), humanID: me, dummyIDs: dummies)
                case .destroyTower: t.handle(midOuterDestroyed(), humanID: me, dummyIDs: dummies)
                case .recall: t.handle(.channelCompleted(heroID: me, kind: .recall, destination: .zero), humanID: me, dummyIDs: dummies)
                case .complete: break
                }
            }
            XCTAssertTrue(t.isComplete)
            XCTAssertEqual(Set(seen).count, TutorialStep.allCases.count, "各手順のタイトルは異なる（\(lang)）")
        }
    }
}
