import Compression
import Foundation
import UIKit
import VelstriaCore

// 担当: app-services
// プロフィール（profile.json）とリプレイ（replays/*.vreplay）のローカル永続化。
// - scheduleSave: 0.5 秒以内の連続変更を 1 回の書き込みにまとめる（専用シリアルキューで atomic write）
// - saveNow: 保留中の書き込みを取り消して同期的に即時保存（バックグラウンド移行・課金付与の直後など）
// - 世代バックアップ: profile.json → profile.bak1 → profile.bak2 と繰り下げる（壊れたファイルは世代に入れない）
// - 読み込み時に profile.json が壊れていれば、新しいバックアップから順に復旧する
// - schemaVersion によるマイグレーションフック（JSON オブジェクトの段階で変換 → 欠損キーを既定値で補完 → デコード）
// - バックグラウンド移行・終了の通知で保留中の保存を書き出す（呼び出し側の saveNow 漏れに対する保険）
// - 読み込み時に profile.replays とディスク上のリプレイを突き合わせる
// - リプレイ（数百 KB〜数 MB の JSON）の符号化・書き込みは専用キューで行い、試合終了時にメインスレッドを止めない。
//   書き込み中のファイルは存在扱いにし、読み込み・削除・全削除・バックグラウンド移行では書き込み完了を待つ。
// - リプレイの上限は maxReplays（ここが唯一の定義）。お気に入りは上限の対象外（別枠 maxFavoriteReplays まで）。
//   突き合わせ（reconcileReplays）とディスク上の上限（enforceReplayFileCap）の両方でお気に入りを消さない。
//   上限を超えたら、報酬の無い試合から自動で保存した物（AI 同士の観戦・カスタム・オンライン）を先に、古い順に消す
//   （evictionTier。観戦を続けて見ても、戦績から開ける自分の対戦のリプレイが押し出されない）。
// - 読み込み・復号は loadReplayAsync でメインスレッドの外で行う（大きなリプレイでも画面を止めない）。
// - 取り込み（.vreplay）は信用しないデータとして扱い、大きさ・先頭のマジック・展開後の大きさに上限を設けて復号する
//   （内容の検証は ReplayArchiveService）。

/// 読み込み・インポートの失敗理由。
enum PersistenceError: Error, Equatable, LocalizedError {
    /// JSON として読めない、または Profile として解釈できない。
    case invalidFormat
    /// 新しいバージョンのアプリで作られたデータ（このバージョンでは読めない）。
    case newerSchema(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return L("データの形式が正しくありません。", "The data format is invalid.")
        case .newerSchema:
            return L("新しいバージョンのアプリで作成されたデータです。アプリを更新してください。",
                     "This data was created by a newer version of the app. Please update the app.")
        }
    }
}

/// 起動時にプロフィールをどこから読み込んだか（UI で「バックアップから復旧しました」を出す用）。
enum ProfileLoadSource: Equatable {
    /// 保存データなし（新規プロフィール）。
    case none
    case primary
    /// profile.bak1 = 1、profile.bak2 = 2。
    case backup(generation: Int)
    /// ファイルはあったがすべて読めなかった。
    case unrecoverable
}

final class PersistenceService: @unchecked Sendable {
    /// 連続変更をまとめる時間窓。
    static let defaultSaveDebounce: TimeInterval = 0.5
    /// バックアップ世代数（profile.bak1 / profile.bak2）。
    static let backupGenerations = 2
    /// 保存するリプレイの上限（超えたら古い順に削除）。お気に入りは数えない。画面・プライバシー表記もこの値を使う。
    static let maxReplays = 20
    /// お気に入りにできるリプレイの上限（お気に入りは自動削除されないため、別枠で抑える）。
    static let maxFavoriteReplays = 30
    /// 取り込むファイルの大きさの上限（圧縮後）。
    static let maxImportedReplayBytes = 32 * 1024 * 1024
    /// 取り込むリプレイの展開後の大きさの上限（圧縮爆弾の防止）。
    static let maxDecodedReplayBytes = 96 * 1024 * 1024
    /// 現行スキーマ版数（Profile の既定値が正本）。
    static let currentSchemaVersion = Profile().schemaVersion

    /// 圧縮リプレイのファイル先頭マジック。
    private static let replayMagic = Data("VRPZ".utf8)

    let directory: URL
    let saveDebounce: TimeInterval
    /// バックアップを繰り下げる最短間隔。短時間の連続保存でバックアップ世代が同じ内容に潰れないようにする。
    let backupRotationInterval: TimeInterval

