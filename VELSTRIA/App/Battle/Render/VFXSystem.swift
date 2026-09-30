import CoreGraphics
import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。パーティクル（ParticleEmitterComponent）のプリセットとプール、
// 安価なメッシュ演出（広がる輪・閃光球）。同時放出体の数と粒子数は画質設定で制限する。

enum VFXPreset: Equatable {
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
    private let materials: RenderMaterials
    private let meshes: UnitMeshLibrary

    private struct Active {
        var entity: Entity
        var until: Float
        var important: Bool
    }

    private var freeEmitters: [Entity] = []
    private var active: [Active] = []
    private var loops: [EntityID: Entity] = [:]
    private var time: Float = 0

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

    private var freeRings: [ModelEntity] = []
    private var freeFlashes: [ModelEntity] = []
    private var meshFX: [MeshFX] = []

    private(set) lazy var dotTexture: TextureResource? = VFXSystem.makeTexture(size: 64) { ctx, s in
        let colors = [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)]
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
                                   endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s / 2, options: [])
        }
    }

    private(set) lazy var starTexture: TextureResource? = VFXSystem.makeTexture(size: 64) { ctx, s in
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
        self.materials = materials
        self.meshes = meshes
        root.name = "vfx"
        active.reserveCapacity(64)
        meshFX.reserveCapacity(48)
        for _ in 0..<min(12, quality.maxEmitters) {
            let e = Entity()
            e.isEnabled = false
            root.addChild(e)
            freeEmitters.append(e)
        }
    }

    func apply(quality q: RenderQuality) { quality = q }

    var activeCount: Int { active.count + loops.count + meshFX.count }

    // MARK: パーティクル

    /// important = false の演出は予算超過時に省略する。life = 粒子の寿命の上書き（EffectDef.durationSec）。
    func spawn(_ preset: VFXPreset, at p: SIMD3<Float>, color: UIColor, scale: Float = 1, count: Int? = nil,
               important: Bool = false, direction: SIMD3<Float>? = nil, life: Double? = nil) {
        if active.count >= quality.maxEmitters {
            guard important, let k = active.firstIndex(where: { !$0.important }) else { return }
            release(at: k)
        }
        guard let (component, life) = makeEmitter(preset, color: color, scale: scale, count: count, life: life) else { return }
        let e = freeEmitters.popLast() ?? {
            let n = Entity()
            root.addChild(n)
            return n
        }()
        e.position = p
        if let d = direction, simd_length(d) > 1e-4 {
            e.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(d))
        } else {
            e.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        }
        e.components.set(component)
        e.isEnabled = true
        active.append(Active(entity: e, until: time + life, important: important))
    }

    /// 帰還・転移の詠唱中ループ。
    func startLoop(id: EntityID, at p: SIMD3<Float>, color: UIColor) {
        guard loops[id] == nil, let (c, _) = makeEmitter(.recallLoop, color: color, scale: 1, count: nil) else { return }
        let e = freeEmitters.popLast() ?? {
            let n = Entity()
            root.addChild(n)
            return n
        }()
        e.position = p
        e.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        e.components.set(c)
        e.isEnabled = true
        loops[id] = e
    }

    func moveLoop(id: EntityID, to p: SIMD3<Float>) {
        loops[id]?.position = p
    }

    func stopLoop(id: EntityID) {
        guard let e = loops.removeValue(forKey: id) else { return }
        if var c = e.components[ParticleEmitterComponent.self] {
            c.isEmitting = false
            e.components.set(c)
        }
        // 残った粒子が消えるまで待ってから回収
        active.append(Active(entity: e, until: time + 1.0, important: false))
    }

    func hasLoop(_ id: EntityID) -> Bool { loops[id] != nil }

    private func release(at k: Int) {
        let e = active[k].entity
        e.components.remove(ParticleEmitterComponent.self)
        e.isEnabled = false
        freeEmitters.append(e)
        active.swapAt(k, active.count - 1)
        active.removeLast()
    }

    // MARK: メッシュ演出

    /// 地面で広がる輪。
    func ring(at p: SIMD3<Float>, color: RGB, from r0: Float, to r1: Float, duration: Float, alpha: Float = 0.9) {
        guard meshFX.count < 40 else { return }
        let e = freeRings.popLast() ?? {
            let m = ModelEntity(mesh: meshes.ring(radius: 1, thickness: 0.12) ?? meshes.unitSphere, materials: [])
            OverlayOrder.apply(m, OverlayOrder.ring)
            root.addChild(m)
            return m
        }()
        e.model?.materials = [materials.unlit(color, alpha: 0.999)]
        e.position = p + SIMD3(0, 0.06, 0)
        e.scale = [r0, 1, r0]
        e.isEnabled = true
        e.components.set(OpacityComponent(opacity: alpha))
        meshFX.append(MeshFX(entity: e, start: time, duration: duration, fromScale: [r0, 1, r0], toScale: [r1, 1, r1],
                             alpha: alpha, kind: 0))
    }

    /// 閃光球（膨らんで消える）。
    func flash(at p: SIMD3<Float>, color: RGB, radius: Float, duration: Float, alpha: Float = 0.55) {
        guard meshFX.count < 40 else { return }
        let e = freeFlashes.popLast() ?? {
            let m = ModelEntity(mesh: meshes.unitSphere, materials: [])
            root.addChild(m)
            return m
        }()
        e.model?.materials = [materials.unlit(color, alpha: 0.999)]
        e.position = p
        e.scale = SIMD3(repeating: radius * 0.4)
        e.isEnabled = true
        e.components.set(OpacityComponent(opacity: alpha))
        meshFX.append(MeshFX(entity: e, start: time, duration: duration, fromScale: SIMD3(repeating: radius * 0.4),
                             toScale: SIMD3(repeating: radius), alpha: alpha, kind: 1))
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

    func clear() {
        while !active.isEmpty { release(at: active.count - 1) }
        for (_, e) in loops {
            e.components.remove(ParticleEmitterComponent.self)
            e.isEnabled = false
            freeEmitters.append(e)
        }
        loops.removeAll()
        for fx in meshFX { fx.entity.isEnabled = false }
        meshFX.removeAll()
    }

    // MARK: プリセット

    private func makeEmitter(_ preset: VFXPreset, color: UIColor, scale s: Float,
                             count: Int?, life lifeOverride: Double? = nil) -> (ParticleEmitterComponent, Float)? {
        var p = ParticleEmitterComponent()
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
            return (p, Float(life))
        }
        let total = quality.particles(count ?? n)
        if let lifeOverride { life = max(0.25, min(2.0, lifeOverride)) }
        m.lifeSpan = life
        m.birthRate = Float(Double(total) / emitDuration)
        p.mainEmitter = m
        p.timing = .once(warmUp: nil, emit: .init(duration: emitDuration))
        p.isEmitting = true
        return (p, Float(life + emitDuration) + 0.25)
    }

    private static func makeTexture(size: Int, draw: (CGContext, CGFloat) -> Void) -> TextureResource? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(ctx, CGFloat(size))
        guard let img = ctx.makeImage() else { return nil }
        return try? TextureResource(image: img, options: .init(semantic: .color))
    }
}
