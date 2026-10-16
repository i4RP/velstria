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
    var brushCards: [StageMeshBuffer] = []
    var brushCenters: [SIMD3<Float>] = []
    /// 祭壇の円盤（ルーンの模様、RealityKit 標準材質の UV）。
    var runeDiscs = StageMeshBuffer()
    /// 地面に落とす影（配合マップの補助マップへ焼く）。
    var shades: [StageSplat.Shade] = []
    /// 小物の種類ごとの個数（計測用）。
    var counts: [StagePropKind: Int] = [:]
    /// 置いた小物（テスト用: 硬い物が歩ける所に無いことを確かめる）。
    var placements: [StagePlacement] = []
    /// 泉の台座（新セットの spawn_dais）の柱の頂部の受け皿（world）。添字 = Team.players の順。台座が無いセットでは空。
    /// MapScene がここへチーム色の小さな結晶を置く。
    var fountainSockets: [[SIMD3<Float>]] = []
    /// 地図の外の暗がり（頂点色の板。border が作る。lite では空）。
    var edgeSkirt = StageMeshBuffer()
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
    /// 新セット（泉の台座がある = StageArtSet.ruins）の色合わせ。配置と乱数の消費は旧セットと同じ。
    let ruinsLook: Bool
    var rng: RenderRNG
    var out = StageLayoutResult()
    private var propTriangles = 0

    init(map: MapDefinition, props: [StagePropKind: StagePropMesh], density: Float, level: GraphicsQuality) {
        self.map = map
        geo = StageGeometry(map: map)
        self.props = props
        self.density = density
        self.level = level
        ruinsLook = props[.spawnDais] != nil
        rng = RenderRNG(seed: 0x57A6E)
    }

    /// lite: UI テスト用（StagePrep.lite）。地図の外の崖と森を省き、描画の負荷を下げる。
    static func build(map: MapDefinition, props: [StagePropKind: StagePropMesh], density: Float,
                      level: GraphicsQuality, lite: Bool = false) -> StageLayoutResult {
        var l = StageLayout(map: map, props: props, density: density, level: level)
        // 泉の台座は試合の目印なので、装飾の三角形の予算で省かれないよう最初に置く
        l.fountains()
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
        // 新セットは Tripo の葉の色が暗いので少し明るく
        let v = rng.range(0.88, 1.08) * (ruinsLook ? 1.1 : 1)
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
            case .polygon(let points):
                polygonWall(points.map { geo.m($0) }, index: oi)
            }
        }
    }

    /// 矩形の壁: 足跡いっぱいの一枚岩（slabCore）+ 上に茂みと木。
    /// 2026-10-16 まで辺に崖の岩・角に柱状の岩を並べていたが、境界がガタガタで隙間が暗く見えたので一枚岩にした。
    mutating func rectWall(lo: SIMD2<Float>, hi: SIMD2<Float>, index: Int) {
        if ruinsLook && isRiverRuin((lo + hi) / 2) {
            masonryWall(outline: StageLayout.roundedRect(lo: lo + 0.12, hi: hi - 0.12,
                                                        radius: 0.35, step: 0.8), center: (lo + hi) / 2)
            return
        }
        let coreH = rng.range(1.85, 2.15)
        // 角は少し丸める（衝突は角をユニットの半径で丸めた膨張。足元は裾 0.28 m の張り出しで角の近くまで埋まる）。
        // 半径は上面の縁の入り（slabCore の inset、最大 0.55 m・短辺の 0.28 倍）以上にする（小さいと角で上面の輪が裏返る）
        let outline = StageLayout.roundedRect(lo: lo, hi: hi, radius: min(0.6, min(hi.x - lo.x, hi.y - lo.y) * 0.45), step: 1.1)
        appendRock(StageLayout.slabCore(outline: outline, height: coreH, seed: UInt64(index) &* 977, tint: rockTint()), at: (lo + hi) / 2)
        // 上の茂みと木（内側 0.9 m より内。上面は北ほど低いので少し沈める）
        let top = coreH * 0.92
        let ilo = lo + 0.9, ihi = hi - 0.9
        guard ihi.x > ilo.x, ihi.y > ilo.y else { return }
        let area = (ihi.x - ilo.x) * (ihi.y - ilo.y)
        let bushes = max(1, Int((area / 4.5 * density).rounded()))
        for _ in 0..<bushes {
            let p = SIMD2(rng.range(ilo.x, ihi.x), rng.range(ilo.y, ihi.y))
            let b = size(.bush)
            let k = rng.range(1.1, 1.8) / max(b.x, b.z)
            place(.bush, at: p, y: top - 0.25, yaw: rng.range(0, 6.28), scale: SIMD3(k, k * rng.range(0.85, 1.15), k))
        }
        let trees = Int((area / 13 * density).rounded())
        for t in 0..<trees {
            // 南（手前）に寄せる: 木が隠すのは壁の上になる（北に置くと壁の向こうの歩ける所を隠す）
            let p = SIMD2(rng.range(ilo.x, ihi.x), ilo.y + (ihi.y - ilo.y) * rng.range(0, 0.65))
            placeTree(at: p, y: top - 0.3, height: rng.range(2.8, 3.3), tall: t % 3 == 2)
        }
    }

    mutating func placeTree(at p: SIMD2<Float>, y: Float, height h: Float, tall: Bool) {
        let kind: StagePropKind = tall ? .treeTall : .treeRound
        let b = size(kind)
        let k = h / b.y
        place(kind, at: p, y: y, yaw: rng.range(0, 6.28), scale: SIMD3(k, k, k) * SIMD3(rng.range(0.92, 1.08), 1, rng.range(0.92, 1.08)))
    }

    /// 円の壁: 足跡いっぱいの丸い一枚岩 + 上に茂み（大きければ木）。
    mutating func circleWall(center c: SIMD2<Float>, radius r: Float, index: Int) {
        if ruinsLook && isRiverRuin(c) {
            let outline = (0..<16).map { k -> SIMD2<Float> in
                let a = Float(k) / 16 * 2 * Float.pi
                return c + SIMD2(cos(a), sin(a)) * (r - 0.12)
            }
            masonryWall(outline: outline, center: c)
            return
        }
        let coreH = rng.range(1.5, 1.8)
        var outline: [SIMD2<Float>] = []
        let segs = max(16, Int((2 * .pi * r / 0.9).rounded()))
        for k in 0..<segs {
            let a = Float(k) / Float(segs) * 2 * .pi
            outline.append(c + SIMD2(cos(a), sin(a)) * r)
        }
        appendRock(StageLayout.slabCore(outline: outline, height: coreH, seed: UInt64(index) &* 1307, tint: rockTint()), at: c)
        let b = size(.bush)
        let k = min(1.8, r * 0.9) / max(b.x, b.z)
        place(.bush, at: c + SIMD2(rng.range(-0.3, 0.3), rng.range(-0.3, 0.3)), y: coreH - 0.3, yaw: rng.range(0, 6.28), scale: SIMD3(k, k, k))
        if r >= 2.5 && rng.chance(0.75 * density) {
            placeTree(at: c + SIMD2(rng.range(-0.4, 0.4), rng.range(-0.6, 0)), y: coreH - 0.35, height: rng.range(2.8, 3.3), tall: rng.chance(0.3))
        }
    }

    /// 多角形の壁（2026-10-16、MLBB のミニマップ原本から起こした滑らかな輪郭）: 足跡いっぱいの一枚岩（slopedSlab）+ 上に茂みと木。
    mutating func polygonWall(_ outline: [SIMD2<Float>], index: Int) {
        guard outline.count >= 3 else { return }
        let wallCenter = outline.reduce(SIMD2<Float>.zero, +) / Float(outline.count)
        if ruinsLook && isRiverRuin(wallCenter) {
            masonryWall(outline: StageLayout.signedArea(outline) < 0 ? Array(outline.reversed()) : outline, center: wallCenter)
            return
        }
        let slab = StageLayout.slopedSlab(outline: outline, seed: UInt64(index) &* 1733, tint: rockTint(),
                                          fine: level != .low, refine: level == .high)
        let center = outline.reduce(SIMD2<Float>.zero, +) / Float(outline.count)
        appendRock(slab.mesh, at: center)
        // 上の茂みと木: 上面の輪の内側（縁から 0.45 m より内）。上面は頂点ごとに高さが違うので低い方に合わせて少し沈める
        let top = slab.top
        guard top.count >= 3 else { return }
        var lo = top[0], hi = top[0]
        for p in top { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let area = abs(StageLayout.signedArea(top))
        func spot(southBias: Bool) -> SIMD2<Float>? {
            for _ in 0..<12 {
                let p = SIMD2(rng.range(lo.x, hi.x), southBias ? rng.range(lo.y, lo.y + (hi.y - lo.y) * 0.65) : rng.range(lo.y, hi.y))
                if polygonDistance(p, top) < -0.45 { return p }
            }
            return nil
        }
        let bushes = Int((area / 4.5 * density).rounded())
        for _ in 0..<bushes {
            guard let p = spot(southBias: false) else { continue }
            let b = size(.bush)
            let k = rng.range(1.0, 1.6) / max(b.x, b.z)
            place(.bush, at: p, y: slab.minTopHeight - 0.25, yaw: rng.range(0, 6.28), scale: SIMD3(k, k * rng.range(0.85, 1.15), k))
        }
        // 木は南（手前）寄り: 木が隠すのは壁の上になる
        let trees = Int((area / 14 * density).rounded())
        for t in 0..<trees {
            guard let p = spot(southBias: true) else { continue }
            placeTree(at: p, y: slab.minTopHeight - 0.3, height: rng.range(2.6, 3.2), tall: t % 3 == 2)
        }
    }

    mutating func appendRock(_ core: StageMeshBuffer, at p: SIMD2<Float>) {
        let key = StageChunks.key(world(p))
        var buf = out.chunks.rocks.removeValue(forKey: key) ?? StageMeshBuffer(reserveVertices: 2048)
        buf.append(core)
        out.chunks.rocks[key] = buf
    }

    /// 川沿いの既存の衝突形状を、そのまま低い石積みへ置き換える。
    func isRiverRuin(_ p: SIMD2<Float>) -> Bool {
        let center = SIMD2<Float>(repeating: geo.mapMeters / 2)
        if simd_distance(p, center) < 16 { return true }
        return map.camps.contains {
            ($0.kind == .astralWyrm || $0.kind == .ancientColossus) && simd_distance(p, geo.m($0.pos)) < 10
        }
    }

    mutating func masonryWall(outline: [SIMD2<Float>], center: SIMD2<Float>) {
        stonePrism(outline, bottom: 0, top: 0.95, color: stageColor(0.27, 0.36, 0.34, 0))
        stonePrism(outline, bottom: 0.95, top: 1.1, color: stageColor(0.48, 0.51, 0.39, 0))
        // 控えめな金の笠石。壁の足跡の外には出さない。
        let stride = max(3, outline.count / 16)
        for i in outline.indices where i % stride == 0 {
            let a = outline[i], b = outline[(i + 1) % outline.count]
            let edge = b - a
            guard simd_length(edge) > 0.001 else { continue }
            let inward = simd_normalize(SIMD2(-edge.y, edge.x)) * 0.16
            guard polygonDistance(a + inward, outline) < 0, polygonDistance(b + inward, outline) < 0 else { continue }
            stonePrism([a, b, b + inward, a + inward],
                       bottom: 1.1, top: 1.18, color: stageColor(0.46, 0.39, 0.20, 0))
        }
        guard polygonDistance(center, outline) < -0.8 else { return }
        let b = size(.bush)
        let k: Float = 1.5 / max(b.x, b.z)
        place(.bush, at: center, y: 0.98, yaw: 0, scale: SIMD3(k, k * 0.65, k))
    }

    /// 歩行可能な円盤の縁は薄い床の象嵌（新しい見えない壁を作らない）。
    mutating func terraceRing(center c: SIMD2<Float>, radius r: Float) {
        for k in 0..<48 {
            let a = Float(k) / 48 * 2 * Float.pi
            let b = (Float(k) + 0.94) / 48 * 2 * Float.pi
            let u = SIMD2(cos(a), sin(a)), v = SIMD2(cos(b), sin(b))
            stonePrism([c + u * r, c + v * r, c + v * (r - 0.28), c + u * (r - 0.28)],
                       bottom: 0.025, top: 0.055, color: stageColor(0.08, 0.16, 0.14, 0))
        }
    }

    /// 静的な石材を既存の頂点色チャンクへ結合する（Entity / 更新処理の追加なし）。
    mutating func stonePrism(_ outline: [SIMD2<Float>], bottom: Float, top: Float, color: SIMD4<UInt8>) {
        guard outline.count >= 3 else { return }
        let center = outline.reduce(SIMD2<Float>.zero, +) / Float(outline.count)
        let key = StageChunks.key(world(center))
        var mesh = out.chunks.flora.removeValue(forKey: key) ?? StageMeshBuffer()
        let cap = outline.map { mesh.addVertex(world($0, top), [0, 1, 0], .zero, color) }
        for (a, b, c) in StageLayout.triangulate(outline) { mesh.addTriangle(cap[a], cap[b], cap[c]) }
        for i in outline.indices {
            let a = outline[i], b = outline[(i + 1) % outline.count]
            let edge = b - a
            let normal = simd_normalize(SIMD3(edge.y, 0, edge.x))
            let p0 = mesh.addVertex(world(a, bottom), normal, .zero, color)
            let p1 = mesh.addVertex(world(b, bottom), normal, .zero, color)
            let p2 = mesh.addVertex(world(b, top), normal, .zero, color)
            let p3 = mesh.addVertex(world(a, top), normal, .zero, color)
            mesh.addTriangle(p0, p1, p2)
            mesh.addTriangle(p0, p2, p3)
        }
        out.chunks.flora[key] = mesh
    }

    // MARK: 地図の外（崖の壁と森）

    mutating func border() {
        let M = geo.mapMeters
        // 縁の崖: 重なり合う一枚岩の帯（2026-10-16。小岩の列だと縁がガタガタに見えた）。
        // 縁は移動の限界（地図の縁）に合わせる: 崖の裾が地図の縁にかかり、ユニットが何もない所で止まって見えない。
        // 南は低く（手前の地図を隠さない）、北は高い。北・南の帯は角まで伸ばす
        for side in 0..<4 {
            let south = side == 0, north = side == 2, alongX = side % 2 == 0
            let (u0, u1): (Float, Float) = alongX ? (-7, M + 7) : (-1.5, M + 1.5)
            var u = u0
            while u < u1 {
                let len = max(2.5, min(rng.range(6.5, 9.5), u1 - u + 1))
                let inner: Float = south ? 0.25 : rng.range(-0.1, 0.15)
                let depth: Float = rng.range(4.2, 5.6)
                let h: Float = south ? rng.range(0.8, 1.1) : (north ? rng.range(2.5, 3.2) : rng.range(2.1, 2.8))
                let lo: SIMD2<Float>, hi: SIMD2<Float>
                switch side {
                case 0: lo = SIMD2(u, -inner - depth); hi = SIMD2(u + len, -inner)
                case 1: lo = SIMD2(M + inner, u); hi = SIMD2(M + inner + depth, u + len)
                case 2: lo = SIMD2(u, M + inner); hi = SIMD2(u + len, M + inner + depth)
                default: lo = SIMD2(-inner - depth, u); hi = SIMD2(-inner, u + len)
                }
                let outline = StageLayout.roundedRect(lo: lo, hi: hi, radius: 0.9, step: 1.3)
                appendRock(StageLayout.slabCore(outline: outline, height: h, seed: UInt64(side * 1000) &+ UInt64(u + 20) &* 31,
                                                tint: rockTint()), at: (lo + hi) / 2)
                u += len - rng.range(0.8, 1.4)
            }
        }
        let sides: [(start: SIMD2<Float>, dir: SIMD2<Float>, out: SIMD2<Float>, south: Bool)] = [
            (SIMD2(-16, 0), SIMD2(1, 0), SIMD2(0, -1), true),
            (SIMD2(M, -16), SIMD2(0, 1), SIMD2(1, 0), false),
            (SIMD2(M + 16, M), SIMD2(-1, 0), SIMD2(0, 1), false),
            (SIMD2(0, M + 16), SIMD2(0, -1), SIMD2(-1, 0), false),
        ]
        let len = Float(MapDefinition.standard.size / Balance.unitsPerMeter) + 32
        let spacing = (M + 32) / len
        let step = 4.4 / max(0.6, density)
        for s in sides {
            // 森（崖の後ろに 2 列。南は 1 列で遠くへ: 手前を隠さない）
            let rows: [Float] = s.south ? [8.5] : [6.8, 11.0]
            for (ri, depth) in rows.enumerated() {
                var u: Float = rng.range(0, step)
                while u < len {
                    let p = s.start + s.dir * (u * spacing) + s.out * (depth + rng.range(-0.8, 1.0))
                    let tall = ri == rows.count - 1 ? rng.chance(0.6) : rng.chance(0.25)
                    placeTree(at: p, y: -0.05, height: tall ? rng.range(4.4, 5.4) : rng.range(3.6, 4.6), tall: tall)
                    if ri == 0 && rng.chance(0.6 * density) {
                        let bp = p + s.dir * rng.range(-1.6, 1.6) + s.out * rng.range(0.4, 1.4)
                        let b = size(.bush)
                        let k = rng.range(1.4, 2.2) / max(b.x, b.z)
                        place(.bush, at: bp, y: -0.05, yaw: rng.range(0, 6.28), scale: SIMD3(k, k, k))
                    }
                    // 奥の列は画面に入ることが少ないので間隔を広げる
                    u += step * rng.range(0.85, 1.25) * (ri == 0 ? 1 : 1.5)
                }
            }
        }
        out.edgeSkirt = StageLayout.edgeSkirt(mapMeters: M)
    }

    // MARK: 泉の台座（新セット）

    /// 泉の遺跡の台座のメッシュの特徴（ローカル座標。メッシュから求めるので、作り直しても配置を書き換えずに済む）。
    struct DaisFeatures {
        /// 床（歩く面）の高さ。
        var floor: Float
        /// 縁の柱の頂部の受け皿（柱ごとに 1 つ）。
        var sockets: [SIMD3<Float>]
    }

    static func daisFeatures(_ m: StagePropMesh) -> DaisFeatures {
        let radius = max(m.size.x, m.size.z) / 2
        // 床: 上向きの面の頂点（中心の窪みと縁の柱・段を除く）の高さの中央値
        var ys: [Float] = []
        for (i, p) in m.positions.enumerated() {
            let r = simd_length(SIMD2(p.x, p.z))
            if m.normals[i].y > 0.9 && r > 0.2 * radius && r < 0.6 * radius { ys.append(p.y) }
        }
        ys.sort()
        let floor = ys.isEmpty ? m.size.y * 0.3 : ys[ys.count / 2]
        // 柱: 床より十分高く縁に近い頂点を、地図の角度（x 右・北が +）で束ねる
        let cut = floor + (m.boundsMax.y - floor) * 0.45
        var pts: [(a: Float, p: SIMD3<Float>)] = []
        for p in m.positions where p.y > cut && simd_length(SIMD2(p.x, p.z)) > 0.5 * radius {
            pts.append((atan2(-p.z, p.x), p))
        }
        guard pts.count >= 3 else { return DaisFeatures(floor: floor, sockets: []) }
        pts.sort { $0.a < $1.a }
        // 最も広い角度の空きの直後から一周し、20° 以上の空きで束を切る（-π/π をまたぐ束もつながる）
        var widest = 0, widestGap: Float = -1
        for k in pts.indices {
            let next = pts[(k + 1) % pts.count].a + (k + 1 == pts.count ? 2 * .pi : 0)
            if next - pts[k].a > widestGap { (widest, widestGap) = (k, next - pts[k].a) }
        }
        var clusters: [[SIMD3<Float>]] = [[]]
        for j in 0..<pts.count {
            let k = (widest + 1 + j) % pts.count
            if j > 0 {
                let prev = (k + pts.count - 1) % pts.count
                var gap = pts[k].a - pts[prev].a
                if gap < 0 { gap += 2 * .pi }
                if gap > 0.35 { clusters.append([]) }
            }
            clusters[clusters.count - 1].append(pts[k].p)
        }
        var sockets: [SIMD3<Float>] = []
        for c in clusters where c.count >= 4 {
            let top = c.map(\.y).max() ?? 0
            let crown = c.filter { $0.y > top - 0.08 }
            let mid = crown.reduce(SIMD3<Float>.zero, +) / Float(max(1, crown.count))
            sockets.append(SIMD3(mid.x, top, mid.z))
        }
        return DaisFeatures(floor: floor, sockets: sockets)
    }

    /// 泉の床から上の床の高さ（m）。ユニットは地面（y = 0）に立つので、台座は床がこの高さになるまで沈める（縁の段は埋まってよい）。
    static let daisFloorHeight: Float = 0.12

    /// 泉（両チーム）に遺跡の台座を置く。歩ける所に置く飾りなので placements（硬い物の記録）には入れない。
    /// 柱の無い向き（最も広い空き）を Core の方へ向け、泉から Core への通り道に柱を立てない。
    mutating func fountains() {
        guard let mesh = props[.spawnDais] else { return }
        let f = StageLayout.daisFeatures(mesh)
        var gapCenter: Float = 0
        if !f.sockets.isEmpty {
            let angles = f.sockets.map { atan2(-$0.z, $0.x) }.sorted()
            var best: Float = -1
            for k in angles.indices {
                let next = k + 1 < angles.count ? angles[k + 1] : angles[0] + 2 * .pi
                if next - angles[k] > best { (best, gapCenter) = (next - angles[k], (angles[k] + next) / 2) }
            }
        }
        for team in Team.players {
            let c = geo.m(map.fountain(team)), core = geo.m(map.core(team))
            let toCore = atan2(core.y - c.y, core.x - c.x)
            let m = transform(c, y: min(-0.02, StageLayout.daisFloorHeight - f.floor), yaw: toCore - gapCenter,
                              scale: SIMD3(repeating: 1))
            guard admitProp(mesh) else { continue }
            out.counts[.spawnDais, default: 0] += 1
            let key = StageChunks.key(world(c))
            var buf = out.chunks.props.removeValue(forKey: key) ?? StageMeshBuffer(reserveVertices: 4096)
            // 灰緑の石を少し明るく（拠点の中央の床と揃える）
            buf.append(mesh, transform: m, color: tint(1.12, 1.12, 1.1))
            out.chunks.props[key] = buf
            out.fountainSockets.append(f.sockets.map { s in
                let w = m * SIMD4(s, 1)
                return SIMD3(w.x, w.y, w.z)
            })
        }
    }

    // MARK: 祭壇（ボスの巣・番人のキャンプ）

    mutating func pits() {
        if ruinsLook {
            let c = SIMD2<Float>(repeating: geo.mapMeters / 2)
            runeDisc(center: c, radius: 5.4, rotation: .pi / 4)
            terraceRing(center: c, radius: 5.55)
        }
        for camp in map.camps {
            let c = geo.m(camp.pos)
            switch camp.kind {
            case .astralWyrm, .ancientColossus:
                runeDisc(center: c, radius: 5.6, rotation: camp.kind == .astralWyrm ? 0.2 : 1.0)
                if ruinsLook { terraceRing(center: c, radius: 5.85) }
                pitRuins(center: c)
            case .blueSentinel, .redSentinel:
                runeDisc(center: c, radius: 2.5, rotation: Float(camp.id) * 0.7)
            case .small, .hornLizard, .emberBeetle, .magmaGolem, .treasureCrab, .mossWanderer:
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
        for c in map.camps where simd_distance(p, geo.m(c.pos)) < (c.kind.isSentinel || c.kind.isBoss ? 8.6 : 3.6) { return false }
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
        // 多角形の壁の根元: 裾のすぐ外（足跡から 0.3〜0.5 m）に低い草の房と小石を並べ、岩の根元を地面になじませる
        // （膝下の高さだけなので歩ける所に置いてよい）
        let rootStep = 1.4 / max(0.5, density)
        for poly in geo.polygons {
            var acc: Float = 0
            for k in poly.indices {
                let a = poly[k], b = poly[(k + 1) % poly.count]
                let len = simd_distance(a, b)
                guard len > 1e-4 else { continue }
                acc += len
                let e = (b - a) / len, nrm = SIMD2(e.y, -e.x) // 反時計回りの輪郭の外向き
                while acc > rootStep {
                    acc -= rootStep
                    let p = a + (b - a) * rng.range(0, 1) + nrm * rng.range(0.3, 0.5)
                    guard p.x > 0.5, p.y > 0.5, p.x < M - 0.5, p.y < M - 0.5,
                          geo.laneDistance(p) > 2.5, geo.obstacleDistance(p) > 0.2 else { continue }
                    let key = StageChunks.key(world(p))
                    var buf = out.chunks.flora.removeValue(forKey: key) ?? StageMeshBuffer(reserveVertices: 2048)
                    grassTuft(&buf, at: p, height: rng.range(0.3, 0.55), blades: 6)
                    if rng.chance(0.3) { pebble(&buf, at: p + nrm * 0.15, size: rng.range(0.16, 0.3)) }
                    out.chunks.flora[key] = buf
                }
            }
        }
        // 川岸の小石と葦
        let riverHalf = Float(map.riverWidth / 100) / 2
        let bankCount = Int(260 * density)
        for _ in 0..<bankCount {
            let p: SIMD2<Float>
            if geo.riverBank.count >= 3 {
                // 多角形の川（反時計回り）: 岸の輪郭の上の点から外向き（右手側）へ少しずらす
                let bank = geo.riverBank
                let i = min(bank.count - 1, Int(rng.range(0, Float(bank.count))))
                let a = bank[i], b = bank[(i + 1) % bank.count]
                let edge = b - a, len = simd_length(edge)
                guard len > 0.01 else { continue }
                let outward = SIMD2<Float>(edge.y, -edge.x) / len
                p = a + edge * rng.range(0, 1) + outward * rng.range(-0.2, 0.7)
            } else {
                let s = rng.range(-8, M + 8)
                let side: Float = rng.chance(0.5) ? 1 : -1
                let along = SIMD2<Float>(s, M - s)
                let normal = SIMD2<Float>(0.70710678, 0.70710678)
                p = along + normal * side * (riverHalf + rng.range(-0.2, 0.7))
            }
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
        // 新セットは暗い地面に合わせて暗い灰緑の花崗岩（明るい灰色だと白い紙片に見える）
        let col = ruinsLook ? stageColor(shade * 0.55, shade * 0.62, shade * 0.56, 0) : stageColor(shade, shade * 1.02, shade * 1.06, 0)
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

    /// 地図全体の房の密度基準。近景12 / 遠景4三角形。既存9万三角形予算を維持。
    static let maxBrushClumps: Float = 3000

    mutating func brushFields() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-brushLegacy") { legacyBrushFields(); return }
        #endif
        // MLBB の草むらは広い（総面積 約 940 m²）ので、房の間隔を総面積に合わせて広げ、三角形数を予算内に収める
        // （細かい格子の草むらは外接矩形ではなくセルの面積で数える）
        let total = map.brushes.indices.reduce(Float(0)) { acc, k in
            acc + Float(map.brushArea(k) / (Balance.unitsPerMeter * Balance.unitsPerMeter))
        }
        let step: Float = max(level == .low ? 0.55 : 0.45, (total / StageLayout.maxBrushClumps).squareRoot())
        for (k, b) in map.brushes.enumerated() {
            let lo = geo.m(Vec2(b.rect.minX, b.rect.minY)), hi = geo.m(Vec2(b.rect.maxX, b.rect.maxY))
            let center = (lo + hi) / 2
            var buf = StageMeshBuffer(reserveVertices: 20_000)
            var cards = StageMeshBuffer()
            var brng = RenderRNG(seed: UInt64(b.id) &* 613 &+ 7)
            let w = hi.x - lo.x, d = hi.y - lo.y
            let nx = max(1, Int((w / step).rounded())), ny = max(1, Int((d / step).rounded()))
            /// 草むらの形の中か（q = 草むらの中心からの位置 m）。細かい格子の草むらは格子で、矩形の草むらは矩形で判定する。
            func inside(_ q: SIMD2<Float>) -> Bool {
                map.brush(k, contains: Vec2(Double(center.x + q.x) * Balance.unitsPerMeter, Double(center.y + q.y) * Balance.unitsPerMeter))
            }
            var placed = 0
            for ix in 0..<nx {
                for iy in 0..<ny {
                    let lx = (Float(ix) + 0.5) / Float(nx) * w - w / 2 + brng.range(-0.12, 0.12)
                    let ly = (Float(iy) + 0.5) / Float(ny) * d - d / 2 + brng.range(-0.12, 0.12)
                    let root = SIMD2(min(max(lx, -w / 2 + 0.08), w / 2 - 0.08), min(max(ly, -d / 2 + 0.08), d / 2 - 0.08))
                    let seed = brng.next()
                    guard inside(root) else { continue }
                    // 縁の房は内側へ少し倒す（見た目の縁を草むらの形に合わせる: 0.45 m 先が外なら反対へ）
                    var inward = SIMD2<Float>(0, 0)
                    for dir in [SIMD2<Float>(1, 0), SIMD2<Float>(-1, 0), SIMD2<Float>(0, 1), SIMD2<Float>(0, -1)] where !inside(root + dir * 0.45) {
                        inward -= dir
                    }
                    var nearRNG = RenderRNG(seed: seed), farRNG = RenderRNG(seed: seed)
                    brushClump(&buf, rng: &nearRNG, at: root, lean: inward)
                    brushClump(&cards, rng: &farRNG, at: root, lean: inward, distant: true)
                    placed += 1
                }
            }
            if placed == 0 {
                // 房の間隔より小さい草むら（壁に削られたものなど）にも 1 房は置く（メッシュを空にしない）
                let root = geo.m(map.brushInteriorPoint(k)) - center
                var nearRNG = RenderRNG(seed: UInt64(b.id) &+ 11), farRNG = RenderRNG(seed: UInt64(b.id) &+ 11)
                brushClump(&buf, rng: &nearRNG, at: root, lean: .zero)
                brushClump(&cards, rng: &farRNG, at: root, lean: .zero, distant: true)
            }
            out.brushes.append(buf)
            out.brushCards.append(cards)
            out.brushCenters.append(world(center))
        }
    }

    /// Three bent foliage cards per cell; shared atlas, one material/mesh per brush area.
    /// Near = 12 triangles/cell, far = 4. Roots and placement are identical for both LODs.
    func brushClump(_ buf: inout StageMeshBuffer, rng: inout RenderRNG, at p: SIMD2<Float>,
                    lean: SIMD2<Float>, distant: Bool = false) {
        let yaw = rng.range(0, .pi)
        let h = rng.range(1.05, 1.35)
        let tile = Int(rng.range(0, 4))
        let tint = rng.range(0.88, 1.08)
        let count = distant ? 2 : 3
        let segments = distant ? 1 : 2
        for card in 0..<count {
            let a = yaw + Float(card) * .pi / Float(count)
            let side = SIMD3<Float>(cos(a), 0, sin(a))
            let face = SIMD3<Float>(-sin(a), 0, cos(a))
            let start = UInt32(buf.vertexCount)
            for row in 0...segments {
                let t = Float(row) / Float(segments)
                let offset = SIMD3<Float>(lean.x, 0, -lean.y) * (0.12 * t * t)
                let center = SIMD3<Float>(p.x, -0.03 + h * t, -p.y) + offset + face * (0.10 * t * t)
                for edge in 0...1 {
                    let u = Float(edge)
                    let pos = center + side * ((u - 0.5) * 0.94)
                    let uv = SIMD2<Float>((Float((tile + card) % 4) + 0.015 + u * 0.97) / 4, 0.015 + t * 0.97)
                    buf.addVertex(pos, simd_normalize(face + SIMD3<Float>(0, 0.65, 0)), uv,
                                  stageColor(tint * 0.5, tint * 0.5, tint * 0.5, t * t))
                }
            }
            for row in 0..<segments {
                let i = start + UInt32(row * 2)
                buf.addTriangle(i, i + 1, i + 3)
                buf.addTriangle(i, i + 3, i + 2)
            }
        }
    }

    #if DEBUG
    mutating func legacyBrushFields() {
        // MLBB の草むらは広い（総面積 約 940 m²）ので、房の間隔を総面積に合わせて広げ、三角形数を予算内に収める
        let total = map.brushes.reduce(Float(0)) { acc, b in
            let lo = geo.m(Vec2(b.rect.minX, b.rect.minY)), hi = geo.m(Vec2(b.rect.maxX, b.rect.maxY))
            return acc + abs((hi.x - lo.x) * (hi.y - lo.y))
        }
        let step: Float = max(level == .low ? 0.55 : 0.45, (total / StageLayout.maxBrushClumps).squareRoot())
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
                    legacyBrushClump(&buf, rng: &brng, at: root, lean: inward)
                }
            }
            out.brushes.append(buf)
            out.brushCards.append(buf)
            out.brushCenters.append(world(center))
        }
    }

    /// 草むらの 1 房（背の高い葉 6〜9 枚）。座標は草むらの中心が原点。
    func legacyBrushClump(_ buf: inout StageMeshBuffer, rng: inout RenderRNG, at p: SIMD2<Float>, lean: SIMD2<Float>) {
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
            // 1 段（根元と先だけ）の葉。草むらが広いので 1 枚あたりの三角形を抑える
            buf.blade(base: root, direction: dir, side: side, height: h, width: rng.range(0.1, 0.15), bend: rng.range(0.08, 0.24),
                      segments: 1) { t in
                let c = t < 0.5 ? dark + (mid - dark) * (t * 2) : mid + (tip - mid) * ((t - 0.5) * 2)
                return stageColor(c.x, c.y, c.z, t)
            }
        }
    }

    #endif

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

    /// 壁の形の基準値（2026-10-16、docs/STAGE.md 1.1）。カメラは 56° 見下ろし・縦画角 48° なので、画面の上端の視線は 32°、
    /// 中央は 56°、下端は 80°。面の傾斜がその視線より寝ていれば、面の向こうの地面は隠れない。
    enum WallProfile {
        /// 高さの上限（m）。ヒーロー（約 1.8 m）の頭が壁の向こうに見える。
        static let maxHeight: Float = 2.0
        /// 細い壁は低く: 高さ ≤ heightBase + heightPerHalfWidth × 半分の厚み（m）。
        static let heightBase: Float = 0.55
        static let heightPerHalfWidth: Float = 1.1
        /// 面の傾斜角（度）。北向き（奥）は画面の中央の視線 56° より十分寝かせ、壁の向こうの歩ける所を隠さない
        /// （上端の視線 32° でも隠すのは高さ × 0.32 だけ）。南向き（手前）は立てて崖に見せる（隠すのは壁の上だけ）。
        static let slopeNorth: Float = 38
        static let slopeSide: Float = 58
        static let slopeSouth: Float = 74
        /// 裾の張り出し（m）。足跡（衝突）から 0.4 m 以内（1 章の規則）。
        static let footFlare: Float = 0.28
    }

    /// 傾斜付きの一枚岩（2026-10-16）。輪郭（凹んでいてよい）を足跡とし、面の向きごとに WallProfile の傾斜で上をすぼめ、
    /// 上の縁を丸めて上面（苔）をなだらかに盛り上げる。法線は滑らか。
    /// fine（画質 中・高）: 縦 13 段・上面の内側 3 段の盛り上がり・数 cm の起伏で岩らしくする。低は縦 9 段・平らな上面。
    /// refine（画質 高）: さらに輪郭をもう一度 centripetal Catmull-Rom で補間して頂点を 2 倍にする（衝突の多角形は 1 mm の精度
    /// なので形は変わらない）。壁 44 の三角形は 低 約 16 万・中 約 28 万・高 約 57 万（ステージ全体の予算は 90 万 / 100 万）。
    /// 戻り値の top は上面の輪（地図座標 m）、minTopHeight は上面の縁の最も低い高さ。
    static func slopedSlab(outline raw: [SIMD2<Float>], seed: UInt64, tint: SIMD4<UInt8>, fine: Bool = true, refine: Bool = false)
        -> (mesh: StageMeshBuffer, top: [SIMD2<Float>], minTopHeight: Float) {
        var rng = RenderRNG(seed: seed | 1)
        let ccw = signedArea(raw) < 0 ? Array(raw.reversed()) : raw
        let outline = refine ? refineOutline(ccw) : ccw
        let n = outline.count
        guard n >= 3 else { return (StageMeshBuffer(), [], 0) }
        // 頂点ごとの外向きの法線・半分の厚み（内向きに伸ばした線が向こうの辺に当たるまでの半分）
        var normals: [SIMD2<Float>] = [], halfWidth: [Float] = []
        for k in 0..<n {
            let a = outline[(k + n - 1) % n], b = outline[k], c = outline[(k + 1) % n]
            let e0 = simd_normalize(b - a), e1 = simd_normalize(c - b)
            let nn = SIMD2(e0.y, -e0.x) + SIMD2(e1.y, -e1.x)
            normals.append(simd_length(nn) > 1e-5 ? simd_normalize(nn) : SIMD2(e1.y, -e1.x))
        }
        // 厚みは格子（2 m）で辺を探して O(n) 近くに抑える（頂点が数百〜千あるため）。内向きの線が向こうの辺に当たる距離と、
        // 輪郭に沿って 1 m 以内の辺を除いた最も近い辺までの距離の短い方（三日月の先端で、線が細い先の奥まで伸びて
        // 厚く見積もるのを防ぐ）
        let edgeGrid = EdgeGrid(outline, cell: 2)
        for k in 0..<n {
            let ray = edgeGrid.rayHit(from: outline[k], dir: -normals[k], skip: k, limit: 40)
            let other = edgeGrid.nearestOther(to: k, excludingArc: 1.0, limit: 40)
            halfWidth.append(min(ray, other) / 2)
        }
        // 厚みのむらをならす（近くの 5 点の最小）
        let smoothHalf = (0..<n).map { k in (-2...2).map { halfWidth[(k + $0 + n) % n] }.min() ?? halfWidth[k] }
        var heights: [Float] = [], runs: [Float] = [], lips: [Float] = []
        for k in 0..<n {
            let h = min(WallProfile.maxHeight, WallProfile.heightBase + WallProfile.heightPerHalfWidth * smoothHalf[k])
            let ny = normals[k].y
            let deg = ny >= 0 ? WallProfile.slopeSide + (WallProfile.slopeNorth - WallProfile.slopeSide) * ny
                              : WallProfile.slopeSide + (WallProfile.slopeSouth - WallProfile.slopeSide) * -ny
            let run = min(h / tan(deg * .pi / 180), smoothHalf[k] * 0.75)
            heights.append(h)
            runs.append(run)
            lips.append(min(0.35, max(0, smoothHalf[k] - run) * 0.4))
        }
        // 上面の輪が自己交差しない（耳刈りで刈り切れる）所まで、傾斜と縁の丸めの入りを一律に縮める
        // （三日月の細い先では厚みの見積もりが粗く、内へ寄せた輪が交差しうる。縮めた壁は面が少し立つ）
        for scale in [Float(1), 0.7, 0.45, 0.25, 0] {
            let ring = (0..<n).map { k in outline[k] - normals[k] * ((runs[k] + lips[k]) * scale) }
            if triangulate(ring).count == n - 2 || scale == 0 {
                runs = runs.map { $0 * scale }
                lips = lips.map { $0 * scale }
                break
            }
        }
        // 高さを輪に沿ってならす（急な段差を作らない。頂点が細かいほど広い窓で）
        let win = fine ? 3 : 1
        let h2 = (0..<n).map { k -> Float in
            var s: Float = 0, w: Float = 0
            for d in -win...win { let wt = Float(win + 1 - abs(d)); s += heights[(k + d + n) % n] * wt; w += wt }
            return s / w
        }
        // 縦の段（f = 高さの割合。負は地面の下 0.06 m）: 裾の張り出しは下ほど強く 2 乗で消え、傾斜は直線、
        // 上の縁は smoothstep で丸める
        let fs: [Float] = fine ? [-1, 0.03, 0.08, 0.15, 0.24, 0.35, 0.48, 0.62, 0.75, 0.86, 0.94, 0.985, 1.0]
                               : [-1, 0.05, 0.14, 0.28, 0.46, 0.66, 0.84, 0.96, 1.0]
        func foot(_ f: Float) -> Float { f < 0 ? 1 : pow(max(0, 1 - f / 0.45), 2) }
        func lipAt(_ f: Float) -> Float { smoothstep(0.82, 1.0, f) }
        let bulge = (0..<n).map { _ in rng.range(-0.04, 0.05) }
        let noiseSeed = Float(seed % 997)
        func shaded(_ s: Float) -> SIMD4<UInt8> {
            func m(_ v: UInt8) -> UInt8 { UInt8(max(0, min(255, (Float(v) * s).rounded()))) }
            return SIMD4(m(tint.x), m(tint.y), m(tint.z), tint.w)
        }
        var positions: [SIMD3<Float>] = [], colors: [SIMD4<UInt8>] = []
        var top: [SIMD2<Float>] = []
        for (li, f) in fs.enumerated() {
            let last = li == fs.count - 1
            for k in 0..<n {
                var off = WallProfile.footFlare * foot(f) - runs[k] * max(0, f) - lips[k] * lipAt(f)
                if f > 0 && !last { off += bulge[k] * sin(.pi * f) }
                var q = outline[k] + normals[k] * off
                // 岩の起伏（裾は足跡の規則のため動かさない）: 低い周波数の 3D ノイズで ±5 cm
                if fine && f > 0.1 && !last {
                    let p3 = SIMD3(q.x, f * h2[k], q.y) * 0.9 + noiseSeed
                    q += normals[k] * (StageLayout.valueNoise3(p3) - 0.5) * 0.1 * min(1, (f - 0.1) * 4)
                }
                let y = f < 0 ? -0.06 : h2[k] * f + (last ? 0.04 : 0)
                positions.append(SIMD3(q.x, y, -q.y))
                colors.append(shaded(0.82 + 0.32 * max(0, f)))
                if last { top.append(q) }
            }
        }
        var tris: [(Int, Int, Int)] = []
        func band(_ r: Int) {
            for k in 0..<n {
                let a = r * n + k, b = r * n + (k + 1) % n, c = (r + 1) * n + (k + 1) % n, d = (r + 1) * n + k
                tris.append((a, b, c))
                tris.append((a, c, d))
            }
        }
        for r in 0..<(fs.count - 1) { band(r) }
        // 上面の盛り上がり（fine）: 縁の内側に 3 段の輪を足して中ほどを少し高くする。内側の輪から順に耳刈りを試し、
        // 自己交差して刈り切れない輪は使わない（その外の輪で閉じる）
        var rings: [[SIMD2<Float>]] = [top]
        if fine {
            for j in 1...3 {
                let t = Float(j) / 4
                let ring: [SIMD2<Float>] = (0..<n).map { k in
                    let remaining: Float = max(0, smoothHalf[k] - runs[k] - lips[k])
                    let inset: Float = remaining * 0.8 * t
                    return top[k] - normals[k] * inset
                }
                rings.append(ring)
            }
        }
        var use = rings.count - 1
        var cap = triangulate(rings[use])
        while cap.count != n - 2 && use > 0 {
            use -= 1
            cap = triangulate(rings[use])
        }
        var capRing = fs.count - 1
        if use > 0 {
            for j in 1...use {
                let t = Float(j) / 4
                for k in 0..<n {
                    let dome = min(0.22, 0.12 * smoothHalf[k]) * (1 - (1 - t) * (1 - t))
                    positions.append(SIMD3(rings[j][k].x, h2[k] + 0.04 + dome, -rings[j][k].y))
                    colors.append(shaded(1.14 + 0.03 * t))
                }
                band(capRing)
                capRing += 1
            }
        }
        // 上面: 耳刈り（凹んだ形でも正しく覆う）。刈り切れなければ足跡の輪郭（単純な多角形）の分け方を使い、
        // それも駄目なら重心からの扇
        let base = capRing * n
        if cap.count != n - 2 { cap = triangulate(outline) }
        if cap.count != n - 2 {
            let ring = rings[use]
            let c = ring.reduce(SIMD2<Float>.zero, +) / Float(n)
            positions.append(SIMD3(c.x, h2.reduce(0, +) / Float(n) + 0.04, -c.y))
            colors.append(shaded(1.14))
            let ci = positions.count - 1 - base
            cap = (0..<n).map { ($0, ($0 + 1) % n, ci) }
        }
        for t in cap { tris.append((base + t.0, base + t.1, base + t.2)) }
        var vn = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for t in tris {
            let a = positions[t.0], b = positions[t.1], c = positions[t.2]
            let nrm = simd_cross(b - a, c - a)
            vn[t.0] += nrm
            vn[t.1] += nrm
            vn[t.2] += nrm
        }
        var buf = StageMeshBuffer(reserveVertices: positions.count)
        for (i, p) in positions.enumerated() {
            let nn = simd_length(vn[i]) > 1e-6 ? simd_normalize(vn[i]) : SIMD3<Float>(0, 1, 0)
            buf.addVertex(p, nn, .zero, colors[i])
        }
        for t in tris { buf.addTriangle(UInt32(t.0), UInt32(t.1), UInt32(t.2)) }
        return (buf, top, h2.min() ?? 0)
    }

    /// 閉じた折れ線の各辺の中点を、centripetal Catmull-Rom の値に置き換えて足す（頂点 2 倍。元の頂点は動かさない）。
    static func refineOutline(_ pts: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let n = pts.count
        guard n >= 4 else { return pts }
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(n * 2)
        func knot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { max(1e-5, simd_distance(a, b).squareRoot()) }
        for i in 0..<n {
            let p0 = pts[(i + n - 1) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            let t0: Float = 0, t1 = t0 + knot(p0, p1), t2 = t1 + knot(p1, p2), t3 = t2 + knot(p2, p3)
            let t = (t1 + t2) / 2
            func lerp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ ta: Float, _ tb: Float) -> SIMD2<Float> {
                (a * (tb - t) + b * (t - ta)) / (tb - ta)
            }
            let a1 = lerp(p0, p1, t0, t1), a2 = lerp(p1, p2, t1, t2), a3 = lerp(p2, p3, t2, t3)
            let mid = lerp(lerp(a1, a2, t0, t2), lerp(a2, a3, t1, t3), t1, t2)
            out.append(p1)
            out.append(mid)
        }
        return out
    }

    /// 3D の値ノイズ（0〜1、滑らか）。岩の起伏用。
    static func valueNoise3(_ p: SIMD3<Float>) -> Float {
        let i = SIMD3<Float>(floor(p.x), floor(p.y), floor(p.z)), f = p - i
        let u = f * f * (SIMD3<Float>(repeating: 3) - 2 * f)
        func h(_ x: Float, _ y: Float, _ z: Float) -> Float {
            var v = UInt32(bitPattern: Int32(truncatingIfNeeded: Int(x))) &* 0x8DA6_B343
            v ^= UInt32(bitPattern: Int32(truncatingIfNeeded: Int(y))) &* 0xD816_3841
            v ^= UInt32(bitPattern: Int32(truncatingIfNeeded: Int(z))) &* 0xCB1A_B31F
            v ^= v >> 13
            v = v &* 0x5BD1_E995
            v ^= v >> 15
            return Float(v & 0xFFFF) / 65535
        }
        func l(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
        let x0 = l(l(h(i.x, i.y, i.z), h(i.x + 1, i.y, i.z), u.x), l(h(i.x, i.y + 1, i.z), h(i.x + 1, i.y + 1, i.z), u.x), u.y)
        let x1 = l(l(h(i.x, i.y, i.z + 1), h(i.x + 1, i.y, i.z + 1), u.x),
                   l(h(i.x, i.y + 1, i.z + 1), h(i.x + 1, i.y + 1, i.z + 1), u.x), u.y)
        return l(x0, x1, u.z)
    }

    /// 輪郭の辺を格子に入れて、内向きの線が最初に当たる辺までの距離を速く求める。
    struct EdgeGrid {
        let pts: [SIMD2<Float>]
        let cell: Float
        let origin: SIMD2<Float>
        let cols: Int, rows: Int
        var buckets: [[Int]]

        init(_ pts: [SIMD2<Float>], cell: Float) {
            self.pts = pts
            self.cell = cell
            var lo = pts[0], hi = pts[0]
            for p in pts { lo = simd_min(lo, p); hi = simd_max(hi, p) }
            origin = lo
            cols = max(1, Int((hi.x - lo.x) / cell) + 1)
            rows = max(1, Int((hi.y - lo.y) / cell) + 1)
            var b = [[Int]](repeating: [], count: cols * rows)
            let n = pts.count
            for j in 0..<n {
                let a = pts[j], c = pts[(j + 1) % n]
                let c0 = Int((min(a.x, c.x) - lo.x) / cell), c1 = Int((max(a.x, c.x) - lo.x) / cell)
                let r0 = Int((min(a.y, c.y) - lo.y) / cell), r1 = Int((max(a.y, c.y) - lo.y) / cell)
                for r in max(0, r0)...min(rows - 1, r1) { for cc in max(0, c0)...min(cols - 1, c1) { b[r * cols + cc].append(j) } }
            }
            buckets = b
        }

        /// 頂点 k から、輪郭に沿って arc（m）以内の辺を除いた最も近い辺までの距離（無ければ limit）。
        func nearestOther(to k: Int, excludingArc arc: Float, limit: Float) -> Float {
            let n = pts.count
            let p = pts[k]
            // 輪郭に沿った距離で除く範囲（前後に何本の辺か）
            var back = 0, fwd = 0
            var acc: Float = 0
            while back < n / 2 && acc < arc { acc += simd_distance(pts[(k - back - 1 + n) % n], pts[(k - back + n) % n]); back += 1 }
            acc = 0
            while fwd < n / 2 && acc < arc { acc += simd_distance(pts[(k + fwd) % n], pts[(k + fwd + 1) % n]); fwd += 1 }
            func excluded(_ j: Int) -> Bool {
                let d = (j - k + n) % n // 辺 j は頂点 j → j+1
                return d < fwd || d >= n - back
            }
            var best = limit
            let cc = Int((p.x - origin.x) / cell), rr = Int((p.y - origin.y) / cell)
            var ring = 0
            while Float(ring - 1) * cell < best && ring <= max(cols, rows) {
                for r in (rr - ring)...(rr + ring) {
                    for c in (cc - ring)...(cc + ring) where max(abs(r - rr), abs(c - cc)) == ring {
                        guard r >= 0, c >= 0, r < rows, c < cols else { continue }
                        for j in buckets[r * cols + c] where !excluded(j) {
                            let a = pts[j], b = pts[(j + 1) % n], ab = b - a
                            let l2 = simd_dot(ab, ab)
                            let t = l2 > 0 ? max(0, min(1, simd_dot(p - a, ab) / l2)) : 0
                            best = min(best, simd_distance(p, a + ab * t))
                        }
                    }
                }
                ring += 1
            }
            return best
        }

        /// p から dir へ伸ばした線が、skip の隣の辺以外に最初に当たる距離（当たらなければ limit）。
        func rayHit(from p: SIMD2<Float>, dir: SIMD2<Float>, skip k: Int, limit: Float) -> Float {
            let n = pts.count
            var best = limit
            var seen = Set<Int>()
            // 線に沿って格子を歩く（半セルずつ）
            var s: Float = 0
            while s < best + cell {
                let q = p + dir * s
                let cc = Int((q.x - origin.x) / cell), r = Int((q.y - origin.y) / cell)
                if cc < 0 || r < 0 || cc >= cols || r >= rows { break }
                for dr in -1...1 {
                    for dc in -1...1 {
                        let rr = r + dr, c2 = cc + dc
                        guard rr >= 0, c2 >= 0, rr < rows, c2 < cols else { continue }
                        for j in buckets[rr * cols + c2] where j != k && (j + 1) % n != k && !seen.contains(j) {
                            seen.insert(j)
                            let a = pts[j], e = pts[(j + 1) % n] - a
                            let den = dir.x * e.y - dir.y * e.x
                            guard abs(den) > 1e-6 else { continue }
                            let w = a - p
                            let t = (w.x * e.y - w.y * e.x) / den
                            let u = (w.x * dir.y - w.y * dir.x) / den
                            if t > 0.05 && u >= 0 && u <= 1 { best = min(best, t) }
                        }
                    }
                }
                s += cell * 0.5
            }
            return best
        }
    }

    /// 符号付き面積（反時計回りが正）。
    static func signedArea(_ pts: [SIMD2<Float>]) -> Float {
        var a: Float = 0
        for k in pts.indices {
            let p = pts[k], q = pts[(k + 1) % pts.count]
            a += p.x * q.y - q.x * p.y
        }
        return a / 2
    }

    /// 単純多角形（反時計回り）の耳刈り。三角形は元の添字（反時計回り）。自己交差などで刈り切れなければ途中までを返す。
    static func triangulate(_ pts: [SIMD2<Float>]) -> [(Int, Int, Int)] {
        var idx = Array(pts.indices)
        var tris: [(Int, Int, Int)] = []
        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        // 刈った所の続きから探す（毎回先頭から探すと O(n³) になる。頂点が 1 mm の精度で数百あるため）。
        // 耳の中に入りうるのは凹んだ頂点だけなので、中に頂点が無いかは凹んだ頂点だけで調べる
        var start = 0
        while idx.count > 3 {
            var clipped = false
            let m = idx.count
            let reflex = (0..<m).map { k in cross(pts[idx[(k + m - 1) % m]], pts[idx[k]], pts[idx[(k + 1) % m]]) <= 1e-7 }
            for step in 0..<m {
                let i = (start + step) % m
                let i0 = idx[(i + m - 1) % m], i1 = idx[i], i2 = idx[(i + 1) % m]
                let a = pts[i0], b = pts[i1], c = pts[i2]
                guard !reflex[i] else { continue }
                var ear = true
                for k in 0..<m where reflex[k] {
                    let j = idx[k]
                    guard j != i0 && j != i1 && j != i2 else { continue }
                    let p = pts[j]
                    if cross(a, b, p) >= 0 && cross(b, c, p) >= 0 && cross(c, a, p) >= 0 { ear = false; break }
                }
                if ear {
                    tris.append((i0, i1, i2))
                    idx.remove(at: i)
                    start = i % max(1, idx.count)
                    clipped = true
                    break
                }
            }
            if !clipped { return tris }
        }
        if idx.count == 3 { tris.append((idx[0], idx[1], idx[2])) }
        return tris
    }

    /// 壁の一枚岩（2026-10-16）。足跡の輪郭をそのまま押し出し、裾を少し広げ、上の縁を丸めて苔の平らな上面にした 1 つの塊。
    /// 小さな岩を辺に並べると境界がガタガタで隙間が暗く見えるので、壁 1 つを滑らかな 1 つの塊にする（MLBB 風のスタイライズ）。
    /// outline は凸（矩形・円）。北向きの面は 2 割低く（カメラは南から見下ろすので、壁の向こうの歩ける所を隠さない）。
    /// 裾は足跡から 0.3 m まで（docs/STAGE.md 1 章の 0.4 m の規則）。法線は滑らか（シェーダーが上向きの面を苔にする）。
    static func slabCore(outline raw: [SIMD2<Float>], height h: Float, seed: UInt64, tint: SIMD4<UInt8>) -> StageMeshBuffer {
        var rng = RenderRNG(seed: seed | 1)
        let n = raw.count
        guard n >= 3 else { return StageMeshBuffer() }
        // 反時計回りに揃える
        var area: Float = 0
        for k in 0..<n { let a = raw[k], b = raw[(k + 1) % n]; area += a.x * b.y - b.x * a.y }
        let outline = area < 0 ? Array(raw.reversed()) : raw
        let center = outline.reduce(SIMD2<Float>.zero, +) / Float(n)
        var lo = outline[0], hi = outline[0]
        for p in outline { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        // 上面の縁の内側への入り（細い壁で反対側と交差しない量）
        let inset = min(0.55, min(hi.x - lo.x, hi.y - lo.y) * 0.28)
        // 頂点ごとの外向きの法線（隣り合う辺の法線の平均）・高さ・ふくらみ
        var normals: [SIMD2<Float>] = [], heights: [Float] = [], bulge: [Float] = []
        for k in 0..<n {
            let a = outline[(k + n - 1) % n], b = outline[k], c = outline[(k + 1) % n]
            let e0 = simd_normalize(b - a), e1 = simd_normalize(c - b)
            let nn = SIMD2(e0.y, -e0.x) + SIMD2(e1.y, -e1.x)
            normals.append(simd_length(nn) > 1e-5 ? simd_normalize(nn) : simd_normalize(b - center))
            heights.append(h * (1 - 0.2 * max(0, normals[k].y)) + rng.range(-0.05, 0.05))
            bulge.append(rng.range(-0.04, 0.05))
        }
        // 段: (高さの割合（負は絶対値 m）, 外への張り出し m, ふくらみの効き, 明るさ)
        let levels: [(fy: Float, push: Float, bulge: Float, shade: Float)] = [
            (-0.06, 0.28, 0, 0.84), (0.16, 0.17, 0.5, 0.9), (0.5, 0.07, 1, 1.0), (0.86, 0.0, 1, 1.05),
            (1.0, -inset * 0.4, 0.5, 1.1), (1.02, -inset, 0, 1.14),
        ]
        var buf = StageMeshBuffer(reserveVertices: n * levels.count + 1)
        var positions: [SIMD3<Float>] = []
        var colors: [SIMD4<UInt8>] = []
        func shaded(_ s: Float) -> SIMD4<UInt8> {
            func m(_ v: UInt8) -> UInt8 { UInt8(max(0, min(255, (Float(v) * s).rounded()))) }
            return SIMD4(m(tint.x), m(tint.y), m(tint.z), tint.w)
        }
        for l in levels {
            for k in 0..<n {
                let q = outline[k] + normals[k] * (l.push + bulge[k] * l.bulge)
                let y = l.fy < 0 ? l.fy : heights[k] * l.fy
                positions.append(SIMD3(q.x, y, -q.y))
                colors.append(shaded(l.shade))
            }
        }
        let topY = heights.reduce(0, +) / Float(n) * 1.02 + 0.04
        positions.append(SIMD3(center.x, topY, -center.y))
        colors.append(shaded(1.14))
        let topIndex = positions.count - 1
        var tris: [(Int, Int, Int)] = []
        func idx(_ r: Int, _ k: Int) -> Int { r * n + (k % n) }
        // 輪郭は地図座標で反時計回り（上から見ても反時計回り）→ 側面は外から見て反時計回りになる順で
        for r in 0..<(levels.count - 1) {
            for k in 0..<n {
                let a = idx(r, k), b = idx(r, k + 1), c = idx(r + 1, k + 1), d = idx(r + 1, k)
                tris.append((a, b, c))
                tris.append((a, c, d))
            }
        }
        let last = levels.count - 1
        for k in 0..<n { tris.append((idx(last, k), idx(last, k + 1), topIndex)) }
        var vn = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for t in tris {
            let a = positions[t.0], b = positions[t.1], c = positions[t.2]
            let nrm = simd_cross(b - a, c - a)
            vn[t.0] += nrm
            vn[t.1] += nrm
            vn[t.2] += nrm
        }
        for (i, p) in positions.enumerated() {
            let nn = simd_length(vn[i]) > 1e-6 ? simd_normalize(vn[i]) : SIMD3<Float>(0, 1, 0)
            buf.addVertex(p, nn, .zero, colors[i])
        }
        for t in tris { buf.addTriangle(UInt32(t.0), UInt32(t.1), UInt32(t.2)) }
        return buf
    }

    /// 地図の外の暗がり（2026-10-16）。外周の崖の下（縁から 3 m）から外へ、暗い森の地面 → ほぼ黒へ落とす。
    /// 頂点色だけの不透明な板（stageVertexColorSurface、揺れの重み 0）。地図の切れ目と地平線を見せない。
    static func edgeSkirt(mapMeters M: Float) -> StageMeshBuffer {
        // (縁からの距離 m, 線形の色)
        let rings: [(Float, SIMD3<Float>)] = [
            (3, SIMD3(0.020, 0.032, 0.026)), (12, SIMD3(0.007, 0.012, 0.011)), (30, SIMD3(0.002, 0.003, 0.004)),
            (80, SIMD3(0.001, 0.0015, 0.002)),
        ]
        var buf = StageMeshBuffer(reserveVertices: rings.count * 4)
        let y: Float = 0.006 // 地面（0）・細部タイル（0.004）より上、石畳（0.010）より下
        let up = SIMD3<Float>(0, 1, 0)
        for (d, c) in rings {
            for corner in [SIMD2<Float>(-d, -d), SIMD2(M + d, -d), SIMD2(M + d, M + d), SIMD2(-d, M + d)] {
                buf.addVertex(SIMD3(corner.x, y, -corner.y), up, .zero, stageColor(c.x, c.y, c.z, 0))
            }
        }
        // 上から見て反時計回り（world の法線 +Y）。地図座標の反時計回りは world でも上から見て反時計回り
        for r in 0..<(rings.count - 1) {
            for k in 0..<4 {
                let a = UInt32(r * 4 + k), b = UInt32(r * 4 + (k + 1) % 4)
                let c = UInt32((r + 1) * 4 + (k + 1) % 4), d = UInt32((r + 1) * 4 + k)
                buf.addTriangle(a, d, c)
                buf.addTriangle(a, c, b)
            }
        }
        return buf
    }
}
