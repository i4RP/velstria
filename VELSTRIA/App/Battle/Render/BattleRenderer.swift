import Combine
import os
import QuartzCore
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。
// ARView の所有者。SceneEvents.Update 毎に controller.frame(dt:) → 描画同期を行う（ゲームループの駆動役）。
// 地面テクスチャはメインスレッド外で生成し、準備完了まで sim を進めない（読み込み幕で覆う）。

@MainActor
final class BattleRenderer {
    let controller: BattleController
    private(set) var settings: RenderSettings

    private var view: BattleRenderView?
    private var updateSubscription: Cancellable?
    private var eventToken: UUID?
    private var loadTask: Task<Void, Never>?
    private var pendingEvents: [SimEvent] = []

    private let anchor = AnchorEntity(world: .zero)
    private let rig = CameraRig()
    private let sun = DirectionalLight()
    private let fill = DirectionalLight()
    private let post: PostProcessor
    private var postAttached = false
    private var thermalObserver: NSObjectProtocol?
    /// 端末が高温（.serious 以上）のあいだ後処理を止めて GPU 負荷を下げる（試合後半のフレーム落ち・発熱対策）。
    private var thermalThrottled = false
    private var world: BattleWorld?
    private var appliedFrameRate = 0
    private var wasPaused = false
    private var paceAccumulator: Double = 0
    /// フレーム時間・ヒッチの集計（出荷ビルドでも常時。Perf/FrameStats.swift）。
    let frameStats: FrameStats
    private var loadStart: Double = 0
    private var buildStart: Double = 0
    private var liveStarted = false
    private var loadInterval: OSSignpostIntervalState?
    #if DEBUG || SCREENSHOTS
    private var perfRun: PerfRun?
    private var warmupFramesUsed = 0
    #endif

    init(controller: BattleController, settings: RenderSettings) {
        var settings = settings
        #if DEBUG || SCREENSHOTS
        if let q = PerfRun.requestedQuality { settings.quality = .preset(q) }
        #endif
        self.controller = controller
        self.settings = settings
        post = PostProcessor(settings: PostProcessor.isAvailable ? .preset(settings.quality.level) : .preset(.low))
        frameStats = FrameStats(frameRate: settings.frameRate)
        pendingEvents.reserveCapacity(256)
    }

    // MARK: 構築

