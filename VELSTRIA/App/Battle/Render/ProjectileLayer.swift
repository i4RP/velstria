import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。投射物の見た目（visual ID 別）。見た目はスタイル別プールで再利用する。
//   basic_attack: ヒーロー/ミニオンの通常攻撃（チーム色の光弾）
//   tower_shot: タワー/Core の大きな光球（落下軌道）
//   empowered_attack: 強化通常攻撃（金白の大弾 + 軌跡）
//   それ以外: EffectDef（Projectile/Trail は細長い光条、その他は光球）を effect の scale で拡大し、ヒーロー色相で着色

@MainActor
final class ProjectileLayer {
    let root = Entity()
    private let materials: RenderMaterials
    private let meshes: UnitMeshLibrary
    private let master: MasterData
    private var quality: RenderQuality

    enum Style: Hashable {
        case heroBolt(Team)
        case minionBolt(Team)
        case tower(Team)
        case empowered
        /// 色相（0〜1000）と細長いか。
        case skill(hue: Int, streak: Bool)
    }

    @MainActor
    final class Visual {
        let style: Style
        let entity = Entity()
        let core: ModelEntity
        let halo: ModelEntity
        var id: EntityID = 0
        var lastSeen = 0
        var startHeight: Float = 1
        var endHeight: Float = 1
        var startDistance: Double = 1
        var color: RGB
        var baseScale: SIMD3<Float>
        /// スキル弾の演出倍率（EffectDef.scaleM）。同じスタイルでも演出ごとに違うので、プールから出す時に合わせ直す。
        var effectScale: Float = 0
        /// 軌跡を付けるスタイル（塔・強化・スキル弾）。
        var wantsTrail = false
        /// 軌跡の大きさ（光暈の半径 × 0.55）。
        var trailSize: Float = 0
        /// 表示中に借りている軌跡の放出体。
        var trail: Entity?
        var yaw: Float = 0

        init(style: Style, core: ModelEntity, halo: ModelEntity, color: RGB, baseScale: SIMD3<Float>) {
            self.style = style
            self.core = core
            self.halo = halo
            self.color = color
            self.baseScale = baseScale
        }
    }

    private var active: [EntityID: Visual] = [:]
    private var list: [Visual] = []
    private var pools: [Style: [Visual]] = [:]
    private var stamp = 0
    /// 軌跡の放出体を作るか（試合開始時の画質で決める。試合中に画質が下がったら放出だけ止める）。
    private let buildsTrails: Bool
    /// 軌跡の放出体のプール。弾の見た目とは別のエンティティで、表示中の弾の位置へ毎フレーム合わせる。
    /// 付けたままの粒子系は 1 つにつき約 1 MB を常に持つ（シミュレータ実測）ため、弾の見た目ごとには付けず、
    /// 同時に飛ぶ軌跡付きの弾の数だけ持つ。尽きた時はその弾だけ軌跡なし（作らない）。
    private var freeTrails: [Entity] = []
    private var trailsPrewarmed = false
    /// 軌跡の放出体の数（観戦 9 分・4 倍速の headless 計測で同時に飛ぶ軌跡付きの弾の最大は 9）。
    static let trailPoolSize = 16
    /// 軌跡が尽きて省いた回数（計測用）。
    private(set) var trailsSkipped = 0
    private var trailsInUse = 0
    /// 同時に使った軌跡の最大（計測用）。
    private(set) var peakTrails = 0

    init(materials: RenderMaterials, meshes: UnitMeshLibrary, master: MasterData, quality: RenderQuality) {
        self.materials = materials
        self.meshes = meshes
        self.master = master
        self.quality = quality
        buildsTrails = quality.projectileTrails
        root.name = "projectiles"
        list.reserveCapacity(64)
    }

    func apply(quality q: RenderQuality) { quality = q }

    // MARK: 事前生成

    /// スタイルのプールが count 個になるまで作る（無効のまま。軌跡の放出体も構築して付けておく）。
    func prewarm(_ style: Style, visual: String, count: Int) {
        var have = pools[style]?.count ?? 0
        while have < count {
            recycle(make(style, visual: visual))
            have += 1
        }
    }

    /// プールに待機中の数（テスト・計測用）。
    func pooledCount(_ style: Style) -> Int { pools[style]?.count ?? 0 }

    /// 軌跡の放出体を作る（中・高画質。無効のまま部品を付けておく）。
    func prewarmTrails() {
        trailsPrewarmed = true
        guard buildsTrails else { return }
        while freeTrails.count < ProjectileLayer.trailPoolSize { freeTrails.append(makeTrail()) }
    }

