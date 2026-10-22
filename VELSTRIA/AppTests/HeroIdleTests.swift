import XCTest
import simd
@testable import VELSTRIA
import VelstriaCore

/// Personality must survive the same animator used by the gallery and battle,
/// including legacy full-body idle clips and recovery from movement / attacks.
@MainActor
final class HeroIdleTests: XCTestCase {
    private let ids = HeroRoster.activeHeroIDs

    private func profile(_ id: String) -> HeroMotionProfile {
        let bp = HeroBlueprints.blueprint(heroID: id, role: nil)
        return HeroMotionProfile(blueprint: bp, metrics: BodyMetrics.make(bp.build), heroID: id)
    }

    private func components(_ p: HeroPose) -> [Float] {
        [p.offset.x, p.offset.y, p.offset.z, p.pitch, p.roll, p.yaw,
         p.hipsDrop, p.hipsPitch, p.hipsYaw, p.hipsRoll,
         p.torsoPitch, p.torsoYaw, p.torsoRoll, p.headPitch, p.headYaw, p.headRoll,
         p.armR.pitch, p.armR.out, p.armR.yaw, p.armR.elbow,
         p.armL.pitch, p.armL.out, p.armL.yaw, p.armL.elbow,
         p.legR.pitch, p.legR.out, p.legR.knee, p.legR.ankle,
         p.legL.pitch, p.legL.out, p.legL.knee, p.legL.ankle,
         p.weaponR, p.weaponL, p.cape, p.wings, p.glow, p.ring, p.opacity,
         p.plant, p.footR.x, p.footR.y, p.footR.z, p.footL.x, p.footL.y, p.footL.z]
    }

    private func difference(_ a: HeroPose, _ b: HeroPose) -> Float {
        zip(components(a), components(b)).map { abs($0.0 - $0.1) }.max() ?? 0
    }

    private func assertIdle(_ animator: HeroAnimator, _ id: String,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let idle = try XCTUnwrap(animator.profile.idle, id, file: file, line: line)
        let expected = idle.pose(rest: animator.profile.rest, time: animator.idleTime)
        XCTAssertLessThan(difference(animator.current, expected), 0.002, id, file: file, line: line)
        XCTAssertEqual(animator.clipUpperWeight, 0, accuracy: 0.001, id, file: file, line: line)
        XCTAssertEqual(animator.clipLowerWeight, 0, accuracy: 0.001, id, file: file, line: line)
    }

    /// Deliberately exaggerated generic idle: it must never hide authored poses.
    /// Also includes an action so the recovery path has a real clip to fade out.
    private func genericBinding() throws -> HeroMotionBinding {
        let count = HeroSegmentRotations.count
        let idle = HeroMotionClip(name: "generic_idle", frames: 2, fps: 30, loop: true,
                                  rootXZ: 1, impact: nil, release: nil, end: 1, rotBase: 0, rootBase: 0)
        let action = HeroMotionClip(name: "test_attack", frames: 8, fps: 30, loop: false,
                                    rootXZ: 1, impact: 3, release: nil, end: 7,
                                    rotBase: 2 * count, rootBase: 2)
        let lib = HeroMotionLibrary(clips: [idle, action],
                                    rot: Array(repeating: rx(1.1), count: 10 * count),
                                    root: Array(repeating: SIMD3<Float>(0.1, -0.2, 0.1), count: 10))
        var set = HeroMotionSet()
        set.idle = "generic_idle"
        set.attacks = ["test_attack"]
        return try XCTUnwrap(HeroMotionBinding(set: set, library: lib))
    }

    func testAllTenHeroesHaveDistinctSpawnPosesAndLivingIdlesFor65Seconds() throws {
        XCTAssertEqual(ids.count, 10)
        var poses: [HeroPose] = []
        for id in ids {
            let p = profile(id)
            _ = try XCTUnwrap(p.idle, id)
            var a = HeroAnimator(profile: p, defaultRunSpeed: 3.3)
            for prior in poses {
                XCTAssertGreaterThan(difference(a.current, prior), 0.025, "\(id): duplicated standing silhouette")
            }
            poses.append(a.current)
            let first = a.current
            var motion: Float = 0
            for _ in 0..<3900 {
                let pose = a.advance(dt: 1 / 60, moveSpeed: 0)
                XCTAssertTrue(components(pose).allSatisfy(\.isFinite), id)
                motion = max(motion, difference(first, pose))
                XCTAssertGreaterThanOrEqual(pose.legR.knee, 0, id)
                XCTAssertGreaterThanOrEqual(pose.legL.knee, 0, id)
            }
            XCTAssertGreaterThan(motion, 0.004, "\(id): frozen idle")
        }
    }

