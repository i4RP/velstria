import Foundation
import simd
import VelstriaCore

// 担当: battle-renderer（ステージ）。崖・木・茂み・遺跡・草花・草むらの配置と、チャンク毎の頂点の組み立て
// （純粋関数・乱数は種固定。背景スレッド可）。守るべき規則は docs/STAGE.md の 1 章:
// 硬く見えるものは壁の足跡の内側か地図の外だけ、足跡の外の歩ける所には低い草花だけを置く。

/// チャンク（12 m 格子）× 材質ごとに結合した頂点。画面に入るのは 20〜45 m 幅なので、細かいほど視錐台の外を描かずに済む。
struct StageChunks: Sendable {
    /// Meshy の小物（アトラスの材質）。
    var props: [Int: StageMeshBuffer] = [:]
    /// 崖の芯（三平面投影の岩と苔）。
    var rocks: [Int: StageMeshBuffer] = [:]
    /// 頂点色だけの草花・小石。
    var flora: [Int: StageMeshBuffer] = [:]

    static let size: Float = 12
    static let origin: Float = -20
    static let count = 14

    static func key(_ w: SIMD3<Float>) -> Int {
        let cx = max(0, min(count - 1, Int(floor((w.x - origin) / size))))
        let cz = max(0, min(count - 1, Int(floor((-w.z - origin) / size))))
        return cz * count + cx
    }

    var triangleCount: Int {
        props.values.reduce(0) { $0 + $1.triangleCount } + rocks.values.reduce(0) { $0 + $1.triangleCount }
            + flora.values.reduce(0) { $0 + $1.triangleCount }
    }
}

struct StageLayoutResult: Sendable {
    var chunks = StageChunks()
    /// index = MapDefinition.brushes の添字。頂点は草むらの中心が原点。
    var brushes: [StageMeshBuffer] = []
    var brushCenters: [SIMD3<Float>] = []
    /// 祭壇の円盤（ルーンの模様、RealityKit 標準材質の UV）。
    var runeDiscs = StageMeshBuffer()
    /// 地面に落とす影（配合マップの補助マップへ焼く）。
    var shades: [StageSplat.Shade] = []
    /// 小物の種類ごとの個数（計測用）。
    var counts: [StagePropKind: Int] = [:]
    /// 置いた小物（テスト用: 硬い物が歩ける所に無いことを確かめる）。
    var placements: [StagePlacement] = []
}

struct StagePlacement: Sendable {
    var kind: StagePropKind
    /// 足跡の中心（地図座標 m）。
    var center: SIMD2<Float>
    /// 足跡の半径（水平の長辺の半分、m）。
    var radius: Float
    /// 小物のローカル座標 → world。
    var transform: simd_float4x4
}

struct StageLayout {
    let map: MapDefinition
    let geo: StageGeometry
    let props: [StagePropKind: StagePropMesh]
    let density: Float
    let level: GraphicsQuality
    var rng: RenderRNG
    var out = StageLayoutResult()
    private var propTriangles = 0

    init(map: MapDefinition, props: [StagePropKind: StagePropMesh], density: Float, level: GraphicsQuality) {
        self.map = map
        geo = StageGeometry(map: map)
        self.props = props
        self.density = density
        self.level = level
        rng = RenderRNG(seed: 0x57A6E)
    }

    /// lite: UI テスト用（StagePrep.lite）。地図の外の崖と森を省き、描画の負荷を下げる。
    static func build(map: MapDefinition, props: [StagePropKind: StagePropMesh], density: Float,
                      level: GraphicsQuality, lite: Bool = false) -> StageLayoutResult {
        var l = StageLayout(map: map, props: props, density: density, level: level)
        l.walls()
        if !lite { l.border() }
        l.pits()
        l.groundFlora()
        l.brushFields()
        return l.out
    }

    // MARK: 座標

    @inline(__always) func world(_ p: SIMD2<Float>, _ y: Float = 0) -> SIMD3<Float> { SIMD3(p.x, y, -p.y) }

    /// 地図座標で角度 a（ローカル +X の向き）の Y 回転。
    @inline(__always) func transform(_ p: SIMD2<Float>, y: Float, yaw a: Float, scale s: SIMD3<Float>) -> simd_float4x4 {
        MX.t(world(p, y)) * MX.ry(a) * MX.s(s.x, s.y, s.z)
    }

    func tint(_ r: Float, _ g: Float, _ b: Float) -> SIMD4<UInt8> { stageColor(r * 0.5, g * 0.5, b * 0.5, 0) }

    mutating func rockTint() -> SIMD4<UInt8> {
        let v = rng.range(0.9, 1.08)
        let warm = rng.range(-0.04, 0.04)
        return tint(v * (1 + warm), v, v * (1 - warm))
    }

    mutating func leafTint() -> SIMD4<UInt8> {
        let v = rng.range(0.88, 1.08)
        let hue = rng.range(-1, 1)
        // + は黄緑寄り、− は青緑寄り
        return tint(v * (1 + hue * 0.08), v, v * (1 - hue * 0.1))
    }

    // MARK: 小物の配置

    private mutating func admitProp(_ mesh: StagePropMesh) -> Bool {
        let triangles = mesh.indices.count / 3
        guard triangles <= BattleWorkBudget.stagePropTriangles(level) - propTriangles else { return false }
        propTriangles += triangles
        return true
    }

