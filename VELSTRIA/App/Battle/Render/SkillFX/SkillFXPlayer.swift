import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer（スキル演出）。FXCue の再生器。
// - 粒子: 汎用の放出体のプール（部品は付けたまま、再生のたびに FXEmit の全項目を書き戻して restart / burst）。
// - メッシュ: 形ごとのエンティティのプール（材質は FXMaterialLibrary のキャッシュを差し替えるだけ）。
// - 遅れ・繰り返しは予定表で順に発火し、追従（術者・被弾者・投射物）は毎フレーム位置を読み直す。
// プレイ中は何も作らない: 画像・メッシュ・材質・放出体は prewarm（読み込み幕の裏）で作り切る。プールが尽きたら
// 最も古いものを打ち切って使い回す（追従の継続放出は打ち切らない）。

@MainActor
final class SkillFXPlayer {
    let root = Entity()
    let textures = FXTextureLibrary()
    let meshes = FXMeshLibrary()
    let materials: FXMaterialLibrary
    private var quality: RenderQuality
    let poolQuality: RenderQuality

    /// 追従の主体。
    enum Follow: Hashable {
        case unit(EntityID)
        case projectile(EntityID)
    }

    /// 1 回の再生の文脈（world 座標）。
    struct Context {
        var palette: FXPalette
        /// 段の原点。
        var origin: SIMD3<Float>
        /// 術者の位置（along の起点）。
        var caster: SIMD3<Float>
        /// 照準点。
        var target: SIMD3<Float>
        /// 前方（xz の単位ベクトル）。
        var forward: SIMD3<Float>
        var follow: Follow?
        /// 同じ段の何回目か（連撃の 2 撃目など。向きの左右を変えるのに使う）。
        var variant = 0
    }

    /// 追従の主体の位置（BattleWorld が設定）。nil = 消えた。
    var resolve: (Follow) -> SIMD3<Float>? = { _ in nil }
    /// 画面の揺れの要求（強さ・位置）。
    var onShake: (Float, SIMD3<Float>) -> Void = { _, _ in }

    // MARK: プール

    @MainActor
    final class Emitter {
        let entity = Entity()
    }

    private struct EmitInst {
        var emitter: Emitter
        var until: Float
        var follow: Follow?
        var offset: SIMD3<Float>
        var yaw: Float
        var looping: Bool
        var stopAt: Float
        var start: Float = 0
        /// 追従の主体を一度でも見つけたか（投射物は発射の次のフレームに現れる）。
        var seen = false
    }

    private struct MeshInst {
        var entity: ModelEntity
        var shape: FXShape
        var spec: FXMesh
        var start: Float
        var base: SIMD3<Float>
        var yaw: Float
        var follow: Follow?
        var offset: SIMD3<Float>
        var ground: Bool
    }

    private struct Pending {
        var time: Float
        var cue: FXCue
        var ctx: Context
        var index: Int
    }

    private var freeEmitters: [Emitter] = []
    private var emitterCount = 0
    private var emits: [EmitInst] = []
    private var freeMeshes: [FXShape: [ModelEntity]] = [:]
    private var meshInsts: [MeshInst] = []
    private var pending: [Pending] = []
    private var time: Float = 0
    private var prewarmed = false
    private lazy var blank: ParticleEmitterComponent = {
        AssetLedger.record(.emitter, "skillfx blank")
        return ParticleEmitterComponent()
    }()

    struct Stats {
        var plays = 0
        var stolenEmitters = 0
        var stolenMeshes = 0
        var peakEmitters = 0
        var peakMeshes = 0
        var droppedCues = 0
        var peakPending = 0
    }
    private(set) var stats = Stats()

    init(quality: RenderQuality) {
        self.quality = quality
        poolQuality = quality
        materials = FXMaterialLibrary(textures: textures)
        root.name = "skillfx"
        emits.reserveCapacity(64)
        meshInsts.reserveCapacity(128)
        pending.reserveCapacity(BattleWorkBudget.pendingCues)
    }

    func apply(quality q: RenderQuality) { quality = q }

    var pendingCount: Int { pending.count }

    var activeCount: Int { emits.count + meshInsts.count }

    /// 放出体のプールの大きさ（粒子系 1 つ ≒ 1 MB を常に持つので画質で決める）。
    static func emitterCapacity(_ q: RenderQuality) -> Int {
        switch q.level {
        case .low: return 10
        case .medium: return 22
        case .high: return 34
        }
    }

