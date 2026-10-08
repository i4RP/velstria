import XCTest
@testable import VelstriaCore

/// 攻撃ボタンの優先対象（HP 割合が低い敵 / 実質 HP が最も低い目標 / 最も近い目標）、ヒーローロック、アクティブモンスターの判別。
final class AttackSelectionOptionsTests: XCTestCase {
    private func world() -> (w: CombatWorld, a: Int) {
        var w = CombatWorld()
        let a = w.addHero(team: .blue, at: Vec2(5000, 5000), ranged: true, stats: CombatWorld.stats(range: 550))
        return (w, a)
    }

    private func pick(_ w: inout CombatWorld, _ a: Int, _ p: TargetPriority, heroLock: Bool = false,
                      activeMonsterOnly: Bool = false) -> Int? {
        CombatSystem.selectTarget(&w.s, w.ctx, attacker: a, priority: p, heroLock: heroLock,
                                  activeMonsterOnly: activeMonsterOnly)
    }

    // MARK: 優先対象

    func testLowestHealthPercentComparesTheRatioNotTheAmount() {
        var (w, a) = world()
        let big = w.addHero(team: .red, at: Vec2(5200, 5000), stats: CombatWorld.stats(hp: 3000))
        let small = w.addHero(team: .red, at: Vec2(5300, 5000), stats: CombatWorld.stats(hp: 500))
        w.s.units[big].hp = 600      // 20%（残り HP は多い）
        w.s.units[small].hp = 250    // 50%（残り HP は少ない）
        XCTAssertEqual(pick(&w, a, .lowestHealthPercent), big)
        // 実質 HP（残り HP ベース）なら small
        XCTAssertEqual(pick(&w, a, .lowestHealth), small)
    }

    func testNearestPicksTheClosestEnemyOfAnyKind() {
        var (w, a) = world()
        _ = w.addHero(team: .red, at: Vec2(5400, 5000))
        let minion = w.addMinion(.melee, team: .red, at: Vec2(5150, 5000))
        XCTAssertEqual(pick(&w, a, .nearest), minion)
    }

    func testNewPrioritiesKeepStableRawValues() {
        XCTAssertEqual(TargetPriority.heroesFirst.rawValue, 0)
        XCTAssertEqual(TargetPriority.lowestHealth.rawValue, 3)
        XCTAssertEqual(TargetPriority.lowestHealthPercent.rawValue, 4)
        XCTAssertEqual(TargetPriority.nearest.rawValue, 5)
    }

    // MARK: ヒーローロック

    func testHeroLockPicksHeroesBeforeCloserMinions() {
        var (w, a) = world()
        let hero = w.addHero(team: .red, at: Vec2(5450, 5000))
        let minion = w.addMinion(.melee, team: .red, at: Vec2(5100, 5000))
        XCTAssertEqual(pick(&w, a, .nearest), minion)
        XCTAssertEqual(pick(&w, a, .nearest, heroLock: true), hero)
        // 射程内に敵ヒーローがいなければ通常どおり
        w.s.units[hero].pos = Vec2(9000, 9000)
        XCTAssertEqual(pick(&w, a, .nearest, heroLock: true), minion)
    }

    func testHeroLockChoosesAmongHeroesByThePriority() {
        var (w, a) = world()
        let near = w.addHero(team: .red, at: Vec2(5200, 5000), stats: CombatWorld.stats(hp: 1000))
        let far = w.addHero(team: .red, at: Vec2(5450, 5000), stats: CombatWorld.stats(hp: 1000))
        w.addMinion(.melee, team: .red, at: Vec2(5100, 5000))
        w.s.units[far].hp = 100
        XCTAssertEqual(pick(&w, a, .nearest, heroLock: true), near)
        XCTAssertEqual(pick(&w, a, .lowestHealthPercent, heroLock: true), far)
    }

    func testHeroLockCommandChasesTheLockedHeroAndUnlockedDoesNot() {
        // 射程外へ逃げた敵ヒーローを、ロックありなら追い続け、ロックなしなら近くのミニオンへ移る
        for lock in [true, false] {
            var (w, a) = world()
            let hero = w.addHero(team: .red, at: Vec2(5400, 5000))
            let minion = w.addMinion(.melee, team: .red, at: Vec2(5100, 5000))
            let heroID = w.id(a)
            let cmd = { HeroCommand(heroID: heroID, command: .attackNearestWith(priority: .nearest, heroLock: lock,
                                                                                activeMonsterOnly: false)) }
            CommandSystem.apply([cmd()], &w.s, w.ctx)
            XCTAssertEqual(w.s.units[a].attackTargetID, lock ? w.id(hero) : w.id(minion), "lock=\(lock)")
            // ヒーローを狙っていたなら、射程の外へ出ても追う（ロックありのみ）
            CombatSystem.markStickyTarget(&w.s, attacker: a, target: hero)
            w.s.units[hero].pos = Vec2(5800, 5000)
            CommandSystem.apply([cmd()], &w.s, w.ctx)
            XCTAssertEqual(w.s.units[a].attackTargetID, lock ? w.id(hero) : w.id(minion), "lock=\(lock) 追撃")
        }
    }

    // MARK: アクティブモンスターの判別

    func testActiveMonsterOnlySkipsIdleMonstersWhenThereAreOtherTargets() {
        var (w, a) = world()
        let monster = w.addUnit(.monster, team: .neutral, at: Vec2(5100, 5000))
        let minion = w.addMinion(.melee, team: .red, at: Vec2(5400, 5000))
        XCTAssertEqual(pick(&w, a, .nearest), monster)
        XCTAssertEqual(pick(&w, a, .nearest, activeMonsterOnly: true), minion)
        // 戦っている（誰かを狙っている）モンスターは対象のまま
        w.s.units[monster].attackTargetID = w.id(a)
        XCTAssertEqual(pick(&w, a, .nearest, activeMonsterOnly: true), monster)
    }

    func testActiveMonsterOnlyStillTargetsAnIdleMonsterWhenItIsTheOnlyOne() {
        var (w, a) = world()
        let monster = w.addUnit(.monster, team: .neutral, at: Vec2(5100, 5000))
        XCTAssertEqual(pick(&w, a, .nearest, activeMonsterOnly: true), monster)
    }

    // MARK: 互換

    func testCommandsRoundTripAndOldReplayCommandsStillDecode() throws {
        let cmd = PlayerCommand.attackNearestWith(priority: .lowestHealthPercent, heroLock: true, activeMonsterOnly: false)
        let data = try JSONEncoder().encode(cmd)
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: data), cmd)
        let old = PlayerCommand.attackNearest(priority: .minionsFirst)
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(old)), old)
    }
}
