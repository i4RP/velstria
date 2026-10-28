import XCTest
@testable import VelstriaCore

/// 遊ぶ地図（canyon。`MapDefinition.map(for:)`）でボット同士の試合を最後まで回し、試合時間の要件を確かめ、塔が倒れる時刻を記録する。
/// BotMatchTests は standard の地図で動くので、canyon の試合時間はここで見る（docs/TOWER_BASE_MLBB.md「確かめ」）。
/// 長時間のため Release で実行する: swift test -c release --filter CanyonMatchTests
final class CanyonMatchTests: XCTestCase {
    static let seeds: [UInt64] = [3, 6, 12]

    func testCanyonBotMatchesTowerFallTimes() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter CanyonMatchTests")
        #else
        var reports: [BotMatchReport] = []
        for seed in Self.seeds {
            for difficulty in [Difficulty.normal, .hard] {
                let cfg = MatchFactory.botMatch(difficulty: difficulty, seed: seed)
                reports.append(BotMatchReport.run("canyon seed \(seed) \(difficulty)", config: cfg,
                                                  map: .canyon))
            }
        }
        print(BotMatchReport.fallHeader())
        for r in reports { print(r.fallRow) }
        var peak: [[Int]] = [[0, 0, 0], [0, 0, 0]]
        for r in reports {
            for t in 0..<2 { for k in 0..<3 { peak[t][k] = max(peak[t][k], r.maxMinions[t][k]) } }
        }
        print("max minions alive per team (melee/ranged/siege): blue \(peak[0]) red \(peak[1])")
        for r in reports {
            XCTAssertEqual(r.endReason, .coreDestroyed, "\(r.label) must end by core destruction")
            XCTAssertGreaterThanOrEqual(r.duration, 8 * 60, "\(r.label) too short")
            XCTAssertLessThanOrEqual(r.duration, 30 * 60, "\(r.label) too long")
            // 内塔が落ちてからベースまでが 1 回の復活の時間で終わらない（2026-10-21 の崩れ: 8:38 → 8:44 → 8:50）
            if let inner = r.firstFall(tier: 1), let base = r.firstFall(tier: 3) {
                XCTAssertGreaterThanOrEqual(base - inner, 60, "\(r.label) base fell within a minute of the first inner turret")
            }
        }
        #endif
    }
}
