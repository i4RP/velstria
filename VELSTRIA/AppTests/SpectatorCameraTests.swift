import RealityKit
import simd
import UIKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 観戦カメラと観戦の描画: カメラの移り方（glide / cut / direct・snap の反映）・広い倍率と地図の余白・framing の逆算、
/// 指の操作の計算（パン・ピンチ）、追従先の解決（消えた対象・霧の向こう・倒れた対象）、霧の視点の切替、
/// ゾーンの観戦色、詠唱ループの視界、演出の間引きの範囲、影・頭上バーの倍率、追っているヒーローの輪。
@MainActor
final class SpectatorCameraTests: XCTestCase {
    private let M = MapScene.mapMeters

    // MARK: カメラの移り方

    func testCutSnapsAndGlideEasesToTheTarget() {
        let rig = CameraRig()
        rig.update(CameraDrive(target: SIMD2(20, -20), zoom: 1), dt: 0, mapMeters: M)
        let start = rig.focus.value
        // glide: 0.6 秒でイーズしながら移り先に着く（途中は両端の間）
        var drive = CameraDrive(target: SIMD2(40, -20), zoom: 1)
        drive.transition = .glide(0.6)
        rig.update(drive, dt: 1.0 / 60, mapMeters: M)
        drive.transition = .follow
        XCTAssertTrue(rig.isGliding)
        var lastX = rig.focus.value.x
        for _ in 0..<17 {
            rig.update(drive, dt: 1.0 / 60, mapMeters: M)
            XCTAssertGreaterThanOrEqual(rig.focus.value.x, lastX - 1e-4, "glide は行き過ぎない")
            lastX = rig.focus.value.x
        }
        XCTAssertGreaterThan(rig.focus.value.x, start.x + 1)
        XCTAssertLessThan(rig.focus.value.x, 40)
        for _ in 0..<30 { rig.update(drive, dt: 1.0 / 60, mapMeters: M) }
        XCTAssertFalse(rig.isGliding)
        XCTAssertEqual(rig.focus.value.x, 40, accuracy: 0.05)
        // cut: その場で合わせる（距離も）
        var cut = CameraDrive(target: SIMD2(90, -90), zoom: 1.3)
        cut.transition = .cut
        rig.update(cut, dt: 1.0 / 60, mapMeters: M)
        XCTAssertEqual(rig.focus.value, CameraRig.clampFocus(SIMD2(90, -90 - CameraRig.focusLead), mapMeters: M, zoom: 1.3))
        XCTAssertEqual(rig.currentDistance, CameraRig.baseDistance * 1.3, accuracy: 1e-4)
    }

    func testDirectDriveIgnoresTheSpringAndCancelsGlides() {
        let rig = CameraRig()
        rig.update(CameraDrive(target: SIMD2(30, -30), zoom: 1, free: true), dt: 0, mapMeters: M)
        var glide = CameraDrive(target: SIMD2(50, -30), zoom: 1)
        glide.transition = .glide(1)
        rig.update(glide, dt: 1.0 / 60, mapMeters: M)
        XCTAssertTrue(rig.isGliding)
        var pan = CameraDrive(target: SIMD2(33, -31), zoom: 1, free: true)
        pan.direct = true
        rig.update(pan, dt: 1.0 / 60, mapMeters: M)
        XCTAssertFalse(rig.isGliding, "指の操作は切替の移動より優先")
        XCTAssertEqual(rig.focus.value, SIMD2(33, -31), "ばねを掛けずに指に付いてくる")
        // ピンチは距離もほぼ即座
        var pinch = CameraDrive(target: SIMD2(33, -31), zoom: 2.2, free: true)
        pinch.zoomRange = CameraRig.spectatorZoomRange
        pinch.directZoom = true
        for _ in 0..<12 { rig.update(pinch, dt: 1.0 / 60, mapMeters: M) }
        XCTAssertEqual(rig.currentZoom, 2.2, accuracy: 0.02)
    }

