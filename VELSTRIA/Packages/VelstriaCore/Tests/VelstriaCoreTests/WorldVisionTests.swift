import XCTest
@testable import VelstriaCore

/// チーム視界（DESIGN §9）: 視界格子・草むら・ステルス・真視界・Revealed・死亡ヒーロー。
final class WorldVisionTests: XCTestCase {
    typealias Kit = WorldTestKit

    func makeState() -> (SimState, SimContext) {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.setTime(&s, 60)
        Kit.suppressWaves(&s)
        return (s, ctx)
    }

    /// 構造物から遠い草むら（Blue 南ジャングルの「熾甲虫の右」）。
    var jungleBrush: BrushArea {
        MapDefinition.standard.brushes.first { $0.rect == Rect2(minX: 7800, minY: 1750, maxX: 8300, maxY: 2350) }!
    }

    func testGridShapeAndFountainVision() {
        let (s, _) = makeState()
        XCTAssertEqual(s.vision.cols, 60)
        XCTAssertEqual(s.vision.rows, 60)
        XCTAssertEqual(s.vision.cells.count, 3600)
        XCTAssertTrue(s.vision.isLit(Vec2(600, 600), for: .blue))
        XCTAssertTrue(s.vision.isLit(Vec2(600 + 1200, 600), for: .blue))
        XCTAssertFalse(s.vision.isLit(Vec2(600, 600), for: .red))
        XCTAssertTrue(s.vision.isLit(Vec2(11400, 11400), for: .red))
        // タワー視界 1100
        XCTAssertTrue(s.vision.isLit(Vec2(4656 + 1000, 4991), for: .blue))
        XCTAssertFalse(s.vision.isLit(Vec2(6000, 6000), for: .blue))
        XCTAssertFalse(s.vision.isLit(Vec2(6000, 6000), for: .red))
    }

    func testEnemiesVisibleOnlyInLitCells() {
        var (s, ctx) = makeState()
        let enemy = Kit.addHero(&s, ctx, team: .red, pos: Vec2(6000, 6000))
        VisionSystem.update(&s, ctx)
        XCTAssertFalse(s.isVisible(enemy, to: .blue))
        XCTAssertTrue(s.isVisible(enemy, to: .red))
        XCTAssertEqual(s.units[enemy].visibleMask, Team.red.visionBit)

        let scout = Kit.addHero(&s, ctx, team: .blue, pos: Vec2(5200, 5400))
        VisionSystem.update(&s, ctx)
        XCTAssertTrue(s.isVisible(enemy, to: .blue))
        // 死亡中のヒーローは視界を与えない
        s.units[scout].hero?.respawnTimer = 10
        s.units[scout].isAlive = false
        VisionSystem.update(&s, ctx)
        XCTAssertFalse(s.isVisible(enemy, to: .blue))
        // 死亡中のヒーローは敵から見えない
        XCTAssertEqual(s.units[scout].visibleMask, Team.blue.visionBit)
    }

    func testMinionSightRadius() {
        var (s, ctx) = makeState()
        let enemy = Kit.addHero(&s, ctx, team: .red, pos: Vec2(6000, 6000))
        // 判定は敵の居る格子（中心 (6100,6100)）が視界円に入るか
        let minion = Kit.addMinion(&s, ctx, team: .blue, pos: Vec2(6000 - 600, 6000))
        VisionSystem.update(&s, ctx)
        XCTAssertTrue(s.isVisible(enemy, to: .blue))
        s.units[minion].pos = Vec2(6000 - 1000, 6000)
        VisionSystem.update(&s, ctx)
        XCTAssertFalse(s.isVisible(enemy, to: .blue))
    }

    func testBrushHidesUnlessSameBrushOrClose() {
        var (s, ctx) = makeState()
        let b = jungleBrush
        let hider = Kit.addHero(&s, ctx, team: .red, pos: Vec2(b.rect.minX + 30, b.rect.center.y))
        let scout = Kit.addHero(&s, ctx, team: .blue, pos: Vec2(b.rect.minX - 600, b.rect.center.y))
        VisionSystem.update(&s, ctx)
        XCTAssertEqual(s.units[hider].brushIndex, b.id)
        XCTAssertNil(s.units[scout].brushIndex)
        XCTAssertTrue(s.vision.isLit(s.units[hider].pos, for: .blue))
        XCTAssertFalse(s.isVisible(hider, to: .blue), "hidden in brush")
        XCTAssertTrue(s.isVisible(scout, to: .red), "scout outside brush is visible")

        // 300 以内に近づくと見える
        s.units[scout].pos = Vec2(b.rect.minX - 250, b.rect.center.y)
        VisionSystem.update(&s, ctx)
        XCTAssertTrue(s.isVisible(hider, to: .blue))

        // 同じ草むら内なら距離が 300 超でも見える
        s.units[scout].pos = Vec2(b.rect.maxX - 10, b.rect.maxY - 10)
        s.units[hider].pos = Vec2(b.rect.minX + 10, b.rect.minY + 10)
        XCTAssertGreaterThan(s.units[scout].pos.distance(to: s.units[hider].pos), Balance.brushRevealRadius)
        VisionSystem.update(&s, ctx)
        XCTAssertTrue(s.isVisible(hider, to: .blue))
        XCTAssertTrue(s.isVisible(scout, to: .red))

        // Revealed は草むらでも見える
        s.units[scout].pos = Vec2(b.rect.minX - 600, b.rect.center.y)
        s.units[hider].statuses.append(StatusEffect(kind: .revealed, duration: 3))
        VisionSystem.update(&s, ctx)
        XCTAssertTrue(s.isVisible(hider, to: .blue))
    }

