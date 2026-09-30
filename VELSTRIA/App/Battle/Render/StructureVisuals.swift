import Foundation
import RealityKit
import simd
import VelstriaCore

// 担当: battle-renderer。タワー（台座 + 柱 + 浮遊結晶）と Star Core（巨大な星結晶 + 回転する環）。
// 破壊後は柱と結晶を消して瓦礫を出す（結晶は落ちながらフェード）。

@MainActor
final class StructureMeshes {
    struct TeamSet {
        var plinth: MeshResource?
        var pillar: MeshResource?
        var pillarGlow: MeshResource?
        var crystal: MeshResource?
        var shards: MeshResource?
        var coreBase: MeshResource?
        var coreBaseGlow: MeshResource?
        var coreStar: MeshResource?
        var coreRing: MeshResource?
        var coreRingSmall: MeshResource?
    }

    private var sets: [Int: TeamSet] = [:]

    func set(_ team: Team) -> TeamSet {
        if let s = sets[team.rawValue] { return s }
        let red = team == .red
        let main: Swatch = red ? .redMain : .blueMain
        let cloth: Swatch = red ? .redCloth : .blueCloth
        let rune: Swatch = red ? .glowRed : .glowBlue
        let crystalRamp: Ramp = red ? .crystalRed : .crystalBlue
        var s = TeamSet()

        // タワー台座（破壊後も残る）
        var plinth = MeshBuilder()
        plinth.frustum(bottomRadius: 1.55, topRadius: 1.4, height: 0.34, segments: 8, color: .solid(.stoneDark), phase: 0.39)
        plinth.frustum(bottomRadius: 1.2, topRadius: 1.08, height: 0.32, segments: 8, color: .solid(.stone), phase: 0.39,
                       transform: MX.t(0, 0.34, 0))
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi + .pi / 4
            plinth.box(size: [0.34, 0.5, 0.34], color: .solid(.stoneDark), transform: MX.t(cos(a) * 1.28, 0, -sin(a) * 1.28) * MX.ry(a))
        }
        s.plinth = plinth.makeMesh(name: "towerPlinth_\(team.rawValue)")

