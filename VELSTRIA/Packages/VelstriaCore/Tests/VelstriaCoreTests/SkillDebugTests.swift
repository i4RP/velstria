import XCTest
@testable import VelstriaCore

final class SkillDebugRosterTests: XCTestCase {
    func testDebugRoster() {
        let ids = MasterData.shared.heroes.map(\.heroID)
        for level in [1, 6, 12] {
            var lo = (99.0, ""), hi = (0.0, "")
            var out: [String] = []
            for (x, a) in ids.enumerated() {
                for b in ids[x...] {
                    let r = SkillBalanceTests.duel(a, b, level: level)
                    if r.ttk < lo.0 { lo = (r.ttk, "\(a)-\(b)") }
                    if r.ttk > hi.0 { hi = (r.ttk, "\(a)-\(b)") }
                    if r.ttk < 2.5 || r.ttk > 15 { out.append("\(a)-\(b):\(String(format: "%.1f", r.ttk))") }
                }
            }
            print("ROSTER L\(level) min \(lo) max \(hi) out \(out.count) \(out.prefix(12))")
        }
    }
}

final class SkillDebugTests: XCTestCase {
    func testDebugDuel() {
        let env = ProcessInfo.processInfo.environment
        let a = env["DUEL_A"] ?? "H001", b = env["DUEL_B"] ?? "H001"
        for level in [1, 6, 12] {
            var w = SkillWorld()
            let axis = Vec2(1, 1).normalized
            let ia = w.addHero(a, team: .blue, at: skillArena - axis * 225, level: level, ranks: nil)
            let ib = w.addHero(b, team: .red, at: skillArena + axis * 225, level: level, ranks: nil)
            print("ranks", w.s.units[ia].hero!.skillRanks, "hp", w.s.units[ia].stats.maxHP, "mana", w.s.units[ia].resource)
            var casts = [0, 0]
            for _ in 0..<(30 * 30) {
                for (me, foe) in [(ia, ib), (ib, ia)] {
                    guard w.s.units[me].isAlive, w.s.units[foe].isAlive else { continue }
                    let foeID = w.s.units[foe].id
                    if w.s.units[me].attackTargetID != foeID {
                        w.s.units[me].attackTargetID = foeID
                        w.s.units[me].moveIntent = .none
                    }
                    for slot in [SkillSlot.ultimate, .skill1, .skill2, .skill3]
                    where SkillSystem.canCast(w.s, w.ctx, heroIndex: me, slot: slot) {
                        if SkillSystem.cast(&w.s, w.ctx, heroIndex: me, slot: slot, target: .unit(foeID)) {
                            casts[me == ia ? 0 : 1] += 1
                        }
                    }
                }
                w.flushEvents()
                w.tick()
                if !w.s.units[ia].isAlive || !w.s.units[ib].isAlive { break }
            }
            for (x, t) in [(0, ib), (1, ia)] {
                var bySource: [String: Double] = [:]
                for d in w.damageEvents where d.targetID == w.id(t) { bySource["\(d.source)", default: 0] += d.amount }
                let heal = w.log.reduce(0.0) { acc, e in
                    if case .heal(let id, _, let amt) = e, id == w.id(t) { return acc + amt }
                    return acc
                }
                let shield = w.log.reduce(0.0) { acc, e in
                    if case .shieldGained(let id, _, let amt) = e, id == w.id(t) { return acc + amt }
                    return acc
                }
                print("L\(level) t=\(String(format: "%.2f", w.s.time - 1)) side\(x) casts=\(casts[x]) victimHP=\(Int(w.s.units[t].hp)) heal=\(Int(heal)) shield=\(Int(shield)) dmg=\(bySource.sorted { $0.key < $1.key }.map { "\($0.key)=\(Int($0.value))" })")
            }
        }
    }
}
