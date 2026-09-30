import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。読み込み完了後の描画世界（各レイヤーの所有者）と SimEvent → 演出の振り分け。

@MainActor
final class BattleWorld {
    let root = Entity()
    let controller: BattleController
    private(set) var settings: RenderSettings
    let materials: RenderMaterials
    let meshes = UnitMeshLibrary()
    let text = TextMeshCache()
    let map: MapScene
    let units: UnitLayer
    let projectiles: ProjectileLayer
    let zones: ZoneLayer
    let vfx: VFXSystem
    let aim: AimLayer
    let fog: FogOfWar?
    private weak var arView: ARView?
    private weak var overlay: CombatTextOverlay?
    private var time: Float = 0
    private var textSeed = 0
    private var lastHealFX: [EntityID: Float] = [:]
    private var pendingHeal: Double = 0
    private var pendingHealTimer: Float = 0
    private var shakeRequest: Float = 0
    private let master: MasterData

    init(controller: BattleController, settings: RenderSettings, groundImage: CGImage?, arView: ARView,
         overlay: CombatTextOverlay) {
        self.controller = controller
        self.settings = settings
        self.arView = arView
        self.overlay = overlay
        master = controller.ctx.master
        root.name = "world"
        materials = RenderMaterials(colorblind: settings.colorblind)
        map = MapScene(map: controller.ctx.map, materials: materials, quality: settings.quality, groundImage: groundImage)
        root.addChild(map.root)
        units = UnitLayer(materials: materials, meshes: meshes, text: text, master: controller.ctx.master)
        root.addChild(units.root)
        projectiles = ProjectileLayer(materials: materials, meshes: meshes, master: controller.ctx.master, quality: settings.quality)
        root.addChild(projectiles.root)
        zones = ZoneLayer(materials: materials, meshes: meshes)
        root.addChild(zones.root)
        vfx = VFXSystem(quality: settings.quality, materials: materials, meshes: meshes)
        root.addChild(vfx.root)
        aim = AimLayer(materials: materials, meshes: meshes)
        root.addChild(aim.root)
        if let viewer = controller.viewerTeam {
            fog = FogOfWar(team: viewer, size: settings.quality.fogTextureSize)
            if let fog { root.addChild(fog.entity) }
        } else {
            fog = nil
        }
        units.prewarm()
        zones.onTrigger = { [weak self] pos, color, radius in
            guard let self else { return }
            self.vfx.ring(at: pos, color: color, from: max(0.3, radius * 0.4), to: radius * 1.1, duration: 0.45)
            self.vfx.spawn(.areaBlast, at: pos, color: color.uiColor, scale: radius, important: true)
        }
    }

    var liveEntityCount: Int { units.liveCount + projectiles.count + zones.count + vfx.activeCount }

    private func makeFrame(dt: Float) -> RenderFrame {
        let state = controller.state
        var focus = controller.humanHeroID
        if focus == nil, case .followUnit(let id) = controller.cameraMode { focus = id }
        return RenderFrame(state: state, alpha: Float(controller.interpolationAlpha), dt: dt, time: time,
                           viewerTeam: controller.viewerTeam, humanID: controller.humanHeroID, focusID: focus,
                           ended: state.phase == .ended, winner: state.winner)
    }

    // MARK: 毎フレーム