    /// 小物を置く。footprint の中心が p、底が y。
    mutating func place(_ kind: StagePropKind, at p: SIMD2<Float>, y: Float, yaw: Float, scale s: SIMD3<Float>,
                        color: SIMD4<UInt8>? = nil) {
        guard let mesh = props[kind] else { return }
        // Wall cores and brush silhouettes have independent construction paths.
        // Stop decoration before new meshes/density silently exceed the GPU budget.
        guard admitProp(mesh) else { return }
        out.counts[kind, default: 0] += 1
        let m = transform(p, y: y, yaw: yaw, scale: s)
        out.placements.append(.init(kind: kind, center: p, radius: max(mesh.size.x * s.x, mesh.size.z * s.z) / 2, transform: m))
        let key = StageChunks.key(world(p))
        // 辞書から取り出してから足す（取り出さずに書き換えると配列全体が毎回複製される）
        var buf = out.chunks.props.removeValue(forKey: key) ?? StageMeshBuffer(reserveVertices: 4096)
        let c = color ?? (kind.isFoliage ? leafTint() : rockTint())
        if kind.isFoliage {
            let h = max(0.01, mesh.size.y)
            let start: Float = kind == .bush ? 0.15 : 0.38
            let gain: Float = kind == .bush ? 0.6 : 1
            buf.append(mesh, transform: m, color: c) { lp in smoothstep(start * h, h, lp.y) * gain }
        } else {
            buf.append(mesh, transform: m, color: c)
        }
        out.chunks.props[key] = buf
        if kind == .treeRound || kind == .treeTall {
            // 樹冠の影（南東へずらす）
            let r = max(mesh.size.x * s.x, mesh.size.z * s.z) * 0.5
            out.shades.append(.init(center: p + StageSplat.shadowDirection * (r * 0.7 + 0.4), radius: r * 1.05, strength: 0.42))
        }
    }

    /// 高さ h・水平の長辺 w になる倍率（縦横比を保つかどうかは呼び出し側）。
    func size(_ kind: StagePropKind) -> SIMD3<Float> { props[kind]?.size ?? SIMD3(1, 1, 1) }

    // MARK: 壁（崖）

    mutating func walls() {
        for (oi, o) in map.obstacles.enumerated() {
            switch o {
            case .rect(let r):
                let lo = geo.m(Vec2(r.minX, r.minY)), hi = geo.m(Vec2(r.maxX, r.maxY))
                rectWall(lo: lo, hi: hi, index: oi)
            case .circle(let c, let radius):
                circleWall(center: geo.m(c), radius: Float(radius / Balance.unitsPerMeter), index: oi)
            }
        }
    }

    /// 矩形の壁: 芯の岩山 + 4 辺に崖の岩 + 角に柱状の岩 + 上に茂みと木。
    mutating func rectWall(lo: SIMD2<Float>, hi: SIMD2<Float>, index: Int) {
        let w = hi.x - lo.x, d = hi.y - lo.y
        let coreH = rng.range(1.35, 1.6)
        // 芯
        let outline = StageLayout.roundedRect(lo: lo + 0.3, hi: hi - 0.3, radius: min(0.9, min(w, d) * 0.3), step: 0.8)
        let core = StageLayout.rockCore(outline: outline, height: coreH, topInset: 0.35, seed: UInt64(index) &* 977, tint: rockTint())
        appendRock(core, at: (lo + hi) / 2)
        // 辺の崖（外向き）。カメラは南から北を見下ろすので、高い物は奥（北）の地面を隠す。
        // 北の辺は低く（壁の向こうの歩ける所を隠さない）、南の辺は高く（隠すのは壁の上だけ）
        let rock = size(.cliffRockA)
        let sides: [(a: SIMD2<Float>, b: SIMD2<Float>, out: SIMD2<Float>)] = [
            (SIMD2(lo.x, lo.y), SIMD2(hi.x, lo.y), SIMD2(0, -1)),  // 南
            (SIMD2(hi.x, lo.y), SIMD2(hi.x, hi.y), SIMD2(1, 0)),   // 東
            (SIMD2(hi.x, hi.y), SIMD2(lo.x, hi.y), SIMD2(0, 1)),   // 北
            (SIMD2(lo.x, hi.y), SIMD2(lo.x, lo.y), SIMD2(-1, 0)),  // 西
        ]
        for (si, s) in sides.enumerated() {
            let len = simd_distance(s.a, s.b)
            let dir = (s.b - s.a) / max(len, 1e-3)
            let n = max(1, Int(ceil(len / 3.8)))
            let other = si % 2 == 0 ? d : w // 壁の奥行き（この辺に垂直）
            for k in 0..<n {
                // 短い辺では辺より長くしない（角の先へのはみ出しは片側 0.15 m まで）
                let width = min(len + 0.3, min(5.8, max(2.0, len / Float(n) * 1.3)))
                // 端の岩が角の先へはみ出さないように（はみ出しは 0.2 m まで）
                var along = (Float(k) + 0.5) / Float(n) * len + rng.range(-0.2, 0.2)
                along = len > width - 0.4 ? min(max(along, width / 2 - 0.2), len - width / 2 + 0.2) : len / 2
                let sx = width / rock.x
                let h = si == 0 ? rng.range(1.9, 2.5) : (si == 2 ? rng.range(1.4, 1.8) : rng.range(1.7, 2.3))
                let sy = h / rock.y
                // 奥行きは壁の厚みの 7 割まで（反対側の辺の岩と重なりすぎないように）
                let sz = min(sx, other * 0.7 / rock.z)
                let depth = rock.z * sz
                let p = s.a + dir * along - s.out * (depth / 2 - 0.08)
                let yaw = atan2(dir.y, dir.x) + (rng.chance(0.5) ? .pi : 0) + rng.range(-0.04, 0.04)
                place(.cliffRockA, at: p, y: -0.06, yaw: yaw, scale: SIMD3(sx, sy, sz))
            }
        }
        // 角
        let corners = [SIMD2(lo.x, lo.y), SIMD2(hi.x, lo.y), SIMD2(hi.x, hi.y), SIMD2(lo.x, hi.y)]
        for (ci, c) in corners.enumerated() {
            // 軸ごとに内側へ（向きによらない足跡の半径だけ入れ、はみ出しは 0.25 m まで）
            let sg = SIMD2<Float>(c.x < (lo.x + hi.x) / 2 ? 1 : -1, c.y < (lo.y + hi.y) / 2 ? 1 : -1)
            let north = ci >= 2
            if !north && rng.chance(0.6) {
                let b = size(.cliffRockB)
                let k = rng.range(2.0, 2.5) / b.y
                let r = simd_length(SIMD2(b.x, b.z)) * k / 2
                place(.cliffRockB, at: c + sg * max(0, r - 0.25), y: -0.06, yaw: rng.range(0, 6.28), scale: SIMD3(k, k, k))
            } else {
                let b = size(.boulder)
                let k = rng.range(1.5, 2.0) / max(b.x, b.z)
                let ky = min(k, (north ? 1.35 : 1.7) / b.y)
                let r = simd_length(SIMD2(b.x, b.z)) * k / 2
                place(.boulder, at: c + sg * max(0, r - 0.25), y: -0.08, yaw: rng.range(0, 6.28), scale: SIMD3(k, ky, k))
            }
        }
        // 上の茂みと木（内側 0.9 m より内）
        let ilo = lo + 0.9, ihi = hi - 0.9
        guard ihi.x > ilo.x, ihi.y > ilo.y else { return }
        let area = (ihi.x - ilo.x) * (ihi.y - ilo.y)
        let bushes = max(1, Int((area / 4.5 * density).rounded()))
        for _ in 0..<bushes {
            let p = SIMD2(rng.range(ilo.x, ihi.x), rng.range(ilo.y, ihi.y))
            let b = size(.bush)
            let k = rng.range(1.1, 1.8) / max(b.x, b.z)
            place(.bush, at: p, y: coreH - 0.25, yaw: rng.range(0, 6.28), scale: SIMD3(k, k * rng.range(0.85, 1.15), k))
        }
        let trees = Int((area / 13 * density).rounded())
        for t in 0..<trees {
            // 南（手前）に寄せる: 木が隠すのは壁の上になる（北に置くと壁の向こうの歩ける所を隠す）
            let p = SIMD2(rng.range(ilo.x, ihi.x), ilo.y + (ihi.y - ilo.y) * rng.range(0, 0.65))
            placeTree(at: p, y: coreH - 0.3, height: rng.range(2.8, 3.3), tall: t % 3 == 2)
        }
    }