    func makeView() -> BattleRenderView {
        loadStart = CACurrentMediaTime()
        AssetLedger.beginLoading()
        loadInterval = FrameStats.signposter.beginInterval("battle.load")
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.renderOptions = [
            .disableMotionBlur, .disableDepthOfField, .disableCameraGrain, .disablePersonOcclusion,
            .disableFaceMesh, .disableGroundingShadows, .disableAREnvironmentLighting,
        ]
        arView.environment.background = .color(UIColor(red: 0.03, green: 0.05, blue: 0.10, alpha: 1))
        arView.isUserInteractionEnabled = false
        arView.isMultipleTouchEnabled = false

        anchor.name = "battle"
        rig.camera.name = "camera"
        anchor.addChild(rig.camera)
        setupLights()
        arView.scene.addAnchor(anchor)

        let v = BattleRenderView(arView: arView)
        view = v
        applyFrameRate()

        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.onUpdate(deltaTime: event.deltaTime)
        }
        eventToken = controller.subscribe { [weak self] events in
            self?.pendingEvents.append(contentsOf: events)
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateThermalState() }
        }
        updateThermalState()
        startLoading()
        return v
    }

    private func setupLights() {
        // 太陽: 左上奥から（影は右手前へ落ちる）
        sun.light.intensity = 3400
        sun.light.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        sun.look(at: .zero, from: [-0.55, 1.0, -0.45], relativeTo: nil)
        anchor.addChild(sun)
        // 補助光（青みの空色、影なし）
        fill.light.intensity = 900
        fill.light.color = UIColor(red: 0.62, green: 0.74, blue: 1.0, alpha: 1)
        fill.look(at: .zero, from: [0.6, 0.8, 0.7], relativeTo: nil)
        anchor.addChild(fill)
        applyShadows()
    }

    /// 影マップが覆う範囲（太陽に垂直な面での半径 m）。横長 iPhone（2.16:1）・ズーム 1.3 で画面に映る地面は
    /// 光の座標で半径 18.3 m（中心を shadowCenterOffset に置いた場合）+ 揺れの余白。
    static let shadowHalfExtent: Float = 20
    /// 画面に映る地面を光の座標で囲んだ箱の中心（注視点からのずれ、ズーム 1 あたり。world x・z）。
    /// 太陽の向き・カメラの俯角 56°・縦画角 48°・2.16:1 から求めた値（同じ光線上なら地面のどの点でも同じ箱になる）。
    static let shadowCenterOffset = SIMD2<Float>(-0.79, -6.11)
    /// 影マップの画素格子へ丸める刻み。2·範囲/256 は 256〜4096 px のどの解像度でも画素幅の整数倍になる。
    static let shadowSnapStep: Float = 2 * shadowHalfExtent / 256

    private func applyShadows() {
        if settings.quality.shadows {
            // .automatic はカメラの視錐台へ毎フレーム合わせ直すため、カメラが動くと影の縁が這うように揺らぐ。
            // 範囲固定の正射影にして太陽を注視点へ追従させ、位置を画素格子に丸める（followSun）
            sun.shadow = DirectionalLightComponent.Shadow(
                shadowProjection: .fixed(zNear: 1, zFar: 100, orthographicScale: BattleRenderer.shadowHalfExtent), depthBias: 1.6)
            followSun()
        } else {
            sun.shadow = nil
        }
    }

    /// 太陽（影の投影の中心）を画面に映る地面の中心へ動かす。向きは固定で、光の座標の x・y を画素格子に丸める。
    private func followSun() {
        guard settings.quality.shadows else { return }
        let f = rig.focus.value
        let zoom = Float(min(max(controller.cameraZoom, 0.7), 1.4))
        let o = BattleRenderer.shadowCenterOffset * zoom
        let c = SIMD3<Float>(f.x + o.x, 0, f.y + o.y)
        sun.position = BattleRenderer.snappedSunPosition(center: c, orientation: sun.orientation)
    }

    /// 光の右・上の軸で丸めた太陽の位置（中心から光の逆向きに 50 m 下がった点）。
    static func snappedSunPosition(center c: SIMD3<Float>, orientation q: simd_quatf) -> SIMD3<Float> {
        let right = q.act([1, 0, 0]), up = q.act([0, 1, 0]), forward = q.act([0, 0, -1])
        let step = shadowSnapStep
        let a = (simd_dot(c, right) / step).rounded() * step
        let b = (simd_dot(c, up) / step).rounded() * step
        return right * a + up * b + forward * (simd_dot(c, forward) - 50)
    }

    private func startLoading() {
        let map = controller.ctx.map
        let size = settings.quality.groundTextureSize
        let colorblind = settings.colorblind
        loadTask = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                GroundTextureGenerator.makeImage(map: map, size: size, colorblind: colorblind)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.buildWorld(groundImage: image)
        }
    }

    private func buildWorld(groundImage: CGImage?) {
        guard world == nil, let view else { return }
        buildStart = CACurrentMediaTime()
        let w = BattleWorld(controller: controller, settings: settings, groundImage: groundImage,
                            arView: view.arView, overlay: view.combatText)
        anchor.addChild(w.root)
        world = w
        // 最初のフレームで追従対象へカメラを合わせる
        w.updateCamera(rig: rig, dt: 0, snap: true)
        // 幕の裏で数フレーム描画し、マテリアル・粒子のパイプライン生成を済ませてから試合を始める
        for step in w.makeWarmupPlan() { step.run() }
        warmupFrames = BattleRenderer.warmupFrameCount
        // ウィンドウへ載った後に改めて指定する（載る前の指定は描画ループに反映されない）
        appliedFrameRate = 0
        applyFrameRate()
    }

    static let warmupFrameCount = 18
    private var warmupFrames = 0

    // MARK: ループ

    private func onUpdate(deltaTime rawDelta: Double) {
        guard let world, let view else { return }
        // 後処理はウィンドウへ載って描画が回り始めてから取り付ける（描画系の準備前に renderCallbacks を触ると落ちる）
        if !postAttached, view.arView.window != nil {
            postAttached = true
            if PostProcessor.isAvailable { post.attach(to: view.arView) }
        }
        // 30fps 設定: 描画ループが指定より速く回る環境（シミュレータ等）でも更新は 30Hz に間引く
        var deltaTime = rawDelta
        if settings.frameRate < 60 {
            paceAccumulator += rawDelta
            let interval = 1.0 / Double(settings.frameRate)
            guard paceAccumulator >= interval * 0.9 else { return }
            deltaTime = paceAccumulator
            paceAccumulator = 0
        }
        let dt = min(max(deltaTime, 0), 0.1)
        defer { publishCameraViewport(dt: dt) }
        if warmupFrames > 0 {
            warmupFrames -= 1
            #if DEBUG || SCREENSHOTS
            warmupFramesUsed += 1
            #endif
            world.sync(events: [], dt: Float(dt), rig: rig)
            world.updateCamera(rig: rig, dt: 0, snap: true)
            followSun()
            if warmupFrames == 0 {
                view.liftCurtain()
                // ここから試合開始（予備駆動は sim を進めずに待っている。HUD もここで表示する）
                controller.markPresentationReady()
                beginLive()
            }
            return
        }
        if controller.isPaused {
            // 一時停止中はシミュレーション・同期を止め、カメラ（自由視点）だけ動かす
            if !wasPaused { view.combatText.clear() }
            wasPaused = true
            pendingEvents.removeAll(keepingCapacity: true)
            world.updateCamera(rig: rig, dt: Float(dt), snap: false)
            followSun()
            return
        }
        wasPaused = false
        let t0 = CACurrentMediaTime()
        controller.frame(dt: deltaTime)
        let t1 = CACurrentMediaTime()
        world.sync(events: pendingEvents, dt: Float(dt), rig: rig)
        pendingEvents.removeAll(keepingCapacity: true)
        world.updateCamera(rig: rig, dt: Float(dt), snap: false)
        followSun()
        let t2 = CACurrentMediaTime()
        world.updateOverlay(dt: Float(dt))
        let t3 = CACurrentMediaTime()
        frameStats.record(frameDt: deltaTime, sim: t1 - t0, sync: t2 - t1, overlay: t3 - t2)
        #if DEBUG
        view.debugOverlay.record(frameDt: deltaTime, sim: t1 - t0, sync: t3 - t1, entities: world.liveEntityCount)
        #endif
        #if DEBUG || SCREENSHOTS
        if let perfRun, perfRun.tick(dt: deltaTime, entities: world.liveEntityCount) { finishPerfRun(perfRun) }
        #endif
    }

    // MARK: 計測

    /// 幕が上がった（ここから先の生成・ヒッチはプレイ中のものとして数える）。
    private func beginLive() {
        guard !liveStarted else { return }
        liveStarted = true
        AssetLedger.beginLive()
        frameStats.reset()
        frameStats.setFrameRate(settings.frameRate)
        frameStats.beginLive()
        if let loadInterval { FrameStats.signposter.endInterval("battle.load", loadInterval) }
        loadInterval = nil
        #if DEBUG || SCREENSHOTS
        if let seconds = PerfRun.requestedSeconds {
            perfRun = PerfRun(seconds: seconds)
            controller.speed = PerfRun.requestedSpeed
        }
        liveAt = CACurrentMediaTime()
        #endif
    }

    #if DEBUG || SCREENSHOTS
    private var liveAt: Double = 0

    private func finishPerfRun(_ run: PerfRun) {
        let loadMs = (liveAt - loadStart) * 1000
        let warmupMs = (liveAt - buildStart) * 1000
        let frames = warmupFramesUsed
        let settings = settings
        let speed = controller.speed
        run.finish { thermal, footprint, entities in
            PerfReport(device: PerfRun.deviceModel, os: UIDevice.current.systemVersion, build: PerfRun.buildName,
                       quality: "\(settings.quality.level)", frameRate: settings.frameRate, speed: speed,
                       requestedSeconds: run.seconds, loadMs: loadMs, warmupMs: warmupMs, warmupFrames: frames,
                       frame: frameStats.summary(), ledger: AssetLedger.snapshot(), thermalStates: thermal,
                       peakFootprintMB: footprint, peakEntities: entities, notes: [])
        }
    }
    #endif

    // MARK: 設定

    private func publishCameraViewport(dt: Double) {
        guard let size = view?.arView.bounds.size, size.width > 0, size.height > 0 else { return }
        controller.updateCameraViewport(rig.groundFootprint(aspectRatio: Float(size.width / size.height)), dt: dt)
    }

    func apply(settings new: RenderSettings) {
        #if DEBUG || SCREENSHOTS
        var new = new
        if let q = PerfRun.requestedQuality { new.quality = .preset(q) }
        #endif
        guard new != settings else { return }
        let old = settings
        settings = new
        if new.frameRate != old.frameRate { applyFrameRate() }
        if new.quality.shadows != old.quality.shadows { applyShadows() }
        if new.quality.level != old.quality.level { post.apply(postSettings) }
        world?.apply(settings: new)
    }

    private func updateThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        let throttled = state == .serious || state == .critical
        guard throttled != thermalThrottled else { return }
        thermalThrottled = throttled
        post.apply(postSettings)
    }

    /// 画質設定と端末の温度から決まる後処理の設定。
    private var postSettings: PostProcessSettings {
        thermalThrottled || !PostProcessor.isAvailable ? .preset(.low) : .preset(settings.quality.level)
    }

    private func applyFrameRate() {
        guard let arView = view?.arView, appliedFrameRate != settings.frameRate else { return }
        appliedFrameRate = settings.frameRate
        frameStats.setFrameRate(settings.frameRate)
        // ARView は公開の preferredFramesPerSecond を持たないため、RealityKit のフレームレート指定を使う
        arView.__enableAutomaticFrameRate = false
        arView.__preferredFrameRate = Float(settings.frameRate)
    }

    // MARK: 破棄

    func teardown() {
        controller.updateCameraViewport([], dt: 1)
        frameStats.endLive()
        AssetLedger.end()
        if let loadInterval { FrameStats.signposter.endInterval("battle.load", loadInterval) }
        loadInterval = nil
        loadTask?.cancel()
        loadTask = nil
        updateSubscription?.cancel()
        updateSubscription = nil
        if let token = eventToken {
            controller.unsubscribe(token)
            eventToken = nil
        }
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
            self.thermalObserver = nil
        }
        pendingEvents.removeAll()
        world?.teardown()
        world = nil
        anchor.removeFromParent()
        post.detach()
        if let arView = view?.arView {
            arView.scene.anchors.removeAll()
        }
        view?.combatText.clear()
        view = nil
    }
}
