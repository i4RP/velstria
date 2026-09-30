import Foundation
import RealityKit
import simd
import VelstriaCore

// 担当: battle-renderer。ユニットの見た目（ミニオン・モンスター・人形・ヒーロー）と手続きアニメーション。
// 位置は prevPos → pos を interpolationAlpha で補間し、向きは角速度制限付きで滑らかに追従する。

/// 1 フレーム分の描画入力。
struct RenderFrame {
    var state: SimState
    var alpha: Float
    var dt: Float
    var time: Float
    var viewerTeam: Team?
    var humanID: EntityID?
    /// 戦闘数値・揺れの基準にするヒーロー（観戦では追従中のヒーロー）。
    var focusID: EntityID?
    var ended: Bool
    var winner: Team?

    @inline(__always)
    func interpolated(_ i: Int) -> Vec2 {
        let u = state.units[i]
        return Vec2.lerp(u.prevPos, u.pos, Double(alpha))
    }

    /// 視点チームから見えるか（観戦 = 全可視、構造物は常に可視）。
    func isVisible(_ i: Int) -> Bool {
        guard let viewer = viewerTeam else { return true }
        return state.isVisible(i, to: viewer)
    }
}

/// 角度の補間（最短方向、最大角速度 rate rad/s）。
@inline(__always)
func approachAngle(_ current: Float, _ target: Float, rate: Float, dt: Float) -> Float {
    var d = (target - current).truncatingRemainder(dividingBy: 2 * .pi)
    if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
    let step = rate * dt
    if abs(d) <= step { return target }
    return current + (d > 0 ? step : -step)
}

/// sim の facing → Y 回転角（worldOrientation と同じ規約）。
@inline(__always)
func yawForFacing(_ facing: Double) -> Float { Float(facing - Double.pi / 2) }

// MARK: - 状態表示（気絶・束縛・減速・シールド・帰還）

@MainActor
final class StatusIndicators {
    let root = Entity()
    private var stun: ModelEntity?
    private var rootFX: ModelEntity?
    private var slow: ModelEntity?
    private var bubble: ModelEntity?
    private var recall: ModelEntity?
    private let meshes: UnitMeshLibrary
    private let materials: RenderMaterials
    private let headHeight: Float
    private let size: Float
    private var t: Float = 0

    init(meshes: UnitMeshLibrary, materials: RenderMaterials, headHeight: Float, size: Float) {
        self.meshes = meshes
        self.materials = materials
        self.headHeight = headHeight
        self.size = size
        root.name = "status"
    }

    struct Flags: Equatable {
        var stunned = false
        var rooted = false
        var slowed = false
        var shielded = false
        var recallTeam: Team?
    }

    static func flags(of u: VelstriaCore.Unit) -> Flags {
        var f = Flags()
        for s in u.statuses {
            switch s.kind {
            case .stun, .airborne: f.stunned = true
            case .root: f.rooted = true
            case .slow: f.slowed = true
            default: break
            }
        }
        f.shielded = u.isAlive && !u.shields.isEmpty && u.totalShield > 1
        if let ch = u.hero?.channel { f.recallTeam = ch.kind == .recall ? u.team : .neutral }
        return f
    }

    func update(_ f: Flags, dt: Float) {
        t += dt
        if f.stunned {
            let e = stun ?? make(meshes.stunStars, glow: true, y: headHeight + 0.25, scale: 1)
            stun = e
            e.isEnabled = true
            e.orientation = simd_quatf(angle: t * 4.5, axis: [0, 1, 0])
        } else { stun?.isEnabled = false }
        if f.rooted {
            let e = rootFX ?? make(meshes.rootVines, glow: true, y: 0.02, scale: size)
            rootFX = e
            e.isEnabled = true
            e.scale = SIMD3(repeating: size * (1 + sin(t * 6) * 0.03))
        } else { rootFX?.isEnabled = false }
        if f.slowed {
            let e = slow ?? make(meshes.slowRing, glow: true, y: 0.02, scale: size)
            slow = e
            e.isEnabled = true
            e.orientation = simd_quatf(angle: -t * 1.2, axis: [0, 1, 0])
        } else { slow?.isEnabled = false }
        if f.shielded {
            let e = bubble ?? makeBubble()
            bubble = e
            e.isEnabled = true
            let pulse = 1 + sin(t * 3.2) * 0.025
            e.scale = SIMD3(size * 0.95, headHeight * 0.62, size * 0.95) * pulse
        } else { bubble?.isEnabled = false }
        if let team = f.recallTeam {
            let e = recall ?? makeRecall(team)
            recall = e
            e.isEnabled = true
            e.orientation = simd_quatf(angle: t * 1.6, axis: [0, 1, 0])
            let s = size * (1.25 + sin(t * 5) * 0.04)
            e.scale = [s, 1, s]
        } else { recall?.isEnabled = false }
    }

