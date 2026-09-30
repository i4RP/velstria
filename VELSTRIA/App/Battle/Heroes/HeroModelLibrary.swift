import Foundation
import RealityKit
import SwiftUI
import UIKit
import VelstriaCore

// 担当: hero-models。ヒーローモデルの生成口・共有キャッシュ・手続きアニメーションの適用。
// メッシュはヒーロー ID ごと、マテリアルはヒーロー × スキンごとに共有し、インスタンスはエンティティ階層だけを持つ。

/// 生成オプション（戦闘・プレビューで使い分ける）。
struct HeroModelOptions {
    /// 足元のチームリング。
    var teamMarker = true
    /// 足元の丸影。
    var shadow = true
    /// 色覚配慮のチーム色（青 / 橙）。
    var colorblind = false
    /// Epic スキンのオーラ粒子。
    var aura = true

    @MainActor static var battle: HeroModelOptions {
        HeroModelOptions(teamMarker: true, shadow: true, colorblind: HeroModelLibrary.colorblindTeamMarkers, aura: true)
    }

    static let showcase = HeroModelOptions(teamMarker: false, shadow: false, colorblind: false, aura: true)
}

@MainActor
enum HeroModelLibrary {
    /// 戦闘のチームリングを色覚配慮色にする（描画担当が設定 colorblindMode を反映する）。
    static var colorblindTeamMarkers = false

    private static var meshCache: [String: HeroMeshSet] = [:]

    static func makeModel(heroID: String, skinID: String?, team: Team, master: MasterData) -> HeroModelHandle {
        makeHero(heroID: heroID, skinID: skinID, team: team, master: master, options: .battle)
    }

    /// 具象型で返す生成口（プレビュー・ギャラリー用）。
    static func makeHero(heroID: String, skinID: String?, team: Team, master: MasterData,
                         options: HeroModelOptions) -> HeroModel {
        let def = master.hero(heroID)
        let bp = HeroBlueprints.blueprint(heroID: heroID, role: def?.role)
        let meshes = meshSet(heroID: heroID, blueprint: bp)
        let skin = HeroSkins.resolve(heroID: heroID, skinID: skinID, master: master)
        let palette = HeroPalettes.palette(heroID: heroID, blueprint: bp, skin: skin)
        let materials = HeroMaterialLibrary.materials(key: "\(heroID)#\(skin.variant)#\(skin.isEpic)", palette: palette)
        let runSpeed = Float((def?.moveSpeed ?? 330) / Balance.unitsPerMeter)
        return HeroModel(heroID: heroID, skin: skin, blueprint: bp, meshes: meshes, materials: materials,
                         palette: palette, team: team, options: options, defaultRunSpeed: runSpeed)
    }

    /// 試合のロード中に呼ぶと、初回表示時のメッシュ生成を避けられる。
    static func preload(heroIDs: [String], master: MasterData) {
        for id in heroIDs {
            let bp = HeroBlueprints.blueprint(heroID: id, role: master.hero(id)?.role)
            _ = meshSet(heroID: id, blueprint: bp)
        }
        _ = HeroEffectMeshes.teamRingSolid
        _ = HeroEffectMeshes.teamRingDashed
        _ = HeroEffectMeshes.groundRing
        _ = HeroEffectMeshes.glowSprite
    }

    static func meshSet(heroID: String, blueprint: HeroBlueprint) -> HeroMeshSet {
        if let m = meshCache[heroID] { return m }
        var assembler = HeroAssembler(blueprint: blueprint)
        let set = assembler.build(name: "hero.\(heroID)")
        meshCache[heroID] = set
        return set
    }
}

// MARK: - 効果用メッシュ

@MainActor
enum HeroEffectMeshes {
    /// 青: 連続リング + 前方の矢印。材質 0 = チーム色、1 = 影。
    static let teamRingSolid: MeshResource = makeTeamRing(dashed: false)
    /// 赤: 破線リング（色に頼らず形でも区別できる）。
    static let teamRingDashed: MeshResource = makeTeamRing(dashed: true)
    static let shadowOnly: MeshResource = {
        var b = MeshBuilder()
        b.add(MeshTemplate.flat(arcPoints(.zero, 0.44, 0, 2 * .pi, 32).dropLast()), trs(V3(0, 0.012, 0)), .secondary)
        return b.makeMesh(name: "hero.shadow") ?? MeshResource.generatePlane(width: 0.8, depth: 0.8)
    }()

