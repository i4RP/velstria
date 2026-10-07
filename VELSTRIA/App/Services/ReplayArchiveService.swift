import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import VelstriaCore

// 担当: app-services（観戦: リプレイ一覧）
// 報酬の対象外の試合のリプレイ保存・観戦の視聴記録・リプレイの書き出し / 取り込み。
// - 保存（archive）: 報酬の対象の試合は RewardService が保存する。ここでは対象外のうち見返す価値のあるもの
//   （AI 同士の観戦・人間のいない構成・カスタム・オンライン）を保存する。報酬・戦績・通算成績には一切触れない。
//   リプレイの再生・オンラインの観戦席・練習場・チュートリアル・途中退出・30 秒未満・中断で終わった試合は保存しない。
//   オンラインのホストは席に着いても実況（観戦の画面で回す）でも、試合を最初から回しているので保存する。
// - 視聴記録: 観戦・リプレイを最後まで見たら 1 回（同じ試合・同じリプレイは何度見ても 1 回。8 倍速の周回で稼げない）。
//   通算の観戦数・実績（Gem なし）・今週の観戦目標だけが進む。Coin・Gem・パス XP は付かない。
// - 書き出し: 保存済みのファイル（"VRPZ" + LZFSE 圧縮 JSON）を分かりやすい名前で一時フォルダに複製して共有シートへ渡す。
// - 取り込み: 外から来たファイルは信用しない。大きさ・マジック・展開後の大きさ（PersistenceService.decodeUntrustedReplay）、
//   再生できる版か（ReplayData.isPlayable）、構成と入力の中身（validate）を確かめてから一覧に加える。

extension UTType {
    /// VELSIA のリプレイファイル（.vreplay）。project.yml / Info.plist の UTExportedTypeDeclarations と一致させること。
    static let velsiaReplay = UTType(exportedAs: "com.bitcoinpay.velstria.replay", conformingTo: .data)
}

/// 観戦・リプレイの視聴の種類（視聴記録・実績・今週の目標の区別）。
enum WatchKind: Equatable {
    /// AI 同士の観戦・オンラインの観戦席（生で見た試合）。
    case spectate
    /// 保存済み・取り込み・直後のリプレイの再生。
    case replay
}

enum ReplayArchiveService {
    /// これより短い試合（tick）は保存しない（すぐ終わった観戦などで一覧が埋まらないように）。30 秒。
    static let minimumArchivedTicks = 900

    // MARK: - 保存（報酬なし）

    /// この試合のリプレイを報酬なしで保存する場合の出どころ（保存しないなら nil）。
    static func archiveSource(for outcome: BattleOutcome) -> ReplaySource? {
        let launch = outcome.launch
        // リプレイの再生。オンラインの観戦席は途中から・遅延付きで見ているので記録が無い（BattleController が記録しない）。
        // 観戦の起動でも記録があるのはホストの実況（権威シミュレーションを tick 0 から回す）だけ
        guard launch.replay == nil, let replay = outcome.replay else { return nil }
        // 途中退出・中断で終わった試合は最後まで再現できても見返す価値が薄い（報酬の対象の試合と同じ扱い）
        guard !outcome.abandoned, outcome.summary.endReason != .aborted else { return nil }
        guard replay.finalTick >= minimumArchivedTicks, replay.isPlayable else { return nil }
        switch launch.config.mode {
        case .practice, .tutorial, .magicChess:
            return nil
        case .online:
            return .online
        case .spectate, .custom, .standard, .ranked, .brawl:
            let source = ReplaySource.of(launch.config)
            // 人間のいる通常戦・ランク戦・乱闘は報酬の対象（RewardService が保存する）。ここでは重ねて保存しない
            return source == .standard ? nil : source
        }
    }

    /// リプレイの持ち主の座席（オンラインは自分の座席、オフラインは人間の枠、AI 同士は nil）。
    static func ownerSeat(for outcome: BattleOutcome) -> Int? {
        let config = outcome.launch.config
        // ホストの実況（オンラインの観戦の起動）は座席が無い: 持ち主なし（勝敗・ヒーローを付けない）
        if outcome.launch.onlineSpectator { return nil }
        if let seat = outcome.launch.onlineSeat, config.players.indices.contains(seat) { return seat }
        return config.players.firstIndex { $0.controller == .human }
    }

