import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// シーク・再同期（presentationEpoch の変化）の後に前の時刻の演出が残らない: クリーチャーは死亡演出なしで作り直す、
/// 瓦礫になった構造物が元に戻る（B5）、弾・予告・粒子・戦闘数値を捨てる（発動演出なし）、HUD の通知・終了演出を捨てて
/// 戦闘 BGM を再開する（B34）。
@MainActor
final class PresentationResetTests: XCTestCase {
    private func frame(_ s: SimState, dt: Float = 1.0 / 60, viewer: Team? = nil) -> RenderFrame {
        RenderFrame(state: s, alpha: 1, dt: dt, time: 0, viewerTeam: viewer, humanID: nil, focusID: nil,
                    ended: s.phase == .ended, winner: s.winner)
    }

    private func layer() -> UnitLayer {
        let l = UnitLayer(materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary(), text: TextMeshCache(), master: .shared)
        l.prewarm()
        return l
    }

    private func creatureCount(_ s: SimState) -> Int {
        s.units.filter { $0.kind == .minion || $0.kind == .monster || $0.kind == .dummy }.count
    }

    // MARK: ユニット

    func testCreaturesAreRecycledWithoutDeathFadeAfterAJumpBack() {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 11))
        for _ in 0..<30 { sim.step() }
        let early = sim.state
        // 最初のウェーブ（0:20）が出て進んでいる時刻
        for _ in 0..<(30 * 25) { sim.step() }
        let late = sim.state
        XCTAssertGreaterThan(creatureCount(late), creatureCount(early))

        // 作り直さないと、消えた個体の死亡演出が残る（巻き戻しで敵味方が一斉に倒れて見える）
        let plain = layer()
        plain.sync(frame(late, dt: 1))
        plain.sync(frame(early))
        XCTAssertGreaterThan(plain.dyingCount, 0)

        let reset = layer()
        reset.sync(frame(late, dt: 1))
        let pooledBefore = reset.pooledCount(.minion(.melee, .blue))
        reset.resetForPresentationEpoch()
        XCTAssertEqual(reset.liveCount, reset.heroes.count + reset.structures.count, "クリーチャーは全てプールへ戻る")
        XCTAssertGreaterThan(reset.pooledCount(.minion(.melee, .blue)), pooledBefore)
        reset.sync(frame(early, dt: BattleWorld.presentationSnapDt))
        XCTAssertEqual(reset.dyingCount, 0, "死亡演出なし")
        XCTAssertEqual(reset.liveCount, reset.heroes.count + reset.structures.count + creatureCount(early))
        for u in early.units where u.kind == .minion || u.kind == .monster {
            XCTAssertNotNil(reset.creature(u.id), "今の状態の個体を作り直す")
            XCTAssertEqual(reset.creature(u.id)?.visibility ?? 0, 1, accuracy: 0.001, "フェードインせずに表示")
        }
        // 前へ飛んでも同じ
        reset.resetForPresentationEpoch()
        reset.sync(frame(late, dt: BattleWorld.presentationSnapDt))
        XCTAssertEqual(reset.dyingCount, 0)
        XCTAssertEqual(reset.liveCount, reset.heroes.count + reset.structures.count + creatureCount(late))
    }

    /// B5: 瓦礫の構造物は、置き換わった状態で生きていれば元の姿へ戻る（オンラインの再同期・シーク）。
    func testDestroyedStructureRevivesWhenTheStateSaysAlive() throws {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 12))
        let alive = sim.state
        let ti = try XCTUnwrap(alive.units.indices.first { alive.units[$0].kind == .tower })
        let id = alive.units[ti].id
        var destroyed = alive
        destroyed.units[ti].hp = 0
        destroyed.units[ti].isAlive = false

        let l = layer()
        l.sync(frame(alive))
        let v = try XCTUnwrap(l.structure(id))
        XCTAssertFalse(v.destroyed)
        l.sync(frame(destroyed))
        XCTAssertTrue(v.destroyed)
        XCTAssertTrue(v.isCollapsing, "通常の破壊は崩れる演出")
        XCTAssertFalse(v.bar.root.isEnabled)

        // 状態が置き換わって生きている → 元の姿
        l.resetForPresentationEpoch()
        l.sync(frame(alive))
        XCTAssertFalse(v.destroyed, "瓦礫のまま残らない")
        XCTAssertTrue(v.bar.root.isEnabled)
        XCTAssertFalse(v.isCollapsing)

        // シークで破壊後へ飛んだ時は崩れる演出なしで瓦礫
        l.resetForPresentationEpoch()
        l.sync(frame(destroyed))
        XCTAssertTrue(v.destroyed)
        XCTAssertFalse(v.isCollapsing, "シーク後は崩れる途中を見せない")

        // 作り直しの合図が無くても（再同期の取りこぼし）、生きている状態なら戻る
        l.sync(frame(alive))
        XCTAssertFalse(v.destroyed)
    }

    // MARK: 弾・予告・粒子・戦闘数値

    func testProjectilesAndZonesAreFlushedWithoutTriggerEffects() throws {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 13))
        for _ in 0..<30 { sim.step() }
        var state = sim.state
        let hero = try XCTUnwrap(state.units.first { $0.kind == .hero && $0.team == .blue })
        let projectiles = ProjectileLayer(materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary(), master: .shared,
                                          quality: .preset(.medium))
        let zones = ZoneLayer(materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary())
        var triggers = 0
        zones.onTrigger = { _, _, _, _ in triggers += 1 }
        let payload = HitPayload(damage: 50, damageType: .magic, source: .skill(.skill3), affectsEnemies: true)
        state.projectiles = [Projectile(id: 900, ownerID: hero.id, team: hero.team, pos: hero.pos,
                                        motion: .linear(direction: Vec2(1, 0), maxDistance: 900), speed: 1000,
                                        payload: HitPayload(damage: 1, damageType: .physical, source: .basicAttack),
                                        visual: "basic_attack")]
        state.zones = [AreaZone(id: 901, ownerID: hero.id, team: hero.team, center: hero.pos, radius: 300, delay: 1.5,
                                payload: payload, visual: "")]
        projectiles.sync(frame(state)) { _ in 1 }
        zones.sync(frame(state))
        XCTAssertEqual(projectiles.count, 1)
        XCTAssertTrue(zones.isShown(901))

        // 巻き戻した先には弾も予告も無い
        projectiles.resetForPresentationEpoch()
        zones.resetForPresentationEpoch()
        XCTAssertEqual(projectiles.count, 0)
        XCTAssertEqual(zones.count, 0)
        XCTAssertFalse(zones.isShown(901))
        var empty = state
        empty.projectiles = []
        empty.zones = []
        projectiles.sync(frame(empty)) { _ in 1 }
        zones.sync(frame(empty))
        XCTAssertEqual(triggers, 0, "消えた予告の発動演出を出さない")
        XCTAssertEqual(zones.count, 0, "フェードアウトも残さない")

        // 状態にあるものは出し直す（プールから）
        let pooled = zones.pooledCount
        projectiles.resetForPresentationEpoch()
        zones.resetForPresentationEpoch()
        projectiles.sync(frame(state)) { _ in 1 }
        zones.sync(frame(state))
        XCTAssertEqual(projectiles.count, 1)
        XCTAssertTrue(zones.isShown(901))
        XCTAssertEqual(zones.pooledCount, pooled - 1)
        XCTAssertEqual(triggers, 0)
    }

    func testVFXResetStopsEverythingButKeepsStats() {
        let vfx = VFXSystem(quality: .preset(.low), materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary())
        vfx.spawn(.hitSpark, at: .zero, color: .white)
        vfx.spawn(.levelUp, at: .zero, color: .yellow, important: true)
        vfx.startLoop(id: 5, at: .zero, color: .blue)
        vfx.ring(at: .zero, color: RGB(1, 1, 1), from: 0.5, to: 2, duration: 3)
        vfx.flash(at: .zero, color: RGB(1, 1, 1), radius: 1, duration: 3)
        let spawns = vfx.stats.spawns
        XCTAssertGreaterThan(vfx.activeCount, 0)
        vfx.resetForPresentationEpoch()
        XCTAssertEqual(vfx.activeCount, 0)
        XCTAssertFalse(vfx.hasLoop(5), "詠唱ループも止める")
        XCTAssertEqual(vfx.loopCount, 0)
        XCTAssertEqual(vfx.stats.spawns, spawns, "計測は残す")
        vfx.startLoop(id: 5, at: .zero, color: .blue)
        XCTAssertTrue(vfx.hasLoop(5), "止めた後に付け直せる")
    }

    // MARK: 世界全体

    private struct WorldHarness {
        let controller: BattleController
        let world: BattleWorld
        let rig: CameraRig
        let overlay: CombatTextOverlay
    }

    private func makeWorld(_ launch: BattleLaunch) -> WorldHarness {
        let controller = BattleController(launch: launch)
        let arView = ARView(frame: CGRect(x: 0, y: 0, width: 844, height: 390), cameraMode: .nonAR,
                            automaticallyConfigureSession: false)
        let overlay = CombatTextOverlay(frame: arView.bounds)
        let world = BattleWorld(controller: controller,
                                settings: RenderSettings(quality: .preset(.low), frameRate: 60, showDamageNumbers: true,
                                                         colorblind: false),
                                groundImage: nil, arView: arView, overlay: overlay)
        let rig = CameraRig()
        world.updateCamera(rig: rig, dt: 0, snap: true)
        return WorldHarness(controller: controller, world: world, rig: rig, overlay: overlay)
    }

    func testWorldResetAfterJumpingBackShowsOnlyTheNewState() throws {
        let h = makeWorld(BattleLaunch(config: MatchFactory.botMatch(seed: 14)))
        let c = h.controller
        var events: [SimEvent] = []
        c.subscribe { events.append(contentsOf: $0) }
        h.world.sync(events: [], dt: 1.0 / 60, rig: h.rig)
        let start = c.state
        for k in 0..<(30 * 28) {
            c.frame(dt: Balance.dt)
            if k % 3 == 0 {
                h.world.sync(events: events, dt: 3 * Float(Balance.dt), rig: h.rig)
                events.removeAll()
            }
        }
        h.overlay.spawn(text: "123", world: .zero, style: .gold, seed: 1)
        h.world.vfx.ring(at: .zero, color: RGB(1, 1, 1), from: 0.5, to: 2, duration: 5)
        XCTAssertGreaterThan(h.world.units.liveCount, h.world.units.heroes.count + h.world.units.structures.count)

        // 巻き戻し（シークと同じく状態を置き換える。オンラインの再同期と同じ経路）
        let epoch = c.presentationEpoch
        c.restore(start)
        XCTAssertGreaterThan(c.presentationEpoch, epoch)
        h.world.resetForPresentationEpoch(rig: h.rig)
        XCTAssertEqual(h.world.units.dyingCount, 0)
        XCTAssertEqual(h.world.units.liveCount, h.world.units.heroes.count + h.world.units.structures.count + creatureCount(start))
        XCTAssertEqual(h.world.projectiles.count, start.projectiles.filter { !$0.done }.count)
        XCTAssertEqual(h.world.zones.count, start.zones.count)
        XCTAssertEqual(h.world.vfx.activeCount, 0, "前の時刻の粒子・輪・閃光を捨てる")
        XCTAssertEqual(h.overlay.activeCount, 0, "戦闘数値を捨てる")
        for u in start.units where u.kind == .hero {
            let v = try XCTUnwrap(h.world.units.hero(u.id))
            XCTAssertEqual(v.visibility, 1, accuracy: 0.001)
        }
    }

    func testWorldResetRevivesTowersAndRestartsChannelLoops() throws {
        let h = makeWorld(BattleLaunch(config: MatchFactory.botMatch(seed: 15)))
        let c = h.controller
        h.world.sync(events: [], dt: 1.0 / 60, rig: h.rig)
        let original = c.state
        let ti = try XCTUnwrap(original.units.indices.first { original.units[$0].kind == .tower && original.units[$0].team == .red })
        let towerID = original.units[ti].id
        var ruined = original
        ruined.units[ti].hp = 0
        ruined.units[ti].isAlive = false
        let hi = try XCTUnwrap(ruined.units.indices.first { ruined.units[$0].kind == .hero && ruined.units[$0].team == .blue })
        ruined.units[hi].hero?.channel = Channel(kind: .recall, duration: 8)

        c.restore(ruined)
        h.world.resetForPresentationEpoch(rig: h.rig)
        let tower = try XCTUnwrap(h.world.units.structure(towerID))
        XCTAssertTrue(tower.destroyed)
        XCTAssertFalse(tower.isCollapsing, "飛んだ先で壊れていた塔は崩れる途中を見せない")
        XCTAssertTrue(h.world.vfx.hasLoop(ruined.units[hi].id), "詠唱中のヒーローの帰還ループを付け直す")

        c.restore(original)
        h.world.resetForPresentationEpoch(rig: h.rig)
        XCTAssertFalse(tower.destroyed, "B5: 戻った先で生きている塔は元の姿")
        XCTAssertFalse(h.world.vfx.hasLoop(ruined.units[hi].id), "詠唱していない時刻へ戻ったらループを消す")
    }

    // MARK: 描画ループ（BattleRenderer の判断）

    func testRendererDropsOnlyEventsFromBeforeTheDiscontinuity() {
        typealias Epochs = BattleRenderer.PresentationEpochs
        var e = Epochs(epoch: 3)
        // 変化なし
        XCTAssertFalse(e.noteEvents(epoch: 3))
        XCTAssertFalse(e.beginFrame(epoch: 3).reset)

        // シーク: フレームの間で置き換わり、次の描画の前にイベントは届いていない → 作り直して溜まっている分を捨てる
        let seek = e.beginFrame(epoch: 4)
        XCTAssertTrue(seek.reset)
        XCTAssertTrue(seek.dropPending, "置き換え前に溜まったイベントは前の時刻のもの")
        XCTAssertFalse(e.beginFrame(epoch: 4).reset, "同じ不連続で二度は作り直さない")
        XCTAssertFalse(e.noteEvents(epoch: 4), "作り直した後のイベントは捨てない")

        // オンラインの再同期: frame の中で「置き換え → 届いた分を進める」。最初のイベントで前の分を捨て、作り直しても残す
        XCTAssertTrue(e.noteEvents(epoch: 5), "置き換え後に届いた最初のイベントより前の分を捨てる")
        XCTAssertFalse(e.noteEvents(epoch: 5), "同じ不連続の後のイベントは溜め続ける")
        let resync = e.beginFrame(epoch: 5)
        XCTAssertTrue(resync.reset)
        XCTAssertFalse(resync.dropPending, "置き換え後のイベントは作り直しの後に描く")

        // 読み込み中に変わっていた（幕が上がった最初のフレームで作り直す）
        var loading = Epochs(epoch: 0)
        XCTAssertTrue(loading.beginFrame(epoch: 2).reset)

        // 一時停止中のコマ送りは演出も描き、大きな飛び（UI テストの早送り）は状態だけ合わせる
        XCTAssertTrue(Epochs.showsFrameStepEvents(from: 100, to: 101))
        XCTAssertTrue(Epochs.showsFrameStepEvents(from: 100, to: 100 + Epochs.frameStepEventLimit))
        XCTAssertFalse(Epochs.showsFrameStepEvents(from: 100, to: 700))
    }

    // MARK: HUD

    private func kill(_ s: SimState) -> SimEvent {
        let blue = s.heroIndices(team: .blue).map { s.units[$0].id }
        let red = s.heroIndices(team: .red).map { s.units[$0].id }
        return .heroKilled(HeroKillEvent(victimID: red[0], killerID: blue[0], assistIDs: [], bounty: 300, isFirstBlood: true,
                                         multiKill: 1, killerStreak: 1, isShutdown: false))
    }

    /// B34: 終わりから巻き戻すと終了演出が消え、止めた戦闘 BGM が戻る。キルフィード・告知・トーストも捨てる。
    func testHUDResetClearsNoticesAndEndPhaseAndRestartsMusic() {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 16)))
        let model = HUDModel(controller: c)
        model.start(app: app, onFinish: { _ in })
        defer { model.stop() }
        app.audio.playMusic(.battle)
        XCTAssertEqual(app.audio.currentTrack, .battle)
        model.handle([kill(c.state), .announcement(.towerDestroyed(team: .red, lane: .mid, tier: .outer))])
        model.showToast("x", symbol: "bag.fill", isError: false)
        XCTAssertEqual(model.killFeed.count, 1)
        XCTAssertNotNil(model.banner)
        XCTAssertNotNil(model.toast)
        model.debugEnd(winner: .blue)
        XCTAssertNotNil(model.endPhase)
        XCTAssertNil(app.audio.currentTrack, "終了演出で戦闘 BGM を止める")

        // 状態が置き換わる（終わっていない時刻へ）
        c.restore(c.state)
        model.refresh()
        XCTAssertTrue(model.killFeed.isEmpty)
        XCTAssertNil(model.banner)
        XCTAssertNil(model.toast)
        XCTAssertNil(model.endPhase, "試合が終わっていなければ終了演出を解除")
        XCTAssertEqual(app.audio.currentTrack, .battle, "戦闘 BGM を再開")

        // 変化が無ければ何もしない
        model.handle([kill(c.state)])
        model.refresh()
        XCTAssertEqual(model.killFeed.count, 1)
    }

    /// 置き換えの後、refresh より先に届いた通知は残す（前の時刻の通知だけを捨てる）。
    func testHUDKeepsNoticesThatArriveAfterTheDiscontinuity() {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 19)))
        let model = HUDModel(controller: c)
        model.start(app: app, onFinish: { _ in })
        defer { model.stop() }
        model.handle([kill(c.state)])
        XCTAssertEqual(model.killFeed.count, 1)
        c.restore(c.state)
        model.handle([kill(c.state)])
        XCTAssertEqual(model.killFeed.count, 1, "前の時刻の通知は捨て、置き換え後に届いた通知は残す")
        model.refresh()
        XCTAssertEqual(model.killFeed.count, 1, "同じ不連続で二度は捨てない")
    }

    /// プレイヤー（オンラインの再同期）: 置き換え後も自分が死亡中なら死亡情報（倒した相手）を残し、生きていれば捨てる。
    func testPlayerResyncKeepsDeathInfoWhileStillDead() throws {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P",
                                                                                          seed: 21)))
        let model = HUDModel(controller: c)
        model.start(app: app, onFinish: { _ in })
        defer { model.stop() }
        let me = try XCTUnwrap(c.humanHeroID)
        let hi = try XCTUnwrap(c.humanIndex)
        let alive = c.state
        let killer = alive.units[try XCTUnwrap(alive.heroIndices(team: .red).first)]
        var dead = alive
        dead.units[hi].hero?.respawnTimer = 10
        c.restore(dead)
        model.refresh()
        model.handle([.unitDied(unitID: me, kind: .hero, team: .blue, killerID: killer.id, pos: alive.units[hi].pos)])
        XCTAssertEqual(model.deathInfo?.killerHeroID, killer.hero?.heroID)

        c.restore(dead)
        model.refresh()
        XCTAssertNotNil(model.deathInfo, "まだ死亡中なら倒した相手の表示を残す")
        c.restore(alive)
        model.handle([])
        XCTAssertNil(model.deathInfo, "生きている状態へ置き換わったら捨てる")
    }

    func testHUDKeepsTheEndWhenTheNewStateHasEnded() {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 17)))
        let model = HUDModel(controller: c)
        model.start(app: app, onFinish: { _ in })
        defer { model.stop() }
        app.audio.playMusic(.battle)
        var ended = c.state
        ended.phase = .ended
        ended.endReason = .coreDestroyed
        ended.winner = .red
        c.restore(ended)
        XCTAssertTrue(c.isEnded)
        model.refresh()
        XCTAssertNotNil(model.endPhase, "終わった時刻へ飛んだら終了演出")
        XCTAssertNil(app.audio.currentTrack, "終わった時刻では戦闘 BGM を戻さない")
    }

    func testHUDResetsAfterASeekWhilePaused() async {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 18)))
        let model = HUDModel(controller: c)
        model.start(app: app, onFinish: { _ in })
        defer { model.stop() }
        for _ in 0..<120 { c.frame(dt: Balance.dt) }
        model.toggleSpectatorPause()
        XCTAssertTrue(c.isPaused)
        model.handle([kill(c.state)])
        XCTAssertEqual(model.killFeed.count, 1)
        let hud = c.hudTick
        c.requestSeek(toTick: 30)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(60))
        while c.seekingToTick != nil && clock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(c.state.tick, 30)
        XCTAssertNotEqual(c.hudTick, hud, "一時停止中でも HUD が更新される")
        model.refresh()   // HUDTicker が hudTick の変化で呼ぶ
        XCTAssertTrue(model.killFeed.isEmpty)
        XCTAssertTrue(model.spectatorPaused, "一時停止は保つ")
        XCTAssertTrue(c.isPaused)
    }
}
