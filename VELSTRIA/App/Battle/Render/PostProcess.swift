import Foundation
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

/// renderCallbacks から（RealityKit の描画スレッドで）呼ばれる。設定・パイプラインは lock で守る。
final class PostProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: PostProcessSettings
    private var device: MTLDevice?
    private var prefilter: MTLComputePipelineState?
    private var downsample: MTLComputePipelineState?
    private var upsample: MTLComputePipelineState?
    private var library: MTLLibrary?
    private var compositePipelines: [UInt: MTLRenderPipelineState] = [:]
    /// 合成パイプラインを作成中の出力形式（描画スレッドを止めないよう非同期に作る）。
    private var pendingFormats: Set<UInt> = []
    private var down: [MTLTexture] = []
    private var up: [MTLTexture] = []
    private var chainKey = SIMD3<Int>(0, 0, 0)
    private var compiling = false
    /// 作り直し（resetLocked）の世代。古いコンパイル結果を後から書き込まない。
    private var generation = 0
    /// コンパイル失敗の回数。上限に達したら後処理を外す（何もしない全画面コピーを毎フレーム払わない）。
    private var failures = 0
    private var gaveUp = false
    static let maxFailures = 3

    init(settings: PostProcessSettings) {
        self.settings = settings
        // 読み込み中（地面テクスチャ生成の裏）にコンパイルを済ませ、幕が上がった最初のフレームから効かせる。
        // iOS の GPU は 1 つなので、描画系の device と同じ。違えば process で作り直す
        if settings.enabled, let device = MTLCreateSystemDefaultDevice() {
            lock.lock()
            prepareLocked(device: device)
            lock.unlock()
        }
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

    /// シェーダーを非同期にコンパイルする（lock 保持中に呼ぶ）。
    /// コンパイルとパイプライン生成は自前の背景キューで同期 API を使って行う。Metal の完了ハンドラ
    /// （Metal のコンパイラキュー上）から同期 API を呼ぶと同じキューを待ってトラップするため、完了ハンドラ版は使わない。
    /// lock は生成中に持たない（結果を書き込むときだけ取る）。
    private func prepareLocked(device: MTLDevice) {
        guard self.device == nil, !compiling, !gaveUp else { return }
        compiling = true
        let gen = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let options = MTLCompileOptions()
            options.mathMode = .fast
            var lib: MTLLibrary?
            do {
                lib = try device.makeLibrary(source: PostProcessor.shaderSource, options: options)
            } catch {
                #if DEBUG
                NSLog("%@", "[PostProcess] shader compile failed: \(error)")
                #endif
            }
            func compute(_ name: String) -> MTLComputePipelineState? {
                lib?.makeFunction(name: name).flatMap { try? device.makeComputePipelineState(function: $0) }
            }
            let pre = compute("velBloomPrefilter"), dn = compute("velBloomDownsample"), upPipe = compute("velBloomUpsample")
            // 実機の描画先として最も多い形式は先に作っておく（最初のフレームを待たせない）
            let srgb = lib.flatMap { PostProcessor.makeComposite(for: .bgra8Unorm_srgb, device: device, library: $0) }
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard gen == self.generation else { return }
            self.compiling = false
            guard let lib, let pre, let dn, let upPipe else {
                // 一時的な失敗（コンパイラの中断など）は次のフレームで作り直す。続けば諦めて外す
                self.noteFailureLocked()
                return
            }
            self.device = device
            self.library = lib
            self.prefilter = pre
            self.downsample = dn
            self.upsample = upPipe
            if let srgb { self.compositePipelines[MTLPixelFormat.bgra8Unorm_srgb.rawValue] = srgb }
        }
    }

    /// 合成パイプライン（全画面三角形 → 出力形式 format）。背景キューから呼ぶ（同期でコンパイルする）。
    private static func makeComposite(for format: MTLPixelFormat, device: MTLDevice,
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
        compositePipelines.removeAll()
        pendingFormats.removeAll()
        down.removeAll()
        up.removeAll()
        chainKey = .zero
        compiling = false
    }

    /// 合成パイプラインを非同期に作り始める（lock 保持中に呼ぶ。完成までは元画像を写す）。
    private func requestCompositeLocked(for format: MTLPixelFormat, device: MTLDevice, library: MTLLibrary) {
        let key = format.rawValue
        guard compositePipelines[key] == nil, !pendingFormats.contains(key) else { return }
        pendingFormats.insert(key)
        let gen = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pipeline = PostProcessor.makeComposite(for: format, device: device, library: library)
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard gen == self.generation else { return }
            self.pendingFormats.remove(key)
            if let pipeline {
                self.compositePipelines[key] = pipeline
            } else {
                self.noteFailureLocked()
            }
        }
    }

    private func ensureChain(device: MTLDevice, width: Int, height: Int, levels: Int) -> Bool {
        let key = SIMD3(width, height, levels)
        if key == chainKey, down.count == levels { return true }
        down.removeAll()
        up.removeAll()
        chainKey = .zero
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
        chainKey = key
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
        guard s.enabled, !gaveUp, let library, let device else {
            PostProcessor.copy(ctx)
            return
        }
        let src = ctx.sourceColorTexture, dst = ctx.targetColorTexture
        guard let composite = compositePipelines[dst.pixelFormat.rawValue] else {
            requestCompositeLocked(for: dst.pixelFormat, device: device, library: library)
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
        renc.setRenderPipelineState(composite)
        renc.setFragmentTexture(src, index: 0)
        renc.setFragmentTexture(bloomTexture ?? src, index: 1)
        renc.setFragmentBytes(&cp, length: MemoryLayout<CompositeParams>.stride, index: 0)
        renc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renc.endEncoding()
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
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct BloomParams { float threshold; float knee; float scatter; float linearInput; };
    struct CompositeParams { float bloomIntensity; float contrast; float saturation; float linearInput; };

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
        float4 base = src.sample(velLinear, in.uv);
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
        // 8bit 化の縞を消す微小ディザ（画素位置で固定。時間で変えないのでちらつかない）
        float2 px = in.position.xy;
        float n = fract(52.9829189 * fract(dot(px, float2(0.06711056, 0.00583715))));
        c += (n - 0.5) / 255.0;
        c = clamp(c, 0.0, 1.0);
        return float4(velFromPerceptual(c, p.linearInput), base.a);
    }
    """
}
