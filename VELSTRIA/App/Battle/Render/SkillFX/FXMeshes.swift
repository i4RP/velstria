import Foundation
import RealityKit
import UIKit

// 担当: battle-renderer（スキル演出）。演出用の単位メッシュ（UV 付き）と、画像 × 色の Unlit 材質のキャッシュ。
// どちらも読み込み幕の裏で作り切る（AssetLedger の .mesh / .material）。
// 材質は半透明（深度を書かない）・両面・トーンマップなし。色は画像（白 + アルファ）に掛ける。
// メッシュは LowLevelMesh（頂点の並び 0 = 位置・法線・UV、並び 1 = 頂点の色）。プールの枠ごとに 1 つ持ち（FXMeshSlot）、
// 頂点の色に 1 体ごとの値（g = コマ送りのコマ、b = 溶けの進み、a = 模様の種）を書く。材質は共有のまま、コマ・溶けは
// シェーダー（FXShaders.metal）が頂点の色から読む。形は手続き（build）か Blender の模型（FXModelFile、fxm_<名前>.bin）。

/// 演出のメッシュの形（頂点の位置・法線・UV と三角形の添字）。
struct FXGeometry {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var uvs: [SIMD2<Float>]
    var indices: [UInt32]
    var boundsMin: SIMD3<Float>
    var boundsMax: SIMD3<Float>

    init(positions: [SIMD3<Float>], normals: [SIMD3<Float>], uvs: [SIMD2<Float>], indices: [UInt32]) {
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.indices = indices
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for p in positions {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        if positions.isEmpty {
            lo = .zero
            hi = .zero
        }
        boundsMin = lo
        boundsMax = hi
    }
}

/// Blender の模型（tools/vfx_assets/blender/fx_common.py の write_fxm）。little endian:
/// "FXM1"・頂点数 u32・添字数 u32・予約 u32・境界 min/max（f32 × 6）・頂点 × n（位置 3・法線 3・UV 2 の f32 = 32 バイト）・添字 u32 × m。
enum FXModelFile {
    static let headerBytes = 40
    static let vertexBytes = 32

    static func load(_ s: FXShape, bundle: Bundle = .main) -> FXGeometry? {
        guard let name = s.modelResource, let url = bundle.url(forResource: name, withExtension: "bin"),
              let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> FXGeometry? {
        guard data.count >= headerBytes else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> FXGeometry? in
            guard raw.count >= headerBytes, raw[0] == 0x46, raw[1] == 0x58, raw[2] == 0x4D, raw[3] == 0x31 else { return nil }
            func u32(_ o: Int) -> UInt32 { UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
            func f32(_ o: Int) -> Float { Float(bitPattern: u32(o)) }
            let n = Int(u32(4)), ni = Int(u32(8))
            guard n > 0, ni > 0, ni % 3 == 0, raw.count >= headerBytes + n * vertexBytes + ni * 4 else { return nil }
            var pos: [SIMD3<Float>] = [], nor: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = []
            pos.reserveCapacity(n)
            nor.reserveCapacity(n)
            uv.reserveCapacity(n)
            for k in 0..<n {
                let o = headerBytes + k * vertexBytes
                pos.append(SIMD3(f32(o), f32(o + 4), f32(o + 8)))
                nor.append(SIMD3(f32(o + 12), f32(o + 16), f32(o + 20)))
                uv.append(SIMD2(f32(o + 24), f32(o + 28)))
            }
            var idx: [UInt32] = []
            idx.reserveCapacity(ni)
            let base = headerBytes + n * vertexBytes
            for k in 0..<ni {
                let i = u32(base + k * 4)
                guard Int(i) < n else { return nil }
                idx.append(i)
            }
            return FXGeometry(positions: pos, normals: nor, uvs: uv, indices: idx)
        }
    }
}

/// プールの 1 枠のメッシュ（LowLevelMesh。頂点の色を 1 体ごとに書き換える）。
@MainActor
final class FXMeshSlot {
    let mesh: LowLevelMesh
    let resource: MeshResource
    let vertexCount: Int
    /// いま頂点の色に書いてある値（r = 予約 255、g = コマ、b = 溶けの進み、a = 模様の種）。
    private(set) var params: SIMD4<UInt8>

