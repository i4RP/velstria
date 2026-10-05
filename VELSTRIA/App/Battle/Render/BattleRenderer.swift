import Combine
import os
import QuartzCore
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。
// ARView の所有者。SceneEvents.Update 毎に controller.frame(dt:) → 描画同期を行う（ゲームループの駆動役）。
// 地面テクスチャはメインスレッド外で生成し（ロード画面から先行して始め、試合をまたいで使い回す）、準備完了まで sim を進めない。
// 世界の構築後は WarmupScheduler が準備の段を複数フレームに分けて実行し、描画が落ち着いた合図で読み込み幕を上げる。
// プレイ中は AdaptiveQuality（画質の自動調整）がフレーム時間・端末温度・低電力モードを見て、ユーザー設定を上限に画質を上下させる。

@MainActor
final class BattleRenderer {
    let controller: BattleController
    /// ユーザーの画質設定（画質の自動調整の上限）。
    private(set) var settings: RenderSettings
    /// 画質の自動調整の結果（実際に描画へ反映している値。settings を超えない）。
    private(set) var governed: AdaptiveQuality.Output
    private var governor: AdaptiveQuality

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
    private var powerObserver: NSObjectProtocol?
    private var world: BattleWorld?
    /// 幕の裏のウォームアップ（完了で nil）。
    private var scheduler: WarmupScheduler?
    private var warmupFrameIndex = 0
    /// SceneEvents.Update を受けた回数（後処理の取り付けを最初のフレームの後へ遅らせる）。
    private var updateCount = 0
    private var appliedFrameRate = 0
    private var wasPaused = false
    private var paceAccumulator: Double = 0
    /// 太陽の影を描いているか（ウォームアップでは両方の状態を描く）。
    private var sunShadowOn = false
    /// 端末本来の描画倍率（ウィンドウへ載った時に読む）と、適用中の倍率。
    private var nativeScale: CGFloat = 0
    private var appliedScale: Float = 1
    /// フレーム時間・ヒッチの集計（出荷ビルドでも常時。Perf/FrameStats.swift）。
    let frameStats: FrameStats
    private var loadStart: Double = 0
    private var buildStart: Double = 0
    private var liveStarted = false
    private var loadInterval: OSSignpostIntervalState?
    /// 読み込み・ウォームアップの段の所要と画質の自動調整の記録（PerfRun のレポートへ。上限付き）。
    private(set) var notes: [String] = []
    private static let maxNotes = 256
    #if DEBUG || SCREENSHOTS
    private var perfRun: PerfRun?
    #endif

    init(controller: BattleController, settings: RenderSettings) {
        let settings = BattleRenderer.effectiveUserSettings(settings)
        self.controller = controller
        self.settings = settings
        let info = ProcessInfo.processInfo
        var config = AdaptiveQuality.Config()
        #if DEBUG || SCREENSHOTS
        // 起動引数で自動起動した戦闘（tools/screenshots.sh）は、シミュレータの負荷で画質が揺れないようフレーム時間では動かさない
        // （-perfRun の計測では動かす）
        if DebugLaunch.args.contains("-battle") && PerfRun.requestedSeconds == nil { config.adaptsToFrameTime = false }
        #endif
        governor = AdaptiveQuality(user: settings, thermal: info.thermalState, lowPower: info.isLowPowerModeEnabled,
                                   config: config)
        governed = governor.output
        // 後処理のシェーダーはユーザー設定の段で作る（自動調整で一時的に切っていても、戻すときにコンパイルを待たない）
        // シミュレータでは後処理を使わない（renderCallbacks.postProcess が呼ばれず、コンパイルの CPU だけを食う）
        post = PostProcessor(settings: PostProcessor.isAvailable ? .preset(settings.quality.level) : .preset(.low))
        post.apply(BattleRenderer.availablePost(governed.post))
        frameStats = FrameStats(frameRate: governed.settings.frameRate)
        pendingEvents.reserveCapacity(256)
    }

