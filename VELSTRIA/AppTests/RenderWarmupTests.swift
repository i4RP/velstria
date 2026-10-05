import QuartzCore
import RealityKit
import simd
import UIKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

// battle-renderer（性能）: 読み込み幕の裏の準備（BattleWorld.makeWarmupPlan）の後、プレイ中にアセットを 1 つも作らないこと。
// 実際の描画世界（BattleWorld）をレンダラーと同じ順で組み、ウォームアップを実行してから headless で試合を進め、
// AssetLedger の live（幕が上がった後の生成）が 0 件であることを確かめる。例外は設けない。

@MainActor
final class RenderWarmupTests: XCTestCase {
    private struct Harness {
        let controller: BattleController
        let world: BattleWorld
        let rig: CameraRig
        let arView: ARView
        let anchor: AnchorEntity
        var events: [SimEvent] = []
    }

    /// BattleRenderer.buildWorld と同じ順: 世界を作る → カメラを合わせる → 準備の段を全て実行 → 幕の裏で数フレーム → 片付け。
    private func makeHarness(_ config: MatchConfig, quality: RenderQuality, governed: RenderQuality? = nil,
                             finishWarmup: Bool = true) -> Harness {
        AssetLedger.beginLoading()
        let controller = BattleController(launch: BattleLaunch(config: config))
        let arView = ARView(frame: CGRect(x: 0, y: 0, width: 844, height: 390), cameraMode: .nonAR,
                            automaticallyConfigureSession: false)
        let overlay = CombatTextOverlay(frame: arView.bounds)
        let settings = RenderSettings(quality: quality, frameRate: 60, showDamageNumbers: true, colorblind: false)
        let world = BattleWorld(controller: controller, settings: settings, groundImage: nil, arView: arView, overlay: overlay)
        // BattleRenderer.buildWorld と同じく、ユーザー設定の上限で作ってから自動調整後の値を反映する
        if let governed {
            world.apply(settings: RenderSettings(quality: governed, frameRate: 60, showDamageNumbers: true, colorblind: false))
        }
        let rig = CameraRig()
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(rig.camera)
        anchor.addChild(world.root)
        arView.scene.addAnchor(anchor)
        world.updateCamera(rig: rig, dt: 0, snap: true)
        var timings: [(String, Double)] = []
        for step in world.makeWarmupPlan() {
            let t0 = CACurrentMediaTime()
            step.run()
            timings.append((step.name, (CACurrentMediaTime() - t0) * 1000))
        }
        let total = timings.reduce(0) { $0 + $1.1 }
        let slowest = timings.sorted { $0.1 > $1.1 }.prefix(6).map { String(format: "%@ %.1f", $0.0, $0.1) }
        print(String(format: "warmup plan: %d steps, %.0f ms (Debug, simulator). slowest: ", timings.count, total)
              + slowest.joined(separator: ", "))
        XCTAssertTrue(world.isWarmupGalleryOpen, "準備の後は陳列が開いている")
        for _ in 0..<4 {
            world.sync(events: [], dt: 1.0 / 60, rig: rig)
            world.updateCamera(rig: rig, dt: 0, snap: true)
        }
        if finishWarmup {
            world.finishWarmup()
            XCTAssertFalse(world.isWarmupGalleryOpen)
        }
        AssetLedger.beginLive()
        return Harness(controller: controller, world: world, rig: rig, arView: arView, anchor: anchor)
    }

    /// 試合を until 秒まで進める（frameDt 毎に描画同期。speed 倍速）。
    private func play(_ h: inout Harness, until seconds: Double, frameDt: Double = 1.0 / 30, speed: Double = 4,
                      each: ((inout Harness) -> Void)? = nil) {
        var buffer: [SimEvent] = []
        let token = h.controller.subscribe { buffer.append(contentsOf: $0) }
        h.controller.speed = speed
        h.controller.markPresentationReady()
        while h.controller.state.time < seconds && !h.controller.isEnded {
            h.controller.frame(dt: frameDt)
            each?(&h)
            h.world.sync(events: buffer, dt: Float(frameDt), rig: h.rig)
            buffer.removeAll(keepingCapacity: true)
            h.world.updateCamera(rig: h.rig, dt: Float(frameDt), snap: false)
        }
        h.controller.unsubscribe(token)
    }

