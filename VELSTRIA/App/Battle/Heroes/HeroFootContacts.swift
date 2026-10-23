import simd

/// Two bounded support anchors for the authored H025 gait. Visual only; no sim
/// displacement, physics bodies or per-frame collection allocation.
struct HeroFootContacts {
    private struct Leg {
        let hip: Int
        let knee: Int
        let ankle: Int
        let thigh: Float
        let shin: Float
        let height: Float
        let correction: simd_quatf
        var anchor = V3.zero
        var contact = -1
        var weight: Float = 0
    }
    private var right: Leg
    private var left: Leg
    private var previousOrigin: V3?

    init?(rig: HeroSkeletonRig) {
        func leg(_ hip: HeroJointRole, _ knee: HeroJointRole, _ ankle: HeroJointRole) -> Leg? {
            guard let h = rig.index[hip], let k = rig.index[knee], let a = rig.index[ankle] else { return nil }
            return Leg(hip: h, knee: k, ankle: a,
                       thigh: simd_distance(rig.restPosition[h], rig.restPosition[k]),
                       shin: simd_distance(rig.restPosition[k], rig.restPosition[a]),
                       height: rig.restPosition[a].y, correction: rig.correction[a])
        }
        guard let r = leg(.upLegR, .legR, .footR), let l = leg(.upLegL, .legL, .footL) else { return nil }
        right = r; left = l
    }

    mutating func reset() {
        right.contact = -1; right.weight = 0
        left.contact = -1; left.weight = 0
        previousOrigin = nil
    }

    @inline(__always) private static func point(_ m: simd_float4x4, _ p: V3) -> V3 {
        let v = m * SIMD4(p, 1)
        return V3(v.x, v.y, v.z)
    }

    mutating func apply(_ q: inout HeroSegmentRotations, poser: HeroSkeletonPoser,
                        world: simd_float4x4, phase: Float?, walking: Bool, dt: Float) -> Bool {
        let origin = Self.point(world, .zero)
        if let previousOrigin, simd_distance(origin, previousOrigin) > 1 { reset() }
        self.previousOrigin = origin
        guard let phase, dt > 0 else { right.contact = -1; left.contact = -1; right.weight = 0; left.weight = 0; return false }
        let inverse = simd_inverse(world), duty: Float = walking ? 0.62 : 0.38
        let r = Self.solve(&right, phase: phase, duty: duty, poser: poser, world: world, inverse: inverse, dt: dt,
                           thigh: &q.thighR, shin: &q.shinR, foot: q.footR)
        let l = Self.solve(&left, phase: (phase + 0.5).truncatingRemainder(dividingBy: 1), duty: duty,
                           poser: poser, world: world, inverse: inverse, dt: dt,
                           thigh: &q.thighL, shin: &q.shinL, foot: q.footL)
        return r || l
    }

    private static func solve(_ leg: inout Leg, phase: Float, duty: Float, poser: HeroSkeletonPoser,
                              world: simd_float4x4, inverse: simd_float4x4, dt: Float,
                              thigh: inout simd_quatf, shin: inout simd_quatf, foot: simd_quatf) -> Bool {
        guard phase < duty else { leg.contact = -1; leg.weight = 0; return false }
        let kind = phase / duty < 0.5 ? 0 : 1
        let pivot = V3(0, -leg.height, kind == 0 ? 0.045 : -0.105)
        let delta = (foot * leg.correction).act(pivot)
        let ankle = poser.position[leg.ankle], hip = poser.position[leg.hip]
        if leg.contact != kind {
            leg.anchor = point(world, ankle + delta)
            leg.anchor.y = world.columns.3.y
            leg.contact = kind
            leg.weight = 0
        }
        let target = point(inverse, leg.anchor) - delta
        let difference = simd_distance(target, ankle)
        // A sharp reversal must be allowed to take a new step rather than drag
        // the limb outside its reach. Authored gait owns the next landing.
        guard difference < 0.16 else { leg.contact = -1; leg.weight = 0; return false }
        leg.weight = min(1, leg.weight + dt / 0.035)
        let toward = target - hip
        let distance = min(leg.thigh + leg.shin - 0.001, max(0.01, simd_length(toward)))
        guard simd_length(toward) > 1e-5 else { return false }
        let direction = simd_normalize(toward)
        var bend = V3(0, 0, -1) - direction * simd_dot(direction, V3(0, 0, -1))
        if simd_length(bend) < 0.01 { bend = V3(1, 0, 0) }
        bend = simd_normalize(bend)
        let along = (leg.thigh * leg.thigh - leg.shin * leg.shin + distance * distance) / (2 * distance)
        let knee = hip + direction * along + bend * sqrt(max(0, leg.thigh * leg.thigh - along * along))
        let end = hip + direction * distance
        let a = simd_quatf(from: simd_normalize(thigh.act(V3(0, -1, 0))), to: simd_normalize(knee - hip)) * thigh
        let b = simd_quatf(from: simd_normalize(shin.act(V3(0, -1, 0))), to: simd_normalize(end - knee)) * shin
        thigh = simd_slerp(thigh, a, leg.weight)
        shin = simd_slerp(shin, b, leg.weight)
        return true
    }
}
