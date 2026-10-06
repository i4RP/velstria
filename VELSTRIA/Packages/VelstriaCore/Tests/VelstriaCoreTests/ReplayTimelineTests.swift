import XCTest
@testable import VelstriaCore

/// 観戦・リプレイの年表（キル・構造物・目標・ゴールド推移）。決定論・巻き戻し・保存形式の互換。
final class ReplayTimelineTests: XCTestCase {
    private func runBotMatch(seed: UInt64, ticks: Int, sampleInterval: Int = 300) -> (ReplayTimeline, SimState) {
        let sim = Simulation(config: MatchFactory.botMatch(seed: seed))
        var builder = ReplayTimelineBuilder(sampleInterval: sampleInterval)
        builder.begin(state: sim.state)
        for _ in 0..<ticks where !sim.isEnded {
            builder.observe(events: sim.step(), state: sim.state)
        }
        return (builder.timeline, sim.state)
    }

    func testTimelineIsDeterministicAndSampled() {
        let ticks = 30 * 60 * 6   // 6 分
        let (a, stateA) = runBotMatch(seed: 77, ticks: ticks)
        let (b, _) = runBotMatch(seed: 77, ticks: ticks)
        XCTAssertEqual(a, b, "同じシードなら同じ年表")
        XCTAssertEqual(a.coveredTick, stateA.tick)
        XCTAssertEqual(a.samples.first?.tick, 0)
        XCTAssertEqual(a.samples.count, ticks / 300 + 1)
        XCTAssertTrue(zip(a.samples, a.samples.dropFirst()).allSatisfy { $0.tick < $1.tick })
        XCTAssertTrue(zip(a.events, a.events.dropFirst()).allSatisfy { $0.tick <= $1.tick })
        // 6 分の AI 戦ではキルが起きる。キルには倒された位置と倒した側が入る
        let kills = a.events.filter { if case .kill = $0.kind { return true } else { return false } }
        XCTAssertFalse(kills.isEmpty)
        for k in kills {
            XCTAssertNotNil(k.pos)
            guard case .kill(let victim, _, _, let killerTeam, _, _, _) = k.kind else { continue }
            XCTAssertNotNil(stateA.unit(victim))
            if let team = killerTeam { XCTAssertNotEqual(team, stateA.unit(victim)?.team) }
        }
        // サンプルのキル数は状態のキル数と一致する
        let last = a.samples.last!
        XCTAssertLessThanOrEqual(last.blueKills + last.redKills, stateA.teams[0].kills + stateA.teams[1].kills)
        XCTAssertGreaterThan(last.blueGold, 0)
        XCTAssertGreaterThan(last.blueXP, 0)
    }

    func testRewindThenReobserveReproducesTheSameTimeline() {
        let config = MatchFactory.botMatch(seed: 5)
        let sim = Simulation(config: config)
        var builder = ReplayTimelineBuilder()
        builder.begin(state: sim.state)
        var keyframe: SimState?
        for _ in 0..<(30 * 60 * 5) {
            builder.observe(events: sim.step(), state: sim.state)
            if sim.state.tick == 30 * 60 * 2 { keyframe = sim.state }
        }
        let linear = builder.timeline
        // 2 分の時点へ巻き戻して同じ区間を進め直す
        sim.restore(from: keyframe!)
        builder.rewind(to: keyframe!.tick)
        XCTAssertTrue(builder.timeline.events.allSatisfy { $0.tick <= keyframe!.tick })
        XCTAssertEqual(builder.timeline.coveredTick, keyframe!.tick)
        while sim.state.tick < linear.coveredTick {
            builder.observe(events: sim.step(), state: sim.state)
        }
        XCTAssertEqual(builder.timeline, linear, "巻き戻して進め直しても年表は同じ")
        // 記録済みの tick を二重に取り込まない
        let before = builder.timeline
        builder.observe(events: [.announcement(.ace(team: .blue))], state: sim.state)
        XCTAssertEqual(builder.timeline, before)
    }

    func testQueriesAndWeights() {
        var t = ReplayTimeline()
        t.events = [
            TimelineEvent(tick: 100, kind: .kill(victimID: 1, killerID: 2, assistIDs: [], killerTeam: .blue,
                                                 isFirstBlood: true, multiKill: 1, isShutdown: false), pos: Vec2(1, 1)),
            TimelineEvent(tick: 200, kind: .structure(team: .red, kind: .tower, lane: .mid, tier: .outer, killerID: 2), pos: nil),
            TimelineEvent(tick: 300, kind: .objective(kind: .astralWyrm, team: .red, killerID: 9), pos: nil),
            TimelineEvent(tick: 400, kind: .ace(team: .red), pos: nil),
        ]
        t.coveredTick = 400
        XCTAssertEqual(t.nextEvent(after: 100)?.tick, 200)
        XCTAssertEqual(t.nextEvent(after: 100, minWeight: 0.8)?.tick, 300)
        XCTAssertEqual(t.previousEvent(before: 300)?.tick, 200)
        XCTAssertEqual(t.events(in: 150...350).map(\.tick), [200, 300])
        XCTAssertEqual(t.events[0].creditedTeam, .blue)
        XCTAssertEqual(t.events[1].creditedTeam, .blue, "構造物は壊した側")
        XCTAssertEqual(t.events[2].creditedTeam, .red)
        XCTAssertGreaterThan(t.events[2].weight, t.events[1].weight)
        t.truncate(after: 250)
        XCTAssertEqual(t.events.map(\.tick), [100, 200])
        XCTAssertEqual(t.coveredTick, 250)
    }

    func testReplayDataTimelineRoundTripAndOldFilesStillDecode() throws {
        let (timeline, _) = runBotMatch(seed: 3, ticks: 900)
        let data = ReplayData(config: MatchFactory.botMatch(seed: 3), frames: [], finalTick: 900, summary: nil, timeline: timeline)
        let back = try JSONDecoder().decode(ReplayData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(back.timeline, timeline)
        // 年表の無い古い形式（timeline キーなし）も読める
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as! [String: Any]
        json.removeValue(forKey: "timeline")
        let old = try JSONDecoder().decode(ReplayData.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.timeline)
        XCTAssertEqual(old.finalTick, 900)
    }

    func testRecorderKeepsFurthestTickAndIncompleteFlag() {
        let recorder = ReplayRecorder(config: MatchFactory.botMatch(seed: 1))
        recorder.record(tick: 10, commands: [])
        recorder.record(tick: 5, commands: [])   // 観戦のシークで戻った
        XCTAssertEqual(recorder.lastTick, 10)
        XCTAssertFalse(recorder.isIncomplete)
        recorder.markIncomplete()
        XCTAssertTrue(recorder.isIncomplete)
    }
}