    private func assertNothingCreatedWhileLive(file: StaticString = #filePath, line: UInt = #line) {
        let snap = AssetLedger.snapshot()
        XCTAssertEqual(snap.liveTotal, 0, "プレイ中のアセット生成: \(snap.live)\n" + snap.liveSamples.joined(separator: "\n"),
                       file: file, line: line)
    }

    override func tearDown() {
        AssetLedger.end()
        super.tearDown()
    }

    // MARK: 試合を通して 0 件

    /// perf_run.sh と同じ観戦試合（seed 20261001）を高画質で 9 分（ジャングル 0:30・ワーム 2:00・巨像 8:00 を含む）。
    func testSpectateMatchCreatesNothingWhileLiveHigh() {
        var h = makeHarness(MatchFactory.botMatch(seed: 20261001), quality: .preset(.high))
        XCTAssertGreaterThanOrEqual(AssetLedger.snapshot().loading["emitter"] ?? 0, RenderQuality.preset(.high).maxEmitters,
                                    "放出体は読み込み中に作り切る")
        var sawColossus = false, sawWyrm = false, peakMonsters = 0
        play(&h, until: 9 * 60) { h in
            let s = h.controller.state
            var monsters = 0
            for u in s.units where u.kind == .monster && u.isAlive {
                monsters += 1
                if u.monster?.kind == .ancientColossus { sawColossus = true }
                if u.monster?.kind == .astralWyrm { sawWyrm = true }
            }
            peakMonsters = max(peakMonsters, monsters)
        }
        XCTAssertGreaterThanOrEqual(h.controller.state.time, 8 * 60 + 30, "試合が 8:30 を越えて進んだ")
        XCTAssertTrue(sawWyrm, "ワーム（2:00）が出た")
        XCTAssertTrue(sawColossus, "巨像（8:00）が出た")
        XCTAssertGreaterThanOrEqual(peakMonsters, 28, "0:30 にジャングル 28 体が同時に出た")
        let st = h.world.vfx.stats
        print("vfx: spawns \(st.spawns) borrowed \(st.borrowed) stolen \(st.stolen) peak "
              + VFXPreset.allCases.map { "\($0)=\(st.peak[$0] ?? 0)" }.joined(separator: " ")
              + " / trails peak \(h.world.projectiles.peakTrails) skipped \(h.world.projectiles.trailsSkipped)")
        XCTAssertEqual(h.world.projectiles.trailsSkipped, 0, "軌跡のプールは足りている")
        assertNothingCreatedWhileLive()
    }

    /// 実時間（1 倍速・60 fps の描画同期）で perf_run.sh と同じ 150 秒。
    func testSpectateAtRealSpeedCreatesNothingWhileLive() {
        var h = makeHarness(MatchFactory.botMatch(seed: 20261001), quality: .preset(.high))
        play(&h, until: 150, frameDt: 1.0 / 60, speed: 1)
        let st = h.world.vfx.stats
        print("vfx(1x): spawns \(st.spawns) borrowed \(st.borrowed) stolen \(st.stolen) peak "
              + VFXPreset.allCases.map { "\($0)=\(st.peak[$0] ?? 0)" }.joined(separator: " ")
              + " / trails peak \(h.world.projectiles.peakTrails)")
        assertNothingCreatedWhileLive()
    }

    /// 低画質（放出体の上限 14・軌跡なし）でも 2:30 まで 0 件。途中で画質を上げ下げしても作らない。
    func testLowQualityAndQualityChangesCreateNothing() {
        var h = makeHarness(MatchFactory.botMatch(seed: 7), quality: .preset(.low))
        play(&h, until: 75)
        // 適応の調整（中・高への変更を含む: 上限がプールを超えても作らずに使い回す）
        h.world.apply(settings: RenderSettings(quality: .preset(.high), frameRate: 60, showDamageNumbers: true, colorblind: false))
        XCTAssertTrue(h.world.ambient.isEnabled, "環境パーティクルは作り直さずに切り替える")
        play(&h, until: 110)
        h.world.apply(settings: RenderSettings(quality: .preset(.medium), frameRate: 30, showDamageNumbers: false, colorblind: false))
        XCTAssertFalse(h.world.ambient.isEnabled)
        play(&h, until: 150)
        assertNothingCreatedWhileLive()
    }