    var pooledTrailCount: Int { freeTrails.count }

    private func makeTrail() -> Entity {
        AssetLedger.record(.entity, "projectile trail")
        AssetLedger.record(.emitter, "projectile trail")
        var p = ParticleEmitterComponent()
        p.fieldSimulationSpace = .global
        p.emitterShape = .sphere
        p.emitterShapeSize = SIMD3(repeating: 0.05)
        p.speed = 0.05
        var m = p.mainEmitter
        m.birthRate = Float(quality.particles(70))
        m.lifeSpan = 0.3
        m.size = 0.2
        m.sizeMultiplierAtEndOfLifespan = 0.1
        m.blendMode = .additive
        m.opacityCurve = .linearFadeOut
        m.color = .constant(.single(.white))
        m.isLightingEnabled = false
        p.mainEmitter = m
        p.timing = .repeating(warmUp: nil, emit: .init(duration: 10), idle: nil)
        let e = Entity()
        e.name = "projectileTrail"
        e.components.set(p)
        e.isEnabled = false
        root.addChild(e)
        return e
    }

    /// 表示を始めた弾に軌跡を付ける（色・大きさ・粒子数を書き換えて restart。構築しない）。
    private func attachTrail(_ v: Visual) {
        guard v.wantsTrail, quality.projectileTrails, v.trail == nil else { return }
        let t: Entity
        if let e = freeTrails.popLast() {
            t = e
        } else if !trailsPrewarmed && buildsTrails {
            t = makeTrail()
        } else {
            trailsSkipped += 1
            return
        }
        guard var pe = t.components[ParticleEmitterComponent.self] else { return }
        pe.mainEmitter.color = .constant(.single(v.color.uiColor))
        pe.mainEmitter.size = v.trailSize
        pe.mainEmitter.birthRate = Float(quality.particles(70))
        pe.isEmitting = true
        pe.restart()
        t.position = v.entity.position
        t.components.set(pe)
        t.isEnabled = true
        v.trail = t
        trailsInUse += 1
        peakTrails = max(peakTrails, trailsInUse)
    }

    private func detachTrail(_ v: Visual) {
        guard let t = v.trail else { return }
        v.trail = nil
        trailsInUse -= 1
        if var pe = t.components[ParticleEmitterComponent.self] {
            pe.isEmitting = false
            t.components.set(pe)
        }
        t.isEnabled = false
        freeTrails.append(t)
    }

    /// 試合で出うる投射物の見た目と、同時に必要になりうる数。
    /// 通常攻撃・塔はチーム別、スキル弾は試合のヒーローのスキル定義（SkillCatalog の照準 + EffectDef）から求める。
    /// 数は観戦 8 試合の headless 計測の最大（ヒーロー弾 3・ミニオン弾 18・塔 3・スキル弾 2 / スタイル）に余裕を足した値。
    static func plannedStyles(state: SimState, master: MasterData) -> [(style: Style, visual: String, count: Int)] {
        var out: [(style: Style, visual: String, count: Int)] = []
        for team in Team.players {
            out.append((.heroBolt(team), "basic_attack", 6))
            out.append((.minionBolt(team), "basic_attack", 24))
            out.append((.tower(team), "tower_shot", 5))
        }
        out.append((.empowered, "empowered_attack", 4))
        var seen = Set<Style>()
        for u in state.units where u.kind == .hero {
            guard let h = u.hero, let def = master.hero(h.heroID) else { continue }
            let hue = Int(Theme.heroHue(h.heroID) * 1000)
            for slot in SkillSlot.actives {
                guard let sk = master.skill(hero: h.heroID, slot: slot) else { continue }
                let t = SkillCatalog.targeting(for: sk, hero: def)
                let type = master.effect(sk.effectID)?.effectType
                let streakByType = type == .projectile || type == .trail
                let style: Style
                switch t.archetype {
                case .lineSkillshot: style = .skill(hue: hue, streak: streakByType)
                case .piercingLine: style = .skill(hue: hue, streak: true)
                case .blinkEmpower:
                    // 強化通常攻撃の追加弾（演出 ID が無ければ empowered_attack）
                    if sk.effectID.isEmpty { continue }
                    style = .skill(hue: hue, streak: streakByType)
                default: continue
                }
                guard seen.insert(style).inserted else { continue }
                out.append((style, sk.effectID, 3))
            }
        }
        return out
    }

    // MARK: ウォームアップ（読み込み幕の裏）

