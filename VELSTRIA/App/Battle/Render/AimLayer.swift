import Foundation
import RealityKit
import VelstriaCore

// 担当: battle-renderer。スキル照準の表示（controller.aim）。
// 射程円 + 方向型（矢印/線の幅/扇形）・地点型（効果円）・対象型（対象円）・自身中心型。キャンセル領域では赤。
// キット層（docs/SKILL_KITS.md）のスキルは SkillTargeting.shape を先に見る（AimShapePlan）。.auto は従来の archetype / aim の分岐。

/// 照準の形の計画（純粋。単体テスト対象）。shape が .auto、または aim と形が合わないものは .legacy = 従来の分岐。
/// 長さは m（Balance.unitsPerMeter）。
enum AimShapePlan: Equatable {
    case legacy
    /// 扇（半角ラジアン。半径は射程）。
    case fan(halfAngle: Float)
    /// 幅つきの直線（半幅 m）。
    case band(halfWidth: Float)
    /// 地点への突進の経路（半幅 m）+ 終点の輪。
    case dash(halfWidth: Float)
    /// 指定地点の円（半径 m）。
    case circleAtPoint(radius: Float)
    /// 自身中心のリング（半径 m）。
    case selfRing(radius: Float)
    /// 対象指定の照準環。
    case lockOn

