import Foundation
import RealityKit
import simd
import VelstriaCore

// 担当: battle-renderer。見下ろしカメラ（透視 ~48°、俯角 56°、回転なし）。
// 注視点を臨界減衰バネで追従し、地図内にクランプ。大きな出来事で小さく揺らす（トラウマ方式）。
// 観戦（BattleWorld が CameraDrive で指示する）:
// - 倍率の範囲が広い（spectatorZoomRange。地図の余白は広げた分だけ内側へ寄せ、地図の外の虚空を見せない）
// - 追う対象の切替は glide（時間指定のイーズ）か cut（即座）。指で動かす自由カメラは direct（ばねを掛けない）
// - 複数の対象を収める framing（注視点と距離を逆算）、画面上の点 → 地面の点の変換（パン・ピンチ）

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

/// カメラの移り方。
enum CameraTransition: Equatable {
    /// 通常の追従（臨界減衰ばね。遠いワープは従来どおり即座に合わせる）。
    case follow
    /// その場で切り替える（最初のフレーム・シーク・再同期・遠い対象への切替）。
    case cut
    /// 指定秒で滑らかに移る（近い対象への切替）。移動中も移り先の対象の動きに追従する。
    case glide(Float)
}

/// 1 フレーム分のカメラの指示（BattleWorld が決める）。
struct CameraDrive {
    /// 追従先の world (x, z)。
    var target: SIMD2<Float>
    /// 倍率（1 = baseDistance）。zoomRange に丸める。
    var zoom: Double
    /// 自由視点（追従先の前方へずらさない。注視点のばねも少し緩い）。
    var free = false
    /// 注視点を追従先より画面の上（北）へずらす量（m。nil = 既定: 追従は focusLead、自由視点は 0）。
    /// 負の値で追従先が画面の中央より上に来る。
    var lead: Float?
    var transition: CameraTransition = .follow
    /// 指で直接動かしている（ばねを掛けずに注視点を合わせる）。
    var direct = false
    /// ピンチ中（距離もほぼ即座に合わせる）。
    var directZoom = false
    /// 注視点・距離のばねの時定数（nil = 既定）。
    var focusSmoothTime: Float?
    var zoomSmoothTime: Float?
    /// 25 m を超える注視点の跳び（帰還・復活のワープ）を即座に合わせるか（framing は滑らかに寄せる）。
    var snapsOnTeleport = true
    var zoomRange: ClosedRange<Double> = CameraRig.playerZoomRange
}

@MainActor
final class CameraRig {
    nonisolated static let pitchDegrees: Float = 56
    nonisolated static let fovDegrees: Float = 48
    /// cameraZoom = 1 のときの注視点までの距離（m）。
    nonisolated static let baseDistance: Float = 12.5
    /// 注視点を置く位置（ヒーローの少し前方 = 画面のやや下にヒーロー）。
    nonisolated static let focusLead: Float = 0.9
    /// プレイヤーの倍率（設定 0.8〜1.3 + 余裕）。
    nonisolated static let playerZoomRange: ClosedRange<Double> = 0.7...1.4
    /// 観戦者の倍率（ピンチ・自動カメラの framing）。2.5 で地図のおよそ半分が映る。
    nonisolated static let spectatorZoomRange: ClosedRange<Double> = 0.7...2.5
    /// これより遠い対象への切替は滑らかに移らず切り替える（m。地図の端から端を流し撮りしない）。
    nonisolated static let cutDistance: Float = 45
    /// 追従中にこれより大きく跳んだら即座に合わせる（帰還・復活のワープ）。
    nonisolated static let teleportSnapDistance: Float = 25
    /// 地図の余白・倍率による拡大の基準にする画面の縦横比（横長 iPhone）。
    nonisolated static let designAspect: Float = 2.16

    let camera = PerspectiveCamera()
    private(set) var focus = CriticallyDampedSpring(.zero)
    private var distance = CriticallyDampedScalar(value: baseDistance)
    private var trauma: Float = 0
    private var time: Float = 0
    private var initialized = false
    private var glide: Glide?

    private struct Glide {
        var from: SIMD2<Float>
        var elapsed: Float
        var duration: Float
    }

    init() {
        camera.name = "camera"
        camera.camera = PerspectiveCameraComponent(near: 1.0, far: 160, fieldOfViewInDegrees: CameraRig.fovDegrees,
                                                   fieldOfViewOrientation: .vertical)
        camera.orientation = CameraRig.orientation
    }