    func testSpectatorZoomRangeAndScaledMapMargins() {
        XCTAssertEqual(CameraRig.distance(forZoom: 2.2), CameraRig.distance(forZoom: 1.4), "プレイヤーの範囲は 1.4 まで")
        XCTAssertEqual(CameraRig.distance(forZoom: 2.2, range: CameraRig.spectatorZoomRange), CameraRig.baseDistance * 2.2)
        XCTAssertEqual(CameraRig.distance(forZoom: 9, range: CameraRig.spectatorZoomRange), CameraRig.baseDistance * 2.5)
        XCTAssertEqual(CameraRig.distance(forZoom: .nan, range: CameraRig.spectatorZoomRange), CameraRig.baseDistance)
        // プレイヤーの範囲では従来の余白のまま
        let corner = SIMD2<Float>(-50, 50)
        XCTAssertEqual(CameraRig.clampFocus(corner, mapMeters: M, zoom: 1.3), CameraRig.clampFocus(corner, mapMeters: M))
        // 引くほど内側へ寄せ、地図の外が映る幅は引く前と同じ（左端・上端）
        let aspect = CameraRig.designAspect
        func overshoot(_ zoom: Double) -> (left: Float, north: Float) {
            let f = CameraRig.clampFocus(SIMD2(-50, -500), mapMeters: M, zoom: zoom)
            let d = CameraRig.baseDistance * Float(zoom)
            let side = d * tan(CameraRig.fovDegrees * .pi / 360) * aspect
            let north = CameraRig.groundOffsetPerDistance(ndc: SIMD2(0, 1), aspectRatio: aspect)!.y * d
            return (side - f.x, -(f.y + north) - M)
        }
        let near = overshoot(1.4), far = overshoot(2.5)
        XCTAssertEqual(far.left, near.left, accuracy: 0.05, "左右の地図の外の幅は倍率によらない")
        XCTAssertEqual(far.north, near.north, accuracy: 0.05, "北の地図の外の幅は倍率によらない")
        // 地図より画面が大きい極端な場合は中央
        let tiny = CameraRig.clampFocus(SIMD2(0, 0), mapMeters: 20, zoom: 2.5)
        XCTAssertEqual(tiny.x, 10)
    }

    func testGroundOffsetMatchesFootprintAndViewportCenterIsTheFocus() {
        let rig = CameraRig()
        rig.update(CameraDrive(target: SIMD2(40, -50), zoom: 1.7, free: true, zoomRange: CameraRig.spectatorZoomRange),
                   dt: 0, mapMeters: M)
        let aspect: Float = 874.0 / 402.0
        let fp = rig.groundFootprint(aspectRatio: aspect)
        XCTAssertEqual(fp.count, 4)
        // 画面の隅の地面 = 注視点 + 距離 × groundOffsetPerDistance
        let g = CameraRig.groundOffsetPerDistance(ndc: SIMD2(-1, 1), aspectRatio: aspect)! * rig.currentDistance
        let tl = rig.focus.value + g
        XCTAssertEqual(fp[0].x, Double(tl.x) * 100, accuracy: 1)
        XCTAssertEqual(fp[0].y, -Double(tl.y) * 100, accuracy: 1)
        // 4 隅の対角線の交点 = 画面の中心 = 注視点（射影変換は交点を保つ）
        let c = try! XCTUnwrap(HUDSpectatorGestureLayer.viewportCenter(fp))
        XCTAssertEqual(c.x, Double(rig.focus.value.x) * 100, accuracy: 1)
        XCTAssertEqual(c.y, -Double(rig.focus.value.y) * 100, accuracy: 1)
        XCTAssertNil(HUDSpectatorGestureLayer.viewportCenter([]))
    }

