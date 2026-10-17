import Foundation
import Metal
import QuartzCore
import RealityKit
import UIKit

// 担当: Effekseer を RealityKit の後処理（PostProcessor.process）の中で描くパス。描画スレッドで、PostProcessor の錠の中から呼ぶ。
// 1 つのレンダーパスで:
//   1. 3D 画面の色（sourceColor）を自前の色（fxColor）へ、深度（sourceDepth）を自前の深度（Depth32Float・タイルの中だけ）へ写す
//   2. 同じパスで Effekseer の「3D に隠れる層」を描く（歪みの背景は効果を描く前の 3D 画面 = sourceColor）
//   3. 深度を遠い面へ戻し（velDepthReset）、「3D の上の層」（旧来の .efk・命中の閃き。EfkRuntime.setOnTop）を描く
// ブルーム・合成は fxColor を元画像として読む（効果にもブルームが掛かる。奥義の脈の放射状のぼかしも効果ごと掛かる）。
// 効果が 1 つも出ていない・Effekseer がこの経路で描かないフレームは何もしない（sourceColor をそのまま使う。追加の費用 0）。
// 3D 画面が sRGB の形式（BGRA8Unorm_sRGB など）の時は、fxColor の sRGB でない見え方（テクスチャのビュー）へ sRGB に符号化して写し、
// Effekseer もそこへ描く（Effekseer の Metal の描き手は sRGB の描画先で何も描かない。2026-10-18 の CI の自己診断。重ね描きと同じくガンマの空間で混ぜる）。
// 安全装置: 後処理用の描き手ができたら、描画先の形式・深度の向きごとに 1 回、小さな確かめの効果（Zt_PostProbe）を画面外の小さな画へ
// 描いて光った画素を数える（probe）。足りなければその試合は重ね描きのまま（実機で「Effekseer が何も出ない」を起こさない）。
// メインスレッドは drawsEffekseer（直近にこの経路で描ける状態だった）を見て、重ね描きと後処理のどちらで描くかを毎フレーム決める。

final class EffekseerPostPass: @unchecked Sendable {
    /// 後処理の中で描く経路を使うか（全体の切り替え。false = 実機でも常に重ね描き）。
    nonisolated(unsafe) static var isEnabled = true
    /// 確かめの効果（Effects/Effekseer/Zt_PostProbe.efk。白い大きな光 1 枚。全試合で読む）。
    static let probeEffect = "Zt_PostProbe"
    /// 確かめで光るべき画素の数の下限（64 × 64 の画の中央に大きく映る）。
    static let probeMinLit = 40
    static let probeSize = 64

    /// 後処理の中で描くか（純粋。単体テスト対象）: 切り替えが有効・描き手ができた・確かめで十分に光った時だけ。
    static func usesPostPath(enabled: Bool, prepared: Bool, probeLit: Int?) -> Bool {
        enabled && prepared && (probeLit ?? 0) >= probeMinLit
    }

    /// 写すパスのシェーダー（PostProcessor.shaderSource の後ろへ繋いで 1 つのライブラリにする。VelVertexOut・velFullscreenVertex を使う）。
    static let shaderSource = """

    struct VelSceneCopyOut { float4 color [[color(0)]]; float depth [[depth(any)]]; };

    // 3D 画面の色と深度を写す（同じ大きさ。画素をそのまま読む）
    fragment VelSceneCopyOut velSceneCopyFragment(VelVertexOut in [[stage_in]],
                                                  texture2d<float, access::read> color [[texture(0)]],
                                                  depth2d<float, access::read> depth [[texture(1)]]) {
        uint2 p = uint2(in.position.xy);
        VelSceneCopyOut o;
        o.color = color.read(p);
        o.depth = depth.read(p);
        return o;
    }

    static float3 velLinearToSRGB(float3 c) {
        c = max(c, 0.0);
        return select(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, c * 12.92, c <= 0.0031308);
    }

    // sRGB の 3D 画面（読むと線形）を、sRGB でない見え方の描画先へ sRGB に符号化して写す（元の画素と同じ値になる）
    fragment VelSceneCopyOut velSceneCopySRGBFragment(VelVertexOut in [[stage_in]],
                                                      texture2d<float, access::read> color [[texture(0)]],
                                                      depth2d<float, access::read> depth [[texture(1)]]) {
        uint2 p = uint2(in.position.xy);
        float4 c = color.read(p);
        VelSceneCopyOut o;
        o.color = float4(velLinearToSRGB(c.rgb), c.a);
        o.depth = depth.read(p);
        return o;
    }

    // 深度を一様な値（遠い面）へ戻す（色は書かない）。3D に隠れる層の後、3D の上の層の前
    struct VelDepthResetOut { float4 position [[position]]; };
    vertex VelDepthResetOut velDepthResetVertex(uint vid [[vertex_id]], constant float &depth [[buffer(0)]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VelDepthResetOut o;
        o.position = float4(p * 2.0 - 1.0, depth, 1.0);
        return o;
    }
    fragment void velDepthResetFragment() {}
    """

