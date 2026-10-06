import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。読み込み完了後の描画世界（各レイヤーの所有者）と SimEvent → 演出の振り分け。
// 観戦: 霧は常に作り（全体視点では隠す）、観戦者の視点チームの切替に追従する。自動カメラ（CameraDirector）の
// 持ち主で、カメラの追従先の解決（倒れた対象・消えた対象・霧の向こうの対象・複数対象の framing）と切替の移り方を決める。

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
    /// スキル固有の演出（SkillFX）。
    let skillDirector: SkillFXDirector
    let aim: AimLayer
    /// 霧（プレイヤーは自チームの視界。観戦者は常に作り、視点チームを選んだ時だけ出す）。
    let fog: FogOfWar?
    let ambient: AmbientParticles
    /// 観戦カメラの窓口（HUD の指の操作と共有）。
    let cameraLink: SpectatorCameraLink
    /// 自動カメラ（観戦中のみ）。
    let director: CameraDirector?
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
    /// 直前の有効な注視点（追従対象が消えた・霧に入った時はここに留まる）。
    private var lastCameraTarget: SIMD2<Float>?
    /// 直前のフレームで追っていた主役・注視の種類（切替の検出）。
    private var lastCameraSubject: EntityID?
    private var lastCameraKind: CameraAim.Kind = .follow
    /// 直前のフレームの framing の倍率（シーク中に画を保つ）。
    private var lastCameraFitZoom: Double?
    /// カメラが最後に見た presentationEpoch（シーク・再同期でカメラを切り替える）。
    private var cameraEpoch: Int?
    /// 画面に映る地面の範囲（world x・z の外接矩形 + 余白。演出の間引き）。
    private var cullBounds: (min: SIMD2<Float>, max: SIMD2<Float>)?
    /// 最後に同期した視点チーム（一時停止中の視点の切替を検出する）。
    private var syncedViewer: Team?
    private var hasSyncedViewer = false
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
        skillDirector = SkillFXDirector(master: controller.ctx.master, quality: settings.quality, units: units,
                                        projectiles: projectiles)
        root.addChild(skillDirector.player.root)
        aim = AimLayer(materials: materials, meshes: meshes)
        root.addChild(aim.root)
        ambient = AmbientParticles(map: controller.ctx.map, teams: materials.teams, texture: vfx.starTexture,
                                   quality: settings.quality)
        root.addChild(ambient.root)
        if controller.viewerTeam != nil || controller.isSpectating {
            // 観戦者は試合中に視点チームを選べるので、全体視点で始まっても作っておく（途中で作るとヒッチになる）
            fog = FogOfWar(team: controller.viewerTeam, size: settings.quality.fogTextureSize)
            if let fog { root.addChild(fog.entity) }
        } else {
            fog = nil
        }
        cameraLink = SpectatorCameraLink.link(for: controller)
        director = controller.isSpectating ? CameraDirector(controller: controller, link: cameraLink) : nil
        #if DEBUG
        showcase = RenderShowcase.isRequested ? RenderShowcase(master: controller.ctx.master) : nil
        if SkillFXDemo.isRequested {
            let demo = SkillFXDemo()
            demo.walk = { [weak controller] p in controller?.send(.moveTo(point: p)) }
            skillDirector.demo = demo
        }
        #endif
        skillDirector.player.onShake = { [weak self] amount, pos in
            guard let self, let focus = self.controller.humanHeroID ?? self.makeFrame(dt: 0).focusID,
                  let fp = self.units.worldPositionOf(focus), simd_distance(fp, pos) < 14 else { return }
            self.shakeRequest = max(self.shakeRequest, amount)
        }
        zones.onTrigger = { [weak self] id, pos, color, radius in
            guard let self else { return }
            // スキル固有の演出があるゾーンは、その発動演出（SkillFXDirector.onZoneTriggered）に任せる
            if self.skillDirector.isSkillZone(id) { return }
            self.vfx.ring(at: pos, color: color, from: max(0.3, radius * 0.4), to: radius * 1.1, duration: 0.45)
            self.vfx.spawn(.areaBlast, at: pos, color: color.uiColor, scale: radius, important: true)
        }
        prepareSpectatorFog()
        director?.start()
    }

    var liveEntityCount: Int { units.liveCount + projectiles.count + zones.count + vfx.activeCount }

    private func makeFrame(dt: Float) -> RenderFrame {
        let state = controller.state
        let focus = controller.presentationFocusID
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
        updateCullBounds(rig: rig)
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
        syncedViewer = frame.viewerTeam
        hasSyncedViewer = true
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
        updateChannelLoops(frame)
        skillDirector.update(dt: dt, state: frame.state)
        #if DEBUG
        if let demo = skillDirector.demo {
            let t = time
            demo.update(dt: dt, director: skillDirector, units: units, master: master, state: frame.state,
                        humanID: controller.humanHeroID) { [units] id, slot in units.noteCast(heroID: id, slot: slot, time: t) }
        }
        #endif
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
        syncFogVision()
        fog?.update(state: frame.state, dt: dt)
        flushHealText(dt: dt, frame: frame)
    }

    func updateOverlay(dt: Float) {
        guard let overlay, let arView else { return }
        overlay.update(dt: dt) { p in arView.project(p) }
    }

    // MARK: 不連続（シーク・再同期）

    /// 作り直しの同期に使う dt（秒）。見た目の可視性・ヒーローの死後の消え方（2.8 秒）・向き・HP バーの遅れ・
    /// 結晶の落下・霧の補間を 1 回で終わらせる長さ。
    static let presentationSnapDt: Float = 3

    /// presentationEpoch が変わった（シーク・オンラインの再同期）: 前の時刻の演出を演出なしで捨て、今の状態へ即座に合わせる。
    /// - クリーチャーは死亡演出なしでプールへ戻して作り直す。飛んでいる弾・地面の予告（発動演出なし）・粒子・輪・閃光・スキル演出・
    ///   詠唱ループ・戦闘数値・回復のまとめ・揺れを捨てる
    /// - 構造物は状態どおり（破壊前へ戻ったら瓦礫から元の姿へ）、ヒーローの可視性・死後の消え方・向きは補間せずに合わせる
    /// - 詠唱中（帰還・転移）のヒーローのループは今の状態から付け直す
    /// - 霧は補間せずに今の視界へ（次の計算結果で一度に合わせる）、カメラは切り替え（滑らせない）
    /// イベントは配らない・受け取らない（シークで飛ばした区間の演出は出さない）。一時停止中でも呼ばれる。
    func resetForPresentationEpoch(rig: CameraRig) {
        units.resetForPresentationEpoch()
        projectiles.resetForPresentationEpoch()
        zones.resetForPresentationEpoch()
        vfx.resetForPresentationEpoch()
        // スキル演出（予定の合図・追従・ゾーンと投射物の対応）も捨てる
        skillDirector.clear()
        overlay?.clear()
        textStacks.removeAll(keepingCapacity: true)
        lastHealFX.removeAll(keepingCapacity: true)
        pendingHeal = 0
        pendingHealTimer = 0
        shakeRequest = 0
        // 1 回目で見た目を今の状態から作り直し、2 回目で作ったばかりの見た目のフェード（HP バーの遅れなど）も終わらせる
        for _ in 0..<2 { sync(events: [], dt: BattleWorld.presentationSnapDt, rig: rig) }
        let state = controller.state
        let viewer = controller.viewerTeam
        for i in state.units.indices where state.units[i].kind == .hero {
            let u = state.units[i]
            guard let channel = u.hero?.channel, u.isAlive, viewer.map({ state.isVisible(i, to: $0) }) ?? true,
                  let p = units.worldPositionOf(u.id) else { continue }
            vfx.startLoop(id: u.id, at: p, color: channel.kind == .recall ? teamLight(u.team) : FXColors.teleport)
        }
        updateCamera(rig: rig, dt: 0, snap: true)
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

    /// 画面に映る地面の近く（演出の間引き）。カメラの実際の倍率で変わる映る範囲（+ 余白）で判定する（B28）。
    private func nearCamera(_ p: SIMD3<Float>) -> Bool {
        if let b = cullBounds { return BattleWorld.isInside(p, bounds: b) }
        guard let arView else { return true }
        let c = arView.cameraTransform.translation
        let dx = p.x - c.x, dz = p.z - (c.z - 7)
        return dx * dx + dz * dz < 24 * 24
    }

    /// 演出を出す範囲の余白（m。画面の外から飛び込む粒子・輪の分）。
    static let cullMargin: Float = 3

    /// 画面に映る地面（sim 座標の 4 隅）→ world x・z の外接矩形 + 余白。
    static func cullBounds(footprint: [Vec2], margin: Float) -> (min: SIMD2<Float>, max: SIMD2<Float>)? {
        guard footprint.count >= 3 else { return nil }
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for v in footprint {
            let w = SIMD2(Float(v.x / Balance.unitsPerMeter), Float(-v.y / Balance.unitsPerMeter))
            lo = simd_min(lo, w)
            hi = simd_max(hi, w)
        }
        return (lo - SIMD2(repeating: margin), hi + SIMD2(repeating: margin))
    }

    static func isInside(_ p: SIMD3<Float>, bounds b: (min: SIMD2<Float>, max: SIMD2<Float>)) -> Bool {
        p.x >= b.min.x && p.x <= b.max.x && p.z >= b.min.y && p.z <= b.max.y
    }

    /// 描画中の画面の縦横比（ARView の大きさ。まだ無ければ横長 iPhone の値）。
    private var viewAspect: Float {
        guard let size = arView?.bounds.size, size.width > 0, size.height > 0 else { return CameraRig.designAspect }
        return Float(size.width / size.height)
    }

    private func updateCullBounds(rig: CameraRig) {
        cullBounds = BattleWorld.cullBounds(footprint: rig.groundFootprint(aspectRatio: viewAspect), margin: BattleWorld.cullMargin)
    }

    /// 詠唱ループ（帰還・転移）: 視点チームから見えている間だけ出して本人に追従させ、見えなくなったら止める
    /// （霧に入った敵の帰還・転移の位置を漏らさない。B6）。途中で見えるようになった詠唱にも付ける。
    /// 見え方は本体のフェード値で判定し、霧の縁での点滅を避ける（付ける 0.65 以上・外す 0.35 未満）。
    private func updateChannelLoops(_ f: RenderFrame) {
        let s = f.state
        for i in s.units.indices where s.units[i].kind == .hero {
            let id = s.units[i].id
            let channel = s.units[i].hero?.isDead == false ? s.units[i].hero?.channel : nil
            let hasLoop = vfx.hasLoop(id)
            // 本体の見え方（視点チームから見えている間 1 へ、見えなくなると 0 へ素早くフェードする）
            let visibility = units.hero(id)?.visibility ?? 0
            if let channel, visibility >= (hasLoop ? 0.35 : 0.65), let p = units.worldPositionOf(id) {
                if hasLoop {
                    vfx.moveLoop(id: id, to: p)
                } else {
                    vfx.startLoop(id: id, at: p, color: channel.kind == .recall ? teamColor(id, f) : FXColors.teleport)
                }
            } else if hasLoop {
                vfx.stopLoop(id: id)
            }
        }
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
        observePassive(e, f)
        switch e {
        case .attackStarted(let src, _):
            units.noteAttack(sourceID: src, time: time)
        case .attackReleased(let src, _, _):
            units.noteAttack(sourceID: src, time: time)
        case .damage(let d):
            units.noteHit(targetID: d.targetID)
            onDamage(d, f)
            if isShown(d.targetID, f) { skillDirector.onDamage(d, state: f.state) }
        case .heal(let target, let source, let amount):
            onHeal(target: target, source: source, amount: amount, f)
        case .shieldGained(let target, _, let amount):
            guard isShown(target, f), let p = anchor(target, heightRatio: 0.5) else { break }
            vfx.spawn(.shield, at: p, color: FXColors.shield, important: target == f.focusID)
            if target == f.focusID, let tp = textAnchor(target) {
                spawnText(CombatTextFormat.plus(amount), at: tp + SIMD3(-0.4, 0, 0), style: .shield)
            }
        case .projectileHit(let pid, let tid, let pos):
            if skillDirector.onProjectileHit(projectileID: pid, pos: pos, state: f.state) { break }
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
            if isShown(c.casterID, f), !skillDirector.onCast(c, state: f.state) { skillFX(c, f) }
        case .zoneCreated(let zoneID, let ownerID, _, let visual, let center, _, _, _, _):
            if isShown(ownerID, f) {
                skillDirector.onZoneCreated(zoneID: zoneID, ownerID: ownerID, visual: visual, center: center)
            }
        case .zoneTriggered(let zoneID, let center, _):
            if zones.isShown(zoneID) || f.viewerTeam == nil {
                skillDirector.onZoneTriggered(zoneID: zoneID, center: center)
            }
        case .projectileLaunched(let pid, let owner, let visual):
            if isShown(owner, f) {
                skillDirector.onProjectileLaunched(projectileID: pid, ownerID: owner, visual: visual, state: f.state)
            }
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

    /// パッシブの発動の推定（見えているヒーローのものだけ）。
    private func observePassive(_ e: SimEvent, _ f: RenderFrame) {
        let subject: EntityID?
        switch e {
        case .shieldGained(let target, _, _), .statusApplied(let target, _, _): subject = target
        case .damage(let d): subject = d.sourceID
        case .heal(_, let source, _): subject = source
        default: return
        }
        guard let id = subject, isShown(id, f) else { return }
        skillDirector.observe(e, state: f.state)
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

    /// 注視の解決結果（カメラの追従先と、切替の検出に使う主役）。
    struct CameraAim: Equatable {
        enum Kind: Equatable {
            /// ユニットの追従（注視点を少し前方へずらす）。
            case follow
            /// 自由視点（ミニマップ・パン）。
            case free
            /// 複数のユニットを収める（注視点と倍率を逆算）。
            case framing
        }

        /// 追従先の world (x, z)。nil = 有効な追従先が無い（直前の注視点に留まる）。
        var target: SIMD2<Float>?
        var kind: Kind = .follow
        /// 追っている主役（切替の検出）。自由視点は nil。
        var subject: EntityID?
        /// 複数のユニットを収める倍率（framing のみ）。
        var fitZoom: Double?
        /// 注視点を追従先より北へずらす量の上書き（m）。
        var lead: Float?
    }

    /// 倒れたヒーローを追っている時、倒れた場所を見せる時間（sim の秒）。過ぎたら同じチームの近くの味方を映す（B30）。
    static let deathHoldSeconds: Double = 2.4
    /// 死亡中の味方追従（プレイヤー）: 追っている味方を画面の中央より少し上に置く（下の味方一覧に隠れないように。m）。
    static let deathFollowLead: Float = -0.7

    func updateCamera(rig: CameraRig, dt: Float, snap: Bool) {
        let seeking = controller.seekingToTick != nil
        // シーク中は sim が途中の tick を行き来する（描画は同期しない）ので、視界の切替の反映もシークの後で行う
        if controller.isPaused && !seeking { refreshVisionWhilePaused(rig: rig, dt: dt) }
        director?.update()
        let aim = seeking ? heldCameraAim() : resolveCameraAim()
        let target = aim.target ?? lastCameraTarget ?? rig.focus.value
        if let t = aim.target { lastCameraTarget = t }
        var drive = CameraDrive(target: target, zoom: controller.effectiveCameraZoom, free: aim.kind != .follow)
        drive.lead = aim.lead
        drive.zoomRange = controller.isSpectating ? CameraRig.spectatorZoomRange : CameraRig.playerZoomRange
        if let fit = aim.fitZoom {
            // 複数を収める: 今の倍率より寄らない（単独の追従との行き来で寄り引きを繰り返さない）。
            // 寄り引きと注視点はゆっくり動かす（人の出入りで画面が揺れないように）
            drive.zoom = max(fit, controller.effectiveCameraZoom)
            drive.focusSmoothTime = 0.4
            drive.zoomSmoothTime = 0.7
            drive.snapsOnTeleport = false
        }
        // 指で動かしている自由カメラ（パン・ピンチの中心の固定）はばねを掛けずに合わせる
        drive.direct = aim.kind == .free && (cameraLink.isPanning || cameraLink.isPinching)
        drive.directZoom = cameraLink.isPinching
        #if DEBUG
        if let z = StageDebug.cameraZoom { drive.zoom = z }
        #endif
        drive.transition = cameraTransition(rig: rig, aim: aim, target: target, snap: snap)
        rig.update(drive, dt: dt, mapMeters: MapScene.mapMeters)
        lastCameraSubject = aim.subject
        lastCameraKind = aim.kind
        lastCameraFitZoom = aim.fitZoom
        // 指の操作（パン・ピンチ）の起点と、引いた時の頭上バーの大きさ（実際に描いている距離から。B27 と同じ考え）
        let f = rig.focus.value
        cameraLink.renderedFocus = Vec2(Double(f.x) * Balance.unitsPerMeter, -Double(f.y) * Balance.unitsPerMeter)
        cameraLink.renderedZoom = rig.currentZoom
        OverheadBar.zoomScale = OverheadBar.zoomScale(forZoom: rig.currentZoom)
    }

    /// 切替の移り方: 最初・snap・シーク/再同期（presentationEpoch の変化）は即座に。追う主役が変わった時
    /// （観戦者の選択・自動カメラ・倒れた対象の代わり）は近ければ滑らかに、遠ければ即座に切り替える（B26）。
    private func cameraTransition(rig: CameraRig, aim: CameraAim, target: SIMD2<Float>, snap: Bool) -> CameraTransition {
        let epoch = controller.presentationEpoch
        defer { cameraEpoch = epoch }
        if let last = cameraEpoch, last != epoch {
            // シーク・再同期: 霧も次の目標へ補間せずに合わせる（飛んだ先の視界を、前の視界からゆっくり変えない）
            fog?.refreshImmediately()
        }
        if snap || cameraEpoch != epoch { return .cut }
        guard aim.kind != .free, aim.subject != nil,
              aim.subject != lastCameraSubject || aim.kind != lastCameraKind else { return .follow }
        return BattleWorld.transition(forSwitchDistance: simd_distance(rig.focus.value, target))
    }

    /// 主役を切り替える時の移り方（移る距離 m から）。
    static func transition(forSwitchDistance d: Float) -> CameraTransition {
        if d > CameraRig.cutDistance { return .cut }
        if d > 1.5 { return .glide(CameraRig.glideDuration(distance: d)) }
        return .follow
    }

    /// カメラの注視点（world x・z）と自由視点か（読み込み幕の裏の陳列の位置などに使う）。
    func cameraFocus() -> (target: SIMD2<Float>, free: Bool) {
        let aim = resolveCameraAim()
        return (aim.target ?? lastCameraTarget ?? SIMD2(repeating: 0), aim.kind != .follow)
    }

    /// シーク中の注視: 自由カメラ（指・ミニマップ）はそのまま動かし、追従・framing は直前の注視点と倍率に留まる
    /// （途中の tick の状態で倒れた・消えた判定や代わりの味方を選ぶと、シークの間に画が揺れる。終われば presentationEpoch で切り替える）。
    private func heldCameraAim() -> CameraAim {
        if case .free = controller.cameraMode { return resolveCameraAim() }
        return CameraAim(target: nil, kind: lastCameraKind == .free ? .follow : lastCameraKind, subject: lastCameraSubject,
                         fitZoom: lastCameraFitZoom)
    }

    /// 今のカメラモードから注視を解決する（状態は変えない）。
    func resolveCameraAim() -> CameraAim {
        #if DEBUG
        if let t = StageDebug.cameraTarget { return CameraAim(target: t, kind: .free) }
        #endif
        let s = controller.state
        let viewer = controller.viewerTeam
        switch controller.cameraMode {
        case .followHero:
            if let id = controller.humanHeroID, let p = units.worldPositionOf(id) {
                return CameraAim(target: SIMD2(p.x, p.z), subject: id)
            }
            if let i = s.humanHeroIndex {
                let p = worldPosition(s.units[i].pos)
                return CameraAim(target: SIMD2(p.x, p.z), subject: s.units[i].id)
            }
            return CameraAim()
        case .followUnit(let id):
            return followAim(id, state: s, viewer: viewer)
        case .free(let v):
            let p = worldPosition(v)
            return CameraAim(target: SIMD2(p.x, p.z), kind: .free)
        case .framing(let ids):
            return framingAim(ids, state: s, viewer: viewer)
        }
    }

    /// ユニットの追従。消えた（撃破で列から除かれた）・視点チームから見えない対象は直前の注視点に留まる（B25・霧の向こうを漏らさない）。
    /// 倒れたヒーローは倒れた場所を少し見せてから、同じチームの近くの味方を映す（復活したら本人へ戻る。B30）。
    private func followAim(_ id: EntityID, state s: SimState, viewer: Team?) -> CameraAim {
        var aim = CameraAim(subject: id)
        if !controller.isSpectating { aim.lead = BattleWorld.deathFollowLead }
        guard let i = s.index(of: id) else { return aim }
        let u = s.units[i]
        let dead = u.kind == .hero && (u.hero?.isDead == true || !u.isAlive)
        if let viewer, !dead, !s.isVisible(i, to: viewer) { return aim }
        if dead {
            // 視点チームから見えない敵の死は、見えていた最後の場所に留まる
            if let viewer, u.team != viewer, !s.vision.isLit(u.pos, for: viewer) { return aim }
            let since = s.time - (u.deathTime ?? s.time)
            if since >= BattleWorld.deathHoldSeconds, let ally = BattleWorld.nearestAlly(of: i, state: s, viewer: viewer) {
                let allyID = s.units[ally].id
                let p = units.worldPositionOf(allyID) ?? worldPosition(s.units[ally].pos)
                aim.subject = allyID
                aim.target = SIMD2(p.x, p.z)
                return aim
            }
            let p = worldPosition(u.pos)
            aim.target = SIMD2(p.x, p.z)
            return aim
        }
        let p = units.worldPositionOf(id) ?? worldPosition(u.pos)
        aim.target = SIMD2(p.x, p.z)
        return aim
    }

    /// 倒れたヒーローの代わりに映す味方（同じチームで生きていて、視点チームから見えている。倒れた場所に一番近い）。
    static func nearestAlly(of i: Int, state s: SimState, viewer: Team?) -> Int? {
        let origin = s.units[i].pos
        var best: (index: Int, d: Double)?
        for j in s.heroIndices(team: s.units[i].team) where j != i {
            let u = s.units[j]
            guard u.isAlive, u.hero?.isDead == false else { continue }
            if let viewer, !s.isVisible(j, to: viewer) { continue }
            let d = u.pos.distanceSquared(to: origin)
            if best == nil || d < best!.d { best = (j, d) }
        }
        return best?.index
    }

    /// 複数のユニットを収める（自動カメラの集団戦）。視点チームから見えないユニット・倒れたヒーローは除く。
    private func framingAim(_ ids: [EntityID], state s: SimState, viewer: Team?) -> CameraAim {
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(ids.count)
        for id in ids {
            guard let i = s.index(of: id) else { continue }
            let u = s.units[i]
            guard u.isAlive, u.hero?.isDead != true else { continue }
            if let viewer, !s.isVisible(i, to: viewer) { continue }
            let p = units.worldPositionOf(id) ?? worldPosition(u.pos)
            points.append(SIMD2(p.x, p.z))
        }
        var aim = CameraAim(kind: .framing, subject: ids.first)
        guard let fit = CameraRig.framing(points, aspectRatio: viewAspect) else {
            // 誰も映せない（全員倒れた・霧に入った）: 主役の追従として扱う（倒れた主役は代わりの味方へ）
            if let first = ids.first {
                var follow = followAim(first, state: s, viewer: viewer)
                follow.lead = nil
                return follow
            }
            return aim
        }
        aim.target = fit.focus
        aim.lead = 0
        aim.fitZoom = Double(fit.distance / CameraRig.baseDistance)
        return aim
    }

    /// 一時停止中（sync が呼ばれない）に観戦者が視点チームを切り替えた: 描画を一度だけ同期して見え方・ゾーンの色を合わせ、
    /// 霧は落ち着くまで更新を続ける（停止中は sim が変わらないので、落ち着いた後は何もしない）。
    private func refreshVisionWhilePaused(rig: CameraRig, dt: Float) {
        if !hasSyncedViewer || syncedViewer != controller.viewerTeam {
            // 見え方のフェードを一度で終える長さ（フェードは dt × 9 で進む）
            sync(events: [], dt: 0.25, rig: rig)
        }
        if let fog, !fog.isSettled {
            syncFogVision()
            fog.update(state: controller.state, dt: dt)
        }
    }

    /// 観戦者の視界（全体 / Blue / Red）の切替を霧へ反映する。全体視点で始まる観戦は、読み込み幕が上がるまで
    /// 透明な霧の板を描いて準備しておく（WorldWarmup.prepareSpectatorFog）。
    private func syncFogVision() {
        guard let fog else { return }
        if fog.isShowingWarmup {
            guard controller.isPresentationReady else { return }
            fog.endWarmupDisplay()
        }
        let want = controller.viewerTeam
        if fog.team != want { fog.setTeam(want) }
    }

    // MARK: 設定・破棄

    /// 設定の反映。画質の変更（利用者の選んだ画質の範囲内での自動調整を含む）では何も作らない:
    /// 放出体の上限・粒子数・軌跡・環境パーティクルは事前に作ったものの有効/無効と値の書き換えだけで切り替える。
    func apply(settings new: RenderSettings) {
        settings = new
        vfx.apply(quality: new.quality)
        skillDirector.player.apply(quality: new.quality)
        projectiles.apply(quality: new.quality)
        ambient.apply(quality: new.quality)
        if !new.showDamageNumbers { overlay?.clear() }
    }

    func teardown() {
        director?.stop()
        OverheadBar.zoomScale = 1
        cameraLink.renderedFocus = nil
        finishWarmup()
        vfx.clear()
        skillDirector.clear()
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