    mutating func placeTree(at p: SIMD2<Float>, y: Float, height h: Float, tall: Bool) {
        let kind: StagePropKind = tall ? .treeTall : .treeRound
        let b = size(kind)
        let k = h / b.y
        place(kind, at: p, y: y, yaw: rng.range(0, 6.28), scale: SIMD3(k, k, k) * SIMD3(rng.range(0.92, 1.08), 1, rng.range(0.92, 1.08)))
    }

    /// 円の壁: 芯の岩山 + 周りに岩 + 上に茂み（大きければ木）。
    mutating func circleWall(center c: SIMD2<Float>, radius r: Float, index: Int) {
        let coreH = rng.range(1.1, 1.35)
        var outline: [SIMD2<Float>] = []
        let segs = 18
        for k in 0..<segs {
            let a = Float(k) / Float(segs) * 2 * .pi
            outline.append(c + SIMD2(cos(a), sin(a)) * (r - 0.3))
        }
        appendRock(StageLayout.rockCore(outline: outline, height: coreH, topInset: 0.3, seed: UInt64(index) &* 1307, tint: rockTint()), at: c)
        let n = max(3, Int((2 * .pi * r / 2.3).rounded()))
        let a0 = rng.range(0, 6.28)
        for k in 0..<n {
            let a = a0 + Float(k) / Float(n) * 2 * .pi
            let outward = SIMD2(cos(a), sin(a))
            // 北側（奥）は低く: 高いと壁の向こうの歩ける所を隠す
            let north = outward.y > 0.5
            let kind: StagePropKind = k % 3 == 1 ? .boulder : .cliffRockA
            let b = size(kind)
            let width = min(3.2, max(1.6, 2 * .pi * r / Float(n) * 1.25))
            let sx = width / b.x
            let h = north ? rng.range(1.25, 1.6) : rng.range(1.5, 2.1)
            let sy = h / b.y
            let sz = min(sx, r * 0.9 / b.z)
            let depth = b.z * sz
            // 接線方向の両端が円の外へ出すぎないよう、幅の半分だけ内側へ寄せる
            let half = width / 2
            let reach = (max(0, r * r - half * half)).squareRoot()
            let p = c + outward * (min(r - depth / 2 + 0.15, reach - depth / 2 + 0.25))
            // ローカル +X を接線（外向きの法線に垂直）へ
            let yaw = atan2(outward.y, outward.x) + .pi / 2
            place(kind, at: p, y: -0.06, yaw: yaw, scale: SIMD3(sx, sy, sz))
        }
        let b = size(.bush)
        let k = min(1.8, r * 0.9) / max(b.x, b.z)
        place(.bush, at: c + SIMD2(rng.range(-0.3, 0.3), rng.range(-0.3, 0.3)), y: coreH - 0.2, yaw: rng.range(0, 6.28), scale: SIMD3(k, k, k))
        if r >= 2.5 && rng.chance(0.75 * density) {
            placeTree(at: c + SIMD2(rng.range(-0.4, 0.4), rng.range(0, 0.6)), y: coreH - 0.25, height: rng.range(2.8, 3.3), tall: rng.chance(0.3))
        }
    }

