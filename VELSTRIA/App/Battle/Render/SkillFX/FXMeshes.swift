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
        // 法線: Unlit は使わないが、加算・模様の CustomMaterial（FXShaders.metal）の描画には要る
        let normals: [SIMD3<Float>]
        switch s {
        case .disc, .arc, .band:
            normals = Array(repeating: [0, 1, 0], count: pos.count)
        case .wall, .billboard:
            normals = Array(repeating: [0, 0, 1], count: pos.count)
        case .cylinder, .funnel, .spire:
            normals = pos.map { p in
                let h = SIMD3<Float>(p.x, 0, p.z)
                return simd_length(h) > 1e-5 ? simd_normalize(h) : [0, 1, 0]
            }
        case .dome, .sphere:
            normals = pos.map { simd_length($0) > 1e-5 ? simd_normalize($0) : [0, 1, 0] }
        }
        // 裏面は材質の faceCulling = .none で描く
        var d = MeshDescriptor(name: "fx_\(s.rawValue)")
        d.positions = MeshBuffers.Positions(pos)
        d.normals = MeshBuffers.Normals(normals)
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

    var built: [any Material] {
        let plain: [any Material] = cache.keys.sorted { "\($0)" < "\($1)" }.compactMap { cache[$0] }
        return plain + shaded.keys.sorted { "\($0)" < "\($1)" }.compactMap { shaded[$0] }
    }
    var count: Int { cache.count + shaded.count }

    // MARK: 加算・流れる模様（FXShaders.metal の CustomMaterial）

    /// 加算の明るさの段階。フェードは段階の材質を差し替えて落とす（OpacityComponent が加算に効くかに頼らない）。
    nonisolated static let addLevels = 10

    struct ShadedKey: Hashable {
        var base: Key
        var blend: FXBlend
        var flow: FlowKey?
        /// 加算の明るさの段階（1〜addLevels）。アルファ合成は addLevels（OpacityComponent で落とす）。
        var level: Int
    }

    struct FlowKey: Hashable {
        var pattern: FXFlowTex
        var scroll: SIMD2<Int16>
        var tiling: Int16
        var strength: Int16
        var erosion: Int16
        var er: UInt8, eg: UInt8, eb: UInt8
    }

    private var shaded: [ShadedKey: CustomMaterial] = [:]
    private var flowTextures: [FXFlowTex: TextureResource] = [:]
    /// Program が無く、加算・模様のメッシュを従来のアルファ合成の材質で出した回数（材質を作るとき。計測・テスト用）。
    private(set) var fallbacks = 0

    /// このメッシュに使う材質の鍵。従来の材質（アルファ合成・模様なし）は nil。
    static func shadedKey(_ m: FXMesh, palette: FXPalette, level: Int) -> ShadedKey? {
        guard m.blend == .add || m.flow != nil else { return nil }
        let base = key(m.tex, palette.rgb(m.tint))
        let flow = m.flow.map { f -> FlowKey in
            func q(_ v: Float) -> Int16 { Int16(max(-30000, min(30000, (v * 100).rounded()))) }
            let e = key(nil, palette.rgb(f.edge))
            return FlowKey(pattern: f.pattern, scroll: SIMD2(q(f.scroll.x), q(f.scroll.y)), tiling: q(f.tiling),
                           strength: q(f.strength), erosion: q(f.erosion), er: e.r, eg: e.g, eb: e.b)
        }
        let lv = m.blend == .add ? max(1, min(addLevels, level)) : addLevels
        return ShadedKey(base: base, blend: m.blend, flow: flow, level: lv)
    }

    /// 加算の不透明度 a（0〜1）→ 明るさの段階（0 = 出さない）。
    nonisolated static func addLevel(_ a: Float) -> Int {
        guard a > 0.001 else { return 0 }
        return max(1, min(addLevels, Int((a * Float(addLevels)).rounded(.up))))
    }

    /// メッシュの材質（加算・模様は CustomMaterial、それ以外は従来の Unlit）。Program が無ければ従来の材質で代える。
    func material(for m: FXMesh, palette: FXPalette, level: Int = FXMaterialLibrary.addLevels) -> any Material {
        guard let k = FXMaterialLibrary.shadedKey(m, palette: palette, level: level) else {
            return material(m.tex, palette.rgb(m.tint))
        }
        if let c = shaded[k] { return c }
        guard let program = k.blend == .add ? FXPrograms.add : FXPrograms.alpha else {
            fallbacks += 1
            return material(m.tex, palette.rgb(m.tint))
        }
        AssetLedger.record(.material, "fx \(k.blend.rawValue) \(m.tex?.rawValue ?? "solid")\(k.flow == nil ? "" : " flow") L\(k.level)")
        var c = CustomMaterial(program: program)
        let tint = UIColor(red: CGFloat(k.base.r) / 255, green: CGFloat(k.base.g) / 255, blue: CGFloat(k.base.b) / 255, alpha: 1)
        let shape = textures.texture(m.tex ?? .glow)
        if let shape {
            c.baseColor = .init(tint: tint, texture: .init(shape))
        } else {
            c.baseColor = .init(tint: tint, texture: nil)
        }
        if let f = k.flow {
            c.emissiveColor = .init(color: UIColor(red: CGFloat(f.er) / 255, green: CGFloat(f.eg) / 255, blue: CGFloat(f.eb) / 255,
                                                   alpha: 1), texture: nil)
            c.metallic = .init(floatLiteral: Float(f.strength) / 100)
            c.custom.value = SIMD4(Float(f.scroll.x) / 100, Float(f.scroll.y) / 100, Float(f.tiling) / 100, Float(f.erosion) / 100)
            if let t = flowTexture(f.pattern) { c.custom.texture = .init(t) }
        } else {
            c.emissiveColor = .init(color: tint, texture: nil)
            c.metallic = .init(floatLiteral: 0)
            c.custom.value = SIMD4(0, 0, 1, 0)
            if let shape { c.custom.texture = .init(shape) }
        }
        c.roughness = .init(floatLiteral: Float(k.level) / Float(FXMaterialLibrary.addLevels))
        if k.blend == .alpha { c.blending = .transparent(opacity: .init(floatLiteral: 1)) }
        c.writesDepth = false
        c.faceCulling = .none
        shaded[k] = c
        return c
    }

    /// 加算のメッシュは全ての明るさの段階、それ以外は 1 つを先に作る（読み込み幕の裏）。
    func prewarm(_ m: FXMesh, palette: FXPalette) {
        if m.blend == .add {
            for lv in 1...FXMaterialLibrary.addLevels { _ = material(for: m, palette: palette, level: lv) }
        } else {
            _ = material(for: m, palette: palette)
        }
    }

    private func flowTexture(_ p: FXFlowTex) -> TextureResource? {
        if let t = flowTextures[p] { return t }
        guard let img = FXFlowTex.image(p),
              let t = try? TextureResource(image: img, options: .init(semantic: .raw)) else { return nil }
        AssetLedger.record(.texture, "fx flow \(p.rawValue)")
        flowTextures[p] = t
        return t
    }
}