    func sync(events: [SimEvent], dt: Float, rig: CameraRig) {
        time += dt
        let frame = makeFrame(dt: dt)
        for e in events { handle(e, frame: frame) }
        if shakeRequest > 0 {
            rig.addShake(shakeRequest)
            shakeRequest = 0
        }
        map.update(dt: dt)
        units.sync(frame)
        projectiles.sync(frame) { [units] id in units.headHeight(id) }
        zones.sync(frame)
        vfx.update(dt: dt)
        // 詠唱ループを本人に追従
        for i in frame.state.units.indices where frame.state.units[i].kind == .hero && frame.state.units[i].hero?.channel != nil {
            let id = frame.state.units[i].id
            if vfx.hasLoop(id), let p = units.worldPositionOf(id) { vfx.moveLoop(id: id, to: p) }
        }
        // 照準
        var aimOrigin: Vec2?
        if let id = controller.humanHeroID, let p = units.worldPositionOf(id) {
            aimOrigin = Vec2(Double(p.x) * Balance.unitsPerMeter, Double(-p.z) * Balance.unitsPerMeter)
        }
        aim.update(controller.aim, origin: aimOrigin, dt: dt)
        // 草むら（視点ヒーローが入っている草むらを半透明に）
        if let hi = frame.state.humanHeroIndex, frame.viewerTeam != nil {
            map.setTranslucentBrush(frame.state.units[hi].brushIndex)
        } else {
            map.setTranslucentBrush(nil)
        }
        fog?.update(state: frame.state, dt: dt)
        flushHealText(dt: dt, frame: frame)
    }

    func updateOverlay(dt: Float) {
        guard let overlay, let arView else { return }
        overlay.update(dt: dt) { p in arView.project(p) }
    }

    // MARK: イベント → 演出

    private func isShown(_ id: EntityID, _ f: RenderFrame) -> Bool {
        if let i = f.state.index(of: id) { return f.isVisible(i) }
        if let c = units.creature(id) { return c.visibility > 0.3 }
        return false
    }

    private func anchor(_ id: EntityID, heightRatio: Float = 0.55) -> SIMD3<Float>? {
        guard let p = units.worldPositionOf(id) else { return nil }
        return p + SIMD3(0, units.headHeight(id) * heightRatio, 0)
    }

    private func nearCamera(_ p: SIMD3<Float>) -> Bool {
        guard let arView else { return true }
        let c = arView.cameraTransform.translation
        let dx = p.x - c.x, dz = p.z - (c.z - 7)
        return dx * dx + dz * dz < 24 * 24
    }

    private func heroColor(_ id: EntityID?, _ f: RenderFrame) -> UIColor {
        if let id, let u = f.state.unit(id), let h = u.hero {
            return UIColor(hue: CGFloat(Theme.heroHue(h.heroID)), saturation: 0.62, brightness: 1, alpha: 1)
        }
        return UIColor(red: 0.7, green: 0.85, blue: 1, alpha: 1)
    }

    private func teamColor(_ id: EntityID?, _ f: RenderFrame) -> UIColor {
        guard let id, let u = f.state.unit(id) else { return UIColor(white: 1, alpha: 1) }
        if u.team == .neutral { return UIColor(red: 1, green: 0.7, blue: 0.35, alpha: 1) }
        return materials.teams.light(u.team).uiColor
    }

    private func spawnText(_ s: String, at p: SIMD3<Float>, style: CombatTextStyle) {
        guard settings.showDamageNumbers, let overlay else { return }
        textSeed &+= 1
        overlay.spawn(text: s, world: p, style: style, seed: textSeed)
    }

