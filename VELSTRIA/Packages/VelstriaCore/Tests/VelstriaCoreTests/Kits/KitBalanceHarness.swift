import Foundation
import XCTest
@testable import VelstriaCore

// キットのヒーロー（H025–H034）のバランスを、汎用ヒーローと同じ物差しで測るハーネス（docs/SKILL_KITS.md の「バランス計測」）。
//
// 手順（1 つの対戦 = duel）:
//   - SkillWorld に 2 人を置く（本番のマップ・マスター・キット）。ユニットの操作は既存の SkillBalanceTests.duel と同じ
//     スクリプト: 通常攻撃 + 使えるスキルを（奥義 → スキル1 → スキル2 の順に）射程内なら相手へ撃つ。ボット AI は使わない。
//   - 40 秒で決着しなければ引き分け。同時に倒れても引き分け。引き分けは 0.5 勝として数える（どの集計でも）。
//   - 偏りを消すため、1 組を「両方の陣営の割り当て」(a が blue / a が red) × 開始距離 (300/450/600) × 乱数の種 (2 つ)
//     の 12 戦で平均する。
//   - 勝率 = 総当たり（自分以外の全ヒーロー）の平均スコア。レベルは 1/6/12（スキルは自動習得）。
// 同じ入力なら結果は常に同じ（決定論）。重い集計は Release のみ（KitBalanceTests）。

enum BalanceHarness {
    static let startDistances: [Double] = [300, 450, 600]
    static let seeds: [UInt64] = [1, 2]
    static let levels = [1, 6, 12]
    static let maxSeconds = 40.0

    // MARK: - 1 戦

    /// a 視点の得点（勝ち 1 / 引き分け 0.5 / 負け 0）。
    static func score(aDead: Bool, bDead: Bool) -> Double {
        if aDead == bDead { return 0.5 }
        return bDead ? 1 : 0
    }

    /// a 対 b の 1 戦。aIsBlue = a を blue 側（先に動く側）に置く。a 視点の得点を返す。
    static func duelScore(_ a: String, _ b: String, level: Int, distance: Double, seed: UInt64,
                          aIsBlue: Bool) -> Double {
        var w = SkillWorld(seed: seed)
        let axis = Vec2(1, 1).normalized
        let blueID = aIsBlue ? a : b
        let redID = aIsBlue ? b : a
        let ib = w.addHero(blueID, team: .blue, at: skillArena - axis * (distance / 2), level: level, ranks: nil)
        let ir = w.addHero(redID, team: .red, at: skillArena + axis * (distance / 2), level: level, ranks: nil)
        let ticks = Int(maxSeconds * Balance.tickRate)
        for _ in 0..<ticks {
            for (me, foe) in [(ib, ir), (ir, ib)] {
                guard w.s.units[me].isAlive, w.s.units[foe].isAlive else { continue }
                act(&w, me: me, foe: foe)
            }
            w.s.events.removeAll(keepingCapacity: true)
            w.tick()
            w.log.removeAll(keepingCapacity: true)
            let blueDead = !w.s.units[ib].isAlive, redDead = !w.s.units[ir].isAlive
            if blueDead || redDead {
                let aDead = aIsBlue ? blueDead : redDead
                let bDead = aIsBlue ? redDead : blueDead
                return score(aDead: aDead, bDead: bDead)
            }
        }
        return 0.5
    }

    /// 1 体の操作: 相手を攻撃対象にし、使えるスキルを射程内なら撃つ（既存の duel と同じ）。
    static func act(_ w: inout SkillWorld, me: Int, foe: Int) {
        // 突進・跳躍中の相手には撃たない（着地を待つ）
        let foeMoving = w.s.units[foe].displacement != nil
        let foeID = w.s.units[foe].id
        if w.s.units[me].attackTargetID != foeID {
            w.s.units[me].attackTargetID = foeID
            w.s.units[me].moveIntent = .none
        }
        for slot in [SkillSlot.ultimate, .skill1, .skill2]
        where SkillSystem.canCast(w.s, w.ctx, heroIndex: me, slot: slot) && !foeMoving
            && SkillBalanceTests.inReach(w, me, foe, slot) {
            _ = SkillSystem.cast(&w.s, w.ctx, heroIndex: me, slot: slot, target: .unit(foeID))
        }
    }

