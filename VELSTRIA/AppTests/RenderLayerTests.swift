import Metal
import RealityKit
import simd
import XCTest
@testable import VELSTRIA
import VelstriaCore

// battle-renderer: 地面付近の平面の高さ（Z-fighting 防止）・影の追従・画面の後処理・霧の補間・カメラの静止。

@MainActor
final class RenderLayerTests: XCTestCase {
    // MARK: 地面の段

    func testOpaqueGroundLayersAreSeparated() {
        let stack = GroundLayer.opaqueStack
        for k in 1..<stack.count {
            XCTAssertGreaterThanOrEqual(stack[k] - stack[k - 1], 0.004 - 1e-6,
                                        "重なる不透明な平面は 4 mm 以上離す（同じ高さだと Z-fighting でちらつく）")
        }
        XCTAssertGreaterThan(GroundLayer.paving, GroundLayer.detail, "細部タイルは石畳の下（目地にだけ見える）")
        XCTAssertLessThan(GroundLayer.outerGround, GroundLayer.ground)
    }

    func testOverlaysSitAboveStaticMarkingsAndBelowFog() {
        let staticTop = GroundLayer.staticTop
        XCTAssertGreaterThanOrEqual(staticTop, GroundLayer.markingLine + GroundLayer.bossStarThickness / 2)
        XCTAssertGreaterThanOrEqual(staticTop, GroundLayer.markingTop)
        for h in GroundLayer.overlays {
            XCTAssertGreaterThanOrEqual(h - staticTop, 0.004 - 1e-6, "足元表示は静的な印より上（\(h)）")
            XCTAssertLessThan(h, GroundLayer.fog, "足元表示は霧の板より下（\(h)）")
        }
        XCTAssertEqual(Set(GroundLayer.overlays).count, GroundLayer.overlays.count, "足元表示の高さは重複しない")
        XCTAssertGreaterThan(GroundLayer.water, GroundLayer.staticTop, "水面は川底の印より上")
    }

    func testFountainEmblemOverlapsPlazaSoLayersMustDiffer() {
        // 泉の紋章（半径 7.45 m）と Core の石畳（半径 4.65〜15.65 m）は重なる。重なる以上、段を分けていること
        let map = MapDefinition.standard
        for team in Team.players {
            let d = Float(map.fountain(team).distance(to: map.core(team)) / Balance.unitsPerMeter)
            XCTAssertLessThan(d - 7.45, 15.65, "紋章が石畳に掛かる")
        }
        XCTAssertNotEqual(GroundLayer.marking, GroundLayer.paving)
        XCTAssertNotEqual(GroundLayer.markingLine, GroundLayer.marking)
        XCTAssertNotEqual(GroundLayer.markingTop, GroundLayer.markingLine)
    }

    func testHeroFootMarkersSitAboveStaticMarkings() {
        // ヒーローの丸影・チームリング・矢印（HeroEffectMeshes）が石畳・紋章・Core の輪より上にあること
        for mesh in [HeroEffectMeshes.teamRingSolid, HeroEffectMeshes.teamRingDashed, HeroEffectMeshes.shadowOnly] {
            XCTAssertGreaterThanOrEqual(mesh.bounds.min.y - GroundLayer.staticTop, 0.004 - 1e-5,
                                        "足元表示が静的な地面の印に埋もれる・同一平面になる")
        }
    }

    func testOverlayOrderIsStrictlyIncreasing() {
        let orders: [Int32] = [OverlayOrder.groundDetail, OverlayOrder.water, OverlayOrder.groundDecal, OverlayOrder.fog,
                               OverlayOrder.zoneFill, OverlayOrder.zoneEdge, OverlayOrder.ring, OverlayOrder.selfRing,
                               OverlayOrder.unitMarker, OverlayOrder.castRing, OverlayOrder.rangeRing, OverlayOrder.vfxRing,
                               OverlayOrder.aim, OverlayOrder.barBack]
        for k in 1..<orders.count { XCTAssertLessThan(orders[k - 1], orders[k]) }
        XCTAssertLessThan(OverlayOrder.groundDecal, OverlayOrder.fog, "霧の下に描くべき地面デカールは霧より先")
    }

    // MARK: 影