    private func make(_ mesh: MeshResource?, glow: Bool, y: Float, scale: Float) -> ModelEntity {
        let e = ModelEntity(mesh: mesh ?? meshes.unitSphere, materials: [glow ? materials.glow : materials.lit])
        e.position.y = y
        e.scale = SIMD3(repeating: scale)
        root.addChild(e)
        return e
    }

    private func makeBubble() -> ModelEntity {
        let e = ModelEntity(mesh: meshes.unitSphere, materials: [materials.unlit(RGB(0.72, 0.9, 1.0), alpha: 0.2)])
        e.position.y = headHeight * 0.5
        root.addChild(e)
        return e
    }

    private func makeRecall(_ team: Team) -> ModelEntity {
        let c = team == .neutral ? RGB(0.85, 0.7, 1.0) : materials.teams.light(team)
        let e = ModelEntity(mesh: meshes.ring(radius: 1, thickness: 0.1) ?? meshes.unitSphere,
                            materials: [materials.unlit(c, alpha: 0.9)])
        e.position.y = 0.04
        OverlayOrder.apply(e, OverlayOrder.ring)
        root.addChild(e)
        return e
    }

    func reset() {
        stun?.isEnabled = false
        rootFX?.isEnabled = false
        slow?.isEnabled = false
        bubble?.isEnabled = false
        recall?.isEnabled = false
    }
}

// MARK: - クリーチャー（ミニオン・モンスター・人形）

enum CreatureKey: Hashable {
    case minion(MinionType, Team)
    case monster(MonsterKind)
    case dummy

    init?(_ u: VelstriaCore.Unit) {
        switch u.kind {
        case .minion:
            guard let m = u.minion else { return nil }
            self = .minion(m.type, u.team == .red ? .red : .blue)
        case .monster:
            guard let m = u.monster else { return nil }
            self = .monster(m.kind)
        case .dummy:
            self = .dummy
        default:
            return nil
        }
    }

    var isBoss: Bool {
        if case .monster(let k) = self { return k == .astralWyrm || k == .ancientColossus }
        return false
    }
}

@MainActor
final class CreatureVisual {
    let key: CreatureKey
    let root = Entity()
    /// アニメーションで動かす胴体（root 直下）。
    let body = Entity()
    /// 向き（Y 回転）だけを持つノード。HP バー・状態表示は root 直下で回転させない。
    let yawNode = Entity()
    private var parts: [Entity] = []
    private var partRest: [simd_quatf] = []
    private var segments: [Entity] = []
    let bar: OverheadBar
    let status: StatusIndicators
    let headHeight: Float
    let scale: Float

    var id: EntityID = 0
    var lastSeen = 0
    var visibility: Float = 0
    private var yaw: Float = 0
    private var walkPhase: Float = 0
    private var attackT: Float = 1
    private var hitT: Float = 1
    private var idlePhase: Float = 0
    private(set) var dyingT: Float?
    private var opacityApplied: Float = 1
    private var lastPos = Vec2.zero

