import XCTest
@testable import VelstriaCore

/// キットの強い通常攻撃（H027 子龍の三連突き・H032 ディアスの円撃）の数え方と、描画への合図（SimEvent.empoweredAttack）。
/// 数え方は MLBB の実機と同じ:
/// - 子龍: 日本語クライアントの原本「通常攻撃またはスキルで 3 回ダメージを与えた後、次の通常攻撃で狂龍乱舞を発動」と画面収録
///   （通常攻撃 355・355・388 の次が三連突き = 通常攻撃だけなら 4 回目。奥義中は「2 回の攻撃ごと」= 3 回目）。docs/kits/Zilong.md。
/// - ディアス: 画面収録（vid12 の 10 撃・vid6）で通常攻撃 2 回の後の 3 回目が円撃。docs/kits/Dyrroth.md。
/// 合図は判定・数値・乱数・状態に触れない（同じ試合を合図ありで進めても結果は同じ = 合図は出力だけ）。
final class EmpoweredAttackTests: XCTestCase {
    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    private func world(_ heroID: String, level: Int = 12) -> (SkillWorld, Int) {
        var w = SkillWorld()
        let k = w.addHero(heroID, team: .blue, at: skillArena, level: level, ranks: [1, 1, 1], facing: 0)
        return (w, k)
    }

    @discardableResult
    private func addEnemy(_ w: inout SkillWorld, dx: Double, dy: Double = 0, hero: String = "H001") -> Int {
        w.addHero(hero, team: .red, at: skillArena + Vec2(dx, dy), level: 12, ranks: [1, 1, 1])
    }

    /// 1 回の通常攻撃（attackReleased）ごとの記録。
    private struct Swing {
        var tick: Int
        /// その攻撃の直前（前の tick の終わり）に「次は強い通常攻撃」と出ていたか。
        var readyBefore: Bool
        var empowered: EmpoweredAttackEvent?
        /// 合図がその tick の attackReleased と、その攻撃の命中（円撃の周りの命中も）より前に出たか。
        var cueBeforeRelease: Bool
    }

    /// 対象を殴り続け、攻撃ごとの記録と、対象への通常攻撃の命中の tick を返す（対象は毎 tick 全快にして倒さない）。
    private func swings(_ w: inout SkillWorld, attacker k: Int, target e: Int, ticks: Int)
        -> (swings: [Swing], hitTicks: [Int]) {
        var out: [Swing] = []
        var hitTicks: [Int] = []
        let me = w.id(k), tid = w.id(e)
        w.s.units[k].attackTargetID = tid
        for n in 0..<ticks {
            w.s.units[e].hp = w.s.units[e].stats.maxHP
            let ready = HeroKits.empoweredAttackReady(w.s.units[k].hero!)
            w.log.removeAll(keepingCapacity: true)
            w.tick()
            for (j, ev) in w.log.enumerated() {
                guard case .attackReleased(let src, _, _) = ev, src == me else { continue }
                var cue: EmpoweredAttackEvent?
                var cueIndex = -1
                for (i, prev) in w.log[..<j].enumerated() {
                    if case .empoweredAttack(let x) = prev, x.sourceID == me { cue = x; cueIndex = i }
                }
                // その攻撃の命中（この tick の自分の通常攻撃のダメージ）はすべて合図より後
                let firstHit = w.log.firstIndex {
                    if case .damage(let d) = $0, d.sourceID == me, d.source == .basicAttack { return true } else { return false }
                }
                let ordered = cue != nil && cueIndex < j && (firstHit.map { cueIndex < $0 } ?? true)
                out.append(Swing(tick: n, readyBefore: ready, empowered: cue, cueBeforeRelease: ordered))
            }
            hitTicks += w.damageEvents.filter { $0.targetID == tid && $0.source == .basicAttack }.map { _ in n }
        }
        return (out, hitTicks)
    }

    // MARK: - 子龍（H027）