    private func handle(_ e: SimEvent, frame f: RenderFrame) {
        switch e {
        case .attackStarted(let src, _):
            units.noteAttack(sourceID: src, time: time)
        case .attackReleased(let src, _, _):
            units.noteAttack(sourceID: src, time: time)
        case .damage(let d):
            units.noteHit(targetID: d.targetID)
            onDamage(d, f)
        case .heal(let target, let source, let amount):
            onHeal(target: target, source: source, amount: amount, f)
        case .shieldGained(let target, _, let amount):
            guard isShown(target, f), let p = anchor(target, heightRatio: 0.5) else { break }
            vfx.spawn(.shield, at: p, color: UIColor(red: 0.8, green: 0.92, blue: 1, alpha: 1), important: target == f.focusID)
            if target == f.focusID { spawnText(CombatTextFormat.plus(amount), at: p + SIMD3(0, 1.2, 0), style: .shield) }
        case .projectileHit(let pid, let tid, let pos):
            let info = projectiles.info(pid)
            let p = info?.pos ?? worldPosition(pos, height: 1)
            guard nearCamera(p) else { break }
            if let info {
                switch info.style {
                case .tower:
                    vfx.spawn(.magicHit, at: p, color: info.color.uiColor, scale: 1.4, important: tid == f.focusID)
                    vfx.flash(at: p, color: info.color, radius: 0.7, duration: 0.2)
                case .skill:
                    vfx.spawn(.magicHit, at: p, color: info.color.uiColor, scale: 1.2, important: true)
                case .empowered:
                    vfx.spawn(.crit, at: p, color: info.color.uiColor, scale: 1.1, important: true)
                default:
                    break
                }
            }
        case .skillCast(let c):
            units.noteCast(heroID: c.casterID, slot: c.slot, time: time)
            if isShown(c.casterID, f) { skillFX(c, f) }
        case .spellCast(let caster, let spell, _, let target):
            if isShown(caster, f) { spellFX(caster: caster, spell: spell, target: target, f) }
        case .displaced(let id, let kind, let from, let to, _):
            guard isShown(id, f) else { break }
            let a = worldPosition(from, height: 0.9), b = worldPosition(to, height: 0.9)
            let d = b - a
            let len = simd_length(d)
            if len > 0.5, kind != .knockback {
                vfx.spawn(.trail, at: (a + b) / 2, color: teamColor(id, f), scale: len / 2, important: false, direction: d)
            }
        case .blinked(let id, let from, let to):
            guard isShown(id, f) else { break }
            vfx.spawn(.blink, at: worldPosition(from, height: 0.9), color: heroColor(id, f), important: true)
            vfx.spawn(.blink, at: worldPosition(to, height: 0.9), color: heroColor(id, f), important: true)
        case .unitDied(let id, let kind, let team, _, let pos):
            guard kind == .minion || kind == .monster || kind == .dummy, isShown(id, f) else { break }
            let p = worldPosition(pos, height: 0.6)
            guard nearCamera(p) else { break }
            let c = team == .neutral ? UIColor(red: 0.8, green: 0.7, blue: 1.0, alpha: 1) : materials.teams.light(team).uiColor
            vfx.spawn(.death, at: p, color: c, scale: kind == .monster ? 1.6 : 1)
        case .heroKilled(let k):
            guard let p = anchor(k.victimID, heightRatio: 0.5) else { break }
            vfx.spawn(.heroDeath, at: p, color: teamColor(k.victimID, f), important: true)
            vfx.ring(at: SIMD3(p.x, 0, p.z), color: RGB(0.9, 0.9, 1.0), from: 0.4, to: 2.4, duration: 0.6)
            if k.victimID == f.focusID { shakeRequest = max(shakeRequest, 0.25) }
        case .goldGained(let heroID, let amount, let pos):
            guard heroID == f.focusID, amount >= 1 else { break }
            let p = worldPosition(pos, height: 1.2)
            vfx.spawn(.gold, at: p, color: .yellow, important: true)
            spawnText(CombatTextFormat.plus(amount), at: p + SIMD3(0, 0.4, 0), style: .gold)
        case .levelUp(let heroID, _):
            guard isShown(heroID, f), let base = units.worldPositionOf(heroID) else { break }
            vfx.spawn(.levelUp, at: base + SIMD3(0, 0.1, 0), color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), important: true)
            vfx.ring(at: base, color: RGB(1, 0.86, 0.45), from: 0.3, to: 1.8, duration: 0.7)
        case .structureDestroyed(let id, let kind, let team, _, _, _):
            guard let base = units.worldPositionOf(id) else { break }
            let top = base + SIMD3(0, kind == .core ? 3.6 : 4.6, 0)
            vfx.spawn(.towerExplosion, at: top, color: materials.teams.light(team).uiColor, scale: kind == .core ? 1.6 : 1,
                      important: true)
            vfx.spawn(.death, at: base + SIMD3(0, 1, 0), color: UIColor(white: 0.55, alpha: 1), scale: 3, important: true)
            vfx.flash(at: top, color: materials.teams.light(team), radius: kind == .core ? 4.5 : 3, duration: 0.45, alpha: 0.7)
            vfx.ring(at: base, color: materials.teams.light(team), from: 1, to: kind == .core ? 12 : 8, duration: 0.8)
            if let focus = f.focusID, let fp = units.worldPositionOf(focus), simd_distance(fp, base) < 20 {
                shakeRequest = max(shakeRequest, kind == .core ? 0.8 : 0.55)
            }
        case .respawned(let heroID, let pos):
            let p = worldPosition(pos)
            guard f.viewerTeam == nil || f.state.unit(heroID)?.team == f.viewerTeam else { break }
            vfx.spawn(.respawn, at: p + SIMD3(0, 0.1, 0), color: teamColor(heroID, f), important: true)
            vfx.ring(at: p, color: materials.teams.light(f.state.unit(heroID)?.team ?? .blue), from: 2, to: 0.4, duration: 0.6)
        case .channelStarted(let heroID, let kind, _):
            guard isShown(heroID, f), let p = units.worldPositionOf(heroID) else { break }
            let c: UIColor = kind == .recall ? teamColor(heroID, f) : UIColor(red: 0.85, green: 0.7, blue: 1, alpha: 1)
            vfx.startLoop(id: heroID, at: p, color: c)
        case .channelCanceled(let heroID, _):
            vfx.stopLoop(id: heroID)
        case .channelCompleted(let heroID, _, let dest):
            vfx.stopLoop(id: heroID)
            if f.viewerTeam == nil || f.state.unit(heroID)?.team == f.viewerTeam {
                vfx.spawn(.blink, at: worldPosition(dest, height: 0.9), color: teamColor(heroID, f), important: true)
            }
        default:
            break
        }
    }

    private func onDamage(_ d: DamageEvent, _ f: RenderFrame) {
        guard d.amount > 0, isShown(d.targetID, f), let p = anchor(d.targetID) else { return }
        let involvesFocus = d.sourceID == f.focusID || d.targetID == f.focusID
        if involvesFocus || nearCamera(p) {
            if d.isCrit {
                vfx.spawn(.crit, at: p, color: UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 1), important: involvesFocus)
            } else {
                switch d.source {
                case .skill, .spell:
                    vfx.spawn(.magicHit, at: p, color: heroColor(d.sourceID, f), important: involvesFocus)
                case .basicAttack, .minion, .monster, .tower:
                    let src = d.sourceID.flatMap { f.state.unit($0) }
                    // ミニオン同士の小競り合いは控えめに
                    let minor = src?.kind == .minion && f.state.unit(d.targetID)?.kind == .minion
                    if !minor || settings.quality.level == .high {
                        let c: UIColor
                        switch d.damageType {
                        case .physical: c = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
                        case .magic: c = UIColor(red: 0.75, green: 0.6, blue: 1, alpha: 1)
                        case .trueDamage: c = .white
                        }
                        vfx.spawn(.hitSpark, at: p, color: c, scale: minor ? 0.7 : 1, count: minor ? 5 : nil, important: involvesFocus)
                    }
                default:
                    break
                }
            }
        }
        // 戦闘数値
        if d.sourceID == f.focusID, d.targetID != f.focusID {
            spawnText(CombatTextFormat.damage(d.amount, crit: d.isCrit), at: p + SIMD3(0, 0.6, 0),
                      style: .dealt(d.damageType, crit: d.isCrit))
        } else if d.targetID == f.focusID, d.source != .fountain || d.amount >= 1 {
            spawnText(CombatTextFormat.damage(d.amount, crit: false), at: p + SIMD3(0, 0.8, 0), style: .taken)
            if case .skill(.ultimate) = d.source { shakeRequest = max(shakeRequest, 0.45) }
        }
    }

    private func onHeal(target: EntityID, source: EntityID?, amount: Double, _ f: RenderFrame) {
        guard isShown(target, f) else { return }
        if target == f.focusID { pendingHeal += amount }
        guard amount >= 25, let p = units.worldPositionOf(target) else { return }
        if let last = lastHealFX[target], time - last < 0.5 { return }
        lastHealFX[target] = time
        vfx.spawn(.heal, at: p + SIMD3(0, 0.2, 0), color: UIColor(red: 0.45, green: 1, blue: 0.55, alpha: 1),
                  important: target == f.focusID)
    }

    /// 小さな回復（吸収など）はまとめて表示する。
    private func flushHealText(dt: Float, frame f: RenderFrame) {
        pendingHealTimer += dt
        guard pendingHealTimer >= 0.35 else { return }
        pendingHealTimer = 0
        guard pendingHeal >= 5, let focus = f.focusID, let p = anchor(focus, heightRatio: 1) else {
            pendingHeal = 0
            return
        }
        spawnText(CombatTextFormat.plus(pendingHeal), at: p + SIMD3(0.3, 0.3, 0), style: .heal)
        pendingHeal = 0
    }

    private func skillFX(_ c: SkillCastEvent, _ f: RenderFrame) {
        let color = UIColor(hue: CGFloat(Theme.heroHue(c.heroID)), saturation: 0.62, brightness: 1, alpha: 1)
        let effect = master.effect(c.effectID)
        let scale = Float(effect?.scaleM ?? 1.2)
        let origin = units.worldPositionOf(c.casterID) ?? worldPosition(c.origin)
        let target = worldPosition(c.target)
        let radius = Float(c.radius / Balance.unitsPerMeter)
        let dir = target - origin
        let len = simd_length(dir)
        var ringColor = RGB(0.8, 0.9, 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) { ringColor = RGB(Double(r), Double(g), Double(b)) }
        // アーキタイプ別の主演出
        switch c.archetype {
        case .cone:
            let mid = origin + (len > 0.1 ? simd_normalize(dir) * min(len, radius) * 0.5 : .zero) + SIMD3(0, 0.9, 0)
            vfx.spawn(.skillBurst, at: mid, color: color, scale: scale, important: true)
        case .dashStrike, .leapSlam:
            if len > 0.5 {
                vfx.spawn(.trail, at: (origin + target) / 2 + SIMD3(0, 0.9, 0), color: color, scale: len / 2, important: true,
                          direction: dir)
            }
            vfx.ring(at: target, color: ringColor, from: 0.3, to: max(1, radius), duration: 0.45)
            vfx.spawn(.areaBlast, at: target, color: color, scale: max(0.8, radius), important: true)
        case .blinkEmpower, .targetedBlink:
            vfx.spawn(.blink, at: origin + SIMD3(0, 0.9, 0), color: color, important: true)
        case .selfAoE, .teamHeal, .multiStrike:
            vfx.ring(at: origin, color: ringColor, from: 0.4, to: max(1.2, radius), duration: 0.5)
            vfx.spawn(.areaBlast, at: origin, color: color, scale: max(0.8, radius), important: true)
        case .lineSkillshot, .piercingLine:
            let muzzle = origin + (len > 0.1 ? simd_normalize(dir) * 0.8 : .zero) + SIMD3(0, 1.1, 0)
            vfx.spawn(.skillBurst, at: muzzle, color: color, scale: 0.6, important: true)
        case .groundAoE, .healZone, .passive:
            vfx.spawn(.magicHit, at: origin + SIMD3(0, 1.4, 0), color: color, scale: 0.8, important: false)
        }
        // 演出種別（EffectDef）による追加
        switch effect?.effectType {
        case .shield:
            vfx.spawn(.shield, at: origin + SIMD3(0, 0.9, 0), color: color, scale: max(1, scale * 0.7), important: true)
        case .burst:
            if c.archetype != .cone {
                vfx.spawn(.skillBurst, at: target + SIMD3(0, 0.8, 0), color: color, scale: scale * 0.7, important: false)
            }
        default:
            break
        }
    }

    private func spellFX(caster: EntityID, spell: String, target: Vec2, _ f: RenderFrame) {
        guard let p = units.worldPositionOf(caster) else { return }
        let tp = worldPosition(target, height: 0.9)
        switch spell {
        case "BS02":
            vfx.spawn(.skillBurst, at: p + SIMD3(0, 1, 0), color: .white, important: true)
        case "BS03":
            vfx.spawn(.heal, at: p, color: UIColor(red: 0.45, green: 1, blue: 0.55, alpha: 1), scale: 1.4, important: true)
            vfx.ring(at: p, color: RGB(0.45, 1, 0.55), from: 0.5, to: 8, duration: 0.6)
        case "BS04":
            vfx.spawn(.shield, at: p + SIMD3(0, 0.9, 0), color: UIColor(red: 0.95, green: 0.85, blue: 0.5, alpha: 1), important: true)
        case "BS05":
            vfx.flash(at: tp, color: RGB(1, 0.85, 0.4), radius: 1.2, duration: 0.3)
            vfx.spawn(.crit, at: tp, color: UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1), scale: 1.4, important: true)
        case "BS06":
            vfx.ring(at: p, color: RGB(0.5, 1, 0.95), from: 0.5, to: 2, duration: 0.5)
            vfx.spawn(.blink, at: p + SIMD3(0, 0.6, 0), color: UIColor(red: 0.5, green: 1, blue: 0.95, alpha: 1))
        case "BS07":
            vfx.spawn(.magicHit, at: tp, color: UIColor(red: 1, green: 0.5, blue: 0.2, alpha: 1), scale: 1.3, important: true)
        case "BS08":
            vfx.spawn(.blink, at: p + SIMD3(0, 0.9, 0), color: UIColor(red: 0.7, green: 0.55, blue: 1, alpha: 1), important: true)
        case "BS10":
            vfx.spawn(.magicHit, at: tp, color: UIColor(red: 0.75, green: 0.55, blue: 1, alpha: 1), scale: 1.2, important: true)
        default:
            vfx.spawn(.skillBurst, at: p + SIMD3(0, 1, 0), color: heroColor(caster, f), scale: 0.8)
        }
    }

    // MARK: カメラ

    func updateCamera(rig: CameraRig, dt: Float, snap: Bool) {
        var target = SIMD2<Float>(repeating: 0)
        var free = false
        switch controller.cameraMode {
        case .followHero:
            if let id = controller.humanHeroID, let p = units.worldPositionOf(id) {
                target = SIMD2(p.x, p.z)
            } else if let i = controller.state.humanHeroIndex {
                let p = worldPosition(controller.state.units[i].pos)
                target = SIMD2(p.x, p.z)
            }
        case .followUnit(let id):
            if let p = units.worldPositionOf(id) {
                target = SIMD2(p.x, p.z)
            } else if let u = controller.state.unit(id) {
                let p = worldPosition(u.pos)
                target = SIMD2(p.x, p.z)
            }
        case .free(let v):
            let p = worldPosition(v)
            target = SIMD2(p.x, p.z)
            free = true
        }
        rig.update(target: target, zoom: controller.cameraZoom, free: free, dt: dt, mapMeters: MapScene.mapMeters)
    }

    // MARK: 設定・破棄

    func apply(settings new: RenderSettings) {
        settings = new
        vfx.apply(quality: new.quality)
        projectiles.apply(quality: new.quality)
        if !new.showDamageNumbers { overlay?.clear() }
    }

    func teardown() {
        vfx.clear()
        units.teardown()
        projectiles.teardown()
        zones.teardown()
        zones.onTrigger = nil
        root.removeFromParent()
    }
}
