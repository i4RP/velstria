import XCTest
@testable import VelstriaCore

final class CombatProjectileZoneTests: XCTestCase {

    private func damage(_ amount: Double, heroesOnly: Bool = false) -> HitPayload {
        HitPayload(damage: amount, damageType: .trueDamage, source: .skill(.skill1), heroesOnly: heroesOnly)
    }

    private func hitTargets(_ w: CombatWorld) -> [EntityID?] {
        w.s.events.compactMap { if case .projectileHit(_, let t, _) = $0 { return t } else { return nil } }
    }

    // MARK: - 追尾弾

    func testHomingProjectileHitsTarget() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let t = w.addHero(team: .red, at: Vec2(5600, 5000))
        ProjectileSystem.spawn(&w.s, ownerIndex: o, motion: .homing(targetID: w.id(t)), speed: 1500,
                               payload: damage(100), visual: "test")
        w.tick(9)
        XCTAssertTrue(w.damageEvents.isEmpty)
        w.tick(3)
        XCTAssertEqual(w.damageEvents.count, 1)
        XCTAssertEqual(w.damageEvents.first?.targetID, w.id(t))
        XCTAssertEqual(hitTargets(w), [w.id(t)])
        XCTAssertTrue(w.s.projectiles[0].done)
        XCTAssertEqual(w.s.projectiles[0].hitIDs, [w.id(t)])
    }

    func testHomingProjectileFollowsMovingTarget() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let t = w.addHero(team: .red, at: Vec2(5300, 5300))
        w.s.units[t].moveIntent = .direction(Vec2(1, 1))
        ProjectileSystem.spawn(&w.s, ownerIndex: o, motion: .homing(targetID: w.id(t)), speed: 1500,
                               payload: damage(10), visual: "test")
        w.tick(20)
        XCTAssertEqual(w.damageEvents.count, 1)
    }

    func testHomingProjectileFizzlesWhenTargetDiesOrTurnsInvisible() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let dies = w.addHero(team: .red, at: Vec2(5600, 5000))
        let hides = w.addHero(team: .red, at: Vec2(5000, 5600))
        ProjectileSystem.spawn(&w.s, ownerIndex: o, motion: .homing(targetID: w.id(dies)), speed: 1500,
                               payload: damage(100), visual: "a")
        ProjectileSystem.spawn(&w.s, ownerIndex: o, motion: .homing(targetID: w.id(hides)), speed: 1500,
                               payload: damage(100), visual: "b")
        w.tick(3)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: nil, targetIndex: dies, amount: 10_000, type: .trueDamage,
                                 source: .spell)
        w.s.units[hides].visibleMask = Team.red.visionBit
        let before = w.damageEvents.count
        w.tick()
        XCTAssertTrue(w.s.projectiles.allSatisfy(\.done))
        XCTAssertEqual(hitTargets(w), [nil, nil])
        w.tick(20)
        XCTAssertEqual(w.damageEvents.count, before)
    }

    // MARK: - 直線弾

    func testLinearSkillshotHitsFirstEnemyOnly() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let far = w.addHero(team: .red, at: Vec2(5600, 5000))
        let near = w.addHero(team: .red, at: Vec2(5300, 5000))
        ProjectileSystem.spawn(&w.s, ownerIndex: o, motion: .linear(direction: Vec2(1, 0), maxDistance: 1000),
                               speed: 1600, width: 30, payload: damage(100), visual: "shot")
        w.tick(20)
        XCTAssertEqual(w.damageEvents.map(\.targetID), [w.id(near)])
        XCTAssertEqual(w.s.units[far].hp, 1000)
        XCTAssertTrue(w.s.projectiles[0].done)
        XCTAssertEqual(w.s.projectiles[0].pos.x, 5300 - 55 - 30, accuracy: 1e-6, "当たった位置で止まる")
    }

    func testLinearSkillshotMissesOutsideWidth() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let miss = w.addHero(team: .red, at: Vec2(5300, 5000 + 55 + 30 + 1))
        let graze = w.addHero(team: .red, at: Vec2(5600, 5000 - 55 - 30 + 1))
        ProjectileSystem.spawn(&w.s, ownerIndex: o, motion: .linear(direction: Vec2(1, 0), maxDistance: 1000),
                               speed: 1600, width: 30, payload: damage(100), visual: "shot")
        w.tick(25)
        XCTAssertEqual(w.s.units[miss].hp, 1000)
        XCTAssertEqual(w.damageEvents.map(\.targetID), [w.id(graze)])
    }

    func testLinearPierceHitsAllInPathOrder() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let second = w.addHero(team: .red, at: Vec2(5700, 5000))
        let first = w.addUnit(.minion, team: .red, at: Vec2(5250, 5020))
        w.addHero(team: .blue, at: Vec2(5400, 5000)) // 味方には当たらない
        w.addUnit(.tower, team: .red, at: Vec2(5500, 5000), radius: 110) // 構造物には当たらない
        ProjectileSystem.spawn(&w.s, ownerIndex: o, motion: .linear(direction: Vec2(1, 0), maxDistance: 2000),
                               speed: 3000, width: 40, pierce: true, payload: damage(100), visual: "arrow")
        w.tick(30)
        XCTAssertEqual(w.damageEvents.map(\.targetID), [w.id(first), w.id(second)])
        XCTAssertEqual(w.s.projectiles[0].hitIDs, [w.id(first), w.id(second)])
        XCTAssertEqual(w.s.projectiles[0].traveled, 2000, accuracy: 1e-6)
    }

    func testFastLinearProjectileDoesNotTunnel() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        // 1 tick 300 ユニット進む弾と半径 5 の対象（点サンプリングなら 5000 と 5300 の間ですり抜ける）
        let tiny = w.addUnit(.minion, team: .red, at: Vec2(5150, 5000), radius: 5)
        ProjectileSystem.spawn(&w.s, ownerIndex: o, motion: .linear(direction: Vec2(1, 0), maxDistance: 1200),
                               speed: 9000, width: 0, payload: damage(10), visual: "fast")
        w.tick(5)
        XCTAssertEqual(w.damageEvents.map(\.targetID), [w.id(tiny)])
    }

    func testLinearHeroesOnlyMaxDistanceAndMapEdge() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        w.addUnit(.minion, team: .red, at: Vec2(5200, 5000))
        let hero = w.addHero(team: .red, at: Vec2(5500, 5000))
        let beyond = w.addHero(team: .red, at: Vec2(5000, 5900))
        ProjectileSystem.spawn(&w.s, ownerIndex: o, motion: .linear(direction: Vec2(1, 0), maxDistance: 1000),
                               speed: 1600, width: 20, payload: damage(10, heroesOnly: true), visual: "h")
        ProjectileSystem.spawn(&w.s, ownerIndex: o, motion: .linear(direction: Vec2(0, 1), maxDistance: 700),
                               speed: 1600, width: 20, payload: damage(10), visual: "short")
        let edge = w.addHero(team: .blue, at: Vec2(11_950, 5000))
        ProjectileSystem.spawn(&w.s, ownerIndex: edge, motion: .linear(direction: Vec2(1, 0), maxDistance: 1000),
                               speed: 1600, payload: damage(10), visual: "edge")
        w.tick(30)
        XCTAssertEqual(w.damageEvents.map(\.targetID), [w.id(hero)])
        XCTAssertEqual(w.s.units[beyond].hp, 1000)
        XCTAssertEqual(w.s.projectiles[1].traveled, 700, accuracy: 1e-6)
        XCTAssertTrue(w.s.projectiles[1].done)
        XCTAssertTrue(w.s.projectiles[2].done)
        XCTAssertEqual(w.s.projectiles[2].pos.x, 12_000, accuracy: 1e-6)
    }

    func testLinearKnockbackPushesAlongTravelDirection() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let t = w.addHero(team: .red, at: Vec2(5300, 5010))
        var p = damage(10)
        p.cc = .knockback
        ProjectileSystem.spawn(&w.s, ownerIndex: o, motion: .linear(direction: Vec2(1, 0), maxDistance: 1000),
                               speed: 1600, width: 30, payload: p, visual: "kb")
        w.tick(6)
        let d = w.s.units[t].displacement
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.to.y ?? 0, d?.from.y ?? 1, accuracy: 1e-6)
        XCTAssertGreaterThan(d?.to.x ?? 0, d?.from.x ?? 0)
    }

    // MARK: - ゾーン

    func testZoneTriggersExactlyAfterDelay() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let inside = w.addHero(team: .red, at: Vec2(5600, 5000))
        let outside = w.addHero(team: .red, at: Vec2(5600, 5400))
        ZoneSystem.spawn(&w.s, ownerIndex: o, center: Vec2(5600, 5100), radius: 200, delay: 0.5,
                         payload: damage(100), visual: "aoe")
        XCTAssertTrue(w.s.events.contains { if case .zoneCreated = $0 { return true } else { return false } })
        w.tick(14)
        XCTAssertFalse(w.s.zones[0].triggered)
        XCTAssertTrue(w.damageEvents.isEmpty)
        w.tick()
        XCTAssertTrue(w.s.zones[0].triggered)
        XCTAssertTrue(w.s.zones[0].done)
        XCTAssertEqual(w.damageEvents.map(\.targetID), [w.id(inside)])
        XCTAssertEqual(w.s.units[outside].hp, 1000)
        XCTAssertEqual(w.s.zones[0].hitIDs, [w.id(inside)])
        w.tick(30)
        XCTAssertEqual(w.damageEvents.count, 1, "単発ゾーンは 1 回だけ")
    }

    func testConeShapeIncludesTargetRadius() {
        let c = Vec2(5000, 5000)
        let cone = ZoneShape.cone(direction: Vec2(1, 0), halfAngle: .pi / 4)
        func hit(_ angleDeg: Double, _ dist: Double, r: Double = 55) -> Bool {
            let p = c + Vec2.fromAngle(angleDeg * .pi / 180, length: dist)
            return ZoneSystem.contains(shape: cone, center: c, radius: 300, point: p, pointRadius: r)
        }
        XCTAssertTrue(hit(0, 200))
        XCTAssertTrue(hit(30, 280))
        XCTAssertFalse(hit(180, 200), "背後")
        XCTAssertTrue(hit(0, 350), "外周は対象半径ぶん広い")
        XCTAssertFalse(hit(0, 360))
        // 角度外でも辺まで対象半径以内なら当たる（200×sin15° ≈ 51.8 < 55）
        XCTAssertTrue(hit(60, 200))
        XCTAssertFalse(hit(70, 200)) // 200×sin25° ≈ 84.5
        XCTAssertTrue(hit(135, 30), "中心が対象の円に含まれる")
    }

    func testLineShape() {
        let c = Vec2(5000, 5000)
        let line = ZoneShape.line(direction: Vec2(0, 1), length: 600)
        func hit(_ x: Double, _ y: Double) -> Bool {
            ZoneSystem.contains(shape: line, center: c, radius: 50, point: Vec2(x, y), pointRadius: 55)
        }
        XCTAssertTrue(hit(5000, 5500))
        XCTAssertTrue(hit(5100, 5300))
        XCTAssertFalse(hit(5120, 5300))
        XCTAssertTrue(hit(5000, 5700))
        XCTAssertFalse(hit(5000, 5710))
        XCTAssertFalse(hit(5000, 4890))
    }

    func testConeAndLineZonesSelectTargets() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let front = w.addHero(team: .red, at: Vec2(5200, 5000))
        w.addHero(team: .red, at: Vec2(4800, 5000))
        let lineHit = w.addUnit(.minion, team: .red, at: Vec2(5000, 5500))
        ZoneSystem.spawn(&w.s, ownerIndex: o, center: Vec2(5000, 5000), radius: 300,
                         shape: .cone(direction: Vec2(1, 0), halfAngle: .pi / 4), delay: 0,
                         payload: damage(10), visual: "cone")
        ZoneSystem.spawn(&w.s, ownerIndex: o, center: Vec2(5000, 5000), radius: 40,
                         shape: .line(direction: Vec2(0, 1), length: 800), delay: 0,
                         payload: damage(10), visual: "line")
        w.tick()
        XCTAssertEqual(w.damageEvents.map(\.targetID), [w.id(front), w.id(lineHit)])
    }

    func testPersistentZoneTicksAndResolvesAfterOwnerDeath() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let t = w.addHero(team: .red, at: Vec2(5500, 5000))
        ZoneSystem.spawn(&w.s, ownerIndex: o, center: Vec2(5500, 5000), radius: 150, delay: 0.2, duration: 2,
                         tickInterval: 0.5, payload: damage(10), visual: "field")
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: nil, targetIndex: o, amount: 10_000, type: .trueDamage,
                                 source: .spell)
        XCTAssertFalse(w.s.units[o].isAlive)
        w.tick(120)
        // 発動時 1 回 + 0.5 秒毎に 4 回
        XCTAssertEqual(w.damageEvents.filter { $0.targetID == w.id(t) }.count, 5)
        XCTAssertEqual(w.s.units[t].hp, 950, accuracy: 1e-9)
        XCTAssertTrue(w.s.zones[0].done)
        XCTAssertTrue(w.damageEvents.filter { $0.targetID == w.id(t) }.allSatisfy { $0.sourceID == w.id(o) })
    }

    func testZoneFollowsLivingOwner() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        w.s.units[o].moveIntent = .direction(Vec2(1, 1))
        ZoneSystem.spawn(&w.s, ownerIndex: o, center: Vec2(5000, 5000), radius: 200, delay: 0, duration: 3,
                         followsOwner: true, payload: damage(1), visual: "aura")
        w.tick(30)
        XCTAssertEqual(w.s.zones[0].center, w.s.units[o].pos)
        XCTAssertGreaterThan(w.s.zones[0].center.distance(to: Vec2(5000, 5000)), 200)
        let frozen = w.s.zones[0].center
        w.s.units[o].isAlive = false
        w.tick(10)
        XCTAssertEqual(w.s.zones[0].center, frozen)
    }

    func testHealZoneHealsAlliesAndDamagesEnemies() {
        var w = CombatWorld()
        let o = w.addHero(team: .blue, at: Vec2(5000, 5000))
        let ally = w.addHero(team: .blue, at: Vec2(5100, 5000))
        let enemy = w.addHero(team: .red, at: Vec2(5000, 5100))
        let allyTower = w.addUnit(.tower, team: .blue, at: Vec2(4900, 4900), radius: 110)
        w.s.units[ally].hp = 500
        w.s.units[allyTower].hp = 100
        let payload = HitPayload(damage: 50, damageType: .magic, source: .skill(.skill3), cc: .slow,
                                 statuses: [StatusEffect(kind: .speedBoost, duration: 2, magnitude: 0.2)],
                                 affectsEnemies: true, affectsAllies: true, healAmount: 100)
        ZoneSystem.spawn(&w.s, ownerIndex: o, center: Vec2(5000, 5000), radius: 300, delay: 0, payload: payload,
                         visual: "heal")
        w.tick()
        XCTAssertEqual(w.s.units[ally].hp, 600, accuracy: 1e-9)
        XCTAssertEqual(w.s.units[enemy].hp, 950, accuracy: 1e-9)
        XCTAssertTrue(w.s.units[enemy].has(.slow))
        XCTAssertFalse(w.s.units[enemy].has(.speedBoost), "強化は敵に付与しない")
        XCTAssertTrue(w.s.units[ally].has(.speedBoost))
        XCTAssertFalse(w.s.units[ally].has(.slow))
        XCTAssertEqual(w.s.units[allyTower].hp, 100, "構造物は対象外")
        XCTAssertEqual(w.s.units[ally].hero?.recentSupporters.map(\.sourceID), [w.id(o)])
    }
}
