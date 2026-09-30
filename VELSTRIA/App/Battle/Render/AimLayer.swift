import Foundation
import RealityKit
import VelstriaCore

// 担当: battle-renderer。スキル照準の表示（controller.aim）。
// 射程円 + 方向型（矢印/線の幅/扇形）・地点型（効果円）・対象型（対象円）・自身中心型。キャンセル領域では赤。

@MainActor
final class AimLayer {
    let root = Entity()
    private let materials: RenderMaterials
    private let meshes: UnitMeshLibrary
    private let rangeRing = ModelEntity()
    private let rangeFill = ModelEntity()
    private let strip = ModelEntity()
    private let stripEdgeL = ModelEntity()
    private let stripEdgeR = ModelEntity()
    private let arrow = ModelEntity()
    private let cone = ModelEntity()
    private let coneEdge = ModelEntity()
    private let targetFill = ModelEntity()
    private let targetRing = ModelEntity()
    /// 照準形状ごとに出し分ける部品（毎フレームの配列生成を避けるため保持）。
    private var optionalParts: [ModelEntity] = []
    private var shown: AimIndicator?
    private var cancelling = false
    private var t: Float = 0

    static let normalColor = RGB(0.55, 0.88, 1.0)
    static let allyColor = RGB(0.45, 1.0, 0.6)
    static let cancelColor = RGB(1.0, 0.3, 0.28)

    init(materials: RenderMaterials, meshes: UnitMeshLibrary) {
        self.materials = materials
        self.meshes = meshes
        root.name = "aim"
        for e in [rangeFill, rangeRing, strip, stripEdgeL, stripEdgeR, arrow, cone, coneEdge, targetFill, targetRing] {
            OverlayOrder.apply(e, OverlayOrder.aim)
            e.isEnabled = false
            root.addChild(e)
        }
        optionalParts = [strip, stripEdgeL, stripEdgeR, arrow, cone, coneEdge, targetFill, targetRing]
        root.isEnabled = false
    }

    private func paint(_ c: RGB) {
        let solid = materials.unlit(c, alpha: 0.85)
        let soft = materials.unlit(c, alpha: 0.2)
        let faint = materials.unlit(c, alpha: 0.07)
        rangeRing.model = meshes.ring(radius: 1, thickness: 0.012).map { ModelComponent(mesh: $0, materials: [solid]) }
        rangeFill.model = meshes.unitDisc.map { ModelComponent(mesh: $0, materials: [faint]) }
        strip.model = meshes.groundStrip.map { ModelComponent(mesh: $0, materials: [soft]) }
        stripEdgeL.model = meshes.groundStrip.map { ModelComponent(mesh: $0, materials: [solid]) }
        stripEdgeR.model = meshes.groundStrip.map { ModelComponent(mesh: $0, materials: [solid]) }
        arrow.model = meshes.arrowHead.map { ModelComponent(mesh: $0, materials: [solid]) }
        cone.model = meshes.sector(halfAngle: .pi / 4, outline: false).map { ModelComponent(mesh: $0, materials: [soft]) }
        coneEdge.model = meshes.sector(halfAngle: .pi / 4, outline: true, thicknessRatio: 0.03)
            .map { ModelComponent(mesh: $0, materials: [solid]) }
        targetFill.model = meshes.unitDisc.map { ModelComponent(mesh: $0, materials: [soft]) }
        targetRing.model = meshes.ring(radius: 1, thickness: 0.06).map { ModelComponent(mesh: $0, materials: [solid]) }
    }