    func testFramingFitsAllPointsOnScreen() {
        let aspect: Float = 2.16
        let points: [SIMD2<Float>] = [SIMD2(30, -40), SIMD2(52, -44), SIMD2(41, -58), SIMD2(36, -35)]
        let fit = try! XCTUnwrap(CameraRig.framing(points, aspectRatio: aspect))
        XCTAssertGreaterThan(fit.distance, CameraRig.baseDistance, "広がった集団は引いて収める")
        let pos = SIMD3(fit.focus.x, 0, fit.focus.y) + CameraRig.offset(distance: fit.distance)
        let quad = CameraRig.groundFootprint(position: pos, orientation: CameraRig.orientation,
                                             verticalFieldOfView: CameraRig.fovDegrees, aspectRatio: aspect)
        for p in points {
            XCTAssertTrue(SpectatorCameraTests.inside(Vec2(Double(p.x) * 100, -Double(p.y) * 100), quad), "\(p) が画面の外")
        }
        // 1 人だけ・近い 2 人は最小の距離
        let one = try! XCTUnwrap(CameraRig.framing([SIMD2(10, -10)], aspectRatio: aspect))
        XCTAssertEqual(one.distance, CameraRig.baseDistance)
        XCTAssertNil(CameraRig.framing([], aspectRatio: aspect))
        // 地図全体ほど離れていても上限で止める
        let far = try! XCTUnwrap(CameraRig.framing([SIMD2(5, -5), SIMD2(115, -115)], aspectRatio: aspect))
        XCTAssertEqual(far.distance, CameraRig.baseDistance * 2.5)
    }

    /// 凸四角形（時計回り）の内側か。
    static func inside(_ p: Vec2, _ quad: [Vec2]) -> Bool {
        guard quad.count == 4 else { return false }
        var sign = 0.0
        for k in 0..<4 {
            let a = quad[k], b = quad[(k + 1) % 4]
            let c = (b - a).cross(p - a)
            if sign == 0 { sign = c } else if c * sign < 0 { return false }
        }
        return true
    }

    func testSwitchTransitionByDistance() {
        XCTAssertEqual(BattleWorld.transition(forSwitchDistance: 1), .follow)
        if case .glide(let t) = BattleWorld.transition(forSwitchDistance: 20) {
            XCTAssertGreaterThan(t, 0.45)
            XCTAssertLessThan(t, 0.95)
        } else {
            XCTFail("近い切替は滑らかに")
        }
        XCTAssertEqual(BattleWorld.transition(forSwitchDistance: 60), .cut, "遠い切替は即座に")
    }

    // MARK: 指の操作

    func testPanKeepsTheGroundUnderTheFinger() {
        let size = CGSize(width: 844, height: 390)
        let zoom = 1.6
        let start = Vec2(6000, 6000)
        let a = CGPoint(x: 300, y: 120), b = CGPoint(x: 520, y: 300)
        let focus = SpectatorCameraMath.panFocus(startFocus: start, from: a, to: b, size: size, zoom: zoom)
        let ga = SpectatorCameraMath.groundOffset(a, size: size, zoom: zoom)!
        let gb = SpectatorCameraMath.groundOffset(b, size: size, zoom: zoom)!
        let before = start + ga, after = focus + gb
        XCTAssertEqual(before.x, after.x, accuracy: 0.5)
        XCTAssertEqual(before.y, after.y, accuracy: 0.5)
        // 右へドラッグ = 注視点は西（sim -x）、下へドラッグ = 注視点は北（sim +y）
        XCTAssertLessThan(focus.x, start.x)
        XCTAssertGreaterThan(focus.y, start.y)
        // 地図の外へは出ない（カメラの余白と同じ）
        let edge = SpectatorCameraMath.panFocus(startFocus: Vec2(600, 600), from: CGPoint(x: 100, y: 100),
                                                to: CGPoint(x: 800, y: 380), size: size, zoom: zoom)
        XCTAssertEqual(edge, SpectatorCameraMath.clamp(edge, zoom: zoom))
        XCTAssertGreaterThan(edge.x, 0)
    }