    // 以下は queue 上でのみ読み書きする。
    private let queue = DispatchQueue(label: "com.velstria.persistence", qos: .utility)
    private var pendingProfile: Profile?
    private var flushScheduled = false
    /// profile.json が正常な内容か（壊れたファイルはバックアップ世代に回さない）。
    private var primaryIsValid = true
    private var lastRotation: Date?
    private var writeCount = 0

    /// リプレイの符号化・書き込み用（プロフィールの保存と互いに待たないよう別キュー）。
    private let replayQueue = DispatchQueue(label: "com.velstria.persistence.replay", qos: .utility)
    /// 書き込み待ちのリプレイのファイル名（replayLock で保護。検索専用）。
    private var pendingReplayNames: Set<String> = []
    /// お気に入りのリプレイのファイル名（replayLock で保護。ディスク上の上限で消さない。突き合わせの度に更新）。
    private var protectedReplayNames: Set<String> = []
    private let replayLock = NSLock()

    /// 直近の loadProfile の結果（メインスレッドから参照）。
    private(set) var lastLoadSource: ProfileLoadSource = .none
    private var lifecycleObservers: [NSObjectProtocol] = []

    init(directory: URL? = nil, saveDebounce: TimeInterval = PersistenceService.defaultSaveDebounce,
         backupRotationInterval: TimeInterval = 30) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("Velstria", isDirectory: true)
        }
        self.saveDebounce = saveDebounce
        self.backupRotationInterval = backupRotationInterval
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: replaysDirectory, withIntermediateDirectories: true)
        let center = NotificationCenter.default
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            lifecycleObservers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.flushPendingSaves()
            })
        }
    }

    deinit {
        for o in lifecycleObservers { NotificationCenter.default.removeObserver(o) }
    }

    var profileURL: URL { directory.appendingPathComponent("profile.json") }
    var replaysDirectory: URL { directory.appendingPathComponent("replays", isDirectory: true) }
    /// generation = 1 / 2
    func backupURL(generation: Int) -> URL { directory.appendingPathComponent("profile.bak\(generation)") }
    /// 読めなかった profile.json の退避先（問い合わせ対応用に 1 つだけ残す）。
    var corruptURL: URL { directory.appendingPathComponent("profile.corrupt.json") }

    // MARK: - エンコード

    static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        // NaN / 無限大が混入しても保存全体が失敗しないように文字列化する
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")
        if pretty { e.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }

    // MARK: - 読み込み・復旧

    /// profile.json を読み込む。壊れていれば bak1 → bak2 の順に復旧を試み、復旧できたら profile.json を書き直す。
    func loadProfile() -> Profile? {
        let fm = FileManager.default
        let candidates = [profileURL] + (1...Self.backupGenerations).map { backupURL(generation: $0) }
        var anyFileFound = false
        for (index, url) in candidates.enumerated() {
            guard let data = try? Data(contentsOf: url) else { continue }
            anyFileFound = true
            guard var profile = try? decodeProfile(data) else {
                if index == 0 {
                    // 壊れた本体は退避し、以後の保存でバックアップ世代に混ざらないようにする
                    try? fm.removeItem(at: corruptURL)
                    try? fm.copyItem(at: profileURL, to: corruptURL)
                    queue.sync { primaryIsValid = false }
                }
                continue
            }
            Self.sanitize(&profile)
            reconcileReplays(profile: &profile)
            if index == 0 {
                lastLoadSource = .primary
            } else {
                lastLoadSource = .backup(generation: index)
                // 復旧した内容を本体として書き直す（バックアップ世代はそのまま残す）
                queue.sync {
                    writePrimary(profile, rotate: false)
                }
            }
            return profile
        }
        lastLoadSource = anyFileFound ? .unrecoverable : .none
        return nil
    }

    /// Profile の JSON をデコードする。現行スキーマで直接読めなければマイグレーション + 欠損キー補完を行う。
    func decodeProfile(_ data: Data) throws -> Profile {
        let decoder = Self.makeDecoder()
        guard let probe = try? decoder.decode(SchemaProbe.self, from: data) else { throw PersistenceError.invalidFormat }
        let version = probe.schemaVersion ?? 1
        if version == Self.currentSchemaVersion, let p = try? decoder.decode(Profile.self, from: data) {
            return p
        }
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PersistenceError.invalidFormat
        }
        ProfileMigrator.migrate(&object, from: version)
        let merged = Self.mergingDefaults(into: object)
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              var profile = try? decoder.decode(Profile.self, from: mergedData) else {
            throw PersistenceError.invalidFormat
        }
        profile.schemaVersion = max(Self.currentSchemaVersion, profile.schemaVersion)
        return profile
    }

    /// schemaVersion だけを読む。
    private struct SchemaProbe: Decodable {
        var schemaVersion: Int?
        var playerID: String?
    }

    /// 既定値の Profile を土台に、保存データのキーを再帰的に上書きする（旧版で欠けているキーを補う）。
    /// 合成 Codable は既定値付きのプロパティでもキー欠落でデコードに失敗するため、
    /// 配列の要素・辞書の値（メール・戦績・実績など）も要素型の既定値で補う（elementTemplates）。
    static func mergingDefaults(into loaded: [String: Any]) -> [String: Any] {
        guard let defaults = jsonObject(Profile()) else { return loaded }
        return deepMerge(base: defaults, over: loaded, path: "")
    }

    private static func jsonObject<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? makeEncoder().encode(value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 要素型の既定値（JSON）。キーは Profile からのパス（配列の要素は "[]"、辞書の値は "{}"）。
    /// Profile に配列・辞書の要素型を追加したらここにも加えること。
    private static let elementTemplates: [String: [String: Any]] = {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let pairs: [(String, [String: Any]?)] = [
            ("mail[]", jsonObject(MailItem(date: epoch, title: "", body: ""))),
            ("mail[].attachments[]", jsonObject(MailAttachment(kind: .coin))),
            ("matchHistory[]", jsonObject(MatchRecord(
                date: epoch, mode: .standard, difficulty: .normal, won: nil, duration: 0, heroID: "", kills: 0,
                deaths: 0, assists: 0, creepScore: 0, gold: 0, damageToHeroes: 0, grade: "", isMVP: false,
                items: [], replayID: nil, summary: nil))),
            ("replays[]", jsonObject(ReplayMeta(date: epoch, fileName: "", mode: .standard, heroID: nil, won: nil, duration: 0))),
            ("runePages[]", jsonObject(RunePage(name: "", primaryPath: .valor, runeIDs: ["", "", ""]))),
            ("purchaseLedger[]", jsonObject(PurchaseRecord(transactionID: 0, productID: "", gemsGranted: 0, priceJPY: 0, date: epoch))),
            ("storePurchases[]", jsonObject(StorePurchaseCount(sku: "", count: 0))),
            ("friends[]", jsonObject(Friend(code: "", name: "", addedAt: epoch))),
            ("missions.daily[]", jsonObject(MissionProgress(id: ""))),
            ("missions.weekly[]", jsonObject(MissionProgress(id: ""))),
            ("achievements{}", jsonObject(AchievementProgress())),
            ("career.perHero{}", jsonObject(HeroCareer())),
        ]
        var table: [String: [String: Any]] = [:]
        for (path, template) in pairs {
            if let template { table[path] = template }
        }
        return table
    }()

    private static func deepMerge(base: [String: Any], over: [String: Any], path: String) -> [String: Any] {
        var result = base
        for key in over.keys.sorted() {
            let value = over[key]!
            let childPath = path.isEmpty ? key : "\(path).\(key)"
            if let template = elementTemplates[childPath + "[]"], let array = value as? [Any] {
                result[key] = array.map { element -> Any in
                    guard let object = element as? [String: Any] else { return element }
                    return deepMerge(base: template, over: object, path: childPath + "[]")
                }
            } else if let template = elementTemplates[childPath + "{}"], let dict = value as? [String: Any] {
                var merged: [String: Any] = [:]
                for k in dict.keys.sorted() {
                    let element = dict[k]!
                    if let object = element as? [String: Any] {
                        merged[k] = deepMerge(base: template, over: object, path: childPath + "{}")
                    } else {
                        merged[k] = element
                    }
                }
                result[key] = merged
            } else if let b = result[key] as? [String: Any], let o = value as? [String: Any] {
                result[key] = deepMerge(base: b, over: o, path: childPath)
            } else {
                result[key] = value
            }
        }
        return result
    }

    /// 読み込んだ値の範囲を正す（改変・旧版の不整合でアプリが落ちないように）。
    static func sanitize(_ p: inout Profile) {
        p.starlightCoin = max(0, p.starlightCoin)
        p.freeGem = max(0, p.freeGem)
        p.paidGem = max(0, p.paidGem)
        p.accountLevel = min(RewardService.maxAccountLevel, max(1, p.accountLevel))
        p.accountXP = max(0, p.accountXP)
        p.pass.xp = min(LiveOpsService.passXPPerLevel * LiveOpsService.passMaxLevel, max(0, p.pass.xp))
        if p.runePages.isEmpty {
            p.selectedRunePage = 0
        } else {
            p.selectedRunePage = min(p.runePages.count - 1, max(0, p.selectedRunePage))
        }
        if p.matchHistory.count > RewardService.maxMatchHistory {
            p.matchHistory = Array(p.matchHistory.prefix(RewardService.maxMatchHistory))
        }
        if p.ownedHeroIDs.isEmpty { p.ownedHeroIDs = Profile().ownedHeroIDs }
        if p.playerID.isEmpty { p.playerID = UUID().uuidString }
        // フレンド: 識別子が壊れていたら作り直す。改変されたフレンド・申請は取り除く（重複・自分自身・不正なコード）
        if !FriendCode.isValid(p.friendCode) { p.friendCode = FriendCode.generate() }
        if !FriendInboxKey.isValid(p.inboxKey) { p.inboxKey = FriendInboxKey.generate() }
        var seen: Set<String> = [p.friendCode]
        p.friends = p.friends.filter { FriendCode.isValid($0.code) && seen.insert($0.code).inserted }
        p.outgoingFriendRequests = p.outgoingFriendRequests.filter { FriendCode.isValid($0) && $0 != p.friendCode }
    }

    // MARK: - 保存

    /// 変更時に呼ばれる。saveDebounce 以内の連続呼び出しは最後の内容 1 回の書き込みにまとめる。
    func scheduleSave(_ profile: Profile) {
        queue.async {
            self.pendingProfile = profile
            guard !self.flushScheduled else { return }
            self.flushScheduled = true
            self.queue.asyncAfter(deadline: .now() + self.saveDebounce) {
                self.flushScheduled = false
                guard let p = self.pendingProfile else { return }
                self.pendingProfile = nil
                self.writePrimary(p, rotate: true)
            }
        }
    }

    /// 保留中の保存を取り消し、指定の内容を同期的に書き込む。
    func saveNow(_ profile: Profile) {
        queue.sync {
            pendingProfile = nil
            writePrimary(profile, rotate: true)
        }
    }

    /// 保留中の保存があれば即座に書き込む（バックグラウンド移行・終了処理・テスト用）。書き込み中のリプレイも待つ。
    func flushPendingSaves() {
        queue.sync {
            guard let p = pendingProfile else { return }
            pendingProfile = nil
            writePrimary(p, rotate: true)
        }
        waitForReplayWrites()
    }

    var hasPendingSave: Bool { queue.sync { pendingProfile != nil } }
    /// プロフィールを書き込んだ回数（デバウンスの検証用）。
    var profileWriteCount: Int { queue.sync { writeCount } }

    /// queue 上で呼ぶこと。
    private func writePrimary(_ profile: Profile, rotate: Bool) {
        guard let data = try? Self.makeEncoder().encode(profile) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if rotate { rotateBackupsIfNeeded() }
        do {
            try data.write(to: profileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            primaryIsValid = true
            writeCount += 1
        } catch {
            // 書き込み失敗（容量不足など）は次回の保存で再試行される
        }
    }

    /// profile.json → bak1 → bak2 の繰り下げ。queue 上で呼ぶこと。
    private func rotateBackupsIfNeeded() {
        let fm = FileManager.default
        guard primaryIsValid, fm.fileExists(atPath: profileURL.path) else { return }
        let now = Date()
        if let last = lastRotation, now.timeIntervalSince(last) < backupRotationInterval { return }
        lastRotation = now
        for generation in stride(from: Self.backupGenerations, to: 1, by: -1) {
            let older = backupURL(generation: generation)
            let newer = backupURL(generation: generation - 1)
            guard fm.fileExists(atPath: newer.path) else { continue }
            try? fm.removeItem(at: older)
            try? fm.moveItem(at: newer, to: older)
        }
        let bak1 = backupURL(generation: 1)
        try? fm.removeItem(at: bak1)
        try? fm.copyItem(at: profileURL, to: bak1)
    }

    // MARK: - リプレイ

    /// リプレイのメタ（一覧表示・絞り込み・再生可否の判定に使う情報はファイルを開かずに済むよう写しておく）。
    static func makeReplayMeta(_ replay: ReplayData, heroID: String?, won: Bool?, date: Date,
                               source: ReplaySource? = nil, ownerSeat: Int? = nil) -> ReplayMeta {
        let config = replay.config
        let seat = ownerSeat ?? (heroID == nil ? nil : config.players.firstIndex { $0.controller == .human })
        return ReplayMeta(date: date, fileName: "\(UUID().uuidString).vreplay", mode: config.mode,
                          heroID: heroID, won: won, duration: Double(replay.finalTick) * Balance.dt,
                          simVersion: config.simVersion, formatVersion: replay.formatVersion,
                          source: source ?? ReplaySource.of(config), ownerSeat: seat,
                          winner: replay.summary?.winner, seed: config.seed, heroIDs: config.players.map(\.heroID),
                          contentKey: ReplayArchiveService.contentKey(of: replay))
    }

    /// リプレイをファイルに同期保存する（ディスク上は常に最新 maxReplays 件まで。お気に入りは数えない）。
    /// 試合結果の保存と profile.replays への登録は `storeReplay(_:heroID:won:date:in:)` を使うこと。
    func saveReplay(_ replay: ReplayData, heroID: String?, won: Bool?, date: Date) -> ReplayMeta? {
        let meta = Self.makeReplayMeta(replay, heroID: heroID, won: won, date: date)
        let written: Bool = replayQueue.sync {
            guard writeReplayFile(replay, fileName: meta.fileName) else { return false }
            enforceReplayFileCap(keeping: meta.fileName)
            return true
        }
        return written ? meta : nil
    }

    /// リプレイを profile.replays（新しい順）に登録し、ファイルの符号化・書き込みはバックグラウンドで行う。
    /// 上限超過分・孤立ファイルを整理し、戦績の replayID もリプレイ一覧と矛盾しないように保つ。
    /// 書き込みに失敗した場合（容量不足など）は、次回起動時の突き合わせでメタと戦績のリンクが外れる。
    /// source / ownerSeat を省くと構成から決める（取り込み・オンラインの座席は呼び出し側が渡す）。
    @discardableResult
    func storeReplay(_ replay: ReplayData, heroID: String?, won: Bool?, date: Date,
                     source: ReplaySource? = nil, ownerSeat: Int? = nil,
                     in profile: inout Profile) -> ReplayMeta? {
        let meta = Self.makeReplayMeta(replay, heroID: heroID, won: won, date: date, source: source, ownerSeat: ownerSeat)
        let name = meta.fileName
        setReplayPending(name, true)
        replayQueue.async { [self] in
            _ = writeReplayFile(replay, fileName: name)
            setReplayPending(name, false)
        }
        profile.replays.insert(meta, at: 0)
        reconcileReplays(profile: &profile)
        return profile.replays.contains(where: { $0.id == meta.id }) ? meta : nil
    }

    /// replayQueue 上で呼ぶこと。
    private func writeReplayFile(_ replay: ReplayData, fileName: String) -> Bool {
        guard let data = Self.encodeReplay(replay) else { return false }
        do {
            try FileManager.default.createDirectory(at: replaysDirectory, withIntermediateDirectories: true)
            try data.write(to: replaysDirectory.appendingPathComponent(fileName), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func setReplayPending(_ name: String, _ pending: Bool) {
        replayLock.lock()
        if pending { pendingReplayNames.insert(name) } else { pendingReplayNames.remove(name) }
        replayLock.unlock()
    }

    /// 書き込み待ちのリプレイか。
    func isReplayWritePending(_ fileName: String) -> Bool {
        replayLock.lock()
        defer { replayLock.unlock() }
        return pendingReplayNames.contains(fileName)
    }

    /// 書き込み待ちのリプレイがすべてディスクに書かれるまで待つ。
    func waitForReplayWrites() {
        replayQueue.sync {}
    }

    /// 上限を超えた時に消す順（小さい方から先に消す）。0 = 報酬の無い試合から自動で保存した物（AI 同士の観戦・カスタム・
    /// オンライン。観戦は同じシードで見直せる）、1 = 自分の対戦（戦績から開ける）と自分で取り込んだ物。同じ順なら古い物から。
    static func evictionTier(_ meta: ReplayMeta) -> Int {
        switch meta.source {
        case .spectate, .custom, .online: return 0
        case .standard, .imported: return 1
        }
    }

    /// profile.replays とディスク上のファイルを突き合わせる:
    /// ファイルの無いメタを除去、上限超過分（お気に入り以外。自動で保存した観戦などを先に、その中で古い順）を削除、
    /// どのメタにも属さないファイルを削除、戦績のリンクを整理。
    func reconcileReplays(profile: inout Profile) {
        let fm = FileManager.default
        var seen = Set<String>()
        var valid: [ReplayMeta] = []
        let sorted = profile.replays.sorted { a, b in
            a.date != b.date ? a.date > b.date : a.fileName < b.fileName
        }
        for meta in sorted {
            guard !seen.contains(meta.fileName), Self.isSafeReplayFileName(meta.fileName) else { continue }
            seen.insert(meta.fileName)
            let url = replaysDirectory.appendingPathComponent(meta.fileName)
            guard fm.fileExists(atPath: url.path) || isReplayWritePending(meta.fileName) else { continue }
            valid.append(meta)
        }
        // お気に入りは上限の対象外（自動では消さない）。それ以外は上限を超えた分を消す順に選ぶ
        let regular = valid.indices.filter { !valid[$0].isFavorite }
        let overflow = max(0, regular.count - Self.maxReplays)
        let evicted = Set(regular.sorted { a, b in
            let ta = Self.evictionTier(valid[a]), tb = Self.evictionTier(valid[b])
            return ta != tb ? ta < tb : a > b   // valid は新しい順なので、添字の大きい方が古い
        }.prefix(overflow))
        var kept: [ReplayMeta] = []
        for (i, meta) in valid.enumerated() {
            guard evicted.contains(i) else {
                kept.append(meta)
                continue
            }
            let url = replaysDirectory.appendingPathComponent(meta.fileName)
            if isReplayWritePending(meta.fileName) {
                // 書き込み後に消す（同じキューで順に処理される）
                replayQueue.async { try? FileManager.default.removeItem(at: url) }
            } else {
                try? fm.removeItem(at: url)
            }
        }
        profile.replays = kept
        let keptNames = Set(kept.map(\.fileName))
        setProtectedReplayNames(Set(kept.filter(\.isFavorite).map(\.fileName)))
        for file in replayFiles() {
            let name = file.lastPathComponent
            guard !keptNames.contains(name), !isReplayWritePending(name) else { continue }
            try? fm.removeItem(at: file)
        }
        unlinkMissingReplays(profile: &profile)
    }

    /// ディスク上の上限（enforceReplayFileCap）から守るファイルを、今のお気に入りに合わせる（突き合わせ・削除はしない）。
    func updateFavoriteProtection(_ profile: Profile) {
        setProtectedReplayNames(Set(profile.replays.filter(\.isFavorite).map(\.fileName)))
    }

    func loadReplay(_ meta: ReplayMeta) -> ReplayData? {
        guard Self.isSafeReplayFileName(meta.fileName) else { return nil }
        if isReplayWritePending(meta.fileName) { waitForReplayWrites() }
        guard let data = try? Data(contentsOf: replaysDirectory.appendingPathComponent(meta.fileName)) else { return nil }
        return Self.decodeReplay(data)
    }

    /// メインスレッドの外で読み込み・復号する（書き込み待ちもメインスレッドで待たない）。
    func loadReplayAsync(_ meta: ReplayMeta) async -> ReplayData? {
        await withCheckedContinuation { (continuation: CheckedContinuation<ReplayData?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                continuation.resume(returning: loadReplay(meta))
            }
        }
    }

    /// リプレイのファイルの場所（共有の書き出し用）。
    func replayFileURL(_ meta: ReplayMeta) -> URL? {
        guard Self.isSafeReplayFileName(meta.fileName) else { return nil }
        return replaysDirectory.appendingPathComponent(meta.fileName)
    }

    /// メタのファイル名がリプレイの置き場の直下を指すか（取り込んだプロフィールに変な名前があってもフォルダの外に触れない）。
    static func isSafeReplayFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && name != "." && name != ".."
            && !name.hasPrefix(".") && name.hasSuffix(".vreplay")
    }

    /// 保存中のリプレイの合計サイズ（バイト）。書き込み待ちのものは含まない。
    func replayStorageBytes() -> Int64 {
        replayFiles().reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// 保存中のリプレイの合計サイズ（メインスレッドの外で、書き込み待ちが終わってから数える）。
    func replayStorageBytesAsync() async -> Int64 {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int64, Never>) in
            DispatchQueue.global(qos: .utility).async { [self] in
                waitForReplayWrites()
                continuation.resume(returning: replayStorageBytes())
            }
        }
    }

    func deleteReplay(_ meta: ReplayMeta) {
        guard Self.isSafeReplayFileName(meta.fileName) else { return }
        if isReplayWritePending(meta.fileName) { waitForReplayWrites() }
        try? FileManager.default.removeItem(at: replaysDirectory.appendingPathComponent(meta.fileName))
    }

    /// リプレイを削除し、profile.replays と戦績のリンクからも外す。
    func deleteReplay(_ meta: ReplayMeta, from profile: inout Profile) {
        deleteReplay(meta)
        profile.replays.removeAll { $0.id == meta.id || $0.fileName == meta.fileName }
        unlinkMissingReplays(profile: &profile)
    }

    /// profile.replays に無いリプレイを指す戦績の replayID を外す。
    private func unlinkMissingReplays(profile: inout Profile) {
        let ids = Set(profile.replays.map(\.id))
        for i in profile.matchHistory.indices {
            if let rid = profile.matchHistory[i].replayID, !ids.contains(rid) {
                profile.matchHistory[i].replayID = nil
            }
        }
    }

    private func replayFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: replaysDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { $0.pathExtension == "vreplay" }
    }

    private func setProtectedReplayNames(_ names: Set<String>) {
        replayLock.lock()
        protectedReplayNames = names
        replayLock.unlock()
    }

    /// お気に入りとして守るファイルか（ディスク上の上限で消さない）。
    func isReplayProtected(_ fileName: String) -> Bool {
        replayLock.lock()
        defer { replayLock.unlock() }
        return protectedReplayNames.contains(fileName)
    }

    /// ディスク上のリプレイを新しい順に maxReplays 件まで残す（お気に入りは数えず、消さない）。
    private func enforceReplayFileCap(keeping fileName: String) {
        let files = replayFiles().filter { !isReplayProtected($0.lastPathComponent) }
        guard files.count > Self.maxReplays else { return }
        let dated = files.map { url -> (URL, Date) in
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (url, d)
        }
        let newestFirst = dated.sorted { a, b in
            if a.0.lastPathComponent == fileName { return true }
            if b.0.lastPathComponent == fileName { return false }
            return a.1 != b.1 ? a.1 > b.1 : a.0.lastPathComponent < b.0.lastPathComponent
        }
        for (url, _) in newestFirst.dropFirst(Self.maxReplays) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// JSON を LZFSE 圧縮し、マジックを前置する。
    static func encodeReplay(_ replay: ReplayData) -> Data? {
        guard let json = try? makeEncoder().encode(replay) else { return nil }
        guard let compressed = try? (json as NSData).compressed(using: .lzfse) as Data else { return json }
        return replayMagic + compressed
    }

    /// 圧縮形式・非圧縮 JSON の両方を読める。
    static func decodeReplay(_ data: Data) -> ReplayData? {
        let json: Data
        if data.starts(with: replayMagic) {
            guard let raw = try? (data.dropFirst(replayMagic.count) as NSData).decompressed(using: .lzfse) as Data else {
                return nil
            }
            json = raw
        } else {
            json = data
        }
        return try? makeDecoder().decode(ReplayData.self, from: json)
    }

    /// 外から来たリプレイ（取り込み）の復号の失敗理由。
    enum UntrustedReplayError: Error, Equatable {
        /// ファイルが大きすぎる。
        case tooLarge
        /// リプレイの形式ではない（先頭のマジック・JSON の始まりが無い）。
        case notReplay
        /// 展開・復号できない（壊れている）。
        case damaged
    }

    /// 信用しないデータからリプレイを復号する: 大きさ・先頭のマジック（圧縮形式 "VRPZ" か JSON の "{"）・
    /// 展開後の大きさ（上限まで。超えたら壊れている扱い）を確かめてから JSON を解釈する。
    static func decodeUntrustedReplay(_ data: Data, maxBytes: Int = maxImportedReplayBytes,
                                      maxDecodedBytes: Int = maxDecodedReplayBytes) throws -> ReplayData {
        guard data.count <= maxBytes else { throw UntrustedReplayError.tooLarge }
        let json: Data
        if data.starts(with: replayMagic) {
            guard let raw = boundedDecompressLZFSE(data.dropFirst(replayMagic.count), limit: maxDecodedBytes) else {
                throw UntrustedReplayError.damaged
            }
            json = raw
        } else {
            // 非圧縮 JSON（旧形式）は先頭の空白を除いて "{" で始まること
            guard let first = data.first(where: { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }), first == UInt8(ascii: "{") else {
                throw UntrustedReplayError.notReplay
            }
            json = data
        }
        guard let replay = try? makeDecoder().decode(ReplayData.self, from: json) else { throw UntrustedReplayError.damaged }
        return replay
    }

    /// 出力の上限つきで LZFSE を展開する（上限に達したら nil。巨大な展開結果でメモリを使い果たさない）。
    private static func boundedDecompressLZFSE(_ input: Data, limit: Int) -> Data? {
        guard !input.isEmpty, limit > 0 else { return nil }
        // 上限 + 1 バイトの領域に展開し、上限を超えた（= 領域を使い切った）ら拒否する
        let capacity = limit + 1
        var output = Data(count: capacity)
        let written: Int = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, capacity, s, input.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard written > 0, written <= limit else { return nil }
        output.count = written
        return output
    }

    // MARK: - エクスポート / インポート

    /// バックアップ用にプロフィールを書き出す（アカウント連携画面の「データのバックアップ」）。
    func exportProfileData(_ profile: Profile) -> Data? {
        try? Self.makeEncoder(pretty: true).encode(profile)
    }

    /// バックアップから復元（検証に失敗したら throw）。保存はしない（呼び出し側が app.profile に代入する）。
    /// この端末に存在しないリプレイへの参照は外す。
    func importProfile(from data: Data) throws -> Profile {
        guard let probe = try? Self.makeDecoder().decode(SchemaProbe.self, from: data),
              let playerID = probe.playerID, !playerID.isEmpty else {
            throw PersistenceError.invalidFormat
        }
        let version = probe.schemaVersion ?? 1
        if version > Self.currentSchemaVersion {
            throw PersistenceError.newerSchema(found: version, supported: Self.currentSchemaVersion)
        }
        var profile = try decodeProfile(data)
        Self.sanitize(&profile)
        let fm = FileManager.default
        profile.replays.removeAll {
            !Self.isSafeReplayFileName($0.fileName)
                || (!fm.fileExists(atPath: replaysDirectory.appendingPathComponent($0.fileName).path) && !isReplayWritePending($0.fileName))
        }
        unlinkMissingReplays(profile: &profile)
        return profile
    }

    // MARK: - 全削除

    /// 全データ削除（プライバシー設定から）。保留中の保存も破棄する。
    func deleteAll() {
        // 書き込み中のリプレイが削除後に残らないよう、先に書き終えさせる
        waitForReplayWrites()
        queue.sync {
            pendingProfile = nil
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: replaysDirectory, withIntermediateDirectories: true)
            primaryIsValid = true
            lastRotation = nil
        }
        lastLoadSource = .none
    }
}

/// スキーマ版数ごとの変換。版数を上げる時は steps に (from: 旧版, apply: 変換) を追加する。
/// 変換は JSON オブジェクト（[String: Any]）に対して行い、最後に欠損キーを既定値で補完してデコードする。
enum ProfileMigrator {
    typealias Step = (from: Int, apply: (inout [String: Any]) -> Void)

    /// 例: 名前変更した場合
    ///   (from: N, apply: { obj in obj["newKey"] = obj.removeValue(forKey: "oldKey") })
    static let steps: [Step] = [
        // v1 → v2: BGM の既定をミュートに変えたため、保存済みの BGM 音量も 0 にする
        (from: 1, apply: { obj in
            guard var settings = obj["settings"] as? [String: Any] else { return }
            settings["bgmVolume"] = 0
            obj["settings"] = settings
        }),
        // v2 → v3: 効果音の既定もミュートに変えたため、保存済みの効果音量も 0 にする
        (from: 2, apply: { obj in
            guard var settings = obj["settings"] as? [String: Any] else { return }
            settings["sfxVolume"] = 0
            obj["settings"] = settings
        }),
    ]

    static func migrate(_ object: inout [String: Any], from version: Int) {
        var v = version
        for step in steps.sorted(by: { $0.from < $1.from }) where step.from >= v {
            step.apply(&object)
            v = step.from + 1
        }
        object["schemaVersion"] = max(v, PersistenceService.currentSchemaVersion)
    }
}
