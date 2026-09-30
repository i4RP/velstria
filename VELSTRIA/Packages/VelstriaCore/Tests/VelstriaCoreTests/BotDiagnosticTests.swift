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
        if let from = env["BOT_TRACE"].flatMap(Double.init) {
            // 戦闘の細かい推移: 0.5 秒毎に全ヒーローの HP・目標・攻撃対象（1 行）
            let sim = Simulation(config: cfg)
            while !sim.isEnded && sim.state.time < from + 30 {
                let ev = sim.step()
                for e in ev {
                    if case .heroKilled(let k) = e { print(String(format: "%.1f KILL %d by %d", sim.state.time, k.victimID, k.killerID ?? -1)) }
                }
                guard sim.state.time >= from, sim.state.tick % 15 == 0 else { continue }
                var line = String(format: "%.1f", sim.state.time)
                for i in sim.state.heroIndices {
                    let u = sim.state.units[i]
                    let m = sim.state.bots.memory(for: u.id)
                    let g = m.map { "\($0.goal)".prefix(4) } ?? "-"
                    let t = u.attackTargetID.map { String($0) } ?? "."
                    line += String(format: " |%d%@ %3.0f%% %@>%@ (%4.0f,%4.0f)", u.id, u.team == .blue ? "b" : "r",
                                   u.hpRatio * 100, String(g), t, u.pos.x / 10, u.pos.y / 10)
                }
                print(line)
            }
            return
        }
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
            let cores = s.units.filter { $0.kind == .core }.map { "\($0.team):\(Int($0.hp))" }.joined(separator: " ")
            let minions = s.units.filter { $0.kind == .minion }
            let nearCore = Team.players.map { team in
                minions.filter { m in m.team != team && m.pos.distance(to: s.units.first { $0.kind == .core && $0.team == team }!.pos) < 1500 }.count
            }
            print(String(format: "--- %.0fs plans B:%@>%d R:%@>%d cores %@ enemyMinionsNearCore B:%d R:%d", s.time,
                         "\(s.bots.teams[0].plan.kind)", s.bots.teams[0].plan.targetID ?? -1,
                         "\(s.bots.teams[1].plan.kind)", s.bots.teams[1].plan.targetID ?? -1, cores,
                         nearCore[0], nearCore[1]))
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

    /// 調整用: 複数シードの要約（試合時間の分布・キル・Lv）。BOT_BATCH=シード数、BOT_DIFF=難易度、BOT_HUMAN=1 で人間枠あり。
    func testDiagnosticBatch() throws {
        let env = ProcessInfo.processInfo.environment
        guard let n = env["BOT_BATCH"].flatMap(Int.init) else { throw XCTSkip("BOT_BATCH=n で実行") }
        let diff = Difficulty(rawValue: Int(env["BOT_DIFF"] ?? "1") ?? 1) ?? .normal
        let base = UInt64(env["BOT_SEED"] ?? "1") ?? 1
        var durations: [Double] = []
        var lines: [String] = []
        var noKillTeams = 0
        var timeouts = 0
        var lowLevel = 0
        var posLevels = [Double](repeating: 0, count: 5)
        var posCounts = [Double](repeating: 0, count: 5)
        for k in 0..<n {
            let seed = base + UInt64(k)
            let cfg = env["BOT_HUMAN"] != nil
                ? MatchFactory.standardMatch(humanHeroID: "H003", humanName: "Idle", allyDifficulty: diff,
                                             enemyDifficulty: diff, seed: seed)
                : MatchFactory.botMatch(difficulty: diff, seed: seed)
            let r = BotMatchReport.run("seed \(seed) \(diff)", config: cfg)
            durations.append(r.duration)
            if r.endReason != .coreDestroyed { timeouts += 1 }
            if r.kills[0] == 0 || r.kills[1] == 0 { noKillTeams += 1 }
            if r.avgLevelAt12 < 9 { lowLevel += 1 }
            lines.append(r.tableRow)
            for h in r.heroes where h.isBot {
                posLevels[h.position.rawValue] += Double(h.levelAt12)
                posCounts[h.position.rawValue] += 1
            }
        }
        print("level@12 by position: " + LanePosition.allCases.map {
            String(format: "%@ %.1f", "\($0)", posLevels[$0.rawValue] / max(1, posCounts[$0.rawValue]))
        }.joined(separator: ", "))
        print(BotMatchReport.tableHeader())
        for l in lines { print(l) }
        let sorted = durations.sorted()
        let mean = durations.reduce(0, +) / Double(max(1, n))
        let over30 = durations.filter { $0 > 30 * 60 }.count
        print(String(format: "BATCH %@ n=%d mean %.1f min, median %.1f, max %.1f, >30min %d, timeouts %d, zero-kill teams %d, avgLv<9 %d",
                     "\(diff)", n, mean / 60, sorted[n / 2] / 60, (sorted.last ?? 0) / 60, over30, timeouts, noKillTeams,
                     lowLevel))
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
        let from = Double(ProcessInfo.processInfo.environment["BOT_FROM"] ?? "0") ?? 0
        var tfTicks = 0, tfInRange = 0, tfHeroTarget = 0, tfNoTarget = 0
        while sim.state.time < until && !sim.isEnded {
            sim.step()
            if sim.state.time >= from {
                for i in heroes {
                    let u = sim.state.units[i]
                    guard u.isAlive, sim.state.bots.memory(for: u.id)?.goal == .teamfight else { continue }
                    tfTicks += 1
                    guard let t = sim.state.index(of: u.attackTargetID) else { tfNoTarget += 1; continue }
                    if sim.state.units[t].kind == .hero { tfHeroTarget += 1 }
                    let reach = u.stats.attackRange + u.radius + sim.state.units[t].radius
                    if u.pos.distance(to: sim.state.units[t].pos) <= reach + 5 { tfInRange += 1 }
                }
            }
            guard sim.state.tick % 30 == 0, sim.state.time >= from else { continue }
            for (k, i) in heroes.enumerated() {
                if sim.state.units[i].hero!.isDead { counts[k][BotGoal.allCases.count] += 1; continue }
                let g = sim.state.bots.memory(for: sim.state.units[i].id)!.goal
                counts[k][g.rawValue] += 1
            }
        }
        print("teamfight ticks \(tfTicks) inRange \(tfInRange) heroTarget \(tfHeroTarget) noTarget \(tfNoTarget)")
        for i in heroes {
            let h = sim.state.units[i].hero!
            print(String(format: "%@ %@ dmgToHeroes %.0f taken %.0f towerDmg %.0f atk %.0f hp %.0f armor %.0f K/D/A %d/%d/%d",
                         "\(sim.state.units[i].team)", "\(h.position)", h.score.damageToHeroes, h.score.damageTaken,
                         h.score.towerDamage, sim.state.units[i].stats.attack, sim.state.units[i].stats.maxHP,
                         sim.state.units[i].stats.armor, h.score.kills, h.score.deaths, h.score.assists))
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