    /// 既定の頂点の色（コマ 0・溶け無し・種 0）。
    nonisolated static let rest = SIMD4<UInt8>(255, 0, 0, 0)
    /// 頂点の並び 0 の 1 頂点のバイト数（位置 float3・法線 float3・UV float2）。
    nonisolated static let stride = 32

    private init(mesh: LowLevelMesh, resource: MeshResource, vertexCount: Int) {
        self.mesh = mesh
        self.resource = resource
        self.vertexCount = vertexCount
        params = FXMeshSlot.rest
    }

    static func make(_ g: FXGeometry) -> FXMeshSlot? {
        let n = g.positions.count
        guard n > 0, g.normals.count == n, g.uvs.count == n, !g.indices.isEmpty else { return nil }
        var d = LowLevelMesh.Descriptor()
        d.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: 0),
            .init(semantic: .normal, format: .float3, offset: 12),
            .init(semantic: .uv0, format: .float2, offset: 24),
            .init(semantic: .color, format: .uchar4Normalized, layoutIndex: 1, offset: 0),
        ]
        d.vertexLayouts = [.init(bufferIndex: 0, bufferStride: stride), .init(bufferIndex: 1, bufferStride: 4)]
        d.vertexCapacity = n
        d.indexCapacity = g.indices.count
        d.indexType = .uint32
        guard let ll = try? LowLevelMesh(descriptor: d) else { return nil }
        ll.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            guard let dst = raw.baseAddress else { return }
            for k in 0..<n {
                let o = dst + k * stride
                let p = g.positions[k], q = g.normals[k], t = g.uvs[k]
                o.storeBytes(of: p.x, toByteOffset: 0, as: Float.self)
                o.storeBytes(of: p.y, toByteOffset: 4, as: Float.self)
                o.storeBytes(of: p.z, toByteOffset: 8, as: Float.self)
                o.storeBytes(of: q.x, toByteOffset: 12, as: Float.self)
                o.storeBytes(of: q.y, toByteOffset: 16, as: Float.self)
                o.storeBytes(of: q.z, toByteOffset: 20, as: Float.self)
                o.storeBytes(of: t.x, toByteOffset: 24, as: Float.self)
                o.storeBytes(of: t.y, toByteOffset: 28, as: Float.self)
            }
        }
        ll.withUnsafeMutableBytes(bufferIndex: 1) { raw in
            let dst = raw.bindMemory(to: SIMD4<UInt8>.self)
            for k in 0..<min(n, dst.count) { dst[k] = FXMeshSlot.rest }
        }
        ll.withUnsafeMutableIndices { raw in
            let dst = raw.bindMemory(to: UInt32.self)
            for (k, i) in g.indices.enumerated() where k < dst.count { dst[k] = i }
        }
        ll.parts.replaceAll([LowLevelMesh.Part(indexCount: g.indices.count, topology: .triangle,
                                               bounds: BoundingBox(min: g.boundsMin, max: g.boundsMax))])
        guard let resource = try? MeshResource(from: ll) else { return nil }
        return FXMeshSlot(mesh: ll, resource: resource, vertexCount: n)
    }

    /// 頂点の色を書き換える（変わった時だけ。頂点の並び 1 だけを書き直す）。
    func set(_ p: SIMD4<UInt8>) {
        guard p != params else { return }
        params = p
        let n = vertexCount
        mesh.replaceUnsafeMutableBytes(bufferIndex: 1) { raw in
            let dst = raw.bindMemory(to: SIMD4<UInt8>.self)
            for k in 0..<min(n, dst.count) { dst[k] = p }
        }
    }
}

@MainActor
final class FXMeshLibrary {
    private var geometries: [FXShape: FXGeometry] = [:]
    private var shared: [FXShape: FXMeshSlot] = [:]
    /// 読めなかった模型（バンドルに無い・壊れている）。その形の合図は出さない。
    private(set) var missing: Set<FXShape> = []

