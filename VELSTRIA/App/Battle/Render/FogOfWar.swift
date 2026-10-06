import CoreGraphics
import Foundation
import Metal
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。戦場の霧（プレイヤーは自チームの視界。観戦者は選んだチームの視界、全体視点では霧を出さない）。
// state.vision.cells（60×60）→ 双線形で N×N へ拡大 → ボックスぼかし 2 回、を 10Hz で行い（視界は 3 tick 毎にしか変わらない）、
// 時間方向の補間は毎フレーム指数的に行って地面すぐ上の半透明な板の不透明度テクスチャ（LowLevelTexture）へ転送する
// （10Hz で段階的に動かすと、走っている間に霧の縁がカクついて見える）。
// 目標の計算（拡大・ぼかし）は背景キュー（FogWorker）で行い、出来上がった配列を表示側と入れ替える（二重バッファ）。
// メインスレッドに残るのは毎フレームの補間と転送だけで、補間が目標に届いたら転送も止める。
// 観戦者は試合中に視点チーム（全体 / Blue / Red）を切り替えられる（setTeam）。全体視点では板を隠して計算もしない。
// Blue ⇄ Red は今の霧から滑らかに移り、隠していた状態から出す時は最初の目標に合わせてから見せる（古い濃度を見せない）。

/// 霧の濃度場（純粋な計算部分。テスト可能）。0 = 見えている、1 = 霧。
struct FogField {
    let size: Int
    private(set) var current: [Float]
    private(set) var target: [Float]
    private var temp: [Float]
    private var initialized = false

    init(size: Int) {
        self.size = max(8, size)
        current = [Float](repeating: 1, count: self.size * self.size)
        target = current
        temp = current
    }

    /// 視界格子から目標の霧濃度を作る。bit = 視点チームの Team.visionBit。行 0 = sim y の最小側。
    mutating func computeTarget(cells: [UInt8], cols: Int, rows: Int, bit: UInt8) {
        FogField.fillTarget(&target, temp: &temp, size: size, cells: cells, cols: cols, rows: rows, bit: bit)
        if !initialized {
            current = target
            initialized = true
        }
    }

    /// 背景で作った目標を差し込む。中身を入れ替え、t には古い目標が戻る（次の計算の作業領域に回す）。
    mutating func swapTarget(_ t: inout [Float]) {
        guard t.count == size * size else { return }
        swap(&target, &t)
        if !initialized {
            current = target
            initialized = true
        }
    }

    /// 目標の霧濃度を target へ書く（純関数。どのスレッドからでもよい）。temp はぼかしの作業領域（size² 要素）。
    static func fillTarget(_ target: inout [Float], temp: inout [Float], size n: Int, cells: [UInt8], cols: Int, rows: Int,
                           bit: UInt8) {
        if target.count != n * n { target = [Float](repeating: 1, count: n * n) }
        if temp.count != n * n { temp = [Float](repeating: 1, count: n * n) }
        guard cols > 0, rows > 0, cells.count >= cols * rows else {
            for i in target.indices { target[i] = 0 }
            return
        }
        cells.withUnsafeBufferPointer { cb in
            target.withUnsafeMutableBufferPointer { tb in
                let sxScale = Float(cols) / Float(n), syScale = Float(rows) / Float(n)
                for y in 0..<n {
                    let fy = (Float(y) + 0.5) * syScale - 0.5
                    let y0 = max(0, min(rows - 1, Int(floor(fy))))
                    let y1 = min(rows - 1, y0 + 1)
                    let ty = max(0, min(1, fy - Float(y0)))
                    for x in 0..<n {
                        let fx = (Float(x) + 0.5) * sxScale - 0.5
                        let x0 = max(0, min(cols - 1, Int(floor(fx))))
                        let x1 = min(cols - 1, x0 + 1)
                        let tx = max(0, min(1, fx - Float(x0)))
                        let a: Float = cb[y0 * cols + x0] & bit != 0 ? 0 : 1
                        let b: Float = cb[y0 * cols + x1] & bit != 0 ? 0 : 1
                        let c: Float = cb[y1 * cols + x0] & bit != 0 ? 0 : 1
                        let d: Float = cb[y1 * cols + x1] & bit != 0 ? 0 : 1
                        let top = a + (b - a) * tx, bottom = c + (d - c) * tx
                        tb[y * n + x] = top + (bottom - top) * ty
                    }
                }
            }
        }
        let radius = max(1, n / 64)
        blur(&target, temp: &temp, size: n, radius: radius)
        blur(&target, temp: &temp, size: n, radius: radius)
    }

