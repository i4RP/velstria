import Foundation
import RealityKit
import UIKit

// 担当: battle-renderer（スキル演出）。演出用の単位メッシュ（UV 付き）と、画像 × 色の Unlit 材質のキャッシュ。
// どちらも読み込み幕の裏で作り切る（AssetLedger の .mesh / .material）。
// 材質は半透明（深度を書かない）・両面・トーンマップなし。色は画像（白 + アルファ）に掛ける。

@MainActor
final class FXMeshLibrary {
    private var cache: [FXShape: MeshResource] = [:]

    func mesh(_ s: FXShape) -> MeshResource? {
        if let m = cache[s] { return m }
        guard let m = FXMeshLibrary.build(s) else { return nil }
        AssetLedger.record(.mesh, "fx \(s.rawValue)")
        cache[s] = m
        return m
    }

    var built: [MeshResource] { FXShape.allCases.compactMap { cache[$0] } }

    func prewarm() { for s in FXShape.allCases { _ = mesh(s) } }

    private static func build(_ s: FXShape) -> MeshResource? {
        var pos: [SIMD3<Float>] = []
        var uv: [SIMD2<Float>] = []
        var idx: [UInt32] = []
        func quad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) { idx += [a, b, c, a, c, d] }
        switch s {
        case .disc:
            // 画像の上（v = 1）= 前（-Z）
            pos = [[-0.5, 0, 0.5], [0.5, 0, 0.5], [0.5, 0, -0.5], [-0.5, 0, -0.5]]
            uv = [[0, 0], [1, 0], [1, 1], [0, 1]]
            quad(0, 1, 2, 3)
        case .wall:
            pos = [[-0.5, 0, 0], [0.5, 0, 0], [0.5, 1, 0], [-0.5, 1, 0]]
            uv = [[0, 0], [1, 0], [1, 1], [0, 1]]
            quad(0, 1, 2, 3)
        case .billboard:
            pos = [[-0.5, -0.5, 0], [0.5, -0.5, 0], [0.5, 0.5, 0], [-0.5, 0.5, 0]]
            uv = [[0, 0], [1, 0], [1, 1], [0, 1]]
            quad(0, 1, 2, 3)
        case .cylinder, .funnel, .spire:
            let (r0, r1): (Float, Float) = s == .cylinder ? (1, 1) : (s == .funnel ? (0.35, 1) : (1, 0.08))
            let n = 28
            for i in 0...n {
                let u = Float(i) / Float(n)
                let a = u * 2 * .pi
                pos.append([cos(a) * r0, 0, sin(a) * r0])
                pos.append([cos(a) * r1, 1, sin(a) * r1])
                uv.append([u * 2, 0])
                uv.append([u * 2, 1])
            }
            for i in 0..<n {
                let a = UInt32(i * 2)
                quad(a, a + 2, a + 3, a + 1)
            }
        case .dome, .sphere:
            let rings = s == .dome ? 10 : 16
            let n = 24
            let top: Float = .pi / 2
            let bottom: Float = s == .dome ? 0 : -.pi / 2
            for j in 0...rings {
                let v = Float(j) / Float(rings)
                let lat = bottom + (top - bottom) * v
                for i in 0...n {
                    let u = Float(i) / Float(n)
                    let a = u * 2 * .pi
                    pos.append([cos(lat) * cos(a), sin(lat), cos(lat) * sin(a)])
                    uv.append([u * 2, v])
                }
            }
            let w = UInt32(n + 1)
            for j in 0..<rings {
                for i in 0..<n {
                    let a = UInt32(j) * w + UInt32(i)
                    quad(a, a + 1, a + w + 1, a + w)
                }
            }
        case .arc, .band:
            // 前（-Z）を中心に ±90°（arc）または全周（band）。画像の下（v = 0）= 外縁、横（u）= 弧に沿う
            let inner: Float = s == .arc ? 0.72 : 0.8
            let span: Float = s == .arc ? .pi : 2 * .pi
            let n = s == .arc ? 32 : 48
            for i in 0...n {
                let u = Float(i) / Float(n)
                let a = -.pi / 2 - span / 2 + span * u
                let d = SIMD3<Float>(cos(a), 0, sin(a))
                pos.append(d)
                pos.append(d * inner)
                uv.append([s == .arc ? u : u * 3, 0])
                uv.append([s == .arc ? u : u * 3, 1])
            }
            for i in 0..<n {
                let a = UInt32(i * 2)
                quad(a, a + 2, a + 3, a + 1)
            }
        }
        // 裏面は材質の faceCulling = .none で描く
        var d = MeshDescriptor(name: "fx_\(s.rawValue)")
        d.positions = MeshBuffers.Positions(pos)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }
}

/// 画像 × 色の Unlit 材質（半透明・深度を書かない・トーンマップなし）。
@MainActor
final class FXMaterialLibrary {
    private let textures: FXTextureLibrary
    private var cache: [Key: UnlitMaterial] = [:]

    struct Key: Hashable {
        var tex: FXTex?
        var r: UInt8, g: UInt8, b: UInt8
    }

    init(textures: FXTextureLibrary) {
        self.textures = textures
    }

    static func key(_ tex: FXTex?, _ c: RGB) -> Key {
        func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return Key(tex: tex, r: q(c.r), g: q(c.g), b: q(c.b))
    }

    func material(_ tex: FXTex?, _ c: RGB) -> UnlitMaterial {
        let k = FXMaterialLibrary.key(tex, c)
        if let m = cache[k] { return m }
        AssetLedger.record(.material, "fx \(tex?.rawValue ?? "solid")")
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        let tint = UIColor(red: CGFloat(k.r) / 255, green: CGFloat(k.g) / 255, blue: CGFloat(k.b) / 255, alpha: 1)
        if let tex, let t = textures.texture(tex) {
            m.color = .init(tint: tint, texture: .init(t))
        } else {
            m.color = .init(tint: tint)
        }
        m.blending = .transparent(opacity: .init(floatLiteral: 1))
        m.writesDepth = false
        m.faceCulling = .none
        cache[k] = m
        return m
    }

    var built: [UnlitMaterial] { cache.keys.sorted { "\($0)" < "\($1)" }.compactMap { cache[$0] } }
    var count: Int { cache.count }
}