    nonisolated static var orientation: simd_quatf {
        simd_quatf(angle: -pitchDegrees * .pi / 180, axis: [1, 0, 0])
    }

    /// 注視点（world xz の (x, z)）から見たカメラ位置のオフセット。
    nonisolated static func offset(distance d: Float) -> SIMD3<Float> {
        let p = pitchDegrees * .pi / 180
        return SIMD3(0, d * sin(p), d * cos(p))
    }

    /// 注視点を地図内に保つ（外周の森が少し見える程度の余白）。
    nonisolated static func clampFocus(_ f: SIMD2<Float>, mapMeters M: Float) -> SIMD2<Float> {
        clampFocus(f, mapMeters: M, zoom: 1)
    }

    /// 倍率つき。プレイヤーの範囲（≤ 1.4）では従来の余白、観戦者が引いた分だけ余白を広げて、
    /// 画面に映る地図の外側の幅を引く前と同じに保つ（地図が小さく映る時は中央に置く）。
    nonisolated static func clampFocus(_ f: SIMD2<Float>, mapMeters M: Float, zoom: Double) -> SIMD2<Float> {
        let extra = Float(max(0, zoom - playerZoomRange.upperBound))
        let grow = marginGrowthPerZoom
        let side = 5.5 + extra * grow.side
        let north = 3.5 + extra * grow.north
        let south = 7.5 + extra * grow.south
        let x = side <= M - side ? min(max(f.x, side), M - side) : M / 2
        let zMin = -(M - north), zMax = -south
        let z = zMin <= zMax ? min(max(f.y, zMin), zMax) : (zMin + zMax) / 2
        return SIMD2(x, z)
    }

    /// 倍率 1 増えるごとに画面の端が注視点から離れる量（m）: 横は注視点の行の半幅、北・南は画面の上端・下端まで。
    nonisolated static let marginGrowthPerZoom: (side: Float, north: Float, south: Float) = {
        let unit = footprintPerDistance(aspectRatio: designAspect)
        let side = baseDistance * tan(fovDegrees * .pi / 360) * designAspect
        return (side, baseDistance * unit.north, baseDistance * unit.south)
    }()

    nonisolated static func distance(forZoom zoom: Double) -> Float {
        distance(forZoom: zoom, range: playerZoomRange)
    }

    nonisolated static func distance(forZoom zoom: Double, range: ClosedRange<Double>) -> Float {
        guard zoom.isFinite else { return baseDistance }
        return baseDistance * Float(min(max(zoom, range.lowerBound), range.upperBound))
    }

    /// 切替の移動にかける時間（秒。近いほど短い）。
    nonisolated static func glideDuration(distance d: Float) -> Float {
        0.45 + min(1, max(0, d) / cutDistance) * 0.5
    }

    /// 減衰中を含む、いま描いているカメラの距離（m）と倍率。影・頭上バー・指の操作はこちらを使う。
    var currentDistance: Float { distance.value }
    var currentZoom: Double { Double(distance.value / CameraRig.baseDistance) }
    /// 切替の移動中。
    var isGliding: Bool { glide != nil }

    // MARK: 画面と地面