    /// 横・縦の移動和ボックスぼかし（半径 r）。
    private static func blur(_ target: inout [Float], temp: inout [Float], size n: Int, radius r: Int) {
        let inv = 1 / Float(r * 2 + 1)
        target.withUnsafeMutableBufferPointer { t in
            temp.withUnsafeMutableBufferPointer { tmp in
                for y in 0..<n {
                    let row = y * n
                    var sum: Float = 0
                    for k in -r...r { sum += t[row + max(0, min(n - 1, k))] }
                    for x in 0..<n {
                        tmp[row + x] = sum * inv
                        sum += t[row + min(n - 1, x + r + 1)] - t[row + max(0, x - r)]
                    }
                }
                for x in 0..<n {
                    var sum: Float = 0
                    for k in -r...r { sum += tmp[max(0, min(n - 1, k)) * n + x] }
                    for y in 0..<n {
                        t[y * n + x] = sum * inv
                        sum += tmp[min(n - 1, y + r + 1) * n + x] - tmp[max(0, y - r) * n + x]
                    }
                }
            }
        }
    }

    /// 全体を一様な濃度にする（観戦の全体視点の準備描画: 0 = 霧なし）。次の目標は補間せずにそのまま採用する。
    mutating func reset(to v: Float) {
        for i in current.indices {
            current[i] = v
            target[i] = v
        }
        initialized = false
    }

    /// 現在値を目標へ k だけ近づける（0〜1）。戻り値 = 補間後に残った差の最大値。
    @discardableResult
    mutating func blend(_ k: Float) -> Float {
        let kk = max(0, min(1, k))
        var residual: Float = 0
        current.withUnsafeMutableBufferPointer { c in
            target.withUnsafeBufferPointer { t in
                for i in 0..<c.count {
                    let d = t[i] - c[i]
                    // 1/255 の 1/4 未満の差は詰め切る（いつまでも転送し続けない）
                    if abs(d) < 0.001 {
                        c[i] = t[i]
                    } else {
                        c[i] += d * kk
                        residual = max(residual, abs(t[i] - c[i]))
                    }
                }
            }
        }
        return residual
    }

    /// RGBA8 へ書き出す（RGB = 白、A = 不透明度。色はマテリアルの tint で決まる）。
    /// topDown = true で行 0 を sim y 最大側にする。
    func write(into bytes: UnsafeMutablePointer<UInt8>, maxAlpha: Float, topDown: Bool) {
        let n = size
        current.withUnsafeBufferPointer { c in
            for y in 0..<n {
                let srcRow = (topDown ? (n - 1 - y) : y) * n
                let dst = bytes + y * n * 4
                for x in 0..<n {
                    dst[x * 4] = 255
                    dst[x * 4 + 1] = 255
                    dst[x * 4 + 2] = 255
                    dst[x * 4 + 3] = UInt8(max(0, min(255, c[srcRow + x] * maxAlpha * 255)))
                }
            }
        }
    }

    /// sim 座標の霧濃度（テスト・デバッグ用）。
    func value(atSim p: Vec2, mapSize: Double) -> Float {
        let x = max(0, min(size - 1, Int(p.x / mapSize * Double(size))))
        let y = max(0, min(size - 1, Int(p.y / mapSize * Double(size))))
        return current[y * size + x]
    }
}

