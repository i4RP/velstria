import XCTest
@testable import VelstriaCore

/// キットのヒーロー（H025–H034）の勝率を、同じロールの汎用ヒーロー（キットなし）の中央値と比べる（ハーネス: KitBalanceHarness.swift）。
/// 重い集計は Release のみ: swift test -c release --filter KitBalanceTests
final class KitBalanceTests: XCTestCase {
    /// 許容する差（勝率のパーセントポイント）。最初は広めに取り、キットの調整が済んだら絞る。
    static let bandLv1 = 45.0
    static let bandOther = 35.0
    /// 導入時点（キット調整前）で帯を外れていた組。"H026:12" = H026 の Lv12。表には出すが失敗にはしない。
    /// 各キットの調整が済んだら該当行を消して帯を守らせる（新しい外れ値は即失敗になる）。
    static let knownOutliers: Set<String> = []

    static var kitIDs: [String] { MasterData.shared.heroes.map(\.heroID).filter { HeroKits.hasKit($0) } }

    // MARK: - ハーネスの健全性（Debug でも走る軽いもの）

    func testScoringCountsDrawsAsHalf() {
        XCTAssertEqual(BalanceHarness.score(aDead: false, bDead: true), 1)
        XCTAssertEqual(BalanceHarness.score(aDead: true, bDead: false), 0)
        XCTAssertEqual(BalanceHarness.score(aDead: true, bDead: true), 0.5)
        XCTAssertEqual(BalanceHarness.score(aDead: false, bDead: false), 0.5)
        XCTAssertEqual(BalanceHarness.median([3, 1, 2]), 2)
        XCTAssertEqual(BalanceHarness.median([4, 1, 2, 3]), 2.5)
    }

    func testPairScoreIsSideNeutralAndAntisymmetric() {
        // 同じヒーロー同士は、陣営の割り当てを平均するとちょうど 0.5
        XCTAssertEqual(BalanceHarness.pairScore("H002", "H002", level: 6), 0.5, accuracy: 1e-12)
        let ab = BalanceHarness.pairScore("H002", "H006", level: 6)
        let ba = BalanceHarness.pairScore("H006", "H002", level: 6)
        XCTAssertEqual(ab + ba, 1, accuracy: 1e-12)
        // 決定論
        XCTAssertEqual(ab, BalanceHarness.pairScore("H002", "H006", level: 6))
    }

    func testKitHeroesAreInTheRosterAndRolesHaveGenericPeers() {
        let ids = MasterData.shared.heroes.map(\.heroID)
        XCTAssertEqual(Self.kitIDs.count, 10)
        for kit in Self.kitIDs {
            let role = MasterData.shared.hero(kit)!.role
            let peers = ids.filter { !HeroKits.hasKit($0) && MasterData.shared.hero($0)!.role == role }
            XCTAssertGreaterThanOrEqual(peers.count, 3, "\(kit) \(role)")
        }
    }

    func testBurstIsPositiveForEveryRosterHero() {
        // 軽い確認: 代表 3 体の 3 秒のダメージが 0 より大きい
        for id in ["H001", "H025", "H033"] {
            XCTAssertGreaterThan(BalanceHarness.burst(id, level: 6, distance: 300), 0, id)
        }
    }

    // MARK: - 勝率の表（Release のみ）

    func testKitWinRatesStayNearRoleMedians() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter KitBalanceTests")
        #else
        let started = Date()
        let master = MasterData.shared
        let ids = master.heroes.map(\.heroID)
        let kits = Self.kitIDs
        var rates: [Int: [String: Double]] = [:]
        for level in BalanceHarness.levels {
            rates[level] = BalanceHarness.roundRobin(ids, level: level)
        }
        func medianOfGenerics(_ role: Role, level: Int) -> Double {
            BalanceHarness.median(ids.filter { !HeroKits.hasKit($0) && master.hero($0)!.role == role }
                .map { rates[level]![$0]! })
        }

        var table = "KitBalance: 勝率 % (総当たり、両陣営 x 距離 300/450/600 x 種 \(BalanceHarness.seeds.count)、引き分け 0.5)\n"
        table += "kit    role       | Lv1   med   d    | Lv6   med   d    | Lv12  med   d\n"
        var failures: [String] = []
        var knownOut: [String] = []
        for kit in kits {
            let role = master.hero(kit)!.role
            var line = "\(kit)  " + role.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            for level in BalanceHarness.levels {
                let r = rates[level]![kit]! * 100
                let med = medianOfGenerics(role, level: level) * 100
                let delta = r - med
                line += String(format: " | %5.1f %5.1f %+6.1f", r, med, delta)
                let band = level == 1 ? Self.bandLv1 : Self.bandOther
                if abs(delta) > band {
                    let msg = String(format: "%@ Lv%d: %.1f%% vs role median %.1f%% (%+.1f pt, band %.0f)",
                                     kit, level, r, med, delta, band)
                    if Self.knownOutliers.contains("\(kit):\(level)") { knownOut.append(msg) } else { failures.append(msg) }
                }
            }
            table += line + "\n"
        }
        // 参考: 汎用ヒーローの勝率の分布（ロール別の中央値と最小・最大）
        table += "\n汎用ヒーロー（ロール別: 中央値 [最小 - 最大]）\n"
        for role in Role.allCases {
            let generic = ids.filter { !HeroKits.hasKit($0) && master.hero($0)!.role == role }
            guard !generic.isEmpty else { continue }
            var line = role.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            for level in BalanceHarness.levels {
                let v = generic.map { rates[level]![$0]! * 100 }
                line += String(format: " | Lv%-2d %5.1f [%5.1f - %5.1f]", level, BalanceHarness.median(v) , v.min()!, v.max()!)
            }
            table += line + "\n"
        }
        if !knownOut.isEmpty { table += "\n既知の外れ値（帯の外だが許容中）:\n" + knownOut.joined(separator: "\n") + "\n" }
        table += String(format: "\n(%.0f s)\n", Date().timeIntervalSince(started))
        print(table)
        XCTAssertTrue(failures.isEmpty, "勝率が同ロール中央値から外れている: \(failures)")
        #endif
    }

    // MARK: - 瞬間火力（報告のみ）

    func testBurstReport() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter KitBalanceTests")
        #else
        let master = MasterData.shared
        let ids = master.heroes.map(\.heroID)
        var table = "KitBurst: 開幕 3 秒にダミー(H001)へ与える実ダメージ（開始距離 300/450 の平均）。比 = 同ロール汎用ヒーローの中央値に対する倍率\n"
        table += "kit    role       | Lv1 dmg  ratio | Lv6 dmg  ratio | Lv12 dmg ratio\n"
        for kit in Self.kitIDs {
            let role = master.hero(kit)!.role
            var line = "\(kit)  " + role.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            for level in BalanceHarness.levels {
                let dmg = BalanceHarness.burstAverage(kit, level: level)
                let generic = ids.filter { !HeroKits.hasKit($0) && master.hero($0)!.role == role }
                    .map { BalanceHarness.burstAverage($0, level: level) }
                let med = BalanceHarness.median(generic)
                XCTAssertTrue(dmg.isFinite && dmg >= 0, "\(kit) Lv\(level)")
                line += String(format: " | %7.0f %5.2f", dmg, med > 0 ? dmg / med : 0)
            }
            table += line + "\n"
        }
        print(table)
        #endif
    }
}