    mutating func appendRock(_ core: StageMeshBuffer, at p: SIMD2<Float>) {
        let key = StageChunks.key(world(p))
        var buf = out.chunks.rocks.removeValue(forKey: key) ?? StageMeshBuffer(reserveVertices: 2048)
        buf.append(core)
        out.chunks.rocks[key] = buf
    }

    // MARK: 地図の外（崖の壁と森）

    mutating func border() {
        let M = geo.mapMeters
        let rock = size(.cliffRockA)
        // 4 辺: (始点, 向き, 外向き)
        let sides: [(start: SIMD2<Float>, dir: SIMD2<Float>, out: SIMD2<Float>, south: Bool)] = [
            (SIMD2(-16, 0), SIMD2(1, 0), SIMD2(0, -1), true),
            (SIMD2(M, -16), SIMD2(0, 1), SIMD2(1, 0), false),
            (SIMD2(M + 16, M), SIMD2(-1, 0), SIMD2(0, 1), false),
            (SIMD2(0, M + 16), SIMD2(0, -1), SIMD2(-1, 0), false),
        ]
        let len = M + 32
        let step = 4.4 / max(0.6, density)
        for s in sides {
            // 縁の崖（南は低く、少し外へ）
            var t: Float = 0
            while t < len {
                let width = rng.range(4.8, 6.2)
                let sx = width / rock.x
                let h = s.south ? rng.range(1.1, 1.5) : rng.range(2.0, 2.9)
                let sy = h / rock.y
                let sz = sx * rng.range(0.9, 1.2)
                let off: Float = (s.south ? 2.4 : 1.3) + rock.z * sz * 0.5
                let p = s.start + s.dir * t + s.out * off
                place(.cliffRockA, at: p, y: -0.1, yaw: atan2(s.dir.y, s.dir.x) + (rng.chance(0.5) ? .pi : 0), scale: SIMD3(sx, sy, sz))
                t += width * 0.82
            }
            // 森（2〜3 列）。南は木を遠くへ（手前を隠さない）
            let rows: [Float] = s.south ? [8.5] : [5.2, 10.0]
            for (ri, depth) in rows.enumerated() {
                var u: Float = rng.range(0, step)
                while u < len {
                    let p = s.start + s.dir * u + s.out * (depth + rng.range(-1.0, 1.0))
                    let tall = ri == rows.count - 1 ? rng.chance(0.6) : rng.chance(0.25)
                    placeTree(at: p, y: -0.05, height: tall ? rng.range(4.4, 5.4) : rng.range(3.6, 4.6), tall: tall)
                    if ri == 0 && rng.chance(0.6 * density) {
                        let bp = p + s.dir * rng.range(-1.6, 1.6) - s.out * rng.range(1.2, 2.2)
                        let b = size(.bush)
                        let k = rng.range(1.4, 2.2) / max(b.x, b.z)
                        place(.bush, at: bp, y: -0.05, yaw: rng.range(0, 6.28), scale: SIMD3(k, k, k))
                    }
                    // 奥の列は画面に入ることが少ないので間隔を広げる
                    u += step * rng.range(0.85, 1.25) * (ri == 0 ? 1 : 1.5)
                }
            }
        }
        // 四隅の柱状の岩
        let corners = [SIMD2<Float>(-3, -3), SIMD2(M + 3, -3), SIMD2(M + 3, M + 3), SIMD2(-3, M + 3)]
        for (ci, c) in corners.enumerated() {
            let b = size(.cliffRockB)
            let h: Float = ci < 2 ? 1.8 : rng.range(2.8, 3.4)
            let k = h / b.y
            place(.cliffRockB, at: c, y: -0.1, yaw: rng.range(0, 6.28), scale: SIMD3(k, k, k))
        }
    }

    // MARK: 祭壇（ボスの巣・番人のキャンプ）

    mutating func pits() {
        for camp in map.camps {
            let c = geo.m(camp.pos)
            switch camp.kind {
            case .astralWyrm, .ancientColossus:
                runeDisc(center: c, radius: 5.6, rotation: camp.kind == .astralWyrm ? 0.2 : 1.0)
                pitRuins(center: c)
            case .blueSentinel, .redSentinel:
                runeDisc(center: c, radius: 2.5, rotation: Float(camp.id) * 0.7)
            case .small:
                break
            }
        }
    }