/// 霧の目標計算を背景キューで行う（計算用の配列を使い回し、表示側と受け渡しで入れ替える二重バッファ）。
final class FogWorker: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "velstria.fog", qos: .userInitiated)
    let size: Int
    private let lock = NSLock()
    /// 次の計算に使う配列（lock で守る）。
    private var spare: [[Float]] = []
    /// ぼかしの作業領域（直列キューの中だけで触る）。
    private var temp: [Float] = []

    init(size: Int) { self.size = size }

    /// 目標を背景キューで計算し、completion をメインスレッドで呼ぶ。
    func compute(cells: [UInt8], cols: Int, rows: Int, bit: UInt8, completion: @escaping @Sendable ([Float]) -> Void) {
        FogWorker.queue.async { [self] in
            var out = takeSpare()
            FogField.fillTarget(&out, temp: &temp, size: size, cells: cells, cols: cols, rows: rows, bit: bit)
            DispatchQueue.main.async { completion(out) }
        }
    }

    /// 表示側から戻った古い目標を次の計算に回す。
    func recycle(_ buffer: [Float]) {
        lock.lock()
        if spare.count < 2 { spare.append(buffer) }
        lock.unlock()
    }

    private func takeSpare() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return spare.popLast() ?? [Float](repeating: 1, count: size * size)
    }
}

@MainActor
final class FogOfWar {
    let entity: ModelEntity
    private var field: FogField
    /// 視点チーム（nil = 霧を出さない。観戦の全体視点）。
    private(set) var team: Team?
    private let worker: FogWorker
    /// 視点チームを切り替えた回数（切替前に投げた計算の結果を捨てる）。
    private var generation = 0
    /// 隠していた状態から出す: 最初の目標に補間なしで合わせ、転送してから板を見せる。
    private var revealPending = false
    /// 読み込み幕の裏で、透明な霧の板を描いている（観戦の全体視点でもパイプラインを準備しておく）。
    private(set) var isShowingWarmup = false
    /// 次に計算する目標は補間せずに合わせる（refreshImmediately）。
    private var snapNext = false
    /// 今の視点チームで目標を受け取った世代（切替後の最初の目標が届くまで古い）。
    private var receivedGeneration = -1

    /// 表示が今の視点チームの目標に落ち着いている（一時停止中に更新を続けるかの判定。視点なしは常に落ち着いている）。
    var isSettled: Bool {
        guard team != nil else { return true }
        return receivedGeneration == generation && !blending && !revealPending && !isComputing
    }
    private var accumulator: Float = 1
    /// 背景で計算中（結果が戻るまで次を投げない）。
    private(set) var isComputing = false
    /// 新しい目標を受け取った（CPU 転送の環境はこのときだけ進める）。
    private var retargetPending = false
    private var lowLevel: LowLevelTexture?
    private var texture: TextureResource?
    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    /// 転送用バッファ（GPU が前のフレームの転送で読んでいる間に書き換えないよう 3 本を順に使う）。
    private var staging: [MTLBuffer] = []
    private var stagingIndex = 0
    /// 補間がまだ目標に届いていない（転送を続ける）。
    private var blending = true
    /// GPU への転送の間引き（最大 30Hz）。RealityKit は転送の完了を待ってから描くため、毎フレーム転送すると詰まる。
    private var uploadAccumulator: Float = 1
    static let uploadInterval: Float = 1.0 / 30.0
    private var cpuBytes: [UInt8]
    /// 霧の最大不透明度。
    static let maxAlpha: Float = 0.64
    static let color = RGB(0.02, 0.035, 0.09)
    /// テクスチャの行 0 が sim y 最大側（画像と同じ上→下の並び）。
    static let topDown = true

    /// 表示中の濃度場（テスト用）。
    var displayedField: FogField { field }

