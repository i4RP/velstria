import Foundation
import RealityKit
import simd
import VelstriaCore

// 担当: battle-renderer。見下ろしカメラ（透視 ~48°、俯角 56°、回転なし）。
// 注視点を臨界減衰バネで追従し、地図内にクランプ。大きな出来事で小さく揺らす（トラウマ方式）。

/// 臨界減衰のスムージング（SmoothDamp）。smoothTime ≒ 目標到達までの時間。
struct CriticallyDampedSpring {
    var value: SIMD2<Float>
    var velocity: SIMD2<Float> = .zero

    init(_ value: SIMD2<Float>) { self.value = value }

    mutating func update(target: SIMD2<Float>, smoothTime: Float, dt: Float) {
        guard dt > 0 else { return }
        let omega = 2 / max(0.0001, smoothTime)
        let x = omega * dt
        let decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = value - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * decay
        value = target + (change + temp) * decay
        // 漸近的に止まるばねを静止させる（0.1 mm 未満の動きが続くと、細い線や影の縁が止まった後も揺らぐ）
        if simd_length_squared(value - target) < 1e-8, simd_length_squared(velocity) < 1e-6 {
            value = target
            velocity = .zero
        }
    }

    mutating func snap(to v: SIMD2<Float>) {
        value = v
        velocity = .zero
    }
}

/// スカラー版。
struct CriticallyDampedScalar {
    var value: Float
    var velocity: Float = 0

    mutating func update(target: Float, smoothTime: Float, dt: Float) {
        guard dt > 0 else { return }
        let omega = 2 / max(0.0001, smoothTime)
        let x = omega * dt
        let decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = value - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * decay
        value = target + (change + temp) * decay
        if abs(value - target) < 1e-4, abs(velocity) < 1e-3 {
            value = target
            velocity = 0
        }
    }
}

@MainActor
final class CameraRig {
    static let pitchDegrees: Float = 56
    static let fovDegrees: Float = 48
    /// cameraZoom = 1 のときの注視点までの距離（m）。
    static let baseDistance: Float = 12.5
    /// 注視点を置く位置（ヒーローの少し前方 = 画面のやや下にヒーロー）。
    static let focusLead: Float = 0.9

    let camera = PerspectiveCamera()
    private(set) var focus = CriticallyDampedSpring(.zero)
    private var distance = CriticallyDampedScalar(value: baseDistance)
    private var trauma: Float = 0
    private var time: Float = 0
    private var initialized = false

    init() {
        camera.name = "camera"
        camera.camera = PerspectiveCameraComponent(near: 1.0, far: 160, fieldOfViewInDegrees: CameraRig.fovDegrees,
                                                   fieldOfViewOrientation: .vertical)
        camera.orientation = CameraRig.orientation
    }

    static var orientation: simd_quatf {
        simd_quatf(angle: -pitchDegrees * .pi / 180, axis: [1, 0, 0])
    }

    /// 注視点（world xz の (x, z)）から見たカメラ位置のオフセット。
    static func offset(distance d: Float) -> SIMD3<Float> {
        let p = pitchDegrees * .pi / 180
        return SIMD3(0, d * sin(p), d * cos(p))
    }

    /// 注視点を地図内に保つ（外周の森が少し見える程度の余白）。
    static func clampFocus(_ f: SIMD2<Float>, mapMeters M: Float) -> SIMD2<Float> {
        SIMD2(min(max(f.x, 5.5), M - 5.5), min(max(f.y, -(M - 3.5)), -7.5))
    }

    static func distance(forZoom zoom: Double) -> Float {
        baseDistance * Float(min(max(zoom, 0.7), 1.4))
    }

    /// Screen corners intersected with y = 0, in clockwise sim coordinates.
    /// Uses the rendered pose, including damping, map-edge clamping, zoom and camera shake.
    func groundFootprint(aspectRatio: Float) -> [Vec2] {
        Self.groundFootprint(position: camera.position, orientation: camera.orientation,
                             verticalFieldOfView: Self.fovDegrees, aspectRatio: aspectRatio)
    }

    static func groundFootprint(position: SIMD3<Float>, orientation: simd_quatf,
                                verticalFieldOfView: Float, aspectRatio: Float) -> [Vec2] {
        guard aspectRatio.isFinite, aspectRatio > 0, position.y > 0,
              verticalFieldOfView > 0, verticalFieldOfView < 180 else { return [] }
        let halfHeight = tan(verticalFieldOfView * .pi / 360)
        let corners: [SIMD2<Float>] = [SIMD2(-1, 1), SIMD2(1, 1), SIMD2(1, -1), SIMD2(-1, -1)]
        var points: [Vec2] = []
        points.reserveCapacity(4)
        for corner in corners {
            let ray = orientation.act(SIMD3(corner.x * halfHeight * aspectRatio, corner.y * halfHeight, -1))
            guard ray.y < -0.00001 else { return [] }
            let hit = position + ray * (-position.y / ray.y)
            guard hit.x.isFinite, hit.z.isFinite else { return [] }
            points.append(Vec2(Double(hit.x) * Balance.unitsPerMeter, -Double(hit.z) * Balance.unitsPerMeter))
        }
        return points
    }

    /// 揺れを加える（0〜1、重ねると加算で上限 1）。
    func addShake(_ amount: Float) {
        trauma = min(1, trauma + amount)
    }

    /// target = 追従対象の world (x, z)。snap = true で即座に移動（遠距離のワープ時）。
    func update(target: SIMD2<Float>, zoom: Double, free: Bool, dt: Float, mapMeters: Float) {
        time += dt
        let lead = free ? SIMD2<Float>.zero : SIMD2(0, -CameraRig.focusLead)
        let desired = CameraRig.clampFocus(target + lead, mapMeters: mapMeters)
        if !initialized || simd_distance(desired, focus.value) > 25 {
            focus.snap(to: desired)
            distance.value = CameraRig.distance(forZoom: zoom)
            initialized = true
        } else {
            focus.update(target: desired, smoothTime: free ? 0.16 : 0.11, dt: dt)
        }
        distance.update(target: CameraRig.distance(forZoom: zoom), smoothTime: 0.25, dt: dt)

        var pos = SIMD3(focus.value.x, 0, focus.value.y) + CameraRig.offset(distance: distance.value)
        if trauma > 0.001 {
            let k = trauma * trauma
            let sx = sin(time * 37) * 0.6 + sin(time * 61 + 1.3) * 0.4
            let sy = sin(time * 43 + 2.1) * 0.6 + sin(time * 71 + 0.4) * 0.4
            pos += SIMD3(sx, sy * 0.6, sy * 0.3) * (0.35 * k)
            trauma = max(0, trauma - dt * 1.8)
        }
        camera.position = pos
    }
}
