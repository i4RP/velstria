import Foundation
import RealityKit
import simd

// 担当: hero-models。ヒーロー用の手続きメッシュ生成。
// 素片（球・円錐台・角丸箱・回転体・押し出し・結晶・布）を生成し、骨ごとに 1 メッシュへ結合する。
// 1 骨 = 1 エンティティ（面ごとにマテリアル番号）にすることで、エンティティ数と描画単位を抑える。

// MARK: - 変換ヘルパ

typealias V3 = SIMD3<Float>
typealias V2 = SIMD2<Float>

let qIdentity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

@inline(__always) func rx(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [1, 0, 0]) }
@inline(__always) func ry(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 1, 0]) }
@inline(__always) func rz(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 0, 1]) }

/// 平行移動・回転・拡縮から 4x4 行列を作る。
func trs(_ t: V3, _ r: simd_quatf = qIdentity, _ s: V3 = [1, 1, 1]) -> simd_float4x4 {
    let rm = simd_float3x3(r)
    return simd_float4x4(columns: (
        SIMD4(rm.columns.0 * s.x, 0),
        SIMD4(rm.columns.1 * s.y, 0),
        SIMD4(rm.columns.2 * s.z, 0),
        SIMD4(t, 1)))
}

/// +Y を dir へ向ける回転（反平行でも破綻しない）。
func rotationFromY(to dir: V3) -> simd_quatf {
    let d = simd_normalize(dir)
    let y = V3(0, 1, 0)
    let c = simd_dot(y, d)
    if c > 0.9999 { return qIdentity }
    if c < -0.9999 { return rx(.pi) }
    return simd_quatf(from: y, to: d)
}

// MARK: - 素片

/// 素片メッシュ（原点基準の単位形状）。
struct MeshTemplate {
    var positions: [V3] = []
    var normals: [V3] = []
    var indices: [UInt32] = []

