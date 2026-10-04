import Foundation
import RealityKit
import simd

// 担当: battle-renderer（ステージ）。ステージのメッシュを CPU 側で組み立てる入れ物と、LowLevelMesh への書き出し。
// 頂点 = 位置 float3 + 法線 snorm8×4 + UV unorm16×2 + 色 unorm8×4（24 バイト）。
// 色は CustomMaterial のシェーダーが読む: rgb = 色味（0.5 が中立、シェーダーで ×2）または草花の色そのもの、
// a = 風で揺れる重み（0 は動かない）。docs/STAGE.md の 3.4 を参照。

struct StageVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var uv: SIMD2<Float>
    var color: SIMD4<UInt8>
}

/// 結合前の頂点・添字。背景スレッドで作り、main actor で `makeMesh` する。
struct StageMeshBuffer: Sendable {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var uvs: [SIMD2<Float>] = []
    private(set) var colors: [SIMD4<UInt8>] = []
    private(set) var indices: [UInt32] = []
    private(set) var boundsMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    private(set) var boundsMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

    init(reserveVertices n: Int = 0) {
        if n > 0 {
            positions.reserveCapacity(n)
            normals.reserveCapacity(n)
            uvs.reserveCapacity(n)
            colors.reserveCapacity(n)
            indices.reserveCapacity(n * 2)
        }
    }

    var vertexCount: Int { positions.count }
    var triangleCount: Int { indices.count / 3 }
    var isEmpty: Bool { indices.isEmpty }

    @discardableResult
    mutating func addVertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float> = .zero,
                            _ c: SIMD4<UInt8> = SIMD4(128, 128, 128, 0)) -> UInt32 {
        let i = UInt32(positions.count)
        positions.append(p)
        normals.append(n)
        uvs.append(uv)
        colors.append(c)
        boundsMin = simd_min(boundsMin, p)
        boundsMax = simd_max(boundsMax, p)
        return i
    }

    mutating func addTriangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        indices.append(a)
        indices.append(b)
        indices.append(c)
    }

    /// 小物メッシュを変換して追加する（法線は回転・拡大の逆転置で変換）。
    mutating func append(_ prop: StagePropMesh, transform m: simd_float4x4, color: SIMD4<UInt8>,
                         windWeight: ((SIMD3<Float>) -> Float)? = nil) {
        let base = UInt32(positions.count)
        let nm = MeshBuilder.normalMatrix(m)
        let count = prop.positions.count
        positions.reserveCapacity(positions.count + count)
        for k in 0..<count {
            let lp = prop.positions[k]
            let p4 = m * SIMD4(lp, 1)
            let p = SIMD3(p4.x, p4.y, p4.z)
            var c = color
            if let windWeight {
                c.w = UInt8(max(0, min(255, (windWeight(lp) * 255).rounded())))
            }
            addVertex(p, simd_normalize(nm * prop.normals[k]), prop.uvs[k], c)
        }
        indices.reserveCapacity(indices.count + prop.indices.count)
        for i in prop.indices { indices.append(base &+ i) }
    }

    mutating func append(_ other: StageMeshBuffer) {
        let base = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        uvs += other.uvs
        colors += other.colors
        for i in other.indices { indices.append(base &+ i) }
        if !other.isEmpty {
            boundsMin = simd_min(boundsMin, other.boundsMin)
            boundsMax = simd_max(boundsMax, other.boundsMax)
        }
    }

    /// 両面の細い板（草の葉）: 根元から先へ segments 段の帯。片側ずつ別の頂点で法線を分ける。
    mutating func blade(base p0: SIMD3<Float>, direction dir: SIMD3<Float>, side: SIMD3<Float>, height: Float,
                        width: Float, bend: Float, segments: Int, colors ramp: (Float) -> SIMD4<UInt8>) {
        var left: [UInt32] = [], right: [UInt32] = [], left2: [UInt32] = [], right2: [UInt32] = []
        let up = simd_normalize(dir)
        let face = simd_normalize(simd_cross(side, up))
        for s in 0...segments {
            let t = Float(s) / Float(segments)
            // 先へ行くほど細く、曲がる（bend は face 方向の倒れ）
            let w = width * (1 - t * 0.92) * 0.5
            let center = p0 + up * (height * t) + face * (bend * t * t * height)
            let c = ramp(t)
            let n = simd_normalize(face + up * 0.25)
            left.append(addVertex(center - side * w, n, .zero, c))
            right.append(addVertex(center + side * w, n, .zero, c))
            left2.append(addVertex(center - side * w, -n, .zero, c))
            right2.append(addVertex(center + side * w, -n, .zero, c))
        }
        for s in 0..<segments {
            addTriangle(left[s], right[s], right[s + 1])
            addTriangle(left[s], right[s + 1], left[s + 1])
            addTriangle(left2[s], right2[s + 1], right2[s])
            addTriangle(left2[s], left2[s + 1], right2[s + 1])
        }
    }
}