    /// 高画質で始めて、試合中の自動調整（粒子数・上限・軌跡・環境パーティクルを下げて戻す）でも作らない。
    func testAdaptiveQualityWithinChosenLevelCreatesNothing() {
        var h = makeHarness(MatchFactory.botMatch(seed: 3), quality: .preset(.high))
        XCTAssertTrue(h.world.ambient.isEnabled)
        var step = 0
        play(&h, until: 160) { h in
            step += 1
            guard step % 240 == 0 else { return }
            var q = RenderQuality.preset(.high)
            switch (step / 240) % 3 {
            case 0: break
            case 1:
                q.particleScale = 0.5
                q.maxEmitters = 16
                q.projectileTrails = false
                q.ambientParticles = false
            default:
                q = .preset(.medium)
            }
            h.world.apply(settings: RenderSettings(quality: q, frameRate: 60, showDamageNumbers: true, colorblind: false))
        }
        assertNothingCreatedWhileLive()
    }

    /// 低電力モード・高温で始まった試合（自動調整で画質を下げた状態で開始）でも、プールはユーザー設定の上限で作られ、
    /// 画質が戻った後の軌跡・環境パーティクル・演出を作らずに出せる。
    func testMatchStartingThrottledStillPoolsForTheUserLevel() {
        var throttled = RenderQuality.preset(.high)
        throttled.particleScale = 0.6
        throttled.maxEmitters = 26
        throttled.projectileTrails = false
        throttled.ambientParticles = false
        let full = makeHarness(MatchFactory.botMatch(seed: 3), quality: .preset(.high))
        let fullEmitters = full.world.vfx.pooledEmitterCount
        AssetLedger.end()
        var h = makeHarness(MatchFactory.botMatch(seed: 3), quality: .preset(.high), governed: throttled)
        XCTAssertEqual(h.world.projectiles.pooledTrailCount, ProjectileLayer.trailPoolSize, "軌跡は高画質の分だけ作る")
        XCTAssertEqual(h.world.vfx.pooledEmitterCount, fullEmitters, "放出体のプールは高画質と同じ大きさ")
        XCTAssertFalse(h.world.ambient.isEnabled, "幕が上がる時点では自動調整後の画質（環境パーティクルなし）")
        // 画質が戻る（低電力モード解除・冷却）
        play(&h, until: 60) { h in
            if h.controller.state.time > 20, !h.world.ambient.isEnabled {
                h.world.apply(settings: RenderSettings(quality: .preset(.high), frameRate: 60, showDamageNumbers: true,
                                                       colorblind: false))
            }
        }
        XCTAssertTrue(h.world.ambient.isEnabled)
        assertNothingCreatedWhileLive()
    }

    /// 人間の試合（霧・照準・自分の HP バー）。全スキル・スペルの照準を全色で出しても作らない。
    func testHumanMatchAimAndFogCreateNothing() {
        let config = MatchFactory.standardMatch(humanHeroID: "H009", humanName: "Tester", seed: 11)
        var h = makeHarness(config, quality: .preset(.medium))
        let master = h.controller.ctx.master
        guard let id = h.controller.humanHeroID, let u = h.controller.state.unit(id), let hero = u.hero,
              let def = master.hero(hero.heroID) else { return XCTFail("人間ヒーローがいない") }
        var targetings: [(AimIndicator.Kind, SkillTargeting)] = []
        for slot in SkillSlot.actives {
            if let sk = master.skill(hero: hero.heroID, slot: slot) {
                targetings.append((.skill(slot), SkillCatalog.targeting(for: sk, hero: def)))
            }
        }
        for (k, spell) in hero.spells.enumerated() {
            if let t = HUDSpellAim.targeting(spellID: spell) { targetings.append((.spell(k), t)) }
        }
        XCTAssertFalse(targetings.isEmpty)
        var frame = 0
        play(&h, until: 90, speed: 2) { h in
            frame += 1
            let k = frame / 20
            guard k < targetings.count * 3 else {
                h.controller.aim = nil
                return
            }
            let (kind, t) = targetings[k % targetings.count]
            var tt = t
            if k / targetings.count == 1 { tt.targetsAllies = true }
            guard let me = h.controller.humanHeroID.flatMap({ h.controller.state.unit($0) }) else { return }
            h.controller.aim = AimIndicator(kind: kind, targeting: tt, origin: me.pos, target: me.pos + Vec2(600, 200),
                                            isCancelling: k / targetings.count == 2)
        }
        assertNothingCreatedWhileLive()
    }

