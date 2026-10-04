import XCTest
import UIKit
@testable import VELSTRIA
import VelstriaCore

final class ServicesPersistenceTests: XCTestCase {
    private var dirs: [URL] = []

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        dirs = []
        super.tearDown()
    }

    private func make(debounce: TimeInterval = 0.5, rotation: TimeInterval = 0) -> PersistenceService {
        let s = ServicesFixtures.tempPersistence(debounce: debounce, rotation: rotation)
        dirs.append(s.directory)
        return s
    }

    private func profile(coins: Int) -> Profile {
        var p = Profile()
        p.displayName = "P\(coins)"
        p.starlightCoin = coins
        return p
    }

    private func wait(_ seconds: TimeInterval) {
        let e = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { e.fulfill() }
        wait(for: [e], timeout: seconds + 2)
    }

    func testRoundTrip() {
        let s = make()
        var p = profile(coins: 1234)
        p.freeGem = 7
        p.mail = [MailItem(date: Date(timeIntervalSince1970: 1_800_000_000), title: "t", body: "b",
                           attachments: [MailAttachment(kind: .gem, amount: 3)])]
        p.achievements["ACH_FIRST_WIN"] = AchievementProgress(progress: 1, unlockedAt: Date(timeIntervalSince1970: 1_800_000_000))
        s.saveNow(p)
        let reloaded = PersistenceService(directory: s.directory)
        XCTAssertEqual(reloaded.loadProfile(), p)
        XCTAssertEqual(reloaded.lastLoadSource, .primary)
    }

    func testEmptyDirectoryLoadsNothing() {
        let s = make()
        XCTAssertNil(s.loadProfile())
        XCTAssertEqual(s.lastLoadSource, .none)
    }

    func testDebouncedSavesCoalesce() {
        let s = make(debounce: 0.3)
        for i in 1...10 { s.scheduleSave(profile(coins: i)) }
        XCTAssertTrue(s.hasPendingSave)
        XCTAssertEqual(s.profileWriteCount, 0, "0.3 秒経つまで書き込まない")
        wait(0.7)
        XCTAssertEqual(s.profileWriteCount, 1)
        XCTAssertFalse(s.hasPendingSave)
        XCTAssertEqual(PersistenceService(directory: s.directory).loadProfile()?.starlightCoin, 10)
    }

    func testSaveNowFlushesAndCancelsPending() {
        let s = make(debounce: 0.3)
        s.scheduleSave(profile(coins: 1))
        s.saveNow(profile(coins: 2))
        XCTAssertEqual(s.profileWriteCount, 1)
        wait(0.6)
        XCTAssertEqual(s.profileWriteCount, 1, "保留分は取り消される")
        XCTAssertEqual(PersistenceService(directory: s.directory).loadProfile()?.starlightCoin, 2)
        s.scheduleSave(profile(coins: 3))
        s.flushPendingSaves()
        XCTAssertEqual(PersistenceService(directory: s.directory).loadProfile()?.starlightCoin, 3)
    }

    func testBackupGenerationsAndRecoveryFromCorruptPrimary() throws {
        let s = make()
        s.saveNow(profile(coins: 1))
        s.saveNow(profile(coins: 2))
        s.saveNow(profile(coins: 3))
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: s.backupURL(generation: 1).path))
        XCTAssertTrue(fm.fileExists(atPath: s.backupURL(generation: 2).path))

        try Data("{\"schemaVersion\": 1, \"playerID\": trunc".utf8).write(to: s.profileURL)
        let r1 = PersistenceService(directory: s.directory, backupRotationInterval: 0)
        XCTAssertEqual(r1.loadProfile()?.starlightCoin, 2, "最新のバックアップ（bak1）から復旧")
        XCTAssertEqual(r1.lastLoadSource, .backup(generation: 1))
        XCTAssertTrue(fm.fileExists(atPath: s.corruptURL.path), "壊れたファイルは退避")
        // 復旧した内容で profile.json が書き直されている
        XCTAssertEqual(PersistenceService(directory: s.directory).loadProfile()?.starlightCoin, 2)

        // 本体と bak1 が壊れていれば bak2
        try Data([0xFF, 0x00, 0x13]).write(to: s.profileURL)
        try Data("not json".utf8).write(to: s.backupURL(generation: 1))
        let r2 = PersistenceService(directory: s.directory)
        XCTAssertEqual(r2.loadProfile()?.starlightCoin, 1)
        XCTAssertEqual(r2.lastLoadSource, .backup(generation: 2))
    }

    func testCorruptPrimaryIsNotRotatedIntoBackups() throws {
        let s = make()
        s.saveNow(profile(coins: 1))
        s.saveNow(profile(coins: 2)) // bak1 = 1
        try Data("garbage".utf8).write(to: s.profileURL)
        try? FileManager.default.removeItem(at: s.backupURL(generation: 1))
        try? FileManager.default.removeItem(at: s.backupURL(generation: 2))
        let r = PersistenceService(directory: s.directory, backupRotationInterval: 0)
        XCTAssertNil(r.loadProfile())
        XCTAssertEqual(r.lastLoadSource, .unrecoverable)
        r.saveNow(profile(coins: 5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.backupURL(generation: 1).path),
                       "壊れた本体をバックアップ世代に入れない")
        XCTAssertEqual(PersistenceService(directory: s.directory).loadProfile()?.starlightCoin, 5)
    }

    func testBackupRotationInterval() {
        let s = make(rotation: 3600)
        s.saveNow(profile(coins: 1))
        s.saveNow(profile(coins: 2)) // 初回の繰り下げ: bak1 = 1
        s.saveNow(profile(coins: 3)) // 間隔内なので繰り下げない
        let data = try? Data(contentsOf: s.backupURL(generation: 1))
        XCTAssertEqual(data.flatMap { try? s.decodeProfile($0) }?.starlightCoin, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.backupURL(generation: 2).path))
    }

    func testMigrationFillsMissingKeys() throws {
        let s = make()
        var p = profile(coins: 42)
        p.settings.voiceVolume = 0.25
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        // 旧版を想定: いくつかのキーが存在しない
        object.removeValue(forKey: "pass")
        object.removeValue(forKey: "missions")
        object.removeValue(forKey: "monthlySpendJPY")
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        settings.removeValue(forKey: "hudOpacity")
        object["settings"] = settings
        object["schemaVersion"] = 0
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try s.decodeProfile(data)
        XCTAssertEqual(decoded.starlightCoin, 42)
        XCTAssertEqual(decoded.settings.voiceVolume, 0.25)
        XCTAssertEqual(decoded.settings.hudOpacity, 1.0)
        XCTAssertEqual(decoded.pass, PassState())
        XCTAssertEqual(decoded.schemaVersion, PersistenceService.currentSchemaVersion)
        XCTAssertEqual(decoded.playerID, p.playerID)
    }

    func testMigrationV1MutesBGMAndSFX() throws {
        let s = make()
        var p = profile(coins: 7)
        p.settings.bgmVolume = 0.7
        p.settings.sfxVolume = 0.8
        p.settings.voiceVolume = 0.6
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        object["schemaVersion"] = 1
        let decoded = try s.decodeProfile(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.settings.bgmVolume, 0)
        XCTAssertEqual(decoded.settings.sfxVolume, 0)
        XCTAssertEqual(decoded.settings.voiceVolume, 0.6)
        XCTAssertEqual(decoded.starlightCoin, 7)
        XCTAssertEqual(decoded.schemaVersion, PersistenceService.currentSchemaVersion)

        // 現行版で保存した音量はそのまま
        p.settings.bgmVolume = 0.5
        p.settings.sfxVolume = 0.4
        let current = try s.decodeProfile(JSONEncoder().encode(p))
        XCTAssertEqual(current.settings.bgmVolume, 0.5)
        XCTAssertEqual(current.settings.sfxVolume, 0.4)
    }

    /// v2（BGM だけミュート済み）からは効果音だけを 0 にし、ユーザーが上げた BGM 音量は保つ。
    func testMigrationV2MutesSFXOnly() throws {
        let s = make()
        var p = profile(coins: 3)
        p.settings.bgmVolume = 0.5
        p.settings.sfxVolume = 0.8
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        object["schemaVersion"] = 2
        let decoded = try s.decodeProfile(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.settings.bgmVolume, 0.5)
        XCTAssertEqual(decoded.settings.sfxVolume, 0)
        XCTAssertEqual(decoded.schemaVersion, PersistenceService.currentSchemaVersion)
    }

    /// 配列の要素・辞書の値に欠けたキー（旧版の MailItem などにフィールドが追加された場合）も既定値で補い、
    /// プロフィール全体が読めなくなることを防ぐ。
    func testMigrationFillsMissingKeysInsideArraysAndDictionaries() throws {
        let s = make()
        var p = profile(coins: 7)
        p.mail = [MailItem(date: Date(timeIntervalSince1970: 1_800_000_000), title: "旧メール", body: "本文",
                           attachments: [MailAttachment(kind: .gem, amount: 30)], read: true)]
        p.achievements["ACH_FIRST_WIN"] = AchievementProgress(progress: 1, unlockedAt: Date(timeIntervalSince1970: 1_800_000_000))
        p.career.perHero["H003"] = HeroCareer(matches: 4, wins: 3, kills: 10, deaths: 2, assists: 5, mvps: 1)
        p.missions.daily = [MissionProgress(id: "D01", progress: 2, claimed: false)]
        p.runePages = [RunePage(name: "Page", primaryPath: .arcana, runeIDs: ["R1", "R2", "R3"])]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        func strip(_ key: String, from value: Any?) -> Any? {
            guard var o = value as? [String: Any] else { return value }
            o.removeValue(forKey: key)
            return o
        }
        var mail = try XCTUnwrap(object["mail"] as? [[String: Any]])
        mail[0].removeValue(forKey: "claimed")
        mail[0]["attachments"] = (mail[0]["attachments"] as? [Any])?.map { strip("amount", from: $0) as Any }
        object["mail"] = mail
        var achievements = try XCTUnwrap(object["achievements"] as? [String: Any])
        achievements["ACH_FIRST_WIN"] = strip("claimed", from: achievements["ACH_FIRST_WIN"])
        object["achievements"] = achievements
        var career = try XCTUnwrap(object["career"] as? [String: Any])
        var perHero = try XCTUnwrap(career["perHero"] as? [String: Any])
        perHero["H003"] = strip("mvps", from: perHero["H003"])
        career["perHero"] = perHero
        object["career"] = career
        var missions = try XCTUnwrap(object["missions"] as? [String: Any])
        missions["daily"] = (missions["daily"] as? [Any])?.map { strip("claimed", from: $0) as Any }
        object["missions"] = missions
        object["runePages"] = (object["runePages"] as? [Any])?.map { strip("id", from: $0) as Any }

        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(Profile.self, from: data), "前提: そのままでは読めない")
        let decoded = try s.decodeProfile(data)
        XCTAssertEqual(decoded.starlightCoin, 7)
        XCTAssertEqual(decoded.mail.first?.title, "旧メール")
        XCTAssertEqual(decoded.mail.first?.read, true)
        XCTAssertEqual(decoded.mail.first?.claimed, false)
        XCTAssertEqual(decoded.mail.first?.attachments, [MailAttachment(kind: .gem, amount: 0)], "欠けたキーは要素型の既定値")
        XCTAssertNotNil(decoded.achievements["ACH_FIRST_WIN"]?.unlockedAt)
        XCTAssertEqual(decoded.achievements["ACH_FIRST_WIN"]?.claimed, false)
        XCTAssertEqual(decoded.career.perHero["H003"]?.wins, 3)
        XCTAssertEqual(decoded.career.perHero["H003"]?.mvps, 0)
        XCTAssertEqual(decoded.missions.daily, [MissionProgress(id: "D01", progress: 2, claimed: false)])
        XCTAssertEqual(decoded.runePages.first?.name, "Page")
        XCTAssertEqual(decoded.runePages.first?.runeIDs, ["R1", "R2", "R3"])
    }

    func testExportImport() throws {
        let s = make()
        let p = profile(coins: 99)
        let data = try XCTUnwrap(s.exportProfileData(p))
        XCTAssertEqual(try s.importProfile(from: data), p)
        XCTAssertThrowsError(try s.importProfile(from: Data("hello".utf8))) { error in
            XCTAssertEqual(error as? PersistenceError, .invalidFormat)
        }
        XCTAssertThrowsError(try s.importProfile(from: Data("{\"foo\": 1}".utf8))) { error in
            XCTAssertEqual(error as? PersistenceError, .invalidFormat)
        }
        var newer = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        newer["schemaVersion"] = PersistenceService.currentSchemaVersion + 1
        XCTAssertThrowsError(try s.importProfile(from: JSONSerialization.data(withJSONObject: newer))) { error in
            XCTAssertEqual(error as? PersistenceError,
                           .newerSchema(found: PersistenceService.currentSchemaVersion + 1,
                                        supported: PersistenceService.currentSchemaVersion))
        }
    }

    func testImportDropsReplaysMissingOnThisDevice() throws {
        let s = make()
        var p = profile(coins: 1)
        let meta = ReplayMeta(date: Date(), fileName: "missing.vreplay", mode: .standard, heroID: "H001", won: true, duration: 600)
        p.replays = [meta]
        p.matchHistory = [MatchRecord(date: Date(), mode: .standard, difficulty: .normal, won: true, duration: 600,
                                      heroID: "H001", kills: 1, deaths: 0, assists: 0, creepScore: 10, gold: 1000,
                                      damageToHeroes: 100, grade: "B", isMVP: false, items: [], replayID: meta.id, summary: nil)]
        let imported = try s.importProfile(from: XCTUnwrap(s.exportProfileData(p)))
        XCTAssertTrue(imported.replays.isEmpty)
        XCTAssertNil(imported.matchHistory.first?.replayID)
    }

    func testNonFiniteNumbersDoNotBreakSaving() {
        let s = make()
        var p = profile(coins: 5)
        p.career.totalDamage = .nan
        p.career.totalGold = .infinity
        s.saveNow(p)
        let loaded = PersistenceService(directory: s.directory).loadProfile()
        XCTAssertEqual(loaded?.starlightCoin, 5)
        XCTAssertEqual(loaded?.career.totalGold, .infinity)
        XCTAssertTrue(loaded?.career.totalDamage.isNaN == true)
    }

    func testReplayCapAndConsistency() throws {
        let s = make()
        var p = Profile()
        let config = ServicesFixtures.config(mode: .standard)
        let summary = ServicesFixtures.summary(mode: .standard, won: true, minutes: 12)
        let base = ServicesFixtures.weekday
        var metas: [ReplayMeta] = []
        for i in 0..<23 {
            let replay = ServicesFixtures.replay(config: config, summary: summary, ticks: 900 + i)
            let meta = try XCTUnwrap(s.storeReplay(replay, heroID: "H001", won: true,
                                                   date: base.addingTimeInterval(Double(i)), in: &p))
            metas.append(meta)
            p.matchHistory.insert(MatchRecord(date: meta.date, mode: .standard, difficulty: .normal, won: true, duration: 30,
                                              heroID: "H001", kills: 0, deaths: 0, assists: 0, creepScore: 0, gold: 0,
                                              damageToHeroes: 0, grade: "B", isMVP: false, items: [], replayID: meta.id,
                                              summary: nil), at: 0)
            s.reconcileReplays(profile: &p)
        }
        XCTAssertEqual(p.replays.count, 20)
        XCTAssertEqual(p.replays.first?.id, metas.last?.id, "新しい順")
        XCTAssertFalse(p.replays.contains { $0.id == metas[0].id }, "古いものから削除")
        s.waitForReplayWrites()
        let files = try FileManager.default.contentsOfDirectory(atPath: s.replaysDirectory.path)
        XCTAssertEqual(files.count, 20)
        XCTAssertEqual(Set(files), Set(p.replays.map(\.fileName)))
        XCTAssertEqual(p.matchHistory.filter { $0.replayID != nil }.count, 20)

        // 圧縮形式で保存され、読み戻せる
        let raw = try Data(contentsOf: s.replaysDirectory.appendingPathComponent(p.replays[0].fileName))
        XCTAssertTrue(raw.starts(with: Data("VRPZ".utf8)))
        let loaded = try XCTUnwrap(s.loadReplay(p.replays[0]))
        XCTAssertEqual(loaded.finalTick, 922)
        XCTAssertEqual(loaded.config, config)
        XCTAssertEqual(p.replays[0].duration, 922 * Balance.dt, accuracy: 0.0001)

        // 個別削除
        let victim = p.replays[0]
        s.deleteReplay(victim, from: &p)
        XCTAssertEqual(p.replays.count, 19)
        XCTAssertFalse(p.matchHistory.contains { $0.replayID == victim.id })
        XCTAssertNil(s.loadReplay(victim))
    }

    /// 読み込み時に、ファイルの無いメタ・どのメタにも属さないファイル・切れた戦績リンクを整理する。
    func testLoadReconcilesReplaysWithDisk() throws {
        let s = make()
        var p = Profile()
        let config = ServicesFixtures.config(mode: .standard)
        let summary = ServicesFixtures.summary(mode: .standard, won: true, minutes: 12)
        let kept = try XCTUnwrap(s.storeReplay(ServicesFixtures.replay(config: config, summary: summary), heroID: "H001",
                                               won: true, date: ServicesFixtures.weekday, in: &p))
        let dangling = ReplayMeta(date: ServicesFixtures.weekday.addingTimeInterval(60), fileName: "missing.vreplay",
                                  mode: .standard, heroID: "H001", won: true, duration: 10)
        p.replays.insert(dangling, at: 0)
        p.matchHistory = [MatchRecord(date: dangling.date, mode: .standard, difficulty: .normal, won: true, duration: 10,
                                      heroID: "H001", kills: 0, deaths: 0, assists: 0, creepScore: 0, gold: 0,
                                      damageToHeroes: 0, grade: "B", isMVP: false, items: [], replayID: dangling.id,
                                      summary: nil)]
        let orphan = s.replaysDirectory.appendingPathComponent("orphan.vreplay")
        try Data("orphan".utf8).write(to: orphan)
        s.saveNow(p)
        s.waitForReplayWrites()

        let loaded = try XCTUnwrap(PersistenceService(directory: s.directory).loadProfile())
        XCTAssertEqual(loaded.replays.map(\.id), [kept.id])
        XCTAssertNil(loaded.matchHistory[0].replayID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.replaysDirectory.appendingPathComponent(kept.fileName).path))
    }

    /// リプレイの符号化・書き込みはバックグラウンドで行い、書き込み中も一覧・突き合わせ・読み込みで矛盾しない。
    func testReplayWriteIsAsynchronousButConsistent() throws {
        let s = make()
        var p = Profile()
        let config = ServicesFixtures.config(mode: .standard)
        let summary = ServicesFixtures.summary(mode: .standard, won: true, minutes: 12)
        let replay = ServicesFixtures.replay(config: config, summary: summary, ticks: 1234)
        let meta = try XCTUnwrap(s.storeReplay(replay, heroID: "H001", won: true, date: ServicesFixtures.weekday, in: &p))
        XCTAssertEqual(p.replays.map(\.id), [meta.id])
        // 書き込み中でも突き合わせで外れない
        s.reconcileReplays(profile: &p)
        XCTAssertEqual(p.replays.map(\.id), [meta.id])
        // 読み込みは書き込みの完了を待つ
        XCTAssertEqual(s.loadReplay(meta)?.finalTick, 1234)
        XCTAssertFalse(s.isReplayWritePending(meta.fileName))
        // 同期版は戻った時点でファイルがある
        let direct = try XCTUnwrap(s.saveReplay(replay, heroID: nil, won: nil, date: ServicesFixtures.weekday))
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.replaysDirectory.appendingPathComponent(direct.fileName).path))
        // 全削除は書き込み中のリプレイも残さない
        _ = s.storeReplay(replay, heroID: "H001", won: true, date: ServicesFixtures.weekday, in: &p)
        s.deleteAll()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: s.replaysDirectory.path), [])
    }

    /// バックグラウンド移行の通知で保留中の保存が書き出される。
    func testBackgroundNotificationFlushesPendingSave() {
        let s = make(debounce: 30)
        s.scheduleSave(profile(coins: 42))
        XCTAssertTrue(s.hasPendingSave)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(s.hasPendingSave)
        XCTAssertEqual(PersistenceService(directory: s.directory).loadProfile()?.starlightCoin, 42)
    }

    func testDeleteAll() {
        let s = make(debounce: 0.2)
        s.saveNow(profile(coins: 1))
        s.scheduleSave(profile(coins: 2))
        s.deleteAll()
        wait(0.4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.profileURL.path), "保留中の保存も破棄")
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.replaysDirectory.path))
        XCTAssertNil(s.loadProfile())
    }
}