extension StageMeshBuffer {
    /// RealityKit のメッシュにする（main actor）。頂点が無ければ nil。
    @MainActor
    func makeMesh() -> MeshResource? {
        guard !isEmpty else { return nil }
        let stride = 24
        let useShort = positions.count <= Int(UInt16.max)
        var d = LowLevelMesh.Descriptor()
        d.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: 0),
            .init(semantic: .normal, format: .char4Normalized, offset: 12),
            .init(semantic: .uv0, format: .ushort2Normalized, offset: 16),
            .init(semantic: .color, format: .uchar4Normalized, offset: 20),
        ]
        d.vertexLayouts = [.init(bufferIndex: 0, bufferStride: stride)]
        d.vertexCapacity = positions.count
        d.indexCapacity = indices.count
        d.indexType = useShort ? .uint16 : .uint32
        guard let mesh = try? LowLevelMesh(descriptor: d) else { return nil }
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            guard let dst = raw.baseAddress else { return }
            for k in 0..<positions.count {
                let o = dst + k * stride
                let p = positions[k]
                o.storeBytes(of: p.x, toByteOffset: 0, as: Float.self)
                o.storeBytes(of: p.y, toByteOffset: 4, as: Float.self)
                o.storeBytes(of: p.z, toByteOffset: 8, as: Float.self)
                let n = normals[k]
                let packed = SIMD4<Int8>(Int8(max(-127, min(127, (n.x * 127).rounded()))),
                                         Int8(max(-127, min(127, (n.y * 127).rounded()))),
                                         Int8(max(-127, min(127, (n.z * 127).rounded()))), 0)
                o.storeBytes(of: packed, toByteOffset: 12, as: SIMD4<Int8>.self)
                let uv = uvs[k]
                let pu = SIMD2<UInt16>(UInt16(max(0, min(65535, (uv.x * 65535).rounded()))),
                                       UInt16(max(0, min(65535, (uv.y * 65535).rounded()))))
                o.storeBytes(of: pu, toByteOffset: 16, as: SIMD2<UInt16>.self)
                o.storeBytes(of: colors[k], toByteOffset: 20, as: SIMD4<UInt8>.self)
            }
        }
        mesh.withUnsafeMutableIndices { raw in
            if useShort {
                let dst = raw.bindMemory(to: UInt16.self)
                for (k, i) in indices.enumerated() { dst[k] = UInt16(truncatingIfNeeded: i) }
            } else {
                let dst = raw.bindMemory(to: UInt32.self)
                for (k, i) in indices.enumerated() { dst[k] = i }
            }
        }
        mesh.parts.replaceAll([LowLevelMesh.Part(indexCount: indices.count, topology: .triangle,
                                                 bounds: BoundingBox(min: boundsMin, max: boundsMax))])
        return try? MeshResource(from: mesh)
    }
}

/// 色を 0〜1 の float から頂点色へ。
@inline(__always)
func stageColor(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 0) -> SIMD4<UInt8> {
    func q(_ v: Float) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
    return SIMD4(q(r), q(g), q(b), q(a))
}
