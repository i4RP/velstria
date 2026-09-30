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
}