    /// 3D 画面の色の形式 → Effekseer が描く形式（sRGB は sRGB でない見え方へ。encodeSRGB = 写す時に符号化する）。
    static func renderFormat(_ src: MTLPixelFormat) -> (format: MTLPixelFormat, encodeSRGB: Bool) {
        switch src {
        case .bgra8Unorm_srgb: return (.bgra8Unorm, true)
        case .rgba8Unorm_srgb: return (.rgba8Unorm, true)
        default: return (src, false)
        }
    }

    /// メインスレッドが「後処理で描ける」と見なす、最後に描ける状態だったフレームからの秒数。
    static let staleSeconds: Double = 0.3

    private let lock = NSLock()
    private weak var runtime: EfkRuntime?
    private var capableAt: Double = -100
    /// 確かめの結果の報告（BattleRenderer が計測ログへ 1 回書く。lock で守る）。
    private var reports: [String] = []
    /// 背景で作っている・作り終えた・作れなかった写すパスのパイプライン（lock で守る）。
    private var pendingFormats: Set<UInt> = []
    private var failedFormats: Set<UInt> = []
    private var readyPipelines: [UInt: Pipelines] = [:]
    /// 以下は描画スレッドだけが触る（PostProcessor の錠の中）。
    private var copyPipelines: [UInt: Pipelines] = [:]
    private var depthState: MTLDepthStencilState?
    /// 3D 画面と同じ形式の写し（ブルーム・合成が読む）と、Effekseer が描く見え方（sRGB は sRGB でない形式のビュー）。
    private var color: MTLTexture?
    private var colorTarget: MTLTexture?
    private var depth: MTLTexture?
    /// 確かめの結果（描画先の形式 × 深度の向き → 光った画素の数。-1 = 確かめられなかった）。
    private var probes: [ProbeKey: Int] = [:]

    private struct ProbeKey: Hashable {
        var format: UInt
        var reversed: Bool
    }

    /// 形式ごとのパイプライン（写す・深度を戻す）。
    struct Pipelines {
        var copy: MTLRenderPipelineState
        var resetDepth: MTLRenderPipelineState
    }

    /// 描く Effekseer（実機の後処理が使える時だけ BattleRenderer が渡す。nil で外す）。どのスレッドからでもよい。
    func attach(_ r: EfkRuntime?) {
        lock.lock()
        runtime = r
        if r == nil { capableAt = -100 }
        lock.unlock()
    }

    /// 直近にこの経路で描ける状態だったか（メインスレッド。false の間は重ね描き）。
    func drawsEffekseer(now: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runtime != nil && now - capableAt < EffekseerPostPass.staleSeconds
    }