    func testSunSnapLocksShadowTexelsToTheWorld() {
        let sun = DirectionalLight()
        sun.look(at: .zero, from: [-0.55, 1.0, -0.45], relativeTo: nil)
        let q = sun.orientation
        let right = q.act([1, 0, 0]), up = q.act([0, 1, 0])
        let step = BattleRenderer.shadowSnapStep
        let c = SIMD3<Float>(31.37, 0, -42.11)
        let p = BattleRenderer.snappedSunPosition(center: c, orientation: q)
        // 光の右・上の座標は刻みの整数倍（影マップの画素格子に乗る）
        for axis in [right, up] {
            let v = simd_dot(p, axis) / step
            XCTAssertEqual(v, v.rounded(), accuracy: 1e-2)
        }
        // 刻みより十分小さいカメラの動きでは位置が変わらない（影の縁が這わない）
        let a = (simd_dot(c, right) / step).rounded() * step - simd_dot(c, right)
        let b = (simd_dot(c, up) / step).rounded() * step - simd_dot(c, up)
        let nudge = right * (a * 0.5) + up * (b * 0.5)
        let p2 = BattleRenderer.snappedSunPosition(center: c + nudge, orientation: q)
        XCTAssertLessThan(simd_distance(p, p2), 1e-3)
        // 範囲の 1/256 刻み = 256〜4096 px のどの影マップ解像度でも画素幅の整数倍
        XCTAssertEqual(step * 256, 2 * BattleRenderer.shadowHalfExtent, accuracy: 1e-4)
    }

    // MARK: 後処理

    func testPostProcessPresets() {
        XCTAssertFalse(PostProcessSettings.preset(.low).enabled, "低画質は後処理なし（余分な全画面パスを省く）")
        for q in [GraphicsQuality.medium, .high] {
            let s = PostProcessSettings.preset(q)
            XCTAssertTrue(s.enabled)
            XCTAssertGreaterThanOrEqual(s.bloomLevels, 2)
            XCTAssertGreaterThan(s.bloomIntensity, 0)
            XCTAssertGreaterThan(s.bloomKnee, 0, "硬い閾値は細い発光線の明滅を招く")
        }
    }

    func testPostProcessShadersCompile() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal 非対応の環境") }
        let lib = try device.makeLibrary(source: PostProcessor.shaderSource, options: nil)
        for name in ["velBloomPrefilter", "velBloomDownsample", "velBloomUpsample"] {
            let f = try XCTUnwrap(lib.makeFunction(name: name), name)
            XCTAssertNoThrow(try device.makeComputePipelineState(function: f), name)
        }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = lib.makeFunction(name: "velFullscreenVertex")
        d.fragmentFunction = lib.makeFunction(name: "velCompositeFragment")
        d.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        XCTAssertNoThrow(try device.makeRenderPipelineState(descriptor: d))
    }

    func testPostProcessLinearFormats() {
        XCTAssertTrue(PostProcessor.isLinear(.bgra8Unorm_srgb))
        XCTAssertTrue(PostProcessor.isLinear(.rgba16Float))
        XCTAssertFalse(PostProcessor.isLinear(.bgra8Unorm))
    }

    // MARK: 霧・カメラ

    func testFogBlendSettlesExactly() {
        var f = FogField(size: 16)
        let cols = 4, rows = 4
        f.computeTarget(cells: [UInt8](repeating: 0, count: cols * rows), cols: cols, rows: rows, bit: 1)
        f.computeTarget(cells: [UInt8](repeating: 1, count: cols * rows), cols: cols, rows: rows, bit: 1)
        var residual: Float = 1
        var frames = 0
        while residual > 0, frames < 600 {
            residual = f.blend(1 - exp(-8.0 / 60))
            frames += 1
        }
        XCTAssertEqual(residual, 0, "補間は有限時間で目標に一致し、転送が止まる")
        XCTAssertLessThan(frames, 120, "2 秒以内に収まる")
    }

    func testCameraSpringComesToExactRest() {
        var s = CriticallyDampedSpring(SIMD2(0, 0))
        let target = SIMD2<Float>(3, -2)
        for _ in 0..<240 { s.update(target: target, smoothTime: 0.11, dt: 1.0 / 60) }
        XCTAssertEqual(s.value, target, "止まった後に微小な動きが続かない（細い線や影の縁が揺らがない）")
        XCTAssertEqual(s.velocity, .zero)
        var z = CriticallyDampedScalar(value: 12.5)
        for _ in 0..<240 { z.update(target: 15, smoothTime: 0.25, dt: 1.0 / 60) }
        XCTAssertEqual(z.value, 15)
    }
}