    static let groundRing: MeshResource = {
        var b = MeshBuilder()
        b.add(MeshTemplate.annulus(inner: 0.64, outer: 0.72, segments: 56), trs(.zero), .primary)
        b.add(MeshTemplate.annulus(inner: 0.5, outer: 0.55, segments: 48, dashes: 12, dashFill: 0.55), trs(.zero), .primary)
        for i in 0..<4 {
            let a = Float(i) / 4 * 2 * .pi
            let p = V3(cos(a) * 0.82, 0, sin(a) * 0.82)
            b.add(MeshTemplate.flat([V2(0, 0.07), V2(0.045, 0), V2(0, -0.07), V2(-0.045, 0)]), trs(p, ry(-a)), .primary)
        }
        return b.makeMesh(name: "hero.groundRing") ?? MeshResource.generatePlane(width: 1.4, depth: 1.4)
    }()

    /// 詠唱の光（カメラを向く板。放射グラデーションのテクスチャを貼る）。
    static let glowSprite: MeshResource = MeshResource.generatePlane(width: 1, height: 1)

    private static func makeTeamRing(dashed: Bool) -> MeshResource {
        var b = MeshBuilder()
        let ring = dashed
            ? MeshTemplate.annulus(inner: 0.5, outer: 0.585, segments: 60, dashes: 10, dashFill: 0.68)
            : MeshTemplate.annulus(inner: 0.5, outer: 0.585, segments: 60)
        b.add(ring, trs(V3(0, 0.02, 0)), .primary)
        // 正面（-Z）の矢印
        b.add(MeshTemplate.flat([V2(-0.11, -0.6), V2(0, -0.74), V2(0.11, -0.6), V2(0, -0.645)]), trs(V3(0, 0.021, 0)), .primary)
        b.add(MeshTemplate.flat(arcPoints(.zero, 0.44, 0, 2 * .pi, 32).dropLast()), trs(V3(0, 0.012, 0)), .secondary)
        return b.makeMesh(name: dashed ? "hero.teamRing.dashed" : "hero.teamRing.solid")
            ?? MeshResource.generatePlane(width: 1.2, depth: 1.2)
    }
}

// MARK: - モデル

/// 手続き生成ヒーロー。root 直下に body（死亡フェード用）→ motion（全身の移動・傾き）→ 骨の階層。
@MainActor
final class HeroModel: HeroModelHandle {
    let root = Entity()
    let overheadHeight: Float
    let heroID: String
    let skin: HeroSkinInfo
    /// 骨・装備・効果を含むエンティティ数（性能確認用）。
    private(set) var entityCount = 0
    let triangleCount: Int

    private let body = Entity()
    private let motion = Entity()
    private let hips: ModelEntity
    private let torso: ModelEntity
    private let head: ModelEntity
    private let upperArmL: ModelEntity
    private let upperArmR: ModelEntity
    private let foreArmL: ModelEntity
    private let foreArmR: ModelEntity
    private let thighL: ModelEntity
    private let thighR: ModelEntity
    private let shinL: ModelEntity
    private let shinR: ModelEntity
    private let weapon: ModelEntity
    private let offhand: ModelEntity
    private let back: ModelEntity?
    private let wingL: ModelEntity?
    private let wingR: ModelEntity?
    private let flag: ModelEntity?
    private let float: ModelEntity?
    private let castGlow: ModelEntity
    private let groundRing: ModelEntity
    private let teamRing: ModelEntity?
    private let aura: Entity?

    private let metrics: BodyMetrics
    private let floatMotion: FloatMotion
    private let floatAnchor: V3
    private let weaponFollowsArm: Bool
    private let offhandFollowsArm: Bool
    private var animator: HeroAnimator
    private var appliedOpacity: Float = 1
    private var glowVisible = false
    private var ringVisible = false
    private var auraVisible = true