    /// 確かめの結果の報告を取り出す（メインスレッド。計測ログ・Debug の出力へ）。
    func takeReports() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let r = reports
        reports.removeAll()
        return r
    }

    private func noteCapable(_ now: Double) {
        lock.lock()
        capableAt = now
        lock.unlock()
    }

    private func report(_ s: String) {
        lock.lock()
        if reports.count < 8 { reports.append(s) }
        lock.unlock()
    }

    private var attached: EfkRuntime? {
        lock.lock()
        defer { lock.unlock() }
        return runtime
    }

    /// 効果を描いた画（3D 画面の写し + 効果）を返す。この経路で描かないフレームは nil（呼び出し側は sourceColor をそのまま使う）。
    /// library は PostProcessor のライブラリ（shaderSource + EffekseerPostPass.shaderSource）。
    func encode(_ ctx: ARView.PostProcessContext, library: MTLLibrary, device: MTLDevice) -> MTLTexture? {
        guard EffekseerPostPass.isEnabled, let runtime = attached else { return nil }
        let src = ctx.sourceColorTexture, srcDepth = ctx.sourceDepthTexture
        // 深度を写せる形（同じ大きさ・1 サンプル）でなければこの経路は使わない（重ね描きのまま）
        guard src.width == srcDepth.width, src.height == srcDepth.height, src.sampleCount == 1, srcDepth.sampleCount == 1
        else { return nil }
        let reversed = EfkRuntime.isReversedDepth(projection: ctx.projection)
        let rf = EffekseerPostPass.renderFormat(src.pixelFormat)
        guard runtime.isPrepared(postColorFormat: rf.format, reversedDepth: reversed) else { return nil }
        // 安全装置: この形式・深度の向きで本当に描けるかを 1 回だけ確かめる（描けなければこの試合は重ね描き）
        let key = ProbeKey(format: rf.format.rawValue, reversed: reversed)
        if probes[key] == nil {
            let lit = runtime.probePost(effectNamed: EffekseerPostPass.probeEffect, colorFormat: rf.format, reversedDepth: reversed)
            probes[key] = lit
            let ok = EffekseerPostPass.usesPostPath(enabled: true, prepared: true, probeLit: lit)
            report("effekseer post probe src=\(src.pixelFormat.rawValue) draw=\(rf.format.rawValue) reversed=\(reversed) "
                   + "lit=\(lit) -> \(ok ? "post" : "overlay")")
        }
        guard EffekseerPostPass.usesPostPath(enabled: true, prepared: true, probeLit: probes[key]),
              let pipelines = pipelines(rf.format, encodeSRGB: rf.encodeSRGB, library: library, device: device),
              let depthState = makeDepthState(device), ensureTargets(device: device, like: src, target: rf) else { return nil }
        noteCapable(CACurrentMediaTime())
        // メインスレッドがこの経路で描くと決めていて、効果が出ている時だけ描く
        guard runtime.drawsInPostProcess, runtime.activeCount > 0, let color, let colorTarget, let depth else { return nil }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = colorTarget
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        rp.depthAttachment.texture = depth
        rp.depthAttachment.loadAction = .dontCare
        rp.depthAttachment.storeAction = .dontCare
        guard let enc = ctx.commandBuffer.makeRenderCommandEncoder(descriptor: rp) else { return nil }
        enc.label = "velEffekseer"
        enc.setRenderPipelineState(pipelines.copy)
        enc.setDepthStencilState(depthState)
        enc.setFragmentTexture(src, index: 0)
        enc.setFragmentTexture(srcDepth, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        // 描かなかった（効果がちょうど消えた）時も、写した画は元画像と同じなのでそのまま使える
        _ = runtime.encodePost(encoder: enc, projection: ctx.projection, background: src,
                               resetDepth: EffekseerPostPass.depthReset(pipelines.resetDepth, depthState, reversed: reversed))
        enc.endEncoding()
        return color
    }

    // MARK: 準備

    private func pipelines(_ format: MTLPixelFormat, encodeSRGB: Bool, library: MTLLibrary,
                           device: MTLDevice) -> Pipelines? {
        let key = format.rawValue << 1 | (encodeSRGB ? 1 : 0)
        if let p = copyPipelines[key] { return p }
        lock.lock()
        if let p = readyPipelines.removeValue(forKey: key) {
            lock.unlock()
            copyPipelines[key] = p
            return p
        }
        let busy = pendingFormats.contains(key) || failedFormats.contains(key)
        if !busy { pendingFormats.insert(key) }
        lock.unlock()
        guard !busy else { return nil }
        // 描画スレッドを止めないよう背景で作る（作り終えるまでは重ね描き）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let p = EffekseerPostPass.makePipelines(format, encodeSRGB: encodeSRGB, library: library, device: device)
            guard let self else { return }
            self.lock.lock()
            self.pendingFormats.remove(key)
            if let p { self.readyPipelines[key] = p } else { self.failedFormats.insert(key) }
            self.lock.unlock()
        }
        return nil
    }

    /// 写す・深度を戻すパイプライン（色 = Effekseer が描く形式、深度 = Depth32Float）。テストからも使う。
    static func makePipelines(_ format: MTLPixelFormat, encodeSRGB: Bool = false, library: MTLLibrary,
                              device: MTLDevice) -> Pipelines? {
        let d = MTLRenderPipelineDescriptor()
        d.label = "velSceneCopy"
        d.vertexFunction = library.makeFunction(name: "velFullscreenVertex")
        d.fragmentFunction = library.makeFunction(name: encodeSRGB ? "velSceneCopySRGBFragment" : "velSceneCopyFragment")
        d.colorAttachments[0].pixelFormat = format
        d.depthAttachmentPixelFormat = .depth32Float
        let r = MTLRenderPipelineDescriptor()
        r.label = "velDepthReset"
        r.vertexFunction = library.makeFunction(name: "velDepthResetVertex")
        r.fragmentFunction = library.makeFunction(name: "velDepthResetFragment")
        r.colorAttachments[0].pixelFormat = format
        r.colorAttachments[0].writeMask = []
        r.depthAttachmentPixelFormat = .depth32Float
        guard d.vertexFunction != nil, d.fragmentFunction != nil, r.vertexFunction != nil, r.fragmentFunction != nil,
              let copy = try? device.makeRenderPipelineState(descriptor: d),
              let reset = try? device.makeRenderPipelineState(descriptor: r) else { return nil }
        return Pipelines(copy: copy, resetDepth: reset)
    }

    /// 深度を遠い面（逆 Z は 0、通常は 1）へ戻す処理（3D の上の層の前に、同じ encoder で）。
    static func depthReset(_ pipeline: MTLRenderPipelineState, _ depthState: MTLDepthStencilState,
                           reversed: Bool) -> (MTLRenderCommandEncoder) -> Void {
        { enc in
            var far: Float = reversed ? 0 : 1
            enc.setRenderPipelineState(pipeline)
            enc.setDepthStencilState(depthState)
            enc.setCullMode(.none)
            enc.setVertexBytes(&far, length: MemoryLayout<Float>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }

    private func makeDepthState(_ device: MTLDevice) -> MTLDepthStencilState? {
        if let depthState { return depthState }
        depthState = EffekseerPostPass.writeDepthState(device)
        return depthState
    }

    /// 深度を必ず書く（比べない）状態。
    static func writeDepthState(_ device: MTLDevice) -> MTLDepthStencilState? {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .always
        d.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: d)
    }

    /// 写し先（3D 画面と同じ大きさ・形式の色と、Effekseer が描く見え方、タイルの中だけの深度）。大きさ・形式が変わった時だけ作り直す。
    private func ensureTargets(device: MTLDevice, like src: MTLTexture,
                               target rf: (format: MTLPixelFormat, encodeSRGB: Bool)) -> Bool {
        if let c = color, c.width == src.width, c.height == src.height, c.pixelFormat == src.pixelFormat,
           colorTarget?.pixelFormat == rf.format, depth != nil {
            return true
        }
        color = nil
        colorTarget = nil
        depth = nil
        guard let made = EffekseerPostPass.makeTargets(device: device, format: src.pixelFormat, width: src.width,
                                                       height: src.height) else { return false }
        color = made.color
        colorTarget = made.target
        depth = made.depth
        return true
    }

    /// 色（format）・Effekseer が描く見え方（renderFormat）・深度（Depth32Float。実機はタイルの中だけ）。テストからも使う。
    static func makeTargets(device: MTLDevice, format: MTLPixelFormat, width: Int, height: Int,
                            memorylessDepth: Bool = true) -> (color: MTLTexture, target: MTLTexture, depth: MTLTexture)? {
        let rf = renderFormat(format)
        let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        cd.usage = rf.encodeSRGB ? [.renderTarget, .shaderRead, .pixelFormatView] : [.renderTarget, .shaderRead]
        cd.storageMode = .private
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        dd.usage = [.renderTarget]
        #if targetEnvironment(simulator)
        dd.storageMode = .private
        #else
        dd.storageMode = memorylessDepth ? .memoryless : .private
        #endif
        guard let c = device.makeTexture(descriptor: cd), let d = device.makeTexture(descriptor: dd) else { return nil }
        let view: MTLTexture? = rf.encodeSRGB ? c.makeTextureView(pixelFormat: rf.format) : c
        guard let t = view else { return nil }
        c.label = "velEffekseerColor"
        d.label = "velEffekseerDepth"
        return (c, t, d)
    }
}