    mutating func runeDisc(center c: SIMD2<Float>, radius r: Float, rotation: Float) {
        let segs = 64
        let y = GroundLayer.paving
        let up = SIMD3<Float>(0, 1, 0)
        let col = stageColor(0.5, 0.5, 0.5, 0)
        // 模様の向き: 画像の上端が北（RealityKit 標準材質の UV は下端 0）
        func uv(_ q: SIMD2<Float>) -> SIMD2<Float> {
            let l = rotate(q, rotation)
            return SIMD2(0.5 + l.x / (2 * r), 0.5 + l.y / (2 * r))
        }
        let ci = out.runeDiscs.addVertex(world(c, y), up, uv(.zero), col)
        var ring: [UInt32] = []
        for k in 0..<segs {
            let a = Float(k) / Float(segs) * 2 * .pi
            let q = SIMD2(cos(a), sin(a)) * r
            ring.append(out.runeDiscs.addVertex(world(c + q, y), up, uv(q), col))
        }
        for k in 0..<segs {
            // 上から見て反時計回り（法線 +Y）
            out.runeDiscs.addTriangle(ci, ring[k], ring[(k + 1) % segs])
        }
    }

    func rotate(_ v: SIMD2<Float>, _ a: Float) -> SIMD2<Float> {
        SIMD2(cos(a) * v.x - sin(a) * v.y, sin(a) * v.x + cos(a) * v.y)
    }

    /// ボスの巣のまわりの遺跡は、近くの壁の足跡の内側にだけ置く（歩ける所に硬い物を置かない）。
    mutating func pitRuins(center c: SIMD2<Float>) {
        var placed = 0
        for r in geo.rects {
            let rc = (r.min + r.max) / 2
            guard simd_distance(rc, c) < 14, placed < 2 else { continue }
            // 巣に面した辺の内側に柱を 1〜2 本
            let toPit = simd_normalize(c - rc)
            let edge = SIMD2(min(max(c.x, r.min.x + 0.9), r.max.x - 0.9), min(max(c.y, r.min.y + 0.9), r.max.y - 0.9))
            let b = size(.ruinPillar)
            let k = rng.range(2.1, 2.5) / b.y
            place(.ruinPillar, at: edge, y: 0.6, yaw: atan2(toPit.y, toPit.x), scale: SIMD3(k, k, k), color: tint(1, 1, 1))
            placed += 1
        }
        for circle in geo.circles where simd_distance(circle.center, c) < 10 && placed < 3 {
            let b = size(.ruinPillar)
            let k = rng.range(2.0, 2.4) / b.y
            let toPit = simd_normalize(c - circle.center)
            place(.ruinPillar, at: circle.center + toPit * (circle.radius * 0.45), y: 0.7, yaw: atan2(toPit.y, toPit.x),
                  scale: SIMD3(k, k, k), color: tint(1, 1, 1))
            placed += 1
        }
    }

    // MARK: 草花・小石（歩ける所。背の低いものだけ）

    /// 歩ける地面の小物を置いてよい場所か（レーン・川・石畳・壁・草むらを避ける）。
    func isFloraSpot(_ p: SIMD2<Float>) -> Bool {
        guard p.x > 0.5, p.y > 0.5, p.x < geo.mapMeters - 0.5, p.y < geo.mapMeters - 0.5 else { return false }
        if geo.laneDistance(p) < 4.4 { return false }
        if geo.riverDistance(p) < Float(map.riverWidth / 100) / 2 + 0.6 { return false }
        if geo.obstacleDistance(p) < 0.15 { return false }
        if geo.brushDistance(p) < 0.3 { return false }
        for team in Team.players {
            if simd_distance(p, geo.m(map.fountain(team))) < 10.5 || simd_distance(p, geo.m(map.core(team))) < 15 { return false }
        }
        for c in map.camps where simd_distance(p, geo.m(c.pos)) < (c.kind == .small ? 3.6 : 8.6) { return false }
        for t in map.towers where simd_distance(p, geo.m(t.pos)) < 3.4 { return false }
        return true
    }

