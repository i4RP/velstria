import CoreGraphics
import Foundation
import simd
import VelstriaCore

// 担当: battle-renderer（ステージ）。地面の配合マップと補助マップを地図データから作る（純粋関数、背景スレッド可）。
// 範囲は地図座標（m）で x, y とも −20…140（地図の外 20 m を含む）。画像の上端が北（y = 140）。
//   配合マップ RGBA: R 土 / G 石畳 / B 川 / A 森の下草（草地は残り）
//   補助マップ RGBA: R 遮蔽 / G 大きな色むら（0.5 中立）/ B 川の深さ / A 予備
// 意味は docs/STAGE.md の 3.4、シェーダーは tools/stage/shaders/StageShaders.metal の stageGroundSurface。

enum StageSplat {
    static let origin: Float = -20
    static let span: Float = 160

    /// 地面に落ちる影（木の樹冠など）。中心は地図座標（m）。
    struct Shade: Sendable {
        var center: SIMD2<Float>
        var radius: Float
        var strength: Float
    }

    struct Maps: Sendable {
        let control: CGImage
        let aux: CGImage
    }

    /// 太陽（左上の奥）の影が伸びる向き（地図座標、南東）。
    static let shadowDirection = simd_normalize(SIMD2<Float>(0.75, -0.66))