    func testZilongFlurryIsTheFourthBasicAttackAndTheCueComesExactlyWithIt() {
        var (w, k) = world("H027")
        let e = addEnemy(&w, dx: 140)
        let (list, hitTicks) = swings(&w, attacker: k, target: e, ticks: 300)
        XCTAssertGreaterThanOrEqual(list.count, 9)
        // MLBB: 3 回ダメージを与えた後の次（通常攻撃だけなら 4 回目）が三連突き。合図は三連突きの攻撃にだけ出る
        let pattern = list.prefix(8).map { $0.empowered != nil }
        XCTAssertEqual(pattern, [false, false, false, true, false, false, false, true])
        // 「次は強い」の表示（readiness）は、その攻撃の前に合図と同じ所で立っている
        XCTAssertEqual(list.prefix(8).map(\.readyBefore), pattern)
        for s in list where s.empowered != nil {
            let cue = s.empowered!
            XCTAssertTrue(s.cueBeforeRelease, "合図は attackReleased・命中より前")
            XCTAssertEqual(cue.heroID, "H027")
            XCTAssertEqual(cue.targetID, w.id(e))
            XCTAssertEqual(cue.hits, Kit_H027.Tune.flurryHits)
            XCTAssertEqual(cue.radius, 0, "単体")
            XCTAssertEqual(cue.reach, 180 + Kit_H027.Tune.flurryRangeBonus, accuracy: 1e-9, "伸びた射程（1.8 → 2.5）")
            // 2・3 発目は合図の interval ごとに当たる（実際の命中の tick と一致）
            let gapTicks = Int((cue.interval / Balance.dt).rounded())
            XCTAssertEqual(gapTicks, 4, "画面収録の 4 コマおき")
            for n in 0..<cue.hits {
                XCTAssertTrue(hitTicks.contains(s.tick + n * gapTicks), "\(n + 1) 発目は合図の \(n * gapTicks) tick 後")
            }
        }
    }

    func testZilongFlurryIsTheThirdAttackDuringTheUltimate() {
        var (w, k) = world("H027")
        let e = addEnemy(&w, dx: 140)
        XCTAssertTrue(w.cast(k, .ultimate))
        w.flushEvents()
        let (list, _) = swings(&w, attacker: k, target: e, ticks: 150)
        XCTAssertGreaterThanOrEqual(list.count, 6)
        // 奥義中は「2 回の攻撃ごと」: 2 回の後の 3 回目が三連突き
        XCTAssertEqual(list.prefix(6).map { $0.empowered != nil }, [false, false, true, false, false, true])
        XCTAssertEqual(list.prefix(6).map(\.readyBefore), list.prefix(6).map { $0.empowered != nil })
    }

    func testZilongSkillDamageCountsTowardTheFlurryAndTheCueFollowsIt() {
        var (w, k) = world("H027")
        let e = addEnemy(&w, dx: 140)
        // スキル1 のダメージで 1 つ: 通常攻撃 2 回の後の 3 回目が三連突き（スキルも 3 回のうちに数える。2.1.40 の文）
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        XCTAssertEqual(w.s.units[k].hero!.kit!.jarldCharge, 1, "スキル1 は発動と同じ tick に当たる")
        let (list, _) = swings(&w, attacker: k, target: e, ticks: 120)
        XCTAssertGreaterThanOrEqual(list.count, 3)
        XCTAssertEqual(list.prefix(3).map { $0.empowered != nil }, [false, false, true])
    }

    // MARK: - ディアス（H032）