    init(key: CreatureKey, meshes: UnitMeshLibrary, materials: RenderMaterials, text: TextMeshCache) {
        self.key = key
        root.name = "creature"
        root.addChild(yawNode)
        yawNode.addChild(body)
        let pm: PartMeshes
        var barColor = RGB(0.95, 0.62, 0.28)
        var barStyle: OverheadBar.Style = .monster(boss: false)
        switch key {
        case .minion(let type, let team):
            pm = meshes.minion(type, team: team)
            scale = 1
            headHeight = type == .siege ? 1.45 : 1.25
            barColor = materials.teams.main(team)
            barStyle = .minion
        case .monster(let kind):
            pm = meshes.monster(kind)
            switch kind {
            case .campSmall: scale = 0.62; headHeight = 0.95
            case .campLarge: scale = 1.05; headHeight = 1.5
            case .blueSentinel, .redSentinel: scale = 1.2; headHeight = 2.95
            case .astralWyrm: scale = 1.2; headHeight = 2.9
            case .ancientColossus: scale = 2.05; headHeight = 5.0
            }
            barStyle = .monster(boss: kind == .astralWyrm || kind == .ancientColossus)
        case .dummy:
            pm = meshes.dummy
            scale = 1
            headHeight = 2.0
            barColor = RGB(0.95, 0.4, 0.4)
            barStyle = .minion
        }
        body.scale = SIMD3(repeating: scale)
        if let m = pm.body { body.addChild(ModelEntity(mesh: m, materials: [materials.lit])) }
        if let m = pm.bodyGlow { body.addChild(ModelEntity(mesh: m, materials: [materials.glow])) }
        if case .monster(.astralWyrm) = key {
            // 頭（body メッシュ）を持ち上げ、胴の節を後ろへ並べる
            for child in body.children {
                child.position = [0, 1.6, -0.8]
                child.scale = SIMD3(repeating: 1.25)
            }
            for k in 0..<10 {
                let seg = Entity()
                if let m = pm.part { seg.addChild(ModelEntity(mesh: m, materials: [materials.lit])) }
                if k % 2 == 0, let m = pm.partGlow { seg.addChild(ModelEntity(mesh: m, materials: [materials.glow])) }
                let r = 0.56 - Float(k) * 0.032
                seg.scale = SIMD3(repeating: r)
                body.addChild(seg)
                segments.append(seg)
            }
        } else if pm.part != nil || pm.partGlow != nil {
            let count = pm.mirrorPart ? 2 : 1
            for k in 0..<count {
                let pivot = Entity()
                var pos = pm.partPivot
                var rest = simd_quatf(angle: 0, axis: [0, 1, 0])
                if k == 1 {
                    pos.x = -pos.x
                    rest = simd_quatf(angle: .pi, axis: [0, 1, 0])
                }
                pivot.position = pos
                pivot.orientation = rest
                if let m = pm.part { pivot.addChild(ModelEntity(mesh: m, materials: [materials.lit])) }
                if let m = pm.partGlow { pivot.addChild(ModelEntity(mesh: m, materials: [materials.glow])) }
                body.addChild(pivot)
                parts.append(pivot)
                partRest.append(rest)
            }
        }
        bar = OverheadBar(style: barStyle, fillColor: barColor, materials: materials, meshes: meshes, text: text)
        bar.root.position.y = headHeight * (key.isBoss ? 1 : 1) + 0.25
        root.addChild(bar.root)
        let footprint: Float
        switch key {
        case .minion(let t, _): footprint = t == .siege ? 0.9 : 0.6
        case .monster(let k): footprint = k == .campSmall ? 0.6 : (k == .ancientColossus ? 2.6 : (k == .astralWyrm ? 2.2 : 1.2))
        case .dummy: footprint = 0.7
        }
        status = StatusIndicators(meshes: meshes, materials: materials, headHeight: headHeight, size: footprint)
        root.addChild(status.root)
    }

    /// プールから取り出して ID に割り当てる。
    func activate(id: EntityID, at p: Vec2, facing: Double) {
        self.id = id
        dyingT = nil
        attackT = 1
        hitT = 1
        walkPhase = 0
        visibility = 0
        opacityApplied = -1
        yaw = yawForFacing(facing)
        lastPos = p
        idlePhase = Float(id % 17) * 0.7
        root.position = worldPosition(p)
        yawNode.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        body.position = .zero
        body.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        bar.root.isEnabled = true
        status.reset()
        root.isEnabled = true
        applyOpacity(0)
    }

