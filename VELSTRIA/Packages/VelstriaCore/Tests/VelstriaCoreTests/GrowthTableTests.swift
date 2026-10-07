import XCTest
@testable import VelstriaCore

/// 0〜10 分のロール別成長表の計測（参照仕様の Phase 1）。ボット同士の試合を回し、チェックポイント毎に
/// ロール（レーン位置）別の平均 Lv・累計 Gold・CS と、Lv4 到達時刻を表にして print する。値の判定はしない（計測専用）。
/// 長時間のため Release で実行する: swift test -c release --filter GrowthTableTests
final class GrowthTableTests: XCTestCase {
    static let seeds: [UInt64] = [1, 6, 11, 16]
    static let checkpoints: [Double] = [30, 60, 120, 180, 300, 480, 600]

    private struct Sample {
        var level: Double = 0
        var gold: Double = 0
        var cs: Double = 0
        var kills: Double = 0
        var n: Double = 0
    }

    func testPrintGrowthTable() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter GrowthTableTests")
        #else
        let positions = LanePosition.allCases
        // [ロール][チェックポイント]
        var table = Array(repeating: Array(repeating: Sample(), count: Self.checkpoints.count), count: positions.count)
        var lv4: [[Double]] = Array(repeating: [], count: positions.count)
        var lv4Missing = Array(repeating: 0, count: positions.count)

        for seed in Self.seeds {
            let sim = Simulation(config: MatchFactory.botMatch(difficulty: .normal, seed: seed))
            let heroIdx = sim.state.heroIndices
            var reachedLv4: [Double?] = Array(repeating: nil, count: heroIdx.count)
            var next = 0
            while !sim.isEnded && sim.state.time < Self.checkpoints.last! + 1 {
                _ = sim.step()
                for (k, i) in heroIdx.enumerated() where reachedLv4[k] == nil {
                    if sim.state.units[i].hero!.level >= 4 { reachedLv4[k] = sim.state.time }
                }
                if next < Self.checkpoints.count, sim.state.time >= Self.checkpoints[next] {
                    for i in heroIdx {
                        let h = sim.state.units[i].hero!
                        let p = h.position.rawValue
                        table[p][next].level += Double(h.level)
                        table[p][next].gold += Balance.startingGold + h.score.goldEarned
                        table[p][next].cs += Double(h.score.creepScore)
                        table[p][next].kills += Double(h.score.kills)
                        table[p][next].n += 1
                    }
                    next += 1
                }
            }
            for (k, i) in heroIdx.enumerated() {
                let p = sim.state.units[i].hero!.position.rawValue
                if let t = reachedLv4[k] { lv4[p].append(t) } else { lv4Missing[p] += 1 }
            }
        }

        let head = Self.checkpoints.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) }
        for (title, pick, fmt) in [
            ("平均 Lv", { (s: Sample) in s.level / max(1, s.n) }, "%.1f"),
            ("平均 累計 Gold（開始 300 込み）", { (s: Sample) in s.gold / max(1, s.n) }, "%.0f"),
            ("平均 CS（ミニオン+モンスター）", { (s: Sample) in s.cs / max(1, s.n) }, "%.1f"),
            ("平均 キル数", { (s: Sample) in s.kills / max(1, s.n) }, "%.2f"),
        ] as [(String, (Sample) -> Double, String)] {
            print("\n### GROWTH \(title)（seeds \(Self.seeds.count) × 両陣営、normal）")
            print("| role | " + head.joined(separator: " | ") + " |")
            print("|---|" + head.map { _ in "---|" }.joined())
            for p in positions {
                let cells = table[p.rawValue].map { String(format: fmt, pick($0)) }
                print("| \(p) | " + cells.joined(separator: " | ") + " |")
            }
        }
        print("\n### GROWTH Lv4 到達時刻（秒）")
        print("| role | 平均 | 最短 | 最長 | 10 分までに未到達 |")
        print("|---|---|---|---|---|")
        for p in positions {
            let xs = lv4[p.rawValue]
            let avg = xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
            print(String(format: "| %@ | %.0f | %.0f | %.0f | %d |", "\(p)", avg, xs.min() ?? 0, xs.max() ?? 0, lv4Missing[p.rawValue]))
        }
        XCTAssertFalse(table.flatMap { $0 }.allSatisfy { $0.n == 0 }, "no samples were taken")
        #endif
    }
}
