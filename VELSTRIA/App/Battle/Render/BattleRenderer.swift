import Combine
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
    private var world: BattleWorld?
    private var appliedFrameRate = 0
    private var wasPaused = false
    private var paceAccumulator: Double = 0

    init(controller: BattleController, settings: RenderSettings) {
        self.controller = controller
        self.settings = settings
        pendingEvents.reserveCapacity(256)
    }

    // MARK: 構築

    func makeView() -> BattleRenderView {
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

    private func applyShadows() {
        if settings.quality.shadows {
            sun.shadow = DirectionalLightComponent.Shadow(shadowProjection: .automatic(maximumDistance: 34), depthBias: 1.6)
        } else {
            sun.shadow = nil
        }
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
        let w = BattleWorld(controller: controller, settings: settings, groundImage: groundImage,
                            arView: view.arView, overlay: view.combatText)
        anchor.addChild(w.root)
        world = w
        // 最初のフレームで追従対象へカメラを合わせる
        w.updateCamera(rig: rig, dt: 0, snap: true)
        // 幕の裏で数フレーム描画し、マテリアル・粒子のパイプライン生成を済ませてから試合を始める
        w.prewarmEffects()
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
        if warmupFrames > 0 {
            warmupFrames -= 1
            world.sync(events: [], dt: Float(dt), rig: rig)
            world.updateCamera(rig: rig, dt: 0, snap: true)
            if warmupFrames == 0 { view.liftCurtain() }
            return
        }
        if controller.isPaused {
            // 一時停止中はシミュレーション・同期を止め、カメラ（自由視点）だけ動かす
            if !wasPaused { view.combatText.clear() }
            wasPaused = true
            pendingEvents.removeAll(keepingCapacity: true)
            world.updateCamera(rig: rig, dt: Float(dt), snap: false)
            return
        }
        wasPaused = false
        let t0 = CACurrentMediaTime()
        controller.frame(dt: deltaTime)
        let t1 = CACurrentMediaTime()
        world.sync(events: pendingEvents, dt: Float(dt), rig: rig)
        pendingEvents.removeAll(keepingCapacity: true)
        world.updateCamera(rig: rig, dt: Float(dt), snap: false)
        world.updateOverlay(dt: Float(dt))
        let t2 = CACurrentMediaTime()
        #if DEBUG
        view.debugOverlay.record(frameDt: deltaTime, sim: t1 - t0, sync: t2 - t1, entities: world.liveEntityCount)
        #else
        _ = t2
        #endif
    }

    // MARK: 設定

    func apply(settings new: RenderSettings) {
        guard new != settings else { return }
        let old = settings
        settings = new
        if new.frameRate != old.frameRate { applyFrameRate() }
        if new.quality.shadows != old.quality.shadows { applyShadows() }
        world?.apply(settings: new)
    }

    private func applyFrameRate() {
        guard let arView = view?.arView, appliedFrameRate != settings.frameRate else { return }
        appliedFrameRate = settings.frameRate
        // ARView は公開の preferredFramesPerSecond を持たないため、RealityKit のフレームレート指定を使う
        arView.__enableAutomaticFrameRate = false
        arView.__preferredFrameRate = Float(settings.frameRate)
    }

    // MARK: 破棄

    func teardown() {
        loadTask?.cancel()
        loadTask = nil
        updateSubscription?.cancel()
        updateSubscription = nil
        if let token = eventToken {
            controller.unsubscribe(token)
            eventToken = nil
        }
        pendingEvents.removeAll()
        world?.teardown()
        world = nil
        anchor.removeFromParent()
        if let arView = view?.arView {
            arView.scene.anchors.removeAll()
        }
        view?.combatText.clear()
        view = nil
    }
}