    private var warmupShown: [Visual] = []

    /// プールの見た目を全て陳列し、軌跡の放出体も全て一度ずつ動かす（粒子系の初期化を幕の裏で済ませる）。
    func showWarmup(slot: () -> SIMD3<Float>) {
        for style in pools.keys.sorted(by: { "\($0)" < "\($1)" }) {
            guard let l = pools.removeValue(forKey: style) else { continue }
            for v in l {
                v.entity.position = slot()
                v.entity.isEnabled = true
                attachTrail(v)
                warmupShown.append(v)
            }
        }
    }

    /// 陳列した見た目をプールへ戻す。
    func endWarmup() {
        for v in warmupShown { recycle(v) }
        warmupShown.removeAll()
        trailsInUse = 0
        peakTrails = 0
        trailsSkipped = 0
    }

    var count: Int { list.count }

    /// 着弾演出用: 表示中の投射物の位置と色。
    func info(_ id: EntityID) -> (pos: SIMD3<Float>, color: RGB, style: Style)? {
        guard let v = active[id] else { return nil }
        return (v.entity.position, v.color, v.style)
    }

    func style(for p: Projectile, state: SimState) -> Style {
        let owner = state.unit(p.ownerID)
        let team: Team = p.team == .red ? .red : .blue
        switch p.visual {
        case "basic_attack":
            return owner?.kind == .hero ? .heroBolt(team) : .minionBolt(team)
        case "tower_shot":
            return .tower(team)
        case "empowered_attack":
            return .empowered
        default:
            let hue = owner?.hero.map { Theme.heroHue($0.heroID) } ?? 0.55
            let type = master.effect(p.visual)?.effectType
            return .skill(hue: Int(hue * 1000), streak: type == .projectile || type == .trail || p.pierce)
        }
    }

    private func make(_ style: Style, visual: String) -> Visual {
        AssetLedger.record(.entity, "projectile \(style)")
        let color: RGB
        var coreScale: SIMD3<Float>
        var haloScale: Float
        switch style {
        case .heroBolt(let t):
            color = materials.teams.light(t); coreScale = [0.09, 0.09, 0.42]; haloScale = 0.24
        case .minionBolt(let t):
            color = materials.teams.light(t); coreScale = [0.07, 0.07, 0.26]; haloScale = 0.16
        case .tower(let t):
            color = materials.teams.light(t); coreScale = [0.26, 0.26, 0.26]; haloScale = 0.55
        case .empowered:
            color = RGB(1.0, 0.92, 0.62); coreScale = [0.14, 0.14, 0.6]; haloScale = 0.38
        case .skill(let hue, let streak):
            let c = UIColor(hue: CGFloat(hue) / 1000, saturation: 0.6, brightness: 1, alpha: 1)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            color = RGB(Double(r), Double(g), Double(b))
            (coreScale, haloScale) = Self.skillScales(effectScale(visual), streak: streak)
        }
        let core = ModelEntity(mesh: meshes.unitSphere, materials: [materials.unlit(color.mixed(RGB(1, 1, 1), 0.55))])
        core.scale = coreScale
        let halo = ModelEntity(mesh: meshes.unitSphere, materials: [materials.unlit(color, alpha: 0.35)])
        halo.scale = Self.haloScale(haloScale, core: coreScale)
        let v = Visual(style: style, core: core, halo: halo, color: color, baseScale: coreScale)
        if case .skill = style { v.effectScale = effectScale(visual) }
        v.entity.addChild(core)
        v.entity.addChild(halo)
        // 軌跡（中・高画質、目立つ弾のみ。放出体は表示中だけ軌跡のプールから借りる）
        switch style {
        case .tower, .empowered, .skill: v.wantsTrail = buildsTrails
        default: v.wantsTrail = false
        }
        v.trailSize = haloScale * 0.55
        root.addChild(v.entity)
        return v
    }

    /// スキル弾の演出倍率（EffectDef.scaleM。未定義は 1.2）。
    private func effectScale(_ visual: String) -> Float {
        Float(master.effect(visual)?.scaleM ?? 1.2)
    }

    /// スキル弾の芯の拡大率と光暈の半径。
    static func skillScales(_ k: Float, streak: Bool) -> (core: SIMD3<Float>, halo: Float) {
        (streak ? [0.14 * k, 0.14 * k, 0.75 * k] : SIMD3(repeating: 0.22 * k), 0.36 * k)
    }

    private static func haloScale(_ halo: Float, core: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(halo, halo, max(halo, core.z * 0.8))
    }

