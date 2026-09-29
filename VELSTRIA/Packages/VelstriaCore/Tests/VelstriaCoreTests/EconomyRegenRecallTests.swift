import XCTest
@testable import VelstriaCore

/// パッシブ Gold・自然回復・泉・帰還/帰還門（DESIGN §2, §4, §7, §8）。
final class EconomyRegenRecallTests: XCTestCase {
    private let center = Vec2(6000, 6000)

    private func ticks(_ seconds: Double) -> Int { Int((seconds / Balance.dt).rounded()) }

    // MARK: - Gold・回復

    func testPassiveGoldStartsAt20Seconds() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        f.s.tick = 0
        let g0 = f.hero(a).gold
        for _ in 0..<ticks(10) { f.economyTick() }
        XCTAssertEqual(f.hero(a).gold, g0)
        f.s.tick = ticks(20)
        for _ in 0..<ticks(10) { f.economyTick() }
        XCTAssertEqual(f.hero(a).gold - g0, 30, accuracy: 0.2)
        XCTAssertEqual(f.hero(a).score.goldEarned, 30, accuracy: 0.2)
        // 死亡中も入る
        f.s.units[a].isAlive = false
        f.s.units[a].hero!.respawnTimer = 30
        let g1 = f.hero(a).gold
        for _ in 0..<ticks(1) { f.economyTick() }
        XCTAssertEqual(f.hero(a).gold - g1, 3, accuracy: 0.05)
    }

    func testRegenHalvedInCombat() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        f.place(a, at: center)
        let maxHP = f.s.units[a].stats.maxHP
        let regen = f.s.units[a].stats.hpRegen
        f.s.units[a].hp = maxHP * 0.5
        for _ in 0..<ticks(1) { f.economyTick() }
        XCTAssertEqual(f.s.units[a].hp - maxHP * 0.5, regen, accuracy: 1e-6)
        let hp1 = f.s.units[a].hp
        f.s.units[a].lastCombatTime = f.s.time
        for _ in 0..<ticks(1) { f.economyTick() }
        XCTAssertEqual(f.s.units[a].hp - hp1, regen * 0.5, accuracy: 1e-6)
        XCTAssertTrue(EconomySystem.isInCombat(f.s, unitIndex: a))
    }

    func testResourceRegen() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        f.place(a, at: center)
        f.s.units[a].resource = 0
        let rr = f.s.units[a].stats.resourceRegen
        for _ in 0..<ticks(1) { f.economyTick() }
        XCTAssertEqual(f.s.units[a].resource, min(f.s.units[a].stats.maxResource, rr), accuracy: 1e-6)
    }

    func testFountainHealsAllies() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        f.place(a, at: f.ctx.map.fountain(.blue))
        let st = f.s.units[a].stats
        f.s.units[a].hp = st.maxHP * 0.3
        f.s.units[a].resource = 0
        for _ in 0..<ticks(1) { f.economyTick() }
        XCTAssertEqual(f.s.units[a].hp, st.maxHP * 0.4 + st.hpRegen, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[a].resource, min(st.maxResource, st.maxResource * 0.1 + st.resourceRegen),
                       accuracy: 1e-6)
    }

    func testEnemyFountainDealsTrueDamage() {
        var f = EconomyFixture.standard()
        let r = f.heroes(.red)[0]
        f.place(r, at: f.ctx.map.fountain(.blue))
        f.s.units[r].stats.armor = 500
        let hp0 = f.s.units[r].hp
        let regen = f.s.units[r].stats.hpRegen
        f.s.events.removeAll()
        for _ in 0..<10 { f.economyTick() }
        // 10 tick = 1/3 秒 → 333.3 の確定ダメージ（防御無視）
        XCTAssertEqual(hp0 - f.s.units[r].hp, 1000.0 / 3 - regen / 3, accuracy: 0.5)
        XCTAssertTrue(f.s.events.contains {
            if case .damage(let d) = $0 { return d.source == .fountain && d.damageType == .trueDamage }
            return false
        })
        // 味方の泉ではダメージなし
        let b = f.heroes(.blue)[0]
        f.place(b, at: f.ctx.map.fountain(.blue))
        let hpB = f.s.units[b].hp
        f.economyTick()
        XCTAssertGreaterThanOrEqual(f.s.units[b].hp, hpB)
        // 居続ければ死亡し、ヒーローの関与が無ければ処刑扱い
        for _ in 0..<ticks(5) where f.s.units[r].isAlive { f.economyTick() }
        XCTAssertFalse(f.s.units[r].isAlive)
        XCTAssertTrue(f.s.pendingDeaths.contains { $0.victimID == f.id(r) })
        let ev = f.processDeaths()
        XCTAssertNil(ev.heroKills.first?.killerID)
        XCTAssertGreaterThan(f.hero(r).respawnTimer, 0)
    }

    // MARK: - 帰還

    private func recallTick(_ f: inout EconomyFixture) -> [SimEvent] {
        f.s.tick += 1
        f.s.time = Double(f.s.tick) * Balance.dt
        f.s.events.removeAll()
        RecallSystem.update(&f.s, f.ctx)
        return f.s.events
    }

    func testRecallCompletesAfterSixSeconds() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        f.place(a, at: center)
        f.s.units[a].hp = 10
        RecallSystem.startRecall(&f.s, f.ctx, heroIndex: a)
        XCTAssertEqual(f.hero(a).channel?.total, Balance.recallChannel)
        var done = false
        var elapsed = 0
        while !done && elapsed < ticks(7) {
            elapsed += 1
            done = recallTick(&f).contains { if case .channelCompleted(_, .recall, _) = $0 { return true }; return false }
        }
        XCTAssertTrue(done)
        XCTAssertEqual(Double(elapsed) * Balance.dt, Balance.recallChannel, accuracy: Balance.dt * 1.01)
        XCTAssertTrue(f.ctx.map.isInFountain(f.s.units[a].pos, team: .blue))
        XCTAssertNil(f.hero(a).channel)
        // 到着時の回復はしない（泉の回復は EconomySystem）
        XCTAssertEqual(f.s.units[a].hp, 10)
    }

    func testEmpoweredRecallWithColossusBlessing() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        f.place(a, at: center)
        f.s.units[a].statuses.append(StatusEffect(kind: .colossusBlessing, duration: 100, magnitude: 0.15))
        RecallSystem.startRecall(&f.s, f.ctx, heroIndex: a)
        XCTAssertEqual(f.hero(a).channel?.total, Balance.empoweredRecallChannel)
        for _ in 0..<ticks(2) { _ = recallTick(&f) }
        XCTAssertTrue(f.ctx.map.isInFountain(f.s.units[a].pos, team: .blue))
    }

    func testDamageCancelsRecallButEarlierDamageDoesNot() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        f.place(a, at: center)
        // 詠唱開始より前の tick に受けたダメージでは中断しない
        f.s.units[a].lastDamagedTime = f.s.time
        RecallSystem.startRecall(&f.s, f.ctx, heroIndex: a)
        _ = recallTick(&f)
        XCTAssertNotNil(f.hero(a).channel)
        for _ in 0..<ticks(1) { _ = recallTick(&f) }
        XCTAssertNotNil(f.hero(a).channel)
        // 詠唱中の被ダメ（この tick の戦闘処理）→ 次の tick で中断
        f.s.units[a].lastDamagedTime = f.s.time
        let ev = recallTick(&f)
        XCTAssertNil(f.hero(a).channel)
        XCTAssertTrue(ev.contains(.channelCanceled(heroID: f.id(a), kind: .recall)))
        XCTAssertEqual(f.s.units[a].pos, center)
    }

    func testStunCancelsRecall() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        f.place(a, at: center)
        RecallSystem.startRecall(&f.s, f.ctx, heroIndex: a)
        f.s.units[a].statuses.append(StatusEffect(kind: .stun, duration: 1))
        _ = recallTick(&f)
        XCTAssertNil(f.hero(a).channel)
        // 行動不能中は開始できない
        RecallSystem.startRecall(&f.s, f.ctx, heroIndex: a)
        XCTAssertNil(f.hero(a).channel)
    }

    // MARK: - 帰還門

    func testTeleportDestinationValidation() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        let tower = f.tower(team: .blue, lane: .mid, tier: .outer)
        let tpos = f.s.units[tower].pos
        // 何もない場所・敵タワーは不可
        XCTAssertNil(RecallSystem.teleportDestination(f.s, f.ctx, heroIndex: a, requested: center))
        let enemy = f.tower(team: .red, lane: .mid, tier: .outer)
        XCTAssertNil(RecallSystem.teleportDestination(f.s, f.ctx, heroIndex: a, requested: f.s.units[enemy].pos))
        // 味方タワー 400 以内はそのまま
        let near = tpos + Vec2(300, 0)
        XCTAssertEqual(RecallSystem.teleportDestination(f.s, f.ctx, heroIndex: a, requested: near), near)
        XCTAssertNil(RecallSystem.teleportDestination(f.s, f.ctx, heroIndex: a, requested: tpos + Vec2(450, 0)))
        // タワー真上は衝突半径の外へ
        let onTop = RecallSystem.teleportDestination(f.s, f.ctx, heroIndex: a, requested: tpos)!
        let d = onTop.distance(to: tpos)
        XCTAssertGreaterThanOrEqual(d, f.s.units[tower].radius + f.s.units[a].radius)
        XCTAssertLessThanOrEqual(d, Balance.Economy.teleportTowerRadius)
        // 泉は可
        let fountain = f.ctx.map.fountain(.blue) + Vec2(100, 100)
        XCTAssertEqual(RecallSystem.teleportDestination(f.s, f.ctx, heroIndex: a, requested: fountain), fountain)
        // 破壊済みタワーは不可
        f.s.units[tower].isAlive = false
        XCTAssertNil(RecallSystem.teleportDestination(f.s, f.ctx, heroIndex: a, requested: near))
    }

    func testTeleportInvalidDestinationFails() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0]
        f.s.events.removeAll()
        RecallSystem.startTeleport(&f.s, f.ctx, heroIndex: a, destination: center, duration: 3)
        XCTAssertNil(f.hero(a).channel)
        XCTAssertTrue(f.s.events.contains(.channelCanceled(heroID: f.id(a), kind: .teleport)))
    }

    func testTeleportCompletesAndFailsIfTowerFalls() {
        var f = EconomyFixture.standard()
        let a = f.heroes(.blue)[0], b = f.heroes(.blue)[1]
        f.place(a, at: center)
        f.place(b, at: center)
        let tower = f.tower(team: .blue, lane: .top, tier: .outer)
        let dest = f.s.units[tower].pos + Vec2(200, 0)
        RecallSystem.startTeleport(&f.s, f.ctx, heroIndex: a, destination: dest, duration: 3)
        XCTAssertEqual(f.hero(a).channel?.kind, .teleport)
        for _ in 0..<ticks(3) { _ = recallTick(&f) }
        XCTAssertNil(f.hero(a).channel)
        XCTAssertEqual(f.s.units[a].pos, dest)

        RecallSystem.startTeleport(&f.s, f.ctx, heroIndex: b, destination: dest, duration: 3)
        _ = recallTick(&f)
        f.s.units[tower].isAlive = false
        var canceled = false
        for _ in 0..<ticks(3) {
            canceled = canceled || recallTick(&f).contains(.channelCanceled(heroID: f.id(b), kind: .teleport))
        }
        XCTAssertTrue(canceled)
        XCTAssertEqual(f.s.units[b].pos, center)
    }
}
