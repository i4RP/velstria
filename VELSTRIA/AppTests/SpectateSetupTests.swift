import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 観戦の準備（M6）とリザルトからの続き（M5）・デバッグ起動の観戦フラグ（M15）。
@MainActor
final class SpectateSetupTests: XCTestCase {
    func testSeedParsingAndLabel() {
        XCTAssertEqual(SpectateSetup.parseSeed("#0000ABCD"), 0xABCD)
        XCTAssertEqual(SpectateSetup.parseSeed("0xff"), 255)
        XCTAssertEqual(SpectateSetup.parseSeed(" 20261001 "), 20261001, "数字だけなら 10 進")
        XCTAssertEqual(SpectateSetup.parseSeed("beef"), 0xBEEF, "英字を含めば 16 進")
        XCTAssertEqual(SpectateSetup.parseSeed("#FFFFFFFFFFFFFFFF"), UInt64.max)
        XCTAssertNil(SpectateSetup.parseSeed(""))
        XCTAssertNil(SpectateSetup.parseSeed("#"))
        XCTAssertNil(SpectateSetup.parseSeed("xyz"))
        XCTAssertNil(SpectateSetup.parseSeed("#1FFFFFFFFFFFFFFFF"), "64 bit を超える")
        XCTAssertEqual(SpectateSetup.seedLabel(0xABCD), "#0000ABCD")
        XCTAssertEqual(SpectateSetup.seedLabel(0x1_0000_0000), "#0000000100000000")
        // 表記は読み戻せる（コピーしたシードで同じ試合）
        for seed: UInt64 in [1, 20261001, 0xFFFF_FFFF, 0x1234_5678_9ABC_DEF0] {
            XCTAssertEqual(SpectateSetup.parseSeed(SpectateSetup.seedLabel(seed)), seed)
        }
    }

    func testPreferencesBuildOptionsAndLaunch() {
        var prefs = SpectatePreferences()
        // 難易度の未設定はプロフィールの既定難易度
        var o = SpectateSetup.matchOptions(prefs, preferred: .hard, picks: [])
        XCTAssertEqual(o.blueDifficulty, .hard)
        XCTAssertEqual(o.redDifficulty, .hard)
        XCTAssertNil(o.maxDuration)
        prefs.blueDifficulty = .easy
        prefs.map = .brawl
        prefs.maxMinutes = 10
        prefs.speed = 4
        prefs.vision = .red
        prefs.director = false
        o = SpectateSetup.matchOptions(prefs, preferred: .hard, picks: [SpectatePick(team: .red, position: .mid, heroID: "H003")])
        XCTAssertEqual(o.blueDifficulty, .easy)
        XCTAssertEqual(o.redDifficulty, .hard)
        XCTAssertEqual(o.maxDuration, 600)
        XCTAssertEqual(o.map, .brawl)

        let config = SpectateSetup.config(options: o, seed: 42)
        XCTAssertEqual(config.mode, .brawl)
        XCTAssertEqual(config.maxDuration, 600)
        XCTAssertEqual(config.players.first { $0.team == .red && $0.position == .mid }?.heroID, "H003")
        let launch = SpectateSetup.launch(config: config, prefs: prefs)
        XCTAssertTrue(launch.isSpectating, "全員 AI の乱闘は観戦扱い")
        XCTAssertTrue(launch.isAllBotsOffline)
        XCTAssertNil(launch.localTeam)
        XCTAssertEqual(launch.spectatorOptions, SpectatorOptions(speed: 4, vision: .red, director: false))
        // 報酬の対象外
        let outcome = BattleOutcome(launch: launch, summary: ServicesFixtures.summary(mode: .brawl, won: true, minutes: 10),
                                    replay: nil, abandoned: false)
        XCTAssertFalse(RewardService.isRewardEligible(outcome))

        // 選べない速度は 1 倍に戻す
        prefs.speed = 3
        XCTAssertEqual(SpectateSetup.spectatorOptions(prefs).speed, 1)
    }

