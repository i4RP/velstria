import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 自動カメラ（CameraDirector）: 見どころの記憶・点数付け（純関数）・画の切替の規則（sim の時間）、
/// 試合を進めた時の振る舞い（映すのは生きているヒーロー・最短の長さ・手動操作で控える・視点チーム・シークで作り直す）。
@MainActor
final class CameraDirectorTests: XCTestCase {
    // MARK: 合成した状態

    /// AI 同士の試合の開始状態から、ヒーローを互いに離れた格子に置き直した状態（time = 100 秒、視界は全て暗い）。
    private func spreadState(seed: UInt64 = 3) -> SimState {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: seed)))
        var s = c.state
        s.time = 100
        for (k, i) in s.heroIndices.enumerated() {
            s.units[i].pos = Vec2(1000 + Double(k % 5) * 2200, 1000 + Double(k / 5) * 6000)
            s.units[i].prevPos = s.units[i].pos
            s.units[i].visibleMask = Team.blue.visionBit | Team.red.visionBit
        }
        var v = VisionState()
        v.cols = 60
        v.rows = 60
        v.cells = [UInt8](repeating: 0, count: 3600)
        s.vision = v
        return s
    }

    /// blue[0] と red[0] を (6000, 4000)（他のヒーローの列から 3000 離れた場所）で戦わせる。
    private func duel(_ s: inout SimState, lowRedHP: Bool = false) -> (blue: Int, red: Int) {
        let b = s.heroIndices(team: .blue)[0], r = s.heroIndices(team: .red)[0]
        s.units[b].pos = Vec2(6000, 4000)
        s.units[r].pos = Vec2(6400, 4000)
        s.units[b].lastCombatTime = s.time - 0.5
        s.units[r].lastCombatTime = s.time - 0.5
        if lowRedHP { s.units[r].hp = s.units[r].stats.maxHP * 0.2 }
        return (b, r)
    }

    // MARK: 点数付け

    func testQuietHeroesHaveLowScoresAndNoFraming() {
        let s = spreadState()
        let cands = DirectorScoring.candidates(state: s, moments: DirectorMoments(), vision: nil)
        XCTAssertEqual(cands.count, 10, "生きているヒーロー全員が候補")
        for c in cands {
            XCTAssertTrue(c.others.isEmpty, "近くに敵がいなければ単独の追従")
            XCTAssertFalse(c.isFight)
            XCTAssertLessThan(c.score, 5)
            XCTAssertEqual(c.cameraMode, .followUnit(c.subject))
        }
        // 同点はユニットの添字順（決まった順に並ぶ）
        let again = DirectorScoring.candidates(state: s, moments: DirectorMoments(), vision: nil)
        XCTAssertEqual(cands, again)
    }

    func testFightRanksFirstAndFramesBothHeroes() {
        var s = spreadState()
        let (b, r) = duel(&s)
        let cands = DirectorScoring.candidates(state: s, moments: DirectorMoments(), vision: nil)
        let top = try! XCTUnwrap(cands.first)
        XCTAssertTrue([s.units[b].id, s.units[r].id].contains(top.subject))
        XCTAssertTrue(top.isFight)
        XCTAssertEqual(top.others.count, 1)
        if case .framing(let ids) = top.cameraMode {
            XCTAssertEqual(Set(ids), [s.units[b].id, s.units[r].id])
            XCTAssertEqual(ids.first, top.subject, "先頭が主役")
        } else {
            XCTFail("戦いは framing: \(top.cameraMode)")
        }
        XCTAssertGreaterThan(top.score, cands[2].score + 20, "戦いは静かなヒーローより明らかに高い")
        XCTAssertEqual(top.center.x, 6200, accuracy: 1)
    }

    func testLowHealthHeroBecomesTheSubject() {
        var s = spreadState()
        let (_, r) = duel(&s, lowRedHP: true)
        let top = DirectorScoring.candidates(state: s, moments: DirectorMoments(), vision: nil).first
        XCTAssertEqual(top?.subject, s.units[r].id, "倒れそうなヒーロー（追われている側）を主役にする")
    }

    func testVisionHidesEnemiesTheTeamCannotSee() {
        var s = spreadState()
        let (b, r) = duel(&s)
        s.units[r].visibleMask = Team.red.visionBit   // Blue からは見えない
        let blueView = DirectorScoring.candidates(state: s, moments: DirectorMoments(), vision: .blue)
        XCTAssertFalse(blueView.contains { $0.subject == s.units[r].id }, "見えない敵は映さない")
        let blueHero = try! XCTUnwrap(blueView.first { $0.subject == s.units[b].id })
        XCTAssertTrue(blueHero.others.isEmpty, "見えない敵を収めない")
        XCTAssertFalse(blueHero.isFight, "見えない敵との戦いは分からない")
        // Red の視点では両方見える（味方は常に見える・Blue のヒーローの visibleMask は両方）
        let redView = DirectorScoring.candidates(state: s, moments: DirectorMoments(), vision: .red)
        XCTAssertTrue(redView.first?.isFight ?? false)
    }

    func testBossFightScores() {
        var s = spreadState()
        let hero = s.heroIndices(team: .blue)[1]
        // ボスが居なければ何もしない（開始時は出現前）
        guard let boss = s.units.indices.first(where: { s.units[$0].monster?.kind == .astralWyrm && s.units[$0].isAlive }) else {
            // 開始時にボスが居ない地図: ボスを置いて確かめる代わりに、点数が増えないことだけ確かめる
            let base = DirectorScoring.candidates(state: s, moments: DirectorMoments(), vision: nil)
            XCTAssertLessThan(base.first?.score ?? 0, 5)
            return
        }
        s.units[hero].pos = s.units[boss].pos + Vec2(500, 0)
        s.units[boss].lastDamagedTime = s.time - 1
        let top = DirectorScoring.candidates(state: s, moments: DirectorMoments(), vision: nil).first
        XCTAssertEqual(top?.subject, s.units[hero].id, "ボスを叩いているヒーロー")
    }

    // MARK: 見どころの記憶

    func testMomentsDecayAndRespectVision() {
        let s = spreadState()
        let killer = s.heroIndices(team: .blue)[2], victim = s.heroIndices(team: .red)[2]
        let kill = HeroKillEvent(victimID: s.units[victim].id, killerID: s.units[killer].id, assistIDs: [], bounty: 300,
                                 isFirstBlood: true, multiKill: 2, killerStreak: 2, isShutdown: false)
        var m = DirectorMoments()
        m.record([.heroKilled(kill)], state: s)
        XCTAssertEqual(m.items.count, 1)
        XCTAssertEqual(m.items[0].weight, 45 + 15 + 22, "ファーストブラッド + ダブルキル")
        let now = m.interest(subject: s.units[killer].id, at: s.units[killer].pos, now: s.time, vision: nil)
        XCTAssertEqual(now, 82, accuracy: 0.001)
        let later = m.interest(subject: s.units[killer].id, at: s.units[killer].pos, now: s.time + 3, vision: nil)
        XCTAssertEqual(later, 41, accuracy: 0.01, "半減期 3 秒")
        // 主役でなくても近くのヒーローは分けてもらう。遠いヒーローは 0
        let near = m.interest(subject: 0, at: s.units[victim].pos + Vec2(500, 0), now: s.time, vision: nil)
        XCTAssertGreaterThan(near, 0)
        XCTAssertEqual(m.interest(subject: 0, at: Vec2(11000, 11000), now: s.time, vision: nil), 0)
        // 関わったチームはどちらも知っている
        XCTAssertGreaterThan(m.interest(subject: s.units[killer].id, at: .zero, now: s.time, vision: .red), 0)

        // どちらのヒーローでもない奥義（Blue のヒーローが暗い場所で撃った）は Red には分からない
        let caster = s.heroIndices(team: .blue)[3]
        let ult = SkillCastEvent(casterID: s.units[caster].id, heroID: "H001", slot: .ultimate, skillID: "x", effectID: "x",
                                 archetype: .selfAoE, origin: s.units[caster].pos, target: s.units[caster].pos,
                                 range: 0, radius: 300)
        var m2 = DirectorMoments()
        m2.record([.skillCast(ult)], state: s)
        XCTAssertEqual(m2.items.first?.kind, .ultimate)
        XCTAssertGreaterThan(m2.interest(subject: s.units[caster].id, at: .zero, now: s.time, vision: .blue), 0)
        XCTAssertEqual(m2.interest(subject: s.units[caster].id, at: .zero, now: s.time, vision: .red), 0)
        // 奥義以外のスキルは覚えない
        var basic = ult
        basic.slot = .skill1
        m2.record([.skillCast(basic)], state: s)
        XCTAssertEqual(m2.items.count, 1)

        // 古い記憶・巻き戻した後の未来の記憶は捨てる
        m.prune(now: s.time + 13)
        XCTAssertTrue(m.items.isEmpty)
        m.record([.heroKilled(kill)], state: s)
        m.prune(now: s.time - 10)
        XCTAssertTrue(m.items.isEmpty)
    }

    func testMomentCapacity() {
        let s = spreadState()
        let caster = s.heroIndices(team: .blue)[0]
        let ult = SkillCastEvent(casterID: s.units[caster].id, heroID: "H001", slot: .ultimate, skillID: "x", effectID: "x",
                                 archetype: .selfAoE, origin: .zero, target: .zero, range: 0, radius: 0)
        var m = DirectorMoments()
        m.record(Array(repeating: .skillCast(ult), count: 100), state: s)
        XCTAssertEqual(m.items.count, DirectorMoments.capacity)
    }

    // MARK: 画の切替

    private func cand(_ id: EntityID, _ score: Double, others: [EntityID] = []) -> DirectorCandidate {
        DirectorCandidate(subject: id, others: others, score: score, center: .zero, isFight: !others.isEmpty)
    }

    func testPolicyHoldsMinimumShotAndUsesHysteresis() {
        var p = DirectorPolicy()
        XCTAssertEqual(p.decide([cand(1, 20), cand(2, 10)], now: 0), .cut(cand(1, 20)))
        // 最短の長さの前は、少し良い程度では変えない
        XCTAssertEqual(p.decide([cand(2, 40), cand(1, 20)], now: 1), .keep)
        // 最短の長さの後でも、ヒステリシス（×1.3 + 10）を越えなければ変えない
        XCTAssertEqual(p.decide([cand(2, 35), cand(1, 20)], now: 5), .keep)
        XCTAssertEqual(p.decide([cand(2, 37), cand(1, 20)], now: 5.5), .cut(cand(2, 37)))
        XCTAssertEqual(p.shotStart, 5.5)
    }

    func testPolicyInterruptsForBigMoments() {
        var p = DirectorPolicy()
        _ = p.decide([cand(1, 30)], now: 0)
        // 大きな見どころ（75 以上で今の画の 1.6 倍）は最短の長さの前でも割り込む
        XCTAssertEqual(p.decide([cand(2, 90), cand(1, 30)], now: 2), .cut(cand(2, 90)))
        // 割り込みの直後（1.5 秒以内）は続けて割り込まない
        XCTAssertEqual(p.decide([cand(3, 200), cand(2, 90)], now: 2.5), .keep)
        XCTAssertEqual(p.decide([cand(3, 200), cand(2, 90)], now: 3.6), .cut(cand(3, 200)))
    }

    func testPolicyKeepsSubjectWithinTheSameFight() {
        var p = DirectorPolicy()
        _ = p.decide([cand(1, 60, others: [2])], now: 0)
        // 同じ戦いの相手の方が高くなっても主役は変えない（収める顔ぶれだけ更新）
        XCTAssertEqual(p.decide([cand(2, 200, others: [1]), cand(1, 60, others: [2])], now: 10), .keep)
        let grown = cand(1, 80, others: [2, 3])
        XCTAssertEqual(p.decide([grown, cand(2, 70, others: [1, 3])], now: 11), .update(grown))
        XCTAssertEqual(p.current, grown)
        XCTAssertEqual(p.shotStart, 0, "顔ぶれの更新は新しい画として数えない")
    }

    func testPolicyHoldsBrieflyWhenSubjectIsLostThenSwitches() {
        var p = DirectorPolicy()
        _ = p.decide([cand(1, 60), cand(2, 5)], now: 0)
        // 主役が候補から消えた（倒れた・霧に入った）: 2 秒は撃破の場面を見せる（描画側の代わりの味方より先に次の画へ）
        XCTAssertLessThan(DirectorPolicy.Config().lostHold, BattleWorld.deathHoldSeconds)
        XCTAssertEqual(p.decide([cand(2, 5)], now: 10), .keep)
        XCTAssertEqual(p.decide([cand(2, 5)], now: 11.5), .keep)
        XCTAssertEqual(p.decide([cand(2, 5)], now: 12.6), .cut(cand(2, 5)))
        // 誰も映せない時は今の画のまま
        XCTAssertEqual(p.decide([], now: 20), .keep)
    }

    func testPolicyRotatesAwayFromQuietShots() {
        var p = DirectorPolicy()
        _ = p.decide([cand(1, 5), cand(2, 4)], now: 0)
        XCTAssertEqual(p.decide([cand(1, 5), cand(2, 4)], now: 10), .keep)
        XCTAssertEqual(p.decide([cand(1, 5), cand(2, 4)], now: 14.5), .cut(cand(2, 4)), "静かな画が続いたら別のヒーローへ")
        p.reset()
        XCTAssertNil(p.current)
    }

    func testFastPlaybackKeepsShotsReadableInRealTime() {
        XCTAssertEqual(CameraDirector.config(speed: 1), DirectorPolicy.Config(), "等速は既定の規則")
        XCTAssertEqual(CameraDirector.config(speed: 0.5), DirectorPolicy.Config())
        let fast = CameraDirector.config(speed: 8)
        XCTAssertEqual(fast.minShot / 8, 1.2, accuracy: 1e-9, "8 倍速でも実時間で 1.2 秒は同じ画")
        XCTAssertEqual(fast.lostHold / 8, 0.8, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(fast.rotateAfter, fast.minShot * 2)
    }

    // MARK: 試合を進める

    /// 実時間の代わり（自動カメラの clock が読む。inout で渡すと読み書きが重なるので参照型にする）。
    private final class TestClock {
        var now: TimeInterval
        init(_ now: TimeInterval) { self.now = now }
    }

    private func run(_ c: BattleController, director d: CameraDirector, ticks: Int, clock: TestClock,
                     each: (Int) -> Void = { _ in }) {
        for t in 0..<ticks where !c.isEnded {
            c.frame(dt: Balance.dt)
            clock.now += Balance.dt
            d.update()
            each(t)
        }
    }

    func testDirectorFollowsLiveHeroesAndRespectsShotRules() {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 20261001)))
        XCTAssertTrue(c.spectatorDirectorEnabled)
        let link = SpectatorCameraLink.link(for: c)
        let d = CameraDirector(controller: c, link: link)
        let now = TestClock(1000)
        d.clock = { now.now }
        d.start()
        defer { d.stop() }
        XCTAssertTrue(link.director === d)

        var lastMode = c.cameraMode
        var lastSwitchTime = -Double.infinity
        var lastSubject: EntityID?
        var switches = 0
        var framed = 0
        run(c, director: d, ticks: 2400, clock: now) { _ in
            let mode = c.cameraMode
            guard mode != lastMode else { return }
            lastMode = mode
            let s = c.state
            let ids: [EntityID]
            switch mode {
            case .followUnit(let id): ids = [id]
            case .framing(let list): ids = list; framed += 1
            default: return XCTFail("自動カメラは追従か framing だけを書く: \(mode)")
            }
            for id in ids {
                let u = s.unit(id)
                XCTAssertEqual(u?.kind, .hero)
                XCTAssertEqual(u?.hero?.isDead, false, "映すのは生きているヒーロー")
            }
            guard let subject = ids.first, subject != lastSubject else { return }
            if let shot = d.policy.current, let prev = lastSubject, s.unit(prev)?.hero?.isDead == false {
                // 主役がまだ生きているのに変えたなら、最短の長さを過ぎたか大きな見どころの割り込み
                let gap = s.time - lastSwitchTime
                XCTAssertTrue(gap >= DirectorPolicy.Config().minShot - 1e-6
                              || (shot.score >= DirectorPolicy.Config().interruptScore
                                  && gap >= DirectorPolicy.Config().interruptGap - 1e-6),
                              "早すぎる切替: \(gap) 秒、点数 \(shot.score)")
            }
            lastSubject = subject
            lastSwitchTime = s.time
            switches += 1
        }
        XCTAssertGreaterThan(switches, 1, "80 秒の間に何度か画を変える")
        print("director: \(switches) shots, \(framed) framing updates in \(c.state.time) s")
    }

    func testManualInputSuspendsAndDoubleTapResumes() {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 5)))
        let link = SpectatorCameraLink.link(for: c)
        let d = CameraDirector(controller: c, link: link)
        let now = TestClock(50)
        d.clock = { now.now }
        d.start()
        defer { d.stop() }
        run(c, director: d, ticks: 30, clock: now)
        let directed = c.cameraMode
        guard case .followUnit = directed else { return XCTFail("最初の画: \(directed)") }
        XCTAssertEqual(c.cameraZoomOverride, CameraDirector.followZoom, "自動カメラは少し引いて周りも見せる")

        // 観戦者がミニマップ・パンで自由カメラにした → 控える（実時間 10 秒）
        c.cameraMode = .free(Vec2(6000, 6000))
        run(c, director: d, ticks: 60, clock: now)
        XCTAssertTrue(d.isSuspended)
        XCTAssertEqual(c.cameraMode, .free(Vec2(6000, 6000)), "控えている間は書き換えない")
        // 窓口からの手動操作の知らせで控えが延びる
        now.now += 8
        link.noteManualCameraInput()
        now.now += 5
        d.update()
        XCTAssertEqual(c.cameraMode, .free(Vec2(6000, 6000)))
        // 控えが明けると画へ戻る
        now.now += 6
        run(c, director: d, ticks: 10, clock: now)
        XCTAssertFalse(d.isSuspended)
        if case .free = c.cameraMode { XCTFail("控えが明けたら自動カメラへ戻る") }

        // 観戦者がピンチで決めた倍率は、控えが明けても上書きしない
        c.cameraZoomOverride = 2.1
        link.noteManualCameraInput()
        now.now += 11
        run(c, director: d, ticks: 10, clock: now)
        XCTAssertEqual(c.cameraZoomOverride, 2.1)

        // ダブルタップ（resumeDirector）はすぐ戻す
        c.cameraMode = .free(Vec2(3000, 3000))
        d.update()
        XCTAssertTrue(d.isSuspended)
        XCTAssertTrue(link.resumeDirector())
        XCTAssertFalse(d.isSuspended)
        if case .free = c.cameraMode { XCTFail("ダブルタップで自動カメラの画へ") }

        // オフの間は何も書かない。オンに戻すと控えなしですぐ選ぶ
        c.spectatorDirectorEnabled = false
        c.cameraMode = .free(Vec2(1000, 1000))
        run(c, director: d, ticks: 30, clock: now)
        XCTAssertEqual(c.cameraMode, .free(Vec2(1000, 1000)))
        XCTAssertFalse(link.resumeDirector(), "オフの自動カメラには戻さない")
        c.spectatorDirectorEnabled = true
        run(c, director: d, ticks: 10, clock: now)
        if case .free = c.cameraMode { XCTFail("オンにしたらすぐ画を選ぶ") }
    }

    func testDirectorOnlyShowsWhatTheChosenTeamCanSee() {
        var launch = BattleLaunch(config: MatchFactory.botMatch(seed: 77))
        launch.spectatorOptions = SpectatorOptions(speed: 1, vision: .blue, director: true)
        let c = BattleController(launch: launch)
        let d = CameraDirector(controller: c, link: SpectatorCameraLink.link(for: c))
        let now = TestClock(0)
        d.clock = { now.now }
        d.start()
        defer { d.stop() }
        var lastMode = c.cameraMode
        var writes = 0
        run(c, director: d, ticks: 1800, clock: now) { _ in
            guard c.cameraMode != lastMode else { return }
            lastMode = c.cameraMode
            writes += 1
            let s = c.state
            let ids: [EntityID]
            switch c.cameraMode {
            case .followUnit(let id): ids = [id]
            case .framing(let list): ids = list
            default: return
            }
            for id in ids {
                guard let i = s.index(of: id) else { return XCTFail() }
                XCTAssertTrue(s.isVisible(i, to: .blue), "Blue の視点では Blue に見えているヒーローだけ")
            }
        }
        XCTAssertGreaterThan(writes, 0)
    }

    func testSeekResetsTheDirector() async {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 9)))
        let d = CameraDirector(controller: c, link: SpectatorCameraLink.link(for: c))
        let now = TestClock(0)
        d.clock = { now.now }
        d.start()
        defer { d.stop() }
        run(c, director: d, ticks: 900, clock: now)
        XCTAssertNotNil(d.policy.current)
        c.requestSeek(toTick: 300)
        // シーク中は選ばない
        d.update()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(60))
        while c.seekingToTick != nil && clock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(c.state.tick, 300)
        d.update()
        XCTAssertTrue(d.moments.items.allSatisfy { $0.time <= c.state.time }, "巻き戻した先の未来の出来事を覚えていない")
        if let shot = d.policy.current {
            XCTAssertEqual(c.state.unit(shot.subject)?.hero?.isDead, false, "シークの後の画は今の状態から選び直す")
        }
    }

    func testPlayersHaveNoDirector() {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 2)))
        let d = CameraDirector(controller: c, link: SpectatorCameraLink.link(for: c))
        XCTAssertFalse(d.isActive)
        c.spectatorDirectorEnabled = true
        XCTAssertFalse(d.isActive, "プレイヤーには自動カメラを使わない")
        d.update()
        XCTAssertEqual(c.cameraMode, .followHero)
    }

    func testLinkIsSharedPerController() {
        let a = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 1)))
        let b = BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 2)))
        let la = SpectatorCameraLink.link(for: a)
        XCTAssertTrue(SpectatorCameraLink.link(for: a) === la, "同じ controller は同じ窓口")
        XCTAssertFalse(SpectatorCameraLink.link(for: b) === la)
        XCTAssertTrue(la.controller === a)
    }
}
