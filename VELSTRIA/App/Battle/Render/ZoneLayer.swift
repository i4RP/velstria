import Foundation
import RealityKit
import VelstriaCore

// 担当: battle-renderer。地面ゾーンの予告（円・扇・線の半透明デカール）。
// 予告中は内側の塗りが中心から広がり（delay の進捗）、発動で輪と粒子が弾ける。持続ゾーンは脈動する。
// 色: 味方に有益 = 緑、視点チームのゾーン = 水色、敵 = 赤、中立 = 橙。
// 観戦の全体視点（視点チームなし）はどちらの味方でもないので、チーム色（色覚配慮の配色に従う）で塗る。
// 観戦者が視点チームを切り替えたら、表示中のゾーンも塗り直す。

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
    /// 表示中のゾーンを塗った視点チーム（切り替わったら塗り直す）。
    private var colorViewer: Team?
    private var hasColorViewer = false
    /// 発動時の演出（world 位置・色・半径）を呼び出し側へ通知する。
    var onTrigger: ((EntityID, SIMD3<Float>, RGB, Float) -> Void)?

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

    static let healColor = RGB(0.4, 1.0, 0.55)
    static let allyColor = RGB(0.45, 0.85, 1.0)
    static let enemyColor = RGB(1.0, 0.33, 0.30)
    static let neutralColor = RGB(1.0, 0.62, 0.25)
    /// ゾーンの色の全て（マテリアルの事前生成に使う）。
    static let colors = [healColor, allyColor, enemyColor, neutralColor]
    /// 塗り・予告の進捗・縁の不透明度。
    static let alphas = (fill: 0.16, progress: 0.28, edge: 0.9)
    /// 円ゾーンの縁の太さ（m）。
    static let edgeThickness: Float = 0.1

    static func color(for z: AreaZone, viewer: Team?, teams: TeamColors) -> RGB {
        if z.payload.affectsAllies && (z.payload.healAmount > 0 || z.payload.shieldAmount > 0) && !z.payload.affectsEnemies {
            return healColor
        }
        guard let viewer else {
            // 観戦の全体視点: 味方・敵の区別をせず、どちらのチームのゾーンも同じ規則（チーム色）で塗る
            return z.team == .neutral ? neutralColor : spectatorColor(z.team, teams: teams)
        }
        if z.payload.healAmount > 0 && z.team == viewer { return healColor }
        switch z.team {
        case .neutral: return neutralColor
        default:
            return z.team == viewer ? allyColor : enemyColor
        }
    }

    /// 観戦の全体視点でのチームのゾーン色（チームの明色。色覚配慮の配色では青・橙）。
    static func spectatorColor(_ team: Team, teams: TeamColors) -> RGB { teams.light(team) }

    /// 観戦の全体視点で使うゾーン色（マテリアルの事前生成に使う）。
    static func spectatorColors(teams: TeamColors) -> [RGB] { Team.players.map { spectatorColor($0, teams: teams) } }

    /// 試合のヒーローのスキルが作るゾーンの半径（m）。SkillArchetypes で ZoneSystem.spawn する型だけ（いずれも円）。
    static func plannedRadii(state: SimState, master: MasterData) -> [Float] {
        var out = Set<Int>()
        for u in state.units where u.kind == .hero {
            guard let h = u.hero, let def = master.hero(h.heroID) else { continue }
            for slot in SkillSlot.actives {
                guard let sk = master.skill(hero: h.heroID, slot: slot) else { continue }
                let t = SkillCatalog.targeting(for: sk, hero: def)
                switch t.archetype {
                case .dashStrike, .groundAoE, .healZone, .leapSlam, .multiStrike:
                    // UnitMeshLibrary.ring と同じ 0.05 m 単位
                    out.insert(Int((Float(t.radius / Balance.unitsPerMeter) * 20).rounded()))
                default:
                    continue
                }
            }
        }
        return out.sorted().map { Float($0) / 20 }
    }

    /// ゾーンの見た目のプールが count 個になるまで作り、円の縁のメッシュを radii の半径ぶん作る。
    func prewarm(count: Int, radii: [Float]) {
        while pool.count < count { pool.append(makeVisual()) }
        _ = meshes.unitDisc
        _ = meshes.groundStrip
        for r in radii { _ = meshes.ring(radius: r, thickness: ZoneLayer.edgeThickness) }
        for c in ZoneLayer.colors + ZoneLayer.spectatorColors(teams: materials.teams) {
            _ = materials.unlit(c, alpha: ZoneLayer.alphas.fill)
            _ = materials.unlit(c, alpha: ZoneLayer.alphas.progress)
            _ = materials.unlit(c, alpha: ZoneLayer.alphas.edge)
        }
    }

    /// プールに待機中の数（テスト用）。
    var pooledCount: Int { pool.count }

    /// presentationEpoch の変化（シーク・再同期）: 表示中・フェード中の予告を発動演出なしで全てプールへ戻す。
    /// 次の sync で今の状態のゾーンだけを出し直す（発動済みのものは発動済みとして作るので、二重に弾けない）。
    func resetForPresentationEpoch() {
        for v in list + fading {
            v.node.isEnabled = false
            v.node.components.remove(OpacityComponent.self)
            v.hidden = false
            v.fadeOut = nil
            pool.append(v)
        }
        list.removeAll(keepingCapacity: true)
        fading.removeAll(keepingCapacity: true)
        active.removeAll(keepingCapacity: true)
    }

    // MARK: ウォームアップ（読み込み幕の裏）

    private var warmupShown: [Visual] = []

    /// プールの見た目を全て陳列する（色・半径を巡回。半分はフェード中の半透明）。
    func showWarmup(radii: [Float], slot: () -> SIMD3<Float>) {
        let rs = radii.isEmpty ? [1] : radii
        for (k, v) in pool.enumerated() {
            let c = ZoneLayer.colors[k % ZoneLayer.colors.count]
            configureCircle(v, radius: rs[k % rs.count], color: c)
            v.progress.scale = [rs[k % rs.count] * 0.6, 1, rs[k % rs.count] * 0.6]
            v.node.position = slot()
            v.node.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            if k % 2 == 1 { v.node.components.set(OpacityComponent(opacity: 0.5)) }
            v.node.isEnabled = true
            warmupShown.append(v)
        }
        pool.removeAll()
    }

    /// 陳列した見た目をプールへ戻す。
    func endWarmup() {
        for v in warmupShown {
            v.node.isEnabled = false
            v.node.components.remove(OpacityComponent.self)
            pool.append(v)
        }
        warmupShown.removeAll()
    }

    private func take() -> Visual {
        if let v = pool.popLast() { return v }
        return makeVisual()
    }

    private func makeVisual() -> Visual {
        AssetLedger.record(.entity, "zone visual")
        let v = Visual()
        v.node.addChild(v.fill)
        v.node.addChild(v.progress)
        v.node.addChild(v.edge)
        OverlayOrder.apply(v.fill, OverlayOrder.zoneFill)
        OverlayOrder.apply(v.progress, OverlayOrder.zoneFill)
        OverlayOrder.apply(v.edge, OverlayOrder.zoneEdge)
        v.node.isEnabled = false
        root.addChild(v.node)
        return v
    }

    private func configureCircle(_ v: Visual, radius r: Float, color: RGB) {
        let fillMat = materials.unlit(color, alpha: ZoneLayer.alphas.fill)
        let progMat = materials.unlit(color, alpha: ZoneLayer.alphas.progress)
        let edgeMat = materials.unlit(color, alpha: ZoneLayer.alphas.edge)
        v.color = color
        v.fill.position = .zero
        v.progress.position = [0, 0.004, 0]
        v.edge.position = [0, 0.008, 0]
        v.fill.model = meshes.unitDisc.map { ModelComponent(mesh: $0, materials: [fillMat]) }
        v.progress.model = meshes.unitDisc.map { ModelComponent(mesh: $0, materials: [progMat]) }
        v.edge.model = meshes.ring(radius: r, thickness: ZoneLayer.edgeThickness).map { ModelComponent(mesh: $0, materials: [edgeMat]) }
        v.fill.scale = [r, 1, r]
        v.edge.scale = [1, 1, 1]
    }

    private func configure(_ v: Visual, zone z: AreaZone, color: RGB) {
        let r = Float(z.radius / Balance.unitsPerMeter)
        let fillMat = materials.unlit(color, alpha: ZoneLayer.alphas.fill)
        let progMat = materials.unlit(color, alpha: ZoneLayer.alphas.progress)
        let edgeMat = materials.unlit(color, alpha: ZoneLayer.alphas.edge)
        v.color = color
        v.fill.position = .zero
        v.progress.position = [0, 0.004, 0]
        v.edge.position = [0, 0.008, 0]
        switch z.shape {
        case .circle:
            configureCircle(v, radius: r, color: color)
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
        if !hasColorViewer || colorViewer != f.viewerTeam {
            // 観戦者が視点チームを切り替えた: 表示中のゾーンを新しい視点の色へ塗り直す
            hasColorViewer = true
            colorViewer = f.viewerTeam
            for k in state.zones.indices {
                guard let v = active[state.zones[k].id] else { continue }
                recolor(v, color: ZoneLayer.color(for: state.zones[k], viewer: f.viewerTeam, teams: materials.teams))
            }
        }
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
                    onTrigger?(v.id, v.node.position, v.color, r)
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
                    onTrigger?(v.id, v.node.position, v.color, Float(v.fill.scale.x))
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

    /// 形はそのままで色だけ差し替える（マテリアルは事前生成済みのものを使う）。
    private func recolor(_ v: Visual, color: RGB) {
        guard v.color != color else { return }
        v.color = color
        v.fill.model?.materials = [materials.unlit(color, alpha: ZoneLayer.alphas.fill)]
        v.progress.model?.materials = [materials.unlit(color, alpha: ZoneLayer.alphas.progress)]
        v.edge.model?.materials = [materials.unlit(color, alpha: ZoneLayer.alphas.edge)]
    }

    /// 表示中のゾーンの色（テスト用）。
    func displayedColor(_ id: EntityID) -> RGB? { active[id]?.color }

    func teardown() {
        root.removeFromParent()
        active.removeAll()
        list.removeAll()
        fading.removeAll()
        pool.removeAll()
    }
}
