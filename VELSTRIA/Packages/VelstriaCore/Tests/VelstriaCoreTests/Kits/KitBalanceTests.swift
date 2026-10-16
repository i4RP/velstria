import XCTest
@testable import VelstriaCore

/// キットのヒーロー（H025–H034 = MLBB のヒーロー）の勝率を、同じ MLBB のロールの汎用ヒーロー（キットなし）の中央値と比べる
/// （ハーネス: KitBalanceHarness.swift）。重い集計は Release のみ: swift test -c release --filter KitBalanceTests
///
/// 2026-10-14（スキルの段階）からキットは公式の表そのまま（換算なし）なので、勝率を帯に合わせる調整はしない。この表は
/// 「MLBB のヒーロー」と「MLBB のスキルの中央値の型を持つ汎用ヒーロー（docs/GENERIC_SKILLS.md）」の差を見る物差しになった。
/// 帯（±45 / ±35）は変えていない。外れた組は理由を書いて knownOutliers に置く（新しい外れ値は即失敗になる）。
final class KitBalanceTests: XCTestCase {
    /// 許容する差（勝率のパーセントポイント）。
    static let bandLv1 = 45.0
    static let bandOther = 35.0
    /// 帯を外れているが許している組（"H026:12" = H026 の Lv12）。表には出すが失敗にはしない。2026-10-14 の Release の計測（差、pt）:
    /// - H026 エウドラ Lv6 +75.8・Lv12 +75.8、H031 オーロラ Lv1 +81.6・Lv6 +75.0・Lv12 +77.0: 汎用のアルカニスト（MLBB のメイジの型）は
    ///   ダメージのスキルが実質スキル1 と奥義だけ（遠隔のスキル2 はブリンク + 強化通常攻撃）で、装備なしでは魔法攻撃 0 なので基礎値だけ。
    ///   MLBB のメイジの 2 体はスキル1・2 とも多段のダメージ（エウドラの鎖・オーロラの雹と凍結エリア）を持つので大きく勝ち越す（汎用の中央値 4.5〜10.4%）。
    /// - H028 セイバー Lv6 +63.4・Lv12 +62.5、H033 アルカード Lv6 +53.3・Lv12 +56.4: MLBB のアサシンの 2 体は多段（剣の接触 9 回・剣撃・三連撃、
    ///   S2 の 4〜6 秒の CD と奥義後の CD 半減・混合吸収）。汎用のアサシンは扇形・突進・背後への各 1 撃（中央値 31%）。
    ///   アルカードは 2026-10-16 に幾何と時間を動画の値にした後 Lv6 +51.3・Lv12 +55.9（吸収が向きの帯・衝撃波に振りかぶり。docs/kits/Alucard.md）。
    /// - H029 ティグラル Lv12 +43.4: MLBB のタンク（HP 成長 307）で奥義 3 段目の 1000 (+130%)。比べるのは MLBB のタンクの型の汎用ヒーロー
    ///   （ヴァンガード。Velstria のロールはサポートのまま: peerRole）。以前の基準（汎用サポート）では Lv1 +66.7・Lv6 +65.7・Lv12 +61.7。
    /// （H034 フランコはヴァンガードと比べると Lv6 +22.0・Lv12 +24.7 で帯の中。以前の H034:6 / H034:12 の外れ値は外した）
    static let knownOutliers: Set<String> = ["H026:6", "H026:12", "H028:6", "H028:12", "H029:12", "H031:1", "H031:6", "H031:12",
                                             "H033:6", "H033:12"]

    static var kitIDs: [String] { MasterData.shared.allHeroes.map(\.heroID).filter { HeroKits.hasKit($0) } }

    /// 比べる汎用ヒーローのロール = MLBB のロール（2026-10-14）。ティグラル（H029）とフランコ（H034）は MLBB ではタンクで、能力値も
    /// MLBB のタンクの値（HP 成長 307 / 281）。Velstria のロールはサポートのままだが、汎用のサポートは MLBB のサポートの中央値（遠隔・HP 成長 174）なので、
    /// MLBB のタンクの中央値の汎用ヒーロー（ヴァンガード）と比べる。ほかの 8 体は Velstria のロールが MLBB のロールと同じ。
    static func peerRole(_ kit: String) -> Role {
        switch kit {
        case "H029", "H034": return .vanguard
        default: return MasterData.shared.hero(kit)!.role
        }
    }

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
        let ids = MasterData.shared.allHeroes.map(\.heroID)
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
        let ids = master.allHeroes.map(\.heroID)
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
            let role = Self.peerRole(kit)
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

    // MARK: - ゲームに出す 10 体（MLBB のヒーロー）同士の総当たり（Release のみ）

    /// ゲームに出すヒーロー（HeroRoster.activeHeroIDs = H025–H034。全員 MLBB の公式の値）同士の総当たりの勝率（報告のみ。
    /// 公式の値の組み合わせの結果なので帯で縛らない。2026-10-14: ディアス 100 / 100 / 100%、ミヤ 30 / 0 / 0%（Lv1 / 6 / 12）。docs/SKILL_KITS.md）。
    func testActiveRosterRoundRobin() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter KitBalanceTests")
        #else
        let ids = HeroRoster.activeHeroIDs
        var table = "Active roster: 勝率 % (H025–H034 同士の総当たり、両陣営 x 距離 300/450/600 x 種 \(BalanceHarness.seeds.count))\n"
        table += "hero  | Lv1   | Lv6   | Lv12\n"
        var rates: [Int: [String: Double]] = [:]
        for level in BalanceHarness.levels { rates[level] = BalanceHarness.roundRobin(ids, level: level) }
        for id in ids {
            table += id + " " + BalanceHarness.levels.map { String(format: " | %5.1f", rates[$0]![id]! * 100) }.joined() + "\n"
        }
        print(table)
        #endif
    }

    // MARK: - 瞬間火力（報告のみ）

    func testBurstReport() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter KitBalanceTests")
        #else
        let master = MasterData.shared
        let ids = master.allHeroes.map(\.heroID)
        var table = "KitBurst: 開幕 3 秒にダミー(H001)へ与える実ダメージ（開始距離 300/450 の平均）。比 = 同ロール汎用ヒーローの中央値に対する倍率\n"
        table += "kit    role       | Lv1 dmg  ratio | Lv6 dmg  ratio | Lv12 dmg ratio\n"
        for kit in Self.kitIDs {
            let role = Self.peerRole(kit)
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
