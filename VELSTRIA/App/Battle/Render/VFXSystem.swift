import CoreGraphics
import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。パーティクル（ParticleEmitterComponent）のプリセットとプール、
// 安価なメッシュ演出（広がる輪・閃光球）。同時放出体の数と粒子数は画質設定で制限する。
//
// 放出体は種類（preset）ごとのプールに、その種類の ParticleEmitterComponent を付けたまま保持する。
// 再生のたびに色・大きさ・数を既存の部品へ書き戻して restart() するだけで、部品の構築・付け外しはしない
// （外して付け直すと RealityKit が粒子系をその場で作り直し、戦闘中の初回・多発時のヒッチになる）。
// 見た目は従来（再生毎に新しい部品を作る）と同じ: configure は種類ごとに決まった項目を全て書くので、同じ種類の部品へ
// 書き戻した値は新規に作った値と一致する。値の書き戻し・restart は構築ではないので AssetLedger の .emitter に数えない
// （.emitter は ParticleEmitterComponent() を呼ぶ箇所 = 読み込み中のプール生成だけ）。種類のプールが尽きた時に他の種類の
// 空きを借りる場合も、既定値の雛形（1 度だけ構築）の写しから設定し直すだけで構築しない。
// プールの大きさは試合開始時の画質（利用者が選んだ画質）で決め、試合中に画質が下がっても作り直さない。

enum VFXPreset: CaseIterable, Hashable {
    case hitSpark
    case crit
    case magicHit
    case heal
    case shield
    case levelUp
    case death
    case heroDeath
    case respawn
    case towerExplosion
    case debris
    case smoke
    case gold
    case skillBurst
    case blink
    case areaBlast
    case trail
    case recallLoop
}

@MainActor
final class VFXSystem {
    let root = Entity()
    private var quality: RenderQuality
    /// プールの大きさを決めた画質（試合開始時の設定。適応で下げても作り直さない）。
    let poolQuality: RenderQuality
    private let materials: RenderMaterials
    private let meshes: UnitMeshLibrary

    /// プールの放出体（種類ごとの部品を付けたまま保持する）。
    @MainActor
    final class Emitter {
        let entity = Entity()
        fileprivate(set) var preset: VFXPreset
        /// 付いている部品がこの種類の設定か（他の種類のプールから借りた直後は false = 既定値の雛形から設定し直す）。
        fileprivate var configured = true

        fileprivate init(preset: VFXPreset) { self.preset = preset }
    }

    private struct Active {
        var emitter: Emitter
        var until: Float
        var important: Bool
    }

    private var free: [VFXPreset: [Emitter]] = [:]
    private var active: [Active] = []
    private var loops: [EntityID: Emitter] = [:]
    private var time: Float = 0
    /// プールを事前に作った（以後は作らずに使い回す）。
    private var prewarmed = false

    /// 計測用の集計（再生数・種類ごとの同時再生の最大・プールが尽きて借りた/打ち切った回数）。
    struct Stats {
        var spawns = 0
        var peak: [VFXPreset: Int] = [:]
        var borrowed = 0
        var stolen = 0
    }
    private(set) var stats = Stats()
    private var activeByPreset: [VFXPreset: Int] = [:]
    /// 既定値の部品（他の種類から借りた放出体を設定し直す時の初期値。構築は 1 度だけ）。
    private lazy var blank: ParticleEmitterComponent = {
        AssetLedger.record(.emitter, "vfx blank template")
        return ParticleEmitterComponent()
    }()

    // メッシュ演出
    private struct MeshFX {
        var entity: ModelEntity
        var start: Float
        var duration: Float
        var fromScale: SIMD3<Float>
        var toScale: SIMD3<Float>
        var alpha: Float
        var kind: Int
    }

    /// 同時に表示できるメッシュ演出（輪 + 閃光）の上限。プールは輪・閃光それぞれこの数まで事前に作る。
    static let meshFXCap = 40
    /// 輪の Unlit の不透明度（半透明 = 深度を書かない）と閃光（不透明。フェードは OpacityComponent）。
    static let ringAlpha = 0.99
    static let flashAlpha = 0.999

    private var freeRings: [ModelEntity] = []
    private var freeFlashes: [ModelEntity] = []
    private var ringCount = 0
    private var flashCount = 0
    private var meshFX: [MeshFX] = []