    func testDyrrothCircleStrikeIsTheThirdBasicAttackAndTheCueCarriesTheJudgedCircle() {
        var (w, k) = world("H032")
        let e = addEnemy(&w, dx: 140)
        var circles: [HitShape] = []
        HitShapeProbe.sink = { shape in
            if case .circle = shape.form, shape.source == .basicAttack { circles.append(shape) }
        }
        defer { HitShapeProbe.sink = nil }
        let (list, _) = swings(&w, attacker: k, target: e, ticks: 400)
        XCTAssertGreaterThanOrEqual(list.count, 9)
        let pattern = list.prefix(9).map { $0.empowered != nil }
        XCTAssertEqual(pattern, [false, false, true, false, false, true, false, false, true])
        XCTAssertEqual(list.prefix(9).map(\.readyBefore), pattern)
        let cues = list.compactMap(\.empowered)
        XCTAssertEqual(circles.count, cues.count, "円撃の判定 1 回につき合図 1 つ")
        for (s, shape) in zip(list.filter { $0.empowered != nil }, circles) {
            let cue = s.empowered!
            XCTAssertTrue(s.cueBeforeRelease)
            XCTAssertEqual(cue.heroID, "H032")
            XCTAssertEqual(cue.hits, 1)
            XCTAssertEqual(cue.interval, 0)
            // 合図の円 = sim が判定した円（中心・半径）。描画の輪はこの半径の ±3% に出す（AppTests）
            guard case .circle(let center, let radius, _) = shape.form else { continue }
            XCTAssertEqual(cue.radius, radius, accuracy: 1e-9)
            XCTAssertEqual(cue.radius, Kit_H032.Tune.circleRadius)
            XCTAssertEqual(cue.origin.x, center.x, accuracy: 1e-9)
            XCTAssertEqual(cue.origin.y, center.y, accuracy: 1e-9)
        }
    }

    /// 撮影用の準備（HeroKits.primeEmpoweredAttack）: 次の通常攻撃が強い通常攻撃になる（キットの無い・持たないヒーローは何もしない）。
    func testPrimeMakesTheNextAttackEmpowered() {
        for id in ["H027", "H032"] {
            var (w, k) = world(id)
            let e = addEnemy(&w, dx: 140)
            XCTAssertFalse(HeroKits.empoweredAttackReady(w.s.units[k].hero!), id)
            HeroKits.primeEmpoweredAttack(&w.s, unit: k)
            XCTAssertTrue(HeroKits.empoweredAttackReady(w.s.units[k].hero!), id)
            let (list, _) = swings(&w, attacker: k, target: e, ticks: 40)
            XCTAssertNotNil(list.first?.empowered, "\(id): 準備した次の通常攻撃が強い通常攻撃")
        }
        var (w, k) = world("H029")
        let before = w.s.units[k].hero!.kit
        HeroKits.primeEmpoweredAttack(&w.s, unit: k)
        XCTAssertEqual(w.s.units[k].hero!.kit, before, "強い通常攻撃の無いキットは変えない")
    }

    // MARK: - 決定性・形式

    /// 合図はイベントの出力だけ: 同じ試合を 2 回進めると状態ハッシュ・イベントが一致し、合図の有無で判定が変わらない
    /// （合図を出す前と同じ命中の並び = 既存の Kit_H027Tests / Kit_H032Tests の数え方・ダメージのテストがそのまま通る）。
    func testCueIsOutputOnlyAndDeterministic() {
        func run() -> (UInt64, [SimEvent]) {
            var (w, k) = world("H032")
            let e = addEnemy(&w, dx: 140)
            let z = w.addHero("H027", team: .blue, at: skillArena + Vec2(0, 120), level: 12, ranks: [1, 1, 1], facing: 0)
            w.s.units[k].attackTargetID = w.id(e)
            w.s.units[z].attackTargetID = w.id(e)
            var all: [SimEvent] = []
            for _ in 0..<240 {
                w.s.units[e].hp = w.s.units[e].stats.maxHP
                w.log.removeAll(keepingCapacity: true)
                w.tick()
                all += w.log
            }
            return (w.s.stateHash(), all)
        }
        let a = run(), b = run()
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, b.1)
        XCTAssertGreaterThan(a.1.filter { if case .empoweredAttack = $0 { return true } else { return false } }.count, 3)
    }

    /// 新しいイベントは Codable で往復できる（SimState の events は tick の終わりに空になるので、スナップショット・リプレイには
    /// 入らないが、型としては他のイベントと同じに扱える）。
    func testCueRoundTripsThroughCodable() throws {
        let e = SimEvent.empoweredAttack(EmpoweredAttackEvent(sourceID: 7, targetID: 9, heroID: "H032", hits: 1, interval: 0,
                                                              radius: 200, reach: 170, origin: Vec2(10, 20)))
        let data = try JSONEncoder().encode([e])
        XCTAssertEqual(try JSONDecoder().decode([SimEvent].self, from: data), [e])
    }
}