    /// 計測の起動引数（-perfQuality）を反映したユーザー設定。ロード画面の先行準備も同じ値を使う。
    static func effectiveUserSettings(_ s: RenderSettings) -> RenderSettings {
        #if DEBUG || SCREENSHOTS
        var s = s
        if let q = PerfRun.requestedQuality { s.quality = .preset(q) }
        return s
        #else
        return s
        #endif
    }

    // MARK: 構築

    func makeView() -> BattleRenderView {
        loadStart = CACurrentMediaTime()
        AssetLedger.beginLoading()
        loadInterval = FrameStats.signposter.beginInterval("battle.load")
        // 地面テクスチャ・マテリアルの Program・後処理のパイプラインを並行して作り始める（ロード画面で始めていれば受け取るだけ）
        BattlePreload.begin(render: settings, map: controller.ctx.map)
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
        v.setLoading(progress: 0, label: L("地形を生成中", "Generating terrain"))
        applyFrameRate()

        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.onUpdate(deltaTime: event.deltaTime)
        }
        eventToken = controller.subscribe { [weak self] events in
            self?.pendingEvents.append(contentsOf: events)
        }
        // 端末温度・低電力モードは画質の自動調整へ（監視はここだけ）
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateThermalState() }
        }
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePowerState() }
        }
        updateThermalState()
        updatePowerState()
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
        setSunShadow(governed.settings.quality.shadows)
    }

    private func setSunShadow(_ on: Bool) {
        guard on != sunShadowOn else { return }
        sunShadowOn = on
        if on {
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
        guard sunShadowOn else { return }
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
        let quality = settings.quality
        // ステージ（docs/STAGE.md）は配置・配合マップを背景で作る（ロード画面の BattlePreload が先に始めている）。
        // 素材やシェーダーが使えず作れなかったときだけ従来の地面画像を使う
        let useStage = StageAssets.isBundled
        let state = useStage ? "stage" : GroundTextureCache.cached(map: map, size: size, colorblind: colorblind) != nil ? "cache hit"
            : GroundTextureCache.isGenerating(map: map, size: size, colorblind: colorblind) ? "prefetched" : "generated"
        let t0 = CACurrentMediaTime()
        loadTask = Task { [weak self] in
            var image: CGImage?
            if !useStage {
                image = await GroundTextureCache.image(map: map, size: size, colorblind: colorblind)
            } else if !(await StagePrep.ready(map: map, quality: quality)) {
                image = await GroundTextureCache.image(map: map, size: size, colorblind: colorblind)
            }
            guard let self, !Task.isCancelled else { return }
            self.note(String(format: "ground %@ (%d²), waited %.0f ms", state, size, (CACurrentMediaTime() - t0) * 1000))
            self.buildWorld(groundImage: image)
        }
    }

    private func buildWorld(groundImage: CGImage?) {
        guard world == nil, let view else { return }
        buildStart = CACurrentMediaTime()
        // プール（放出体・軌跡・環境パーティクル）はユーザーが選んだ画質の上限で作り、自動調整の値はその後で反映する。
        // 低電力モード・高温で始まった試合でも、画質が戻った時に作らずに軌跡・演出を出せるようにする
        let w = BattleWorld(controller: controller, settings: settings, groundImage: groundImage,
                            arView: view.arView, overlay: view.combatText)
        if governed.settings != settings { w.apply(settings: governed.settings) }
        anchor.addChild(w.root)
        world = w
        // 最初のフレームで追従対象へカメラを合わせる
        w.updateCamera(rig: rig, dt: 0, snap: true)
        note(String(format: "world build %.0f ms", (CACurrentMediaTime() - buildStart) * 1000))
        // 幕の裏の準備を複数フレームに分けて実行し、描画が落ち着いてから幕を上げる（固定フレーム数では上げない）。
        // 影はユーザー設定で有効なら自動調整が切り替えうるので、両方の状態を描いておく
        scheduler = WarmupScheduler(steps: w.makeWarmupPlan(), targetInterval: 1 / Double(max(1, governed.settings.frameRate)),
                                    warmShadowVariants: settings.quality.shadows, gates: warmupGates())
        warmupFrameIndex = 0
        view.setLoading(progress: 0.15, label: L("戦場を構築中", "Building battlefield"))
        // ウィンドウへ載った後に改めて指定する（載る前の指定は描画ループに反映されない）
        appliedFrameRate = 0
        applyFrameRate()
    }

    /// 幕を上げる前に揃っていてほしいもの。
    private func warmupGates() -> [WarmupScheduler.Gate] {
        var gates = [WarmupScheduler.Gate("materialPrograms") { MaterialPrograms.isReadyForWarmup }]
        #if !targetEnvironment(simulator)
        // シミュレータでは renderCallbacks.postProcess が呼ばれないため待たない
        let post = post
        gates.append(WarmupScheduler.Gate("postProcess") { post.isReady })
        #endif
        return gates
    }

    // MARK: ループ

    /// いま描画ループに指定するフレームレート（一時停止中は 30 に落として発熱・電池を抑える）。
    private var currentFrameRate: Int {
        let fps = governed.settings.frameRate
        return wasPaused ? min(30, fps) : fps
    }

    private func onUpdate(deltaTime rawDelta: Double) {
        guard let view else { return }
        updateCount += 1
        // 後処理はウィンドウへ載って描画が回り始めてから（最初のフレームを描いた後に）取り付ける
        // （描画系の準備前に renderCallbacks を触ると落ちる）
        if !postAttached, updateCount >= 2, view.arView.window != nil {
            postAttached = true
            if PostProcessor.isAvailable { post.attach(to: view.arView) }
            nativeScale = view.arView.contentScaleFactor
            applyRenderScale()
        }
        guard let world else {
            // 地面テクスチャの生成待ち（所要は端末・画質で 0.2〜1 秒程度）。時間で 0 → 15% へ近づける
            let t = CACurrentMediaTime() - loadStart
            view.setLoading(progress: 0.15 * (1 - exp(-t / 0.6)), label: L("地形を生成中", "Generating terrain"))
            return
        }
        // 30fps 設定: 描画ループが指定より速く回る環境（シミュレータ等）でも更新は 30Hz に間引く
        var deltaTime = rawDelta
        let fps = currentFrameRate
        if fps < 60 {
            paceAccumulator += rawDelta
            let interval = 1.0 / Double(fps)
            guard paceAccumulator >= interval * 0.9 else { return }
            deltaTime = paceAccumulator
            paceAccumulator = 0
        }
        let dt = min(max(deltaTime, 0), 0.1)
        defer { publishCameraViewport(dt: dt) }
        if let scheduler {
            warmupFrame(world: world, view: view, scheduler: scheduler, frameDt: deltaTime, dt: dt)
            return
        }
        if controller.isPaused {
            // 一時停止中はシミュレーション・同期を止め、カメラ（自由視点）だけ動かす
            if !wasPaused {
                view.combatText.clear()
                wasPaused = true
                applyFrameRate()
            }
            pendingEvents.removeAll(keepingCapacity: true)
            world.updateCamera(rig: rig, dt: Float(dt), snap: false)
            followSun()
            return
        }
        if wasPaused {
            wasPaused = false
            applyFrameRate()
            // 一時停止の前後のフレームは自動調整の判定に使わない
            governor.resetWindow()
        }
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
        if let change = governor.record(frameDt: deltaTime, work: t3 - t0) { applyGovernor(change) }
        #if DEBUG
        view.debugOverlay.record(frameDt: deltaTime, sim: t1 - t0, sync: t3 - t1, entities: world.liveEntityCount)
        view.debugOverlay.detail = "Q \(governor.step)"
        #endif
        #if DEBUG || SCREENSHOTS
        if let perfRun, perfRun.tick(dt: deltaTime, entities: world.liveEntityCount) { finishPerfRun(perfRun) }
        #endif
    }

    /// 幕の裏の 1 フレーム。描画同期（初回はヒーロー・構造物の生成）→ 準備の段 → 影の両状態 → 落ち着き待ち。
    private func warmupFrame(world: BattleWorld, view: BattleRenderView, scheduler: WarmupScheduler, frameDt: Double,
                             dt: Double) {
        warmupFrameIndex += 1
        let t0 = CACurrentMediaTime()
        world.sync(events: [], dt: Float(dt), rig: rig)
        world.updateCamera(rig: rig, dt: 0, snap: true)
        followSun()
        // 最初のフレームは同期そのもの（ヒーロー・構造物の初回生成）が重いので、準備の段は次のフレームから
        guard warmupFrameIndex > 1 else {
            let now = CACurrentMediaTime()
            note(String(format: "first warm-up frame: initial sync %.0f ms (+%.0f ms after world build start)",
                        (now - t0) * 1000, (now - buildStart) * 1000))
            return
        }
        if warmupFrameIndex == 2 {
            note(String(format: "warm-up scheduler starts +%.0f ms after world build start", (t0 - buildStart) * 1000))
        }
        #if DEBUG || SCREENSHOTS
        if warmupFrameIndex <= 24 {
            note(String(format: "warm-up frame %d start +%.0f ms (dt %.1f ms)", warmupFrameIndex, (t0 - buildStart) * 1000,
                        frameDt * 1000))
        }
        #endif
        let d = scheduler.frame(dt: frameDt)
        setSunShadow(governed.settings.quality.shadows != d.invertShadows)
        let label: String
        switch scheduler.phase {
        case .steps: label = L("戦場を構築中", "Building battlefield")
        case .shadowVariants, .settle: label = L("描画を最適化中", "Optimizing rendering")
        case .done: label = L("準備完了", "Ready")
        }
        view.setLoading(progress: 0.15 + 0.85 * scheduler.displayProgress(), label: label)
        if d.finished { completeWarmup(world: world, view: view, scheduler: scheduler) }
    }

    private func completeWarmup(world: BattleWorld, view: BattleRenderView, scheduler: WarmupScheduler) {
        self.scheduler = nil
        for n in scheduler.notes { note(n) }
        if let ms = MaterialPrograms.buildMs { note(String(format: "material programs built in %.0f ms", ms)) }
        if let ms = PostProcessShaderCache.compileMs { note(String(format: "post-process pipelines compiled in %.0f ms", ms)) }
        world.finishWarmup()
        setSunShadow(governed.settings.quality.shadows)
        // 影の両状態を描き終えたので、自動調整が影を切り替えてよい
        if let change = governor.setShadowSwitchable(scheduler.shadowVariantsWarmed) { applyGovernor(change) }
        view.setLoading(progress: 1, label: L("準備完了", "Ready"))
        view.liftCurtain()
        // ここから試合開始（予備駆動は sim を進めずに待っている。HUD もここで表示する）
        controller.markPresentationReady()
        beginLive()
    }

    // MARK: 計測

    /// 幕が上がった（ここから先の生成・ヒッチはプレイ中のものとして数える）。
    private func beginLive() {
        guard !liveStarted else { return }
        liveStarted = true
        AssetLedger.beginLive()
        frameStats.reset()
        frameStats.setFrameRate(governed.settings.frameRate)
        frameStats.beginLive()
        governor.resetWindow()
        note("quality at live: \(governor.step) (thermal \(AdaptiveQuality.thermalName(governor.thermal)), low power \(governor.lowPower))")
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
        let frames = warmupFrameIndex
        let settings = governed.settings
        let speed = controller.speed
        note(String(format: "quality at end: %@ (frame p95 %.1f ms, work p95 %.2f ms over the last window)",
                    governor.step.description, governor.lastFrameP95Ms, governor.lastWorkP95Ms))
        let notes = notes
        run.finish { thermal, footprint, entities in
            PerfReport(device: PerfRun.deviceModel, os: UIDevice.current.systemVersion, build: PerfRun.buildName,
                       quality: "\(settings.quality.level)", frameRate: settings.frameRate, speed: speed,
                       requestedSeconds: run.seconds, loadMs: loadMs, warmupMs: warmupMs, warmupFrames: frames,
                       frame: frameStats.summary(), ledger: AssetLedger.snapshot(), thermalStates: thermal,
                       peakFootprintMB: footprint, peakEntities: entities, notes: notes)
        }
    }
    #endif

    /// 計測ログに 1 行残す（上限付き）。
    private func note(_ text: String) {
        guard notes.count < BattleRenderer.maxNotes else { return }
        notes.append(text)
    }

    // MARK: 設定

    private func publishCameraViewport(dt: Double) {
        guard let size = view?.arView.bounds.size, size.width > 0, size.height > 0 else { return }
        controller.updateCameraViewport(rig.groundFootprint(aspectRatio: Float(size.width / size.height)), dt: dt)
    }

    func apply(settings new: RenderSettings) {
        let new = BattleRenderer.effectiveUserSettings(new)
        guard new != settings else { return }
        settings = new
        if let change = governor.setUser(new) {
            applyGovernor(change)
        } else if governor.output != governed {
            applyGoverned(governor.output)
        }
    }

    private func updateThermalState() {
        if let change = governor.setThermal(ProcessInfo.processInfo.thermalState) { applyGovernor(change) }
    }

    private func updatePowerState() {
        if let change = governor.setLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled) { applyGovernor(change) }
    }

    /// 画質の自動調整の決定を反映し、signpost と計測ログに残す。
    private func applyGovernor(_ change: AdaptiveQuality.Change) {
        applyGoverned(change.output)
        let text = change.summary
        FrameStats.signposter.emitEvent("quality", "\(text, privacy: .public)")
        note("quality " + text)
    }

    private func applyGoverned(_ new: AdaptiveQuality.Output) {
        let old = governed
        governed = new
        if new.settings.frameRate != old.settings.frameRate { applyFrameRate() }
        // ウォームアップ中の影は WarmupScheduler の指示で毎フレーム決める
        if new.settings.quality.shadows != old.settings.quality.shadows, scheduler == nil { applyShadows() }
        if new.post != old.post { post.apply(BattleRenderer.availablePost(new.post)) }
        if new.renderScale != old.renderScale { applyRenderScale() }
        if new.settings != old.settings { world?.apply(settings: new.settings) }
    }

    /// 後処理が使えない環境（シミュレータ）では常に low（後処理なし）。
    private static func availablePost(_ p: PostProcessSettings) -> PostProcessSettings {
        PostProcessor.isAvailable ? p : .preset(.low)
    }

    private func applyFrameRate() {
        guard let arView = view?.arView else { return }
        let fps = currentFrameRate
        frameStats.setFrameRate(governed.settings.frameRate)
        guard appliedFrameRate != fps else { return }
        appliedFrameRate = fps
        // ARView は公開の preferredFramesPerSecond を持たないため、RealityKit のフレームレート指定を使う
        arView.__enableAutomaticFrameRate = false
        arView.__preferredFrameRate = Float(fps)
    }

    /// 描画解像度（Apple の推奨どおり contentScaleFactor を下げる）。ウィンドウへ載る前は端末の倍率が分からないので待つ。
    private func applyRenderScale() {
        guard let arView = view?.arView, nativeScale > 0, appliedScale != governed.renderScale else { return }
        appliedScale = governed.renderScale
        arView.contentScaleFactor = nativeScale * CGFloat(governed.renderScale)
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
        StagePrep.discard()
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
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
            self.powerObserver = nil
        }
        scheduler = nil
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
