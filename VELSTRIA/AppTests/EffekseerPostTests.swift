import Metal
import RealityKit
import XCTest
@testable import VELSTRIA

// Effekseer を RealityKit の後処理の中で描く経路（EffekseerPostPass・EfkRuntime の後処理用の描き手）。
// シミュレータは RealityKit の後処理を呼ばないので、3D 画面の代わりに黒い画と一様な深度で描き手・描画・深度の向きを確かめる。
// 実機の見た目（ブルーム・3D に隠れる・歪み）は docs/EFFEKSEER.md「実機で確かめること」。

@MainActor
final class EffekseerPostTests: XCTestCase {
    /// 逆 Z（近いほど深度が大きい = RealityKit）と通常の射影を見分ける。
    func testReversedDepthIsDetectedFromTheProjection() {
        let reversed = EffekseerPostPass.reversedPerspective(fovY: 0.6, aspect: 2, near: 0.1)
        XCTAssertTrue(EfkRuntime.isReversedDepth(projection: reversed))
        // 通常（近い = 0、遠い = 1。Metal の深度 0〜1）
        let n: Float = 0.1, f: Float = 200, s = 1 / tan(Float(0.3))
        let normal = simd_float4x4(columns: (SIMD4(s / 2, 0, 0, 0), SIMD4(0, s, 0, 0), SIMD4(0, 0, f / (n - f), -1),
                                             SIMD4(0, 0, n * f / (n - f), 0)))
        XCTAssertFalse(EfkRuntime.isReversedDepth(projection: normal))
    }

