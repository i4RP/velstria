import Foundation
import QuartzCore
import Metal
import RealityKit

// 担当: battle-renderer。画面の後処理（ARView.renderCallbacks.postProcess）。
// 発光部の滲み（ブルーム: 輝度抽出 → 1/2〜1/32 へ 13 タップ縮小 → テントフィルタで拡大加算）と
// 色調整（コントラスト・彩度・暗部の青み/明部の暖色・ディザ）を合成する。
// シェーダーは実行時にソースからコンパイルする（ビルド環境に Metal ツールチェーンを要求しない）。
// 準備が済むまで・失敗時は元画像をそのまま写す（画面が黒くならないこと最優先）。
// 縮小の 13 タップ + 初段の Karis 平均（輝度重み）で、細い発光線が動いたときの明滅（ブルームのちらつき）を抑える。

struct PostProcessSettings: Equatable {
    var enabled: Bool
    /// ブルームの強さ（0 で無効）。
    var bloomIntensity: Float
    /// 輝度抽出の閾値（最大チャンネル、0〜1）と柔らかさ。
    var bloomThreshold: Float
    var bloomKnee: Float
    /// 縮小段数（1/2 から 1/2^levels まで）。
    var bloomLevels: Int
    var contrast: Float
    var saturation: Float

    static func preset(_ q: GraphicsQuality) -> PostProcessSettings {
        switch q {
        case .low:
            return PostProcessSettings(enabled: false, bloomIntensity: 0, bloomThreshold: 0.8, bloomKnee: 0.25,
                                       bloomLevels: 0, contrast: 1, saturation: 1)
        case .medium:
            return PostProcessSettings(enabled: true, bloomIntensity: 1.3, bloomThreshold: 0.6, bloomKnee: 0.3,
                                       bloomLevels: 4, contrast: 1.05, saturation: 1.07)
        case .high:
            return PostProcessSettings(enabled: true, bloomIntensity: 1.5, bloomThreshold: 0.6, bloomKnee: 0.3,
                                       bloomLevels: 5, contrast: 1.06, saturation: 1.08)
        }
    }
}

/// 後処理のシェーダー・パイプライン（GPU ごとに 1 回だけ作り、試合をまたいで使い回す）。
final class PostProcessPipelines: @unchecked Sendable {
    let device: MTLDevice
    let library: MTLLibrary
    let prefilter: MTLComputePipelineState
    let downsample: MTLComputePipelineState
    let upsample: MTLComputePipelineState
    private let lock = NSLock()
    private var composites: [UInt: MTLRenderPipelineState] = [:]

    init(device: MTLDevice, library: MTLLibrary, prefilter: MTLComputePipelineState, downsample: MTLComputePipelineState,
         upsample: MTLComputePipelineState) {
        self.device = device
        self.library = library
        self.prefilter = prefilter
        self.downsample = downsample
        self.upsample = upsample
    }

    /// 出力形式 format の合成パイプライン（未作成なら nil。どのスレッドからでもよい）。
    func composite(_ format: MTLPixelFormat) -> MTLRenderPipelineState? {
        lock.lock()
        defer { lock.unlock() }
        return composites[format.rawValue]
    }

    func store(_ pipeline: MTLRenderPipelineState, for format: MTLPixelFormat) {
        lock.lock()
        composites[format.rawValue] = pipeline
        lock.unlock()
    }
}