    func deactivate() {
        root.isEnabled = false
        root.components.remove(OpacityComponent.self)
        opacityApplied = 1
        dyingT = nil
    }

    func beginAttack() { attackT = 0 }
    func hit() { hitT = 0 }

    func beginDying() {
        guard dyingT == nil else { return }
        dyingT = 0
        bar.root.isEnabled = false
        status.reset()
    }

    /// 生存中の更新。
    func update(_ f: RenderFrame, index i: Int, visible: Bool) {
        let u = f.state.units[i]
        let p = f.interpolated(i)
        let dt = f.dt
        // 可視性のフェード
        let target: Float = visible ? 1 : 0
        visibility += (target - visibility) * min(1, dt * 9)
        if abs(target - visibility) < 0.02 { visibility = target }
        applyOpacity(visibility)
        root.isEnabled = visibility > 0.01
        guard root.isEnabled else {
            lastPos = p
            return
        }
        root.position = worldPosition(p)
        let speed = Float(u.pos.distance(to: u.prevPos) / Balance.dt)
        let moving = speed > 20
        yaw = approachAngle(yaw, yawForFacing(u.facing), rate: 9, dt: dt)
        yawNode.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        lastPos = p
        animate(time: f.time, dt: dt, speed: speed, moving: moving)
        // HP バー
        let maxHP = max(1, u.stats.maxHP)
        bar.update(hp: Float(u.hp / maxHP), shield: Float(u.totalShield / maxHP), resource: nil, level: nil, dt: dt)
        bar.root.isEnabled = u.isAlive
        status.update(StatusIndicators.flags(of: u), dt: dt)
    }

