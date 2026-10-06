import XCTest
@testable import VELSTRIA
import VelstriaCore

/// リプレイ一覧（M4）と観戦の記録（M5）: 報酬なしの保存、お気に入りと上限、旧版のメタ、再生の判定、
/// 書き出し / 取り込み（信用しないファイルの検証）、視聴記録の重複防止と報酬が増えないこと。
@MainActor
final class ReplayLibraryTests: XCTestCase {
    private var dirs: [URL] = []

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        dirs = []
        super.tearDown()
    }

    private func make() -> PersistenceService {
        let s = ServicesFixtures.tempPersistence()
        dirs.append(s.directory)
        return s
    }

    private let master = MasterData.shared
    private let now = ServicesFixtures.weekday

    /// 実際の構成と結果から作る、AI 同士の観戦の結果（記録は入力なしの小さなリプレイ）。
    private func spectateOutcome(seed: UInt64 = 5, minutes: Double = 12, abandoned: Bool = false,
                                 endReason: EndReason = .coreDestroyed, map: SpectateMap = .standard) -> BattleOutcome {
        let config = MatchFactory.spectateMatch(options: SpectateMatchOptions(map: map), seed: seed)
        var summary = ServicesFixtures.summary(mode: config.mode, won: true, minutes: minutes, humanPresent: false)
        summary.endReason = endReason
        summary.humanTeam = nil
        let replay = ReplayData(config: config, frames: [], finalTick: Int(minutes * 60 / Balance.dt), summary: summary)
        return BattleOutcome(launch: BattleLaunch(config: config), summary: summary, replay: replay, abandoned: abandoned)
    }

    private func process(_ outcome: BattleOutcome, _ p: inout Profile, persistence: PersistenceService,
                         report: RewardReport = RewardReport(noRewards: true)) -> RewardReport {
        var r = report
        ReplayArchiveService.process(outcome: outcome, report: &r, profile: &p, persistence: persistence, master: master, now: now)
        return r
    }

    // MARK: 報酬なしの保存

    func testArchivePolicyMatrix() {
        XCTAssertEqual(ReplayArchiveService.archiveSource(for: spectateOutcome()), .spectate)
        XCTAssertEqual(ReplayArchiveService.archiveSource(for: spectateOutcome(map: .brawl)), .spectate, "全員 AI の乱闘も観戦")
        XCTAssertNil(ReplayArchiveService.archiveSource(for: spectateOutcome(abandoned: true)), "途中退出は保存しない")
        XCTAssertNil(ReplayArchiveService.archiveSource(for: spectateOutcome(endReason: .aborted)), "中断は保存しない")
        XCTAssertNil(ReplayArchiveService.archiveSource(for: spectateOutcome(minutes: 0.2)), "30 秒未満は保存しない")

        // 人間のいる通常戦・ランク戦・乱闘は報酬の側（RewardService）が保存する
        XCTAssertNil(ReplayArchiveService.archiveSource(for: ServicesFixtures.outcome(mode: .standard, withReplay: true)))
        XCTAssertNil(ReplayArchiveService.archiveSource(for: ServicesFixtures.outcome(mode: .brawl, withReplay: true)))
        XCTAssertEqual(ReplayArchiveService.archiveSource(for: ServicesFixtures.outcome(mode: .custom, withReplay: true)), .custom)
        XCTAssertEqual(ReplayArchiveService.archiveSource(for: ServicesFixtures.outcome(mode: .online, withReplay: true)), .online)
        XCTAssertNil(ReplayArchiveService.archiveSource(for: ServicesFixtures.outcome(mode: .practice, withReplay: true)))
        XCTAssertNil(ReplayArchiveService.archiveSource(for: ServicesFixtures.outcome(mode: .standard, withReplay: true,
                                                                                      isReplayPlayback: true)), "リプレイの再生")
        // オンラインの観戦席（記録が無い）
        var watcher = ServicesFixtures.outcome(mode: .online, withReplay: true)
        watcher.launch = BattleLaunch(config: watcher.launch.config, onlineSpectator: true)
        XCTAssertNil(ReplayArchiveService.archiveSource(for: watcher))
    }

    func testSpectateIsArchivedWithoutRewardsOrRecords() throws {
        let persistence = make()
        let original = Profile()
        var p = original
        let outcome = spectateOutcome()
        let reward = RewardService.apply(outcome: outcome, to: &p, master: master, persistence: persistence, now: now)
        XCTAssertTrue(reward.noRewards)
        let r = process(outcome, &p, persistence: persistence, report: reward)
        XCTAssertTrue(r.replaySaved)
        let meta = try XCTUnwrap(p.replays.first)
        XCTAssertEqual(r.replayID, meta.id)
        XCTAssertEqual(meta.source, .spectate)
        XCTAssertNil(meta.heroID)
        XCTAssertNil(meta.ownerSeat)
        XCTAssertEqual(meta.simVersion, MatchConfig.currentSimVersion)
        XCTAssertEqual(meta.formatVersion, ReplayData.currentFormatVersion)
        XCTAssertEqual(meta.seed, 5)
        XCTAssertEqual(meta.heroIDs, outcome.launch.config.players.map(\.heroID))
        XCTAssertEqual(meta.winner, .blue)
        // 報酬・戦績・通算の試合成績は変わらない
        XCTAssertEqual(p.starlightCoin, original.starlightCoin)
        XCTAssertEqual(p.freeGem, original.freeGem)
        XCTAssertEqual(p.accountXP, original.accountXP)
        XCTAssertEqual(p.pass.xp, original.pass.xp)
        XCTAssertEqual(p.matchHistory, original.matchHistory)
        XCTAssertEqual(p.career.matches, 0)
        XCTAssertEqual(p.missions, original.missions)
        XCTAssertEqual(r.coins, 0)
        XCTAssertEqual(r.passXP, 0)
        // 保存は即時（デバウンスを待たない）
        XCTAssertFalse(persistence.hasPendingSave)
        persistence.waitForReplayWrites()
        XCTAssertEqual(persistence.loadReplay(meta)?.config, outcome.launch.config)

        // 同じシードで観戦し直しても重ねて保存しない
        let again = process(spectateOutcome(), &p, persistence: persistence)
        XCTAssertEqual(p.replays.count, 1)
        XCTAssertEqual(again.replayID, meta.id)
        XCTAssertFalse(again.watchCounted, "同じ試合は 2 回数えない")
    }

    func testCustomAndOnlineKeepOwner() throws {
        let persistence = make()
        var p = Profile()
        let custom = ServicesFixtures.outcome(mode: .custom, won: true, withReplay: true)
        _ = process(custom, &p, persistence: persistence)
        let meta = try XCTUnwrap(p.replays.first)
        XCTAssertEqual(meta.source, .custom)
        XCTAssertEqual(meta.heroID, "H001")
        XCTAssertEqual(meta.won, true)
        XCTAssertEqual(meta.ownerSeat, custom.launch.config.players.firstIndex { $0.controller == .human })

        let online = ServicesFixtures.config(mode: .online)
        let seat = MatchFactory.onlineSeatIndex(team: .blue, position: .mid)
        let summary = ServicesFixtures.summary(mode: .online, won: false, minutes: 10)
        let replay = ServicesFixtures.replay(config: online, summary: summary, ticks: 1200)
        let outcome = BattleOutcome(launch: BattleLaunch(config: online, onlineSeat: seat), summary: summary, replay: replay, abandoned: false)
        let r = process(outcome, &p, persistence: persistence)
        let onlineMeta = try XCTUnwrap(p.replays.first { $0.id == r.replayID })
        XCTAssertEqual(onlineMeta.source, .online)
        XCTAssertEqual(onlineMeta.ownerSeat, seat)
        XCTAssertEqual(onlineMeta.heroID, online.players[seat].heroID)
        XCTAssertFalse(r.watchCounted, "自分の対戦は観戦ではない")
    }

    // MARK: 視聴記録（報酬なし・重複なし）

    func testWatchCountsOncePerMatchAndGrantsNoCurrency() throws {
        let persistence = make()
        var p = Profile()
        let first = process(spectateOutcome(seed: 1), &p, persistence: persistence)
        XCTAssertTrue(first.watchCounted)
        XCTAssertEqual(p.career.spectatedMatches, 1)
        XCTAssertTrue(first.achievementsUnlocked.contains("ACH_WATCH_1"))
        let ach = try XCTUnwrap(p.achievements["ACH_WATCH_1"])
        XCTAssertTrue(ach.claimed, "Gem の無い実績は解除と同時に受取済み")
        XCTAssertNil(LiveOpsService.claimAchievement(id: "ACH_WATCH_1", profile: &p, now: now))
        XCTAssertEqual(LiveOpsService.claimableAchievementCount(profile: p), 0)
        XCTAssertEqual(p.freeGem, 0)
        XCTAssertEqual(p.starlightCoin, 0)
        XCTAssertEqual(p.pass.xp, 0)

        // 途中退出・同じ試合は数えない
        XCTAssertFalse(process(spectateOutcome(seed: 2, abandoned: true), &p, persistence: persistence).watchCounted)
        XCTAssertFalse(process(spectateOutcome(seed: 1), &p, persistence: persistence).watchCounted)
        XCTAssertEqual(p.career.spectatedMatches, 1)

        // リプレイ: 同じリプレイを何度（何倍速で）見ても 1 回
        let replay = try XCTUnwrap(spectateOutcome(seed: 3).replay)
        let playback = BattleOutcome(launch: BattleLaunch(config: replay.config, replay: replay),
                                     summary: try XCTUnwrap(replay.summary), replay: nil, abandoned: false)
        XCTAssertTrue(process(playback, &p, persistence: persistence).watchCounted)
        XCTAssertFalse(process(playback, &p, persistence: persistence).watchCounted)
        var stopped = playback
        stopped.abandoned = true
        XCTAssertFalse(process(stopped, &p, persistence: persistence).watchCounted, "途中で止めた再生は数えない")
        XCTAssertEqual(p.career.replaysWatched, 1)
        XCTAssertEqual(p.replays.count, 1, "リプレイの再生は保存しない（観戦 1 件だけ）")

        // 今週の目標（報酬なし）
        let goals = LiveOpsService.watchGoalProgress(profile: p, now: now)
        XCTAssertEqual(goals.first { $0.goal.kind == .spectate }?.progress, 1)
        XCTAssertEqual(goals.first { $0.goal.kind == .replay }?.progress, 1)
        let nextWeek = now.addingTimeInterval(8 * 86_400)
        XCTAssertTrue(LiveOpsService.watchGoalProgress(profile: p, now: nextWeek).allSatisfy { $0.progress == 0 })
        XCTAssertEqual(p.freeGem + p.starlightCoin + p.pass.xp, 0)
    }

    func testWatchKeyDistinguishesMatches() {
        let a = MatchFactory.spectateMatch(options: SpectateMatchOptions(), seed: 1)
        var b = a
        b.players[0].botDifficulty = .hard
        XCTAssertEqual(ReplayArchiveService.matchKey(a), ReplayArchiveService.matchKey(a))
        XCTAssertNotEqual(ReplayArchiveService.matchKey(a), ReplayArchiveService.matchKey(b))
        XCTAssertNotEqual(ReplayArchiveService.matchKey(a), ReplayArchiveService.matchKey(MatchFactory.spectateMatch(options: SpectateMatchOptions(), seed: 2)))
        var p = Profile()
        for i in 0..<(WatchLog.maxKeys + 5) {
            LiveOpsService.recordWatch(.spectate, key: "k\(i)", seconds: 60, profile: &p, now: now)
        }
        XCTAssertEqual(p.watchLog.countedKeys.count, WatchLog.maxKeys, "キーは上限まで")
        XCTAssertEqual(p.career.spectatedMatches, WatchLog.maxKeys + 5)
    }

    // MARK: お気に入り・上限

    func testFavoritesAreExemptFromCapInBothPlaces() throws {
        let persistence = make()
        var p = Profile()
        let config = ServicesFixtures.config(mode: .standard)
        let summary = ServicesFixtures.summary(mode: .standard, won: true, minutes: 12)
        var favorites: [ReplayMeta] = []
        for i in 0..<3 {
            let meta = try XCTUnwrap(persistence.storeReplay(ServicesFixtures.replay(config: config, summary: summary, ticks: 900 + i),
                                                             heroID: "H001", won: true, date: now.addingTimeInterval(Double(i)), in: &p))
            XCTAssertEqual(ReplayArchiveService.toggleFavorite(id: meta.id, profile: &p, persistence: persistence), .changed(true))
            favorites.append(meta)
        }
        for i in 0..<(PersistenceService.maxReplays + 5) {
            _ = persistence.storeReplay(ServicesFixtures.replay(config: config, summary: summary, ticks: 2000 + i),
                                        heroID: "H001", won: true, date: now.addingTimeInterval(Double(100 + i)), in: &p)
        }
        XCTAssertEqual(ReplayLibrary.regularCount(p.replays), PersistenceService.maxReplays)
        XCTAssertEqual(p.replays.filter(\.isFavorite).count, 3, "最も古いお気に入りも残る")
        for f in favorites { XCTAssertTrue(p.replays.contains { $0.id == f.id }) }

        // 外すと通常の上限の対象に戻るが、その場では消さない（付け直せる）。次に保存した時に最も古いものとして消える
        XCTAssertEqual(ReplayArchiveService.toggleFavorite(id: favorites[0].id, profile: &p, persistence: persistence), .changed(false))
        XCTAssertTrue(p.replays.contains { $0.id == favorites[0].id }, "外した直後は残る")
        XCTAssertEqual(ReplayLibrary.regularCount(p.replays), PersistenceService.maxReplays + 1)
        XCTAssertTrue(ReplayArchiveService.isOverRegularCap(p))
        _ = persistence.storeReplay(ServicesFixtures.replay(config: config, summary: summary, ticks: 4000),
                                    heroID: "H001", won: true, date: now.addingTimeInterval(500), in: &p)
        XCTAssertFalse(p.replays.contains { $0.id == favorites[0].id }, "次の保存で最も古いので消える")
        XCTAssertEqual(ReplayLibrary.regularCount(p.replays), PersistenceService.maxReplays)

        // ディスク上の上限（プロフィールを知らない同期保存の経路）でもお気に入りのファイルは消さない
        persistence.waitForReplayWrites()
        for i in 0..<3 {
            _ = persistence.saveReplay(ServicesFixtures.replay(config: config, summary: summary, ticks: 5000 + i), heroID: nil, won: nil,
                                       date: now.addingTimeInterval(Double(9999 + i)))
        }
        for f in favorites.dropFirst() {
            XCTAssertTrue(FileManager.default.fileExists(atPath: persistence.replaysDirectory.appendingPathComponent(f.fileName).path))
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: persistence.replaysDirectory.path)
        XCTAssertEqual(files.count, PersistenceService.maxReplays + 2, "お気に入り以外は上限まで")
    }

    func testFavoriteLimitAndRename() throws {
        let persistence = make()
        var p = Profile()
        for i in 0..<(PersistenceService.maxFavoriteReplays + 1) {
            p.replays.append(ReplayMeta(date: now.addingTimeInterval(Double(i)), fileName: "f\(i).vreplay", mode: .standard,
                                        heroID: "H001", won: true, duration: 60, isFavorite: i < PersistenceService.maxFavoriteReplays))
            try Data("x".utf8).write(to: persistence.replaysDirectory.appendingPathComponent("f\(i).vreplay"))
        }
        let last = try XCTUnwrap(p.replays.last)
        XCTAssertEqual(ReplayArchiveService.toggleFavorite(id: last.id, profile: &p, persistence: persistence), .limitReached)
        XCTAssertEqual(ReplayArchiveService.toggleFavorite(id: UUID(), profile: &p, persistence: persistence), .notFound)

        ReplayArchiveService.rename(id: last.id, to: "  決勝\n戦  ", profile: &p)
        XCTAssertEqual(p.replays.first { $0.id == last.id }?.name, "決勝戦")
        ReplayArchiveService.rename(id: last.id, to: String(repeating: "あ", count: 80), profile: &p)
        XCTAssertEqual(p.replays.first { $0.id == last.id }?.name?.count, ReplayArchiveService.maxNameLength)
        ReplayArchiveService.rename(id: last.id, to: "   ", profile: &p)
        XCTAssertNil(p.replays.first { $0.id == last.id }?.name, "空にすると自動の名前へ戻る")
        XCTAssertEqual(ReplayLibrary.title(for: p.replays.first { $0.id == last.id }!, master: master),
                       MasterText.hero(try XCTUnwrap(master.hero("H001"))))
    }

    // MARK: 旧版のメタ・再生の判定

    func testLegacyMetaDecodesWithDefaultsAndIsBackfilled() async throws {
        let persistence = make()
        let config = ServicesFixtures.config(mode: .ranked)
        let summary = ServicesFixtures.summary(mode: .ranked, won: false, minutes: 9)
        let data = ServicesFixtures.replay(config: config, summary: summary)
        let stored = try XCTUnwrap(persistence.saveReplay(data, heroID: "H001", won: false, date: now))
        // 旧版のメタ（追加フィールドなし）
        let legacyJSON = """
        {"id":"\(stored.id.uuidString)","date":0,"fileName":"\(stored.fileName)","mode":\(MatchMode.ranked.rawValue),"heroID":"H001","won":false,"duration":30}
        """
        let legacy = try JSONDecoder().decode(ReplayMeta.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(legacy.source, .standard)
        XCTAssertFalse(legacy.isFavorite)
        XCTAssertNil(legacy.simVersion)
        XCTAssertNil(legacy.isPlayable)
        XCTAssertEqual(ReplayLibrary.compatibility(legacy), .unknown)
        XCTAssertEqual(try JSONDecoder().decode(ReplayMeta.self, from: Data(#"{"date":0,"fileName":"a.vreplay","mode":4,"duration":1}"#.utf8)).source,
                       .spectate)

        var p = Profile()
        p.replays = [legacy]
        let updates = await ReplayArchiveService.backfillAsync(p.replays, persistence: persistence)
        ReplayArchiveService.applyBackfill(updates, to: &p)
        let filled = try XCTUnwrap(p.replays.first)
        XCTAssertEqual(filled.simVersion, MatchConfig.currentSimVersion)
        XCTAssertEqual(filled.formatVersion, ReplayData.currentFormatVersion)
        XCTAssertEqual(filled.seed, config.seed)
        XCTAssertEqual(filled.heroIDs, config.players.map(\.heroID))
        XCTAssertEqual(filled.ownerSeat, config.players.firstIndex { $0.controller == .human })
        XCTAssertEqual(ReplayLibrary.compatibility(filled), .playable)
    }

    func testLaunchUsesIsPlayableAndOwnerSeat() async throws {
        let persistence = make()
        let config = MatchFactory.standardMatch(humanHeroID: "H002", humanName: "T", humanTeam: .red, seed: 8)
        let data = ReplayRecorder(config: config).finish(summary: nil)
        var meta = try XCTUnwrap(persistence.saveReplay(data, heroID: "H002", won: nil, date: now))
        XCTAssertEqual(meta.ownerSeat, config.players.firstIndex { $0.controller == .human })
        meta.ownerSeat = 3
        switch await ReplayLibrary.loadLaunch(for: meta, persistence: persistence, options: SpectatorOptions(speed: 4)) {
        case .success(let launch):
            XCTAssertEqual(launch.replayOwnerSeat, 3)
            XCTAssertEqual(launch.ownerSeat, 3)
            XCTAssertEqual(launch.spectatorOptions.speed, 4)
            XCTAssertTrue(launch.isSpectating)
        case .failure(let e):
            XCTFail("\(e)")
        }
        // 形式の版数が違うものも再生しない（B11: simVersion だけでなく formatVersion も見る）
        var future = data
        future.formatVersion = ReplayData.currentFormatVersion + 1
        XCTAssertEqual(ReplayLibrary.launch(replay: future, ownerSeat: nil).failureValue, .incompatible)
        let futureMeta = try XCTUnwrap(persistence.saveReplay(future, heroID: nil, won: nil, date: now))
        XCTAssertEqual(ReplayLibrary.compatibility(futureMeta), .incompatible)
        XCTAssertEqual(ReplayLibrary.launch(for: futureMeta, persistence: persistence).failureValue, .incompatible)
        var missing = meta
        missing.fileName = "nope.vreplay"
        let r = await ReplayLibrary.loadLaunch(for: missing, persistence: persistence)
        XCTAssertEqual(r.failureValue, .missing)
    }

    func testFiltersAndModes() {
        let metas = [
            ReplayMeta(date: now, fileName: "a.vreplay", mode: .standard, heroID: "H001", won: true, duration: 1),
            ReplayMeta(date: now.addingTimeInterval(1), fileName: "b.vreplay", mode: .spectate, heroID: nil, won: nil, duration: 1, isFavorite: true),
            ReplayMeta(date: now.addingTimeInterval(2), fileName: "c.vreplay", mode: .brawl, heroID: nil, won: nil, duration: 1, source: .spectate),
            ReplayMeta(date: now.addingTimeInterval(3), fileName: "d.vreplay", mode: .online, heroID: "H002", won: false, duration: 1),
            ReplayMeta(date: now.addingTimeInterval(4), fileName: "e.vreplay", mode: .ranked, heroID: "H003", won: nil, duration: 1, source: .imported),
            ReplayMeta(date: now.addingTimeInterval(5), fileName: "f.vreplay", mode: .custom, heroID: "H004", won: true, duration: 1),
        ]
        func names(_ f: ReplayLibrary.Filter, _ m: MatchMode? = nil) -> [String] {
            ReplayLibrary.filtered(metas, filter: f, mode: m).map(\.fileName)
        }
        XCTAssertEqual(names(.all), ["f.vreplay", "e.vreplay", "d.vreplay", "c.vreplay", "b.vreplay", "a.vreplay"])
        XCTAssertEqual(names(.favorites), ["b.vreplay"])
        XCTAssertEqual(names(.mine), ["f.vreplay", "a.vreplay"])
        XCTAssertEqual(names(.spectate), ["c.vreplay", "b.vreplay"])
        XCTAssertEqual(names(.online), ["d.vreplay"])
        XCTAssertEqual(names(.imported), ["e.vreplay"])
        XCTAssertEqual(names(.all, .brawl), ["c.vreplay"])
        XCTAssertEqual(ReplayLibrary.modes(in: metas), [.standard, .ranked, .brawl, .custom, .online, .spectate])
        XCTAssertEqual(ReplayLibrary.regularCount(metas), 5)
    }

    // MARK: 書き出し・取り込み

    private func storedSample(_ persistence: PersistenceService, _ p: inout Profile) throws -> (ReplayMeta, ReplayData) {
        let config = ServicesFixtures.config(mode: .standard)
        let summary = ServicesFixtures.summary(mode: .standard, won: true, minutes: 12)
        let replay = ServicesFixtures.replay(config: config, summary: summary)
        let meta = try XCTUnwrap(persistence.storeReplay(replay, heroID: "H001", won: true, date: now, in: &p))
        return (meta, replay)
    }

    func testExportCopyAndImportRoundTrip() async throws {
        let source = make()
        var p = Profile()
        let (meta, replay) = try storedSample(source, &p)
        let item = try XCTUnwrap(ReplayShareItem(meta: meta, persistence: source))
        let exported = try item.exportCopy()
        dirs.append(exported.deletingLastPathComponent())
        XCTAssertEqual(exported.pathExtension, "vreplay")
        XCTAssertTrue(exported.lastPathComponent.hasPrefix("VELSIA_Replay_"))
        XCTAssertEqual(try Data(contentsOf: exported), try Data(contentsOf: source.replaysDirectory.appendingPathComponent(meta.fileName)))

        // 別の端末（別のプロフィール）に取り込む
        let target = make()
        let app = AppModel(persistence: target)
        app.profile = Profile()
        let result = await ReplayArchiveService.importReplay(from: exported, app: app, now: now)
        let imported = try XCTUnwrap(try? result.get())
        XCTAssertEqual(imported.source, .imported)
        XCTAssertEqual(imported.heroID, "H001")
        XCTAssertEqual(imported.won, true)
        XCTAssertEqual(app.profile.replays.map(\.id), [imported.id])
        target.waitForReplayWrites()
        XCTAssertEqual(target.loadReplay(imported), replay)
        // 同じものは重ねて取り込まない
        let again = await ReplayArchiveService.importReplay(from: exported, app: app, now: now)
        XCTAssertEqual(again.failureValue, .duplicate(imported.id))
        XCTAssertEqual(app.profile.replays.count, 1)
    }

    func testUntrustedDecodeRejectsBadFiles() throws {
        let config = ServicesFixtures.config(mode: .standard)
        let summary = ServicesFixtures.summary(mode: .standard, won: true, minutes: 12)
        let replay = ServicesFixtures.replay(config: config, summary: summary)
        let good = try XCTUnwrap(PersistenceService.encodeReplay(replay))
        XCTAssertEqual(try PersistenceService.decodeUntrustedReplay(good), replay)
        // 旧形式（非圧縮 JSON）も読める
        XCTAssertEqual(try PersistenceService.decodeUntrustedReplay(try JSONEncoder().encode(replay)), replay)

        func failure(_ data: Data, maxBytes: Int = PersistenceService.maxImportedReplayBytes,
                     maxDecoded: Int = PersistenceService.maxDecodedReplayBytes) -> PersistenceService.UntrustedReplayError? {
            do {
                _ = try PersistenceService.decodeUntrustedReplay(data, maxBytes: maxBytes, maxDecodedBytes: maxDecoded)
                return nil
            } catch {
                return error as? PersistenceService.UntrustedReplayError
            }
        }
        XCTAssertEqual(failure(Data("PK\u{3}\u{4}zipfile".utf8)), .notReplay)
        XCTAssertEqual(failure(Data()), .notReplay)
        XCTAssertEqual(failure(good, maxBytes: 10), .tooLarge)
        XCTAssertEqual(failure(Data("VRPZ".utf8) + Data(repeating: 0xAB, count: 64)), .damaged)
        XCTAssertEqual(failure(Data("{\"not\": \"a replay\"}".utf8)), .damaged)
        // 展開後が上限を超える（圧縮爆弾）は読まない
        let bomb = Data("VRPZ".utf8) + (try (Data(repeating: 0x20, count: 4 * 1024 * 1024) as NSData).compressed(using: .lzfse) as Data)
        XCTAssertLessThan(bomb.count, 64 * 1024)
        XCTAssertEqual(failure(bomb, maxDecoded: 1024 * 1024), .damaged)
    }

    func testValidateRejectsMalformedContent() throws {
        let config = ServicesFixtures.config(mode: .standard)
        let summary = ServicesFixtures.summary(mode: .standard, won: true, minutes: 12)
        let base = ServicesFixtures.replay(config: config, summary: summary)
        XCTAssertNoThrow(try ReplayArchiveService.validate(base, master: master))

        func error(_ mutate: (inout ReplayData) -> Void) -> ReplayArchiveService.ImportError? {
            var r = base
            mutate(&r)
            do {
                try ReplayArchiveService.validate(r, master: master)
                return nil
            } catch {
                return error as? ReplayArchiveService.ImportError
            }
        }
        XCTAssertEqual(error { $0.config.simVersion += 1 }, .incompatible(newer: true))
        XCTAssertEqual(error { $0.config.simVersion -= 1 }, .incompatible(newer: false))
        XCTAssertEqual(error { $0.formatVersion += 1 }, .incompatible(newer: true))
        XCTAssertEqual(error { $0.config.players.removeLast() }, .invalidContent)
        XCTAssertEqual(error { $0.config.players[0].heroID = "H999" }, .invalidContent)
        XCTAssertEqual(error { $0.config.players[1].heroID = $0.config.players[0].heroID }, .invalidContent)
        XCTAssertEqual(error { $0.config.players[0].spells = ["NOPE"] }, .invalidContent)
        XCTAssertEqual(error { $0.config.players[0].position = $0.config.players[1].position }, .invalidContent)
        XCTAssertEqual(error { $0.config.players[0].displayName = String(repeating: "x", count: 500) }, .invalidContent)
        XCTAssertEqual(error { $0.config.mode = .practice }, .invalidContent)
        XCTAssertEqual(error { $0.config.maxDuration = .infinity }, .invalidContent)
        XCTAssertEqual(error { $0.finalTick = 10_000_000 }, .invalidContent)
        XCTAssertEqual(error { $0.frames = [ReplayFrame(tick: 5, commands: []), ReplayFrame(tick: 5, commands: [])] }, .invalidContent)
        XCTAssertEqual(error { $0.frames = [ReplayFrame(tick: $0.finalTick + 1, commands: [])] }, .invalidContent)
        XCTAssertEqual(error { $0.frames = [ReplayFrame(tick: 3, commands: [HeroCommand(heroID: 999_999, command: .stop)])] },
                       .invalidContent, "この試合のヒーロー以外への入力")
        // 正しいヒーローへの入力は通る
        let state = Simulation(config: config, map: MapDefinition.map(for: config.mode)).state
        let hero = state.units[state.heroIndices[0]].id
        XCTAssertNil(error { $0.frames = [ReplayFrame(tick: 3, commands: [HeroCommand(heroID: hero, command: .stop)])] })
    }

    /// 復号は "nan" / "+inf" の文字列を数値として読むので、入力・結果・年表の数値が有限で盤面の近くにあることを確かめる
    /// （NaN や巨大な座標は sim の格子計算、巨大なキル数・無限のゴールドはリザルトの Int(...) で落ちる）。
    func testValidateRejectsNonFiniteAndHugeValues() throws {
        let config = ServicesFixtures.config(mode: .standard)
        let summary = ServicesFixtures.summary(mode: .standard, won: true, minutes: 12)
        let base = ServicesFixtures.replay(config: config, summary: summary)
        let state = Simulation(config: config, map: MapDefinition.map(for: config.mode)).state
        let hero = state.units[state.heroIndices[0]].id

        func error(_ mutate: (inout ReplayData) -> Void) -> ReplayArchiveService.ImportError? {
            var r = base
            mutate(&r)
            do {
                try ReplayArchiveService.validate(r, master: master)
                return nil
            } catch {
                return error as? ReplayArchiveService.ImportError
            }
        }
        func command(_ c: PlayerCommand) -> (inout ReplayData) -> Void {
            { $0.frames = [ReplayFrame(tick: 3, commands: [HeroCommand(heroID: hero, command: c)])] }
        }
        XCTAssertEqual(error(command(.moveTo(point: Vec2(.nan, 100)))), .invalidContent)
        XCTAssertEqual(error(command(.move(direction: Vec2(.infinity, 0)))), .invalidContent)
        XCTAssertEqual(error(command(.castSkill(slot: .skill1, target: .point(Vec2(1e300, 0))))), .invalidContent)
        XCTAssertEqual(error(command(.castSpell(index: 0, target: .direction(Vec2(0, -.infinity))))), .invalidContent)
        XCTAssertEqual(error(command(.emote(emoteID: String(repeating: "e", count: 5000)))), .invalidContent)
        XCTAssertNil(error(command(.castSkill(slot: .skill1, target: .point(Vec2(6000, 6000))))), "盤面内の地点は通る")
        XCTAssertNil(error(command(.move(direction: Vec2(0.6, -0.8)))))

        XCTAssertEqual(error { $0.summary?.players[0].score.goldEarned = .infinity }, .invalidContent)
        XCTAssertEqual(error { $0.summary?.players[0].score.kills = Int.max }, .invalidContent)
        XCTAssertEqual(error { $0.summary?.players[0].mvpScore = .nan }, .invalidContent)
        XCTAssertEqual(error { $0.summary?.players[0].heroID = "H999" }, .invalidContent)
        XCTAssertEqual(error { $0.summary?.teamKills = [-1, 0] }, .invalidContent)
        XCTAssertEqual(error { $0.summary?.duration = 1e12 }, .invalidContent)

        // 初期化では 1 以上に丸められるが、復号した値はそのまま（0 だと年表の作り直しで tick % 0 になる）
        XCTAssertEqual(error { r in
            var t = ReplayTimeline(samples: [TimelineSample(state: state)])
            t.sampleInterval = 0
            r.timeline = t
        }, .invalidContent)
        XCTAssertEqual(error { r in
            var sample = TimelineSample(state: state)
            sample.blueGold = .nan
            r.timeline = ReplayTimeline(samples: [sample])
        }, .invalidContent)
        XCTAssertEqual(error { $0.timeline = ReplayTimeline(events: [TimelineEvent(tick: 5, kind: .ace(team: .blue), pos: Vec2(.nan, 0))]) },
                       .invalidContent)
        XCTAssertEqual(error { $0.timeline = ReplayTimeline(coveredTick: 10_000_000) }, .invalidContent)
    }

    /// 実際に記録した結果・年表（短い AI 同士の試合）は検証を通る。
    func testValidateAcceptsRecordedSummaryAndTimeline() throws {
        let config = MatchFactory.spectateMatch(options: SpectateMatchOptions(), seed: 21)
        let sim = Simulation(config: config, map: MapDefinition.map(for: config.mode))
        let recorder = ReplayRecorder(config: config)
        sim.recorder = recorder
        var builder = ReplayTimelineBuilder()
        builder.begin(state: sim.state)
        for _ in 0..<600 {
            let events = sim.step()
            builder.observe(events: events, state: sim.state)
        }
        recorder.timeline = builder.timeline
        let replay = recorder.finish(summary: ScoreSystem.summary(sim.state))
        XCTAssertNoThrow(try ReplayArchiveService.validate(replay, master: master))
        // 保存形式（"nan" を文字列で書く符号化）を経ても同じ
        let decoded = try PersistenceService.decodeUntrustedReplay(try XCTUnwrap(PersistenceService.encodeReplay(replay)))
        XCTAssertNoThrow(try ReplayArchiveService.validate(decoded, master: master))
    }

    /// 取り込みの経路全体: NaN を含むファイルは保存形式としては読めても、検証で弾かれて一覧に入らない。
    func testImportRejectsNaNCommandFile() async throws {
        let config = ServicesFixtures.config(mode: .standard)
        let state = Simulation(config: config, map: MapDefinition.map(for: config.mode)).state
        let hero = state.units[state.heroIndices[0]].id
        var replay = ServicesFixtures.replay(config: config, summary: ServicesFixtures.summary(mode: .standard, won: true, minutes: 12))
        replay.frames = [ReplayFrame(tick: 3, commands: [HeroCommand(heroID: hero, command: .moveTo(point: Vec2(.nan, .nan)))])]
        let data = try XCTUnwrap(PersistenceService.encodeReplay(replay))
        XCTAssertNotNil(try? PersistenceService.decodeUntrustedReplay(data), "形式としては読める")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        dirs.append(dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("evil.vreplay")
        try data.write(to: file)

        let app = AppModel(persistence: make())
        app.profile = Profile()
        let result = await ReplayArchiveService.importReplay(from: file, app: app, now: now)
        XCTAssertEqual(result.failureValue, .invalidContent)
        XCTAssertTrue(app.profile.replays.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Inbox の外のファイル（利用者のファイル）は消さない")
    }

    /// 「VELSIA で開く」の複製（Documents/Inbox）だけを取り込み後に消す。/private の付いた URL でも同じ場所と分かる。
    func testRemoveInboxCopyOnlyTouchesInbox() throws {
        let documents = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        dirs.append(documents)
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let copy = inbox.appendingPathComponent("a.vreplay")
        let other = documents.appendingPathComponent("b.vreplay")
        try Data("x".utf8).write(to: copy)
        try Data("y".utf8).write(to: other)

        ReplayArchiveService.removeInboxCopy(other, documents: documents)
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        // シミュレータ・端末の一時フォルダは /var → /private/var のリンク。解いた側の URL でも消せる
        ReplayArchiveService.removeInboxCopy(copy.resolvingSymlinksInPath(), documents: documents)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }

    /// 書き出しの複製は古いものから片付ける（新しいものは共有シートが使っている途中かもしれないので残す）。
    func testStaleExportsAreRemoved() throws {
        let root = ReplayShareItem.exportRoot
        let stale = root.appendingPathComponent("stale-\(UUID().uuidString)", isDirectory: true)
        let fresh = root.appendingPathComponent("fresh-\(UUID().uuidString)", isDirectory: true)
        for d in [stale, fresh] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            dirs.append(d)
        }
        try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: stale.path)
        ReplayShareItem.removeStaleExports()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    func testUnsafeFileNamesAreNeverTouched() throws {
        let persistence = make()
        let outside = persistence.directory.appendingPathComponent("keep.vreplay")
        try Data("keep".utf8).write(to: outside)
        let evil = ReplayMeta(date: now, fileName: "../keep.vreplay", mode: .standard, heroID: nil, won: nil, duration: 1)
        persistence.deleteReplay(evil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertNil(persistence.loadReplay(evil))
        XCTAssertNil(persistence.replayFileURL(evil))
        var p = Profile()
        p.replays = [evil]
        persistence.reconcileReplays(profile: &p)
        XCTAssertTrue(p.replays.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testStorageBytesCountsFiles() async throws {
        let persistence = make()
        var p = Profile()
        _ = try storedSample(persistence, &p)
        persistence.waitForReplayWrites()
        let bytes = await persistence.replayStorageBytesAsync()
        XCTAssertGreaterThan(bytes, 0)
        XCTAssertFalse(ReplayLibrary.storageText(bytes).isEmpty)
    }
}

extension Result {
    /// 失敗の値（テスト用）。
    var failureValue: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