/// 後処理パイプラインの作成窓口（端末で 1 つ）。ロード画面（BattlePreload）から先行して作り始め、
/// BattleRenderer の PostProcessor は出来上がったものを受け取る（2 試合目以降はコンパイルしない）。
/// コンパイルとパイプライン生成は自前の背景キューで同期 API を使って行う。Metal の完了ハンドラ
/// （Metal のコンパイラキュー上）から同期 API を呼ぶと同じキューを待ってトラップするため、完了ハンドラ版は使わない。
enum PostProcessShaderCache {
    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "velstria.postprocess.compile", qos: .userInitiated)
    nonisolated(unsafe) private static var ready: PostProcessPipelines?
    nonisolated(unsafe) private static var compiling = false
    nonisolated(unsafe) private static var waiters: [@Sendable (PostProcessPipelines?) -> Void] = []
    /// コンパイルにかかった時間（ms。計測ログ用）。
    nonisolated(unsafe) private(set) static var compileMs: Double?

    /// 既定の GPU 向けに作り始める（済み・作成中なら何もしない。後処理を使わないシミュレータでは作らない）。
    static func prewarm() {
        guard PostProcessor.isAvailable, let device = MTLCreateSystemDefaultDevice() else { return }
        request(device: device) { _ in }
    }

    /// 作成済みなら返す（lock を取るだけなので描画スレッドから呼んでよい）。
    static func pipelines(for device: MTLDevice) -> PostProcessPipelines? {
        lock.lock()
        defer { lock.unlock() }
        guard let r = ready, r.device.registryID == device.registryID else { return nil }
        return r
    }

    static var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ready != nil
    }

    /// 作成を依頼する。completion（失敗時は nil）は常に背景キューから非同期に呼ぶ（呼び出し側の lock の中では呼ばない）。
    static func request(device: MTLDevice, completion: @escaping @Sendable (PostProcessPipelines?) -> Void) {
        lock.lock()
        if let r = ready, r.device.registryID == device.registryID {
            lock.unlock()
            queue.async { completion(r) }
            return
        }
        waiters.append(completion)
        guard !compiling else {
            lock.unlock()
            return
        }
        compiling = true
        lock.unlock()
        queue.async {
            let t0 = CFAbsoluteTimeGetCurrent()
            let built = build(device: device)
            lock.lock()
            if let built {
                ready = built
                compileMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            }
            compiling = false
            let callbacks = waiters
            waiters.removeAll()
            lock.unlock()
            for c in callbacks { c(built) }
        }
    }

    /// 背景キューで同期にコンパイルする。実機の描画先として最も多い形式の合成パイプラインも先に作る（最初のフレームを待たせない）。
    private static func build(device: MTLDevice) -> PostProcessPipelines? {
        let options = MTLCompileOptions()
        options.mathMode = .fast
        let lib: MTLLibrary
        do {
            lib = try device.makeLibrary(source: PostProcessor.shaderSource, options: options)
        } catch {
            #if DEBUG
            NSLog("%@", "[PostProcess] shader compile failed: \(error)")
            #endif
            return nil
        }
        func compute(_ name: String) -> MTLComputePipelineState? {
            lib.makeFunction(name: name).flatMap { try? device.makeComputePipelineState(function: $0) }
        }
        guard let pre = compute("velBloomPrefilter"), let dn = compute("velBloomDownsample"),
              let up = compute("velBloomUpsample") else { return nil }
        let p = PostProcessPipelines(device: device, library: lib, prefilter: pre, downsample: dn, upsample: up)
        if let srgb = PostProcessor.makeComposite(for: .bgra8Unorm_srgb, device: device, library: lib) {
            p.store(srgb, for: .bgra8Unorm_srgb)
        }
        return p
    }
}

/// renderCallbacks から（RealityKit の描画スレッドで）呼ばれる。設定・パイプラインは lock で守る。
final class PostProcessor: @unchecked Sendable {
    /// iOS シミュレータの RealityKit は postProcess を呼ばない。シェーダーのコンパイル（読み込み中の CPU）や
    /// コールバックの取り付けは無駄なので、シミュレータでは後処理を使わない。
    #if targetEnvironment(simulator)
    static let isAvailable = false
    #else
    static let isAvailable = true
    #endif

    private let lock = NSLock()
    private var settings: PostProcessSettings
    private var device: MTLDevice?
    private var prefilter: MTLComputePipelineState?
    private var downsample: MTLComputePipelineState?
    private var upsample: MTLComputePipelineState?
    private var library: MTLLibrary?
    /// 端末共通のコンパイル結果（合成パイプラインは出力形式ごとにここへ溜まり、試合をまたいで使い回す）。
    private var pipelines: PostProcessPipelines?
    /// 合成パイプラインを作成中の出力形式（描画スレッドを止めないよう非同期に作る）。
    private var pendingFormats: Set<UInt> = []
    private var down: [MTLTexture] = []
    private var up: [MTLTexture] = []
    /// 縮小用テクスチャを確保した画面サイズ。段数は確保済み以下なら作り直さない（自動調整で段数を減らしても確保し直さない）。
    private var chainSize = SIMD2<Int>(0, 0)
    private var compiling = false
    /// 作り直し（resetLocked）の世代。古いコンパイル結果を後から書き込まない。
    private var generation = 0
    /// コンパイル失敗の回数。上限に達したら後処理を外す（何もしない全画面コピーを毎フレーム払わない）。
    private var failures = 0
    private var gaveUp = false
    /// ブルーム・合成まで通したフレームがある（パイプライン・縮小用テクスチャが揃い、以後の描画でシェーダーを作らない）。
    private var fullPassDone = false
    static let maxFailures = 3

    init(settings: PostProcessSettings) {
        self.settings = settings
        // 読み込み中（地面テクスチャ生成の裏）にコンパイルを済ませ、幕が上がった最初のフレームから効かせる。
        // ロード画面で PostProcessShaderCache.prewarm 済みなら出来上がったものを受け取るだけ。
        // iOS の GPU は 1 つなので、描画系の device と同じ。違えば process で作り直す
        if settings.enabled, let device = MTLCreateSystemDefaultDevice() {
            lock.lock()
            prepareLocked(device: device)
            lock.unlock()
        }
    }