    func testPinchZoomAndAnchor() {
        XCTAssertEqual(SpectatorCameraMath.pinchZoom(startZoom: 1, magnification: 0.5), 2)
        XCTAssertEqual(SpectatorCameraMath.pinchZoom(startZoom: 1, magnification: 2), 0.7, "観戦者の範囲に丸める")
        XCTAssertEqual(SpectatorCameraMath.pinchZoom(startZoom: 2, magnification: 0.1), 2.5)
        XCTAssertEqual(SpectatorCameraMath.pinchZoom(startZoom: 1.2, magnification: 0), 1.2, "壊れた値は無視")
        let size = CGSize(width: 812, height: 375)
        let anchor = CGPoint(x: 600, y: 90)
        let start = Vec2(5000, 7000)
        let f = SpectatorCameraMath.pinchFocus(startFocus: start, anchor: anchor, size: size, fromZoom: 1, toZoom: 2)
        let before = start + SpectatorCameraMath.groundOffset(anchor, size: size, zoom: 1)!
        let after = f + SpectatorCameraMath.groundOffset(anchor, size: size, zoom: 2)!
        XCTAssertEqual(before.x, after.x, accuracy: 0.5, "ピンチの中心の地面は動かない")
        XCTAssertEqual(before.y, after.y, accuracy: 0.5)
        // 滑りの長さは画面の短辺の 0.4 倍まで
        let end = SpectatorCameraMath.flingEnd(from: CGPoint(x: 100, y: 100), predicted: CGPoint(x: 2000, y: 100), size: size)
        XCTAssertEqual(end.x, 100 + 375 * 0.4, accuracy: 0.01)
        XCTAssertEqual(SpectatorCameraMath.flingEnd(from: .zero, predicted: CGPoint(x: 10, y: 0), size: size).x, 10)
    }

    // MARK: 描画世界

    private struct World {
        let controller: BattleController
        let world: BattleWorld
        let rig: CameraRig
        let arView: ARView
    }

    private func makeWorld(_ launch: BattleLaunch) -> World {
        let c = BattleController(launch: launch)
        let arView = ARView(frame: CGRect(x: 0, y: 0, width: 844, height: 390), cameraMode: .nonAR,
                            automaticallyConfigureSession: false)
        let settings = RenderSettings(quality: .preset(.low), frameRate: 60, showDamageNumbers: true, colorblind: false)
        let world = BattleWorld(controller: c, settings: settings, groundImage: nil, arView: arView,
                                overlay: CombatTextOverlay(frame: arView.bounds))
        let rig = CameraRig()
        world.sync(events: [], dt: 1.0 / 30, rig: rig)
        world.updateCamera(rig: rig, dt: 0, snap: true)
        return World(controller: c, world: world, rig: rig, arView: arView)
    }

    private func frames(_ w: World, _ n: Int, dt: Float = 1.0 / 30) {
        for _ in 0..<n {
            w.world.sync(events: [], dt: dt, rig: w.rig)
            w.world.updateCamera(rig: w.rig, dt: dt, snap: false)
        }
    }

    private func world(_ p: Vec2) -> SIMD2<Float> {
        let w = worldPosition(p)
        return SIMD2(w.x, w.z)
    }

    func testFollowFallbacksForVanishedHiddenAndDeadTargets() {
        var launch = BattleLaunch(config: MatchFactory.botMatch(seed: 41))
        launch.spectatorOptions.director = false
        let w = makeWorld(launch)
        defer { w.world.teardown() }
        let c = w.controller
        w.controller.markPresentationReady()
        var s = c.state
        let blue = s.heroIndices(team: .blue), red = s.heroIndices(team: .red)
        // 互いに離れた場所に置く（Blue 0 の近くに Blue 1、遠くに Blue 2）
        s.units[blue[0]].pos = Vec2(5000, 5000)
        s.units[blue[1]].pos = Vec2(5600, 5200)
        s.units[blue[2]].pos = Vec2(9000, 2000)
        s.units[red[0]].pos = Vec2(7000, 7000)
        for i in s.heroIndices { s.units[i].prevPos = s.units[i].pos }
        c.restore(s)
        let a = s.units[blue[0]].id
        c.cameraMode = .followUnit(a)
        frames(w, 60)
        XCTAssertLessThan(simd_distance(w.rig.focus.value, world(Vec2(5000, 5000)) + SIMD2(0, -CameraRig.focusLead)), 0.3)

        // 列から消えた対象: 地図の隅へ飛ばず直前の注視点に留まる（B25）
        let held = w.rig.focus.value
        c.cameraMode = .followUnit(987_654)
        frames(w, 30)
        XCTAssertLessThan(simd_distance(w.rig.focus.value, held), 0.01)

        // 霧の向こうの敵は追わない（Blue の視点で見えていない Red 0）
        c.spectatorVision = .blue
        var hidden = c.state
        hidden.units[red[0]].visibleMask = Team.red.visionBit
        c.restore(hidden)
        c.cameraMode = .followUnit(hidden.units[red[0]].id)
        frames(w, 30)
        XCTAssertLessThan(simd_distance(w.rig.focus.value, held), 0.01, "見えない敵の位置へ寄らない")
        c.spectatorVision = nil

        // 倒れた直後は倒れた場所、時間が経ったら近くの味方（B30）
        var dead = c.state
        dead.units[blue[0]].isAlive = false
        dead.units[blue[0]].hero?.respawnTimer = 20
        dead.units[blue[0]].deathTime = dead.time - 1
        c.restore(dead)
        c.cameraMode = .followUnit(a)
        XCTAssertEqual(w.world.resolveCameraAim().subject, a, "倒れた直後は本人（倒れた場所）")
        dead.units[blue[0]].deathTime = dead.time - BattleWorld.deathHoldSeconds - 0.1
        c.restore(dead)
        let aim = w.world.resolveCameraAim()
        XCTAssertEqual(aim.subject, dead.units[blue[1]].id, "一番近い生きている味方を映す")
        frames(w, 60)
        XCTAssertLessThan(simd_distance(w.rig.focus.value, world(Vec2(5600, 5200)) + SIMD2(0, -CameraRig.focusLead)), 0.5)
        // 復活したら本人へ戻る
        var alive = c.state
        alive.units[blue[0]].isAlive = true
        alive.units[blue[0]].hero?.respawnTimer = 0
        alive.units[blue[0]].deathTime = nil
        alive.units[blue[0]].pos = Vec2(1500, 1500)
        alive.units[blue[0]].prevPos = Vec2(1500, 1500)
        c.restore(alive)
        XCTAssertEqual(w.world.resolveCameraAim().subject, a)
    }