    func testLuminaKeepsAnUprightNarrowStanceThroughoutHerIdle() throws {
        var a = HeroAnimator(profile: profile("H025"), defaultRunSpeed: 3.3,
                             motion: try genericBinding())
        for _ in 0..<3900 {
            let p = a.advance(dt: 1 / 60, moveSpeed: 0)
            XCTAssertLessThanOrEqual(abs(p.legR.out), 0.05)
            XCTAssertLessThanOrEqual(abs(p.legL.out), 0.05)
            XCTAssertLessThanOrEqual(p.legR.knee, 0.12)
            XCTAssertLessThanOrEqual(p.legL.knee, 0.12)
            XCTAssertLessThanOrEqual(abs(p.pitch), 0.04)
            XCTAssertLessThanOrEqual(abs(p.torsoPitch), 0.06)
            XCTAssertLessThanOrEqual(abs(p.hipsDrop), 0.025)
            XCTAssertEqual(a.clipLowerWeight, 0)
        }
    }

    func testGenericFullBodyIdleCannotOverridePlayableHeroes() throws {
        let binding = try genericBinding()
        for id in ids {
            var a = HeroAnimator(profile: profile(id), defaultRunSpeed: 3.3, motion: binding)
            try assertIdle(a, id)
            for _ in 0..<60 { _ = a.advance(dt: 1 / 60, moveSpeed: 0) }
            // Hot replacement is used by the model gallery; it must obey the same precedence.
            a.setMotion(binding)
            for _ in 0..<30 { _ = a.advance(dt: 1 / 60, moveSpeed: 0) }
            try assertIdle(a, id)
        }
        var legacy = HeroAnimator(profile: profile("H001"), defaultRunSpeed: 3.3, motion: binding)
        for _ in 0..<30 { _ = legacy.advance(dt: 1 / 60, moveSpeed: 0) }
        XCTAssertEqual(legacy.clips.clipName, "generic_idle")
        XCTAssertGreaterThan(legacy.clipLowerWeight, 0.99, "Legacy clip support must remain available")
    }

    func testWalkingAndAttackRecoveryReturnToEachHeroesOwnStance() throws {
        let binding = try genericBinding()
        for id in ids {
            var a = HeroAnimator(profile: profile(id), defaultRunSpeed: 3.3, motion: binding)
            a.setState(.run)
            for _ in 0..<900 { _ = a.advance(dt: 1 / 60, moveSpeed: 3.3) }
            XCTAssertEqual(a.idleTime, 0, "\(id): idle gestures advance while running")
            a.setState(.idle)
            XCTAssertEqual(a.idleTime, 0, "\(id): stopping must start from the calm stance")
            for _ in 0..<180 { _ = a.advance(dt: 1 / 60, moveSpeed: 0) }
            XCTAssertLessThan(a.idleTime, 3, "\(id): long movement must not jump into a late idle gesture")
            try assertIdle(a, id)

            a.playAttack(windup: 0.25, interval: 0.8)
            for _ in 0..<20 { _ = a.advance(dt: 1 / 60, moveSpeed: 0) }
            a.setState(.idle)
            XCTAssertEqual(a.idleTime, 0, "\(id): attack recovery must restart the idle clock")
            for _ in 0..<240 { _ = a.advance(dt: 1 / 60, moveSpeed: 0) }
            try assertIdle(a, id)
        }
    }

    func testIdleAccentsStayContinuousAtCycleBoundaries() throws {
        for id in ids {
            let p = profile(id)
            let idle = try XCTUnwrap(p.idle, id)
            for cycle in 1...5 {
                let seam = idle.gesturePeriod * Float(cycle)
                let a = idle.pose(rest: p.rest, time: seam - 0.0001)
                let b = idle.pose(rest: p.rest, time: seam + 0.0001)
                XCTAssertLessThan(difference(a, b), 0.001, "\(id): idle loop pops")
            }
        }
    }
}
