import Foundation
import RealityKit
import VelstriaCore

// 担当: battle-renderer。地面ゾーンの予告（円・扇・線の半透明デカール）。
// 予告中は内側の塗りが中心から広がり（delay の進捗）、発動で輪と粒子が弾ける。持続ゾーンは脈動する。
// 色: 味方に有益 = 緑、視点チームのゾーン = 水色、敵 = 赤、中立 = 橙。

@MainActor
final class ZoneLayer {
    let root = Entity()
    private let materials: RenderMaterials
    private let meshes: UnitMeshLibrary

    @MainActor
    final class Visual {
        let node = Entity()
        let fill = ModelEntity()
        let progress = ModelEntity()
        let edge = ModelEntity()
        var id: EntityID = 0
        var lastSeen = 0
        var shapeKey = ""
        var color = RGB(1, 1, 1)
        var fadeOut: Float?
        var triggered = false
        /// 視界外へ出て一時的に隠している（ゾーン自体はまだ残っている）。
        var hidden = false
    }

    private var active: [EntityID: Visual] = [:]
    private var list: [Visual] = []
    private var fading: [Visual] = []
    private var pool: [Visual] = []
    private var stamp = 0
    /// 発動時の演出（world 位置・色・半径）を呼び出し側へ通知する。
    var onTrigger: ((SIMD3<Float>, RGB, Float) -> Void)?

    init(materials: RenderMaterials, meshes: UnitMeshLibrary) {
        self.materials = materials
        self.meshes = meshes
        root.name = "zones"
    }

    var count: Int { list.count + fading.count }

    /// 表示中のゾーンか（視界外で隠している予告は含まない）。
    func isShown(_ id: EntityID) -> Bool { active[id].map { !$0.hidden } ?? false }

    /// ゾーン形状の外接円（sim 座標）。
    static func bounds(of z: AreaZone) -> (center: Vec2, radius: Double) {
        switch z.shape {
        case .circle, .cone:
            return (z.center, z.radius)
        case .line(let direction, let length):
            let half = max(0, length) / 2
            return (z.center + direction.normalized * half, half + z.radius)
        }
    }

    static func color(for z: AreaZone, viewer: Team?, teams: TeamColors) -> RGB {
        if z.payload.affectsAllies && (z.payload.healAmount > 0 || z.payload.shieldAmount > 0) && !z.payload.affectsEnemies {
            return RGB(0.4, 1.0, 0.55)
        }
        if z.payload.healAmount > 0 && z.team == (viewer ?? .blue) { return RGB(0.4, 1.0, 0.55) }
        switch z.team {
        case .neutral: return RGB(1.0, 0.62, 0.25)
        default:
            let ally = z.team == (viewer ?? .blue)
            return ally ? RGB(0.45, 0.85, 1.0) : RGB(1.0, 0.33, 0.30)
        }
    }

    private func take() -> Visual {
        if let v = pool.popLast() { return v }
        AssetLedger.record(.entity, "zone visual")
        let v = Visual()
        v.node.addChild(v.fill)
        v.node.addChild(v.progress)
        v.node.addChild(v.edge)
        OverlayOrder.apply(v.fill, OverlayOrder.zoneFill)
        OverlayOrder.apply(v.progress, OverlayOrder.zoneFill)
        OverlayOrder.apply(v.edge, OverlayOrder.zoneEdge)
        root.addChild(v.node)
        return v
    }

    private func configure(_ v: Visual, zone z: AreaZone, color: RGB) {
        let r = Float(z.radius / Balance.unitsPerMeter)
        let fillMat = materials.unlit(color, alpha: 0.16)
        let progMat = materials.unlit(color, alpha: 0.28)
        let edgeMat = materials.unlit(color, alpha: 0.9)
        v.color = color
        v.fill.position = .zero
        v.progress.position = [0, 0.004, 0]
        v.edge.position = [0, 0.008, 0]
        switch z.shape {
        case .circle:
            v.fill.model = meshes.unitDisc.map { ModelComponent(mesh: $0, materials: [fillMat]) }
            v.progress.model = meshes.unitDisc.map { ModelComponent(mesh: $0, materials: [progMat]) }
            v.edge.model = meshes.ring(radius: r, thickness: 0.1).map { ModelComponent(mesh: $0, materials: [edgeMat]) }
            v.fill.scale = [r, 1, r]
            v.edge.scale = [1, 1, 1]
        case .cone(_, let half):
            let h = Float(half)
            v.fill.model = meshes.sector(halfAngle: h, outline: false).map { ModelComponent(mesh: $0, materials: [fillMat]) }
            v.progress.model = meshes.sector(halfAngle: h, outline: false).map { ModelComponent(mesh: $0, materials: [progMat]) }
            v.edge.model = meshes.sector(halfAngle: h, outline: true, thicknessRatio: min(0.2, 0.1 / max(0.5, r)))
                .map { ModelComponent(mesh: $0, materials: [edgeMat]) }
            v.fill.scale = [r, 1, r]
            v.edge.scale = [r, 1, r]
        case .line(_, let length):
            let l = Float(length / Balance.unitsPerMeter)
            v.fill.model = meshes.groundStrip.map { ModelComponent(mesh: $0, materials: [fillMat]) }
            v.progress.model = meshes.groundStrip.map { ModelComponent(mesh: $0, materials: [progMat]) }
            v.edge.model = meshes.groundStrip.map { ModelComponent(mesh: $0, materials: [edgeMat]) }
            v.fill.scale = [l, 1, r * 2]
            // 縁は先端の横線（進行方向の終端）
            v.edge.position = [l - 0.08, 0.008, 0]
            v.edge.scale = [0.12, 1, r * 2]
        }
    }