    /// 練習モード（人形・開始レベル）でも 0 件。
    func testPracticeMatchCreatesNothingWhileLive() {
        let config = MatchFactory.practiceMatch(humanHeroID: "H003", humanName: "T",
                                                options: PracticeOptions(startLevel: 3), tutorial: false, seed: 1)
        var h = makeHarness(config, quality: .preset(.medium))
        XCTAssertGreaterThan(h.world.units.pooledCount(.dummy), 0, "人形のプールを作る")
        play(&h, until: 70)
        assertNothingCreatedWhileLive()
    }

    /// ヒーロー別の通常攻撃（24 人を 3 試合に分けて、高画質）: 武器の軌跡・ヒーロー別の弾と粒子の尾・発射炎・着弾を
    /// 出しても、幕が上がった後に何も作らない。軌跡のプールも足りる。
    func testHeroAttackFXCreateNothingWhileLive() {
        let rosters: [[String]] = [
            ["H003", "H004", "H005", "H009", "H010", "H011", "H015", "H016", "H017", "H021"],
            ["H022", "H023", "H001", "H002", "H006", "H007", "H008", "H012", "H013", "H014"],
            ["H018", "H019", "H020", "H024", "H001", "H012", "H003", "H010", "H017", "H022"],
        ]
        var trailFrames = 0, heroShots = 0, launched = 0
        for (k, roster) in rosters.enumerated() {
            var config = MatchFactory.botMatch(seed: 20261001 + UInt64(k))
            for i in config.players.indices { config.players[i].heroID = roster[i] }
            var h = makeHarness(config, quality: .preset(.high))
            let melee = roster.filter { HeroFXProfiles.profile($0)?.isRanged == false }.count
            XCTAssertGreaterThanOrEqual(h.world.units.weaponTrailCount, melee, "近接のヒーローに武器の軌跡を作る")
            play(&h, until: 110)
            XCTAssertEqual(h.world.projectiles.trailsSkipped, 0, "軌跡のプールは足りている（\(roster)）")
            trailFrames += h.world.units.weaponTrailFrames
            heroShots += h.world.projectiles.heroShotsShown
            launched += h.world.projectiles.launchedFromWeapon
            print("hero fx \(k): trails \(h.world.units.weaponTrailCount) frames \(h.world.units.weaponTrailFrames) "
                  + "shots \(h.world.projectiles.heroShotsShown) from weapon \(h.world.projectiles.launchedFromWeapon) "
                  + "trail peak \(h.world.projectiles.peakTrails) vfx peak "
                  + VFXPreset.allCases.map { "\($0)=\(h.world.vfx.stats.peak[$0] ?? 0)" }.joined(separator: " "))
            assertNothingCreatedWhileLive()
            h.world.teardown()
            AssetLedger.end()
        }
        XCTAssertGreaterThan(trailFrames, 0, "武器の軌跡を描いた")
        XCTAssertGreaterThan(heroShots, 0, "ヒーロー別の弾を出した")
        XCTAssertGreaterThan(launched, 0, "発射位置（武器の先端・弓・手）から出した")
    }

    // MARK: 陳列・プール