    init?(team: Team?, size: Int) {
        self.team = team
        field = FogField(size: size)
        let n = field.size
        worker = FogWorker(size: n)
        cpuBytes = [UInt8](repeating: 255, count: n * n * 4)
        // 霧の板（地図全体、地面の少し上）
        let M = MapScene.mapMeters
        var d = MeshDescriptor(name: "fog")
        d.positions = MeshBuffers.Positions([[0, 0, 0], [M, 0, 0], [M, 0, -M], [0, 0, -M]])
        d.normals = MeshBuffers.Normals([[0, 1, 0], [0, 1, 0], [0, 1, 0], [0, 1, 0]])
        func uv(_ x: Float, _ y: Float) -> SIMD2<Float> { PaletteLayout.originBottomLeft ? SIMD2(x, y) : SIMD2(x, 1 - y) }
        d.textureCoordinates = MeshBuffers.TextureCoordinates([uv(0, 0), uv(1, 0), uv(1, 1), uv(0, 1)])
        d.primitives = .triangles([0, 1, 2, 0, 2, 3])
        guard let mesh = try? MeshResource.generate(from: [d]) else { return nil }
        AssetLedger.record(.mesh, "fog plane")
        entity = ModelEntity(mesh: mesh, materials: [])
        entity.name = "fog"
        entity.position.y = GroundLayer.fog
        OverlayOrder.apply(entity, OverlayOrder.fog)

        // GPU テクスチャ（LowLevelTexture）。使えない環境では CGImage 経由で置き換える
        if let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue() {
            let buffers = (0..<3).compactMap { _ in dev.makeBuffer(length: n * n * 4, options: .storageModeShared) }
            let desc = LowLevelTexture.Descriptor(textureType: .type2D, pixelFormat: .rgba8Unorm, width: n, height: n,
                                                  depth: 1, mipmapLevelCount: 1, textureUsage: [.shaderRead])
            if buffers.count == 3, let llt = try? LowLevelTexture(descriptor: desc), let tex = try? TextureResource(from: llt) {
                device = dev
                queue = q
                staging = buffers
                lowLevel = llt
                texture = tex
                AssetLedger.record(.texture, "fog \(n)² (LowLevelTexture)")
            }
        }
        if texture == nil, let img = FogOfWar.image(bytes: cpuBytes, size: n) {
            texture = try? TextureResource(image: img, options: .init(semantic: .raw, mipmapsMode: .none))
            AssetLedger.record(.texture, "fog \(n)² (CGImage)")
        }
        guard let texture else { return nil }
        var mat = UnlitMaterial(applyPostProcessToneMap: false)
        var t = MaterialParameters.Texture(texture)
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        t.sampler = .init(sd)
        // Unlit の透明度は色テクスチャの A × opacity（opacity テクスチャだけでは反映されない）
        mat.color = .init(tint: FogOfWar.color.uiColor, texture: t)
        mat.blending = .transparent(opacity: .init(floatLiteral: 1))
        mat.writesDepth = false
        AssetLedger.record(.material, "fog unlit")
        entity.model?.materials = [mat]
        entity.isEnabled = team != nil
    }

    /// 視点チームを切り替える（観戦者の視界: 全体 / Blue / Red）。nil で板を隠して計算も止める。
    func setTeam(_ t: Team?) {
        guard t != team else { return }
        let wasHidden = team == nil || !entity.isEnabled
        team = t
        generation &+= 1
        guard t != nil else {
            revealPending = false
            if !isShowingWarmup { entity.isEnabled = false }
            return
        }
        // 次の update ですぐ作り直す（0.1 秒ちょうど = 補間する側。隠していた時は revealPending で合わせる）
        accumulator = max(accumulator, 0.1)
        if wasHidden && !isShowingWarmup {
            revealPending = true
            entity.isEnabled = false
        }
    }

    /// 次の更新ですぐ目標を作り直し、補間せずに合わせる（シーク・再同期で状態が飛んだ時）。
    func refreshImmediately() {
        snapNext = true
        accumulator = max(accumulator, 1)
    }

    /// 読み込み幕の裏で透明な霧の板を描く（全体視点で始まる観戦でも、霧のマテリアルを幕の裏で一度描いておく）。
    func beginWarmupDisplay() {
        isShowingWarmup = true
        field.reset(to: 0)
        upload()
        entity.isEnabled = true
    }

    /// 幕が上がった: 視点チームが無ければ板を隠す（あれば通常どおり、次の目標に合わせて出す）。
    func endWarmupDisplay() {
        guard isShowingWarmup else { return }
        isShowingWarmup = false
        if team == nil {
            entity.isEnabled = false
        } else {
            revealPending = true
            entity.isEnabled = false
            accumulator = max(accumulator, 0.1)
        }
    }

