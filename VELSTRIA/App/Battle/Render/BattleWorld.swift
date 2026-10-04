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
    let ambient: AmbientParticles
    /// 読み込み幕の裏の陳列（makeWarmupPlan が開き、finishWarmup で片付ける。WorldWarmup.swift）。
    var gallery: WarmupGallery?
    /// 陳列を開いた時の sim の tick（sim が進んだら幕が上がったとみなして片付ける安全策）。
    var galleryTick = 0
    private weak var arView: ARView?
    private weak var overlay: CombatTextOverlay?
    private var time: Float = 0
    private var textSeed = 0
    private var lastHealFX: [EntityID: Float] = [:]
    private var pendingHeal: Double = 0
    private var pendingHealTimer: Float = 0
    private var shakeRequest: Float = 0
    private let master: MasterData
    private var hueCache: [String: UIColor] = [:]
    private var textStacks: [EntityID: TextStack] = [:]
    private let teamLightBlue: UIColor
    private let teamLightRed: UIColor
    #if DEBUG
    private let showcase: RenderShowcase?
    #endif

    init(controller: BattleController, settings: RenderSettings, groundImage: CGImage?, arView: ARView,
         overlay: CombatTextOverlay) {
        self.controller = controller
        self.settings = settings
        self.arView = arView
        self.overlay = overlay
        master = controller.ctx.master
        root.name = "world"
        materials = RenderMaterials(colorblind: settings.colorblind)
        teamLightBlue = materials.teams.light(.blue).uiColor
        teamLightRed = materials.teams.light(.red).uiColor
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
        ambient = AmbientParticles(map: controller.ctx.map, teams: materials.teams, texture: vfx.starTexture,
                                   quality: settings.quality)
        root.addChild(ambient.root)
        if let viewer = controller.viewerTeam {
            fog = FogOfWar(team: viewer, size: settings.quality.fogTextureSize)
            if let fog { root.addChild(fog.entity) }
        } else {
            fog = nil
        }
        #if DEBUG
        showcase = RenderShowcase.isRequested ? RenderShowcase(master: controller.ctx.master) : nil
        #endif
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
        // 陳列を片付け忘れたまま試合が始まった（finishWarmup が呼ばれなかった）場合の安全策
        if gallery != nil, controller.state.tick != galleryTick { finishWarmup() }
        gallery?.update(dt: dt)
        time += dt
        #if DEBUG
        var frame = makeFrame(dt: dt)
        frame.camera = rig.camera.position
        if let showcase {
            var injected: [SimEvent] = []
            showcase.apply(&frame, events: &injected)
            for e in injected { handle(e, frame: frame) }
        }
        #else
        var frame = makeFrame(dt: dt)
        frame.camera = rig.camera.position
        #endif
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
        #if DEBUG
        var aimShown = controller.aim
        if aimShown == nil { aimShown = showcase?.aim }
        #else
        let aimShown = controller.aim
        #endif
        aim.update(aimShown, origin: aimOrigin, dt: dt)
        // 草むら: 表示中のスキル予告に重なる草むらを半透明に
        map.beginBrushMarks()
        let mapDef = controller.ctx.map
        for k in frame.state.zones.indices {
            let z = frame.state.zones[k]
            guard zones.isShown(z.id) else { continue }
            let bounds = ZoneLayer.bounds(of: z)
            map.markBrushes(overlapping: bounds.center, radius: bounds.radius, map: mapDef)
        }
        map.applyBrushTranslucency()
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

    /// 戦闘数値の出現位置（HP バー・名前の上）。
    private func textAnchor(_ id: EntityID) -> SIMD3<Float>? {
        guard let p = units.worldPositionOf(id) else { return nil }
        let bar: Float = units.hero(id) != nil ? 1.25 : 0.75
        return p + SIMD3(0, units.headHeight(id) + bar, 0)
    }

    private func nearCamera(_ p: SIMD3<Float>) -> Bool {
        guard let arView else { return true }
        let c = arView.cameraTransform.translation
        let dx = p.x - c.x, dz = p.z - (c.z - 7)
        return dx * dx + dz * dz < 24 * 24
    }

    private func heroColor(_ id: EntityID?, _ f: RenderFrame) -> UIColor {
        if let id, let i = f.state.index(of: id), let heroID = f.state.units[i].hero?.heroID {
            return hueColor(heroID)
        }
        return FXColors.defaultMagic
    }

    /// ヒーロー色相の演出色（キャッシュ）。
    func hueColor(_ heroID: String) -> UIColor {
        if let c = hueCache[heroID] { return c }
        let c = UIColor(hue: CGFloat(Theme.heroHue(heroID)), saturation: 0.62, brightness: 1, alpha: 1)
        hueCache[heroID] = c
        return c
    }

    /// 演出色（UIColor）→ 輪・閃光の単色マテリアル用の RGB（変換できない色は既定の淡青）。
    static func ringRGB(_ color: UIColor) -> RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return FXRings.skillDefault }
        return RGB(Double(r), Double(g), Double(b))
    }

    private func teamColor(_ id: EntityID?, _ f: RenderFrame) -> UIColor {
        guard let id, let i = f.state.index(of: id) else { return FXColors.white }
        return teamLight(f.state.units[i].team)
    }

    private func teamLight(_ team: Team) -> UIColor {
        switch team {
        case .blue: return teamLightBlue
        case .red: return teamLightRed
        case .neutral: return FXColors.neutral
        }
    }

    /// stackKey が同じ数値が短時間に続いたら上へずらして重ならないようにする。
    private func spawnText(_ s: String, at p: SIMD3<Float>, style: CombatTextStyle, stackKey: EntityID? = nil) {
        guard settings.showDamageNumbers, let overlay else { return }
        textSeed &+= 1
        var pos = p
        if let key = stackKey {
            // 撃破済みユニットの記録を時々掃除する
            if textStacks.count > 128 { textStacks = textStacks.filter { time - $0.value.time < 1 } }
            var entry = textStacks[key] ?? TextStack(time: -10, count: 0)
            entry.count = time - entry.time < 0.4 ? min(entry.count + 1, 4) : 0
            entry.time = time
            textStacks[key] = entry
            pos += SIMD3(entry.count % 2 == 0 ? 0 : 0.3, Float(entry.count) * 0.34, 0)
        }
        overlay.spawn(text: s, world: pos, style: style, seed: textSeed)
    }

    private struct TextStack {
        var time: Float
        var count: Int
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
            vfx.spawn(.shield, at: p, color: FXColors.shield, important: target == f.focusID)
            if target == f.focusID, let tp = textAnchor(target) {
                spawnText(CombatTextFormat.plus(amount), at: tp + SIMD3(-0.4, 0, 0), style: .shield)
            }
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
            let c = team == .neutral ? FXColors.monsterDeath : teamLight(team)
            vfx.spawn(.death, at: p, color: c, scale: kind == .monster ? 1.6 : 1)
        case .heroKilled(let k):
            guard let p = anchor(k.victimID, heightRatio: 0.5) else { break }
            vfx.spawn(.heroDeath, at: p, color: teamColor(k.victimID, f), important: true)
            vfx.ring(at: SIMD3(p.x, 0, p.z), color: FXRings.heroDeath, from: 0.4, to: 2.4, duration: 0.6)
            if k.victimID == f.focusID { shakeRequest = max(shakeRequest, 0.25) }
        case .goldGained(let heroID, let amount, let pos):
            guard heroID == f.focusID, amount >= 1 else { break }
            let p = worldPosition(pos, height: 1.2)
            vfx.spawn(.gold, at: p, color: FXColors.gold, important: true)
            spawnText(CombatTextFormat.plus(amount), at: p + SIMD3(0, 0.4, 0), style: .gold)
        case .levelUp(let heroID, _):
            guard isShown(heroID, f), let base = units.worldPositionOf(heroID) else { break }
            vfx.spawn(.levelUp, at: base + SIMD3(0, 0.1, 0), color: FXColors.levelUp, important: true)
            vfx.ring(at: base, color: FXRings.levelUp, from: 0.3, to: 1.8, duration: 0.7)
        case .structureDestroyed(let id, let kind, let team, _, _, _):
            guard let base = units.worldPositionOf(id) else { break }
            let top = base + SIMD3(0, kind == .core ? 3.6 : 4.6, 0)
            vfx.spawn(.towerExplosion, at: top, color: teamLight(team), scale: kind == .core ? 1.6 : 1,
                      important: true)
            vfx.spawn(.debris, at: top - SIMD3(0, 1.5, 0), color: .gray, scale: kind == .core ? 1.5 : 1, important: true)
            vfx.spawn(.smoke, at: base + SIMD3(0, 1.2, 0), color: .gray, scale: kind == .core ? 1.6 : 1, important: true)
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
            let c: UIColor = kind == .recall ? teamColor(heroID, f) : FXColors.teleport
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
                vfx.spawn(.crit, at: p, color: FXColors.crit, important: involvesFocus)
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
                        case .physical: c = FXColors.physical
                        case .magic: c = FXColors.magic
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
        if d.sourceID == f.focusID, d.targetID != f.focusID, let tp = textAnchor(d.targetID) {
            spawnText(CombatTextFormat.damage(d.amount, crit: d.isCrit), at: tp, style: .dealt(d.damageType, crit: d.isCrit),
                      stackKey: d.targetID)
        } else if d.targetID == f.focusID, let tp = textAnchor(d.targetID) {
            spawnText(CombatTextFormat.damage(d.amount, crit: false), at: tp + SIMD3(0.35, 0, 0), style: .taken,
                      stackKey: d.targetID)
            if case .skill(.ultimate) = d.source { shakeRequest = max(shakeRequest, 0.45) }
        }
    }

    private func onHeal(target: EntityID, source: EntityID?, amount: Double, _ f: RenderFrame) {
        guard isShown(target, f) else { return }
        if target == f.focusID { pendingHeal += amount }
        guard amount >= 25, let p = units.worldPositionOf(target) else { return }
        if let last = lastHealFX[target], time - last < 0.5 { return }
        if lastHealFX.count > 128 { lastHealFX = lastHealFX.filter { time - $0.value < 1 } }
        lastHealFX[target] = time
        vfx.spawn(.heal, at: p + SIMD3(0, 0.2, 0), color: FXColors.heal,
                  important: target == f.focusID)
    }

    /// 小さな回復（吸収など）はまとめて表示する。
    private func flushHealText(dt: Float, frame f: RenderFrame) {
        pendingHealTimer += dt
        guard pendingHealTimer >= 0.35 else { return }
        pendingHealTimer = 0
        guard pendingHeal >= 5, let focus = f.focusID, let p = textAnchor(focus) else {
            pendingHeal = 0
            return
        }
        spawnText(CombatTextFormat.plus(pendingHeal), at: p + SIMD3(-0.35, 0.1, 0), style: .heal)
        pendingHeal = 0
    }

    private func skillFX(_ c: SkillCastEvent, _ f: RenderFrame) {
        let color = hueColor(c.heroID)
        let effect = master.effect(c.effectID)
        let scale = Float(effect?.scaleM ?? 1.2)
        // 演出の長さ（EffectDef.durationSec）を粒子と輪の寿命へ反映
        let life = effect.map { max(0.25, min(2.0, $0.durationSec)) }
        let ringTime = Float(life ?? 0.45) * 0.8
        let origin = units.worldPositionOf(c.casterID) ?? worldPosition(c.origin)
        let target = worldPosition(c.target)
        let radius = Float(c.radius / Balance.unitsPerMeter)
        let dir = target - origin
        let len = simd_length(dir)
        let ringColor = BattleWorld.ringRGB(color)
        // アーキタイプ別の主演出
        switch c.archetype {
        case .cone:
            let mid = origin + (len > 0.1 ? simd_normalize(dir) * min(len, radius) * 0.5 : .zero) + SIMD3(0, 0.9, 0)
            vfx.spawn(.skillBurst, at: mid, color: color, scale: scale, important: true, life: life)
        case .dashStrike, .leapSlam:
            if len > 0.5 {
                vfx.spawn(.trail, at: (origin + target) / 2 + SIMD3(0, 0.9, 0), color: color, scale: len / 2, important: true,
                          direction: dir, life: life)
            }
            vfx.ring(at: target, color: ringColor, from: 0.3, to: max(1, radius), duration: ringTime)
            vfx.spawn(.areaBlast, at: target, color: color, scale: max(0.8, radius), important: true, life: life)
        case .blinkEmpower, .targetedBlink:
            vfx.spawn(.blink, at: origin + SIMD3(0, 0.9, 0), color: color, important: true, life: life)
        case .selfAoE, .teamHeal, .multiStrike:
            vfx.ring(at: origin, color: ringColor, from: 0.4, to: max(1.2, radius), duration: ringTime)
            vfx.spawn(.areaBlast, at: origin, color: color, scale: max(0.8, radius), important: true, life: life)
        case .lineSkillshot, .piercingLine:
            let muzzle = origin + (len > 0.1 ? simd_normalize(dir) * 0.8 : .zero) + SIMD3(0, 1.1, 0)
            vfx.spawn(.skillBurst, at: muzzle, color: color, scale: 0.6, important: true)
        case .groundAoE, .healZone, .passive:
            vfx.spawn(.magicHit, at: origin + SIMD3(0, 1.4, 0), color: color, scale: 0.8, important: false)
        }
        // 演出種別（EffectDef.effectType）による追加。大きさは scale_m、長さは duration_sec
        switch effect?.effectType {
        case .shield:
            vfx.spawn(.shield, at: origin + SIMD3(0, 0.9, 0), color: color, scale: max(1, scale * 0.7), important: true, life: life)
            vfx.flash(at: origin + SIMD3(0, 0.9, 0), color: ringColor, radius: max(1, scale * 0.8), duration: ringTime, alpha: 0.3)
        case .burst:
            if c.archetype != .cone {
                vfx.spawn(.skillBurst, at: target + SIMD3(0, 0.8, 0), color: color, scale: scale * 0.7, important: false, life: life)
            }
        case .area:
            if c.archetype != .selfAoE && c.archetype != .teamHeal {
                vfx.ring(at: target, color: ringColor, from: 0.3, to: max(scale, radius), duration: ringTime, alpha: 0.7)
            }
        case .trail:
            if len > 0.5 && c.archetype != .dashStrike && c.archetype != .leapSlam {
                vfx.spawn(.trail, at: (origin + target) / 2 + SIMD3(0, 0.9, 0), color: color, scale: len / 2, important: false,
                          direction: dir, life: life)
            }
        case .projectile, .none:
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
            vfx.spawn(.heal, at: p, color: FXColors.heal, scale: 1.4, important: true)
            vfx.ring(at: p, color: FXRings.heal, from: 0.5, to: 8, duration: 0.6)
        case "BS04":
            vfx.spawn(.shield, at: p + SIMD3(0, 0.9, 0), color: FXColors.barrier, important: true)
        case "BS05":
            vfx.flash(at: tp, color: FXRings.smite, radius: 1.2, duration: 0.3)
            vfx.spawn(.crit, at: tp, color: FXColors.smite, scale: 1.4, important: true)
        case "BS06":
            vfx.ring(at: p, color: FXRings.haste, from: 0.5, to: 2, duration: 0.5)
            vfx.spawn(.blink, at: p + SIMD3(0, 0.6, 0), color: FXColors.haste)
        case "BS07":
            vfx.spawn(.magicHit, at: tp, color: FXColors.ignite, scale: 1.3, important: true)
        case "BS08":
            vfx.spawn(.blink, at: p + SIMD3(0, 0.9, 0), color: FXColors.ghost, important: true)
        case "BS10":
            vfx.spawn(.magicHit, at: tp, color: FXColors.chain, scale: 1.2, important: true)
        default:
            vfx.spawn(.skillBurst, at: p + SIMD3(0, 1, 0), color: heroColor(caster, f), scale: 0.8)
        }
    }

    // MARK: カメラ

    func updateCamera(rig: CameraRig, dt: Float, snap: Bool) {
        let (target, free) = cameraFocus()
        var zoom = controller.cameraZoom
        #if DEBUG
        if let z = StageDebug.cameraZoom { zoom = z }
        #endif
        rig.update(target: target, zoom: zoom, free: free, dt: dt, mapMeters: MapScene.mapMeters)
    }

    /// カメラの注視点（world x・z）と自由視点か。
    func cameraFocus() -> (target: SIMD2<Float>, free: Bool) {
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
        #if DEBUG
        if let t = StageDebug.cameraTarget { return (t, true) }
        #endif
        return (target, free)
    }

    // MARK: 設定・破棄

    /// 設定の反映。画質の変更（利用者の選んだ画質の範囲内での自動調整を含む）では何も作らない:
    /// 放出体の上限・粒子数・軌跡・環境パーティクルは事前に作ったものの有効/無効と値の書き換えだけで切り替える。
    func apply(settings new: RenderSettings) {
        settings = new
        vfx.apply(quality: new.quality)
        projectiles.apply(quality: new.quality)
        ambient.apply(quality: new.quality)
        if !new.showDamageNumbers { overlay?.clear() }
    }

    func teardown() {
        finishWarmup()
        vfx.clear()
        units.teardown()
        projectiles.teardown()
        zones.teardown()
        zones.onTrigger = nil
        root.removeFromParent()
    }
}