        // 柱・冠・旗・ランタン
        var pillar = MeshBuilder(), pillarGlow = MeshBuilder()
        pillar.frustum(bottomRadius: 0.66, topRadius: 0.44, height: 3.1, segments: 8, color: .ramp(.stonePillar), phase: 0.39,
                       transform: MX.t(0, 0.66, 0))
        for y: Float in [1.3, 2.7] {
            pillar.torus(majorRadius: y < 2 ? 0.62 : 0.5, minorRadius: 0.07, segments: 16, sides: 4, color: .solid(.gold),
                         transform: MX.t(0, y, 0))
        }
        pillar.frustum(bottomRadius: 0.42, topRadius: 0.78, height: 0.36, segments: 8, color: .solid(.metalDark), phase: 0.39,
                       transform: MX.t(0, 3.76, 0))
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi
            pillar.frustum(bottomRadius: 0.1, topRadius: 0, height: 0.75, segments: 4, color: .solid(.gold),
                           transform: MX.t(cos(a) * 0.62, 4.05, -sin(a) * 0.62) * MX.ry(a) * MX.rz(-0.35))
            // 旗
            pillar.box(size: [0.36, 1.1, 0.04], color: .solid(cloth),
                       transform: MX.t(cos(a) * 0.6, 1.55, -sin(a) * 0.6) * MX.ry(a + .pi / 2))
            pillar.box(size: [0.36, 0.1, 0.05], color: .solid(.gold),
                       transform: MX.t(cos(a) * 0.62, 2.62, -sin(a) * 0.62) * MX.ry(a + .pi / 2))
            pillarGlow.crystal(radius: 0.06, height: 0.22, color: .solid(rune),
                               transform: MX.t(cos(a) * 0.64, 2.0, -sin(a) * 0.64))
            // 台座角のランタン
            let b = Float(k) / 4 * 2 * .pi + .pi / 4
            pillar.box(size: [0.18, 0.05, 0.18], color: .solid(.metalDark), transform: MX.t(cos(b) * 1.28, 0.5, -sin(b) * 1.28))
            pillarGlow.box(size: [0.14, 0.2, 0.14], color: .solid(.lanternWarm), transform: MX.t(cos(b) * 1.28, 0.55, -sin(b) * 1.28))
            pillar.frustum(bottomRadius: 0.12, topRadius: 0, height: 0.14, segments: 4, color: .solid(.metalDark),
                           transform: MX.t(cos(b) * 1.28, 0.75, -sin(b) * 1.28))
        }
        pillarGlow.annulus(inner: 0.46, outer: 0.56, segments: 16, y: 4.125, color: .solid(rune))
        s.pillar = pillar.makeMesh(name: "towerPillar_\(team.rawValue)")
        s.pillarGlow = pillarGlow.makeMesh(name: "towerPillarGlow_\(team.rawValue)")

        var crystal = MeshBuilder()
        crystal.crystal(radius: 0.46, height: 1.45, sides: 6, waist: 0.42, color: .ramp(crystalRamp, from: 0.15, to: 1),
                        transform: MX.t(0, -0.62, 0))
        s.crystal = crystal.makeMesh(name: "towerCrystal_\(team.rawValue)")
        var shards = MeshBuilder()
        for k in 0..<3 {
            let a = Float(k) / 3 * 2 * .pi
            shards.crystal(radius: 0.1, height: 0.34, color: .ramp(crystalRamp, from: 0.4, to: 1),
                           transform: MX.t(cos(a) * 0.85, -0.1 + Float(k) * 0.1, -sin(a) * 0.85))
        }
        s.shards = shards.makeMesh(name: "towerShards_\(team.rawValue)")

        // Core 台座
        var coreBase = MeshBuilder(), coreGlow = MeshBuilder()
        coreBase.frustum(bottomRadius: 3.4, topRadius: 3.15, height: 0.4, segments: 12, color: .solid(.stoneDark))
        coreBase.frustum(bottomRadius: 2.7, topRadius: 2.5, height: 0.34, segments: 12, color: .solid(.stone),
                         transform: MX.t(0, 0.4, 0))
        coreBase.frustum(bottomRadius: 1.5, topRadius: 1.2, height: 0.5, segments: 12, color: .solid(.stoneLight),
                         transform: MX.t(0, 0.74, 0))
        coreGlow.annulus(inner: 2.2, outer: 2.38, segments: 36, y: 0.745, color: .solid(rune))
        coreGlow.annulus(inner: 1.0, outer: 1.12, segments: 24, y: 1.245, color: .solid(rune))
        for k in 0..<6 {
            let a = Float(k) / 6 * 2 * .pi + .pi / 6
            let p = SIMD3<Float>(cos(a) * 2.95, 0.4, -sin(a) * 2.95)
            coreBase.frustum(bottomRadius: 0.26, topRadius: 0.2, height: 2.3, segments: 6, color: .ramp(.stonePillar),
                             transform: MX.t(p))
            coreBase.box(size: [0.55, 0.16, 0.55], color: .solid(.gold), transform: MX.t(p + SIMD3(0, 2.3, 0)) * MX.ry(a))
            coreGlow.crystal(radius: 0.14, height: 0.5, color: .ramp(crystalRamp, from: 0.4, to: 1),
                             transform: MX.t(p + SIMD3(0, 2.46, 0)))
            coreBase.box(size: [0.3, 1.0, 0.03], color: .solid(main), transform: MX.t(p + SIMD3(0, 1.3, 0)) * MX.ry(a + .pi / 2)
                         * MX.t(0, 0, -0.26))
        }
        s.coreBase = coreBase.makeMesh(name: "coreBase_\(team.rawValue)")
        s.coreBaseGlow = coreGlow.makeMesh(name: "coreBaseGlow_\(team.rawValue)")

        // 星結晶（中心の大結晶 + 放射状の小結晶）
        var star = MeshBuilder()
        star.crystal(radius: 0.95, height: 3.0, sides: 6, waist: 0.5, color: .ramp(crystalRamp, from: 0.1, to: 1),
                     transform: MX.t(0, -1.5, 0))
        for k in 0..<6 {
            let a = Float(k) / 6 * 2 * .pi
            star.crystal(radius: 0.28, height: 1.5, sides: 5, color: .ramp(crystalRamp, from: 0.3, to: 1),
                         transform: MX.ry(a) * MX.rz(-1.25) * MX.t(0, 0.5, 0))
        }
        s.coreStar = star.makeMesh(name: "coreStar_\(team.rawValue)")
        var ring = MeshBuilder()
        ring.torus(majorRadius: 2.25, minorRadius: 0.08, segments: 40, sides: 5, color: .solid(rune))
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi
            ring.crystal(radius: 0.1, height: 0.3, color: .solid(.glowWhite), transform: MX.t(cos(a) * 2.25, -0.15, -sin(a) * 2.25))
        }
        s.coreRing = ring.makeMesh(name: "coreRing_\(team.rawValue)")
        var ring2 = MeshBuilder()
        ring2.torus(majorRadius: 1.65, minorRadius: 0.06, segments: 32, sides: 5, color: .solid(.glowGold))
        s.coreRingSmall = ring2.makeMesh(name: "coreRing2_\(team.rawValue)")
        sets[team.rawValue] = s
        return s
    }
}

