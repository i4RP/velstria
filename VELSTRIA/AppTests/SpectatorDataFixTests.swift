import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 統合レビューのデータ指摘の回帰テスト: 保存の上限で消す順、お気に入りを外した時、重複の判定、出来事の数（二分探索）、
/// 取り消されたシークの続き、事前計算の先回り。
@MainActor
final class SpectatorDataFixTests: XCTestCase {
    private func replay(_ config: MatchConfig, finalTick: Int = 900, frames: [ReplayFrame] = []) -> ReplayData {
        ReplayData(config: config, frames: frames, finalTick: finalTick, summary: nil)
    }

    // MARK: 保存の上限

    func testAutoArchivedReplaysAreEvictedBeforeTheOwnMatches() {
        let persistence = ServicesFixtures.tempPersistence()
        var p = Profile()
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        // 自分の対戦を上限まで（古い）→ その後に AI 同士の観戦を 5 件（新しい）
        var own: [UUID] = []
        for k in 0..<PersistenceService.maxReplays {
            let config = MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: UInt64(100 + k))
            let meta = persistence.storeReplay(replay(config), heroID: "H001", won: true,
                                               date: base.addingTimeInterval(Double(k)), in: &p)
            own.append(try! XCTUnwrap(meta).id)
        }
        for k in 0..<5 {
            _ = persistence.storeReplay(replay(MatchFactory.botMatch(seed: UInt64(900 + k))), heroID: nil, won: nil,
                                        date: base.addingTimeInterval(10_000 + Double(k)), in: &p)
        }
        persistence.waitForReplayWrites()
        XCTAssertEqual(ReplayLibrary.regularCount(p.replays), PersistenceService.maxReplays)
        let kept = Set(p.replays.map(\.id))
        XCTAssertTrue(own.allSatisfy { kept.contains($0) }, "自分の対戦は観戦の自動保存に押し出されない")
        XCTAssertEqual(p.replays.filter { $0.source == .spectate }.count, 0, "上限を超えた分は観戦から消す")
        XCTAssertEqual(PersistenceService.evictionTier(p.replays[0]), 1)
    }

    func testUnfavoritingDoesNotDeleteTheReplayRightAway() {
        let persistence = ServicesFixtures.tempPersistence()
        var p = Profile()
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let fav = try! XCTUnwrap(persistence.storeReplay(replay(MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 1)),
                                                          heroID: "H001", won: true, date: base, in: &p))
        XCTAssertEqual(ReplayArchiveService.toggleFavorite(id: fav.id, profile: &p, persistence: persistence), .changed(true))
        for k in 0..<PersistenceService.maxReplays {
            _ = persistence.storeReplay(replay(MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: UInt64(10 + k))),
                                        heroID: "H001", won: true, date: base.addingTimeInterval(Double(k + 1)), in: &p)
        }
        persistence.waitForReplayWrites()
        XCTAssertFalse(ReplayArchiveService.isOverRegularCap(p))
        // 上限まで埋まっている時に外しても、その場では消さない（付け直せる）
        XCTAssertEqual(ReplayArchiveService.toggleFavorite(id: fav.id, profile: &p, persistence: persistence), .changed(false))
        XCTAssertTrue(p.replays.contains { $0.id == fav.id }, "外した直後に消えた")
        XCTAssertTrue(ReplayArchiveService.isOverRegularCap(p))
        XCTAssertNotNil(persistence.loadReplay(p.replays.first { $0.id == fav.id }!), "ファイルも残る")
        XCTAssertTrue(ReplayLibrary.unfavoritedMessage(p).count > L("お気に入りから外しました", "Removed from favorites").count,
                      "上限を超えていることを知らせる")
        XCTAssertEqual(ReplayArchiveService.toggleFavorite(id: fav.id, profile: &p, persistence: persistence), .changed(true))
        XCTAssertFalse(ReplayArchiveService.isOverRegularCap(p))
    }

    // MARK: 重複の判定

    func testSameSeedSpectateWithADifferentDifficultyIsNotADuplicate() {
        let persistence = ServicesFixtures.tempPersistence()
        var p = Profile()
        let easy = replay(MatchFactory.botMatch(difficulty: .easy, seed: 77))
        let hard = replay(MatchFactory.botMatch(difficulty: .hard, seed: 77))
        XCTAssertEqual(easy.config.players.map(\.heroID), hard.config.players.map(\.heroID), "前提: 同じシードの編成は同じ")
        XCTAssertNotEqual(ReplayArchiveService.contentKey(of: easy), ReplayArchiveService.contentKey(of: hard))
        _ = persistence.storeReplay(easy, heroID: nil, won: nil, date: Date(), in: &p)
        persistence.waitForReplayWrites()
        XCTAssertNotNil(ReplayArchiveService.existingDuplicate(of: easy, in: p, load: persistence.loadReplay), "同じ試合は重複")
        XCTAssertNil(ReplayArchiveService.existingDuplicate(of: hard, in: p, load: persistence.loadReplay), "難易度が違えば別の試合")
    }

    func testRecordingsWithInputsAreComparedByContent() {
        let persistence = ServicesFixtures.tempPersistence()
        var p = Profile()
        let config = MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 5)
        let a = replay(config, frames: [ReplayFrame(tick: 10, commands: [HeroCommand(heroID: 11, command: .move(direction: Vec2(1, 0)))])])
        let b = replay(config, frames: [ReplayFrame(tick: 10, commands: [HeroCommand(heroID: 11, command: .move(direction: Vec2(0, 1)))])])
        _ = persistence.storeReplay(a, heroID: "H001", won: nil, date: Date(), in: &p)
        persistence.waitForReplayWrites()
        XCTAssertNotNil(ReplayArchiveService.existingDuplicate(of: a, in: p, load: persistence.loadReplay))
        XCTAssertNil(ReplayArchiveService.existingDuplicate(of: b, in: p, load: persistence.loadReplay), "入力が違えば別の試合")
    }

    // MARK: 出来事の数

    func testEventCountMatchesALinearFilter() {
        var t = ReplayTimeline()
        let ticks = [3, 3, 10, 50, 50, 50, 120, 400]
        t.events = ticks.map { TimelineEvent(tick: $0, kind: .ace(team: .blue), pos: nil) }
        for probe in [-1, 0, 3, 4, 49, 50, 51, 119, 120, 399, 400, 1000] {
            XCTAssertEqual(HUDSpectatorState.eventCount(in: t, atOrBefore: probe), ticks.filter { $0 <= probe }.count, "tick \(probe)")
        }
        XCTAssertEqual(HUDSpectatorState.eventCount(in: ReplayTimeline(), atOrBefore: 10), 0)
    }

    // MARK: シークの続き・事前計算の先回り

    func testCancelledSeekKeepsItsProgressForTheNextCall() async {
        let config = MatchFactory.botMatch(seed: 13)
        let start = Simulation(config: config).state
        let worker = ReplaySeekWorker(inputs: [:], finalTick: nil, map: MapDefinition.map(for: config.mode))
        let goal = 1900
        let cancelled = Task { await worker.advance(from: start, to: goal, timeline: nil, keyframeInterval: 900) }
        cancelled.cancel()
        let partial = await cancelled.value
        XCTAssertFalse(partial.completed)
        XCTAssertLessThan(partial.state.tick, goal)
        // 次の呼び出しは途中から続ける（結果は通常の再生と同じ）
        let full = await worker.advance(from: start, to: goal, timeline: nil, keyframeInterval: 900)
        XCTAssertTrue(full.completed)
        XCTAssertEqual(full.state.tick, goal)
        let linear = Simulation(config: config)
        for _ in 0..<goal { linear.step() }
        XCTAssertEqual(full.state.stateHash(), linear.state.stateHash())
        XCTAssertTrue(full.keyframes.allSatisfy { $0.tick % 900 == 0 && $0.tick <= goal }, "途中のキーフレームは間隔どおり")
    }

    func testBakeSkipsAheadToAnExistingStateAndStillMatchesLinearPlay() async {
        let config = MatchFactory.botMatch(seed: 21)
        let linear = Simulation(config: config)
        var builder = ReplayTimelineBuilder()
        builder.begin(state: linear.state)
        for _ in 0..<1200 { builder.observe(events: linear.step(), state: linear.state) }
        let ahead = ReplayBakeSkip(state: linear.state, timeline: builder.timeline)
        for _ in 0..<600 { builder.observe(events: linear.step(), state: linear.state) }
        let plan = ReplayBakePlan(config: config, inputs: [:], finalTick: nil, limitTick: 1800, keyframeInterval: 900, maxKeyframes: 96)
        final class Box: @unchecked Sendable { var last: ReplayBakeBatch? }
        let box = Box()
        await ReplayBakeEngine.run(plan, skipAhead: { tick in tick < 1200 ? ahead : nil }, publish: { batch in
            box.last = batch
            return true
        })
        let last = try! XCTUnwrap(box.last)
        XCTAssertTrue(last.finished)
        XCTAssertEqual(last.bakedTick, 1800)
        XCTAssertLessThan(last.simulatedTicks, 1800, "先回りした区間は計算し直さない")
        XCTAssertEqual(last.timeline.events, builder.timeline.events, "飛んでも年表は通常の再生と同じ")
        XCTAssertEqual(last.timeline.coveredTick, 1800)
    }
}