    /// 形の頂点（手続きの形は作り、模型はバンドルから読む）。
    func geometry(_ s: FXShape) -> FXGeometry? {
        if let g = geometries[s] { return g }
        guard !missing.contains(s) else { return nil }
        guard let g = s.isModel ? FXModelFile.load(s) : FXMeshLibrary.build(s) else {
            missing.insert(s)
            return nil
        }
        geometries[s] = g
        return g
    }

    /// 共通のメッシュ（読み込み幕の裏の陳列・撮影の確認用。頂点の色は既定値）。プールの枠は makeSlot。
    func mesh(_ s: FXShape) -> MeshResource? {
        if let m = shared[s] { return m.resource }
        guard let g = geometry(s), let slot = FXMeshSlot.make(g) else { return nil }
        AssetLedger.record(.mesh, "fx \(s.rawValue)")
        shared[s] = slot
        return slot.resource
    }

    /// プールの 1 枠のメッシュ（頂点の色を 1 体ごとに書き換える）。
    func makeSlot(_ s: FXShape) -> FXMeshSlot? {
        guard let g = geometry(s), let slot = FXMeshSlot.make(g) else { return nil }
        AssetLedger.record(.mesh, "fx slot \(s.rawValue)")
        return slot
    }

    var built: [MeshResource] { FXShape.allCases.compactMap { shared[$0]?.resource } }

    /// 手続きの形を全て作る。模型は試合のレシピが使うものだけ（SkillFXPlayer.prewarm が mesh(_:) を呼ぶ）。
    func prewarm() { for s in FXShape.allCases where !s.isModel { _ = mesh(s) } }

    private static func build(_ s: FXShape) -> FXGeometry? {
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
        case .crescent, .ringLip, .twister, .pillar2, .bladeRing, .burstDome, .starCross, .shardRing, .sk025s1, .sk025s2, .sk025ult, .sk026s1, .sk026s2, .sk026ult, .sk027s1, .sk027s2, .sk027ult, .sk028s1, .sk028s2, .sk028ult, .sk029s1, .sk029s2, .sk029ult, .sk030s1, .sk030s2, .sk030ult, .sk031s1, .sk031s2, .sk031ult, .sk032s1, .sk032s2, .sk032ult, .sk033s1, .sk033s2, .sk033ult, .sk034s1, .sk034s2, .sk034ult, .sk025s1b, .sk025s2b, .sk025ultb, .sk026s1b, .sk026s2b, .sk026ultb, .sk027s1b, .sk027s2b, .sk027ultb, .sk028s1b, .sk028s2b, .sk028ultb, .sk029s1b, .sk029s2b, .sk029ultb, .sk030s1b, .sk030s2b, .sk030ultb, .sk032s1b, .sk032s2b, .sk032ultb, .sk033s1b, .sk033s2b, .sk033ultb, .sk034s1b, .sk034s2b, .sk034ultb:
            // 模型（FXModelFile が読む）
            return nil
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
        default:
            normals = pos.map { simd_length($0) > 1e-5 ? simd_normalize($0) : [0, 1, 0] }
        }
        // 裏面は材質の faceCulling = .none で描く
        return FXGeometry(positions: pos, normals: normals, uvs: uv, indices: idx)
    }
}

/// 画像 × 色の Unlit 材質（半透明・深度を書かない・トーンマップなし）。
@MainActor
final class FXMaterialLibrary {
    private let textures: FXTextureLibrary
    private let sheets: FXSheetLibrary
    private var cache: [Key: UnlitMaterial] = [:]

    struct Key: Hashable {
        var tex: FXTex?
        var r: UInt8, g: UInt8, b: UInt8
        /// 深度を読まない（FXMesh.onTop）。
        var onTop = false
    }

    init(textures: FXTextureLibrary, sheets: FXSheetLibrary) {
        self.textures = textures
        self.sheets = sheets
    }

    static func key(_ tex: FXTex?, _ c: RGB, onTop: Bool = false) -> Key {
        func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return Key(tex: tex, r: q(c.r), g: q(c.g), b: q(c.b), onTop: onTop)
    }

    func material(_ tex: FXTex?, _ c: RGB, onTop: Bool = false) -> UnlitMaterial {
        let k = FXMaterialLibrary.key(tex, c, onTop: onTop)
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
        if onTop { m.readsDepth = false }
        m.faceCulling = .none
        cache[k] = m
        return m
    }