@MainActor
final class StructureVisual {
    let id: EntityID
    let isCore: Bool
    let team: Team
    let root = Entity()
    private let intact = Entity()
    private let floating = Entity()
    private var ringA: Entity?
    private var ringB: Entity?
    private var shards: Entity?
    private let rubble: ModelEntity?
    let bar: OverheadBar
    let rangeRing: ModelEntity
    private(set) var destroyed = false
    private var fallT: Float = 0
    private var phase: Float
    private var rangeAlpha: Float = 0
    private var opacityFloating: Float = 1
    private var occlusionAlpha: Float = 1

    /// 攻撃の発射点（world 高さ）。
    var muzzleHeight: Float { isCore ? 3.4 : 4.5 }

    init(unit u: VelstriaCore.Unit, meshes: StructureMeshes, unitMeshes: UnitMeshLibrary, materials: RenderMaterials, text: TextMeshCache) {
        id = u.id
        isCore = u.kind == .core
        team = u.team
        phase = Float(u.id % 7)
        root.name = isCore ? "core_\(u.id)" : "tower_\(u.id)"
        root.position = worldPosition(u.pos)
        let s = meshes.set(u.team)
        root.addChild(intact)
        root.addChild(floating)
        if isCore {
            if let m = s.coreBase { root.addChild(ModelEntity(mesh: m, materials: [materials.lit])) }
            if let m = s.coreBaseGlow { root.addChild(ModelEntity(mesh: m, materials: [materials.glow])) }
            if let m = s.coreStar { floating.addChild(ModelEntity(mesh: m, materials: [materials.glow])) }
            floating.position.y = 3.6
            let a = Entity(), b = Entity()
            if let m = s.coreRing { a.addChild(ModelEntity(mesh: m, materials: [materials.glow])) }
            if let m = s.coreRingSmall { b.addChild(ModelEntity(mesh: m, materials: [materials.glow])) }
            a.position.y = 3.6
            b.position.y = 3.6
            intact.addChild(a)
            intact.addChild(b)
            ringA = a
            ringB = b
        } else {
            if let m = s.plinth { root.addChild(ModelEntity(mesh: m, materials: [materials.lit])) }
            if let m = s.pillar { intact.addChild(ModelEntity(mesh: m, materials: [materials.lit])) }
            if let m = s.pillarGlow { intact.addChild(ModelEntity(mesh: m, materials: [materials.glow])) }
            if let m = s.crystal { floating.addChild(ModelEntity(mesh: m, materials: [materials.glow])) }
            floating.position.y = 4.95
            let sh = Entity()
            if let m = s.shards { sh.addChild(ModelEntity(mesh: m, materials: [materials.glow])) }
            sh.position.y = 4.8
            intact.addChild(sh)
            shards = sh
        }
        if let m = unitMeshes.rubble {
            let r = ModelEntity(mesh: m, materials: [materials.lit])
            r.scale = SIMD3(repeating: isCore ? 2.0 : 1.0)
            r.position.y = isCore ? 0.3 : 0.6
            r.isEnabled = false
            root.addChild(r)
            rubble = r
        } else {
            rubble = nil
        }
        bar = OverheadBar(style: .structure(core: isCore), fillColor: materials.teams.main(u.team), materials: materials,
                          meshes: unitMeshes, text: text)
        bar.root.position.y = isCore ? 7.0 : 6.4
        root.addChild(bar.root)
        let range = Float((isCore ? Balance.coreRange : Balance.towerRange) / Balance.unitsPerMeter)
        rangeRing = ModelEntity(mesh: unitMeshes.ring(radius: range, thickness: 0.12) ?? unitMeshes.unitSphere,
                                materials: [materials.unlit(RGB(1.0, 0.35, 0.3), alpha: 0.85)])
        rangeRing.position.y = 0.05
        rangeRing.isEnabled = false
        OverlayOrder.apply(rangeRing, OverlayOrder.ring)
        root.addChild(rangeRing)
        if !u.isAlive { setDestroyed(immediate: true) }
    }