/// 輪・閃光の色（単色マテリアルのキー。事前生成と同じ値を使う）。
enum FXRings {
    static let white = RGB(1, 1, 1)
    static let heroDeath = RGB(0.9, 0.9, 1.0)
    static let levelUp = RGB(1, 0.86, 0.45)
    /// スキル演出の既定（色相が取れない時）。
    static let skillDefault = RGB(0.8, 0.9, 1)
    static let heal = RGB(0.45, 1, 0.55)
    static let haste = RGB(0.5, 1, 0.95)
    static let smite = RGB(1, 0.85, 0.4)
}

/// 演出で繰り返し使う色（イベント毎の生成を避ける）。
enum FXColors {
    static let white = UIColor.white
    static let defaultMagic = UIColor(red: 0.7, green: 0.85, blue: 1, alpha: 1)
    static let neutral = UIColor(red: 1, green: 0.7, blue: 0.35, alpha: 1)
    static let shield = UIColor(red: 0.8, green: 0.92, blue: 1, alpha: 1)
    static let monsterDeath = UIColor(red: 0.8, green: 0.7, blue: 1.0, alpha: 1)
    static let levelUp = UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
    static let teleport = UIColor(red: 0.85, green: 0.7, blue: 1, alpha: 1)
    static let crit = UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 1)
    static let physical = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
    static let magic = UIColor(red: 0.75, green: 0.6, blue: 1, alpha: 1)
    static let heal = UIColor(red: 0.45, green: 1, blue: 0.55, alpha: 1)
    static let barrier = UIColor(red: 0.95, green: 0.85, blue: 0.5, alpha: 1)
    static let smite = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
    static let haste = UIColor(red: 0.5, green: 1, blue: 0.95, alpha: 1)
    static let ignite = UIColor(red: 1, green: 0.5, blue: 0.2, alpha: 1)
    static let ghost = UIColor(red: 0.7, green: 0.55, blue: 1, alpha: 1)
    static let chain = UIColor(red: 0.75, green: 0.55, blue: 1, alpha: 1)
    static let gold = UIColor(red: 1, green: 0.84, blue: 0.3, alpha: 1)
}
