import XCTest
@testable import VelstriaCore

/// バランスのスモーク: ロール代表（H001–H006）同士の 1v1 を Lv 1/6/12（自動習得のランク）で戦わせ、
/// 通常攻撃 + CD 毎のスキルで決着までの時間（TTK）が帯（minTTK〜maxTTK）に収まることを確認する。
/// スキルの数値は MLBB の値そのもの（キット = 公式の表、汎用 = MLBB のロール × 枠の型。docs/GENERIC_SKILLS.md）なので、
/// 外れても数値は直さない（帯の外れは実装の不具合か、帯の見直しのどちらか）。
///
/// 帯の見直し（2026-10-14、スキルの段階。Release の計測: Windows・`swift test -c release`）:
/// - 以前の帯 2.5〜22 秒（全員総当たりの絶対帯 2.0〜25 秒）は、スキルが MLBB の 2〜3 倍（スロット倍率 4.0 / 3.0 / 2.6、回復 × 2.4）だった尺度の帯。
///   倍率を外して MLBB の値にしたら、ロール代表の TTK は 4.1〜16.4 秒 → 10.5〜36.4 秒になった（Lv1 は 12.9〜26.2 秒）。
/// - 上限 22 → 38 秒: 伸びたのはタンク（ヴァンガード）とサポートの組（22〜36 秒）。MLBB の値ではタンクの HP 成長が大きく、サポートの奥義は
///   味方全体回復（MLBB のフローリンのブルームの 250 から）+ シールドで、装備なしの硬い同士・回復持ち同士は長引く（最長はサポート同士の Lv12 36.4 秒）。
///   38 秒は対戦の打ち切り（40 秒 = 引き分け）の手前で、引き分けになる組（決着がつかない不具合）を落とす。
/// - 下限 2.5 → 1.8 秒: 縮んだのはディアス（H032）の Lv6 / 12 の遠隔の柔らかい相手（H003 2.0〜2.1 秒、H030 2.2〜2.4 秒）。公式の値の
///   奥義 650〜1250 + 損失 HP の 25%・S1 の 3 連の爆発・ダメージ 1 回ごとの S1・S2 の CD −1 秒が重なる、MLBB のディアスのバーストそのもの。
///   1.8 秒は計測の最短（2.0 秒）の 1 割下で、一撃で倒れる（数 tick で決着する）不具合だけを落とす。
/// - 全員総当たり（ゲームに出す 10 体 = H025–H034）の絶対帯 2.0〜25 → 1.5〜40 秒（下限は上と同じ理由で 0.5 秒下げ、上限は打ち切りの 40 秒）。
///   分布（Release）: 中央値 Lv1 13.5 / Lv6 8.5 / Lv12 9.1 秒、最短 2.2 秒、最長 24.2 秒（フランコ同士の Lv12）。外れは 2% まで（変えていない）。
final class SkillBalanceTests: XCTestCase {
    static let representatives = ["H001", "H002", "H003", "H004", "H005", "H006"]
    static let levels = [1, 6, 12]
    static let minTTK = 1.8
    static let maxTTK = 38.0
    /// 全員総当たり（testFullRosterStaysNearBand）で 1 戦も外れてはいけない帯。
    static let hardMinTTK = 1.5
    static let hardMaxTTK = 40.0

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
        let order: [SkillSlot] = [.ultimate, .skill1, .skill2]
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
        if t.archetype == .blinkEmpower { return dist <= t.range + w.s.units[me].stats.attackRange }
        return dist <= t.reach
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

    /// 全 34 ヒーローの総当たり（Release のみ）。ロール代表以外も大きく外れないこと。
    func testFullRosterStaysNearBand() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter SkillBalanceTests")
        #else
        let ids = MasterData.shared.heroes.map(\.heroID)
        var total = 0
        var outside: [String] = []
        var hard: [String] = []
        var byLevel: [Int: [Double]] = [:]
        for level in Self.levels {
            for (x, a) in ids.enumerated() {
                for b in ids[x...] {
                    let r = Self.duel(a, b, level: level)
                    total += 1
                    byLevel[level, default: []].append(r.ttk)
                    let label = String(format: "Lv%d %@ vs %@: %.2f s", level, a, b, r.ttk)
                    if r.ttk < Self.minTTK || r.ttk > Self.maxTTK { outside.append(label) }
                    if r.ttk < Self.hardMinTTK || r.ttk > Self.hardMaxTTK { hard.append(label) }
                }
            }
        }
        // TTK の分布（帯を見直すときの根拠。レベル別の分位点）
        for level in Self.levels {
            let v = (byLevel[level] ?? []).sorted()
            guard !v.isEmpty else { continue }
            func q(_ p: Double) -> Double { v[min(v.count - 1, Int((Double(v.count - 1) * p).rounded()))] }
            print(String(format: "SkillBalanceTests roster Lv%d: n %d / min %.1f / p5 %.1f / p25 %.1f / median %.1f / p75 %.1f / p95 %.1f / max %.1f s",
                         level, v.count, v[0], q(0.05), q(0.25), q(0.5), q(0.75), q(0.95), v[v.count - 1]))
        }
        print("SkillBalanceTests roster: \(total) duels, \(outside.count) outside \(Self.minTTK)–\(Self.maxTTK) s: \(outside)")
        XCTAssertTrue(hard.isEmpty, "\(hard)")
        XCTAssertLessThanOrEqual(Double(outside.count), Double(total) * 0.02)
        #endif
    }

    func testDuelIsDeterministic() {
        let a = Self.duel("H002", "H006", level: 6)
        let b = Self.duel("H002", "H006", level: 6)
        XCTAssertEqual(a.ttk, b.ttk)
        XCTAssertEqual(a.winnerIsA, b.winnerIsA)
        XCTAssertEqual(a.remainingHPRatio, b.remainingHPRatio)
    }
}