    func sync(_ f: RenderFrame) {
        stamp &+= 1
        let state = f.state
        for k in state.zones.indices {
            let z = state.zones[k]
            if let viewer = f.viewerTeam, z.team != viewer, !state.vision.isLit(z.center, for: viewer) {
                // 視界外の敵ゾーン: 表示中なら隠して残す（消えたゾーンと区別し、発動していないのに発動演出を出さない）
                if let v = active[z.id] {
                    v.lastSeen = stamp
                    if !v.hidden {
                        v.hidden = true
                        v.node.isEnabled = false
                    }
                    // 視界外で発動した分は演出なしで済ませる（再び見えても二重に弾けない）
                    if z.triggered { v.triggered = true }
                }
                continue
            }
            let v: Visual
            if let existing = active[z.id] {
                v = existing
                if v.hidden {
                    v.hidden = false
                    v.node.isEnabled = true
                }
            } else {
                v = take()
                v.id = z.id
                v.fadeOut = nil
                v.hidden = false
                v.triggered = z.triggered
                configure(v, zone: z, color: ZoneLayer.color(for: z, viewer: f.viewerTeam, teams: materials.teams))
                v.node.components.remove(OpacityComponent.self)
                v.node.isEnabled = true
                active[z.id] = v
                list.append(v)
            }
            v.lastSeen = stamp
            v.node.position = worldPosition(z.center, height: GroundLayer.zone)
            var yaw: Float = 0
            switch z.shape {
            case .cone(let d, _), .line(let d, _):
                yaw = Float(atan2(d.y, d.x))
            case .circle:
                break
            }
            v.node.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            let r = Float(z.radius / Balance.unitsPerMeter)
            if !z.triggered {
                // 予告の進捗（中心から広がる / 線は根元から伸びる）
                let prog = z.totalDelay > 0 ? Float(1 - max(0, z.delay) / z.totalDelay) : 1
                let e = max(0.02, prog)
                switch z.shape {
                case .circle, .cone:
                    v.progress.scale = [r * e, 1, r * e]
                case .line(_, let length):
                    v.progress.scale = [Float(length / Balance.unitsPerMeter) * e, 1, r * 2]
                }
                v.progress.isEnabled = true
            } else {
                if !v.triggered {
                    v.triggered = true
                    onTrigger?(v.node.position, v.color, r)
                }
                // 持続ゾーン: 塗りを脈動
                v.progress.isEnabled = true
                let pulse = 0.85 + sin(f.time * 6) * 0.15
                switch z.shape {
                case .circle, .cone:
                    v.progress.scale = [r * pulse, 1, r * pulse]
                case .line(_, let length):
                    v.progress.scale = [Float(length / Balance.unitsPerMeter), 1, r * 2 * pulse]
                }
            }
        }
        // 消えたゾーン → 短くフェードアウト（単発ゾーンは発動演出を出してから）
        var k = 0
        while k < list.count {
            let v = list[k]
            if v.lastSeen != stamp {
                if active[v.id] === v { active[v.id] = nil }
                list.swapAt(k, list.count - 1)
                list.removeLast()
                if v.hidden {
                    // 視界外のまま消えた（見えない所で発動・終了した）: 演出を出さずに回収
                    v.hidden = false
                    v.node.isEnabled = false
                    pool.append(v)
                    continue
                }
                if !v.triggered {
                    v.triggered = true
                    onTrigger?(v.node.position, v.color, Float(v.fill.scale.x))
                }
                v.fadeOut = 0
                fading.append(v)
            } else {
                k += 1
            }
        }
        k = 0
        while k < fading.count {
            let v = fading[k]
            let t = (v.fadeOut ?? 1) + f.dt / 0.25
            v.fadeOut = t
            if t >= 1 {
                v.node.isEnabled = false
                v.node.components.remove(OpacityComponent.self)
                fading.swapAt(k, fading.count - 1)
                fading.removeLast()
                pool.append(v)
            } else {
                v.node.components.set(OpacityComponent(opacity: 1 - t))
                k += 1
            }
        }
    }

    func teardown() {
        root.removeFromParent()
        active.removeAll()
        list.removeAll()
        fading.removeAll()
        pool.removeAll()
    }
}