    /// 目標の霧は 10Hz で作り直し（背景キュー）、表示は毎フレーム目標へ滑らかに近づける（時定数 1/8 秒 ≒ 従来の 10Hz × 55%）。
    func update(state: SimState, dt: Float) {
        guard let team else { return }
        accumulator += dt
        // 前の計算の結果待ちで遅れているだけの間は「久しぶり」に数えない
        if isComputing { accumulator = min(accumulator, 0.1) }
        if accumulator >= 0.1, !isComputing {
            // 久しぶりの計算（最初・長い中断の後）は補間せずに目標へ合わせる
            let first = accumulator > 0.5 || snapNext
            snapNext = false
            accumulator = 0
            isComputing = true
            let vision = state.vision
            let gen = generation
            worker.compute(cells: vision.cells, cols: vision.cols, rows: vision.rows, bit: team.visionBit) { [weak self] t in
                MainActor.assumeIsolated { self?.receive(t, first: first, generation: gen) }
            }
        }
        guard blending else { return }
        guard lowLevel != nil else {
            // GPU 転送が使えない環境（CGImage で差し替え）は重いので従来どおり 10Hz（新しい目標が来た時）だけ進める
            guard retargetPending else { return }
            retargetPending = false
            blending = field.blend(0.55) > 0
            upload()
            return
        }
        retargetPending = false
        blending = field.blend(1 - exp(-max(0, dt) * 8)) > 0
        uploadAccumulator += dt
        // 補間は毎フレーム進め、転送は最大 30Hz（目標に届いた瞬間は必ず転送して最終状態を出す）
        guard uploadAccumulator >= FogOfWar.uploadInterval || !blending else { return }
        uploadAccumulator = 0
        upload()
    }

    /// 背景で出来た目標を表示側と入れ替える（メインスレッド）。
    private func receive(_ target: [Float], first: Bool, generation gen: Int) {
        isComputing = false
        guard gen == generation, team != nil else {
            // 切替前の視点チームで作った目標は使わない（次の update ですぐ作り直す）
            worker.recycle(target)
            accumulator = max(accumulator, 0.1)
            return
        }
        receivedGeneration = gen
        var t = target
        field.swapTarget(&t)
        worker.recycle(t)
        if revealPending {
            revealPending = false
            field.blend(1)
            upload()
            blending = false
            retargetPending = false
            entity.isEnabled = true
            return
        }
        if first { field.blend(1) }
        blending = true
        retargetPending = true
    }

    private func upload() {
        let n = field.size
        if let llt = lowLevel, let queue, staging.count == 3, let cb = queue.makeCommandBuffer() {
            stagingIndex = (stagingIndex + 1) % staging.count
            let buf = staging[stagingIndex]
            field.write(into: buf.contents().bindMemory(to: UInt8.self, capacity: n * n * 4), maxAlpha: FogOfWar.maxAlpha,
                        topDown: FogOfWar.topDown)
            let dst = llt.replace(using: cb)
            if let blit = cb.makeBlitCommandEncoder() {
                blit.copy(from: buf, sourceOffset: 0, sourceBytesPerRow: n * 4, sourceBytesPerImage: n * n * 4,
                          sourceSize: MTLSize(width: n, height: n, depth: 1), to: dst, destinationSlice: 0,
                          destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                blit.endEncoding()
            }
            cb.commit()
        } else if let texture {
            cpuBytes.withUnsafeMutableBufferPointer { b in
                if let base = b.baseAddress {
                    field.write(into: base, maxAlpha: FogOfWar.maxAlpha, topDown: FogOfWar.topDown)
                }
            }
            if let img = FogOfWar.image(bytes: cpuBytes, size: n) {
                AssetLedger.record(.texture, "fog replace (CGImage fallback)")
                try? texture.replace(withImage: img, options: .init(semantic: .raw, mipmapsMode: .none))
            }
        }
    }

    private static func image(bytes: [UInt8], size n: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
