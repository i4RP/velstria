import XCTest
@testable import VELSTRIA
import VelstriaCore

/// H029 ボルグの専用の収録（H029MotionClips.json、docs/H029_MOTION.md）が実際の再生経路で使われること:
/// 手続き（HeroIdle・HeroGait・Motion_H029 の全身の通常攻撃）に上書きされず、打撃は KitTimes / sim の windup に合う。
final class H029MotionClipTests: XCTestCase {
    private let hero = "H029"

    private func animator() throws -> HeroAnimator {
        HeroMotionClips.setResolverForTesting(nil)
        let lib = HeroMotionClips.library(heroID: hero)
        let set = try XCTUnwrap(HeroMotionSets.set(heroID: hero))
        let binding = try XCTUnwrap(HeroMotionBinding(set: set, library: lib))
        let bp = HeroBlueprints.blueprint(heroID: hero, role: nil)
        return HeroAnimator(profile: HeroMotionProfile(blueprint: bp, metrics: BodyMetrics.make(bp.build), heroID: hero),
                            defaultRunSpeed: 2.6, motion: binding)
    }

    func testDedicatedClipsAreBoundAndOverrideProceduralMotion() throws {
        HeroMotionClips.setResolverForTesting(nil)
        let lib = HeroMotionClips.library(heroID: hero)
        let set = try XCTUnwrap(HeroMotionSets.set(heroID: hero))
        XCTAssertEqual(set.idle, "idle_h029", "HeroIdle があっても専用の待機を外さない")
        let b = try XCTUnwrap(HeroMotionBinding(set: set, library: lib))
        XCTAssertTrue(b.dedicatedIdle)
        XCTAssertTrue(set.dedicatedAttack)
        XCTAssertNotNil(b.walk)
        XCTAssertNotNil(b.run)
        XCTAssertEqual(b.attacks.count, 1)
        XCTAssertEqual(b.casts.compactMap { $0 }.count, 3)
        XCTAssertEqual(b.cast(1, stage: 1), lib.index(of: "maul_upswing_h029"), "S2 の再使用（打ち上げ）のクリップ")
        XCTAssertEqual(b.cast(1, stage: 0), lib.index(of: "shield_charge_h029"))
        XCTAssertTrue(b.locksLegs(1), "突進中も脚はクリップ")
        XCTAssertFalse(b.locksLegs(0))
        for name in ["idle_h029", "walk_h029", "run_h029", "maul_smash_h029", "maul_wave_h029", "shield_charge_h029",
                     "maul_upswing_h029", "maul_sanctuary_h029"] {
            let c = try XCTUnwrap(lib.index(of: name), name)
            XCTAssertNotEqual(lib.clips[c].detailMask, 0, "\(name): 肩・指・つま先の補助関節")
        }
        let a = try animator()
        XCTAssertTrue(a.profile.attackMotions.isEmpty, "Motion_H029 の全身の通常攻撃が専用の収録を上書きしない")
        XCTAssertEqual(a.clips.clipName, "idle_h029", "出現直後から専用の待機")
    }

    func testAttackImpactLandsAtSimWindupAtBaseAndFastAttackSpeed() throws {
        for interval: Float in [0.97, 0.45] {
            var a = try animator()
            let windup = interval * Float(Balance.attackWindupRatio)
            a.setState(.attack)
            a.playAttack(windup: windup, interval: interval)
            XCTAssertEqual(a.clips.clipName, "maul_smash_h029")
            var t: Float = 0, hit: Float?
            while t < interval {
                let before = a.clips.clipTime
                _ = a.advance(dt: 1.0 / 120, moveSpeed: 0)
                t += 1.0 / 120
                if hit == nil, before < a.clips.impactTime, a.clips.clipTime >= a.clips.impactTime { hit = t }
            }
            XCTAssertEqual(try XCTUnwrap(hit, "\(interval)"), windup, accuracy: 1.0 / 60, "命中 = sim の windup（攻撃間隔 \(interval)）")
            XCTAssertTrue(a.clips.clipTime <= a.clips.endTime + 1e-4)
        }
    }

    func testCastClipsStrikeAtKitTimes() throws {
        let cases: [(SkillSlot, Int, String, Float)] = [
            (.skill1, 0, "maul_wave_h029", KitTimes(hero, .skill1).seconds("waveFirstDelay")),
            (.skill2, 0, "shield_charge_h029",
             Float(KitTimes(hero, .skill2).distance("dashRange") / KitTimes(hero, .skill2).speed("dashSpeed"))),
            (.skill2, 1, "maul_upswing_h029", KitTimes(hero, .skill2, stage: 1).seconds("smashDelay")),
            (.ultimate, 0, "maul_sanctuary_h029", KitTimes(hero, .ultimate).seconds("ultTotal")),
        ]
        for (slot, stage, name, strike) in cases {
            XCTAssertGreaterThan(strike, 0, name)
            var a = try animator()
            if stage == 0 {
                a.setState(.cast(slot))
            } else {
                a.setState(.cast(slot))
                _ = a.advance(dt: 0.3, moveSpeed: 0)
                a.playCast(slot, stage: stage)
            }
            XCTAssertEqual(a.clips.clipName, name)
            var t: Float = 0, hit: Float?
            while t < strike + 0.3 {
                let before = a.clips.clipTime
                _ = a.advance(dt: 1.0 / 120, moveSpeed: 0)
                t += 1.0 / 120
                if hit == nil, before < a.clips.impactTime, a.clips.clipTime >= a.clips.impactTime { hit = t }
            }
            XCTAssertEqual(try XCTUnwrap(hit, name), strike, accuracy: 1.0 / 60, "\(name) の打撃 = KitTimes")
        }
    }

    func testLocomotionPicksWalkOrRunBySpeed() throws {
        var a = try animator()
        a.setState(.run)
        for _ in 0..<60 { _ = a.advance(dt: 1.0 / 60, moveSpeed: 2.6) }
        XCTAssertEqual(a.clips.clipName, "run_h029")
        a.setState(.idle)
        for _ in 0..<60 { _ = a.advance(dt: 1.0 / 60, moveSpeed: 0) }
        a.setState(.run)
        for _ in 0..<60 { _ = a.advance(dt: 1.0 / 60, moveSpeed: 1.2) }
        XCTAssertEqual(a.clips.clipName, "walk_h029")
    }
}