    func testSubjectSwitchGlidesOrCutsAndEpochCuts() {
        var launch = BattleLaunch(config: MatchFactory.botMatch(seed: 42))
        launch.spectatorOptions.director = false
        let w = makeWorld(launch)
        defer { w.world.teardown() }
        let c = w.controller
        c.markPresentationReady()
        var s = c.state
        let h = s.heroIndices
        s.units[h[0]].pos = Vec2(4000, 4000)
        s.units[h[1]].pos = Vec2(5500, 4600)     // 約 16 m
        s.units[h[2]].pos = Vec2(10500, 10000)   // 約 80 m 以上
        for i in h { s.units[i].prevPos = s.units[i].pos }
        c.restore(s)
        c.cameraMode = .followUnit(s.units[h[0]].id)
        frames(w, 40)
        c.cameraMode = .followUnit(s.units[h[1]].id)
        frames(w, 1)
        XCTAssertTrue(w.rig.isGliding, "近い対象への切替は滑らかに")
        frames(w, 40)
        XCTAssertFalse(w.rig.isGliding)
        c.cameraMode = .followUnit(s.units[h[2]].id)
        frames(w, 1)
        XCTAssertFalse(w.rig.isGliding)
        let target = CameraRig.clampFocus(world(Vec2(10500, 10000)) + SIMD2(0, -CameraRig.focusLead), mapMeters: M, zoom: 1)
        XCTAssertLessThan(simd_distance(w.rig.focus.value, target), 0.01, "遠い対象への切替は即座に")
        // 自由視点 → 追従も滑らかに
        c.cameraMode = .free(Vec2(9500, 9800))
        frames(w, 20)
        c.cameraMode = .followUnit(s.units[h[2]].id)
        frames(w, 1)
        XCTAssertTrue(w.rig.isGliding)
        frames(w, 40)
        // シーク・再同期（presentationEpoch）は即座に。snap: true も（B26）
        var moved = c.state
        moved.units[h[2]].pos = Vec2(10000, 9000)
        moved.units[h[2]].prevPos = moved.units[h[2]].pos
        c.restore(moved)
        frames(w, 1)
        let t2 = CameraRig.clampFocus(world(Vec2(10000, 9000)) + SIMD2(0, -CameraRig.focusLead), mapMeters: M, zoom: 1)
        XCTAssertLessThan(simd_distance(w.rig.focus.value, t2), 0.01)
        c.cameraMode = .followUnit(s.units[h[0]].id)
        w.world.updateCamera(rig: w.rig, dt: 1.0 / 30, snap: true)
        XCTAssertFalse(w.rig.isGliding, "snap は切替でも即座")
    }

