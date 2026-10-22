import simd
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// Star Core の終幕: カメラの撮り方（地図の中・台座や塔に入らない・Core が隠れない・寄り → 切り替え → 回り込み → 引きの構図、
/// 最初だけの揺れ、動きを減らす設定）と、HUD の終了の流れ（Core の破壊の通知 → 終幕で HUD を隠す → バナー → 続ける、
/// 降参・シーク/再同期で終わった状態・画面確認の終了はバナーから、巻き戻し・置き換え・退出）。
@MainActor
final class CoreFinaleTests: XCTestCase {
    private let maps: [(String, MapDefinition)] = [("standard", .standard), ("brawl", .brawl)]

    private func gamePose(focus: SIMD2<Float>, distance: Float = CameraRig.baseDistance) -> CameraPose {
        CameraPose(position: SIMD3(focus.x, 0, focus.y) + CameraRig.offset(distance: distance), yaw: 0,
                   pitch: -CameraRig.pitchDegrees * .pi / 180)
    }

    private func shot(_ team: Team, _ map: MapDefinition, heroes: [SIMD2<Float>] = [], reducedMotion: Bool = false)
        -> CoreFinaleShot {
        CoreFinaleShot(team: team, map: map, heroes: heroes, reducedMotion: reducedMotion, aspect: CameraRig.designAspect)
    }

    // MARK: 姿勢の計算

    func testFramingPutsTheTargetAtTheRequestedScreenPosition() {
        let target = SIMD3<Float>(40, 2.6, -50)
        for (p, screen) in [(SIMD3<Float>(48, 9, -42), SIMD2<Float>(0.3, -0.06)), (SIMD3<Float>(30, 4, -60), SIMD2<Float>(-0.4, 0.2)),
                            (SIMD3<Float>(40, 12, -38), SIMD2<Float>(0, 0))] {
            let pose = CameraPose.framing(target, at: screen, from: p, aspect: CameraRig.designAspect)
            let got = pose.screen(of: target, aspect: CameraRig.designAspect)
            XCTAssertEqual(got?.x ?? 9, screen.x, accuracy: 0.002)
            XCTAssertEqual(got?.y ?? 9, screen.y, accuracy: 0.002)
            // ロールなし: 右の向きは水平
            XCTAssertEqual(pose.orientation.act([1, 0, 0]).y, 0, accuracy: 1e-5)
        }
        // ゲームカメラと同じ向き（yaw 0・pitch -56°）は CameraRig.orientation と一致する
        let game = gamePose(focus: SIMD2(30, -30))
        let a = game.orientation.act([0, 0, -1]), b = CameraRig.orientation.act([0, 0, -1])
        XCTAssertLessThan(simd_distance(a, b), 1e-5)
    }