    /// 試合の終了時（AppModel.completeBattle）に、報酬の計算の後で呼ぶ。報酬・戦績・通算成績は変えない。
    /// - 報酬の対象外のリプレイを保存して report.replaySaved / replayID を立てる（リザルトの「リプレイを見る」）。
    /// - 観戦・リプレイを最後まで見たら視聴記録を進め、実績（Gem なし）を評価する。
    /// 変更があれば即時保存する。
    @discardableResult
    static func process(outcome: BattleOutcome, report: inout RewardReport, profile: inout Profile,
                        persistence: PersistenceService, master: MasterData, now: Date) -> Bool {
        var changed = false
        if !report.replaySaved, let replay = outcome.replay, let source = archiveSource(for: outcome) {
            if let dup = existingDuplicate(of: replay, in: profile, load: persistence.loadReplay) {
                // 同じシードで観戦し直した試合など、同じリプレイは重ねて保存しない（既存のものを指す）
                report.replaySaved = true
                report.replayID = dup.id
            } else {
                let seat = ownerSeat(for: outcome)
                let heroID = seat.map { outcome.launch.config.players[$0].heroID }
                let won = seat == nil ? nil : outcome.summary.humanWon
                if let meta = persistence.storeReplay(replay, heroID: heroID, won: won, date: now,
                                                      source: source, ownerSeat: seat, in: &profile) {
                    report.replaySaved = true
                    report.replayID = meta.id
                    changed = true
                }
            }
        }
        if let watch = watchEntry(for: outcome),
           LiveOpsService.recordWatch(watch.kind, key: watch.key, seconds: outcome.summary.duration, profile: &profile, now: now) {
            report.watchCounted = true
            let unlocked = LiveOpsService.evaluateAchievements(profile: &profile, master: master, now: now)
            report.achievementsUnlocked += unlocked.filter { !report.achievementsUnlocked.contains($0) }
            changed = true
        }
        if changed { persistence.saveNow(profile) }
        return changed
    }

    // MARK: - 視聴記録

    /// 視聴記録の対象（最後まで見た観戦・リプレイ）と重複判定のキー。対象外は nil。
    static func watchEntry(for outcome: BattleOutcome) -> (kind: WatchKind, key: String)? {
        let launch = outcome.launch
        guard launch.isSpectating, !outcome.abandoned else { return nil }
        if let replay = launch.replay {
            // 中断で終わった記録は「最後まで」にならない
            guard replay.summary?.endReason != .aborted else { return nil }
            return (.replay, "r:" + matchKey(replay.config) + ":\(replay.finalTick)")
        }
        guard outcome.summary.endReason != .aborted else { return nil }
        return (.spectate, "s:" + matchKey(launch.config))
    }