// MARK: - 自己診断（Debug。単体テストと演出の撮影 FXCapture から）

#if DEBUG
extension EffekseerPostPass {
    struct SelfTest: Equatable {
        var label = ""
        /// 描き手を作れた（後処理用。重ね描きの比較は常に true）。
        var prepared = false
        /// 描いた（encodePost / 重ね描きの描画が呼べた）。
        var drew = false
        /// 進めた後の Effekseer の粒子の数。
        var instances = 0
        /// 深度が遠い画で効果が映った画素の数。
        var litFar = 0
        /// 深度が近い（全面が効果の手前にある）画で効果が映った画素の数（0 = 3D に隠れる）。
        var litNear = 0
        /// 同じ近い深度で、効果を「3D の上の層」（setOnTop）にした時に映った画素の数（> 0 = 深度を戻して上に描く）。
        var litNearOnTop = 0
        /// 安全装置の確かめ（probePost）で光った画素の数（後処理の組だけ）。
        var probe = 0

        var summary: String {
            "efkPost[\(label)] prepared=\(prepared) drew=\(drew) instances=\(instances) litFar=\(litFar) litNear=\(litNear) "
                + "litNearOnTop=\(litNearOnTop) probe=\(probe)"
        }
    }

    /// 逆 Z・遠い面なしの射影（RealityKit と同じ形。近いほど深度が大きい）。
    static func reversedPerspective(fovY: Float, aspect: Float, near: Float) -> simd_float4x4 {
        let f = 1 / tan(fovY / 2)
        return simd_float4x4(columns: (SIMD4(f / aspect, 0, 0, 0), SIMD4(0, f, 0, 0), SIMD4(0, 0, 0, -1), SIMD4(0, 0, near, 0)))
    }