    var built: [any Material] {
        let plain: [any Material] = cache.keys.sorted { "\($0)" < "\($1)" }.compactMap { cache[$0] }
        return plain + shaded.keys.sorted { "\($0)" < "\($1)" }.compactMap { shaded[$0] }
    }
    var count: Int { cache.count + shaded.count }

    // MARK: 加算・流れる模様・コマ送り・溶け（FXShaders.metal の CustomMaterial）

    /// 加算の明るさの段階。フェードは段階の材質を差し替えて落とす（OpacityComponent が加算に効くかに頼らない）。
    nonisolated static let addLevels = 10

    struct ShadedKey: Hashable {
        var base: Key
        var blend: FXBlend
        var flow: FlowKey?
        /// 加算の明るさの段階（1〜addLevels）。アルファ合成は addLevels（OpacityComponent で落とす）。
        var level: Int
        /// コマ送りの画像（nil = base.tex の 1 枚絵）。
        var sheet: FXSheet? = nil
        /// 溶け（nil = 無し）。
        var dissolve: DissolveKey? = nil
    }

    struct FlowKey: Hashable {
        var pattern: FXFlowTex
        var scroll: SIMD2<Int16>
        var tiling: Int16
        var strength: Int16
        var erosion: Int16
        var er: UInt8, eg: UInt8, eb: UInt8
    }

    struct DissolveKey: Hashable {
        var pattern: FXFlowTex
        var tiling: Int16
        var width: Int16
        var er: UInt8, eg: UInt8, eb: UInt8
    }

    private var shaded: [ShadedKey: CustomMaterial] = [:]
    private var flowTextures: [FXFlowTex: TextureResource] = [:]
    /// Program が無く、加算・模様のメッシュを従来のアルファ合成の材質で出した回数（材質を作るとき。計測・テスト用）。
    private(set) var fallbacks = 0
    /// false = 加算・模様の材質を新しく作らない（幕までに作り切れなかった試合。SkillFXPlayer.sealShadedMaterials）。
    /// 作ってある材質はそのまま使い、無いものは従来の材質で代える。
    var createsShaded = true

    /// このメッシュに使う材質の鍵。従来の材質（アルファ合成・模様なし・コマ送りなし・溶けなし）は nil。
    static func shadedKey(_ m: FXMesh, palette: FXPalette, level: Int) -> ShadedKey? {
        guard m.blend == .add || m.flow != nil || m.sheet != nil || m.dissolve != nil else { return nil }
        func q(_ v: Float) -> Int16 { Int16(max(-30000, min(30000, (v * 100).rounded()))) }
        let base = key(m.tex, palette.rgb(m.tint), onTop: m.onTop)
        let flow = m.flow.map { f -> FlowKey in
            let e = key(nil, palette.rgb(f.edge))
            return FlowKey(pattern: f.pattern, scroll: SIMD2(q(f.scroll.x), q(f.scroll.y)), tiling: q(f.tiling),
                           strength: q(f.strength), erosion: q(f.erosion), er: e.r, eg: e.g, eb: e.b)
        }
        let dissolve = m.dissolve.map { d -> DissolveKey in
            let e = key(nil, palette.rgb(d.edge))
            return DissolveKey(pattern: d.pattern, tiling: q(d.tiling), width: q(d.width), er: e.r, eg: e.g, eb: e.b)
        }
        let lv = m.blend == .add ? max(1, min(addLevels, level)) : addLevels
        return ShadedKey(base: base, blend: m.blend, flow: flow, level: lv, sheet: m.sheet, dissolve: dissolve)
    }

    /// 加算の不透明度 a（0〜1）→ 明るさの段階（0 = 出さない）。
    nonisolated static func addLevel(_ a: Float) -> Int {
        guard a > 0.001 else { return 0 }
        return max(1, min(addLevels, Int((a * Float(addLevels)).rounded(.up))))
    }