    /// 三角形の巻き順を頂点法線に合わせる（外向き反時計回り）。
    mutating func orientToNormals() {
        var i = 0
        while i + 2 < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            let fn = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            if simd_dot(fn, normals[a] + normals[b] + normals[c]) < 0 { indices.swapAt(i + 1, i + 2) }
            i += 3
        }
    }

    fileprivate mutating func quad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) {
        indices.append(contentsOf: [a, b, c, a, c, d])
    }

    /// 単位球（lat は -π/2...π/2）。
    static func sphere(segments: Int, rings: Int, latFrom: Float = -.pi / 2, latTo: Float = .pi / 2) -> MeshTemplate {
        var t = MeshTemplate()
        for r in 0...rings {
            let lat = latFrom + (latTo - latFrom) * Float(r) / Float(rings)
            let y = sin(lat), cr = cos(lat)
            for s in 0...segments {
                let lon = 2 * Float.pi * Float(s) / Float(segments)
                let n = V3(cr * cos(lon), y, cr * sin(lon))
                t.positions.append(n)
                t.normals.append(n)
            }
        }
        let w = UInt32(segments + 1)
        for r in 0..<rings {
            for s in 0..<segments {
                let a = UInt32(r) * w + UInt32(s)
                t.quad(a, a + 1, a + w + 1, a + w)
            }
        }
        if latFrom > -.pi / 2 + 0.01 {
            // 下側の蓋
            t.appendDisc(y: sin(latFrom), radius: cos(latFrom), segments: segments, up: false)
        }
        t.orientToNormals()
        return t
    }

    fileprivate mutating func appendDisc(y: Float, radius: Float, segments: Int, up: Bool) {
        guard radius > 0.0001 else { return }
        let n = V3(0, up ? 1 : -1, 0)
        let c = UInt32(positions.count)
        positions.append(V3(0, y, 0))
        normals.append(n)
        for s in 0...segments {
            let lon = 2 * Float.pi * Float(s) / Float(segments)
            positions.append(V3(radius * cos(lon), y, radius * sin(lon)))
            normals.append(n)
        }
        for s in 0..<UInt32(segments) {
            indices.append(contentsOf: [c, c + 1 + s, c + 2 + s])
        }
    }

    /// y=0 で半径 r0、y=1 で半径 r1 の円錐台。
    static func frustum(r0: Float, r1: Float, segments: Int, caps: Bool = true) -> MeshTemplate {
        var t = MeshTemplate()
        let slope = r0 - r1
        for ring in 0...1 {
            let r = ring == 0 ? r0 : r1
            for s in 0...segments {
                let lon = 2 * Float.pi * Float(s) / Float(segments)
                let cx = cos(lon), cz = sin(lon)
                t.positions.append(V3(r * cx, Float(ring), r * cz))
                t.normals.append(simd_normalize(V3(cx, slope, cz)))
            }
        }
        let w = UInt32(segments + 1)
        for s in 0..<UInt32(segments) { t.quad(s, s + 1, s + 1 + w, s + w) }
        if caps {
            t.appendDisc(y: 0, radius: r0, segments: segments, up: false)
            t.appendDisc(y: 1, radius: r1, segments: segments, up: true)
        }
        t.orientToNormals()
        return t
    }

    /// トーラス（主半径 1、管半径 k、Y 軸まわり）。arc で部分円弧。
    static func torus(minor k: Float, segments: Int, sides: Int, arc: Float = 2 * .pi) -> MeshTemplate {
        var t = MeshTemplate()
        for s in 0...segments {
            let u = arc * Float(s) / Float(segments)
            let cu = cos(u), su = sin(u)
            for j in 0...sides {
                let v = 2 * Float.pi * Float(j) / Float(sides)
                let n = V3(cos(v) * cu, sin(v), cos(v) * su)
                t.positions.append(V3(cu, 0, su) + n * k)
                t.normals.append(n)
            }
        }
        let w = UInt32(sides + 1)
        for s in 0..<UInt32(segments) {
            for j in 0..<UInt32(sides) {
                let a = s * w + j
                t.quad(a, a + 1, a + w + 1, a + w)
            }
        }
        t.orientToNormals()
        return t
    }

    /// 直方体（角は鋭角・面ごとの法線）。
    static func box(_ size: V3) -> MeshTemplate {
        var t = MeshTemplate()
        let h = size / 2
        for axis in 0..<3 {
            for sign: Float in [-1, 1] {
                let u = (axis + 1) % 3, v = (axis + 2) % 3
                var n = V3.zero
                n[axis] = sign
                let base = UInt32(t.positions.count)
                for (a, b) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
                    var p = V3.zero
                    p[axis] = sign * h[axis]
                    p[u] = a * h[u]
                    p[v] = b * h[v]
                    t.positions.append(p)
                    t.normals.append(n)
                }
                t.quad(base, base + 1, base + 2, base + 3)
            }
        }
        t.orientToNormals()
        return t
    }

    /// 角丸直方体（箱と球のミンコフスキー和）。steps は角の分割数。
    static func roundedBox(_ size: V3, radius: Float, steps k: Int = 2) -> MeshTemplate {
        var t = MeshTemplate()
        let half = size / 2
        let r = max(0.0005, min(radius, min(half.x, min(half.y, half.z)) * 0.98))
        let inner = V3(max(0, half.x - r), max(0, half.y - r), max(0, half.z - r))
        // 軸ごとのサンプル: 負側の角 (-45°→0°) と正側の角 (0°→45°)。0° は重複させ平面部を作る。
        let count = 2 * k + 2
        var tans: [Float] = []
        var sides: [Float] = []
        for j in 0..<count {
            if j <= k {
                tans.append(tan(-Float.pi / 4 + Float.pi / 4 * Float(j) / Float(k)))
                sides.append(-1)
            } else {
                tans.append(tan(Float.pi / 4 * Float(j - k - 1) / Float(k)))
                sides.append(1)
            }
        }
        for axis in 0..<3 {
            for sign: Float in [-1, 1] {
                let u = (axis + 1) % 3, v = (axis + 2) % 3
                let base = UInt32(t.positions.count)
                for j in 0..<count {
                    for l in 0..<count {
                        var d = V3.zero
                        d[axis] = sign
                        d[u] = tans[j]
                        d[v] = tans[l]
                        let n = simd_normalize(d)
                        var o = V3.zero
                        o[axis] = sign * inner[axis]
                        o[u] = sides[j] * inner[u]
                        o[v] = sides[l] * inner[v]
                        t.positions.append(o + n * r)
                        t.normals.append(n)
                    }
                }
                let w = UInt32(count)
                for j in 0..<UInt32(count - 1) {
                    for l in 0..<UInt32(count - 1) {
                        let a = base + j * w + l
                        t.quad(a, a + 1, a + w + 1, a + w)
                    }
                }
            }
        }
        t.orientToNormals()
        return t
    }

    /// 回転体。profile は (半径, 高さ) を下から上へ。同一点を 2 つ並べると折り目になる。
    static func lathe(_ profile: [V2], segments: Int, capBottom: Bool = false, capTop: Bool = false) -> MeshTemplate {
        var t = MeshTemplate()
        let n = profile.count
        guard n >= 2 else { return t }
        var normals2: [V2] = []
        for i in 0..<n {
            // 隣と同一点なら折り目として片側の接線のみを使う
            let hasPrev = i > 0 && simd_distance(profile[i - 1], profile[i]) > 1e-5
            let hasNext = i < n - 1 && simd_distance(profile[i + 1], profile[i]) > 1e-5
            let prev = hasPrev ? profile[i - 1] : profile[i]
            let next = hasNext ? profile[i + 1] : profile[i]
            var tan2 = next - prev
            if simd_length(tan2) < 1e-6 { tan2 = V2(0, 1) }
            normals2.append(simd_normalize(V2(tan2.y, -tan2.x)))
        }
        for i in 0..<n {
            for s in 0...segments {
                let lon = 2 * Float.pi * Float(s) / Float(segments)
                let c = cos(lon), sn = sin(lon)
                t.positions.append(V3(profile[i].x * c, profile[i].y, profile[i].x * sn))
                let nm = V3(normals2[i].x * c, normals2[i].y, normals2[i].x * sn)
                t.normals.append(simd_length(nm) > 1e-6 ? simd_normalize(nm) : V3(0, 1, 0))
            }
        }
        let w = UInt32(segments + 1)
        for i in 0..<UInt32(n - 1) {
            if simd_distance(profile[Int(i)], profile[Int(i) + 1]) < 1e-5 { continue }
            for s in 0..<UInt32(segments) {
                let a = i * w + s
                t.quad(a, a + 1, a + w + 1, a + w)
            }
        }
        if capBottom { t.appendDisc(y: profile[0].y, radius: profile[0].x, segments: segments, up: false) }
        if capTop { t.appendDisc(y: profile[n - 1].y, radius: profile[n - 1].x, segments: segments, up: true) }
        t.orientToNormals()
        return t
    }

    /// XY 平面の単純多角形を Z 方向に押し出す（厚み depth、中心 z=0）。
    static func extrude(_ poly: [V2], depth: Float) -> MeshTemplate {
        var t = MeshTemplate()
        var pts = poly
        if signedArea(pts) < 0 { pts.reverse() }
        let tris = earClip(pts)
        let hz = depth / 2
        for (z, nz) in [(hz, Float(1)), (-hz, Float(-1))] {
            let base = UInt32(t.positions.count)
            for p in pts {
                t.positions.append(V3(p.x, p.y, z))
                t.normals.append(V3(0, 0, nz))
            }
            for tri in tris { t.indices.append(contentsOf: [base + tri.0, base + tri.1, base + tri.2]) }
        }
        let m = pts.count
        for i in 0..<m {
            let a = pts[i], b = pts[(i + 1) % m]
            let e = b - a
            guard simd_length(e) > 1e-6 else { continue }
            let n2 = simd_normalize(V2(e.y, -e.x))
            let n = V3(n2.x, n2.y, 0)
            let base = UInt32(t.positions.count)
            t.positions.append(contentsOf: [V3(a.x, a.y, hz), V3(b.x, b.y, hz), V3(b.x, b.y, -hz), V3(a.x, a.y, -hz)])
            t.normals.append(contentsOf: [n, n, n, n])
            t.quad(base, base + 1, base + 2, base + 3)
        }
        t.orientToNormals()
        return t
    }

    /// 双角錐の結晶（半径 1、上端 top・下端 -bottom、平坦シェーディング）。
    static func crystal(sides: Int, top: Float, bottom: Float, waist: Float = 0) -> MeshTemplate {
        var t = MeshTemplate()
        let apexT = V3(0, top, 0), apexB = V3(0, -bottom, 0)
        let center = V3(0, waist, 0)
        for s in 0..<sides {
            let a0 = 2 * Float.pi * Float(s) / Float(sides)
            let a1 = 2 * Float.pi * Float(s + 1) / Float(sides)
            let p0 = V3(cos(a0), waist, sin(a0)), p1 = V3(cos(a1), waist, sin(a1))
            for apex in [apexT, apexB] {
                var fn = simd_normalize(simd_cross(p1 - apex, p0 - apex))
                if simd_dot(fn, (apex + p0 + p1) / 3 - center) < 0 { fn = -fn }
                let base = UInt32(t.positions.count)
                t.positions.append(contentsOf: [apex, p0, p1])
                t.normals.append(contentsOf: [fn, fn, fn])
                t.indices.append(contentsOf: [base, base + 1, base + 2])
            }
        }
        t.orientToNormals()
        return t
    }

    /// 布（マント・旗）。上辺中央が原点、-Y へ垂れる。幅 w0→w1、長さ len、+Z へ反る。両面。
    /// jag > 0 で下端をギザギザにする。
    static func cloth(w0: Float, w1: Float, length: Float, curve: Float, bulge: Float,
                      cols: Int, rows: Int, jag: Float = 0) -> MeshTemplate {
        var t = MeshTemplate()
        func point(_ c: Int, _ r: Int) -> V3 {
            let u = Float(c) / Float(cols)
            let colJag = jag > 0 ? (c % 2 == 0 ? 1 : 1 - jag) : 1
            let v = Float(r) / Float(rows) * colJag
            let w = w0 + (w1 - w0) * v
            let x = (u - 0.5) * w
            let y = -v * length
            let z = curve * v * v + bulge * (1 - (2 * u - 1) * (2 * u - 1)) * (1 - 0.5 * v)
            return V3(x, y, z)
        }
        for layer in 0..<2 {
            let base = UInt32(t.positions.count)
            let off: Float = layer == 0 ? 0.004 : -0.004
            for r in 0...rows {
                for c in 0...cols {
                    let p = point(c, r)
                    let px = point(min(cols, c + 1), r) - point(max(0, c - 1), r)
                    let py = point(c, min(rows, r + 1)) - point(c, max(0, r - 1))
                    var n = simd_normalize(simd_cross(py, px))
                    if layer == 1 { n = -n }
                    t.positions.append(p + n * off)
                    t.normals.append(n)
                }
            }
            let w = UInt32(cols + 1)
            for r in 0..<UInt32(rows) {
                for c in 0..<UInt32(cols) {
                    let a = base + r * w + c
                    t.quad(a, a + 1, a + w + 1, a + w)
                }
            }
        }
        t.orientToNormals()
        return t
    }

    /// XZ 平面の円環（上向き）。dashes > 0 で破線。
    static func annulus(inner: Float, outer: Float, segments: Int, dashes: Int = 0, dashFill: Float = 0.6) -> MeshTemplate {
        var t = MeshTemplate()
        let n = V3(0, 1, 0)
        func addArc(_ a0: Float, _ a1: Float, _ segs: Int) {
            let base = UInt32(t.positions.count)
            for s in 0...segs {
                let a = a0 + (a1 - a0) * Float(s) / Float(segs)
                t.positions.append(V3(inner * cos(a), 0, inner * sin(a)))
                t.positions.append(V3(outer * cos(a), 0, outer * sin(a)))
                t.normals.append(contentsOf: [n, n])
            }
            for s in 0..<UInt32(segs) {
                let a = base + s * 2
                t.quad(a, a + 1, a + 3, a + 2)
            }
        }
        if dashes > 0 {
            let step = 2 * Float.pi / Float(dashes)
            let per = max(2, segments / dashes)
            for d in 0..<dashes {
                let a0 = Float(d) * step
                addArc(a0, a0 + step * dashFill, per)
            }
        } else {
            addArc(0, 2 * .pi, segments)
        }
        t.orientToNormals()
        return t
    }

    /// 平らな多角形（XZ 平面、上向き）。
    static func flat(_ poly: [V2]) -> MeshTemplate {
        var t = MeshTemplate()
        var pts = poly
        if signedArea(pts) < 0 { pts.reverse() }
        for p in pts {
            t.positions.append(V3(p.x, 0, p.y))
            t.normals.append(V3(0, 1, 0))
        }
        for tri in earClip(pts) { t.indices.append(contentsOf: [tri.0, tri.1, tri.2]) }
        t.orientToNormals()
        return t
    }
}