    func setDestroyed(immediate: Bool) {
        guard !destroyed else { return }
        destroyed = true
        intact.isEnabled = false
        rubble?.isEnabled = true
        bar.root.isEnabled = false
        rangeRing.isEnabled = false
        fallT = immediate ? 1 : 0
        if immediate { floating.isEnabled = false }
    }

    /// 追従ヒーローがこの構造物の奥（画面上で柱に隠れる位置）にいるか。
    func occludes(_ p: SIMD3<Float>) -> Bool {
        let c = root.position
        let dz = c.z - p.z
        return abs(p.x - c.x) < (isCore ? 3.4 : 1.7) && dz > 0.2 && dz < (isCore ? 6.5 : 4.6)
    }

    /// showRange: 視点ヒーローが敵タワーの射程付近にいる。occluding: 追従ヒーローを隠している（半透明にする）。
    func update(_ f: RenderFrame, index i: Int, showRange: Bool, occluding: Bool = false) {
        let u = f.state.units[i]
        phase += f.dt
        if !u.isAlive && !destroyed { setDestroyed(immediate: false) }
        if destroyed {
            if fallT < 1 {
                fallT = min(1, fallT + f.dt / 1.3)
                floating.position.y -= f.dt * (1 + fallT * 5)
                floating.orientation = simd_quatf(angle: fallT * 1.5, axis: simd_normalize(SIMD3<Float>(1, 0, 0.4)))
                let a = 1 - fallT
                if abs(a - opacityFloating) > 0.01 {
                    opacityFloating = a
                    floating.components.set(OpacityComponent(opacity: a))
                }
                if fallT >= 1 { floating.isEnabled = false }
            }
            return
        }
        // 追従ヒーローを隠す間は柱と結晶を半透明に
        let occTarget: Float = occluding ? 0.4 : 1
        if abs(occTarget - occlusionAlpha) > 0.01 {
            occlusionAlpha += (occTarget - occlusionAlpha) * min(1, f.dt * 8)
            if abs(occTarget - occlusionAlpha) < 0.02 { occlusionAlpha = occTarget }
            if occlusionAlpha >= 0.995 {
                intact.components.remove(OpacityComponent.self)
                floating.components.remove(OpacityComponent.self)
            } else {
                intact.components.set(OpacityComponent(opacity: occlusionAlpha))
                floating.components.set(OpacityComponent(opacity: occlusionAlpha))
            }
        }
        let t = phase
        if isCore {
            floating.position.y = 3.6 + sin(t * 1.1) * 0.18
            floating.orientation = simd_quatf(angle: t * 0.35, axis: [0, 1, 0])
            ringA?.orientation = simd_quatf(angle: t * 0.8, axis: [0, 1, 0]) * simd_quatf(angle: 0.45, axis: [1, 0, 0])
            ringB?.orientation = simd_quatf(angle: -t * 1.1, axis: [0, 1, 0]) * simd_quatf(angle: -0.6, axis: [0, 0, 1])
        } else {
            floating.position.y = 4.95 + sin(t * 1.6) * 0.12
            floating.orientation = simd_quatf(angle: t * 0.7, axis: [0, 1, 0])
            shards?.orientation = simd_quatf(angle: -t * 1.3, axis: [0, 1, 0])
        }
        let maxHP = max(1, u.stats.maxHP)
        bar.update(hp: Float(u.hp / maxHP), shield: 0, resource: nil, level: nil, dt: f.dt)
        bar.keepScreenSize(camera: f.camera)
        // 射程円（フェード）
        let target: Float = showRange ? 1 : 0
        rangeAlpha += (target - rangeAlpha) * min(1, f.dt * 6)
        rangeRing.isEnabled = rangeAlpha > 0.02
        if rangeRing.isEnabled {
            rangeRing.components.set(OpacityComponent(opacity: rangeAlpha * (0.75 + sin(t * 4) * 0.2)))
        }
    }
}