    init(heroID: String, skin: HeroSkinInfo, blueprint bp: HeroBlueprint, meshes ms: HeroMeshSet,
         materials: [RealityKit.Material], palette: HeroPalette, team: Team, options: HeroModelOptions,
         defaultRunSpeed: Float) {
        self.heroID = heroID
        self.skin = skin
        metrics = ms.metrics
        floatMotion = ms.floatMotion
        floatAnchor = ms.floatAnchor
        triangleCount = ms.triangleCount
        weaponFollowsArm = bp.weaponFollowsArm
        offhandFollowsArm = bp.offhand == .stoneFist || bp.offhand == .azureClaw
        overheadHeight = (ms.metrics.headTop + 0.38) * bp.scale

        func part(_ mesh: MeshResource?, _ name: String) -> ModelEntity {
            let e = ModelEntity()
            e.name = name
            if let mesh { e.components.set(ModelComponent(mesh: mesh, materials: materials)) }
            return e
        }
        let m = ms.metrics
        hips = part(ms.hips, "hips")
        torso = part(ms.torso, "torso")
        head = part(ms.head, "head")
        upperArmL = part(ms.upperArmL, "upperArmL")
        upperArmR = part(ms.upperArmR, "upperArmR")
        foreArmL = part(ms.foreArmL, "foreArmL")
        foreArmR = part(ms.foreArmR, "foreArmR")
        thighL = part(ms.thighL, "thighL")
        thighR = part(ms.thighR, "thighR")
        shinL = part(ms.shinL, "shinL")
        shinR = part(ms.shinR, "shinR")
        weapon = part(ms.weapon, "weapon")
        offhand = part(ms.offhand, "offhand")
        back = ms.back.map { part($0, "back") }
        wingL = ms.wingL.map { part($0, "wingL") }
        wingR = ms.wingR.map { part($0, "wingR") }
        flag = ms.flag.map { part($0, "flag") }
        float = ms.float.map { part($0, "float") }

        root.name = "hero.\(heroID)"
        root.addChild(body)
        body.addChild(motion)
        motion.scale = V3(repeating: bp.scale)
        motion.addChild(hips)
        hips.position = V3(0, m.hipY, 0)
        hips.addChild(thighL)
        hips.addChild(thighR)
        thighL.position = V3(-m.hipHalf, 0, 0)
        thighR.position = V3(m.hipHalf, 0, 0)
        thighL.addChild(shinL)
        thighR.addChild(shinR)
        shinL.position = V3(0, -m.thigh, 0)
        shinR.position = V3(0, -m.thigh, 0)
        hips.addChild(torso)
        torso.position = V3(0, 0.03, 0)
        torso.addChild(head)
        head.position = V3(0, m.torsoLen, 0)
        torso.addChild(upperArmL)
        torso.addChild(upperArmR)
        upperArmL.position = V3(-m.shoulderX, m.shoulderY, 0)
        upperArmR.position = V3(m.shoulderX, m.shoulderY, 0)
        upperArmL.addChild(foreArmL)
        upperArmR.addChild(foreArmR)
        foreArmL.position = V3(0, -m.upperArm, 0)
        foreArmR.position = V3(0, -m.upperArm, 0)
        foreArmL.addChild(offhand)
        foreArmR.addChild(weapon)
        weapon.scale = V3(repeating: bp.weaponScale)
        offhand.scale = V3(repeating: bp.offhandScale)
        offhand.position = V3(0, -m.foreArm - 0.035, 0)
        weapon.position = V3(0, -m.foreArm - 0.035, 0)
        if let back {
            torso.addChild(back)
            back.position = ms.backAnchor
        }
        if let wingL, let wingR {
            torso.addChild(wingL)
            torso.addChild(wingR)
            wingL.position = ms.wingAnchor + V3(-0.08, 0, 0)
            wingR.position = ms.wingAnchor + V3(0.08, 0, 0)
        }
        if let flag {
            weapon.addChild(flag)
            flag.position = ms.flagAnchor
        }
        if let float {
            if case .halo = ms.floatMotion { torso.addChild(float) } else { motion.addChild(float) }
            float.position = ms.floatAnchor
        }

        // 詠唱の光（武器の先端）
        castGlow = ModelEntity()
        castGlow.name = "castGlow"
        castGlow.components.set(ModelComponent(mesh: HeroEffectMeshes.glowSprite,
                                               materials: [HeroMaterialLibrary.glowSprite(palette.glow)]))
        castGlow.components.set(BillboardComponent())
        castGlow.position = ms.weaponTip
        castGlow.scale = V3(repeating: 0.001)
        castGlow.isEnabled = false
        weapon.addChild(castGlow)

        // 帰還・奥義の足元の輪
        groundRing = ModelEntity()
        groundRing.name = "groundRing"
        groundRing.components.set(ModelComponent(mesh: HeroEffectMeshes.groundRing,
                                                 materials: [HeroMaterialLibrary.unlit(palette.glow, opacity: 0.8)]))
        groundRing.position = V3(0, 0.03, 0)
        groundRing.isEnabled = false
        body.addChild(groundRing)

        // チームリングと丸影
        if options.teamMarker && team != .neutral {
            let color = UIColor(Theme.teamColor(team, colorblind: options.colorblind))
            let ring = ModelEntity()
            ring.name = "teamRing"
            ring.components.set(ModelComponent(
                mesh: team == .red ? HeroEffectMeshes.teamRingDashed : HeroEffectMeshes.teamRingSolid,
                materials: [HeroMaterialLibrary.unlit(color, opacity: 0.9),
                            HeroMaterialLibrary.unlit(HSB(0, 0, 0), opacity: 0.32)]))
            body.addChild(ring)
            teamRing = ring
        } else if options.shadow {
            let shadow = ModelEntity()
            shadow.name = "shadow"
            shadow.components.set(ModelComponent(mesh: HeroEffectMeshes.shadowOnly, materials: [
                HeroMaterialLibrary.unlit(HSB(0, 0, 0), opacity: 0.32),
                HeroMaterialLibrary.unlit(HSB(0, 0, 0), opacity: 0.32)]))
            body.addChild(shadow)
            teamRing = shadow
        } else {
            teamRing = nil
        }

        // Epic スキンのオーラ
        if palette.aura && options.aura {
            let e = Entity()
            e.name = "aura"
            e.components.set(HeroModel.auraEmitter(color: palette.glow.uiColor))
            e.position = V3(0, 0.1, 0)
            body.addChild(e)
            aura = e
        } else {
            aura = nil
        }

        animator = HeroAnimator(profile: HeroMotionProfile(blueprint: bp, metrics: ms.metrics),
                                defaultRunSpeed: defaultRunSpeed)
        entityCount = HeroModel.countEntities(root)
        apply(animator.current, time: 0)
    }