    static func make(map: MapDefinition, shades: [Shade], controlSize n: Int = 1024, auxSize na: Int = 512) -> Maps? {
        let geo = StageGeometry(map: map)
        // MARK: 配合マップ
        var dirt = Field(n), pave = Field(n), river = Field(n), forest = Field(n)
        // 土: レーン
        for path in geo.lanes {
            for k in 0..<(path.count - 1) {
                dirt.stampSegment(path[k], path[k + 1], inner: 2.3, outer: 3.6, wobble: 0.7, seed: 11)
            }
        }
        // 土: キャンプの空き地
        for c in map.camps {
            let p = geo.m(c.pos)
            switch c.kind {
            case .small, .hornLizard, .emberBeetle, .magmaGolem: dirt.stampDisc(p, inner: 0.9, outer: 2.3, wobble: 0.8, seed: 23)
            case .blueSentinel, .redSentinel: dirt.stampDisc(p, inner: 2.4, outer: 3.3, wobble: 0.5, seed: 29)
            // 川の中立・宝殻蟹・ボスは土の空き地を作らない（川・祭壇の床）
            case .astralWyrm, .ancientColossus, .treasureCrab, .mossWanderer: break
            }
        }
        // 石畳: 拠点（泉・Core・参道）、タワーの台座、祭壇
        for team in Team.players {
            let f = geo.m(map.fountain(team)), c = geo.m(map.core(team))
            pave.stampDisc(f, inner: 8.4, outer: 9.4, wobble: 0.5, seed: 31)
            pave.stampDisc(c, inner: 12.6, outer: 13.8, wobble: 0.7, seed: 37)
            pave.stampSegment(f, c, inner: 4.6, outer: 5.6, wobble: 0.4, seed: 41)
        }
        for t in map.towers where !t.isCore {
            pave.stampDisc(geo.m(t.pos), inner: 2.5, outer: 3.2, wobble: 0.35, seed: 43)
        }
        for c in map.camps {
            let p = geo.m(c.pos)
            switch c.kind {
            case .astralWyrm, .ancientColossus: pave.stampDisc(p, inner: 7.0, outer: 8.2, wobble: 0.6, seed: 47)
            case .blueSentinel, .redSentinel: pave.stampDisc(p, inner: 2.6, outer: 3.2, wobble: 0.3, seed: 53)
            case .small, .hornLizard, .emberBeetle, .magmaGolem, .treasureCrab, .mossWanderer: break
            }
        }
        // 川（祭壇の床では途切れる）
        let pits = map.camps.filter { $0.kind == .astralWyrm || $0.kind == .ancientColossus }.map { geo.m($0.pos) }
        let halfWidth = Float(map.riverWidth / 100) / 2
        river.fillDiagonalBand(sum: geo.mapMeters, halfWidth: halfWidth + 1.2) { p in
            let d = geo.riverDistance(p) + (valueNoise(p * 0.35, seed: 61) - 0.5) * 0.9
            var w = 1 - smoothstep(halfWidth - 0.6, halfWidth + 0.5, d)
            for c in pits { w *= smoothstep(7.4, 8.6, simd_distance(p, c)) }
            return w
        }
        // 森の下草: 壁際・草むらの下・地図の外・ジャングルの奥のまだら（なだらかなので 1/4 の解像度で求めて拡大）
        forest.fillCoarse(factor: 4) { p in
            var w: Float = 0
            let dObs = geo.obstacleDistance(p) + (valueNoise(p * 0.45, seed: 67) - 0.5) * 1.4
            w = max(w, 1 - smoothstep(0.4, 2.8, dObs))
            let out = geo.outsideDistance(p)
            w = max(w, smoothstep(-1.5, 2.5, out))
            // 地図の縁へ向かって森の下草が増える（外周の森へなじませる）
            w = max(w, smoothstep(-7, -1.5, out) * 0.55 * smoothstep(5, 9, geo.laneDistance(p)))
            if geo.brushDistance(p) < 0.6 { w = max(w, 0.85) }
            let dl = geo.laneDistance(p)
            if dl > 8 {
                let patch = smoothstep(0.54, 0.72, fbm(p * 0.06, seed: 71)) * smoothstep(8, 13, dl)
                w = max(w, patch * 0.55)
            }
            return w
        }
        var control = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let g = pave.v[i]
            let b = river.v[i] * (1 - g)
            let r = dirt.v[i] * (1 - g) * (1 - b)
            let a = max(0, min(forest.v[i], 1 - g - b - r))
            control[i * 4] = q(r)
            control[i * 4 + 1] = q(g)
            control[i * 4 + 2] = q(b)
            control[i * 4 + 3] = q(a)
        }
        // MARK: 補助マップ
        var aux = [UInt8](repeating: 0, count: na * na * 4)
        let shadeGrid = ShadeGrid(shades: shades)
        let obstacleGrid = ObstacleGrid(geo: geo)
        for row in 0..<na {
            for col in 0..<na {
                let p = Field.point(col, row, na)
                // 影は南東へずらした位置で壁からの距離を測る（光の向きに合わせた接地の陰）
                let ps = p - shadowDirection * 1.1
                let dObs = obstacleGrid.distance(ps, limit: 3.5)
                var ao: Float = (1 - smoothstep(0, 1.6, dObs)) * 0.75 + (1 - smoothstep(0, 3.4, dObs)) * 0.25
                ao = max(ao, shadeGrid.shade(at: p))
                if obstacleGrid.inBrush(p, margin: 0.2) { ao = max(ao, 0.32) }
                ao = max(ao, smoothstep(0, 10, geo.outsideDistance(p)) * 0.55)
                let macro = fbm(p * 0.035, seed: 83) * 0.85 + valueNoise(p * 0.21, seed: 89) * 0.15
                let rd = geo.riverDistance(p)
                var depth = 1 - smoothstep(0, halfWidth, rd)
                if depth > 0 {
                    for c in pits { depth *= smoothstep(6.5, 9, simd_distance(p, c)) }
                    // レーンが川を渡る所は浅瀬
                    depth *= 0.45 + 0.55 * smoothstep(2.5, 5.5, geo.laneDistance(p))
                }
                let i = (row * na + col) * 4
                aux[i] = q(min(1, ao))
                aux[i + 1] = q(macro)
                aux[i + 2] = q(depth)
                aux[i + 3] = 0
            }
        }
        guard let c = image(control, n), let a = image(aux, na) else { return nil }
        return Maps(control: c, aux: a)
    }

    // MARK: 内部

    private static func q(_ v: Float) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }

    private static func image(_ bytes: [UInt8], _ n: Int) -> CGImage? {
        // 色空間なし（線形の値）。sRGB として読ませるとシェーダーで値が歪む
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// 1 チャンネルの場（0〜1）。
    struct Field {
        let n: Int
        var v: [Float]
        init(_ n: Int) {
            self.n = n
            v = [Float](repeating: 0, count: n * n)
        }

        static func point(_ col: Int, _ row: Int, _ n: Int) -> SIMD2<Float> {
            let s = StageSplat.span / Float(n)
            return SIMD2(StageSplat.origin + (Float(col) + 0.5) * s, StageSplat.origin + StageSplat.span - (Float(row) + 0.5) * s)
        }

        func colRange(_ x0: Float, _ x1: Float) -> ClosedRange<Int>? {
            let s = StageSplat.span / Float(n)
            let a = max(0, Int(floor((x0 - StageSplat.origin) / s)))
            let b = min(n - 1, Int(ceil((x1 - StageSplat.origin) / s)))
            return a <= b ? a...b : nil
        }

        func rowRange(_ y0: Float, _ y1: Float) -> ClosedRange<Int>? {
            let s = StageSplat.span / Float(n)
            let top = StageSplat.origin + StageSplat.span
            let a = max(0, Int(floor((top - y1) / s)))
            let b = min(n - 1, Int(ceil((top - y0) / s)))
            return a <= b ? a...b : nil
        }

        mutating func stamp(minX: Float, maxX: Float, minY: Float, maxY: Float, _ f: (SIMD2<Float>) -> Float) {
            guard let cols = colRange(minX, maxX), let rows = rowRange(minY, maxY) else { return }
            v.withUnsafeMutableBufferPointer { buf in
                for row in rows {
                    for col in cols {
                        let w = f(Field.point(col, row, n))
                        let i = row * n + col
                        if w > buf[i] { buf[i] = w }
                    }
                }
            }
        }

        mutating func stampSegment(_ a: SIMD2<Float>, _ b: SIMD2<Float>, inner: Float, outer: Float, wobble: Float, seed: UInt32) {
            let pad = outer + wobble
            stamp(minX: min(a.x, b.x) - pad, maxX: max(a.x, b.x) + pad, minY: min(a.y, b.y) - pad, maxY: max(a.y, b.y) + pad) { p in
                let d = segmentDistance(p, a, b) + (valueNoise(p * 0.3, seed: seed) - 0.5) * 2 * wobble
                return 1 - smoothstep(inner, outer, d)
            }
        }

        mutating func stampDisc(_ c: SIMD2<Float>, inner: Float, outer: Float, wobble: Float, seed: UInt32) {
            let pad = outer + wobble
            stamp(minX: c.x - pad, maxX: c.x + pad, minY: c.y - pad, maxY: c.y + pad) { p in
                let d = simd_distance(p, c) + (valueNoise(p * 0.45, seed: seed) - 0.5) * 2 * wobble
                return 1 - smoothstep(inner, outer, d)
            }
        }

        mutating func fill(_ f: (SIMD2<Float>) -> Float) {
            stamp(minX: StageSplat.origin, maxX: StageSplat.origin + StageSplat.span,
                  minY: StageSplat.origin, maxY: StageSplat.origin + StageSplat.span, f)
        }

        /// x + y = sum の帯（幅 ±halfWidth）だけを求める（川）。
        mutating func fillDiagonalBand(sum: Float, halfWidth: Float, _ f: (SIMD2<Float>) -> Float) {
            let s = StageSplat.span / Float(n)
            let reach = halfWidth * 1.4142136 + s
            let n = n
            // x + y = sum ± reach の範囲の列だけ（行ごとの範囲は先に求める: 書き込み中に self を読まない）
            let ranges = (0..<n).map { row -> ClosedRange<Int>? in
                let y = Field.point(0, row, n).y
                return colRange(sum - y - reach, sum - y + reach)
            }
            v.withUnsafeMutableBufferPointer { buf in
                for row in 0..<n {
                    guard let cols = ranges[row] else { continue }
                    for col in cols {
                        let w = f(Field.point(col, row, n))
                        let i = row * n + col
                        if w > buf[i] { buf[i] = w }
                    }
                }
            }
        }

        /// 1/factor の解像度で求めて双線形に拡大する（なだらかな場向け）。
        mutating func fillCoarse(factor: Int, _ f: (SIMD2<Float>) -> Float) {
            let nc = max(2, n / factor)
            var coarse = [Float](repeating: 0, count: nc * nc)
            for row in 0..<nc {
                for col in 0..<nc { coarse[row * nc + col] = f(Field.point(col, row, nc)) }
            }
            let scale = Float(nc) / Float(n)
            v.withUnsafeMutableBufferPointer { buf in
                for row in 0..<n {
                    let fy = max(0, min(Float(nc - 1), (Float(row) + 0.5) * scale - 0.5))
                    let y0 = Int(fy), y1 = min(nc - 1, y0 + 1), ty = fy - Float(y0)
                    for col in 0..<n {
                        let fx = max(0, min(Float(nc - 1), (Float(col) + 0.5) * scale - 0.5))
                        let x0 = Int(fx), x1 = min(nc - 1, x0 + 1), tx = fx - Float(x0)
                        let a = coarse[y0 * nc + x0] + (coarse[y0 * nc + x1] - coarse[y0 * nc + x0]) * tx
                        let b = coarse[y1 * nc + x0] + (coarse[y1 * nc + x1] - coarse[y1 * nc + x0]) * tx
                        let w = a + (b - a) * ty
                        let i = row * n + col
                        if w > buf[i] { buf[i] = w }
                    }
                }
            }
        }
    }

    /// 壁・草むらの距離の検索を速くする 8 m 格子（limit より遠い壁は limit を返す）。
    struct ObstacleGrid {
        static let cell: Float = 8
        static let reach: Float = 4
        let geo: StageGeometry
        var rectCells: [Int: [Int]] = [:]
        var circleCells: [Int: [Int]] = [:]
        var brushCells: [Int: [Int]] = [:]

        init(geo: StageGeometry) {
            self.geo = geo
            func cover(_ lo: SIMD2<Float>, _ hi: SIMD2<Float>, _ body: (Int) -> Void) {
                let r = ObstacleGrid.reach
                for x in Int(floor((lo.x - r) / ObstacleGrid.cell))...Int(floor((hi.x + r) / ObstacleGrid.cell)) {
                    for y in Int(floor((lo.y - r) / ObstacleGrid.cell))...Int(floor((hi.y + r) / ObstacleGrid.cell)) {
                        body(ShadeGrid.key(x, y))
                    }
                }
            }
            for (i, r) in geo.rects.enumerated() { cover(r.min, r.max) { rectCells[$0, default: []].append(i) } }
            for (i, c) in geo.circles.enumerated() {
                cover(c.center - c.radius, c.center + c.radius) { circleCells[$0, default: []].append(i) }
            }
            for (i, b) in geo.brushes.enumerated() { cover(b.min, b.max) { brushCells[$0, default: []].append(i) } }
        }

        func key(_ p: SIMD2<Float>) -> Int {
            ShadeGrid.key(Int(floor(p.x / ObstacleGrid.cell)), Int(floor(p.y / ObstacleGrid.cell)))
        }

        func distance(_ p: SIMD2<Float>, limit: Float) -> Float {
            let k = key(p)
            var d = limit
            for i in rectCells[k] ?? [] { d = min(d, rectDistance(p, geo.rects[i].min, geo.rects[i].max)) }
            for i in circleCells[k] ?? [] { d = min(d, simd_distance(p, geo.circles[i].center) - geo.circles[i].radius) }
            return d
        }

        func inBrush(_ p: SIMD2<Float>, margin: Float) -> Bool {
            for i in brushCells[key(p)] ?? [] where rectDistance(p, geo.brushes[i].min, geo.brushes[i].max) < margin { return true }
            return false
        }
    }

    /// 影の検索を速くする 8 m 格子。
    struct ShadeGrid {
        static let cell: Float = 8
        var cells: [Int: [Shade]] = [:]
        init(shades: [Shade]) {
            for s in shades {
                let r = s.radius
                let x0 = Int(floor((s.center.x - r) / ShadeGrid.cell)), x1 = Int(floor((s.center.x + r) / ShadeGrid.cell))
                let y0 = Int(floor((s.center.y - r) / ShadeGrid.cell)), y1 = Int(floor((s.center.y + r) / ShadeGrid.cell))
                for x in x0...x1 {
                    for y in y0...y1 { cells[ShadeGrid.key(x, y), default: []].append(s) }
                }
            }
        }
        static func key(_ x: Int, _ y: Int) -> Int { (y + 64) * 256 + (x + 64) }
        func shade(at p: SIMD2<Float>) -> Float {
            guard let list = cells[ShadeGrid.key(Int(floor(p.x / ShadeGrid.cell)), Int(floor(p.y / ShadeGrid.cell)))] else { return 0 }
            var a: Float = 0
            for s in list {
                let d = simd_distance(p, s.center)
                a = max(a, (1 - smoothstep(s.radius * 0.45, s.radius, d)) * s.strength)
            }
            return a
        }
    }
}

