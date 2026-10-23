import Foundation
import simd

/// A fixed-size local pose for H025's authored cloth/hair chains. No entities,
/// timers, allocations or physics world; evaluated by the visible model update.
struct HeroSecondaryPose {
    static let names = ["capel1", "capel2", "capel3", "caper1", "caper2", "caper3",
                        "hair1", "hair2", "hair3", "skirtl", "skirtr"]
    var pitch = SIMD16<Float>(repeating: 0)
    var roll = SIMD16<Float>(repeating: 0)

    func rotation(_ index: Int) -> simd_quatf {
        rx(pitch[index]) * rz(roll[index])
    }
}

struct HeroSecondaryMotion {
    private(set) var pose = HeroSecondaryPose()
    private var velocityX = SIMD16<Float>(repeating: 0)
    private var velocityZ = SIMD16<Float>(repeating: 0)
    private var previousPosition: V3?
    private var previousYaw: Float = 0
    private var previousSpeed: Float = 0
    private var time: Float = 0
    private(set) var turn: Float = 0
    private(set) var acceleration: Float = 0

    /// Analytic underdamped spring. Stable at 30/60Hz and after a bounded slow frame.
    static func spring(value: SIMD2<Float>, velocity: SIMD2<Float>, target: SIMD2<Float>,
                       frequency: Float, damping: Float, dt: Float) -> (SIMD2<Float>, SIMD2<Float>) {
        guard dt > 0 else { return (value, velocity) }
        let omega = frequency, decay = damping * omega
        let damped = omega * sqrt(max(0.001, 1 - damping * damping))
        let e = exp(-decay * dt), c = cos(damped * dt), s = sin(damped * dt)
        let error = value - target
        return (target + e * (error * c + (velocity + decay * error) * (s / damped)),
                e * (velocity * c - (decay * velocity + omega * omega * error) * (s / damped)))
    }

    mutating func reset(position: V3, yaw: Float, speed: Float) {
        previousPosition = position
        previousYaw = yaw
        previousSpeed = speed
        turn = 0
        acceleration = 0
        pose = HeroSecondaryPose()
        velocityX = .zero
        velocityZ = .zero
    }

    mutating func update(dt rawDelta: Float, position: V3, yaw: Float, speed: Float, dead: Bool) {
        let dt = min(0.1, max(0, rawDelta))
        guard let previousPosition, simd_distance(position, previousPosition) < 3, dt > 0 else {
            reset(position: position, yaw: yaw, speed: speed)
            return
        }
        let angle = atan2(sin(yaw - previousYaw), cos(yaw - previousYaw))
        let targetTurn = max(-12, min(12, angle / dt))
        let targetAccel = max(-24, min(24, (speed - previousSpeed) / dt))
        turn += (targetTurn - turn) * (1 - exp(-dt * 15))
        acceleration += (targetAccel - acceleration) * (1 - exp(-dt * 12))
        self.previousPosition = position
        previousYaw = yaw
        previousSpeed = speed
        time += dt
        let run = dead ? 0 : min(1.5, speed / 3.375)
        let wind = dead ? 0 : acceleration * 0.004
        for i in 0..<HeroSecondaryPose.names.count {
            let depth = i < 6 ? i % 3 : (i < 9 ? i - 6 : 0)
            let side: Float = i < 3 || i == 9 ? -1 : 1
            let parent = depth > 0 ? i - 1 : -1
            let inheritedX = parent >= 0 ? pose.pitch[parent] * 0.18 : 0
            let inheritedZ = parent >= 0 ? pose.roll[parent] * 0.30 : 0
            let ripple = sin(time * 10.5 - Float(depth) * 0.9 + side * 0.4) * 0.025 * run
            let target: SIMD2<Float>
            if i < 6 {
                let drag: Float = depth == 0 ? 0.29 : 0.07
                target = SIMD2(-0.035 - drag * run - wind + inheritedX + ripple,
                               side * 0.018 + turn * 0.015 + inheritedZ + ripple * 0.65)
            } else if i < 9 {
                let drag: Float = depth == 0 ? 0.31 : 0.12
                target = SIMD2(-0.025 - drag * run - wind * 1.2 + inheritedX + ripple,
                               turn * 0.025 + inheritedZ + ripple * 0.8)
            } else {
                target = SIMD2(0.04 + run * 0.20 + max(0, wind), side * 0.02 + turn * 0.01)
            }
            let frequency: Float = i >= 9 ? 16 : (depth == 0 ? 16 : (depth == 1 ? 12 : 9))
            let (v, speed) = Self.spring(value: SIMD2(pose.pitch[i], pose.roll[i]),
                                         velocity: SIMD2(velocityX[i], velocityZ[i]), target: target,
                                         frequency: frequency, damping: 0.72, dt: dt)
            pose.pitch[i] = min(0.42, max(-0.65, v.x))
            pose.roll[i] = min(0.28, max(-0.28, v.y))
            velocityX[i] = abs(v.x - pose.pitch[i]) > 1e-5 ? 0 : speed.x
            velocityZ[i] = abs(v.y - pose.roll[i]) > 1e-5 ? 0 : speed.y
        }
    }
}
