import XCTest
@testable import VelstriaCore

// 判定の形の観測（HitShapeProbe）と、1 スキルを撃って集める道具（HitShapeScenario）。docs/vfx/RANGES.md。
// 観測は判定・数値・決定論に触れない（受け口を置いても試合の状態は同じ）。集めた形はキットの Tune の値そのもの。

final class HitShapeProbeTests: XCTestCase {
    override func tearDown() {
        HitShapeProbe.sink = nil
        super.tearDown()
    }

    func testProbeIsInactiveWithoutSink() {
        HitShapeProbe.sink = nil
        XCTAssertFalse(HitShapeProbe.isActive)
        HitShapeProbe.sink = { _ in }
        XCTAssertTrue(HitShapeProbe.isActive)
        HitShapeProbe.sink = nil
        XCTAssertFalse(HitShapeProbe.isActive)
    }

    /// 受け口を置いても置かなくても、同じ試合は同じ状態になる（判定・乱数・イベントに触れない）。形は実際に届く。
    func testSinkDoesNotChangeTheMatch() {
        let cfg = MatchFactory.botMatch(difficulty: .hard, seed: 7)
        let map = MapDefinition.map(for: cfg.mode)
        let a = Simulation(config: cfg, map: map)
        let b = Simulation(config: cfg, map: map)
        var shapes = 0
        var eventsA: [SimEvent] = []
        var eventsB: [SimEvent] = []
        for _ in 0..<(30 * 150) {
            HitShapeProbe.sink = nil
            eventsA += a.step()
            HitShapeProbe.sink = { _ in shapes += 1 }
            eventsB += b.step()
        }
        HitShapeProbe.sink = nil
        XCTAssertEqual(a.state.stateHash(), b.state.stateHash())
        XCTAssertEqual(a.state.rng, b.state.rng)
        XCTAssertEqual(eventsA, eventsB)
        XCTAssertGreaterThan(shapes, 0, "150 秒の試合で判定の形が 1 つも届かない")
    }

    // MARK: - ゴルム（H034）

    func testGolmShockIsTheTuneCircleAtTheSlam() throws {
        let t = try XCTUnwrap(HitShapeScenario.run(heroID: "H034", slot: .skill2))
        let cast = try XCTUnwrap(t.casts.first)
        let circles = t.shapes.compactMap { s -> (Double, Double)? in
            if case .circle(_, let r, _) = s.form, s.kind == .area { return (s.time - cast.time, r) }
            return nil
        }
        XCTAssertEqual(circles.count, 1)
        XCTAssertEqual(circles.first?.1 ?? 0, Kit_H034.Tune.shockRadius, accuracy: 1e-9)
        XCTAssertEqual(circles.first?.0 ?? 0, Kit_H034.Tune.shockDelay, accuracy: Balance.dt + 1e-6)
    }

    func testGolmHookSweepsTheTuneWidthFromTheLaunch() throws {
        let t = try XCTUnwrap(HitShapeScenario.run(heroID: "H034", slot: .skill1))
        let cast = try XCTUnwrap(t.casts.first)
        let sweeps = t.shapes.filter { $0.kind == .projectile }
        XCTAssertFalse(sweeps.isEmpty)
        for s in sweeps {
            guard case .line(_, _, let hw, _) = s.form else { return XCTFail("鉤の掃引が線分でない") }
            XCTAssertEqual(hw, Kit_H034.Tune.hookWidth, accuracy: 1e-9)
        }
        XCTAssertEqual((sweeps.first?.time ?? 0) - cast.time, Kit_H034.Tune.hookDelay, accuracy: Balance.dt + 1e-6)
        // 人形に当たって止まる（非貫通）: 最後の区間の終わりは人形の手前
        XCTAssertTrue(t.events.contains { if case .projectileHit = $0.event { return true }; return false })
    }

    func testGolmUltStrikesSixTimesAtTheTuneInterval() throws {
        let t = try XCTUnwrap(HitShapeScenario.run(heroID: "H034", slot: .ultimate, targetsHero: true))
        let cast = try XCTUnwrap(t.casts.first)
        let strikes = t.shapes.filter { if case .unit = $0.form { return true }; return false }.map { $0.time - cast.time }
        XCTAssertEqual(strikes.count, Kit_H034.Tune.ultHits)
        for (n, time) in strikes.enumerated() {
            XCTAssertEqual(time, Kit_H034.Tune.ultDelay + Kit_H034.Tune.ultInterval * Double(n), accuracy: Balance.dt + 1e-6)
        }
    }

    // MARK: - ボルグ（H029）

    func testBorgWaveIsThreeTrapezoidBandsMovingForward() throws {
        let t = try XCTUnwrap(HitShapeScenario.run(heroID: "H029", slot: .skill1))
        let cast = try XCTUnwrap(t.casts.first)
        let bands = t.shapes.compactMap { s -> (Double, [Vec2])? in
            if case .polygon(let p) = s.form { return (s.time - cast.time, p) }
            return nil
        }
        XCTAssertEqual(bands.count, Kit_H029.Tune.waveCount)
        let origin = try XCTUnwrap(HitShapeTrace.position(t.caster, at: cast.time))
        for (k, band) in bands.enumerated() {
            XCTAssertEqual(band.0, Kit_H029.Tune.waveFirstDelay + Kit_H029.Tune.waveInterval * Double(k),
                           accuracy: Balance.dt + 1e-6)
            // 奥行き（北向き = +y）: 帯の奥の辺
            let far = band.1.map { $0.y - origin.y }.max() ?? 0
            let hi = k == Kit_H029.Tune.waveCount - 1 ? Kit_H029.Tune.waveReach
                : (Kit_H029.Tune.waveBandStart[k] + Kit_H029.Tune.waveBandLength) * Kit_H029.Tune.waveReach
            XCTAssertEqual(far, hi, accuracy: 1e-6)
        }
    }

