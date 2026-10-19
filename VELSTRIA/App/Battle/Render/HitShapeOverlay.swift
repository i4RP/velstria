#if DEBUG || TESTER_TOOLS
import Foundation
import Metal
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer（内部ビルドの「判定の形」の表示。docs/vfx/RANGES.md）。
// sim が実際に当たりを調べた形（HitShapeProbe: 円・扇・線の幅と長さ・帯・単体の命中）を、判定の瞬間から 0.5 秒、地面に細い線で描く。
// 設定 > テスター用 の「判定の形を表示」（UserDefaults）で有効にした試合と、比較撮影（-fxCapture）・-hitShapes で出す。
// 3D の場面の中に描くので、演出チェック（ReplayKit）の録画・比較撮影の画面にも写る。
// - 判定・数値は変えない（受け口で形を受け取るだけ）。シーク中（裏で進め直す tick）の形は捨てる。
// - 線はチームごとに 1 つの LowLevelMesh（頂点だけを書き換える）。メッシュ・材質・エンティティは読み込み中に作り
//   （AssetLedger に記録）、試合中は作らない。線の数には上限（maxQuads）があり、超えた分は描かない。
// - 弾・突進の毎 tick の掃引は同じ鍵（trackID）の線をつないで 1 本にし、持続するゾーンは最新の形に置き換える。

@MainActor
final class HitShapeOverlay {
    /// 設定の鍵（設定 > テスター用 の「判定の形を表示」）。
    static let enabledKey = "velstria.hitShapes"

