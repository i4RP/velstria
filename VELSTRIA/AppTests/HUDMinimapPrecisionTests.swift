import SwiftUI
import simd
import XCTest
@testable import VELSTRIA
import VelstriaCore

@MainActor
final class HUDMinimapPrecisionTests: XCTestCase {
    private func makeModel() -> HUDModel {
        let config = MatchFactory.standardMatch(humanHeroID: "H001", humanName: "T", seed: 11)
        return HUDModel(controller: BattleController(launch: BattleLaunch(config: config)))
    }

    func testPaddedProjectionUsesTheSameExtentForMarkersAndTouches() {
        for size in [CGFloat(132), 164, 340] {
            let projection = HUDMinimapProjection(size: size, mapSize: 9000, inset: 9)
            XCTAssertEqual(projection.point(.zero), CGPoint(x: 9, y: size - 9))
            XCTAssertEqual(projection.point(Vec2(9000, 9000)), CGPoint(x: size - 9, y: 9))
            for p in [Vec2.zero, Vec2(4500, 4500), Vec2(733, 8700), Vec2(9000, 9000)] {
                let roundTrip = projection.world(projection.point(p))
                XCTAssertEqual(roundTrip.x, p.x, accuracy: 1e-8)
                XCTAssertEqual(roundTrip.y, p.y, accuracy: 1e-8)
            }
            XCTAssertEqual(projection.world(CGPoint(x: -20, y: size + 20)), .zero)
            XCTAssertEqual(projection.length(9000), size - 18)
        }
        XCTAssertEqual(HUDMinimapProjection(size: 0).world(.zero), Balance.mapCenter)
        XCTAssertEqual(HUDMinimapProjection(size: 10, inset: 8).world(.zero), Balance.mapCenter)
    }

    func testViewportEdgesAreClippedAtTheirActualIntersections() {
        let projection = HUDMinimapProjection(size: 150, mapSize: 100)
        let diamond = [Vec2(50, 140), Vec2(140, 50), Vec2(50, -40), Vec2(-40, 50)]
        let clipped = projection.clippedPolygon(diamond)
        XCTAssertEqual(clipped.count, 8, "Clamping four vertices would give an incorrect diamond")
        for p in clipped {
            XCTAssertTrue((0...100).contains(p.x))
            XCTAssertTrue((0...100).contains(p.y))
            XCTAssertEqual(abs(p.x - 50) + abs(p.y - 50), 90, accuracy: 1e-8)
        }
        XCTAssertTrue(projection.clippedPolygon([Vec2(-20, 10), Vec2(-10, 20), Vec2(-10, 0)]).isEmpty)
        XCTAssertTrue(projection.clippedPolygon([Vec2(.nan, 0), .zero, Vec2(1, 1)]).isEmpty)
    }

    func testGroundFootprintProjectsBackToAllFourScreenCorners() {
        let rig = CameraRig()
        let expected: [SIMD2<Float>] = [SIMD2(-1, 1), SIMD2(1, 1), SIMD2(1, -1), SIMD2(-1, -1)]
        for aspect in [Float(1.8), 2.16, 2.4] {
            for zoom in [0.8, 1.0, 1.3] {
                for target in [SIMD2<Float>(60, -60), SIMD2(-20, 50), SIMD2(20, -70)] {
                    rig.update(target: target, zoom: zoom, free: true, dt: 1.0 / 60, mapMeters: 120)
                    let polygon = rig.groundFootprint(aspectRatio: aspect)
                    XCTAssertEqual(polygon.count, 4)
                    let tangent = tan(CameraRig.fovDegrees * .pi / 360)
                    for (p, corner) in zip(polygon, expected) {
                        let local = rig.camera.orientation.inverse.act(worldPosition(p) - rig.camera.position)
                        XCTAssertEqual(local.x / -local.z / tangent / aspect, corner.x, accuracy: 0.00002)
                        XCTAssertEqual(local.y / -local.z / tangent, corner.y, accuracy: 0.00002)
                    }
                    XCTAssertGreaterThan(polygon[0].distance(to: polygon[1]), polygon[2].distance(to: polygon[3]),
                                         "The far edge is wider: the camera footprint is not a rectangle")
                }
            }
        }
        XCTAssertTrue(rig.groundFootprint(aspectRatio: 0).isEmpty)
    }

