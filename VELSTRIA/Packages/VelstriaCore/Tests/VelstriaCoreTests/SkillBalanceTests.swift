import XCTest
@testable import VelstriaCore

/// バランスのスモーク: ロール代表（H001–H006）同士の 1v1 を Lv 1/6/12（自動習得のランク）で戦わせ、
/// 通常攻撃 + CD 毎のスキルで決着までの時間（TTK）が 2.5〜15 秒に収まることを確認する。
/// 外れる場合は Balance.Skills の係数（SkillBalance.swift）で調整する（マスターデータは変えない）。
final class SkillBalanceTests: XCTestCase {
    static let representatives = ["H001", "H002", "H003", "H004", "H005", "H006"]
    static let levels = [1, 6, 12]
    static let minTTK = 2.5
    static let maxTTK = 15.0

    struct DuelResult {
        var ttk: Double
        /// 勝者（blue = a）。時間切れは nil。
        var winnerIsA: Bool?
        var remainingHPRatio: Double
    }

    /// a（blue）対 b（red）の 1v1。450 離れて開始し、互いに通常攻撃しつつ、使えるスキルを相手へ撃つ。
    static func duel(_ a: String, _ b: String, level: Int, maxSeconds: Double = 40) -> DuelResult {
        var w = SkillWorld()
        let axis = Vec2(1, 1).normalized
        let ia = w.addHero(a, team: .blue, at: skillArena - axis * 225, level: level, ranks: nil)
        let ib = w.addHero(b, team: .red, at: skillArena + axis * 225, level: level, ranks: nil)
        let start = w.s.time
        let order: [SkillSlot] = [.ultimate, .skill1, .skill2, .skill3]
        let ticks = Int(maxSeconds * Balance.tickRate)
        for _ in 0..<ticks {
            for (me, foe) in [(ia, ib), (ib, ia)] {
                guard w.s.units[me].isAlive, w.s.units[foe].isAlive else { continue }
                // 突進・跳躍中の相手には撃たない（着地を待つ）
                let foeMoving = w.s.units[foe].displacement != nil
                let foeID = w.s.units[foe].id
                if w.s.units[me].attackTargetID != foeID {
                    w.s.units[me].attackTargetID = foeID
                    w.s.units[me].moveIntent = .none
                }
                for slot in order where SkillSystem.canCast(w.s, w.ctx, heroIndex: me, slot: slot)
                    && !foeMoving && inReach(w, me, foe, slot) {
                    _ = SkillSystem.cast(&w.s, w.ctx, heroIndex: me, slot: slot, target: .unit(foeID))
                }
            }
            w.s.events.removeAll(keepingCapacity: true)
            w.tick()
            w.log.removeAll(keepingCapacity: true)
            let aDead = !w.s.units[ia].isAlive, bDead = !w.s.units[ib].isAlive
            if aDead || bDead {
                let winner: Bool? = aDead && bDead ? nil : bDead
                let survivor = bDead ? ia : ib
                return DuelResult(ttk: w.s.time - start, winnerIsA: winner, remainingHPRatio: w.s.units[survivor].hpRatio)
            }
        }
        return DuelResult(ttk: maxSeconds, winnerIsA: nil, remainingHPRatio: 1)
    }

    /// 相手がスキルの届く距離に居るか（AI と同じく、届かない時は撃たずに歩く）。
    static func inReach(_ w: SkillWorld, _ me: Int, _ foe: Int, _ slot: SkillSlot) -> Bool {
        let t = w.targeting(me, slot)
        let dist = w.s.units[me].pos.distance(to: w.s.units[foe].pos) - w.s.units[foe].radius
        switch t.archetype {
        case .selfAoE, .multiStrike, .teamHeal:
            return dist <= t.radius
        case .blinkEmpower:
            return dist <= t.range + w.s.units[me].stats.attackRange
        case .passive:
            return false
        default:
            return dist <= SkillAiming.autoAimReach(t)
        }
    }

    func testRolePairDuelTimeToKill() {
        let names = Self.representatives.map { MasterData.shared.hero($0)!.role.rawValue.prefix(3) }
        var failures: [String] = []
        var table = "TTK (秒) — 行 = blue, 列 = red\n"
        var minSeen = Double.infinity, maxSeen = 0.0
        for level in Self.levels {
            table += "Lv\(level)\t" + names.joined(separator: "\t") + "\n"
            for (x, a) in Self.representatives.enumerated() {
                table += "\(names[x])\t"
                for (y, b) in Self.representatives.enumerated() {
                    guard y >= x else { table += "-\t"; continue }
                    let r = Self.duel(a, b, level: level)
                    minSeen = min(minSeen, r.ttk)
                    maxSeen = max(maxSeen, r.ttk)
                    table += String(format: "%.1f\t", r.ttk)
                    if r.ttk < Self.minTTK || r.ttk > Self.maxTTK {
                        failures.append(String(format: "Lv%d %@ vs %@: %.2f s", level, a, b, r.ttk))
                    }
                }
                table += "\n"
            }
        }
        table += String(format: "min %.2f / max %.2f\n", minSeen, maxSeen)
        print(table)
        XCTAssertTrue(failures.isEmpty, "TTK が範囲外: \(failures)")
    }

    func testDuelIsDeterministic() {
        let a = Self.duel("H002", "H006", level: 6)
        let b = Self.duel("H002", "H006", level: 6)
        XCTAssertEqual(a.ttk, b.ttk)
        XCTAssertEqual(a.winnerIsA, b.winnerIsA)
        XCTAssertEqual(a.remainingHPRatio, b.remainingHPRatio)
    }
}