    /// この試合で出すか（設定・比較撮影・起動引数。-noHitShapes で出さない）。
    static var isRequested: Bool {
        #if DEBUG
        if DebugLaunch.args.contains("-noHitShapes") { return false }
        if DebugLaunch.value(after: "-fxCapture") != nil || DebugLaunch.args.contains("-hitShapes") { return true }
        #endif
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// 線を出す長さ（秒。描画の時間。ヒットストップ・一時停止の間は進まない）。
    static let lifetime: Float = 0.5
    /// 線の幅（m）。
    static let lineWidth: Float = 0.06
    /// 円を分ける数（一周）。
    static let circleSegments = 48
    /// 1 チームの線の上限（四角形の数）。
    static let maxQuads = 2048
    /// 覚えておく形の上限（古いものから捨てる）。
    static let maxItems = 96
    /// 1 フレームに受け取る形の上限（超えた分は捨てる）。
    static let maxPending = 256
    /// 地面からの高さ（照準より少し上）。
    static let height: Float = GroundLayer.aim + 0.002
    /// 描画順（照準より後 = 上）。
    static let order: Int32 = OverlayOrder.aim + 1
    /// 頂点 1 つのバイト数（位置 float3・法線 float3・UV float2。WeaponTrail と同じ並び）。
    static let stride = 32

    /// 表示中の形（線に直す前）。
    struct Item {
        var shape: HitShape
        var age: Float = 0
    }

    let root = Entity()
    private(set) var items: [Item] = []
    private var pending: [HitShape] = []
    private var dirty = false
    private weak var controller: BattleController?
    private var layers: [Team: (mesh: LowLevelMesh, entity: ModelEntity)] = [:]
    private var attached = false
    /// 描いた四角形の数（チームごと。テスト用）。
    private(set) var quadCounts: [Team: Int] = [:]

    init(controller: BattleController) {
        self.controller = controller
        root.name = "hitShapes"
        for team in [Team.blue, Team.red] {
            guard let layer = HitShapeOverlay.makeLayer(team: team) else { continue }
            layers[team] = layer
            root.addChild(layer.entity)
        }
    }

    /// 受け口を置く（この試合の間だけ。外すのは detach）。
    func attach() {
        guard !attached else { return }
        attached = true
        HitShapeProbe.sink = { [weak self] shape in
            MainActor.assumeIsolated { self?.receive(shape) }
        }
    }

    /// 受け口を外して線を消す（試合の終わり）。
    func detach() {
        if attached { HitShapeProbe.sink = nil }
        attached = false
        items.removeAll()
        pending.removeAll()
        for (_, l) in layers { l.entity.isEnabled = false }
    }

    /// sim の判定の形（HitShapeProbe の受け口から。sim の tick の中で呼ばれる）。
    func receive(_ shape: HitShape) {
        // シーク・裏の進め直しの形は出さない
        if controller?.seekingToTick != nil { return }
        guard pending.count < HitShapeOverlay.maxPending else { return }
        pending.append(shape)
    }

    /// 毎フレーム（BattleWorld.sync）。dt = 描画の時間。
    func update(dt: Float) {
        if !pending.isEmpty {
            for s in pending { merge(s) }
            pending.removeAll(keepingCapacity: true)
            dirty = true
        }
        if !items.isEmpty {
            for k in items.indices { items[k].age += dt }
            let before = items.count
            items.removeAll { $0.age >= HitShapeOverlay.lifetime }
            if items.count != before { dirty = true }
        }
        guard dirty else { return }
        dirty = false
        rebuild()
    }

    /// 弾・突進の掃引は同じ鍵の線をつなぐ。ゾーンは最新の形に置き換える。
    private func merge(_ s: HitShape) {
        if s.trackID != 0, let k = items.lastIndex(where: { $0.shape.trackID == s.trackID && $0.shape.kind == s.kind }) {
            switch (s.kind, items[k].shape.form, s.form) {
            case (.projectile, .line(let a, _, let hw, let sq), .line(_, let b, _, _)),
                 (.sweep, .line(let a, _, let hw, let sq), .line(_, let b, _, _)):
                items[k].shape.form = .line(from: a, to: b, halfWidth: hw, squareEnds: sq)
                items[k].shape.time = s.time
                items[k].age = 0
                return
            case (.zone, _, _):
                items[k] = Item(shape: s)
                return
            default:
                break
            }
        }
        items.append(Item(shape: s))
        if items.count > HitShapeOverlay.maxItems { items.removeFirst(items.count - HitShapeOverlay.maxItems) }
    }

    // MARK: 線の組み立て

    /// 形 → 地面の線分（sim の座標）。
    static func segments(_ form: HitShape.Form) -> [(Vec2, Vec2)] {
        func circle(_ c: Vec2, _ r: Double) -> [(Vec2, Vec2)] {
            arc(c, r, from: 0, to: 2 * .pi, count: circleSegments)
        }
        func arc(_ c: Vec2, _ r: Double, from a0: Double, to a1: Double, count n: Int) -> [(Vec2, Vec2)] {
            guard r > 0 else { return [] }
            let k = max(1, n)
            return (0..<k).map { i in
                let u0 = a0 + (a1 - a0) * Double(i) / Double(k)
                let u1 = a0 + (a1 - a0) * Double(i + 1) / Double(k)
                return (c + Vec2.fromAngle(u0) * r, c + Vec2.fromAngle(u1) * r)
            }
        }
        switch form {
        case .circle(let c, let r, let inner):
            return circle(c, r) + (inner > 0 ? circle(c, inner) : [])
        case .cone(let c, let d, let r, let half, let inner):
            let mid = d.angle
            let n = max(6, Int(Double(circleSegments) * half / .pi))
            var out = arc(c, r, from: mid - half, to: mid + half, count: n)
            if inner > 0 { out += arc(c, inner, from: mid - half, to: mid + half, count: n) }
            let a = Vec2.fromAngle(mid - half), b = Vec2.fromAngle(mid + half)
            out.append((c + a * inner, c + a * r))
            out.append((c + b * inner, c + b * r))
            return out
        case .line(let a, let b, let hw, let square):
            let ab = b - a
            let len = ab.length
            let dir = len > 1e-6 ? ab / len : Vec2(1, 0)
            let n = Vec2(-dir.y, dir.x) * hw
            var out: [(Vec2, Vec2)] = [(a + n, b + n), (a - n, b - n)]
            if square {
                out += [(a + n, a - n), (b + n, b - n)]
            } else {
                // 端の半円（カプセル）
                let ang = dir.angle
                out += arc(b, hw, from: ang - .pi / 2, to: ang + .pi / 2, count: 10)
                out += arc(a, hw, from: ang + .pi / 2, to: ang + 3 * .pi / 2, count: 10)
            }
            return out
        case .polygon(let p):
            guard p.count >= 2 else { return [] }
            return p.indices.map { (p[$0], p[($0 + 1) % p.count]) }
        case .unit(let at, let r):
            return circle(at, r)
        }
    }

    private func rebuild() {
        var byTeam: [Team: [(Vec2, Vec2)]] = [:]
        for item in items {
            let team: Team = item.shape.team == .red ? .red : .blue
            byTeam[team, default: []] += HitShapeOverlay.segments(item.shape.form)
        }
        for (team, layer) in layers {
            let segs = byTeam[team] ?? []
            let n = min(segs.count, HitShapeOverlay.maxQuads)
            quadCounts[team] = n
            guard n > 0 else {
                if layer.entity.isEnabled { layer.entity.isEnabled = false }
                continue
            }
            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
            let h = HitShapeOverlay.height
            let w = HitShapeOverlay.lineWidth / 2
            layer.mesh.replaceUnsafeMutableBytes(bufferIndex: 0) { raw in
                guard let dst = raw.baseAddress else { return }
                for k in 0..<n {
                    let p = worldPosition(segs[k].0, height: h)
                    let q = worldPosition(segs[k].1, height: h)
                    var d = q - p
                    d.y = 0
                    let len = (d * d).sum().squareRoot()
                    let dir = len > 1e-5 ? d / len : SIMD3<Float>(1, 0, 0)
                    // 継ぎ目が欠けないよう、線の幅の半分だけ両端へ伸ばす
                    let a = p - dir * w, b = q + dir * w
                    let side = SIMD3<Float>(-dir.z, 0, dir.x) * w
                    let v = [a - side, a + side, b + side, b - side]
                    for (j, pos) in v.enumerated() {
                        HitShapeOverlay.write(dst, k * 4 + j, pos)
                        lo = simd_min(lo, pos)
                        hi = simd_max(hi, pos)
                    }
                }
            }
            layer.mesh.parts[0].indexCount = n * 6
            layer.mesh.parts[0].bounds = BoundingBox(min: lo - 0.05, max: hi + 0.05)
            if !layer.entity.isEnabled { layer.entity.isEnabled = true }
        }
    }

    @inline(__always)
    private static func write(_ dst: UnsafeMutableRawPointer, _ index: Int, _ p: SIMD3<Float>) {
        let o = dst + index * stride
        o.storeBytes(of: p.x, toByteOffset: 0, as: Float.self)
        o.storeBytes(of: p.y, toByteOffset: 4, as: Float.self)
        o.storeBytes(of: p.z, toByteOffset: 8, as: Float.self)
        o.storeBytes(of: Float(0), toByteOffset: 12, as: Float.self)
        o.storeBytes(of: Float(1), toByteOffset: 16, as: Float.self)
        o.storeBytes(of: Float(0), toByteOffset: 20, as: Float.self)
        o.storeBytes(of: Float(0), toByteOffset: 24, as: Float.self)
        o.storeBytes(of: Float(0), toByteOffset: 28, as: Float.self)
    }

    /// チームの線の入れ物（メッシュ・材質・エンティティ。読み込み中に 1 回だけ作る）。
    private static func makeLayer(team: Team) -> (mesh: LowLevelMesh, entity: ModelEntity)? {
        var d = LowLevelMesh.Descriptor()
        d.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: 0),
            .init(semantic: .normal, format: .float3, offset: 12),
            .init(semantic: .uv0, format: .float2, offset: 24),
        ]
        d.vertexLayouts = [.init(bufferIndex: 0, bufferStride: stride)]
        d.vertexCapacity = maxQuads * 4
        d.indexCapacity = maxQuads * 6
        d.indexType = .uint16
        guard let ll = try? LowLevelMesh(descriptor: d) else { return nil }
        ll.withUnsafeMutableIndices { raw in
            let dst = raw.bindMemory(to: UInt16.self)
            for q in 0..<maxQuads {
                let a = UInt16(q * 4)
                for (j, i) in [a, a + 1, a + 2, a, a + 2, a + 3].enumerated() { dst[q * 6 + j] = i }
            }
        }
        ll.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            _ = raw.initializeMemory(as: UInt8.self, repeating: 0)
        }
        ll.parts.replaceAll([LowLevelMesh.Part(indexCount: 0, topology: .triangle,
                                               bounds: BoundingBox(min: [-1, 0, -1], max: [1, 0.1, 1]))])
        guard let resource = try? MeshResource(from: ll) else { return nil }
        let name = "hit shapes \(team)"
        AssetLedger.record(.mesh, name)
        AssetLedger.record(.material, name)
        AssetLedger.record(.entity, name)
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        let c: UIColor = team == .red ? UIColor(red: 1, green: 0.35, blue: 0.3, alpha: 1)
            : UIColor(red: 0.25, green: 0.95, blue: 1, alpha: 1)
        m.color = .init(tint: c)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.95))
        m.writesDepth = false
        m.faceCulling = .none
        let e = ModelEntity(mesh: resource, materials: [m])
        e.name = name
        e.isEnabled = false
        OverlayOrder.apply(e, order)
        return (ll, e)
    }
}
#endif
