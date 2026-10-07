import CoreGraphics
import Foundation
import Metal
import RealityKit
import simd

// 担当: battle-renderer。近接ヒーローの武器の軌跡（振りの間だけ伸びて消える光の帯）。
//
// 帯は LowLevelMesh の 2 × columns 頂点（内端・外端の対）で、毎フレーム頂点だけを書き換える（メッシュ・マテリアル・
// エンティティは読み込み中にヒーローの見た目 1 体につき 1 度だけ作り、AssetLedger に記録する。試合中は作らない）。
// 点の出所は HeroModelHandle.weaponTrailSample()（ワールド座標の握り・先端と振りの最中か）。振りの間だけ標本を積み、
// 振りが終わると帯の頭は止まって尾から消える。標本はフレーム毎の粗い間隔なので、時刻で等間隔の columns 列を
// Catmull-Rom で補間して弧を滑らかにする。
// UV: u = 古さ（0 = 最新 → 1 = 寿命）、v = 根元 → 先端。ヒーロー別の小さなグラデーションのテクスチャ（不透明度は古いほど・
// 根元ほど下がり、新しい先端ほど白く熱い）を UnlitMaterial に貼り、半透明・深度を書かない・両面で描く。
// 深度は読む（本体・地形に隠れる）。地面付近の平面ではないので GroundLayer / OverlayOrder の対象外。

@MainActor
final class WeaponTrail {
    /// 帯の列の数（時刻で等間隔）。
    static let columns = 14
    /// 積む標本の最大（120 fps でも寿命 0.25 秒ぶん）。
    static let capacity = 32
    /// 頂点 1 つのバイト数（位置 float3・法線 float3・UV float2）。
    static let stride = 32
    /// 標本の間でこれ以上跳んだら帯を切る（瞬間移動・復活）。
    static let maxJump: Float = 2.5

    let entity: ModelEntity
    let style: HeroFXProfile.Trail
    private let mesh: LowLevelMesh

    private var times = [Float](repeating: 0, count: WeaponTrail.capacity)
    private var bases = [SIMD3<Float>](repeating: .zero, count: WeaponTrail.capacity)
    private var tips = [SIMD3<Float>](repeating: .zero, count: WeaponTrail.capacity)
    /// 最も古い標本の位置（環状）と数。
    private var head = 0
    private var count = 0
    private var wasSwinging = false
    /// 前フレームの刃（振り始めに帯の始点として足す）。
    private var prevTime: Float = -1
    private var prevBase = SIMD3<Float>.zero
    private var prevTip = SIMD3<Float>.zero
    /// 陳列（ウォームアップ）中は更新で消さない。
    private(set) var isWarmup = false
    /// 帯を描いたフレーム数（計測・テスト用）。
    private(set) var shownFrames = 0