    private static func countEntities(_ e: Entity) -> Int {
        var n = 1
        for c in e.children { n += countEntities(c) }
        return n
    }

    private static func auraEmitter(color: UIColor) -> ParticleEmitterComponent {
        var p = ParticleEmitterComponent()
        p.emitterShape = .cylinder
        p.emitterShapeSize = [0.42, 0.04, 0.42]
        p.birthLocation = .surface
        p.emissionDirection = [0, 1, 0]
        p.speed = 0.22
        p.speedVariation = 0.08
        p.mainEmitter.birthRate = 20
        p.mainEmitter.lifeSpan = 1.5
        p.mainEmitter.lifeSpanVariation = 0.3
        p.mainEmitter.size = 0.035
        p.mainEmitter.sizeVariation = 0.015
        p.mainEmitter.acceleration = [0, 0.25, 0]
        p.mainEmitter.color = .evolving(start: .single(color), end: .single(color.withAlphaComponent(0)))
        p.mainEmitter.blendMode = .additive
        p.mainEmitter.opacityCurve = .quickFadeInOut
        return p
    }

    // MARK: HeroModelHandle

    var state: HeroAnimState { animator.state }

    func setState(_ state: HeroAnimState) {
        let wasDead = animator.state == .dead
        animator.setState(state)
        if wasDead && state != .dead {
            // 復活: 即座に不透明へ戻す
            setOpacity(1)
        }
    }

    func update(dt: Double, moveSpeed: Double) {
        // moveSpeed は sim ユニット/秒（HeroDef.moveSpeed と同じ単位）。20 以下は m/s とみなす。
        var speed = Float(max(0, moveSpeed))
        if speed > 20 { speed /= Float(Balance.unitsPerMeter) }
        let pose = animator.advance(dt: Float(dt), moveSpeed: speed)
        apply(pose, time: animator.time)
    }

