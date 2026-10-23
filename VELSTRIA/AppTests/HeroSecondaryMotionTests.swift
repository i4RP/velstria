import XCTest
import simd
@testable import VELSTRIA

final class HeroSecondaryMotionTests: XCTestCase {
    func testSpringIsFrameRateIndependentAndSettles() {
        func sample(_ rate: Int) -> SIMD2<Float> {
            var x = SIMD2<Float>(-0.5, 0.25), v = SIMD2<Float>.zero
            for _ in 0..<rate {
                (x, v) = HeroSecondaryMotion.spring(value: x, velocity: v, target: .zero,
                    frequency: 9, damping: 0.72, dt: 1 / Float(rate))
            }
            return x
        }
        XCTAssertLessThan(simd_length(sample(30) - sample(60)), 1e-5)
        XCTAssertLessThan(simd_length(sample(60)), 0.005)
    }

    func testTurnStopAndTeleportStayBounded() {
        var cloth = HeroSecondaryMotion()
        for f in 0..<180 {
            cloth.update(dt: 1.0 / 60, position: [0, 0, -Float(f) * 0.05],
                         yaw: Float(f) * 0.10, speed: 3.375, dead: false)
            for i in 0..<11 {
                XCTAssertTrue(cloth.pose.pitch[i].isFinite)
                XCTAssertLessThanOrEqual(abs(cloth.pose.pitch[i]), 0.65)
                XCTAssertLessThanOrEqual(abs(cloth.pose.roll[i]), 0.28)
            }
        }
        for _ in 0..<90 {
            cloth.update(dt: 1.0 / 60, position: [0, 0, -8.95], yaw: 17.9, speed: 0, dead: false)
        }
        XCTAssertLessThan(abs(cloth.turn), 0.001)
        XCTAssertLessThan(abs(cloth.pose.pitch[2]), 0.06)
        cloth.update(dt: 1.0 / 60, position: [100, 0, 0], yaw: 0, speed: 0, dead: false)
        XCTAssertEqual(cloth.pose.pitch, .zero)
        XCTAssertEqual(cloth.turn, 0)
    }

    func testDeathDrapesCapeAndHairThenRespawnReturnsToIdle() {
        var cloth = HeroSecondaryMotion()
        cloth.update(dt: 0, position: .zero, yaw: 0, speed: 0, dead: false)
        for _ in 0..<90 { cloth.update(dt: 1.0 / 60, position: .zero, yaw: 0, speed: 0, dead: true) }
        XCTAssertEqual(cloth.pose.pitch[0], 0.58, accuracy: 0.01)
        XCTAssertEqual(cloth.pose.pitch[6], 0.85, accuracy: 0.01)
        for _ in 0..<120 { cloth.update(dt: 1.0 / 60, position: .zero, yaw: 0, speed: 0, dead: false) }
        XCTAssertLessThan(abs(cloth.pose.pitch[0]), 0.05)
        XCTAssertLessThan(abs(cloth.pose.pitch[6]), 0.05)
    }
}
