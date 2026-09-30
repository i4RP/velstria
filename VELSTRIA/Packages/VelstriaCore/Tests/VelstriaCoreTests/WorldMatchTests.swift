import XCTest
@testable import VelstriaCore

/// ヒーロー抜き（ミニオン・構造物・中立のみ）の標準戦を 12 分回す統合テスト（外塔の序盤保護と裏取り保護があるため、ミニオンだけでは 10 分台前半に最初の塔が落ちる）。
/// 長時間のため Release で実行する: swift test -c release --filter WorldMatchTests
final class WorldMatchTests: XCTestCase {
    struct Digest: Equatable {
        var tick: Int
        var ids: [EntityID]
        var positions: [Vec2]
        var hps: [Double]
        var rng: SplitMix64
        var world: WorldState
    }

    func digest(_ s: SimState) -> Digest {
        Digest(tick: s.tick, ids: s.units.map(\.id), positions: s.units.map(\.pos), hps: s.units.map(\.hp),
               rng: s.rng, world: s.world)
    }

    func testMinionsOnlyMatchRunsTwelveMinutesDeterministicallyAndTowersFall() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter WorldMatchTests")
        #else
        let cfg = MatchConfig(mode: .standard, seed: 20260928, players: [])
        let a = Simulation(config: cfg)
        let b = Simulation(config: cfg)
        var destroyed: [(team: Team, lane: Lane?, tier: TowerTier?, time: Double)] = []
        var waves = 0
        var campsKilled = 0
        let t0 = DispatchTime.now().uptimeNanoseconds
        a.runHeadless(maxTime: 720) { ev in
            for e in ev {
                switch e {
                case .structureDestroyed(_, _, let team, let lane, let tier, _):
                    destroyed.append((team, lane, tier, a.state.time))
                case .waveSpawned: waves += 1
                case .unitDied(_, let kind, _, _, _) where kind == .monster: campsKilled += 1
                default: break
                }
            }
        }
        let msPerTick = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6 / Double(a.state.tick)
        b.runHeadless(maxTime: 720)

        XCTAssertEqual(a.state.tick, 21600)
        XCTAssertEqual(digest(a.state), digest(b.state), "same config must give identical state")
        XCTAssertEqual(waves, 24)
        XCTAssertEqual(campsKilled, 0, "nobody attacks neutral camps in a minions-only match")
        XCTAssertFalse(destroyed.isEmpty, "at least one tower should fall within 12 minutes")
        // 外塔から順に落ちる（無敵の順序）
        for d in destroyed where d.tier != .outer {
            let outerDown = destroyed.contains { $0.team == d.team && $0.lane == d.lane && $0.tier == .outer && $0.time <= d.time }
            XCTAssertTrue(outerDown, "\(d) fell before its outer tower")
        }
        // ミニオンは障害物に埋まらず、レーン付近に留まる
        for u in a.state.units where u.kind == .minion {
            XCTAssertTrue(a.ctx.nav.isWalkable(u.pos), "\(u.pos)")
            XCTAssertLessThan(a.ctx.map.distanceToLane(u.pos, lane: u.minion!.lane), Balance.minionLaneChaseLimit + 200)
        }
        XCTAssertLessThan(msPerTick, 1.0, "tick budget")
        print(String(format: "minions-only 10 min: %d structures down, %.3f ms/tick", destroyed.count, msPerTick))
        for d in destroyed {
            print("  \(d.team) \(String(describing: d.lane)) \(String(describing: d.tier)) at \(Int(d.time))s")
        }
        #endif
    }
}