/// 地図の形を地図座標（m）で問い合わせる。
struct StageGeometry {
    let lanes: [[SIMD2<Float>]]
    let rects: [(min: SIMD2<Float>, max: SIMD2<Float>)]
    let circles: [(center: SIMD2<Float>, radius: Float)]
    let brushes: [(min: SIMD2<Float>, max: SIMD2<Float>)]
    let mapMeters: Float

    init(map: MapDefinition) {
        func m(_ v: Vec2) -> SIMD2<Float> { SIMD2(Float(v.x / Balance.unitsPerMeter), Float(v.y / Balance.unitsPerMeter)) }
        lanes = map.lanes.map { lane in map.lanePath(lane, for: .blue).map(m) }
        var rects: [(SIMD2<Float>, SIMD2<Float>)] = []
        var circles: [(SIMD2<Float>, Float)] = []
        for o in map.obstacles {
            switch o {
            case .rect(let r): rects.append((m(Vec2(r.minX, r.minY)), m(Vec2(r.maxX, r.maxY))))
            case .circle(let c, let radius): circles.append((m(c), Float(radius / Balance.unitsPerMeter)))
            }
        }
        self.rects = rects.map { (min: $0.0, max: $0.1) }
        self.circles = circles.map { (center: $0.0, radius: $0.1) }
        brushes = map.brushes.map { (min: m(Vec2($0.rect.minX, $0.rect.minY)), max: m(Vec2($0.rect.maxX, $0.rect.maxY))) }
        mapMeters = Float(map.size / Balance.unitsPerMeter)
    }