    static func make(_ t: SkillTargeting) -> AimShapePlan {
        let radius = Float(t.radius / Balance.unitsPerMeter)
        switch t.shape {
        case .auto:
            return .legacy
        case .fan:
            guard t.aim == .direction, t.halfAngle > 0.01 else { return .legacy }
            return .fan(halfAngle: Float(min(t.halfAngle, Double.pi)))
        case .wideLine:
            return t.aim == .direction ? .band(halfWidth: max(0.3, radius)) : .legacy
        case .dashToPoint:
            return t.aim == .direction ? .dash(halfWidth: max(0.3, radius)) : .legacy
        case .circleAtPoint:
            return t.aim == .point ? .circleAtPoint(radius: max(radius, 0.6)) : .legacy
        case .selfRing:
            return t.aim == .none ? .selfRing(radius: max(radius, 0.8)) : .legacy
        case .lockOn:
            return t.aim == .unit ? .lockOn : .legacy
        }
    }
}

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
    private var solidMaterial: UnlitMaterial?
    private var softMaterial: UnlitMaterial?
    /// 扇のメッシュを作った半角（0.01 rad 単位。paint で π/4 に戻る）。
    private var fanHalfAngle: Float = 0.79
    /// 射程リングのメッシュを作った半径（0.05 m 単位。単位円を拡大すると多角形が目立ち線幅も変わるため実寸で作る）。
    private var ringRadius: Float = -1

    static let normalColor = RGB(0.86, 0.95, 1.0)
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

    /// 照準の色の全て（マテリアルの事前生成に使う）。
    static let colors = [normalColor, allyColor, cancelColor]
    /// 線・塗り・射程の塗りの不透明度。
    static let alphas = (solid: 0.85, soft: 0.2, faint: 0.07)
    /// 射程リングの線幅（m）。
    static let rangeRingThickness: Float = 0.08

    /// 射程リングのメッシュ半径（0.05 m 単位）。
    static func rangeRingRadius(_ range: Float) -> Float { (range * 20).rounded() / 20 }

    /// 照準の形状・全色のマテリアルと、ranges（m）の射程リングを作る（読み込み幕の裏。初めて照準した瞬間の生成をなくす）。
    func prewarm(ranges: [Float]) {
        for c in AimLayer.colors { paint(c) }
        for r in ranges where r > 0.3 {
            _ = meshes.ring(radius: AimLayer.rangeRingRadius(r), thickness: AimLayer.rangeRingThickness)
        }
        // 見た目の状態は初回の照準で塗り直す
        shown = nil
        solidMaterial = nil
        ringRadius = -1
    }

    /// 人間ヒーローのスキル・スペルの射程（m。射程リングは 0.3 m 超のみ描く）。
    static func plannedRanges(state: SimState, humanID: EntityID?, master: MasterData) -> [Float] {
        guard let id = humanID, let u = state.unit(id), let h = u.hero, let def = master.hero(h.heroID) else { return [] }
        var out: [Float] = []
        for slot in SkillSlot.actives {
            guard let sk = master.skill(hero: h.heroID, slot: slot) else { continue }
            let t = SkillCatalog.targeting(for: sk, hero: def)
            out.append(Float(t.range / Balance.unitsPerMeter))
            // キット層: 再使用の段ごとの射程（初めて再使用の照準をした瞬間のメッシュ生成をなくす）
            if HeroKits.hasKit(h.heroID) {
                for stage in 1...3 {
                    let st = HeroKits.targeting(for: sk, hero: def, stage: stage)
                    if st.range != t.range { out.append(Float(st.range / Balance.unitsPerMeter)) }
                }
            }
        }
        for spell in h.spells {
            if let t = HUDSpellAim.targeting(spellID: spell) { out.append(Float(t.range / Balance.unitsPerMeter)) }
        }
        return out
    }

    private func paint(_ c: RGB) {
        let solid = materials.unlit(c, alpha: AimLayer.alphas.solid)
        let soft = materials.unlit(c, alpha: AimLayer.alphas.soft)
        let faint = materials.unlit(c, alpha: AimLayer.alphas.faint)
        solidMaterial = solid
        softMaterial = soft
        fanHalfAngle = 0.79
        ringRadius = -1
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

    /// 扇のメッシュを半角に合わせる（0.01 rad 単位でキャッシュ。従来の cone は π/4）。
    private func useFan(_ halfAngle: Float) {
        let q = (halfAngle * 100).rounded() / 100
        guard abs(q - fanHalfAngle) > 0.004, let soft = softMaterial, let solid = solidMaterial else { return }
        fanHalfAngle = q
        cone.model = meshes.sector(halfAngle: q, outline: false).map { ModelComponent(mesh: $0, materials: [soft]) }
        coneEdge.model = meshes.sector(halfAngle: q, outline: true, thicknessRatio: 0.03)
            .map { ModelComponent(mesh: $0, materials: [solid]) }
    }

    /// 幅つきの帯 + 矢印（直線・突進の経路）。len は矢印の根元までの長さ（m）。
    private func showBand(origin o: SIMD3<Float>, rot: simd_quatf, half: Float, len: Float) {
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
        arrow.scale = [0.75, 1, max(half * 2.4, 0.9)]
    }

    /// キット層の形（AimShapePlan。.legacy 以外）を描く。部品は従来の照準と同じものを使う。
    private func applyShape(_ plan: AimShapePlan, origin o: SIMD3<Float>, target: Vec2, rot: simd_quatf,
                            range: Float, radius: Float, dirLen: Double) {
        switch plan {
        case .legacy:
            break
        case .fan(let halfAngle):
            useFan(halfAngle)
            cone.isEnabled = true
            coneEdge.isEnabled = true
            // 扇の半径は射程（射程が無い形のときは効果半径）
            let r = max(range > 0.3 ? range : radius, 1)
            cone.position = o
            cone.orientation = rot
            cone.scale = [r, 1, r]
            coneEdge.position = o + SIMD3(0, 0.003, 0)
            coneEdge.orientation = rot
            coneEdge.scale = [r, 1, r]
        case .band(let half):
            useFan(.pi / 4)
            showBand(origin: o, rot: rot, half: half, len: max(0.5, range - 0.7))
        case .dash(let half):
            useFan(.pi / 4)
            showBand(origin: o, rot: rot, half: half, len: max(0.5, range - 0.7))
            // 終点の輪（着地点の目安）
            let r = max(half, 0.6)
            targetRing.isEnabled = true
            targetRing.position = o + rot.act(SIMD3<Float>(max(0.5, range), 0.003, 0))
            targetRing.scale = [r, 1, r]
        case .circleAtPoint(let r):
            useFan(.pi / 4)
            let tp = worldPosition(target, height: GroundLayer.aim + 0.005)
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
        case .selfRing(let r):
            useFan(.pi / 4)
            targetFill.isEnabled = true
            targetRing.isEnabled = true
            targetFill.position = o
            targetFill.scale = [r, 1, r]
            targetRing.position = o + SIMD3(0, 0.003, 0)
            targetRing.scale = [r, 1, r]
        case .lockOn:
            useFan(.pi / 4)
            let tp = worldPosition(target, height: GroundLayer.aim + 0.005)
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
        }
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
        let o = worldPosition(origin, height: GroundLayer.aim)
        let range = Float(aim.targeting.range / Balance.unitsPerMeter)
        let radius = Float(aim.targeting.radius / Balance.unitsPerMeter)
        let dirLen = delta.length
        let yaw: Float = dirLen > 1 ? Float(atan2(delta.y, delta.x)) : 0
        let rot = simd_quatf(angle: yaw, axis: [0, 1, 0])

        let hasRange = range > 0.3
        rangeRing.isEnabled = hasRange
        rangeFill.isEnabled = hasRange
        if hasRange {
            let q = AimLayer.rangeRingRadius(range)
            if q != ringRadius, let solid = solidMaterial {
                ringRadius = q
                // 線幅 8 cm 固定（最も遠い画面上端でも 2.5 px 以上）
                rangeRing.model = meshes.ring(radius: q, thickness: AimLayer.rangeRingThickness)
                    .map { ModelComponent(mesh: $0, materials: [solid]) }
            }
            rangeRing.position = o
            rangeRing.scale = [1, 1, 1]
            rangeFill.position = o - SIMD3(0, 0.005, 0)
            rangeFill.scale = [range, 1, range]
        }
        for e in optionalParts { e.isEnabled = false }

        // キット層: shape が .auto 以外なら形を先に決める（合わない組み合わせは .legacy で従来の分岐へ）
        let plan = AimShapePlan.make(aim.targeting)
        if plan != .legacy {
            applyShape(plan, origin: o, target: target, rot: rot, range: range, radius: radius, dirLen: dirLen)
            return
        }
        useFan(.pi / 4)

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
            let tp = worldPosition(target, height: GroundLayer.aim + 0.005)
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
            let tp = worldPosition(target, height: GroundLayer.aim + 0.005)
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
