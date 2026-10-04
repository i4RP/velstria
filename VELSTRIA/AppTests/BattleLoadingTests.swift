import Metal
import RealityKit
import UIKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

// battle-renderer（性能）: 読み込みの先行準備と試合のフレーム進行。
// - BattleController の追いつき上限（通常速度 4 step / 早送り 12 step）と、上限が sim の結果を変えないこと
// - 地面テクスチャの共有キャッシュ（同じ画像を 2 回作らない・メモリ警告で手放す）
// - 霧の目標計算を背景で行っても同期計算と同じ結果になること
// - 後処理パイプラインの共有キャッシュ・準備完了の判定、マテリアル Program の生成
// - 読み込み幕の進捗表示、ゲームモードの Info.plist キー

@MainActor
final class BattleLoadingTests: XCTestCase {
    // MARK: フレーム進行（追いつき上限）

    func testCatchUpIsCappedAtNormalSpeed() {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 5)))
        XCTAssertEqual(BattleController.maxSteps(speed: 1), 4)
        // 0.25 秒の遅れ（7.5 tick 分）でも 1 フレームで進めるのは 4 tick まで（残りは捨てて時間を伸ばす）
        c.frame(dt: 0.25)
        XCTAssertEqual(c.state.tick, 4)
        XCTAssertLessThanOrEqual(c.interpolationAlpha, 1)
        // 次の通常フレームで溜まった遅れを一気に取り返さない
        c.frame(dt: 1.0 / 60)
        XCTAssertLessThanOrEqual(c.state.tick, 6)
    }

    func testFastForwardKeepsTheLargerCap() {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 5)))
        c.speed = 4
        XCTAssertEqual(BattleController.maxSteps(speed: 4), BattleController.maxStepsPerFrame)
        c.frame(dt: 0.25)
        XCTAssertEqual(c.state.tick, BattleController.maxStepsPerFrame)
    }

    func testRegularFramesAreUnaffected() {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 5)))
        for _ in 0..<120 { c.frame(dt: 1.0 / 60) }
        XCTAssertGreaterThanOrEqual(c.state.tick, 59)
        XCTAssertLessThanOrEqual(c.state.tick, 60)
    }

    /// 同じ試合を滑らかなフレームと、ヒッチ混じりのフレーム（上限で遅れを捨てる）で進めても、同じ tick の状態は一致する。
    func testCatchUpCapDoesNotChangeSimResults() {
        let config = MatchFactory.botMatch(seed: 20261001)
        let smooth = BattleController(launch: BattleLaunch(config: config))
        let hitchy = BattleController(launch: BattleLaunch(config: config))
        let target = 750
        func advance(_ c: BattleController, pattern: [Double]) {
            var k = 0
            while c.state.tick < target {
                // 終わり際は 1 フレームで高々 1 tick になる小さな dt で合わせる
                let dt = target - c.state.tick > BattleController.maxCatchUpSteps ? pattern[k % pattern.count] : Balance.dt * 0.5
                c.frame(dt: dt)
                k += 1
            }
        }
        advance(smooth, pattern: [1.0 / 60])
        advance(hitchy, pattern: [1.0 / 60, 0.2, 1.0 / 60, 0.25, 0.05, 1.0 / 30, 0.12])
        XCTAssertEqual(smooth.state.tick, target)
        XCTAssertEqual(hitchy.state.tick, target)
        XCTAssertEqual(smooth.state.stateHash(), hitchy.state.stateHash(), "1 フレームの step 数は sim の結果を変えない")
    }

    // MARK: 地面テクスチャのキャッシュ

    func testGroundTextureCacheSharesGenerationAndEvicts() async {
        let map = MapDefinition.standard
        GroundTextureCache.evictAll()
        let before = GroundTextureCache.generatedCount
        GroundTextureCache.prefetch(map: map, size: 64, colorblind: true)
        XCTAssertTrue(GroundTextureCache.isGenerating(map: map, size: 64, colorblind: true), "ロード画面から先に作り始める")
        let a = await GroundTextureCache.image(map: map, size: 64, colorblind: true)
        let b = await GroundTextureCache.image(map: map, size: 64, colorblind: true)
        XCTAssertNotNil(a)
        XCTAssertTrue(a === b, "2 試合目は作り直さない")
        XCTAssertEqual(GroundTextureCache.generatedCount - before, 1)
        XCTAssertNotNil(GroundTextureCache.cached(map: map, size: 64, colorblind: true))
        // 別の設定（色覚）は別の画像。保持は直近 1 件
        _ = await GroundTextureCache.image(map: map, size: 64, colorblind: false)
        XCTAssertEqual(GroundTextureCache.generatedCount - before, 2)
        XCTAssertNil(GroundTextureCache.cached(map: map, size: 64, colorblind: true))
        // メモリ警告で手放す（通知そのものは送らない: 他のサービス（音楽の保持など）の状態まで変えてしまうため）
        GroundTextureCache.handleMemoryWarning()
        XCTAssertNil(GroundTextureCache.cached(map: map, size: 64, colorblind: false))
    }

    // MARK: 霧

    func testFogTargetComputedInBackgroundMatchesSynchronousResult() throws {
        let fog = try XCTUnwrap(FogOfWar(team: .blue, size: 64))
        let sim = Simulation(config: MatchFactory.botMatch(seed: 7))
        fog.update(state: sim.state, dt: 0.2)
        XCTAssertTrue(fog.isComputing, "目標の計算はメインスレッドの外")
        let deadline = Date().addingTimeInterval(5)
        while fog.isComputing && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertFalse(fog.isComputing)
        var expected = FogField(size: 64)
        expected.computeTarget(cells: sim.state.vision.cells, cols: sim.state.vision.cols, rows: sim.state.vision.rows,
                               bit: Team.blue.visionBit)
        XCTAssertEqual(fog.displayedField.target, expected.target, "背景計算でも見た目は同じ")
        XCTAssertEqual(fog.displayedField.current, expected.target, "最初の目標は補間せずに合わせる")
        // 次の更新で補間・転送が回る（落ちない）
        fog.update(state: sim.state, dt: 1.0 / 60)
    }

    func testFogSwapTargetRecyclesBuffers() {
        var f = FogField(size: 8)
        var t = [Float](repeating: 0.25, count: 64)
        f.swapTarget(&t)
        XCTAssertEqual(f.target.first, 0.25)
        XCTAssertEqual(f.current.first, 0.25, "初回は現在値も合わせる")
        XCTAssertEqual(t.count, 64, "古い目標が戻る（次の計算の作業領域）")
        var wrong = [Float](repeating: 0, count: 3)
        f.swapTarget(&wrong)
        XCTAssertEqual(f.target.first, 0.25, "大きさの違う配列は受け取らない")
    }

    // MARK: シェーダー

    func testPostProcessPipelinesAreSharedAcrossProcessors() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal 非対応の環境") }
        let done = expectation(description: "compiled")
        PostProcessShaderCache.request(device: device) { _ in done.fulfill() }
        wait(for: [done], timeout: 30)
        let p = try XCTUnwrap(PostProcessShaderCache.pipelines(for: device))
        XCTAssertNotNil(p.composite(.bgra8Unorm_srgb), "最も多い出力形式は先に作る")
        // 2 つ目以降の PostProcessor はコンパイルせずに受け取る
        let processor = PostProcessor(settings: .preset(.high))
        XCTAssertTrue(processor.hasPipelines)
        XCTAssertFalse(processor.isReady, "最初のフレームを通すまでは幕を上げない")
        XCTAssertTrue(PostProcessor(settings: .preset(.low)).isReady, "後処理なしは待たない")
    }

    /// 単独で実行すると RealityKit のエンジンが未初期化の状態から始まる（Program の init が背景でエンジンを作ろうとして
    /// 落ちないこと＝メインスレッドで先にエンジンを起こしていることの確認にもなる）。
    func testMaterialProgramsBuild() async {
        let done = expectation(description: "programs")
        Task { @MainActor in
            await MaterialPrograms.waitUntilReady()
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 30)
        XCTAssertTrue(MaterialPrograms.isReady)
        let unlit = try? XCTUnwrap(MaterialPrograms.unlitTransparent)
        XCTAssertEqual(unlit?.descriptor.blendMode, .alpha)
        XCTAssertEqual(unlit?.descriptor.applyPostProcessToneMap, false)
        XCTAssertNil(MaterialPrograms.pbrOpaque?.descriptor.blendMode)
    }

    // MARK: 読み込み幕・Info.plist

    func testCurtainProgressNeverGoesBackwards() {
        let view = BattleRenderView(arView: ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false))
        view.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        view.setLoading(progress: 0.4, label: "A")
        view.setLoading(progress: 0.2, label: "B")
        XCTAssertEqual(view.curtain.progress, 0.4, accuracy: 1e-9)
        XCTAssertEqual(view.curtain.text, "B")
        view.setLoading(progress: 1.7, label: "C")
        XCTAssertEqual(view.curtain.progress, 1)
        view.layoutIfNeeded()
    }

    func testRendererStartsAtTheUserSettingsWhenTheDeviceIsCool() {
        let controller = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 3)))
        let user = RenderSettings(quality: .preset(.high), frameRate: 60, showDamageNumbers: true, colorblind: false)
        let renderer = BattleRenderer(controller: controller, settings: user)
        let info = ProcessInfo.processInfo
        if info.thermalState == .nominal || info.thermalState == .fair, !info.isLowPowerModeEnabled {
            XCTAssertEqual(renderer.governed.settings, renderer.settings)
            XCTAssertEqual(renderer.governed.renderScale, 1)
        }
        XCTAssertLessThanOrEqual(renderer.governed.settings.frameRate, renderer.settings.frameRate)
        renderer.teardown()
    }

    func testGameModeInfoPlistKeys() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["GCSupportsGameMode"] as? Bool, true, "ゲームモード（iOS 18+）")
        XCTAssertEqual(info["LSApplicationCategoryType"] as? String, "public.app-category.action-games",
                       "ゲームモードはゲームとして分類されたアプリだけ")
    }
}