    /// 記録の中身を区別するキー（構成の全体 = シード・難易度・最大時間・スペルなど、記録の長さ・入力の数）。
    /// 入力の無い記録（AI 同士）は構成が同じなら同じ試合（決定論）。入力のある記録は、キーが同じならファイルの中身まで比べる。
    static func contentKey(of replay: ReplayData) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let config = (try? encoder.encode(replay.config)).map { String(decoding: $0, as: UTF8.self) } ?? matchKey(replay.config)
        let inputs = replay.frames.reduce(0) { $0 + $1.commands.count }
        return String(RankService.stableHash("\(config)|\(replay.finalTick)|\(replay.frames.count)|\(inputs)"), radix: 36)
    }

    /// 試合を区別するキー（構成が同じなら同じ。シード・モード・版数・編成・難易度・最大時間）。
    static func matchKey(_ config: MatchConfig) -> String {
        var parts = ["\(config.mode.rawValue)", "\(config.simVersion)", "\(config.seed)", "\(Int(config.maxDuration))"]
        for p in config.players {
            parts.append("\(p.team.rawValue)\(p.position.rawValue)\(p.heroID)\(p.controller == .human ? "h" : "b")\(p.botDifficulty.rawValue)")
        }
        return String(RankService.stableHash(parts.joined(separator: "|")), radix: 36)
    }

    // MARK: - 旧版のメタの補完

    /// 版数・編成が写っていない旧版のメタを、ファイルを開いて補う（メインスレッドの外で呼ぶこと）。
    /// 戻り値は補えたメタ（id → 新しいメタ）。ファイルが無い・壊れているものは含めない。
    static func backfill(_ metas: [ReplayMeta], persistence: PersistenceService) -> [UUID: ReplayMeta] {
        var result: [UUID: ReplayMeta] = [:]
        for meta in metas where meta.simVersion == nil {
            guard let replay = persistence.loadReplay(meta) else { continue }
            var m = meta
            let config = replay.config
            m.simVersion = config.simVersion
            m.formatVersion = replay.formatVersion
            m.winner = replay.summary?.winner
            m.seed = config.seed
            m.heroIDs = config.players.map(\.heroID)
            m.contentKey = m.contentKey ?? contentKey(of: replay)
            if m.ownerSeat == nil, m.heroID != nil { m.ownerSeat = ownerSeat(of: replay) }
            result[meta.id] = m
        }
        return result
    }

    /// 旧版のメタの補完をメインスレッドの外で行う。
    static func backfillAsync(_ metas: [ReplayMeta], persistence: PersistenceService) async -> [UUID: ReplayMeta] {
        let pending = metas.filter { $0.simVersion == nil }
        guard !pending.isEmpty else { return [:] }
        return await withCheckedContinuation { (continuation: CheckedContinuation<[UUID: ReplayMeta], Never>) in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: backfill(pending, persistence: persistence))
            }
        }
    }

    /// 補完の結果をプロフィールへ反映する（その間に消された・変わったメタは触らない）。
    static func applyBackfill(_ updates: [UUID: ReplayMeta], to profile: inout Profile) {
        for i in profile.replays.indices {
            guard let u = updates[profile.replays[i].id], profile.replays[i].simVersion == nil else { continue }
            var m = profile.replays[i]
            m.simVersion = u.simVersion
            m.formatVersion = u.formatVersion
            m.winner = u.winner
            m.seed = u.seed
            m.heroIDs = u.heroIDs
            if m.contentKey == nil { m.contentKey = u.contentKey }
            if m.ownerSeat == nil { m.ownerSeat = u.ownerSeat }
            profile.replays[i] = m
        }
    }

    /// リプレイの持ち主（記録した人間）の座席。結果の「人間」を優先し、無ければ最初の人間の枠。
    static func ownerSeat(of replay: ReplayData) -> Int? {
        let players = replay.config.players
        if let human = replay.summary?.humanPlayer,
           let seat = players.firstIndex(where: { $0.team == human.team && $0.position == human.position }) {
            return seat
        }
        return players.firstIndex { $0.controller == .human }
    }

    // MARK: - お気に入り・名前

    enum FavoriteResult: Equatable {
        case changed(Bool)
        /// お気に入りの上限に達している。
        case limitReached
        case notFound
    }

    /// お気に入りを切り替える（上限 PersistenceService.maxFavoriteReplays）。外すと通常の上限の対象に戻るが、その場では消さない
    /// （うっかり外しても付け直せる。上限を超えていれば、次にリプレイを保存した時・次の起動の突き合わせで古い順に消える）。
    static func toggleFavorite(id: UUID, profile: inout Profile, persistence: PersistenceService) -> FavoriteResult {
        guard let i = profile.replays.firstIndex(where: { $0.id == id }) else { return .notFound }
        let newValue = !profile.replays[i].isFavorite
        if newValue && profile.replays.filter(\.isFavorite).count >= PersistenceService.maxFavoriteReplays {
            return .limitReached
        }
        profile.replays[i].isFavorite = newValue
        // ここでは突き合わせない（付けた時に他のリプレイを消さない・外した時にその場で消さない）。守るファイルだけ合わせる
        persistence.updateFavoriteProtection(profile)
        return .changed(newValue)
    }

    /// お気に入りを外した結果、通常の上限を超えている（次の保存で古い順に消える）。一覧のトーストで知らせる。
    static func isOverRegularCap(_ profile: Profile) -> Bool {
        profile.replays.filter { !$0.isFavorite }.count > PersistenceService.maxReplays
    }

    /// 名前の最大文字数。
    static let maxNameLength = 32

    /// 名前を付ける（空白だけ・空なら自動の表示名へ戻す）。改行などの制御文字は除く。
    static func rename(id: UUID, to name: String, profile: inout Profile) {
        guard let i = profile.replays.firstIndex(where: { $0.id == id }) else { return }
        profile.replays[i].name = sanitizedName(name)
    }

    static func sanitizedName(_ raw: String) -> String? {
        let cleaned = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maxNameLength))
    }

    // MARK: - 取り込み

    enum ImportError: Error, Equatable {
        /// ファイルを開けない。
        case unreadable
        case tooLarge
        /// リプレイのファイルではない。
        case notReplay
        /// 壊れている。
        case damaged
        /// このバージョンでは再生できない（newer = 新しいバージョンのアプリで記録された）。
        case incompatible(newer: Bool)
        /// 構成・入力の中身が不正。
        case invalidContent
        /// 同じリプレイが既に一覧にある。
        case duplicate(UUID)

        var message: String {
            switch self {
            case .unreadable: return L("ファイルを開けませんでした。", "The file couldn't be opened.")
            case .tooLarge: return L("ファイルが大きすぎます。", "The file is too large.")
            case .notReplay: return L("VELSIA のリプレイファイルではありません。", "This isn't a VELSIA replay file.")
            case .damaged: return L("リプレイファイルが壊れています。", "The replay file is damaged.")
            case .incompatible(let newer):
                return newer ? L("新しいバージョンのアプリで記録されたリプレイです。アプリを更新してください。",
                                 "This replay was recorded with a newer version. Please update the app.")
                             : L("以前のバージョンで記録されたリプレイのため、このバージョンでは再生できません。",
                                 "This replay was recorded with an earlier version and can't be played in this version.")
            case .invalidContent: return L("リプレイの内容が正しくありません。", "The replay's contents are invalid.")
            case .duplicate: return L("このリプレイは既に一覧にあります。", "This replay is already in your list.")
            }
        }
    }

    /// 取り込める試合の種類（練習場・チュートリアル・マジックチェスのリプレイは作られない）。
    static let importableModes: [MatchMode] = [.standard, .ranked, .spectate, .brawl, .custom, .online]
    /// 1 tick の入力数の上限（10 人分の操作 + 予備）。
    static let maxCommandsPerFrame = 64
    /// 表示名の最大文字数（それより長いものは不正な内容とみなす）。
    static let maxDisplayNameLength = 64

    /// 構成と入力の中身を検証する（取り込み用。sim が前提にする形を外れたものは再生させない）。
    static func validate(_ replay: ReplayData, master: MasterData) throws {
        let config = replay.config
        guard replay.isPlayable else {
            let newer = config.simVersion > MatchConfig.currentSimVersion || replay.formatVersion > ReplayData.currentFormatVersion
            throw ImportError.incompatible(newer: newer)
        }
        guard importableModes.contains(config.mode), config.practice == nil else { throw ImportError.invalidContent }
        guard config.maxDuration.isFinite, (60...3600).contains(config.maxDuration) else { throw ImportError.invalidContent }
        // 10 人（Blue 5 → Red 5、ポジション順）・重複なし・マスターにあるヒーロー / スペル / ルーン / スキン
        let players = config.players
        guard players.count == 10 else { throw ImportError.invalidContent }
        for team in Team.players {
            let positions = players.filter { $0.team == team }.map(\.position)
            guard positions.sorted(by: { $0.rawValue < $1.rawValue }) == LanePosition.allCases else { throw ImportError.invalidContent }
        }
        guard Set(players.map(\.heroID)).count == players.count else { throw ImportError.invalidContent }
        for p in players {
            guard p.team != .neutral, master.hero(p.heroID) != nil,
                  p.spells.count <= 2, p.spells.allSatisfy({ master.spell($0) != nil }),
                  p.runes.count <= 3, p.runes.allSatisfy({ $0.isEmpty || master.rune($0) != nil }),
                  p.skinID.map({ master.cosmetic($0) != nil }) ?? true,
                  p.displayName.count <= maxDisplayNameLength else { throw ImportError.invalidContent }
        }
        // 入力: tick は 1...finalTick の昇順で重複なし、1 tick の入力数に上限、対象はこの試合のヒーロー
        let maxTick = Int((config.maxDuration / Balance.dt).rounded()) + 30
        guard replay.finalTick >= 0, replay.finalTick <= maxTick else { throw ImportError.invalidContent }
        guard replay.frames.count <= replay.finalTick + 1 else { throw ImportError.invalidContent }
        var lastTick = 0
        var commandHeroes = Set<EntityID>()
        for f in replay.frames {
            guard f.tick > lastTick, f.tick <= replay.finalTick, f.commands.count <= maxCommandsPerFrame else {
                throw ImportError.invalidContent
            }
            lastTick = f.tick
            for c in f.commands {
                // 座標・方向が有限で盤面の近くにあること（NaN・巨大な値は sim の格子計算 Int(...) で落ちる）
                guard isSafePayload(c.command) else { throw ImportError.invalidContent }
                commandHeroes.insert(c.heroID)
            }
        }
        if !commandHeroes.isEmpty {
            // ヒーローのエンティティ ID は構成から決まる（初期状態を作って確かめる）
            let state = Simulation(config: config, map: MapDefinition.map(for: config.mode)).state
            let heroIDs = Set(state.heroIndices.map { state.units[$0].id })
            guard commandHeroes.isSubset(of: heroIDs) else { throw ImportError.invalidContent }
        }
        // 結果（リザルト・詳細の成績表にそのまま出る）と年表（シークバーの印）も、表示の Int(...) で落ちない範囲に限る
        if let summary = replay.summary { try validate(summary, master: master) }
        if let timeline = replay.timeline { try validate(timeline, finalTick: replay.finalTick) }
    }

    /// 座標・数値の上限（盤面の大きさの数倍。表示・格子計算で Int に変換しても溢れない）。
    static let maxCoordinate = Balance.mapSize * 4
    /// 成績の数値の上限（キル数・ゴールド・ダメージなど）。
    static let maxStatValue: Double = 1e9
    static let maxStatCount = 100_000
    /// 年表の項目数の上限。
    static let maxTimelineItems = 50_000

    private static func isFinite(_ v: Vec2, bound: Double = maxCoordinate) -> Bool {
        v.x.isFinite && v.y.isFinite && abs(v.x) <= bound && abs(v.y) <= bound
    }

    private static func isSafe(_ target: SkillTarget) -> Bool {
        switch target {
        case .none, .unit: return true
        case .direction(let v), .point(let v): return isFinite(v)
        }
    }

    /// 入力の中身が sim で扱える範囲か（添字は sim 側で確かめているので、浮動小数と文字列の長さだけ見る）。
    static func isSafePayload(_ command: PlayerCommand) -> Bool {
        switch command {
        case .move(let dir): return isFinite(dir)
        case .moveTo(let p): return isFinite(p)
        case .castSkill(_, let target): return isSafe(target)
        case .castSpell(let index, let target): return (0..<8).contains(index) && isSafe(target)
        case .sellItem(let slotIndex): return (0..<64).contains(slotIndex)
        case .buyItem(let itemID): return itemID.count <= maxDisplayNameLength
        case .emote(let emoteID): return emoteID.count <= maxDisplayNameLength
        case .stop, .attack, .attackNearest, .levelSkill, .setAutoLevel, .recall, .surrenderVote,
             .removeTutorialDummies, .setController, .setGearOption:
            return true
        }
    }

    private static func isStat(_ v: Double) -> Bool { v.isFinite && abs(v) <= maxStatValue }
    private static func isCount(_ v: Int) -> Bool { (0...maxStatCount).contains(v) }

    /// 記録された結果の検証（人数・数値の範囲・ヒーロー）。
    static func validate(_ summary: MatchSummary, master: MasterData) throws {
        guard summary.players.count <= 10, summary.teamKills.count <= 3, summary.towersDestroyed.count <= 3,
              summary.teamKills.allSatisfy(isCount), summary.towersDestroyed.allSatisfy(isCount),
              summary.duration.isFinite, (0.0...(4.0 * 3600)).contains(summary.duration) else { throw ImportError.invalidContent }
        for p in summary.players {
            let s = p.score
            guard master.hero(p.heroID) != nil, p.displayName.count <= maxDisplayNameLength,
                  p.grade.count <= 4, p.items.count <= 16, p.items.allSatisfy({ $0.count <= maxDisplayNameLength }),
                  (0...100).contains(p.level), isStat(p.mvpScore),
                  [s.kills, s.deaths, s.assists, s.minionKills, s.monsterKills, s.towersDestroyed, s.objectivesTaken,
                   s.largestKillStreak, s.largestMultiKill].allSatisfy(isCount),
                  [s.goldEarned, s.damageToHeroes, s.damageTaken, s.healingDone, s.shieldingDone, s.towerDamage].allSatisfy(isStat)
            else { throw ImportError.invalidContent }
        }
    }

    /// 記録された年表の検証（tick の範囲・数値の範囲・項目数）。tick は記録の終わりの少し先まで許す。
    static func validate(_ timeline: ReplayTimeline, finalTick: Int) throws {
        let ticks = 0...(max(0, finalTick) + 30)
        guard timeline.events.count <= maxTimelineItems, timeline.samples.count <= maxTimelineItems,
              (1...100_000).contains(timeline.sampleInterval), ticks.contains(timeline.coveredTick)
        else { throw ImportError.invalidContent }
        for e in timeline.events {
            guard ticks.contains(e.tick), e.pos.map({ isFinite($0) }) ?? true else { throw ImportError.invalidContent }
            switch e.kind {
            case .kill(_, _, let assists, _, _, let multi, _):
                guard assists.count <= 10, (0...10).contains(multi) else { throw ImportError.invalidContent }
            case .structure, .objective, .ace, .matchEnd:
                break
            }
        }
        for s in timeline.samples {
            guard ticks.contains(s.tick),
                  [s.blueGold, s.redGold, s.blueXP, s.redXP].allSatisfy(isStat),
                  [s.blueKills, s.redKills, s.blueTowers, s.redTowers].allSatisfy(isCount)
            else { throw ImportError.invalidContent }
        }
    }

    /// ファイルを読み、復号・検証する（メインスレッドの外で呼ぶこと）。
    static func readImport(at url: URL, master: MasterData) throws -> ReplayData {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            // 上限 + 1 バイトまでしか読まない（巨大なファイルを丸ごと読み込まない）
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: PersistenceService.maxImportedReplayBytes + 1) ?? Data()
        } catch {
            throw ImportError.unreadable
        }
        let replay: ReplayData
        do {
            replay = try PersistenceService.decodeUntrustedReplay(data)
        } catch let e as PersistenceService.UntrustedReplayError {
            switch e {
            case .tooLarge: throw ImportError.tooLarge
            case .notReplay: throw ImportError.notReplay
            case .damaged: throw ImportError.damaged
            }
        }
        try validate(replay, master: master)
        return replay
    }

    /// 一覧に同じリプレイがあるか（構成の全体・長さ・入力が同じ）。メタのキー（contentKey）で絞り、入力のある記録と
    /// キーの無い旧版のメタは load でファイルを開いて中身を比べる（シード・編成・長さが同じでも難易度や入力が違えば別の試合）。
    static func existingDuplicate(of replay: ReplayData, in profile: Profile,
                                  load: (ReplayMeta) -> ReplayData?) -> ReplayMeta? {
        let config = replay.config
        let heroes = config.players.map(\.heroID)
        let duration = replay.duration
        let key = contentKey(of: replay)
        return profile.replays.first { meta in
            guard meta.seed == config.seed, meta.mode == config.mode, meta.heroIDs == heroes,
                  abs(meta.duration - duration) < 0.001 else { return false }
            if let k = meta.contentKey {
                guard k == key else { return false }
                // 入力の無い記録は構成が同じなら同じ試合（決定論）
                if replay.frames.isEmpty { return true }
            }
            guard let stored = load(meta) else { return false }
            return stored.config == config && stored.finalTick == replay.finalTick && stored.frames == replay.frames
        }
    }

    /// 検証済みのリプレイを一覧に加える（出どころは「取り込み」。日付は取り込んだ時刻）。
    static func storeImported(_ replay: ReplayData, profile: inout Profile, persistence: PersistenceService,
                              now: Date) throws -> ReplayMeta {
        if let dup = existingDuplicate(of: replay, in: profile, load: persistence.loadReplay) { throw ImportError.duplicate(dup.id) }
        let seat = ownerSeat(of: replay)
        let heroID = seat.map { replay.config.players[$0].heroID }
        let won: Bool? = replay.summary.flatMap { s in
            guard let seat, let w = s.winner else { return nil }
            return w == replay.config.players[seat].team
        }
        guard let meta = persistence.storeReplay(replay, heroID: heroID, won: won, date: now,
                                                 source: .imported, ownerSeat: seat, in: &profile) else {
            throw ImportError.unreadable
        }
        return meta
    }

    /// ファイルからリプレイを取り込む（読み込み・検証はメインスレッドの外。一覧への追加と保存はメインスレッド）。
    @MainActor
    static func importReplay(from url: URL, app: AppModel, now: Date = Date()) async -> Result<ReplayMeta, ImportError> {
        let master = app.master
        let read: Result<ReplayData, ImportError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: .success(try readImport(at: url, master: master)))
                } catch let e as ImportError {
                    continuation.resume(returning: .failure(e))
                } catch {
                    continuation.resume(returning: .failure(.unreadable))
                }
            }
        }
        removeInboxCopy(url)
        switch read {
        case .failure(let e):
            return .failure(e)
        case .success(let replay):
            var p = app.profile
            do {
                let meta = try storeImported(replay, profile: &p, persistence: app.persistence, now: now)
                app.profile = p
                app.persistence.saveNow(p)
                return .success(meta)
            } catch let e as ImportError {
                return .failure(e)
            } catch {
                return .failure(.unreadable)
            }
        }
    }

    /// 他のアプリから開かれたリプレイを取り込み、結果をトーストで知らせる。戦闘中・初回設定中でなければリプレイ一覧を開く。
    @MainActor
    static func handleOpenedFile(_ url: URL, app: AppModel) async {
        let result = await importReplay(from: url, app: app)
        switch result {
        case .success:
            app.haptics.success()
            app.showToast(L("リプレイを取り込みました", "Replay imported"))
        case .failure(.duplicate):
            app.showToast(ImportError.duplicate(UUID()).message)
        case .failure(let e):
            app.haptics.warning()
            app.showToast(e.message)
            return
        }
        // 対戦の準備（オンラインの部屋を含む）を開いている間は画面を動かさない（取り込みはトーストで知らせるだけ）
        guard app.activeBattle == nil, app.activeMagicChess == nil, !app.router.isMatchFlowPresented,
              app.profile.onboardingCompleted else { return }
        if app.router.path.last != .replays { app.router.path.append(.replays) }
    }

    /// 「ほかのアプリから開く」で Documents/Inbox に複製されたファイルは取り込み後に消す（アプリの領域に溜めない）。
    /// 渡される URL は /private/var/…、Documents は /var/… のことがあるので、シンボリックリンクを解いて比べる。
    static func removeInboxCopy(_ url: URL, documents: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first) {
        guard url.isFileURL, let documents else { return }
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
        guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(inbox + "/") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 開かれた URL がリプレイファイルか（onOpenURL の振り分け）。
    static func isReplayFile(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == "vreplay"
    }

    // MARK: - 書き出し

    /// 書き出すファイル名（例: VELSIA_Replay_20261006_1530_AI.vreplay）。
    static func exportFileName(for meta: ReplayMeta) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmm"
        let tag: String
        switch meta.source {
        case .spectate: tag = "AI"
        case .online: tag = "Online"
        case .custom: tag = "Custom"
        case .imported: tag = "Shared"
        case .standard: tag = meta.heroID ?? "Match"
        }
        return "VELSIA_Replay_\(f.string(from: meta.date))_\(tag).vreplay"
    }
}