    func testStealthNeedsCloseObserverTowerOrFountain() {
        var (s, ctx) = makeState()
        let sneak = Kit.addHero(&s, ctx, team: .red, pos: Vec2(6000, 6000))
        s.units[sneak].statuses.append(StatusEffect(kind: .stealth, duration: 10))
        let scout = Kit.addHero(&s, ctx, team: .blue, pos: Vec2(6000 - 600, 6000))
        VisionSystem.update(&s, ctx)
        XCTAssertFalse(s.isVisible(sneak, to: .blue))
        s.units[scout].pos = Vec2(6000 - 200, 6000)
        VisionSystem.update(&s, ctx)
        XCTAssertTrue(s.isVisible(sneak, to: .blue))

        // タワーの真視界 750
        s.units[scout].pos = Vec2(3000, 5000)
        s.units[sneak].pos = Vec2(4656 + 600, 4991)
        VisionSystem.update(&s, ctx)
        XCTAssertTrue(s.isVisible(sneak, to: .blue))
        s.units[sneak].pos = Vec2(4656 + 900, 4991)
        VisionSystem.update(&s, ctx)
        XCTAssertTrue(s.vision.isLit(s.units[sneak].pos, for: .blue))
        XCTAssertFalse(s.isVisible(sneak, to: .blue))

        // 泉の中は常に看破
        s.units[sneak].pos = Vec2(900, 900)
        VisionSystem.update(&s, ctx)
        XCTAssertTrue(s.isVisible(sneak, to: .blue))
    }

    func testStructuresAlwaysVisibleAndNeutralBits() {
        var (s, ctx) = makeState()
        VisionSystem.update(&s, ctx)
        for i in s.units.indices where s.units[i].isStructure {
            XCTAssertEqual(s.units[i].visibleMask, Team.blue.visionBit | Team.red.visionBit)
        }
        let monster = s.addUnit(UnitFactory.makeMonster(kind: .campSmall, campID: 0, pos: Vec2(4656 + 500, 4991)))
        VisionSystem.update(&s, ctx)
        XCTAssertEqual(s.unit(monster)?.visibleMask, Team.blue.visionBit)
        // 破壊された構造物（残骸）も両チームから見えるが、攻撃対象にはならない
        let tower = Kit.structureIndex(s, team: .red, lane: .mid, tier: .outer)
        Kit.kill(&s, tower)
        VisionSystem.update(&s, ctx)
        XCTAssertEqual(s.units[tower].visibleMask, Team.blue.visionBit | Team.red.visionBit)
        XCTAssertFalse(s.isTargetableEnemy(tower, of: .blue))
    }

    func testVisibilityDrivesTargeting() {
        var (s, ctx) = makeState()
        let b = jungleBrush
        let hider = Kit.addHero(&s, ctx, team: .red, pos: b.rect.center)
        Kit.addHero(&s, ctx, team: .blue, pos: b.rect.center + Vec2(-700, 0))
        VisionSystem.update(&s, ctx)
        XCTAssertFalse(s.isTargetableEnemy(hider, of: .blue))
        XCTAssertTrue(s.enemies(of: .blue, near: b.rect.center, radius: 100).isEmpty)
    }

    func testFullSimulationUpdatesAtTenHertz() {
        var (s, ctx) = makeState()
        let enemy = Kit.addHero(&s, ctx, team: .red, pos: Vec2(6000, 6000))
        let scout = Kit.addHero(&s, ctx, team: .blue, pos: Vec2(3000, 3000))
        VisionSystem.update(&s, ctx)
        s.units[scout].pos = Vec2(5500, 5500)
        let enemyID = s.units[enemy].id
        let sim = Simulation(snapshot: s)
        var ticksUntilVisible = 0
        while sim.state.isVisible(sim.state.index(of: enemyID)!, to: .blue) == false && ticksUntilVisible < 10 {
            sim.step()
            ticksUntilVisible += 1
        }
        XCTAssertLessThanOrEqual(ticksUntilVisible, Balance.visionUpdateEveryTicks)
        XCTAssertGreaterThan(ticksUntilVisible, 0)
    }
}