    mutating func groundFlora() {
        let M = geo.mapMeters
        let tufts = Int(1400 * density)
        var placed = 0, attempts = 0
        while placed < tufts && attempts < tufts * 6 {
            attempts += 1
            let p = SIMD2(rng.range(0, M), rng.range(0, M))
            guard isFloraSpot(p) else { continue }
            // 壁際ほど濃く
            let dObs = geo.obstacleDistance(p)
            if dObs > 3 && !rng.chance(0.35) { continue }
            placed += 1
            var buf = out.chunks.flora.removeValue(forKey: StageChunks.key(world(p))) ?? StageMeshBuffer(reserveVertices: 2048)
            grassTuft(&buf, at: p, height: rng.range(0.28, 0.55), blades: Int(rng.range(7, 11)))
            if rng.chance(0.22) { flowers(&buf, at: p + SIMD2(rng.range(-0.4, 0.4), rng.range(-0.4, 0.4))) }
            out.chunks.flora[StageChunks.key(world(p))] = buf
            // 低い葉の茂み（膝下。歩ける所に置いてよい高さ）
            if level != .low && ((dObs < 1.5 && rng.chance(0.3)) || rng.chance(0.02)) {
                groundCover(at: p + SIMD2(rng.range(-0.6, 0.6), rng.range(-0.6, 0.6)))
            }
        }
        // 壁の根元の小石・低い茂み（足跡の内側ぎりぎり）
        for r in geo.rects {
            let perim = 2 * ((r.max.x - r.min.x) + (r.max.y - r.min.y))
            let n = Int(perim / 2.2 * density)
            for _ in 0..<n {
                let t = rng.range(0, 4)
                let side = Int(t), f = t - Float(side)
                let p: SIMD2<Float>
                switch side {
                case 0: p = SIMD2(r.min.x + f * (r.max.x - r.min.x), r.min.y + 0.05)
                case 1: p = SIMD2(r.max.x - 0.05, r.min.y + f * (r.max.y - r.min.y))
                case 2: p = SIMD2(r.min.x + f * (r.max.x - r.min.x), r.max.y - 0.05)
                default: p = SIMD2(r.min.x + 0.05, r.min.y + f * (r.max.y - r.min.y))
                }
                var buf = out.chunks.flora.removeValue(forKey: StageChunks.key(world(p))) ?? StageMeshBuffer(reserveVertices: 2048)
                pebble(&buf, at: p, size: rng.range(0.18, 0.34))
                grassTuft(&buf, at: p + SIMD2(rng.range(-0.3, 0.3), rng.range(-0.3, 0.3)), height: rng.range(0.3, 0.5), blades: 6)
                out.chunks.flora[StageChunks.key(world(p))] = buf
            }
        }
        // 川岸の小石と葦
        let riverHalf = Float(map.riverWidth / 100) / 2
        let bankCount = Int(260 * density)
        for _ in 0..<bankCount {
            let s = rng.range(-8, M + 8)
            let side: Float = rng.chance(0.5) ? 1 : -1
            let along = SIMD2<Float>(s, M - s)
            let normal = SIMD2<Float>(0.70710678, 0.70710678)
            let p = along + normal * side * (riverHalf + rng.range(-0.2, 0.7))
            guard p.x > 0.5, p.y > 0.5, p.x < M - 0.5, p.y < M - 0.5, geo.laneDistance(p) > 4.6,
                  geo.obstacleDistance(p) > 0.2 else { continue }
            var nearPit = false
            for c in map.camps where (c.kind == .astralWyrm || c.kind == .ancientColossus) && simd_distance(p, geo.m(c.pos)) < 9 { nearPit = true }
            if nearPit { continue }
            var buf = out.chunks.flora.removeValue(forKey: StageChunks.key(world(p))) ?? StageMeshBuffer(reserveVertices: 2048)
            if rng.chance(0.55) {
                pebble(&buf, at: p, size: rng.range(0.15, 0.32))
            } else {
                grassTuft(&buf, at: p, height: rng.range(0.45, 0.7), blades: 7, reed: true)
            }
            out.chunks.flora[StageChunks.key(world(p))] = buf
        }
    }

    /// 低い葉の茂み（bush を膝下の高さに潰したもの）。歩ける所に置くので、置いた記録（placements）には入れない。
    mutating func groundCover(at p: SIMD2<Float>) {
        guard let mesh = props[.bush], isFloraSpot(p), admitProp(mesh) else { return }
        let foot = rng.range(0.7, 1.2)
        let k = foot / max(mesh.size.x, mesh.size.z)
        let ky = rng.range(0.28, 0.4) / mesh.size.y
        let m = transform(p, y: -0.04, yaw: rng.range(0, 6.28), scale: SIMD3(k, ky, k))
        let key = StageChunks.key(world(p))
        var buf = out.chunks.props.removeValue(forKey: key) ?? StageMeshBuffer(reserveVertices: 4096)
        let h = max(0.01, mesh.size.y)
        buf.append(mesh, transform: m, color: leafTint()) { lp in smoothstep(0.1 * h, h, lp.y) * 0.5 }
        out.chunks.props[key] = buf
        out.counts[.bush, default: 0] += 1
    }

    /// 草の房（両面の細い葉）。
    mutating func grassTuft(_ buf: inout StageMeshBuffer, at p: SIMD2<Float>, height h: Float, blades: Int, reed: Bool = false) {
        let base = world(p, -0.02)
        let hueShift = rng.range(-0.06, 0.06)
        for _ in 0..<blades {
            let a = rng.range(0, 6.28)
            let lean = rng.range(0.15, 0.45)
            let dir = simd_normalize(SIMD3(cos(a) * lean, 1, -sin(a) * lean))
            let side = simd_normalize(simd_cross(dir, SIMD3(cos(a + 1.3), 0, -sin(a + 1.3))))
            let bh = h * rng.range(0.7, 1.15)
            let root = base + SIMD3(rng.range(-0.06, 0.06), 0, rng.range(-0.06, 0.06))
            let dark: SIMD3<Float> = reed ? SIMD3(0.16, 0.26, 0.12) : SIMD3(0.07, 0.2, 0.08)
            let tip: SIMD3<Float> = reed ? SIMD3(0.62, 0.66, 0.36) : SIMD3(0.42 + hueShift, 0.66, 0.24)
            buf.blade(base: root, direction: dir, side: side, height: bh, width: reed ? 0.04 : 0.06, bend: rng.range(0.1, 0.3),
                      segments: 1) { t in
                let c = dark + (tip - dark) * t
                return stageColor(c.x, c.y, c.z, t * 0.6)
            }
        }
    }

    /// 小さな花（4 枚の花びら）。
    mutating func flowers(_ buf: inout StageMeshBuffer, at p: SIMD2<Float>) {
        let palette: [SIMD3<Float>] = [SIMD3(0.95, 0.95, 0.88), SIMD3(0.98, 0.86, 0.35), SIMD3(0.9, 0.55, 0.7), SIMD3(0.7, 0.8, 1.0)]
        let col = palette[Int(rng.nextFloat() * Float(palette.count)) % palette.count]
        for _ in 0..<Int(rng.range(2, 5)) {
            let q = p + SIMD2(rng.range(-0.25, 0.25), rng.range(-0.25, 0.25))
            let y = rng.range(0.08, 0.16)
            let c = world(q, y)
            let r = rng.range(0.035, 0.055)
            let up = SIMD3<Float>(0, 1, 0)
            let cc = stageColor(col.x, col.y, col.z, 0.3)
            let center = buf.addVertex(c + SIMD3(0, 0.005, 0), up, .zero, stageColor(1, 0.85, 0.3, 0.3))
            var ring: [UInt32] = []
            for k in 0..<8 {
                let a = Float(k) / 8 * 2 * .pi
                let rr = k % 2 == 0 ? r : r * 0.45
                ring.append(buf.addVertex(c + SIMD3(cos(a) * rr, 0, -sin(a) * rr), up, .zero, cc))
            }
            for k in 0..<8 { buf.addTriangle(center, ring[k], ring[(k + 1) % 8]) }
        }
    }

