import CoreGraphics
import Foundation
import Metal
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。戦場の霧（非観戦）。
// state.vision.cells（60×60）→ 双線形で N×N へ拡大 → ボックスぼかし 2 回 → 時間方向に補間、を 10Hz で行い、
// 地面すぐ上の半透明な板の不透明度テクスチャ（LowLevelTexture）へ転送する。

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
        let n = size
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
        blur(radius: radius)
        blur(radius: radius)
        if !initialized {
            current = target
            initialized = true
        }
    }

    /// 横・縦の移動和ボックスぼかし（半径 r）。
    private mutating func blur(radius r: Int) {
        let n = size
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

    /// 現在値を目標へ k だけ近づける（0〜1）。
    mutating func blend(_ k: Float) {
        let kk = max(0, min(1, k))
        current.withUnsafeMutableBufferPointer { c in
            target.withUnsafeBufferPointer { t in
                for i in 0..<c.count { c[i] += (t[i] - c[i]) * kk }
            }
        }
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

@MainActor
final class FogOfWar {
    let entity: ModelEntity
    private var field: FogField
    private let team: Team
    private var accumulator: Float = 1
    private var lowLevel: LowLevelTexture?
    private var texture: TextureResource?
    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var staging: MTLBuffer?
    private var cpuBytes: [UInt8]
    /// 霧の最大不透明度。
    static let maxAlpha: Float = 0.64
    static let color = RGB(0.02, 0.035, 0.09)
    /// テクスチャの行 0 が sim y 最大側（画像と同じ上→下の並び）。
    static let topDown = true

    init?(team: Team, size: Int) {
        self.team = team
        field = FogField(size: size)
        let n = field.size
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
        entity = ModelEntity(mesh: mesh, materials: [])
        entity.name = "fog"
        entity.position.y = 0.1
        OverlayOrder.apply(entity, OverlayOrder.fog)

        // GPU テクスチャ（LowLevelTexture）。使えない環境では CGImage 経由で置き換える
        if let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue(),
           let buf = dev.makeBuffer(length: n * n * 4, options: .storageModeShared) {
            let desc = LowLevelTexture.Descriptor(textureType: .type2D, pixelFormat: .rgba8Unorm, width: n, height: n,
                                                  depth: 1, mipmapLevelCount: 1, textureUsage: [.shaderRead])
            if let llt = try? LowLevelTexture(descriptor: desc), let tex = try? TextureResource(from: llt) {
                device = dev
                queue = q
                staging = buf
                lowLevel = llt
                texture = tex
            }
        }
        if texture == nil, let img = FogOfWar.image(bytes: cpuBytes, size: n) {
            texture = try? TextureResource(image: img, options: .init(semantic: .raw, mipmapsMode: .none))
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
        entity.model?.materials = [mat]
    }

    /// 10Hz で霧を更新する。
    func update(state: SimState, dt: Float) {
        accumulator += dt
        guard accumulator >= 0.1 else { return }
        let k: Float = accumulator > 0.5 ? 1 : 0.55
        accumulator = 0
        field.computeTarget(cells: state.vision.cells, cols: state.vision.cols, rows: state.vision.rows, bit: team.visionBit)
        field.blend(k)
        upload()
    }

    private func upload() {
        let n = field.size
        if let llt = lowLevel, let queue, let staging, let cb = queue.makeCommandBuffer() {
            field.write(into: staging.contents().bindMemory(to: UInt8.self, capacity: n * n * 4), maxAlpha: FogOfWar.maxAlpha,
                        topDown: FogOfWar.topDown)
            let dst = llt.replace(using: cb)
            if let blit = cb.makeBlitCommandEncoder() {
                blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: n * 4, sourceBytesPerImage: n * n * 4,
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