    // MARK: - 1 組・総当たり

    /// a 対 b の平均得点（a 視点）。両陣営 × 開始距離 × 種を平均する。pairScore(a, b) + pairScore(b, a) == 1。
    static func pairScore(_ a: String, _ b: String, level: Int) -> Double {
        var total = 0.0
        var n = 0
        for aIsBlue in [true, false] {
            for d in startDistances {
                for seed in seeds {
                    total += duelScore(a, b, level: level, distance: d, seed: seed, aIsBlue: aIsBlue)
                    n += 1
                }
            }
        }
        return total / Double(n)
    }

    /// 1 レベルぶんの総当たり: ヒーロー → 勝率（自分以外の全員に対する平均得点、0...1）。
    static func roundRobin(_ heroes: [String], level: Int, threads: Int = 4) -> [String: Double] {
        var pairs: [(Int, Int)] = []
        for x in heroes.indices { for y in (x + 1)..<max(x + 1, heroes.count) { pairs.append((x, y)) } }
        var scores = [Double](repeating: 0, count: pairs.count)
        let lock = NSLock()
        let width = max(1, threads)
        DispatchQueue.concurrentPerform(iterations: width) { worker in
            var k = worker
            while k < pairs.count {
                let s = pairScore(heroes[pairs[k].0], heroes[pairs[k].1], level: level)
                lock.lock()
                scores[k] = s
                lock.unlock()
                k += width
            }
        }
        var sum = [Double](repeating: 0, count: heroes.count)
        for (k, p) in pairs.enumerated() {
            sum[p.0] += scores[k]
            sum[p.1] += 1 - scores[k]
        }
        var out: [String: Double] = [:]
        let opponents = Double(max(1, heroes.count - 1))
        for (i, h) in heroes.enumerated() { out[h] = sum[i] / opponents }
        return out
    }

    static func median(_ values: [Double]) -> Double {
        let v = values.sorted()
        guard !v.isEmpty else { return 0 }
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }

    // MARK: - 瞬間火力（burst check）

    /// 手順: 攻撃側（指定レベル・スキル自動習得・資源 満タン・CD 0）を、動かない標的（ダミー）から distance 離して置き、
    /// 3 秒間、通常攻撃 + 使えるスキル全部（奥義から）を撃たせて、ダミーが受けたダメージの合計を返す。
    /// ダミーは既定で H001（ヴァンガード、最も硬い）。ダメージは防御・魔防込み（実ダメージ）。報告用で合否には使わない。
    static func burst(_ hero: String, level: Int, distance: Double, seconds: Double = 3,
                      dummy: String = "H001") -> Double {
        var w = SkillWorld()
        let axis = Vec2(1, 1).normalized
        let me = w.addHero(hero, team: .blue, at: skillArena - axis * (distance / 2), level: level, ranks: nil)
        let target = w.addHero(dummy, team: .red, at: skillArena + axis * (distance / 2), level: level, ranks: nil)
        for _ in 0..<Int((seconds * Balance.tickRate).rounded(.up)) {
            if w.s.units[me].isAlive, w.s.units[target].isAlive { act(&w, me: me, foe: target) }
            w.s.events.removeAll(keepingCapacity: true)
            w.tick()
        }
        return w.damage(to: target)
    }

    /// 開始距離 300 / 450 の平均。
    static func burstAverage(_ hero: String, level: Int) -> Double {
        let ds: [Double] = [300, 450]
        return ds.map { burst(hero, level: level, distance: $0) }.reduce(0, +) / Double(ds.count)
    }
}