    private(set) lazy var dotTexture: TextureResource? = VFXSystem.makeTexture(size: 64, name: "vfx dot") { ctx, s in
        let colors = [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)]
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
                                   endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s / 2, options: [])
        }
    }

    private(set) lazy var starTexture: TextureResource? = VFXSystem.makeTexture(size: 64, name: "vfx star") { ctx, s in
        let c = s / 2
        let colors = [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)]
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c, y: c), startRadius: 0, endCenter: CGPoint(x: c, y: c),
                                   endRadius: s * 0.22, options: [])
        }
        // 4 方向の光条
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
        for k in 0..<4 {
            ctx.saveGState()
            ctx.translateBy(x: c, y: c)
            ctx.rotate(by: CGFloat(k) * .pi / 2)
            ctx.move(to: CGPoint(x: 0, y: -s * 0.05))
            ctx.addLine(to: CGPoint(x: s * 0.48, y: 0))
            ctx.addLine(to: CGPoint(x: 0, y: s * 0.05))
            ctx.closePath()
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    init(quality: RenderQuality, materials: RenderMaterials, meshes: UnitMeshLibrary) {
        self.quality = quality
        poolQuality = quality
        self.materials = materials
        self.meshes = meshes
        root.name = "vfx"
        active.reserveCapacity(64)
        meshFX.reserveCapacity(48)
    }

    func apply(quality q: RenderQuality) { quality = q }

    var activeCount: Int { active.count + loops.count + meshFX.count }

    /// プールの放出体の総数（テスト・計測用）。
    var pooledEmitterCount: Int { free.values.reduce(0) { $0 + $1.count } + active.count + loops.count }

    // MARK: 事前生成

    /// 種類ごとの初期の割り当ての重み（観戦試合の headless 計測での同時再生の最大: 1 倍速 150 秒と 4 倍速 9 分の中間）。
    /// 実際の配分は借り合いで使われ方に合わせて変わる（1 倍速で借りるのは再生の約 3%）。
    static func weight(_ preset: VFXPreset) -> Int {
        switch preset {
        case .hitSpark: return 20
        case .magicHit: return 10
        case .blink: return 8
        case .levelUp, .skillBurst, .areaBlast, .trail: return 5
        case .shield: return 4
        case .death, .gold: return 3
        case .heal, .crit: return 2
        case .heroDeath, .respawn, .towerExplosion, .debris, .smoke: return 1
        case .recallLoop: return 0
        }
    }

    /// 帰還・転移ループの初期の割り当て（同時に詠唱するヒーローがこれを超えたら他の種類から借りる）。
    static let loopCapacity = 4

    /// 種類ごとの初期のプールの大きさ。合計はおよそ maxEmitters（+ ループ）で、どの種類も最低 1 つ。
    /// 放出体は付けたままの粒子系 1 つにつき約 1 MB（シミュレータ実測）を常に持つため、合計を同時再生の上限に合わせる
    /// （種類ごとに上限まで持つと高画質で 200 個超 = 数百 MB になる）。使われ方の偏りは借り合いで吸収する。
    static func capacity(_ preset: VFXPreset, maxEmitters m: Int) -> Int {
        if preset == .recallLoop { return loopCapacity }
        let total = VFXPreset.allCases.reduce(0) { $0 + weight($1) }
        return max(1, Int((Float(weight(preset) * m) / Float(total)).rounded()))
    }

    /// 放出体のプールを試合開始時の画質の上限まで作る（読み込み幕の裏。種類ごとに部品を構築して付けておく）。
    func prewarmEmitters() {
        _ = dotTexture
        _ = starTexture
        _ = blank
        prewarmed = true
        for preset in VFXPreset.allCases {
            let want = VFXSystem.capacity(preset, maxEmitters: poolQuality.maxEmitters)
            var list = free[preset] ?? []
            while list.count < want { list.append(makeEmitter(preset)) }
            free[preset] = list
        }
    }

    /// 輪・閃光のプールを上限まで作る。
    func prewarmMeshFX() {
        while ringCount < VFXSystem.meshFXCap { freeRings.append(makeRing()) }
        while flashCount < VFXSystem.meshFXCap { freeFlashes.append(makeFlash()) }
    }

    private func makeEmitter(_ preset: VFXPreset) -> Emitter {
        AssetLedger.record(.entity, "vfx emitter")
        AssetLedger.record(.emitter, "\(preset)")
        let em = Emitter(preset: preset)
        var c = ParticleEmitterComponent()
        _ = configure(&c, preset, color: FXColors.white, scale: 1, count: nil)
        em.entity.components.set(c)
        em.entity.isEnabled = false
        root.addChild(em.entity)
        return em
    }

    private func makeRing() -> ModelEntity {
        AssetLedger.record(.entity, "vfx ring")
        ringCount += 1
        let m = ModelEntity(mesh: meshes.ring(radius: 1, thickness: 0.12) ?? meshes.unitSphere, materials: [])
        OverlayOrder.apply(m, OverlayOrder.vfxRing)
        m.isEnabled = false
        root.addChild(m)
        return m
    }

    private func makeFlash() -> ModelEntity {
        AssetLedger.record(.entity, "vfx flash")
        flashCount += 1
        let m = ModelEntity(mesh: meshes.unitSphere, materials: [])
        m.isEnabled = false
        root.addChild(m)
        return m
    }

    /// 種類のプールから放出体を取り出す。事前生成済み（prewarmEmitters 後）なら空でも作らずに、
    /// 1. 他の種類の空きを借りて設定し直す（以後はその種類のプールへ戻る = 使われ方に合わせて配分が変わる）
    /// 2. 空きが無ければ再生中で最も古いもの（同じ種類を優先、ループは除く）を打ち切って使い回す
    /// 事前生成していなければ新しく作る（台帳に記録。テスト用の単体の VFXSystem だけ）。
    private func take(_ preset: VFXPreset) -> Emitter {
        if let em = free[preset]?.popLast() { return em }
        if prewarmed {
            if let donor = free.max(by: { $0.value.count < $1.value.count }), donor.value.count > 0,
               let em = free[donor.key]?.popLast() {
                em.preset = preset
                em.configured = false
                stats.borrowed += 1
                return em
            }
            var oldest: Int?
            for k in active.indices {
                let same = active[k].emitter.preset == preset
                guard let o = oldest else { oldest = k; continue }
                let oSame = active[o].emitter.preset == preset
                if same != oSame { if same { oldest = k }; continue }
                if active[k].until < active[o].until { oldest = k }
            }
            if let k = oldest {
                let em = active[k].emitter
                active.swapAt(k, active.count - 1)
                active.removeLast()
                activeByPreset[em.preset, default: 1] -= 1
                if em.preset != preset {
                    em.preset = preset
                    em.configured = false
                }
                stats.stolen += 1
                return em
            }
        }
        return makeEmitter(preset)
    }

    /// 放出体を再生する（部品は付けたまま値を合わせて restart。構築しない）。戻り値は回収までの秒数。
    private func fire(_ em: Emitter, at p: SIMD3<Float>, color: UIColor, scale: Float, count: Int?,
                      direction: SIMD3<Float>?, life: Double?) -> Float {
        var c = em.configured ? (em.entity.components[ParticleEmitterComponent.self] ?? blank) : blank
        em.configured = true
        let until = configure(&c, em.preset, color: color, scale: scale, count: count, life: life)
        c.restart()
        em.entity.position = p
        if let d = direction, simd_length(d) > 1e-4 {
            em.entity.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(d))
        } else {
            em.entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        }
        em.entity.components.set(c)
        em.entity.isEnabled = true
        return until
    }

    // MARK: パーティクル

    /// important = false の演出は予算超過時に省略する。life = 粒子の寿命の上書き（EffectDef.durationSec）。
    func spawn(_ preset: VFXPreset, at p: SIMD3<Float>, color: UIColor, scale: Float = 1, count: Int? = nil,
               important: Bool = false, direction: SIMD3<Float>? = nil, life: Double? = nil) {
        if active.count >= quality.maxEmitters {
            guard important, let k = active.firstIndex(where: { !$0.important }) else { return }
            release(at: k)
        }
        let em = take(preset)
        let until = fire(em, at: p, color: color, scale: scale, count: count, direction: direction, life: life)
        active.append(Active(emitter: em, until: time + until, important: important))
        noteActive(preset)
    }

    private func noteActive(_ preset: VFXPreset) {
        stats.spawns += 1
        let n = (activeByPreset[preset] ?? 0) + 1
        activeByPreset[preset] = n
        if n > stats.peak[preset] ?? 0 { stats.peak[preset] = n }
    }

    /// 帰還・転移の詠唱中ループ。
    func startLoop(id: EntityID, at p: SIMD3<Float>, color: UIColor) {
        guard loops[id] == nil else { return }
        let em = take(.recallLoop)
        _ = fire(em, at: p, color: color, scale: 1, count: nil, direction: nil, life: nil)
        loops[id] = em
        noteActive(.recallLoop)
    }

    func moveLoop(id: EntityID, to p: SIMD3<Float>) {
        loops[id]?.entity.position = p
    }

    func stopLoop(id: EntityID) {
        guard let em = loops.removeValue(forKey: id) else { return }
        if var c = em.entity.components[ParticleEmitterComponent.self] {
            c.isEmitting = false
            em.entity.components.set(c)
        }
        // 残った粒子が消えるまで待ってから回収
        active.append(Active(emitter: em, until: time + 1.0, important: false))
    }

    func hasLoop(_ id: EntityID) -> Bool { loops[id] != nil }

    /// 回収（部品は外さず、エンティティを止めてプールへ戻す）。
    private func release(at k: Int) {
        let em = active[k].emitter
        activeByPreset[em.preset, default: 1] -= 1
        em.entity.isEnabled = false
        free[em.preset, default: []].append(em)
        active.swapAt(k, active.count - 1)
        active.removeLast()
    }

    // MARK: メッシュ演出

    /// 地面で広がる輪。
    func ring(at p: SIMD3<Float>, color: RGB, from r0: Float, to r1: Float, duration: Float, alpha: Float = 0.9) {
        guard meshFX.count < VFXSystem.meshFXCap else { return }
        startRing(at: p, color: color, from: r0, to: r1, duration: duration, alpha: alpha)
    }

    private func startRing(at p: SIMD3<Float>, color: RGB, from r0: Float, to r1: Float, duration: Float, alpha: Float) {
        let e = freeRings.popLast() ?? makeRing()
        // 半透明（深度を書かない）にして、足元のリングを欠けさせない。高さは呼び出し元によらず固定
        e.model?.materials = [materials.unlit(color, alpha: VFXSystem.ringAlpha)]
        e.position = SIMD3(p.x, GroundLayer.vfxRing, p.z)
        e.scale = [r0, 1, r0]
        e.isEnabled = true
        e.components.set(OpacityComponent(opacity: alpha))
        meshFX.append(MeshFX(entity: e, start: time, duration: duration, fromScale: [r0, 1, r0], toScale: [r1, 1, r1],
                             alpha: alpha, kind: 0))
    }

    /// 閃光球（膨らんで消える）。
    func flash(at p: SIMD3<Float>, color: RGB, radius: Float, duration: Float, alpha: Float = 0.55) {
        guard meshFX.count < VFXSystem.meshFXCap else { return }
        startFlash(at: p, color: color, radius: radius, duration: duration, alpha: alpha)
    }

    private func startFlash(at p: SIMD3<Float>, color: RGB, radius: Float, duration: Float, alpha: Float) {
        let e = freeFlashes.popLast() ?? makeFlash()
        e.model?.materials = [materials.unlit(color, alpha: VFXSystem.flashAlpha)]
        e.position = p
        e.scale = SIMD3(repeating: radius * 0.4)
        e.isEnabled = true
        e.components.set(OpacityComponent(opacity: alpha))
        meshFX.append(MeshFX(entity: e, start: time, duration: duration, fromScale: SIMD3(repeating: radius * 0.4),
                             toScale: SIMD3(repeating: radius), alpha: alpha, kind: 1))
    }

    // MARK: ウォームアップ（読み込み幕の裏）

    /// プールの放出体を全て（予算・種類の上限によらず）一度ずつ再生し、輪と閃光も出す。
    /// 各放出体の粒子系の初期化とパイプライン生成を幕の裏で済ませる。center の周りの半径 spread に並べる。
    func fireWarmup(around center: SIMD3<Float>, spread: Float, ringColors: [RGB], flashColors: [RGB]) {
        var n = 0
        for preset in VFXPreset.allCases {
            guard let list = free.removeValue(forKey: preset) else { continue }
            for em in list {
                let a = Float(n) * 2.399963
                let r = spread * (0.25 + 0.75 * Float((n * 37) % 100) / 100)
                n += 1
                let p = center + SIMD3(cos(a) * r, 0.6, sin(a) * r * 0.5)
                let until = fire(em, at: p, color: FXColors.white, scale: 1, count: nil, direction: nil, life: nil)
                active.append(Active(emitter: em, until: time + max(until, 0.5), important: true))
                activeByPreset[preset, default: 0] += 1
            }
        }
        for (k, c) in ringColors.enumerated() {
            let p = center + SIMD3(Float(k % 6) - 2.5, 0, Float(k / 6) * 0.6 - 1)
            startRing(at: p, color: c, from: 0.4, to: 0.8, duration: 1.5, alpha: 0.8)
        }
        for (k, c) in flashColors.enumerated() {
            let p = center + SIMD3(Float(k % 6) - 2.5, 1.2, Float(k / 6) * 0.6 - 1)
            startFlash(at: p, color: c, radius: 0.3, duration: 1.5, alpha: 0.5)
        }
    }

    // MARK: 更新

    func update(dt: Float) {
        time += dt
        var k = 0
        while k < active.count {
            if active[k].until <= time { release(at: k) } else { k += 1 }
        }
        k = 0
        while k < meshFX.count {
            let fx = meshFX[k]
            let t = (time - fx.start) / fx.duration
            if t >= 1 {
                fx.entity.isEnabled = false
                if fx.kind == 0 { freeRings.append(fx.entity) } else { freeFlashes.append(fx.entity) }
                meshFX.swapAt(k, meshFX.count - 1)
                meshFX.removeLast()
                continue
            }
            let e = 1 - (1 - t) * (1 - t)
            fx.entity.scale = fx.fromScale + (fx.toScale - fx.fromScale) * e
            fx.entity.components.set(OpacityComponent(opacity: fx.alpha * (1 - t)))
            k += 1
        }
    }

    /// 全ての再生を止めてプールへ戻す（ウォームアップの終了・破棄）。部品は付けたまま。
    func clear() {
        while !active.isEmpty { release(at: active.count - 1) }
        activeByPreset.removeAll()
        stats = Stats()
        for (_, em) in loops {
            if var c = em.entity.components[ParticleEmitterComponent.self] {
                c.isEmitting = false
                em.entity.components.set(c)
            }
            em.entity.isEnabled = false
            free[em.preset, default: []].append(em)
        }
        loops.removeAll()
        for fx in meshFX {
            fx.entity.isEnabled = false
            if fx.kind == 0 { freeRings.append(fx.entity) } else { freeFlashes.append(fx.entity) }
        }
        meshFX.removeAll()
    }

    /// presentationEpoch の変化（シーク・再同期）: 再生中の粒子・輪・閃光・詠唱ループを全て止めてプールへ戻す
    /// （前の時刻の演出を残さない）。計測（stats）は試合を通した値なので残す。詠唱中のループは呼び出し側が今の状態から付け直す。
    func resetForPresentationEpoch() {
        let kept = stats
        clear()
        stats = kept
    }

    /// 詠唱ループの数（テスト用）。
    var loopCount: Int { loops.count }

    // MARK: プリセット

    /// preset の設定を部品へ書き込む（新規の部品にも、同じ種類で使い回す部品にも同じ値になる: 種類ごとに書く項目が
    /// 決まっているため、前回の値は全て上書きされる）。戻り値は回収までの秒数。
    @discardableResult
    private func configure(_ p: inout ParticleEmitterComponent, _ preset: VFXPreset, color: UIColor, scale s: Float,
                           count: Int?, life lifeOverride: Double? = nil) -> Float {
        p.fieldSimulationSpace = .global
        p.birthLocation = .volume
        p.birthDirection = .normal
        p.emitterShape = .sphere
        p.emitterShapeSize = SIMD3(repeating: 0.1 * s)
        p.speedVariation = 0.5
        var m = p.mainEmitter
        m.image = dotTexture
        m.blendMode = .additive
        m.opacityCurve = .quickFadeInOut
        m.billboardMode = .billboard
        m.color = .constant(.single(color))
        m.sizeMultiplierAtEndOfLifespan = 0.3
        m.isLightingEnabled = false
        m.lifeSpanVariation = 0.1
        m.sizeVariation = 0.02
        var emitDuration: Double = 0.06
        var n: Int
        var life: Double
        switch preset {
        case .hitSpark:
            n = 9; life = 0.28
            p.speed = 3.2 * s
            m.size = 0.07 * s
            m.stretchFactor = 1.2
            m.acceleration = [0, -7, 0]
            m.dampingFactor = 2.5
        case .crit:
            n = 20; life = 0.4
            p.speed = 4.6 * s
            m.size = 0.1 * s
            m.stretchFactor = 1.4
            m.image = starTexture
            m.acceleration = [0, -5, 0]
            m.dampingFactor = 2
            m.color = .evolving(start: .single(UIColor(red: 1, green: 0.95, blue: 0.6, alpha: 1)), end: .single(color))
        case .magicHit:
            n = 14; life = 0.45
            p.speed = 2.2 * s
            m.size = 0.13 * s
            m.image = starTexture
            m.dampingFactor = 3
            m.angularSpeed = 3
            m.color = .evolving(start: .single(.white), end: .single(color))
        case .heal:
            n = 16; life = 0.9
            p.emitterShape = .cylinder
            p.emitterShapeSize = [0.55 * s, 0.1, 0.55 * s]
            p.birthDirection = .world
            p.emissionDirection = [0, 1, 0]
            p.speed = 1.1
            m.size = 0.12 * s
            m.image = starTexture
            m.opacityCurve = .gradualFadeInOut
            emitDuration = 0.3
        case .shield:
            n = 18; life = 0.55
            p.birthLocation = .surface
            p.emitterShapeSize = SIMD3(repeating: 0.8 * s)
            p.speed = 0.5
            m.size = 0.09 * s
            m.image = starTexture
            m.opacityCurve = .gradualFadeInOut
        case .levelUp:
            n = 44; life = 1.0
            p.emitterShape = .cylinder
            p.birthLocation = .surface
            p.emitterShapeSize = [0.7, 0.05, 0.7]
            p.birthDirection = .world
            p.emissionDirection = [0, 1, 0]
            p.speed = 3.4
            p.speedVariation = 1.4
            m.size = 0.1
            m.image = starTexture
            m.stretchFactor = 0.6
            m.dampingFactor = 1.2
            emitDuration = 0.25
        case .death:
            // 消滅の光粒（上へ昇って消える）
            n = 14; life = 0.7
            p.speed = 1.6 * s
            m.size = 0.1 * s
            m.image = starTexture
            m.opacityCurve = .linearFadeOut
            m.acceleration = [0, 2.4, 0]
            m.dampingFactor = 3
            m.sizeMultiplierAtEndOfLifespan = 0.2
        case .heroDeath:
            n = 36; life = 1.1
            p.speed = 2.6
            m.size = 0.18
            m.image = starTexture
            m.acceleration = [0, 1.5, 0]
            m.dampingFactor = 2.4
            m.color = .evolving(start: .single(color), end: .single(UIColor(white: 0.2, alpha: 1)))
        case .respawn:
            n = 40; life = 1.1
            p.emitterShape = .cylinder
            p.emitterShapeSize = [0.6, 0.05, 0.6]
            p.birthDirection = .world
            p.emissionDirection = [0, 1, 0]
            p.speed = 4
            p.speedVariation = 1.5
            m.size = 0.12
            m.image = starTexture
            m.stretchFactor = 0.8
            m.dampingFactor = 1.4
            emitDuration = 0.35
        case .towerExplosion:
            n = 70; life = 1.4
            p.emitterShapeSize = SIMD3(repeating: 1.2)
            p.speed = 6
            p.speedVariation = 3
            m.size = 0.32
            m.acceleration = [0, -6, 0]
            m.dampingFactor = 1.5
            m.sizeMultiplierAtEndOfLifespan = 0.1
            m.color = .evolving(start: .single(UIColor(red: 1, green: 0.9, blue: 0.6, alpha: 1)), end: .single(color))
        case .debris:
            n = 26; life = 1.3
            p.emitterShapeSize = SIMD3(repeating: 0.8 * s)
            p.birthDirection = .world
            p.emissionDirection = [0, 1, 0]
            p.speed = 5.5 * s
            p.speedVariation = 2.5
            m.spreadingAngle = 1.1
            m.size = 0.16 * s
            m.sizeVariation = 0.08
            m.blendMode = .alpha
            m.opacityCurve = .linearFadeOut
            m.acceleration = [0, -14, 0]
            m.angularSpeed = 5
            m.sizeMultiplierAtEndOfLifespan = 0.8
            // 粒子色は線形空間で扱われるため暗めに指定する
            m.color = .constant(.random(a: UIColor(red: 0.13, green: 0.12, blue: 0.12, alpha: 1),
                                        b: UIColor(red: 0.26, green: 0.22, blue: 0.19, alpha: 1)))
        case .smoke:
            n = 10; life = 1.6
            p.emitterShapeSize = SIMD3(repeating: 1.2 * s)
            p.birthDirection = .world
            p.emissionDirection = [0, 1, 0]
            p.speed = 0.9
            m.size = 0.55 * s
            m.sizeVariation = 0.2
            m.blendMode = .alpha
            m.opacityCurve = .gradualFadeInOut
            m.sizeMultiplierAtEndOfLifespan = 2.2
            m.dampingFactor = 1
            m.color = .constant(.single(UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 0.6)))
            emitDuration = 0.2
        case .gold:
            n = 12; life = 0.8
            p.birthDirection = .world
            p.emissionDirection = [0, 1, 0]
            p.speed = 3.5
            p.speedVariation = 1
            m.size = 0.11
            m.image = starTexture
            m.acceleration = [0, -9, 0]
            m.color = .constant(.single(UIColor(red: 1, green: 0.84, blue: 0.3, alpha: 1)))
            m.blendMode = .alpha
        case .skillBurst:
            n = 26; life = 0.55
            p.emitterShapeSize = SIMD3(repeating: 0.3 * s)
            p.speed = 3.6 * s
            m.size = 0.14 * s
            m.image = starTexture
            m.dampingFactor = 3.2
            m.color = .evolving(start: .single(.white), end: .single(color))
        case .blink:
            n = 22; life = 0.5
            p.emitterShape = .cylinder
            p.emitterShapeSize = [0.5, 0.9, 0.5]
            p.speed = 1.4
            m.size = 0.12
            m.image = starTexture
            m.dampingFactor = 2
            m.color = .evolving(start: .single(.white), end: .single(color))
        case .areaBlast:
            n = 34; life = 0.55
            p.emitterShape = .torus
            p.emitterShapeSize = SIMD3(repeating: max(0.5, s))
            p.torusInnerRadius = 0.08
            p.birthDirection = .world
            p.emissionDirection = [0, 1, 0]
            p.speed = 2.4
            m.size = 0.15
            m.image = starTexture
            m.dampingFactor = 2.5
            m.color = .evolving(start: .single(.white), end: .single(color))
        case .trail:
            n = 30; life = 0.5
            p.emitterShape = .box
            p.emitterShapeSize = [0.25, max(0.3, s), 0.25]
            p.speed = 0.4
            m.size = 0.14
            m.image = starTexture
            m.opacityCurve = .linearFadeOut
            m.color = .evolving(start: .single(.white), end: .single(color))
            emitDuration = 0.12
        case .recallLoop:
            n = 0; life = 0.95
            p.emitterShape = .cylinder
            p.birthLocation = .surface
            p.emitterShapeSize = [0.85, 0.05, 0.85]
            p.birthDirection = .world
            p.emissionDirection = [0, 1, 0]
            p.speed = 1.7
            m.size = 0.1
            m.image = starTexture
            m.opacityCurve = .gradualFadeInOut
            m.birthRate = Float(quality.particles(34))
            m.lifeSpan = life
            p.mainEmitter = m
            p.timing = .repeating(warmUp: nil, emit: .init(duration: 1), idle: nil)
            p.isEmitting = true
            return Float(life)
        }
        let total = quality.particles(count ?? n)
        if let lifeOverride { life = max(0.25, min(2.0, lifeOverride)) }
        m.lifeSpan = life
        m.birthRate = Float(Double(total) / emitDuration)
        p.mainEmitter = m
        p.timing = .once(warmUp: nil, emit: .init(duration: emitDuration))
        p.isEmitting = true
        return Float(life + emitDuration) + 0.25
    }

    private static func makeTexture(size: Int, name: String, draw: (CGContext, CGFloat) -> Void) -> TextureResource? {
        AssetLedger.record(.texture, name)
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(ctx, CGFloat(size))
        guard let img = ctx.makeImage() else { return nil }
        return try? TextureResource(image: img, options: .init(semantic: .color))
    }
}
