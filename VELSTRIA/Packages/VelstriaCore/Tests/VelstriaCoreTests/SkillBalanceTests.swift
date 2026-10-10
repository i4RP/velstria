import XCTest
@testable import VelstriaCore

/// バランスのスモーク: ロール代表（H001–H006）同士の 1v1 を Lv 1/6/12（自動習得のランク）で戦わせ、
/// 通常攻撃 + CD 毎のスキルで決着までの時間（TTK）が 2.5〜20 秒に収まることを確認する。
/// 外れる場合は Balance.Skills の係数（SkillBalance.swift）で調整する（マスターデータは変えない）。
///
/// 帯の根拠: スキルのクールダウンは Mobile Legends と同じ秒数（Balance.Skills.cooldownScale = 1.0）。MLBB の装備なしの 1v1 は
/// Lv1 で HP 約 2500 に対し通常攻撃が毎秒 100 前後（防御込み）+ スキル1 が 6〜11 秒ごとに 300〜400 で、決着まで 15〜20 秒前後かかる。
/// Velstria のスキル 1 発のダメージは MLBB 以上（汎用のスキル1 は Lv1 で約 900 = MLBB の 2〜3 倍）なので、同じクールダウンなら TTK は
/// MLBB 以下になる。上限 20 秒はその MLBB の目安。下限 2.5 秒（一撃死の防止）は CD が半分だったころと同じ。
/// 全員総当たりの分布（Release）: 中央値 Lv1 13.6 / Lv6 8.6 / Lv12 9.1 秒（CD が半分だったころは 10.0 / 5.3 / 5.8 秒、上限 15 秒）。
final class SkillBalanceTests: XCTestCase {
    static let representatives = ["H001", "H002", "H003", "H004", "H005", "H006"]
    static let levels = [1, 6, 12]
    static let minTTK = 2.5
    static let maxTTK = 20.0
    /// 全員総当たり（testFullRosterStaysNearBand）で 1 戦も外れてはいけない帯。
    static let hardMinTTK = 2.0
    static let hardMaxTTK = 25.0

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