    /// 幕を上げてよいか（後処理が無効・断念済み、またはブルーム・合成まで通したフレームがある）。
    /// どのスレッドから呼んでもよい。
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !settings.enabled || gaveUp || fullPassDone
    }

    /// パイプラインが揃っている（最初のフレームを待たずに分かる部分。テスト・計測用）。
    var hasPipelines: Bool {
        lock.lock()
        defer { lock.unlock() }
        return library != nil && prefilter != nil && downsample != nil && upsample != nil
    }

    /// 取り付け済みの ARView。renderCallbacks は描画が始まる前（ウィンドウに載る前）に触ると落ちるため、
    /// attach より前の設定変更・attach していない破棄では触らない。
    @MainActor private weak var attachedView: ARView?

    /// ARView へ取り付ける（メインスレッド・描画開始後）。無効設定では後処理を外して余分なパスを省く。
    @MainActor
    func attach(to arView: ARView) {
        attachedView = arView
        arView.renderCallbacks.prepareWithDevice = PostProcessor.makePrepareCallback(self)
        updateCallback(arView)
    }

    /// 奥義の画面の脈（一瞬の閃光と放射状のぼかし）。BattleFeel が自分が関わる奥義で立てる。
    /// process が開始時刻からの減衰を毎フレーム求める（main の更新の間隔に左右されない）。低画質は後処理ごと無いので出ない。
    struct ScreenPulse: Equatable, Sendable {
        /// 閃光の色（知覚空間 0〜1）。
        var color: SIMD3<Float> = .one
        /// 閃光の強さ（0〜1。スクリーン合成の量）。
        var flash: Float = 0
        /// 放射状のぼかしの強さ（0〜1。1 で中心へ 12% 縮めた像まで重ねる）。
        var blur: Float = 0
        /// ぼかしの中心（画面の UV。左上 0,0）。
        var center: SIMD2<Float> = [0.5, 0.5]
        /// 開始時刻（CACurrentMediaTime）。
        var start: Double = -100

        static let flashSeconds: Double = 0.22
        static let blurSeconds: Double = 0.3

        /// 開始から t 秒の倍率（0〜1）。0.03 秒で立ち上がり、残りで弱まる（終わりほどゆっくり）。
        static func envelope(_ t: Double, length: Double) -> Float {
            guard t >= 0, t < length, length > 0 else { return 0 }
            let rise = 0.03
            if t < rise { return Float(t / rise) }
            let u = (t - rise) / max(0.001, length - rise)
            return Float((1 - u) * (1 - u))
        }

        /// 時刻 now の閃光・ぼかしの強さ。
        func amounts(at now: Double) -> (flash: Float, blur: Float) {
            let t = now - start
            return (flash * ScreenPulse.envelope(t, length: ScreenPulse.flashSeconds),
                    blur * ScreenPulse.envelope(t, length: ScreenPulse.blurSeconds))
        }
    }

    private var pulseState = ScreenPulse()

    /// 画面の歪み（衝撃波の屈折）。スキル演出の輪（FXMesh.refract）を BattleRenderer が画面へ投影して毎フレーム渡す。
    /// 中心・半径は画面の UV（左上 0,0。半径の x = 画面の幅に対する比、y = 高さに対する比で地面の楕円）、
    /// strength は画面の高さに対するずれの最大。
    /// 低画質・後処理の自動の切り下げ・シミュレータでは出ない（輪のメッシュはそのまま見える）。
    struct Ripple: Equatable, Sendable {
        var center: SIMD2<Float>
        var radius: SIMD2<Float>
        var strength: Float
    }

    /// 一度に歪める輪の最大（合成のシェーダーの配列の大きさ）。
    static let maxRipples = 4
    private var rippleState: [Ripple] = []

    /// 歪みの輪を置き換える（どのスレッドからでもよい。maxRipples を超える分は捨てる）。
    func ripples(_ list: [Ripple]) {
        lock.lock()
        defer { lock.unlock() }
        rippleState = Array(list.prefix(PostProcessor.maxRipples))
    }

    /// 脈を立てる（どのスレッドからでもよい）。今の脈の残りより強い時だけ置き換える（弱い脈で強い脈を消さない）。
    func pulse(_ p: ScreenPulse) {
        lock.lock()
        defer { lock.unlock() }
        let now = p.start
        let left = pulseState.amounts(at: now)
        if p.flash >= left.flash || p.blur >= left.blur { pulseState = p }
    }

    @MainActor
    func apply(_ new: PostProcessSettings) {
        lock.lock()
        settings = new
        lock.unlock()
        if let arView = attachedView { updateCallback(arView) }
    }

    /// 取り外す。ウィンドウから外れた後の ARView には触らない（renderCallbacks の設定で落ちうる）。
    /// 残ったコールバックは self を弱参照し、解放後は元画像を写すだけなので害はない。
    @MainActor
    func detach() {
        guard let arView = attachedView else { return }
        attachedView = nil
        guard arView.window != nil else { return }
        arView.renderCallbacks.postProcess = nil
        arView.renderCallbacks.prepareWithDevice = nil
    }

    @MainActor
    private func updateCallback(_ arView: ARView) {
        lock.lock()
        let enabled = settings.enabled && !gaveUp
        lock.unlock()
        arView.renderCallbacks.postProcess = enabled ? PostProcessor.makePostProcessCallback(self) : nil
    }

    /// コンパイルに失敗し続けたとき後処理を外す（メインスレッドへ回して呼ぶ）。
    @MainActor
    private func removeAfterFailure() {
        guard let arView = attachedView, arView.window != nil else { return }
        arView.renderCallbacks.postProcess = nil
    }

    // RealityKit は描画スレッドからコールバックを呼ぶ。@MainActor のメソッド内でクロージャを書くと
    // メインアクターに隔離されたクロージャと推論されるため（Swift 6 の動的検査で落ちる）、隔離のない場所で作る。
    private static func makePostProcessCallback(_ p: PostProcessor) -> (ARView.PostProcessContext) -> Void {
        { [weak p] ctx in
            if let p { p.process(ctx) } else { PostProcessor.copy(ctx) }
        }
    }

    private static func makePrepareCallback(_ p: PostProcessor) -> (MTLDevice) -> Void {
        { [weak p] device in p?.prepare(device: device) }
    }

    // MARK: 準備

    private func prepare(device: MTLDevice) {
        lock.lock()
        defer { lock.unlock() }
        prepareLocked(device: device)
    }

    /// パイプラインを受け取る（lock 保持中に呼ぶ）。作成済みならその場で、未作成なら PostProcessShaderCache に依頼して
    /// 背景キューで出来上がるのを待つ（lock は生成中に持たない。結果を書き込むときだけ取る）。
    private func prepareLocked(device: MTLDevice) {
        guard self.device == nil, !compiling, !gaveUp else { return }
        if let p = PostProcessShaderCache.pipelines(for: device) {
            adoptLocked(p)
            return
        }
        compiling = true
        let gen = generation
        PostProcessShaderCache.request(device: device) { [weak self] p in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard gen == self.generation else { return }
            self.compiling = false
            guard let p else {
                // 一時的な失敗（コンパイラの中断など）は次のフレームで作り直す。続けば諦めて外す
                self.noteFailureLocked()
                return
            }
            self.adoptLocked(p)
        }
    }

    private func adoptLocked(_ p: PostProcessPipelines) {
        pipelines = p
        device = p.device
        library = p.library
        prefilter = p.prefilter
        downsample = p.downsample
        upsample = p.upsample
    }

    /// 合成パイプライン（全画面三角形 → 出力形式 format）。背景キューから呼ぶ（同期でコンパイルする）。
    fileprivate static func makeComposite(for format: MTLPixelFormat, device: MTLDevice,
                                          library: MTLLibrary) -> MTLRenderPipelineState? {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "velFullscreenVertex")
        d.fragmentFunction = library.makeFunction(name: "velCompositeFragment")
        d.colorAttachments[0].pixelFormat = format
        guard d.vertexFunction != nil, d.fragmentFunction != nil else { return nil }
        return try? device.makeRenderPipelineState(descriptor: d)
    }

    private func noteFailureLocked() {
        failures += 1
        guard failures >= PostProcessor.maxFailures, !gaveUp else { return }
        gaveUp = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.removeAfterFailure() }
        }
    }

    /// 別の GPU 用に作ったものを捨てる（lock 保持中に呼ぶ）。
    private func resetLocked() {
        generation += 1
        device = nil
        library = nil
        prefilter = nil
        downsample = nil
        upsample = nil
        pipelines = nil
        pendingFormats.removeAll()
        down.removeAll()
        up.removeAll()
        chainSize = .zero
        compiling = false
        fullPassDone = false
    }

    /// 合成パイプラインを非同期に作り始める（lock 保持中に呼ぶ。完成までは元画像を写す）。
    private func requestCompositeLocked(for format: MTLPixelFormat, pipelines p: PostProcessPipelines) {
        let key = format.rawValue
        guard p.composite(format) == nil, !pendingFormats.contains(key) else { return }
        pendingFormats.insert(key)
        let gen = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pipeline = PostProcessor.makeComposite(for: format, device: p.device, library: p.library)
            if let pipeline { p.store(pipeline, for: format) }
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard gen == self.generation else { return }
            self.pendingFormats.remove(key)
            if pipeline == nil { self.noteFailureLocked() }
        }
    }

    private func ensureChain(device: MTLDevice, width: Int, height: Int, levels: Int) -> Bool {
        let size = SIMD2(width, height)
        if size == chainSize, down.count >= levels { return true }
        down.removeAll()
        up.removeAll()
        chainSize = .zero
        var w = width, h = height
        for _ in 0..<levels {
            w = max(1, w / 2)
            h = max(1, h / 2)
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]
            d.storageMode = .private
            guard let a = device.makeTexture(descriptor: d), let b = device.makeTexture(descriptor: d) else {
                down.removeAll()
                up.removeAll()
                return false
            }
            a.label = "velBloomDown"
            b.label = "velBloomUp"
            down.append(a)
            up.append(b)
        }
        chainSize = size
        return true
    }

    // MARK: 毎フレーム

    private func process(_ ctx: ARView.PostProcessContext) {
        lock.lock()
        defer { lock.unlock() }
        let s = settings
        // prepareWithDevice は描画系の初期化時にしか呼ばれないため、後から取り付けた場合はここで準備する
        if let d = device, d.registryID != ctx.device.registryID {
            resetLocked()
        }
        if library == nil { prepareLocked(device: ctx.device) }
        guard s.enabled, !gaveUp, let pipelines, let device else {
            PostProcessor.copy(ctx)
            return
        }
        let src = ctx.sourceColorTexture, dst = ctx.targetColorTexture
        guard let composite = pipelines.composite(dst.pixelFormat) else {
            requestCompositeLocked(for: dst.pixelFormat, pipelines: pipelines)
            PostProcessor.copy(ctx)
            return
        }
        let linear = PostProcessor.isLinear(src.pixelFormat)
        var bloomTexture: MTLTexture?
        let levels = max(0, min(6, s.bloomLevels))
        if s.bloomIntensity > 0, levels >= 2, let prefilter, let downsample, let upsample,
           ensureChain(device: device, width: src.width, height: src.height, levels: levels),
           let enc = ctx.commandBuffer.makeComputeCommandEncoder() {
            enc.label = "velBloom"
            var bp = BloomParams(threshold: s.bloomThreshold, knee: max(0.001, s.bloomKnee), scatter: 0.75,
                                 linearInput: linear ? 1 : 0)
            // 輝度抽出 + 1/2 縮小
            enc.setComputePipelineState(prefilter)
            enc.setTexture(src, index: 0)
            enc.setTexture(down[0], index: 1)
            enc.setBytes(&bp, length: MemoryLayout<BloomParams>.stride, index: 0)
            PostProcessor.dispatch(enc, prefilter, down[0])
            // 縮小
            enc.setComputePipelineState(downsample)
            for i in 1..<levels {
                enc.setTexture(down[i - 1], index: 0)
                enc.setTexture(down[i], index: 1)
                PostProcessor.dispatch(enc, downsample, down[i])
            }
            // 拡大合成（最下段は down をそのまま低解像度側に使う）
            enc.setComputePipelineState(upsample)
            for i in stride(from: levels - 2, through: 0, by: -1) {
                let low = i == levels - 2 ? down[levels - 1] : up[i + 1]
                enc.setTexture(low, index: 0)
                enc.setTexture(down[i], index: 1)
                enc.setTexture(up[i], index: 2)
                enc.setBytes(&bp, length: MemoryLayout<BloomParams>.stride, index: 0)
                PostProcessor.dispatch(enc, upsample, up[i])
            }
            enc.endEncoding()
            bloomTexture = up[0]
        }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = dst
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let renc = ctx.commandBuffer.makeRenderCommandEncoder(descriptor: rp) else {
            PostProcessor.copy(ctx)
            return
        }
        renc.label = "velComposite"
        var cp = CompositeParams(bloomIntensity: bloomTexture == nil ? 0 : s.bloomIntensity, contrast: s.contrast,
                                 saturation: s.saturation, linearInput: linear ? 1 : 0)
        let pulse = pulseState.amounts(at: CACurrentMediaTime())
        if pulse.flash > 0.001 {
            cp.flashR = pulseState.color.x
            cp.flashG = pulseState.color.y
            cp.flashB = pulseState.color.z
            cp.flashAmount = pulse.flash
        }
        if pulse.blur > 0.001 {
            cp.blurCX = pulseState.center.x
            cp.blurCY = pulseState.center.y
            cp.blurStrength = pulse.blur
        }
        // 衝撃波の屈折（最大 4 つ。中心・半径は画面の UV）
        cp.rippleAspect = Float(dst.width) / Float(max(1, dst.height))
        for (k, r) in rippleState.prefix(PostProcessor.maxRipples).enumerated() {
            let shape = SIMD4<Float>(r.center.x, r.center.y, max(0.001, r.radius.x), max(0.001, r.radius.y))
            switch k {
            case 0: cp.ripple0 = shape
            case 1: cp.ripple1 = shape
            case 2: cp.ripple2 = shape
            default: cp.ripple3 = shape
            }
            cp.rippleStrength[k] = r.strength
        }
        renc.setRenderPipelineState(composite)
        renc.setFragmentTexture(src, index: 0)
        renc.setFragmentTexture(bloomTexture ?? src, index: 1)
        renc.setFragmentBytes(&cp, length: MemoryLayout<CompositeParams>.stride, index: 0)
        renc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renc.endEncoding()
        if bloomTexture != nil || s.bloomIntensity <= 0 || levels < 2 { fullPassDone = true }
    }

    private static func dispatch(_ enc: MTLComputeCommandEncoder, _ p: MTLComputePipelineState, _ out: MTLTexture) {
        let w = p.threadExecutionWidth
        let h = max(1, p.maxTotalThreadsPerThreadgroup / w)
        let tg = MTLSize(width: w, height: h, depth: 1)
        let groups = MTLSize(width: (out.width + w - 1) / w, height: (out.height + h - 1) / h, depth: 1)
        enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
    }

    /// 元画像をそのまま写す（未準備・失敗時）。
    static func copy(_ ctx: ARView.PostProcessContext) {
        let src = ctx.sourceColorTexture, dst = ctx.targetColorTexture
        guard src.width == dst.width, src.height == dst.height, src.pixelFormat == dst.pixelFormat,
              let blit = ctx.commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: src, to: dst)
        blit.endEncoding()
    }

    /// sample() が線形値を返す（sRGB 形式は自動で復号される・浮動小数は線形）形式か。
    static func isLinear(_ f: MTLPixelFormat) -> Bool {
        switch f {
        case .bgra8Unorm_srgb, .rgba8Unorm_srgb, .rgba16Float, .rgba32Float, .rg11b10Float, .rgb9e5Float, .bgr10_xr_srgb,
             .bgra10_xr_srgb:
            return true
        default:
            return false
        }
    }

    private struct BloomParams {
        var threshold: Float
        var knee: Float
        /// 拡大時に低解像度側（広い滲み）を混ぜる割合（0〜1、エネルギーは保存）。
        var scatter: Float
        var linearInput: Float
    }

    private struct CompositeParams {
        var bloomIntensity: Float
        var contrast: Float
        var saturation: Float
        var linearInput: Float
        // 奥義の脈（ScreenPulse）。0 なら何もしない
        var flashR: Float = 1
        var flashG: Float = 1
        var flashB: Float = 1
        var flashAmount: Float = 0
        var blurCX: Float = 0.5
        var blurCY: Float = 0.5
        var blurStrength: Float = 0
        var pad: Float = 0
        // 衝撃波の屈折（Ripple）。中心 xy・半径 zw（画面の UV）、強さ 0 なら何もしない
        var ripple0 = SIMD4<Float>(0, 0, 1, 1)
        var ripple1 = SIMD4<Float>(0, 0, 1, 1)
        var ripple2 = SIMD4<Float>(0, 0, 1, 1)
        var ripple3 = SIMD4<Float>(0, 0, 1, 1)
        var rippleStrength = SIMD4<Float>(0, 0, 0, 0)
        var rippleAspect: Float = 1
        var ripplePad0: Float = 0
        var ripplePad1: Float = 0
        var ripplePad2: Float = 0
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct BloomParams { float threshold; float knee; float scatter; float linearInput; };
    struct CompositeParams { float bloomIntensity; float contrast; float saturation; float linearInput;
                             float flashR; float flashG; float flashB; float flashAmount;
                             float blurCX; float blurCY; float blurStrength; float pad;
                             float4 ripple0; float4 ripple1; float4 ripple2; float4 ripple3; float4 rippleStrength;
                             float rippleAspect; float ripplePad0; float ripplePad1; float ripplePad2; };

    // 衝撃波の屈折: 輪（中心 r.xy・半径 r.zw）の縁の帯の画素を、中心から外へずらして引く（縁の内側は外へ、外側は内へ寄せる
    // = 背景が輪の縁で膨らんで見える）。帯の幅は半径の 22%。
    static float2 velRipple(float2 uv, float4 r, float strength, float aspect) {
        if (strength <= 0.0) return float2(0.0);
        float2 d = (uv - r.xy) / r.zw;
        float dist = length(d);
        if (dist < 1e-4) return float2(0.0);
        float band = 1.0 - smoothstep(0.0, 0.22, abs(dist - 1.0));
        float side = clamp((1.0 - dist) / 0.22, -1.0, 1.0);
        float2 dir = (d / dist) * r.zw;
        return -dir / max(length(dir), 1e-4) * strength * band * side * float2(1.0 / aspect, 1.0);
    }

    constexpr sampler velLinear(filter::linear, address::clamp_to_edge, coord::normalized);

    static float3 velToPerceptual(float3 c, float linearInput) {
        return linearInput > 0.5 ? sqrt(max(c, 0.0)) : c;
    }
    static float3 velFromPerceptual(float3 c, float linearInput) {
        return linearInput > 0.5 ? c * c : c;
    }

    // 13 タップ縮小（Jimenez 2014）。karis = true で 2x2 ブロック毎の輝度重み平均（明滅の抑制）。
    static float3 velDownsample13(texture2d<float, access::sample> src, float2 uv, float2 t, bool karis) {
        float3 a = src.sample(velLinear, uv + t * float2(-2, -2)).rgb;
        float3 b = src.sample(velLinear, uv + t * float2( 0, -2)).rgb;
        float3 c = src.sample(velLinear, uv + t * float2( 2, -2)).rgb;
        float3 d = src.sample(velLinear, uv + t * float2(-1, -1)).rgb;
        float3 e = src.sample(velLinear, uv + t * float2( 1, -1)).rgb;
        float3 f = src.sample(velLinear, uv + t * float2(-2,  0)).rgb;
        float3 g = src.sample(velLinear, uv).rgb;
        float3 h = src.sample(velLinear, uv + t * float2( 2,  0)).rgb;
        float3 i = src.sample(velLinear, uv + t * float2(-1,  1)).rgb;
        float3 j = src.sample(velLinear, uv + t * float2( 1,  1)).rgb;
        float3 k = src.sample(velLinear, uv + t * float2(-2,  2)).rgb;
        float3 l = src.sample(velLinear, uv + t * float2( 0,  2)).rgb;
        float3 m = src.sample(velLinear, uv + t * float2( 2,  2)).rgb;
        if (!karis) {
            float3 r = (d + e + i + j) * 0.125;
            r += (a + b + g + f) * 0.03125;
            r += (b + c + h + g) * 0.03125;
            r += (f + g + l + k) * 0.03125;
            r += (g + h + m + l) * 0.03125;
            return r;
        }
        float3 g0 = (d + e + i + j) * 0.25;
        float3 g1 = (a + b + g + f) * 0.25;
        float3 g2 = (b + c + h + g) * 0.25;
        float3 g3 = (f + g + l + k) * 0.25;
        float3 g4 = (g + h + m + l) * 0.25;
        float w0 = 0.5   / (1.0 + max(g0.r, max(g0.g, g0.b)));
        float w1 = 0.125 / (1.0 + max(g1.r, max(g1.g, g1.b)));
        float w2 = 0.125 / (1.0 + max(g2.r, max(g2.g, g2.b)));
        float w3 = 0.125 / (1.0 + max(g3.r, max(g3.g, g3.b)));
        float w4 = 0.125 / (1.0 + max(g4.r, max(g4.g, g4.b)));
        return (g0 * w0 + g1 * w1 + g2 * w2 + g3 * w3 + g4 * w4) / max(w0 + w1 + w2 + w3 + w4, 1e-4);
    }

    kernel void velBloomPrefilter(texture2d<float, access::sample> src [[texture(0)]],
                                  texture2d<float, access::write> dst [[texture(1)]],
                                  constant BloomParams& p [[buffer(0)]],
                                  uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
        float2 uv = (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height());
        float2 t = 1.0 / float2(src.get_width(), src.get_height());
        float3 c = velToPerceptual(velDownsample13(src, uv, t, true), p.linearInput);
        // 柔らかい閾値（最大チャンネル）。彩度の低い明部（日向の石畳・白い壁）は滲ませず、発光色だけを拾う
        float br = max(c.r, max(c.g, c.b));
        float mn = min(c.r, min(c.g, c.b));
        float soft = clamp(br - p.threshold + p.knee, 0.0, 2.0 * p.knee);
        soft = soft * soft / (4.0 * p.knee + 1e-5);
        float contrib = max(soft, br - p.threshold) / max(br, 1e-4);
        float sat = (br - mn) / max(br, 1e-4);
        float w = smoothstep(0.18, 0.55, sat);
        dst.write(float4(c * contrib * w, 1.0), gid);
    }

    kernel void velBloomDownsample(texture2d<float, access::sample> src [[texture(0)]],
                                   texture2d<float, access::write> dst [[texture(1)]],
                                   uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
        float2 uv = (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height());
        float2 t = 1.0 / float2(src.get_width(), src.get_height());
        dst.write(float4(velDownsample13(src, uv, t, false), 1.0), gid);
    }

    // 低解像度側を 3x3 テントで拡大し、同解像度の縮小結果と scatter の割合で混ぜる（合計の明るさは増えない）。
    kernel void velBloomUpsample(texture2d<float, access::sample> low [[texture(0)]],
                                 texture2d<float, access::sample> high [[texture(1)]],
                                 texture2d<float, access::write> dst [[texture(2)]],
                                 constant BloomParams& p [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
        float2 uv = (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height());
        float2 t = 1.0 / float2(low.get_width(), low.get_height());
        float3 s = low.sample(velLinear, uv).rgb * 4.0;
        s += (low.sample(velLinear, uv + t * float2(-1, 0)).rgb + low.sample(velLinear, uv + t * float2(1, 0)).rgb
            + low.sample(velLinear, uv + t * float2(0, -1)).rgb + low.sample(velLinear, uv + t * float2(0, 1)).rgb) * 2.0;
        s += low.sample(velLinear, uv + t * float2(-1, -1)).rgb + low.sample(velLinear, uv + t * float2(1, -1)).rgb
            + low.sample(velLinear, uv + t * float2(-1, 1)).rgb + low.sample(velLinear, uv + t * float2(1, 1)).rgb;
        float3 h = high.sample(velLinear, uv).rgb;
        dst.write(float4(mix(h, s * (1.0 / 16.0), p.scatter), 1.0), gid);
    }

    struct VelVertexOut { float4 position [[position]]; float2 uv; };

    vertex VelVertexOut velFullscreenVertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VelVertexOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = float2(p.x, 1.0 - p.y);
        return o;
    }

    fragment float4 velCompositeFragment(VelVertexOut in [[stage_in]],
                                         texture2d<float, access::sample> src [[texture(0)]],
                                         texture2d<float, access::sample> bloom [[texture(1)]],
                                         constant CompositeParams& p [[buffer(0)]]) {
        float4 base;
        float2 uv = in.uv;
        uv += velRipple(in.uv, p.ripple0, p.rippleStrength.x, p.rippleAspect);
        uv += velRipple(in.uv, p.ripple1, p.rippleStrength.y, p.rippleAspect);
        uv += velRipple(in.uv, p.ripple2, p.rippleStrength.z, p.rippleAspect);
        uv += velRipple(in.uv, p.ripple3, p.rippleStrength.w, p.rippleAspect);
        if (p.blurStrength > 0.0) {
            // 奥義の放射状のぼかし: 中心へ縮めた像を 8 枚重ねる（強さ 1 で 12% まで）
            float2 center = float2(p.blurCX, p.blurCY);
            float2 d = uv - center;
            float4 acc = float4(0.0);
            for (int i = 0; i < 8; i++) {
                float k = 1.0 - p.blurStrength * 0.12 * (float(i) / 7.0);
                acc += src.sample(velLinear, center + d * k);
            }
            base = acc / 8.0;
        } else {
            base = src.sample(velLinear, uv);
        }
        float3 c = velToPerceptual(base.rgb, p.linearInput);
        if (p.bloomIntensity > 0.0) {
            float3 b = bloom.sample(velLinear, in.uv).rgb;
            // スクリーン合成（白飛びさせずに光を足す）
            c = 1.0 - (1.0 - c) * (1.0 - min(b * p.bloomIntensity, 1.0));
        }
        // 色調整: コントラスト（中間調を軸）・彩度・暗部をわずかに青へ / 明部をわずかに暖色へ
        c = (c - 0.5) * p.contrast + 0.5;
        float lum = dot(c, float3(0.2126, 0.7152, 0.0722));
        c = mix(float3(lum), c, p.saturation);
        float shadow = 1.0 - smoothstep(0.0, 0.45, lum);
        float highlight = smoothstep(0.55, 1.0, lum);
        c += shadow * float3(-0.006, 0.0, 0.018) + highlight * float3(0.012, 0.006, -0.01);
        if (p.flashAmount > 0.0) {
            // 奥義の閃光（スクリーン合成。白飛びさせずに明るくする）
            float3 f = float3(p.flashR, p.flashG, p.flashB) * p.flashAmount;
            c = 1.0 - (1.0 - clamp(c, 0.0, 1.0)) * (1.0 - f);
        }
        // 8bit 化の縞を消す微小ディザ（画素位置で固定。時間で変えないのでちらつかない）
        float2 px = in.position.xy;
        float n = fract(52.9829189 * fract(dot(px, float2(0.06711056, 0.00583715))));
        c += (n - 0.5) / 255.0;
        c = clamp(c, 0.0, 1.0);
        return float4(velFromPerceptual(c, p.linearInput), base.a);
    }
    """
}