    /// 画面上の点（正規化: x = -1 左 … 1 右、y = -1 下 … 1 上）が指す地面の点の、注視点からのずれ（world x・z）。
    /// カメラの距離 1 あたり（距離 d では d 倍。カメラは回転しないので、注視点がどこでも同じ）。
    nonisolated static func groundOffsetPerDistance(ndc: SIMD2<Float>, aspectRatio: Float) -> SIMD2<Float>? {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return nil }
        let halfHeight = tan(fovDegrees * .pi / 360)
        let pos = offset(distance: 1)
        let ray = orientation.act(SIMD3(ndc.x * halfHeight * aspectRatio, ndc.y * halfHeight, -1))
        guard ray.y < -0.00001 else { return nil }
        let hit = pos + ray * (-pos.y / ray.y)
        guard hit.x.isFinite, hit.z.isFinite else { return nil }
        return SIMD2(hit.x, hit.z)
    }

    /// 距離 1 の時に画面に映る地面: 注視点から上端（北）・下端（南）までと、上端・下端の半幅（m）。
    nonisolated static func footprintPerDistance(aspectRatio: Float) -> (north: Float, south: Float, topHalfWidth: Float,
                                                             bottomHalfWidth: Float) {
        let top = groundOffsetPerDistance(ndc: SIMD2(1, 1), aspectRatio: aspectRatio) ?? SIMD2(1.6, -0.77)
        let bottom = groundOffsetPerDistance(ndc: SIMD2(1, -1), aspectRatio: aspectRatio) ?? SIMD2(0.74, 0.41)
        return (-top.y, bottom.y, top.x, bottom.x)
    }

    /// 複数の点（world x・z）を画面に収める注視点（ずらしなし）と距離。
    /// margin: 点の外側に残す余白（m。北は頭上のバーの分を多めに）。距離は minDistance〜maxDistance に丸める。
    nonisolated static func framing(_ points: [SIMD2<Float>], aspectRatio: Float,
                        margin: (side: Float, north: Float, south: Float) = (3, 3.5, 2),
                        minDistance: Float = baseDistance,
                        maxDistance: Float = baseDistance * Float(spectatorZoomRange.upperBound))
        -> (focus: SIMD2<Float>, distance: Float)? {
        guard let first = points.first else { return nil }
        var lo = first, hi = first
        for p in points.dropFirst() {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        let unit = footprintPerDistance(aspectRatio: aspectRatio)
        let halfWidth = (hi.x - lo.x) / 2 + margin.side
        let north = lo.y - margin.north   // world z は北ほど小さい
        let south = hi.y + margin.south
        // 縦: 余白込みの奥行きが画面の上端〜下端に収まる。横: 画面で一番狭い下端の幅に収まる（控えめな見積もり）
        let dVertical = (south - north) / max(0.01, unit.north + unit.south)
        let dHorizontal = halfWidth / max(0.01, unit.bottomHalfWidth)
        let d = min(max(max(dVertical, dHorizontal), minDistance), maxDistance)
        // 余白込みの箱の中心を、画面に映る地面の縦の中央へ置く
        let center = (north + south) / 2
        let z = center - (unit.south - unit.north) * d / 2
        return (SIMD2((lo.x + hi.x) / 2, z), d)
    }

    /// Screen corners intersected with y = 0, in clockwise sim coordinates.
    /// Uses the rendered pose, including damping, map-edge clamping, zoom and camera shake.
    func groundFootprint(aspectRatio: Float) -> [Vec2] {
        Self.groundFootprint(position: camera.position, orientation: camera.orientation,
                             verticalFieldOfView: Self.fovDegrees, aspectRatio: aspectRatio)
    }

    nonisolated static func groundFootprint(position: SIMD3<Float>, orientation: simd_quatf,
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

    /// target = 追従対象の world (x, z)。遠距離のワープ（25 m 超）は即座に合わせる。
    func update(target: SIMD2<Float>, zoom: Double, free: Bool, dt: Float, mapMeters: Float) {
        update(CameraDrive(target: target, zoom: zoom, free: free), dt: dt, mapMeters: mapMeters)
    }

    func update(_ d: CameraDrive, dt: Float, mapMeters: Float) {
        time += dt
        let targetDistance = CameraRig.distance(forZoom: d.zoom, range: d.zoomRange)
        let lead = d.lead ?? (d.free ? 0 : CameraRig.focusLead)
        let desired = CameraRig.clampFocus(d.target + SIMD2(0, -lead), mapMeters: mapMeters,
                                           zoom: Double(targetDistance / CameraRig.baseDistance))
        var transition = d.transition
        if !initialized { transition = .cut }
        switch transition {
        case .cut:
            focus.snap(to: desired)
            distance = CriticallyDampedScalar(value: targetDistance)
            glide = nil
            initialized = true
        case .glide(let duration):
            glide = Glide(from: focus.value, elapsed: 0, duration: max(0.05, duration))
        case .follow:
            break
        }
        if d.direct {
            // 指の操作が最優先（切替の移動中でも止めて指に付いてくる）
            glide = nil
            focus.snap(to: desired)
        } else if var g = glide {
            // 移り先の対象が動いても、残り時間で追いつくように補間する（イーズインアウト）
            g.elapsed += dt
            let t = min(1, g.elapsed / g.duration)
            let e = t * t * (3 - 2 * t)
            focus.snap(to: g.from + (desired - g.from) * e)
            glide = t >= 1 ? nil : g
        } else if d.snapsOnTeleport && simd_distance(desired, focus.value) > CameraRig.teleportSnapDistance {
            focus.snap(to: desired)
            distance.value = targetDistance
        } else {
            focus.update(target: desired, smoothTime: d.focusSmoothTime ?? (d.free ? 0.16 : 0.11), dt: dt)
        }
        distance.update(target: targetDistance, smoothTime: d.directZoom ? 0.04 : (d.zoomSmoothTime ?? 0.25), dt: dt)

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