    /// 通常の射影（深度 0 = 近い、1 = 遠い）。
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let f = 1 / tan(fovY / 2)
        return simd_float4x4(columns: (SIMD4(f / aspect, 0, 0, 0), SIMD4(0, f, 0, 0), SIMD4(0, 0, far / (near - far), -1),
                                       SIMD4(0, 0, near * far / (near - far), 0)))
    }

    /// 撮影の最後に試す組（3D 画面の色の形式・深度の向きと、比べるための重ね描きの描き手）。
    static let selfTestCases: [(label: String, format: MTLPixelFormat, reversed: Bool, overlay: Bool)] = [
        ("overlay", .bgra8Unorm, false, true),
        ("bgra8", .bgra8Unorm, false, false),
        ("bgra8srgb-rev", .bgra8Unorm_srgb, true, false),
        ("rgba16f-rev", .rgba16Float, true, false),
    ]

    /// 後処理の中で描く経路を、黒い画と一様な深度（遠い / 近い）で試す（実機の 3D 画面が無くても、描き手の作成・描画・深度の向きを確かめる）。
    /// format は 3D 画面の色の形式（sRGB は本番と同じく sRGB でない見え方へ描く）。overlay = 重ね描きの描き手で同じ画を描く（比べる基準。深度なし）。
    /// effects はバンドルの効果の名前（拡張子なし）。確かめの効果（probeEffect）も読んで probePost を試す。
    /// saveTo を渡すと、遠い深度の画を PNG で書き出す。
    @MainActor
    static func selfTest(effects: [String], bundle: Bundle = .main, size: Int = 192, format: MTLPixelFormat = .bgra8Unorm_srgb,
                         reversed: Bool = true, overlay: Bool = false, label: String = "", timeout: Double = 8,
                         saveTo: URL? = nil) -> SelfTest {
        var r = SelfTest(label: label.isEmpty ? "\(format.rawValue)\(reversed ? "-rev" : "")" : label)
        let rf = overlay ? (format: MTLPixelFormat.bgra8Unorm, encodeSRGB: false) : renderFormat(format)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(), let rt = EfkRuntime(),
              let dir = bundle.url(forResource: EffekseerOverlay.bundleFolder, withExtension: nil),
              let lib = try? device.makeLibrary(source: PostProcessor.librarySource, options: nil),
              let pipelines = makePipelines(rf.format, encodeSRGB: rf.encodeSRGB, library: lib, device: device),
              let depthState = writeDepthState(device)
        else { return r }
        for n in effects + [probeEffect] {
            _ = rt.loadEffectNamed(n, path: dir.appendingPathComponent(n + ".efk").path, magnification: 1)
        }
        if !overlay {
            let deadline = CFAbsoluteTimeGetCurrent() + timeout
            while !rt.isPrepared(postColorFormat: rf.format, reversedDepth: reversed) {
                guard CFAbsoluteTimeGetCurrent() < deadline else { return r }
                Thread.sleep(forTimeInterval: 0.02)
            }
            r.probe = rt.probePost(effectNamed: probeEffect, colorFormat: rf.format, reversedDepth: reversed)
            rt.drawsInPostProcess = true
        }
        r.prepared = true
        let cam = Entity()
        cam.look(at: [0, 0.8, 0], from: [0, 8, 8.5], relativeTo: nil)
        let world = cam.transformMatrix(relativeTo: nil)
        let handles = effects.map { rt.playNamed($0, position: .zero, yaw: 0, scale: 1, speed: 1) }
        for _ in 0..<8 { rt.advance(cameraWorld: world, deltaSeconds: 1.0 / 60) }
        r.instances = rt.activeCount
        let fov: Float = 40 * .pi / 180
        let proj = reversed ? reversedPerspective(fovY: fov, aspect: 1, near: 0.5)
            : perspective(fovY: fov, aspect: 1, near: 0.5, far: 200)
        let farDepth: Double = reversed ? 0 : 1, nearDepth: Double = reversed ? 1 : 0

        func draw(clearDepth: Double) -> (lit: Int, drew: Bool, bytes: [UInt8]) {
            let px = format == .rgba16Float ? 8 : 4
            guard let made = makeTargets(device: device, format: overlay ? .bgra8Unorm : format, width: size, height: size,
                                         memorylessDepth: false),
                  let buf = device.makeBuffer(length: size * size * px, options: .storageModeShared),
                  let cb = queue.makeCommandBuffer() else { return (0, false, []) }
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = made.target
            rp.colorAttachments[0].loadAction = .clear
            rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            rp.colorAttachments[0].storeAction = .store
            if !overlay {
                rp.depthAttachment.texture = made.depth
                rp.depthAttachment.loadAction = .clear
                rp.depthAttachment.clearDepth = clearDepth
                rp.depthAttachment.storeAction = .dontCare
            }
            guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return (0, false, []) }
            let drew = overlay
                ? rt.debugEncodeOverlay(encoder: enc, cameraWorld: world, projection: proj)
                : rt.encodePost(encoder: enc, projection: proj, background: nil,
                                resetDepth: depthReset(pipelines.resetDepth, depthState, reversed: reversed))
            enc.endEncoding()
            guard let blit = cb.makeBlitCommandEncoder() else { return (0, drew, []) }
            blit.copy(from: made.color, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: size, height: size, depth: 1), to: buf, destinationOffset: 0,
                      destinationBytesPerRow: size * px, destinationBytesPerImage: size * size * px)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: size * size * 4)
            var lit = 0
            if px == 8 {
                let p = buf.contents().bindMemory(to: Float16.self, capacity: size * size * 4)
                for i in 0..<(size * size) {
                    let v = (0..<3).map { Float(p[i * 4 + $0]) }
                    if (v.max() ?? 0) > 0.04 { lit += 1 }
                    for c in 0..<3 { bytes[i * 4 + (2 - c)] = UInt8(max(0, min(255, (v[c].squareRoot() * 255).rounded()))) }
                    bytes[i * 4 + 3] = 255
                }
            } else {
                let p = buf.contents().bindMemory(to: UInt8.self, capacity: size * size * 4)
                bytes = Array(UnsafeBufferPointer(start: p, count: size * size * 4))
                for i in stride(from: 0, to: bytes.count, by: 4) where max(bytes[i], bytes[i + 1], bytes[i + 2]) > 10 { lit += 1 }
            }
            return (lit, drew, bytes)
        }

        let far = draw(clearDepth: farDepth)
        let near = draw(clearDepth: nearDepth)
        for h in handles where h >= 0 { rt.setOnTop(true, handle: h) }
        let onTop = draw(clearDepth: nearDepth)
        r.drew = far.drew
        r.litFar = far.lit
        r.litNear = near.lit
        r.litNearOnTop = onTop.lit
        if let saveTo, !far.bytes.isEmpty { savePNG(far.bytes, size: size, to: saveTo) }
        rt.stopAll()
        return r
    }

    /// BGRA の画素を PNG で書き出す（確認用）。
    static func savePNG(_ bytes: [UInt8], size: Int, to url: URL) {
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                           | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let png = UIImage(cgImage: image).pngData() else { return }
        try? png.write(to: url, options: .atomic)
    }
}
#endif