    func m(_ v: Vec2) -> SIMD2<Float> { SIMD2(Float(v.x / Balance.unitsPerMeter), Float(v.y / Balance.unitsPerMeter)) }

    /// 壁の足跡までの距離（内側は負）。
    func obstacleDistance(_ p: SIMD2<Float>) -> Float {
        var d = Float.greatestFiniteMagnitude
        for r in rects { d = min(d, rectDistance(p, r.min, r.max)) }
        for c in circles { d = min(d, simd_distance(p, c.center) - c.radius) }
        return d
    }

    func brushDistance(_ p: SIMD2<Float>) -> Float {
        var d = Float.greatestFiniteMagnitude
        for b in brushes { d = min(d, rectDistance(p, b.min, b.max)) }
        return d
    }

    func laneDistance(_ p: SIMD2<Float>) -> Float {
        var d = Float.greatestFiniteMagnitude
        for path in lanes {
            for k in 0..<(path.count - 1) { d = min(d, segmentDistance(p, path[k], path[k + 1])) }
        }
        return d
    }

    /// 川の中心線（x + y = 地図の一辺）からの距離。
    func riverDistance(_ p: SIMD2<Float>) -> Float { abs(p.x + p.y - mapMeters) * 0.70710678 }

    /// 地図の外へはみ出した距離（内側は負）。
    func outsideDistance(_ p: SIMD2<Float>) -> Float {
        rectDistance(p, .zero, SIMD2(repeating: mapMeters)) > 0 ? rectDistance(p, .zero, SIMD2(repeating: mapMeters))
            : -min(min(p.x, mapMeters - p.x), min(p.y, mapMeters - p.y))
    }
}