// MARK: - 多角形

func signedArea(_ p: [V2]) -> Float {
    var a: Float = 0
    for i in 0..<p.count {
        let q = p[(i + 1) % p.count]
        a += p[i].x * q.y - q.x * p[i].y
    }
    return a / 2
}

/// 耳切り法による三角形分割（反時計回りの単純多角形）。
func earClip(_ pts: [V2]) -> [(UInt32, UInt32, UInt32)] {
    var idx = Array(0..<pts.count)
    var out: [(UInt32, UInt32, UInt32)] = []
    func cross2(_ o: V2, _ a: V2, _ b: V2) -> Float { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
    func inside(_ p: V2, _ a: V2, _ b: V2, _ c: V2) -> Bool {
        cross2(a, b, p) >= 0 && cross2(b, c, p) >= 0 && cross2(c, a, p) >= 0
    }
    var guardCount = 0
    while idx.count > 3 && guardCount < 10_000 {
        guardCount += 1
        var clipped = false
        for i in 0..<idx.count {
            let i0 = idx[(i + idx.count - 1) % idx.count], i1 = idx[i], i2 = idx[(i + 1) % idx.count]
            let a = pts[i0], b = pts[i1], c = pts[i2]
            if cross2(a, b, c) <= 1e-9 { continue }
            var ok = true
            for j in idx where j != i0 && j != i1 && j != i2 {
                if inside(pts[j], a, b, c) { ok = false; break }
            }
            if ok {
                out.append((UInt32(i0), UInt32(i1), UInt32(i2)))
                idx.remove(at: i)
                clipped = true
                break
            }
        }
        if !clipped {
            // 退化形状: 残りを扇形で閉じる
            for i in 1..<(idx.count - 1) { out.append((UInt32(idx[0]), UInt32(idx[i]), UInt32(idx[i + 1]))) }
            return out
        }
    }
    if idx.count == 3 { out.append((UInt32(idx[0]), UInt32(idx[1]), UInt32(idx[2]))) }
    return out
}

/// 円弧上の点列（中心 c、半径 r、角度 a0→a1）。
func arcPoints(_ c: V2, _ r: Float, _ a0: Float, _ a1: Float, _ n: Int) -> [V2] {
    (0...n).map { i in
        let a = a0 + (a1 - a0) * Float(i) / Float(n)
        return c + V2(cos(a), sin(a)) * r
    }
}

/// 星形の多角形。
func starPolygon(points: Int, outer: Float, inner: Float, rotation: Float = .pi / 2) -> [V2] {
    (0..<(points * 2)).map { i in
        let r = i % 2 == 0 ? outer : inner
        let a = rotation + Float.pi * Float(i) / Float(points)
        return V2(cos(a), sin(a)) * r
    }
}

/// 三日月形（外円と内円の差）。先端は ±span/2。
func crescentPolygon(radius: Float, thickness: Float, span: Float, offset: Float, n: Int = 14) -> [V2] {
    let outer = arcPoints(.zero, radius, -span / 2, span / 2, n)
    let innerR = radius - thickness
    let inner = arcPoints(V2(-offset, 0), innerR, span / 2 * 0.92, -span / 2 * 0.92, n)
    return outer + inner
}

// MARK: - 結合

/// 骨ごとの結合メッシュを作る。面ごとにマテリアル番号（HeroMat）を持つ。
struct MeshBuilder {
    private(set) var positions: [V3] = []
    private(set) var normals: [V3] = []
    private(set) var indices: [UInt32] = []
    private(set) var faceMaterials: [UInt32] = []
    /// 頂点ごとのマテリアル番号（素片単位で 1 つなので頂点から決まる）。パレット UV に使う。
    private(set) var vertexSlots: [UInt8] = []

    var isEmpty: Bool { indices.isEmpty }
    var triangleCount: Int { indices.count / 3 }

    mutating func add(_ t: MeshTemplate, _ m: simd_float4x4, _ mat: HeroMat) {
        let base = UInt32(positions.count)
        let m3 = simd_float3x3(V3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                               V3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                               V3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        let det = simd_determinant(m3)
        let nm = det.magnitude > 1e-12 ? simd_transpose(simd_inverse(m3)) : m3
        positions.reserveCapacity(positions.count + t.positions.count)
        normals.reserveCapacity(normals.count + t.normals.count)
        for p in t.positions {
            let q = m * SIMD4(p, 1)
            positions.append(V3(q.x, q.y, q.z))
        }
        for n in t.normals {
            let q = nm * n
            let l = simd_length(q)
            normals.append(l > 1e-8 ? q / l : V3(0, 1, 0))
        }
        vertexSlots.append(contentsOf: repeatElement(UInt8(mat.rawValue), count: t.positions.count))
        let flip = det < 0
        var i = 0
        while i + 2 < t.indices.count {
            let a = t.indices[i] + base, b = t.indices[i + 1] + base, c = t.indices[i + 2] + base
            if flip { indices.append(contentsOf: [a, c, b]) } else { indices.append(contentsOf: [a, b, c]) }
            faceMaterials.append(mat.rawValue)
            i += 3
        }
    }

    /// 別の結合メッシュを変換して取り込む（部品を原点で作ってから配置する用）。
    mutating func merge(_ o: MeshBuilder, _ m: simd_float4x4) {
        let t = MeshTemplate(positions: o.positions, normals: o.normals, indices: o.indices)
        let faceBase = faceMaterials.count
        let vertexBase = vertexSlots.count
        add(t, m, .primary)
        // add は 1 つのマテリアルで登録するので、元の番号で上書きする
        for i in 0..<o.faceMaterials.count { faceMaterials[faceBase + i] = o.faceMaterials[i] }
        for i in 0..<o.vertexSlots.count { vertexSlots[vertexBase + i] = o.vertexSlots[i] }
    }

    /// マテリアル番号ごとのパーツを持つメッシュ（台座・効果用。materials は HeroMat の順）。
    func makeMesh(name: String) -> MeshResource? {
        guard !indices.isEmpty else { return nil }
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(normals)
        d.primitives = .triangles(indices)
        d.materials = .perFace(faceMaterials)
        return try? MeshResource.generate(from: [d])
    }

    /// パレットアトラス用メッシュ（ヒーロー本体）。材質番号は HeroAtlasPart の順:
    /// 0 = アトラス PBR（色は UV でパレットを参照）、1 = 半透明の布、2 = 発光（非照明）、3 = 金属。
    /// 骨 1 本あたりの描画単位を 1〜3 に抑える。
    func makeAtlasMesh(name: String, glowingEyes: Bool) -> MeshResource? {
        guard !indices.isEmpty else { return nil }
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(vertexSlots.map { HeroPaletteAtlas.uv(slot: Int($0)) })
        d.primitives = .triangles(indices)
        let parts = faceMaterials.map { raw -> UInt32 in
            HeroAtlasPart.of(HeroMat(rawValue: raw) ?? .primary, glowingEyes: glowingEyes).rawValue
        }
        if let first = parts.first, parts.allSatisfy({ $0 == first }) {
            d.materials = .allFaces(first)
        } else {
            d.materials = .perFace(parts)
        }
        return try? MeshResource.generate(from: [d])
    }
}

/// ヒーロー本体のマテリアル区分（ModelEntity.materials の添字）。
enum HeroAtlasPart: UInt32, CaseIterable {
    case surface, veil, glow, metal

    static func of(_ slot: HeroMat, glowingEyes: Bool) -> HeroAtlasPart {
        switch slot {
        case .veil: return .veil
        case .glow, .shine: return .glow
        case .eye: return glowingEyes ? .glow : .surface
        case .metal: return .metal
        default: return .surface
        }
    }
}

// MARK: - 形状ショートカット

/// 共有テンプレート（単位形状）。
enum MeshTemplates {
    static let sphereHi = MeshTemplate.sphere(segments: 20, rings: 13)
    static let sphereMid = MeshTemplate.sphere(segments: 13, rings: 9)
    static let sphereLo = MeshTemplate.sphere(segments: 8, rings: 6)
    static let sphereTiny = MeshTemplate.sphere(segments: 6, rings: 4)
    static let dome = MeshTemplate.sphere(segments: 14, rings: 5, latFrom: 0, latTo: .pi / 2)
    static let cube = MeshTemplate.box([1, 1, 1])
}

enum MeshDetail { case tiny, low, mid, high }

extension MeshBuilder {
    mutating func sphere(_ c: V3, _ r: Float, _ mat: HeroMat, _ detail: MeshDetail = .mid) {
        ellipsoid(c, [r, r, r], mat, detail: detail)
    }

    mutating func ellipsoid(_ c: V3, _ radii: V3, _ mat: HeroMat, rot: simd_quatf = qIdentity, detail: MeshDetail = .mid) {
        let t: MeshTemplate
        switch detail {
        case .tiny: t = MeshTemplates.sphereTiny
        case .low: t = MeshTemplates.sphereLo
        case .mid: t = MeshTemplates.sphereMid
        case .high: t = MeshTemplates.sphereHi
        }
        add(t, trs(c, rot, radii), mat)
    }

    /// 半球ドーム（底面あり）。+Y が頂点方向。
    mutating func dome(_ c: V3, _ radii: V3, _ mat: HeroMat, rot: simd_quatf = qIdentity) {
        add(MeshTemplates.dome, trs(c, rot, radii), mat)
    }

    /// a→b の円錐台（半径 r0→r1）。
    mutating func frustum(_ a: V3, _ b: V3, _ r0: Float, _ r1: Float, _ mat: HeroMat, segments: Int = 12, caps: Bool = true) {
        let d = b - a
        let len = simd_length(d)
        guard len > 1e-5 else { return }
        let t = MeshTemplate.frustum(r0: r0, r1: r1, segments: segments, caps: caps)
        add(t, trs(a, rotationFromY(to: d), [1, len, 1]), mat)
    }

    /// 両端が丸い肢（円錐台 + 端の球）。
    mutating func limb(_ a: V3, _ b: V3, _ r0: Float, _ r1: Float, _ mat: HeroMat, segments: Int = 11) {
        frustum(a, b, r0, r1, mat, segments: segments, caps: false)
        sphere(a, r0, mat, .low)
        sphere(b, r1, mat, .low)
    }

    mutating func rod(_ a: V3, _ b: V3, _ r: Float, _ mat: HeroMat, segments: Int = 8) {
        frustum(a, b, r, r, mat, segments: segments)
    }

    mutating func cone(_ base: V3, _ tip: V3, _ r: Float, _ mat: HeroMat, segments: Int = 10) {
        frustum(base, tip, r, 0, mat, segments: segments)
    }

    mutating func box(_ c: V3, _ size: V3, _ mat: HeroMat, rot: simd_quatf = qIdentity) {
        add(MeshTemplates.cube, trs(c, rot, size), mat)
    }

    mutating func rbox(_ c: V3, _ size: V3, _ radius: Float, _ mat: HeroMat, rot: simd_quatf = qIdentity) {
        // 小さな箱は角の分割を減らす
        let steps = min(size.x, min(size.y, size.z)) < 0.1 || radius < 0.02 ? 1 : 2
        add(MeshTemplate.roundedBox(size, radius: radius, steps: steps), trs(c, rot), mat)
    }

    /// トーラス（既定は Y 軸まわり＝水平）。
    mutating func torus(_ c: V3, _ R: Float, _ r: Float, _ mat: HeroMat, rot: simd_quatf = qIdentity,
                        segments: Int = 16, sides: Int = 6, arc: Float = 2 * .pi) {
        add(MeshTemplate.torus(minor: r / R, segments: segments, sides: sides, arc: arc), trs(c, rot, [R, R, R]), mat)
    }

    mutating func lathe(_ profile: [V2], _ c: V3, _ mat: HeroMat, rot: simd_quatf = qIdentity, scale: V3 = [1, 1, 1],
                        segments: Int = 16, capBottom: Bool = false, capTop: Bool = false) {
        add(MeshTemplate.lathe(profile, segments: segments, capBottom: capBottom, capTop: capTop), trs(c, rot, scale), mat)
    }

    /// XY 平面の多角形を押し出し、rot で向ける。
    mutating func extrude(_ poly: [V2], depth: Float, _ c: V3, _ mat: HeroMat, rot: simd_quatf = qIdentity, scale: V3 = [1, 1, 1]) {
        add(MeshTemplate.extrude(poly, depth: depth), trs(c, rot, scale), mat)
    }

    /// YZ 平面（刃を ±X に向けた武器用）に多角形を置いて押し出す。poly の x は -Z（前方）に対応。
    mutating func blade(_ poly: [V2], depth: Float, _ c: V3, _ mat: HeroMat, extra: simd_quatf = qIdentity) {
        extrude(poly, depth: depth, c, mat, rot: extra * ry(.pi / 2))
    }

    mutating func crystal(_ c: V3, radius: Float, height: Float, _ mat: HeroMat, rot: simd_quatf = qIdentity,
                          sides: Int = 6, bottom: Float = 0.35) {
        add(MeshTemplate.crystal(sides: sides, top: 1, bottom: bottom), trs(c, rot, [radius, height, radius]), mat)
    }
}
