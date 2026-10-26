import RealityKit
import simd
import XCTest
@testable import VELSTRIA
import VelstriaCore

@MainActor
final class FirstPersonCameraTests: XCTestCase {
    func testEyePositionFollowsImmediatelyAndIgnoresCinematicDisplacement() {
        let rig = CameraRig()
        rig.update(target: SIMD2(20, -20), zoom: 1, free: false, dt: 0, mapMeters: 120)
        rig.addPushIn(0.7)
        rig.addShake(1)
        for eye in [SIMD3<Float>(40, 1.7, -50), SIMD3(40.1, 1.7, -50.2), SIMD3(100, 1.7, -10)] {
            rig.updateFirstPerson(eye: eye, yaw: 0.6, pitch: -0.2, dt: 1.0 / 60)
            XCTAssertEqual(rig.camera.position, eye, "視点は移動中も体の目の位置から遅れない")
            XCTAssertEqual(rig.gamePose.position, eye)
            XCTAssertEqual(rig.focus.value, SIMD2(eye.x, eye.z))
            XCTAssertTrue(rig.isFirstPerson)
        }
        XCTAssertEqual(rig.camera.camera.near, CameraRig.firstPersonNear)
        XCTAssertEqual(rig.verticalFOV, CameraRig.firstPersonFOV)
        XCTAssertEqual(simd_distance(rig.camera.orientation.act([0, 0, -1]),
                                    CameraPose(position: .zero, yaw: 0.6, pitch: -0.2).forward), 0, accuracy: 1e-5)
    }

    func testLookingDownProjectsTorsoBelowEyes() throws {
        let rig = CameraRig()
        let eye = SIMD3<Float>(40, 1.7, -50)
        let torso = eye + SIMD3<Float>(0, -0.7, 0.06)
        let size = CGSize(width: 844, height: 390)
        rig.updateFirstPerson(eye: eye, yaw: 0, pitch: -80 * .pi / 180, dt: 0)
        let projection = CombatTextProjection(position: rig.camera.position, orientation: rig.camera.orientation,
                                             viewport: size, verticalFOV: rig.verticalFOV,
                                             near: rig.camera.camera.near, far: rig.camera.camera.far)
        let point = try XCTUnwrap(projection.project(torso), "下を向くと目より下にある自分の胴体が映る")
        XCTAssertEqual(point.x, size.width / 2, accuracy: 0.01)
        XCTAssertTrue((0...size.height).contains(point.y))
        XCTAssertGreaterThan(point.y, size.height / 2)

        let upright = CombatTextProjection(position: eye, orientation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                          viewport: size, verticalFOV: rig.verticalFOV,
                                          near: rig.camera.camera.near)
        XCTAssertNil(upright.project(torso), "正面を向いた視界を自分の胴体でふさがない")
    }

    func testReturningToSpectatorRestoresOverheadLensAndOrientation() {
        let rig = CameraRig()
        rig.updateFirstPerson(eye: SIMD3(40, 1.7, -50), yaw: 1.2, pitch: 0.4, dt: 0)
        rig.update(CameraDrive(target: SIMD2(60, -60), zoom: 1.5, free: true,
                               zoomRange: CameraRig.spectatorZoomRange), dt: 0, mapMeters: 120)
        XCTAssertFalse(rig.isFirstPerson)
        XCTAssertEqual(rig.camera.camera.near, 1)
        XCTAssertEqual(rig.verticalFOV, CameraRig.fovDegrees)
        XCTAssertEqual(simd_distance(rig.camera.orientation.act([0, 0, -1]),
                                    CameraRig.orientation.act([0, 0, -1])), 0, accuracy: 1e-5)
        XCTAssertGreaterThan(rig.camera.position.y, 5)
        XCTAssertEqual(rig.groundFootprint(aspectRatio: CameraRig.designAspect).count, 4)
    }

    func testFirstPersonFrustumRejectsBehindAndOffscreenWithoutDroppingTallUnits() {
        var frustum = FirstPersonFrustum(position: SIMD3(0, 1.7, 0),
                                        orientation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                        verticalFOV: CameraRig.firstPersonFOV, aspect: CameraRig.designAspect, far: 160)
        XCTAssertTrue(frustum.contains(SIMD3(0, 0, -20), height: 2))
        XCTAssertTrue(frustum.contains(SIMD3(0, 0, -20), height: 12))
        XCTAssertFalse(frustum.contains(SIMD3(0, 0, 20), height: 2))
        XCTAssertFalse(frustum.contains(SIMD3(100, 0, -20), height: 2))
        XCTAssertFalse(frustum.contains(SIMD3(0, 0, -180), height: 2))
        frustum.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        XCTAssertTrue(frustum.contains(SIMD3(-20, 0, 0), height: 2))
        XCTAssertFalse(frustum.contains(SIMD3(20, 0, 0), height: 2))
    }

    func testHorizonFootprintRemainsFiniteAndBounded() {
        let rig = CameraRig()
        let eye = SIMD3<Float>(40, 1.7, -50)
        for pitch: Float in [-0.7, 0, 0.7] {
            rig.updateFirstPerson(eye: eye, yaw: 0.8, pitch: pitch, dt: 0)
            let footprint = rig.groundFootprint(aspectRatio: CameraRig.designAspect)
            XCTAssertEqual(footprint.count, 4, "水平線より上の画面の隅も有限の表示範囲を持つ")
            for point in footprint {
                XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                let world = worldPosition(point)
                XCTAssertLessThanOrEqual(simd_distance(SIMD2(world.x, world.z), SIMD2(eye.x, eye.z)),
                                         rig.camera.camera.far + 0.01)
            }
        }
    }

    func testFirstPersonBarDepthTracksLookDirectionAndScalesAtCloseRange() {
        let savedOrientation = OverheadBar.cameraOrientation
        defer { OverheadBar.cameraOrientation = savedOrientation }
        OverheadBar.cameraOrientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        XCTAssertEqual(OverheadBar.viewDepth(world: SIMD3(-5, 0, 0), camera: .zero), 5, accuracy: 1e-5)
        XCTAssertEqual(OverheadBar.viewDepth(world: SIMD3(5, 0, 0), camera: .zero), -5, accuracy: 1e-5)
        let close = OverheadBar.firstPersonScreenScale(distance: 1)
        let distant = OverheadBar.firstPersonScreenScale(distance: 10)
        XCTAssertEqual(close * 10, distant, accuracy: 1e-5,
                       "近距離でもバーの大きさを距離に比例させ、画面を覆わない")
        XCTAssertLessThan(close, 0.1)
    }
}