    func testPausedCameraCanRefreshWithoutAdvancingTheSimulation() {
        let model = makeModel()
        let controller = model.controller
        controller.isPaused = true
        let tick = controller.hudTick
        let polygon = [Vec2(-100, 1000), Vec2(2000, 1000), Vec2(1500, 0), Vec2(0, 0)]
        controller.updateCameraViewport(polygon, dt: 1.0 / 30)
        model.refreshMinimapCamera()
        XCTAssertEqual(controller.hudTick, tick)
        XCTAssertGreaterThan(controller.cameraViewportTick, 0)
        XCTAssertEqual(model.minimap.viewportPolygon, HUDMinimapProjection(size: 1).clippedPolygon(polygon))
        let version = model.minimapVersion
        model.refreshMinimapCamera()
        XCTAssertEqual(model.minimapVersion, version, "Stationary camera should not invalidate the Canvas")
    }

    func testFreeCameraDoesNotOffsetTheRequestedMapPosition() {
        let target = SIMD2<Float>(60, -60)
        let freeRig = CameraRig()
        freeRig.update(target: target, zoom: 1, free: true, dt: 0, mapMeters: 120)
        XCTAssertEqual(freeRig.focus.value, target)
        let followRig = CameraRig()
        followRig.update(target: target, zoom: 1, free: false, dt: 0, mapMeters: 120)
        XCTAssertEqual(followRig.focus.value.y, target.y - CameraRig.focusLead, accuracy: 0.0001)
    }

    func testHiddenHeroesKeepLastSeenPositionThenExpire() throws {
        let model = makeModel()
        var state = model.controller.state
        let enemy = try XCTUnwrap(state.heroIndices.first { state.units[$0].team == .red })
        for i in state.heroIndices where state.units[i].team == .red { state.units[i].visibleMask = 0 }
        let seen = Vec2(5200, 6800)
        state.units[enemy].pos = seen
        state.units[enemy].prevPos = seen
        state.units[enemy].visibleMask = Team.blue.visionBit
        model.refreshMinimap(state, model.controller.ctx)
        XCTAssertEqual(model.minimap.heroes.filter { $0.team == .red }.map(\.pos), [seen])

        state.time += 1
        state.units[enemy].visibleMask = 0
        state.units[enemy].pos = Vec2(10000, 10000)
        state.units[enemy].prevPos = state.units[enemy].pos
        model.refreshMinimap(state, model.controller.ctx)
        let ghost = try XCTUnwrap(model.minimap.heroes.first { $0.team == .red })
        XCTAssertEqual(ghost.pos, seen)
        XCTAssertLessThan(ghost.alpha, 1)
        XCTAssertNil(ghost.facing, "A last-known marker must not reveal the hidden hero's new heading")

        state.time += HUDModel.ghostLifetime
        model.refreshMinimap(state, model.controller.ctx)
        XCTAssertFalse(model.minimap.heroes.contains { $0.team == .red })
    }

    func testMinimapUsesRendererInterpolationAndHumanDrawsLast() throws {
        let model = makeModel()
        var state = model.controller.state
        let human = try XCTUnwrap(state.humanHeroIndex)
        state.units[human].prevPos = Vec2(1000, 2000)
        state.units[human].pos = Vec2(1030, 2020)
        model.refreshMinimap(state, model.controller.ctx)
        let dot = try XCTUnwrap(model.minimap.heroes.last)
        XCTAssertTrue(dot.isHuman)
        XCTAssertEqual(dot.pos, Vec2.lerp(state.units[human].prevPos, state.units[human].pos,
                                        Double(Float(model.controller.interpolationAlpha))))
        XCTAssertNotNil(dot.heroID)
        XCTAssertNotNil(dot.facing)
        XCTAssertEqual(model.minimap.vision, state.vision)
    }

    func testUnseenOrdinaryCampDoesNotRevealAHiddenClear() throws {
        let model = makeModel()
        var state = model.controller.state
        let camp = try XCTUnwrap(model.controller.ctx.map.camps.firstIndex {
            $0.kind != .astralWyrm && $0.kind != .ancientColossus
        })
        state.time = 100
        state.vision.cells = state.vision.cells.map { _ in 0 }
        state.world.campRespawnAt[camp] = nil
        model.refreshMinimap(state, model.controller.ctx)
        XCTAssertTrue(model.minimap.camps[camp].alive)
        state.world.campRespawnAt[camp] = 180
        model.refreshMinimap(state, model.controller.ctx)
        XCTAssertTrue(model.minimap.camps[camp].alive)
        XCTAssertNil(model.minimap.camps[camp].respawnRemaining)
        state.vision.cells = state.vision.cells.map { _ in Team.blue.visionBit }
        model.refreshMinimap(state, model.controller.ctx)
        XCTAssertFalse(model.minimap.camps[camp].alive)
        XCTAssertEqual(model.minimap.camps[camp].respawnRemaining, 80)
    }

}