    func testDestroyedCoreAndTrigger() throws {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 5))
        sim.step()
        var s = sim.state
        XCTAssertNil(CoreFinale.destroyedCore(in: s), "試合中")
        let red = try XCTUnwrap(s.units.firstIndex { $0.kind == .core && $0.team == .red })
        s.units[red].isAlive = false
        s.units[red].hp = 0
        s.units[red].deathTime = s.time
        s.phase = .ended
        s.winner = .blue
        s.endReason = .surrender
        XCTAssertNil(CoreFinale.destroyedCore(in: s), "降参で終わった試合は終幕を流さない")
        s.endReason = .coreDestroyed
        let core = try XCTUnwrap(CoreFinale.destroyedCore(in: s))
        XCTAssertEqual(core.team, .red)
        XCTAssertEqual(core.deathTime, s.time)
        XCTAssertEqual(CoreFinale.remainingUntilResult(s) ?? 0, TowerTimeline.finaleResult, accuracy: 1e-9)
        s.time += 2
        XCTAssertEqual(CoreFinale.remainingUntilResult(s) ?? 0, TowerTimeline.finaleResult - 2, accuracy: 1e-9,
                       "残りは Core が壊れた時刻から数える")
        XCTAssertTrue(CoreFinale.isTrigger(.matchEnded(winner: .blue, reason: .coreDestroyed)))
        XCTAssertFalse(CoreFinale.isTrigger(.matchEnded(winner: .blue, reason: .surrender)))
        XCTAssertFalse(CoreFinale.isTrigger(.matchEnded(winner: nil, reason: .aborted)))
    }

    // MARK: 撮り方

    /// 両チームの Core・標準と乱闘の地図: 低い視点・回り込み・引きの構図の全区間で、カメラは地図の中、台座・塔・泉・壁の外、
    /// Core への視線は遮られない。結晶は画面の中に映り、引きの構図では Core が右寄せ（左が空く）。
    func testShotsStayInsideTheMapClearOfStructuresAndFrameTheCore() {
        let M = MapScene.mapMeters
        let aspect = CameraRig.designAspect
        for (name, map) in maps {
            for team in Team.players {
                let s = shot(team, map)
                let tag = "\(name) \(team)"
                XCTAssertEqual(CoreFinaleShot.violations(core: s.core, azimuth: s.azimuth, sweep: s.sweep, map: map), 0, tag)
                let chosen = CoreFinaleShot.candidates(core: s.core, map: map).first { $0.azimuth == s.azimuth && $0.sweep == s.sweep }
                XCTAssertEqual(chosen?.leftClutter, 0, "\(tag) 引きの構図の左（バナーの場所）に塔・泉を入れない")
                let crystal = s.core + SIMD3(0, 4.2, 0)
                var t = TowerTimeline.finalePushEnd
                while t <= TowerTimeline.finaleSettleEnd + 1 {
                    let p = s.pose(at: t, game: gamePose(focus: SIMD2(s.core.x, s.core.z)))
                    XCTAssertTrue(p.position.x > 1 && p.position.x < M - 1 && p.position.z < -1 && p.position.z > -(M - 1),
                                  "\(tag) t=\(t) 地図の中: \(p.position)")
                    XCTAssertGreaterThanOrEqual(simd_distance(SIMD2(p.position.x, p.position.z), SIMD2(s.core.x, s.core.z)),
                                                CoreFinaleShot.platformClearance - 0.01, "\(tag) t=\(t) 台座の外")
                    XCTAssertGreaterThan(p.position.y, 1.5, "\(tag) t=\(t)")
                    let c = p.screen(of: crystal, aspect: aspect)
                    XCTAssertNotNil(c, "\(tag) t=\(t)")
                    if let c {
                        XCTAssertLessThan(abs(c.x), 0.85, "\(tag) t=\(t) 結晶が画面の中")
                        XCTAssertLessThan(abs(c.y), 0.85, "\(tag) t=\(t) 結晶が画面の中")
                    }
                    t += 0.05
                }
                let wide = s.pose(at: TowerTimeline.finaleResult, game: gamePose(focus: .zero))
                XCTAssertEqual(wide, s.widePose)
                let anchor = wide.screen(of: s.core + SIMD3(0, CoreFinaleShot.wideAnchor, 0), aspect: aspect)
                XCTAssertEqual(anchor?.x ?? 0, CoreFinaleShot.wideScreen.x, accuracy: 0.01, "\(tag) Core を右寄せ")
                XCTAssertGreaterThan(anchor?.x ?? 0, 0.15, tag)
                XCTAssertLessThan(wide.pitch, -0.2, "\(tag) 引きの構図は見下ろす")
                XCTAssertEqual(s.pose(at: .infinity, game: gamePose(focus: .zero)), s.widePose, "\(tag) 終わった後は引きの構図で止まる")
            }
        }
    }

    /// 寄りはゲームカメラから始まり（遠ければ Core を中心にしたゲームカメラから）、切り替えは 0.6 秒の 1 回だけ。
    /// その後は滑らか（1 フレームの移動が小さい）。揺れは最初だけ。
    func testPushStartsFromTheGameCameraAndCutsOnlyOnce() {
        let s = shot(.red, .standard)
        let near = gamePose(focus: SIMD2(s.core.x - 6, s.core.z + 4))
        let start = s.pose(at: 0, game: near)
        XCTAssertLessThan(simd_distance(start.position, near.position), CoreFinaleShot.shakeAmplitude * 1.25,
                          "近ければ今のゲームカメラから寄る（揺れの分だけずれる）")
        XCTAssertEqual(start.pitch, near.pitch, accuracy: 1e-5)
        let far = gamePose(focus: SIMD2(30, -30))
        let farStart = s.pose(at: 0, game: far)
        let focus = farStart.position + farStart.forward * (-farStart.position.y / farStart.forward.y)
        XCTAssertLessThan(simd_distance(SIMD2(focus.x, focus.z), SIMD2(s.core.x, s.core.z)), 0.3,
                          "遠ければ Core を中心にしたゲームカメラから（地図を横切って流さない）")
        let end = s.pose(at: TowerTimeline.finalePushEnd - 1e-4, game: near)
        XCTAssertLessThan(simd_distance(end.position, s.core), 13, "Core へ寄る")
        XCTAssertGreaterThan(end.position.y, 6, "寄りは上から（台座・結晶に入らない）")

        let dt = 1.0 / 60
        var cuts = 0
        var last = s.pose(at: 0, game: near)
        var t = dt
        while t <= TowerTimeline.finaleSettleEnd + 0.5 {
            let p = s.pose(at: t, game: near)
            let step = simd_distance(p.position, last.position)
            if step > 0.6 {
                cuts += 1
                XCTAssertEqual(t, TowerTimeline.finalePushEnd, accuracy: dt * 1.01, "切り替えは寄りの終わりだけ")
            } else if t > TowerTimeline.finalePushEnd + dt {
                XCTAssertLessThan(step, 0.25, "t=\(t) 回り込み・引きは滑らか")
                XCTAssertLessThan(abs(CameraPose.wrapAngle(p.yaw - last.yaw)), 0.05, "t=\(t)")
            }
            last = p
            t += dt
        }
        XCTAssertEqual(cuts, 1)
        // 揺れ: 寄りの終わりと同じゲームカメラ（寄りで動かない）なら、動きは揺れだけ。最初の 0.4 秒だけ小さく揺れる
        let still = CameraPose(position: s.core + SIMD3(0, CoreFinaleShot.pushLook, 0) - near.forward * CoreFinaleShot.pushDistance,
                               yaw: near.yaw, pitch: near.pitch)
        var early: Float = 0, late: Float = 0
        var u = 0.0
        while u < TowerTimeline.finalePushEnd {
            let d = simd_distance(s.pose(at: u, game: still).position, still.position)
            if u < CoreFinaleShot.shakeEnd { early = max(early, d) } else { late = max(late, d) }
            u += dt
        }
        XCTAssertGreaterThan(early, 0.01, "決着の瞬間に揺らす")
        XCTAssertLessThanOrEqual(early, CoreFinaleShot.shakeAmplitude * 1.25, "揺れは小さい")
        XCTAssertLessThan(late, 1e-4, "揺れは最初だけ")
    }

    func testReducedMotionHoldsStillShots() {
        let s = shot(.blue, .standard, reducedMotion: true)
        let game = gamePose(focus: SIMD2(40, -40))
        XCTAssertEqual(s.pose(at: 0.1, game: game), game, "寄らずにゲームカメラのまま")
        XCTAssertEqual(s.pose(at: 0.5, game: game), game)
        let low = s.pose(at: TowerTimeline.finalePushEnd, game: game)
        XCTAssertEqual(s.pose(at: 2.0, game: game), low, "回り込まない")
        XCTAssertEqual(s.pose(at: TowerTimeline.finaleOrbitEnd - 0.01, game: game), low)
        XCTAssertEqual(s.pose(at: TowerTimeline.finaleOrbitEnd, game: game), s.widePose, "引きの構図へは切り替えで")
        XCTAssertEqual(s.pose(at: 9, game: game), s.widePose)
    }

    /// 手前のヒーローで結晶が隠れる向きは避ける（同じ状態なら全員同じ向き）。
    func testHeroesStandingInFrontChangeTheAngle() {
        let map = MapDefinition.standard
        let base = shot(.red, map)
        let core = SIMD2(base.core.x, base.core.z)
        // 既定の向きの回り込みの途中のカメラと Core の間に 3 人立たせる
        let cam = base.position(azimuth: base.orbitAzimuth(at: 2), radius: 7.2, height: 2)
        let between = (SIMD2(cam.x, cam.z) - core)
        let heroes = [0.45, 0.6, 0.75].map { core + between * Float($0) }
        let candidates = CoreFinaleShot.candidates(core: base.core, map: map)
        let before = candidates.first { $0.azimuth == base.azimuth && $0.sweep == base.sweep }!
        let moved = shot(.red, map, heroes: heroes)
        XCTAssertTrue(moved.azimuth != base.azimuth || moved.sweep != base.sweep, "隠れる向きを避けて回り込む")
        let after = candidates.first { $0.azimuth == moved.azimuth && $0.sweep == moved.sweep }!
        XCTAssertEqual(after.problems, 0, "地図の制約は守る")
        XCTAssertLessThan(CoreFinaleShot.heroOcclusion(core: core, samples: after.samples, heroes: heroes),
                          CoreFinaleShot.heroOcclusion(core: core, samples: before.samples, heroes: heroes))
        XCTAssertEqual(shot(.red, map, heroes: heroes), moved, "同じ状態からは同じ撮り方（全員の画面で同じ）")
    }

    /// 演出の姿勢は update の後に重ね、次の update でゲームカメラ（既定の向き）へ戻る。ゲームカメラのばねは裏で追従を続ける。
    func testRigPresentsTheShotAndFallsBackToTheGameCamera() {
        let rig = CameraRig()
        let M = MapScene.mapMeters
        rig.update(CameraDrive(target: SIMD2(30, -30), zoom: 1), dt: 0, mapMeters: M)
        let game = rig.gamePose
        XCTAssertEqual(rig.camera.position, game.position)
        let s = shot(.blue, .standard)
        rig.present(s.widePose)
        XCTAssertTrue(rig.isPresenting)
        XCTAssertEqual(rig.camera.position, s.widePose.position)
        XCTAssertLessThan(simd_distance(rig.camera.orientation.act([0, 0, -1]), s.widePose.forward), 1e-5)
        rig.update(CameraDrive(target: SIMD2(32, -30), zoom: 1), dt: 1.0 / 60, mapMeters: M)
        XCTAssertFalse(rig.isPresenting)
        XCTAssertLessThan(simd_distance(rig.camera.orientation.act([0, 0, -1]), CameraRig.orientation.act([0, 0, -1])), 1e-6,
                          "次の update で既定の向き")
        XCTAssertGreaterThan(rig.gamePose.position.x, game.position.x, "ゲームカメラは追従を続ける")
        XCTAssertEqual(rig.groundFootprint(aspectRatio: CameraRig.designAspect).count, 4)
    }

    func testOverheadBarsHideOnlyWhileTheCinematicShotIsShown() {
        let s = shot(.red, .standard)
        XCTAssertFalse(s.hidesOverheadBars(at: 0.3), "寄りの間はゲームカメラの向き")
        XCTAssertTrue(s.hidesOverheadBars(at: TowerTimeline.finalePushEnd))
        XCTAssertTrue(s.hidesOverheadBars(at: .infinity))
        let run = CoreFinaleRun(team: .red, shot: s, deathTime: 100, skipped: false, cameraMode: .followHero)
        XCTAssertEqual(run.elapsed(presentationTime: 101.5), 1.5, accuracy: 1e-9)
        var skipped = run
        skipped.skipped = true
        XCTAssertEqual(skipped.elapsed(presentationTime: 100), .infinity, "通知を受けずに終わった状態: 引きの構図から")
    }

    // MARK: HUD

    private func start(_ config: MatchConfig) -> (BattleController, HUDModel, AppModel) {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: config))
        let m = HUDModel(controller: c)
        m.start(app: app, onFinish: { _ in })
        return (c, m, app)
    }

    /// Core を壊して終わった状態（sim の終わり方と同じ値）。
    private func coreDestroyed(_ s: SimState, loser: Team) -> SimState {
        var s = s
        if let i = s.units.firstIndex(where: { $0.kind == .core && $0.team == loser }) {
            s.units[i].isAlive = false
            s.units[i].hp = 0
            s.units[i].deathTime = s.time
        }
        s.phase = .ended
        s.winner = loser.opponent
        s.endReason = .coreDestroyed
        return s
    }

    /// Core の破壊の通知 → 終幕（HUD を隠す・パネルを開かない）→ バナー（左寄せ）→ 続ける。
    func testCoreDestroyedPlaysTheFinaleBeforeTheBanner() async throws {
        let (c, m, app) = start(MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 7))
        defer { m.stop() }
        for _ in 0..<30 { c.frame(dt: Balance.dt) }
        app.audio.playMusic(.battle)
        m.openPanel(.scoreboard)
        XCTAssertEqual(m.panel, .scoreboard)
        c.restore(coreDestroyed(c.state, loser: .red))
        m.handle([.matchEnded(winner: .blue, reason: .coreDestroyed)])
        XCTAssertEqual(m.endPhase, .finale(.victory, .coreDestroyed))
        XCTAssertTrue(m.endPhase?.isFinale == true)
        XCTAssertNil(m.panel, "開いていたパネルは閉じる")
        XCTAssertFalse(m.canControl)
        XCTAssertNil(app.audio.currentTrack, "決着で戦闘 BGM を止める")
        m.openPanel(.pause)
        XCTAssertNil(m.panel, "終幕の間は一時停止メニューも開かない")
        XCTAssertFalse(c.isPaused)
        m.refresh()
        XCTAssertEqual(m.endPhase, .finale(.victory, .coreDestroyed), "15Hz の更新で飛ばさない")
        m.finishFinale()
        XCTAssertEqual(m.endPhase, .banner(.victory, .coreDestroyed))
        XCTAssertTrue(m.endFollowsFinale, "バナーを引きの構図の左へ")
        m.finishFinale()
        XCTAssertEqual(m.endPhase, .banner(.victory, .coreDestroyed), "二度は進めない")
        // バナーの後に「続ける」
        try await Task.sleep(for: .seconds(HUDModel.endBannerDuration + 0.3))
        XCTAssertEqual(m.endPhase, .prompt(.victory, .coreDestroyed))
    }

    /// 終幕の残りの時間が過ぎるとバナーへ進む（Core が壊れてから 5.2 秒。ここでは壊れた時刻を前へずらして短くする）。
    func testFinaleAdvancesToTheBannerOnTime() async throws {
        let (c, m, _) = start(MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 8))
        defer { m.stop() }
        for _ in 0..<30 { c.frame(dt: Balance.dt) }
        var s = coreDestroyed(c.state, loser: .blue)
        let i = try XCTUnwrap(s.units.firstIndex { $0.kind == .core && $0.team == .blue })
        s.units[i].deathTime = s.time - (TowerTimeline.finaleResult - 0.3)
        c.restore(s)
        m.handle([.matchEnded(winner: .red, reason: .coreDestroyed)])
        XCTAssertEqual(m.endPhase, .finale(.defeat, .coreDestroyed))
        try await Task.sleep(for: .seconds(0.8))
        XCTAssertEqual(m.endPhase, .banner(.defeat, .coreDestroyed))
    }

    /// 降参・時間切れ、通知を受けずに終わった状態（シーク・再同期）、画面確認の終了はバナーから（終幕なし）。
    func testOtherEndsGoStraightToTheBanner() {
        do {
            let (c, m, _) = start(MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 9))
            defer { m.stop() }
            var s = c.state
            s.phase = .ended
            s.winner = .red
            s.endReason = .surrender
            c.restore(s)
            m.handle([.matchEnded(winner: .red, reason: .surrender)])
            XCTAssertEqual(m.endPhase, .banner(.defeat, .surrender))
            XCTAssertFalse(m.endFollowsFinale)
        }
        do {
            let (c, m, _) = start(MatchFactory.botMatch(seed: 9))
            defer { m.stop() }
            c.restore(coreDestroyed(c.state, loser: .red))
            m.refresh()
            XCTAssertEqual(m.endPhase, .banner(.teamWin(.blue), .coreDestroyed), "終わった時刻へ飛んだ: 終幕なし")
            XCTAssertTrue(m.endFollowsFinale, "描画側は引きの構図で止まるので、バナーは左へ")
            XCTAssertTrue(HUDSpectatorEndCardRule.isVisible(m))
        }
        do {
            let (_, m, _) = start(MatchFactory.botMatch(seed: 10))
            defer { m.stop() }
            m.debugEnd(winner: .blue)
            XCTAssertEqual(m.endPhase, .banner(.teamWin(.blue), .coreDestroyed), "画面確認の終了はバナーから")
            XCTAssertFalse(m.endFollowsFinale, "Core は壊れていない: 従来の中央のバナー")
        }
        do {
            // Core が壊れていない（合成の通知だけ）: 終幕は流さない
            let (_, m, _) = start(MatchFactory.botMatch(seed: 11))
            defer { m.stop() }
            m.handle([.matchEnded(winner: .blue, reason: .coreDestroyed)])
            XCTAssertEqual(m.endPhase, .banner(.teamWin(.blue), .coreDestroyed))
        }
    }

    /// 観戦・リプレイ: 終幕の間は再生終了のカード・パネル・戦術マップを出さず、バナーの時刻からカードとドックに戻る。
    func testSeekableSpectatorSeesTheCardOnlyAfterTheFinale() {
        let (c, m, _) = start(MatchFactory.botMatch(seed: 12))
        defer { m.stop() }
        for _ in 0..<30 { c.frame(dt: Balance.dt) }
        c.restore(coreDestroyed(c.state, loser: .blue))
        m.handle([.matchEnded(winner: .red, reason: .coreDestroyed)])
        XCTAssertEqual(m.endPhase, .finale(.teamWin(.red), .coreDestroyed))
        XCTAssertFalse(HUDSpectatorEndCardRule.isVisible(m), "終幕の間はカードを出さない")
        m.openPanel(.scoreboard)
        XCTAssertNil(m.panel)
        m.setTacticalMap(open: true)
        XCTAssertFalse(m.isTacticalMapOpen)
        m.toggleSpectatorPause()
        XCTAssertFalse(c.isPaused)
        m.finishFinale()
        XCTAssertTrue(HUDSpectatorEndCardRule.isVisible(m))
        m.openPanel(.scoreboard)
        XCTAssertEqual(m.panel, .scoreboard, "終幕の後は従来どおり開ける")
    }

    /// 終幕の途中で終わる前へ巻き戻す（観戦のシーク・オンラインの再同期）: 終幕をやめて試合中へ戻り、戦闘 BGM を再開する。
    func testRewindingDuringTheFinaleRestoresTheMatch() {
        let (c, m, app) = start(MatchFactory.botMatch(seed: 13))
        defer { m.stop() }
        for _ in 0..<30 { c.frame(dt: Balance.dt) }
        let alive = c.state
        c.restore(coreDestroyed(alive, loser: .red))
        m.handle([.matchEnded(winner: .blue, reason: .coreDestroyed)])
        XCTAssertTrue(m.endPhase?.isFinale == true)
        c.restore(alive)
        m.refresh()
        XCTAssertNil(m.endPhase, "終わる前へ戻ったら終幕を解除")
        XCTAssertFalse(m.endFollowsFinale)
        XCTAssertEqual(app.audio.currentTrack, .battle)
        // もう一度決着すれば、また終幕から
        c.restore(coreDestroyed(c.state, loser: .red))
        m.handle([.matchEnded(winner: .blue, reason: .coreDestroyed)])
        XCTAssertTrue(m.endPhase?.isFinale == true)
        // 終わった状態のまま置き換わった（描画側は引きの構図へ飛ぶ）: バナーへ進める
        c.restore(c.state)
        m.refresh()
        XCTAssertEqual(m.endPhase, .banner(.teamWin(.blue), .coreDestroyed))
    }

    /// 終幕の途中で試合を出る: 結果は 1 回だけ渡り、その後に終幕の続き（バナー）へ進まない。
    func testLeavingDuringTheFinale() async throws {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P",
                                                                                          seed: 14)))
        let m = HUDModel(controller: c)
        var outcomes = 0
        m.start(app: app, onFinish: { _ in outcomes += 1 })
        for _ in 0..<30 { c.frame(dt: Balance.dt) }
        var s = coreDestroyed(c.state, loser: .red)
        let i = try XCTUnwrap(s.units.firstIndex { $0.kind == .core && $0.team == .red })
        s.units[i].deathTime = s.time - (TowerTimeline.finaleResult - 0.2)
        c.restore(s)
        m.handle([.matchEnded(winner: .blue, reason: .coreDestroyed)])
        XCTAssertTrue(m.endPhase?.isFinale == true)
        m.leave()
        m.stop()
        XCTAssertEqual(outcomes, 1)
        try await Task.sleep(for: .seconds(0.5))
        XCTAssertTrue(m.endPhase?.isFinale == true, "退出の後は進めない")
        m.continueAfterEnd()
        XCTAssertEqual(outcomes, 1, "結果は 1 回だけ")
    }
}
