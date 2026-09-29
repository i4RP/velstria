import XCTest
@testable import VelstriaCore

/// 中立モンスター（DESIGN §4）: 反撃・キャンプ単位の反撃・リーシュ帰還と全回復・攻撃者死亡でリセット。
final class WorldMonsterTests: XCTestCase {
    typealias Kit = WorldTestKit

    /// 標準マップでキャンプが出現した直後の状態。
    func makeJungle() -> (SimState, SimContext) {
        var (s, ctx) = Kit.makeState(Kit.emptyConfig())
        Kit.setTime(&s, 30)
        Kit.suppressWaves(&s)
        SpawnSystem.update(&s, ctx)
        return (s, ctx)
    }

    /// 障害物・キャンプのない平地に 1 体だけ置いた状態（リーシュの挙動を単独で確認する）。
    func makeOpenField(kind: MonsterKind = .blueSentinel, home: Vec2 = Vec2(6000, 3000)) -> (SimState, SimContext, Int) {
        var map = MapDefinition.standard
        map.obstacles = []
        map.brushes = []
        map.camps = []
        let cfg = Kit.emptyConfig()
        let ctx = SimContext(master: .shared, map: map, config: cfg)
        var s = SimState(config: cfg)
        SpawnSystem.setupMatch(&s, ctx)
        s.phase = .playing
        Kit.setTime(&s, 60)
        Kit.suppressWaves(&s)
        let id = s.addUnit(UnitFactory.makeMonster(kind: kind, campID: 0, pos: home))
        for i in s.units.indices { StatCalculator.recompute(&s, i, ctx) }
        VisionSystem.update(&s, ctx)
        return (s, ctx, s.index(of: id)!)
    }

    func monsterIndex(_ s: SimState, kind: MonsterKind, near p: Vec2) -> Int {
        s.units.indices.filter { s.units[$0].monster?.kind == kind }
            .min { s.units[$0].pos.distance(to: p) < s.units[$1].pos.distance(to: p) }!
    }