    /// 小石（低い多面体）。
    mutating func pebble(_ buf: inout StageMeshBuffer, at p: SIMD2<Float>, size s: Float) {
        let (verts, faces) = MeshBuilder.icosahedron()
        let c = world(p, 0)
        let squash = rng.range(0.45, 0.7)
        let shade = rng.range(0.14, 0.24) // 線形値（sRGB で 0.4〜0.53 程度の灰色）
        let col = stageColor(shade, shade * 1.02, shade * 1.06, 0)
        var moved: [SIMD3<Float>] = []
        for v in verts {
            let j = 1 + rng.range(-0.18, 0.18)
            moved.append(c + SIMD3(v.x * s * j, max(-0.02, v.y * s * squash * j), v.z * s * j))
        }
        for f in faces {
            let a = moved[f.0], b = moved[f.1], d = moved[f.2]
            let cr = simd_cross(b - a, d - a)
            guard simd_length(cr) > 1e-7 else { continue } // 底を潰した面は縮退する
            let n = simd_normalize(cr)
            let top = max(0, n.y)
            let cc = stageColor(Float(col.x) / 255 * (0.8 + 0.35 * top), Float(col.y) / 255 * (0.8 + 0.35 * top + 0.08 * top),
                                Float(col.z) / 255 * (0.8 + 0.3 * top), 0)
            let i0 = buf.addVertex(a, n, .zero, cc), i1 = buf.addVertex(b, n, .zero, cc), i2 = buf.addVertex(d, n, .zero, cc)
            buf.addTriangle(i0, i1, i2)
        }
    }

    // MARK: 草むら

    mutating func brushFields() {
        let step: Float = level == .low ? 0.55 : 0.45
        for b in map.brushes {
            let lo = geo.m(Vec2(b.rect.minX, b.rect.minY)), hi = geo.m(Vec2(b.rect.maxX, b.rect.maxY))
            let center = (lo + hi) / 2
            var buf = StageMeshBuffer(reserveVertices: 20_000)
            var brng = RenderRNG(seed: UInt64(b.id) &* 613 &+ 7)
            let w = hi.x - lo.x, d = hi.y - lo.y
            let nx = max(1, Int((w / step).rounded())), ny = max(1, Int((d / step).rounded()))
            for ix in 0..<nx {
                for iy in 0..<ny {
                    let lx = (Float(ix) + 0.5) / Float(nx) * w - w / 2 + brng.range(-0.12, 0.12)
                    let ly = (Float(iy) + 0.5) / Float(ny) * d - d / 2 + brng.range(-0.12, 0.12)
                    // 縁の房は内側へ少し倒す（見た目の縁を判定の矩形に合わせる: はみ出しは 0.5 m 以内）
                    let edgeX = abs(lx) / (w / 2), edgeY = abs(ly) / (d / 2)
                    let inward = SIMD2<Float>(edgeX > 0.6 ? (lx > 0 ? -1 : 1) : 0, edgeY > 0.6 ? (ly > 0 ? -1 : 1) : 0)
                    let root = SIMD2(min(max(lx, -w / 2 + 0.08), w / 2 - 0.08), min(max(ly, -d / 2 + 0.08), d / 2 - 0.08))
                    brushClump(&buf, rng: &brng, at: root, lean: inward)
                }
            }
            out.brushes.append(buf)
            out.brushCenters.append(world(center))
        }
    }

    /// 草むらの 1 房（背の高い葉 6〜9 枚）。座標は草むらの中心が原点。
    func brushClump(_ buf: inout StageMeshBuffer, rng: inout RenderRNG, at p: SIMD2<Float>, lean: SIMD2<Float>) {
        let blades = Int(rng.range(5, 8))
        let base = SIMD3<Float>(p.x, -0.03, -p.y)
        let hueShift = rng.range(-0.05, 0.05)
        for _ in 0..<blades {
            let a = rng.range(0, 6.28)
            let l = rng.range(0.08, 0.26)
            var dirXZ = SIMD2<Float>(cos(a), sin(a)) * l + lean * 0.14
            if simd_length(dirXZ) > 0.32 { dirXZ = simd_normalize(dirXZ) * 0.32 }
            let dir = simd_normalize(SIMD3(dirXZ.x, 1, -dirXZ.y))
            let side = simd_normalize(simd_cross(dir, SIMD3(cos(a + 1.2), 0, -sin(a + 1.2))))
            let h = rng.range(0.85, 1.3)
            let root = base + SIMD3(rng.range(-0.06, 0.06), 0, rng.range(-0.06, 0.06))
            let yellow = rng.chance(0.12)
            let dark = SIMD3<Float>(0.04, 0.14, 0.06)
            let mid = SIMD3<Float>(0.1, 0.33, 0.13)
            let tip: SIMD3<Float> = yellow ? SIMD3(0.62, 0.66, 0.26) : SIMD3(0.36 + hueShift, 0.62, 0.22)
            buf.blade(base: root, direction: dir, side: side, height: h, width: rng.range(0.1, 0.15), bend: rng.range(0.08, 0.24),
                      segments: 2) { t in
                let c = t < 0.5 ? dark + (mid - dark) * (t * 2) : mid + (tip - mid) * ((t - 0.5) * 2)
                return stageColor(c.x, c.y, c.z, t)
            }
        }
    }