    /// 形ごとのメッシュのプールの大きさ。
    static func meshCapacity(_ s: FXShape, _ q: RenderQuality) -> Int {
        let base: Int
        switch s {
        case .disc: base = 28
        case .arc: base = 12
        case .billboard: base = 12
        case .cylinder, .sphere: base = 10
        case .wall, .band: base = 8
        case .dome, .spire, .funnel: base = 5
        }
        return q.level == .low ? max(2, base / 2) : base
    }

    static func qualityRank(_ q: RenderQuality) -> Int {
        switch q.level {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    // MARK: 事前生成（読み込み幕の裏）

    /// 試合のヒーローのレシピが使う画像・材質と、全てのプールを作る。
    func prewarm(recipes: [(palette: FXPalette, recipe: SkillFXRecipe)]) {
        textures.prewarm(FXTex.allCases)
        meshes.prewarm()
        _ = blank
        for (palette, r) in recipes {
            for cue in r.all {
                if case .mesh(let m) = cue.element { _ = materials.material(m.tex, palette.rgb(m.tint)) }
            }
        }
        let n = SkillFXPlayer.emitterCapacity(poolQuality)
        while emitterCount < n { freeEmitters.append(makeEmitter()) }
        for s in FXShape.allCases {
            var list = freeMeshes[s] ?? []
            while list.count < SkillFXPlayer.meshCapacity(s, poolQuality) { list.append(makeMesh(s)) }
            freeMeshes[s] = list
        }
        prewarmed = true
    }

    private func makeEmitter() -> Emitter {
        AssetLedger.record(.entity, "skillfx emitter")
        AssetLedger.record(.emitter, "skillfx")
        emitterCount += 1
        let em = Emitter()
        var c = ParticleEmitterComponent()
        configure(&c, FXEmit(), palette: .from(RGB(1, 1, 1)))
        c.isEmitting = false
        em.entity.components.set(c)
        em.entity.isEnabled = false
        root.addChild(em.entity)
        return em
    }

    private func makeMesh(_ s: FXShape) -> ModelEntity {
        AssetLedger.record(.entity, "skillfx \(s.rawValue)")
        let m = ModelEntity(mesh: meshes.mesh(s) ?? MeshResource.generateBox(size: 0.01), materials: [])
        if s == .billboard { m.components.set(BillboardComponent()) }
        m.components.set(DynamicLightShadowComponent(castsShadow: false))
        m.isEnabled = false
        root.addChild(m)
        return m
    }

    // MARK: 再生

    /// 段の合図を全て予定に入れる（遅れ 0 のものはこの場で発火）。
    func play(_ cues: [FXCue], _ ctx: Context) {
        guard !cues.isEmpty else { return }
        stats.plays += 1
        let rank = SkillFXPlayer.qualityRank(quality)
        stats.droppedCues += max(0, cues.count - BattleWorkBudget.cuesPerPlay)
        var remaining = BattleWorkBudget.cuesPerPlay
        for cue in cues.prefix(BattleWorkBudget.cuesPerPlay) where cue.minQuality <= rank {
            guard remaining > 0 else { stats.droppedCues += 1; break }
            let requested = max(1, cue.count)
            let admitted = min(requested, remaining)
            stats.droppedCues += requested - admitted
            remaining -= admitted
            for k in 0..<admitted {
                let t = cue.at + cue.every * Float(k)
                if t <= 0.0001 {
                    fire(cue, ctx, index: k)
                } else if pending.count < BattleWorkBudget.pendingCues {
                    pending.append(Pending(time: time + t, cue: cue, ctx: ctx, index: k))
                    stats.peakPending = max(stats.peakPending, pending.count)
                } else {
                    stats.droppedCues += 1
                }
            }
        }
    }

    /// 追従の継続放出を止める（投射物の着弾・消滅、術者の死亡）。メッシュの追従は最後の位置に残す。
    func stop(follow f: Follow) {
        for k in emits.indices where emits[k].follow == f && emits[k].looping {
            stopEmitting(k)
        }
        for k in meshInsts.indices where meshInsts[k].follow == f {
            meshInsts[k].follow = nil
        }
        pending.removeAll { $0.ctx.follow == f && $0.cue.anchor == .follow }
    }

    private func stopEmitting(_ k: Int) {
        let e = emits[k]
        if var c = e.emitter.entity.components[ParticleEmitterComponent.self] {
            c.isEmitting = false
            e.emitter.entity.components.set(c)
        }
        emits[k].looping = false
        emits[k].until = min(e.until, time + 0.8)
    }

    // MARK: 発火

    /// 局所の向き（前方の yaw + 加算の度）。
    private static func yaw(of forward: SIMD3<Float>) -> Float { atan2(-forward.x, -forward.z) }

    private static func rotate(_ v: SIMD3<Float>, yaw: Float) -> SIMD3<Float> {
        // 局所（右・上・前）→ world。前 = -Z を yaw だけ回す
        let c = cos(yaw), s = sin(yaw)
        let local = SIMD3<Float>(v.x, v.y, -v.z)
        return SIMD3(local.x * c + local.z * s, local.y, -local.x * s + local.z * c)
    }

    private func anchorPosition(_ a: FXAnchor, _ ctx: Context) -> SIMD3<Float> {
        switch a {
        case .origin: return ctx.origin
        case .follow: return ctx.follow.flatMap { resolve($0) } ?? ctx.origin
        case .target: return ctx.target
        case .along(let t): return ctx.caster + (ctx.target - ctx.caster) * t
        }
    }

    private func fire(_ cue: FXCue, _ ctx: Context, index k: Int) {
        let baseYaw = SkillFXPlayer.yaw(of: ctx.forward)
        let stepYaw = cue.stepYaw * Float(k) * .pi / 180
        // 位置: 輪状の配置（orbit）は向きと一緒に回す
        var local = cue.offset + cue.stepOffset * Float(k)
        if cue.orbit != 0 {
            let r = SkillFXPlayer.rotate(local, yaw: stepYaw)
            local = SIMD3(r.x, r.y, -r.z)
        }
        let yaw = baseYaw + stepYaw
        let anchor = anchorPosition(cue.anchor, ctx)
        let worldOffset = SkillFXPlayer.rotate(local, yaw: baseYaw)
        let follow: Follow? = cue.anchor == .follow ? ctx.follow : nil
        switch cue.element {
        case .shake(let s):
            onShake(s, anchor)
        case .emit(let e):
            spawnEmit(e, at: anchor + worldOffset, yaw: yaw, follow: follow, offset: worldOffset, ctx: ctx)
        case .mesh(var m):
            // 連撃の偶数回は左右反転（掃く向きを交互に）
            if ctx.variant % 2 == 1 {
                m.yaw = -m.yaw
                m.yawEnd = m.yawEnd.map { -$0 }
                m.roll = -m.roll
            }
            spawnMesh(m, at: anchor + worldOffset, yaw: yaw, follow: follow, offset: worldOffset, ctx: ctx,
                      groundLevel: local.y < 0.05 && anchor.y < 0.3)
        }
    }

    private func spawnEmit(_ e: FXEmit, at p: SIMD3<Float>, yaw: Float, follow: Follow?, offset: SIMD3<Float>, ctx: Context) {
        let em: Emitter
        if let free = freeEmitters.popLast() {
            em = free
        } else if prewarmed {
            // 最も早く終わる一斉放出を打ち切る（継続放出は残す）
            guard let k = emits.indices.filter({ !emits[$0].looping }).min(by: { emits[$0].until < emits[$1].until }) else { return }
            em = emits[k].emitter
            emits.swapAt(k, emits.count - 1)
            emits.removeLast()
            stats.stolenEmitters += 1
        } else {
            em = makeEmitter()
        }
        var c = em.entity.components[ParticleEmitterComponent.self] ?? blank
        configure(&c, e, palette: ctx.palette)
        em.entity.position = p
        em.entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        if e.rate > 0 {
            c.isEmitting = true
            c.restart()
        } else {
            c.isEmitting = false
            c.restart()
            c.burst()
        }
        em.entity.components.set(c)
        em.entity.isEnabled = true
        let looping = e.rate > 0
        let span = e.span
        emits.append(EmitInst(emitter: em, until: span.isFinite ? time + span : .infinity, follow: follow, offset: offset,
                              yaw: yaw, looping: looping && e.duration <= 0,
                              stopAt: looping && e.duration > 0 ? time + e.duration : .infinity, start: time))
        stats.peakEmitters = max(stats.peakEmitters, emits.count)
    }

    private func spawnMesh(_ m: FXMesh, at p: SIMD3<Float>, yaw: Float, follow: Follow?, offset: SIMD3<Float>, ctx: Context,
                           groundLevel: Bool) {
        let e: ModelEntity
        if let free = freeMeshes[m.shape]?.popLast() {
            e = free
        } else if prewarmed {
            guard let k = meshInsts.indices.filter({ meshInsts[$0].shape == m.shape })
                .min(by: { meshInsts[$0].start < meshInsts[$1].start }) else { return }
            e = meshInsts[k].entity
            meshInsts.swapAt(k, meshInsts.count - 1)
            meshInsts.removeLast()
            stats.stolenMeshes += 1
        } else {
            e = makeMesh(m.shape)
        }
        e.model?.materials = [materials.material(m.tex, ctx.palette.rgb(m.tint))]
        let ground = groundLevel && (m.shape == .disc || m.shape == .arc || m.shape == .band)
        if ground {
            OverlayOrder.apply(e, OverlayOrder.skillDecal)
        } else {
            e.components.remove(ModelSortGroupComponent.self)
        }
        var base = p
        if ground { base.y = GroundLayer.skillDecal }
        let inst = MeshInst(entity: e, shape: m.shape, spec: m, start: time, base: base, yaw: yaw, follow: follow,
                            offset: offset, ground: ground)
        meshInsts.append(inst)
        apply(inst, t: 0)
        e.isEnabled = true
        stats.peakMeshes = max(stats.peakMeshes, meshInsts.count)
    }

    // MARK: 更新

    func update(dt: Float) {
        time += dt
        // 予定の発火
        if !pending.isEmpty {
            var k = 0
            while k < pending.count {
                if pending[k].time <= time {
                    let p = pending[k]
                    pending.swapAt(k, pending.count - 1)
                    pending.removeLast()
                    fire(p.cue, p.ctx, index: p.index)
                } else {
                    k += 1
                }
            }
        }
        // 粒子
        var k = 0
        while k < emits.count {
            var e = emits[k]
            if let f = e.follow {
                if let p = resolve(f) {
                    e.emitter.entity.position = p + e.offset
                    emits[k].seen = true
                } else if e.looping && (e.seen || time - e.start > 0.3) {
                    stopEmitting(k)
                    e = emits[k]
                    emits[k].follow = nil
                }
            }
            if e.stopAt <= time && e.stopAt.isFinite {
                stopEmitting(k)
                emits[k].stopAt = .infinity
            }
            if emits[k].until <= time {
                release(emitAt: k)
                continue
            }
            k += 1
        }
        // メッシュ
        k = 0
        while k < meshInsts.count {
            let inst = meshInsts[k]
            let t = (time - inst.start) / max(0.01, inst.spec.life)
            if t >= 1 {
                inst.entity.isEnabled = false
                freeMeshes[inst.shape, default: []].append(inst.entity)
                meshInsts.swapAt(k, meshInsts.count - 1)
                meshInsts.removeLast()
                continue
            }
            if let f = inst.follow, let p = resolve(f) {
                var b = p + inst.offset
                if inst.ground { b.y = GroundLayer.skillDecal }
                meshInsts[k].base = b
            }
            apply(meshInsts[k], t: t)
            k += 1
        }
    }

    private func apply(_ inst: MeshInst, t: Float) {
        let m = inst.spec
        let e = m.ease.apply(t)
        let age = t * m.life
        let size = m.size + (m.sizeEnd - m.size) * e
        var yawDeg = m.yaw
        if let end = m.yawEnd { yawDeg = m.yaw + (end - m.yaw) * e }
        yawDeg += m.spin * age
        let yaw = inst.yaw + yawDeg * .pi / 180
        var q = simd_quatf(angle: yaw, axis: [0, 1, 0])
        if m.pitch != 0 { q = q * simd_quatf(angle: -m.pitch * .pi / 180, axis: [1, 0, 0]) }
        if m.roll != 0 { q = q * simd_quatf(angle: m.roll * .pi / 180, axis: [0, 0, 1]) }
        var p = inst.base
        p.y += m.rise * age
        if m.advance != 0 { p += SkillFXPlayer.rotate([0, 0, m.advance * age], yaw: inst.yaw) }
        inst.entity.position = p
        if m.shape != .billboard { inst.entity.orientation = q }
        inst.entity.scale = size
        // 不透明度: fadeIn まで立ち上がり、fadeOut から 0 へ
        var a: Float = 1
        if t < m.fadeIn { a = t / max(0.001, m.fadeIn) }
        if t > m.fadeOut { a = min(a, 1 - (t - m.fadeOut) / max(0.001, 1 - m.fadeOut)) }
        inst.entity.components.set(OpacityComponent(opacity: max(0, min(1, a * m.alpha))))
    }

    private func release(emitAt k: Int) {
        let e = emits[k]
        e.emitter.entity.isEnabled = false
        freeEmitters.append(e.emitter)
        emits.swapAt(k, emits.count - 1)
        emits.removeLast()
    }

    /// 全て止めてプールへ戻す。
    func clear() {
        pending.removeAll(keepingCapacity: true)
        while !emits.isEmpty {
            if var c = emits[emits.count - 1].emitter.entity.components[ParticleEmitterComponent.self] {
                c.isEmitting = false
                emits[emits.count - 1].emitter.entity.components.set(c)
            }
            release(emitAt: emits.count - 1)
        }
        for inst in meshInsts {
            inst.entity.isEnabled = false
            freeMeshes[inst.shape, default: []].append(inst.entity)
        }
        meshInsts.removeAll()
        stats = Stats()
    }

    // MARK: ウォームアップ（読み込み幕の裏）

    /// 全ての形のプールを一度描き、全ての放出体を画像を替えながら一度ずつ動かす。
    func fireWarmup(around center: SIMD3<Float>, spread: Float) {
        let mats = materials.built
        var n = 0
        func slot() -> SIMD3<Float> {
            let a = Float(n) * 2.399963
            let r = spread * (0.2 + 0.8 * Float((n * 37) % 100) / 100)
            n += 1
            return center + SIMD3(cos(a) * r, 0.8, sin(a) * r * 0.5)
        }
        for s in FXShape.allCases {
            guard var list = freeMeshes[s] else { continue }
            for e in list {
                e.model?.materials = mats.isEmpty ? [] : [mats[n % mats.count]]
                e.position = slot()
                e.scale = SIMD3(repeating: 0.3)
                e.components.set(OpacityComponent(opacity: 0.5))
                e.isEnabled = true
                meshInsts.append(MeshInst(entity: e, shape: s, spec: FXMesh(shape: s, life: 0.6), start: time,
                                          base: e.position, yaw: 0, follow: nil, offset: .zero, ground: false))
            }
            list.removeAll()
            freeMeshes[s] = list
        }
        // 材質の全ては陳列の棚（BattleWorld.openGalleryShelf）で一度ずつ描く
        let palette = FXPalette.from(RGB(1, 1, 1))
        var texIndex = 0
        while let em = freeEmitters.popLast() {
            let tex = FXTex.allCases[texIndex % FXTex.allCases.count]
            texIndex += 1
            var c = em.entity.components[ParticleEmitterComponent.self] ?? blank
            configure(&c, FXEmit(tex: tex, count: 4, life: 0.4, size: 0.2, speed: 1), palette: palette)
            c.isEmitting = false
            c.restart()
            c.burst()
            em.entity.components.set(c)
            em.entity.position = slot()
            em.entity.isEnabled = true
            emits.append(EmitInst(emitter: em, until: time + 0.8, follow: nil, offset: .zero, yaw: 0, looping: false,
                                  stopAt: .infinity))
        }
    }

    // MARK: 粒子の設定

    /// FXEmit の全項目を部品へ書く（使い回す部品の前回の値を全て上書きする）。
    private func configure(_ p: inout ParticleEmitterComponent, _ e: FXEmit, palette: FXPalette) {
        p.fieldSimulationSpace = .global
        p.particlesInheritTransform = false
        p.spawnedEmitter = nil
        p.speed = e.speed
        p.speedVariation = e.speed * e.speedVar
        p.radialAmount = 0
        p.torusInnerRadius = 0.05
        p.birthLocation = e.surface ? .surface : .volume
        switch e.shape {
        case .point:
            p.emitterShape = .point
            p.emitterShapeSize = SIMD3(repeating: 0.01)
        case .sphere(let r):
            p.emitterShape = .sphere
            p.emitterShapeSize = SIMD3(repeating: max(0.01, r))
        case .disc(let r):
            p.emitterShape = .cylinder
            p.emitterShapeSize = [max(0.01, r), 0.02, max(0.01, r)]
        case .ring(let r):
            p.emitterShape = .torus
            p.emitterShapeSize = SIMD3(repeating: max(0.05, r))
            p.torusInnerRadius = min(0.08, r * 0.2)
        case .box(let b):
            p.emitterShape = .box
            p.emitterShapeSize = SIMD3(max(0.01, b.x), max(0.01, b.y), max(0.01, b.z))
        case .line(let len):
            p.emitterShape = .box
            p.emitterShapeSize = [0.05, 0.05, max(0.05, len)]
        }
        switch e.dir {
        case .outward:
            p.birthDirection = .normal
            p.emissionDirection = [0, 1, 0]
        case .up:
            p.birthDirection = .world
            p.emissionDirection = [0, 1, 0]
        case .down:
            p.birthDirection = .world
            p.emissionDirection = [0, -1, 0]
        case .forward:
            p.birthDirection = .local
            p.emissionDirection = [0, 0, -1]
        case .backward:
            p.birthDirection = .local
            p.emissionDirection = [0, 0, 1]
        case .local(let v):
            p.birthDirection = .local
            let n = simd_length(v) > 1e-4 ? simd_normalize(v) : SIMD3<Float>(0, 1, 0)
            p.emissionDirection = [n.x, n.y, -n.z]
        }
        var m = p.mainEmitter
        m.image = e.additive ? textures.glowTexture(e.tex) : textures.texture(e.tex)
        m.imageSequence = nil
        m.blendMode = e.additive ? .additive : .alpha
        m.isLightingEnabled = false
        m.opacityCurve = e.fade
        switch e.orient {
        case .billboard: m.billboardMode = .billboard
        case .upright: m.billboardMode = .billboardYAligned
        case .ground: m.billboardMode = .free(axis: [0, 1, 0], variation: 0)
        case .facing: m.billboardMode = .free(axis: [0, 0, 1], variation: 0)
        }
        let start = palette.rgb(e.tint).uiColor(alpha: 1)
        if let end = e.tintEnd {
            m.color = .evolving(start: .single(start), end: .single(palette.rgb(end).uiColor(alpha: 1)))
        } else {
            m.color = .constant(.single(start))
        }
        m.colorEvolutionPower = 1
        m.size = e.size
        m.sizeVariation = e.size * e.sizeVar
        m.sizeMultiplierAtEndOfLifespan = e.grow
        m.sizeMultiplierAtEndOfLifespanPower = 1
        m.lifeSpan = Double(e.life)
        m.lifeSpanVariation = Double(e.life * e.lifeVar)
        m.spreadingAngle = e.spread * .pi / 180
        m.acceleration = [0, -e.gravity, 0]
        m.dampingFactor = e.drag
        m.angle = e.angle * .pi / 180
        m.angleVariation = e.angleVar * .pi / 180
        m.angularSpeed = e.spin * .pi / 180
        m.angularSpeedVariation = e.spinVar * .pi / 180
        m.stretchFactor = e.stretch
        m.noiseStrength = e.noise
        m.noiseScale = 1
        m.noiseAnimationSpeed = 1
        m.vortexStrength = e.vortex
        m.vortexDirection = [0, 1, 0]
        m.attractionStrength = e.attract
        m.attractionCenter = .zero
        m.mass = 1
        m.massVariation = 0
        if e.rate > 0 {
            m.birthRate = e.rate * quality.particleScale
            m.birthRateVariation = 0
            p.burstCount = 0
            p.burstCountVariation = 0
            p.timing = .repeating(warmUp: nil, emit: .init(duration: 1), idle: nil)
        } else if e.emit > 0.001 {
            let n = quality.particles(e.count)
            m.birthRate = Float(n) / e.emit
            m.birthRateVariation = 0
            p.burstCount = 0
            p.burstCountVariation = 0
            p.timing = .once(warmUp: nil, emit: .init(duration: Double(e.emit)))
        } else {
            m.birthRate = 0
            m.birthRateVariation = 0
            // 1 枚もの（閃光・衝撃波）は画質で減らさない
            p.burstCount = e.count <= 2 ? e.count : quality.particles(e.count)
            p.burstCountVariation = 0
            p.timing = .once(warmUp: nil, emit: .init(duration: 0.05))
        }
        p.mainEmitter = m
    }
}