    func testIdleUntilAttackedThenAggroOnAttacker() {
        var (s, ctx) = makeJungle()
        let m = monsterIndex(s, kind: .redSentinel, near: Vec2(6300, 3300))
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: Vec2(6300, 2900) + Vec2(0, 50))
        MonsterSystem.update(&s, ctx)
        XCTAssertNil(s.units[m].attackTargetID)
        XCTAssertEqual(s.units[m].moveIntent, .none)

        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: m, amount: 100,
                                 type: .physical, source: .basicAttack)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].attackTargetID, s.units[hero].id)
        XCTAssertEqual(s.units[m].moveIntent, .follow(targetID: s.units[hero].id, range: s.units[m].stats.attackRange))

        // 別のユニットが殴ったら最後の攻撃者へ切り替え
        let other = Kit.addHero(&s, ctx, team: .red, pos: Vec2(6600, 3300))
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[other].id, targetIndex: m, amount: 100,
                                 type: .physical, source: .basicAttack)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].attackTargetID, s.units[other].id)
    }

    func testWholeCampRespondsTogether() {
        var (s, ctx) = makeJungle()
        let camp = ctx.map.camps.first { $0.kind == .small && $0.side == .blue }!
        let members = s.units.indices.filter { s.units[$0].monster?.campID == camp.id }
        XCTAssertEqual(members.count, 3)
        let large = members.first { s.units[$0].monster?.kind == .campLarge }!
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: camp.pos + Vec2(0, -350))
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: large, amount: 50,
                                 type: .physical, source: .basicAttack)
        MonsterSystem.update(&s, ctx)
        for k in members { XCTAssertEqual(s.units[k].attackTargetID, s.units[hero].id) }
        // 他のキャンプは反応しない
        let otherCamp = s.units.indices.first { s.units[$0].kind == .monster && s.units[$0].monster?.campID != camp.id }!
        XCTAssertNil(s.units[otherCamp].attackTargetID)
    }

    func testLeashReturnsHomeInvulnerableAndHeals() {
        var (s, ctx, m) = makeOpenField()
        let home = s.units[m].monster!.home
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: home + Vec2(1200, 0))
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: m, amount: 800,
                                 type: .trueDamage, source: .basicAttack)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].attackTargetID, s.units[hero].id)

        // リーシュ半径 900 を超えた
        s.units[m].pos = home + Vec2(Balance.leashRadius + 10, 0)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].monster?.leashing, true)
        XCTAssertNil(s.units[m].attackTargetID)
        XCTAssertEqual(s.units[m].moveIntent, .point(home))
        XCTAssertTrue(s.units[m].has(.invulnerable))
        XCTAssertEqual(CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: m, amount: 500,
                                                type: .trueDamage, source: .basicAttack), 0)
        // 帰還中は殴られても反撃しない
        MonsterSystem.update(&s, ctx)
        XCTAssertNil(s.units[m].attackTargetID)

        // 到着で全回復・待機へ
        s.units[m].pos = home
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].hp, s.units[m].stats.maxHP)
        XCTAssertEqual(s.units[m].monster?.leashing, false)
        XCTAssertFalse(s.units[m].has(.invulnerable))
        XCTAssertNil(s.units[m].lastAttackerID)
        XCTAssertEqual(s.units[m].moveIntent, .none)
    }

    func testLeashInFullSimulation() {
        var (s, ctx, m) = makeOpenField()
        let home = s.units[m].monster!.home
        // 攻撃者は巣から 1300（到達前にリーシュ 900 を超える）
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: home + Vec2(1300, 0))
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: m, amount: 600,
                                 type: .trueDamage, source: .basicAttack)
        let monsterID = s.units[m].id, heroID = s.units[hero].id
        let sim = Simulation(snapshot: s, map: ctx.map)
        var sawLeash = false
        var maxDistance = 0.0
        var heroDamaged = false
        for _ in 0..<(12 * 30) {
            for e in sim.step() {
                if case .damage(let d) = e, d.targetID == heroID { heroDamaged = true }
            }
            let u = sim.state.unit(monsterID)!
            maxDistance = max(maxDistance, u.pos.distance(to: home))
            if u.monster?.leashing == true { sawLeash = true }
        }
        let u = sim.state.unit(monsterID)!
        XCTAssertTrue(sawLeash)
        XCTAssertFalse(heroDamaged)
        XCTAssertGreaterThan(maxDistance, Balance.leashRadius)
        XCTAssertLessThan(maxDistance, Balance.leashRadius + 50)
        XCTAssertLessThan(u.pos.distance(to: home), Balance.monsterHomeTolerance + 1)
        XCTAssertEqual(u.hp, u.stats.maxHP)
        XCTAssertEqual(u.monster?.leashing, false)
        XCTAssertNil(u.attackTargetID)
    }

    func testFightsBackInFullSimulation() {
        var (s, ctx, m) = makeOpenField(kind: .campLarge)
        let home = s.units[m].monster!.home
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: home + Vec2(200, 0))
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: m, amount: 10,
                                 type: .physical, source: .basicAttack)
        let heroID = s.units[hero].id
        let sim = Simulation(snapshot: s, map: ctx.map)
        var monsterHits = 0
        sim.runHeadless(maxTime: s.time + 5) { ev in
            for e in ev {
                if case .damage(let d) = e, d.targetID == heroID, d.source == .monster { monsterHits += 1 }
            }
        }
        // 1.2 秒間隔で 5 秒 → 4 発前後
        XCTAssertGreaterThanOrEqual(monsterHits, 3)
        XCTAssertLessThanOrEqual(monsterHits, 5)
    }

    func testResetWhenAttackerDies() {
        var (s, ctx, m) = makeOpenField()
        let home = s.units[m].monster!.home
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: home + Vec2(300, 0))
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: m, amount: 700,
                                 type: .trueDamage, source: .basicAttack)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].attackTargetID, s.units[hero].id)
        s.units[m].pos = home + Vec2(200, 0)

        Kit.kill(&s, hero)
        MonsterSystem.update(&s, ctx)
        XCTAssertNil(s.units[m].attackTargetID)
        XCTAssertEqual(s.units[m].monster?.leashing, true)
        XCTAssertEqual(s.units[m].moveIntent, .point(home))
        s.units[m].pos = home
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].hp, s.units[m].stats.maxHP)
        XCTAssertEqual(s.units[m].monster?.leashing, false)
    }

    func testKeepsFightingWhenLastAttackerIsLostToSourcelessDamage() {
        var (s, ctx, m) = makeOpenField()
        let home = s.units[m].monster!.home
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: home + Vec2(300, 0))
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: m, amount: 500,
                                 type: .trueDamage, source: .basicAttack)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].attackTargetID, s.units[hero].id)
        let hpMidFight = s.units[m].hp
        // 発生源の無いダメージ（環境・持続ダメージ等）で lastAttackerID が消えても、交戦中の相手を追い続ける
        s.units[m].lastAttackerID = nil
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].attackTargetID, s.units[hero].id)
        XCTAssertEqual(s.units[m].monster?.leashing, false)
        XCTAssertEqual(s.units[m].hp, hpMidFight, "must not reset (full heal) mid-fight")
        // 交戦相手が倒れたらリセット（巣に居るのでその場で全回復）
        Kit.kill(&s, hero)
        MonsterSystem.update(&s, ctx)
        XCTAssertNil(s.units[m].attackTargetID)
        XCTAssertEqual(s.units[m].hp, s.units[m].stats.maxHP)
    }

    func testLeashClearsAndBlocksCrowdControl() {
        var (s, ctx, m) = makeOpenField()
        let home = s.units[m].monster!.home
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: home + Vec2(1200, 0))
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: m, amount: 100,
                                 type: .trueDamage, source: .basicAttack)
        CombatSystem.applyCC(&s, ctx, sourceID: s.units[hero].id, targetIndex: m, cc: .slow, isUltimate: false,
                             from: s.units[hero].pos)
        XCTAssertTrue(s.units[m].has(.slow))
        s.units[m].pos = home + Vec2(Balance.leashRadius + 10, 0)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].monster?.leashing, true)
        // リセット開始で弱体は外れ、帰還中は CC を受けない
        XCTAssertFalse(s.units[m].has(.slow))
        XCTAssertTrue(s.units[m].has(.ccImmune))
        CombatSystem.applyCC(&s, ctx, sourceID: s.units[hero].id, targetIndex: m, cc: .stun, isUltimate: true,
                             from: s.units[hero].pos)
        XCTAssertFalse(s.units[m].has(.stun))
        // 到着で保護は外れる
        s.units[m].pos = home
        MonsterSystem.update(&s, ctx)
        XCTAssertFalse(s.units[m].has(.ccImmune))
        XCTAssertFalse(s.units[m].has(.invulnerable))
    }

    func testBossesUseShorterLeash() {
        var (s, ctx, m) = makeOpenField(kind: .astralWyrm)
        let home = s.units[m].monster!.home
        let hero = Kit.addHero(&s, ctx, team: .blue, pos: home + Vec2(900, 0))
        CombatSystem.applyDamage(&s, ctx, sourceID: s.units[hero].id, targetIndex: m, amount: 10,
                                 type: .physical, source: .basicAttack)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].attackTargetID, s.units[hero].id)
        s.units[m].pos = home + Vec2(Balance.bossLeashRadius + 10, 0)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].monster?.leashing, true)

        // 通常モンスターは同じ距離では帰らない
        var (s2, ctx2, m2) = makeOpenField(kind: .campLarge)
        let home2 = s2.units[m2].monster!.home
        let h2 = Kit.addHero(&s2, ctx2, team: .blue, pos: home2 + Vec2(900, 0))
        CombatSystem.applyDamage(&s2, ctx2, sourceID: s2.units[h2].id, targetIndex: m2, amount: 10,
                                 type: .physical, source: .basicAttack)
        s2.units[m2].pos = home2 + Vec2(Balance.bossLeashRadius + 10, 0)
        MonsterSystem.update(&s2, ctx2)
        XCTAssertEqual(s2.units[m2].monster?.leashing, false)
        XCTAssertEqual(s2.units[m2].attackTargetID, s2.units[h2].id)
    }

    func testLeashingMonsterSteersAroundWalls() {
        var (s, ctx) = makeJungle()
        let m = monsterIndex(s, kind: .redSentinel, near: Vec2(6300, 3300))
        let home = s.units[m].monster!.home
        // 巣 (6300,3300) と壁 (5300..6900, 1950..2450) を挟んだ反対側（リーシュ範囲外）
        s.units[m].pos = Vec2(6100, 1800)
        MonsterSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].monster?.leashing, true)
        guard case .point(let p) = s.units[m].moveIntent else { return XCTFail("should walk home") }
        XCTAssertNotEqual(p, home)
        XCTAssertTrue(ctx.nav.hasLineOfSight(from: s.units[m].pos, to: p, radius: s.units[m].radius))

        let id = s.units[m].id
        let sim = Simulation(snapshot: s)
        sim.runHeadless(maxTime: s.time + 15)
        let u = sim.state.unit(id)!
        XCTAssertEqual(u.monster?.leashing, false)
        XCTAssertLessThan(u.pos.distance(to: home), Balance.monsterHomeTolerance + 1)
    }

    func testMonstersAreNeutralAndVisibleOnlyWhenLit() {
        var (s, ctx) = makeJungle()
        let m = monsterIndex(s, kind: .blueSentinel, near: Vec2(3300, 6300))
        VisionSystem.update(&s, ctx)
        XCTAssertEqual(s.units[m].team, .neutral)
        XCTAssertFalse(s.isVisible(m, to: .blue))
        XCTAssertFalse(s.isVisible(m, to: .red))
        Kit.addHero(&s, ctx, team: .blue, pos: Vec2(3300, 5700))
        VisionSystem.update(&s, ctx)
        XCTAssertTrue(s.isVisible(m, to: .blue))
        XCTAssertFalse(s.isVisible(m, to: .red))
    }
}