    // MARK: 適用

    private func apply(_ p: HeroPose, time t: Float) {
        motion.position = p.offset
        motion.orientation = ry(p.yaw) * rx(-p.pitch) * rz(p.roll)
        hips.position = V3(0, metrics.hipY - p.hipsDrop, 0)
        hips.orientation = ry(p.hipsYaw) * rz(p.hipsRoll)
        torso.orientation = ry(p.torsoYaw - p.hipsYaw) * rx(-p.torsoPitch) * rz(p.torsoRoll)
        head.orientation = ry(p.headYaw) * rx(-p.headPitch) * rz(p.headRoll)
        // 開き（out）は腕のローカルで先に回すので、腕を上げても外側へ開く
        upperArmR.orientation = ry(p.armR.yaw) * rx(p.armR.pitch) * rz(p.armR.out)
        upperArmL.orientation = ry(-p.armL.yaw) * rx(p.armL.pitch) * rz(-p.armL.out)
        foreArmR.orientation = rx(p.armR.elbow)
        foreArmL.orientation = rx(p.armL.elbow)
        // 武器角は胴基準の絶対角: 腕の前後・開き・肘の回転を打ち消してから θ だけ傾ける
        weapon.orientation = weaponFollowsArm ? qIdentity
            : rx(-p.armR.elbow) * rz(-p.armR.out) * rx(p.weaponR - p.armR.pitch)
        offhand.orientation = offhandFollowsArm ? qIdentity
            : rx(-p.armL.elbow) * rz(p.armL.out) * rx(p.weaponL - p.armL.pitch)
        thighR.orientation = rx(p.legR.pitch) * rz(p.legR.out)
        thighL.orientation = rx(p.legL.pitch) * rz(-p.legL.out)
        shinR.orientation = rx(-p.legR.knee)
        shinL.orientation = rx(-p.legL.knee)
        back?.orientation = rx(-p.cape)
        if let wingL, let wingR {
            let sp = min(1.3, max(0, p.wings))
            let flap = 0.06 * sin(t * 2.4)
            wingR.orientation = ry(-(1 - sp) * 1.1) * rz(sp * 0.35 - 0.12 + flap)
            wingL.orientation = ry((1 - sp) * 1.1) * rz(-(sp * 0.35 - 0.12 + flap))
        }
        flag?.orientation = ry(0.28 * sin(t * 5.3) + 0.12 * sin(t * 8.7))
        if let float {
            switch floatMotion {
            case .none:
                break
            case .orbit(let sp):
                float.orientation = ry(t * sp)
                float.position = floatAnchor + V3(0, 0.05 * sin(t * 1.6), 0)
            case .halo(let sp):
                float.orientation = rz(t * sp)
                float.position = floatAnchor + V3(0, 0.02 * sin(t * 1.3), 0)
            case .hover(let sp):
                float.orientation = ry(t * sp) * rz(0.15 * sin(t * 0.9))
                float.position = floatAnchor + V3(0, 0.06 * sin(t * 1.4), 0)
            }
        }

        let g = p.glow
        let showGlow = g > 0.03
        if showGlow != glowVisible {
            castGlow.isEnabled = showGlow
            glowVisible = showGlow
        }
        if showGlow {
            castGlow.scale = V3(repeating: 0.25 + 0.35 * g)
        }
        let showRing = p.ring > 0.03
        if showRing != ringVisible {
            groundRing.isEnabled = showRing
            ringVisible = showRing
        }
        if showRing {
            groundRing.scale = V3(repeating: 0.5 + 0.5 * p.ring)
            groundRing.orientation = ry(t * 1.4)
        }
        if let aura {
            let show = animator.state != .dead
            if show != auraVisible {
                aura.isEnabled = show
                auraVisible = show
            }
        }
        setOpacity(p.opacity)
    }

    private func setOpacity(_ o: Float) {
        let v = min(1, max(0, o))
        guard abs(v - appliedOpacity) > 0.004 || (v >= 0.999 && appliedOpacity < 1) else { return }
        if v >= 0.999 {
            body.components.remove(OpacityComponent.self)
            appliedOpacity = 1
        } else {
            body.components.set(OpacityComponent(opacity: v))
            appliedOpacity = v
        }
    }
}