    func testBorgRecastSmashIsTheTuneFanAfterTheDelay() throws {
        let t = try XCTUnwrap(HitShapeScenario.run(heroID: "H029", slot: .skill2, recastAfter: 0.85))
        XCTAssertEqual(t.casts.count, 2, "突進と再使用の 2 回の発動")
        let recast = try XCTUnwrap(t.casts.last)
        let cones = t.shapes.compactMap { s -> (Double, Double, Double)? in
            if case .cone(_, _, let r, let half, _) = s.form { return (s.time - recast.time, r, half) }
            return nil
        }
        XCTAssertEqual(cones.count, 1)
        XCTAssertEqual(cones.first?.0 ?? 0, Kit_H029.Tune.smashDelay, accuracy: Balance.dt + 1e-6)
        XCTAssertEqual(cones.first?.1 ?? 0, Kit_H029.Tune.smashReach, accuracy: 1e-9)
        XCTAssertEqual(cones.first?.2 ?? 0, Kit_H029.Tune.smashHalfAngle, accuracy: 1e-9)
        // 突進の掃引（半幅 = dashWidth）
        let sweeps = t.shapes.filter { $0.kind == .sweep }
        XCTAssertFalse(sweeps.isEmpty)
        for s in sweeps {
            guard case .line(_, _, let hw, _) = s.form else { return XCTFail("突進の掃引が線分でない") }
            XCTAssertEqual(hw, Kit_H029.Tune.dashWidth, accuracy: 1e-9)
        }
    }

    func testBorgImplosionCatchesAtCastAndDetonatesAtTheTotal() throws {
        let t = try XCTUnwrap(HitShapeScenario.run(heroID: "H029", slot: .ultimate))
        let cast = try XCTUnwrap(t.casts.first)
        let circles = t.shapes.compactMap { s -> (HitShape.Kind, Double, Double)? in
            if case .circle(_, let r, _) = s.form { return (s.kind, s.time - cast.time, r) }
            return nil
        }
        let catchCircle = try XCTUnwrap(circles.first { $0.0 == .kit })
        XCTAssertEqual(catchCircle.1, 0, accuracy: 1e-6)
        XCTAssertEqual(catchCircle.2, Kit_H029.Tune.ultReach, accuracy: 1e-9)
        let blast = try XCTUnwrap(circles.first { $0.0 == .area })
        XCTAssertEqual(blast.1, Kit_H029.Tune.ultTotal, accuracy: Balance.dt + 1e-6)
        XCTAssertEqual(blast.2, Kit_H029.Tune.ultReach, accuracy: 1e-9)
    }

    // MARK: - 演出が読む値

    /// 演出が読む値（KitFXValue）は判定と照準の値と同じ。
    func testFXValuesAreTheTuneAndAgreeWithTargeting() throws {
        let master = MasterData.shared
        func value(_ hero: String, _ slot: SkillSlot, _ key: String, stage: Int = 0) -> Double? {
            HeroKits.fxValues(heroID: hero, slot: slot, stage: stage).first { $0.key == key }?.value
        }
        let golm = try XCTUnwrap(master.hero("H034"))
        let hook = HeroKits.targeting(for: try XCTUnwrap(master.skill(hero: "H034", slot: .skill1)), hero: golm, stage: 0)
        XCTAssertEqual(value("H034", .skill1, "hookWidth"), hook.radius)
        XCTAssertEqual(value("H034", .skill1, "hookRange"), hook.range)
        let shock = HeroKits.targeting(for: try XCTUnwrap(master.skill(hero: "H034", slot: .skill2)), hero: golm, stage: 0)
        XCTAssertEqual(value("H034", .skill2, "shockRadius"), shock.radius)
        XCTAssertEqual(value("H034", .skill2, "shockDelay"), Kit_H034.Tune.shockDelay)
        let borg = try XCTUnwrap(master.hero("H029"))
        let smash = HeroKits.targeting(for: try XCTUnwrap(master.skill(hero: "H029", slot: .skill2)), hero: borg, stage: 1)
        XCTAssertEqual(value("H029", .skill2, "smashReach", stage: 1), smash.radius)
        XCTAssertEqual(value("H029", .skill2, "smashHalfAngle", stage: 1), smash.halfAngle)
        let dash = HeroKits.targeting(for: try XCTUnwrap(master.skill(hero: "H029", slot: .skill2)), hero: borg, stage: 0)
        XCTAssertEqual(value("H029", .skill2, "dashRange"), dash.range)
        XCTAssertEqual(value("H029", .skill2, "dashWidth"), dash.radius)
        let ult = HeroKits.targeting(for: try XCTUnwrap(master.skill(hero: "H029", slot: .ultimate)), hero: borg, stage: 0)
        XCTAssertEqual(value("H029", .ultimate, "ultReach"), ult.radius)
        XCTAssertEqual(HeroKits.fxValues(heroID: "H029", slot: .skill1).first { $0.key == "waveBandStart" }?.values,
                       Kit_H029.Tune.waveBandStart)
        // キットの無いヒーローは空
        XCTAssertTrue(HeroKits.fxValues(heroID: "H001", slot: .skill1).isEmpty)
    }
}