    func update(_ aim: AimIndicator?, origin liveOrigin: Vec2?, dt: Float) {
        t += dt
        guard let aim else {
            if root.isEnabled { root.isEnabled = false }
            shown = nil
            return
        }
        let color = aim.isCancelling ? AimLayer.cancelColor : (aim.targeting.targetsAllies ? AimLayer.allyColor : AimLayer.normalColor)
        if shown == nil || aim.isCancelling != cancelling || shown?.targeting.targetsAllies != aim.targeting.targetsAllies {
            paint(color)
            cancelling = aim.isCancelling
        }
        shown = aim
        root.isEnabled = true
        // 照準の原点はヒーローの描画位置に追従させる（補間のずれを防ぐ）
        let origin = liveOrigin ?? aim.origin
        let delta = aim.target - aim.origin
        let target = origin + delta
        let o = worldPosition(origin, height: 0.07)
        let range = Float(aim.targeting.range / Balance.unitsPerMeter)
        let radius = Float(aim.targeting.radius / Balance.unitsPerMeter)
        let dirLen = delta.length
        let yaw: Float = dirLen > 1 ? Float(atan2(delta.y, delta.x)) : 0
        let rot = simd_quatf(angle: yaw, axis: [0, 1, 0])

        let hasRange = range > 0.3
        rangeRing.isEnabled = hasRange
        rangeFill.isEnabled = hasRange
        if hasRange {
            rangeRing.position = o
            rangeRing.scale = [range, 1, range]
            rangeFill.position = o - SIMD3(0, 0.005, 0)
            rangeFill.scale = [range, 1, range]
        }
        for e in optionalParts { e.isEnabled = false }

        switch aim.targeting.aim {
        case .direction:
            switch aim.targeting.archetype {
            case .cone:
                cone.isEnabled = true
                coneEdge.isEnabled = true
                let r = max(range, 1)
                cone.position = o
                cone.orientation = rot
                cone.scale = [r, 1, r]
                coneEdge.position = o + SIMD3(0, 0.003, 0)
                coneEdge.orientation = rot
                coneEdge.scale = [r, 1, r]
            default:
                // 直線スキルショット・貫通・突進: 幅つきの帯 + 矢印
                let half: Float
                switch aim.targeting.archetype {
                case .lineSkillshot: half = max(0.3, radius * 0.5)
                case .piercingLine: half = max(0.4, radius)
                default: half = 0.45
                }
                let len = max(0.5, (aim.targeting.archetype == .piercingLine ? max(range, Float(dirLen / 100)) : range) - 0.7)
                strip.isEnabled = true
                strip.position = o
                strip.orientation = rot
                strip.scale = [len, 1, half * 2]
                let side = rot.act(SIMD3<Float>(0, 0, 1))
                stripEdgeL.isEnabled = true
                stripEdgeR.isEnabled = true
                stripEdgeL.position = o + side * half + SIMD3(0, 0.003, 0)
                stripEdgeR.position = o - side * half + SIMD3(0, 0.003, 0)
                stripEdgeL.orientation = rot
                stripEdgeR.orientation = rot
                stripEdgeL.scale = [len, 1, 0.06]
                stripEdgeR.scale = [len, 1, 0.06]
                arrow.isEnabled = true
                arrow.position = o + rot.act(SIMD3<Float>(len, 0.003, 0))
                arrow.orientation = rot
                let aw = max(half * 2.4, 0.9)
                arrow.scale = [0.75, 1, aw]
            }
        case .point:
            let tp = worldPosition(target, height: 0.075)
            let r = max(radius, 0.6)
            targetFill.isEnabled = true
            targetRing.isEnabled = true
            targetFill.position = tp
            targetFill.scale = [r, 1, r]
            let pulse = 1 + sin(t * 8) * 0.03
            targetRing.position = tp + SIMD3(0, 0.003, 0)
            targetRing.scale = [r * pulse, 1, r * pulse]
            if dirLen > 50 {
                strip.isEnabled = true
                strip.position = o
                strip.orientation = rot
                strip.scale = [Float(dirLen / 100), 1, 0.08]
            }
        case .unit:
            let tp = worldPosition(target, height: 0.075)
            targetRing.isEnabled = true
            targetRing.position = tp
            let pulse: Float = 0.9 + sin(t * 10) * 0.08
            targetRing.scale = [pulse, 1, pulse]
            if dirLen > 50 {
                strip.isEnabled = true
                strip.position = o
                strip.orientation = rot
                strip.scale = [Float(dirLen / 100), 1, 0.1]
            }
        case .none:
            let r = max(radius, 0.8)
            targetFill.isEnabled = true
            targetRing.isEnabled = true
            targetFill.position = o
            targetFill.scale = [r, 1, r]
            targetRing.position = o + SIMD3(0, 0.003, 0)
            targetRing.scale = [r, 1, r]
        }
    }
}