    /// 陳列はカメラの注視点に開き、全プリセットの放出体・クリーチャー・投射物・ゾーン・ヒーローを描き、片付けで全て戻る。
    func testWarmupGalleryShowsEverythingInFrontOfCameraAndCleansUp() {
        AssetLedger.beginLoading()
        let controller = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 20261001)))
        let arView = ARView(frame: CGRect(x: 0, y: 0, width: 844, height: 390), cameraMode: .nonAR,
                            automaticallyConfigureSession: false)
        let world = BattleWorld(controller: controller, settings: RenderSettings(quality: .preset(.low), frameRate: 60,
                                                                                showDamageNumbers: true, colorblind: false),
                                groundImage: nil, arView: arView, overlay: CombatTextOverlay(frame: arView.bounds))
        let rig = CameraRig()
        world.updateCamera(rig: rig, dt: 0, snap: true)
        let poolsBefore = world.vfx.pooledEmitterCount
        XCTAssertEqual(poolsBefore, 0, "放出体のプールは準備の段で作る（世界の生成では作らない）")
        for step in world.makeWarmupPlan() { step.run() }
        guard let gallery = world.gallery else { return XCTFail("陳列が開いていない") }
        // 注視点（カメラの追従先）に置く
        let (focus, _) = world.cameraFocus()
        XCTAssertLessThan(simd_distance(SIMD2(gallery.center.x, gallery.center.z), focus), 0.01)
        XCTAssertGreaterThan(gallery.sampleCount, 100, "マテリアル・メッシュの見本")
        // 低画質の上限（14）を超えて、全種類（帰還ループ・瞬間移動・範囲・軌跡を含む）を再生している
        let pooled = world.vfx.pooledEmitterCount
        XCTAssertGreaterThan(pooled, RenderQuality.preset(.low).maxEmitters)
        XCTAssertGreaterThanOrEqual(world.vfx.activeCount, pooled, "全ての放出体を一度ずつ再生")
        XCTAssertEqual(world.projectiles.pooledCount(.minionBolt(.blue)), 0, "投射物のプールは全て陳列中")
        XCTAssertEqual(world.zones.pooledCount, 0, "ゾーンのプールは全て陳列中")
        XCTAssertEqual(world.units.pooledCount(.monster(.ancientColossus)), 0, "巨像（1 体）も陳列中")
        world.finishWarmup()
        XCTAssertEqual(world.projectiles.pooledCount(.minionBolt(.blue)), 24)
        XCTAssertEqual(world.units.pooledCount(.monster(.ancientColossus)), 1)
        XCTAssertNil(world.gallery)
        XCTAssertNil(gallery.root.parent, "陳列は外す")
        XCTAssertEqual(world.vfx.activeCount, 0, "放出体・輪・閃光はプールへ戻る")
        XCTAssertEqual(world.vfx.pooledEmitterCount, pooled)
        XCTAssertEqual(world.zones.pooledCount, BattleWorld.zonePoolSize)
        // 片付けは何度呼んでもよい
        world.finishWarmup()
        world.teardown()
        AssetLedger.end()
    }

    /// 片付けを呼ばずに試合が始まっても（sim が進んだら）陳列を片付ける。
    func testGalleryClosesWhenSimAdvances() {
        var h = makeHarness(MatchFactory.botMatch(seed: 5), quality: .preset(.medium), finishWarmup: false)
        XCTAssertTrue(h.world.isWarmupGalleryOpen)
        play(&h, until: 1)
        XCTAssertFalse(h.world.isWarmupGalleryOpen)
        assertNothingCreatedWhileLive()
    }

    /// 放出体は種類ごとの部品を付けたまま使い回す（再生のたびに ParticleEmitterComponent を構築しない・外さない）。
    func testVFXReusesAttachedEmitterComponents() {
        AssetLedger.beginLoading()
        let materials = RenderMaterials(colorblind: false)
        let vfx = VFXSystem(quality: .preset(.medium), materials: materials, meshes: UnitMeshLibrary())
        vfx.prewarmEmitters()
        vfx.prewarmMeshFX()
        // 輪・閃光の色は BattleWorld の準備（plannedUnlitMaterials）で作る。ここでは使う 2 色だけ
        materials.prewarmUnlit([(FXRings.white, VFXSystem.ringAlpha, true), (FXRings.smite, VFXSystem.flashAlpha, true)])
        let pooled = vfx.pooledEmitterCount
        XCTAssertGreaterThan(pooled, RenderQuality.preset(.medium).maxEmitters)
        AssetLedger.beginLive()
        for k in 0..<400 {
            let preset = VFXPreset.allCases[k % VFXPreset.allCases.count]
            if preset == .recallLoop {
                vfx.startLoop(id: EntityID(k), at: .zero, color: .white)
                vfx.stopLoop(id: EntityID(k))
            } else {
                vfx.spawn(preset, at: SIMD3(Float(k % 7), 1, 0), color: k % 2 == 0 ? .red : .cyan, scale: 1 + Float(k % 3) * 0.3,
                          important: k % 5 == 0, life: k % 4 == 0 ? 1.2 : nil)
            }
            vfx.ring(at: .zero, color: FXRings.white, from: 0.3, to: 1, duration: 0.3)
            vfx.flash(at: .zero, color: FXRings.smite, radius: 0.5, duration: 0.2)
            vfx.update(dt: 1.0 / 30)
        }
        vfx.update(dt: 5)
        XCTAssertEqual(vfx.activeCount, 0)
        XCTAssertEqual(vfx.pooledEmitterCount, pooled, "放出体の総数は変わらない")
        for e in vfx.root.children where e.components[ModelComponent.self] == nil {
            XCTAssertNotNil(e.components[ParticleEmitterComponent.self], "回収しても部品は付けたまま")
        }
        assertNothingCreatedWhileLive()
    }

    /// プールの大きさ: モンスターは地図のキャンプ構成どおり、ミニオンは実測の最大以上。
    func testCreaturePoolSizesCoverMapAndWaves() {
        let sizes = UnitLayer.creaturePoolSizes(map: .standard, dummySpots: 0)
        func size(_ k: CreatureKey) -> Int { sizes.first { $0.key == k }?.count ?? 0 }
        XCTAssertEqual(size(.monster(.campLarge)), 8)
        XCTAssertEqual(size(.monster(.campSmall)), 16)
        XCTAssertEqual(size(.monster(.astralWyrm)), 1)
        XCTAssertEqual(size(.monster(.ancientColossus)), 1)
        // 1 波 = 近接 3（10:00 以降 4）+ 遠隔 3 × 3 レーン。2 波以上が重なっても足りる
        let wave = SpawnSystem.waveComposition(waveIndex: 2, time: 11 * 60)
        let melee = wave.filter { $0 == .melee }.count * 3, ranged = wave.filter { $0 == .ranged }.count * 3
        XCTAssertGreaterThanOrEqual(size(.minion(.melee, .blue)), melee * 2)
        XCTAssertGreaterThanOrEqual(size(.minion(.ranged, .red)), ranged * 2)
        XCTAssertNil(sizes.first { $0.key == .dummy })
    }

    /// 扇形のキャッシュは縁の太さを区別する（ゾーンと照準で同じ角度でも太さが混ざらない）。
    func testSectorCacheDistinguishesThickness() {
        let lib = UnitMeshLibrary()
        let thin = lib.sector(halfAngle: .pi / 4, outline: true, thicknessRatio: 0.03)
        let thick = lib.sector(halfAngle: .pi / 4, outline: true, thicknessRatio: 0.2)
        XCTAssertFalse(thin === thick)
        XCTAssertTrue(thin === lib.sector(halfAngle: .pi / 4, outline: true, thicknessRatio: 0.03))
    }

    /// 環境パーティクルは読み込み時に作り、画質で切り替えるだけ。
    func testAmbientParticlesToggleWithoutCreating() {
        let amb = AmbientParticles(map: .standard, teams: TeamColors(colorblind: false), texture: nil, quality: .preset(.medium))
        XCTAssertFalse(amb.isEnabled)
        XCTAssertEqual(amb.emitterCount, 4 + AmbientParticles.riverSegments)
        AssetLedger.beginLoading()
        AssetLedger.beginLive()
        amb.apply(quality: .preset(.high))
        XCTAssertTrue(amb.isEnabled)
        amb.apply(quality: .preset(.low))
        XCTAssertFalse(amb.isEnabled)
        assertNothingCreatedWhileLive()
    }
}