    init?(style: HeroFXProfile.Trail, material: RealityKit.Material, name: String) {
        let n = WeaponTrail.columns
        var d = LowLevelMesh.Descriptor()
        d.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: 0),
            .init(semantic: .normal, format: .float3, offset: 12),
            .init(semantic: .uv0, format: .float2, offset: 24),
        ]
        d.vertexLayouts = [.init(bufferIndex: 0, bufferStride: WeaponTrail.stride)]
        d.vertexCapacity = n * 2
        d.indexCapacity = (n - 1) * 6
        d.indexType = .uint16
        guard let ll = try? LowLevelMesh(descriptor: d) else { return nil }
        ll.withUnsafeMutableIndices { raw in
            let dst = raw.bindMemory(to: UInt16.self)
            var k = 0
            for c in 0..<(n - 1) {
                let a = UInt16(c * 2), b = a + 1, c2 = a + 2, d2 = a + 3
                for i in [a, b, d2, a, d2, c2] {
                    dst[k] = i
                    k += 1
                }
            }
        }
        ll.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            _ = raw.initializeMemory(as: UInt8.self, repeating: 0)
        }
        ll.parts.replaceAll([LowLevelMesh.Part(indexCount: (n - 1) * 6, topology: .triangle,
                                               bounds: BoundingBox(min: [-0.5, 0, -0.5], max: [0.5, 2, 0.5]))])
        guard let resource = try? MeshResource(from: ll) else { return nil }
        AssetLedger.record(.mesh, name)
        AssetLedger.record(.entity, name)
        mesh = ll
        self.style = style
        entity = ModelEntity(mesh: resource, materials: [material])
        entity.name = name
        entity.isEnabled = false
    }

    var isShowing: Bool { entity.isEnabled }

    /// 1 フレーム分の更新。blade = 今の刃（ワールド）、origin = 帯の親（HeroVisual.root）のワールド位置
    /// （親は平行移動だけ。回転は modelRoot 側）。blade = nil は刃なし（帯は尾から消えるだけ）。
    func update(_ blade: HeroWeaponTrailSample.Blade?, now: Float, origin: SIMD3<Float>) {
        if isWarmup { return }
        if let b = blade {
            if b.swing {
                if !wasSwinging || count == 0 || now - newestTime > style.life {
                    // 振り始め: 前の帯を捨て、前フレームの刃から始める（1 フレーム目から帯になる）
                    count = 0
                    if prevTime >= 0, now > prevTime, now - prevTime < 0.1 { push(prevTime, prevBase, prevTip) }
                }
                push(now, b.base, b.tip)
            }
            wasSwinging = b.swing
            prevTime = now
            prevBase = b.base
            prevTip = b.tip
        } else {
            wasSwinging = false
            prevTime = -1
        }
        rebuild(now: now, origin: origin)
    }

    /// 帯を消して標本を捨てる（死亡・不可視・画質で切った時）。
    func reset() {
        isWarmup = false
        count = 0
        wasSwinging = false
        prevTime = -1
        if entity.isEnabled { entity.isEnabled = false }
    }

    /// ウォームアップの陳列: local（親の座標）を中心に扇形の帯を出してシェーダーを幕の裏で作らせる。reset で戻す。
    func showForWarmup(at local: SIMD3<Float>) {
        isWarmup = true
        let n = WeaponTrail.columns
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        mesh.replaceUnsafeMutableBytes(bufferIndex: 0) { raw in
            guard let dst = raw.baseAddress else { return }
            for k in 0..<n {
                let f = Float(k) / Float(n - 1)
                let a = -1.2 + 2.4 * f
                let dir = SIMD3<Float>(sin(a), 0.2, -cos(a))
                let inner = local + dir * 0.15, outer = local + dir * 0.55
                lo = simd_min(lo, simd_min(inner, outer))
                hi = simd_max(hi, simd_max(inner, outer))
                WeaponTrail.write(dst, k * 2, inner, uv: WeaponTrail.uv(f * 0.9, 0))
                WeaponTrail.write(dst, k * 2 + 1, outer, uv: WeaponTrail.uv(f * 0.9, 1))
            }
        }
        setBounds(lo, hi)
        entity.isEnabled = true
    }

    /// 書き込んだ頂点（位置・UV。列 k の内端が 2k、外端が 2k + 1。テスト用）。
    func vertices() -> [(position: SIMD3<Float>, uv: SIMD2<Float>)] {
        var out: [(position: SIMD3<Float>, uv: SIMD2<Float>)] = []
        mesh.withUnsafeBytes(bufferIndex: 0) { raw in
            guard let src = raw.baseAddress else { return }
            for k in 0..<(WeaponTrail.columns * 2) {
                let o = src + k * WeaponTrail.stride
                let p = SIMD3<Float>(o.load(fromByteOffset: 0, as: Float.self), o.load(fromByteOffset: 4, as: Float.self),
                                     o.load(fromByteOffset: 8, as: Float.self))
                let uv = SIMD2<Float>(o.load(fromByteOffset: 24, as: Float.self), o.load(fromByteOffset: 28, as: Float.self))
                out.append((p, uv))
            }
        }
        return out
    }

    // MARK: 標本

    private var newestTime: Float { count > 0 ? times[(head + count - 1) % WeaponTrail.capacity] : -.greatestFiniteMagnitude }

    @inline(__always)
    private func slot(_ k: Int) -> Int { (head + k) % WeaponTrail.capacity }

    private func push(_ t: Float, _ base: SIMD3<Float>, _ tip: SIMD3<Float>) {
        if count > 0 {
            let last = slot(count - 1)
            if simd_distance(tips[last], tip) > WeaponTrail.maxJump { count = 0 }
        }
        if count > 0 {
            let last = slot(count - 1)
            if t - times[last] < 1e-4 {
                // 同じ時刻（dt = 0 のフレーム）は置き換える
                bases[last] = base
                tips[last] = tip
                return
            }
        }
        if count == WeaponTrail.capacity {
            head = (head + 1) % WeaponTrail.capacity
            count -= 1
        }
        let i = slot(count)
        times[i] = t
        bases[i] = base
        tips[i] = tip
        count += 1
    }

    // MARK: 帯の組み立て

    private func rebuild(now: Float, origin: SIMD3<Float>) {
        let life = style.life
        guard count >= 2 else { return hide() }
        let newest = times[slot(count - 1)]
        // 寿命を過ぎた古い標本を捨てる（補間に 1 つ前を残す）
        while count > 2, times[slot(1)] < now - life {
            head = (head + 1) % WeaponTrail.capacity
            count -= 1
        }
        if now - newest >= life {
            // 帯の頭まで消えた: 標本を捨てる
            count = 0
            return hide()
        }
        let oldest = times[slot(0)]
        let start = max(oldest, now - life)
        guard newest - start > 1e-4 else { return hide() }
        let n = WeaponTrail.columns
        let inner = style.inner, outer = style.outer
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        var j = count - 2
        mesh.replaceUnsafeMutableBytes(bufferIndex: 0) { raw in
            guard let dst = raw.baseAddress else { return }
            for k in 0..<n {
                let t = newest - (newest - start) * Float(k) / Float(n - 1)
                while j > 0 && times[slot(j)] > t { j -= 1 }
                let t0 = times[slot(j)], t1 = times[slot(j + 1)]
                let s = t1 > t0 ? min(1, max(0, (t - t0) / (t1 - t0))) : 0
                let i0 = slot(max(0, j - 1)), i1 = slot(j), i2 = slot(j + 1), i3 = slot(min(count - 1, j + 2))
                let base = WeaponTrail.catmullRom(bases[i0], bases[i1], bases[i2], bases[i3], s)
                let tip = WeaponTrail.catmullRom(tips[i0], tips[i1], tips[i2], tips[i3], s)
                let a = base + (tip - base) * inner - origin
                let b = base + (tip - base) * outer - origin
                lo = simd_min(lo, simd_min(a, b))
                hi = simd_max(hi, simd_max(a, b))
                let u = min(1, max(0, (now - t) / life))
                WeaponTrail.write(dst, k * 2, a, uv: WeaponTrail.uv(u, 0))
                WeaponTrail.write(dst, k * 2 + 1, b, uv: WeaponTrail.uv(u, 1))
            }
        }
        setBounds(lo, hi)
        if !entity.isEnabled { entity.isEnabled = true }
        shownFrames += 1
    }

    private func hide() {
        if entity.isEnabled { entity.isEnabled = false }
    }

    private func setBounds(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>) {
        guard lo.x <= hi.x else { return }
        mesh.parts[0].bounds = BoundingBox(min: lo - 0.05, max: hi + 0.05)
    }

    /// テクスチャの端の画素で隣（u = 1 の透明な列）と混ざらないよう、内側へ寄せた UV。
    @inline(__always)
    static func uv(_ u: Float, _ v: Float) -> SIMD2<Float> {
        SIMD2(0.02 + 0.96 * u, 0.04 + 0.92 * v)
    }

    @inline(__always)
    private static func write(_ dst: UnsafeMutableRawPointer, _ index: Int, _ p: SIMD3<Float>, uv: SIMD2<Float>) {
        let o = dst + index * stride
        o.storeBytes(of: p.x, toByteOffset: 0, as: Float.self)
        o.storeBytes(of: p.y, toByteOffset: 4, as: Float.self)
        o.storeBytes(of: p.z, toByteOffset: 8, as: Float.self)
        o.storeBytes(of: Float(0), toByteOffset: 12, as: Float.self)
        o.storeBytes(of: Float(1), toByteOffset: 16, as: Float.self)
        o.storeBytes(of: Float(0), toByteOffset: 20, as: Float.self)
        o.storeBytes(of: uv.x, toByteOffset: 24, as: Float.self)
        o.storeBytes(of: uv.y, toByteOffset: 28, as: Float.self)
    }

    /// 一様 Catmull-Rom（p1 → p2 を s で補間。端は点を重ねる）。
    @inline(__always)
    static func catmullRom(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>,
                           _ s: Float) -> SIMD3<Float> {
        // 型を決めて 1 項ずつ書く（SIMD3 と整数リテラルの長い式は、CI の Xcode で「型検査が時間内に終わらない」エラーになった）。
        // 計算の順序は元の式（2*p0 - 5*p1 + 4*p2 - p3 など）と同じ。
        let k2: Float = 2, k3: Float = 3, k4: Float = 4, k5: Float = 5
        let s2: Float = s * s
        let s3: Float = s2 * s
        let a: SIMD3<Float> = k2 * p1
        let b: SIMD3<Float> = (p2 - p0) * s
        let c0: SIMD3<Float> = k2 * p0 - k5 * p1
        let c1: SIMD3<Float> = c0 + k4 * p2
        let c: SIMD3<Float> = (c1 - p3) * s2
        let d0: SIMD3<Float> = k3 * p1 - p0
        let d1: SIMD3<Float> = d0 - k3 * p2
        let d: SIMD3<Float> = (d1 + p3) * s3
        let sum: SIMD3<Float> = a + b + c + d
        return sum * 0.5
    }
}