    func testPreferencesPersistAndDecodeLegacy() throws {
        var p = Profile()
        p.spectatePreferences = SpectatePreferences(map: .brawl, blueDifficulty: .easy, redDifficulty: nil, speed: 2,
                                                    vision: .blue, director: false, maxMinutes: 20)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(back.spectatePreferences, p.spectatePreferences)

        // 欠けたキーは既定値
        let partial = try JSONDecoder().decode(SpectatePreferences.self, from: Data(#"{"speed":8}"#.utf8))
        XCTAssertEqual(partial.speed, 8)
        XCTAssertEqual(partial.map, .standard)
        XCTAssertTrue(partial.director)
        XCTAssertNil(partial.blueDifficulty)

        // 旧版のプロフィール（観戦の設定・視聴記録・観戦の通算が無い）も読める
        let s = ServicesFixtures.tempPersistence()
        defer { try? FileManager.default.removeItem(at: s.directory) }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Profile())) as? [String: Any])
        object.removeValue(forKey: "spectatePreferences")
        object.removeValue(forKey: "watchLog")
        var career = try XCTUnwrap(object["career"] as? [String: Any])
        career.removeValue(forKey: "spectatedMatches")
        career.removeValue(forKey: "replaysWatched")
        career.removeValue(forKey: "watchedSeconds")
        object["career"] = career
        object["replays"] = [["id": UUID().uuidString, "date": 0, "fileName": "x.vreplay", "mode": 0, "duration": 12]]
        let decoded = try s.decodeProfile(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.spectatePreferences, SpectatePreferences())
        XCTAssertEqual(decoded.watchLog, WatchLog())
        XCTAssertEqual(decoded.career.spectatedMatches, 0)
        XCTAssertEqual(decoded.replays.first?.fileName, "x.vreplay")
        XCTAssertEqual(decoded.replays.first?.isFavorite, false)
    }

    func testNextSpectateKeepsMapAndDifficulty() {
        let options = SpectateMatchOptions(map: .brawl, blueDifficulty: .hard, redDifficulty: .easy,
                                           picks: [SpectatePick(team: .blue, position: .top, heroID: "H001")], maxDuration: 1200)
        let first = SpectateSetup.config(options: options, seed: 10)
        let next = SpectateSetup.nextConfig(after: first, seed: 11)
        XCTAssertEqual(next.mode, .brawl)
        XCTAssertEqual(next.seed, 11)
        XCTAssertEqual(next.maxDuration, 1200)
        XCTAssertTrue(next.players.filter { $0.team == .blue }.allSatisfy { $0.botDifficulty == .hard })
        XCTAssertTrue(next.players.filter { $0.team == .red }.allSatisfy { $0.botDifficulty == .easy })
        XCTAssertNotEqual(next, first)
    }

    func testUITestSeedStillMatchesBotMatch() {
        // UI テスト（シード 20261001）の編成は従来どおり
        let prefs = SpectatePreferences()
        let config = SpectateSetup.config(options: SpectateSetup.matchOptions(prefs, preferred: .normal, picks: []),
                                          seed: SpectateSetup.uiTestSeed)
        XCTAssertEqual(config, MatchFactory.botMatch(seed: SpectateSetup.uiTestSeed))
    }

    func testCompleteBattleArchivesSpectateWithoutRewards() throws {
        let persistence = ServicesFixtures.tempPersistence()
        defer { try? FileManager.default.removeItem(at: persistence.directory) }
        let app = AppModel(persistence: persistence)
        app.profile = Profile()
        let before = app.profile
        let config = MatchFactory.spectateMatch(options: SpectateMatchOptions(), seed: 77)
        var summary = ServicesFixtures.summary(mode: .spectate, won: true, minutes: 15, humanPresent: false)
        summary.humanTeam = nil
        let replay = ReplayData(config: config, frames: [], finalTick: 15 * 60 * 30, summary: summary)
        let report = app.completeBattle(BattleOutcome(launch: BattleLaunch(config: config), summary: summary,
                                                      replay: replay, abandoned: false), now: ServicesFixtures.weekday)
        XCTAssertTrue(report.noRewards)
        XCTAssertTrue(report.replaySaved)
        XCTAssertTrue(report.watchCounted)
        XCTAssertEqual(app.profile.replays.count, 1)
        XCTAssertEqual(app.profile.career.spectatedMatches, 1)
        XCTAssertEqual(app.profile.starlightCoin, before.starlightCoin)
        XCTAssertEqual(app.profile.freeGem, before.freeGem)
        XCTAssertEqual(app.profile.pass.xp, before.pass.xp)
        XCTAssertEqual(app.profile.accountXP, before.accountXP)
        XCTAssertTrue(app.profile.matchHistory.isEmpty)
        XCTAssertEqual(app.profile.career.matches, 0)
        XCTAssertEqual(app.lastRewardReport, report)
    }

    func testDebugReplayFlagsAndRoutes() {
        let replay = DebugLaunch.syntheticReplay(config: MatchFactory.botMatch(seed: 1), seconds: 60)
        XCTAssertEqual(replay.finalTick, 1800)
        XCTAssertTrue(replay.frames.isEmpty)
        XCTAssertTrue(replay.isPlayable)
        XCTAssertEqual(DebugLaunch.parseRoute("arcade"), .arcade)
        XCTAssertEqual(DebugLaunch.parseRoute("customSetup"), .customSetup)
        XCTAssertEqual(DebugLaunch.parseRoute("replays"), .replays)
        XCTAssertEqual(DebugLaunch.parseRoute("spectateSetup"), .spectateSetup)
        // 引数が無ければ観戦の既定
        XCTAssertEqual(DebugLaunch.spectatorOptions(), SpectatorOptions())

        let persistence = ServicesFixtures.tempPersistence()
        defer { try? FileManager.default.removeItem(at: persistence.directory) }
        let app = AppModel(persistence: persistence)
        app.profile = Profile()
        // 保存が無ければ合成リプレイ
        let synthetic = DebugLaunch.latestReplayLaunch(app: app, seed: 9)
        XCTAssertNotNil(synthetic.replay)
        XCTAssertTrue(synthetic.isSpectating)
        DebugLaunch.addSampleReplays(to: app)
        XCTAssertEqual(app.profile.replays.count, 4)
        XCTAssertEqual(app.profile.replays.filter { ReplayLibrary.compatibility($0) == .incompatible }.count, 1)
        XCTAssertEqual(app.profile.replays.filter(\.isFavorite).count, 1)
        // 最新の保存済みリプレイ
        let latest = DebugLaunch.latestReplayLaunch(app: app, seed: 9)
        XCTAssertEqual(latest.config, MatchFactory.botMatch(seed: 20261001))
    }
}