/// 共有シートに渡すリプレイ（書き出しは共有を選んだ時に行う）。
struct ReplayShareItem: Transferable, Sendable {
    let sourceURL: URL
    let exportName: String
    let persistence: PersistenceService

    init?(meta: ReplayMeta, persistence: PersistenceService) {
        guard let url = persistence.replayFileURL(meta) else { return nil }
        self.sourceURL = url
        self.exportName = ReplayArchiveService.exportFileName(for: meta)
        self.persistence = persistence
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .velsiaReplay) { item in
            SentTransferredFile(try item.exportCopy())
        }
        .suggestedFileName { $0.exportName }
    }

    /// 書き出しの複製を置く一時フォルダ。
    static var exportRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ReplayExport", isDirectory: true)
    }

    /// 前回までの書き出しの複製のうち古いもの（共有シートが使い終わったもの）を消す。
    static func removeStaleExports(olderThan age: TimeInterval = 3600, now: Date = Date()) {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for dir in dirs {
            let created = (try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if now.timeIntervalSince(created) > age { try? fm.removeItem(at: dir) }
        }
    }

    /// 一時フォルダに分かりやすい名前で複製する（保存中のファイルは書き終わるのを待つ）。
    func exportCopy() throws -> URL {
        persistence.waitForReplayWrites()
        Self.removeStaleExports()
        let dir = Self.exportRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(exportName)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return dest
    }
}