    private func animate(time: Float, dt: Float, speed: Float, moving: Bool) {
        idlePhase += dt
        if moving { walkPhase += dt * (4 + speed / 60) }
        attackT = min(1, attackT + dt / 0.38)
        hitT = min(1, hitT + dt / 0.14)
        let lunge = attackT < 1 ? sin(attackT * .pi) : 0
        var offset = SIMD3<Float>(0, 0, 0)
        var roll: Float = 0
        var pitch: Float = 0
        switch key {
        case .monster(.astralWyrm):
            offset.y = sin(idlePhase * 1.6) * 0.12
            pitch = -lunge * 0.25
            // 首から尾へ弧を描いて下がる胴（うねりは尾ほど大きい）
            let n = Float(max(1, segments.count - 1))
            for (k, seg) in segments.enumerated() {
                let s = Float(k)
                let t = s / n
                let sway = sin(idlePhase * 1.8 - s * 0.7 + walkPhase * 0.4) * (0.15 + t * 0.7)
                let y = 0.35 + 1.05 * (1 - t) * (1 - t * 0.35) + sin(idlePhase * 1.6 - s * 0.6) * 0.09
                seg.position = [sway, y, -0.3 + s * 0.44]
            }
        case .monster(.ancientColossus), .monster(.blueSentinel), .monster(.redSentinel):
            offset.y = moving ? abs(sin(walkPhase)) * 0.06 : sin(idlePhase * 1.2) * 0.02
            roll = moving ? sin(walkPhase) * 0.05 : 0
            for (k, part) in parts.enumerated() {
                // 攻撃: 右腕（交互）を振り下ろす / 歩行: 腕を前後に振る
                let swing: Float
                if lunge > 0 && k == 0 { swing = -lunge * 1.6 } else if moving { swing = sin(walkPhase + Float(k) * .pi) * 0.35 } else {
                    swing = sin(idlePhase * 1.4 + Float(k)) * 0.05
                }
                part.orientation = partRest[k] * simd_quatf(angle: k == 0 ? swing : -swing, axis: [1, 0, 0])
            }
            offset.z = -lunge * 0.25
        case .dummy:
            // 被弾で揺れる
            roll = sin(hitT * .pi * 3) * (1 - hitT) * 0.25
        default:
            offset.y = moving ? abs(sin(walkPhase)) * 0.07 : sin(idlePhase * 2) * 0.015
            roll = moving ? sin(walkPhase) * 0.07 : 0
            offset.z = -lunge * 0.3
            pitch = -lunge * 0.18
            for (k, part) in parts.enumerated() {
                let swing: Float
                switch key {
                case .minion(.siege, _):
                    // 砲身の反動
                    part.position.z = lunge * 0.18
                    swing = -lunge * 0.2
                case .minion(.ranged, _):
                    swing = -lunge * 0.9
                default:
                    swing = -lunge * 1.9 + (moving ? sin(walkPhase) * 0.2 : 0)
                }
                part.orientation = partRest[k] * simd_quatf(angle: swing, axis: [1, 0, 0])
            }
        }
        body.position = offset
        body.orientation = simd_quatf(angle: roll, axis: [0, 0, 1]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        let hitScale: Float = hitT < 1 ? 1 + sin(hitT * .pi) * 0.07 : 1
        body.scale = SIMD3(repeating: scale * hitScale)
    }

    /// 死亡演出（沈み込み + 傾き + フェード）。終了で true。
    func updateDying(dt: Float) -> Bool {
        guard var t = dyingT else { return true }
        t += dt / (key.isBoss ? 1.6 : 0.9)
        dyingT = t
        if t >= 1 { return true }
        let e = t * t
        body.position = [0, -e * headHeight * 0.55, 0]
        body.orientation = simd_quatf(angle: e * 0.9, axis: [0, 0, 1])
        applyOpacity(visibility * (1 - e))
        return false
    }

    private func applyOpacity(_ a: Float) {
        guard abs(a - opacityApplied) > 0.005 else { return }
        opacityApplied = a
        if a >= 0.995 {
            root.components.remove(OpacityComponent.self)
        } else {
            root.components.set(OpacityComponent(opacity: max(0, a)))
        }
    }
}

// MARK: - ヒーロー

@MainActor
final class HeroVisual {
    let id: EntityID
    let team: Team
    let root = Entity()
    let modelRoot = Entity()
    let handle: HeroModelHandle
    let ring: ModelEntity
    let bar: OverheadBar
    let status: StatusIndicators
    private(set) var animState: HeroAnimState = .idle
    private var yaw: Float = 0
    var visibility: Float = 1
    private var opacityApplied: Float = 1
    private var castUntil: Float = -1
    private var castSlot: SkillSlot = .skill1
    private var attackUntil: Float = -1
    private var deadTime: Float = 0
    private var ringPulse: Float = 0
    private var isSelf: Bool
    private var lastResource: Double = -1