    /// メッシュの材質（加算・模様・コマ送り・溶けは CustomMaterial、それ以外は従来の Unlit）。Program が無ければ従来の材質で代える
    /// （コマ送りは tex の 1 枚絵、溶けは不透明度だけ）。
    func material(for m: FXMesh, palette: FXPalette, level: Int = FXMaterialLibrary.addLevels) -> any Material {
        guard let k = FXMaterialLibrary.shadedKey(m, palette: palette, level: level) else {
            return material(m.tex, palette.rgb(m.tint), onTop: m.onTop)
        }
        if let c = shaded[k] { return c }
        guard createsShaded, let program = k.blend == .add ? FXPrograms.add : FXPrograms.alpha else {
            fallbacks += 1
            return material(m.tex, palette.rgb(m.tint), onTop: m.onTop)
        }
        let sheetTexture = m.sheet.flatMap { sheets.texture($0, additive: m.blend == .add) }
        if m.sheet != nil && sheetTexture == nil {
            // シートが読めない（作っていない）: 1 枚絵で出す
            fallbacks += 1
            return material(m.tex, palette.rgb(m.tint), onTop: m.onTop)
        }
        var label = "fx \(k.blend.rawValue) "
        label += m.sheet?.rawValue ?? m.tex?.rawValue ?? "solid"
        if k.flow != nil { label += " flow" }
        if k.dissolve != nil { label += " dissolve" }
        label += " L\(k.level)"
        AssetLedger.record(.material, label)
        var c = CustomMaterial(program: program)
        let tint = UIColor(red: CGFloat(k.base.r) / 255, green: CGFloat(k.base.g) / 255, blue: CGFloat(k.base.b) / 255, alpha: 1)
        let shape = sheetTexture ?? textures.texture(m.tex ?? .glow)
        if let shape {
            c.baseColor = .init(tint: tint, texture: .init(shape))
        } else {
            c.baseColor = .init(tint: tint, texture: nil)
        }
        // コマ送りの格子（シェーダーは specular = 1 / 列、clearcoat = 1 / 行 が 0 より大きければコマを切り出す）
        if let s = m.sheet {
            c.specular = .init(floatLiteral: 1 / Float(s.columns))
            c.clearcoat = .init(floatLiteral: 1 / Float(s.rows))
        } else {
            c.specular = .init(floatLiteral: 0)
            c.clearcoat = .init(floatLiteral: 0)
        }
        // 溶けの縁の光の幅（clearcoatRoughness。0 = 光らない）
        c.clearcoatRoughness = .init(floatLiteral: k.dissolve.map { Float($0.width) / 100 } ?? 0)
        if let f = k.flow {
            c.emissiveColor = .init(color: UIColor(red: CGFloat(f.er) / 255, green: CGFloat(f.eg) / 255, blue: CGFloat(f.eb) / 255,
                                                   alpha: 1), texture: nil)
            c.metallic = .init(floatLiteral: Float(f.strength) / 100)
            c.custom.value = SIMD4(Float(f.scroll.x) / 100, Float(f.scroll.y) / 100, Float(f.tiling) / 100, Float(f.erosion) / 100)
            if let t = flowTexture(f.pattern) { c.custom.texture = .init(t) }
        } else if let d = k.dissolve {
            // 模様なしの溶け: 模様の画像と繰り返しだけを渡す（強さ 0 = 色は変えない）
            c.emissiveColor = .init(color: UIColor(red: CGFloat(d.er) / 255, green: CGFloat(d.eg) / 255, blue: CGFloat(d.eb) / 255,
                                                   alpha: 1), texture: nil)
            c.metallic = .init(floatLiteral: 0)
            c.custom.value = SIMD4(0, 0, Float(d.tiling) / 100, 0)
            if let t = flowTexture(d.pattern) { c.custom.texture = .init(t) }
        } else {
            c.emissiveColor = .init(color: tint, texture: nil)
            c.metallic = .init(floatLiteral: 0)
            c.custom.value = SIMD4(0, 0, 1, 0)
            if let shape { c.custom.texture = .init(shape) }
        }
        c.roughness = .init(floatLiteral: Float(k.level) / Float(FXMaterialLibrary.addLevels))
        if k.blend == .alpha { c.blending = .transparent(opacity: .init(floatLiteral: 1)) }
        c.writesDepth = false
        if k.base.onTop { c.readsDepth = false }
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