// MARK: - テクスチャ・マテリアル

/// 軌跡のグラデーションのテクスチャとマテリアル（ヒーロー ID ごとに 1 つ、読み込み中に作る）。
@MainActor
final class WeaponTrailKit {
    /// テクスチャの大きさ（u = 古さ × v = 根元 → 先端）。
    static let textureSize = (u: 64, v: 32)

    private var cache: [String: UnlitMaterial] = [:]

    /// 作ったマテリアルの数（テスト用）。
    var materialCount: Int { cache.count }

    func material(for profile: HeroFXProfile, trail: HeroFXProfile.Trail) -> UnlitMaterial? {
        if let m = cache[profile.heroID] { return m }
        let (w, h) = WeaponTrailKit.textureSize
        var px = WeaponTrailKit.pixels(look: trail.look, color: profile.primary, width: w, height: h)
        let tex: TextureResource? = px.withUnsafeMutableBytes { raw -> TextureResource? in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let img = ctx.makeImage() else { return nil }
            return try? TextureResource(image: img, options: .init(semantic: .color, mipmapsMode: .none))
        }
        guard let tex else { return nil }
        AssetLedger.record(.texture, "weapon trail \(profile.heroID)")
        AssetLedger.record(.material, "weapon trail \(profile.heroID)")
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        m.color = .init(tint: .white, texture: .init(tex))
        m.blending = .transparent(opacity: .init(floatLiteral: trail.opacity))
        m.writesDepth = false
        m.faceCulling = .none
        cache[profile.heroID] = m
        return m
    }