    init(unit u: VelstriaCore.Unit, isSelf: Bool, master: MasterData, materials: RenderMaterials, meshes: UnitMeshLibrary,
         text: TextMeshCache) {
        id = u.id
        team = u.team
        self.isSelf = isSelf
        let h = u.hero
        handle = HeroModelFactory.make(heroID: h?.heroID ?? "H001", skinID: h?.skinID, team: u.team, master: master)
        root.name = "hero_\(u.id)"
        root.addChild(modelRoot)
        modelRoot.addChild(handle.root)
        let ringColor = isSelf ? TeamColors.selfColor : materials.teams.main(u.team)
        ring = ModelEntity(mesh: meshes.ring(radius: 0.72, thickness: isSelf ? 0.13 : 0.09) ?? meshes.unitSphere,
                           materials: [materials.unlit(ringColor, alpha: isSelf ? 0.95 : 0.8)])
        ring.position.y = 0.035
        OverlayOrder.apply(ring, OverlayOrder.ring)
        root.addChild(ring)
        let fill = isSelf ? TeamColors.selfColor : materials.teams.main(u.team)
        let resColor = h?.resourceKind == .energy ? RGB(1.0, 0.84, 0.3) : RGB(0.35, 0.62, 1.0)
        bar = OverheadBar(style: .hero(isSelf: isSelf, showResource: isSelf), fillColor: fill, materials: materials,
                          meshes: meshes, text: text, name: h?.displayName, resourceColor: resColor)
        bar.root.position.y = handle.overheadHeight + 0.45
        root.addChild(bar.root)
        status = StatusIndicators(meshes: meshes, materials: materials, headHeight: handle.overheadHeight, size: 0.85)
        root.addChild(status.root)
        yaw = yawForFacing(u.facing)
        root.position = worldPosition(u.pos)
        modelRoot.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    func noteCast(_ slot: SkillSlot, time: Float) {
        castSlot = slot
        castUntil = time + 0.5
    }

    func noteAttack(time: Float) { attackUntil = time + 0.32 }

    func update(_ f: RenderFrame, index i: Int, visible: Bool) {
        let u = f.state.units[i]
        let dt = f.dt
        let dead = u.hero?.isDead == true || !u.isAlive
        // 可視性
        let target: Float = visible ? 1 : 0
        visibility += (target - visibility) * min(1, dt * 9)
        if abs(target - visibility) < 0.02 { visibility = target }
        // 死亡後しばらくして消える
        if dead { deadTime += dt } else { deadTime = 0 }
        let deathFade: Float = dead ? max(0, 1 - max(0, deadTime - 2.2) / 0.6) : 1
        let alpha = visibility * deathFade
        applyOpacity(alpha)
        root.isEnabled = alpha > 0.01
        let p = f.interpolated(i)
        root.position = worldPosition(p)
        let speed = u.pos.distance(to: u.prevPos) / Balance.dt
        if !dead {
            yaw = approachAngle(yaw, yawForFacing(u.facing), rate: 13, dt: dt)
            modelRoot.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        }
        // アニメーション状態
        let state = Self.animState(unit: u, time: f.time, castUntil: castUntil, castSlot: castSlot,
                                   attackUntil: attackUntil, ended: f.ended, winner: f.winner)
        if state != animState {
            animState = state
            handle.setState(state)
        }
        if root.isEnabled {
            handle.update(dt: Double(dt), moveSpeed: dead ? 0 : speed)
        }
        // 足元リング・バー
        ring.isEnabled = !dead
        bar.root.isEnabled = !dead
        if isSelf {
            ringPulse += dt
            let s = 1 + sin(ringPulse * 3) * 0.03
            ring.scale = [s, 1, s]
        }
        if !dead {
            let maxHP = max(1, u.stats.maxHP)
            var res: Float?
            if isSelf, u.stats.maxResource > 0 { res = Float(u.resource / u.stats.maxResource) }
            bar.update(hp: Float(u.hp / maxHP), shield: Float(u.totalShield / maxHP), resource: res,
                       level: u.hero?.level, dt: dt)
            status.update(StatusIndicators.flags(of: u), dt: dt)
        } else {
            status.reset()
        }
    }

    /// sim の状態 → アニメーション状態（優先度: 死亡 > 勝利 > 行動不能 > 詠唱 > スキル > 攻撃 > 移動 > 待機）。
    static func animState(unit u: VelstriaCore.Unit, time: Float, castUntil: Float, castSlot: SkillSlot, attackUntil: Float,
                          ended: Bool, winner: Team?) -> HeroAnimState {
        if u.hero?.isDead == true || !u.isAlive { return .dead }
        if ended, let winner, winner == u.team { return .victory }
        if u.statuses.contains(where: { $0.kind == .stun || $0.kind == .airborne }) { return .stunned }
        if u.hero?.channel != nil { return .channel }
        if time < castUntil { return .cast(castSlot) }
        if u.windupRemaining != nil || time < attackUntil { return .attack }
        if u.displacement != nil || u.pos.distanceSquared(to: u.prevPos) > 1 { return .run }
        return .idle
    }

    private func applyOpacity(_ a: Float) {
        guard abs(a - opacityApplied) > 0.005 else { return }
        opacityApplied = a
        if a >= 0.995 {
            root.components.remove(OpacityComponent.self)
        } else {
            root.components.set(OpacityComponent(opacity: max(0, a)))
        }
    }
}