    private func take(_ style: Style, visual: String) -> Visual {
        if var l = pools[style], let v = l.popLast() {
            pools[style] = l
            // スキル弾はスタイル（色相・細長さ）が同じでも演出ごとに大きさが違う（例: Ranger のスキル 1 と奥義）
            if case .skill(_, let streak) = style {
                let k = effectScale(visual)
                if k != v.effectScale { resize(v, effectScale: k, streak: streak) }
            }
            return v
        }
        return make(style, visual: visual)
    }

    private func resize(_ v: Visual, effectScale k: Float, streak: Bool) {
        let (core, halo) = Self.skillScales(k, streak: streak)
        v.effectScale = k
        v.baseScale = core
        v.core.scale = core
        v.halo.scale = Self.haloScale(halo, core: core)
        v.trailSize = halo * 0.55
        if let t = v.trail, var p = t.components[ParticleEmitterComponent.self] {
            p.mainEmitter.size = v.trailSize
            t.components.set(p)
        }
    }

    /// 表示中の投射物の芯の拡大率（テスト用）。
    func coreScale(of id: EntityID) -> SIMD3<Float>? { active[id]?.core.scale }

    private func recycle(_ v: Visual) {
        v.entity.isEnabled = false
        detachTrail(v)
        pools[v.style, default: []].append(v)
    }

    func sync(_ f: RenderFrame, heightOf: (EntityID) -> Float) {
        stamp &+= 1
        let state = f.state
        for k in state.projectiles.indices {
            let p = state.projectiles[k]
            if p.done { continue }
            // 視点チームから見えない位置の敵弾は描かない
            if let viewer = f.viewerTeam, p.team != viewer, !state.vision.isLit(p.pos, for: viewer) {
                if let v = active.removeValue(forKey: p.id) { detach(v) }
                continue
            }
            let v: Visual
            var isNew = false
            if let existing = active[p.id] {
                v = existing
            } else {
                v = take(style(for: p, state: state), visual: p.visual)
                v.id = p.id
                let owner = state.unit(p.ownerID)
                if let owner, owner.isStructure {
                    v.startHeight = owner.kind == .core ? 3.6 : 4.9
                } else {
                    v.startHeight = owner.map { heightOf($0.id) * 0.6 } ?? 1
                }
                v.endHeight = 1.0
                if case .homing(let tid) = p.motion, let t = state.unit(tid) {
                    v.startDistance = max(1, p.pos.distance(to: t.pos))
                    v.endHeight = t.isStructure ? 1.6 : heightOf(tid) * 0.5
                } else {
                    v.startDistance = 1
                    v.endHeight = v.startHeight
                }
                active[p.id] = v
                list.append(v)
                v.entity.isEnabled = true
                isNew = true
            }
            v.lastSeen = stamp
            let pos = Vec2.lerp(p.prevPos, p.pos, Double(f.alpha))
            var h = v.startHeight
            if case .homing(let tid) = p.motion, let t = state.unit(tid) {
                let remaining = min(1, pos.distance(to: t.pos) / v.startDistance)
                h = v.endHeight + (v.startHeight - v.endHeight) * Float(remaining)
            }
            v.entity.position = worldPosition(pos, height: h)
            let d = p.pos - p.prevPos
            if d.lengthSquared > 1e-6 {
                v.yaw = Float(atan2(d.y, d.x)) - .pi / 2
            }
            v.entity.orientation = simd_quatf(angle: v.yaw, axis: [0, 1, 0])
            // 軌跡は弾の位置に合わせる（試合中に軌跡が切られた間 = 画質の自動調整では付けない）
            if isNew { attachTrail(v) }
            v.trail?.position = v.entity.position
            if case .tower = v.style {
                let s = 1 + sin(f.time * 30 + Float(p.id)) * 0.12
                v.core.scale = v.baseScale * s
            }
        }
        var k = 0
        while k < list.count {
            let v = list[k]
            if v.lastSeen != stamp {
                if active[v.id] === v { active[v.id] = nil }
                list.swapAt(k, list.count - 1)
                list.removeLast()
                recycle(v)
            } else {
                k += 1
            }
        }
    }

    private func detach(_ v: Visual) {
        if let k = list.firstIndex(where: { $0 === v }) {
            list.swapAt(k, list.count - 1)
            list.removeLast()
        }
        recycle(v)
    }

    func teardown() {
        root.removeFromParent()
        active.removeAll()
        list.removeAll()
        pools.removeAll()
    }
}
