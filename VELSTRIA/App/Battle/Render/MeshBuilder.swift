import Foundation
import RealityKit
import simd

// 担当: battle-renderer。
// ローポリ手続きメッシュの組み立て。形状を変換付きで 1 つのバッファへ追記し、MeshResource を 1 つ作る
// （= 1 ドローコール）。色はパレット UV（RenderPalette.swift）。面法線のフラットシェーディングを基本にする。

struct MeshBuilder {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var uvs: [SIMD2<Float>] = []
    private(set) var indices: [UInt32] = []

    init(reserve: Int = 0) {
        if reserve > 0 {
            positions.reserveCapacity(reserve)
            normals.reserveCapacity(reserve)
            uvs.reserveCapacity(reserve)
            indices.reserveCapacity(reserve * 2)
        }
    }

    var isEmpty: Bool { indices.isEmpty }
    var vertexCount: Int { positions.count }
    var triangleCount: Int { indices.count / 3 }

    // MARK: 基本

    /// 反時計回り（表から見て）の三角形をフラットシェーディングで追加する。
    mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                           uv ua: SIMD2<Float>, _ ub: SIMD2<Float>, _ uc: SIMD2<Float>) {
        var n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        if len < 1e-9 { return }
        n /= len
        let base = UInt32(positions.count)
        positions.append(a); positions.append(b); positions.append(c)
        normals.append(n); normals.append(n); normals.append(n)
        uvs.append(ua); uvs.append(ub); uvs.append(uc)
        indices.append(base); indices.append(base + 1); indices.append(base + 2)
    }

    mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, uv: SIMD2<Float>) {
        triangle(a, b, c, uv: uv, uv, uv)
    }

    /// 四角形 a-b-c-d（反時計回り）。
    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                       uv ua: SIMD2<Float>, _ ub: SIMD2<Float>, _ uc: SIMD2<Float>, _ ud: SIMD2<Float>) {
        triangle(a, b, c, uv: ua, ub, uc)
        triangle(a, c, d, uv: ua, uc, ud)
    }

    /// 頂点法線を指定した三角形（滑らかなシェーディング）。
    mutating func smoothTriangle(_ p: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>),
                                 normals n: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>),
                                 uvs u: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)) {
        let base = UInt32(positions.count)
        positions.append(p.0); positions.append(p.1); positions.append(p.2)
        normals.append(n.0); normals.append(n.1); normals.append(n.2)
        uvs.append(u.0); uvs.append(u.1); uvs.append(u.2)
        indices.append(base); indices.append(base + 1); indices.append(base + 2)
    }

    /// 別のビルダーを変換して追記する。
    mutating func append(_ other: MeshBuilder, transform m: simd_float4x4 = matrix_identity_float4x4) {
        let base = UInt32(positions.count)
        let nm = MeshBuilder.normalMatrix(m)
        for p in other.positions { positions.append(MeshBuilder.apply(m, p)) }
        for n in other.normals { normals.append(simd_normalize(nm * n)) }
        uvs.append(contentsOf: other.uvs)
        for i in other.indices { indices.append(base + i) }
    }

    // MARK: 形状（すべて変換 m を適用。ローカル原点は形状の底面中心）

    /// 直方体（底面中心が原点）。
    mutating func box(size s: SIMD3<Float>, color: PaletteColor, transform m: simd_float4x4 = matrix_identity_float4x4) {
        let hx = s.x / 2, hz = s.z / 2
        let c: [SIMD3<Float>] = [
            [-hx, 0, -hz], [hx, 0, -hz], [hx, 0, hz], [-hx, 0, hz],
            [-hx, s.y, -hz], [hx, s.y, -hz], [hx, s.y, hz], [-hx, s.y, hz],
        ].map { MeshBuilder.apply(m, $0) }
        let lo = PaletteLayout.uv(color, t: 0), hi = PaletteLayout.uv(color, t: 1)
        // 上面・底面
        quad(c[7], c[6], c[5], c[4], uv: hi, hi, hi, hi)
        quad(c[0], c[1], c[2], c[3], uv: lo, lo, lo, lo)
        // 側面（下 = lo、上 = hi）
        quad(c[3], c[2], c[6], c[7], uv: lo, lo, hi, hi)
        quad(c[1], c[0], c[4], c[5], uv: lo, lo, hi, hi)
        quad(c[2], c[1], c[5], c[6], uv: lo, lo, hi, hi)
        quad(c[0], c[3], c[7], c[4], uv: lo, lo, hi, hi)
    }

    /// 円錐台（角柱）。segments 角形。上半径 0 で角錐。
    mutating func frustum(bottomRadius r0: Float, topRadius r1: Float, height h: Float, segments: Int,
                          color: PaletteColor, capTop: Bool = true, capBottom: Bool = false,
                          smooth: Bool = false, phase: Float = 0,
                          transform m: simd_float4x4 = matrix_identity_float4x4) {
        let n = max(3, segments)
        let lo = PaletteLayout.uv(color, t: 0), hi = PaletteLayout.uv(color, t: 1)
        var ring0: [SIMD3<Float>] = [], ring1: [SIMD3<Float>] = []
        ring0.reserveCapacity(n); ring1.reserveCapacity(n)
        for k in 0..<n {
            let a = phase + Float(k) / Float(n) * 2 * .pi
            let d = SIMD3<Float>(cos(a), 0, -sin(a))
            ring0.append(MeshBuilder.apply(m, d * r0))
            ring1.append(MeshBuilder.apply(m, d * r1 + SIMD3(0, h, 0)))
        }
        let apexTop = MeshBuilder.apply(m, SIMD3(0, h, 0))
        let centerBottom = MeshBuilder.apply(m, .zero)
        if smooth {
            let nm = MeshBuilder.normalMatrix(m)
            let slope = (r0 - r1) / max(h, 1e-4)
            for k in 0..<n {
                let k2 = (k + 1) % n
                let a0 = phase + Float(k) / Float(n) * 2 * .pi
                let a1 = phase + Float(k2) / Float(n) * 2 * .pi
                let n0 = simd_normalize(nm * simd_normalize(SIMD3(cos(a0), slope, -sin(a0))))
                let n1 = simd_normalize(nm * simd_normalize(SIMD3(cos(a1), slope, -sin(a1))))
                smoothTriangle((ring0[k], ring0[k2], ring1[k2]), normals: (n0, n1, n1), uvs: (lo, lo, hi))
                if r1 > 1e-4 {
                    smoothTriangle((ring0[k], ring1[k2], ring1[k]), normals: (n0, n1, n0), uvs: (lo, hi, hi))
                }
            }
        } else {
            for k in 0..<n {
                let k2 = (k + 1) % n
                if r1 > 1e-4 {
                    quad(ring0[k], ring0[k2], ring1[k2], ring1[k], uv: lo, lo, hi, hi)
                } else {
                    triangle(ring0[k], ring0[k2], apexTop, uv: lo, lo, hi)
                }
            }
        }
        if capTop && r1 > 1e-4 {
            for k in 0..<n { triangle(apexTop, ring1[k], ring1[(k + 1) % n], uv: hi) }
        }
        if capBottom {
            for k in 0..<n { triangle(centerBottom, ring0[(k + 1) % n], ring0[k], uv: lo) }
        }
    }

    /// 円柱。
    mutating func cylinder(radius r: Float, height h: Float, segments: Int, color: PaletteColor,
                           smooth: Bool = false, transform m: simd_float4x4 = matrix_identity_float4x4) {
        frustum(bottomRadius: r, topRadius: r, height: h, segments: segments, color: color, smooth: smooth, transform: m)
    }

    /// UV 球（中心が原点）。低ポリ（rings × segments）。
    mutating func sphere(radius r: Float, segments: Int = 10, rings: Int = 6, color: PaletteColor,
                         smooth: Bool = true, transform m: simd_float4x4 = matrix_identity_float4x4) {
        let nm = MeshBuilder.normalMatrix(m)
        func point(_ i: Int, _ j: Int) -> (SIMD3<Float>, SIMD3<Float>, Float) {
            let theta = Float(i) / Float(rings) * .pi
            let phi = Float(j) / Float(segments) * 2 * .pi
            let d = SIMD3<Float>(sin(theta) * cos(phi), cos(theta), -sin(theta) * sin(phi))
            return (MeshBuilder.apply(m, d * r), simd_normalize(nm * d), 1 - Float(i) / Float(rings))
        }
        for i in 0..<rings {
            for j in 0..<segments {
                let a = point(i, j), b = point(i + 1, j), c = point(i + 1, j + 1), d = point(i, j + 1)
                let ua = PaletteLayout.uv(color, t: a.2), ub = PaletteLayout.uv(color, t: b.2)
                let uc = PaletteLayout.uv(color, t: c.2), ud = PaletteLayout.uv(color, t: d.2)
                // 極では片方の三角形が潰れるので省く
                if smooth {
                    if i != rings - 1 { smoothTriangle((a.0, b.0, c.0), normals: (a.1, b.1, c.1), uvs: (ua, ub, uc)) }
                    if i != 0 { smoothTriangle((a.0, c.0, d.0), normals: (a.1, c.1, d.1), uvs: (ua, uc, ud)) }
                } else {
                    if i != rings - 1 { triangle(a.0, b.0, c.0, uv: ua, ub, uc) }
                    if i != 0 { triangle(a.0, c.0, d.0, uv: ua, uc, ud) }
                }
            }
        }
    }

    /// 歪ませた正二十面体（岩・樹冠）。中心が原点。jitter は頂点の半径揺らぎ（0〜1）。
    mutating func blob(radius r: Float, jitter: Float, seed: UInt64, color: PaletteColor,
                       subdivide: Bool = false, transform m: simd_float4x4 = matrix_identity_float4x4) {
        var (verts, faces) = MeshBuilder.icosahedron()
        if subdivide { (verts, faces) = MeshBuilder.subdivide(verts, faces) }
        var rng = RenderRNG(seed: seed)
        let scaled = verts.map { v -> SIMD3<Float> in v * r * (1 + (rng.nextFloat() * 2 - 1) * jitter) }
        let minY = scaled.map(\.y).min() ?? -r
        let maxY = scaled.map(\.y).max() ?? r
        let span = max(1e-4, maxY - minY)
        let world = scaled.map { MeshBuilder.apply(m, $0) }
        for f in faces {
            let ta = (scaled[f.0].y - minY) / span, tb = (scaled[f.1].y - minY) / span, tc = (scaled[f.2].y - minY) / span
            triangle(world[f.0], world[f.1], world[f.2],
                     uv: PaletteLayout.uv(color, t: ta), PaletteLayout.uv(color, t: tb), PaletteLayout.uv(color, t: tc))
        }
    }

    /// 縦長の八面体（結晶）。底が原点、高さ h。
    mutating func crystal(radius r: Float, height h: Float, sides: Int = 4, waist: Float = 0.45,
                          color: PaletteColor, transform m: simd_float4x4 = matrix_identity_float4x4) {
        let n = max(3, sides)
        let bottom = MeshBuilder.apply(m, .zero)
        let top = MeshBuilder.apply(m, SIMD3(0, h, 0))
        var ring: [SIMD3<Float>] = []
        for k in 0..<n {
            let a = Float(k) / Float(n) * 2 * .pi
            ring.append(MeshBuilder.apply(m, SIMD3(cos(a) * r, h * waist, -sin(a) * r)))
        }
        let lo = PaletteLayout.uv(color, t: 0), mid = PaletteLayout.uv(color, t: waist), hi = PaletteLayout.uv(color, t: 1)
        for k in 0..<n {
            let k2 = (k + 1) % n
            triangle(ring[k], ring[k2], top, uv: mid, mid, hi)
            triangle(ring[k2], ring[k], bottom, uv: mid, mid, lo)
        }
    }

    /// トーラス（XZ 平面、中心が原点）。
    mutating func torus(majorRadius R: Float, minorRadius r: Float, segments: Int = 24, sides: Int = 6,
                        color: PaletteColor, transform m: simd_float4x4 = matrix_identity_float4x4) {
        let nm = MeshBuilder.normalMatrix(m)
        func point(_ i: Int, _ j: Int) -> (SIMD3<Float>, SIMD3<Float>, Float) {
            let u = Float(i) / Float(segments) * 2 * .pi
            let v = Float(j) / Float(sides) * 2 * .pi
            let center = SIMD3<Float>(cos(u) * R, 0, -sin(u) * R)
            let dir = SIMD3<Float>(cos(u) * cos(v), sin(v), -sin(u) * cos(v))
            return (MeshBuilder.apply(m, center + dir * r), simd_normalize(nm * dir), (sin(v) + 1) / 2)
        }
        for i in 0..<segments {
            for j in 0..<sides {
                let a = point(i, j), b = point(i + 1, j), c = point(i + 1, j + 1), d = point(i, j + 1)
                let ua = PaletteLayout.uv(color, t: a.2), ub = PaletteLayout.uv(color, t: b.2)
                let uc = PaletteLayout.uv(color, t: c.2), ud = PaletteLayout.uv(color, t: d.2)
                smoothTriangle((a.0, b.0, c.0), normals: (a.1, b.1, c.1), uvs: (ua, ub, uc))
                smoothTriangle((a.0, c.0, d.0), normals: (a.1, c.1, d.1), uvs: (ua, uc, ud))
            }
        }
    }

    /// 平らな円環（XZ 平面、上向き）。内半径 0 で円盤。
    mutating func annulus(inner r0: Float, outer r1: Float, segments: Int = 48, y: Float = 0,
                          startAngle: Float = 0, sweep: Float = 2 * .pi,
                          color: PaletteColor, transform m: simd_float4x4 = matrix_identity_float4x4) {
        let steps = max(3, segments)
        let uvi = PaletteLayout.uv(color, t: 0), uvo = PaletteLayout.uv(color, t: 1)
        for k in 0..<steps {
            let a0 = startAngle + sweep * Float(k) / Float(steps)
            let a1 = startAngle + sweep * Float(k + 1) / Float(steps)
            let d0 = SIMD3<Float>(cos(a0), 0, -sin(a0)), d1 = SIMD3<Float>(cos(a1), 0, -sin(a1))
            let o0 = MeshBuilder.apply(m, d0 * r1 + SIMD3(0, y, 0)), o1 = MeshBuilder.apply(m, d1 * r1 + SIMD3(0, y, 0))
            if r0 < 1e-4 {
                let c = MeshBuilder.apply(m, SIMD3(0, y, 0))
                triangle(c, o0, o1, uv: uvi, uvo, uvo)
            } else {
                let i0 = MeshBuilder.apply(m, d0 * r0 + SIMD3(0, y, 0)), i1 = MeshBuilder.apply(m, d1 * r0 + SIMD3(0, y, 0))
                quad(i0, o0, o1, i1, uv: uvi, uvo, uvo, uvi)
            }
        }
    }

    /// 上向きの矩形（XZ 平面、中心が原点）。
    mutating func flatRect(width w: Float, depth d: Float, y: Float = 0, color: PaletteColor,
                           transform m: simd_float4x4 = matrix_identity_float4x4) {
        let a = MeshBuilder.apply(m, SIMD3(-w / 2, y, d / 2)), b = MeshBuilder.apply(m, SIMD3(w / 2, y, d / 2))
        let c = MeshBuilder.apply(m, SIMD3(w / 2, y, -d / 2)), e = MeshBuilder.apply(m, SIMD3(-w / 2, y, -d / 2))
        let lo = PaletteLayout.uv(color, t: 0), hi = PaletteLayout.uv(color, t: 1)
        quad(a, b, c, e, uv: lo, lo, hi, hi)
    }

    /// 星形（XZ 平面の厚みある星、中心が原点）。
    mutating func star(outer r1: Float, inner r0: Float, thickness t: Float, points: Int = 5,
                       color: PaletteColor, transform m: simd_float4x4 = matrix_identity_float4x4) {
        let n = points * 2
        var top: [SIMD3<Float>] = [], bottom: [SIMD3<Float>] = []
        for k in 0..<n {
            let a = Float(k) / Float(n) * 2 * .pi + .pi / 2
            let r = k % 2 == 0 ? r1 : r0
            top.append(MeshBuilder.apply(m, SIMD3(cos(a) * r, t / 2, -sin(a) * r)))
            bottom.append(MeshBuilder.apply(m, SIMD3(cos(a) * r, -t / 2, -sin(a) * r)))
        }
        let ct = MeshBuilder.apply(m, SIMD3(0, t / 2, 0)), cb = MeshBuilder.apply(m, SIMD3(0, -t / 2, 0))
        let uv = PaletteLayout.uv(color, t: 1)
        for k in 0..<n {
            let k2 = (k + 1) % n
            triangle(ct, top[k], top[k2], uv: uv)
            triangle(cb, bottom[k2], bottom[k], uv: uv)
            quad(bottom[k], bottom[k2], top[k2], top[k], uv: uv, uv, uv, uv)
        }
    }

    // MARK: 出力

    func makeDescriptor(name: String) -> MeshDescriptor {
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        d.primitives = .triangles(indices)
        return d
    }

    @MainActor
    func makeMesh(name: String) -> MeshResource? {
        guard !isEmpty else { return nil }
        return try? MeshResource.generate(from: [makeDescriptor(name: name)])
    }

    // MARK: 変換ユーティリティ

    @inline(__always)
    static func apply(_ m: simd_float4x4, _ p: SIMD3<Float>) -> SIMD3<Float> {
        let v = m * SIMD4<Float>(p, 1)
        return SIMD3(v.x, v.y, v.z)
    }

    static func normalMatrix(_ m: simd_float4x4) -> simd_float3x3 {
        let u = simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                              SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                              SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        return u.inverse.transpose
    }

    static func icosahedron() -> ([SIMD3<Float>], [(Int, Int, Int)]) {
        let t: Float = (1 + Float(5).squareRoot()) / 2
        let v: [SIMD3<Float>] = [
            [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
            [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
            [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
        ].map { simd_normalize($0) }
        let f: [(Int, Int, Int)] = [
            (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
            (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
            (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
            (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
        ]
        return (v, f)
    }

    static func subdivide(_ v: [SIMD3<Float>], _ f: [(Int, Int, Int)]) -> ([SIMD3<Float>], [(Int, Int, Int)]) {
        var verts = v
        var faces: [(Int, Int, Int)] = []
        var cache: [UInt64: Int] = [:]
        func mid(_ a: Int, _ b: Int) -> Int {
            let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
            if let i = cache[key] { return i }
            verts.append(simd_normalize((verts[a] + verts[b]) / 2))
            cache[key] = verts.count - 1
            return verts.count - 1
        }
        for (a, b, c) in f {
            let ab = mid(a, b), bc = mid(b, c), ca = mid(c, a)
            faces.append((a, ab, ca)); faces.append((b, bc, ab)); faces.append((c, ca, bc)); faces.append((ab, bc, ca))
        }
        return (verts, faces)
    }
}

// MARK: - 変換ヘルパー

enum MX {
    static func t(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(x, y, z, 1)
        return m
    }

    static func t(_ p: SIMD3<Float>) -> simd_float4x4 { t(p.x, p.y, p.z) }

    static func s(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(x, y, z, 1))
    }

    static func s(_ k: Float) -> simd_float4x4 { s(k, k, k) }

    static func ry(_ a: Float) -> simd_float4x4 { simd_float4x4(simd_quatf(angle: a, axis: [0, 1, 0])) }
    static func rx(_ a: Float) -> simd_float4x4 { simd_float4x4(simd_quatf(angle: a, axis: [1, 0, 0])) }
    static func rz(_ a: Float) -> simd_float4x4 { simd_float4x4(simd_quatf(angle: a, axis: [0, 0, 1])) }

    /// 平行移動 · Y 回転 · 拡大（よく使う順序）。
    static func trs(_ p: SIMD3<Float>, ry a: Float = 0, s k: SIMD3<Float> = [1, 1, 1]) -> simd_float4x4 {
        t(p) * ry(a) * s(k.x, k.y, k.z)
    }
}

/// 描画専用の軽量乱数（見た目の揺らぎ用。シミュレーションの rng とは独立）。
struct RenderRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// [0, 1)
    mutating func nextFloat() -> Float { Float(next() >> 40) / Float(1 << 24) }

    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * nextFloat() }

    mutating func chance(_ p: Float) -> Bool { nextFloat() < p }
}