    // MARK: 形状の生成

    /// 角を丸めた矩形の輪郭（反時計回り）。
    static func roundedRect(lo: SIMD2<Float>, hi: SIMD2<Float>, radius r: Float, step: Float) -> [SIMD2<Float>] {
        var pts: [SIMD2<Float>] = []
        let r = max(0.05, min(r, min(hi.x - lo.x, hi.y - lo.y) / 2 - 0.01))
        let centers = [SIMD2(hi.x - r, lo.y + r), SIMD2(hi.x - r, hi.y - r), SIMD2(lo.x + r, hi.y - r), SIMD2(lo.x + r, lo.y + r)]
        let starts: [Float] = [-.pi / 2, 0, .pi / 2, .pi]
        for k in 0..<4 {
            // 角の弧
            for j in 0...3 {
                let a = starts[k] + Float(j) / 3 * (.pi / 2)
                pts.append(centers[k] + SIMD2(cos(a), sin(a)) * r)
            }
            // 次の角までの辺を分割
            let from = centers[k] + SIMD2(cos(starts[k] + .pi / 2), sin(starts[k] + .pi / 2)) * r
            let to = centers[(k + 1) % 4] + SIMD2(cos(starts[(k + 1) % 4]), sin(starts[(k + 1) % 4])) * r
            let len = simd_distance(from, to)
            let n = Int(len / step)
            if n >= 1 {
                for j in 1...n { pts.append(from + (to - from) * (Float(j) / Float(n + 1))) }
            }
        }
        return pts
    }

    /// 崖の芯の岩山（輪郭を押し出し、上をすぼめて凹凸を付ける）。法線は滑らか。
    static func rockCore(outline: [SIMD2<Float>], height h: Float, topInset: Float, seed: UInt64, tint: SIMD4<UInt8>) -> StageMeshBuffer {
        var rng = RenderRNG(seed: seed | 1)
        let n = outline.count
        guard n >= 3 else { return StageMeshBuffer() }
        let center = outline.reduce(SIMD2<Float>.zero, +) / Float(n)
        // 段: (高さの割合, 外への張り出し m)
        let levels: [(Float, Float)] = [(-0.08, 0.0), (0.45, 0.12), (0.8, -topInset * 0.4), (1.0, -topInset)]
        var rings: [[SIMD3<Float>]] = []
        for (li, (fy, push)) in levels.enumerated() {
            var ring: [SIMD3<Float>] = []
            for k in 0..<n {
                let p = outline[k]
                let out = simd_length(p - center) > 1e-4 ? simd_normalize(p - center) : SIMD2(1, 0)
                let jitter = li == 0 ? 0 : rng.range(-0.12, 0.12)
                let q = p + out * (push + jitter)
                let y = fy < 0 ? fy : h * fy + (li == levels.count - 1 ? rng.range(-0.12, 0.1) : rng.range(-0.06, 0.06))
                ring.append(SIMD3(q.x, y, -q.y))
            }
            rings.append(ring)
        }
        // 頂点（共有）と三角形
        var positions: [SIMD3<Float>] = rings.flatMap { $0 }
        let top = SIMD3<Float>(center.x, h + 0.08, -center.y)
        positions.append(top)
        let topIndex = positions.count - 1
        var tris: [(Int, Int, Int)] = []
        func idx(_ ring: Int, _ k: Int) -> Int { ring * n + (k % n) }
        // 側面: 輪郭は地図座標で反時計回り → 外から見て反時計回りになる順で
        for r in 0..<(rings.count - 1) {
            for k in 0..<n {
                let a = idx(r, k), b = idx(r, k + 1), c = idx(r + 1, k + 1), d = idx(r + 1, k)
                tris.append((a, b, c))
                tris.append((a, c, d))
            }
        }
        let last = rings.count - 1
        for k in 0..<n { tris.append((idx(last, k), idx(last, k + 1), topIndex)) }
        // 向きの確認（外向きでなければ全体を反転）
        var score: Float = 0
        for t in tris {
            let a = positions[t.0], b = positions[t.1], c = positions[t.2]
            let nrm = simd_cross(b - a, c - a)
            let mid = (a + b + c) / 3
            score += simd_dot(nrm, mid - SIMD3(center.x, h * 0.4, -center.y))
        }
        if score < 0 { tris = tris.map { ($0.0, $0.2, $0.1) } }
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for t in tris {
            let a = positions[t.0], b = positions[t.1], c = positions[t.2]
            let nrm = simd_cross(b - a, c - a)
            normals[t.0] += nrm
            normals[t.1] += nrm
            normals[t.2] += nrm
        }
        var buf = StageMeshBuffer(reserveVertices: positions.count)
        for (i, p) in positions.enumerated() {
            let nn = simd_length(normals[i]) > 1e-6 ? simd_normalize(normals[i]) : SIMD3<Float>(0, 1, 0)
            positions[i] = p
            buf.addVertex(p, nn, .zero, tint)
        }
        for t in tris { buf.addTriangle(UInt32(t.0), UInt32(t.1), UInt32(t.2)) }
        return buf
    }
}