    /// 帯の不透明度の分布。u = 古さ（0 = 最新 → 1 = 寿命）、v = 根元 → 先端。古いほど・根元ほど薄い。
    static func alpha(look: HeroFXProfile.TrailLook, u: Float, v: Float) -> Float {
        func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
            let t = min(1, max(0, (x - a) / (b - a)))
            return t * t * (3 - 2 * t)
        }
        let age: Float
        let across: Float
        switch look {
        case .blade:
            age = pow(1 - u, 1.6)
            across = smooth(0, 0.45, v) * (0.5 + 0.5 * v) * (1 - smooth(0.96, 1, v) * 0.5)
        case .thin:
            age = pow(1 - u, 1.4)
            across = smooth(0.45, 0.85, v) * (1 - smooth(0.96, 1, v) * 0.6)
        case .soft:
            age = pow(1 - u, 1.1)
            across = smooth(0, 0.6, v) * (1 - smooth(0.78, 1, v) * 0.85)
        case .heavy:
            age = pow(1 - u, 1.3)
            across = smooth(0, 0.3, v) * (1 - smooth(0.92, 1, v) * 0.4)
        }
        return max(0, min(1, age * across))
    }

    /// 新しい先端ほど白く熱い（0 = 主色、1 = 白）。
    static func whiteness(look: HeroFXProfile.TrailLook, u: Float, v: Float) -> Float {
        let hot = (1 - u) * (1 - u)
        let edge = max(0, (v - 0.55) / 0.45)
        let k: Float = look == .soft ? 0.45 : 0.75
        return min(1, hot * edge * edge * k)
    }

    /// テクスチャの画素（RGBA・アルファ乗算済み、行 0 = 画像の上端 = v 最大。RealityKit は UV の原点を左下に取る）。
    static func pixels(look: HeroFXProfile.TrailLook, color: RGB, width w: Int, height h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for row in 0..<h {
            let v = 1 - (Float(row) + 0.5) / Float(h)
            for col in 0..<w {
                let u = (Float(col) + 0.5) / Float(w)
                let a = alpha(look: look, u: u, v: v)
                let c = color.mixed(RGB(1, 1, 1), Double(whiteness(look: look, u: u, v: v)))
                let i = (row * w + col) * 4
                func q(_ x: Double) -> UInt8 { UInt8(max(0, min(255, (x * 255).rounded()))) }
                out[i] = q(c.r * Double(a))
                out[i + 1] = q(c.g * Double(a))
                out[i + 2] = q(c.b * Double(a))
                out[i + 3] = q(Double(a))
            }
        }
        return out
    }
}