    /// 写すパス（3D 画面の色・深度 → 自前の色・深度）のシェーダーがブルーム・合成と同じライブラリでコンパイルでき、
    /// 実機に多い色の形式でパイプラインが作れる。
    func testSceneCopyPassCompilesForCommonFormats() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal 非対応の環境") }
        let lib = try device.makeLibrary(source: PostProcessor.librarySource, options: nil)
        XCTAssertNotNil(lib.makeFunction(name: "velSceneCopyFragment"))
        XCTAssertNotNil(lib.makeFunction(name: "velDepthResetVertex"))
        XCTAssertNotNil(lib.makeFunction(name: "velCompositeFragment"), "ブルーム・合成のシェーダーも同じライブラリにある")
        for format in [MTLPixelFormat.bgra8Unorm_srgb, .bgra8Unorm, .rgba16Float] {
            let rf = EffekseerPostPass.renderFormat(format)
            XCTAssertNotNil(EffekseerPostPass.makePipelines(rf.format, encodeSRGB: rf.encodeSRGB, library: lib, device: device),
                            "\(format.rawValue)")
            XCTAssertNotNil(EffekseerPostPass.makeTargets(device: device, format: format, width: 32, height: 32, memorylessDepth: false),
                            "\(format.rawValue)")
        }
        XCTAssertNotNil(lib.makeFunction(name: "velSceneCopySRGBFragment"))
    }

    /// 3D 画面が sRGB の時は sRGB でない見え方へ描く（Effekseer の Metal の描き手は sRGB の描画先で何も描かない。2026-10-18 の撮影の自己診断）。
    func testSRGBScenesAreDrawnThroughANonSRGBView() {
        XCTAssertEqual(EffekseerPostPass.renderFormat(.bgra8Unorm_srgb).format, .bgra8Unorm)
        XCTAssertTrue(EffekseerPostPass.renderFormat(.bgra8Unorm_srgb).encodeSRGB)
        XCTAssertEqual(EffekseerPostPass.renderFormat(.rgba8Unorm_srgb).format, .rgba8Unorm)
        XCTAssertEqual(EffekseerPostPass.renderFormat(.rgba16Float).format, .rgba16Float)
        XCTAssertFalse(EffekseerPostPass.renderFormat(.rgba16Float).encodeSRGB)
        XCTAssertFalse(EffekseerPostPass.renderFormat(.bgra8Unorm).encodeSRGB)
    }

    /// 安全装置の判断: 切り替えが有効・描き手ができた・確かめで十分に光った時だけ後処理で描く。それ以外は重ね描き。
    func testPostPathIsUsedOnlyWhenTheProbePasses() {
        let ok = EffekseerPostPass.probeMinLit
        XCTAssertTrue(EffekseerPostPass.usesPostPath(enabled: true, prepared: true, probeLit: ok))
        XCTAssertFalse(EffekseerPostPass.usesPostPath(enabled: true, prepared: true, probeLit: 0), "何も光らない = 重ね描き")
        XCTAssertFalse(EffekseerPostPass.usesPostPath(enabled: true, prepared: true, probeLit: ok - 1))
        XCTAssertFalse(EffekseerPostPass.usesPostPath(enabled: true, prepared: true, probeLit: -1), "確かめられない = 重ね描き")
        XCTAssertFalse(EffekseerPostPass.usesPostPath(enabled: true, prepared: true, probeLit: nil), "確かめる前 = 重ね描き")
        XCTAssertFalse(EffekseerPostPass.usesPostPath(enabled: true, prepared: false, probeLit: 4096))
        XCTAssertFalse(EffekseerPostPass.usesPostPath(enabled: false, prepared: true, probeLit: 4096), "切り替えを切れば常に重ね描き")
        XCTAssertTrue(EffekseerPostPass.isEnabled, "既定は有効（確かめで守る）")
    }

    /// 確かめ（probePost）が実際の描き手で光る（実機に多い描画先の形式・深度の向き）。確かめの効果が同梱されている。
    func testProbeLightsUpForCommonDrawFormats() throws {
        let rt = try XCTUnwrap(EfkRuntime(), "Metal が使えない環境では確認できない")
        let dir = try XCTUnwrap(Bundle.main.url(forResource: EffekseerOverlay.bundleFolder, withExtension: nil))
        let probe = EffekseerPostPass.probeEffect
        XCTAssertTrue(rt.loadEffectNamed(probe, path: dir.appendingPathComponent(probe + ".efk").path, magnification: 1))
        for (format, reversed) in [(MTLPixelFormat.bgra8Unorm, true), (.bgra8Unorm, false), (.rgba16Float, true)] {
            let deadline = CFAbsoluteTimeGetCurrent() + 8
            while !rt.isPrepared(postColorFormat: format, reversedDepth: reversed), CFAbsoluteTimeGetCurrent() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            let lit = rt.probePost(effectNamed: probe, colorFormat: format, reversedDepth: reversed)
            XCTAssertGreaterThanOrEqual(lit, EffekseerPostPass.probeMinLit, "\(format.rawValue) reversed=\(reversed)")
        }
        XCTAssertEqual(rt.probePost(effectNamed: "no_such_effect", colorFormat: .rgba16Float, reversedDepth: true), -1)
    }

    /// 後処理用の描き手で描ける。深度が遠い時は映り、全面が手前（逆 Z の 1）の時は隠れる。3D の上の層にすると手前があっても映る。
    func testPostPathDrawsEffectsAndIsHiddenBehindNearerDepth() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal 非対応の環境") }
        let names = ["H034_s2_impact", "H034_atk_hit", "H034_s1_impact", "H003_atk_hit"]
        let r = EffekseerPostPass.selfTest(effects: names)
        XCTAssertTrue(r.prepared, "後処理用の描き手が作れる: \(r.summary)")
        XCTAssertTrue(r.drew, r.summary)
        XCTAssertGreaterThan(r.litFar, 30, "遠い深度の前では効果が映る: \(r.summary)")
        XCTAssertEqual(r.litNear, 0, "手前に 3D の面があれば隠れる: \(r.summary)")
        XCTAssertGreaterThan(r.litNearOnTop, 30, "3D の上の層は深度を戻してから描く: \(r.summary)")
        XCTAssertGreaterThanOrEqual(r.probe, EffekseerPostPass.probeMinLit, "安全装置の確かめも通る: \(r.summary)")
    }

    /// 後処理で描く間は重ねのレイヤーを隠し、戻すと見せる。
    func testOverlayLayerIsHiddenWhileThePostProcessDraws() throws {
        let rt = try XCTUnwrap(EfkRuntime(), "Metal が使えない環境では確認できない")
        XCTAssertFalse(rt.drawsInPostProcess)
        XCTAssertFalse(rt.layer.isHidden)
        rt.drawsInPostProcess = true
        XCTAssertTrue(rt.layer.isHidden)
        rt.drawsInPostProcess = false
        XCTAssertFalse(rt.layer.isHidden)
    }

    /// 後処理が取り付く前（シミュレータ・低画質）は重ね描き。描ける状態を見たことが無ければ false。
    func testPostPassIsNotUsedUntilItHasBeenCapable() throws {
        let pass = EffekseerPostPass()
        XCTAssertFalse(pass.drawsEffekseer(now: 10))
        let rt = try XCTUnwrap(EfkRuntime(), "Metal が使えない環境では確認できない")
        pass.attach(rt)
        XCTAssertFalse(pass.drawsEffekseer(now: 10), "後処理が 1 度も呼ばれていなければ重ね描きのまま")
        let post = PostProcessor(settings: .preset(.low))
        post.attachEffekseer(rt)
        XCTAssertFalse(post.drawsEffekseer(now: 10), "後処理が無効（低画質）なら重ね描き")
    }
}