// MARK: 小さな数学

@inline(__always)
func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
}

@inline(__always)
func segmentDistance(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    let ab = b - a
    let len2 = simd_length_squared(ab)
    let t = len2 > 0 ? max(0, min(1, simd_dot(p - a, ab) / len2)) : 0
    return simd_distance(p, a + ab * t)
}

/// 矩形までの距離（内側は負: 最も近い辺までの距離）。
@inline(__always)
func rectDistance(_ p: SIMD2<Float>, _ lo: SIMD2<Float>, _ hi: SIMD2<Float>) -> Float {
    let c = (lo + hi) / 2, h = (hi - lo) / 2
    let q = simd_abs(p - c) - h
    let outside = simd_length(simd_max(q, .zero))
    let inside = min(max(q.x, q.y), 0)
    return outside + inside
}

@inline(__always)
private func hash2(_ x: Int32, _ y: Int32, _ seed: UInt32) -> Float {
    var h = UInt32(bitPattern: x) &* 0x8DA6_B343 ^ UInt32(bitPattern: y) &* 0xD816_3841 ^ seed &* 0xCB1A_B31F
    h ^= h >> 13
    h = h &* 0x5BD1_E995
    h ^= h >> 15
    return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
}

/// 値ノイズ（0〜1）。
func valueNoise(_ p: SIMD2<Float>, seed: UInt32) -> Float {
    let fx = floor(p.x), fy = floor(p.y)
    let ix = Int32(fx), iy = Int32(fy)
    let tx = p.x - fx, ty = p.y - fy
    let ux = tx * tx * (3 - 2 * tx), uy = ty * ty * (3 - 2 * ty)
    let a = hash2(ix, iy, seed), b = hash2(ix + 1, iy, seed)
    let c = hash2(ix, iy + 1, seed), d = hash2(ix + 1, iy + 1, seed)
    return (a + (b - a) * ux) * (1 - uy) + (c + (d - c) * ux) * uy
}

func fbm(_ p: SIMD2<Float>, seed: UInt32) -> Float {
    valueNoise(p, seed: seed) * 0.55 + valueNoise(p * 2.03 + 11.3, seed: seed &+ 1) * 0.3
        + valueNoise(p * 4.07 + 5.1, seed: seed &+ 2) * 0.15
}