    func testCameraHoldsStillWhileSeeking() async {
        var launch = BattleLaunch(config: MatchFactory.botMatch(seed: 47))
        launch.spectatorOptions.director = false
        let w = makeWorld(launch)
        defer { w.world.teardown() }
        let c = w.controller
        c.markPresentationReady()
        var s = c.state
        let h = s.heroIndices[0]
        let id = s.units[h].id
        s.units[h].pos = Vec2(4000, 4000)
        s.units[h].prevPos = s.units[h].pos
        c.restore(s)
        c.cameraMode = .followUnit(id)
        frames(w, 40)
        let held = w.rig.focus.value
        // シーク中（途中の tick の状態）: 追っている対象が遠くへ動いた状態でも、画を動かさない
        c.requestSeek(toTick: 450)
        XCTAssertNotNil(c.seekingToTick)
        var mid = c.state
        mid.units[h].pos = Vec2(10000, 9000)
        mid.units[h].prevPos = mid.units[h].pos
        c.restore(mid)
        frames(w, 20)
        XCTAssertLessThan(simd_distance(w.rig.focus.value, held), 0.01, "シーク中は直前の注視点に留まる")
        // 自由カメラ（指・ミニマップ）はシーク中も動かせる
        c.cameraMode = .free(Vec2(6000, 6000))
        frames(w, 30)
        XCTAssertLessThan(simd_distance(w.rig.focus.value, world(Vec2(6000, 6000))), 0.5)
        // シークが終われば今の状態の対象へ切り替える
        c.cameraMode = .followUnit(id)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(60))
        while c.seekingToTick != nil && clock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(c.seekingToTick)
        frames(w, 2)
        XCTAssertFalse(w.rig.isGliding, "シークの後は切り替え（滑らせない）")
        let after = try! XCTUnwrap(c.state.unit(id))
        XCTAssertLessThan(simd_distance(w.rig.focus.value,
                                        CameraRig.clampFocus(world(after.pos) + SIMD2(0, -CameraRig.focusLead), mapMeters: M, zoom: 1)),
                          1.0)
    }

    func testFramingFitsTheGroupAndDropsHiddenUnits() {
        var launch = BattleLaunch(config: MatchFactory.botMatch(seed: 43))
        launch.spectatorOptions.director = false
        let w = makeWorld(launch)
        defer { w.world.teardown() }
        let c = w.controller
        c.markPresentationReady()
        var s = c.state
        let b = s.heroIndices(team: .blue), r = s.heroIndices(team: .red)
        s.units[b[0]].pos = Vec2(5000, 5000)
        s.units[r[0]].pos = Vec2(7600, 5600)
        s.units[r[1]].pos = Vec2(5800, 3800)
        for i in s.heroIndices { s.units[i].prevPos = s.units[i].pos }
        c.restore(s)
        let ids = [s.units[b[0]].id, s.units[r[0]].id, s.units[r[1]].id]
        c.cameraMode = .framing(ids)
        let aim = w.world.resolveCameraAim()
        XCTAssertEqual(aim.kind, .framing)
        XCTAssertGreaterThan(aim.fitZoom ?? 0, 1, "広がった 3 人を収めるために引く")
        frames(w, 120)
        let quad = w.rig.groundFootprint(aspectRatio: 844.0 / 390.0)
        for i in [b[0], r[0], r[1]] {
            XCTAssertTrue(SpectatorCameraTests.inside(c.state.units[i].pos, quad), "framing の対象 \(i) が画面に入る")
        }
        // Blue の視点で見えない Red は収めない
        c.spectatorVision = .blue
        var hidden = c.state
        hidden.units[r[0]].visibleMask = Team.red.visionBit
        hidden.units[r[1]].visibleMask = Team.red.visionBit
        c.restore(hidden)
        let blueAim = w.world.resolveCameraAim()
        XCTAssertEqual(blueAim.fitZoom ?? 0, 1, accuracy: 1e-4, "見えているのは 1 人だけ")
        let only = world(Vec2(5000, 5000))
        XCTAssertLessThan(abs((blueAim.target?.x ?? 0) - only.x), 0.01)
    }

    func testSpectatorFogFollowsTheChosenVision() async {
        var launch = BattleLaunch(config: MatchFactory.botMatch(seed: 44))
        launch.spectatorOptions.director = false
        let w = makeWorld(launch)
        defer { w.world.teardown() }
        let c = w.controller
        let fog = try! XCTUnwrap(w.world.fog, "観戦者も霧を作っておく")
        XCTAssertNil(fog.team)
        XCTAssertTrue(fog.isShowingWarmup, "幕が上がるまでは透明な板を描いて準備")
        XCTAssertTrue(fog.entity.isEnabled)
        c.markPresentationReady()
        frames(w, 2)
        XCTAssertFalse(fog.entity.isEnabled, "全体視点では霧を出さない")
        XCTAssertTrue(fog.isSettled)
        for _ in 0..<20 { c.frame(dt: Balance.dt) }   // 視界を作る
        c.spectatorVision = .red
        frames(w, 1)
        XCTAssertEqual(fog.team, .red)
        XCTAssertFalse(fog.entity.isEnabled, "最初の目標が届くまでは古い霧を見せない")
        await waitFor { self.frames(w, 1); return fog.entity.isEnabled }
        XCTAssertTrue(fog.entity.isEnabled, "Red の視界の霧を出す")
        // 霧の濃さは Red の視界（Red の泉は見えていて、Blue の泉は霧）
        let redFountain = c.ctx.map.fountain(.red), blueFountain = c.ctx.map.fountain(.blue)
        await waitFor { self.frames(w, 1); return fog.isSettled }
        XCTAssertLessThan(fog.displayedField.value(atSim: redFountain, mapSize: c.ctx.map.size), 0.3)
        XCTAssertGreaterThan(fog.displayedField.value(atSim: blueFountain, mapSize: c.ctx.map.size), 0.7)
        // Blue へ切り替えると滑らかに入れ替わる（板は出したまま）
        c.spectatorVision = .blue
        frames(w, 1)
        XCTAssertTrue(fog.entity.isEnabled)
        await waitFor { self.frames(w, 1); return fog.isSettled }
        XCTAssertLessThan(fog.displayedField.value(atSim: blueFountain, mapSize: c.ctx.map.size), 0.3)
        // 一時停止中の切替も反映する（停止中は sync が呼ばれない）
        c.isPaused = true
        c.spectatorVision = nil
        w.world.updateCamera(rig: w.rig, dt: 1.0 / 30, snap: false)
        XCTAssertNil(fog.team)
        XCTAssertFalse(fog.entity.isEnabled)
        c.spectatorVision = .red
        await waitFor { w.world.updateCamera(rig: w.rig, dt: 1.0 / 30, snap: false); return fog.isSettled && fog.entity.isEnabled }
        XCTAssertEqual(fog.team, .red)
        XCTAssertLessThan(fog.displayedField.value(atSim: redFountain, mapSize: c.ctx.map.size), 0.3)
    }

    func testPlayersFogIgnoresSpectatorVision() {
        let w = makeWorld(BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 4)))
        defer { w.world.teardown() }
        XCTAssertEqual(w.world.fog?.team, .blue)
        XCTAssertNil(w.world.director, "プレイヤーには自動カメラを作らない")
        w.controller.spectatorVision = .red
        frames(w, 2)
        XCTAssertEqual(w.world.fog?.team, .blue)
        // 死亡中の味方追従は味方を画面の少し上に置く（下の味方一覧に隠れないように）
        let s = w.controller.state
        let ally = s.heroIndices(team: .blue).map { s.units[$0].id }.first { $0 != w.controller.humanHeroID }!
        w.controller.cameraMode = .followUnit(ally)
        XCTAssertEqual(w.world.resolveCameraAim().lead, BattleWorld.deathFollowLead)
    }

    private func waitFor(timeout: Double = 5, _ condition: @escaping () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while !condition() && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    func testChannelLoopHidesWhenTheHeroLeavesVision() {
        var launch = BattleLaunch(config: MatchFactory.botMatch(seed: 45))
        launch.spectatorOptions.director = false
        let w = makeWorld(launch)
        defer { w.world.teardown() }
        let c = w.controller
        c.markPresentationReady()
        var s = c.state
        let red = s.heroIndices(team: .red)[0]
        let id = s.units[red].id
        s.units[red].hero?.channel = Channel(kind: .recall, duration: 8)
        c.restore(s)
        frames(w, 10)
        XCTAssertTrue(w.world.vfx.hasLoop(id), "見えている詠唱にはループを付ける（途中から見えた詠唱にも）")
        // Blue の視点に切り替え、Red のヒーローが見えなくなったらループを止める（B6: 帰還の位置を漏らさない）
        c.spectatorVision = .blue
        var hidden = c.state
        hidden.units[red].visibleMask = Team.red.visionBit
        c.restore(hidden)
        frames(w, 10)
        XCTAssertFalse(w.world.vfx.hasLoop(id))
        // 再び見えたら付け直す
        hidden.units[red].visibleMask = Team.red.visionBit | Team.blue.visionBit
        c.restore(hidden)
        frames(w, 10)
        XCTAssertTrue(w.world.vfx.hasLoop(id))
        // 詠唱が終わったら止める
        hidden.units[red].hero?.channel = nil
        c.restore(hidden)
        frames(w, 2)
        XCTAssertFalse(w.world.vfx.hasLoop(id))
    }

    func testFocusRingMarksTheFollowedHeroOnly() {
        var launch = BattleLaunch(config: MatchFactory.botMatch(seed: 46))
        launch.spectatorOptions.director = false
        let w = makeWorld(launch)
        defer { w.world.teardown() }
        let c = w.controller
        let s = c.state
        let a = s.units[s.heroIndices[3]].id, b = s.units[s.heroIndices[7]].id
        c.cameraMode = .followUnit(a)
        frames(w, 2)
        XCTAssertEqual(w.world.units.hero(a)?.focusRing.isEnabled, true)
        XCTAssertEqual(w.world.units.hero(b)?.focusRing.isEnabled, false)
        c.cameraMode = .framing([b, a])
        frames(w, 2)
        XCTAssertEqual(w.world.units.hero(b)?.focusRing.isEnabled, true, "framing は先頭が主役")
        XCTAssertEqual(w.world.units.hero(a)?.focusRing.isEnabled, false)
        c.cameraMode = .free(Vec2(6000, 6000))
        frames(w, 2)
        XCTAssertEqual(w.world.units.hero(b)?.focusRing.isEnabled, false, "自由カメラでは出さない")
        // プレイヤー自身には出さない
        let p = makeWorld(BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 4)))
        defer { p.world.teardown() }
        let me = p.controller.humanHeroID!
        XCTAssertEqual(p.world.units.hero(me)?.focusRing.isEnabled, false)
    }

    func testCullBoundsGrowWithZoom() {
        let rig = CameraRig()
        let aspect: Float = 2.16
        rig.update(CameraDrive(target: SIMD2(60, -60), zoom: 1, free: true), dt: 0, mapMeters: M)
        let near = try! XCTUnwrap(BattleWorld.cullBounds(footprint: rig.groundFootprint(aspectRatio: aspect), margin: 3))
        var wide = CameraDrive(target: SIMD2(60, -60), zoom: 2.4, free: true)
        wide.zoomRange = CameraRig.spectatorZoomRange
        wide.transition = .cut
        rig.update(wide, dt: 0, mapMeters: M)
        let far = try! XCTUnwrap(BattleWorld.cullBounds(footprint: rig.groundFootprint(aspectRatio: aspect), margin: 3))
        XCTAssertGreaterThan(far.max.x - far.min.x, (near.max.x - near.min.x) * 2, "引いた分だけ演出を出す範囲も広がる（B28）")
        XCTAssertTrue(BattleWorld.isInside(SIMD3(60, 0, -60), bounds: near))
        // 以前の固定の範囲（注視点から 24 m）より外でも、画面に映っていれば演出を出す
        XCTAssertTrue(BattleWorld.isInside(SIMD3(60 + 30, 0, -60 - 12), bounds: far))
        XCTAssertFalse(BattleWorld.isInside(SIMD3(60 + 30, 0, -60 - 12), bounds: near))
        XCTAssertNil(BattleWorld.cullBounds(footprint: [], margin: 3))
    }
}
