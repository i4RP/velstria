import XCTest
@testable import VelstriaCore

/// 調整用: 1 試合を回して時系列を表示する（BOT_DIAG=1 の時だけ）。
final class BotDiagnosticTests: XCTestCase {
    func testDiagnosticMatch() throws {
        guard ProcessInfo.processInfo.environment["BOT_DIAG"] != nil else { throw XCTSkip("BOT_DIAG=1 で実行") }
        let env = ProcessInfo.processInfo.environment
        let seed = UInt64(env["BOT_SEED"] ?? "1") ?? 1
        let diff = Difficulty(rawValue: Int(env["BOT_DIFF"] ?? "1") ?? 1) ?? .normal
        let cfg = env["BOT_HUMAN"] != nil
            ? MatchFactory.standardMatch(humanHeroID: "H003", humanName: "Idle", allyDifficulty: diff,
                                         enemyDifficulty: diff, seed: seed)
            : MatchFactory.botMatch(difficulty: diff, seed: seed)
        if let every = env["BOT_SNAP"].flatMap(Double.init) {
            snapshots(cfg, every: every, until: Double(env["BOT_UNTIL"] ?? "300") ?? 300)
            return
        }
        let r = BotMatchReport.run("seed \(seed) \(diff)", config: cfg, keepTimeline: true)
        print(BotMatchReport.tableHeader())
        print(r.tableRow)
        for l in r.heroLines { print(l) }
        for l in r.timeline { print(l) }
        print("decisions \(r.decisions) ticks \(r.ticks) end \(String(describing: r.endReason))")
    }

    func snapshots(_ cfg: MatchConfig, every: Double, until: Double) {
        let sim = Simulation(config: cfg)
        var next = every
        while !sim.isEnded && sim.state.time < until {
            sim.step()
            guard sim.state.time >= next else { continue }
            next += every
            let s = sim.state
            print(String(format: "--- %.0fs plans B:%@ R:%@", s.time, "\(s.bots.teams[0].plan.kind)",
                         "\(s.bots.teams[1].plan.kind)"))
            for i in s.heroIndices {
                let u = s.units[i]
                guard let h = u.hero, let m = s.bots.memory(for: u.id) else { continue }
                let target = s.unit(u.attackTargetID).map { "\($0.kind)#\($0.id) hp\(Int($0.hp))" } ?? "-"
                print(String(format: "%@ %@ %@ pos(%5.0f,%5.0f) hp%3.0f%% lv%d g%4.0f cs%d goal=%@ intent=%@ tgt=%@ items=%d",
                             "\(u.team)", h.heroID, "\(h.position)", u.pos.x, u.pos.y, u.hpRatio * 100, h.level,
                             h.gold, h.score.creepScore, "\(m.goal)", "\(u.moveIntent)", target, h.items.count))
            }
        }
    }

    /// 調整用: BotAI 単体の所要時間（状態のコピーに対して生成だけを計測）。
    func testDiagnosticBotCost() throws {
        guard ProcessInfo.processInfo.environment["BOT_COST"] != nil else { throw XCTSkip("BOT_COST=1 で実行") }
        let seed = UInt64(ProcessInfo.processInfo.environment["BOT_SEED"] ?? "1") ?? 1
        let sim = Simulation(config: MatchFactory.botMatch(difficulty: .normal, seed: seed))
        var botNs: UInt64 = 0
        var stepNs: UInt64 = 0
        var decisions = 0
        var worst: UInt64 = 0
        while !sim.isEnded && sim.state.time < 1500 {
            var copy = sim.state
            copy.tick += 1
            copy.time = Double(copy.tick) * Balance.dt
            let before = copy.bots.decisions
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = BotAI.generateCommands(&copy, sim.ctx)
            let dt = DispatchTime.now().uptimeNanoseconds - t0
            botNs += dt
            worst = max(worst, dt)
            decisions += copy.bots.decisions - before
            let t1 = DispatchTime.now().uptimeNanoseconds
            sim.step()
            stepNs += DispatchTime.now().uptimeNanoseconds - t1
        }
        let ticks = Double(sim.state.tick)
        print(String(format: "bot %.3f ms/tick, %.3f ms/decision, worst tick %.2f ms; step %.3f ms/tick",
                     Double(botNs) / 1e6 / ticks, Double(botNs) / 1e6 / Double(max(1, decisions)),
                     Double(worst) / 1e6, Double(stepNs) / 1e6 / ticks))
    }

    /// 調整用: 最初の 12 分の行動目標の時間配分（ポジション別）。
    func testDiagnosticGoals() throws {
        guard ProcessInfo.processInfo.environment["BOT_GOALS"] != nil else { throw XCTSkip("BOT_GOALS=1 で実行") }
        let seed = UInt64(ProcessInfo.processInfo.environment["BOT_SEED"] ?? "1") ?? 1
        let until = Double(ProcessInfo.processInfo.environment["BOT_UNTIL"] ?? "720") ?? 720
        let sim = Simulation(config: MatchFactory.botMatch(difficulty: .normal, seed: seed))
        var counts = [[Int]](repeating: [Int](repeating: 0, count: BotGoal.allCases.count + 1), count: 10)
        let heroes = sim.state.heroIndices
        while sim.state.time < until {
            sim.step()
            guard sim.state.tick % 30 == 0 else { continue }
            for (k, i) in heroes.enumerated() {
                if sim.state.units[i].hero!.isDead { counts[k][BotGoal.allCases.count] += 1; continue }
                let g = sim.state.bots.memory(for: sim.state.units[i].id)!.goal
                counts[k][g.rawValue] += 1
            }
        }
        let names = BotGoal.allCases.map { "\($0)" } + ["dead"]
        for (k, i) in heroes.enumerated() {
            let h = sim.state.units[i].hero!
            let parts = names.indices.filter { counts[k][$0] > 0 }.map { "\(names[$0])=\(counts[k][$0])" }
            print("\(sim.state.units[i].team) \(h.position) lv\(h.level): \(parts.joined(separator: " "))")
        }
    }

    /// 調整用: レーナーの近くで死んだ敵ミニオンのうち、本人がラストヒットした割合。
    func testDiagnosticLastHits() throws {
        guard ProcessInfo.processInfo.environment["BOT_LH"] != nil else { throw XCTSkip("BOT_LH=1 で実行") }
        let sim = Simulation(config: MatchFactory.botMatch(difficulty: .hard, seed: 1))
        var near = [Int](repeating: 0, count: 10), mine = [Int](repeating: 0, count: 10)
        var others: [String] = []
        let heroes = sim.state.heroIndices
        while sim.state.time < 360 {
            let before = sim.state
            for e in sim.step() {
                guard case .unitDied(_, let kind, let team, let killer, let pos) = e, kind == .minion else { continue }
                for (k, i) in heroes.enumerated() where before.units[i].team != team {
                    guard before.units[i].pos.distance(to: pos) < 1000, before.units[i].isAlive else { continue }
                    near[k] += 1
                    if killer == before.units[i].id { mine[k] += 1 } else {
                        others.append(before.unit(killer).map { "\($0.kind)" } ?? "nil")
                    }
                }
            }
        }
        for (k, i) in heroes.enumerated() {
            let h = sim.state.units[i].hero!
            print("\(sim.state.units[i].team) \(h.position) near \(near[k]) lastHit \(mine[k]) cs \(h.score.creepScore)")
        }
        for kind in ["minion", "hero", "tower", "nil"] { print(kind, others.filter { $0 == kind }.count) }
    }
}
